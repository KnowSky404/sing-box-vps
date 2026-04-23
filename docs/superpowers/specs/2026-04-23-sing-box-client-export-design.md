# Sing-box Client Export Design

**Date:** 2026-04-23

**Goal**

为 `sing-box-vps` 新增一个“导出 sing-box 裸核客户端配置”的能力。脚本应基于当前已安装的服务端协议状态，生成一份适合普通用户直接复制、保存并导入到 `sing-box` 裸核客户端的聚合 `config.json`。

首版目标是“开箱即用”的客户端最佳实践配置，而不是让用户手工拼装 outbound 片段。

## Problem

当前脚本已经可以：

- 识别并列出当前已安装协议。
- 展示协议链接、二维码或参数摘要。
- 为验证流程生成协议探测所需的临时客户端 JSON。

但面向终端用户仍存在明显缺口：

- 多协议场景下，用户只能逐个查看链接或摘要，不能一次拿到适合裸核客户端导入的聚合配置。
- 对 `sing-box` 裸核客户端不熟悉的用户，需要自行理解 `outbounds`、`selector`、`urltest`、`route` 和 `experimental.clash_api` 的结构，门槛较高。
- 即使用户想配合 zashboard 一类 Clash API 面板手动切换节点，也缺少现成的 selector 分组和 API 暴露配置。

## Approved Decisions

### 1. 首版输出“完整可运行客户端配置”

首版不只输出 outbound 片段，而是生成一份完整的 `sing-box` 客户端 JSON，包含：

- `log`
- `dns`
- `inbounds`
- `outbounds`
- `route`
- `experimental`

这样用户拿到文件后即可直接运行，不需要再理解 sing-box 客户端配置骨架。

### 2. 客户端入口固定为本地 Mixed

首版只生成本地 `mixed` 入站，不生成 `tun` 入站。

默认值：

- `listen`: `127.0.0.1`
- `listen_port`: `2080`

原因：

- `mixed` 是最稳妥的最小可用入口，几乎不涉及额外系统权限和路由副作用。
- `tun` 会引入平台差异、权限要求和系统代理预期，不适合作为“直接复制导入”的首版默认方案。

### 3. 仅导出可作为远程节点的协议

首版仅将以下已安装协议导出为客户端远程 outbound：

- `vless+reality`
- `hy2`
- `anytls`

明确不导出：

- `mixed`

原因：

- 服务端 `mixed` 是面向终端代理软件的接入层，不是本项目想推荐给 sing-box 裸核客户端的远程节点协议。
- 若把服务端 `mixed` 也导出到客户端聚合组，会让“裸核客户端最佳实践”与“开放代理接入方式”混在一起，语义不清晰。

### 4. 默认内置 selector 与 urltest

生成配置时，除真实远程节点 outbound 外，还额外生成两个组：

- `auto`:
  - `type`: `urltest`
  - 成员：所有可导出的真实远程节点
- `proxy`:
  - `type`: `selector`
  - 成员：`auto` + 所有可导出的真实远程节点
  - `default`: `auto`

`route.final` 固定指向 `proxy`。

这样默认行为是“自动选路”，但用户也可以通过面板切换到具体节点。

### 5. 默认内置 Clash API 以支持面板切换

首版在 `experimental.clash_api` 中启用本地控制接口，默认值：

- `external_controller`: `127.0.0.1:9090`
- `secret`: 自动生成或复用脚本统一随机口令生成能力

不在首版中内置 `external_ui` 路径，不假定服务器或客户端本机已有面板资源目录。

原因：

- zashboard 一类工具只需要 Clash 兼容 API 即可接管 selector 切换。
- `external_ui` 牵涉额外静态资源目录约定，不属于本次范围。

### 6. 菜单挂载到“查看节点信息”路径下

当前主菜单 `9` 已承担“查看当前连接信息”的职责。首版在该路径下新增一个子操作，而不是新增新的主菜单编号。

推荐结构：

- `1. 查看连接链接 / 二维码`
- `2. 导出 sing-box 裸核客户端配置`
- `0. 返回`

这样可以把“给传统客户端看的连接资料”和“给 sing-box 裸核看的聚合 JSON”放在同一信息域内，避免菜单继续膨胀。

### 7. 同时提供终端展示与落盘文件

生成客户端配置后，脚本应：

- 在终端输出简短说明。
- 将 JSON 保存到固定路径，例如 `/root/sing-box-vps/client/sing-box-client.json`。
- 提示用户可直接复制终端输出，或从固定路径取文件。

首版不做多文件历史版本管理，只覆盖当前导出文件，并在覆盖前为已有文件创建 `.bak` 备份。

## Architecture

本次改动保持在 `install.sh` 内完成，沿用现有协议状态层和菜单结构。

建议增加以下函数边界：

- `list_exportable_client_protocols()`
  - 基于 `list_installed_protocols` 过滤出 `vless-reality`、`hy2`、`anytls`
- `client_export_file_path()`
  - 返回统一导出路径
- `build_client_outbound_json_for_protocol()`
  - 按单协议生成一个远程 outbound JSON 对象
- `build_client_group_outbounds_json()`
  - 生成 `auto` 和 `proxy` 两个分组 outbound
- `build_singbox_client_config()`
  - 组装完整客户端配置 JSON
- `write_client_config_export()`
  - 写入文件、处理备份、统一格式化
- `show_client_config_export()`
  - 在终端打印结果与使用说明
- `node_info_menu()`
  - 作为菜单 `9` 的新入口，统筹“查看连接信息”和“导出客户端配置”

## Data Flow

### 菜单进入

1. 用户进入主菜单 `9`。
2. 脚本读取当前配置状态与已安装协议列表。
3. 展示二级菜单，用户可选择传统连接信息或导出客户端配置。

### 导出客户端配置

1. 调用 `list_exportable_client_protocols()`。
2. 若无可导出协议，则直接提示：
   - 当前仅安装了 `mixed`，或当前无支持导出的远程协议。
3. 对每个可导出协议：
   - 加载对应 state 文件
   - 组装对应 outbound JSON
   - 生成稳定、可读的 tag
4. 生成 `urltest` 组 `auto`
5. 生成 `selector` 组 `proxy`
6. 补齐本地 `mixed` inbound、基础 DNS、`route.final` 和 `experimental.clash_api`
7. 使用 `jq` 或现有 JSON 生成方式格式化并写入固定导出路径
8. 若导出路径已存在，先备份为 `.bak`
9. 在终端展示：
   - 导出成功提示
   - 文件路径
   - 本地代理入口
   - Clash API 地址
   - 配置 JSON 正文

## Generated Config Shape

首版生成的客户端配置应遵循以下结构：

- `log`
  - 默认 `level: info`
  - 保留 `timestamp: true`
- `dns`
  - 使用保守、轻量的远程 DNS 方案
  - 不引入 fakeip
- `inbounds`
  - 仅一个本地 `mixed` 入站，tag 例如 `mixed-in`
- `outbounds`
  - 一个 `selector` outbound：`proxy`
  - 一个 `urltest` outbound：`auto`
  - 多个真实远程协议 outbound
  - 一个 `direct`
  - 一个 `block`
  - 一个 `dns`
- `route`
  - `final: proxy`
  - 最小必需规则，至少处理 `protocol: dns`
- `experimental`
  - `cache_file.enabled: true`
  - `clash_api.external_controller: 127.0.0.1:9090`
  - `clash_api.secret`: 导出时生成的随机口令，并随同 JSON 一起落盘

“最佳实践”在本次中的含义是：

- 结构完整，可直接运行
- 默认自动测速选路
- 可被 Clash API 面板接管手动切换
- 不引入 `tun`、复杂规则集、地理数据库、FakeIP 或系统路由副作用

## Protocol Mapping Rules

### `vless+reality`

生成 `type: vless` outbound，至少包含：

- `server`
- `server_port`
- `uuid`
- `flow` 保持为空，不强行添加
- `tls.enabled: true`
- `tls.server_name`
- `tls.reality.enabled: true`
- `tls.reality.public_key`
- `tls.reality.short_id`

服务端 state 中存在两个 short id 时，首版固定使用第一个非空值。

### `hy2`

生成 `type: hysteria2` outbound，至少包含：

- `server`
- `server_port`
- `password`
- `tls.enabled: true`
- `tls.server_name`

可选附加：

- `obfs`
  - 仅当 `OBFS_ENABLED=y` 时生成
- `up_mbps` / `down_mbps`
  - 仅当服务端 state 有值时生成

### `anytls`

生成 `type: anytls` outbound，至少包含：

- `server`
- `server_port`
- `password`
- `tls.enabled: true`
- `tls.server_name`

若服务端 state 中存在 `USER_NAME`，仅在 sing-box 当前 outbound 文档要求该字段时才写入；否则忽略，避免生成无效字段。

## Tag Naming

生成的 outbound tag 需要满足：

- 稳定
- 可读
- 便于在面板中识别

推荐格式：

- `vless-reality-443`
- `hy2-8443`
- `anytls-443`

若同协议多实例未来出现，再引入序号或节点名去重；首版按当前项目的一机多协议模型，不预先扩展多实例命名。

## Error Handling

- 若未安装任何可导出远程协议，给明确提示，不生成空配置。
- 若某协议 state 文件损坏或缺少关键字段：
  - 记录警告
  - 跳过该协议
  - 若最终无可用协议，则整体失败并提示
- 若导出文件写入失败，终止并报错。
- 若 `.bak` 备份失败，终止写入，避免静默覆盖。
- 若 `jq` 校验生成 JSON 失败，终止导出，不输出不合法配置。

## Testing

本次至少覆盖以下回归场景：

1. 同时安装 `vless-reality` + `hy2` 时，导出配置应同时包含两个真实 outbound、一个 `urltest` 组和一个 `selector` 组。
2. 仅安装 `anytls` 时，导出配置仍应生成完整客户端配置，且 `proxy.default` 指向 `auto`。
3. 仅安装 `mixed` 时，应提示“无可导出的裸核客户端节点”，且不生成配置文件。
4. `hy2` 启用 Salamander 混淆时，客户端 outbound 应包含对应 `obfs` 字段。
5. 已存在旧导出文件时，应先创建 `.bak` 再覆盖写入。
6. 菜单 `9` 的新子菜单应保持原有“查看连接信息”路径可用，不回归现有节点信息展示。

测试形式沿用现有 `tests/` shell 回归测试，不新增外部依赖。

## Scope Boundaries

本次不做以下内容：

- 不生成 `tun` 客户端配置
- 不内置图形面板静态资源
- 不生成 Clash YAML
- 不支持服务端 `mixed` 作为推荐远程节点导出
- 不支持客户端规则集订阅、地理数据库自动下载或复杂分流
- 不开放大量交互式自定义项（端口、测速地址、API 地址等首版固定）
