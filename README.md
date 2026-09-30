# sing-box-vps

面向 VPS 的 sing-box 安装与管理脚本。通过交互菜单部署协议、维护服务、导出客户端配置；安装器会校验配置并保留关键变更的备份。

- **当前适配：1.14.2**；显式固定 1.13.x 时保留对应配置生成路径。
- 脚本版本：`2026093001`
- sing-box 适配版本：`1.14.2`
- **运行环境：** Debian 11+、Ubuntu 20.04+、CentOS 7+/Stream、AlmaLinux、Rocky Linux；需要 root 权限。

[快速安装](#快速安装) · [常用命令](#常用命令) · [项目特性](#项目特性) · [Agent 命令](#agent-非交互命令) · [功能菜单](#功能菜单) · [能力矩阵](docs/superpowers/specs/2026-09-06-protocol-coverage.md)

## 快速安装

在 VPS 上复制这一行：

```bash
bash -c 'set -euo pipefail; umask 077; t=$(mktemp); trap '\''rm -f -- "$t"'\'' EXIT; curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -o "$t" https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/bootstrap.sh; bash -n "$t"; grep -Fqx '\''readonly PROJECT_AUTHOR="KnowSky404"'\'' "$t"; grep -Fqx '\''readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"'\'' "$t"; bash "$t" install'
```

首段命令先把仓库内的 [bootstrap.sh](bootstrap.sh) 下载到权限受限的临时文件，检查 Bash 语法和项目身份，然后运行它。Bootstrap 再下载并校验 [install.sh](install.sh)，校验失败不会执行安装器；两层临时文件都会清理。下载来源是仓库 `main` 分支；如需先审查源码，可克隆仓库后运行 `sudo bash install.sh`。

安装完成后，在任意目录输入 `sbv` 打开管理菜单。要彻底卸载，可从克隆的仓库运行 `sudo bash uninstall.sh --yes` 或 `sudo bash bootstrap.sh uninstall --yes`；菜单里的“卸载 sing-box”会删除服务、核心和配置，但会保留 `sbv` 管理命令，独立卸载脚本还会删除全局 `sbv`。

## 常用命令

| 操作 | 命令 |
| --- | --- |
| 打开交互菜单 | `sbv` |
| 查看状态 | `sbv agent status --json` |
| 检查运行配置 | `sbv agent check --json` |
| 查看 Agent 能力 | `sbv agent capabilities --json` |
| 检查指定核心版本的升级条件 | `sbv agent upgrade-check --json 1.14.0` |

主要支持 VLESS + REALITY、普通 VLESS、Mixed、SOCKS、HTTP、Shadowsocks、Trojan、VMess、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 和 ShadowTLS 入站。每种协议的运行条件、导出和验证范围见[能力矩阵](docs/superpowers/specs/2026-09-06-protocol-coverage.md)。

## 项目特性

- 15 个入站预设，支持多实例和按协议管理。
- 生成和修改配置时运行 `sing-box check`，并为关键变更保留备份与回滚路径。
- 提供交互菜单与 `sbv agent` JSON 命令；客户端配置可导出并校验。

<details>
<summary>查看详细能力与协议限制</summary>

- **Agent 友好命令行**：提供 `sbv agent ... --json` 非交互命令，方便 Hermes、OpenClaw、Codex 等 AI Agent 发现完整能力、获取状态与节点信息、导出客户端配置，并执行带预检、确认、持久备份和自动回滚的固定版本升级。所有 `--json` 响应采用 `schema_version: "1.0"` 统一 envelope，同时保留兼容字段 `schema: "1"`；对外协议 ID 统一使用 `vless-reality`、`vless-plain`、`mixed`、`socks`、`http`、`shadowsocks`、`trojan`、`vmess`、`hysteria2`、`hysteria`、`anytls`、`snell`、`tuic`、`naive`、`shadowtls`。
- **1.14.x 深度适配**：继续采用 **Endpoint（端点化）** 架构，并适配顶层 ACME `certificate_providers`、可复用 `http_clients`、远程规则集 `http_client` 与 Hysteria2 `disable_chrome_parrot`。
- **跨版本配置生成**：目标核心为 1.14+ 时生成新版配置结构；显式固定或运行 1.13.x 时继续生成内联 `tls.acme` 与旧版远程规则集结构。受管 shared `http_client` 只在 1.14+ 顶层配置中渲染；接管或重建时会保留可内联表达的 ACME 扩展字段，未注册或发生 drift 的 shared client 会拒绝重写。仅更新二进制时不会重写现有配置。
- **托管 route rule-set**：高级组件 Agent 现在可用同一 revision/CAS 事务管理 inline、local、remote 三种 `route.rule_set`；inline 只接受有界 matcher rules，local 文件按引用使用且不会随删除清理，remote URL 与 1.14+ named `http_client` 引用受控校验。生成、接管、删除保护和 live drift 检查复用组件生命周期；规则集不作为普通代理节点导出、分享或同步 SubMan，URL 等完整配置只经敏感 component export 返回。
- **可审计升级**：`upgrade-check` 会报告实例健康度、当前配置校验、配置 SHA-256、1.14 已知弃用项和阻断原因；`upgrade` 只接受固定版本与 `--yes`，先在 `/root/sing-box-vps-backups/` 创建 root-only 备份，并原子维护 `transaction-result.json`（事务 ID、旧/新版本、状态历史、manifest hash 与回滚结果）。目标核心校验失败时尝试恢复旧二进制并返回非零；若恢复未通过最终校验，会明确返回 `rollback_failed` 和人工介入标记。
- **多协议支持**：支持 **VLESS + REALITY**、普通 **VLESS**、**Mixed (HTTP/HTTPS/SOCKS)**、**独立 SOCKS**、**独立 HTTP（可选入口 TLS）**、**Shadowsocks**、**Trojan**、**VMess**、**Hysteria2**、**Hysteria v1**、**AnyTLS**、**Snell**、**TUIC**、**NaiveProxy** 与 **ShadowTLS** 十五个入站预设。已有服务新增 HTTP、Shadowsocks、Trojan、VMess、普通 VLESS、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 或 ShadowTLS 时单独进入共享实例事务，不与其他协议合并追加；全协议目标仍未完成。
- **Mixed 多实例管理**：schema 2 支持多个稳定 ID/tag、独立监听地址/端口、独立认证和默认实例；Agent 提供 `create`、`replace`、`delete`、`default`、`migrate`、`recover`，交互菜单 17 提供逐实例管理。非回环明文监听需要显式公网暴露确认；跨协议批量删除会拒绝并要求逐实例处理 Mixed。
- **VLESS REALITY 多实例**：可在安装菜单追加多个 REALITY 实例，每个实例拥有独立端口、ShortID、节点名称、可选上下行限速和实例级出站策略；节点展示和 SubMan 同步会逐实例输出。
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

</details>

## Agent 非交互命令

适合在 SSH 会话中查询状态、导出配置或执行受控操作。常用只读命令见上方；完整命令和事务语义如下。

<details>
<summary>查看完整 Agent 命令与升级说明</summary>

```bash
sbv agent capabilities --json
sbv agent upgrade-check --json 1.14.0
sbv agent upgrade --json 1.14.0 --yes
sbv agent status --json
sbv agent nodes --json
sbv agent links --json
sbv agent export-client --json
sbv agent check --json
sbv agent doctor --json
sbv agent service restart --json --yes
sbv agent warp --json
sbv agent subman-sync --json
sbv agent component list --json
sbv agent component diagnose --json
sbv agent component export --json --id ID [--expected-revision N]  # 敏感输出
sbv agent component recover --json --yes --expected-revision N
sbv agent component takeover --json --yes --expected-revision N [--allow-public]
sbv agent component rebuild --json --yes --expected-revision N
sbv agent component create|replace --json --yes --expected-revision N --file component.json [--allow-public]
sbv agent component delete --json --yes --expected-revision N --id ID
sbv agent instance view <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance diagnose <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance export <protocol> --json [--id ID] [--expected-revision N]  # 敏感输出
sbv agent instance create|replace <protocol> --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance delete|default <protocol> --json --yes --expected-revision N --id ID
sbv agent instance rebuild <protocol> --json --yes --expected-revision N
sbv agent instance takeover <protocol> --json --yes --expected-revision 0 [--allow-public]
sbv agent instance migrate mixed --json --yes --expected-revision N
sbv agent instance recover <protocol> --json --yes --expected-revision N
sbv update sbv
sbv update sing-box latest
sbv update sing-box 1.14.2
```

代码块中的 `create|replace`、`delete|default` 只是二选一记法，实际执行时
只保留一个操作词；`<protocol>` 替换为支持的协议 ID，并从同一状态快照
读取 `--expected-revision`。

其中 `<protocol>` 的只读入口支持 `vless-reality`、`mixed`、`socks`、`http`、`shadowsocks`、`trojan`、`vmess`、`vless-plain`、`anytls`、`hy2`、`snell`、`tuic`、`hysteria`、`naive` 和 `shadowtls`；写入口支持除 `vless-reality` 外的其余协议，只有 `mixed` 支持 `migrate`。`view` 和 `diagnose` 默认脱敏，`export`、`links`、`export-client` 与 `subman-sync` 应只在受信上下文使用。

- `capabilities`：输出协议、历史功能入口与 `mutation` / `sensitive` / 确认要求，Agent 应先据此选择操作。旧 `protocol_registry` 保持兼容，并为每个协议增加只读 `environment` 核心版本/构建依赖观察；`managed_registry` 将普通协议与高级组件按 role 合并，使用 `registry_kind` 区分来源。协议级 `available=null` 仍表示尚未完成实例预检，`validated.status=not_assessed` 表示没有该实例的数据面验证；环境依赖满足不等于已部署或连接通过。
- `upgrade-check`：只读检查固定目标版本的升级资格，返回 `ready`、`blockers[]`、当前核心校验、配置 hash、已知弃用项和兼容性 warning；不会协调或迁移协议状态，也不下载目标二进制，真正的目标版本 `sing-box check` 在 `upgrade` 替换服务进程前执行。
- `upgrade`：必须使用完整版本号和 `--yes`。创建持久备份后只替换核心二进制，逐字节保留服务端配置；备份清单覆盖全部普通 runtime 文件及 binary、`sbv`、service unit、metadata。每次实际变更返回 `transaction.id`、`transaction.result_path` 和 `transaction.result_persisted`，并在备份目录原子写入权限 `0600` 的 `transaction-result.json`。实际变更只有 `result_persisted=true` 才可接受事务状态；若目标版本已经安装，则返回 `changed=false`、`transaction.status=not_attempted`、`reason=already_installed`，且不会创建备份或事务文件。目标校验、版本、配置 hash 或服务状态不符合预期时尝试自动恢复旧二进制、意外变化的配置和升级前服务活动状态，返回非零与结构化回滚结果。仅当 `rolled_back=true` 且 `rollback_ok=true` 时才可视为自动恢复完成；`error=rollback_failed` 时必须停止并人工处理。
- `status`：输出脚本/核心/服务/路径/已安装协议，并包含入站与出站栈、BBR、REALITY 实例与 QoS 计数，以及客户端导出/SubMan 是否已配置；不返回凭据。索引、状态或 live 入站集合无法完整对应时返回非零及 `protocol_index_untrusted` / `protocol_state_untrusted`，不报告部分协议。
- `nodes`：输出所有协议的安全摘要；REALITY、Mixed、SOCKS、HTTP、Shadowsocks、Trojan、VMess、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 和 ShadowTLS 均逐实例输出，`instance_revision` 可用于下一次 CAS 写入；不包含 UUID、密钥、完整分享链接或密码，适合写入普通诊断日志。实例清单、状态与 live 入站不完整时不输出部分节点。
- `links`：逐协议、逐 REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS 实例输出完整连接材料，包括 VLESS/VMess/Hysteria2 分享链接、Mixed/SOCKS 链接，以及 Hysteria/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS outbound JSON；Hysteria、AnyTLS、Snell、TUIC、NaiveProxy、ShadowTLS 分别返回 `hysteria_standard_uri_unavailable`、`anytls_standard_uri_unavailable`、`snell_standard_uri_unavailable`、`tuic_standard_uri_unavailable`、`naive_standard_uri_unavailable`、`shadowtls_standard_uri_unavailable` warning；Naive 还返回 `naive_libcronet_required`，仅在受信任上下文使用，并沿用与 `nodes` 相同的全有或全无清单门禁。Hysteria2 手动 Ed25519 证书会附带稳定的 `warnings[].code`，提示分享链接无法表达 1.14+ 客户端兼容开关。
- `warp`：输出 Cloudflare Warp 状态（启用/路由模式/账户/自定义域名规则集统计），安全用于日常诊断。
- `export-client`：生成并通过 `sing-box check` 校验裸核客户端配置，写入 `/root/sing-box-vps/client/sing-box-client.json`，覆盖前创建 `.bak` 备份，同时以 JSON 返回路径和配置内容。对 1.14+ Hysteria2 Ed25519 节点会自动设置顶层 `disable_chrome_parrot: true` 并返回结构化 warning。包含 Mixed 或独立 SOCKS 时逐实例导出为 SOCKS5 + UoT v2，并返回明文传输 warning；Trojan/VMess/普通 VLESS/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS 按用户完整导出传输与明确的证书信任方式，不读取服务端私钥，不自动关闭验证。Naive outbound 需要官方 `with_naive_outbound` 和 `libcronet.so`；VMess URI 与客户端 JSON 均保留 V2Ray `security`、`alter_id` 和 typed transport；Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 与 ShadowTLS 无标准 URI，使用完整 outbound JSON。
- `check`：执行 `sing-box check` 校验服务端配置，并返回 stdout、stderr、退出码和是否通过。
- `doctor`：输出只读诊断报告，包含服务状态、路径存在性、协议状态和嵌入的配置校验结果。
- `service restart`：必须显式传入 `--yes`，先校验配置，通过后才重启服务，并返回重启前后的服务状态。
- `subman-sync`：非交互推送节点到 SubMan；配置缺失时返回结构化错误，不进入交互提示。API 失败时会在 `last_error` 返回稳定的 `code`、`disposition`、HTTP 状态与可用的 `Retry-After`，传输结果不确定时不会盲目重放写请求。Hysteria2、Trojan 与 VMess 使用独立逐实例/用户路径，Hysteria v1、TUIC、AnyTLS、Snell、NaiveProxy 明确跳过并返回原因；仅 TLS 系统信任且 URI 可无损表达的条目进入同步。
- `instance`：管理结构化 Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/VLESS plain/AnyTLS/Hysteria2/Snell/TUIC/Hysteria/NaiveProxy/ShadowTLS 实例。`view`/`diagnose` 是共享锁保护的只读入口，默认脱敏；`export` 是敏感入口，返回完整 typed record 与连接材料。Agent 的连接材料按 `127.0.0.1` 生成，仅表示本机/受信上下文的连接基线，不是公网地址或可达性证明。`rebuild` 在精确 CAS 下修复受管配置漂移并递增 revision；`takeover` 只接管无 active typed state 的可无损 live inventory，默认拒绝公网监听，必须显式 `--allow-public`。`migrate` 仅把 Mixed legacy schema 1 转成 revision 1；`create`/`replace`/`delete`/`default` 使用 `--expected-revision`，凭据通过私有文件输入；删除最后一个实例后保留 revision tombstone，下一次写入不能把 CAS 重置为 0；`recover` 只处理可验证的未完成事务。首次全新安装仍写 legacy schema 1，直到显式迁移。
- `component`：管理高级入站、Endpoint、可复用出站/分组、ACME provider、shared `http_client`、network namespace 和 typed `route.rule_set`。`list`/`diagnose` 只返回元数据、环境/资源和事务摘要；`export` 按 ID 返回完整记录，是敏感操作。`create`/`replace`/`delete`/`takeover`/`rebuild`/`recover` 使用独立 schema 1 revision/CAS 和持久事务目录 `/root/sing-box-vps.component-write.lock`，候选会执行引用图、监听资源与目标核心 `sing-box check`；非回环监听、TUN、隧道和 OpenVPN server 需要 `--allow-public`。高级组件不进入普通节点分享、客户端导出或 SubMan 同步。
- `instance <operation> socks`：使用 `view`/`diagnose`/敏感 `export` 读取，以及 `create`/`replace`/`delete`/`default`/`rebuild`/`takeover`/`recover`、`--expected-revision`、typed record、共享事务和回滚边界管理独立 SOCKS；记录只表达 SOCKS 入站的监听/认证，不含 HTTP 或 TLS。`migrate socks` 明确返回 invalid arguments；已有 live SOCKS 配置应使用 takeover，不把 legacy `.env` migration 语义套到该预设。实例生命周期、两核心 check/runtime、菜单、接管和 Agent/export 回归及最终 Docker/TCP 门禁已通过，但不应从注册表存在推断为全协议目标完成。
- `instance <operation> http`：操作与 SOCKS 相同，但完整记录必须包含 `tls: {enabled:false}` 或手工 TLS 的 `enabled/server_name/certificate_path/key_path`。非回环写入须显式 `--allow-public`，无 legacy migration。记录示例与限制见 [Agent Runbook](docs/agents/sing-box-vps-agent-runbook.md)。HTTP TLS 节点的 `shareable=false`、`client_exportable=true`，不将空链接视为可用 URI。
- `instance <operation> shadowsocks`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 `listen.network` 和 `authentication`，完整示例见 [Agent Runbook](docs/agents/sing-box-vps-agent-runbook.md#shadowsocks-inbound)。`nodes` 不输出密钥；敏感的 `links` 返回逐用户 URI、outbounds 与限制 warning。
- `instance <operation> vmess`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一 `name`/UUID/`security`/`alter_id` 用户、TLS 信任和 typed V2Ray transport（none/http/ws/grpc/quic）。分享和 SubMan 仅接受 TLS 系统信任且 URI 可无损表达的用户；完整边界见 [VMess 契约](docs/agents/sing-box-vps-agent-runbook.md#vmess-typed-instance-contract)。
- `instance <operation> anytls`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一用户名/密码、必需手工 TLS 证书路径、server name、客户端 `certificate`/`system` 信任和出站策略。AnyTLS 没有标准分享 URI，`links` 返回凭据 outbound JSON 与 `anytls_standard_uri_unavailable` warning；`nodes` 不返回密码。legacy AnyTLS 的 ACME/provider 配置不自动迁移到 typed store，接管会拒绝无法无损表达的字段；完整边界见 [AnyTLS 契约](docs/agents/sing-box-vps-agent-runbook.md#anytls-typed-instance-contract)。
- `instance <operation> hy2`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一用户名/密码、必需手工 TLS、`certificate`/`system` 客户端信任、可独立设置的 `up_mbps`/`down_mbps`、Salamander obfs、masquerade 和出站策略。legacy Hysteria2 的 ACME/provider 配置不自动扁平化；标准 Hysteria2 URI 按用户生成，证书信任、URI 大小、带宽/masquerade 和 Ed25519 客户端开关均返回结构化 warning；完整边界见 [Hysteria2 契约](docs/agents/sing-box-vps-agent-runbook.md#hysteria2-typed-instance-contract)。
- `instance <operation> hysteria`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一 `name`/`auth_str` 用户、必需手工 TLS、`certificate`/`system` 客户端信任、上下行 `up_mbps`/`down_mbps`、字符串 obfs 与 QUIC 参数。服务端渲染为 `type: hysteria` 的 UDP/QUIC 入站并自动加入 `alpn:["h3"]`；客户端按用户输出完整 outbound JSON，`links` 返回 `hysteria_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [Hysteria 契约](docs/agents/sing-box-vps-agent-runbook.md#hysteria-typed-instance-contract)。
- `instance <operation> snell`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含版本 `5`/`6`、PSK、0–128 个唯一用户 key、v5 `none/http` obfs（HTTP host 作为客户端元数据）或 v6 `default/unshaped/unsafe-raw` shaping。Snell listener 固定 TCP，UDP 业务依赖 packet API；客户端导出逐用户保留 `network:["tcp","udp"]` outbound JSON，`links` 返回 `snell_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [Snell 契约](docs/agents/sing-box-vps-agent-runbook.md#snell-typed-instance-contract)。
- `instance <operation> tuic`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个 UUID/密码用户、手工证书 TLS、客户端 `certificate`/`system` 信任、拥塞控制、auth timeout、heartbeat 和 zero-rtt。服务端是 QUIC/UDP 入站，`udp_relay_mode` (`native`/`quic`) 与 `udp_over_stream` 只在客户端出站生效，不会写入入站。客户端按用户输出完整 TUIC outbound JSON，`links` 返回 `tuic_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [TUIC 契约](docs/agents/sing-box-vps-agent-runbook.md#tuic-typed-instance-contract)。
- `instance <operation> naive`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个用户名/密码用户、手工 TLS、客户端 `certificate`/`system` 信任、`listen.network`、QUIC 拥塞控制、窗口、并发和额外 headers。服务端按 TCP/UDP 选择渲染 Naive 入站；客户端按用户输出完整 Naive outbound JSON，`links` 返回 `naive_standard_uri_unavailable` 和 `naive_libcronet_required`，不执行 SubMan 同步。完整边界见 [NaiveProxy 契约](docs/agents/sing-box-vps-agent-runbook.md#naiveproxy-typed-instance-contract)。
- `instance <operation> shadowtls`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 v1/v2/v3 凭据、握手服务器与 SNI 映射、strict/wildcard SNI、客户端 `certificate`/`system` 信任和 loopback Mixed detour。服务端渲染 ShadowTLS 外层与隐藏的 loopback Mixed 内层；客户端按用户输出完整 outbound JSON，`links` 返回 `shadowtls_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [ShadowTLS 契约](docs/agents/sing-box-vps-agent-runbook.md#shadowtls-typed-instance-contract)。
- `update sbv`：从 GitHub 更新 `/usr/local/bin/sbv` 管理脚本；别名为 `sbv update-sbv`。
- `update sing-box [latest|x.y.z]`：普通运维更新入口，逐字节保留现有配置，目标核心校验通过后才重启服务，失败明确返回非零；别名为 `sbv update-sing-box [latest|x.y.z]`。自动化升级优先使用上面的固定版本 `agent upgrade`。

Mixed 实例写入使用类型化记录文件；`create` 和 `replace` 必须通过 `--file` 提供一个完整 JSON 对象，不接受命令行凭据。示例（`replace` 时 `id` 和 `tag` 必须保持原值，不能借此改身份）：

```json
{
  "id": "main",
  "name": "办公 Mixed",
  "tag": "mixed-in",
  "listen": {"address": "127.0.0.1", "port": 1080},
  "authentication": {
    "enabled": true,
    "username": "proxy-user",
    "password": "请替换为私有凭据"
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

记录只允许上述字段；`listen`、`outbound_policy` 和 `dependencies` 也会参与候选配置及依赖检查，当前 `dependencies` 必须为空数组。写入成功后，根状态标记为 `CONFIG_SCHEMA_VERSION=2`，结构化文件以 `schema_version: 1`、`protocol: "mixed"`、单调 `revision`、`default_instance_id` 和 `instances[]` 封装该记录。`nodes`/`links` 是只读发现入口，可用于找到实例 `id`/tag；若输出 `instance_revision`，写入 CAS 应使用它，否则应从同一状态快照读取 revision（当前 `capabilities` 只声明需要 revision，不提供当前值），不能用猜测值覆盖并发修改。`recover` 是例外：必须使用未完成事务 journal 中原始的 `expected_revision`，不能拿当前 store revision 冒充恢复条件。

交互式管理会话在整个菜单期间持有排他管理 `flock`；需要先选择菜单 0 退出会话，其他 Agent 读写才能取得同一管理锁。Agent 只读操作使用共享锁，写入使用排他锁；锁冲突或未完成事务会返回结构化错误，不会静默绕过锁。

实例结果的 `transaction.firewall` 保留后端可用性和脱敏诊断，并同步写入持久 result 文件；事务目录清理后仍可审计。`unavailable` 不代表已开放防火墙，也不代表公网业务已验证。

已有 1.13.x 主机应先运行 `sbv update sbv` 更新管理脚本，再调用 `capabilities` 与 `upgrade-check`。1.14 对旧版 inline `tls.acme` 和远程规则集 `download_detour` 会给出弃用 warning，但两者到 1.16 才移除，因此 warning 本身不会阻止 1.13→1.14；其他真实不兼容会在目标 1.14 二进制的 `sing-box check` 阶段阻止重启并触发回滚。

### `sbv` 自更新的失败语义

`sbv update sbv` 和 `sbv update-sbv` 使用同一套事务流程：`PRECHECK → STAGE → VALIDATE → BACKUP → COMMIT → POSTCHECK → CLEANUP`。远程内容只会写入 `/usr/local/bin` 同目录的候选文件，候选必须通过非空/最小大小、预期 shebang、`bash -n`、唯一 `SCRIPT_VERSION`、项目身份和版本单调性校验，之后才会使用同目录原子 `mv` 提交。候选 SHA-256 仅用于本地提交前后完整性核对，不代表远端签名或供应链认证。

- 下载或校验失败：`changed=false`、`rollback_attempted=false`，原有 `sbv` 的内容、权限和所有者保持不变；CLI 返回非零，交互菜单展示错误摘要后继续运行。
- 当前版本相同且目标健康：安全 `no-op`，不会创建备份或替换目标文件。
- 提交后 postcheck 失败：自动恢复备份，并再次校验旧版本、SHA-256、Bash 语法和执行权限，报告 `rolled_back=true`。
- `rollback_failed`：自动恢复未通过，报告 `manual_intervention_required=true`，并保留 root-only 备份和候选恢复文件。请先按错误提示人工恢复并重新执行 `bash -n`、版本、SHA-256 与执行权限校验，再运行 `sbv`。

更新成功后当前进程仍运行旧代码，请按提示重新运行 `sbv`。错误摘要和脱敏诊断会写入 `/root/sing-box-vps/sbv.log`；日志写入失败不会覆盖原始更新错误。

Agent/Hermes 文档入口：

- [Agent 快速上下文](docs/agents/llms.txt)
- [完整 Agent 运维手册](docs/agents/sing-box-vps-agent-runbook.md)
- [Hermes 单主机 1.13→1.14 演练](docs/agents/sing-box-1.13-to-1.14-upgrade-test.md)
- [可安装 Operator Skill](skills/sing-box-vps-operator/SKILL.md)

</details>

## 功能菜单

<details>
<summary>查看 30 项管理菜单与分享链接说明</summary>

Mixed/SOCKS 分享链接对用户名、密码按字节执行 URI 百分号编码，避免 `@`、`#`、`%`、空格或换行改变链接结构；服务端凭据保持不变。HTTP Basic 无法表达含冒号的用户名或含 ASCII 控制字符的认证：此时 Mixed 的 Agent `links` 只提供 SOCKS5，并返回 `mixed_http_auth_unrepresentable`，不生成不可用的 HTTP 链接。SOCKS5 URI 不携带 UoT v2 等客户端选项，返回 `socks5_uri_transport_options_omitted`；需要完整配置时使用 `export-client` JSON。百分号编码不是加密，链接仍是敏感材料。

1. **安装新协议**：首次安装或向现有实例追加 VLESS REALITY、Mixed、独立 SOCKS、独立 HTTP、Shadowsocks、Trojan、VMess、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy、ShadowTLS；协议选择注册表第 5 项为 SOCKS，第 6 项为 HTTP，第 9 项为 VMess，第 11 项为 Snell，第 12 项为 TUIC，第 13 项为 Hysteria v1，第 14 项为 NaiveProxy，第 15 项为 ShadowTLS。
2. **修改已安装协议配置**：只修改选中的协议/REALITY 实例，并重建、校验整体配置。
3. **移除已安装协议**：移除指定协议或 REALITY 实例；存在多个 REALITY 实例时会明确询问“单实例”或“整个 VLESS 协议”，并同步清理 QoS 与已移除端口的防火墙放行。
4. **更新 sing-box 版本**：保留配置的核心更新；目标 `sing-box check` 通过才重启。
5. **卸载 sing-box**：清理核心、服务与运行配置，保留管理命令 `sbv`。
6. **启动 sing-box**。
7. **停止 sing-box**。
8. **重启 sing-box**。
9. **运行状态摘要**。
10. **查看实时日志**。
11. **查看节点信息**：链接/二维码、裸核客户端导出与 SubMan 同步。
12. **流媒体验证检测**：本机直出或 Warp 出口。
13. **配置 Cloudflare Warp**：账户、开关、全量/选择性路由、自定义域名及规则集。
14. **系统管理**：BBR，以及入站监听栈和出站/DNS 策略。
15. **更新管理脚本 `sbv`**。
16. **卸载管理脚本 `sbv`**。
17. **管理 Mixed 实例**：创建、修改、删除、设置默认实例、迁移 legacy 状态和恢复未完成事务。
18. **管理 SOCKS 实例**：创建、修改、删除、设置默认实例和恢复未完成事务；使用独立 SOCKS 的 schema 2 typed store，不提供 legacy `.env` migration。
19. **管理 HTTP 实例**：创建、修改、删除、设置默认实例和恢复未完成事务；入口可选明文或手工证书 TLS，使用共享事务，不提供 legacy migration。
20. **管理 Shadowsocks 实例**：逐实例管理认证、监听网络、默认实例与事务恢复，不提供 legacy migration。
21. **管理 Trojan 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、TLS 信任及传输，使用共享 CAS 事务，不提供 legacy migration。
22. **管理 VMess 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、TLS 信任、V2Ray transport、`security` 与 `alter_id`，使用共享 CAS 事务，不提供 legacy migration。
23. **管理 VLESS 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理普通 VLESS 用户、TLS 信任和 V2Ray transport，使用共享 CAS 事务，不提供 legacy migration。
24. **管理 AnyTLS 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、手工 TLS 证书和客户端信任，使用共享 CAS 事务。legacy AnyTLS 仍沿用原 ACME/provider 更新路径，不自动扁平化迁移。
25. **管理 Hysteria2 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、手工 TLS、带宽、Salamander obfs、masquerade 与客户端信任。legacy Hysteria2 仍沿用原 ACME/provider 更新路径，不自动扁平化迁移。
26. **管理 Snell 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理 Snell v5/v6、PSK、用户 key、v5 HTTP obfs 或 v6 shaping。Snell 仅输出完整 outbound JSON，不生成标准分享 URI，也不执行 SubMan 同步。
27. **管理 TUIC 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理 UUID/密码用户、手工证书 TLS、拥塞控制、auth timeout、heartbeat、zero-rtt，以及仅客户端出站使用的 relay/udp-over-stream。TUIC 仅输出完整 outbound JSON，不生成标准分享 URI，也不执行 SubMan 同步。
28. **管理 Hysteria 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理 `name`/`auth_str` 用户、手工证书 TLS、客户端信任、上下行带宽、字符串 obfs 与 QUIC 参数。Hysteria 仅输出完整 outbound JSON，不生成标准分享 URI，也不执行 SubMan 同步。
29. **管理 NaiveProxy 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理用户名/密码用户、手工证书 TLS、客户端信任、TCP/UDP 监听、QUIC 拥塞控制、窗口、并发与额外 headers。NaiveProxy 仅输出完整 outbound JSON，依赖 `with_naive_outbound`/`libcronet.so`，不生成标准分享 URI，也不执行 SubMan 同步。
30. **管理 ShadowTLS 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理 v1/v2/v3 凭据、握手及 SNI 映射、strict/wildcard SNI、客户端信任和 loopback Mixed 内层。ShadowTLS 仅输出完整 outbound JSON，不生成标准分享 URI，也不执行 SubMan 同步。

当脚本发现二进制、service、配置或协议状态层不完整时，会进入接管/修复流程，而不是把残缺实例直接当作全新安装覆盖。

</details>

## 关键路径

<details>
<summary>查看运行文件与备份位置</summary>

- **工作目录**: `/root/sing-box-vps/`
- **配置文件**: `/root/sing-box-vps/config.json`
- **上一版配置备份**: `/root/sing-box-vps/config.json.bak`
- **最后协议删除前的索引备份**: `/root/sing-box-vps/protocols/index.env.bak`
- **协议状态目录**: `/root/sing-box-vps/protocols/`
- **密钥文件**: `/root/sing-box-vps/reality.key` (REALITY) / `warp.key` (Warp)
- **协议状态文件**: `vless-reality.env` / `vless-reality.d/` / `mixed.env` / `instances/mixed.json` / `socks.env` / `instances/socks.json` / `http.env` / `instances/http.json` / `shadowsocks.env` / `instances/shadowsocks.json` / `trojan.env` / `instances/trojan.json` / `vmess.env` / `instances/vmess.json` / `vless-plain.env` / `instances/vless-plain.json` / `hy2.env` / `anytls.env` / `instances/anytls.json` / `snell.env` / `instances/snell.json` / `tuic.env` / `instances/tuic.json` / `hysteria.env` / `instances/hysteria.json` / `naive.env` / `instances/naive.json` / `shadowtls.env` / `instances/shadowtls.json`
- **Trojan 结构化实例状态**: `/root/sing-box-vps/protocols/instances/trojan.json`（schema 1 store，`trojan.env` 为 schema 2 active marker）
- **VMess 结构化实例状态**: `/root/sing-box-vps/protocols/instances/vmess.json`（schema 1 store，`vmess.env` 为 schema 2 active marker）
- **AnyTLS 结构化实例状态**: `/root/sing-box-vps/protocols/instances/anytls.json`（schema 1 store，`anytls.env` 为 schema 2 active marker；仅保留手工 TLS，无法无损接管 ACME/provider）
- **Hysteria2 结构化实例状态**: `/root/sing-box-vps/protocols/instances/hy2.json`（schema 1 store，`hy2.env` 为 schema 2 active marker；手工 TLS 多实例记录保留用户、带宽、obfs、masquerade；legacy ACME/provider 仍保留原状态）
- **Snell 结构化实例状态**: `/root/sing-box-vps/protocols/instances/snell.json`（schema 1 store，`snell.env` 为 schema 2 active marker；记录版本、PSK、用户 key、v5 obfs 或 v6 shaping；无标准 URI/SubMan 同步）
- **TUIC 结构化实例状态**: `/root/sing-box-vps/protocols/instances/tuic.json`（schema 1 store，`tuic.env` 为 schema 2 active marker；记录 UUID/密码用户、手工 TLS、QUIC 参数与客户端出站 relay/udp-over-stream；无标准 URI/SubMan 同步）
- **Hysteria 结构化实例状态**: `/root/sing-box-vps/protocols/instances/hysteria.json`（schema 1 store，`hysteria.env` 为 schema 2 active marker；记录 `name`/`auth_str` 用户、手工 TLS、上下行带宽、obfs 与 QUIC 参数；无标准 URI/SubMan 同步）
- **NaiveProxy 结构化实例状态**: `/root/sing-box-vps/protocols/instances/naive.json`（schema 1 store，`naive.env` 为 schema 2 active marker；记录用户名/密码用户、手工 TLS、客户端信任、TCP/UDP 网络和 Naive/QUIC 出站选项；无标准 URI/SubMan 同步，官方 outbound 需要 `with_naive_outbound` 与 `libcronet.so`）
- **ShadowTLS 结构化实例状态**: `/root/sing-box-vps/protocols/instances/shadowtls.json`（schema 1 store，`shadowtls.env` 为 schema 2 active marker；记录 v1/v2/v3 凭据、握手映射、strict/wildcard SNI、loopback Mixed detour 和客户端信任；无标准 URI/SubMan 同步）
- **Mixed 结构化实例状态**: `/root/sing-box-vps/protocols/instances/mixed.json`（显式迁移或实例写入后启用）
- **Mixed 事务恢复材料**: `/root/sing-box-vps.instance-write.lock`、`/root/sing-box-vps.instance-transactions/`
- **高级组件状态**: `/root/sing-box-vps/components.json`（schema 1、独立 revision；list/diagnose 脱敏，export 敏感）
- **高级组件事务材料**: `/root/sing-box-vps.component-write.lock`（持久 journal、快照与外部资源恢复材料）
- **REALITY QoS 状态**: `/root/sing-box-vps/reality-qos.filters`
- **Warp 分流域名**: `/root/sing-box-vps/warp-domains.txt`
- **Warp 本地规则集目录**: `/root/sing-box-vps/rule-set/warp/`
- **Warp 远程规则集列表**: `/root/sing-box-vps/warp-remote-rule-sets.txt`
- **流媒体验证脚本缓存**: `/root/sing-box-vps/media-check/region_restriction_check.sh`
- **SubMan API 配置**: `/root/sing-box-vps/subman.env`
- **Agent 升级备份**: `/root/sing-box-vps-backups/`（包含敏感运行材料，仅 root 可读）
- **全局命令**: `/usr/local/bin/sbv`

</details>

## 注意事项

- 配置检查与隔离容器探针不证明公网可达或生产环境运行。具体测试范围见[能力矩阵](docs/superpowers/specs/2026-09-06-protocol-coverage.md)。
- 本脚本必须以 `root` 用户身份运行。
- 脚本默认适配最佳稳定性版本，手动选择 `latest` 可能存在不兼容风险。
- `Mixed` 代理默认建议启用用户名密码认证；若关闭认证，请务必确认防火墙和来源访问控制策略。当前 Mixed 入口及导出 SOCKS5 链路未启用 TLS，用户名密码和非加密业务可能暴露，仅应在可信网络或受保护隧道内使用；UoT v2 只把 UDP 封装在 TCP 中，不提供加密，也不要求开放额外的服务端固定 UDP 端口。
- `Hysteria2` 支持 ACME 自动签发与手动证书路径两种 TLS 模式；使用 ACME `DNS-01` 时当前仅支持 Cloudflare。sing-box 1.14+ 客户端连接使用 Ed25519 手动证书的节点时必须禁用 Chrome QUIC 模拟；裸核配置导出会自动处理，分享链接和 SubMan 同步则会输出显式警告。
- `AnyTLS` legacy schema 1 仍支持 ACME 自动签发与手动证书路径；schema 2 typed 实例为可审计的手工证书路径、用户名/密码和 `certificate`/`system` 客户端信任。由于官方文档未定义标准分享 URI，Agent `links` 和客户端导出使用完整 sing-box outbound JSON，并显式将 `client_metadata` 设为空；无法无损表达的 ACME/provider live 配置会拒绝接管而保留原状态。
- SubMan 同步使用公开的 `PUT /api/nodes/by-key/:externalKey` 契约；双栈迁移清理旧 key 时会先读取 Workspace revision，再通过公开节点删除接口提交，避免空 `raw` 或直接修改 Gist。
- 流媒体验证功能当前接入第三方项目 `1-stream/RegionRestrictionCheck`，脚本内已注明作者与仓库地址，后续可替换为自定义检测后端。

---

## 作者

**KnowSky404**

- 项目地址: [https://github.com/KnowSky404/sing-box-vps](https://github.com/KnowSky404/sing-box-vps)

## 开发验证

修改安装器、卸载器、配置模板、工具函数或验证框架后，运行 `bash dev/verification/run.sh`。验证框架在本地 Docker 特权容器中执行运行场景；历史证据见[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)。

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
