# 全协议适配与统一协议管理实施记录

需求来源：[用户原始目标](https://microbin.knowsky.uk/raw/aQg19d)，2026-09-06。
起点为 `cc12c06`，工作区干净；保留参考基线 `0d0bdac` 之后的下载事务修复。
本文记录完整目标的进展；阶段提交不代表全协议已交付。

## 2026-09-09：高级入站、Endpoint 与上游组件状态层（阶段交付）

从 ShadowTLS 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 用于核对当前上游文档入口，再以固定 `v1.14.0` 源码确认 direct/tun/redirect/tproxy/cloudflared、WireGuard/Tailscale/OpenConnect/OpenVPN endpoint，以及 SSH/Tor/direct/bridge/selector/urltest/block 和协议 outbound 的角色、字段和条件构建 tag。Cloudflared token、外部 VPN/Tailscale 控制面、WireGuard peer 和 Naive runtime 均不在本机伪造或认证。

本阶段新增独立 `components.json`（schema 1、revision/CAS、最多 128 条组件）与 30 项组件 registry。组件记录使用显式 `id/role/type/tag/enabled/route_rules/config`，通过未知字段拒绝、类型专属必填检查、引用保护、公开监听确认和同目录原子备份写入；配置生成将启用组件合并到现有协议/ Warp 配置，随后执行组件图（引用与依赖环）、监听资源和目标 `sing-box check`。`sbv agent component list --json` 只返回元数据/配置键，create/replace/delete 需要 `--yes` 与精确 `--expected-revision`；TUN、Cloudflared、OpenVPN server 和非回环监听需要 `--allow-public`。高级 inbound 不进入普通协议索引，Warp endpoint 保留旧专用归属，删除被 route/group/detour 引用的组件会阻断。

新增 `tests/managed_components_contract.sh` 覆盖 registry 30 项、CAS/render、引用删除保护、公开确认、direct+TUN 监听投影、Cloudflared token 脱敏、未知 wrapper 字段和 Agent stale revision，并将其加入 `dev/verification/common.sh` 的 install.sh 本地矩阵。定向与完整本地门禁均通过：`bash dev/verification/run.sh` 运行目录 `dev/verification-runs/20260909105322`，调度解析 108 项测试并退出 0；Docker artifact 同一目录为 15/15 场景成功，`meta/exit-status.txt` 为 0，既有回环协议探针和升级/接管产物均提取成功。固定官方 1.14.0 核心对 direct/tun/redirect/tproxy 组合的图/监听/check 通过；本轮仍未取得 Cloudflared/VPN/Tailscale 外部认证、透明接入真实路由、防火墙事务或新增组件公网/数据面证据。因此 registry 的 `implemented` 只表示本项目组件状态/配置组合切片，`available=null`、`validated.not_assessed` 保持诚实，完整协议目标继续未完成。版本提升为本轮 `2026090903`。

随后独立修正 `redirect` 的监听投影为上游固定的 TCP（不再错误地规划 UDP），并新增回归断言；`tests/managed_components_contract.sh`、`managed_listener_resources.sh`、`listener_network_selection.sh` 与 `live_inbound_inventory_guards.sh` 均退出 0。最新源码的 Docker-only 重跑目录为 `dev/verification-runs/20260909113618`，按 `install.sh` 变更选择的 14/14 场景均为 `STATUS=success`，artifact `meta/exit-status.txt` 为 0；本次跳过已在上一目录完成的 108 项本地矩阵。

## 2026-09-09：NaiveProxy 结构化实例管理链路（阶段交付）

从 Hysteria v1 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 核对 Naive inbound/outbound 的实际字段：Naive 入站使用必需的用户名/密码用户和 TLS，`network` 可选 TCP、UDP 或两者；客户端出站保留 QUIC 拥塞控制、窗口、并发和额外 headers。官方 Naive outbound 需要带 `with_naive_outbound` 的构建，并在运行时加载 `libcronet.so`，因此脚本只披露该依赖，不把普通 `sing-box check` 当成库可用证明。

本阶段接入第十四个 `naive` 预设（安装菜单 14、管理菜单 29），使用 schema 2 active marker + schema 1 JSON store、实例 revision/CAS、监听资源、接管/重建、创建/替换/删除/默认/恢复事务，以及 Agent `nodes`/`links`/`export-client`。typed 记录限定 1–128 个唯一 `username`/`password` 用户、手工 TLS、`certificate`/`system` 客户端信任、规范化 TCP/UDP 监听网络和有界 Naive/QUIC 选项；单网络服务端按核心要求渲染为标量 `network`，双网络省略该字段。客户端按用户输出完整 Naive outbound JSON，`links` 返回 `naive_standard_uri_unavailable` 与 `naive_libcronet_required`，不生成 QR 或执行 SubMan 同步。

新增 `tests/naive_instance_lifecycle.sh`，覆盖双实例 create/replace/delete、stale CAS、删除 tombstone、用户/TLS/网络/选项校验、接管候选、服务端渲染、客户端导出、Agent 脱敏和 no-URI/libcronet warning；设置 `SINGBOX_BINARY_114` 时，专项测试同时对服务端 candidate 与客户端 outbound 执行真实 sing-box 1.14.0 `check`。`bash tests/naive_instance_lifecycle.sh` 与配置真实 ARM64 核心的专项 check 均通过；`VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh` 通过完整本地调度/回归，Docker 远程验证目录 `dev/verification-runs/20260909053849` 的 `summary.log` 为 `remote_status=success`，15/15 场景与 21/21 既有 TCP 探针成功。证据仍是本地结构化事务、目标核心 schema 检查、容器回环和 mock 资源边界，不代表 libcronet 已部署、公网 TCP/UDP 可达、Naive UDP 数据面、生产部署或真实 SubMan API；本阶段未执行生产操作、推送或外部同步。版本沿用本轮 `2026090901`，全协议目标继续未完成。

## 2026-09-09：Hysteria v1 结构化实例管理链路（阶段交付）

从 TUIC 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 与固定官方 `v1.14.0` ARM64 核心核对 Hysteria v1 的实际字段：`users[].auth_str`、手工 TLS、独立 `up_mbps`/`down_mbps`、字符串形式的 QUIC obfs，以及初始包大小、窗口、并发流等 QUIC 选项。Hysteria v1 与 Hysteria2 保持独立协议身份，不复用 salamander/masquerade 或 Hysteria2 的认证语义。

本阶段接入第十三个 `hysteria` 预设（安装菜单 13、管理菜单 28），使用 schema 2 active marker + schema 1 JSON store、实例 revision/CAS、监听资源、接管/重建、创建/替换/删除/默认/恢复事务，以及 Agent `nodes`/`links`/`export-client`。typed 记录限定 1–128 个唯一 `name`/`auth_str` 用户、手工证书 TLS、`certificate`/`system` 客户端信任、正的上下行带宽、可选字符串 obfs 和严格类型的 QUIC 选项；服务端与客户端均通过逐用户 JSON outbound 导出。Hysteria v1 没有本项目可无损生成的标准分享 URI/二维码，也不执行 SubMan 同步；Agent links 返回稳定 warning 并脱敏凭据。

新增 `tests/hysteria_instance_lifecycle.sh`，覆盖双实例 create/replace/delete/default/recover、stale CAS、字段边界、接管候选、服务端渲染、客户端导出和 Agent 脱敏/no-URI warning；设置 `SINGBOX_BINARY_114` 时，专项测试同时对 candidate 与客户端 outbound 执行真实 `sing-box 1.14.0 check`。本阶段专项测试、注册表/文档契约和既有 TUIC 回归均通过；完整 Docker 验证沿用本轮已通过的基础场景，尚未新增公网 Hysteria UDP payload 探针。现有证据是本地结构化事务、目标核心 schema 检查、容器回环与 mock 数据，不代表公网可达性、生产部署或真实 SubMan API；本阶段未执行生产操作、推送或外部同步。版本提升为 `2026090901`，全协议目标继续未完成。

## 2026-09-09：TUIC 结构化实例管理链路（阶段交付）

从 Snell 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 核对 TUIC 官方 inbound/outbound 字段，随后用固定官方 `v1.14.0` ARM64 核心验证实际 schema。核心明确接受 TUIC QUIC/UDP 服务端与客户端字段，但拒绝入站 `udp_relay_mode`；该字段以及 `udp_over_stream` 只属于 outbound。

本阶段接入第十二个 `tuic` 预设（安装菜单 12、管理菜单 27），使用 schema 2 active marker + schema 1 JSON store、实例 revision/CAS、监听资源、接管/重建、创建/替换/删除/默认/恢复事务，以及 Agent `nodes`/`links`/`export-client`。typed 记录限定 1–128 个 UUID/密码用户、手工证书 TLS、`certificate`/`system` 客户端信任、拥塞控制、auth timeout、heartbeat 和 zero-rtt；`udp_relay_mode` (`native|quic`) 与 `udp_over_stream` 保留在记录中供客户端导出，但服务端入站渲染时明确省略。TUIC 无标准分享 URI/二维码，也不执行 SubMan 同步。

新增 `tests/tuic_instance_lifecycle.sh`，覆盖 create/replace/delete/default/recover、stale CAS、删除 tombstone、用户/TLS/选项校验、服务端 outbound-only 字段排除、接管候选、Agent 凭据脱敏、no-URI warning 和客户端逐用户 outbound。设置 `SINGBOX_BINARY_114` 时，专项测试同时对服务端 candidate 与客户端 outbound 执行真实 `sing-box 1.14.0 check`；主机 mock 与该目标核心均通过。受影响文件的完整 Docker 验证运行目录为 `dev/verification-runs/20260909001234`，Docker verification、image build/run 和 exec failure 场景均通过；该次未注入两版核心路径，因此核心依赖门禁按规则跳过，TUIC 的 1.14 检查由上述专项单独完成。该证据是本地结构化生命周期、目标配置检查和回环材料，不代表公网 UDP 可达、TUIC UDP payload、生产部署或真实 SubMan。未执行生产操作、推送或外部同步；版本沿用本轮已提升的 `2026090805`，全协议目标继续未完成。

## 2026-09-08：Snell 结构化实例管理链路（阶段交付）

从 Hysteria2 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 核对 Snell 入站/出站的版本、PSK、用户 key、v5 HTTP obfs 与 v6 traffic-shaping 字段；固定 1.14.0 源码进一步确认入站版本为 `5/6`、出站版本为 `4/6`，不能把两端整数直接当作同一版本。

本阶段接入第十一个 `snell` 预设（菜单 26），使用 schema 2 active marker + schema 1 JSON store、实例 revision/CAS、监听资源、接管/重建、创建/替换/删除/默认/恢复事务，以及 Agent `nodes`/`links`/`export-client`。typed 记录只声明 Snell 自身字段：v6 PSK 为 12–255 字节，用户列表允许 0–128 个唯一 `name`/`userkey`；v5 只允许 `none`/`http` obfs 并保留可选 `obfs_host`，v6 使用 `default`/`unshaped`/`unsafe-raw` shaping。客户端按 v5 入站→v4 出站、v6→v6 映射，逐用户导出完整 JSON；Snell 没有无损标准 URI，不执行 SubMan 同步。

新增 `tests/snell_instance_lifecycle.sh`，覆盖 v5/v6 字段边界、PSK/user-key、CAS stale write、删除 tombstone、接管/重建、Agent 脱敏及 no-URI warning；配置 `SINGBOX_BINARY_114` 时同时对服务端 candidate 与客户端 outbound 执行目标核心 `check`。本阶段本地专项测试通过；Docker 默认门禁将继续运行既有场景，尚未新增 Snell 专属真实数据面探针。容器/回环/静态检查不代表独立 UDP payload、公网、生产或真实 SubMan 证据；本阶段未执行生产操作、推送或外部同步。全协议目标继续未完成。

## 2026-09-08：Hysteria2 结构化实例管理链路（阶段交付）

从 AnyTLS 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 核对 Hysteria2 入站的 `users`、TLS、独立 `up_mbps`/`down_mbps`、salamander obfs 与 masquerade 字段；typed 路径固定使用手工 TLS，避免把 ACME/provider 语义压扁。

本阶段将项目 ID `hy2` 接入共享 schema 2 marker + schema 1 JSON store、实例 CAS 事务、监听资源、接管/重建、菜单 25、Agent `nodes`/`links`/`export-client` 和逐用户客户端 outbound。记录严格限定 1–128 个唯一用户、手工 TLS、可独立设置的上下行带宽、salamander obfs 与有限 masquerade；客户端按证书算法发出 Ed25519 兼容性 warning，不输出私钥。旧 Hysteria2 schema 1 仍保留 ACME/provider 路径；重复 legacy 入站继续阻断，只有活动 typed store 才允许结构化多实例。

新增 `tests/structured_hy2_instance_management.sh`，覆盖 schema/字段边界、独立带宽渲染、重复入站判定、重建/接管、Agent 链接、Ed25519 与部分选项 warning、逐用户 Hysteria2 URI/client outbound 和 mock SubMan 同步。最终 `VERIFY_SKIP_LOCAL_TESTS=1 bash dev/verification/run.sh` 运行目录为 `dev/verification-runs/20260908200118`：Docker 14/14 场景成功，包含旧 Hysteria2 共存/接管路径；此前本地门禁也通过（当前环境未配置 `SINGBOX_BINARY_113`/`SINGBOX_BINARY_114`，核心依赖项按测试契约 skip）。容器 QUIC/TCP 回环和静态/mock SubMan 不代表独立 UDP payload、公网、生产或真实 SubMan 证据；本阶段未执行生产操作、推送或外部同步。全协议目标继续未完成。

## 2026-09-08：普通 VLESS 管理链路接入（阶段交付）

从 VMess 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 的 VLESS 文档确认普通 VLESS outbound 需要 `server`、`server_port`、`uuid`，可选 `flow`、`network`、TLS 和 transport；项目仍固定验证 sing-box `1.13.18` 与 `1.14.0`。

本阶段接入第十个 `vless-plain` 预设，保留 `normalize_protocol_id vless` → `vless-reality` 的旧 alias。普通 VLESS 使用独立 schema 2 marker、schema 1 JSON 实例库和实例 CAS 事务，支持 1–128 个用户、按用户 `flow`、TLS `client_trust`、none/http/ws/grpc/quic typed transport、监听资源计划、接管/重建、菜单 10/23、Agent 节点/分享、裸核客户端导出和 SubMan 逐实例逐用户同步。未知字段、HTTPUpgrade、WS early data、服务器私钥输出和无法由 URI 无损表达的条目均 fail closed；SubMan 与真实外部 API 的同步仍未执行。

新增专项门禁：`vless_plain_structured_instance_store.sh`、`vless_plain_instance_lifecycle.sh`、`vless_plain_export_runtime.sh`、`vless_plain_agent_share.sh`、`subman_vless_plain_sync.sh`、`verification_protocol_probe_vless_plain.sh` 以及 `fresh_install_vless_plain` Docker 场景。专项测试覆盖实例 revision stale-write/delete/recreate、TLS/transport/flow 校验、两核心客户端/服务端 `check`、VLESS URI 特殊字段、凭据脱敏、SubMan `synced=3/skipped=2`、普通 VLESS 与 REALITY 的 live discriminator，以及安装后的真实回环 TCP 探针。最终本地门禁运行目录为 `dev/verification-runs/20260908141403`，以两版官方 ARM64 核心通过 108/108 项；最终 Docker 运行目录为 `dev/verification-runs/20260908144031`，15/15 场景 `STATUS=success`、22/22 协议探针 `RESULT=success`，包含普通 VLESS 新装、十协议共存和升级成功/回滚产物。SubMan 仍为 mock，不把静态配置、容器回环或 mock API 当作生产/公网证据。

## 2026-09-08：AnyTLS 结构化实例管理链路（阶段交付）

从普通 VLESS 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 核对 AnyTLS inbound/outbound 的 `users`、TLS 和 `client_metadata` 字段；客户端的 `tls.certificate` 只嵌入公开 PEM，不读取服务器私钥。

本阶段把 AnyTLS 接入共享 schema 2 marker + schema 1 JSON store、实例 CAS 事务、监听资源、重建/接管、菜单 24、Agent `nodes`/`links`/`export-client` 和逐用户客户端 outbound。typed 记录严格限定 1–128 个用户名/密码、启用的手工 `server_name`/证书/私钥路径及 `client_trust` (`certificate`/`system`)；没有标准分享 URI 时返回 `anytls_standard_uri_unavailable`，凭据只出现在受保护的 outbound JSON。为避免丢失 ACME/provider 语义，legacy AnyTLS 继续使用 schema 1 路径，结构化接管对无法无损表达的 provider/ACME 配置 fail closed 并保留原状态。

新增 `tests/anytls_structured_instance_store.sh`、`anytls_instance_lifecycle.sh`、`anytls_agent_share.sh` 和 `anytls_export_runtime.sh`，并扩展 registry/capability、旧 AnyTLS loader、Agent 清单、重建与菜单回归。无本地核心时 runtime 测试显式 skip；配置了官方 1.13.18/1.14.0 核心时会执行服务端/客户端 `sing-box check`。SubMan 不为 AnyTLS 生成或执行同步请求；本阶段证据仍是本地/mock/容器回环，不代表公网、生产或真实 SubMan 结果。全协议目标继续未完成。

## 2026-09-08：VMess 管理链路接入（阶段交付）

从 Trojan 与 V2Ray transport 阶段继续原始完整目标；保留未跟踪文件 `1`、`2`，未读取或修改。Context7 `/sagernet/sing-box` 与固定 1.14.0 源码确认 VMess 入站用户字段为 `name`、UUID、`alterId`，出站安全枚举为 `auto`、`none`、`zero`、`aes-128-cfb`、`aes-128-gcm`、`chacha20-poly1305`；项目同时保留 1.13.18 ARM64 核心兼容检查。

本阶段接入第九个 `vmess` 预设，不改变旧 `vless` → `vless-reality` alias。VMess 复用结构化 schema 1 store、schema 2 active marker、CAS 实例事务、监听资源计划、接管/重建、菜单 22、Agent 节点/分享/导出和 SubMan 逐实例逐用户路径。每个实例显式建模 1–128 个唯一用户、`security`、`alter_id`、TLS 信任和 none/http/ws/grpc/quic typed transport；不透传 unknown fields、WS early data 或 HTTPUpgrade。导出生成逐用户完整 VMess outbound 与标准 `vmess://` JSON，禁止读取或输出服务器私钥；SubMan 只接受 TLS 系统信任且 URI 无损可表达的条目，其他组合保留稳定 skip code/count。

新增 `tests/vmess_structured_instance_store.sh`、`vmess_structured_takeover.sh`、`vmess_instance_lifecycle.sh`、`vmess_agent_share.sh`、`subman_vmess_sync.sh`、`verification_protocol_probe_vmess.sh` 和 `vmess_export_runtime.sh`，并把协议注册表、旧 Bash、transport、Agent、live inventory 与验证场景映射纳入回归。定向测试覆盖三实例、TLS certificate/system trust、五类 transport、用户 UUID/安全/alterId 校验、接管身份保留、revision stale-write、删除 tombstone/recreate、Agent credential-free nodes、逐用户链接/导出、URI 头部 fail-closed、SubMan `synced=3/skipped=1` 以及 probe-only public certificate。

固定 ARM64 核心的本地 runtime fixture 在 1.13.18 与 1.14.0 均通过 VMess none/http/ws/grpc/quic 两用户服务端和客户端 `sing-box check`；没有配置核心时测试明确 skip，不把静态 JSON 当作业务证据。当前 focused local tests、Bash 语法与 diff 检查通过；SubMan 仍为 mock，尚未执行真实 API。Docker 门禁已完成，运行目录为 `dev/verification-runs/20260908110530`（退出 0）：14/14 场景 `STATUS=success`、21/21 协议探针 `RESULT=success`，其中 `fresh_install_vmess` 含核心 check、受管 VMess store、监听采集和真实回环 TCP 探针；同一运行还覆盖九协议共存及升级成功/回滚产物。普通 VLESS、Naive、Hysteria、ShadowTLS、Tuic、端点和高层控制面仍按矩阵推进；Snell 已在本记录顶部单独接入，但尚未纳入该历史 Docker 探针。

## 2026-09-08：Trojan 管理链路接入（阶段交付）

从已审查的 `2543462` 继续原始完整目标，重新读取原始需求与工作区；既有未跟踪 `1`、`2` 不读取、不修改。基线 `bash dev/verification/run.sh` 在 `20260908065918` 为 local 空变更门禁通过，不等同全回归。固定 HEAD 的既有回归另在私有 archive 快照执行；后续记录区分该基线与最终工作区验收。

重新读取 GitHub `releases/latest`：稳定版仍为 `v1.14.0`，非 draft/prerelease，保留官方 ARM64 `1.13.18` 兼容验证。Context7 resolve/query `/sagernet/sing-box` 返回 testing 分支 Trojan 文档，因此继续核对固定 `v1.14.0` 的 `option/trojan.go`、入站/出站文档和 `protocol/trojan/inbound.go`。后者确认 TLS 是独立可选层，外层 socket 由 transport 决定：原生 TCP、QUIC UDP；不能把 registry 中的可选监听集合直接当作每个实例同时使用的网络。

本阶段接入第八个预设 Trojan，不改变旧 `vless` → `vless-reality` alias。复用结构化 store、marker、CAS 写锁、资源账本、持久事务、回滚、菜单和 Agent；多用户认证与 TLS/transport 各自建模，不透传 fallback、multiplex 或未知字段。沿用上一阶段两个已复现的 runtime guard：HTTPUpgrade、WS early data 不作为支持项。完整目标仍包含后续协议和高级角色，不能以此增量替代。

固定 HEAD `2543462f28012dc57037ae3d7b6e0a72cd7a8640` 的 archive 快照 `/tmp/sbv-trojan-baseline.vgP8YZ` 已执行用户指定的 13 项既有事务、接管、导出、Agent 与升级回归，均退出 0。去重结果 `/tmp/sbv-trojan-baseline-results.YPlPWE/status.unique.tsv`；原执行日志因观察返回后重复调度了后五项而含重复行，不将重复行当作新增覆盖。该证据只属于旧 HEAD 基线，不替代新 Trojan 工作区验证。

只读审阅当前 SubMan `docs/api/openapi.yaml`、`src/lib/client-export/trojan.ts` 和 `common.ts` 后明确：API 接受 `type:trojan` 的 URI，但 parser 的 TLS 默认始终启用，且不能承载自定义证书信任、任意 headers 或 transport timeout。因此新增 `client_trust` 显式区分 `certificate` 与 `system`：默认手工 TLS 使用公开证书信任导出；只有显式系统信任且 URI 字段可无损表达时才分享/同步。明文、证书信任或不能保真的组合返回逐项 warning/skipped，不以改成 insecure 绕过。SubMan 测试仅 mock 契约，不访问真实 API、不改 SubMan 仓库。

阶段检查：真实 SubMan parser（当前本地只读源码）对五种传输 × IPv4/IPv6 的十组 URI 与受管 outbound 逐字段往返比较通过，Unicode/特殊字符/尾换行凭据保真；解析后十份完整候选分别通过两版官方核心 `check`。证据 `/tmp/sbv-trojan-subman-roundtrip.ciA8v0`，不等同真实 SubMan API 同步或公网业务。首次集成门禁 `20260908073435` 在注册表 capability 接入断言处退出 1，未进入 Docker。另定位并修复中的问题包括原生入站被 jq `empty` 删除、QUIC outbound 错误限制业务为 UDP、单实例字段排序误拒绝、Agent 白名单/清单遗漏、单用户 URI 超限影响同实例其他用户。中途源码持续变化，不将阶段结果冒称最终冻结验收。

真实受管 runtime 首轮在原生明文 Trojan 上失败，证据 `/tmp/sbv-trojan-export-failure.ClX4YZ`：1.13.18 `check` 通过，但 outbound 显式 `tls:{enabled:false}` 仍构造 TLS dialer，连接触发 nil config panic。固定 1.14.0 `protocol/trojan/outbound.go` 同样以 TLS 指针非空为条件构造 dialer。修正为明文 outbound 完全省略 TLS，不将明文功能误判为不可支持。`/tmp/sbv-trojan-runtime-parent113b.log` 随后完成九实例、十用户的 10 TCP + 10 UDP、错误密码与错误 SNI 拒绝；这属于原生 Bash 1.13.18 阶段证据，最终 Shell/核心矩阵及 Docker 结果待后续记录。

实际 Bash 4.2.53 直接执行同一 runtime 测试也在两版核心分别通过 10 TCP + 10 UDP、错误认证与错误 SNI 拒绝：`/tmp/sbv-trojan-export-bash42-113.9OaIHi`、`/tmp/sbv-trojan-export-bash42-114.A8egMT`。测试哈希 `629bf408fcd7bc8cccc85789aa5c960a5357de18134f9ffb3beb156fb7d8b55f`；运行时主线程仍补充接管字段边界、SubMan 失败计数、主菜单与通用编辑/删除入口，因此这两组不是全脚本冻结证据。每组起止 hash、命令、退出码均单独保留，数据路径测试未绕过受管导出器，也未使用 insecure。

后续父线程确认原生 Bash 两版受管 runtime 均退出 0：`/tmp/sbv-trojan-runtime-parent113b.log`、`/tmp/sbv-trojan-runtime-parent114.log`，每版九实例、十用户、10 TCP + 10 UDP，并拒绝错误认证和错误 SNI。实际 SubMan parser 最终阶段复跑 `/tmp/sbv-trojan-subman-roundtrip.H91xR5` 仍为十组往返比较及两核心共二十次 check 通过，起止源码 `e4fa7c743…` 相同。此后仅放宽核心确认合法的用户名冒号、补齐提示与汇总边界，未修改传输导出数据路径。

冻结 `ebab73f8e63cfa2ab6e27342a7972ce94ba091a052905e82f0fb2979f391b4e3` 后另复跑实际 Bash 4.2 双核心 runtime：`/tmp/sbv-trojan-export-frozen-bash42-113.po8ory`、`/tmp/sbv-trojan-export-frozen-bash42-114.imfWDt`，两组起止哈希一致且各 10 TCP + 10 UDP 全部通过。后续预审又发现并修复 Agent 全用户跳过时错误返回 `public_ip_unavailable` 和 help 遗漏 Trojan；因此这两组是数据路径冻结证据，不冒称最后整份源码哈希。父线程的 Bash 4.2 生命周期 1.13.18 校验 `/tmp/sbv-trojan-lifecycle-final-bash42-113.log` 通过，包含 16 次模拟 systemctl restart 与真实 core check；不把模拟重启算成真实服务数据路径。

第二轮完整门禁 `20260908074718` 在旧 V2Ray 注册顺序断言退出 1，未进入 Docker。修正该测试及 Agent capabilities 的相同顺序断言后启动第三轮 `20260908080643`。预审发现的交互 SubMan 逐用户计数遗漏已经修正；`tests/subman_trojan_sync.sh` 的本地 mock 回归覆盖同实例 1 同步/1 超限跳过、全部 8 用户 certificate 跳过，以及交互 4 同步/4 跳过和 Agent 保留结构化 warnings。未访问真实 SubMan API。最终门禁与提交审查结果待后续记录。

最终运行时代码 SHA-256 暂冻结为 `5cc640772851d2aa2e542adecda82ed5dd3cc0df220b5f146e481e1a9a633827`。第三轮门禁的 Trojan native runtime 在该版本分别通过两核心 10 TCP + 10 UDP、严格信任和错误认证/SNI 拒绝；新 Agent/share、菜单、状态及接管检查亦通过。实际 Bash 4.2 的 Agent/share、SubMan、菜单分别在 `/tmp/sbv-trojan-agent-final-bash42b.log`、`/tmp/sbv-trojan-subman-final-bash42.log`、`/tmp/sbv-trojan-menu-final-bash42.log` 退出 0。Bash 4.2 分享测试曾因嵌套 here-string 中再执行使用 here-string 的 API 而失败，最小复现 `jq -R . <<< "$(protocol_registry_field trojan agent_id)"` 会使旧 Bash 的 `read -a` 丢失字段；改成先赋值、再交给断言后通过，未为测试放松产品状态校验。

第三轮完整门禁通过前 49 项后，在第 50 项旧 live inventory 测试中发现过时的 `unknown=trojan` 夹具而退出 1，未执行容器阶段。该夹具最终改为核心合法、项目尚未注册的 VMess，保留原“上游支持不等于受管支持”的负例。第一次尾段补跑使用虚构类型时通过了管理拒绝断言、但未通过原有真实核心正向 check；第二次与测试文件编辑重叠出现解析错误，两次均不计成功，最终冻结后的尾段日志为 `/tmp/sbv-trojan-gate3-remaining3.log`。

容器部分单独以 `VERIFY_SKIP_LOCAL_TESTS=1` 执行原验证入口，`dev/verification-runs/20260908083120` 退出 0。父线程逐项检查 13/13 场景 `STATUS=success`、20/20 TCP 探针 `RESULT=success`，包含 Trojan TLS native 新装和 TLS QUIC 八协议共存；失败升级持久结果 `status=rolled_back`、`rollback.result=success`。直接读取运行容器 `09f3c14c99108…` 的 `/usr/local/bin/sbv`，其哈希与上述 `5cc640772…` 一致，保存在 `container-runtime.sha256`。这是完整 Docker 场景复跑，不是又一次完整本地门禁；未操作宿主防火墙、生产、真实 SubMan API 或公网 UDP 可达性。

冻结后的尾段 `/tmp/sbv-trojan-gate3-remaining3.log` 最终退出 0，逐项 `PASS` 为 46/46；与第三轮前 49 项合起来覆盖本轮选定的 95 项本地测试，不声称单次完整门禁或全部 95 项同一初始源码快照。最终运行时仍为 `5cc640772851d2aa2e542adecda82ed5dd3cc0df220b5f146e481e1a9a633827`，新增 Trojan 专项与 Docker 均已覆盖该版本；实际 Bash 4.2 分享、SubMan、菜单和状态测试也通过。独立最终预审没有确认的 P1/P2。当前工具没有原生 `/review` 执行入口，原子提交后使用独立审查员与父线程核对精确提交范围作为等效复审。版本本轮仅递增一次至 `2026090804`；完整全协议目标仍未完成，未 push 或部署，用户未跟踪 `1`、`2` 保留。

`5bccee1` 的立即提交复审未发现运行时代码 P1/P2，但发现 README 和 Agent 上层索引遗漏 Trojan、部分能力列表仍写七协议。随后仅补齐文档索引、公开 ID、命令示例、SubMan/导出边界与最新验证入口，运行时代码、上述哈希和版本不变；历史 Shadowsocks 阶段证据保留，不改写成 Trojan 证据。

## 2026-09-08：V2Ray 传输组合与真实数据路径基础

从 `4460aa1` 继续原始完整目标；工作树只有既有未跟踪文件 `1`、`2`，未读取或修改。基线 `bash dev/verification/run.sh` 的 `dev/verification-runs/20260908060621` 退出 0，为 local 空变更门禁，不代表全量回归。GitHub `releases/latest` 重新确认 `v1.14.0` 为 stable，非 draft/prerelease；本轮仍固定 1.13.18/1.14.0。Context7 首先 resolve/query `/sagernet/sing-box`，结果仅为 testing；随后按固定 tag 的 `option/v2ray_transport.go`、`transport/v2ray/transport.go` 和各 transport client/server 实现核对。1.13.18 与 1.14.0 的 WebSocket server 源码完全相同，transport option 差异主要为新增 schema 描述，未改变本轮字段。

为后续 VMess/Trojan/普通 VLESS 接入增加无副作用的 typed transport 验证与 profile 构造，版本仅递增一次至 `2026090803`。原生 TCP 不向核心输出虚构 transport type；实际 HTTP/WS/gRPC/HTTPUpgrade/QUIC 分别给出外层监听网络、TLS ALPN 和构建依赖。未知字段、原始 JSON 多根、头部注入/碰撞、无效时限及非法 security/flow 组合 fail closed，不写状态、不创建凭据、不申请证书。协议族 API 与旧 alias 分开，公开注册表及菜单保持七项；本阶段没有将普通 VLESS、VMess、Trojan 的完整管理链路标记为已实现。

源代码复核补上两个仅靠配置 check 不足以判定的边界：WS 在空 early-data header 时使用 RequestURI 对比未经编码的路径，故这类模式拒绝会被 URL 转义的路径字符，Unicode/空格需显式 header-based early data；HTTP `HEAD/CONNECT` 不用于共享字节隧道。HTTPUpgrade 的 headers 不冒称会被服务端回写；默认 lite gRPC 不实现的 `permit_without_stream:true` 显式拒绝。完整接口、管理子集及未来 handler 接入示例沿用现有 spec，不建立重复文档体系。

既有重点回归 18/18 通过（13 项事务/接管/升级/Agent/导出测试与 5 项 SubMan 测试），证据 `/tmp/sbv-v2ray-regressions.8Wws1F/results.tsv`；期间 profile 实现仍在修改，不能把该批称为冻结源码全量验证。最终门禁、真实连接、Bash 4.2 结果及审查在本节后续补充。无生产操作、真实 SubMan API 调用、push 或部署；完整目标保持进行中。

首次完整门禁 `dev/verification-runs/20260908062126` 在 V2Ray runtime 阶段退出 52，未开始 Docker；此前通过的局部测试不冒称整个门禁通过。父代理核对失败产物，纠正了早期 WS 夹具的两端路径不一致（server `/ws`、client `/ws path/测试`），不能据此认定 Unicode/header-based early data 不可用。最终测试让两端读取同一冻结 profile，并显式比较传输、ALPN，真实 WS Unicode/空格 TCP/UDP 已在 1.14 验证。另一个审查推断认为指数/小数写法的整数 early-data 值不被 Go 接受；父代理用两版实际核心确认 `1e3/1.0/1E+3` 均 check 成功、`1.5` 被拒绝，因此按数值整数验证，不基于标准库推断扩大拒绝范围。

HTTPUpgrade 失败并非 WS 夹具问题：匹配配置下，父代理分别在 1.14.0 的 Trojan TLS TCP（`/tmp/sbv-v2ray-transport-failure.6sU25V`）、1.13.18 的 Trojan 明文 TCP（`/tmp/sbv-v2ray-transport-failure.s3NtGW`）复现；完整门禁另在 VMess 明文 TCP 复现（`/tmp/sbv-v2ray-transport-failure.R35Wvh`），先前 VLESS UDP 还有 `unknown version:17`。源码 `httpupgrade/server.go` 在两版完全相同，丢弃 hijack reader 与握手字节丢失现象相符，但这里只作为根因推断。未修改或替换官方核心来掩盖问题，也未把失败用例静默删除。

因此分开 inspect 与 build：inspect 保留所有六类结构并返回 HTTPUpgrade 的 `runtime_guard.status=blocked/code=httpupgrade_runtime_unreliable`，普通 build 阻止该类型输出；独立 `--diagnose-httpupgrade` 继续保留六组合真实复现。常规 runtime 仅对其余 27 个组合分别统计 TCP/UDP，另外六项明确 BLOCKED，不计通过；HTTPUpgrade 的实际交付仍是完整目标未完成项。最终源码冻结哈希为 `37cb5df80a955edffcf10d90e6efe1f88fe11a7932a7f486bf09861c5c304d79`，第二轮完整门禁为 `dev/verification-runs/20260908063625`，最终结果见后续记录。

后续四组验证 `/tmp/sbv-v2ray-runtime-final3.44WLAT` 的首次 native 1.13.18 出现 VMess/WS 明文响应 `cipher: message authentication failed`，诊断 `/tmp/sbv-v2ray-transport-failure.Hp2M9n`。父代理确认 UUID、端口、两侧 transport 完全一致，服务端已经认证并转发，不能误报为初始 UUID 认证失败。其余三组与重跑通过不消除该失败。源码复核确认 WS 客户端复制握手缓存时把 `buf.NewSize` 的初始零 Len 作为读取长度，导致已有缓存字节丢失。两版均存在该代码路径，故所有协议族/安全模式的 WS early data 均阻断普通 build；inspect 保留原始字段和固定错误分类。无 early data 的 WS 单独验证，新增六项 BLOCKED 不计为业务通过。第二轮门禁为此前 `37cb…` 源码，不能作为此补修的最终源码验收；最终运行时 SHA-256 改为 `158f8d8d583d241fa728cddba43c5f41f10f2e3d447c7e8617059ffd3739a3d3`。

补修证据：`/tmp/sbv-v2ray-ws-repro-run2.d4xmt1` 使用原失败配置生成同侧匹配的隔离 VMess WS 对照，不加载项目 builder 来绕过 guard。每组固定 200 请求、没有失败重试：1.13.18/1.14.0 无 early data 均 200/200 成功；ASCII + early data 分别 85/92 次失败；Unicode + early data 分别 114/105 次失败。父代理检查复现脚本、结果与两侧 transport 一致性；该复现证明问题并非仅 Unicode 路径。它不是最终受管协议支持测试。

补修后的 native Bash 5 与实际 Bash 4.2 contract 均通过；两种 Shell 直接执行两版核心 runtime，每组 40 profile 检查、27 TCP + 27 UDP payload、错误认证/错误 SNI 各 1 项拒绝；HTTPUpgrade 6 项及 WS early data 6 项单列 BLOCKED。Bash 4.2 的命令、日志与起止冻结 hash 为 `/tmp/sbv-v2ray-final-check.nrsL3m`，不是由旧 Bash 再启动新 Bash 的间接验证。注册表和 Agent 文档覆盖复验通过。此前完整门禁 `20260908063625` 的 85 项本地检查、12/12 Docker 场景、18/18 既有 TCP 探针全部通过，故障升级结果 `rolled_back/success`；它属于补修前快照。补修最终源码另外运行 `VERIFY_SKIP_LOCAL_TESTS=1 bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh`，run 为 `20260908065337`，明确只重跑 Docker，不冒称重新执行全部 85 项本地门禁。容器中实际脚本 hash 已读取并保存为该 run 的 `container-runtime.sha256`，与 `158f8d8d…` 一致。

最终 Docker 补验 `20260908065337` 退出 0、`remote_status=success`：12/12 场景、18/18 既有 TCP 业务探针成功，故障升级 `status=rolled_back`、`rollback.result=success`。本次 Docker 证明现有七预设回归，不是新 V2Ray 协议生命周期或公网/生产验收。最终差异独立预审无新增 P1/P2；无生产访问、push、部署或真实 SubMan 同步，原未跟踪文件 `1`、`2` 保留。全协议目标保持未完成。

## 2026-09-08：Shadowsocks 实例管理、分享与客户端集成

从 `35e98db` 继续，基线 `dev/verification-runs/20260908045421` 是 local 空变更门禁，退出 0；不是新的全量基线。版本本轮仅递增一次至 `2026090802`。再次读取 GitHub `releases/latest`：稳定目标仍为 `v1.14.0`（非 draft/prerelease，2026-08-31 发布）。Context7 先查询 sing-box 和 Shadowsocks 文档；前者仅提供 testing，随后使用固定 `v1.14.0` 源码和两版官方 ARM64 核心确认行为。SIP002 依据 [官方规范](https://github.com/shadowsocks/shadowsocks-org/blob/main/docs/doc/sip002.md)，经典方法使用 URL-safe Base64 userinfo，2022 使用百分号编码而非 Base64 userinfo。

第七预设 `shadowsocks`（别名 `ss`）接入状态、typed record、菜单、Agent CAS 事务、接管/健康比较、默认实例/删除/恢复、实例网络资源、逐用户客户端与分享。九种入站方法覆盖 `none`、五种经典 AEAD 与三种 2022；多用户限核心支持的方法，不提供 relay/mux/plugin 透传。严格拒绝未知字段和不完整凭据；默认回环，公网入口需确认。注册表同时输出同源 `features` 与兼容 `legacy_capabilities`，修复此前网络 planner 读取真实注册表时看不到实例选择能力的问题。IPv4-mapped dotted listen 保留原文，冲突规划按等价 IPv4 判断。

真实核心揭示 2022 PSK 的服务端/客户端不对称：入站依赖 `sing-shadowsocks v0.2.8` 接受超过最小长度的 key，出站依赖 `sing-shadowsocks2 v0.2.1` 要求定长。AES-128 server 16 bytes/user 32 bytes 在两核心 inbound check 均成功，原样客户端 check 均失败。按固定 [v0.2.8 Key 实现](https://github.com/SagerNet/sing-shadowsocks/blob/v0.2.8/shadowaead_2022/protocol.go) 对长 key 执行 SHA-256 并截取 16/32 bytes，导出等效凭据而不改原始 store；真实 TCP/UDP 已验证一致。另修复经典密码末尾 LF 被 Shell 截断的问题，经典分支直接保留 JSON；全实例导出缓冲完成后才输出，失败不返回半份连接材料。

SubMan 使用同一 validated snapshot 产生用户身份、监听地址、凭据及稳定外部键，避免并发重排配错用户。只读核对本机 SubMan OpenAPI 的 `ss` 类型和 parser：双网络加密项可同步，单网络无法由 SIP002 保真，`none` 空密码不被现有 parser 接受，均明确 skipped。测试只有 mock API，并未访问真实 SubMan。长 PSK、单网络及明文边界提供机器可读 warning；日志安全的 Agent nodes 不泄露密钥。

预审修复还包括加密入口不误称明文、菜单端口预检不阻止同端口不同传输、用户数量防算术溢出、临时快照信号清理和 full JSON `none` 明文 warning。完整冻结验收结果在本节后续记录；此前各 worker 的中间哈希和运行不能代替最终源码门禁。全协议目标仍未完成，未 push/部署/操作生产或宿主机防火墙。

冻结运行时 SHA-256：`6a2e211f1d8c7918cda838ec883038911e2e03e02933b3c8cd4c1122be82e506`。实际 Bash 4.2 直接执行 runtime 的 `--run` 分支，1.13.18/1.14.0 均退出 0，每版 9 方法 check、8 outbounds、6 用户认证业务、7 TCP/7 UDP payload、同端口分传输 2 项、错误认证拒绝 1 项；开始/结束源码哈希相同，证据 `/tmp/shadowsocks-runtime-logs/final-6a2e211/`。这是本机回环证据，不证明公网 UDP、防火墙可达或生产部署。

Bash 4.2 focused 首跑中 export test 失败，不能忽略：`wrapper_json=$(jq ... <<< "$(builder ...)")` 的嵌套命令替换触发旧 Bash 临时 IFS 行为，使注册行未按 `|` 拆分。直接读取全部七条注册记录正常，故没有通过给 `fields[20]` 填默认值掩盖问题。测试改为先捕获 builder、再交给 jq，并增加真实产品 dispatcher 路径断言；实际 Bash 4.2 重跑通过，产品源码未变。失败记录在 `/tmp/shadowsocks-runtime-logs/focused-6a2e211/`，修复后双核心 export check 在 `/tmp/sbv-ss-bash42-norun113.1BKp4P/` 与 `/tmp/sbv-ss-bash42-norun114.XltujE/`。其余 focused、SubMan mock 和协议探针测试首跑均通过。

最终验收与重跑边界：

- 默认门禁 `dev/verification-runs/20260908053115` 选择 85 项本地检查，但在旧 `agent_upgrade_commands.sh` 六协议断言处退出 1，未进入 Docker；其中 SS 生命周期（16 次服务重启、真实 core check）、菜单、两核 export/runtime、Agent 与 SubMan 专项已经通过。后续不把该失败 run 宣称为 85/85。
- 普通测试清单共 182 项：首批 173 项在 `6a2e211…` 下完成，168 通过、5 失败；其中四项为旧六协议/未知协议 fixture，修正后独立复跑 4/4 通过。遗漏的 9 项新增测试另行补跑 9/9 通过。证据 `/tmp/sbv-socks-all.3e6PHj/` 保留原始失败、recheck、additional manifest 与阶段哈希。验证框架自身 16/16 串行通过，目录 `/tmp/sbv-verification-all.kEARBq/`。
- 第五项 `subman_sync_orchestration.sh` 发现真实提示回归：全局 skipped 计数会遮住旧协议的空公网 IP 诊断。仅两处 orchestration 新增 Shadowsocks 专用 skipped 计数，使 SS 保真性跳过保留明确结果，旧协议仍返回原无 IP 诊断。最终源码 SHA-256 为 `8d24fa6ef0746668210ac96335e5897ee3128fbc4d446e6e7fdfbb5905a6490b`，版本仍为本轮 `2026090802`。父线程冻结后独立复跑 SubMan orchestration、SS SubMan、SS Agent/share 与 Agent upgrade，4/4 通过，日志和起止哈希 `/tmp/sbv-ss-parent-final.3YqLFx/`。此前一次父测试与测试文件编辑重叠的语法失败已废弃，不作为冻结验证证据。局部修复后未冒称再次完整执行全部 182 项。
- Docker 采用 `VERIFY_SKIP_LOCAL_TESTS=1` 重跑容器部分，两个 run `20260908054547`（修复前）和 `20260908055118`（最终源码）均退出 0。最终 run 逐个回读 12/12 场景 `STATUS=success`、18/18 TCP 探针 `RESULT=success`，包含 SS 新装与七协议共存；升级故障 `status=rolled_back`、`rollback.result=success`。运行容器 `9824f895737b` 内实际脚本 SHA 与最终源码一致，证据 `container-runtime.sha256`。这不是新一轮完整本地门禁。
- 最终源码再次执行 native/Bash 4.2 × 1.13.18/1.14.0 四组 SS runtime，全部退出 0；每组 9 方法 check、8 exports、6 用户认证业务、7 TCP、7 UDP、2 个分网络案例及 1 个错误认证拒绝。`/tmp/shadowsocks-runtime-logs/final-8d24fa6/` 的四组 command/status/start.sha256/end.sha256 均已核对。仅回环与隔离 Docker 证据，未做真实 SubMan 同步、生产部署或公网 UDP 可达验证。

地址接管仍为明确的类型化子集：支持 IPv4、纯十六进制 IPv6 和 `::ffff:IPv4`；完整展开的 dotted IPv6 如 `0:0:0:0:0:ffff:192.0.2.1` 安全拒绝并保留原配置，未将这一覆盖限制称为无损支持全部地址文本。全协议目标继续保持未完成。

## 2026-09-08：保留防火墙开放链路的实例网络选择

从 `607b0c8` 继续，基线 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260908042949` 为 local 空变更门禁、退出 0。核对 Shadowsocks 接入点时发现 `open_all_protocol_ports` 将完整资源计划缩减为 protocol/port，随后 `open_firewall_port` 重新展开注册默认网络，未来单 TCP/UDP 实例会因此多开另一传输。先单独修复这个已确认问题；认证模型草稿未注册或交付，不将资源修复称为 Shadowsocks 支持。

版本统一递增为 `2026090801`。开放链路保留 transport，去重同协议、同端口、同传输的所有监听地址；双参数函数调用保持默认网络兼容。显式选择必须是注册能力内的单个 TCP/UDP，在任何后端调用前拒绝空值、列表、未知值与能力扩张。后端失败仍保留原退出码及部分外部变更提示。扩展现有 `tests/firewall_listener_references.sh`，仅注入测试专属双网络元数据及 mock 后端，覆盖仅 TCP/UDP 开放和清理、同端口双传输保留、重复所有者去重、旧调用、无效选择和完整计划拒绝；不触碰开发机真实防火墙。

定向执行 `bash -n install.sh tests/firewall_listener_references.sh`、`bash tests/firewall_listener_references.sh`、`bash tests/system_safety_guards.sh` 均退出 0；实际 Bash 4.2 直接运行防火墙测试也通过。冻结运行时 SHA-256 为 `93fbfe31df46d261c492c426b7a00698450a8540617a6b803c17f9ed35ab361d`。完整执行 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/remote/entrypoint.sh`，使用官方 ARM64 1.13.18/1.14.0，本地测试未跳过；`dev/verification-runs/20260908044028` 退出 0、`remote_status=success`，76 项本地门禁、11/11 Docker 场景及 16/16 既有协议 TCP 业务探针成功，故障升级 `status=rolled_back`、`rollback.result=success`。直接读取容器 `502c6e22cd10` 的两份实际脚本，哈希均与冻结源码一致，保存于 run 的 `container-runtime.sha256`。防火墙新增选择分支由 mock 后端验证，Docker 证明现有六协议无该回归，不冒称新 Shadowsocks 业务或真实主机防火墙覆盖。未 push、未部署、未访问生产或执行真实 SubMan 同步；全协议目标保持未完成。

## 2026-09-08：Shadowsocks 接入前的监听网络契约

上一轮 `e948653` 完成 HTTP 增量；本轮起点仅保留原有未跟踪 `1`、`2`，基线 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260908035714` 为 local 空变更门禁、退出 0，不冒称新的全量基线。GitHub stable 再次确认 `v1.14.0`。Context7 `/sagernet/sing-box` 仍只返回 testing Shadowsocks 文档，随后读取固定 `v1.14.0` 的 `docs/configuration/{inbound,outbound}/shadowsocks.md`、`protocol/shadowsocks/{inbound,inbound_multi}.go` 与 `option/types.go`。后者明确 NetworkList 同时接受字符串/数组，空数组与 null 落到默认 TCP+UDP；空字符串会因 unknown network 失败。这一差异不能仅凭文档“empty”一词猜测。

接入 Shadowsocks 前发现共享资源计划只展开协议级 `listen_networks`，无法表达同端口分别仅 TCP/仅 UDP 的实例。版本统一递增为 `2026090800`，增加受注册能力开关控制的选择契约；同时拒绝空/重复/畸形监听元数据，避免成功却漏报资源。旧六协议没有被偷偷赋予新网络选项，Shadowsocks 仍未进入公开注册表。后续完整接入须继续实现方法/2022 密钥、多用户、实例状态、事务、菜单、Agent、导出/SubMan 与 TCP/UDP 业务路径，不能以本次资源层工作代替这些要求。

新增 `tests/listener_network_selection.sh` 并纳入默认门禁，覆盖未知协议保护、可选网络、非法输入脱敏、能力门控、畸形元数据与同端口异传输不冲突。测试仅注入局部 Shadowsocks 元数据；固定 ARM64 官方 1.13.18/1.14.0 分别执行 6 组真实 check/start，与核心 PID 持有的 TCP/UDP socket inode 对照。原生连续三轮和实际 Bash 4.2 均通过 22 个拒绝场景、12 次 check、12 次启动。它证明监听资源投影，不证明 Shadowsocks 业务交付或生命周期。

首轮门禁 `dev/verification-runs/20260908040414` 的新测试报告核心退出 1；复核发现启动时用临时 bind 判断占用存在抢占核心端口的竞态。改为只读 `/proc/<pid>/fd` 与网络表的 inode 关联后消除探测干扰，不把其他进程占用误当成目标核心。该失败不计成功；运行时源码始终为 SHA-256 `64f6ce51d26830119bf7f2b219de7104d7b9b196bd7def9bd99c14bfc16b6c3d`。

修正后完整执行 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/remote/entrypoint.sh`，未跳过本地测试；`dev/verification-runs/20260908040724` 退出 0，76 项本地门禁、11/11 Docker 场景和 16/16 既有协议 TCP 业务探针均通过。故障升级为 `status=rolled_back`、`rollback.result=success`。直接读取运行容器 `08faaf038ac0` 中的脚本，哈希与上述冻结源码相同，记录于 run 的 `container-runtime.sha256`。独立新测试日志保存在 `/tmp/sbv-listener-network-final.Ct9Ou1/{native,bash42}.log`，源码和测试文件的起止哈希一致。这不新增 Shadowsocks 业务/生命周期验证状态；未 push、未部署或访问生产。

`41c0aa9` 提交后等效审查的定向重跑再次出现核心退出 1，故未直接交付。保留的 `/tmp/tmp.Zd9UKu3zYT/core.log` 明确为 `start service: context canceled`：socket 已存在但 `Box.Start` 尚未结束，测试的停止信号打断了启动。修正仅涉及测试：等待核心完整 `sing-box started` 标记后再观察 PID socket 并停止，失败时保留私有测试目录；不把“socket 存在”当成初始化已完成。随后原生连续 5 轮（共 60 次核心 check/start）与实际 Bash 4.2 的 12 次 check/start 均通过；默认验证入口 `dev/verification-runs/20260908042346` 为 local、退出 0，不冒称重复执行了完整门禁。运行时代码、版本及上述 Docker 被测哈希未改变，同轮修正不再次递增版本。

`aba8880` 修正后的等效审查与两核心测试通过；继续复核异步启动顺序，补充在父进程中预先清空日志，防止子进程尚未执行重定向时误读上一进程的启动标记。最终隔离版本又通过原生连续 3 轮和实际 Bash 4.2 检查，每轮 22 个拒绝场景、12 次真实核心 check/start。两次后续修正均只涉及测试与本记录，没有改变资源计划运行时代码。

## 2026-09-07：独立 HTTP 与入口 TLS 接入

本轮从 `fe26417` 继续完整目标，重新读取需求、当前工作树和矩阵；基线 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260907135121` 退出 0，但因仅有原有未跟踪文件而为 local 空变更门禁，不能冒称全量基线回归。GitHub `releases/latest` 再次确认稳定版为 `v1.14.0`、非 draft/prerelease。Context7 `/sagernet/sing-box` 仅提供 testing HTTP 文档，随后读取固定 tag `protocol/http/{inbound,outbound}.go` 和对应配置文档：入口有可选 TLS，客户端为 TCP-only HTTP CONNECT，不能替换成 SOCKS 或宣称普通 HTTP outbound 支持 UDP。

版本统一递增为 `2026090711`。HTTP 作为第六个独立预设接入共享实例状态、事务和资源计划；保留旧别名和 Mixed/SOCKS 数据格式。HTTP 记录显式区分明文与手工证书 TLS，支持实例身份、认证、出站策略及证书引用；未建模字段在接管时拒绝有损重建。此阶段不申请 ACME 证书、不改变真实外部账户、不同步 SubMan；本地 OpenAPI `NodeType` 仍无 HTTP 类型，不伪装为 `other`。

提交前复核修复了共享路由候选中的缺失规则插入顺序：已有托管规则原位更新，缺失 sniff 置前，而缺失 direct/Warp fallback 置后，保留自定义条件及 reject 的优先级，回归同时覆盖已有与新增实例标签。HTTP 单条写入记录使用独立 Basic 认证约束（4096 UTF-8 字节上限、用户名无冒号、认证无 ASCII 控制字符），不误用 SOCKS 的 255 字节约束。TLS 状态须显式存在；关闭 TLS 的运行配置省略 `tls`，而非把状态默认值泄露到不兼容字段组合中。

HTTP 导出只生成 TCP HTTP CONNECT，不伪装为 SOCKS/UoT。严格有界的 PEM 读取器只接受公开证书材料，不读取私钥；支持 CRLF 与用户维护的证书符号链接。明文链接和客户端导出返回 `http_plaintext_transport`。合法 TLS 状态返回空 URI 集合与 `http_tls_uri_unrepresentable`，对应安全摘要为 `shareable=false`、`client_exportable=true`；非法认证仍必须失败，不能借 TLS 的空链接语义伪装成功。Mixed 导出不受遗留 HTTP TLS 全局变量影响。

冻结源码 SHA-256 为 `908796034f55875e9ed8b8f521aff235ab4a56b6c9c32f31eb9900ebc3b3be2e`。原生与实际 Bash 4.2 均使用固定 ARM64 官方核心 1.13.18、1.14.0：认证/无认证明文和固定信任 TLS 均完成客户端→HTTP 入站→本地 HTTP marker；错误认证、信任或 SNI 被拒绝，缺失证书和不匹配私钥由真实核心拒绝。Bash 4.2 的六项非 runtime HTTP 测试及两核心 `--run` 均通过，起止源码哈希一致，证据 `/tmp/sbv-http-bash42-final.mLqBq8/`；最终路由测试又以相同测试文件哈希定向复跑通过（`route-final.log`）。这些是本地回环证据，不是公网/生产连接或外部 CA 签发证明。

全量回归发现并修复三个旧五协议选择/capabilities 断言；已执行失败项重跑。首轮完整门禁 `dev/verification-runs/20260908032430` 在验证器单测处停止：HTTP 新场景缺少模拟覆写，误入真实脚本，被只读文件系统阻止；真实 Docker 场景尚未启动。补齐模拟场景、场景列表及产物断言后，验证器 15/15 单测串行通过（`/tmp/sbv-http-verification-final.uLTiEq/`）。该失败运行不计成功；后续完整门禁另行记录。

普通 Shell 回归共 173 项，首轮 171 通过、2 个旧断言失败；修正后两个失败项定向重跑均退出 0，其余测试保持通过，日志与 `recheck-results.txt` 在 `/tmp/sbv-http-suite.tY6E3a/`。该批起止源码哈希一致。连同独立的 15 项验证器单测，共 188 项已验证通过（含修正重跑，而非声称首次全绿）。

第二轮 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/remote/entrypoint.sh` 在 `dev/verification-runs/20260908033809` 完成全部 75 项本地门禁；真实 Docker 前六场景成功，包括 HTTP 菜单 6 首次安装。六协议共存因测试预期数组把 `http` 与 `hysteria2` 的字典序写反而失败；实际配置及索引已包含全部六个正确入站。修正场景断言、针对提取的真实配置确认，并重跑场景映射、调度及 changed-file 产物单测后，运行时代码哈希仍未变化。因此后续以 `VERIFY_SKIP_LOCAL_TESTS=1` 配合相同核心与 `--changed-file` 重跑全部 Docker 场景，不重复无变化的 75 项本地测试；不得将本次失败 Docker 运行计为成功。

最终全量 Docker 重跑 `dev/verification-runs/20260908035049` 退出 0、`remote_status=success`：11/11 场景的 `STATUS=success/EXIT_STATUS=0`，16/16 TCP 业务探针成功，六协议共存的每个协议均有独立成功产物。故障升级结果为 `status=rolled_back`、`rollback.result=success`。父线程直接读取容器 `092f58d20ce9` 实际执行的 `/tmp/sing-box-vps-verification.Le4Ktk/install.sh`，哈希与冻结源码相同，保存于该 run 的 `container-runtime.sha256`。Docker 的新增 HTTP 场景使用明文回环入口；TLS 严格信任与拒绝路径由上述两核心原生/Bash 4.2 runtime 提供证据，不把 Docker 明文连接扩大为 TLS 或公网验证。全协议目标保持未完成，其他普通代理、高级接入、Endpoint 和上游组件继续按矩阵推进；未 push、未访问生产或执行真实 SubMan 同步。

## 2026-09-07：分享 URI 编码与可表达性

对照原目标第八节，发现 Mixed/SOCKS builder 原样拼接 userinfo，甚至测试将原始换行视为有效 URI。版本 `2026090710` 引入共享字节级百分号编码；普通未保留 ASCII 字符的旧链接不变，保留认证内容及 IPv6 方括号语义。Agent 先完整构造链接对象再返回，编码/校验失败不会被嵌套命令替换吞掉为成功的空链接。

Context7 `/sagernet/sing-box` 的结果仅覆盖 testing 配置，不定义代理 URI 编码；因此补查 [RFC 3986 userinfo/percent-encoding](https://www.rfc-editor.org/rfc/rfc3986#section-3.2.1) 和 [RFC 7617 Basic 字段约束](https://www.rfc-editor.org/rfc/rfc7617#section-2)。HTTP Basic 的用户名不能含冒号，认证字段不能含 ASCII 控制字符；此类 Mixed 记录保留 SOCKS5 链接和原始状态，但省略 HTTP 链接并返回 `mixed_http_auth_unrepresentable`。SOCKS5 URI 无法表达 UoT v2 选项，明确附带 `socks5_uri_transport_options_omitted` 并指向完整客户端 JSON；不把编码误称为加密，不声称所有客户端的导入策略一致。

新增默认门禁测试 `plain_proxy_share_links.sh` 和 `plain_proxy_share_runtime.sh`。前者验证逐字节往返、无认证、IPv6、HTTP 字段拒绝、Agent/交互共用输出、编码失败传播及状态不变；后者用生成的 URI 驱动 curl，经真实 Mixed 核心读取本机 HTTP marker。1.13.18 和 1.14.0 均通过特殊认证 HTTP/SOCKS、无认证 HTTP/SOCKS、尾随 LF 的 SOCKS、冒号用户名 SOCKS 和 HTTP 拒绝检查。实际 Bash 4.2 直接运行两版 runtime 的 `--run` 分支也退出 0，证据在 `/tmp/sbv-plain-share-bash42.OruzBw` 和 `/tmp/sbv-plain-share-bash42.k86DFp`；起止源码哈希一致。这不证明所有客户端导入策略、公网连接或 URI 携带完整 UoT 配置。

完整门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/remote/entrypoint.sh` 在 `dev/verification-runs/20260907133621` 退出 0：67 项本地检查、10/10 Docker 场景及 14/14 TCP 探针成功，故障升级为 `status=rolled_back`、`rollback.result=success`。父代理直接读取运行容器内 `/tmp/sing-box-vps-verification.pcrr5Q/install.sh` 的 SHA-256 为 `ea3749aaed4d945de043a4672d3558cda2110dc1d9eed28ee74256bf88ec1865`，与当前源码一致。独立预审未发现确认的 P1/P2；父代理补强了控制字符密码独立负例，并在原生 Bash 与 Bash 4.2 复跑通过。

全量普通 Shell 回归串行通过 166/166，日志 `/tmp/sbv-socks-all.u79hOa/results.tsv`；最终补强的链接负例另行复跑通过。14 项 verification 框架测试也串行全部退出 0，日志 `/tmp/sbv-verification-serial.3qATxO/results.tsv`，合计 180/180；两批起止 `install.sh` 哈希均与上述冻结源码相同。未推送、部署或执行真实 SubMan 同步，全协议目标仍未完成。

## 2026-09-07：独立 SOCKS 接入（当前阶段）

脚本与 README 版本统一为 `2026090709`。本阶段新增独立 `socks` inbound 预设，共享 Mixed 的类型化实例记录、CAS 写入、配置候选校验、持久事务和防火墙归属账本，不复制一套协议专用事务。SOCKS 新装直接使用 schema 2 marker 与 `schema_version: 1` JSON store；没有 legacy SOCKS `.env` 格式，`instance migrate socks` 明确拒绝，既有 live 配置走接管重建。旧 Mixed 的 legacy 迁移及包装函数继续保留。

实例提供创建、替换、删除、默认及恢复，默认回环监听并开启认证。非回环写入需要显式确认；恢复日志绑定协议，仅缺少 protocol 的历史日志按 Mixed 解释，显式 null/false/错误类型不作默认。SOCKS 与 Mixed 均参与 Warp 依赖判断；未索引 store 只接受合法、空且 revision 大于零的删除 tombstone。共享接管保留 ID/tag/名称/凭据/出站策略，省略 listen 时保持真实核心的回环默认，拒绝未建模字段；SOCKS 不接受 Mixed 专属的 `set_system_proxy` 字段。

菜单新增 18「管理 SOCKS 实例」，首次安装协议编号为 5。SOCKS 只提供 SOCKS5 分享链接及带 UoT v2 的客户端 outbound，不提供 HTTP 入口、TLS 或 SubMan 同步。核心支持事实先查 Context7 `/sagernet/sing-box`；该结果只有 testing 文档，随后按固定 v1.14.0 的 `protocol/socks/inbound.go`、`option/simple.go` 和 inbound 文档核实，并用真实 1.13.18/1.14.0 验证。

新增六项 Shell 回归覆盖共享 store、SOCKS 生命周期、真实核心运行、菜单、接管及导出。两版真实核心各通过 instances=2、exported=2、TCP=9、UDP=9、错误认证拒绝=1、失败候选保留旧服务=1；计数包含既有 Mixed 的流量保留检查，导出的两个 outbound 均生成并校验，其中一个用于实际客户端收发。这些是本机回环 SOCKS TCP/UDP 与导出 UoT v2 证据，不证明公网跨主机 UDP associate 或其他协议 UDP 数据路径。systemctl/firewall 在本地生命周期测试中仍为 mock；重启失败回滚另有 mock 故障注入（restarts=10）。

最终源码 SHA-256 `d711688daae51d938a02e737be7e521df6b8ea198c1e93b4f33d24d1feaf947c` 下，实际 Bash 4.2 直接执行两版 runtime 的 `--run` 分支均退出 0，日志为 `/tmp/sbv-socks-bash42.HD1NEM/`（1.13.18）及 `/tmp/sbv-socks-bash42.ZoFg4h/`（1.14.0），每个目录保留命令、stdout/stderr、退出码及一致的起止源码哈希。Bash 4.2 接管、菜单及事务专项也通过；菜单兼容补修处理了空数组展开、单次操作失败退出、删除确认实例 ID 和单次 list 循环问题。父代理独立复跑最终 Mixed/SOCKS 菜单测试通过。

冻结源码的 164 项普通 Shell 测试串行执行全部退出 0，逐项记录 `/tmp/sbv-socks-all.bpCBR9/results.tsv`，起止源码哈希一致；14 项验证框架测试也全部通过，日志 `/tmp/sing-box-vps-verification-suite.WadON6/`，合计 178/178。此前的并行运行、旧 capabilities 夹具及遗漏 SOCKS 的 runtime artifact 夹具曾失败，均不计作最终通过证据；对应夹具已补齐并重新执行。

最终默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/remote/entrypoint.sh` 在 `dev/verification-runs/20260907125254` 退出 0：65 项本地检查、10/10 Docker 场景、14/14 TCP 探针成功；新场景覆盖实际交互首次 SOCKS 安装与四协议安装后经 Agent 事务追加 SOCKS 的五协议共存。故障升级结果为 `status=rolled_back`、`rollback.result=success`。父代理在容器存活期间直接读取 `/tmp/sing-box-vps-verification.8yaSHN/install.sh` 哈希，与上述最终源码完全一致。此前 `20260907122042` 只有首次 SOCKS 安装与 runtime smoke 的局部 Docker 验证，不能代替本次完整门禁。

独立预审关闭了 SOCKS Warp 依赖遗漏、orphan store 忽略、跨协议恢复、协议诊断及导出 warning 误归属问题。warning 识别保留 legacy Mixed 的任意持久化节点名，不把 `socks-mixed` 误认作 Mixed；SOCKS 链接警告不宣称 URI 已配置 UoT。冻结源码复核未发现新增确认的 P1/P2，提交后仍须对精确提交范围审查。全协议目标继续进行，其他协议族和外部系统资源边界尚未完成；未推送、部署、操作生产或执行真实 SubMan 同步，用户未跟踪文件 `1`、`2` 均保留。

### SOCKS 提交后补修

`8d69d01` 的精确范围独立审查确认三处遗漏：`save_socks_state` 在缺少 marker 时可复用非空 orphan store；SOCKS 客户端生成失败可能被聚合导出跳过，发布部分结果；共享 capabilities 操作列表未准确区分 Mixed 的 legacy migration。补修分别在保存入口复用空 tombstone 校验、将 SOCKS 纳入整份导出的 fail-closed 路径，以及新增 `operations_by_protocol` 并从公共操作交集中去掉 `migrate`。本轮版本仍为 `2026090709`，不随补修提交重复递增。

负例确认非空 orphan 和 revision=0 空 store 均拒绝且原文件不变；合法 revision=1 tombstone 可创建新实例并递增到 2。接管测试通过原生 Bash 与实际 Bash 4.2，均带真实 1.13.18/1.14.0 核心。Mixed+SOCKS 聚合导出负例在两版 Bash 下验证了无效认证、缺少 marker、Agent/交互失败、原导出与 `.bak` 哈希不变及凭据不泄漏；Mixed 认证导出兼容回归也通过。前述 178 项全量结果属于主提交验收，补修验证单独记录，不宣称再次运行全部 178 项。

补修后的完整默认门禁在 `dev/verification-runs/20260907131600` 退出 0，命令与前述最终门禁相同：65 项本地检查、10/10 Docker 场景和 14/14 TCP 探针全部成功，故障升级仍为 `status=rolled_back`、`rollback.result=success`。补修源码 SHA-256 为 `29eac9ad1e0cd329ddc7d7d71fe7c1186a4e21d91bda7b0cd1e5b5e26ff0ba90`，父代理直接读取当次运行容器内安装脚本确认一致。两路独立补修预审均确认对应问题关闭，未发现新增确认的 P1/P2；未推送或部署。

## 验收范围

- [ ] 核对 latest stable、目标 release 注册代码、移除 stub、构建标签、平台和运行库；固定版本与来源，保留 1.13.x 路径。
- [ ] 覆盖矩阵分列核心支持、项目 implemented、环境 available、实测 validated，逐项记录部署/接管/编辑/删除/导出/分享/SubMan/限制与证据。
- [ ] 集中协议 family、preset/security/transport、role、内部 ID、公开 ID、alias 和 handler 契约；菜单、Agent、导出、验证共享注册表。
- [ ] 推广稳定实例 ID；兼容 index.env、旧协议状态与 vless-reality.d，保留凭据、名称、端口、tag、路由、QoS、出站策略；未知格式阻断有损重建。
- [ ] 统一 inbounds/outbounds/endpoints/route/certificate_providers/http_clients 组合；检查 tag、引用、环、版本、依赖；渲染不创建凭据或注册账户。
- [ ] 完整管理 mixed/socks/http/shadowsocks/vmess/trojan/naive/hysteria/shadowtls/vless/tuic/hysteria2/anytls/snell。区分普通 VLESS 与旧 REALITY alias；合法 TLS/传输组合、SS2022 密钥、ShadowTLS 完整内外层、Naive 运行库。
- [ ] 高级管理 direct inbound/tun/redirect/tproxy/cloudflared，保留管理连接，明确系统资源归属，隔离验证。
- [ ] 管理 wireguard/tailscale/openconnect/openvpn-client/openvpn-server Endpoint；WireGuard 与 Warp 注册解耦；外部认证和控制面测试条件明示。
- [ ] 管理适用上游代理、ssh/tor/direct/bridge/selector/urltest，保护成员、detour、Endpoint 引用；按源码核实 block/dns/ShadowsocksR 历史边界。
- [ ] 真实客户端配置和组合依赖导出、私有证书最小信任、目标核心 check；无服务端私钥；URI 无损/部分/不支持、IPv6/编码/特殊字符测试。
- [ ] Agent envelope `schema_version=1.0`/`schema=1`、旧命令语义、敏感字段与 stdout/stderr 分离；只读不写状态；新写命令参数校验和确认。
- [ ] 只读审阅 SubMan OpenAPI；保留 VLESS/Hysteria2 幂等/revision/确认/回读/错误契约；其他逐节点准确 unsupported/skipped/warning，部分成功不污染可同步节点。
- [ ] 复用托管事务：预检、锁、持久快照、候选、jq/check、发布、资源、健康检查、提交；失败恢复文件、资源、原服务活动状态。
- [ ] 端口按地址/地址族/TCP/UDP/归属检查，规则与证书引用保护；运行库进入升级 manifest/备份/回滚/卸载；no-op 无虚假事务。
- [ ] 保留原始错误阶段/退出码；可捕获信号清理；不可捕获中断后持久恢复；下载、证书、规则集故障有界超时/可信来源/脱敏。
- [ ] 现有全回归及新增生命周期、兼容迁移、多实例、失败注入、并发、注入、部分同步测试；真实目标二进制服务端/客户端 check。
- [ ] 隔离真实 TCP/UDP 闭环、Endpoint/透明流量路径；Docker 调度/probe/scenarios 共享能力；缺少授权端点的结果记 blocked/skipped，不计通过。
- [ ] README、Agent 文档、状态/资源/事务设计、协议扩展示例、实际命令/版本/证据/限制、原子提交及逐提交等效审查。

DNS Server、证书服务、管理 API、USB/IP 独立服务不扩展为本轮产品功能。生产 VPS、真实 SubMan 同步、Cloudflare 账户和隧道资源不在授权范围。

## 实施阶段

1. 上游核对与公共契约：接回原四协议，集中能力与调度，保持行为兼容。
2. 通用实例、TLS/传输、资源、配置组合、客户端和事务基础。
3. 普通代理及组合协议的完整生命周期和真实连接。
4. 高级入站、Endpoint、上游出站及实际数据路径。
5. 全回归、故障注入、Agent/SubMan 与文档验收。

## 已确认的架构落点和风险

- `normalize_protocol_id` 的 `vless` 必须继续指向 REALITY；普通 VLESS 应使用明确的新 preset ID。
- 菜单编号、Agent capabilities、客户端候选和 probe 白名单各自固定四协议，须接入同一注册表。
- `protocol_inbound_tag` 默认回落为 `vless-in`，builder 对未知协议可能返回空成功，须明确失败。
- `reconcile_protocol_index_if_needed` 会忽略未知 ID；`generate_config_candidate` 通过进程替换读取列表会吞掉发现失败，须先捕获完整列表再准备/发布。
- 现有 `source` 状态读取仅适用于本地受管旧状态；新外部导入必须作为数据校验，不能复用不可信 source。
- `generate_config_candidate` 包含 Warp 注册与材料准备；下一阶段分离准备和渲染，不重写已有凭据。
- 快照现有覆盖项目目录，未形成资源账本/持久恢复状态；需扩展现有事务，不能旁路发布。
- `list_config_protocols` 与接管只认识旧协议；扩大识别前必须先建立未知配置/字段保留保护。

## 证据与进展

第一阶段已接入原四协议注册表、公共 ID/菜单/导出/Agent/SubMan 类型/验证元数据，补上未知索引和状态版本、缺失 handler、空/错误片段与协议发现失败的阻断。配置对象识别、通用多实例、资源账本和完整协议实现仍属于后续阶段，未将它们记为完成。

- 基线 `cc12c06`：155/155 Shell 回归，9/9 Docker 场景、12/12 TCP 业务探测；固定副本 `/tmp/sing-box-vps-baseline-cc12c06`，运行目录 `dev/verification-runs/20260906162844`（在该副本下）。
- 第一阶段审查修复后的版本：`bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/run.sh dev/verification/remote/entrypoint.sh`，退出 0；证据 `dev/verification-runs/20260907031322`，9/9 场景、12/12 TCP 业务探测成功，包含旧 Mixed 恢复、Bash 4.2 修复及过期索引恢复失败保护。Hysteria2 使用 QUIC 传输承载该 TCP 业务；未因此声称 UDP 业务已验证。
- 第一阶段审查修复后的全部非 helper 的 `tests/*.sh`：157/157 通过；逐项退出码 `/tmp/sing-box-vps-post-reviewfix-tests-20260907/summary.tsv`。
- `SINGBOX_BINARY_113=/tmp/sbv-real-schema-final.6rMcum/sing-box-1.13.18-linux-arm64/sing-box SINGBOX_BINARY_114=/tmp/sing-box-v1.14.0-cache/sing-box-1.14.0-linux-arm64/sing-box bash tests/export_client_config_1_14_compatibility.sh`：退出 0，两个实际核心均接受对应客户端配置。
- 本轮版本统一递增为 `2026090601`；目标核心保持稳定 `1.14.0`。阶段内不重复递增。
- 回归发现并修复验证 fixture 的独立 metadata 加载和原固定测试计数；没有改用跳过或 mock 替代真实 Docker 验证。
- 预审期间的 Docker 复验 `dev/verification-runs/20260906170645` 为 9/9 场景、12/12 TCP 探测成功，但当时全量 Shell 为 155/156：发现旧单 Mixed 仅残留索引时不能追加安装的回归。实现现已恢复该明确写入口的无损旧状态恢复，补上索引/凭据保留、状态写入失败回滚和拒绝自定义字段测试，并通过上述最终全量复验。
- 旧 Mixed 恢复还通过了两个实际核心的输入/重新渲染 `check`，同时断言原配置字节和用户名/密码不变；命令 `bash /tmp/sbv-legacy-mixed-real-check.sh`，退出 0。此项为受控配置恢复证据，不替代网络连接探针。
- 2026-09-07 的额外兼容检查在官方 `bash:4.2` 容器复现空 alias 数组的 `nounset` 错误；已修复为空时不展开数组。`tests/protocol_registry_legacy_bash.sh` 在 Bash `4.2.53` 和主机 `5.2.21` 均通过，前者使用只读仓库、无网络容器及临时 `/tmp`。镜像 digest 为 `sha256:326c3fb7e7009e1aa6aad242056abc11c372ac0a2b57dcb29ca5bc8feedf5579`；这证明注册表的旧 Bash 语义兼容，不等于完整 CentOS 系统服务验证。
- 原子提交 `380eedd`（`feat: centralize protocol capability contracts`）随后进行了实际提交范围的等效 `/review`（本工具面没有该命令入口）。审查发现旧过期索引分支先删除索引且吞掉恢复失败；已停止后续功能接入，改为直接复用保留原索引的重建事务，补上空 inbounds 和原始退出码 `47` 的回归测试。独立复核确认索引字节保留、错误传播及旧过期条目清理均通过，上述完整门禁也已复跑。
- 修复已形成原子提交 `223ca06`（`fix: preserve protocol indexes when recovery fails`），提交后等效实际范围审查确认该 P1 已解决、无新增 findings。
- 补充上游角色/版本交叉复核修正了覆盖矩阵：Bridge 从 1.14.0 才存在且只处理 L3；direct inbound 的目标覆盖字段仍然有效，移除仅适用于 direct outbound。证据为固定 tag 源码、1.13.18 对 Bridge type 的实际拒绝，以及两核心对受控 direct inbound 配置的 `check`。

后续仍需完成阶段 2–5 的所有未勾选要求；本阶段的通过结果不作为新增协议或高级接入已实现的证据。

## 2026-09-07：第二阶段候选配置图预检

新增 `validate_managed_component_graph`，接入服务端 candidate 和交互/Agent 客户端候选的核心检查之前；同一 jq 解析完成组件 tag、typed reference 和显式依赖环检查。引用完整性与启动依赖区分，DNS/HTTP/provider 等按各自命名空间解析。错误输出不含配置内容、tag 或凭据。Agent 导出失败返回 `client_config_validation_failed`，不覆盖旧导出或备份。

本轮版本同步为 `2026090701`，仅递增一次。再次查询官方 releases/latest，稳定版仍为 `v1.14.0`（非 draft/prerelease，发布时间 2026-08-31）；使用固定源码 `0b8995879f29a9b98ee027bc17b75e101445b238` 和 1.13.18/1.14.0 实际二进制交叉验证。Context7 只返回 testing 分支及不完整引用资料，因此补读 release tag 的 `option/`、dialer、DNS/HTTP manager 源码。

已执行的新增针对性验证：

- `tests/managed_component_graph.sh`：43 项图单元断言；传入 `SINGBOX_BINARY_113`/`SINGBOX_BINARY_114` 后，两份完整正例均通过两个实际核心 `check`。主机 jq 1.7 与只读、无网络的 Debian 12 验证镜像 jq 1.6 均通过图断言。两版核心路径沿用上文记录。
- `tests/managed_component_graph_core_startup.sh`：在两版核心完成 8 次实际对照；悬空 route final、DNS final、DNS 缺失依赖和 DNS 环均可通过 `check`，但启动退出 1，而新预检已在发布前拒绝。使用无入站监听、无远程规则集及无外部账户的受控配置；不是协议业务数据面证明。
- `tests/generate_config_commits_validated_candidate.sh` 和 `tests/export_client_config_validates_generated_config.sh`：在核心 mock 放行的情况下，真实图预检阻断重复 tag/悬空引用，验证 live 文件、旧 `.bak`、协议状态、导出文件保持，生成器副作用回滚，Agent stdout 仍为有效 envelope。
- 官方 `bash:4.2` 无网络只读容器中 `bash -n /work/install.sh` 通过；此项仅为旧 Bash 语法检查，不是旧发行版的完整服务测试。
- 默认门禁加入两个图测试及客户端发布测试，运行器调度断言从 32 项更新为 35 项；不依赖提交后空 diff，最终使用显式 `--changed-file install.sh dev/verification/common.sh`。
- 最终完整门禁：在上述两个实际核心环境变量下运行 `bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh`，退出 0。证据 `dev/verification-runs/20260907033515`，9/9 Docker 场景、12/12 TCP 业务探针成功，包含 1.13.18 → 1.14.0 升级及注入重启失败后的回滚。Hysteria2 的 QUIC 传输不作为 UDP 业务已经验证的证据。
- 全部 159 个非 helper 的 Shell 测试均退出 0，日志与逐项退出码位于 `/tmp/sing-box-vps-all-tests-20260907-graph-final/summary.tsv`；该次全量传入两核心路径，新增启动对照执行 8 次，没有跳过。单独无网络 jq 1.6 容器只执行图断言，不计为真实核心启动比较。

边界不变：这只是阶段二的候选组合基础，不代表通用实例、所有协议、任意 live 配置无损接管或资源事务已经完成。下一步仍需先实现未知对象/字段的无损保护，再推广结构化实例、纯渲染、资源归属和完整生命周期。

## 2026-09-07：现有入站清单的无损保护

新增 `validate_live_inbound_inventory`，在协议枚举、健康判定、索引协调、自动修复、显式接管、状态重建和配置生成的资源准备之前检查完整 live 入站清单。未知核心类型、非 REALITY 的 VLESS、重复的当前单实例协议、重复显式 tag 和损坏的 JSON/清单结构均固定分类失败；枚举先捕获完整结果与退出码，不输出“已识别前半段”。旧 `vless` CLI alias 继续表示 REALITY，REALITY 多实例继续可用。接管诊断不再打印含 UUID、密码、私钥或 token 的原始状态快照。

本轮版本同步为 `2026090702`，仅递增一次。`tests/live_inbound_inventory_guards.sh` 覆盖全部入口的 fail-closed、配置/索引/状态 hash 与 mode 保持、资源准备及重启未调用、诊断脱敏、合法四协议清单和旧 alias。固定 1.13.18 与 1.14.0 实际核心都先接受 Mixed + Shadowsocks 受控配置，随后脚本门禁拒绝将其中未知 Shadowsocks 当作可管理对象；这证明修复针对真实可运行的丢失路径，而不是仅拒绝无效 fixture。

首次提交后的精确范围审查发现两个问题：sing-box 的 TLS/REALITY `enabled` 布尔值省略时默认为 `false`，不能只拒绝显式 `false`；Agent 的 `status`、`nodes` 和 `links` 也不能绕过完整清单校验后返回部分协议。后续修复要求两级开关都显式为 `true`，并使三个 Agent 命令在无法信任 live 清单时返回 `live_inbound_inventory_untrusted` 结构化错误；负例覆盖省略/禁用开关、部分结果阻断、凭据脱敏，以及公网地址和资源准备均未触发。该修复提交的精确范围审查无 finding。

继续收口既有索引/状态风险的提交经精确审查后发现五项缺口：VLESS 实例枚举仍使用会吞退出码的进程替换，索引 schema/重复项/配置集合不一致未检查，缺失 VLESS 根状态会回退到默认值，孤立未知状态被忽略，成功输出后的状态恢复失败未传播。最终实现改为先只读构建统一可信清单：规范化索引与 live 协议集合必须完全相等，索引和基础状态必须完整且没有重复/孤立项；REALITY 实例清单在公网读取前一次性捕获并验证。节点先写入临时集合，任何加载、实例枚举或最终恢复失败都会清理临时结果并返回固定结构化错误。新增负例逐项复现上述路径，并检查不泄漏已渲染的 Hysteria2 密码或连接材料。

该修复的再次精确审查又复现两项 REALITY 特有缺口：只有 schema 标记的旧根状态仍会被默认节点名、端口和 SNI 补成伪节点；schema 2 只检查清单所列文件，没有核对实例目录、文件内部 ID 和 live VLESS tag 集合。最终收敛为 `status`、`nodes`、`links` 共用的只读 REALITY inventory 验证器：schema 1 直接检查原始连接字段且拒绝实例目录残留；schema 2 校验根密钥、默认实例、清单唯一性、每个完整且启用的实例、目录精确集合、文件名/内部 ID 一致性，以及实例 tag 与 live VLESS tag 的精确集合。负例覆盖空壳旧状态、孤立实例、内部 ID 错配、live tag 错配和凭据不泄漏，并保留两实例成功对照。提交前聚焦复核确认上述两项 P1 均已关闭，未发现新的 P1/P2；状态字段与 live 参数的完整语义往返、密钥数学一致性及既有 shell 状态文件信任边界仍明确保留为范围外风险。

最终 160 个非 helper Shell 测试在两核心环境变量下全部通过，证据为 `/tmp/sing-box-vps-all-tests-20260907-vless-inventory-postreview.tKCE65/summary.tsv`。最终 `bash dev/verification/run.sh --changed-file install.sh --changed-file dev/verification/common.sh` 退出 0，证据目录 `dev/verification-runs/20260907063120`：44 个本地触发测试通过，Docker 9/9 场景和 12/12 TCP 业务探针成功。正常升级从 1.13.18 到 1.14.0，服务前后均为 active 且目标核心 `check` 通过；注入服务失败的场景返回非零，但事务结果持久化并以 `rolled_back=true`、`rollback_ok=true` 恢复 1.13.18、active 服务和通过的核心 `check`。Hysteria2 的 QUIC 仍不作为独立 UDP payload 验证证据。

边界：本项只完成 live inbound inventory 层保护。额外用户/协议字段，以及未知 outbound、endpoint、DNS、证书和 route/rule 的语义往返保护仍未完成；已有 VLESS 状态的名称、QoS 与稳定 ID 在显式重建中的保留也仍需修复。它不代表新增 Shadowsocks 或其他协议已经实现。

## 2026-09-07：REALITY 重建保留既有实例元数据

针对原目标第五节的兼容要求，修复显式重建清空实例目录后重置稳定 ID、节点名和 QoS 的问题。先读取旧受管状态元数据，通过 inbound tag 唯一关联 live VLESS，保留实例身份、默认实例、名称和限速；连接字段仍从 live 配置读取。旧 schema 1 仅为对应主实例保留名称，根状态中与 live 私钥匹配的公钥可直接复用。期望状态比较使用同样的关联与默认实例选择。加载器清除旧 raw env 变量，避免 manifest/tag 从前次读取串入。

扩展既有 takeover 测试，覆盖自定义 ID/默认实例/含空格名称/QoS、二次重建幂等、tag 歧义拒绝、非法 QoS 拒绝、保存失败整树回滚及 schema 1 名称隔离。传入两核心路径时，临时真实 REALITY 密钥用于重建状态的服务端和客户端配置 `check`。本轮脚本与 README 统一为 `2026090703`。

首轮全量回归发现两个无 tag 旧配置接管用例失败：重建后的自动 `imported-*` ID 在健康检查中发生漂移。修复后，单个旧实例可唯一复用既有身份，schema 1 的无 tag/无用户名主实例保留名称；多个无 tag 入站则需要用户名与既有 ID 唯一对应，否则在替换状态前拒绝。补充配置字节不变、二次重建状态树不变和多匿名入站拒绝断言。

最终验证：160 个非 helper Shell 测试在 `SINGBOX_BINARY_113`/`SINGBOX_BINARY_114` 两个实际核心路径下全部退出 0，逐项记录为 `/tmp/sbv-reality-metadata-final.vtBj7I/summary.tsv`。`bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 退出 0，44 个本地门禁测试通过，证据目录 `dev/verification-runs/20260907065820` 包含 9/9 Docker 场景与 12/12 TCP 业务探针成功；包含 1.13.18 → 1.14.0 升级，以及失败注入后 `rolled_back=true`、`rollback_ok=true` 恢复 1.13.18。重建状态渲染的服务端与客户端配置均通过两个真实核心 `check`；Bash 4.2 只读无网络容器的语法检查也通过。Hysteria2 QUIC 仍不计作独立 UDP payload 验证，未操作生产 VPS 或执行 SubMan 同步。

提交 `7acf762` 的精确范围审查发现一项遗漏：旧配置省略 tag 时，重建与健康检查认可内部稳定 tag，但 Agent 清单验证仍直接要求 live tag 非空。修复使 Agent 仅在缺 tag 时复用同一唯一身份关联，随后仍执行完整字段、实例文件集合和 tag 集合检查。新增断言覆盖 tagless 接管后的 `status`、`nodes`、`links` 成功，配置/状态读取不变，多匿名入站拒绝，以及用户名与已有 ID 唯一对应的多实例成功。该后续修复沿用本轮 `2026090703`，不再递增版本。

审查后验证：25 项 Agent/接管/REALITY/清单保护相关测试全部退出 0，记录为 `/tmp/sbv-reality-agent-postreview.pFPefg/summary.tsv`；最终再次执行上述完整门禁，`dev/verification-runs/20260907071014` 的 44 项本地测试、9/9 Docker 场景与 12/12 TCP 探针均成功。前述 160 项全量结果对应首个元数据保留提交；六行 Agent 修复使用相关回归与完整 Docker 门禁复验，未将前次全量结果伪称为再次执行。独立定向复核确认 P1 已关闭，未发现新 P1/P2。

后续仍须实现未知字段和非入站组件的完整无损保护，以及通用实例、资源事务和新增协议全生命周期；本项没有将这些验收要求记为完成。

## 2026-09-07：统一只读实例适配入口

继续第二阶段，先将现有格式接入共享的实例枚举、默认实例和只读加载接口，实例身份使用协议与 ID 二元组。旧单实例协议/schema 1 REALITY 内部以 `main` 表达；schema 2 REALITY 保留原有身份与顺序。Agent 节点/分享遍历和 REALITY 客户端导出使用该接口，不再各自组织 REALITY 特例循环。既有公开 JSON 字段及 CLI alias 不变。

REALITY 导出不再为读取 schema 1 自动执行迁移；完整枚举或任一构建失败均不输出有效前缀。新枚举对清单/默认实例/文件集合错误拒绝，但显式接管清理旧孤立残留的原有契约保留。读取前清空原始状态变量，避免跨协议可选字段污染。此阶段不创建通用 JSON 透传状态、不增加 supported 协议行，也不把非 REALITY 多实例写入记为完成。

新增 `tests/protocol_instance_adapter.sh` 并接入默认门禁；覆盖单实例与多实例身份、旧 alias、缺省 schema 1、可选字段污染、名称/凭据/QoS 保留、只读与导出不迁移、失败时无部分输出及两版实际核心客户端检查。版本本轮统一递增为 `2026090704`。

首轮 161 项回归只有零 REALITY 实例的既有诊断断言失败：导出已正确拒绝且没有写文件，但提前默认实例预检丢失了明确提示。已恢复固定脱敏提示并保留失败退出码。独立预审另发现 schema 2 清单完整但 UUID 缺失时底层客户端构造仍能成功输出空字段；现将 Agent 既有连接完整性检查提取为共享校验，在通用 REALITY 加载后执行。负例覆盖 UUID、SNI、端口、首个 Short ID 和公钥缺失，第二 Short ID 保持可选。只读状态在预检后消失时也直接返回失败，不进入深层退出或使用先前实例值。

预审继续发现 schema 1 的节点名、端口和 SNI 缺失会被旧加载器默认值掩盖；通用入口现在先验证原始旧状态，再加载运行时字段，补齐三个缺失字段的拒绝用例。新测试在官方 Bash 4.2.53 镜像提取的临时运行时上实际执行，发现并修复新只读索引及客户端标签列表的空数组 `nounset` 问题，全部新适配器检查通过；测试在顶层 source 脚本以匹配实际入口，避免 Bash 4.2 对函数内 readonly 数组的作用域差异。这是 Bash 版本兼容运行证据，不代表完整 CentOS 系统验收。

定向复核又复现 Agent 可信清单首项、空索引孤立状态和空安装枚举的同源 Bash 4.2 问题。修复安全空展开和空清单提前返回，并直接覆盖真实 Agent helper 的首项、空清单、孤立状态拒绝及空节点结果；新增测试在 Bash 4.2.53 与两版核心路径下通过。

验证证据：161 项全量回归全部通过，记录为 `/tmp/sbv-instance-adapter-reviewed.VEZLE5/summary.tsv`；最后的必填字段及 Bash 兼容修复另以 28 项相关回归复验，记录为 `/tmp/sbv-adapter-bash42-related.Y1PPqT/summary.tsv`。完整默认门禁 `dev/verification-runs/20260907075359` 的 45 项本地检查及 Docker 均通过；最后 Agent 空数组修复后，以 `VERIFY_SKIP_LOCAL_TESTS=1` 单独复跑 Docker（不把跳过的本地检查计为重新通过），最终证据 `dev/verification-runs/20260907075939` 为 9/9 场景、12/12 TCP 业务探针成功，含正常升级和失败回滚。容器中的脚本 SHA-256 与最终源码一致：`a9dec9b25a791de43db3976883e3d52cf85c1a90e2d10e8940ecf7e0499eb3a9`。新旧实例客户端片段通过真实 1.13.18 / 1.14.0 `check`；Hysteria2 QUIC 不作为独立 UDP payload 验证证据。

本项未执行生产操作、推送或 SubMan 同步，也未完成全协议目标；后续仍需通用多实例持久化/写入口、未知字段及非入站组件无损保护、资源事务，以及新增协议完整生命周期。

提交 `bbf6a3d` 的精确范围等效 `/review` 发现跨协议客户端导出在目标实例加载失败时提前返回，跳过原运行态恢复。修复将目标解析/加载失败保存到统一状态码，跳过渲染但继续恢复原协议；初始失败码优先保留。新增回归从 Mixed 出发，逐项移除 REALITY 默认实例的 UUID、SNI、Short ID 和端口，断言失败无输出、原协议/实例/名称/端口/密码恢复、REALITY 字段清空，且后续 Hysteria2 导出成功。实际 Bash 4.2.53 两核心环境测试通过，修复沿用本轮 `2026090704`。

该审查修复的完整门禁再次退出 0：`dev/verification-runs/20260907080539` 包含 45 项本地检查、9/9 Docker 场景及 12/12 TCP 探针成功，失败升级事务结果为 `rolled_back` 且 rollback `result=success`。已核对运行容器源码与待提交脚本 SHA-256 一致：`7d34399104d4a6aa967995a1423fc032cc83d2a42d9deeae842e66b06b9e84a6`。独立定向复核确认状态恢复 P2 已关闭；前述 161 项全量回归并未在这个小修复后重新执行，不混作最终完整重跑证据。

## 2026-09-07：结构化实例存储基础与 Mixed 类型化适配器

从 `bd8cd9f` 继续，基线门禁 `20260907081124` 为 local 模式退出 0，原有未跟踪文件 `1` 保持不动。只读追踪确认现有 Mixed 健康匹配只看第一个入站、重建循环最终只保留最后一个实例，生成器也固定 `mixed-in`；因此没有直接放开注册表多实例标记，而是先实现后续完整生命周期必需的结构化存储和纯渲染基础。本轮版本统一为 `2026090705`。

新增内部数据 API 支持 create/replace/delete/default 候选、稳定 ID/tag、默认实例、有序清单和 revision 条件写入。第一种类型化 handler 为 Mixed；其他协议明确拒绝，旧 `.env` 和 REALITY 实例目录不会自动转换。数据必须是单一 JSON 文档，严格 allowlist、类型、大小、地址、端口、认证 UTF-8 字节长度和 revision 精确整数范围；不是原始 core 配置透传。凭据通过私有数据捕获及 stdin/文件传递，错误只返回固定阶段/分类。Context7 返回 testing 文档，随后核对固定 [1.14 Mixed 文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/inbound/mixed.md)及 [SOCKS 出站文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/socks.md)，最终以两个固定核心运行确认实际渲染行为。

原子文件写入使用私有目录/文件、锁内 CAS、一次性有界输入捕获、同目录 staging、原子 `.bak` 与目标替换、内容/权限 postcheck 和回滚。no-op 保留 revision、目标 inode 和旧备份。TERM/INT/HUP 清理并恢复已尝试提交的文件；回滚失败保留原文件副本与恢复标记，不销毁恢复材料。不自动夺取遗留锁：不可捕获中断后需明确检查恢复记录，这不是完整服务资源事务或持久恢复管理器。未来启用写命令仍须复用既有 managed snapshot、完整配置候选、资源归属与服务发布流程。

`tests/structured_instance_store.sh` 覆盖数据注入边界、未知字段/schema、非法 IPv4/IPv6、默认实例、稳定 tag、revision 上限、并发两个写者、备份/no-op、commit/postcheck/TERM 失败、rollback_failed 材料保留、目标/备份符号链接拒绝及旧状态字节保持。主审与独立复核发现并修复末尾单冒号 IPv6、换行地址、空默认实例、revision 末端递增和输入重复读取的问题。两核心各运行两个不同认证的 Mixed 实例，分别通过 HTTP/SOCKS 请求同一 loopback 标记服务，共 8 次真实 TCP 请求；这是新存储渲染的数据面证据，不是现有菜单的多实例生命周期验收，也不包含 UDP 业务验证。

该存储尚未接入 Agent/菜单写命令、旧状态迁移、健康修复、接管、删除、防火墙归属或完整客户端导出，不把此项记作 Mixed 多实例完整支持。下一步必须将这些接入点成套实现，再调整能力注册表；全协议目标继续保持未完成。

验证：162 项非 helper Shell 全回归全部通过，记录为 `/tmp/sbv-structured-store-all.xnwzKw/summary.tsv`。完整默认门禁 `20260907083458` 的 46 项本地检查和 Docker 均退出 0。最后仅调整新原语的失败阶段说明与避免把旧认证字段放入 jq 命令行，随后以 `VERIFY_SKIP_LOCAL_TESTS=1` 复跑 Docker，证据 `dev/verification-runs/20260907083903` 为 9/9 场景与 12/12 既有 TCP 探针成功；未把该次跳过的本地门禁计为重跑。最终源码 SHA-256 为 `2c7071fa87cfa95ca52f7811372d77dfe0381b8be6dc815e8916f2fef1708d80`。新增测试另在 GNU Bash 4.2.53 临时运行时上运行通过（主机工具链，不等于完整 CentOS 系统验证），两版真实核心检查和 8/8 HTTP/SOCKS TCP 请求均通过；最后还补验了正确凭据成功/错误凭据拒绝以及成功编辑保留 ID/tag。独立定向复核无新增 P1/P2。未执行生产、远程推送或真实 SubMan 同步。

## 2026-09-07：监听资源规划与删除引用保护

从 `b650a91` 继续，基线 `bash dev/verification/run.sh` 为 `20260907084911` local 模式退出 0；保留原未跟踪文件 `1`。调用图再次确认 Mixed 多实例不能只接存储与生成器：健康匹配、接管、Agent、删除及系统资源都仍有单实例分支。本轮先完成已存在的资源误判/误删路径，作为通用多实例生命周期的必要接入，不改变注册表支持范围。版本本轮仅递增为 `2026090706`。

新增 `managed_listener_plan` 与冲突校验，直接使用注册表 `listen_networks`，识别固定 socket 的 tag 归属、TCP/UDP、规范化地址、地址族和双栈重叠。候选配置发布前与结构化 Mixed validate/candidate/publisher/renderer 已共用；非法/未知字段范围不输出部分计划或凭据。删除时读取 `.bak` 和剩余配置，按旧监听拥有的 transport/port 求差并保护新引用，后端失败保留原错误码、报告可能部分外部变更，不用文件回滚冒充系统已恢复。

Context7 查询仅提供 testing 概览，随后复核固定 [Mixed TCP listener](https://github.com/SagerNet/sing-box/blob/v1.14.0/protocol/mixed/inbound.go)、[TCP Listen](https://github.com/SagerNet/sing-box/blob/v1.14.0/common/listener/listener_tcp.go)、[UDP Listen](https://github.com/SagerNet/sing-box/blob/v1.14.0/common/listener/listener_udp.go) 及其固定依赖 [NetworkFromNetAddr](https://github.com/SagerNet/sing/blob/v0.9.0-beta.4/common/metadata/network.go)。1.13.18 的 TCP 路径也使用同一地址族选择方式。实际二进制仍为 1.13.18（revision `45ca32dcb966f07f97fc888fe8586e359dbe8405`）与 1.14.0（`0b8995879f29a9b98ee027bc17b75e101445b238`），本轮重新查询 latest stable 仍为 1.14.0。

新增 `tests/managed_listener_resources.sh`、`tests/firewall_listener_references.sh`，并在候选发布测试增加核心 mock 放行、资源冲突阻断且旧配置/备份/状态保持的用例。默认门禁加入两项。首轮 163 项回归全部退出 0，证据 `/tmp/sbv-listener-all.HQkXLo/summary.tsv`（已包含资源测试）；该次文件名过滤还排除了实际上可执行的 `subman_config_helpers.sh`，最终枚举纠正为仅排除两项真实 helper，不以这个早期集合冒充最终 164 项全量。

资源测试在 Bash 5 和实际 Bash 4.2.53 上使用两个核心各完成两地址同端口 TCP、同数字 UDP 的启动，4 次 TCP 标记请求，以及 IPv6 等价地址 check 成功但启动报 `address already in use` 的 2 次对照。主机默认不运行通配对照；在 `sing-box-vps-verify` 镜像（`6c1e402cdaa2`）、`--network none --read-only --tmpfs /tmp`、只读挂载仓库与核心的容器中设置 `SBV_TEST_ISOLATED_LISTENER_WILDCARD=1`，额外两次 `::`/IPv4 冲突对照通过。隔离执行总计 check=6、start=2、TCP business=4、等价 IPv6 contrasts=2、wildcard contrasts=2。该容器使用 jq 1.6；不操作宿主机防火墙，不把 UDP 监听当作 UDP 业务验证。Bash 4.2 的防火墙 mock 回归和原结构化实例测试（两核心、8 TCP 请求）也通过。

首次完整门禁 `20260907090000` 在本地 mock harness 阶段因与全回归争用 `/tmp/sing-box-vps-verification.lock` 退出 32；确认原任务已终止、锁已由任务清理后串行重跑。首次隔离资源测试发现旧缓存验证镜像未含 Python，未记通过；按仓库现有 Dockerfile 重建后上述隔离测试通过。

独立预审发现并关闭三项 P2：开放仍加反向传输规则导致新清理留下孤立规则、全量移除未确认 stop 成功、已提交后开放失败缺少阶段说明。现在开放与清理共用实际监听传输，全量 stop 失败恢复文件且保留原始 47 退出码，`ActiveState` 非 inactive 则拒绝清理；新 wrapper 明确报告已提交配置/防火墙可能部分变更/显式重启未执行。相应 mock 正反例、配置/索引/状态/旧备份 hash 保留断言已补齐。后续全回归发现 7 个安装 prompt/state 测试只 mock 配置生成计数，因此将其防火墙 mock 移到新的收集边界，不降低真实资源校验；另在 Bash 4.2 实跑删除入口修复索引协调和删除选择的初始空数组 `nounset`。测试 fixture 避免函数局部 readonly 及 here-doc 重定向的旧 Bash 作用域干扰，真实删除安全回归通过。

完整默认门禁 `bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `20260907090447` 退出 0，48 项本地检查及 9/9 Docker 场景、12/12 既有 TCP 探针通过。最后审查修复之后，另以 `VERIFY_SKIP_LOCAL_TESTS=1` 复跑 Docker，最终证据 `dev/verification-runs/20260907091817` 为 9/9 场景、12/12 探针成功，失败升级事务为 `status=rolled_back`、`rollback.result=success`；没有把该次跳过的本地门禁计为再次执行。在运行容器中直接取得的安装脚本 SHA-256 为 `4439061cd395f9d8ad159436a8104fdb7786d974c08a13218ffa2f253cde6f88`，与最终工作区源码一致。

最终修正枚举后的 164 项回归全部退出 0，两个核心环境变量均已传入，逐项证据 `/tmp/sbv-listener-final-all.JMX95i/summary.tsv`。最终 Bash 4.2.53 另重跑资源计划（两核心 check=4/start=2/TCP business=4/等价 IPv6 contrasts=2）、防火墙 mock 与真实删除入口的停止故障回归，全部通过；主机默认跳过通配启动对照，隔离 Docker 的额外双栈证据如上。预审发现的三项 P2 和两个旧 Bash 空数组问题均已修复，独立复核未发现新增 P1/P2。

边界：尚未实现精确防火墙创建归属账本、跨进程端口预留、完整配置/服务/防火墙持久事务、动态 SOCKS UDP/ACME 临时监听、高级接入资源或通用实例完整写入口。旧 prompt 的整数字端口占用询问尚未替换为完整资源计划；新增候选预检不宣称解决该交互限制。全协议目标仍未完成，未推送、部署、访问生产或执行 SubMan 同步。

### 2026-09-07 Mixed 客户端导出

从 `ca7e5e4` 继续，基线 `bash dev/verification/run.sh` 为 `20260907092728` local 模式退出 0；保留用户原未跟踪文件 `1`。本轮版本只递增一次为 `2026090707`。为推进总目标中明确要求的 Mixed 导出，不再沿用历史设计的排除规则；不将本轮功能冒充完整通用多实例生命周期。

注册表、Agent capabilities/nodes 与交互/Agent 导出现在一致支持旧 Mixed 单实例。SOCKS5 outbound 使用已保存的端口、认证标记及凭据，用户名/密码校验 1–255 字节；无认证时不输出 credential 字段。原始状态的必需字段缺失、无效或凭据超长会拒绝，不用 legacy loader 默认值补造，也不触发状态迁移或凭据生成。即使其他协议可用，无效 Mixed 也中止整份导出，原文件与备份保持不变。生成后依次执行组件图和目标核心 check，沿用私有临时文件、覆盖前备份及发布边界。Agent 候选生成失败返回稳定 `client_config_generation_failed` 错误 envelope。

最终复核进一步要求校验与渲染使用实例适配器同一次加载的原始字段，不二次读取 `.env`：故障注入在缺少 PORT 的快照加载后立即替换为完整新文件，仍须拒绝旧快照默认值。此回归及用户名/密码 255/256 字节、UTF-8 字节数、陈旧凭据、stderr 脱敏、直接调用 dispatcher 的跨协议恢复均通过 Bash 5 与实际 Bash 4.2.53。该保护不是跨进程锁或完整持久事务的替代。

显式开启 UoT v2，使 UDP payload 经现有 TCP 入口传输，不新增固定 UDP 防火墙开放；`network` 留空遵循上游 TCP/UDP 默认。Context7 查询之后按固定 1.13.18/1.14.0 文档及 Mixed `uot.NewRouter` 源码确认。交互输出及 Agent `warnings[].code=mixed_plaintext_transport` 明确提示凭据与非加密业务在代理链路上没有 TLS 保护；UoT 不提供加密。Mixed SubMan、独立 SOCKS 服务端管理和 Mixed 多实例的声明保持未支持。

真实运行测试将实际导出的 SOCKS5 outbound 原样放入精简隔离客户端配置；完整导出仍另行 check。1.13.18/1.14.0 同版本与双向跨版本、认证/无认证共 8 组均有 TCP marker 与 UDP echo payload 成功，合计完整导出 check=8、精简核心 check=16、TCP=8、UDP=8、直接服务端错误认证拒绝=4；父代理已独立复跑。它不证明完整配置的公网规则集下载、原生跨主机 UDP associate 或其他协议 UDP 数据路径。原有 Docker 场景仍单独计为 TCP 证据，未操作生产或 SubMan 服务。

回归证据：166 个实际 Shell 测试全部退出 0，逐项记录 `/tmp/sbv-mixed-export-all.0L4Qeo/summary.tsv`；最后同快照校验收紧后，11 个客户端导出专项再次全部通过，记录 `/tmp/sbv-mixed-export-final.2eT2cN/summary.tsv`。实际 Bash 4.2 另通过 Mixed-only、认证/失败回归和两个跨版本方向的 TCP/UDP 运行。最终默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `dev/verification-runs/20260907095126` 退出 0：51 项本地检查、9/9 Docker 场景、12/12 既有 TCP 探针通过，失败升级的持久事务为 `status=rolled_back`、`rollback.result=success`。直接从当次容器读取的脚本 SHA-256 为 `8f280f8576beb83648ea8eb7a44d25cb3591b1fcc4f198a957993c070e101a22`，与最终源码相同。独立预审及同快照收紧复核未发现新增 P1/P2。全协议目标仍在进行，尚未实现新协议族、完整多实例和系统资源事务；未推送或部署。

## 2026-09-07：Mixed 多实例生命周期接入与验收

本阶段把前述结构化 Mixed 基础接入现有运行时，脚本版本统一为 `2026090708`。这不是全协议目标完成的标志；除当前四种既有预设外的协议族仍未实现，Mixed 也不提供 TLS、独立 SOCKS 服务端管理或新的 SubMan 同步能力。

Mixed 的 schema 2 状态以 `protocols/instances/mixed.json` 为真源，实例拥有稳定 `id`、`tag`、名称、监听地址/端口、认证和出站策略，并保留默认实例与单调 revision。首次全新安装仍走 legacy schema 1 的 `mixed.env` 路径；只有显式 `migrate`、接管重建或后续实例写入才启用 schema 2。显式迁移把 legacy 的现有 ID（单实例为 `main`）、tag、监听地址/端口及用户名/密码带入结构化记录，不通过隐式读取或凭据生成改变旧实例。旧配置省略 `listen` 时按真实核心默认保留 `127.0.0.1`，不使用机器的全局公网监听地址；省略端口或含未建模字段时拒绝有损转换。schema 2 的根标记只按数据读取，拒绝重复元数据或命令内容，不再 `source` 执行。

Agent 写接口覆盖 `create`、`replace`、`delete`、`default`、`migrate` 和 `recover`，返回稳定 JSON envelope，并通过 `--expected-revision` 进行 CAS。`replace` 保持既有 ID/tag；`delete` 删除单个实例并重新选择默认实例，删除最后一个实例时移除 active `mixed.env`、索引项和 Mixed inbound，但保留空 JSON store（`schema_version: 1`）作为 revision tombstone，active marker 仍为 `CONFIG_SCHEMA_VERSION=2`，后续 `create` 以 tombstone revision 继续递增而不重置为 0；`migrate` 使用虚拟 revision 0 迁移 legacy 状态；`recover` 只接受可验证的未完成事务和匹配 journal 原始 revision，缺少防火墙 journal 时失败并要求人工恢复。非回环地址的明文 Mixed 记录必须显式 `--allow-public`；没有该确认时请求在准备阶段拒绝。

实例写入的事务顺序是 prepare → snapshot → publish → resources → service → committed：初次创建也先在目标同目录 staging，再通过原子发布建立文件；共享 `flock` 串行管理写入，`.instance-write.lock/transaction.json` 保存持久阶段和 before/after 信息，`.instance-transactions/` 保存原子 result。配置候选必须经过组件图、监听资源和目标核心 `check`；受管 UFW/iptables/ip6tables 防火墙由实例 ledger prepare/apply/rollback 参与。firewalld 仅作只读外部预检，事务禁止 add/delete/reload；缺少所需 allow 或既有归属账本时在 prepare 阶段失败并要求人工规则。`firewall-cmd` 的 reload 会影响运行时防火墙状态，命令语义以[官方手册](https://firewalld.org/documentation/man-pages/firewall-cmd.html)为准；UFW comment 不作为规则身份，地址语法以[Ubuntu ufw(8) 手册](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)为准。本记录不据此宣称 UFW runtime 已验证。配置、状态、受管防火墙或重启失败时使用原快照恢复，rollback 失败保留 journal 与恢复材料，并要求 `instance recover` 或人工检查；缺少防火墙 journal 时恢复本身失败并转人工处理。文件状态的 `.bak` 和回滚只覆盖文件原语，不能宣称其他进程端口、动态 relay、ACME 临时监听或系统防火墙具有完整事务。

防火墙采用单一前端策略：UFW 活动时只通过 UFW 管理，firewalld 活动时只做外部预检，两者都不活动才直接管理 iptables/ip6tables。两个前端同时活动或已有账本归属于非选中后端时拒绝写入，不自动迁移、删除旧规则。这样避免同时向 UFW 及其底层重复登记归属；规则查询区分入站/出站、目标/来源及 IPv6 等价地址，回滚时若用户已修改 comment 则报告不确定并保留该规则。

交互菜单新增 17「管理 Mixed 实例」，对 schema 2 提供逐实例创建、修改、删除、默认、迁移和恢复。旧的协议删除菜单在活动 Mixed 与其他协议同时选择时拒绝跨协议批量删除，并要求先通过 Mixed 实例入口逐个处理；单独选择 Mixed 才进入逐实例删除流程。该保护避免把其他协议或尚未确认的 Mixed 实例一起移除。

新增六项本地回归覆盖 schema 2 生命周期、两版核心运行、显式迁移、状态匹配、失败恢复、菜单与防火墙归属。预审关闭了隐式监听扩大、候选混入回滚备份、schema 2 标记执行/降级、UFW 目标/来源及 comment 归属误判、双重防火墙管理、操作退出 0 却无实际效果、失败恢复缺少持久审计等问题。最后的恢复审计补修在 Bash 5 与实际 Bash 4.2 下再次通过；持久结果保留脱敏 `transaction.firewall`，即使恢复或审计写入失败，也明确报告失败并保留恢复材料。

最终全量回归累计 172/172 通过：158 项普通测试的逐项记录为 `/tmp/sbv-mixed-lifecycle-ordinary.5S6CsR/summary.tsv`，14 项验证框架测试为 `/tmp/sbv-mixed-lifecycle-verification.Wlffu8/summary.tsv`。普通测试运行期间包含最后一次恢复审计小修，最新生命周期测试已覆盖该修复；不是把此前存在失败或源码漂移的运行直接记为最终成功。默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `dev/verification-runs/20260907113104` 退出 0：57 项本地检查、9/9 Docker 场景、12/12 既有 TCP 探针成功，失败升级结果为 `status=rolled_back`、`rollback.result=success`。直接从本次容器读取的安装脚本 SHA-256 为 `6a06a7c91f085faffc5370f881952e0e5bdfd6c46b68176e69dd3064838c57ef`，与最终源码一致。

Mixed 生命周期的真实 1.13.18/1.14.0 各完成 migration=1、instances=2、TCP=7、UDP=7、错误认证拒绝=1、失败候选保留旧服务=1；省略 `listen` 的旧配置在全局 `::` 默认下迁移后仍为 `127.0.0.1`。实际 Bash 4.2 通过直接执行 runtime 测试的 `--run` 分支复验两版核心，日志 `/tmp/sbv-mixed-lifecycle-bash42.aocZVs/`；不是只用旧 Bash 启动随后切回新 Bash 的外层 runner。这些是本机回环 TCP/UoT UDP payload 证据，不证明公网原生 UDP associate 或其他协议的 UDP 数据路径。

父代理另外以最终源码独立复跑 UFW 0.36.2：`/tmp/instance_firewall_ufw_runtime.sh`，证据 `/tmp/instance_firewall_ufw_runtime.final-source.log`，退出 0 且含 `REAL_UFW_INSTANCE_FIREWALL_OK`。实际覆盖 IPv4/IPv6 等价地址、创建/删除/回滚、保留不同目标的预存规则，以及外部 comment 替换和 marker 前后缀伪造时拒绝误删。镜像为 `sing-box-vps-verify:ufw-20260907`，容器使用 `--rm --network none --cap-add NET_ADMIN --cap-add NET_RAW`，仓库只读挂载；没有操作宿主防火墙。firewalld 仍只有只读预检及 mock 证据，不宣称真实运行验证。全协议目标继续进行；未推送、部署、操作生产或执行 SubMan 同步。

### 提交后补修：UFW 注释与规则字段隔离

`855647b` 的提交后审查发现，预存 UFW 入站规则的用户 comment 若含 `ALLOW OUT`，会被整行动作匹配错误地跳过，随后新增同目标规则可能覆盖用户 comment 并误纳入归属账本。修复先分离 comment，动作与地址族只从规则正文判断，端口只在动作之前的目标字段匹配；comment 仅用于完整归属标记比较。本轮脚本版本保持 `2026090708`，不因修复提交重复递增。

防火墙账本与 Mixed 生命周期回归均通过 Bash 5 和实际 Bash 4.2（生命周期 restarts=18）。父代理独立复跑扩展的真实 UFW 0.36.2 隔离测试：预存规则 comment 中的 `ALLOW OUT`、独立 `32126/tcp` token 及 IPv4 wildcard 的 `(v6) ALLOW IN` 均不会改变规则匹配，apply/rollback 保留用户 comment，仅删除本次真正新建的 owned 规则。证据 `/tmp/instance_firewall_ufw_runtime.comment-parser.parent-final.log` 含 `REAL_UFW_INSTANCE_FIREWALL_OK`，日志 SHA-256 为 `3c4e32b4664f244b85b805fd8b7af049984954748f1c1c43e9018730c2fadb71`；临时测试脚本 SHA-256 为 `69fa7af7531c6ac37aabff28edf41d9562968edc0df902e60b2de22c223f4247`。源码 SHA-256 为 `00ca08698551824e18d4e45f358a62b0aa13471413493c1c69f0fe89c156acca`。容器仍采用上述隔离配置，没有操作宿主机防火墙。

修复后的完整默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `dev/verification-runs/20260907115136` 退出 0：57 项本地检查、9/9 Docker 场景、12/12 既有 TCP 探针通过；失败升级结果仍为 `status=rolled_back`、`rollback.result=success`。直接读取运行容器中的脚本哈希与上述 `00ca0869…` 一致；本次两版 Mixed 生命周期 TCP/UoT UDP 和四种版本组合的客户端导出 runtime 也实际重跑通过。前述 172 项全量记录属于主提交验收，本次补修未冒称再次执行全部 172 项。独立防火墙复核未发现新增 P1/P2；未推送或部署，用户未跟踪文件 `1`、`2` 均保留。

### 2026-09-09：高级组件固定监听资源事务接入

统一组件的 Agent `create`/`replace`/`delete` 现在在配置候选发布后比较旧/新固定监听计划；只有监听实际变化时才创建与快照同目录的防火墙 journal，并复用受管 UFW/iptables/ip6tables 账本执行 prepare→apply→commit。服务重启失败、资源应用失败或资源提交失败会先补偿外部规则，再恢复组件状态和配置；补偿不确定时保留快照并返回稳定的 `firewall_rollback_failed` 错误。无固定监听的 outbound/group 或没有计划变化的配置不会触发无关防火墙后端探测。Agent 成功结果新增脱敏 `firewall` 摘要；组件写入要求 root 与共享管理 `flock`，生成器返回成功但未产生普通配置文件也会拒绝提交。

回归新增到 `tests/managed_components_contract.sh`：固定监听端口替换断言 prepare/apply/commit 顺序、结果摘要和 CAS；注入 apply 失败后断言 rollback、配置/组件 revision 恢复及稳定错误 envelope。该接入仍只覆盖固定监听归属，不实现 TUN/redirect/TProxy 的策略路由、nftables、DNS 劫持、SSH 保留或 Cloudflared 控制面；不把 `unavailable` 后端状态写成公网防火墙或真实数据面验证。本轮定向组件/防火墙/Agent 回归及由 `install.sh` 触发的完整 `bash dev/verification/run.sh --changed-file install.sh` 均退出 0；Docker 运行目录 `dev/verification-runs/20260909130338` 提取 14/14 场景成功、0 个失败。该门禁未配置 `SINGBOX_BINARY_113/114`，本地真实双版本专项目明确显示 skip；Docker 场景和既有本地 mock/协议回归通过不等于 TUN/透明路由/公网防火墙或全协议数据面完成。未推送、部署、访问生产或执行真实 SubMan 同步。

### 2026-09-10：高级组件只读诊断入口

新增 Agent `sbv agent component diagnose --json`。该命令在共享读锁下只读检查组件 state revision/数量、组合配置是否存在、组件引用图、固定监听计划、目标核心 `sing-box check`、服务活动状态和受管防火墙账本规则数，并附带与 `component list` 相同的脱敏 registry/inventory；缺少核心、配置或账本时报告 `unavailable`/`missing`，不把诊断失败伪装成写入成功，也不迁移或改写状态。`list` 与 `diagnose` 均拒绝写入参数，实际 CLI 通过 `agent_dispatch` 的 shared lock 和未完成实例事务门禁。

`tests/managed_components_contract.sh` 增加诊断成功、图/监听通过、核心缺失状态和 Cloudflared token 不泄漏断言；本地 `bash -n` 与组件契约回归通过。该入口只补齐可观测性，不等同 TUN/透明路由、Endpoint 外部认证、动态资源或公网数据面验证；组件重建/接管/导出和持久化崩溃恢复仍未完成。

### 2026-09-10：高级组件受管重建入口

新增 Agent `sbv agent component rebuild --json --yes --expected-revision N`。它在排他管理锁和精确 revision 门禁下不改写 `components.json`，从同一受管状态重新生成组合配置，继续执行组件图、监听资源、目标核心 check、服务重启与防火墙 prepare/apply/commit；失败按既有快照路径恢复，成功结果标记 `operation=rebuild` 且 revision 不递增。回归新增 state/config 字节不变、无资源变化不探测防火墙和参数门禁断言。

该入口补齐了高级组件的重建生命周期，但不等同 live 高级配置接管、TUN/透明路由、Endpoint 外部认证、动态资源或持久化崩溃恢复；组件 takeover/export 仍未完成。

### 2026-09-10：高级组件 live 接管与敏感导出

新增 `sbv agent component takeover --json --yes --expected-revision N [--allow-public]` 与 `sbv agent component export --json --id ID [--expected-revision N]`。接管扫描当前 live 配置中的已注册高级 inbound/endpoint 和自定义 outbound/group，按既有 `(role,type,tag)` 保留稳定 ID，给新对象分配确定性 ID，并把对象字段及绑定 inbound/outbound 的路由规则放入组件 state；内建 `direct`/`block` 与生成器自有 `warp-ep` endpoint 仍由生成器拥有。候选发布后再次确认现有 tagged objects、证书/服务对象和全部 route rules 均未丢失，发现未知 outbound、保留 tag 冲突、未归属全局 route rule 或其他无法保真的对象即回滚。导出只按稳定 ID 返回完整敏感记录，带 `sensitive=true` 与可选 revision 门禁；`list`/`diagnose` 继续脱敏。

新增回归覆盖 endpoint/outbound 接管、重复接管、导出秘密字段、stale revision，以及全局路由规则会导致接管拒绝且 state/config 字节保持。该入口仍不等同 TUN/透明路由真实数据面、Endpoint 外部认证、动态资源事务或未注册上游 outbound 的完整适配。

### 2026-09-10：高级组件持久化事务恢复

高级组件的 create/replace/delete/rebuild/takeover 现在先在 `${SB_PROJECT_DIR}.component-write.lock` 原子发布 owner、CAS revision、before-active、阶段和防火墙意图，再把状态快照保存到同一事务目录。发布、监听资源和服务阶段均有 checkpoint；完成后以 `committed` checkpoint 清理事务目录。进程在清理前中断时，`sbv agent component recover --json --yes --expected-revision N` 校验 dead owner、精确 revision、journal schema、快照及外部防火墙日志，随后按 firewall→state/config→service 顺序补偿；active 或不可信 journal 保留原目录，不做猜测性删除。`component diagnose` 输出 pending 与当前阶段摘要。

`tests/managed_components_contract.sh` 新增 publish 阶段中断模拟：先保存 state/config，再写持久 journal 并注入 revision/route 部分变更，recover 必须回滚字节内容、返回 `status=rolled_back` 并删除事务目录。该切片补齐高级组件崩溃恢复边界，但仍不宣称 TUN/透明路由、动态资源、Endpoint 外部认证、公网防火墙或全协议数据面完成；完整协议目标继续未完成。

### 2026-09-10：受管 TUN auto-route 环路门禁

启用的 managed TUN 若声明 `auto_route=true`，配置生成器会把 `route.auto_detect_interface=true` 合并到顶层路由，以避免默认路由再次捕获 TUN 自身流量；已有配置若明确关闭该保护且没有 `route.default_interface` 则拒绝候选发布，明确设置默认接口时保留操作员选择。`tests/managed_components_contract.sh` 覆盖无 TUN、自动补 guard、显式冲突 fail-closed 与显式默认接口四条边界；`tests/generate_config_commits_validated_candidate.sh` 还覆盖实际 `generate_config` 发布与保留显式默认接口。本切片只处理 sing-box 配置层的环路保护，不冒充主机策略路由/nftables、DNS 劫持、透明接入或真实数据面完成；版本提升为本轮 `2026091003`。

本轮 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260910133840` 完成：`remote_status=success`，Docker artifact 已提取，包含 14/14 场景与 21/21 既有协议探针成功；本机未配置 `SINGBOX_BINARY_113/114` 的真实核心项按规则标记 skip。该证据覆盖当前受管回归和 Docker 安装/升级边界，不扩大为公网协议、动态 Endpoint 或真实 SubMan 验证。

### 2026-09-10：SSH outbound typed contract

managed `ssh` outbound 不再是只检查 `server`/端口的通用 JSON 容器。`managed_component_ssh_config_validate_json` 按固定 sing-box 1.14.0 `SSHOutboundOptions` 及 shared Dial Fields 建立字段 allowlist：服务地址必须为安全非空字符串，端口限制为 1–65535；password、listable private key 或 private-key path 至少提供一种认证方式；user、client version、地址/命名空间、duration、routing mark、network strategy/type、boolean Dial Fields 和 domain resolver 分别执行类型/范围检查。private/host key、cipher、MAC、KEX 的 listable 形状只接受字符串，已移除的 `domain_strategy` 与任意未知字段会在 state/CAS 和 live takeover 前拒绝。

空 `host_key` 保留上游“接受任意主机密钥”的兼容语义，但 inventory 增加脱敏 `host_key_verification`，只有非空固定列表显示 `pinned`，否则显示 `unverified`；list/diagnose 不返回 SSH 密码、私钥或 passphrase，敏感 `export` 仍按稳定 ID 返回完整记录。`tests/managed_components_contract.sh` 新增 password/path/PEM、缺认证、孤立 passphrase、越界端口、deprecated 字段、清单脱敏、live takeover、路由规则保留和 export 断言。此切片只证明状态/候选/无损接管边界；未执行远端 SSH 登录、主机密钥握手或真实 SSH 数据面验证。版本统一为本轮 `2026091004`，完整协议目标仍未完成。
完整默认门禁 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260910153514` 退出 0：本地协议/生命周期/组件回归全部通过，Docker `remote_status=success`，14/14 场景与 21/21 既有协议探针成功；真实 `SINGBOX_BINARY_113/114` 未配置，相关核心项按规则 skip。该验证没有把 SSH outbound 的状态契约扩大为远端 SSH 握手或公网数据面证据。

### 2026-09-10：Tor outbound typed contract

managed `tor` outbound 不再只是检查 `executable_path`/`data_directory` 是否为字符串。`managed_component_tor_config_validate_json` 按固定 sing-box 1.14.0 `TorOutboundOptions` 及 shared Dial Fields 建立 allowlist：Tor-specific 字段仅允许 `executable_path`、`extra_args`、`data_directory` 和字符串值 `torrc` map；Dial Fields 逐项检查字符串、duration、boolean、network strategy/type 与 routing mark 形状，deprecated `domain_strategy`、控制字符和未知字段在 state/CAS 与 live takeover 前拒绝。未提供 executable path 的记录仍保留上游 embedded 语义，但 inventory 只报告 `runtime_mode=embedded_unverified`；提供路径时报告 `external`，不把默认构建缺少 `with_embedded_tor`+CGO、路径存在或 Tor circuit 当作已验证。

`tests/managed_components_contract.sh` 新增 external/embedded Tor 记录、完整 Dial Fields/torrc/extra_args render、错误类型与控制字符拒绝、运行模式脱敏和 live takeover/路由规则保留断言，同时补齐 SSH 的共享 `protect_path` 字段。此切片只证明状态、候选与无损接管边界；未执行外部 Tor 安装、嵌入构建、控制面、远端 circuit 或真实 Tor 数据面验证。版本统一为本轮 `2026091005`，完整协议目标仍未完成。

完整默认门禁 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260910162713` 退出 0：本地协议/生命周期/组件回归全部通过，Docker `remote_status=success`，14/14 场景和 21/21 既有协议探针成功；真实 `SINGBOX_BINARY_113/114` 未配置，相关核心项按规则 skip。该验证没有把 Tor 状态契约扩大为外部 executable、embedded build、Tor circuit 或公网数据面证据。

### 2026-09-10：selector/urltest outbound group typed contract

managed `selector`/`urltest` outbound group 不再只检查 `outbounds` 是非空字符串数组。`managed_component_group_config_validate_json` 按固定 sing-box 1.14.0 group schema 建立分型 allowlist：两者都要求非空且唯一的 outbound member 列表；selector 只接受可选 `default` 与 `interrupt_exist_connections`，并要求 default 指向成员；URLTest 只接受 `url`、`interval`、`tolerance`、`idle_timeout` 与 `interrupt_exist_connections`，其中 tolerance 限制为 uint16。未知字段、交叉字段、重复成员和错误 scalar 在 state/CAS 与 live takeover 前拒绝；图校验继续解析成员引用并阻断依赖环，inventory 只返回脱敏 `member_count`。

`tests/managed_components_contract.sh` 新增 selector/urltest render、成员重复、default 越界、字段交叉/类型、脱敏成员计数和 live takeover/路由规则保留断言。该切片不宣称 URLTest 探测 URL 可达、定时组切换或真实出站数据面已验证。版本统一为本轮 `2026091006`，完整协议目标仍未完成。

完整默认门禁 `bash dev/verification/run.sh` 在 `dev/verification-runs/20260910171857` 退出 0：本地协议/生命周期/组件回归全部通过，Docker `remote_status=success`，14/14 场景和 21/21 协议探针结果为 `success`；真实 `SINGBOX_BINARY_113/114` 未配置，相关核心项按规则 skip。该验证没有把 selector/urltest 状态契约扩大为探测 URL 可达、动态选路切换或公网数据面证据。

### 2026-09-10：SOCKS outbound typed contract

managed SOCKS outbound 现在通过 `managed_component_socks_config_validate_json` 处理，而不是把注册的 protocol outbound 当作任意 JSON。契约按 sing-box 1.14.0 `SOCKSOutboundOptions` 和 shared Dial Fields 限定 `server`、`server_port`、`version`、认证字段、listable TCP/UDP `network`、UDP-over-TCP 以及拨号参数；deprecated `domain_strategy`、未知字段、错误版本/网络/端口和控制字符在 state/CAS 与 live takeover 前拒绝。统一 component state、配置渲染、图/监听/核心校验、重建、接管与敏感导出路径保持不变，凭据不会进入 list/diagnose inventory。

`tests/managed_components_contract.sh` 增加 SOCKS outbound 正向渲染、默认版本、错误版本/网络/UDP-over-TCP/端口、deprecated 字段和控制字符拒绝断言。固定官方 ARM64 `sing-box` 1.13.18 与 1.14.0 对包含 SOCKS outbound、认证、双网络与 UoT v2 的最小组合配置执行 `check` 均成功；该证据不代表已连接远端 SOCKS 服务或完成真实出站数据面验证。版本统一为本轮 `2026091007`，完整协议目标仍未完成。

### 2026-09-10：HTTP outbound typed contract

managed HTTP outbound 现在通过 `managed_component_http_config_validate_json` 处理。契约按 sing-box 1.14.0 `HTTPOutboundOptions` 限定 TCP-only 的 server/port、用户名/密码、path、HTTP header map、Outbound TLS 以及 shared Dial Fields；TLS 内的 ECH、uTLS、REALITY、listable certificate/ALPN/curve 等嵌套对象也有独立 allowlist 和标量校验。未知或弃用嵌套字段、非法 header 名、错误 scalar/list 和控制字符在 state/CAS 与 live takeover 前拒绝，敏感凭据不出现在 list/diagnose。

`tests/managed_components_contract.sh` 增加 HTTP 明文/TLS render、header/path/TLS 嵌套正向断言，以及未知字段、弃用 ECH 字段、错误 engine/header/scalar 和控制字符拒绝断言。固定官方 ARM64 `sing-box` 1.13.18 与 1.14.0 对明文和启用 TLS 的最小 HTTP outbound 配置 `check` 均成功；该证据不代表远端 HTTP CONNECT 握手或真实出站数据面验证。完整协议目标仍未完成。

### 2026-09-10：Shadowsocks outbound typed contract

managed Shadowsocks outbound 现在通过 `managed_component_shadowsocks_config_validate_json` 处理。契约按固定 1.14.0 `ShadowsocksOutboundOptions`、SIP003、UoT、multiplex 与 shared Dial Fields 限定 server/port、method/password、TCP/UDP network、插件和嵌套选项；SS2022 password 按严格 Base64 解码后的 16/32 字节密钥长度校验，传统加密方法必须有非空密码，`none` 仅在显式配置时保留上游兼容语义。未知/弃用字段、错误方法/密钥长度/插件、错误 scalar/list、嵌套 multiplex/UoT 字段和控制字符在 state/CAS 与 live takeover 前拒绝，凭据不进入 list/diagnose。

`tests/managed_components_contract.sh` 增加 SS2022 128/256、传统 AEAD、插件、双网络/UoT/multiplex render 和认证密钥长度、方法/插件/嵌套字段、deprecated Dial Field 与控制字符拒绝断言。固定官方 ARM64 `sing-box` 1.13.18 与 1.14.0 对 SS2022 128/256、传统 AEAD、插件、双网络/UoT/multiplex 最小组合配置 `check` 均成功；该证据不代表远端 Shadowsocks 握手或真实 TCP/UDP 数据面验证。版本统一为本轮 `2026091008`，完整协议目标仍未完成。

### 2026-09-10：VMess/Trojan outbound typed contract

managed VMess 与 Trojan outbound 现在通过 `managed_component_v2ray_outbound_config_validate_json` 处理，复用 `validate_v2ray_transport_state_json` 的 V2Ray transport 边界，并显式校验 Outbound TLS、multiplex、shared Dial Fields、TCP/UDP network 与协议认证字段。VMess 需要非空 UUID、固定 `security`/`alter_id`/packet encoding；Trojan 需要非空 password。HTTP、无 early data 的 WebSocket、gRPC 与 TLS-only QUIC 可表达；HTTPUpgrade、WS early data、明文 QUIC 和 lite-gRPC `permit_without_stream:true` 在 state/CAS 与 live takeover 前 fail closed。未知或弃用字段、错误 scalar/list、控制字符和无效嵌套 transport 不会进入配置渲染。

`tests/managed_components_contract.sh` 增加 VMess/Trojan render、native/plain 与 HTTP/WS/gRPC/QUIC transport 正向断言，以及认证缺失、security/packet encoding、transport/multiplex/TLS/Dial Field、HTTPUpgrade、WS early data、明文 QUIC、gRPC permit 和控制字符拒绝断言。固定官方 ARM64 `sing-box` 1.13.18 与 1.14.0 对 VMess TLS+WS、Trojan TLS+gRPC 及明文最小 outbound 配置 `check` 均成功；该证据不代表远端握手、TLS 信任、QUIC/UDP 或出站数据面验证。版本保持本轮 `2026091008`，完整协议目标仍未完成。

### 2026-09-10：VLESS outbound typed contract

managed VLESS outbound 复用 `managed_component_v2ray_outbound_config_validate_json`，按固定 1.14.0 `VLESSOutboundOptions` 建立 UUID、flow、TCP/UDP network、packet encoding、Outbound TLS、V2Ray transport、multiplex 与 shared Dial Fields 的 typed allowlist。省略 `packet_encoding` 保留 sing-box 默认 xudp；空 flow 可使用 native HTTP/WS/gRPC/TLS-QUIC，`xtls-rprx-vision` 仅允许启用 TLS 且不携带 transport。HTTPUpgrade、WS early data、明文 QUIC、lite-gRPC `permit_without_stream:true`、错误 flow/transport 组合和未知字段在 state/CAS 与 live takeover 前拒绝。

`tests/managed_components_contract.sh` 增加 VLESS render、plain、Vision、HTTP/WS/gRPC/QUIC、省略 packet encoding 正向断言，以及 Vision/TLS、HTTPUpgrade、WS early data、gRPC permit、明文 QUIC、flow/packet encoding/transport/multiplex/TLS/Dial Field 和控制字符拒绝断言。固定官方 ARM64 `sing-box` 1.13.18 与 1.14.0 的 VLESS TLS+WS、Vision、plain、TLS+gRPC、TLS+QUIC 最小 outbound 配置 `check` 已通过本轮本地固定核心检查；聚焦回归与 Docker 门禁负责记录脚本级证据。核心检查不代表远端 VLESS 握手、TLS 信任或 UDP/出站数据面验证。版本统一为本轮 `2026091009`，完整协议目标仍未完成。

### 2026-09-10：AnyTLS outbound typed contract

managed AnyTLS outbound 现在通过 `managed_component_anytls_config_validate_json` 处理，按固定 sing-box 1.14.0 `AnyTLSOutboundOptions` 和 shared Dial Fields 建立 typed allowlist。`server`、`server_port`、非空 `password` 和启用的 outbound TLS 必填；`idle_session_check_interval`、`idle_session_timeout`、`min_idle_session` 与 `client_metadata` 保留上游可选标量。AnyTLS 没有可配置的 `network`、transport 或 multiplex 字段，且目标 `protocol/anytls` adapter 在 lazy connection 路径拒绝 `tcp_fast_open=true`，因此这些边界在 state/CAS 与 live takeover 前 fail closed。TLS 嵌套对象复用既有 outbound-TLS validator，凭据仍只经敏感 component export 返回。

`tests/managed_components_contract.sh` 增加 AnyTLS render/minimal TLS 正向断言，以及缺少 password/TLS、禁用 TLS、TCP fast open、network/transport/multiplex、metadata/min-idle/port/duration、未知 TLS/Dial Field 和控制字符拒绝断言。固定官方 ARM64 `sing-box` 1.13.18 与 1.14.0 对带 TLS、session fields、client metadata 与 shared Dial Fields 的 AnyTLS outbound 最小配置执行 `check`；该证据只代表目标核心配置解析，不代表远端 AnyTLS 握手或 TCP/UDP 出站数据面。版本统一为本轮 `2026091010`，完整协议目标仍未完成。

### 2026-09-11：Snell outbound typed contract

managed Snell outbound 现在通过 `managed_component_snell_config_validate_json` 处理，按固定 sing-box 1.14.0 `SnellOutboundOptions` 建立版本分型 allowlist。outbound 版本仅允许 `4` 或 `6`：v4 接受 `obfs_mode`/`obfs_host` 的 HTTP obfuscation，v6 接受 `mode` 的 `default`/`unshaped`/`unsafe-raw` traffic shaping；两组字段不可交叉，v6 PSK 至少 12 字节、所有 PSK/userkey 保持安全字符串与 255 字节上限。`server`、`server_port`、PSK、可选 userkey/reuse、TCP/UDP network 与 shared Dial Fields 均逐项校验，未知或弃用字段、重复 network、控制字符和越界端口在 state/CAS 与接管前拒绝。

Snell v5 QUIC proxy 不作为独立 outbound 版本提供；inbound 的 v5/v6 只分别映射到 outbound 的 v4/v6，UDP 业务由 Snell TCP 会话的 packet API 承载。`tests/managed_components_contract.sh` 覆盖 v4/v6 render、字段分型、network/PSK/端口边界、共享拨号字段、接管/导出已有路径和脱敏约束。固定官方 ARM64 `sing-box` 1.14.0 对 v4/v6 最小配置 `check` 均成功，1.13.18 明确返回未知 outbound type；这些核心解析证据不代表远端 Snell 握手或 TCP/UDP 数据面。版本统一为本轮 `2026091011`，完整协议目标仍未完成。

### 2026-09-11：Hysteria2 outbound typed contract

managed Hysteria2 outbound 现在通过 `managed_component_hysteria2_config_validate_json` 处理，按固定 sing-box 1.14.0 `Hysteria2OutboundOptions` 建立 typed allowlist。标准服务器路径支持 `server` 与互斥的 `server_port`/`server_ports`、port hopping、up/down Mbps、salamander/gecko obfs、password、TCP/UDP network、必需 outbound TLS、QUIC fields、BBR profile、Chrome QUIC 控制和 shared Dial Fields；v1 Hysteria 的 `auth`/旧接收窗口字段不会被接受。可选 Hysteria Realm 作为分型对象要求 `server_url`、`realm_id`、非空 STUN 列表，约束 IP version、IPv6 与 port mapping 冲突，并对嵌套 HTTP client/TLS 进行边界校验。

`tests/managed_components_contract.sh` 覆盖标准/Realm render、server-port 关系、TLS/QUIC、obfs 分型、带宽/BBR、deprecated 字段、控制字符、STUN/port-mapping/HTTP-client 负例和敏感导出既有路径。固定官方 ARM64 `sing-box` 1.14.0 对标准 Hysteria2 outbound 配置 `check` 通过；Hysteria2 outbound 在 1.13.18 中仍可被注册，但本增量不把核心解析扩大为远端 QUIC 握手或 UDP 数据面证据。版本统一为本轮 `2026091101`，完整协议目标仍未完成。

### 2026-09-11：Hysteria v1 outbound typed contract

managed Hysteria v1 outbound 现在通过 `managed_component_hysteria_config_validate_json` 处理，按固定 sing-box 1.14.0 `HysteriaOutboundOptions` 建立 typed allowlist。标准路径要求 `server` 与互斥的 `server_port`/`server_ports`，并支持 `hop_interval`、`up`/`down` 网络带宽兼容字段、`up_mbps`/`down_mbps`、字符串 obfs、`auth`/`auth_str`、TCP/UDP network、必需 outbound TLS、QUIC fields 与 shared Dial Fields；每个方向至少声明一种带宽形式，auth 的 Base64/字节数组形状均受约束。

Hysteria v1 的 `recv_window_conn`、`recv_window`、`disable_mtu_discovery` 及 Hysteria2 的 `password`、对象 obfs、BBR/Realm 字段不会混入，未知、弃用、错误分型、控制字符和负带宽在 state/CAS 与接管前拒绝。`tests/managed_components_contract.sh` 覆盖两种带宽/auth 形式、端口范围、TLS/QUIC/network、字段隔离和失败边界；固定官方 ARM64 `sing-box` 1.14.0 全字段配置及 1.13.18 兼容子集 `check` 通过，仍不代表远端 Hysteria 握手或 UDP 数据面。版本统一为本轮 `2026091102`，完整协议目标仍未完成。

### 2026-09-11：TUIC outbound typed contract

managed TUIC outbound 现在通过 `managed_component_tuic_config_validate_json` 处理，按固定 sing-box 1.14.0 `TUICOutboundOptions` 建立 typed allowlist。标准路径要求 server/server_port、规范 UUID、可选 password、拥塞控制、native/quic UDP relay、可选 UDP-over-stream、zero-RTT、heartbeat、TCP/UDP network、必需 outbound TLS、QUIC fields 与 shared Dial Fields；`udp_relay_mode` 与 `udp_over_stream` 冲突以及未知/弃用字段在 state/CAS 与接管前拒绝。

`tests/managed_components_contract.sh` 覆盖完整/字符串 network、native/quic relay、UDP-over-stream、TLS/QUIC、UUID/端口/密码/拥塞控制边界、冲突组合和敏感导出既有路径。固定官方 ARM64 `sing-box` 1.14.0 全字段配置及 1.13.18 兼容子集配置 `check` 通过；较新的 QUIC 字段在 1.13.18 中按预期不可用，仍不代表远端 TUIC 握手或 UDP 数据面。版本统一为本轮 `2026091103`，完整协议目标仍未完成。

### 2026-09-11：NaiveProxy 与 ShadowTLS outbound typed contracts

managed NaiveProxy outbound 现在通过 `managed_component_naive_config_validate_json` 处理，按固定 sing-box 1.14.0 `NaiveOutboundOptions` 建立 typed allowlist。标准路径保留 server/server_port、username/password、extra headers、HTTP/2 或 QUIC、UDP-over-TCP、stream/QUIC session receive windows、QUIC congestion control 及 shared Dial Fields；TLS 只接受 Naive 官方支持的 enabled、server_name、certificate、certificate_path、ECH 字段。非零 `insecure_concurrency` 与 QUIC 的目标 adapter 冲突，unsupported TLS、错误 UoT/header/window、控制字符、未知或弃用字段均在 state/CAS 与接管前拒绝；`with_naive_outbound`/`libcronet.so` 仍由环境门控，不从 `check` 推断运行库已加载。

managed ShadowTLS outbound 现在通过 `managed_component_shadowtls_config_validate_json` 处理，按固定 sing-box 1.14.0 `ShadowTLSOutboundOptions` 建立 TCP-only wrapper allowlist。标准路径保留 server/server_port、版本 1–3、可选 password、必需 outbound TLS 与 shared Dial Fields，并与本项目 ShadowTLS 入站的 outer + loopback Mixed composite 分离；未知/弃用字段、错误版本/网络/控制字符和缺少 TLS 在 state/CAS 与接管前拒绝。

`tests/managed_components_contract.sh` 新增 Naive/ShadowTLS outbound render、TLS/UoT/QUIC/headers/window、版本与角色隔离、运行时冲突和敏感字段负例。固定官方 ARM64 `sing-box` 1.14.0 完整 Naive（`bbr2`）与 ShadowTLS 配置、1.13.18 兼容 Naive 子集与 ShadowTLS 配置 `check` 均通过；核心检查不代表 libcronet 加载、远端握手或 TCP/UDP 数据面。版本统一为本轮 `2026091104`，完整协议目标仍未完成。

### 2026-09-11：WireGuard endpoint typed contract

managed WireGuard endpoint 现在通过 `managed_component_wireguard_config_validate_json` 处理，明确使用 sing-box 现代 `WireGuardEndpointOptions`，不恢复已移除的 wireguard outbound。状态层校验标准 32-byte Base64 private/public/PSK、listable CIDR address 与 peer allowed_ips、peer keepalive/reserved tuple、MTU/listen/workers、UDP NAT 行为和 shared Dial Fields；未知/弃用字段、错误 key/prefix、越界 tuple/NAT 值在 state/CAS 与 live takeover 前拒绝。

`tests/managed_components_contract.sh` 新增 WireGuard typed render、scalar/listable 兼容、key/prefix/peer/NAT/未知字段负例，并将 takeover fixture 改为真实形状的 Base64 key。固定官方 ARM64 `sing-box` 1.14.0 全字段 endpoint 与 1.13.18 基础 endpoint 子集 `check` 均通过；这只证明配置解析，不代表系统接口权限、peer 握手或 UDP 数据面。版本统一为本轮 `2026091105`，完整协议目标仍未完成。

### 2026-09-11：Tailscale/OpenConnect/OpenVPN endpoint typed contracts

managed Tailscale endpoint 现在按固定 1.14 `TailscaleEndpointOptions` 校验持久化 state/auth/control、route advertisement、relay AddrPort、exit-node 互斥、可选 SSH 和 shared Dial Fields；OpenConnect endpoint 按 client-only `OpenConnectEndpointOptions` 校验 flavor、token secret/path、mobile identity、CSD/HIP/TNCC、TLS material、form-entry 配对以及压缩/keepalive 互斥；OpenVPN client/server endpoint 分别按 TLS/static_key union 校验 remote、address pool/family、证书和密钥 material、control wrapping、users、push DNS/routes 与 TCP/UDP 约束。PEM/key inline material 可含 LF/CR，路径和普通字段仍拒绝控制字符；未知字段和不合法组合在 state/CAS 与 takeover 前失败。

`tests/managed_components_contract.sh` 新增四类 endpoint 的 render、凭据/材料形状、route/family、TLS/static-key、token/mobile、control-wrap、push DNS 和未知字段负例。固定核心 check 与组件 state/render 只证明本地配置边界；未执行 Tailscale/OpenConnect/OpenVPN 外部认证、证书文件加载、系统接口权限或真实 TCP/UDP 数据面验证。本轮版本统一为 `2026091106`，完整协议目标仍未完成。

### 2026-09-11：组件环境构建 tag 门控

组件 registry 的每次环境读取现在解析目标 `sing-box version` 的 `Tags:` 行，并把已排序、校验过的 tag 列表放入 `environment.core.build_tags`。记录声明 `with_quic`、`with_wireguard`、`with_tailscale`、`with_openconnect`、`with_openvpn`、`with_cloudflared` 或 `with_naive_outbound` 时，已报告但缺失所需 tag 的组件返回 `unavailable`；包装器或旧二进制没有 `Tags:` 行时返回 `not_assessed`，不会把未知构建误报为可用。Hysteria、Hysteria2 与 TUIC outbound 的 registry 条件同步标记为 `with_quic`；Naive 的 `libcronet.so`、外部认证、系统权限和真实数据面仍是独立依赖。

`tests/managed_component_availability.sh` 新增已报告 tag、缺失 `with_quic` 与未报告 tag 的正负门禁，固定官方 1.14.0 ARM64 包的解析结果也保持无凭据、排序和最小字段输出。该切片只改善构建变体可见性，不把 `Tags:`、版本检查或 `sing-box check` 扩大为外部控制面或 TCP/UDP 数据面验证。版本统一为本轮 `2026091107`，完整协议目标仍未完成。

### 2026-09-11：Hysteria v1/Hysteria2 Docker 数据面探针

本轮将 Hysteria v1 从“仅配置/生命周期”推进到可重复的 TCP/UDP payload 业务探针：新增 `tests/verification_protocol_probe_hysteria.sh` 与 `fresh_install_hysteria`，使用受管 typed store/exporter 生成单用户客户端，显式保留 `auth_str`、`up_mbps/down_mbps`、公开证书和 `h3` ALPN；QUIC 初始包/最大并发为 `0` 时按上游默认值接受。服务端使用持久于验证容器的 SAN 证书，客户端经本地 SOCKS 访问 Python HTTP marker，避免将第二用户凭据、私钥或公网可达性写入 artifact。

新增 `verification_execute_protocol_udp_probe` 作为可复用的真实 UDP 探针：它先对 exporter 生成的客户端配置执行 `sing-box check`，再启动本地 UDP echo，运行客户端核心并通过 SOCKS5 UDP ASSOCIATE 发送带协议标识的 marker，严格校验返回 payload 完全一致；探针记录 check、客户端路径、响应、stderr 和 `udp.result.env`，失败时清理自身进程及临时目录，不接触 systemd 管理的服务。`fresh_install_hysteria` 调用它验证 Hysteria v1，`multi_protocol_coexistence` 调用它验证 Hysteria2。

完整 Docker run `dev/verification-runs/20260911154013` 的 16/16 场景与 23/23 协议探针均 success；Hysteria 与 Hysteria2 的 `udp.result.env` 均为 `RESULT=success`，对应 artifact 的 `udp-response.txt` 保留精确 marker。独立 fixture `tests/verification_protocol_probe_udp.sh` 覆盖 SOCKS5 协商、UDP ASSOCIATE、响应解析、artifact 和清理边界。该证据仍限定在固定 1.14.0 核心的隔离 Docker 回环，不扩张为公网 UDP、防火墙/路由、外部认证、生产部署或其他尚未接入探针的协议/Endpoint 数据面；完整协议目标仍未完成。

### 2026-09-11：TUIC UDP 数据面与 exporter ALPN 修复

从上一阶段的 Hysteria v1/Hysteria2 探针继续推进，新增 `verification_generate_tuic_probe_client` 与严格的 TUIC marker/store loader。生成器只接受活动 schema-2 marker、schema-1 typed store 和当前配置中选出的 TUIC tag，随后复用生产 `build_client_tuic_outbounds`；客户端 JSON 保留逐用户 UUID/password、`network:["tcp","udp"]`、native/quic relay 或 udp-over-stream、拥塞控制、heartbeat、zero-rtt、公开证书信任，并拒绝写入私钥。

真实共存场景新增 TUIC typed instance（手工 SAN 证书、native relay、bbr、auth timeout/heartbeat），验证服务端只渲染核心接受的 users/TLS+h3/拥塞/超时字段，监听计划包含 UDP，固定 1.14.0 `sing-box check` 通过。期间发现 exporter 未将客户端 TLS ALPN 与服务端 renderer 的 `h3` 对齐，真实核心报 `CRYPTO_ERROR ... no application protocol`；生产 exporter 已修复为始终输出 `tls.alpn:["h3"]`，并由生命周期、registry 与探针测试锁定。

`multi_protocol_coexistence` 现在启动固定核心客户端，经 SOCKS5 UDP ASSOCIATE 把 marker 穿过 SS2022 原生 UDP、Trojan QUIC、TUIC QUIC/UDP 与 VMess QUIC 至本地 echo 并精确回读；同时修正 VMess/VLESS QUIC exporter 将 proxy network 错误限制为 UDP-only 的问题，保留 `tcp+udp`。完整 Docker run `dev/verification-runs/20260911194118` 记录 16/16 场景、24/24 常规协议探针和六个 QUIC/UDP artifact（Hysteria、Hysteria2、SS2022、Trojan、TUIC、VMess）成功。证据只属于隔离容器/回环和固定 1.14.0 核心，不扩张为公网可达、生产部署、外部认证、SubMan 或全协议目标完成；本阶段版本保持 `2026091110`。
