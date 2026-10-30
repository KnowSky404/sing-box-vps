# 协议与组件完成契约

[English](full-protocol-completion.md) · [SPEC 状态](README.zh-CN.md)

状态：**FP-01–FP-11 已在记录的构建、协议和对端范围内实现并验收**。可选模式、其他厂商控制面、明确 Cloudflare marker 以外的公网连接及生产代理主机仍分别验收。清单基线为 2026-10-30 的 `f498234`，新证据不代表重跑全部历史集合。

## 范围与已有实现

基线包含 **15 个代理预设与 38 个组件记录**。当前注册表中的这些适配均已实现；组件生命周期提供 create、replace、delete、rebuild、takeover、recover 与敏感 export。它们不等于每个实例已完成认证或数据面验证。`capabilities` 的 `validated.status=not_assessed` 有意作为实例证据占位，不是 38 项缺失实现的清单。

当前注册表的完整分组如下：

| 范围 | 记录 | 已有证据边界 |
| --- | --- | --- |
| 代理预设（15） | `vless-reality`、`vless-plain`、`mixed`、`hy2`、`anytls`、`socks`、`http`、`shadowsocks`、`trojan`、`vmess`、`snell`、`tuic`、`hysteria`、`naive`、`shadowtls` | 上游矩阵已记录本地生命周期/配置及有界隔离数据面；分享、TLS 和 SubMan 仍受各协议表达能力约束。 |
| 已有运行证据的高级入站（4） | `direct-inbound`、`tun-inbound`、`redirect-inbound`、`tproxy-inbound` | 已有隔离 marker、资源和清理切片；可选 Redirect/TProxy 宿主策略具有明确的 IPv4 范围。 |
| 已有运行证据的端点（3） | `wireguard-endpoint`、`openvpn-client-endpoint`、`openvpn-server-endpoint` | internal/system-interface、peer/tunnel 和一次性 marker 证据；不代表外部账户或生产。 |
| 出站组件（20） | `ssh`、`tor`、`direct`、`bridge`、`selector`、`urltest`、`block`、`socks`、`http`、`shadowsocks`、`vmess`、`trojan`、`naive`、`hysteria2`、`hysteria`、`tuic`、`vless`、`anytls`、`snell`、`shadowtls`（注册表 ID 均加 `-outbound`） | 已有按协议隔离证明；以下分组/拒绝检查保留更窄的未验证分支。 |
| 规则集（3） | `route-rule-set-inline`、`route-rule-set-local`、`route-rule-set-remote` | 受管 CRUD、核心 check 与本地 HTTP 获取；引用文件仍归操作员所有。 |
| 补充组件验收（8） | `cloudflared-inbound`、`tailscale-endpoint`、`openconnect-endpoint`、`certificate-provider-acme`、`http-client-shared`、`resolved-service`、`network-namespace-default`、`network-namespace-unshare` | typed state、配置及生命周期已存在；已验收运行范围与剩余对端条件见下表。 |

原始证据见[上游矩阵](../wiki/Protocol-Coverage.md)、[组件契约](../wiki/Advanced-Components.md)及[数据面记录](../wiki/Data-Plane-Verification.md)。带日期的“此前缺失”或“仅配置检查”必须结合后续切片阅读；WireGuard/OpenVPN 系统流量、TUN/bridge 流量、受管 Redirect/TProxy 宿主策略及规则集 CRUD 均已在早期记录之后实现，不是待补的新适配器。

## 有限验收矩阵

下表记录当前状态并保留原有要求。隔离 fixture 使用一次性凭据、证书机构、路由和 namespace；不凭 mock 响应或 `sing-box check` 单独标记通过。

| ID | 范围及必要验收 | 执行边界 | 当前状态 |
| --- | --- | --- | --- |
| FP-01 | 受管 ACME provider：通过真实受管引用向私有测试 CA 申请证书，使用证书完成 TLS 连接，验证生命周期/CAS 和清理，保留操作员文件。 | 隔离 Docker，可复用 `tests/hy2_instance_acme_runtime.sh` 的 Pebble 方法；HY2 fixture 自身不证明独立组件 provider CRUD。 | 已验收：私有 CA 签发/TLS/引用保护及保留缓存清理 |
| FP-02 | 共享 HTTP client：将受管命名 client 绑定真实消费者，获取精确本地响应并观察配置路由，验证引用保护和 CAS 清理。 | 隔离本地 HTTP 端点与受管消费者；验证声明的 HTTP 版本，不能静默降级。 | 已验收：真实命名 client 消费、header/版本/detour 观测及引用保护清理 |
| FP-03 | resolved service：在一次性 system bus 注册，通过受管监听精确回答 TCP/UDP DNS 请求，验证服务/监听清理并保留宿主 resolver 配置。 | 带独立 DBus 的一次性 Linux Docker；私有策略须允许测试用户拥有 `org.freedesktop.resolve1`，不能据 socket 存在宣称权限已满足。 | 已验收：私有 bus 名称、精确 TCP/UDP DNS 及监听/名称清理 |
| FP-04 | default network namespace：绑定一次性既有 namespace，经其回读 marker，拒绝不存在的 namespace，并证明组件删除不会删除外部 namespace。 | 特权隔离 Docker，namespace 和路由归 fixture。 | 已验收：同版本安全 glibc 构建、真实 Agent 生命周期及隔离 TCP/拒绝证明；拒绝已知不安全或未知构建 |
| FP-05 | unshare network namespace：创建受管核心 namespace，观察隔离和受控 marker 路径，验证生命周期清理。 | 特权隔离 Docker，不接管宿主路由或 DNS。 | 已验收：同版本安全 glibc 构建、holder 生命周期及隔离 TCP/拒绝证明；拒绝已知不安全或未知构建 |
| FP-06 | Cloudflared 入站：使用有效的一次性 tunnel 身份，观察真实控制连接与 marker 流量，再断开/清理，不泄露 token。 | 需要明确获授权的 Cloudflare 测试 tunnel 和网络路径；缺 token 拒绝仅为负向检查。 | 已验收：授权真实 tunnel、HTTP/2 控制连接、公网 HTTPS→HTTP/1.1 marker 及资源清理 |
| FP-07 | Tailscale 端点：向明确的一次性控制面认证，与 peer 交换 marker，验证持久状态和接口清理；relay、路由通告、exit-node 和 SSH 分支各需自己的证据。 | 需要受控且兼容的测试控制面/peer 或获授权测试账户。 | 已验收：受控 Headscale 认证、internal/system IPv4 TCP+UDP、持久身份及清理 |
| FP-08 | OpenConnect 端点：向明确测试 VPN server 认证并交换 marker，验证选定 system/internal 路径和清理；一种 server flavor 不证明所有厂商或交互表单。 | 需要受控兼容服务端/profile；生产凭据不是 fixture。 | 已验收：私有 CA AnyConnect/ocserv、internal/system IPv4 TCP+UDP 及独立复核的接口/CAS 清理 |
| FP-09 | Selector：配置两个可区分的有效成员，以精确响应验证默认成员与明确切换。 | 隔离本地 upstream，保留已有单成员证据。 | 已验收：两个成员、默认及明确切换 |
| FP-10 | URLTest：使用可区分的健康/不健康成员及本地 health URL，观察成员失败和恢复，在有界等待后验证实际 marker 路径。 | 可控制故障的隔离 upstream，保留已有单成员证据。 | 已验收：健康→故障→恢复的实际选路 |
| FP-11 | Block 出站：让 UDP 经受管 block 路由，确认目的端未收到 marker，并确认 direct 正向对照成功；保留核心和删除证据。 | 隔离本地 UDP marker；没有正向对照的超时不充分。 | 已验收：UDP 拒绝及成功的 direct 正向对照 |

## 继续明确保留的兼容性与外部边界

- HTTPUpgrade 和 WebSocket early data 继续由当前 transport guard 阻断。已有拒绝测试必须保留原 profile 与错误代码；移除 guard 必须有目标核心正负向运行证据。
- 已移除的 ShadowsocksR、DNS outbound 和旧 WireGuard outbound 不列为待实现功能；WireGuard 使用现代 endpoint。
- HTTP/SOCKS 明文限制、不可表达的标准 URI、证书信任跳过及缺少 SubMan adapter 均是协议契约，不能用虚构 URI 或有损 payload 完成验收。
- 平台/build 条件、`with_naive_outbound` 与 `libcronet`、embedded Tor、内核权限及 HY2 Realm 等附加模式保留各自范围；既有 marker 不覆盖所有选项组合、native UDP 模式或厂商控制面。
- 真实 SubMan 身份/聚合成员保留记录在命名验收中；公网、真实 provider 账户、生产验收、PR 审查/合并及 Wiki 发布分别举证，不能靠重标隔离结果完成。

## 证据与执行顺序

优先 FP-01 至 FP-05，再完成 FP-09 至 FP-11，它们可用隔离 fixture 且无需真实账户写入。FP-06 至 FP-08 先准备受控对端并记录所选范围；本地对端可证明受测协议路径，真实厂商/账户和生产仍是独立验收。前置缺失或实验失败必须继续记录为未完成。

每个完成项记录受测代码/核心版本或 hash、精确命令、配置 check、观察到的 marker 或预期拒绝、相关 CAS/回滚、产物位置与清理结果；凭据脱敏，敏感配置保持私有。未变的既有结果按 AGENTS.md 第 4.2 节复用；本文不要求重跑所有旧协议或平台。仅按实际改动增加所需测试和场景，空执行、skip 或取消均不能替代证据。

## 2026-10-30 执行记录

本地私密证据目录为 `/tmp/sbv-protocol-spec-evidence-20261030`（权限 700），包含组件/HTTP client、resolved、namespace、分组及 ACME 结果和日志；凭据和完整 fixture 配置不写入 PR。

- FP-01 复用原 HY2 Pebble fixture，完成两次 HTTP-01 签发、可信传输、缓存复用及共存验证；独立扩展创建受管 provider，申请新的私有 CA 证书并完成 HTTPS 代理 marker。操作员 consumer 仍引用时，删除以 `config_check_failed`/unknown-reference 拒绝，revision/config 不变；移除 consumer 后删除 provider，保留证书缓存。重启私有 CA 后的 fixture 重试使用新域名/缓存；先前 issuer 信任失败记录保留，不计作成功。
- FP-02 在真实规则集 HTTP server 观察 `HTTP/1.1`、配置的 `X-Component-Marker` 与 detour 源地址 `127.0.0.2`。引用中的 client 删除返回 `component_referenced`，revision/config 不变，随后正常删除三个记录。
- FP-03 在私有 system bus 注册 `org.freedesktop.resolve1`，经 TCP/UDP 返回精确 `203.0.113.7`。fixture 仅授权一次性容器 root 拥有此名称；socket 存在不足以证明权限。删除后监听/名称消失，不替换宿主 DNS。
- FP-04/FP-05 将真实 Agent 创建/删除、缺失路径拒绝，与独立 `namespace_core_runtime.sh` 的正向和关闭端口检查组合。官方 **1.14.2 Linux ARM64 glibc** 压缩包 SHA-256 为 `87db5c3a96ebad1c44c0be1fe7955db2f76b8c97bbc0ed62173063d675e078cf`，二进制 SHA-256 为 `2d3a13a6c4661d8a89af73a79e6c78289f41ebca83ed7a20a15d7f4c2b576366`。两类 namespace 均回读精确 marker，关闭端口拒绝后核心仍存活，资源正常清理。Agent 生命周期运行时 SHA-256 为 `5ae09c09e99c0c4603164e09c361a4231472a86ccdf21adb236994a34c7a3982`。
- 同版本官方 ARM64 `with_purego` 构建实际退出 **139**：default 在 marker 已就绪时通过 dial 复现，unshare 在启动时复现。GDB 捕获 libc `start_thread` 的 SIGSEGV；固定上游代码使用锁定 OS thread。该证据证明受测构建失败，不代表已经完全定位 native-code 根因。未改变默认核心版本或下载 URL。组件写入对准确的 Linux/ARM64/1.14.2/tag 组合返回 `namespace_runtime_unsafe_build`，也覆盖原始 `netns`、`control_dialer.netns`、`tunnel_dialer.netns` 引用。该准确平台/版本缺少构建元数据时，inventory 保持 `not_assessed`，写入以 `namespace_runtime_build_not_assessed` 拒绝，不称作已确认崩溃。缺失/default 路径访问失败另在发布前阻断。候选二进制门禁还检查既有 namespace 声明及已知 Dial 字段，在安装、更新或修复替换二进制/运行库/marker 前拒绝同一不安全或未确认组合，普通 header 键不会误触发；对应 `binary_namespace_guard.sh` 与 [RT-01 契约](runtime-transactions.zh-CN.md)。真实官方 purego/glibc 二进制也分别在候选元数据门禁返回拒绝/允许，未安装或激活；结果/hash 为 `/tmp/sbv-binary-namespace-actual.env` 与 `.sha256`。
- FP-06 使用所有者授权的一次性 Cloudflare tunnel，HTTP/2 控制传输及 HTTP/1.1 回环 origin。受管创建/删除、核心 check、公网 HTTPS 精确 marker 均通过，其他私网目的地址继续拒绝。运行时 SHA-256 为 `37f96a49d06c6ac3fe9f858d31717d3797fedda640a9e71c3d71be18385ff519`。准确测试 tunnel 与 DNS 记录已删除，API 回读无匹配资源；不据此声称任意 TCP/UDP tunnel 模式已通过。
- FP-07 使用私有兼容 Headscale **0.29.6** 控制面、可信 TLS、内嵌 DERP/STUN 和一次性 peer，完成真实认证、internal 与命名 system-interface 的 IPv4 TCP/UDP marker、重启后持久节点 ID 复用、revision/CAS 删除及系统 TUN 清理，无需手工路由 workaround。证据为 `/tmp/sbv-vpn-runtime-20261030-final4/fp07-accepted/`；运行时 SHA-256 为 `5ae09c09e99c0c4603164e09c361a4231472a86ccdf21adb236994a34c7a3982`，核心 SHA-256 为 `b8610f45abb7e967e195264383f5cbd20fba7821a3c37e3a8c4c5ab6cad28eac`。这不代表 Tailscale 厂商云、SSH、exit-node、路由通告或 peer-relay 验收。
- FP-08 固定 **ocserv 1.1.6-3**、AnyConnect flavor，严格验证一次性 CA，确认真实 DTLS 及 internal/system IPv4 TCP/UDP marker，VPN 源地址为 `10.91.0.82`，没有 crypto override。流量证据位于 `/tmp/sbv-vpn-runtime-20261030-final4/`，冻结运行时/核心 hash 与 FP-07 相同。修正明确的接口不存在断言后，另在新建 system-mode 创建/IPv4 分配/CAS 删除中独立复核，`/tmp/sbv-vpn-runtime-20261030-lifecycle/container/actual-interface-cleanup.env` 记录 `openconnect_system_interface_absent=1`、`managed_components_empty=1`；该轮运行时 SHA-256 为 `f9d015ab9fbe0e68a65b43d763347139f6a1b493660f9261ca66ec407ee8c5b3`，期间的二进制门禁不改变已验 VPN 数据路径。新 fixture 与旧诊断/原型容器均确认移除；不把该结果扩展到所有厂商 flavor 或交互认证。
- FP-09/FP-10/FP-11 使用生产组件 serializer 与真实 1.14.2 核心，验证可区分 Selector 成员、URLTest 失败/恢复和带 direct 精确对照的 UDP block。既有 Agent 生命周期证据与新增数据面检查分别记录。

namespace 安全构建证据仅覆盖 **Debian 12 / glibc 2.36 / ARM64**。操作员可提供已验证且兼容的 native/同版本构建；项目不会静默把全局核心替换成 glibc 变体。官方 glibc 资产有自身依赖条件，**Rocky 8 的 glibc 2.28 未被覆盖**，不能假定可用。其他平台、版本和可解析的安全构建保留原有处理，这不是通用安全保证。

仅在新建的一次性 Docker 容器中，准备 `/tmp/sbv-component-disposable` 后使用 `SBV_COMPONENT_RUNTIME=1`。`component_runtime_acceptance.sh` 还会拒绝既有安装；`COMPONENT_RUNTIME_CASES` 选择 `shared`、`resolved`、`default`、`unshare` 或预期拒绝的 `bad-build`，`NAMESPACE_LIFECYCLE_ONLY=1` 将受管 CRUD 与独立核心数据面 fixture 分开。ACME wrapper 复用 `hy2_instance_acme_runtime.sh` 并要求私有 Pebble 二进制，provider 使用本轮新域名/缓存。`selector_urltest_runtime.sh`、`namespace_core_runtime.sh` 要求新的产物目录。它们不修改宿主 DBus、resolver、防火墙或 namespace。
