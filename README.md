# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。当前适配 **sing-box 1.14.x**，并保留显式固定 1.13.x 时的配置兼容能力。

## 📌 当前版本信息

- 脚本版本：`2026090804`

- sing-box 适配版本：`1.14.0`

Trojan 为第八个入站预设，支持多实例、多用户，以及独立建模的 TLS 与传输设置；VMess 为第九个入站预设；普通 VLESS 为第十个入站预设，使用独立的 `vless-plain` ID，与旧 `vless`/REALITY alias 分开，支持多实例、多用户、TLS、V2Ray transport、分享和 SubMan 边界。Hysteria2 现支持 schema 2 多实例、多用户、手动 TLS、带宽、Salamander obfs、masquerade、客户端导出、Agent 与 SubMan 逐用户路径；legacy Hysteria2 的 ACME/provider 状态仍保留原路径。新入口默认回环监听；公开监听须明确确认。Shadowsocks 仍为第七预设，保留实例级 TCP/UDP 选择。全协议目标仍在推进，不能由当前预设推断其他上游协议已接入。

Trojan 可管理原生 TCP、HTTP、WebSocket（无 early data）、gRPC 和 TLS QUIC；QUIC 使用 UDP 监听，不限制代理业务只能走 UDP。VMess 同样按用户保留凭据，支持原生 TCP、HTTP、WebSocket（无 early data）、gRPC 和 TLS QUIC，并保留 `security`/`alter_id` 等 V2Ray 字段。普通 VLESS 使用独立的 `vless-plain` 状态/实例库，支持原生 TCP、HTTP、WebSocket、gRPC、QUIC、可选 TLS，以及按用户的 `flow`；客户端导出、VLESS URI、Agent、实例 CAS、接管/重建和 SubMan 均从同一快照生成。客户端导出按明确选择使用系统信任或公开证书，绝不导出服务器私钥或自动关闭证书校验。分享/SubMan 仅同步 TLS 系统信任且 URI 能无损表达的用户，其余返回跳过原因。HTTPUpgrade 与 WebSocket early data 因真实连接失败仍被阻断，未计作已支持。接口与范围见[Trojan 契约](docs/agents/sing-box-vps-agent-runbook.md#trojan-typed-instance-contract)与[VMess 契约](docs/agents/sing-box-vps-agent-runbook.md#vmess-typed-instance-contract)。

## 🚀 一键安装

在您的 VPS 上运行以下安全 Bootstrap 即可开始安装。它会先完整下载到权限为 `0600` 的临时文件，再执行语法和项目身份校验；下载、校验或脚本执行的退出码会原样返回。整个流程运行在子 Shell 中，不会用 `exit` 关闭当前 SSH 登录 Shell。

```bash
(
  set -euo pipefail
  umask 077
  temp_file=$(mktemp "${TMPDIR:-/tmp}/sing-box-vps-bootstrap.XXXXXX")
  trap 'rm -f "${temp_file}"' EXIT
  curl_exit_code=0
  if curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    --retry 2 \
    --retry-delay 1 \
    -o "${temp_file}" \
    https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh; then
    curl_exit_code=0
  else
    curl_exit_code=$?
  fi
  if (( curl_exit_code != 0 )); then
    printf '[ERROR] sing-box-vps Bootstrap 下载失败，curl 退出码: %s；脚本尚未执行，系统未发生变更。\n' \
      "${curl_exit_code}" >&2
    exit "${curl_exit_code}"
  fi
  if ! bash -n "${temp_file}"; then
    printf '[ERROR] sing-box-vps Bootstrap 校验失败：Bash 语法无效；脚本尚未执行，系统未发生变更。\n' >&2
    exit 2
  fi
  if ! grep -Fqx 'readonly PROJECT_AUTHOR="KnowSky404"' "${temp_file}" || \
    ! grep -Fqx 'readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"' "${temp_file}"; then
    printf '[ERROR] sing-box-vps Bootstrap 校验失败：项目身份不匹配；脚本尚未执行，系统未发生变更。\n' >&2
    exit 2
  fi
  script_exit_code=0
  bash "${temp_file}" || script_exit_code=$?
  exit "${script_exit_code}"
)
```

如需独立执行彻底卸载，可运行：

```bash
(
  set -euo pipefail
  umask 077
  temp_file=$(mktemp "${TMPDIR:-/tmp}/sing-box-vps-bootstrap.XXXXXX")
  trap 'rm -f "${temp_file}"' EXIT
  curl_exit_code=0
  if curl -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    --retry 2 \
    --retry-delay 1 \
    -o "${temp_file}" \
    https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/uninstall.sh; then
    curl_exit_code=0
  else
    curl_exit_code=$?
  fi
  if (( curl_exit_code != 0 )); then
    printf '[ERROR] sing-box-vps Bootstrap 下载失败，curl 退出码: %s；脚本尚未执行，系统未发生变更。\n' \
      "${curl_exit_code}" >&2
    exit "${curl_exit_code}"
  fi
  if ! bash -n "${temp_file}"; then
    printf '[ERROR] sing-box-vps Bootstrap 校验失败：Bash 语法无效；脚本尚未执行，系统未发生变更。\n' >&2
    exit 2
  fi
  if ! grep -Fqx 'readonly PROJECT_AUTHOR="KnowSky404"' "${temp_file}" || \
    ! grep -Fqx 'readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"' "${temp_file}"; then
    printf '[ERROR] sing-box-vps Bootstrap 校验失败：项目身份不匹配；脚本尚未执行，系统未发生变更。\n' >&2
    exit 2
  fi
  script_exit_code=0
  bash "${temp_file}" --yes || script_exit_code=$?
  exit "${script_exit_code}"
)
```

Bootstrap 的临时文件在下载和校验阶段都不会执行；网络失败时尤其不会把空内容、部分传输或错误页交给 Bash。示例中的 `curl` 参数兼容 Debian 11、Ubuntu 20.04、CentOS 7 及其后续发行版，并继续尊重标准 `HTTPS_PROXY` 等环境变量。

## 开发验证工作流

Docker 验证镜像自动管理，无需额外配置。

REALITY 显式接管/状态重建按既有 inbound tag 关联实例，保留稳定 ID、节点名称、上下行限速和默认实例；连接字段继续从现有配置恢复，旧公钥仅在私钥一致时复用。存在歧义的身份映射会阻断重建，状态写入失败会恢复原协议状态目录。

Agent 节点/分享列表与 REALITY、VMess、普通 VLESS、Hysteria2、AnyTLS 客户端导出共用只读实例接口：旧单实例状态内部映射为 `main`，REALITY、VMess、普通 VLESS、Hysteria2 与 AnyTLS 保留原实例身份；读取和客户端渲染不自动迁移旧状态或生成凭据。其他协议的多实例持久化仍在实施中。

Mixed 已接入结构化实例状态（schema 2）和完整的实例管理链路：显式迁移会把旧单实例 `.env` 的稳定身份、tag、监听地址/端口和认证材料带入 `protocols/instances/mixed.json`；首次全新安装仍沿用兼容的 schema 1 路径，不会隐式迁移。Agent 与菜单支持创建、替换、删除、设置默认实例、显式迁移和事务恢复，均使用 revision 条件写入。该入口只管理 Mixed，不代表全协议目标已经完成。

服务端候选和结构化状态现在共用固定监听资源预检：区分 TCP/UDP，识别 IPv4 通配、IPv6 等价地址和双栈重叠；冲突时保留原配置。防火墙开放取自完整已发布配置的实际监听传输；删除根据旧配置备份和剩余入站保护仍被引用的规则，不再同时操作无关 TCP/UDP。Mixed 实例事务初次创建也先在目标同目录 staging 后原子发布，并为文件/config、受管 UFW/iptables/ip6tables 规则和服务恢复保存持久 journal/result；同时以共享 `flock` 串行化管理写入。firewalld 仅作只读外部预检，禁止在事务中 add/delete/reload，缺少所需 allow 或既有归属账本时会在变更前失败并要求人工规则。故障时不把文件恢复冒充为外部防火墙已恢复。全量删除必须先确认服务已停止；清单缺失或无法解释时拒绝清理。后端失败返回非零并明确披露已提交配置、尚未执行重启或可能存在的部分外部变更。这仍不是完整防火墙归属账本或系统资源事务，不追溯删除未归属的历史宽规则，也不检查其他进程抢占端口、动态 UDP relay 和 ACME 临时监听。

全协议改造按[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)推进；[上游能力矩阵](docs/superpowers/specs/2026-09-06-protocol-coverage.md)区分上游支持与项目已实现能力。当前运行时注册表位于独立分发的 `install.sh` 中，现有十个入站预设的菜单编号、公开 ID、导出候选、SubMan 类型和验证器元数据均从这里读取；普通 VLESS 使用独立 `vless-plain` preset，旧 `vless` alias 仍表示 REALITY。未知索引/状态版本或生成器返回的无效片段会阻断重建并保留原文件。现有配置的入站清单也会全量预检：未知类型、非 REALITY 的 VLESS、重复的单实例协议和重复显式 tag 会阻断自动重建/接管，不再仅识别第一个受支持入站。Agent 的 `status`、`nodes`、`links` 还要求索引、基础状态和 live 协议集合完全对应；REALITY、普通 VLESS 的状态必须包含完整连接字段，多实例状态的清单、文件名、内部 ID 和 inbound tag 必须与 live VLESS 集合一一对应，否则只返回结构化错误而不输出部分结果。服务端与客户端候选还会检查组件 tag、引用和显式依赖环，然后继续执行目标核心 `check`；这些检查尚不覆盖任意外部配置的字段及出站/端点/路由无损接管，也不表示新增协议已完成。

```bash
bash dev/verification/run.sh
```

独立 SOCKS（协议注册表第 5 项、安装选择菜单 5）已纳入最终门禁并通过：使用 `socks` 入站和 active `CONFIG_SCHEMA_VERSION=2` marker 配合 JSON `schema_version: 1` typed store，沿用与 Mixed 相同的认证记录、实例 ID/tag、监听与 revision CAS。它只提供 SOCKS4/4a/5 代理入口，不提供 HTTP 或 TLS；客户端导出使用 SOCKS5 outbound 和 UoT v2。Agent 实例接口为 `create`、`replace`、`delete`、`default`、`recover`，命令形式与 Mixed 相同但协议参数为 `socks`；`migrate socks` 明确拒绝，已有 live SOCKS 配置应走 takeover。六项回归、两核心 runtime/check、菜单及最终验证框架已通过；完整协议目标仍未完成。详细证据见[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)。

Shadowsocks 增量已通过最终源码的 12/12 Docker 场景、18/18 TCP 探针，以及原生 Bash / 实际 Bash 4.2 × 1.13.18 / 1.14.0 的四组回环业务测试（每组 7 TCP、7 UDP）。九种方法均通过核心配置检查，不把 check 等同于所有方法的业务实测。SubMan 仅有 mock 证据；公网 UDP 和生产部署未验证。本地回归的首次失败、修复与分阶段重跑范围见[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)。

只想验证本地调度与触发规则时，可运行：

```bash
VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh
```

核心脚本改动会自动触发远程验证；仅修改 `tests/`、`docs/`、`README.md` 不会占用测试机。

默认工作流已做分层优化：
- 核心脚本改动默认只跑协议探测快测
- 仅在改动 `dev/verification/run.sh`、`dev/verification/common.sh` 或 `dev/verification/remote/` 时，才追加远程调度与远程框架回归
- 远程验证默认优先收敛到 `runtime_smoke`；安装/重配相关改动会扩到全新安装、接管、重配、十协议共存，以及真实的 `upgrade_1_13_to_1_14` 成功升级和 `upgrade_rollback_1_13_to_1_14` 故障回滚场景；独立 SOCKS、HTTP、Shadowsocks、Trojan、VMess 与普通 VLESS 共存均纳入门禁。

命中远程验证时，测试机会额外执行协议级闭环探测：先用目标 `sing-box` 校验客户端配置，再启动临时客户端连接本机服务端入站，并通过客户端 SOCKS 代理访问本机 HTTP 标记服务。HTTP 增量已通过 75 项本地门禁，修正测试断言后 Docker 重跑为 11/11 场景、16/16 TCP 探测成功；普通 VLESS 阶段的最终本地门禁运行目录为 `dev/verification-runs/20260908141403`，108/108 项通过；最终 Docker 运行目录 `dev/verification-runs/20260908144031` 为 15/15 场景、22/22 协议探针成功，包含普通 VLESS 新装、十协议共存和升级回滚产物。HTTP TLS 另以 1.13.18/1.14.0 与实际 Bash 4.2 完成本地正反向连接测试。SOCKS UoT 的 UDP 证据限于回环测试，不代表公网原生 UDP 可达。未知协议会在产物中标记为 `unsupported`。详细命令、失败记录、重跑范围与证据见[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)。

脚本会自动：
1. 安装所有必要依赖（curl, wget, jq, qrencode 等）。
2. 下载并配置适配的 `sing-box` (当前适配：1.14.0)。
3. 生成 **VLESS + REALITY**、普通 **VLESS**、**Mixed (HTTP/HTTPS/SOCKS)**、独立 **SOCKS**、独立 **HTTP**、**Shadowsocks**、**Trojan**、**VMess**、**Hysteria2** 或 **AnyTLS** 配置，并支持多协议共存；其中 VLESS REALITY、普通 VLESS、VMess 与 Hysteria2 支持多实例，VLESS REALITY 还支持独立端口和可选上下行限速。HTTP/SOCKS 明文入口仅适合可信网络或受保护隧道。
4. 以 **`install.sh`** 作为唯一安装与维护真源，并将自己安装为全局命令 **`sbv`**，方便您随时管理。

---

## 🎮 快速管理

安装完成后，您可以在任何目录下直接输入 `sbv` 来打开交互式管理菜单：

```bash
sbv
```

## ✨ 项目特性

- **Agent 友好命令行**：提供 `sbv agent ... --json` 非交互命令，方便 Hermes、OpenClaw、Codex 等 AI Agent 发现完整能力、获取状态与节点信息、导出客户端配置，并执行带预检、确认、持久备份和自动回滚的固定版本升级。所有 `--json` 响应采用 `schema_version: "1.0"` 统一 envelope，同时保留兼容字段 `schema: "1"`；对外协议 ID 统一使用 `vless-reality`、`vless-plain`、`mixed`、`socks`、`http`、`shadowsocks`、`trojan`、`vmess`、`hysteria2`、`anytls`，独立 SOCKS、VMess、普通 VLESS 与 Hysteria2 生命周期已通过定向门禁。
- **1.14.x 深度适配**：继续采用 **Endpoint（端点化）** 架构，并适配顶层 ACME `certificate_providers`、远程规则集 `http_client` 与 Hysteria2 `disable_chrome_parrot`。
- **跨版本配置生成**：目标核心为 1.14+ 时生成新版配置结构；显式固定或运行 1.13.x 时继续生成内联 `tls.acme` 与旧版远程规则集结构。接管或重建时会保留可内联表达的 ACME 扩展字段；若 provider 引用了无法独立保留的共享 `http_client`，脚本会拒绝重写。仅更新二进制时不会重写现有配置。
- **可审计升级**：`upgrade-check` 会报告实例健康度、当前配置校验、配置 SHA-256、1.14 已知弃用项和阻断原因；`upgrade` 只接受固定版本与 `--yes`，先在 `/root/sing-box-vps-backups/` 创建 root-only 备份，并原子维护 `transaction-result.json`（事务 ID、旧/新版本、状态历史、manifest hash 与回滚结果）。目标核心校验失败时尝试恢复旧二进制并返回非零；若恢复未通过最终校验，会明确返回 `rollback_failed` 和人工介入标记。
- **多协议支持**：支持 **VLESS + REALITY**、普通 **VLESS**、**Mixed (HTTP/HTTPS/SOCKS)**、**独立 SOCKS**、**独立 HTTP（可选入口 TLS）**、**Shadowsocks**、**Trojan**、**VMess**、**Hysteria2** 与 **AnyTLS** 十种入站预设。已有服务新增 HTTP、Shadowsocks、Trojan、VMess、普通 VLESS、Hysteria2 或 AnyTLS 时单独进入共享实例事务，不与其他协议合并追加；全协议目标仍未完成。
- **Mixed 多实例管理**：schema 2 支持多个稳定 ID/tag、独立监听地址/端口、独立认证和默认实例；Agent 提供 `create`、`replace`、`delete`、`default`、`migrate`、`recover`，交互菜单 17 提供逐实例管理。非回环明文监听需要显式公网暴露确认；跨协议批量删除会拒绝并要求逐实例处理 Mixed。
- **VLESS REALITY 多实例**：可在安装菜单追加多个 REALITY 实例，每个实例拥有独立端口、ShortID、节点名称、可选上下行限速和实例级出站策略；节点展示和 SubMan 同步会逐实例输出。
- **REALITY QoS 限速**：为设置了上下行 Mbps 的 REALITY 实例自动规划并应用 `tc` 端口级限速规则，重建配置、更新协议或移除实例时会同步刷新规则，避免遗留过滤器影响新配置。
- **Cloudflare Warp 集成**：支持一键开启/关闭 Warp 出站，自动注册免费账户，完美解决 VPS **“送中”** 问题并解锁 Netflix/Disney+ 等流媒体。
- **Warp 路由分层**：支持 `全量走 Warp` 与 `选择性分流` 两种模式，默认采用更稳妥的 `选择性分流`，内置主流 AI / 流媒体域名规则，并支持用户追加自定义域名、本地规则集和远程规则集；VLESS REALITY 实例还可单独选择跟随全局、强制 direct 或强制 Warp 出口。
- **单一真源**：统一以 `install.sh` 作为安装与维护入口，避免历史旧入口与当前实现漂移。
- **托管实例自修复**：当协议状态层与运行中的 `config.json` 发生漂移时，会优先按协议状态自动重建运行配置，降低 `mixed` 等附加协议意外丢失的风险。
- **配置事务发布**：交互式新增、修改、协议栈、Warp 与删除操作会先快照完整托管状态；服务端配置写入同目录 candidate，并依次通过 `jq` 与当前 sing-box 核心的 `check`，仅在校验成功后保留上一版 `config.json.bak` 并原子替换 live config。生成器、certificate provider 或状态写入失败会恢复配置与协议状态。
- **环境自适应**：支持架构探测（amd64/arm64）及主流发行版（Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux）。
- **极简且安全**：默认开启流量嗅探、uTLS 指纹、多 ShortID 随机化及持久化密钥管理。
- **性能增强**：集成 **BBR** 一键开启功能，显著提升网络吞吐。
- **Mixed 防火墙事务**：启用 UFW 时仅通过 UFW 管理归属规则；没有活动防火墙前端时才直接管理 `iptables`/`ip6tables`。firewalld 仅执行只读外部预检，不由实例事务 add/delete/reload；UFW 与 firewalld 同时活动或已有账本与当前后端冲突时拒绝写入，要求人工处理。
- **工业级配置生成**：采用 **`jq` 安全注入** 模式生成 JSON，彻底规避特殊字符导致的转义错误。
- **协议级展示**：终端可按协议查看节点信息，支持 `VLESS`、`VMess` 与 `Hysteria2` 链接/ANSI 二维码展示，为 `Mixed` 和独立 `SOCKS` 输出代理链接与二维码提示，并为 `AnyTLS` 输出逐实例参数摘要和 sing-box outbound JSON（无标准 URI）；多 REALITY、普通 VLESS、Mixed、SOCKS、Trojan、VMess、Hysteria2、AnyTLS 实例会显示实例 ID、端口和限速摘要。
- **裸核客户端导出**：可从交互菜单或 `sbv agent export-client --json` 生成 `/root/sing-box-vps/client/sing-box-client.json`，支持当前十个预设，覆盖前自动备份，并在输出前执行 `sing-box check`。Mixed 和独立 SOCKS 使用 SOCKS5 outbound 与 UoT v2，VMess/Trojan/普通 VLESS/Hysteria2/AnyTLS 按用户保留认证、TLS 与传输；缺失或无效的端口/认证字段会阻断整份导出，保留原导出及备份，不自动生成密码或降级认证。
- **Mixed 安全边界**：Mixed 服务端和其导出的 SOCKS5/UoT 链路不提供 TLS；公网明文监听必须经过单独确认，不能把它当作独立的 TLS SOCKS 服务端。Mixed 当前也不新增 SubMan 同步能力。
- **独立 SOCKS（已验证边界）**：注册表菜单项 5 使用 `socks` state/Agent ID，active marker 为 schema 2、JSON store 为 `schema_version: 1`，支持同认证 typed record、共享事务与实例级 CAS；服务端无 HTTP/TLS，客户端导出为 SOCKS5 + UoT v2。六项回归、两核心 check/runtime、菜单和最终 Docker/TCP 门禁均已通过；这不等于 TLS、HTTP、SubMan 或全协议目标已完成。证据见[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)。
- **独立 HTTP**：菜单项 6、管理菜单 19，使用 `http` state/Agent ID 与 schema 2 共享实例事务。默认回环监听并启用认证，可选择明文或手工证书 TLS；证书文件由用户维护，实例操作不申请或删除它们。客户端导出为 TCP-only HTTP CONNECT；TLS 导出仅嵌入公开证书信任与 SNI，不读取私钥。明文 URI 返回 `http_plaintext_transport`；TLS 无可保真 URI，返回 `http_tls_uri_unrepresentable` 并使用完整 JSON。访问 HTTPS 目标不等于代理入口已加密；不支持 HTTP SubMan 同步。
- **Shadowsocks**：安装菜单 7、管理菜单 20，协议 ID `shadowsocks`（别名 `ss`），使用 schema 2 marker 与 schema 1 JSON 实例库。支持九种入站方法、可用方法的多用户、实例出站策略和 TCP/UDP 独立选择；默认回环监听，非回环写入需确认。`none` 是明文，2022 ChaCha 不支持多用户；不接管未建模的 relay、mux 或 plugin。完整 JSON 保留网络限制；SIP002 无法表达单网络限制时返回 warning。长 2022 PSK 在客户端按核心规则派生等效定长密钥，原始状态不变。
- **VMess**：安装菜单 9、管理菜单 22，协议 ID `vmess`，使用 schema 2 marker 与 schema 1 JSON 实例库。支持 1–128 个唯一用户、`security`/`alter_id`、TLS 信任和 none/http/ws/grpc/quic typed transport；WS early data 与 HTTPUpgrade 仍按已知 runtime guard 阻断。客户端导出和 `vmess://` 分享保留可表达字段，不读取服务器私钥；SubMan 仅同步 TLS 系统信任且 URI 无损可表达的用户。
- **普通 VLESS**：安装菜单 10、管理菜单 23，协议 ID `vless-plain`（运行时 type 仍为 `vless`），使用独立 schema 2 marker 与 schema 1 JSON 实例库。支持 1–128 个用户、按用户 `flow`、TLS 信任和 none/http/ws/grpc/quic typed transport；客户端导出和 `vless://` 分享不读取服务器私钥，SubMan 仅同步 TLS 系统信任且 URI 无损可表达的用户。旧 `vless` alias 不会被重新解释，仍表示 VLESS + REALITY。
- **SubMan 同步**：按 SubMan OpenAPI 1.0.0 契约将 VLESS + REALITY、普通 VLESS、Hysteria2、双网络加密 Shadowsocks，以及 TLS 系统信任且 URI 无损表达的 Trojan/VMess 用户幂等推送到节点库；各协议按实例/用户使用稳定外部键，从同一快照生成身份与凭据，无法表达的 TLS、传输、证书信任或 URI 大小条目明确跳过。Hysteria2 的带宽和 masquerade 在完整客户端 JSON 中保留，标准 URI 无法携带时仅以 warning 披露，不伪造 SubMan 字段。仅在 Workspace 已远端提交并回读验证后报告成功，并识别 revision、稳定错误分类和安全重试提示。集成测试使用 mock，不代表已授权或执行真实同步；全部跳过不报告同步成功。
- **规范存储**：统一使用 `/root/sing-box-vps/` 存放配置、密钥及持久化参数。

## Agent 非交互命令

适合 Hermes、OpenClaw、Codex 等 Agent 在 SSH 会话中直接调用：

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
sbv agent instance migrate mixed --json --yes --expected-revision 0
sbv agent instance create mixed --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace mixed --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance delete mixed --json --yes --expected-revision N --id ID
sbv agent instance default mixed --json --yes --expected-revision N --id ID
sbv agent instance recover mixed --json --yes --expected-revision N
sbv agent instance create socks --json --yes --expected-revision N --file record.json
sbv agent instance replace socks --json --yes --expected-revision N --file record.json
sbv agent instance delete socks --json --yes --expected-revision N --id ID
sbv agent instance default socks --json --yes --expected-revision N --id ID
sbv agent instance recover socks --json --yes --expected-revision N
sbv agent instance create vmess --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance replace vmess --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance delete vmess --json --yes --expected-revision N --id ID
sbv agent instance default vmess --json --yes --expected-revision N --id ID
sbv agent instance recover vmess --json --yes --expected-revision N
sbv update sbv
sbv update sing-box latest
sbv update sing-box 1.14.0
```

- `capabilities`：输出十种协议、历史功能入口与 `mutation` / `sensitive` / 确认要求，Agent 应先据此选择操作。新增的 `protocol_registry` 提供 family、preset、role、内部/公开 ID、能力和验证方法；独立 SOCKS、VMess、普通 VLESS、Hysteria2 与 AnyTLS 的实现和生命周期已由定向门禁验证，但不应解读为全协议目标完成。`available=null` 与 `validated.status=not_assessed` 表示尚未对当前实例做环境预检和连接验证，不应解读为可部署或测试通过。
- `upgrade-check`：只读检查固定目标版本的升级资格，返回 `ready`、`blockers[]`、当前核心校验、配置 hash、已知弃用项和兼容性 warning；不会协调或迁移协议状态，也不下载目标二进制，真正的目标版本 `sing-box check` 在 `upgrade` 替换服务进程前执行。
- `upgrade`：必须使用完整版本号和 `--yes`。创建持久备份后只替换核心二进制，逐字节保留服务端配置；备份清单覆盖全部普通 runtime 文件及 binary、`sbv`、service unit、metadata。每次实际变更返回 `transaction.id`、`transaction.result_path` 和 `transaction.result_persisted`，并在备份目录原子写入权限 `0600` 的 `transaction-result.json`。实际变更只有 `result_persisted=true` 才可接受事务状态；若目标版本已经安装，则返回 `changed=false`、`transaction.status=not_attempted`、`reason=already_installed`，且不会创建备份或事务文件。目标校验、版本、配置 hash 或服务状态不符合预期时尝试自动恢复旧二进制、意外变化的配置和升级前服务活动状态，返回非零与结构化回滚结果。仅当 `rolled_back=true` 且 `rollback_ok=true` 时才可视为自动恢复完成；`error=rollback_failed` 时必须停止并人工处理。
- `status`：输出脚本/核心/服务/路径/已安装协议，并包含入站与出站栈、BBR、REALITY 实例与 QoS 计数，以及客户端导出/SubMan 是否已配置；不返回凭据。索引、状态或 live 入站集合无法完整对应时返回非零及 `protocol_index_untrusted` / `protocol_state_untrusted`，不报告部分协议。
- `nodes`：输出所有协议的安全摘要；REALITY、Mixed、SOCKS、HTTP、Shadowsocks、Trojan、VMess、Hysteria2 和 AnyTLS 均逐实例输出，`instance_revision` 可用于下一次 CAS 写入；不包含 UUID、密钥、完整分享链接或密码，适合写入普通诊断日志。实例清单、状态与 live 入站不完整时不输出部分节点。
- `links`：逐协议、逐 REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/AnyTLS 实例输出完整连接材料，包括 VLESS/VMess/Hysteria2 分享链接、Mixed/SOCKS 链接，以及 AnyTLS outbound JSON；AnyTLS 明确返回 `anytls_standard_uri_unavailable` warning；仅在受信任上下文使用，并沿用与 `nodes` 相同的全有或全无清单门禁。Hysteria2 手动 Ed25519 证书会附带稳定的 `warnings[].code`，提示分享链接无法表达 1.14+ 客户端兼容开关。
- `warp`：输出 Cloudflare Warp 状态（启用/路由模式/账户/自定义域名规则集统计），安全用于日常诊断。
- `export-client`：生成并通过 `sing-box check` 校验裸核客户端配置，写入 `/root/sing-box-vps/client/sing-box-client.json`，覆盖前创建 `.bak` 备份，同时以 JSON 返回路径和配置内容。对 1.14+ Hysteria2 Ed25519 节点会自动设置顶层 `disable_chrome_parrot: true` 并返回结构化 warning。包含 Mixed 或独立 SOCKS 时逐实例导出为 SOCKS5 + UoT v2，并返回明文传输 warning；Trojan/VMess/普通 VLESS/AnyTLS 按用户完整导出传输与明确的证书信任方式，不读取服务端私钥，不自动关闭验证。VMess URI 与客户端 JSON 均保留 V2Ray `security`、`alter_id` 和 typed transport；AnyTLS 无标准 URI，使用完整 outbound JSON。
- `check`：执行 `sing-box check` 校验服务端配置，并返回 stdout、stderr、退出码和是否通过。
- `doctor`：输出只读诊断报告，包含服务状态、路径存在性、协议状态和嵌入的配置校验结果。
- `service restart`：必须显式传入 `--yes`，先校验配置，通过后才重启服务，并返回重启前后的服务状态。
- `subman-sync`：非交互推送节点到 SubMan；配置缺失时返回结构化错误，不进入交互提示。API 失败时会在 `last_error` 返回稳定的 `code`、`disposition`、HTTP 状态与可用的 `Retry-After`，传输结果不确定时不会盲目重放写请求。 Hysteria2、Trojan 与 VMess 使用独立逐实例/用户路径，完整返回成功、跳过、失败计数及跳过原因；仅 TLS 系统信任且 URI 可无损表达的条目进入同步。
- `instance`：管理 Mixed schema 2 实例。`migrate` 显式把 legacy schema 1 转成 revision 1；`create`/`replace`/`delete`/`default` 使用 `--expected-revision` 做 CAS，凭据通过私有文件输入；删除最后一个实例后移除 active `mixed.env`、索引项和 Mixed inbound，但仍保留空的 JSON store（`schema_version: 1`）作为 revision tombstone，下一次 `create` 必须以该 revision 继续递增，不会重置为 0；`recover` 只处理可验证的未完成事务，缺少防火墙 journal 时失败并要求人工恢复。非回环地址必须显式传 `--allow-public`，并由调用方承担明文暴露风险。首次全新安装仍写 legacy schema 1，直到显式迁移。
- `instance <operation> socks`：使用 `create`/`replace`/`delete`/`default`/`recover`、`--expected-revision`、typed record、共享事务和回滚边界管理独立 SOCKS；记录只表达 SOCKS 入站的监听/认证，不含 HTTP 或 TLS。`migrate socks` 明确返回 invalid arguments；已有 live SOCKS 配置应使用 takeover，不把 legacy `.env` migration 语义套到该预设。六项回归、两核心 check/runtime、菜单和最终 Docker/TCP 门禁已通过，但不应从注册表存在推断为全协议目标完成。
- `instance <operation> http`：操作与 SOCKS 相同，但完整记录必须包含 `tls: {enabled:false}` 或手工 TLS 的 `enabled/server_name/certificate_path/key_path`。非回环写入须显式 `--allow-public`，无 legacy migration。记录示例与限制见 [Agent Runbook](docs/agents/sing-box-vps-agent-runbook.md)。HTTP TLS 节点的 `shareable=false`、`client_exportable=true`，不将空链接视为可用 URI。
- `instance <operation> shadowsocks`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 `listen.network` 和 `authentication`，完整示例见 [Agent Runbook](docs/agents/sing-box-vps-agent-runbook.md#shadowsocks-inbound)。`nodes` 不输出密钥；敏感的 `links` 返回逐用户 URI、outbounds 与限制 warning。
- `instance <operation> vmess`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一 `name`/UUID/`security`/`alter_id` 用户、TLS 信任和 typed V2Ray transport（none/http/ws/grpc/quic）。分享和 SubMan 仅接受 TLS 系统信任且 URI 可无损表达的用户；完整边界见 [VMess 契约](docs/agents/sing-box-vps-agent-runbook.md#vmess-typed-instance-contract)。
- `instance <operation> anytls`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一用户名/密码、必需手工 TLS 证书路径、server name、客户端 `certificate`/`system` 信任和出站策略。AnyTLS 没有标准分享 URI，`links` 返回凭据 outbound JSON 与 `anytls_standard_uri_unavailable` warning；`nodes` 不返回密码。legacy AnyTLS 的 ACME/provider 配置不自动迁移到 typed store，接管会拒绝无法无损表达的字段；完整边界见 [AnyTLS 契约](docs/agents/sing-box-vps-agent-runbook.md#anytls-typed-instance-contract)。
- `instance <operation> hy2`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一用户名/密码、必需手工 TLS、`certificate`/`system` 客户端信任、可独立设置的 `up_mbps`/`down_mbps`、Salamander obfs、masquerade 和出站策略。legacy Hysteria2 的 ACME/provider 配置不自动扁平化；标准 Hysteria2 URI 按用户生成，证书信任、URI 大小、带宽/masquerade 和 Ed25519 客户端开关均返回结构化 warning；完整边界见 [Hysteria2 契约](docs/agents/sing-box-vps-agent-runbook.md#hysteria2-typed-instance-contract)。
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

## 🛠️ 功能菜单

Mixed/SOCKS 分享链接对用户名、密码按字节执行 URI 百分号编码，避免 `@`、`#`、`%`、空格或换行改变链接结构；服务端凭据保持不变。HTTP Basic 无法表达含冒号的用户名或含 ASCII 控制字符的认证：此时 Mixed 的 Agent `links` 只提供 SOCKS5，并返回 `mixed_http_auth_unrepresentable`，不生成不可用的 HTTP 链接。SOCKS5 URI 不携带 UoT v2 等客户端选项，返回 `socks5_uri_transport_options_omitted`；需要完整配置时使用 `export-client` JSON。百分号编码不是加密，链接仍是敏感材料。

1. **安装新协议**：首次安装或向现有实例追加 VLESS REALITY、Mixed、独立 SOCKS、独立 HTTP、Shadowsocks、Trojan、VMess、Hysteria2、AnyTLS；协议选择注册表第 5 项为 SOCKS，第 6 项为 HTTP，第 9 项为 VMess。
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
17. **管理 Mixed 实例**：创建、修改、删除、设置默认实例、迁移 legacy 状态和恢复未完成事务；完整门禁证据见实施记录。
18. **管理 SOCKS 实例**：创建、修改、删除、设置默认实例和恢复未完成事务；使用独立 SOCKS 的 schema 2 typed store，不提供 legacy `.env` migration。
19. **管理 HTTP 实例**：创建、修改、删除、设置默认实例和恢复未完成事务；入口可选明文或手工证书 TLS，使用共享事务，不提供 legacy migration。
20. **管理 Shadowsocks 实例**：逐实例管理认证、监听网络、默认实例与事务恢复，不提供 legacy migration。
21. **管理 Trojan 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、TLS 信任及传输，使用共享 CAS 事务，不提供 legacy migration。
22. **管理 VMess 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、TLS 信任、V2Ray transport、`security` 与 `alter_id`，使用共享 CAS 事务，不提供 legacy migration。
23. **管理 VLESS 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理普通 VLESS 用户、TLS 信任和 V2Ray transport，使用共享 CAS 事务，不提供 legacy migration。
24. **管理 AnyTLS 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、手工 TLS 证书和客户端信任，使用共享 CAS 事务。legacy AnyTLS 仍沿用原 ACME/provider 更新路径，不自动扁平化迁移。
25. **管理 Hysteria2 实例**：逐实例创建、修改、删除、设置默认和恢复；显式管理多用户、手工 TLS、带宽、Salamander obfs、masquerade 与客户端信任。legacy Hysteria2 仍沿用原 ACME/provider 更新路径，不自动扁平化迁移。

当脚本发现二进制、service、配置或协议状态层不完整时，会进入接管/修复流程，而不是把残缺实例直接当作全新安装覆盖。

## 📂 关键路径

- **工作目录**: `/root/sing-box-vps/`
- **配置文件**: `/root/sing-box-vps/config.json`
- **上一版配置备份**: `/root/sing-box-vps/config.json.bak`
- **最后协议删除前的索引备份**: `/root/sing-box-vps/protocols/index.env.bak`
- **协议状态目录**: `/root/sing-box-vps/protocols/`
- **密钥文件**: `/root/sing-box-vps/reality.key` (REALITY) / `warp.key` (Warp)
- **协议状态文件**: `vless-reality.env` / `vless-reality.d/` / `mixed.env` / `instances/mixed.json` / `socks.env` / `instances/socks.json` / `http.env` / `instances/http.json` / `shadowsocks.env` / `instances/shadowsocks.json` / `trojan.env` / `instances/trojan.json` / `vmess.env` / `instances/vmess.json` / `vless-plain.env` / `instances/vless-plain.json` / `hy2.env` / `anytls.env` / `instances/anytls.json`
- **Trojan 结构化实例状态**: `/root/sing-box-vps/protocols/instances/trojan.json`（schema 1 store，`trojan.env` 为 schema 2 active marker）
- **VMess 结构化实例状态**: `/root/sing-box-vps/protocols/instances/vmess.json`（schema 1 store，`vmess.env` 为 schema 2 active marker）
- **AnyTLS 结构化实例状态**: `/root/sing-box-vps/protocols/instances/anytls.json`（schema 1 store，`anytls.env` 为 schema 2 active marker；仅保留手工 TLS，无法无损接管 ACME/provider）
- **Hysteria2 结构化实例状态**: `/root/sing-box-vps/protocols/instances/hy2.json`（schema 1 store，`hy2.env` 为 schema 2 active marker；手工 TLS 多实例记录保留用户、带宽、obfs、masquerade；legacy ACME/provider 仍保留原状态）
- **Mixed 结构化实例状态**: `/root/sing-box-vps/protocols/instances/mixed.json`（显式迁移或实例写入后启用）
- **Mixed 事务恢复材料**: `/root/sing-box-vps.instance-write.lock`、`/root/sing-box-vps.instance-transactions/`
- **REALITY QoS 状态**: `/root/sing-box-vps/reality-qos.filters`
- **Warp 分流域名**: `/root/sing-box-vps/warp-domains.txt`
- **Warp 本地规则集目录**: `/root/sing-box-vps/rule-set/warp/`
- **Warp 远程规则集列表**: `/root/sing-box-vps/warp-remote-rule-sets.txt`
- **流媒体验证脚本缓存**: `/root/sing-box-vps/media-check/region_restriction_check.sh`
- **SubMan API 配置**: `/root/sing-box-vps/subman.env`
- **Agent 升级备份**: `/root/sing-box-vps-backups/`（包含敏感运行材料，仅 root 可读）
- **全局命令**: `/usr/local/bin/sbv`

## ⚠️ 注意事项

- 本脚本必须以 `root` 用户身份运行。
- 脚本默认适配最佳稳定性版本，手动选择 `latest` 可能存在不兼容风险。
- `Mixed` 代理默认建议启用用户名密码认证；若关闭认证，请务必确认防火墙和来源访问控制策略。当前 Mixed 入口及导出 SOCKS5 链路未启用 TLS，用户名密码和非加密业务可能暴露，仅应在可信网络或受保护隧道内使用；UoT v2 只把 UDP 封装在 TCP 中，不提供加密，也不要求开放额外的服务端固定 UDP 端口。
- `Hysteria2` 支持 ACME 自动签发与手动证书路径两种 TLS 模式；使用 ACME `DNS-01` 时当前仅支持 Cloudflare。sing-box 1.14+ 客户端连接使用 Ed25519 手动证书的节点时必须禁用 Chrome QUIC 模拟；裸核配置导出会自动处理，分享链接和 SubMan 同步则会输出显式警告。
- `AnyTLS` legacy schema 1 仍支持 ACME 自动签发与手动证书路径；schema 2 typed 实例为可审计的手工证书路径、用户名/密码和 `certificate`/`system` 客户端信任。由于官方文档未定义标准分享 URI，Agent `links` 和客户端导出使用完整 sing-box outbound JSON，并显式将 `client_metadata` 设为空；无法无损表达的 ACME/provider live 配置会拒绝接管而保留原状态。
- SubMan 同步使用公开的 `PUT /api/nodes/by-key/:externalKey` 契约；双栈迁移清理旧 key 时会先读取 Workspace revision，再通过公开节点删除接口提交，避免空 `raw` 或直接修改 Gist。
- 流媒体验证功能当前接入第三方项目 `1-stream/RegionRestrictionCheck`，脚本内已注明作者与仓库地址，后续可替换为自定义检测后端。

---

## 👨‍💻 作者

**KnowSky404**
- 项目地址: [https://github.com/KnowSky404/sing-box-vps](https://github.com/KnowSky404/sing-box-vps)

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
