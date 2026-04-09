# Multi-Protocol And HY2 Design

**Date:** 2026-04-09

## Goal

将当前基于单协议的 `sing-box-vps` 管理脚本升级为支持多协议独立管理的结构，并新增 `hy2` 协议支持。

本次设计需要同时满足以下目标：

- 用户安装时可选择一个或多个协议，而不是被迫安装全部协议。
- 用户修改配置时，先选择已安装的某个协议，再只修改该协议。
- 升级 `sing-box` 或更新相关配置时，如果某协议命中 breaking changes，必须强制完成该协议配置迁移后才能继续。
- 旧的单协议安装可以自动迁移到新的多协议状态结构。

## Confirmed Decisions

### 1. 多协议架构

- 采用“协议注册表 + 每协议独立状态文件”的方案。
- 一个实例仍只生成一个最终运行配置文件：`/root/sing-box-vps/config.json`。
- `config.json` 的 `inbounds` 改为可同时包含多个协议的 inbound。
- `vless+reality`、`mixed`、`hy2` 三个协议完全独立：
  - 端口独立
  - 域名/SNI 独立
  - 认证参数独立
  - TLS/证书参数独立

### 2. `hy2` 证书策略

- `hy2` 首版同时支持：
  - ACME 自动签发
  - 用户已有证书与私钥路径
- ACME 同时支持：
  - `HTTP-01`
  - `DNS-01`
- 默认挑战方式为 `HTTP-01`
- `DNS-01` 首版仅支持 `Cloudflare`

### 3. breaking changes 判定

- 采用脚本内置协议兼容矩阵作为强制迁移依据。
- 不依赖“升级后失败再说”的被动策略。
- 每个协议状态文件保存自己的 `CONFIG_SCHEMA_VERSION`。
- 当目标 `sing-box` 版本要求更高 schema 版本时，该协议必须强制进入迁移流程。

### 4. 旧结构迁移

- 旧单协议用户升级到新脚本后自动迁移。
- 自动识别旧配置协议类型并导入为新协议状态文件。
- 迁移后统一进入新结构，不再以单协议全局变量为长期状态来源。

## State Model

### 协议索引文件

新增协议索引状态文件，例如：

- `/root/sing-box-vps/protocols/index.env`

至少包含：

- `INSTALLED_PROTOCOLS="vless-reality,mixed,hy2"` 中的已安装集合
- `PROTOCOL_STATE_VERSION="1"`

### 协议状态文件

每个协议一个独立状态文件：

- `/root/sing-box-vps/protocols/vless-reality.env`
- `/root/sing-box-vps/protocols/mixed.env`
- `/root/sing-box-vps/protocols/hy2.env`

权限要求：

- 所有协议状态文件应使用最小权限保存敏感信息，建议统一为 `600`

### 每协议通用字段

每个协议状态文件至少包含：

- `INSTALLED`
- `CONFIG_SCHEMA_VERSION`
- `LAST_MIGRATED_SINGBOX_VERSION`
- `NODE_NAME`
- `PORT`

### `vless+reality` 字段

- `UUID`
- `SNI`
- `REALITY_PRIVATE_KEY`
- `REALITY_PUBLIC_KEY`
- `SHORT_ID_1`
- `SHORT_ID_2`

### `mixed` 字段

- `AUTH_ENABLED`
- `USERNAME`
- `PASSWORD`

### `hy2` 字段

- `DOMAIN`
- `PASSWORD`
- `USER_NAME`
- `UP_MBPS`
- `DOWN_MBPS`
- `OBFS_ENABLED`
- `OBFS_TYPE`
- `OBFS_PASSWORD`
- `TLS_MODE`
- `ACME_MODE`
- `ACME_EMAIL`
- `ACME_DOMAIN`
- `DNS_PROVIDER`
- `CF_API_TOKEN`
- `CERT_PATH`
- `KEY_PATH`
- `MASQUERADE`

## Interaction Design

### 菜单 1：安装协议

- 菜单 `1` 改为协议安装入口，而不是单协议重装入口。
- 进入后先显示：
  - 当前已安装协议列表
  - 当前未安装协议列表
- 用户可一次选择一个或多个未安装协议，例如：
  - `1`
  - `1,3`
  - `1,2,3`
- 已安装协议默认不在该入口直接覆盖修改。
- 已安装协议的配置更新统一走菜单 `3`。
- 所有选中的协议收集完参数后，一次性生成完整 `config.json`。

### 菜单 3：修改协议

- 菜单 `3` 只列出已安装协议。
- 用户先选择一个已安装协议。
- 再进入该协议自己的修改向导。
- 修改完成后重新生成完整 `config.json`。
- 只更新目标协议状态文件，不修改其它协议状态。

### 全局项

以下内容保持实例级，而不是协议级：

- `sing-box` 二进制版本
- Warp
- 高级路由
- BBR
- 流媒检测

### 菜单 8：查看连接信息

多协议模式下，菜单 `8` 改为三步：

1. 显示全局服务状态摘要
2. 让用户选择要查看的已安装协议
3. 进入该协议的连接信息菜单：
   - `1. 仅链接`
   - `2. 仅二维码`
   - `3. 链接 + 二维码`
   - `0. 返回`

## Connection Info Rules

### `vless+reality`

- 展示：
  - `REALITY 协议链接`
  - `REALITY 协议二维码`
- 继续支持 `vless://` 分享链接与 ANSI 二维码

### `mixed`

- 展示：
  - `Mixed HTTP 代理链接`
  - `Mixed SOCKS5 代理链接`
- 不提供二维码
- 如果用户选择二维码相关选项，只输出明确提示，不调用二维码生成

### `hy2`

- 展示：
  - `Hysteria2 协议链接`
  - `Hysteria2 协议二维码`
- 在链接或二维码之前，先输出简短参数摘要：
  - 域名
  - 端口
  - TLS 模式
  - 混淆状态
  - 带宽设置

## Config Generation Design

### 总体生成方式

`generate_config()` 不再依赖单一 `SB_PROTOCOL` 生成配置，而是改为：

1. 读取全局状态
2. 读取协议索引
3. 逐个加载已安装协议状态文件
4. 为每个协议生成对应 inbound JSON
5. 合并为一个完整的 `inbounds` 数组
6. 复用共享的 `outbounds`、`route`、`Warp` 与高级路由逻辑

### `vless+reality` 与 `mixed`

- 保留现有协议生成逻辑的核心行为
- 但其数据来源改为协议状态文件，而不是全局单协议变量

### `hy2`

新增独立的 `hy2` inbound builder。

基于当前 `sing-box` 官方文档，首版 `hy2` 需要支持：

- `type: hysteria2`
- `users`
- `up_mbps`
- `down_mbps`
- 可选 `salamander` 混淆
- 可选 `masquerade`
- 必需 TLS

### `hy2` TLS 生成策略

`sing-box` 官方 migration 文档已经给出从旧 `tls.acme` 迁移到 `certificate_provider` 的方向。

因此本项目的主实现策略应为：

- 手动证书模式：
  - 继续在 inbound `tls` 中写入 `certificate_path` 与 `key_path`
- ACME 模式：
  - 优先生成顶层 `certificate_providers`
  - `hy2` inbound 的 `tls.certificate_provider` 引用对应 provider
- 不再以旧的 inline `tls.acme` 作为主要设计目标

## Upgrade And Migration Design

### 旧单协议自动迁移

启动新脚本时，先执行：

- `migrate_legacy_single_protocol_state_if_needed`

触发条件：

- 不存在新的协议索引文件
- 但存在旧 `config.json`

迁移行为：

1. 自动识别旧配置中的协议类型
2. 从旧 `config.json` 提取参数
3. 如为 `vless+reality`，同时读取旧 `reality.key`
4. 写入对应的新协议状态文件
5. 创建协议索引文件
6. 写入当前 `CONFIG_SCHEMA_VERSION`

### 强制迁移矩阵

脚本内置按协议维护的兼容矩阵，输入为：

- 协议名
- 目标 `sing-box` 版本

输出为：

- 该协议要求的最低 `CONFIG_SCHEMA_VERSION`

矩阵用途：

- 升级 `sing-box`
- 安装新协议并重生成配置
- 修改某协议配置

以上所有行为在写配置前都必须先执行协议兼容检查。

### 强制迁移流程

如果某个已安装协议低于目标版本要求的 schema：

1. 将其标记为“必须迁移”
2. 禁止跳过
3. 强制进入该协议迁移向导
4. 更新协议状态文件中的 `CONFIG_SCHEMA_VERSION`
5. 所有待迁移协议完成后，才允许继续生成配置并重启服务

### 兜底校验

即使兼容矩阵未命中，也仍需保留：

- `sing-box check -c ...`

作为最终兜底校验。

但“是否必须迁移”的判定主逻辑仍以脚本兼容矩阵为准。

## Internal Interface Changes

需要新增或重构以下内部职责：

- `list_installed_protocols`
- `load_protocol_state <protocol>`
- `save_protocol_state <protocol>`
- `build_inbound_for_protocol <protocol>`
- `ensure_protocol_schema_compatible <protocol> <target_version>`
- `migrate_protocol_state_if_required <protocol> <target_version>`
- `migrate_legacy_single_protocol_state_if_needed`

需要废除的长期假设：

- `SB_PROTOCOL` 代表唯一已安装协议
- `.inbounds[0]` 永远代表当前协议

后续读取配置时应改为按协议 `tag` 或 `type` 精确查找目标 inbound。

## Test Scenarios

至少覆盖以下场景：

1. 旧单协议用户自动迁移到新结构成功
2. 安装单个协议成功：
   - `vless+reality`
   - `mixed`
   - `hy2`
3. 安装多个协议成功：
   - `vless+reality + mixed`
   - `vless+reality + hy2`
   - `mixed + hy2`
   - 三协议同时安装
4. 修改单个已安装协议时，其它协议状态与配置保持不变
5. `hy2` 证书模式：
   - ACME `HTTP-01`
   - ACME `DNS-01 (Cloudflare)`
   - 手动证书路径
6. 菜单 `8` 多协议查看流程正常
7. `mixed` 二维码分支不会调用二维码输出
8. 命中 breaking change 矩阵时，协议迁移不可跳过
9. 升级 `sing-box` 时仍默认保留未受影响协议配置

## Assumptions

- `Warp`、高级路由、BBR、流媒检测继续保持实例级
- `DNS-01` 首版仅实现 `Cloudflare`
- 兼容矩阵以内置常量或函数实现，不做远端动态更新
- `hy2` 首版连接信息以结构化展示为主，同时支持链接与二维码输出
