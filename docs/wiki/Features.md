# 功能与限制

- 15 个入站预设，支持多实例和按协议管理。
- 生成和修改配置时运行 `sing-box check`，并为关键变更保留备份与回滚路径。
- 提供交互菜单与 `sbv agent` JSON 命令；客户端配置可导出并校验。


- **Agent 友好命令行**：提供 `sbv agent ... --json` 非交互命令，方便 Hermes、OpenClaw、Codex 等 AI Agent 发现完整能力、获取状态与节点信息、导出客户端配置，并执行带预检、确认、持久备份和自动回滚的固定版本升级。所有 `--json` 响应采用 `schema_version: "1.0"` 统一 envelope，同时保留兼容字段 `schema: "1"`；对外协议 ID 统一使用 `vless-reality`、`vless-plain`、`mixed`、`socks`、`http`、`shadowsocks`、`trojan`、`vmess`、`hysteria2`、`hysteria`、`anytls`、`snell`、`tuic`、`naive`、`shadowtls`。
- **1.14.x 深度适配**：继续采用 **Endpoint（端点化）** 架构，并适配顶层 ACME `certificate_providers`、可复用 `http_clients`、远程规则集 `http_client` 与 Hysteria2 `disable_chrome_parrot`。
- **跨版本配置生成**：目标核心为 1.14+ 时生成新版配置结构；显式固定或运行 1.13.x 时继续生成内联 `tls.acme` 与旧版远程规则集结构。受管 shared `http_client` 只在 1.14+ 顶层配置中渲染；接管或重建时会保留可内联表达的 ACME 扩展字段，未注册或发生 drift 的 shared client 会拒绝重写。仅更新二进制时不会重写现有配置。
- **托管 route rule-set**：高级组件 Agent 现在可用同一 revision/CAS 事务管理 inline、local、remote 三种 `route.rule_set`；inline 只接受有界 matcher rules，local 文件按引用使用且不会随删除清理，remote URL 与 1.14+ named `http_client` 引用受控校验。生成、接管、删除保护和 live drift 检查复用组件生命周期；规则集不作为普通代理节点导出、分享或同步 SubMan，URL 等完整配置只经敏感 component export 返回。
- **可审计升级**：`upgrade-check` 会报告实例健康度、当前配置校验、配置 SHA-256、1.14 已知弃用项和阻断原因；`upgrade` 只接受固定版本与 `--yes`，先在 `/root/sing-box-vps-backups/` 创建 root-only 备份，并原子维护 `transaction-result.json`（事务 ID、旧/新版本、状态历史、manifest hash 与回滚结果）。目标核心校验失败时尝试恢复旧二进制并返回非零；若恢复未通过最终校验，会明确返回 `rollback_failed` 和人工介入标记。
- **多协议支持**：支持 **VLESS + REALITY**、普通 **VLESS**、**Mixed (HTTP/HTTPS/SOCKS)**、**独立 SOCKS**、**独立 HTTP（可选入口 TLS）**、**Shadowsocks**、**Trojan**、**VMess**、**Hysteria2**、**Hysteria v1**、**AnyTLS**、**Snell**、**TUIC**、**NaiveProxy** 与 **ShadowTLS** 十五个入站预设。已有服务新增 HTTP、Shadowsocks、Trojan、VMess、普通 VLESS、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 或 ShadowTLS 时单独进入共享实例事务，不与其他协议合并追加；全协议目标仍未完成。
- **Mixed 多实例管理**：schema 2 支持多个稳定 ID/tag、独立监听地址/端口、独立认证和默认实例；Agent 提供 `create`、`replace`、`delete`、`default`、`migrate`、`recover`，交互菜单 2 选择 Mixed 后提供逐实例管理。非回环明文监听需要显式公网暴露确认；跨协议批量删除会拒绝并要求逐实例处理 Mixed。
- **VLESS REALITY 多实例**：可在安装菜单追加多个 REALITY 实例，每个实例拥有独立端口、ShortID、节点名称、可选上下行限速和实例级出站策略；节点展示和 SubMan 同步会逐实例输出。
- **REALITY SNI 探测**：安装、更新和新增实例可通过 [reality-target-checker](https://github.com/KnowSky404/reality-target-checker) 检查自行提供的候选域名；没有固定推荐列表或失败默认域名，附加风险默认拒绝，接受前明确确认。用法与依赖见 [快速开始](https://github.com/KnowSky404/sing-box-vps/wiki/Getting-Started#reality-sni-探测)。
- **REALITY QoS 限速**：为设置了上下行 Mbps 的 REALITY 实例自动规划并应用 `tc` 端口级限速规则，重建配置、更新协议或移除实例时会同步刷新规则，避免遗留过滤器影响新配置。
- **Cloudflare Warp 集成**：支持一键开启/关闭 Warp 出站，自动注册免费账户，为选定流量提供 Warp 出口；流媒体可用性取决于网络与服务策略。
- **Warp 路由分层**：支持 `全量走 Warp` 与 `选择性分流` 两种模式，默认采用更稳妥的 `选择性分流`，内置主流 AI / 流媒体域名规则，并支持用户追加自定义域名、本地规则集和远程规则集；VLESS REALITY 实例还可单独选择跟随全局、强制 direct 或强制 Warp 出口。
- **单一真源**：统一以 `install.sh` 作为安装与维护入口，避免历史旧入口与当前实现漂移。
- **透明入站宿主策略**：可选 TProxy `host_policy` 仅拥有显式 ingress interface 与目标端口的 IPv4/TCP+UDP 规则、专用 fwmark 策略路由和 local route table；未配置 `host_policy` 的 TProxy/Redirect 仍归操作员管理。2026-09-22 TProxy `host_policy` 验收仅覆盖特权隔离 Docker 中的回环探针，不代表公网或生产环境已验证。
- **托管实例自修复**：当协议状态层与运行中的 `config.json` 发生漂移时，会优先按协议状态自动重建运行配置，降低 `mixed` 等附加协议意外丢失的风险。
- **配置事务发布**：交互式新增、修改、协议栈、Warp 与删除操作会先快照完整托管状态；服务端配置写入同目录 candidate，并依次通过 `jq` 与当前 sing-box 核心的 `check`，仅在校验成功后保留上一版 `config.json.bak` 并原子替换 live config。生成器、certificate provider 或状态写入失败会恢复配置与协议状态。
- **环境自适应**：支持架构探测（amd64/arm64）及主流发行版（Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux）。
- **默认安全设置**：默认开启流量嗅探、uTLS 指纹、多 ShortID 随机化及持久化密钥管理。
- **性能增强**：集成 **BBR** 一键开启功能，可按需调整 TCP 拥塞控制。
- **Mixed 防火墙事务**：启用 UFW 时仅通过 UFW 管理归属规则；没有活动防火墙前端时才直接管理 `iptables`/`ip6tables`。firewalld 仅执行只读外部预检，不由实例事务 add/delete/reload；UFW 与 firewalld 同时活动或已有账本与当前后端冲突时拒绝写入，要求人工处理。
- **配置生成**：采用 **`jq` 安全注入** 模式生成 JSON，彻底规避特殊字符导致的转义错误。
- **协议级展示**：终端可按协议查看节点信息，支持 `VLESS`、`VMess` 与 `Hysteria2` 链接/ANSI 二维码展示，为 `Mixed` 和独立 `SOCKS` 输出代理链接与二维码提示，并为 `Hysteria`、`AnyTLS`、`Snell`、`TUIC`、`NaiveProxy`、`ShadowTLS` 输出逐实例参数摘要和 sing-box outbound JSON（无标准 URI）；多 REALITY、普通 VLESS、Mixed、SOCKS、Trojan、VMess、Hysteria2、Hysteria、AnyTLS、Snell、TUIC、NaiveProxy、ShadowTLS 实例会显示实例 ID、端口和限速摘要。
- **裸核客户端导出**：可从交互菜单或 `sbv agent export-client --json` 生成 `/root/sing-box-vps/client/sing-box-client.json`，支持当前十五个预设，覆盖前自动备份，并在输出前执行 `sing-box check`。Mixed 和独立 SOCKS 使用 SOCKS5 outbound 与 UoT v2，VMess/Trojan/普通 VLESS/Hysteria2/Hysteria/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS 按用户保留认证、TLS 与传输；Naive outbound 依赖官方 `with_naive_outbound` 构建和运行时 `libcronet.so`，缺失或无效的端口/认证字段会阻断整份导出，保留原导出及备份，不自动生成密码或降级认证。
- **Mixed 安全边界**：Mixed 服务端和其导出的 SOCKS5/UoT 链路不提供 TLS；公网明文监听必须经过单独确认，不能把它当作独立的 TLS SOCKS 服务端。Mixed 当前也不新增 SubMan 同步能力。
- **独立 SOCKS**：注册表菜单项 5 使用 `socks` state/Agent ID，active marker 为 schema 2、JSON store 为 `schema_version: 1`，支持同认证 typed record、共享事务与实例级 CAS；服务端无 HTTP/TLS，客户端导出为 SOCKS5 + UoT v2；不提供原生 UDP listener、TLS、HTTP 或 SubMan 同步。
- **独立 HTTP**：菜单项 6、管理菜单 19，使用 `http` state/Agent ID 与 schema 2 共享实例事务。默认回环监听并启用认证，可选择明文或手工证书 TLS；证书文件由用户维护，实例操作不申请或删除它们。客户端导出为 TCP-only HTTP CONNECT；TLS 导出仅嵌入公开证书信任与 SNI，不读取私钥。明文 URI 返回 `http_plaintext_transport`；TLS 无可保真 URI，返回 `http_tls_uri_unrepresentable` 并使用完整 JSON。访问 HTTPS 目标不等于代理入口已加密；不支持 HTTP SubMan 同步。
- **Shadowsocks**：安装菜单 7、管理菜单 20，协议 ID `shadowsocks`（别名 `ss`），使用 schema 2 marker 与 schema 1 JSON 实例库。支持九种入站方法、可用方法的多用户、实例出站策略和 TCP/UDP 独立选择；默认回环监听，非回环写入需确认。`none` 是明文，2022 ChaCha 不支持多用户；不接管未建模的 relay、mux 或 plugin。完整 JSON 保留网络限制；SIP002 无法表达单网络限制时返回 warning。长 2022 PSK 在客户端按核心规则派生等效定长密钥，原始状态不变。
- **VMess**：安装菜单 9、管理菜单 22，协议 ID `vmess`，使用 schema 2 marker 与 schema 1 JSON 实例库。支持 1–128 个唯一用户、`security`/`alter_id`、TLS 信任和 none/http/ws/grpc/quic typed transport；WS early data 与 HTTPUpgrade 仍按已知 runtime guard 阻断。客户端导出和 `vmess://` 分享保留可表达字段，不读取服务器私钥；SubMan 仅同步 TLS 系统信任且 URI 无损可表达的用户。
- **普通 VLESS**：安装菜单 10、管理菜单 23，协议 ID `vless-plain`（运行时 type 仍为 `vless`），使用独立 schema 2 marker 与 schema 1 JSON 实例库。支持 1–128 个用户、按用户 `flow`、TLS 信任和 none/http/ws/grpc/quic typed transport；客户端导出和 `vless://` 分享不读取服务器私钥，SubMan 仅同步 TLS 系统信任且 URI 无损可表达的用户。旧 `vless` alias 不会被重新解释，仍表示 VLESS + REALITY。
- **Hysteria v1**：安装菜单 13、管理菜单 28，协议 ID `hysteria`，使用 schema 2 marker 与 schema 1 JSON 实例库。支持 1–128 个唯一 `name`/`auth_str` 用户、必需手工 TLS、`certificate`/`system` 客户端信任、独立上下行带宽、字符串 obfs 与 QUIC 窗口/MTU/并发流参数；服务端只渲染 Hysteria v1 字段，不混入 Hysteria2 的密码或 masquerade。客户端按用户导出完整 outbound JSON，`links` 返回 `hysteria_standard_uri_unavailable`，不执行 SubMan 同步；非回环监听仍须显式确认。
- **SubMan 同步**：按 SubMan OpenAPI 1.0.0 契约将 VLESS + REALITY、普通 VLESS、Hysteria2、双网络加密 Shadowsocks，以及 TLS 系统信任且 URI 无损表达的 Trojan/VMess 用户幂等推送到节点库；Hysteria v1、Snell、TUIC、NaiveProxy、AnyTLS 与 ShadowTLS 因无标准无损 URI，明确保持 unsupported，不伪装成 `other`。各协议按实例/用户使用稳定外部键，从同一快照生成身份与凭据，无法表达的 TLS、传输、证书信任或 URI 大小条目明确跳过。Hysteria2 的带宽和 masquerade、Hysteria v1 的带宽/obfs/QUIC 选项在完整客户端 JSON 中保留，标准 URI 无法携带时仅以 warning 披露，不伪造 SubMan 字段。仅在 Workspace 已远端提交并回读验证后报告成功，并识别 revision、稳定错误分类和安全重试提示。集成测试使用 mock，不代表已授权或执行真实同步；全部跳过不报告同步成功。
- **规范存储**：统一使用 `/root/sing-box-vps/` 存放配置、密钥及持久化参数。
