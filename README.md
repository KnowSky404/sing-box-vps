# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。当前适配 **sing-box 1.14.x**，并保留显式固定 1.13.x 时的配置兼容能力。

## 📌 当前版本信息

- 脚本版本：`2026090202`
- sing-box 适配版本：`1.14.0`

## 🚀 一键安装

在您的 VPS 上运行以下命令即可开始安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh)
```

如需独立执行彻底卸载，可运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/uninstall.sh)
```

## 开发验证工作流

Docker 验证镜像自动管理，无需额外配置。

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
- 远程验证默认优先收敛到 `runtime_smoke`；安装/重配相关改动会扩到全新安装、接管、重配，以及真实的 `upgrade_1_13_to_1_14` 固定版本升级场景

命中远程验证时，测试机会额外执行协议级闭环探测：在测试机本机启动临时客户端，连接测试机本机的服务端入站，再通过该客户端代理访问测试机本机 HTTP 探针服务。当前优先支持 `vless-reality` 与 `hy2`；未覆盖协议会在产物中标记为 `unsupported`。

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

- **Agent 友好命令行**：提供 `sbv agent ... --json` 非交互命令，方便 Hermes、OpenClaw、Codex 等 AI Agent 发现完整能力、获取状态与节点信息、导出客户端配置，并执行带预检、确认、持久备份和自动回滚的固定版本升级。
- **1.14.x 深度适配**：继续采用 **Endpoint（端点化）** 架构，并适配顶层 ACME `certificate_providers`、远程规则集 `http_client` 与 Hysteria2 `disable_chrome_parrot`。
- **跨版本配置生成**：目标核心为 1.14+ 时生成新版配置结构；显式固定或运行 1.13.x 时继续生成内联 `tls.acme` 与旧版远程规则集结构。仅更新二进制时不会重写现有配置。
- **可审计升级**：`upgrade-check` 会报告实例健康度、当前配置校验、配置 SHA-256、1.14 已知弃用项和阻断原因；`upgrade` 只接受固定版本与 `--yes`，先在 `/root/sing-box-vps-backups/` 创建 root-only 备份，目标核心校验失败时尝试恢复旧二进制并返回非零；若恢复未通过最终校验，会明确返回 `rollback_failed` 和人工介入标记。
- **多协议支持**：支持 **VLESS + REALITY**、**Mixed (HTTP/HTTPS/SOCKS)**、**Hysteria2** 与 **AnyTLS** 四种入站模式，并支持多协议同时安装。
- **VLESS REALITY 多实例**：可在安装菜单追加多个 REALITY 实例，每个实例拥有独立端口、ShortID、节点名称、可选上下行限速和实例级出站策略；节点展示和 SubMan 同步会逐实例输出。
- **REALITY QoS 限速**：为设置了上下行 Mbps 的 REALITY 实例自动规划并应用 `tc` 端口级限速规则，重建配置、更新协议或移除实例时会同步刷新规则，避免遗留过滤器影响新配置。
- **Cloudflare Warp 集成**：支持一键开启/关闭 Warp 出站，自动注册免费账户，完美解决 VPS **“送中”** 问题并解锁 Netflix/Disney+ 等流媒体。
- **Warp 路由分层**：支持 `全量走 Warp` 与 `选择性分流` 两种模式，默认采用更稳妥的 `选择性分流`，内置主流 AI / 流媒体域名规则，并支持用户追加自定义域名、本地规则集和远程规则集；VLESS REALITY 实例还可单独选择跟随全局、强制 direct 或强制 Warp 出口。
- **单一真源**：统一以 `install.sh` 作为安装与维护入口，避免历史旧入口与当前实现漂移。
- **托管实例自修复**：当协议状态层与运行中的 `config.json` 发生漂移时，会优先按协议状态自动重建运行配置，降低 `mixed` 等附加协议意外丢失的风险。
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

- `capabilities`：输出四种协议、历史功能入口与 `mutation` / `sensitive` / 确认要求，Agent 应先据此选择操作。
- `upgrade-check`：只读检查固定目标版本的升级资格，返回 `ready`、`blockers[]`、当前核心校验、配置 hash、已知弃用项和兼容性 warning；它不下载目标二进制，真正的目标版本 `sing-box check` 在 `upgrade` 替换服务进程前执行。
- `upgrade`：必须使用完整版本号和 `--yes`。创建持久备份后只替换核心二进制，逐字节保留服务端配置；目标校验、版本、配置 hash 或服务状态不符合预期时尝试自动恢复旧二进制（配置若意外变化也一并恢复），返回非零与结构化回滚结果。仅当 `rolled_back=true` 且 `rollback_ok=true` 时才可视为自动恢复完成；`error=rollback_failed` 时必须停止并人工处理。
- `status`：输出脚本/核心/服务/路径/已安装协议，并包含入站与出站栈、BBR、REALITY 实例与 QoS 计数，以及客户端导出/SubMan 是否已配置；不返回凭据。
- `nodes`：输出所有协议的安全摘要；REALITY 会逐实例返回端口、上下行限速与出站策略，不包含 UUID、密钥、完整分享链接或密码，适合写入普通诊断日志。
- `links`：逐协议、逐 REALITY 实例输出完整连接材料，包括 VLESS/Hysteria2 分享链接、Mixed HTTP/SOCKS 链接，以及 AnyTLS outbound JSON；仅在受信任上下文使用。Hysteria2 手动 Ed25519 证书会附带稳定的 `warnings[].code`，提示分享链接无法表达 1.14+ 客户端兼容开关。
- `warp`：输出 Cloudflare Warp 状态（启用/路由模式/账户/自定义域名规则集统计），安全用于日常诊断。
- `export-client`：生成并通过 `sing-box check` 校验裸核客户端配置，写入 `/root/sing-box-vps/client/sing-box-client.json`，覆盖前创建 `.bak` 备份，同时以 JSON 返回路径和配置内容。对 1.14+ Hysteria2 Ed25519 节点会自动设置顶层 `disable_chrome_parrot: true` 并返回结构化 warning。
- `check`：执行 `sing-box check` 校验服务端配置，并返回 stdout、stderr、退出码和是否通过。
- `doctor`：输出只读诊断报告，包含服务状态、路径存在性、协议状态和嵌入的配置校验结果。
- `service restart`：必须显式传入 `--yes`，先校验配置，通过后才重启服务，并返回重启前后的服务状态。
- `subman-sync`：非交互推送节点到 SubMan；配置缺失时返回结构化错误，不进入交互提示。API 失败时会在 `last_error` 返回稳定的 `code`、`disposition`、HTTP 状态与可用的 `Retry-After`，传输结果不确定时不会盲目重放写请求。
- `update sbv`：从 GitHub 更新 `/usr/local/bin/sbv` 管理脚本；别名为 `sbv update-sbv`。
- `update sing-box [latest|x.y.z]`：普通运维更新入口，逐字节保留现有配置，目标核心校验通过后才重启服务，失败明确返回非零；别名为 `sbv update-sing-box [latest|x.y.z]`。自动化升级优先使用上面的固定版本 `agent upgrade`。

已有 1.13.x 主机应先运行 `sbv update sbv` 更新管理脚本，再调用 `capabilities` 与 `upgrade-check`。1.14 对旧版 inline `tls.acme` 和远程规则集 `download_detour` 会给出弃用 warning，但两者到 1.16 才移除，因此 warning 本身不会阻止 1.13→1.14；其他真实不兼容会在目标 1.14 二进制的 `sing-box check` 阶段阻止重启并触发回滚。

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
