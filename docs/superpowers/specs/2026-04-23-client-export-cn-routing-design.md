# Client Export CN Routing Design

**Date:** 2026-04-23

**Goal**

在现有“导出 sing-box 裸核客户端配置”功能基础上，补充一套符合最新 `sing-box` 规范的中国大陆直连分流配置：

- 中国大陆域名直连
- 中国大陆 IP 直连
- 非中国大陆流量默认走代理
- DNS 同步按中国大陆与非中国大陆拆分

首版继续保持“本地 `mixed` 入站 + 聚合远程节点 + `selector/urltest/clash_api`”的客户端定位，不引入 `tun`。

## Problem

当前导出的客户端配置已经可以直接运行，但其 `dns/route` 仍是最小骨架：

- 只有基础 DNS 服务器与一条最小 DNS 规则
- 所有非私有地址流量默认走 `proxy`
- 没有中国大陆直连分流

这会带来以下问题：

- 中国大陆站点也会被统一走代理，违背“大陆直连，非大陆代理”的常见客户端最佳实践
- DNS 解析路径无法按中国大陆域名与非中国大陆域名区分，体验与泄漏控制都不理想
- 当前导出虽然可用，但还不是面向中国大陆用户最合理的客户端默认配置

## Approved Decisions

### 1. 采用 `rule_set` 而非旧 Geo 语法

本次必须使用当前 `sing-box` 推荐的 `route.rule_set` / `dns.rules.rule_set` 配置方式，不使用已迁移或逐步淘汰的旧式 `geoip` / `geosite` 直写规则。

理由：

- `sing-box` 当前文档与 migration 文档都推荐使用 `rule_set`
- 远程 `binary` `.srs` 规则集更适合导出客户端配置
- 现有客户端导出已经启用了 `experimental.cache_file`，与 `rule_set` 路线兼容

### 2. 规则源采用“Loyalsoldier geoip + sing-box 官方 geosite”

本次规则源固定为：

- `geoip-cn`
  - 来源：Loyalsoldier
  - URL：`https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs/cn.srs`
- `geosite-cn`
  - 来源：sing-box 官方 geosite
  - 使用 sing-box 官方提供的 `.srs`

原因：

- 用户明确要求 `geoip` 使用 Loyalsoldier 系与 jsDelivr
- 当前未确认 Loyalsoldier 系存在稳定、可直接用于 `sing-box` 的 `geosite-cn.srs` jsDelivr 地址
- 为了交付完整的“大陆域名 + 大陆 IP”直连能力，`geosite` 回退到 sing-box 官方是当前最稳妥方案

### 3. DNS 同步做中国大陆分流

不仅 `route` 要做中国大陆直连，`dns` 也要同步分流：

- 中国大陆域名查询走国内 DNS
- 其他域名查询走远程 DNS

推荐默认值：

- 国内 DNS：阿里 DoH
  - `https://223.5.5.5/dns-query`
- 远程 DNS：Cloudflare DoH
  - `https://1.1.1.1/dns-query`

理由：

- 仅做流量路由、不做 DNS 分流，会导致中国大陆域名解析体验不完整
- 当前导出目标是“可直接运行”的客户端最佳实践，应同时处理 DNS 与路由

### 4. 客户端结构保持不变，只升级 `dns/route`

本次不改变导出客户端的整体形态，仍保持：

- 本地 `mixed` 入站
- 多远程 outbound 聚合
- `urltest` 自动测速
- `selector` 手动切换
- `clash_api` 暴露给面板

只在以下区域增加中国大陆分流能力：

- `dns.servers`
- `dns.rules`
- `route.rules`
- `route.rule_set`
- 视需要增加 `route.default_domain_resolver`

### 5. 继续不引入 `tun`

本次依旧不生成 `tun` 入站，也不引入系统路由接管逻辑。

原因：

- 当前功能定位仍是“导出 sing-box 裸核客户端最小可用配置”
- `tun` 会引入权限、平台适配和系统代理副作用
- 本次只解决分流策略，不扩大客户端运行模式

## Architecture

本次改动仍保持在 `install.sh` 内完成，不新增新的运行时脚本文件。

重点调整现有 `build_singbox_client_config()` 的 JSON 组装逻辑，并增加用于输出远程规则集数组和 DNS 规则的辅助函数。

建议新增的函数边界：

- `build_client_cn_route_rule_sets_json()`
  - 返回客户端导出用的 `route.rule_set` 数组
- `build_client_cn_dns_rules_json()`
  - 返回客户端导出用的 `dns.rules` 数组
- `build_client_cn_route_rules_json()`
  - 返回客户端导出用的 `route.rules` 数组

也可以不拆成三个新函数，而是在 `build_singbox_client_config()` 内用局部 `jq` 组装；但无论是否拆分，逻辑边界必须清晰。

## Data Flow

### 导出客户端配置时

1. 先生成远程节点 outbound 列表
2. 再生成 `selector proxy` 和 `urltest auto`
3. 再生成中国大陆分流所需的 `rule_set`
4. 再生成按中国大陆域名分流的 DNS 规则
5. 再生成按中国大陆域名 / IP 直连的 `route.rules`
6. 统一写入最终客户端 `config.json`

### 运行时行为

1. 本地应用把流量发到 `127.0.0.1:2080`
2. `sing-box` 按路由规则判定：
   - 私有地址：`direct`
   - `geosite-cn`：`direct`
   - `geoip-cn`：`direct`
   - 其他：`proxy`
3. DNS 查询按 `dns.rules` 判定：
   - `geosite-cn`：`cn-dns`
   - 其他：`remote-dns`

## Generated Config Shape

本次改动后，导出客户端配置中的关键结构应为：

- `dns.servers`
  - `cn-dns`
  - `remote-dns`
- `dns.rules`
  - `rule_set: geosite-cn -> cn-dns`
  - 默认 `final: remote-dns`
- `route.rule_set`
  - `geoip-cn` 远程 `binary` SRS
  - `geosite-cn` 远程 `binary` SRS
- `route.rules`
  - `protocol: dns`
  - `ip_is_private -> direct`
  - `rule_set: geosite-cn -> direct`
  - `rule_set: geoip-cn -> direct`
- `route.final`
  - `proxy`

如采用当前 `sing-box` 推荐写法，应优先显式使用：

- `action: "route"`
- `outbound: "direct"` / `outbound: "proxy"`

若当前项目既有客户端导出仍保持兼容写法，则本次应统一升级，避免新旧语法混杂。

## Rule Set Definitions

### `geoip-cn`

- `tag`: `geoip-cn`
- `type`: `remote`
- `format`: `binary`
- `url`: `https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs/cn.srs`

### `geosite-cn`

- `tag`: `geosite-cn`
- `type`: `remote`
- `format`: `binary`
- URL 使用 sing-box 官方 geosite `cn` 规则集

本次不额外引入：

- `geoip-us`
- `geosite-!cn`
- 复杂地区分类

保持最小够用，只满足“大陆直连，非大陆代理”。

## DNS Decisions

推荐 DNS 结构：

- `cn-dns`
  - `type`: `https`
  - `server`: `223.5.5.5`
  - `server_port`: `443`
  - `path`: `/dns-query`
- `remote-dns`
  - `type`: `https`
  - `server`: `1.1.1.1`
  - `server_port`: `443`
  - `path`: `/dns-query`

`dns.rules`：

- `rule_set: geosite-cn -> cn-dns`

`dns.final`：

- `remote-dns`

## Error Handling

- 若规则集 URL 仅是静态字符串配置，本次不在导出时主动探测下载可用性，避免导出过程依赖网络
- 若后续客户端运行时规则集下载失败，由 `sing-box` 自身报错处理
- 若构建客户端配置时远程节点列表为空，仍沿用当前拒绝导出逻辑，不生成仅包含中国大陆规则集的空代理客户端

## Testing

本次至少新增或更新以下覆盖：

1. 多协议导出测试应断言：
   - `route.rule_set` 中包含 `geoip-cn`
   - `route.rule_set` 中包含 `geosite-cn`
   - `route.rules` 中存在 `geosite-cn -> direct`
   - `route.rules` 中存在 `geoip-cn -> direct`
   - `dns.rules` 中存在 `geosite-cn -> cn-dns`
2. 导出配置仍应保留：
   - `selector proxy`
   - `urltest auto`
   - 本地 `mixed` 入站
   - `clash_api`
3. mixed-only 拒绝与 `.bak` 备份测试不应回归

测试形式继续沿用现有 shell 回归测试。

## Scope Boundaries

本次不做以下内容：

- 不引入 `tun`
- 不引入模式切换（例如全局 / 规则 / 直连）
- 不引入更多国家或服务分类规则集
- 不探测规则集远程 URL 在线可用性
- 不把 geosite 源继续强行统一到 Loyalsoldier，直到存在确认可用的 sing-box `.srs` 地址
