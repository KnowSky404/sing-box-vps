# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。当前适配 **sing-box 1.14.x**，并保留显式固定 1.13.x 时的配置兼容能力。

## 📌 当前版本信息

- 脚本版本：`2026090706`
- sing-box 适配版本：`1.14.0`

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

Agent 节点/分享列表与 REALITY 客户端导出共用只读实例接口：旧单实例状态内部映射为 `main`，REALITY 保留原实例身份；读取和客户端渲染不自动迁移旧状态或生成凭据。其他协议的多实例持久化仍在实施中。

开发中的结构化实例存储已加入严格数据模型、revision 条件写入与候选渲染的基础接口，首先验证 Mixed 字段适配器。它尚未接入交互/Agent 写命令及现有实例重建流程，不会自动迁移 `.env`，也不表示当前已支持 Mixed 多实例完整管理。

服务端候选和结构化状态现在共用固定监听资源预检：区分 TCP/UDP，识别 IPv4 通配、IPv6 等价地址和双栈重叠；冲突时保留原配置。防火墙开放取自完整已发布配置的实际监听传输；删除根据旧配置备份和剩余入站保护仍被引用的规则，不再同时操作无关 TCP/UDP。全量删除必须先确认服务已停止；清单缺失或无法解释时拒绝清理。后端失败返回非零并明确披露已提交配置、尚未执行重启或可能存在的部分外部变更。这仍不是完整防火墙归属账本或系统资源事务，不追溯删除未归属的历史宽规则，也不检查其他进程抢占端口、动态 UDP relay 和 ACME 临时监听。

全协议改造按[实施记录](docs/superpowers/plans/2026-09-06-unified-protocol-management.md)推进；[上游能力矩阵](docs/superpowers/specs/2026-09-06-protocol-coverage.md)区分上游支持与项目已实现能力。当前运行时注册表位于独立分发的 `install.sh` 中，原四协议的菜单编号、公开 ID、导出候选、SubMan 类型和验证器元数据均从这里读取。未知索引/状态版本或生成器返回的无效片段会阻断重建并保留原文件。现有配置的入站清单也会全量预检：未知类型、非 REALITY 的 VLESS、重复的单实例协议和重复显式 tag 会阻断自动重建/接管，不再仅识别第一个受支持入站。Agent 的 `status`、`nodes`、`links` 还要求索引、基础状态和 live 协议集合完全对应；REALITY 的旧状态必须包含完整连接字段，多实例状态的清单、文件名、内部 ID 和 inbound tag 必须与 live VLESS 集合一一对应，否则只返回结构化错误而不输出部分结果。服务端与客户端候选还会检查组件 tag、引用和显式依赖环，然后继续执行目标核心 `check`；这些检查尚不覆盖任意外部配置的字段及出站/端点/路由无损接管，也不表示新增协议已完成。

```bash
bash dev/verification/run.sh
```

只想验证本地调度与触发规则时，可运行：

```bash
VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh
```

核心脚本改动会自动触发远程验证；仅修改 `tests/`、`docs/`、`README.md` 不会占用测试机。

默认工作流已做分层优化：
- 核心脚本改动默认只跑协议探测快测
- 仅在改动 `dev/verification/run.sh`、`dev/verification/common.sh` 或 `dev/verification/remote/` 时，才追加远程调度与远程框架回归
- 远程验证默认优先收敛到 `runtime_smoke`；安装/重配相关改动会扩到全新安装、接管、重配、四协议同时安装，以及真实的 `upgrade_1_13_to_1_14` 成功升级和 `upgrade_rollback_1_13_to_1_14` 故障回滚场景

命中远程验证时，测试机会额外执行协议级闭环探测：先用目标 `sing-box` 校验客户端配置，再启动临时客户端连接本机服务端入站，并通过客户端 SOCKS 代理访问本机 HTTP 标记服务。`vless-reality`、`mixed`、`hy2` 与 `anytls` 四种协议均执行真实连接；未知协议会在产物中标记为 `unsupported`。

脚本会自动：
1. 安装所有必要依赖（curl, wget, jq, qrencode 等）。
2. 下载并配置适配的 `sing-box` (当前适配：1.14.0)。
3. 生成安全的 **VLESS + REALITY**、**Mixed (HTTP/HTTPS/SOCKS)**、**Hysteria2** 或 **AnyTLS** 配置，并支持多协议共存；其中 VLESS REALITY 支持多实例、独立端口和可选上下行限速。
4. 以 **`install.sh`** 作为唯一安装与维护真源，并将自己安装为全局命令 **`sbv`**，方便您随时管理。

---

## 🎮 快速管理

安装完成后，您可以在任何目录下直接输入 `sbv` 来打开交互式管理菜单：

```bash
sbv
```

## ✨ 项目特性

- **Agent 友好命令行**：提供 `sbv agent ... --json` 非交互命令，方便 Hermes、OpenClaw、Codex 等 AI Agent 发现完整能力、获取状态与节点信息、导出客户端配置，并执行带预检、确认、持久备份和自动回滚的固定版本升级。所有 `--json` 响应采用 `schema_version: "1.0"` 统一 envelope，同时保留兼容字段 `schema: "1"`；对外协议 ID 统一使用 `vless-reality`、`mixed`、`hysteria2`、`anytls`。
- **1.14.x 深度适配**：继续采用 **Endpoint（端点化）** 架构，并适配顶层 ACME `certificate_providers`、远程规则集 `http_client` 与 Hysteria2 `disable_chrome_parrot`。
- **跨版本配置生成**：目标核心为 1.14+ 时生成新版配置结构；显式固定或运行 1.13.x 时继续生成内联 `tls.acme` 与旧版远程规则集结构。接管或重建时会保留可内联表达的 ACME 扩展字段；若 provider 引用了无法独立保留的共享 `http_client`，脚本会拒绝重写。仅更新二进制时不会重写现有配置。
- **可审计升级**：`upgrade-check` 会报告实例健康度、当前配置校验、配置 SHA-256、1.14 已知弃用项和阻断原因；`upgrade` 只接受固定版本与 `--yes`，先在 `/root/sing-box-vps-backups/` 创建 root-only 备份，并原子维护 `transaction-result.json`（事务 ID、旧/新版本、状态历史、manifest hash 与回滚结果）。目标核心校验失败时尝试恢复旧二进制并返回非零；若恢复未通过最终校验，会明确返回 `rollback_failed` 和人工介入标记。
- **多协议支持**：支持 **VLESS + REALITY**、**Mixed (HTTP/HTTPS/SOCKS)**、**Hysteria2** 与 **AnyTLS** 四种入站模式，并支持多协议同时安装。
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
- **防火墙自动化**：安装或修改端口时，自动尝试在 `UFW`, `Firewalld` 或 `Iptables` 中放行。
- **工业级配置生成**：采用 **`jq` 安全注入** 模式生成 JSON，彻底规避特殊字符导致的转义错误。
- **协议级展示**：终端可按协议查看节点信息，支持 `VLESS` 与 `Hysteria2` 链接/ANSI 二维码展示，为 `Mixed` 输出代理链接与二维码提示，并为 `AnyTLS` 输出参数摘要和 sing-box outbound JSON 示例；多 REALITY 实例会显示实例 ID、端口和限速摘要。
- **裸核客户端导出**：可从交互菜单或 `sbv agent export-client --json` 生成 `/root/sing-box-vps/client/sing-box-client.json`，覆盖前自动备份，并在输出前执行 `sing-box check`。
- **SubMan 同步**：按 SubMan OpenAPI 1.0.0 契约将当前 VPS 的 VLESS / Hysteria2 节点幂等推送到节点库；仅在 Workspace 已远端提交并回读验证后报告成功，并识别 revision、稳定错误分类和安全重试提示。
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
sbv update sbv
sbv update sing-box latest
sbv update sing-box 1.14.0
```

- `capabilities`：输出四种协议、历史功能入口与 `mutation` / `sensitive` / 确认要求，Agent 应先据此选择操作。新增的 `protocol_registry` 提供 family、preset、role、内部/公开 ID、能力和验证方法；`available=null` 与 `validated.status=not_assessed` 表示尚未对当前实例做环境预检和连接验证，不应解读为可部署或测试通过。
- `upgrade-check`：只读检查固定目标版本的升级资格，返回 `ready`、`blockers[]`、当前核心校验、配置 hash、已知弃用项和兼容性 warning；不会协调或迁移协议状态，也不下载目标二进制，真正的目标版本 `sing-box check` 在 `upgrade` 替换服务进程前执行。
- `upgrade`：必须使用完整版本号和 `--yes`。创建持久备份后只替换核心二进制，逐字节保留服务端配置；备份清单覆盖全部普通 runtime 文件及 binary、`sbv`、service unit、metadata。每次实际变更返回 `transaction.id`、`transaction.result_path` 和 `transaction.result_persisted`，并在备份目录原子写入权限 `0600` 的 `transaction-result.json`。实际变更只有 `result_persisted=true` 才可接受事务状态；若目标版本已经安装，则返回 `changed=false`、`transaction.status=not_attempted`、`reason=already_installed`，且不会创建备份或事务文件。目标校验、版本、配置 hash 或服务状态不符合预期时尝试自动恢复旧二进制、意外变化的配置和升级前服务活动状态，返回非零与结构化回滚结果。仅当 `rolled_back=true` 且 `rollback_ok=true` 时才可视为自动恢复完成；`error=rollback_failed` 时必须停止并人工处理。
- `status`：输出脚本/核心/服务/路径/已安装协议，并包含入站与出站栈、BBR、REALITY 实例与 QoS 计数，以及客户端导出/SubMan 是否已配置；不返回凭据。索引、状态或 live 入站集合无法完整对应时返回非零及 `protocol_index_untrusted` / `protocol_state_untrusted`，不报告部分协议。
- `nodes`：输出所有协议的安全摘要；REALITY 会逐实例返回端口、上下行限速与出站策略，不包含 UUID、密钥、完整分享链接或密码，适合写入普通诊断日志。REALITY 根状态、实例清单、实例文件或 live tag 集合不完整时不输出部分节点。
- `links`：逐协议、逐 REALITY 实例输出完整连接材料，包括 VLESS/Hysteria2 分享链接、Mixed HTTP/SOCKS 链接，以及 AnyTLS outbound JSON；仅在受信任上下文使用，并沿用与 `nodes` 相同的全有或全无清单门禁。Hysteria2 手动 Ed25519 证书会附带稳定的 `warnings[].code`，提示分享链接无法表达 1.14+ 客户端兼容开关。
- `warp`：输出 Cloudflare Warp 状态（启用/路由模式/账户/自定义域名规则集统计），安全用于日常诊断。
- `export-client`：生成并通过 `sing-box check` 校验裸核客户端配置，写入 `/root/sing-box-vps/client/sing-box-client.json`，覆盖前创建 `.bak` 备份，同时以 JSON 返回路径和配置内容。对 1.14+ Hysteria2 Ed25519 节点会自动设置顶层 `disable_chrome_parrot: true` 并返回结构化 warning。
- `check`：执行 `sing-box check` 校验服务端配置，并返回 stdout、stderr、退出码和是否通过。
- `doctor`：输出只读诊断报告，包含服务状态、路径存在性、协议状态和嵌入的配置校验结果。
- `service restart`：必须显式传入 `--yes`，先校验配置，通过后才重启服务，并返回重启前后的服务状态。
- `subman-sync`：非交互推送节点到 SubMan；配置缺失时返回结构化错误，不进入交互提示。API 失败时会在 `last_error` 返回稳定的 `code`、`disposition`、HTTP 状态与可用的 `Retry-After`，传输结果不确定时不会盲目重放写请求。
- `update sbv`：从 GitHub 更新 `/usr/local/bin/sbv` 管理脚本；别名为 `sbv update-sbv`。
- `update sing-box [latest|x.y.z]`：普通运维更新入口，逐字节保留现有配置，目标核心校验通过后才重启服务，失败明确返回非零；别名为 `sbv update-sing-box [latest|x.y.z]`。自动化升级优先使用上面的固定版本 `agent upgrade`。

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

1. **安装新协议**：首次安装或向现有实例追加 VLESS REALITY、Mixed、Hysteria2、AnyTLS；REALITY 可继续追加独立实例。
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

当脚本发现二进制、service、配置或协议状态层不完整时，会进入接管/修复流程，而不是把残缺实例直接当作全新安装覆盖。

## 📂 关键路径

- **工作目录**: `/root/sing-box-vps/`
- **配置文件**: `/root/sing-box-vps/config.json`
- **上一版配置备份**: `/root/sing-box-vps/config.json.bak`
- **最后协议删除前的索引备份**: `/root/sing-box-vps/protocols/index.env.bak`
- **协议状态目录**: `/root/sing-box-vps/protocols/`
- **密钥文件**: `/root/sing-box-vps/reality.key` (REALITY) / `warp.key` (Warp)
- **协议状态文件**: `vless-reality.env` / `vless-reality.d/` / `mixed.env` / `hy2.env` / `anytls.env`
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
- `Mixed` 代理默认建议启用用户名密码认证；若关闭认证，请务必确认防火墙和来源访问控制策略。
- `Hysteria2` 支持 ACME 自动签发与手动证书路径两种 TLS 模式；使用 ACME `DNS-01` 时当前仅支持 Cloudflare。sing-box 1.14+ 客户端连接使用 Ed25519 手动证书的节点时必须禁用 Chrome QUIC 模拟；裸核配置导出会自动处理，分享链接和 SubMan 同步则会输出显式警告。
- `AnyTLS` 当前同样支持 ACME 自动签发与手动证书路径两种 TLS 模式；由于官方文档未定义标准分享 URI，脚本默认输出参数摘要与 sing-box outbound JSON 示例，并显式将 `client_metadata` 设为空。
- SubMan 同步使用公开的 `PUT /api/nodes/by-key/:externalKey` 契约；双栈迁移清理旧 key 时会先读取 Workspace revision，再通过公开节点删除接口提交，避免空 `raw` 或直接修改 Gist。
- 流媒体验证功能当前接入第三方项目 `1-stream/RegionRestrictionCheck`，脚本内已注明作者与仓库地址，后续可替换为自定义检测后端。

---

## 👨‍💻 作者

**KnowSky404**
- 项目地址: [https://github.com/KnowSky404/sing-box-vps](https://github.com/KnowSky404/sing-box-vps)

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
