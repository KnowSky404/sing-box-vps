# sing-box 1.14.0 协议能力核对矩阵

审阅日期：2026-09-06

目标稳定版：`v1.14.0`

源码提交：`0b8995879f29a9b98ee027bc17b75e101445b238`

审计起点脚本：`SCRIPT_VERSION=2026090402`；当前交付工作区已提升为 `SCRIPT_VERSION=2026091504`，`SB_SUPPORT_MAX_VERSION=1.14.0`

本文是上游能力核对，不能把上游已注册等同于 sing-box-vps 已实现。矩阵的四种状态分别表示：

- `upstream`：目标版本源码中是否有该角色和 type 的注册实现；`conditional` 表示构建 tag、平台、CGO 或外部控制面有条件。
- `implemented`：本项目是否已经提供状态、配置组合、生命周期、导出/分享等管理链路；`none` 不表示上游不可用。
- `available`：当前官方 ARM64 Linux 发布包中是否已包含该角色的注册实现，以及仍需满足的构建、平台、运行库或外部控制面条件；它独立于源码中存在注册函数。
- `validated`：本轮实际取得的证据。`registry-check` 只证明目标二进制能识别该 type 并进入初始化校验；`project-real-tcp` 表示回读了项目真实 TCP 业务闭环 artifact，`project-real-udp` 表示回读了经 SOCKS5 UDP ASSOCIATE 的真实 UDP payload artifact，`project-real-tcp+udp` 表示两者均已取得；`project-real-tun-resources` 只表示在特权隔离 Docker 中回读了 sing-box core-owned TUN 接口、iproute2 rule/route 与删除清理 artifact；`project-real-bridge-resources` 只表示回读了 bridge outbound 动态 TUN、core-created rule/route 及删除清理 artifact；`project-real-openvpn-tcp+udp` 表示在特权隔离 Docker 中分别以合成证书和用户名/密码组成 `system:false` OpenVPN server/client pair，经受管 direct inbound 回读 TCP 与 UDP marker payload，并完成目标核心 check 与每个 endpoint 删除清理；`project-real-openvpn-system-resources` 只表示在特权隔离 Docker 中创建命名 `system:true` OpenVPN server/client，回读 core-owned 系统接口、配置地址/前缀、MTU、隧道日志和 diagnose，并按 revision 完成接口删除清理，不包含 packet payload 或宿主路由；`project-real-redirect-tcp` 表示在特权隔离 Docker 中用临时 owner-scoped `OUTPUT REDIRECT` 规则回读 redirect TCP marker，并在 probe 退出时清理规则；`project-real-tproxy-tcp+udp` 表示在特权隔离 Docker 的 disposable veth/network namespace 中以临时 fwmark policy route 和 `PREROUTING TPROXY` 规则回读 TProxy TCP+UDP marker，并完成策略/接口清理。后两项的 policy ownership 固定为 verification-container-only/not-managed，不表示宿主策略所有权。它们不能由 `check`、监听端口或进程存活代替，也不代表公网可达、主机透明策略、外部控制面或生产部署。

另有协议专用的 `project-real-snell-tcp+packet-api-udp`：表示在固定核心、隔离 Docker 中同时回读 Snell TCP marker 与经其认证 TCP 会话 packet API 承载的 UDP marker；它明确不是原生 UDP listener 证明。`project-real-ssh-tcp` 表示在特权隔离 Docker 中由一次性 OpenSSH 服务接收 pinned-host-key SSH outbound 的 direct-tcpip loopback marker，并完成组件 CAS 删除；它不表示外部 SSH 服务、公网、生产或 UDP 证据。`project-real-socks-tcp` 表示在同类容器中由一次性认证 SOCKS5 upstream 接收 managed SOCKS outbound 的 CONNECT loopback marker，并完成组件 CAS 删除；它不表示外部 proxy、公网、生产或 UDP 证据。`project-real-selector-tcp` 表示在同类容器中由单成员 selector 选择内建 direct outbound 回读 loopback marker，并完成组件 CAS 删除；它不表示多成员切换、URLTest、公网或生产证据。`project-real-urltest-tcp` 表示在同类容器中由单成员 URLTest 以 loopback HTTP URL 完成健康探测并经 route 回读 marker，再完成组件 CAS 删除；它不表示多成员故障切换、公网或生产证据。`project-real-shadowsocks-tcp` 表示在同类容器中由 managed SS2022 outbound 经既有 SS2022 inbound/upstream 回读 loopback marker，并完成组件 CAS 删除；它不表示外部 Shadowsocks、公网、生产、UDP 或 SubMan 证据。`project-real-direct-tcp` 表示在同类容器中由 managed direct outbound 经 route options 的 destination override 回读 loopback marker，并完成组件 CAS 删除；它不表示宿主策略、公网或生产证据。`project-real-block-reject` 表示在同类容器中由 managed block outbound 对 synthetic route 请求产生预期非零拒绝，并完成组件 CAS 删除；它不表示防火墙丢弃、宿主策略、公网或生产证据。`project-real-vless-tcp` 表示在同类容器中由 managed VLESS outbound 连接一次性本地 VLESS upstream，再经 upstream route 回读 loopback marker，并完成组件 CAS 删除；它不表示外部 VLESS 握手、公网、生产、TLS/REALITY、UDP 或 SubMan 证据。`project-real-tor-external-tcp` 表示在同类特权容器中由 managed Tor outbound 启动镜像内外部 `tor` executable，经认证 SOCKS5 route 访问 `check.torproject.org` 并确认 Tor 页面响应，再完成组件 CAS 删除；它不表示 Tor 公网稳定性、匿名性保证、生产或 SubMan 证据。

表中“版本”优先表示本项目实现时的核心版本门槛：除标明“自 1.14.0”的能力外，继续以项目已有的 1.13.x 兼容路径为下限；它不声称是该协议在 sing-box 历史上的首次引入版本。需要 1.14.0 的 type 或字段必须在目标版本门控后才可生成。

2026-09-09 高级组件增量：本项目新增独立 `components.json`（schema 1、revision/CAS）和 30 项 runtime component registry，接入 direct/tun/redirect/tproxy/cloudflared inbound、WireGuard/Tailscale/OpenConnect/OpenVPN endpoint，以及 SSH/Tor/direct/bridge/selector/urltest/block 和协议 outbound 的受控状态/config 组合。`implemented` 在本增量中表示状态读取、类型专属边界、配置合并、引用/依赖图、监听计划、Agent list/create/replace/delete 和目标核心校验切片已存在；组件的静态 `available` 仍为 `null`，另在 registry 每次读取时填充不缓存的 `environment` 观察（目标核心版本、平台、root/工具/运行库、构建 tag 和外部认证依赖），其 `status` 只能是 `available`、`unavailable` 或 `not_assessed`，不等同于连接验证。`validated` 默认 `not_assessed`。高级 inbound/endpoint 及注册 outbound/group 现在支持无损保护接管和敏感单组件导出；内建 `direct`/`block` 与生成器自有 `warp-ep` endpoint 仍由生成器拥有，未知 outbound、保留 tag 冲突、未归属全局 route rule 及任意未建模顶层字段会阻断接管。这些组件不进入普通分享节点索引，外部控制面、路由/防火墙权限和真实数据面均不由 registry 或 `sing-box check` 推断；若目标二进制未报告 `Tags:`，条件构建保持 `not_assessed`，已报告但缺少所需 tag 时为 `unavailable`。因此下方组件行的 D/T/E/R 与导出、分享、SubMan 仍按此边界记录，完整协议目标继续未完成。

2026-09-10 持久化事务增量：高级组件写入现在在 `${SB_PROJECT_DIR}.component-write.lock` 中原子发布 `transaction.json`，记录 owner、CAS revision、before-active、publish/resources/service/committed 阶段和防火墙外部日志意图。`sbv agent component recover --json --yes --expected-revision N` 只接受已结束的 owner、可信快照和严格 phase/schema；中断发生在发布或资源阶段时先补偿防火墙再恢复 state/config/service，无法证明安全时保留目录并返回稳定错误。`component diagnose` 暴露 pending/phase 摘要；这仍不是公网防火墙、TUN/透明路由、Endpoint 外部认证或真实数据面验证，完整协议目标继续未完成。

2026-09-10 SSH outbound 增量：managed `ssh` component 现在按固定 [1.14.0 SSH outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/ssh.md) 与 [shared Dial Fields](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/shared/dial.md) 的 `SSHOutboundOptions` 建立 allowlist；`server` 必须是安全非空字符串，端口限制为 1–65535，且必须提供 password、private key 或 private-key path 之一。listable private/host key 与 cipher/MAC/KEX 字段只接受字符串列表形状，deprecated `domain_strategy` 和任意未建模字段在 state/CAS、live takeover 前拒绝；`host_key` 仍可省略以保持上游“接受任意主机密钥”的兼容语义，但 inventory 以 `host_key_verification=unverified` 披露，非空固定列表才标记 `pinned`。回归覆盖密码、路径、PEM 私钥、缺凭据、孤立 passphrase、端口越界、未知字段、脱敏 inventory、live takeover、路由规则保留与敏感 export；未执行远端 SSH 登录，不把 `sing-box check` 或状态层写成 SSH 数据面/主机密钥验证证据。

2026-09-10 Tor outbound 增量：managed `tor` component 现在按固定 [1.14.0 Tor outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/tor.md) 与 [shared Dial Fields](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/shared/dial.md) 的 `TorOutboundOptions` 建立 allowlist；Tor-specific 字段仅允许 `executable_path`、`extra_args`、`data_directory` 和字符串值 `torrc` map，且拒绝 deprecated `domain_strategy`、控制字符及错误类型。未提供 executable path 的记录保留上游 embedded 语义，但 inventory 标为 `runtime_mode=embedded_unverified`；指定路径则标为 `external`，不声称路径存在、构建包含 `with_embedded_tor`/CGO 或已有 Tor circuit。回归覆盖 external/embedded 两种记录、Dial Fields、torrc/extra_args 类型边界、控制字符、脱敏运行模式和 live takeover/路由规则保留；未执行外部 Tor 安装、嵌入构建、控制面或真实数据面验证。

2026-09-10 selector/urltest group 增量：managed `selector` 与 `urltest` component 现在按固定 [1.14.0 selector](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/selector.md) / [urltest](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/urltest.md) schema 建立 allowlist；两者都要求非空且唯一的 outbound member 列表，selector 的 `default` 必须属于该列表，URLTest 的 `tolerance` 限制为 uint16，并拒绝错误 scalar、selector-only/urltest-only 交叉字段和未知字段。图校验继续负责把每个成员解析到实际 outbound 并阻断依赖环，inventory 仅显示脱敏 `member_count`。回归覆盖 render、成员重复/default 越界、字段类型、live takeover 与路由规则保留；未把 URLTest 探测 URL 的可达性或真实组切换数据面写成验证证据。

2026-09-10 SOCKS outbound 增量：managed `socks` outbound component 按固定 [1.14.0 SOCKS outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/socks.md) 与 shared Dial Fields 建立 typed allowlist；`server`/`server_port`、版本 `4|4a|5`、用户名/密码、TCP/UDP network、UDP-over-TCP 及拨号字段均按目标类型校验，拒绝 deprecated `domain_strategy`、未知字段、错误版本/网络/端口和控制字符。组件仍使用统一 state/CAS、接管、重建、导出和配置图/监听/核心校验事务，凭据只在敏感 component export 返回。1.13.18/1.14.0 官方 ARM64 核心对最小组合配置 `check` 均通过；未把核心检查扩大为远端 SOCKS 握手或真实出站数据面证据。

2026-09-10 HTTP outbound 增量：managed `http` outbound component 按固定 [1.14.0 HTTP outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/http.md)、Outbound TLS 与 shared Dial Fields 建立递归 typed allowlist；server/port、用户名/密码、path、HTTP headers、TCP-only 语义和 TLS 的 ECH/uTLS/REALITY 嵌套字段均受控，未知/弃用字段、错误 scalar/list、非法 header 名和控制字符在 state/CAS 与接管前拒绝。统一 component state/CAS、接管、重建、敏感导出、图/监听/核心校验事务复用不变。1.13.18/1.14.0 官方 ARM64 核心对明文与启用 TLS 的最小 HTTP outbound 配置 `check` 均通过；真实 HTTP CONNECT 数据面在后续 2026-09-12 增量中单独记录。

2026-09-10 Shadowsocks outbound 增量：managed `shadowsocks` outbound component 按固定 [1.14.0 Shadowsocks outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/shadowsocks.md)、SIP003、UoT、multiplex 与 shared Dial Fields 建立 typed allowlist；server/port、method/password、SS2022 strict Base64 16/32-byte key、TCP/UDP network、插件及嵌套选项均受控，未知/弃用字段、错误方法/密钥长度/插件、错误 scalar/list 和控制字符在 state/CAS 与接管前拒绝。统一 component state/CAS、接管、重建、敏感导出、图/监听/核心校验事务复用不变。1.13.18/1.14.0 官方 ARM64 核心对 SS2022 128/256、传统 AEAD、插件、双网络/UoT/multiplex 最小配置 `check` 均通过；未把核心检查扩大为远端 Shadowsocks 握手或真实 TCP/UDP 数据面证据。

2026-09-10 VMess/Trojan outbound 增量：managed `vmess` 与 `trojan` outbound component 按固定 [1.14.0 VMess](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/vmess.md)、[Trojan](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/trojan.md)、V2Ray transport、Outbound TLS、multiplex 与 shared Dial Fields 建立 typed allowlist；VMess 的 UUID/security/alter_id/packet encoding 与 Trojan password、TCP/UDP network、TLS、transport、multiplex 均受控，未知/弃用字段、错误 scalar/list、控制字符、HTTPUpgrade、WS early data、明文 QUIC 与 lite-gRPC `permit_without_stream` 在 state/CAS 与接管前拒绝。凭据只经敏感 component export 返回，不生成服务端分享 URI 或 SubMan 载荷。两版官方 ARM64 核心对 VMess TLS+WS、Trojan TLS+gRPC 及明文最小 outbound `check` 均通过；这不代表远端握手、TLS 信任、QUIC/UDP 或真实出站数据面验证，完整目标仍未完成。

2026-09-10 VLESS outbound 增量：managed `vless` outbound component 按固定 [1.14.0 VLESS](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/vless.md)、V2Ray transport、Outbound TLS、multiplex 与 shared Dial Fields 建立 typed allowlist；UUID、空 flow/`xtls-rprx-vision`、TCP/UDP network、packet encoding、TLS、transport 与 multiplex 均受控，省略 packet encoding 保留上游 xudp 默认。Vision 仅允许启用 TLS 且不带 transport；HTTPUpgrade、WS early data、明文 QUIC、lite-gRPC `permit_without_stream` 和错误 flow/transport 组合在 state/CAS 与接管前拒绝。凭据只经敏感 component export 返回，不生成服务端分享 URI 或 SubMan 载荷；两版核心 typed check 及远端握手/数据面证据边界均单独记录，完整目标仍未完成。

2026-09-10 AnyTLS outbound 增量：managed `anytls` outbound component 按固定 [1.14.0 AnyTLS](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/anytls.md)、Outbound TLS 与 shared Dial Fields 建立 typed allowlist；`server`、`server_port`、非空 `password`、启用 TLS、可选 idle-session fields 和 `client_metadata` 均按目标类型校验。AnyTLS adapter 固定承载 TCP/UDP，不提供可配置的 `network`、transport 或 multiplex 字段；`tcp_fast_open=true` 因上游 lazy connection 限制在 state/CAS 与接管前拒绝。TLS 嵌套字段复用 outbound-TLS 校验，凭据只经敏感 component export 返回。两版官方 ARM64 核心对 TLS/session/shared-Dial 最小 AnyTLS outbound `check` 通过；未验证远端 AnyTLS 握手或 TCP/UDP 数据面，完整目标仍未完成。

2026-09-11 Snell outbound 增量：managed `snell` outbound component 按固定 [1.14.0 Snell](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/snell.md) 与 shared Dial Fields 建立版本分型 typed allowlist；`server`、`server_port`、非空 PSK、可选 userkey/reuse、TCP/UDP network 与拨号字段逐项校验。outbound 版本只允许 `4` 或 `6`：v4 只接受 HTTP obfuscation 的 `obfs_mode`/`obfs_host`，v6 只接受 traffic shaping 的 `mode`，且 v6 PSK 至少 12 字节；未知、弃用、控制字符、重复 network、越界端口及版本交叉字段在 state/CAS 与接管前拒绝。Snell v5 QUIC proxy 不作为独立 outbound 暴露，inbound v5/v6 仅分别映射 outbound v4/v6，UDP 业务经 TCP packet API 承载。敏感凭据只在 component export 返回。1.14.0 官方 ARM64 核心对 v4/v6 最小配置 `check` 通过，1.13.18 明确拒绝未知 type；这不代表远端 Snell 握手或 TCP/UDP 数据面，完整目标仍未完成。

2026-09-11 Hysteria2 outbound 增量：managed `hysteria2` outbound component 按固定 [1.14.0 Hysteria2](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/hysteria2.md)、QUIC、Outbound TLS 与 shared Dial Fields 建立 typed allowlist；标准路径支持 server 与互斥的 server_port/server_ports、port hopping、up/down Mbps、salamander/gecko obfs、password、TCP/UDP network、必需 TLS、QUIC fields、BBR profile 与 Chrome QUIC 控制，Realm 路径要求 server URL、realm ID、STUN 列表并约束端口映射/IP version/HTTP client。v1 Hysteria 的 `auth` 与已弃用接收窗口字段不会混入，未知/弃用字段、错误分型、控制字符和冲突组合在 state/CAS 与接管前拒绝。敏感凭据只在 component export 返回；1.14.0 官方 ARM64 核心对标准 Hysteria2 outbound `check` 通过，这不代表远端 QUIC 握手或 UDP 数据面，完整目标仍未完成。

2026-09-11 Hysteria v1 outbound 增量：managed `hysteria` outbound component 按固定 [1.14.0 Hysteria](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/hysteria.md)、QUIC、Outbound TLS 与 shared Dial Fields 建立 typed allowlist；支持 server 与互斥的 server_port/server_ports、hop_interval、`up`/`down` 网络带宽兼容字段、up_mbps/down_mbps、字符串 obfs、auth/auth_str、TCP/UDP network、必需 TLS 与 QUIC fields。每个方向要求至少一种带宽声明，auth 接受上游 Base64 字符串或字节数组；Hysteria2 的 password、Salamander/Gecko、BBR、Realm 以及 v1 已弃用接收窗口字段不会交叉。敏感凭据只在 component export 返回；1.14.0 官方 ARM64 全字段和 1.13.18 兼容子集 `check` 通过，这不代表远端 Hysteria 握手或 UDP 数据面，完整目标仍未完成。

2026-09-11 TUIC outbound 增量：managed `tuic` outbound component 按固定 [1.14.0 TUIC](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/tuic.md)、QUIC、Outbound TLS 与 shared Dial Fields 建立 typed allowlist；支持 server/server_port、UUID/password、cubic/new_reno/bbr 拥塞控制、native/quic UDP relay、可选 UDP-over-stream、zero-RTT、heartbeat、TCP/UDP network 与必需 TLS。`udp_relay_mode` 与 `udp_over_stream` 冲突在 state/CAS 与接管前拒绝；1.14.0 官方 ARM64 全字段和 1.13.18 兼容子集 `check` 通过，这不代表远端 TUIC 握手或 UDP 数据面，完整目标仍未完成。

2026-09-11 NaiveProxy/ShadowTLS outbound 增量：managed `naive` outbound 按固定 [1.14.0 NaiveOutboundOptions](https://github.com/SagerNet/sing-box/blob/v1.14.0/option/naive.go) 建立 typed allowlist，保留 server/port、username/password、extra headers、HTTP/2/QUIC、UDP-over-TCP、窗口、Naive 限定 TLS 与 shared Dial Fields；非零 `insecure_concurrency` 与 QUIC 冲突，unsupported TLS、错误 UoT/header/window、未知/弃用字段在 state/CAS 与接管前拒绝。managed `shadowtls` outbound 按固定 [1.14.0 ShadowTLSOutboundOptions](https://github.com/SagerNet/sing-box/blob/v1.14.0/option/shadowtls.go) 建立 TCP-only wrapper typed allowlist，保留 server/port、版本 1–3、password、必需 TLS 与 shared Dial Fields，并与本项目 inbound composite 分离。1.14.0 官方 ARM64 完整 Naive（bbr2）/ShadowTLS 与 1.13.18 兼容子集 `check` 通过；Naive 仍需 `with_naive_outbound`/`libcronet.so`，核心检查不代表库加载、远端握手或数据面，完整目标仍未完成。

2026-09-12 ShadowTLS inbound composite/export 增量：受管 ShadowTLS 客户端不再输出无法承载内层目的地址的孤立 `shadowtls` outbound，而是为每个用户生成一个 ShadowTLS transport outbound 加一个经 `detour` 指向该 transport、目标为 loopback Mixed 的 HTTP outbound；`build_singbox_client_config` 与 Agent link 同时保留完整依赖图，并只把 HTTP primary tag 放入 selector。新增严格的 active marker/store/config 读取和本地 SOCKS 探针客户端生成器，拒绝版本、用户、握手、detour、证书信任或 tag 依赖不一致。Docker run `20260912001650` 在共存和 runtime smoke 两个场景中以持久 SAN 证书启动 handshake cover，固定 1.14.0 核心 `check` 后经 ShadowTLS outer → loopback Mixed → direct 访问 HTTP marker，`result.env` 均为 `RESULT=success`；证据限定在隔离容器/回环，不代表公网、外部 handshake、生产部署、SubMan 或全协议目标完成。

2026-09-12 NaiveProxy TCP data-plane 增量：验证入口新增严格的 active marker/store/config loader 与 probe-client generator，固定读取单一 `network:["tcp"]` Naive 实例，复用生产 exporter 输出带公开证书的完整 Naive outbound，并核对渲染后的 listener、用户认证和 TLS 字段；不接受私钥、未知状态或配置/typed store 漂移。安装器现在从官方归档 staging `libcronet.so` 到 `/usr/local/lib/libcronet.so`，写入 hash marker 并刷新动态链接器缓存；核心升级的独立备份 manifest 同时记录库和 marker，配置/check/服务失败时与二进制一起恢复；未由脚本管理的同名库不会被覆盖，卸载仅移除 hash 仍匹配的受管库。完整 Docker run `20260912014158` 的共存场景固定 1.14.0 核心先执行 server/client `check`，再经 Naive TLS + HTTP/2、loopback SOCKS 和 direct 访问 HTTP marker，`protocol-probes/naive/result.env` 为 `RESULT=success`；严格渲染配置与库 hash artifact 在定向复跑 `20260912022837` 中再次通过，两个场景均成功。证据限定在隔离容器/回环和官方 ARM64 `with_naive_outbound`/`libcronet.so`，不代表 Naive UDP/HTTP3、公网可达、外部认证、生产部署、SubMan 或全协议目标完成。

2026-09-12 HTTP outbound 数据面与 Agent 输出安全增量：`multi_protocol_coexistence` 新增受认证的 loopback HTTP proxy fixture，使用 typed `http` outbound 将 SOCKS5 客户端的 CONNECT 请求路由到本地 marker，并逐项核对 `Proxy-Authorization`、自定义 header、HTTP outbound 配置和 exact response；`http-outbound.result.env` 在完整 Docker run `20260912051138` 中为 `RESULT=success`，同 run 的其他可执行协议探针保持成功，既有 TUIC 常规结果仍为 `unsupported`。为防止生成配置时的进度日志污染 Agent envelope，`--json` 命令现在将人类可读日志写入 stderr，stdout 保持单一 JSON object；组件重生成会从 live config 恢复高级路由和 Warp 开关，避免 component-only CAS 写入静默重置路由。`tests/agent_json_regression.sh` 覆盖两项回归。数据面证据仅属于固定 1.14.0、隔离 Docker/loopback 与合成代理，不代表公网可达、外部代理、生产部署、外部认证、SubMan 或全协议目标完成。

2026-09-10 TUN 路由安全增量：启用的 managed TUN 若设置 `auto_route=true`，候选配置会在顶层 `route` 自动补 `auto_detect_interface=true`；已有配置明确关闭该保护且未设置 `default_interface` 时 fail-closed，明确选择默认接口则保留原设置。该门禁只防止配置层自捕获环路，不宣称已接管主机策略路由、nftables、DNS 劫持或透明数据面，完整协议目标继续未完成。

## 版本与证据

GitHub Releases API 在本轮返回的最近发布为 `v1.15.0-alpha.2`（`prerelease=true`，2026-09-05），因此排除预发布；最近的稳定发布为 `v1.14.0`（`prerelease=false`，2026-08-31）。官方地址：

2026-09-07 再次读取 `releases/latest`，稳定版仍为 `v1.14.0`，`draft=false`、`prerelease=false`，未改变本轮固定目标。

同日资源预检增量：原四协议的固定监听计划取自共享注册表，服务端候选与结构化 Mixed 状态新增地址/传输/端口冲突检查。真实 1.13.18/1.14.0 均验证同数字 TCP/UDP 可启动、不同 loopback IPv4 地址同端口的 TCP 标记请求，以及等价 IPv6 地址冲突；`::` 与 IPv4 重叠另在无网络只读 Docker 中验证。防火墙删除引用保护为 mock 后端调用证据，不是宿主机防火墙实测或完整资源归属事务；UDP 监听与启动不计作 UDP payload 已验证。没有因此新增任何协议的 implemented 声明。

- Release：[v1.14.0](https://github.com/SagerNet/sing-box/releases/tag/v1.14.0)
- Release API：[v1.14.0 JSON](https://api.github.com/repos/SagerNet/sing-box/releases/tags/v1.14.0)
- 官方文档：[inbound](https://sing-box.sagernet.org/configuration/inbound/)、[outbound](https://sing-box.sagernet.org/configuration/outbound/)、[endpoint](https://sing-box.sagernet.org/configuration/endpoint/)、[migration](https://sing-box.sagernet.org/migration/)

Context7 的 `/sagernet/sing-box` 结果主要指向 `testing` 文档，且没有当前稳定 tag；它用于发现上游文档入口，版本和注册事实以固定 tag 源码、发布包和二进制为准。固定 tag 源码已下载到 `/tmp/sing-box-v1.14.0`（detached HEAD 上述提交）。

ARM64 VPS 可直接复用的官方包缓存为 `/tmp/sing-box-v1.14.0-cache/`：

```text
sing-box-1.14.0-linux-arm64.tar.gz
sha256 04d9b40bc98dc55b6f509ce3292145c65478f65866bea64826ebb2f382385088
sing-box-1.14.0-linux-arm64/sing-box
sing-box-1.14.0-linux-arm64/libcronet.so
schema.json
protocol-probe/                 # 本轮的 type 识别/check 探针输入
```

下载地址为 `https://github.com/SagerNet/sing-box/releases/download/v1.14.0/sing-box-1.14.0-linux-arm64.tar.gz`。该二进制执行 `sing-box version` 的结果是 `1.14.0`、`go1.26.7 linux/arm64`、`CGO: disabled`，tags 为 `with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_ccm,with_ocm,with_cloudflared,with_naive_outbound,with_usbip,with_openvpn,with_openconnect,badlinkname,tfogo_checklinkname0,with_purego`。发布包和 SHA-256 均已在本轮校验。

源码关键证据位置：

- `include/registry.go:51-113`：入站、出站、endpoint 的集中注册；`include/registry.go:169-183`：ShadowsocksR 与旧 WireGuard outbound 的移除 stub。
- `include/quic.go:1-37` 与 `include/quic_stub.go:1-78`：QUIC 协议族在 `with_quic` 下注册，否则保留显式失败 stub。
- `include/cloudflared.go`、`include/naive_outbound.go`、`include/openconnect.go`、`include/openvpn.go`、`include/tailscale.go`、`include/wireguard.go` 及对应 `_stub.go`：条件能力与失败原因。
- `release/DEFAULT_BUILD_TAGS`、`release/DEFAULT_BUILD_TAGS_OTHERS`、`release/DEFAULT_BUILD_TAGS_WINDOWS`：官方默认 tag 组合；`docs/installation/build-from-source.md:55-125`：tag、Naive 变体和 libc 依赖。
- `docs/configuration/{inbound,outbound,endpoint}/index.md`：官方导航清单；导航仍列出的 `wireguard` outbound 和 `dns` outbound 不能据此认定在 1.14 可用。
- `docs/deprecated.md:69-124,181-191`、`docs/migration.md:776-1240`：DNS、特殊 outbound、legacy inbound fields、direct override、WireGuard outbound 和 ShadowsocksR 的迁移/移除事实。

本轮还用上述 ARM64 官方二进制对所有下列 type 构造最小 JSON 做了 `sing-box check`：正常 type 进入自身必填字段或 TLS 初始化错误计为 `registry-check`；`wireguard` outbound、`dns` outbound、`shadowsocksr` 被二进制明确报告 removed；endpoint 的五个 type 被识别并进入 endpoint 初始化。该探针没有伪造凭据，也不代表真实 VPN、Cloudflare、OpenConnect 或 OpenVPN 控制面连接成功。第一阶段审查修复后的真实项目证据在 `dev/verification-runs/20260907031322/`：9 个场景、12 次协议 TCP 业务闭环成功，包含旧四协议共存、接管、升级和回滚。其余 UDP 业务及新增协议数据路径仍待扩展；Mixed 导出增量证据如下。

2026-09-07 Mixed 导出增量：Context7 先解析 `/sagernet/sing-box`，结果仅覆盖 testing；随后复核固定 [1.13.18 SOCKS outbound](https://github.com/SagerNet/sing-box/blob/v1.13.18/docs/configuration/outbound/socks.md)、[1.14.0 SOCKS outbound](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/socks.md)、[UoT v2](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/shared/udp-over-tcp.md) 及两个版本 Mixed 的 `uot.NewRouter` 实现。生成器保留 SOCKS5 认证，省略 `network` 以启用 TCP/UDP，显式设置 `udp_over_tcp: {enabled:true, version:2}`。`tests/export_client_config_mixed_runtime.sh` 在 1.13.18/1.14.0 同版本及双向跨版本共四组、每组认证/无认证两种状态取得：8 次完整客户端配置 check、16 次精简客户端/服务端 check、8 次 TCP marker、8 次 UDP echo payload 成功，以及 4 次直接访问服务器的错误认证拒绝。业务测试保留实际导出的 SOCKS5 outbound，仅替换完整导出的公网规则集/路由为隔离直达测试路径；不声称公网规则集下载、原生远程 UDP associate 的防火墙可达性或其他协议 UDP 已验证。所有业务监听均为回环地址，无宿主防火墙变更。
2026-09-08 TUIC 增量：Context7 `/sagernet/sing-box` 的官方 TUIC 文档与固定官方 `v1.14.0` ARM64 二进制共同核对入站/出站字段。真实 `sing-box 1.14.0 check` 明确拒绝入站 `udp_relay_mode`，因此服务端 typed renderer 只写 users、TLS/h3、拥塞控制、auth timeout、heartbeat 和 zero-rtt；`udp_relay_mode` 与 `udp_over_stream` 保留为客户端 outbound-only 字段。`tests/tuic_instance_lifecycle.sh` 覆盖 create/replace/delete/default/recover、CAS 冲突、凭据脱敏、服务端/客户端候选和可选目标核心 check；主机 mock 与实际 1.14.0 均通过。该证据仅为本地结构化生命周期、配置检查和回环材料，不代表公网 UDP 可达、TUIC UDP payload、生产部署或真实 SubMan 同步。

2026-09-09 Hysteria v1 增量：Context7 `/sagernet/sing-box` 官方文档与固定官方 `v1.14.0` ARM64 二进制核对 `hysteria` 入站/出站字段。与 `hysteria2` 分开建模：用户凭据为 `{name,auth_str}`，obfs 为密码字符串，服务端需要上下行带宽；typed renderer 只输出 Hysteria v1 的 TLS/h3、带宽、obfs 与 QUIC 参数，不混入 Hysteria2 的 `password`、Salamander 或 `masquerade`。`tests/hysteria_instance_lifecycle.sh` 覆盖 create/replace/delete、stale CAS、凭据脱敏、手工 TLS、带宽/obfs/QUIC、服务端候选、逐用户客户端 outbound、Agent links warning 和可选目标核心 check；主机 mock 与实际 1.14.0 均通过。该证据仅为本地结构化生命周期、目标配置检查和回环材料，不代表公网 UDP 可达、Hysteria UDP payload、生产部署或真实 SubMan 同步。

2026-09-09 NaiveProxy 增量：Context7 `/sagernet/sing-box` 官方文档与固定官方 `v1.14.0` ARM64 二进制核对 `naive` 入站/出站字段。typed store 将用户凭据、手工 TLS、TCP/UDP 网络选择、QUIC 开关/拥塞控制、并发、窗口和额外 HTTP headers 分开保存；服务端 renderer 对双网络省略 `network`，单网络输出核心要求的字符串值，UDP 网络强制保留 TLS。客户端按用户输出完整 Naive outbound JSON，`client_trust=certificate` 只嵌入公有证书；官方纯 Go outbound 需要 `with_naive_outbound` 与运行时 `libcronet.so`，导出和 Agent warning 明确披露但不声称库已部署。`tests/naive_instance_lifecycle.sh` 覆盖 create/replace/delete、stale CAS、窗口拒绝、凭据脱敏、TCP/UDP renderer、客户端 outbound、Agent warning 和可选目标核心 check；主机 mock 与实际 1.14.0 server/client check 均通过。该证据仅为本地结构化生命周期、目标配置检查和回环材料，不代表 Naive TCP/UDP 数据面、公网可达、libcronet 实际加载、生产部署或真实 SubMan 同步。

## 入站矩阵

`D/T/E/R` 分别为项目的部署、接管、编辑、删除；`—` 为项目尚未提供该生命周期。导出列表示客户端配置，分享列表示可无损表达的分享格式，SubMan 列表示当前项目同步链路；这些列不把“能生成 JSON”当成完成。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| direct-inbound | `direct` / inbound | 基础内建 | TCP 或 UDP，由 `network` 指定，留空为两者；仍支持 `override_address/override_port` 端口转发，不能与 direct outbound 的移除项混淆 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | — / — / — | project-real-tcp+udp；Docker `20260912073323` 的 direct TCP/UDP override loopback marker、目标核心 check、监听和渲染断言通过 |
| mixed | `mixed` / inbound | 基础内建 | TCP listen；同一入口提供 SOCKS4/4a/5 和 HTTP；UDP 业务经 SOCKS UDP/UoT，不开固定 UDP listen；schema 2 可管理多实例 | yes | yes（Linux） | 旧预设 + schema 2 实例链路；yes/yes/yes/yes（首次全新安装仍为 legacy schema 1，显式迁移后启用 schema 2） | SOCKS5 + UoT v2 裸核客户端（明文警告） / HTTP、SOCKS 链接 / no current SubMan | project-real-tcp；多实例生命周期、导出及本轮五协议最终门禁通过 |
| vless-reality（旧预设） | `vless` / inbound | 项目保留 1.13.x；REALITY、Vision 与 TCP 预设 | TCP listen，TCP/UDP 业务；已有多实例、固定 tag/UUID/ShortID、实例出站和 QoS | yes | yes（Linux；需握手目标） | 旧预设；yes/yes/yes/yes | 裸核客户端 / VLESS URI / VLESS 同步 | project-real-tcp |
| vless-plain（普通预设） | `vless` / inbound | 项目兼容 1.13.x；QUIC transport 另需 `with_quic` | 外层 TCP 或 QUIC/UDP；可选 TLS；按用户 `flow`；支持 none/http/ws/grpc/quic，HTTPUpgrade 与 WS early data fail closed | yes | yes（Linux） | 第十预设，schema 2 marker + schema 1 store，共享实例事务；yes/yes/yes/yes；多用户/TLS/transport/接管/恢复 | 逐用户完整 JSON / VLESS URI（可表达字段） / 逐实例逐用户同步（不可表达组合稳定跳过） | 两核心 1.13.18/1.14.0 check/export；专项 lifecycle/Agent/share/SubMan/probe 通过；最终本地 `20260908141403` 为 108/108，最终 Docker `20260908144031` 为 15/15 场景与 22/22 探针通过；本轮两核心 exporter 回归覆盖 none/http/ws/grpc/quic，QUIC outbound 保留 TCP+UDP；Docker `20260911215408` 的普通 VLESS 实例替换与 UDP marker 回环通过 |
| socks（独立预设） | `socks` / inbound | 基础内建 | TCP listen；SOCKS4/4a/5；UDP associate/UoT 业务经该 TCP 会话处理；认证可选；无 HTTP/TLS | yes | yes（Linux） | active schema 2 marker + JSON store（`schema_version: 1`）与共享实例事务；yes/yes/yes/yes（实现范围，不等同全协议目标完成） | SOCKS5 + UoT v2 裸核客户端（明文警告） / SOCKS 链接 / no current SubMan | project-real-tcp；六项回归、两核心 check/runtime、菜单、Docker 10/10 与 TCP 14/14 通过；公网原生 UDP 未验证 |
| http | `http` / inbound | 基础内建；项目兼容 1.13.x；TLS 需用户提供有效证书/私钥引用 | HTTP CONNECT 入口，TCP；入口 TLS 与代理 HTTPS 目标独立；新实例默认回环与认证 | yes | yes（Linux；手工 TLS 文件另行预检） | schema 2 + 共享实例事务；yes/yes/yes/yes；无 legacy migration | HTTP CONNECT TCP 客户端（TLS 嵌入公有证书信任） / 明文 HTTP URI；TLS 返回不可表达 warning / no current SubMan | 两核心 check/TCP/TLS 正反向路径、实际 Bash 4.2、75 项本地门禁；修正测试断言后 Docker 11/11、TCP 16/16；仅本地/容器，非公网或生产证明 |
| shadowsocks | `shadowsocks` / inbound | 基础内建；项目兼容 1.13.x | TCP/UDP 可分选；九种方法；none/2022 ChaCha 无多用户；项目未建模 relay/mux/plugin | yes | yes（Linux） | schema 2 marker + schema 1 JSON 与共享实例事务；yes/yes/yes/yes；无 legacy migration | 逐用户完整 JSON / SIP002（单网络 warning） / 双网络加密项逐用户同步，单网络/none 跳过，mock-only | 两核心、原生 Bash/实际 Bash 4.2：9 方法 check、每组 7 TCP + 7 UDP marker、错误认证拒绝；Docker `20260911194118` 共存场景经 SOCKS5 UDP ASSOCIATE 完成 SS2022 原生 UDP payload 回环；公网/生产未验证 |
| vmess | `vmess` / inbound | 基础内建；项目兼容 1.13.x；QUIC transport 另需 `with_quic` | 原生及 HTTP/WS/gRPC/HTTPUpgrade 外层 TCP，QUIC 外层 UDP + TLS；可承载 TCP/UDP 业务；`alterId>0` 是兼容模式；WS early data/HTTPUpgrade 受 runtime guard 限制 | yes | yes（Linux） | 第九预设，schema 2 marker + schema 1 store，共享实例事务；yes/yes/yes/yes；多用户/TLS/transport/接管/恢复 | 逐用户完整 JSON / `vmess://`（可表达字段） / TLS 系统信任且 URI 无损的逐用户同步，其他明确跳过 | 两核心 1.13.18/1.14.0 check/export（none/http/ws/grpc/quic），本地 takeover/lifecycle/Agent/share/SubMan/probe 测试通过；Docker `20260911194118` 新装、共存、升级成功/回滚及 24/24 常规协议探针通过，VMess QUIC 经 SOCKS5 UDP ASSOCIATE 完成 UDP payload 回环 |
| trojan | `trojan` / inbound | 基础内建；QUIC transport 另需 `with_quic`；项目兼容 1.13.x | 外层 TCP 或 TLS QUIC/UDP；TLS/transport/客户端信任分别建模；不接管 fallback/mux/未知字段；HTTPUpgrade、WS early data 被阻断 | yes | yes（Linux） | 第八预设，schema 2 marker + schema 1 store，共享实例事务；yes/yes/yes/yes；无 legacy migration | 逐用户完整 JSON / TLS 系统信任的无损 URI 子集 / 逐用户同步及跳过原因，本地 mock | 受管导出经实际 SubMan parser 十组往返、两核心 check；完整生命周期见实施记录，Docker `20260911194118` 共存场景经 SOCKS5 UDP ASSOCIATE 完成 Trojan QUIC/UDP payload 回环；仅容器/回环，不是公网或生产证据 |
| naive-inbound | `naive` / inbound | 入站本体内建；QUIC 路径需要 `with_quic` | TCP 或 UDP；用户和 TLS 必填；UDP 为 HTTP/3/QUIC 路径，不能只以 TCP check 代替 | conditional | yes（tag 已含；QUIC/TLS 仍需） | 第十四预设，active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；手工 TLS、多用户、TCP/UDP 选择 | 逐用户完整 Naive outbound JSON / 不生成标准 URI / unsupported，不执行 SubMan | 生命周期与目标 1.14.0 check 通过；Docker `20260912014158` 共存场景以官方 `libcronet.so` 完成 Naive TCP/HTTP2 marker，client/server check、index/store、监听断言均通过；严格渲染配置/hash artifact 与升级运行库回滚在 `20260912022837` 及本地回归中通过；UDP/HTTP3、公网和生产未验证 |
| hysteria | `hysteria` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；`auth_str` 用户、必填上下行带宽、字符串 obfs、QUIC 窗口/MTU/并发流；不要与 hysteria2 字段混用 | conditional | yes（tag 已含） | 第十三预设，active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；手工 TLS、多用户、接管/恢复 | 逐用户完整 Hysteria outbound JSON / 无标准 URI（`hysteria_standard_uri_unavailable`） / unsupported，不执行 SubMan | `tests/hysteria_instance_lifecycle.sh` mock 与目标 1.14.0 server/client check 通过；Docker `20260911194118` 以 SOCKS5 UDP ASSOCIATE marker 完成 Hysteria QUIC/UDP payload 回环；仅容器/回环，不是公网或生产证据 |
| shadowtls | `shadowtls` / inbound | 基础内建 | TCP 包装层；v1/v2/v3 的 password、users、handshake 和 strict/wildcard 约束不同；必须组合内层代理 | yes | yes（Linux） | 第十五预设，schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；outer + loopback Mixed composite、完整 client chain/export、Agent CAS | 每用户 ShadowTLS transport + HTTP detour outbound JSON / 无安全标准 URI（warning） / 不发送 SubMan | Docker `20260912001650` 共存与 runtime smoke 的 ShadowTLS `RESULT=success`，固定 1.14.0 核心 check、TLS cover、HTTP marker 全通过；仅容器/回环，不是公网或生产证明 |
| vless | `vless` / inbound | 基础内建；项目通过 `vless-reality` 与 `vless-plain` 两个预设映射；QUIC 另需 `with_quic` | 外层 TCP 或 QUIC/UDP；TLS/REALITY 和 transport 必须按目标版本组合；`xtls-rprx-vision` 是特定 flow，不是通用开关 | yes | yes（Linux） | generic upstream type；项目生命周期按 `vless-reality`/`vless-plain` 分列 | — / — / — | registry-check；具体管理链路见两个项目预设 |
| tuic | `tuic` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；UUID/password、拥塞控制、auth timeout、heartbeat、0-RTT；UDP relay mode/udp-over-stream 仅属于 outbound | yes | yes（官方包含 `with_quic`） | 第十二预设，active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；手工 TLS、多用户、接管/恢复 | 逐用户完整 TUIC outbound JSON / 无标准 URI（warning） / unsupported，不执行 SubMan | `tests/tuic_instance_lifecycle.sh` mock 与目标 1.14.0 server/client check 通过；Docker `20260911194118` 共存场景经 SOCKS5 UDP ASSOCIATE 完成 TUIC QUIC/UDP payload 回环；仅容器/回环，不是公网或生产证据 |
| hysteria2 | `hysteria2` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；password、salamander/gecko obfs、masquerade；realm/STUN/端口映射是额外控制面 | conditional | yes（tag 已含） | 旧 schema 1 + typed schema 2 手工 TLS 多实例/用户；yes/yes/yes/yes；旧 ACME/provider 接管保留 legacy，重复 legacy 入站仍阻断 | 逐用户完整 client JSON / Hysteria2 URI（证书 trust 或证书算法可能 warning） / system-trust 用户逐用户同步，证书 trust 跳过，带宽/masquerade 无法由 URI 表达并保留 warning | typed store/lifecycle/Agent/export/SubMan mock 专项通过；Docker `20260911194118` 共存场景以 SOCKS5 UDP ASSOCIATE marker 完成 Hysteria2 QUIC/UDP payload 回环；仅容器/回环，不是公网或生产证据 |
| anytls | `anytls` / inbound | 自 1.12.0；基础内建 | TCP listener + TLS；users/password 和 padding scheme；UDP 业务由 AnyTLS UoT adapter 承载，客户端 metadata 不能由普通 URI 无损表达 | yes | yes（Linux） | 旧 schema 1 + typed schema 2 manual-TLS 实例；yes/yes/yes/yes；ACME/provider takeover fail closed | AnyTLS client JSON / 无稳定无损 URI（warning） / no current SubMan | typed store/lifecycle/Agent/export/check；Docker `20260914165733` 共存以 SOCKS5 TCP marker 与 UoT UDP marker 回环通过；仍仅容器/回环，不是原生 UDP listener、公网或生产证明 |
| snell | `snell` / inbound | 自 1.14.0；基础注册但协议为新版本能力 | TCP listen；server 版本 `5` 或 `6`，UDP 业务由 Snell packet API 经 TCP 会话承载；v5 只 HTTP obfs 且不支持 QUIC proxy，v6 为 traffic shaping 并要求 12–255 字节 PSK | yes | yes（Linux） | active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；0–128 用户；无 legacy migration | 逐用户完整 Snell outbound JSON / 无标准 URI（warning） / unsupported（不执行 SubMan） | typed lifecycle/takeover/rebuild/Agent/export 专项通过；配置目标 1.14.0 时执行 check；定向 Docker `20260914185411` 共存场景先验证 v6，再以 revision CAS 替换同一实例验证 v5 HTTP-obfs；v6/v5 TCP 与 packet-API UDP marker、client check、index/store 均通过（`project-real-snell-tcp+packet-api-udp`）；仍未证明原生 UDP listener、公网、生产或 SubMan |
| tun | `tun` / inbound | 基础内建；Linux 需要系统权限与路由工具，平台行为不同 | TCP/UDP/ICMP 的透明接入；Linux `auto_route/auto_redirect`、nftables/iproute2、DNS 劫持和自捕获环路必须一起管理 | yes | yes（Linux；权限/路由仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | project-real-tun-resources；特权隔离 Docker `20260912200008` 在 `fresh_install_vless` 中创建 TUN component，回读 `sbv-tun`、priority 9000/table 2022 rule、table 2022 route 与 diagnose，删除后确认接口/rule/route 清理；不含透明包转发、宿主策略或公网证据 |
| redirect | `redirect` / inbound | Linux、macOS；Linux 通常需 root/iptables 或 nftables 方案 | TCP only；源码 listener 固定 `NetworkTCP`，通过原始目标重定向连接；必须防止管理 SSH 被捕获 | conditional | yes（Linux；root/重定向规则仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | project-real-redirect-tcp；特权隔离 Docker 以临时 owner-scoped `OUTPUT REDIRECT` 规则回读 TCP marker 并清理；不代表宿主策略所有权 |
| tproxy | `tproxy` / inbound | Linux；需 root、策略路由/防火墙能力 | TCP/UDP（空值表示两者）；Linux 专属，UDP NAT 参数和路由归属必须持久化 | conditional | yes（Linux；root/策略路由仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | project-real-tproxy-tcp+udp；特权隔离 Docker 的 disposable veth/network namespace 以临时 fwmark policy route 与 `PREROUTING TPROXY` 回读 TCP+UDP marker 并清理；不代表宿主策略所有权 |
| cloudflared | `cloudflared` / inbound | 自 1.14.0；`with_cloudflared`；需 Cloudflare Tunnel token 和外部控制面 | Cloudflare Tunnel 可承载 TCP、UDP、ICMP；`protocol` 为 QUIC/HTTP2，UDP datagram v2/v3；不能虚构普通节点 URI | conditional | yes（tag 已含；token/控制面仍需） | component state/config；yes/yes/yes/yes* | 不提供普通分享 / — / — | registry-check（无 token 按预期失败） |

`tun`、`redirect`、`tproxy` 与 `cloudflared` 行的 `component state/config` 覆盖本项目的统一状态、配置合并、引用保护、监听投影、Agent CAS、目标核心校验，以及固定监听变化所复用的受管 UFW/iptables/ip6tables 归属事务。TUN 现在另有受限的 core-owned 接口/rule/route 创建、诊断和删除清理证据；命名 `system:true` WireGuard/OpenConnect/OpenVPN 与命名 `system_interface:true` Tailscale endpoint 现在也进入只读接口/地址（如配置）/MTU 资源观察和事务 postcheck，OpenVPN 另有接口/隧道资源观察与删除清理证据；Redirect/TProxy 现在另有 verification-container-only 的临时策略与 TCP/TCP+UDP marker evidence（见 `project-real-redirect-tcp`、`project-real-tproxy-tcp+udp`），但透明包转发、宿主策略路由/nftables 所有权、Cloudflare/VPN/Tailscale 控制面、动态外部资源和公网真实业务仍未宣称通过。`*` 表示同上所述的组件生命周期切片，不是公网部署证明。

`vless-reality` 是本项目旧兼容预设，配置使用上游 `type: vless`，并非独立的上游 type；普通 VLESS 使用独立 `vless-plain` preset/state ID。项目继续把 `vless`、`vless+reality`、`vless-reality` 归一到旧 REALITY 状态，普通 VLESS 不复用该 alias，避免接管、重建或导出时将两种语义混淆。

## 出站及组合组件矩阵

出站的“TCP/UDP”表示该客户端出站可用的网络能力，实际仍受协议和 peer 服务端约束。`selector`、`urltest`、`bridge`、`block` 是路由组合或系统接入组件，不应被当成可分享代理节点。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| direct-outbound | `direct` / outbound | 基础内建 | TCP/UDP 直连；旧 `override_address/port` 在 1.13 已移除，改用 route options | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | — / — / — | `project-real-direct-tcp`；特权 Docker `multi_protocol_coexistence` 以 route options 覆盖到 loopback marker，目标核心 check 和 revision 17→19 CAS 删除通过；仅隔离容器/回环 TCP，不代表宿主策略、公网、生产或 UDP |
| bridge | `bridge` / outbound | 自 1.14.0；需要 Linux/macOS/Windows、rooted Android 或 jailbroken iOS 的权限/接口 | 只接收来自 TUN/Endpoint pre-match 的 L3 流量（TCP/UDP/ICMP），拒绝 L4 代理连接与本机目的地址；Linux 有 iproute2 table/rule | conditional | yes（Linux；接口/root 仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | project-real-bridge-resources；特权隔离 Docker 回读动态 TUN、priority 120/121 rule、table 2200/192.0.2.1 route、diagnose 与删除清理；仅 core-owned 资源观察，不含 L3 转发、公网或生产证据；1.13.18 明确拒绝未知 type |
| block | `block` / outbound | 基础内建 | 丢弃连接/数据；无网络协议 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | `project-real-block-reject`；特权 Docker `multi_protocol_coexistence` 以 custom block route 产生预期请求拒绝，目标核心 check 和 revision 19→21 CAS 删除通过；仅隔离容器/回环拒绝，不代表防火墙/宿主策略、公网、生产或 UDP |
| socks | `socks` / outbound | 基础内建 | SOCKS4/4a/5；TCP，UDP 依 server 支持，可 UDP-over-TCP | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（不进入普通分享节点） / 不生成服务端分享 URI / no current SubMan | `project-real-socks-tcp`；特权 Docker `multi_protocol_coexistence` 以一次性认证 SOCKS5 upstream，经 route 回读 loopback CONNECT marker、核心 check 和 CAS 删除；不代表外部 proxy、公网、生产或 UDP |
| http | `http` / outbound | 基础内建 | HTTP CONNECT，TCP；可配置认证、path、headers 与 outbound TLS | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（不进入普通分享节点） / 不生成服务端分享 URI / no current SubMan | 两核心 1.13.18/1.14.0 明文+TLS typed config check；Docker `20260912051138` 通过受认证 loopback HTTP proxy 的 CONNECT、header 与 marker 回读；仅容器/回环，非公网或生产证据 |
| shadowsocks | `shadowsocks` / outbound | 基础内建 | TCP/UDP；方法覆盖 SS2022 与传统方法，Base64 密钥长度按 method 校验；可 SIP003/multiplex/UoT | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（不进入普通分享节点） / 不生成服务端分享 URI / no current SubMan | `project-real-shadowsocks-tcp`；特权 Docker `multi_protocol_coexistence` 以 SS2022 PSK typed outbound 经既有 SS2022 inbound/upstream 回读 loopback marker，目标核心 check 与 revision 16→17 CAS 删除通过；仅隔离容器/回环 TCP，不代表外部 Shadowsocks、公网、生产、UDP、SubMan 或完整协议目标完成 |
| vmess | `vmess` / outbound | 基础内建 | TCP/UDP；TLS、transport、packet encoding 和 legacy alterId；QUIC 需 TLS/UDP，WS early data 与 HTTPUpgrade 阻断 | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（不进入普通分享节点） / 不生成服务端分享 URI / no current SubMan | 两核心 1.13.18/1.14.0 typed TLS+WS/plain check；Docker `20260911194118` 共存场景使用 VMess QUIC outbound 完成 UDP payload 回环；QUIC exporter 保留 TCP+UDP，非公网或生产证据 |
| trojan | `trojan` / outbound | 基础内建 | TCP/UDP（按 outbound network）；TLS、transport/multiplex 需对端支持；WS early data 与 HTTPUpgrade 阻断 | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（不进入普通分享节点） / 不生成服务端分享 URI / no current SubMan | 两核心 1.13.18/1.14.0 typed TLS+gRPC/plain check；Docker `20260911194118` 共存场景使用 Trojan QUIC outbound 完成 UDP payload 回环；仅隔离容器/回环，不是公网或生产证据 |
| wireguard-legacy | `wireguard` / outbound | 已移除；不能靠导航页恢复 | 不再创建；应使用 WireGuard endpoint，再由 route/dial 关系接入 | removed stub | no（removed） | none；—/—/—/— | 不可导出为旧 outbound / — / — | check 明确报告 removed |
| wireguard | `wireguard` / endpoint | 自 1.11 endpoint 架构；`with_wireguard`；官方 VPS 包含该 tag | UDP tunnel，peer、allowed IP、private key、MTU；system/gVisor 和平台权限影响数据路径；UDP NAT 与 Dial Fields 按 typed allowlist | conditional | yes（tag 已含；peer/权限仍需） | typed component state/config；yes/yes/yes/yes*；现代 endpoint，不恢复旧 outbound | 完整敏感 endpoint JSON（不属于普通分享节点；Warp 由项目专用材料管理） / no URI / no current SubMan | 1.14.0 全字段与 1.13.18 基础 endpoint typed config check；未验证系统接口、peer 握手或 UDP 数据面 |
| hysteria | `hysteria` / outbound | `with_quic` | QUIC/UDP + TLS；server 与互斥的 server_port/server_ports、hop_interval、`up`/`down` 网络带宽兼容字段、up_mbps/down_mbps、auth/auth_str、字符串 obfs 和 QUIC 参数，不与 hysteria2 互换 | conditional | yes（tag 已含） | typed component state/config；yes/yes/yes/yes* | 完整敏感 Hysteria outbound JSON（不生成标准 URI；no current SubMan） | 1.14.0 官方 ARM64 全字段与 1.13.18 兼容子集 typed config check；Docker `20260911194118` 生成的 Hysteria outbound 经受管 Hysteria 入站完成 UDP marker 回环；仅隔离容器/回环，不是外部端点或生产证据 |
| vless | `vless` / outbound | 基础内建 | TCP/UDP；TLS/REALITY、空 flow 或 `xtls-rprx-vision`、transport、xudp/packetaddr encoding 必须分别表示；Vision 仅 TLS 直连 | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（不进入普通分享节点） / 不生成服务端分享 URI / no current SubMan | `project-real-vless-tcp`；特权 Docker `multi_protocol_coexistence` 以明文 TCP VLESS outbound 连接一次性本地 VLESS upstream，经 upstream route 回读 loopback marker，目标核心 check 与 revision 21→23 CAS 删除通过；仅隔离容器/回环 TCP，不代表外部 VLESS、TLS/REALITY、UDP、公网、生产或 SubMan |
| shadowtls | `shadowtls` / outbound | 基础内建 | TCP-only ShadowTLS wrapper；server/port、v1/v2/v3、可选 password、必需 outbound TLS 与 shared Dial Fields；与本项目 inbound outer + loopback Mixed composite 分离 | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 ShadowTLS wrapper component JSON（不生成标准 URI；no current SubMan） | 1.14.0/1.13.18 官方 ARM64 typed config check；仅 wrapper 配置解析，未验证独立上游 ShadowTLS 握手或 TCP 数据面；入站 composite 的完整链路证据见上表 |
| tuic | `tuic` / outbound | `with_quic` | QUIC/UDP + TLS；server/port、UUID/password、`network`、native/quic UDP relay、可选 UDP-over-stream、0-RTT、heartbeat、拥塞控制与 QUIC fields | yes | yes（官方包含 `with_quic`） | typed component state/config；yes/yes/yes/yes* | 完整敏感 TUIC outbound JSON（不生成标准 URI；no current SubMan） | 1.14.0 官方 ARM64 全字段与 1.13.18 兼容子集 typed config check；Docker `20260911194118` 共存场景使用含 `h3` ALPN 的导出 outbound 完成 TUIC UDP payload 回环；仅隔离容器/回环，不是公网或生产证据 |
| hysteria2 | `hysteria2` / outbound | `with_quic`；1.14 新增 hop_interval_max、gecko obfs、BBR profile、Chrome QUIC 控制和 Realm | QUIC/UDP，亦可限制 TCP；server 与互斥的 server_port/server_ports、port hopping、up/down Mbps、salamander/gecko obfs、必需 TLS、QUIC fields、Realm/STUN/port mapping 与 shared Dial Fields | conditional | yes（tag 已含） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（按 trust/证书算法发 warning；不生成服务端分享 URI；no current SubMan） | 1.14.0 官方 ARM64 标准/Realm typed config check；1.13.18 标准子集通过、Realm 字段按预期不可用；Docker `20260911194118` 生成的 Hysteria2 outbound 经共存入站完成 UDP marker 回环；仅隔离容器/回环，不是外部端点或生产证据 |
| anytls | `anytls` / outbound | 自 1.12.0；基础内建 | TCP + UDP adapter（UoT）+ 必需 outbound TLS；password、idle session、client_metadata；无 configurable network/transport/multiplex；`tcp_fast_open=true` 不可用 | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 AnyTLS component JSON（不进入普通分享节点） / 不生成伪 URI / no current SubMan | 两核心 1.13.18/1.14.0 TLS/session/shared-Dial typed config check；定向 Docker `20260914165733` 共存场景 TCP + UoT UDP marker、client check 均通过；仅隔离容器/回环，不是公网或生产证明 |
| snell | `snell` / outbound | 自 1.14.0；基础注册 | TCP transport；outbound 版本 `4` 或 `6`；v4 HTTP obfs、v6 traffic shaping；UDP 业务由客户端通过 TCP 会话的 packet API 承载；v5 QUIC proxy 不作为独立 outbound | yes | yes（Linux） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON（v5/v6 入站映射分别导出 v4/v6；不生成标准 URI；no current SubMan） | 1.14.0 官方 ARM64 v4/v6 typed config check；1.13.18 明确未知 type；受管 exporter 明确输出 `network:["tcp","udp"]`，并在 `20260914185411` 经共存 Snell v6/v5 packet-API UDP marker 闭环（v5 入站映射 outbound v4）；仍未验证远端公网握手、原生 UDP listener 或生产数据面 |
| tor | `tor` / outbound | type 总是注册；嵌入 Tor 需 `with_embedded_tor` + CGO，默认官方包不含 embedded Tor | 通过外部 Tor executable 或嵌入实例；必须管理 executable path/data directory/torrc；不能把 Tor 当普通服务端节点 | conditional | yes（外部 executable；embedded 需额外 tag/CGO） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON / 不生成 Tor 分享 / no current SubMan | `project-real-tor-external-tcp`；特权 Docker `multi_protocol_coexistence` 使用镜像内 `/usr/bin/tor` 经 Tor circuit 访问 `check.torproject.org`，目标核心 check 与 revision 24→25 CAS 删除通过；仅隔离容器/外部 TCP，不代表 Tor 公网稳定性、匿名性保证、生产或 SubMan |
| ssh | `ssh` / outbound | 基础内建；目标 SSH 服务和密钥/host key 策略是外部条件 | TCP；密码或 private key、host key/cipher/kex 需校验；不创建新的 SSH server | conditional | yes（Linux；目标 SSH/凭据仍需） | typed component state/config；yes/yes/yes/yes* | 完整敏感 component JSON / 不生成 SSH 节点 URI / no current SubMan | `project-real-ssh-tcp`；特权 Docker `multi_protocol_coexistence` 以一次性 OpenSSH + pinned host key，经 SOCKS5 route 回读 SSH direct-tcpip loopback marker，并按 CAS 删除；不代表外部 SSH、公网、生产或 UDP |
| dns-legacy | `dns` / outbound | 1.13 已移除 | 不再作为 outbound；使用 DNS rule action、DNS server 和 domain resolver | removed | no（removed） | none；—/—/—/— | 不可用 / — / — | check 明确报告 removed |
| selector | `selector` / outbound group | 基础内建 | 只选择已注册 outbound tag；成员为空或引用不存在都应失败 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | `project-real-selector-tcp`；特权 Docker `multi_protocol_coexistence` 以单成员 `direct` group 经 route 回读 loopback marker、核心 check 和 CAS 删除；不代表多成员切换、公网或生产 |
| urltest | `urltest` / outbound group | 基础内建 | 对成员 URL 测试延迟并选择；需要可达探测 URL、成员 tag 和 timeout/interval 策略 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | `project-real-urltest-tcp`；特权 Docker `multi_protocol_coexistence` 以单成员 `direct`、loopback HTTP health URL 和 route 回读 marker、核心 check 和 CAS 删除；不代表多成员故障切换、公网或生产 |
| naive | `naive` / outbound | `with_naive_outbound`；Linux 官方纯 Go 变体仅 amd64/arm64，其他变体见下文 | HTTP/2 或可选 QUIC；TLS 仅支持 server_name/certificate/certificate_path/ECH；UDP 需 UDP-over-TCP；非零 insecure_concurrency 不可与 QUIC 并用；依赖 libcronet，不能由 check 证明运行库存在 | conditional | yes（tag+libcronet 已含） | typed component state/config；yes/yes/yes/yes* | 完整敏感 Naive outbound JSON（不生成标准 URI；no current SubMan） | 1.14.0 官方 ARM64 完整（bbr2）与 1.13.18 兼容子集 typed config check；共存 Docker `20260912014158` 通过实际 Naive TCP marker，安装器 staging/loader-cache、受管 hash 保护和核心升级运行库回滚通过；严格渲染配置/hash artifact 在 `20260912022837` 复跑；UDP/公网/生产未验证 |

## Endpoint 矩阵

Endpoint 同时具有接入和出站行为，不能塞进普通 `inbounds`/`outbounds` 菜单，也不能把客户端 endpoint 误称为不存在的服务端代理协议。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| wireguard-endpoint | `wireguard` / endpoint | `with_wireguard`；`system` 数据路径依赖平台权限，gVisor 路径依赖 `with_gvisor` | UDP、peer/allowed IP/private key/MTU；支持多个 peer；UDP NAT、workers 与 shared Dial Fields 受控；不是旧 outbound | conditional | yes（tag 已含；peer/权限仍需） | typed component state/config；yes/yes/yes/yes* | 敏感 endpoint JSON；不输出普通分享 / no current SubMan | registry-check + 1.14 全字段/1.13 基础子集 `check` |
| tailscale | `tailscale` / endpoint | `with_tailscale`；需要 auth key 或交互登录/控制面；可带 gVisor/system 接口 | WireGuard peer-to-peer UDP、控制面和可选 relay；可 advertise/accept routes、exit node、SSH；状态目录必须持久化 | conditional | yes（tag 已含；auth/控制面仍需） | typed component state/config；yes/yes/yes/yes* | 敏感 endpoint JSON / 不属于普通分享节点 / no current SubMan | state/render typed checks；registry/core check 不含 auth、relay、SSH 或数据面 |
| openconnect | `openconnect` / endpoint | 自 1.14.0；`with_openconnect`；`system:false` 还要求 `with_gvisor`；需要 Cisco/GlobalProtect/Fortinet/F5/Pulse/Juniper 服务器和交互认证 | VPN 数据面可 TCP/UDP；HTTPS control channel、cookie/token/username/password/cert、TLS/form/移动身份；无授权端点不能标 validated | conditional | yes（tag 已含；system:false 需 gVisor；认证仍需） | typed component state/config；yes/yes/yes/yes* | 敏感 endpoint JSON / 不属于普通分享节点 / no current SubMan | state/render typed checks；registry/core check 不含外部认证或数据面 |
| openvpn-client | `openvpn-client` / endpoint | 自 1.14.0；`with_openvpn`；`system:false` 还要求 `with_gvisor`；需要外部 OpenVPN server/profile/凭据 | TCP 或 UDP；TLS 或 static_key union；interactive auth、certificate/key、control-wrap、topology、DNS/route 需保留 | conditional | yes（tag 已含；system:false 需 gVisor；外部 profile 仍需） | typed component state/config；yes/yes/yes/yes* | 敏感 endpoint JSON / 不属于普通分享节点 / no current SubMan | `project-real-openvpn-tcp+udp`；Docker `20260914151532` 以两组成对的合成 server/client、`system:false`、用户名/密码和临时 SAN 证书分别完成 `tunnel established` 与 marker TCP/UDP 回读，目标核心 check、revision 删除和监听清理均通过；另有 `project-real-openvpn-system-resources`（Docker `20260914210913`）仅覆盖命名 `system:true` 接口/地址/MTU/隧道资源及删除，不包含宿主路由或 payload |
| openvpn-server | `openvpn-server` / endpoint | 自 1.14.0；`with_openvpn`；`system:false` 还要求 `with_gvisor`；证书/密钥和端口资源是部署条件 | TCP 或 UDP，每个 endpoint 只服务一种 network；TLS/static_key union、address pool/family、users/push 与 control-wrap 约束不同 | conditional | yes（tag 已含；system:false 需 gVisor；证书/密钥仍需） | typed component state/config；yes/yes/yes/yes* | 敏感 endpoint JSON / 不属于普通分享节点 / no current SubMan | `project-real-openvpn-tcp+udp`；同一隔离 Docker 场景分别验证 server 监听、peer connected、client tunnel、marker TCP/UDP payload 和删除后的端口/资源清理；另有 `project-real-openvpn-system-resources`（Docker `20260914210913`）验证命名 `system:true` server/client 的 core-owned 接口、地址/MTU、隧道日志、diagnose 与 CAS 删除清理；不证明外部证书部署、公网/生产、宿主路由或 SubMan |

Endpoint 表中仍保留 `none` 的历史行表示没有专用分享/节点适配；2026-09-09 增量新增的 `components.json` 状态/config/CAS 管理切片等价于组件生命周期 `yes/yes/yes/yes*`，但不等同外部 VPN/Tailscale/WireGuard 数据面已验证。`*` 表示配置组合、目标核心 check 和回滚边界已接入，外部认证、系统接口、路由/防火墙及公网业务仍需独立证据。

2026-09-11 WireGuard 增量：managed endpoint 按固定 1.14.0 `WireGuardEndpointOptions` 建立 typed allowlist，校验标准 Base64 32-byte key、CIDR address/allowed_ips、peer keepalive/reserved、MTU/listen/workers、UDP NAT 和 Dial Fields；live takeover 继续排除生成器自有 `warp-ep`，旧 wireguard outbound 仍由核心 removed stub 拒绝。固定 1.14.0 全字段与 1.13.18 基础字段 `check` 通过，未将其扩大为系统接口权限、peer 握手或 UDP 数据面证据。

2026-09-11 Endpoint typed 增量：Tailscale、OpenConnect 与 OpenVPN client/server 从仅 registry-check 提升为受控 typed component state/config 生命周期（`yes/yes/yes/yes*`）。校验覆盖各自 1.14 option allowlist、持久化/认证材料、TLS/static-key union、地址族、relay/push/route、control-wrap、移动身份与 form-entry 约束；inline PEM/key 允许换行，普通路径和字段仍拒绝控制字符。测试和核心检查是本地配置证据，外部控制面、证书文件、动态路由/防火墙和真实 TCP/UDP 数据面仍未验证；OpenVPN 命名 `system:true` 接口/隧道的隔离资源切片见下方 2026-09-14 记录。

2026-09-14 OpenVPN endpoint TCP+UDP 闭环：在 `fresh_install_vless` 特权隔离 Docker 场景中，使用固定官方 ARM64 `sing-box 1.14.0`、临时 SAN 证书和用户名/密码分别创建两组 `system:false` OpenVPN server/client pair；受管 direct inbound 经各自 client endpoint 访问一次性 marker，日志确认 peer/tunnel 建立，目标核心 `check` 通过，随后按 revision 删除每组 proxy/client/server 并确认监听和组件资源清理。对应 `dev/verification-runs/20260914151532` 的 `fresh_install_vless/openvpn-endpoint/result.env` 与 `openvpn-endpoint-udp/result.env` 均为 `RESULT=success`，验证标签为 `project-real-openvpn-tcp+udp`。`tests/managed_openvpn_endpoint_runtime.sh` 提供同等本机 TCP+UDP fixture，缺少 `SINGBOX_BINARY_114` 或依赖时明确 SKIP；该证据不扩张为外部 VPN 控制面、公网、生产或 SubMan 数据面。

2026-09-14 OpenVPN `system:true` 系统资源闭环：同一特权隔离 Docker 场景 `dev/verification-runs/20260914210913` 创建命名 `system:true` server/client（`sbv-ovpn-srv`、`sbv-ovpn-cli`），固定核心 `check` 通过，真实 `ip -j link/addr` artifact 回读两接口、`10.79.0.1/24` 与 `10.79.0.2/24`、MTU 1500，journal 回读 `peer connected`、`tunnel established` 和两个 `started at`，`component diagnose` 报告两个资源 `available/present`，随后按 revision 删除并确认接口消失、after-delete diagnose 无资源。结果文件明确 `PAYLOAD=not_attempted`；该标签 `project-real-openvpn-system-resources` 只覆盖 core-owned 接口/地址/MTU/隧道资源生命周期，不包含宿主路由、透明转发、packet payload、公网、外部控制面或生产/SubMan。

2026-09-14 统一系统 endpoint 资源观察：`managed_component_transparent_resources_json` 现在同时识别命名 `system:true` WireGuard/OpenConnect/OpenVPN 与命名 `system_interface:true` Tailscale，按类型读取接口名、配置地址/前缀和非零 MTU；未声明地址或 MTU 时使用 `not_required`，不猜测核心自动选择的值。接口名严格限制为 Linux IFNAMSIZ 可接受的安全字符，未命名或非法名称保持 `not_assessed`，命名资源缺失返回独立的 `*_system_runtime_resources_missing` 并参与活动组件事务 postcheck。`tests/managed_transparent_resources.sh` 以有界 fake iproute2 输出覆盖 WireGuard/OpenConnect/Tailscale 的 present、default/omitted MTU、地址和缺失接口组合。这是统一诊断/回滚边界的本地证据，不是外部控制面、系统路由/DNS、peer 握手或 UDP/TCP 数据面证明。

2026-09-14 实例级环境投影：`managed_component_inventory_json` 在保留 registry 类型级 `environment` 的同时，为每个持久化 component 返回 `instance_environment`。该投影根据 typed `config` 区分 system/internal endpoint：system-mode WireGuard/OpenConnect/OpenVPN/Tailscale 增加 root 和适用的 `/dev/net/tun` 依赖，internal-mode endpoint 增加 `with_gvisor` build tag；TUN、bridge、Redirect、TProxy 也暴露各自 host prerequisite。缺失依赖为 `unavailable`，目标核心未报告 build tags 时保持 `not_assessed`；不执行登录、接口、路由、DNS、防火墙或数据面操作。实例投影测试覆盖 WireGuard system/internal、bridge、TUN 和 component-list metadata，仍不构成外部认证、peer 握手、透明转发、公网、生产或 SubMan 证据。

## 构建变体和依赖门控

官方 `release/DEFAULT_BUILD_TAGS`（Linux 常见架构、Darwin、Android）包含：
`with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_tailscale,with_ccm,with_ocm,with_cloudflared,with_naive_outbound,with_usbip,with_openvpn,with_openconnect,badlinkname,tfogo_checklinkname0`。
Windows 另加 `with_purego`；`DEFAULT_BUILD_TAGS_OTHERS` 去掉 `with_naive_outbound`。`with_grpc` 和 `with_embedded_tor` 默认关闭。

Naive 是最容易被错误标记为“可用”的例子：

| 变体 | 官方范围 | 运行时/构建依赖 |
|---|---|---|
| Linux purego（包名无后缀） | amd64、arm64 | 官方包含同目录 `libcronet.so`；自建包必须自行取得 cronet 库并放入二进制目录或系统库路径 |
| Linux glibc（`-glibc`） | 386、amd64、arm、arm64、mipsle、mips64le、riscv64、loong64 | CGO + Chromium toolchain；运行时 glibc >= 2.31，loong64 >= 2.36 |
| Linux musl（`-musl`） | 386、amd64、arm、arm64、mipsle、riscv64、loong64 | CGO + Chromium toolchain；静态 musl |
| Windows purego | amd64、arm64 | `with_purego`，官方包含 `libcronet.dll` |
| Apple/Android | 以官方图形客户端构建为主 | CGO；Apple 需要 Xcode，Android 需要 NDK |

`with_quic` 同时控制 Hysteria/TUIC/Hysteria2、Naive HTTP/3、QUIC/HTTP3 DNS 和 V2Ray QUIC transport；缺 tag 的构建不是“协议未注册但可以碰运气”。`with_openconnect`/`with_openvpn` 的 stub 会明确区分 `system:true` 与需要 `with_gvisor` 的 `system:false`。`with_tailscale` 还带来 Tailscale DNS transport、证书 provider 与 DERP service；`with_cloudflared` 仅加入 Cloudflare Tunnel inbound。Tor outbound 本身总是注册，但嵌入 Tor 是单独的 `with_embedded_tor`/CGO 变体。

Release API 的 Linux tar 资产覆盖 amd64、arm64、386、armv5/6/7、mips/mipsle/mips64le、loong64、riscv64、ppc64le、s390x 等；其中 glibc/musl 变体只出现在相应架构。另有 Debian/RPM/Arch/OpenWrt 包、Windows 386/amd64/arm64、Darwin amd64/arm64、Android 和 Apple 客户端包。资产存在只证明发布了该平台文件，不能改变该平台的 tag、CGO、内核权限或 Naive 运行库条件。

## 历史、导航差异和范围边界

| 组件/字段 | 1.14.0 事实 | 处理结论 |
|---|---|---|
| ShadowsocksR inbound/outbound | `include/registry.go` 只注册返回错误的 stub；官方 deprecated 记录其在 1.6.0 已移除 | 不恢复；旧状态/配置必须阻断并提示迁移 |
| WireGuard outbound | 1.11 弃用、1.13 移除；旧导航页仍有页面，注册表 stub 返回明确错误 | 只实现/复用 endpoint；不把页面或 schema 常量当可用能力 |
| DNS outbound | 1.11 弃用、1.13 移除；`option.Outbound.UnmarshalJSONContext` 也明确拒绝 | 使用 DNS server、rule action、domain resolver；不恢复伪 outbound |
| Legacy inbound fields | 1.11 弃用、1.13 移除 | 不在新增协议中写 `sniff`、`domain_strategy` 等旧字段 |
| direct outbound `override_address/override_port` | 1.11 弃用、1.13 移除 | 改 route options；接管遇到旧字段要有无损/阻断策略 |
| Legacy DNS server formats | 1.12 弃用、1.14 移除 | 生成与校验均使用新 DNS server formats |
| `download_detour`、inline `tls.acme` 等 | 1.14 仍兼容但已弃用，官方记录计划在 1.16 移除 | 项目当前 1.13/1.14 兼容路径可 warning；不能以 warning 当成新协议实现 |
| DNS server、certificate provider、API、USB/IP、DERP、CCM/OCM | 是独立 service/transport 能力，不是“代理入站全协议” | 只作为组合依赖单列，不扩张成普通节点协议 |

## 项目差异和后续实现门槛

2026-09-12 透明资源诊断增量：`component diagnose --json` 现在包含只读的
`transparent_resources`。服务 active 时，managed TUN 会核对接口存在、
iproute2 rule/table 与 TUN route，并在启用 auto-redirect 时观测 nftables
规则集；缺失 core-owned 资源返回 `unavailable`。Redirect/TProxy 资源明确
返回 `host_policy_rules_not_managed`，因为宿主 PREROUTING、策略路由和既有
nftables 规则没有被本项目声明所有或自动删除。该入口和
`tests/managed_transparent_resources.sh` 只建立真实资源观测/隔离负例，不
等价于宿主规则事务或透明数据面完成，完整协议目标继续未完成。

2026-09-12 事务 postcheck 增量：活动服务执行组件重启后，若候选配置包含
TUN，事务会再次读取上述只读资源报告，并要求每个 TUN 的接口存在；启用
`auto_route` 时要求匹配的 iproute2 rule/table/route，启用 `auto_redirect`
时要求 nftables 规则集可观测。检查失败先补偿已应用的受管防火墙账本，再
恢复变更前 state/config/service，Agent 返回
`transparent_resource_check_failed`；防火墙补偿失败则保留快照并返回
`firewall_rollback_failed`。这只把 sing-box 自己创建的资源纳入可验证的
提交边界，Redirect/TProxy 宿主 PREROUTING、策略路由和其他 nftables 规则
仍未声明所有或自动管理。

审计起点 `cc12c06` 的协议校验、保存和导出分别维护四协议白名单；当前入站预设由 `SB_PROTOCOL_REGISTRY` 提供 ID、菜单、导出候选、Agent 和验证元数据。上游没有独立的 mixed outbound，客户端须选择 SOCKS 或 HTTP outbound。Mixed、独立 SOCKS 与 HTTP 提供共享的 schema 2 类型化实例状态和生命周期入口，但这只改变项目预设，不扩展上游协议类型。

Mixed schema 2 的完整管理链路包括：显式把 legacy schema 1 单实例迁移为 `protocols/instances/mixed.json`，并保留原有 ID/tag/监听地址/端口/认证；Agent 的 `create`、`replace`、`delete`、`default`、`migrate`、`recover` 使用 revision CAS 和 JSON envelope；交互菜单 17 提供逐实例创建/修改/删除/默认/迁移/恢复。首次全新安装仍沿用 legacy schema 1，不自动迁移。删除最后一个实例后保留空 JSON store（`schema_version: 1`）作为 revision tombstone；active marker 仍是 `CONFIG_SCHEMA_VERSION=2`，并移除 active Mixed 的 env/index/inbound，但下一次 `create` 必须以 tombstone revision 继续递增，不能清空 JSON 后把 CAS 重置为 0。非回环明文入口需要显式 `--allow-public`；活动 Mixed 与其他协议的批量删除会拒绝，要求逐个实例处理。上述是实现范围说明，运行门禁证据由实施记录补充，不能由源码存在替代。

写入口把文件、完整配置候选、监听资源、受管 UFW/iptables/ip6tables 规则和服务重启置于同一实例事务边界：初次创建先同目录 staging 后原子发布；共享 `flock` 防并发，`.instance-write.lock/transaction.json` 记录持久阶段，`.instance-transactions/` 保存 result；故障恢复使用原快照和受管防火墙回滚，并在无法恢复时保留 journal/恢复材料。firewalld 只做只读外部预检，不在事务中 add/delete/reload；缺少所需 allow 或既有归属账本时，必须在任何发布前失败并要求人工规则；缺少防火墙 journal 时恢复失败并转人工处理。`firewall-cmd` 的 reload 会影响运行时防火墙状态，相关命令语义以[官方手册](https://firewalld.org/documentation/man-pages/firewall-cmd.html)为准；UFW 规则的 comment 不作为身份，地址语法以[Ubuntu ufw(8) 手册](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)为准。本记录不据此宣称 UFW runtime 已验证。文件状态原语自身的备份与回滚不等于系统防火墙或其他进程端口的完整事务。

TCP/UDP 的源码核对结果是：Mixed 与 SOCKS 的 listener 都固定为 `NetworkTCP`，UDP 是 SOCKS UDP associate/UoT 业务；Redirect 的 listener 也固定为 `NetworkTCP`，只读取原始目标；TProxy 才按 `option.Network` 同时建立 TCP/UDP 并处理 UDP NAT。Snell inbound 的 listener 固定 TCP，版本分支明确调用 `snellv5`/`snellv6` 服务，UDP 通过服务的 packet API 复用 TCP 会话；Snell outbound 的 option schema 只允许 version `4,6`，inbound schema 只允许 `5,6`，代码分别构造 `snellv4`/`snellv6` client 与 `snellv5`/`snellv6` server，因此不能把整数版本直接视为两端相同版本号。证据为固定 tag 的 `protocol/{mixed,socks,redirect,snell}/*.go`、`option/{redir,snell}.go`。

Warp 是当前项目的 Cloudflare 专用注册与 WireGuard endpoint 路径，不等于已实现通用 WireGuard endpoint 管理。它应保持 `warp` 的旧状态、路由、凭据和回滚语义，并与未来通用 endpoint 分开。

版本交叉复核（2026-09-07）：[v1.13.18 注册代码](https://github.com/SagerNet/sing-box/blob/v1.13.18/include/registry.go) 不含 Bridge；实际 `1.13.18 check` 返回 `unknown outbound type: bridge`。[固定 tag 的 Bridge 文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/bridge.md) 明确标为自 1.14.0 且仅接收 L3 流量。另据 [direct options 源码](https://github.com/SagerNet/sing-box/blob/v1.14.0/option/direct.go)，移除目标覆盖的检查只在 outbound 解码中；同一受控 direct inbound 端口转发配置已分别通过真实 `1.13.18`、`1.14.0 check`。此项是配置兼容证据，尚未证明转发数据面。

对每个从 `none` 变成 `implemented` 的协议，至少需要：协议/预设/角色和实例 ID；状态读写迁移与未知配置保护；合法组合的 builder；依赖、端口、证书和路由归属；目标版本 `sing-box check`；部署/接管/编辑/删除事务；客户端配置和可表达性 warning；真实 TCP/UDP 或 endpoint 数据面探针；Agent、节点摘要、敏感输出和 SubMan 的明确 `unsupported/skipped/warning` 分支。组合协议必须连同内层代理或 endpoint 一起回滚，不能只保存一个孤立 JSON 片段。

Mixed 与独立 SOCKS 的实现边界仍然明确：服务端及导出的 SOCKS5/UoT 链路没有 TLS，独立 SOCKS 也没有 HTTP surface；两者均没有当前 SubMan 同步。独立 SOCKS 的共享实例管理、客户端导出、两核心 check/runtime 与最终 Docker/TCP 门禁均已通过，证据见[实施记录](../plans/2026-09-06-unified-protocol-management.md)。这些 SOCKS 结果不覆盖公网原生 UDP、TLS/HTTP/SubMan 或其他未实现协议；独立 HTTP 的入口 TLS 与 HTTP CONNECT 客户端证据另列于该记录。当前已接入预设及本节明确的组件实例管理范围仍是分阶段实现，全协议目标仍未完成，不能把 `sing-box check` 通过写成所有协议生命周期已完成。

本审阅没有访问生产 VPS、Cloudflare/Tailscale/OpenConnect/OpenVPN 账户，也没有执行真实外部控制面认证；因此这些条件性能力保持 `registry-check` 或未验证，不能在交付说明中写成已通过。后续实现应继续保留当前显式固定的 1.13.x 兼容路径，并在使用 1.14-only type（Snell、Cloudflared、Bridge、OpenConnect、OpenVPN）时以目标版本门控阻断，而不是只提高 `SB_SUPPORT_MAX_VERSION`。

### 2026-09-11：Hysteria v1 真实回环探针切片

Hysteria v1 的验证元数据由 `quic_loopback` 提升为实际 TCP/UDP payload 业务探针：客户端由受管 `build_client_hysteria_outbounds` 生成，补充上游必需的 `h3` ALPN，保留 `auth_str`、独立带宽、字符串 obfs 和公开证书，不复制私钥或第二用户凭据。`fresh_install_hysteria` 远程 Docker 场景覆盖安装、schema-2 marker/store、固定 1.14.0 服务端 UDP listener、`sing-box check`、客户端 SOCKS listener、HTTP marker 以及经 SOCKS5 UDP ASSOCIATE 返回的精确 UDP marker；`multi_protocol_coexistence` 对 Hysteria2 使用相同 helper。完整 run `dev/verification-runs/20260911154013` 的 16/16 场景与 23/23 协议探针均 success，两个 `udp.result.env` 均为 `RESULT=success`，对应 `udp-response.txt` 保留精确 marker。该证据仍限定在隔离 Docker 回环，不扩张为公网、生产、外部认证或全协议目标完成。

### 2026-09-11：TUIC 数据面与 ALPN 修复切片

`verification_generate_tuic_probe_client` 先校验 schema-2 marker 与 schema-1 typed store，再调用生产 `build_client_tuic_outbounds` 导出逐用户客户端；exporter 现在固定补齐与服务端 renderer 一致的 `tls.alpn:["h3"]`，避免 QUIC TLS `no application protocol`。`multi_protocol_coexistence` 新增 Trojan QUIC、TUIC 与 SS2022 实例、UDP listener、目标核心 `check`、SOCKS5 UDP ASSOCIATE marker 与本地 UDP echo 回读，并保留 Trojan TLS/密码、TUIC native relay/UUID/password/heartbeat/拥塞控制、SS2022 key 与公有证书（不含私钥）。完整 Docker run `dev/verification-runs/20260911175746` 的 16/16 场景与 23/23 常规协议探针均 success，Hysteria、Hysteria2、SS2022、Trojan、TUIC 五个 `udp.result.env` 均为 `RESULT=success`。该证据限定在固定 1.14.0 核心的隔离容器/回环，不代表公网可达、生产部署、外部认证、SubMan 或其他协议的数据面。

### 2026-09-11：VMess QUIC 数据面与 V2Ray network 修复切片

`multi_protocol_coexistence` 新增独立的 VMess QUIC typed instance，使用手工 SAN 证书、`security:"auto"`、UUID 用户和服务端 `h3` ALPN；固定 1.14.0 客户端通过 SOCKS5 UDP ASSOCIATE 将 marker 穿过 VMess QUIC 至本地 UDP echo，`udp.result.env` 与精确 `udp-response.txt` 均为成功。期间真实核心复现并修复 VMess exporter 将 QUIC outbound 错误限制为 `network:["udp"]` 的问题；V2Ray transport 的 QUIC socket 是 UDP，但 proxy outbound 仍需保留 TCP 与 UDP，故 VMess/VLESS plain exporter 统一输出 `network:["tcp","udp"]`，并为探针 VLESS QUIC 客户端补齐 `h3` ALPN。两版固定 ARM64 核心的 VMess/VLESS plain exporter runtime 覆盖 none/http/ws/grpc/quic，全部通过；未把 VLESS plain 远端 UDP payload 误记为已验证。

完整 Docker run `dev/verification-runs/20260911194118` 记录 16/16 场景、24/24 可执行常规协议探针和六个 `udp.result.env`（Hysteria、Hysteria2、SS2022、Trojan、TUIC、VMess）成功；一个既有 TUIC 常规 probe 仍按 registry 标记 `unsupported`，不计入可执行探针成功分母。证据仅属于固定 1.14.0 核心的隔离容器/回环，不代表公网可达、生产部署、外部认证、SubMan 或全协议目标完成。

### 2026-09-11：普通 VLESS QUIC 实例替换与 UDP 数据面切片

`fresh_install_vless_plain` 在固定 1.14.0 Docker 容器中先安装普通 VLESS TCP/none revision 1，再使用同一 `main` 实例通过 Agent CAS 替换为 TLS QUIC revision 2；候选配置渲染为 VLESS QUIC/UDP inbound、`tls.alpn:["h3"]`，协议索引仍为 `INSTALLED_PROTOCOLS=vless-plain`，不会把 core 的共享 `type:"vless"` 误归类为 VLESS + REALITY。受管 exporter 生成的 QUIC 客户端保留 `network:["tcp","udp"]`，只在探针副本中把服务端证书信任映射为公开证书/`insecure:true`，不携带私钥。固定核心 `check`、UDP listener、SOCKS5 UDP ASSOCIATE marker 与精确 `udp-response.txt` 均成功；本地 lifecycle/probe/smoke fixtures 也锁定 revision/index/transport/ALPN 回归。

最终 Docker run `dev/verification-runs/20260911215408` 共 15/15 场景，24 个常规 protocol result 中 23/23 可执行 probe 成功、1 个既有 TUIC 结果为 `unsupported`；7 个 UDP artifact（Hysteria、Hysteria2、SS2022、Trojan、TUIC、VMess、普通 VLESS）均为 `RESULT=success`。这是固定 1.14.0 核心与隔离容器回环 evidence，不证明公网可达、生产部署、外部认证、真实 SubMan 或全协议目标完成。

### 2026-09-11：Snell TCP 数据面切片

`verification_generate_snell_probe_client` 只从活动 schema-2 marker 和 schema-1 Snell store 读取受管 v6 实例，严格校验 tag、监听端口、PSK、用户 key、版本与 `mode`，再调用生产 `build_client_snell_outbounds` 输出单实例 TCP 客户端；`multi_protocol_coexistence` 的 typed create、live index/config/store 断言与固定 1.14.0 `sing-box check` 均通过。客户端经本地 SOCKS5 访问 HTTP marker 并精确回读，client artifact 保持 600 且不含服务端私钥。

`dev/verification-runs/20260911230518` 为 15/15 场景、25 个常规协议结果（24 个可执行成功，既有 TUIC 结果为 `unsupported`）；Snell 的 `result.env`、`client.check.txt`、HTTP marker 与 index/store 证据均成功。七个既有 Hysteria/Hysteria2/SS2022/Trojan/TUIC/VMess/普通 VLESS UDP artifact 继续为成功；本轮没有把 Snell packet API 记作独立原生 UDP marker。证据只覆盖固定 1.14.0、隔离 Docker 和回环数据面，不证明公网可达、生产部署、外部认证、SubMan 或完整协议目标。

### 2026-09-12：Direct inbound TCP override 数据面切片

`direct-inbound` 组件现在在通用监听校验之外约束上游 `network` 为 `tcp`/`udp`，并对可选 `override_address` 与 `override_port` 执行安全字符串、控制字符和 1–65535 端口边界检查；这些字段由 renderer 原样保留，仍与 direct outbound 已移除的 destination override 语义分开。`tests/managed_components_contract.sh` 覆盖合法 TCP render、非法 network、控制字符地址和端口溢出负例。

`multi_protocol_coexistence` 创建回环 `direct-inbound-verification` component（revision 2）和 `direct-udp-inbound-verification` component（revision 3），通过目标 1.14.0 `sing-box check` 与 TCP/UDP 监听快照后，分别用一次性 loopback HTTP marker 和 UDP echo marker 作为 override destination；原始 TCP/UDP 请求连接到受管 direct listener，响应必须精确等于 marker，结果写入 `direct-inbound.result.env` 与 `direct-inbound-udp.result.env`，同时保留渲染配置和 component envelope。Docker run `dev/verification-runs/20260912073323` 的 direct TCP/UDP artifact 成功。该结果是固定核心、隔离容器、回环 forwarding 证据，不代表 TUN/redirect/TProxy 透明路由、主机防火墙、公网/生产、外部控制面或全协议目标完成。

### 2026-09-14：Snell UDP packet API 数据面切片

在既有 Snell v6 TCP marker 证据上，`multi_protocol_coexistence` 新增共享 `verification_execute_protocol_udp_probe snell` 调用。生产 `build_client_snell_outbounds` 现在为 v4/v6 exporter 输出 `network:["tcp","udp"]`；探针先执行 client `sing-box check`，再从 SOCKS5 UDP ASSOCIATE 发出带协议标识的 marker，经 Snell v6 的认证 TCP 会话 packet API 到一次性 loopback UDP echo，保存精确响应、`udp.result.env`、client check、stderr 和 journal。

定向 Docker run `dev/verification-runs/20260914153908` 的 `multi_protocol_coexistence` 与 `runtime_smoke` 均成功；共存场景 Snell 的 TCP `result.env` 与 `udp.result.env` 均为 `RESULT=success`，旧协议探针和组件事务也保持通过。该 artifact 只证明固定 1.14.0、隔离容器/回环的 Snell TCP + packet API UDP 闭环，不把它写成原生 UDP listener、外部认证、公网/生产、SubMan 或全协议目标完成。

### 2026-09-14：AnyTLS UoT UDP 数据面切片

在既有 AnyTLS TCP marker 上，`multi_protocol_coexistence` 新增共享
`verification_execute_protocol_udp_probe anytls`。探针继续从受管 AnyTLS
marker/state 生成 outbound，先执行 client `sing-box check`，并断言客户端
JSON 不含可配置的 `network`、`transport` 或 `multiplex` 字段；随后由 SOCKS5
UDP ASSOCIATE 发出带协议标识的 marker，经 AnyTLS 的 UoT adapter 到一次性
loopback UDP echo，保存精确响应、`udp.result.env`、client check 和 stderr。

定向 Docker run `dev/verification-runs/20260914165733` 的共存场景与 runtime smoke
均成功；AnyTLS 的 TCP `result.env`、UoT `udp.result.env`、client check、精确
marker 及 `inbound UoT connection` journal 行均通过。该闭环证明固定 1.14.0、
隔离 Docker/回环中的 AnyTLS TCP listener + UoT UDP
adapter，不是原生 UDP listener、公网可达性、生产部署、外部认证、SubMan 或
完整协议目标完成证明。

### 2026-09-14：Snell v5 HTTP obfs 与 packet API 数据面切片

`multi_protocol_coexistence` 在保留 v6 成功 probe artifact 后，通过
`agent instance replace snell --expected-revision 1` 将同一 typed instance 替换为
v5 HTTP-obfs 记录。`snell-v5-replace.json` 报告 revision `2`、事务
`status:"success"`/`phase:"committed"`；固定 1.14.0 `check` 与渲染配置确认
服务端只输出核心接受的 `obfs_mode`，而 schema-1 typed store 继续保存客户端
所需的 `obfs_host`。

生产 exporter 将 v5 inbound 映射成 outbound version `4`，保留
`obfs_mode:"http"`、`obfs_host` 和 `network:["tcp","udp"]`。在定向 Docker
run `dev/verification-runs/20260914185411` 中，v6 与 v5 的 TCP marker、
packet-API UDP marker、client `check`、精确响应和 Snell journal 均成功，v6
artifact 保存于 `protocol-probes/snell-v6/`，v5 保存于 `protocol-probes/snell/`。
该结果仅证明固定核心、隔离 Docker/回环的受管 adapter，不把 packet API 写成
原生 UDP listener，也不代表公网、生产、外部认证、SubMan 或完整协议目标完成。

### 2026-09-15：Redirect/TProxy 透明数据面证据

`multi_protocol_coexistence` 在特权隔离 Docker 中创建 redirect inbound
（revision 4）和 TProxy inbound（revision 5），目标 ARM64 `sing-box 1.14.0`
`check` 均通过。redirect probe 仅在验证容器内加入按 uid 65534 限定的临时
`OUTPUT REDIRECT` 规则，用一次性 loopback HTTP marker 验证 TCP，并保存
`transparent/redirect/response.txt`、`iptables.with-redirect.txt` 与
`iptables.after-cleanup.txt`；规则不进入项目防火墙账本。

TProxy probe 创建 disposable veth/network namespace，加入 fwmark policy route
及 mangle `PREROUTING` 的 TCP/UDP `TPROXY` 规则，分别回读精确 TCP/UDP marker，
保存 `transparent/tproxy/tcp-response.txt`、`udp-response.txt`、资源/规则
before/with/after-cleanup artifact。两项 `result.env` 都明确
`POLICY_SCOPE=verification_container_only`、`POLICY_OWNERSHIP=not_managed`；
`component diagnose` 回读两实例需 root 但不需 TUN，随后通过 revision 6/7 删除
并断言配置、接口、策略和规则清理。证据路径为
`dev/verification-runs/20260915013127`；这不代表宿主透明策略所有权、公网/生产、
外部认证、SubMan 或完整协议目标完成。

### 2026-09-15：URLTest 单成员健康探测数据面证据

`multi_protocol_coexistence` 在同一特权隔离 Docker 中创建 `urltest` outbound
（revision 14），只允许内建 `direct` 成员，并将其 health URL 指向场景已有的
loopback HTTP marker。组件 route 将 `localhost` 请求送入 URLTest；目标
`sing-box 1.14.0 check`、`interval:"1s"`/`idle_timeout:"5s"` 配置、精确 marker
响应和 bounded retry 均通过，`urltest-outbound.result.env` 标记为
`RESULT=success`、`DATA_PLANE=urltest_direct_loopback`、
`HEALTHCHECK=loopback_http`。组件随后按 revision 14→15 删除，并断言配置与 route
引用均消失；artifact 见 `dev/verification-runs/20260915062630`。

该切片只证明单成员 URLTest 健康探测和路由选择的隔离容器回环路径；没有覆盖多成员
延迟排序/故障切换、外部 health URL、公网、生产、UDP、SubMan 或完整协议目标。

### 2026-09-15：Shadowsocks outbound TCP 数据面证据

`multi_protocol_coexistence` 在特权隔离 Docker 中创建 `shadowsocks` outbound
（revision 16），使用固定 `2022-blake3-aes-128-gcm`、16-byte Base64 PSK 和
`network:["tcp"]`，并将 synthetic domain 的 `socks-in` route 指向该组件。为避免
递归，`ss-in` route 将同一 domain 覆盖到场景已有的 direct loopback HTTP marker；
目标 `sing-box 1.14.0 check`、渲染 outbound/两条 route、认证 SS2022 连接和精确
marker 均通过。artifact 见 `dev/verification-runs/20260915065946`，其中
`shadowsocks-outbound.result.env` 为 `RESULT=success`、
`DATA_PLANE=shadowsocks2022_connect_loopback`、`AUTHENTICATION=ss2022_psk`，并保存
revision 16 create/revision 17 delete envelope。

该切片只证明一次性 SS2022 inbound/upstream 与 managed outbound 的隔离容器回环
TCP 路径；删除后组件与其两条 route 引用均断言清除。没有覆盖 UDP、外部
Shadowsocks 服务、公网、生产、SubMan 或完整协议目标完成。

### 2026-09-15：Direct 与 block outbound 数据面证据

`multi_protocol_coexistence` 在特权隔离 Docker 中分别创建空 config 的 `direct`
和 `block` custom outbound components。`direct-outbound-verification` 由既有认证
SOCKS5 inbound 进入 synthetic domain route，使用 sing-box 1.14 route options 的
`override_address:"127.0.0.1"` 与 marker port 回读精确 direct loopback marker；
`block-outbound-verification` 使用同类 route，curl 必须返回非零状态且不得返回该
marker。两项均通过目标 `sing-box 1.14.0 check`、渲染 outbound/route 和 CAS 清理：
direct 为 revision 17 create、18 delete（最终 revision 19），block 为 revision 19
create、20 delete（最终 revision 21）。结果文件分别标记
`DATA_PLANE=direct_route_override_loopback` 和 `DATA_PLANE=block_reject_loopback`。

该切片只证明隔离容器内的 direct route-option forwarding 与 block 预期拒绝；组件
和 route 删除后均断言清除，没有修改安装器防火墙账本，不覆盖宿主策略、公网、生产、
UDP、SubMan 或完整协议目标。

### 2026-09-15：VLESS outbound TCP 数据面证据

`multi_protocol_coexistence` 在特权隔离 Docker 中启动一次性明文 VLESS upstream，
其自身 route 再以 destination override 指向既有 HTTP loopback marker。随后创建
`vless-outbound-verification` typed component（`flow:""`、`network:["tcp"]`），
经已有认证 SOCKS5 inbound 访问 synthetic domain，真实穿过 VLESS client/server
握手并回读精确 marker；组件配置与 upstream 均通过目标 `sing-box 1.14.0 check`。
组件以 expected revision 21 创建并提交 22，再以 22 删除并提交 23，结果标记为
`DATA_PLANE=vless_tcp_loopback`、`UPSTREAM=vless_loopback_server`，删除后断言
组件和 route 均已清除。完整 Docker 运行目录为
`dev/verification-runs/20260915081600`。

该切片只证明隔离容器内的明文 VLESS TCP outbound 闭环；不覆盖外部 VLESS、TLS/
REALITY、UDP、公网、生产、外部认证、SubMan 或完整协议目标。
