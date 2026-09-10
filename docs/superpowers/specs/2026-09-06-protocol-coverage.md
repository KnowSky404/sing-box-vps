# sing-box 1.14.0 协议能力核对矩阵

审阅日期：2026-09-06

目标稳定版：`v1.14.0`

源码提交：`0b8995879f29a9b98ee027bc17b75e101445b238`

审计起点脚本：`SCRIPT_VERSION=2026090402`；当前交付工作区已提升为 `SCRIPT_VERSION=2026091002`，`SB_SUPPORT_MAX_VERSION=1.14.0`

本文是上游能力核对，不能把上游已注册等同于 sing-box-vps 已实现。矩阵的四种状态分别表示：

- `upstream`：目标版本源码中是否有该角色和 type 的注册实现；`conditional` 表示构建 tag、平台、CGO 或外部控制面有条件。
- `implemented`：本项目是否已经提供状态、配置组合、生命周期、导出/分享等管理链路；`none` 不表示上游不可用。
- `available`：当前官方 ARM64 Linux 发布包中是否已包含该角色的注册实现，以及仍需满足的构建、平台、运行库或外部控制面条件；它独立于源码中存在注册函数。
- `validated`：本轮实际取得的证据。`registry-check` 只证明目标二进制能识别该 type 并进入初始化校验；`project-real-tcp` 表示回读了项目真实 TCP 业务闭环 artifact，不能由 `check`、监听端口或进程存活代替，也不证明 UDP 业务已测。

表中“版本”优先表示本项目实现时的核心版本门槛：除标明“自 1.14.0”的能力外，继续以项目已有的 1.13.x 兼容路径为下限；它不声称是该协议在 sing-box 历史上的首次引入版本。需要 1.14.0 的 type 或字段必须在目标版本门控后才可生成。

2026-09-09 高级组件增量：本项目新增独立 `components.json`（schema 1、revision/CAS）和 30 项 runtime component registry，接入 direct/tun/redirect/tproxy/cloudflared inbound、WireGuard/Tailscale/OpenConnect/OpenVPN endpoint，以及 SSH/Tor/direct/bridge/selector/urltest/block 和协议 outbound 的受控状态/config 组合。`implemented` 在本增量中表示状态读取、类型专属边界、配置合并、引用/依赖图、监听计划、Agent list/create/replace/delete 和目标核心校验切片已存在；组件的静态 `available` 仍为 `null`，另在 registry 每次读取时填充不缓存的 `environment` 观察（目标核心版本、平台、root/工具/运行库和外部认证依赖），其 `status` 只能是 `available`、`unavailable` 或 `not_assessed`，不等同于连接验证。`validated` 默认 `not_assessed`。高级 inbound/endpoint 支持有损保护接管和敏感单组件导出，但通用 outbound 及任意未建模顶层字段仍不接管；这些组件不进入普通分享节点索引，外部控制面、构建 tag、路由/防火墙权限和真实数据面均不由 registry 或 `sing-box check` 推断；因此下方组件行的 D/T/E/R 与导出、分享、SubMan 仍按此边界记录，完整协议目标继续未完成。

2026-09-10 持久化事务增量：高级组件写入现在在 `${SB_PROJECT_DIR}.component-write.lock` 中原子发布 `transaction.json`，记录 owner、CAS revision、before-active、publish/resources/service/committed 阶段和防火墙外部日志意图。`sbv agent component recover --json --yes --expected-revision N` 只接受已结束的 owner、可信快照和严格 phase/schema；中断发生在发布或资源阶段时先补偿防火墙再恢复 state/config/service，无法证明安全时保留目录并返回稳定错误。`component diagnose` 暴露 pending/phase 摘要；这仍不是公网防火墙、TUN/透明路由、Endpoint 外部认证或真实数据面验证，完整协议目标继续未完成。

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
| direct-inbound | `direct` / inbound | 基础内建 | TCP 或 UDP，由 `network` 指定，留空为两者；仍支持 `override_address/override_port` 端口转发，不能与 direct outbound 的移除项混淆 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | — / — / — | registry-check；两核心 override 配置 check 通过 |
| mixed | `mixed` / inbound | 基础内建 | TCP listen；同一入口提供 SOCKS4/4a/5 和 HTTP；UDP 业务经 SOCKS UDP/UoT，不开固定 UDP listen；schema 2 可管理多实例 | yes | yes（Linux） | 旧预设 + schema 2 实例链路；yes/yes/yes/yes（首次全新安装仍为 legacy schema 1，显式迁移后启用 schema 2） | SOCKS5 + UoT v2 裸核客户端（明文警告） / HTTP、SOCKS 链接 / no current SubMan | project-real-tcp；多实例生命周期、导出及本轮五协议最终门禁通过 |
| vless-reality（旧预设） | `vless` / inbound | 项目保留 1.13.x；REALITY、Vision 与 TCP 预设 | TCP listen，TCP/UDP 业务；已有多实例、固定 tag/UUID/ShortID、实例出站和 QoS | yes | yes（Linux；需握手目标） | 旧预设；yes/yes/yes/yes | 裸核客户端 / VLESS URI / VLESS 同步 | project-real-tcp |
| vless-plain（普通预设） | `vless` / inbound | 项目兼容 1.13.x；QUIC transport 另需 `with_quic` | 外层 TCP 或 QUIC/UDP；可选 TLS；按用户 `flow`；支持 none/http/ws/grpc/quic，HTTPUpgrade 与 WS early data fail closed | yes | yes（Linux） | 第十预设，schema 2 marker + schema 1 store，共享实例事务；yes/yes/yes/yes；多用户/TLS/transport/接管/恢复 | 逐用户完整 JSON / VLESS URI（可表达字段） / 逐实例逐用户同步（不可表达组合稳定跳过） | 两核心 1.13.18/1.14.0 check/export；专项 lifecycle/Agent/share/SubMan/probe 通过；最终本地 `20260908141403` 为 108/108，最终 Docker `20260908144031` 为 15/15 场景与 22/22 探针通过；仅容器/回环，非公网或生产证明 |
| socks（独立预设） | `socks` / inbound | 基础内建 | TCP listen；SOCKS4/4a/5；UDP associate/UoT 业务经该 TCP 会话处理；认证可选；无 HTTP/TLS | yes | yes（Linux） | active schema 2 marker + JSON store（`schema_version: 1`）与共享实例事务；yes/yes/yes/yes（实现范围，不等同全协议目标完成） | SOCKS5 + UoT v2 裸核客户端（明文警告） / SOCKS 链接 / no current SubMan | project-real-tcp；六项回归、两核心 check/runtime、菜单、Docker 10/10 与 TCP 14/14 通过；公网原生 UDP 未验证 |
| http | `http` / inbound | 基础内建；项目兼容 1.13.x；TLS 需用户提供有效证书/私钥引用 | HTTP CONNECT 入口，TCP；入口 TLS 与代理 HTTPS 目标独立；新实例默认回环与认证 | yes | yes（Linux；手工 TLS 文件另行预检） | schema 2 + 共享实例事务；yes/yes/yes/yes；无 legacy migration | HTTP CONNECT TCP 客户端（TLS 嵌入公有证书信任） / 明文 HTTP URI；TLS 返回不可表达 warning / no current SubMan | 两核心 check/TCP/TLS 正反向路径、实际 Bash 4.2、75 项本地门禁；修正测试断言后 Docker 11/11、TCP 16/16；仅本地/容器，非公网或生产证明 |
| shadowsocks | `shadowsocks` / inbound | 基础内建；项目兼容 1.13.x | TCP/UDP 可分选；九种方法；none/2022 ChaCha 无多用户；项目未建模 relay/mux/plugin | yes | yes（Linux） | schema 2 marker + schema 1 JSON 与共享实例事务；yes/yes/yes/yes；无 legacy migration | 逐用户完整 JSON / SIP002（单网络 warning） / 双网络加密项逐用户同步，单网络/none 跳过，mock-only | 两核心、原生 Bash/实际 Bash 4.2：9 方法 check、每组 7 TCP + 7 UDP marker、错误认证拒绝；最终源码 Docker 12/12、TCP 18/18；公网/生产未验证 |
| vmess | `vmess` / inbound | 基础内建；项目兼容 1.13.x；QUIC transport 另需 `with_quic` | 原生及 HTTP/WS/gRPC/HTTPUpgrade 外层 TCP，QUIC 外层 UDP + TLS；可承载 TCP/UDP 业务；`alterId>0` 是兼容模式；WS early data/HTTPUpgrade 受 runtime guard 限制 | yes | yes（Linux） | 第九预设，schema 2 marker + schema 1 store，共享实例事务；yes/yes/yes/yes；多用户/TLS/transport/接管/恢复 | 逐用户完整 JSON / `vmess://`（可表达字段） / TLS 系统信任且 URI 无损的逐用户同步，其他明确跳过 | 两核心 1.13.18/1.14.0 check/export（none/http/ws/grpc/quic），本地 takeover/lifecycle/Agent/share/SubMan/probe 测试通过；Docker `20260908110530` 新装、九协议共存、21 个协议探针及升级成功/回滚通过 |
| trojan | `trojan` / inbound | 基础内建；QUIC transport 另需 `with_quic`；项目兼容 1.13.x | 外层 TCP 或 TLS QUIC/UDP；TLS/transport/客户端信任分别建模；不接管 fallback/mux/未知字段；HTTPUpgrade、WS early data 被阻断 | yes | yes（Linux） | 第八预设，schema 2 marker + schema 1 store，共享实例事务；yes/yes/yes/yes；无 legacy migration | 逐用户完整 JSON / TLS 系统信任的无损 URI 子集 / 逐用户同步及跳过原因，本地 mock | 受管导出经实际 SubMan parser 十组往返、两核心 check；完整生命周期和最终 Docker 验收见实施记录，阶段检查不等于最终通过 |
| naive-inbound | `naive` / inbound | 入站本体内建；QUIC 路径需要 `with_quic` | TCP 或 UDP；用户和 TLS 必填；UDP 为 HTTP/3/QUIC 路径，不能只以 TCP check 代替 | conditional | yes（tag 已含；QUIC/TLS 仍需） | 第十四预设，active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；手工 TLS、多用户、TCP/UDP 选择 | 逐用户完整 Naive outbound JSON / 不生成标准 URI / unsupported，不执行 SubMan | `tests/naive_instance_lifecycle.sh` mock 与目标 1.14.0 server/client check 通过；未验证 TCP/UDP 数据面、公网或 libcronet 加载 |
| hysteria | `hysteria` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；`auth_str` 用户、必填上下行带宽、字符串 obfs、QUIC 窗口/MTU/并发流；不要与 hysteria2 字段混用 | conditional | yes（tag 已含） | 第十三预设，active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；手工 TLS、多用户、接管/恢复 | 逐用户完整 Hysteria outbound JSON / 无标准 URI（`hysteria_standard_uri_unavailable`） / unsupported，不执行 SubMan | `tests/hysteria_instance_lifecycle.sh` mock 与目标 1.14.0 server/client check 通过；未验证公网 UDP 或数据面 |
| shadowtls | `shadowtls` / inbound | 基础内建 | TCP 包装层；v1/v2/v3 的 password、users、handshake 和 strict/wildcard 约束不同；必须组合内层代理 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 handshake 按预期失败） |
| vless | `vless` / inbound | 基础内建；项目通过 `vless-reality` 与 `vless-plain` 两个预设映射；QUIC 另需 `with_quic` | 外层 TCP 或 QUIC/UDP；TLS/REALITY 和 transport 必须按目标版本组合；`xtls-rprx-vision` 是特定 flow，不是通用开关 | yes | yes（Linux） | generic upstream type；项目生命周期按 `vless-reality`/`vless-plain` 分列 | — / — / — | registry-check；具体管理链路见两个项目预设 |
| tuic | `tuic` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；UUID/password、拥塞控制、auth timeout、heartbeat、0-RTT；UDP relay mode/udp-over-stream 仅属于 outbound | yes | yes（官方包含 `with_quic`） | 第十二预设，active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；手工 TLS、多用户、接管/恢复 | 逐用户完整 TUIC outbound JSON / 无标准 URI（warning） / unsupported，不执行 SubMan | `tests/tuic_instance_lifecycle.sh` mock 与目标 1.14.0 server/client check 通过；未验证公网 UDP 或数据面 |
| hysteria2 | `hysteria2` / inbound | `with_quic`；官方默认 Linux tag 含它 | QUIC/UDP + TLS；password、salamander/gecko obfs、masquerade；realm/STUN/端口映射是额外控制面 | conditional | yes（tag 已含） | 旧 schema 1 + typed schema 2 手工 TLS 多实例/用户；yes/yes/yes/yes；旧 ACME/provider 接管保留 legacy，重复 legacy 入站仍阻断 | 逐用户完整 client JSON / Hysteria2 URI（证书 trust 或证书算法可能 warning） / system-trust 用户逐用户同步，证书 trust 跳过，带宽/masquerade 无法由 URI 表达并保留 warning | typed store/lifecycle/Agent/export/SubMan mock 专项通过；Docker 旧路径共存通过；未配置目标核心，QUIC 不作为独立 UDP payload 证据 |
| anytls | `anytls` / inbound | 自 1.12.0；基础内建 | TCP + TLS；users/password 和 padding scheme；客户端 metadata 不能由普通 URI 无损表达 | yes | yes（Linux） | 旧 schema 1 + typed schema 2 manual-TLS 实例；yes/yes/yes/yes；ACME/provider takeover fail closed | AnyTLS client JSON / 无稳定无损 URI（warning） / no current SubMan | typed store/lifecycle/Agent/export check；公网与真实 SubMan 未验证 |
| snell | `snell` / inbound | 自 1.14.0；基础注册但协议为新版本能力 | TCP listen；server 版本 `5` 或 `6`，UDP 业务由 Snell packet API 经 TCP 会话承载；v5 只 HTTP obfs 且不支持 QUIC proxy，v6 为 traffic shaping 并要求 12–255 字节 PSK | yes | yes（Linux） | active schema 2 marker + schema 1 JSON store、共享实例事务；yes/yes/yes/yes；0–128 用户；无 legacy migration | 逐用户完整 Snell outbound JSON / 无标准 URI（warning） / unsupported（不执行 SubMan） | typed lifecycle/takeover/rebuild/Agent/export 专项通过；配置目标 1.14.0 时执行 check；未证明 UDP payload、公网、生产或 SubMan |
| tun | `tun` / inbound | 基础内建；Linux 需要系统权限与路由工具，平台行为不同 | TCP/UDP/ICMP 的透明接入；Linux `auto_route/auto_redirect`、nftables/iproute2、DNS 劫持和自捕获环路必须一起管理 | yes | yes（Linux；权限/路由仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check |
| redirect | `redirect` / inbound | Linux、macOS；Linux 通常需 root/iptables 或 nftables 方案 | TCP only；源码 listener 固定 `NetworkTCP`，通过原始目标重定向连接；必须防止管理 SSH 被捕获 | conditional | yes（Linux；root/重定向规则仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check |
| tproxy | `tproxy` / inbound | Linux；需 root、策略路由/防火墙能力 | TCP/UDP（空值表示两者）；Linux 专属，UDP NAT 参数和路由归属必须持久化 | conditional | yes（Linux；root/策略路由仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check |
| cloudflared | `cloudflared` / inbound | 自 1.14.0；`with_cloudflared`；需 Cloudflare Tunnel token 和外部控制面 | Cloudflare Tunnel 可承载 TCP、UDP、ICMP；`protocol` 为 QUIC/HTTP2，UDP datagram v2/v3；不能虚构普通节点 URI | conditional | yes（tag 已含；token/控制面仍需） | component state/config；yes/yes/yes/yes* | 不提供普通分享 / — / — | registry-check（无 token 按预期失败） |

`tun`、`redirect`、`tproxy` 与 `cloudflared` 行的 `component state/config` 覆盖本项目的统一状态、配置合并、引用保护、监听投影、Agent CAS、目标核心校验，以及固定监听变化所复用的受管 UFW/iptables/ip6tables 归属事务；透明路由、策略路由、nftables/iproute2、TUN/Cloudflare 控制面、动态资源和真实业务仍未宣称通过。`*` 表示同上所述的组件生命周期切片，不是公网部署证明。

`vless-reality` 是本项目旧兼容预设，配置使用上游 `type: vless`，并非独立的上游 type；普通 VLESS 使用独立 `vless-plain` preset/state ID。项目继续把 `vless`、`vless+reality`、`vless-reality` 归一到旧 REALITY 状态，普通 VLESS 不复用该 alias，避免接管、重建或导出时将两种语义混淆。

## 出站及组合组件矩阵

出站的“TCP/UDP”表示该客户端出站可用的网络能力，实际仍受协议和 peer 服务端约束。`selector`、`urltest`、`bridge`、`block` 是路由组合或系统接入组件，不应被当成可分享代理节点。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| direct-outbound | `direct` / outbound | 基础内建 | TCP/UDP 直连；旧 `override_address/port` 在 1.13 已移除，改用 route options | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | — / — / — | registry-check |
| bridge | `bridge` / outbound | 自 1.14.0；需要 Linux/macOS/Windows、rooted Android 或 jailbroken iOS 的权限/接口 | 只接收来自 TUN/Endpoint pre-match 的 L3 流量（TCP/UDP/ICMP），拒绝 L4 代理连接与本机目的地址；Linux 有 iproute2 table/rule | conditional | yes（Linux；接口/root 仍需） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check；1.13.18 明确拒绝未知 type |
| block | `block` / outbound | 基础内建 | 丢弃连接/数据；无网络协议 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check |
| socks | `socks` / outbound | 基础内建 | SOCKS4/4a/5；TCP，UDP 依 server 支持，可 UDP-over-TCP | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| http | `http` / outbound | 基础内建 | HTTP CONNECT，TCP；可单独配置 outbound TLS、headers、path | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| shadowsocks | `shadowsocks` / outbound | 基础内建 | TCP/UDP；方法覆盖 SS2022 与传统方法，密码/密钥长度须按 method 校验；可 multiplex/UoT | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 method 按预期失败） |
| vmess | `vmess` / outbound | 基础内建 | TCP/UDP；TLS、transport、packet encoding 和 legacy alterId 组合有限 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| trojan | `trojan` / outbound | 基础内建 | TCP/UDP（按 outbound network）+ TLS；transport/multiplex 需对端支持 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| wireguard-legacy | `wireguard` / outbound | 已移除；不能靠导航页恢复 | 不再创建；应使用 WireGuard endpoint，再由 route/dial 关系接入 | removed stub | no（removed） | none；—/—/—/— | 不可导出为旧 outbound / — / — | check 明确报告 removed |
| wireguard | `wireguard` / endpoint | 自 1.11 endpoint 架构；`with_wireguard`；官方 VPS 包含该 tag | UDP tunnel，peer、allowed IP、private key、MTU；`system`/gVisor 和平台权限影响数据路径 | conditional | yes（tag 已含；peer/权限仍需） | Warp 特例；通用 none | 不属于普通分享节点；Warp 由项目专用材料管理 / no current SubMan | endpoint registry-check |
| hysteria | `hysteria` / outbound | `with_quic` | QUIC/UDP + TLS；`auth_str`、上下行带宽、字符串 obfs 和 QUIC 参数，不与 hysteria2 互换 | conditional | yes（tag 已含） | typed per-user client export（由 Hysteria 入站实例管理驱动）；— | 完整 Hysteria outbound JSON / 无标准 URI（`hysteria_standard_uri_unavailable`） / unsupported | `tests/hysteria_instance_lifecycle.sh` 与真实 1.14.0 outbound check 通过；未验证公网 UDP 或数据面 |
| vless | `vless` / outbound | 基础内建 | TCP/UDP；TLS/REALITY、flow、transport、xudp packet encoding 必须分别表示 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check |
| shadowtls | `shadowtls` / outbound | 基础内建 | TCP 包装层；必须指向实际内层服务端，v1/v2/v3 字段不能混用 | yes | yes（Linux） | none；—/—/—/— | — / — / — | registry-check（无 TLS 按预期失败） |
| tuic | `tuic` / outbound | `with_quic` | QUIC/UDP + TLS；`network`、native/quic UDP relay、可选 UDP-over-stream、0-RTT、heartbeat 和拥塞控制 | yes | yes（官方包含 `with_quic`） | typed per-user client export（由 TUIC 入站实例管理驱动）；— | 完整 TUIC outbound JSON / 无标准 URI（`tuic_standard_uri_unavailable`） / unsupported | `tests/tuic_instance_lifecycle.sh` 与真实 1.14.0 outbound check 通过；未验证公网 UDP 或数据面 |
| hysteria2 | `hysteria2` / outbound | `with_quic` | QUIC/UDP + TLS；obfs、realm/STUN、Chrome QUIC fingerprint 和证书算法约束 | conditional | yes（tag 已含） | typed per-user client export（由 Hysteria2 入站实例管理驱动）；— | Hysteria2 URI 与完整 outbound JSON（按 trust/证书算法发 warning） / — | typed builder/URI/Ed25519 warning 专项通过；目标核心未配置 |
| anytls | `anytls` / outbound | 自 1.12.0；基础内建 | TCP + TLS；password、idle session、client_metadata；需与 AnyTLS server 配套 | yes | yes（Linux） | typed per-user client export；— | AnyTLS client JSON（`client_metadata` empty, optional public PEM） / 不生成伪 URI / no current SubMan | registry-check（无 TLS 按预期失败）；两核心 check when configured |
| snell | `snell` / outbound | 自 1.14.0；基础注册 | TCP transport；版本 `4` 或 `6`，UDP 业务由客户端通过 TCP 会话的 packet API 承载；v5 QUIC proxy 明确不支持；v4 obfs 与 v6 shaping 不同 | yes | yes（Linux） | typed per-user client export（由 Snell 入站实例管理驱动）；— | 完整 outbound JSON（v5 入站映射 v4、v6 入站映射 v6） / — / — | Snell lifecycle/export 专项通过；目标核心 check 需按配置执行；无独立 UDP payload 证据 |
| tor | `tor` / outbound | type 总是注册；嵌入 Tor 需 `with_embedded_tor` + CGO，默认官方包不含 embedded Tor | 通过外部 Tor executable 或嵌入实例；必须管理 executable path/data directory/torrc；不能把 Tor 当普通服务端节点 | conditional | yes（外部 executable；embedded 需额外 tag/CGO） | none；—/—/—/— | — / 不生成 Tor 分享 / — | registry-check（外部路径为空时仅证明注册） |
| ssh | `ssh` / outbound | 基础内建；目标 SSH 服务和密钥/host key 策略是外部条件 | TCP；密码或 private key、host key/cipher/kex 需校验；不创建新的 SSH server | conditional | yes（Linux；目标 SSH/凭据仍需） | none；—/—/—/— | — / 不生成 SSH 节点 URI / — | registry-check |
| dns-legacy | `dns` / outbound | 1.13 已移除 | 不再作为 outbound；使用 DNS rule action、DNS server 和 domain resolver | removed | no（removed） | none；—/—/—/— | 不可用 / — / — | check 明确报告 removed |
| selector | `selector` / outbound group | 基础内建 | 只选择已注册 outbound tag；成员为空或引用不存在都应失败 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check（无 tags 按预期失败） |
| urltest | `urltest` / outbound group | 基础内建 | 对成员 URL 测试延迟并选择；需要可达探测 URL、成员 tag 和 timeout/interval 策略 | yes | yes（Linux） | component state/config；yes/yes/yes/yes* | 不属于分享节点 / — / — | registry-check（无 tags 按预期失败） |
| naive | `naive` / outbound | `with_naive_outbound`；Linux 官方纯 Go 变体仅 amd64/arm64，其他变体见下文 | HTTP/2 或可选 QUIC；TLS 只支持 server_name/certificate/path/ECH；依赖 libcronet，不能由 check 证明运行库存在 | conditional | yes（tag+libcronet 已含；运行库加载仍需） | typed per-user client export（由 NaiveProxy 入站实例管理驱动）；— | 完整 Naive outbound JSON / 不编造 URI（warning） / unsupported | `tests/naive_instance_lifecycle.sh` 与真实 1.14.0 outbound check 通过；未验证 libcronet 加载或数据面 |

## Endpoint 矩阵

Endpoint 同时具有接入和出站行为，不能塞进普通 `inbounds`/`outbounds` 菜单，也不能把客户端 endpoint 误称为不存在的服务端代理协议。

| ID | 官方 type / 角色 | 版本、构建和平台条件 | TCP/UDP/主要约束 | upstream | available（官方 ARM64 包） | implemented；D/T/E/R | 导出 / 分享 / SubMan | validated |
|---|---|---|---|---|---|---|---|---|
| wireguard-endpoint | `wireguard` / endpoint | `with_wireguard`；`system` 数据路径依赖平台权限，gVisor 路径依赖 `with_gvisor` | UDP、peer/allowed IP/private key/MTU；支持多个 peer；不是旧 outbound | conditional | yes（tag 已含；peer/权限仍需） | Warp 特例；通用 none | Warp 专用 key/route 状态；不输出普通分享 / no current SubMan | registry-check |
| tailscale | `tailscale` / endpoint | `with_tailscale`；需要 auth key 或交互登录/控制面；可带 gVisor/system 接口 | WireGuard peer-to-peer UDP、控制面和可选 relay；可 advertise/accept routes、exit node、SSH；状态目录必须持久化 | conditional | yes（tag 已含；auth/控制面仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 auth 时仅注册检查） |
| openconnect | `openconnect` / endpoint | 自 1.14.0；`with_openconnect`；`system:false` 还要求 `with_gvisor`；需要 Cisco/GlobalProtect/Fortinet/F5/Pulse/Juniper 服务器和交互认证 | VPN 数据面可 TCP/UDP；HTTPS control channel、cookie/username/password/cert、DNS transport；无授权端点不能标 validated | conditional | yes（tag 已含；system:false 需 gVisor；认证仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 server 按预期失败） |
| openvpn-client | `openvpn-client` / endpoint | 自 1.14.0；`with_openvpn`；`system:false` 还要求 `with_gvisor`；需要外部 OpenVPN server/profile/凭据 | TCP 或 UDP；TLS 或 static_key；interactive auth、certificate/key、topology 和 DNS/route 需保留 | conditional | yes（tag 已含；system:false 需 gVisor；外部 profile 仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 server 按预期失败） |
| openvpn-server | `openvpn-server` / endpoint | 自 1.14.0；`with_openvpn`；`system:false` 还要求 `with_gvisor` | TCP 或 UDP，每个 endpoint 只服务一种 network；同时 TCP+UDP 要两个 server endpoint；TLS/static_key 模式约束不同 | conditional | yes（tag 已含；system:false 需 gVisor；证书/密钥仍需） | none；—/—/—/— | 不属于普通分享节点 / — / — | registry-check（无 address 按预期失败） |

Endpoint 表中仍保留 `none` 的历史行表示没有专用分享/节点适配；2026-09-09 增量新增的 `components.json` 状态/config/CAS 管理切片等价于组件生命周期 `yes/yes/yes/yes*`，但不等同外部 VPN/Tailscale/WireGuard 数据面已验证。`*` 表示配置组合、目标核心 check 和回滚边界已接入，外部认证、系统接口、路由/防火墙及公网业务仍需独立证据。

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

审计起点 `cc12c06` 的协议校验、保存和导出分别维护四协议白名单；当前六个入站预设由 `SB_PROTOCOL_REGISTRY` 提供 ID、菜单、导出候选、Agent 和验证元数据。上游没有独立的 mixed outbound，客户端须选择 SOCKS 或 HTTP outbound。Mixed、独立 SOCKS 与 HTTP 提供共享的 schema 2 类型化实例状态和生命周期入口，但这只改变项目预设，不扩展上游协议类型。

Mixed schema 2 的完整管理链路包括：显式把 legacy schema 1 单实例迁移为 `protocols/instances/mixed.json`，并保留原有 ID/tag/监听地址/端口/认证；Agent 的 `create`、`replace`、`delete`、`default`、`migrate`、`recover` 使用 revision CAS 和 JSON envelope；交互菜单 17 提供逐实例创建/修改/删除/默认/迁移/恢复。首次全新安装仍沿用 legacy schema 1，不自动迁移。删除最后一个实例后保留空 JSON store（`schema_version: 1`）作为 revision tombstone；active marker 仍是 `CONFIG_SCHEMA_VERSION=2`，并移除 active Mixed 的 env/index/inbound，但下一次 `create` 必须以 tombstone revision 继续递增，不能清空 JSON 后把 CAS 重置为 0。非回环明文入口需要显式 `--allow-public`；活动 Mixed 与其他协议的批量删除会拒绝，要求逐个实例处理。上述是实现范围说明，运行门禁证据由实施记录补充，不能由源码存在替代。

写入口把文件、完整配置候选、监听资源、受管 UFW/iptables/ip6tables 规则和服务重启置于同一实例事务边界：初次创建先同目录 staging 后原子发布；共享 `flock` 防并发，`.instance-write.lock/transaction.json` 记录持久阶段，`.instance-transactions/` 保存 result；故障恢复使用原快照和受管防火墙回滚，并在无法恢复时保留 journal/恢复材料。firewalld 只做只读外部预检，不在事务中 add/delete/reload；缺少所需 allow 或既有归属账本时，必须在任何发布前失败并要求人工规则；缺少防火墙 journal 时恢复失败并转人工处理。`firewall-cmd` 的 reload 会影响运行时防火墙状态，相关命令语义以[官方手册](https://firewalld.org/documentation/man-pages/firewall-cmd.html)为准；UFW 规则的 comment 不作为身份，地址语法以[Ubuntu ufw(8) 手册](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)为准。本记录不据此宣称 UFW runtime 已验证。文件状态原语自身的备份与回滚不等于系统防火墙或其他进程端口的完整事务。

TCP/UDP 的源码核对结果是：Mixed 与 SOCKS 的 listener 都固定为 `NetworkTCP`，UDP 是 SOCKS UDP associate/UoT 业务；Redirect 的 listener 也固定为 `NetworkTCP`，只读取原始目标；TProxy 才按 `option.Network` 同时建立 TCP/UDP 并处理 UDP NAT。Snell inbound 的 listener 固定 TCP，版本分支明确调用 `snellv5`/`snellv6` 服务，UDP 通过服务的 packet API 复用 TCP 会话；Snell outbound 的 option schema 只允许 version `4,6`，inbound schema 只允许 `5,6`，代码分别构造 `snellv4`/`snellv6` client 与 `snellv5`/`snellv6` server，因此不能把整数版本直接视为两端相同版本号。证据为固定 tag 的 `protocol/{mixed,socks,redirect,snell}/*.go`、`option/{redir,snell}.go`。

Warp 是当前项目的 Cloudflare 专用注册与 WireGuard endpoint 路径，不等于已实现通用 WireGuard endpoint 管理。它应保持 `warp` 的旧状态、路由、凭据和回滚语义，并与未来通用 endpoint 分开。

版本交叉复核（2026-09-07）：[v1.13.18 注册代码](https://github.com/SagerNet/sing-box/blob/v1.13.18/include/registry.go) 不含 Bridge；实际 `1.13.18 check` 返回 `unknown outbound type: bridge`。[固定 tag 的 Bridge 文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/bridge.md) 明确标为自 1.14.0 且仅接收 L3 流量。另据 [direct options 源码](https://github.com/SagerNet/sing-box/blob/v1.14.0/option/direct.go)，移除目标覆盖的检查只在 outbound 解码中；同一受控 direct inbound 端口转发配置已分别通过真实 `1.13.18`、`1.14.0 check`。此项是配置兼容证据，尚未证明转发数据面。

对每个从 `none` 变成 `implemented` 的协议，至少需要：协议/预设/角色和实例 ID；状态读写迁移与未知配置保护；合法组合的 builder；依赖、端口、证书和路由归属；目标版本 `sing-box check`；部署/接管/编辑/删除事务；客户端配置和可表达性 warning；真实 TCP/UDP 或 endpoint 数据面探针；Agent、节点摘要、敏感输出和 SubMan 的明确 `unsupported/skipped/warning` 分支。组合协议必须连同内层代理或 endpoint 一起回滚，不能只保存一个孤立 JSON 片段。

Mixed 与独立 SOCKS 的实现边界仍然明确：服务端及导出的 SOCKS5/UoT 链路没有 TLS，独立 SOCKS 也没有 HTTP surface；两者均没有当前 SubMan 同步。独立 SOCKS 的共享实例管理、客户端导出、两核心 check/runtime 与最终 Docker/TCP 门禁均已通过，证据见[实施记录](../plans/2026-09-06-unified-protocol-management.md)。这些 SOCKS 结果不覆盖公网原生 UDP、TLS/HTTP/SubMan 或其他未实现协议；独立 HTTP 的入口 TLS 与 HTTP CONNECT 客户端证据另列于该记录。当前只有六个已接入预设及本节明确的实例管理范围，全协议目标仍未完成，不能把 `sing-box check` 通过写成所有协议生命周期已完成。

本审阅没有访问生产 VPS、Cloudflare/Tailscale/OpenConnect/OpenVPN 账户，也没有执行真实外部控制面认证；因此这些条件性能力保持 `registry-check` 或未验证，不能在交付说明中写成已通过。后续实现应继续保留当前显式固定的 1.13.x 兼容路径，并在使用 1.14-only type（Snell、Cloudflared、Bridge、OpenConnect、OpenVPN）时以目标版本门控阻断，而不是只提高 `SB_SUPPORT_MAX_VERSION`。
