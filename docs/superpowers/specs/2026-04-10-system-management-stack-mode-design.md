# System Management And Stack Mode Design

## Goal

为 `sing-box-vps` 增加独立的系统管理菜单，并提供协议栈管理能力，覆盖入站监听协议栈、出站解析协议栈、Warp 交互限制、以及节点信息在 IPv4/IPv6 下的同步展示。

## Current State

- 主菜单直接暴露 `BBR` 开关，没有系统级子菜单。
- 协议入站统一写死 `listen: "::"`，没有 IPv4-only / IPv6-only / 双栈管理。
- 出站没有单独的协议栈偏好配置，也没有持久化层。
- `Warp` 开启后通过 `route.final` 或 `route.rules[].outbound = "warp-ep"` 接管流量，但脚本没有对“出站协议栈是否仍生效”做显式限制。
- 节点信息当前只按单个公网地址构建，不能在双栈场景下同时输出 IPv4 和 IPv6 分享信息。

## Requirements

### Menu Structure

- 主菜单新增 `系统管理`。
- `BBR` 从主菜单移入 `系统管理`。
- `系统管理` 至少包含：
  - `开启 BBR`
  - `协议栈管理`

### Stack Modes

- 协议栈管理拆成两个独立维度：
  - 入站协议栈：`ipv4_only`、`ipv6_only`、`dual_stack`
  - 出站协议栈：`ipv4_only`、`ipv6_only`、`prefer_ipv4`、`prefer_ipv6`
- 入站协议栈只展示当前系统能力允许的选项：
  - 仅 IPv4 主机：只允许 `ipv4_only`
  - 仅 IPv6 主机：只允许 `ipv6_only`
  - 双栈主机：允许 `ipv4_only`、`ipv6_only`、`dual_stack`
- 出站协议栈在 `Warp` 开启时不可修改，只允许查看当前保存值，并提示该设置当前不生效。

### Config Behavior

- 入站协议栈映射到所有协议入站的 `listen`：
  - `ipv4_only` -> `0.0.0.0`
  - `ipv6_only` -> `::`
  - `dual_stack` -> `::`
- 出站协议栈映射到：
  - `dns.strategy`
  - `direct` 出站的 `domain_resolver.strategy`
- `Warp` 开启时：
  - 保留已保存的出站协议栈值
  - 禁止在菜单中修改它
  - 在 UI 上明确提示 `Warp` 已接管出站路径，因此当前 direct 出站协议栈不生效

### Node Info Behavior

- 节点信息输出必须根据当前入站协议栈和主机公网地址能力动态生成。
- 双栈模式下：
  - 若检测到公网 IPv4 和公网 IPv6，则分别输出两套节点信息
  - 若只探测到其中一个，则仅输出对应那一套
- IPv6 分享地址需要在 URI 中使用方括号包裹主机部分。
- `查看节点信息` 的链接 / 二维码 / 链接+二维码 选择，对当前全部已安装协议都适用。

## Storage Design

- 新增独立状态文件：`/root/sing-box-vps/stack-mode.env`
- 文件包含：
  - `STACK_STATE_VERSION=1`
  - `INBOUND_STACK_MODE=...`
  - `OUTBOUND_STACK_MODE=...`
- 默认值：
  - 双栈主机：`INBOUND_STACK_MODE=dual_stack`
  - 单栈主机：与系统能力一致
  - `OUTBOUND_STACK_MODE=prefer_ipv4`

## System Capability Detection

- 启动协议栈菜单前动态探测：
  - 是否存在全局 IPv4 地址
  - 是否存在全局 IPv6 地址
- 检测优先使用 `ip -o addr show scope global`，避免依赖外部网络。
- 提供三个派生状态：
  - `ipv4`
  - `ipv6`
  - `dual`
- 如果既没有全局 IPv4 也没有全局 IPv6，保守回退为：
  - 入站默认 `ipv4_only`
  - 菜单中仅允许用户保留该默认值，并给出警告

## Config Generation Details

### Inbound Listen Address

- 在 `build_vless_inbound_json`、`build_mixed_inbound_json`、`build_hy2_inbound_json` 中不再写死监听地址。
- 新增统一辅助函数返回当前入站监听地址。

### Outbound Family Preference

- 根据 sing-box 当前文档，优先使用 `domain_resolver.strategy` 而不是继续扩展已废弃的 `domain_strategy`。
- 配置中新增本地 DNS server tag，用于 direct 出站域名解析。
- `direct` 出站追加：
  - `domain_resolver.server = "local-dns"`
  - `domain_resolver.strategy = OUTBOUND_STACK_MODE`
- 顶层 `dns.strategy = OUTBOUND_STACK_MODE`

## Node Info Generation

- 新增公网地址探测函数，分别获取：
  - `PUBLIC_IPV4`
  - `PUBLIC_IPV6`
- 新增地址格式化函数：
  - IPv4 原样输出
  - IPv6 用 `[` 和 `]` 包裹后再参与 URI 构造
- 现有 `build_vless_link`、`build_mixed_http_link`、`build_mixed_socks5_link`、`build_hy2_link` 接受任意单个地址；调用层负责按 IPv4/IPv6 逐套输出。

## Error Handling

- 若用户尝试选择系统不支持的入站模式，拒绝写入并提示。
- 若 `Warp` 开启时进入出站协议栈修改流程，直接提示并返回上一层。
- 若公网地址探测失败，节点信息仍继续输出可探测到的地址；若全部失败，回退到当前单地址探测逻辑并提示。

## Testing Strategy

- 菜单测试：
  - 主菜单出现 `系统管理`
  - `BBR` 不再直接出现在主菜单
  - 系统管理子菜单包含 `开启 BBR` 和 `协议栈管理`
- 协议栈测试：
  - 双栈系统下可选三种入站模式
  - 仅 IPv4 / 仅 IPv6 系统下限制正确
  - `Warp` 开启时禁止修改出站协议栈
- 配置生成测试：
  - 入站监听地址按模式写入
  - `dns.strategy` 与 `direct.domain_resolver.strategy` 同步写入
- 节点信息测试：
  - 双栈下分别输出 IPv4 和 IPv6 信息
  - IPv6 URI 主机正确加方括号
  - 仅存在单个公网地址时只输出对应一套
