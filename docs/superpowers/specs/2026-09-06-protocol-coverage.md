# sing-box 1.14.0 协议能力核对矩阵

审阅日期：2026-09-06

目标稳定版：`v1.14.0`

源码提交：`0b8995879f29a9b98ee027bc17b75e101445b238`

审计起点脚本：`SCRIPT_VERSION=2026090402`；当前交付工作区已提升为 `SCRIPT_VERSION=2026090601`，`SB_SUPPORT_MAX_VERSION=1.14.0`

本文是上游能力核对，不能把上游已注册等同于 sing-box-vps 已实现。矩阵的四种状态分别表示：

- `upstream`：目标版本源码中是否有该角色和 type 的注册实现；`conditional` 表示构建 tag、平台、CGO 或外部控制面有条件。
- `implemented`：本项目是否已经提供状态、配置组合、生命周期、导出/分享等管理链路；`none` 不表示上游不可用。
- `available`：当前官方 ARM64 Linux 发布包中是否已包含该角色的注册实现，以及仍需满足的构建、平台、运行库或外部控制面条件；它独立于源码中存在注册函数。
- `validated`：本轮实际取得的证据。`registry-check` 只证明目标二进制能识别该 type 并进入初始化校验；`project-real-tcp` 表示回读了项目真实 TCP 业务闭环 artifact，不能由 `check`、监听端口或进程存活代替，也不证明 UDP 业务已测。

表中“版本”优先表示本项目实现时的核心版本门槛：除标明“自 1.14.0”的能力外，继续以项目已有的 1.13.x 兼容路径为下限；它不声称是该协议在 sing-box 历史上的首次引入版本。需要 1.14.0 的 type 或字段必须在目标版本门控后才可生成。

## 版本与证据

GitHub Releases API 在本轮返回的最近发布为 `v1.15.0-alpha.2`（`prerelease=true`，2026-09-05），因此排除预发布；最近的稳定发布为 `v1.14.0`（`prerelease=false`，2026-08-31）。官方地址：

2026-09-07 再次读取 `releases/latest`，稳定版仍为 `v1.14.0`，`draft=false`、`prerelease=false`，未改变本轮固定目标。

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

本轮还用上述 ARM64 官方二进制对所有下列 type 构造最小 JSON 做了 `sing-box check`：正常 type 进入自身必填字段或 TLS 初始化错误计为 `registry-check`；`wireguard` outbound、`dns` outbound、`shadowsocksr` 被二进制明确报告 removed；endpoint 的五个 type 被识别并进入 endpoint 初始化。该探针没有伪造凭据，也不代表真实 VPN、Cloudflare、OpenConnect 或 OpenVPN 控制面连接成功。第一阶段审查修复后的真实项目证据在 `dev/verification-runs/20260907031322/`：9 个场景、12 次协议 TCP 业务闭环成功，包含旧四协议共存、接管、升级和回滚。UDP 业务及新增协议数据路径仍待扩展。

## 入站矩阵

`D/T/E/R` 分别为项目的部署、接管、编辑、删除；`—` 为项目尚未提供该生命周期。导出列表示客户端配置，分享列表示可无损表达的分享格式，SubMan 列表示当前项目同步链路；这些列不把“能生成 JSON”当成完成。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| direct-inbound | `direct` / inbound | 基础内建 | TCP 或 UDP，由 `network` 指定，留空为两者；仍支持 `override_address/override_port` 端口转发，不能与 direct outbound 的移除项混淆 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check；两核心 override 配置 check 通过 |
| mixed | `mixed` / inbound | 基础内建 | TCP listen；同一入口提供 SOCKS4/4a/5 和 HTTP；UDP 业务经 SOCKS UDP/UoT，不开 UDP listen | yes | yes（Linux） | 旧预设；yes/yes/yes/yes | 无独立裸核客户端 / HTTP、SOCKS 链接 / no current SubMan | project-real-tcp |
| vless-reality（旧预设） | `vless` / inbound | 项目保留 1.13.x；REALITY、Vision 与 TCP 预设 | TCP listen，TCP/UDP 业务；已有多实例、固定 tag/UUID/ShortID、实例出站和 QoS | yes | yes（Linux；需握手目标） | 旧预设；yes/yes/yes/yes | 裸核客户端 / VLESS URI / VLESS 同步 | project-real-tcp |
| socks | `socks` / inbound | 基础内建 | TCP listen；SOCKS4/4a/5 的 UDP associate/UDP 业务经该 TCP 会话处理；认证可选 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| http | `http` / inbound | 基础内建 | HTTP CONNECT 入口，TCP；入口 TLS 与代理 HTTPS 目标是两件事 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| shadowsocks | `shadowsocks` / inbound | 基础内建 | TCP/UDP；方法、密码、可选多用户/多路复用；2022 方法有密钥格式要求 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 method 的最小配置按预期失败） |
| vmess | `vmess` / inbound | 基础内建 | TCP 监听；TLS 和 V2Ray transport（HTTP/WS/gRPC/HTTPUpgrade 等）需合法组合；`alterId>0` 是兼容模式 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| trojan | `trojan` / inbound | 基础内建 | TCP + TLS；用户、可选 fallback/fallback-for-ALPN、transport；fallback 不是安全性证明 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| naive-inbound | `naive` / inbound | 入站本体内建；QUIC 路径需要 `with_quic` | TCP 或 UDP；用户和 TLS 必填；UDP 为 HTTP/3/QUIC 路径，不能只以 TCP check 代替 | conditional | yes（tag 已含；QUIC/TLS 仍需） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| hysteria | `hysteria` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP；TLS、认证、QUIC 窗口/拥塞和可选 obfs；不要与 hysteria2 字段混用 | conditional | yes（tag 已含） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| shadowtls | `shadowtls` / inbound | 基础内建 | TCP 包装层；v1/v2/v3 的 password、users、handshake 和 strict/wildcard 约束不同；必须组合内层代理 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 handshake 按预期失败） |
| vless | `vless` / inbound | 基础内建；普通 VLESS 与旧项目 `vless-reality` 是不同产品预设 | TCP；TLS/REALITY 和 transport 必须按目标版本组合；`xtls-rprx-vision` 是特定 flow，不是通用开关 | yes | yes（Linux） | none（旧 `vless-reality` 另计）；—/—/—/— | — / — / — | registry-check |
| tuic | `tuic` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；UUID/password、UDP relay mode、拥塞控制、0-RTT 等需分别管理 | conditional | yes（tag 已含） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| hysteria2 | `hysteria2` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；password、salamander/gecko obfs、masquerade；realm/STUN/端口映射是额外控制面 | conditional | yes（tag 已含） | 旧预设（项目 ID `hy2`）；yes/yes/yes/yes | 裸核客户端 / Hysteria2 URI（受证书算法 warning 约束） / 部分同步 | project-real-tcp（QUIC 传输） |
| anytls | `anytls` / inbound | 自 1.12.0；基础内建 | TCP + TLS；users/password 和 padding scheme；客户端 metadata 不能由普通 URI 无损表达 | yes | yes（Linux） | 旧预设；yes/yes/yes/yes | AnyTLS client JSON / 无稳定无损 URI / no current SubMan | project-real-tcp |
| snell | `snell` / inbound | 自 1.14.0；基础注册但协议为新版本能力 | TCP listen；server 版本 `5` 或 `6`，UDP 业务由 Snell packet API 经 TCP 会话承载；v5 只 HTTP obfs 且不支持 QUIC proxy，v6 为 traffic shaping 并要求 12–255 字节 PSK | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 version 按预期失败） |
| tun | `tun` / inbound | 基础内建；Linux 需要系统权限与路由工具，平台行为不同 | TCP/UDP/ICMP 的透明接入；Linux `auto_route/auto_redirect`、nftables/iproute2、DNS 劫持和自捕获环路必须一起管理 | yes | yes（Linux；权限/路由仍需） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check |
| redirect | `redirect` / inbound | Linux、macOS；Linux 通常需 root/iptables 或 nftables 方案 | TCP only；源码 listener 固定 `NetworkTCP`，通过原始目标重定向连接；必须防止管理 SSH 被捕获 | conditional | yes（Linux；root/重定向规则仍需） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check |
| tproxy | `tproxy` / inbound | Linux；需 root、策略路由/防火墙能力 | TCP/UDP（空值表示两者）；Linux 专属，UDP NAT 参数和路由归属必须持久化 | conditional | yes（Linux；root/策略路由仍需） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check |
| cloudflared | `cloudflared` / inbound | 自 1.14.0；`with_cloudflared`；需 Cloudflare Tunnel token 和外部控制面 | Cloudflare Tunnel 可承载 TCP、UDP、ICMP；`protocol` 为 QUIC/HTTP2，UDP datagram v2/v3；不能虚构普通节点 URI | conditional | yes（tag 已含；token/控制面仍需） | none；—/—/—/— | 不提供普通分享 / — / — | registry-check（无 token 按预期失败） |

`vless-reality` 是本项目旧兼容预设，配置使用上游 `type: vless`，并非独立的上游 type。项目当前仍把 `vless`、`vless+reality`、`vless-reality` 归一到同一旧状态 ID（`install.sh` 的 `normalize_protocol_id` 和注册表）；新增普通 VLESS 前必须引入有版本的 preset/状态语义，不能直接改变旧别名。

## 出站及组合组件矩阵

出站的“TCP/UDP”表示该客户端出站可用的网络能力，实际仍受协议和 peer 服务端约束。`selector`、`urltest`、`bridge`、`block` 是路由组合或系统接入组件，不应被当成可分享代理节点。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| direct-outbound | `direct` / outbound | 基础内建 | TCP/UDP 直连；旧 `override_address/port` 在 1.13 已移除，改用 route options | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| bridge | `bridge` / outbound | 自 1.14.0；需要 Linux/macOS/Windows、rooted Android 或 jailbroken iOS 的权限/接口 | 只接收来自 TUN/Endpoint pre-match 的 L3 流量（TCP/UDP/ICMP），拒绝 L4 代理连接与本机目的地址；Linux 有 iproute2 table/rule | conditional | yes（Linux；接口/root 仍需） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check；1.13.18 明确拒绝未知 type |
| block | `block` / outbound | 基础内建 | 丢弃连接/数据；无网络协议 | yes | yes（Linux） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check |
| socks | `socks` / outbound | 基础内建 | SOCKS4/4a/5；TCP，UDP 依 server 支持，可 UDP-over-TCP | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| http | `http` / outbound | 基础内建 | HTTP CONNECT，TCP；可单独配置 outbound TLS、headers、path | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| shadowsocks | `shadowsocks` / outbound | 基础内建 | TCP/UDP；方法覆盖 SS2022 与传统方法，密码/密钥长度须按 method 校验；可 multiplex/UoT | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 method 按预期失败） |
| vmess | `vmess` / outbound | 基础内建 | TCP/UDP；TLS、transport、packet encoding 和 legacy alterId 组合有限 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| trojan | `trojan` / outbound | 基础内建 | TCP/UDP（按 outbound network）+ TLS；transport/multiplex 需对端支持 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| wireguard-legacy | `wireguard` / outbound | 已移除；不能靠导航页恢复 | 不再创建；应使用 WireGuard endpoint，再由 route/dial 关系接入 | removed stub | no（removed） | none；—/—/—/— | 不可导出为旧 outbound / — / — | check 明确报告 removed |
| wireguard | `wireguard` / endpoint | 自 1.11 endpoint 架构；`with_wireguard`；官方 VPS 包含该 tag | UDP tunnel，peer、allowed IP、private key、MTU；`system`/gVisor 和平台权限影响数据路径 | conditional | yes（tag 已含；peer/权限仍需） | Warp 特例；通用 none | 不属于普通分享节点；Warp 由项目专用材料管理 / no current SubMan | endpoint registry-check |
| hysteria | `hysteria` / outbound | `with_quic` | QUIC/UDP + TLS；带宽、obfs、认证和 QUIC 参数，不与 hysteria2 互换 | conditional | yes（tag 已含） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| vless | `vless` / outbound | 基础内建 | TCP/UDP；TLS/REALITY、flow、transport、xudp packet encoding 必须分别表示 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| shadowtls | `shadowtls` / outbound | 基础内建 | TCP 包装层；必须指向实际内层服务端，v1/v2/v3 字段不能混用 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| tuic | `tuic` / outbound | `with_quic` | QUIC/UDP + TLS；native/quic UDP relay、可选 UDP-over-stream、0-RTT 等均是语义参数 | conditional | yes（tag 已含） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| hysteria2 | `hysteria2` / outbound | `with_quic` | QUIC/UDP + TLS；obfs、realm/STUN、Chrome QUIC fingerprint 和证书算法约束 | conditional | yes（tag 已含） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| anytls | `anytls` / outbound | 自 1.12.0；基础内建 | TCP + TLS；password、idle session、client_metadata；需与 AnyTLS server 配套 | yes | yes（Linux） | none；—/—/—/— | AnyTLS client JSON 可作为项目产物 / 不生成伪 URI / no current SubMan | registry-check（无 TLS 按预期失败） |
| snell | `snell` / outbound | 自 1.14.0；基础注册 | TCP transport；版本 `4` 或 `6`，UDP 业务由客户端通过 TCP 会话的 packet API 承载；v5 QUIC proxy 明确不支持；v4 obfs 与 v6 shaping 不同 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 version 按预期失败） |
| tor | `tor` / outbound | type 总是注册；嵌入 Tor 需 `with_embedded_tor` + CGO，默认官方包不含 embedded Tor | 通过外部 Tor executable 或嵌入实例；必须管理 executable path/data directory/torrc；不能把 Tor 当普通服务端节点 | conditional | yes（外部 executable；embedded 需额外 tag/CGO） | none；—/—/—/— | — / 不生成 Tor 分享 / — | registry-check（外部路径为空时仅证明注册） |
| ssh | `ssh` / outbound | 基础内建；目标 SSH 服务和密钥/host key 策略是外部条件 | TCP；密码或 private key、host key/cipher/kex 需校验；不创建新的 SSH server | conditional | yes（Linux；目标 SSH/凭据仍需） | none；—/—/—/— | — / 不生成 SSH 节点 URI / — | registry-check |
| dns-legacy | `dns` / outbound | 1.13 已移除 | 不再作为 outbound；使用 DNS rule action、DNS server 和 domain resolver | removed | no（removed） | none；—/—/—/— | 不可用 / — / — | check 明确报告 removed |
| selector | `selector` / outbound group | 基础内建 | 只选择已注册 outbound tag；成员为空或引用不存在都应失败 | yes | yes（Linux） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check（无 tags 按预期失败） |
| urltest | `urltest` / outbound group | 基础内建 | 对成员 URL 测试延迟并选择；需要可达探测 URL、成员 tag 和 timeout/interval 策略 | yes | yes（Linux） | none；—/—/—/— | 不属于分享节点 / — / — | registry-check（无 tags 按预期失败） |
| naive | `naive` / outbound | `with_naive_outbound`；Linux 官方纯 Go 变体仅 amd64/arm64，其他变体见下文 | HTTP/2 或可选 QUIC；TLS 只支持 server_name/certificate/path/ECH；依赖 libcronet，不能由 check 证明运行库存在 | conditional | yes（tag+libcronet 已含；运行库加载仍需） | none；—/—/—/— | — / 不编造 URI / — | registry-check（无 TLS 按预期失败） |

## Endpoint 矩阵

Endpoint 同时具有接入和出站行为，不能塞进普通 `inbounds`/`outbounds` 菜单，也不能把客户端 endpoint 误称为不存在的服务端代理协议。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| wireguard-endpoint | `wireguard` / endpoint | `with_wireguard`；`system` 数据路径依赖平台权限，gVisor 路径依赖 `with_gvisor` | UDP、peer/allowed IP/private key/MTU；支持多个 peer；不是旧 outbound | conditional | yes（tag 已含；peer/权限仍需） | Warp 特例；通用 none | Warp 专用 key/route 状态；不输出普通分享 / no current SubMan | registry-check |
| tailscale | `tailscale` / endpoint | `with_tailscale`；需要 auth key 或交互登录/控制面；可带 gVisor/system 接口 | WireGuard peer-to-peer UDP、控制面和可选 relay；可 advertise/accept routes、exit node、SSH；状态目录必须持久化 | conditional | yes（tag 已含；auth/控制面仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 auth 时仅注册检查） |
| openconnect | `openconnect` / endpoint | 自 1.14.0；`with_openconnect`；`system:false` 还要求 `with_gvisor`；需要 Cisco/GlobalProtect/Fortinet/F5/Pulse/Juniper 服务器和交互认证 | VPN 数据面可 TCP/UDP；HTTPS control channel、cookie/username/password/cert、DNS transport；无授权端点不能标 validated | conditional | yes（tag 已含；system:false 需 gVisor；认证仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 server 按预期失败） |
| openvpn-client | `openvpn-client` / endpoint | 自 1.14.0；`with_openvpn`；`system:false` 还要求 `with_gvisor`；需要外部 OpenVPN server/profile/凭据 | TCP 或 UDP；TLS 或 static_key；interactive auth、certificate/key、topology 和 DNS/route 需保留 | conditional | yes（tag 已含；system:false 需 gVisor；外部 profile 仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 server 按预期失败） |
| openvpn-server | `openvpn-server` / endpoint | 自 1.14.0；`with_openvpn`；`system:false` 还要求 `with_gvisor` | TCP 或 UDP，每个 endpoint 只服务一种 network；同时 TCP+UDP 要两个 server endpoint；TLS/static_key 模式约束不同 | conditional | yes（tag 已含；system:false 需 gVisor；证书/密钥仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 address 按预期失败） |

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

审计起点 `cc12c06` 的协议校验、保存和导出分别维护四协议白名单。第一阶段将 ID、菜单、导出候选、Agent 和验证元数据接入 `SB_PROTOCOL_REGISTRY`；状态和生命周期仍只有上述四种产品预设。`list_exportable_client_protocols` 当前只列出 VLESS REALITY、Hysteria2、AnyTLS，而 Mixed 的 HTTP/SOCKS 链接由 `links` 单独表达。原四协议已通过上述运行的 TCP 业务闭环；上游 type 识别探针不构成新增协议真实连接验证。上游没有独立的 mixed outbound，客户端须选择 SOCKS 或 HTTP outbound。

TCP/UDP 的源码核对结果是：Mixed 与 SOCKS 的 listener 都固定为 `NetworkTCP`，UDP 是 SOCKS UDP associate/UoT 业务；Redirect 的 listener 也固定为 `NetworkTCP`，只读取原始目标；TProxy 才按 `option.Network` 同时建立 TCP/UDP 并处理 UDP NAT。Snell inbound 的 listener 固定 TCP，版本分支明确调用 `snellv5`/`snellv6` 服务，UDP 通过服务的 packet API 复用 TCP 会话；Snell outbound 的 option schema 只允许 version `4,6`，inbound schema 只允许 `5,6`，代码分别构造 `snellv4`/`snellv6` client 与 `snellv5`/`snellv6` server，因此不能把整数版本直接视为两端相同版本号。证据为固定 tag 的 `protocol/{mixed,socks,redirect,snell}/*.go`、`option/{redir,snell}.go`。

Warp 是当前项目的 Cloudflare 专用注册与 WireGuard endpoint 路径，不等于已实现通用 WireGuard endpoint 管理。它应保持 `warp` 的旧状态、路由、凭据和回滚语义，并与未来通用 endpoint 分开。

版本交叉复核（2026-09-07）：[v1.13.18 注册代码](https://github.com/SagerNet/sing-box/blob/v1.13.18/include/registry.go) 不含 Bridge；实际 `1.13.18 check` 返回 `unknown outbound type: bridge`。[固定 tag 的 Bridge 文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/bridge.md) 明确标为自 1.14.0 且仅接收 L3 流量。另据 [direct options 源码](https://github.com/SagerNet/sing-box/blob/v1.14.0/option/direct.go)，移除目标覆盖的检查只在 outbound 解码中；同一受控 direct inbound 端口转发配置已分别通过真实 `1.13.18`、`1.14.0 check`。此项是配置兼容证据，尚未证明转发数据面。

对每个从 `none` 变成 `implemented` 的协议，至少需要：协议/预设/角色和实例 ID；状态读写迁移与未知配置保护；合法组合的 builder；依赖、端口、证书和路由归属；目标版本 `sing-box check`；部署/接管/编辑/删除事务；客户端配置和可表达性 warning；真实 TCP/UDP 或 endpoint 数据面探针；Agent、节点摘要、敏感输出和 SubMan 的明确 `unsupported/skipped/warning` 分支。组合协议必须连同内层代理或 endpoint 一起回滚，不能只保存一个孤立 JSON 片段。

本审阅没有访问生产 VPS、Cloudflare/Tailscale/OpenConnect/OpenVPN 账户，也没有执行真实外部控制面认证；因此这些条件性能力保持 `registry-check` 或未验证，不能在交付说明中写成已通过。后续实现应继续保留当前显式固定的 1.13.x 兼容路径，并在使用 1.14-only type（Snell、Cloudflared、Bridge、OpenConnect、OpenVPN）时以目标版本门控阻断，而不是只提高 `SB_SUPPORT_MAX_VERSION`。
