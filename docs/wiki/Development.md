# 开发工作流

本页是当前 checkout 的开发、验证和交付细则，入口在 `AGENTS.md`。按当前任务阶段读取对应章节，使用同一 worktree 的规则和实现契约。

来源为固定 [Manifest 工程规范](https://github.com/KnowSky404/Manifest/blob/6f387de5065b6ffc475908880362939185ff89d7/docs/AI_NATIVE_DEVELOPMENT_WORKFLOW.md)，提交 `6f387de5065b6ffc475908880362939185ff89d7`。升级来源须单独评估。项目保留更严格的每次原子提交后及推送或开 PR 前的本地审查、Actions 独立授权和仅自动触发的远程 Security Review，按项目实际使用定点宿主和 Docker 验证。执行时以本仓库规则为准，固定链接用于溯源。

## 任务准备与提交

- 开始前记录原始需求、目标、范围/非目标、可验收条件、风险、授权、基线 SHA 和任务分支。用 PR 或 worktree 内忽略的 `.task/task.md` 保存简要进度，记录当前 head/阶段、检查与审查轮次、结论、候选、阻塞和下一步。跨机用脱敏 PR 摘要；恢复时先读本地规约并与 Git、检查和真实环境对账。不得提交临时记录或记录私密配置与凭据。
- 检查现有工作区和 worktree，保留其他工作。所有功能迭代、Bug 修复及本规约迁移都必须基于最新远程默认分支创建独立 Git worktree 和任务分支，在其中修改、验证和提交；不得在默认分支直接开发或推送。纯文档等其他改动也可使用相同流程。
- 按[风险与验证范围](#风险与验证范围)执行所需检查，记录实际命令、环境、通过、失败、未执行项及原因。仅提交相关改动，使用原子的 Conventional Commits。交付仓库文件时按[单文件构建](#模块化源码与单文件构建)同步版本，提交后立即进入[审查](#审查与合并)。

## 项目与 Shell 规范

- sing-box-vps 是 VPS 上的通用代理平台，使用模块化配置生成与 Shell 自动化安装、配置和服务管理。优先系统工具（如 `curl`、`sed`、`grep`、`systemctl`），避免多余依赖。优先支持 Debian 11+、Ubuntu 20.04+、CentOS 7+/Stream、AlmaLinux、Rocky Linux。失败安全退出并说明结果，最小权限，保护隐私和密钥，禁止后门。
- 在线查询 sing-box 文档、API、格式、迁移、兼容性或官方示例时，必须先用 Context7。结果不可用、不完整或不覆盖问题时才使用网页检索，优先官方文档、仓库及 migration。
- 可执行 Shell 脚本使用 `#!/usr/bin/env bash`，开头启用 `set -euo pipefail`。UTF-8，2 空格缩进，禁用 Tab。全局变量用大写下划线，局部变量用小写下划线并声明 `local`，函数用描述性的 lowercase_with_underscores。常量、颜色和文件路径在脚本顶层定义。
- 日志以不同颜色区分 INFO、WARN、ERROR、SUCCESS。校验全部用户输入，提供合理默认值，考虑环境变量或参数支持非交互安装。运行入口先检查 root 和必要工具；重复执行应保持已有系统状态，如已安装则提示更新或重新配置。下载、备份、恢复和脱敏按仓库根 `SECURITY.md` 的运行安全要求执行。
- `bootstrap.sh` 在私有临时区下载、校验并启动安装/卸载入口；`uninstall.sh` 是独立卸载入口，负责彻底卸载服务、核心、配置和全局 `sbv`。安装器源码、构建器与 Wiki 生成参考见[构建](#模块化源码与单文件构建)和[命令同步](#ai-native-命令与手册同步)。`docs/wiki/` 是发布 Wiki 的维护源，`docs/specs/` 维护实现契约和中英文状态索引，分别记录实现、本地验证和真实服务验收；`docs/agents/llms.txt` 是 Agent 文档导航。

## 风险与验证范围

默认执行能够覆盖本次改动的最小充分验证集合。选择依据是实际差异、受影响函数及其调用方、配置和系统副作用，而不是文件名或提交数量。执行前说明选择范围与理由；混合改动取各项所需验证的并集。

按行为、影响范围、数据和信任边界选最高适用风险；范围扩大时重判，不能可靠界定时升档。各档均核对完整差异、执行适用检查及[审查与合并](#审查与合并)，Actions 仍受[Actions 授权](#github-actions-授权与定点验证)。

| 等级 | 本项目示例 | 最低证据 |
| --- | --- | --- |
| R0 非运行态 | 普通说明、注释和版本展示 | 文档、版本及适用静态检查 |
| R1 低 | 隔离菜单、文案或渲染 | 定点本地回归；改变输入、控制流或系统操作时升级 |
| R2 中 | 协议、命令、配置生成或隔离事务变化 | 受影响测试及关键调用链；按影响执行对应配置校验、运行态验收和简要回滚 |
| R3 高 | root/信任边界、凭据、持久状态迁移、共享生命周期、验证/CI/发布门禁 | 覆盖受影响系统及失败/恢复路径，独立本地审查、隔离候选验收或等效环境，以及适用的兼容、恢复和回滚证据 |

R3 的全量触发条件仍见本节下文。CI/权限变更按 R3 验证失败和授权边界，隔离宿主和可复现 fixture 可作为该类候选验收。真实外部服务及生产验证按对应授权单独验收。

本节是测试范围的单一规则源，Skill、其他 Wiki 页面和检查清单均按本节选择，不得叠加成固定全套。先区分开发回归、只读审查和完整发布验收；创建 PR、合并或同步脚本版本本身不等于要求完整发布验收。

| 改动类型 | 必须验证的范围 | 何时扩大范围 |
| --- | --- | --- |
| 普通文档、注释、格式 | 差异、链接及相关文档命令检查；Shell 文件适用时执行语法检查 | 可执行安装命令发生变化时，追加 Bootstrap 对应测试；格式调整改变行为时按实际行为分类 |
| 版本号或版本展示 | 脚本与 README 版本一致性及相关语法检查 | 改变核心支持版本、兼容策略或升级行为时，按版本适配或生命周期分类 |
| 菜单、文案、展示 | 对应菜单、渲染或交互回归 | 改变安装输入、控制流或系统操作时，追加相关生命周期 Docker 场景 |
| 单个协议的配置、导出、分享 | 该协议及受影响调用方的测试；受影响配置必须通过 `sing-box check` | 改变监听、握手、传输或服务生命周期时，追加该协议的真实运行态验证；共享路径变化时覆盖其他受影响协议 |
| SubMan 对接 | 对应 payload、API mock、同步编排测试 | 真实服务联调属于独立验收，按用户授权执行，不能用 mock 结果代替 |
| 安装、升级、卸载、接管、恢复 | 对应生命周期本地测试及 Docker 场景 | 影响共享流程时追加相关场景；满足下述全量条件时执行全量回归 |
| 共享配置生成、状态、事务、核心版本适配 | 受影响调用方及能覆盖共享分支的跨协议用例，不默认覆盖所有协议；配置变化追加 `sing-box check` | 影响广泛、涉及迁移或无法可靠界定范围时，按下述全量条件执行 |
| 测试文件、Bootstrap 或验证框架 | 执行修改或新增的可独立运行测试及受影响测试；辅助脚本通过其调用方验证；Bootstrap 执行对应下载和校验测试；调度规则执行相关框架测试 | 改变容器执行、探针或产物协议时，追加对应真实 Docker 验证；单个场景改动覆盖该场景及必要前置依赖 |

**全量回归触发条件**：仅在以下情况要求全量，不因每次修改、每个提交或 PR head 变化而自动重跑。

1. `sing-box` 核心版本适配，或配置、持久状态格式迁移。
2. 跨模块共享逻辑存在广泛影响，或分析后仍无法可靠界定影响范围。
3. 用户明确要求全量验证，或本次交付明确要求完整发布验收。

选择全量时，必须指出本次修改的共享函数、受影响调用方或迁移内容，以及定向测试无法覆盖的具体风险。文件大、尚不熟悉实现、仅触及共享文件、可选字段的兼容新增或版本展示递增，都不单独构成全量理由；兼容新增若实际改变核心版本要求或配置/状态格式，仍按相应触发条件执行。

全量回归必须说明覆盖的本地测试集和 Docker 场景集，不能仅凭入口返回成功宣称全量通过。多平台兼容性验证同样按影响选择：涉及发行版分支、系统工具、Bash 兼容性或宿主网络行为时，覆盖受影响的平台；文档、版本展示、菜单文案等改动不触发多平台矩阵。

**执行与结果复用**：

- 执行前用简短记录列出：行为改动、必要测试/场景及前置依赖、不执行的主要范围和理由、预计耗时。普通文档/版本变更以数分钟内完成为目标；定向本地测试预计超过 10 分钟或 Docker 预计超过 20 分钟时，先说明慢项和必要性。该时间是排查与调整计划的软预算，不是超时后跳过必要检查或宣称通过的依据。
- 选定的必要检查已通过、差异已核对且没有新增风险证据时，停止测试并进入提交/审查流程；不得仅为“更放心”、文件名、提交数或 head SHA 变化追加回归。本地/远程审查并不自动要求再跑测试；发现实际问题并修复后才重跑受影响部分。
- 已通过结果在受测代码、配置、测试及其依赖、核心版本和相关执行环境未变时可以复用，记录原验证对应的提交或内容摘要及复用理由。仅文档变化或提交号变化不使结果自动失效；受测内容或依赖变化后，重新验证受影响部分。
- 失败后先修复根因，重跑失败项及受修复影响的测试；只有新增改动、失败证据或未解决风险表明范围扩大时，才追加验证。
- 超出预计耗时或长时间无进展时，先检查具体慢项、超时、网络、下载和前置状态，再调整计划；不得盲目重启全套或无限重试。未完成的必要检查明确标为未完成。安全审查等待单独记录，不以重复跑测试消耗等待时间；可保留 PR 报告待审状态，不能绕过合并门禁。
- 单个协议不默认覆盖所有协议；单个场景不默认覆盖所有场景。独立运行场景前必须准备其安装基线等前置依赖，不能依赖上轮遗留状态。
- 配置检查、本地 mock、隔离 Docker 探针、公网可达性、真实外部服务和生产验收分别记录，不能互相替代。

### 调度器命令与计划

远程验证通过本地 Docker 隔离运行，无需外部 SSH 测试机。框架自动构建 `sing-box-vps-verify` 镜像，启动一次性特权容器，通过 `docker exec -i` 注入运行时脚本并提取 artifact bundle。

- 优先使用精确的 `--test tests/<name>.sh` 选择受影响函数及调用方；只有确实需要组内覆盖时才用 `--group`，不要为了消除 `needs_scope` 选择整个菜单或协议组。
- `--test` 选择已有独立宿主测试，拒绝 helper、容器专用 fixture、符号链接及越界路径；可重复、去重，与 `--base`、`--group`、`--scenario` 组合。它只追加定点测试，不屏蔽完整差异的自动检查，也不替代运行态验证。
- 普通文档只自动选择 `wiki_documentation.sh`；Agent 或升级手册、协议能力矩阵、生成命令目录和安装命令说明按各自映射追加能力、协议、命令契约或 Bootstrap 检查。安装器、源码或版本变化检查生成字节/语法同步（`install_build_sync.sh`）；构建器或模块清单变化才追加 `install_build.sh` 故障注入。计划器/选择规则变化执行 `verification_planner.sh`、`verification_trigger_rules.sh`、`verification_scenario_mapping.sh`，不因此执行 Docker 传输/产物的大型 mock。执行器或传输变更按其影响选测。

- `dev/verification/run.sh --plan` 只输出计划，不运行测试、探测 Docker 或创建产物目录。`--base <ref>` 使用该 ref 与 HEAD 的 merge-base，并纳入已提交分支差异、暂存/未暂存修改及未跟踪文件；默认仅检查相对 HEAD 的工作区差异。提交后的任务使用 `--base` 并核对完整分支差异。
- 文档、版本元数据、Bootstrap、修改的独立测试和可静态识别的 helper 调用方自动选测；容器专用 fixture 不作为宿主测试执行。安装器实际行为或其他未映射影响默认输出 `needs_scope`，执行前拒绝，要求按[风险与验证范围](#风险与验证范围)选择 `--test <path>`、`--group <name>`、`--scenario <name>` 或 `--full`，不得自动扩大为全套。
- `--group` 选择本地回归组，`--scenario` 选择 Docker 场景及必要前置，两者可重复并组合。显式范围是操作者对影响的判定，不是自动分析已证明覆盖充分；服务/网络/生命周期变化仍必须选择相应场景。`--full` 是明确的宿主测试清单和默认全量场景集（当前保留原 17 场景），与可选场景目录分开，通过 `multi_protocol_coexistence` 的共享断言覆盖组件、协议及转换叶子，不重复执行叶子；必须审阅输出清单，不能等同于执行目录中所有脚本。
- 共享 fixture/断言 helper、aggregate、dispatcher 及外部 REALITY/Tor 场景变化保持 `needs_scope`，须明确影响范围，不自动扩大到全部调用方、完整共存或外网。组件、单协议及转换叶子均包含各自的全新 SOCKS 基线；协议叶子额外只安装目标协议，SOCKS 探针使用基线实例；不能把删除后 revision 递增的空组件 store 当作 revision 0。REALITY 探针和纯协议共存的外部 TLS cover、Tor circuit 均须显式选择并独立记录真实外网证据。mock、监听或本地 marker 无法提供该证据。HTTP/ShadowTLS 协议探针只声明 TCP，其他协议分别保留原生 UDP、XUDP 或 UoT 边界。
- 版本同步虽然修改 `install.sh`，仅版本元数据差异只选版本和语法检查。必要检查也可直接执行；优先选择对应 `component_*`、`protocol_probe_*` 或 Naive/Snell 转换场景；确需纯协议共存或原 aggregate 时说明组合影响及额外覆盖。场景补齐安装基线，最终 smoke 在全部变更操作后执行一次。完整拆分的实施验收须实际执行每个新增叶子及 aggregate 兼容共享路径，保留原 CAS 链和组合断言；不因此执行无关升级、卸载等原全量场景。历史结果与耗时边界、精确 ID 和实现/真实验收状态见本地 `docs/specs/scoped-docker-verification.zh-CN.md`（[仓库页面](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/scoped-docker-verification.zh-CN.md)）。
- `--changed-file` 是显式路径输入，与 `--base` 互斥，不能把遗漏真实改动当作缩小范围的方法。计划记录文件、组、测试、场景与未映射影响；执行时保存 `plan.txt` 和各测试日志/耗时。调度不替代[风险与验证范围](#风险与验证范围)的影响分析。
- `VERIFY_SKIP_REMOTE=1` 在选中的本地测试执行后才跳过 Docker，不是轻量测试开关，不能代替分级选择，也不能据此报告运行态或全量验证通过。需要运行态验证但环境不可用时，明确报告未完成及原因。

在仓库根目录运行。先预览，确认测试和场景满足本次影响，再去掉 `--plan` 执行同一组参数：

```bash
# 分支全部已提交改动 + 暂存/未暂存修改 + 未跟踪文件，只预览
bash dev/verification/run.sh --plan --base origin/main

# 只改菜单布局：精确指定相关测试，保留分支自动检查
bash dev/verification/run.sh --plan --base origin/main --test tests/main_menu_renders_sectioned_layout.sh

# 自更新事务确有影响时才选对应组，按实际影响追加场景
bash dev/verification/run.sh --plan --base origin/main --group self-update

# 单协议本地检查；若改动影响运行态，再显式追加对应场景
bash dev/verification/run.sh --plan --base origin/main --group protocol:http --scenario protocol_probe_http

# 传输/容器执行变更：框架回归 + 真实 Docker 安装与最终 smoke
bash dev/verification/run.sh --plan --base origin/main --group verification --scenario fresh_install_http

# 明确需要完整验收时才选已注册的全量集合
bash dev/verification/run.sh --plan --base origin/main --full
```

`--help` 列出支持的组和场景。组包括 `docs`、`version`、`bootstrap`、`menu`、`routing`、`self-update`、`binary-install`、`warp`、`subman`、`verification` 和 `protocol:<协议>`。`binary-install` 覆盖核心下载、版本查询及升级/回滚故障注入，`warp` 覆盖注册结果不确定、恢复和凭据保护。组只选择本地测试；服务、网络或生命周期变更仍需对应 Docker 验收。多个组/场景可重复指定，本地测试去重。`protocol:hy2` 与 `protocol:hysteria` 分别指 Hysteria2 和 Hysteria v1。

动态构造的依赖无法保证被自动发现，仍须按完整差异判断影响。

计划输出 `base`、`file`、`group`、`syntax`、`test`、`scenario` 和选择理由/未映射影响。`plan_status=needs_scope` 时预览仍成功，实际执行返回 2，且不运行任何测试或 Docker；错误参数、无效 ref 或未知组/场景同样在执行前返回 2。`--plan` 不运行测试、不探测 Docker、不创建结果目录。执行后保存 `dev/verification-runs/<时间>/plan.txt`、逐测试日志/耗时以及场景产物，首个失败立即返回，不自动重复全套。

场景根据本次运行已建立的状态补齐前置：独立 `runtime_smoke` 使用较轻的 `fresh_install_http`；VLESS 重配置需要 `fresh_install_vless` 基线；卸载验证先建立可核对旧 UUID 的 VLESS 安装；最终 smoke 在所有变更场景之后。若中途其他场景替换了安装，会重新准备必要基线，计划可能包含重复安装。定点叶子已覆盖各出站、宿主策略、单协议及模式转换；纯协议共存与原完整 aggregate 仍供确有组合影响时显式选择。需确认计划中的额外覆盖，不能仅凭名称推断耗时很短。

全量清单维护于 `selection.sh`，全量结果仍须独立记录公网和外部服务行为。独立 `hy2_instance_acme_runtime.sh` 是 Pebble/私有 CA 容器 fixture，现有注册场景不调用它；直接修改它或静态引用它的 helper 时，调度器保持 `needs_scope`，即使 `--full` 也不能代替其独立隔离运行。保留该未完成边界并按专属容器流程验证，不要在宿主执行它。

同样的宿主保护适用于 `routing_policy_runtime.sh`、`routing_policy_legacy_runtime.sh`、`routing_policy_manual_references_runtime.sh`、`component_runtime_acceptance.sh`、`selector_urltest_runtime.sh`、`acme_component_runtime.sh`、`namespace_core_runtime.sh`、`tailscale_openconnect_runtime.sh` 和 `cloudflared_runtime.sh`。它们要求新的可丢弃 Docker、显式标志及各自对端；生产 Cloudflared 还需要事先授权的专用临时资源和私密凭据文件。脚本或其 helper 发生变化时，计划保留独立隔离运行要求，普通组及 `--full` 均不能把它们当作宿主测试。具体范围、证据和条件见 [协议完成契约](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/full-protocol-completion.zh-CN.md)。

`bash tests/integration_subman_app.sh` 使用 `SUBMAN_SOURCE_DIR` 指定的 SubMan 已提交源码及其锁定依赖，在 `/tmp` 构建隔离 Worker/SQLite 联调，GitHub 对端保持隔离。`integration_subman_production.mjs` 不由普通测试入口执行；必须明确授权目标、私密凭据文件和生产验收标志，只创建、修改和清理本轮独有测试节点/聚合，使用条件写入并核对原业务与发布文件。凭据与完整分享材料不进入公开证据。

## 审查与合并

- 每次完成一个原子提交后，必须立即在本地执行 `/review` 对该提交范围进行代码审查，记录审查范围、提交 SHA、结果和问题处理情况；若当前环境没有该入口，执行等效的本地提交范围审查并明确记录。发现问题时先修复、完成受影响验证并重新提交，再次本地审查，直到没有未解决问题。
- **推送与创建 PR 前置门禁**：每次推送（包括首次推送、修复后的追加推送）或创建 PR 前，必须先完成本地 `/review` 并解决发现的问题。审查须覆盖本次待推送的全部提交及任务分支相对基线的完整差异，结果必须对应当前 HEAD；审查未完成、失败或仍有未解决问题时，不得推送或创建 PR。审查后产生新提交或差异变化时，必须重新本地审查；推送与随后创建 PR 之间若 HEAD 和差异未变，可以复用同一次已完成的本地审查。无 `/review` 入口时沿用上一条的等效审查要求，不能以稍后进行的 PR 机器人审查代替此前置门禁。
- 当前 HEAD 的一次本地审查可同时覆盖最近原子提交和任务分支完整差异，记录两者范围后满足上述两个门禁，无需对同一差异重复启动审查；受测内容未变时按[风险与验证范围](#风险与验证范围)复用测试结果。
- 本地审查门禁通过且按[Actions 授权](#github-actions-授权与定点验证)确认不会未经授权触发 Actions 后，推送任务分支并创建 PR，以默认分支为 PR 目标，记录变更、验证结果和本地审查证据。远程仅保留仓库自动触发的 GPT/Codex Security Review；不得手动评论召唤 Code Review 或 Security Review，也不得通过切换草稿/可审查状态、空提交或其他人为重触发方式补出机器人任务。远程 Code Review 不作为合并门禁，不主动触发或等待；任何已报告的问题仍须核实并处理。
- 审查聚焦正确性、契约和实际安全边界，确定性的格式、构建和已知回归交给检查。记录触发条件、影响与证据。P0（严重泄露、数据损失或中断）及 P1（重大正确性/安全回归）阻塞；P2（局部实质缺陷）按验收与安全影响定，P3 和建议通常可延期。记录修复及证据、不适用及理由、或延期原因及跟进。实际新增的安全、隐私、完整性或验收失败不得延期。
- 优先汇总同一候选的 CI、代码及安全反馈后批量处理。同一候选的并行反馈计一轮，跨推送/会话保留计数。R0 不安排额外循环，R1 最多 2 轮，R2/R3 最多 3 轮自主反馈修复。达到预算仍有阻塞则保留 PR，向 Owner 提交根因、证据和处置选项。预算不免除门禁。修复后只复验受影响项，仍对新的完整差异完成一次当前 HEAD 审查。
- 合并前只读核对当前 PR head 的必要检查、自动审查记录和未解决意见。当前 head 已自动触发 Security Review 时，必须等待完成并确认没有未解决问题；排队、运行中、失败、取消或查询失败均不能按“未触发”放行。确认没有自动触发任何机器人审查时，记录 `not_triggered`，在本地审查、必要验证和 GitHub 必需检查通过且没有未解决问题后直接 rebase 合并，无需手动触发或额外等待机器人；仅自动 Code Review 而无自动 Security Review 时同样不增加远程等待门禁。未触发不等于安全审查通过，不得将旧 head 的报告作为当前 head 的已审查证据。后续提交改变 head 后，重新验证受影响内容、完成本地审查后推送，并按相同规则核对新 head 的自动触发状态。
- 权限、审查或检查阻塞时保留 PR 和工作区并说明原因。合并前按[候选、发布与交接](#候选发布与交接)核对当前基线及集成复验条件，即使能无冲突 rebase 也须核对。默认分支推进导致冲突或要求更新时，安全解决后重新验证受影响内容并复核门禁。满足验证和审查要求后，直接使用 GitHub 的 rebase 合并 PR，无需再次请求合并确认；确认远程默认分支包含合并结果，并核实远程任务分支已自动删除。若分支仍在，核对远端 tip，并以合并时的 PR head 为条件删除。分支已推进、tip 无法确认或无法执行条件删除时保留并报告。确认没有未保存的用户改动或需要保留的产物后，清理对应 worktree 和本地任务分支。未完成的审查、验证、权限问题或清理障碍必须如实报告，不得绕过。
- GitHub `main` 启用分支保护：所有变更通过 PR、保持线性历史、解决审查对话，禁止强推和删除，并对管理员生效；仓库仅允许 rebase 合并且合并后自动删除远程分支。GPT/Codex 机器人以 PR 评论报告审查结果，不是 GitHub 必需状态检查；执行者须主动核对本地审查、必要检查及实际自动触发的当前 head Security Review。未自动触发机器人时遵循上一条的直接合并分支，不手动召唤机器人。

### GitHub Actions 授权与定点验证

**自动 PR CI**

- Owner 授权启用仓库 Actions 并运行 `pr-contract.yml`。唯一的自动入口是指向 `main` 的 `pull_request`，只响应 `opened`、`synchronize`、`reopened`。同一 PR 的新运行取消旧运行。无路径过滤，文档及工作流改动也会产生同名 `PR contract` 检查。提交时直接以 `main` 为目标；旧 PR 仅变更目标但没有当前检查时，等待实际提交同步，或新建一个面向 `main` 的 PR 取代旧 PR。
- 一次性 GitHub 托管 runner 核对事件的合成合并 SHA 与 PR head，再检查差异空白、脚本语法、生成一致性、版本、文档链接和触发器契约。日志记录 head、实际基线、merge SHA 与 tree。流水线没有部署环境、密钥、写权限、自托管 runner 或持久 checkout 凭据。启用前须将公共 fork 设置为所有外部贡献者都需审批。维护者对实际 head 核对 workflow、触发器及权限后才可批准；候选更新仍按此核对。Fork 等待审批或 PR 有冲突时，记录为未取得托管证据。
- 每次 GitHub 写操作前只读核对启用状态和直接/间接触发。只有上述自动路径获得长期授权；新增/恢复其他自动入口、启用其他工作流、手动运行和重跑仍各需明确授权。开发、推送、PR、合并或发布授权不包含额外 Actions。无法排除未授权触发时，先暂停对应写操作。
- 推送前完成必要本地验证及当前 HEAD 审查。PR 创建后观察快速 CI 和自动安全审查，收齐适用反馈后批量修复。CI 记录合成合并提交的第一父提交作为实际验证基线。合并前核对 `PR contract` 成功结果中的 head、基线及集成 tree 与当前候选相符；缺失、取消、跳过、失败或过期均不得当成通过。基线推进时按[集成复验](#候选发布与交接)核对证据，等价才复用。合并不会通过 `push` 再运行一次，也不触发部署。
- 初次上线先检查现有分支的工作流和打开的 PR，确认手动工作流仍禁用且没有其他待触发入口。将 fork 审批设为 Require approval for all external contributors 并回读。启用 Actions 时在同一次设置中选择受限策略（API 同时设置 `enabled=true` 与 `allowed_actions=selected`）。外部 Actions 仅允许 GitHub 自有 Actions。API 单独提交允许列表时，回读名单、默认只读令牌及手动工作流状态后再推送候选或创建 PR。
- `PR contract` 是项目合并门禁，初次上线保留现有分支保护。要求上升为 GitHub 强制检查时，先核实稳定的检查名、每种 PR 状态的结果和失败/取消边界，再取得 Owner 对分支保护变更的明确授权。若授权范围无法保持，先停用新增工作流或恢复仓库 Actions 关闭状态。

**按需宿主验证**

- `command-contract.yml` 保留 `workflow_dispatch`，初次启用自动 CI 时继续禁用。需要较重的候选宿主验证时，分别取得启用和指定 workflow、ref、基线、测试范围的运行授权。未获授权记 `not_run_not_authorized`；本地必要验证和复审照常执行。禁用、取消或未授权的检查不算通过，已有失败单独记录。
- 获准后从受保护的 `main` 加载可信定义，传入完整候选 head 和基线 SHA。`command-contract` 复用宿主执行器，按完整差异选测并保留固定契约。未知影响需要分支更新绑定实际 merge-base 的 `.github/verification-scope.txt`。`scoped-host-verification` 产物保留计划、逐项日志、耗时和概要 14 天。运行态、外部服务和生产结果各自记录。

```bash
# 主分支须已包含本页对应工作流，获准后指定候选和基线完整 SHA
gh workflow run command-contract.yml --ref main -f head_sha="$task_head" -f base_ref="$task_base"
```

选择需要 1.13 和 1.14 的兼容测试时，在获准范围内追加 `-f legacy_core=true`。
只验证 1.14 时，独立的 1.13 分支留在范围之外，报告显示 1.13 未配置。要求双核心的
测试和明确选择的核心检查若未运行，仍会阻塞宿主门禁。

输入校验通过后分别检出受保护的工作流提交和候选 SHA，并复核候选 HEAD。比较基线必须属于
执行本次工作流的受保护 main 历史。尚未集成的候选须用与受保护 main 的实际 merge-base。
已进入受保护 main 历史的提交，可以用获准的更早祖先作为范围基线。
受保护提交中的
`ci.sh` 和计划器验证候选目录。候选选测规则若与受保护版本不同，宿主门禁在执行前退出，
按变更影响在隔离环境验证新规则和场景。选中的检查若因依赖缺失而跳过，记录为未完成。
宿主 CI 禁用监听资源测试的 IPv6 通配启动对照和 OpenVPN 系统 TUN 探针。需要这些证据时，
在获准的隔离运行态环境单独执行。
候选测试在一次性 runner 内执行，要求事先审查及授权，
该运行不用于验证不可信候选或充当 PR 必需检查。回读获准的 head、base、
`command-contract` 终态与宿主结论。手动运行关联加载工作流的 main 提交，候选 SHA 以报告为准。
在 main 以自身为基线只运行固定契约。较重验证仅按风险和候选证据缺口执行一次；同一组有效输入可复用结果。

选测声明的基线始终与实际比较基线一致，且声明覆盖完整差异。若 rebase 改变了集成基线，
旧声明不会自动沿用。集成验收可在隔离环境用 `dev/verification/run.sh --base` 和
明确的 `--test` 或 `--scenario` 参数覆盖实际集成差异，避免把其他 PR 纳入同一轮。

未知影响仍须在分支内更新 `.github/verification-scope.txt`：首行为
`base <merge-base SHA>`，后续每行一个 `--test tests/<name>.sh` 或 `--scenario <name>`。
可用 `git merge-base origin/main HEAD` 取得基线。不接受过期范围、helper、容器专用
fixture、越界路径或任意命令。固定契约列表不能代替影响判断；选择的 Docker 仍是
独立验收，宿主 CI 用 `required_not_run` 标识。计划和摘要记录 host gate、head/tree、基线、工具版本及逐项结果。
本地可直接执行
`bash dev/verification/ci.sh origin/main`，不会调用 GitHub Actions。本地运行应独占 worktree。
选到需要 UID 0 的存储、安全或系统 fixture 时，使用具备 root 权限的隔离环境。
选到读取真实核心的宿主测试时，先配置 `SINGBOX_BINARY_114`。双版本兼容性测试还须配置
`SINGBOX_BINARY_113`，使结果可以绑定实际核心字节。
选中路由配置或实例基线测试时，使用该 1.14 核心检查生成配置并执行适用的私有路由探针。
既有路由核心变量可以指定同一个 1.14 核心，冲突的配置会拒绝执行。
报告记录托管运行的受保护驱动 SHA。选测或执行期间检测到提交或工作区字节变化，或逐项结果与计划不符时，本轮宿主门禁失败。
工作区的已跟踪和未忽略输入不接受符号链接，避免遗漏链接目标字节。
可复用的证据限于干净 worktree、相同的工作区摘要和等价工具链。

## 候选、发布与交接

- DEV 用本地 mock/一次性 Docker。正式 PRE 是必要检查及审查收敛后的稳定候选，用相关隔离场景或已授权的 `sing-box-test`。PRO 指明确授权的 `sing-box-prod` 等实际生产目标。共享 PRE 一次只验收一个候选，记录验收前后版本、候选 head/tree、核心及构建输入、产物摘要、脱敏环境、部署标识及实际行为。按风险执行 PRE，普通文档、推送或更新 PR 不触发部署。
- 合并就绪须满足验收、适用检查/审查、阻塞处理、延期记录和所需候选/恢复证据。合并前核对 head 和当前基线。基线、运行时、测试、构建输入或目标环境变化时，按受影响范围使证据失效。rebase 后核对实际集成 tree，按输入等价性复用候选证据。集成有实质差异时先定点复验，必要时重新验收候选，然后才可发布。
- 单独核对发布授权、目标、集成版本、产物及回滚点。迁移与破坏性操作使用各自授权和数据恢复方案。生产变更后核对实际版本、就绪和受影响行为，失败按恢复方案处置并报告。分别记录实现完成、合并就绪、已合并、发布就绪、已部署和生产验证状态，标明不适用或阻塞项。

使用隔离数据与模拟对端。仓库工作流变更以适用的宿主验证、失败 fixture 和触发器检查进行隔离验收。VPS 操作读取本地 `skills/sing-box-vps-operator/SKILL.md` 的目标分类、生产授权及运行手册。

合并前检查默认分支是否推进。若基线增加了影响本次验证或审查的变化，先取得集成
候选并复验影响范围。rebase 可能只改 SHA；若旧基线仍是候选祖先且默认分支未推进，
用 `git diff --exit-code <候选head> <合并SHA>` 核对 tree。若默认分支已有独立改动，
核对实际集成差异及依赖后再确认仍适用的证据。核心、构建输入、受测代码、验证环境
变化使相应证据失效。仅文档变化且可证明运行和构建输入等价时复用原候选。

从已核验的集成 revision 取用可验证产物，按目标与配置证明候选和发布产物等价。退出前以 Git、检查和环境状态核对交接，清理已用完的任务临时文件。权限或证据不足时记录阻塞。

使用 PR 时间线和本地结果表记录总耗时、PR 开合时间、检查时长、复审轮次、PRE 部署
次数、上下文恢复，以及适用的生产失败/恢复时间。以同范围的历史记录对照。授权关闭的
Actions 和未发生的部署分开记，避免计为耗时优化收益。

## AI Native 命令与手册同步

每个新增或调整的运行时操作同时维护对应非交互命令、嵌入式 operation descriptor、定向测试、命令说明、受影响的 Agent 操作手册与导航。菜单和 CLI 调用相同的业务函数；规范命令 `sbv <resource> <verb> ... --json` 与兼容的 `sbv agent ...` 共享 dispatcher、锁和事务。新增菜单能力默认提供结构化入口。有提示、缺少输入或未知命令不得降级至交互菜单；结构化 stdout 仅输出一个 JSON 对象，进度写 stderr。

`sbv commands --json` 输出版本化目录；`sbv schema <operation-id> --json` 返回单项参数及安全边界。每项操作声明稳定 ID、命令及参数、结构化/仅交互状态、变更/敏感分类、确认条件、并发/CAS、输入契约、服务影响和文档位置。普通 `features.*` 与 `sbv agent capabilities --json` 描述产品能力，不能证明自动化或运行态验收。确需保留仅交互时，在 SPEC 说明缺失的验证、事务或恢复边界，登记 `automation=interactive_only`、原因和菜单入口，经审查确认。禁止用自动输入提示答案冒充非交互能力。

调整嵌入式操作目录或相关实现后，依次生成和检查。

```bash
bash scripts/build-install.sh
bash scripts/build-command-docs.sh
bash scripts/build-install.sh --check
bash scripts/build-command-docs.sh --check
bash tests/command_catalog_contract.sh
bash tests/agent_docs_cover_capabilities.sh
bash tests/wiki_documentation.sh
```

[命令操作目录](https://github.com/KnowSky404/sing-box-vps/wiki/Command-Catalog) 由运行时嵌入式目录生成，不手工编辑。Agent-CLI 维护使用规则，Agent-Runbook 维护操作和恢复流程，`docs/agents/llms.txt` 与 operator skill 维护读取导航；按实际影响调整相关文档，不能用生成参考替代手写事务说明。具体契约见本地 `docs/specs/ai-native-operations.md`（[AI Native SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/ai-native-operations.md)）和 [Agent 命令](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-CLI#操作目录)。

`docs` 验证组包含命令契约和文档同步检查。托管宿主入口及证据边界见 [Actions 授权与定点验证](#github-actions-授权与定点验证)。

## 模块化源码与单文件构建

安装器维护源码位于 [`src/install/`](https://github.com/KnowSky404/sing-box-vps/blob/main/src/install/README.md)，当前分为 46 个 Bash 源码片段，首次拆分时每个片段少于 2,000 行。`manifest.txt` 明确规定拼接顺序；片段包含完整函数和 Shell 结构，但不独立运行。操作目录与 Agent 分流模块在 launcher 前拼接，函数仍可引用后续模块的 helper。

根目录 `install.sh` 是生成后提交的独立运行产物。Bootstrap、自更新、全局 `sbv`、测试及 Docker 继续使用此文件；用户无需下载模块或安装额外构建依赖。不要直接编辑生成文件，也不要改成运行时下载或 `source` 远程模块。

```bash
# 修改对应 src/install 模块后，在仓库根目录生成单文件产物
bash scripts/build-install.sh

# 只读检查：源码与提交的 install.sh 必须完全一致
bash scripts/build-install.sh --check

# 仅构建器或清单变化时：构建失败保护、清单校验及发布行为回归
bash tests/install_build.sh

# 确认本次分支影响及必要行为验证范围
bash dev/verification/run.sh --plan --base origin/main
```

版本在 `src/install/00-preamble.sh` 的文件头和 `SCRIPT_VERSION` 中更新，与根 README 同步；构建脚本原样复制到 `install.sh`。版本格式为 `YYYYMMDDXX`，XX 为当日迭代序号。每个实际交付仓库文件变更的对话轮次递增一次，包括只改文档、规约、测试或配置；同轮拆分多个提交也只递增一次，后续提交沿用。只检查、审查或讨论且无文件变更时不递增。提交时包含模块和生成产物；新增或拆分片段时同时更新清单。构建检查会拒绝缺失、重复、遗漏或越界的模块路径及符号链接，不执行源码或清单中的内容。完整语法检查通过后才同目录原子替换产物，失败保持原文件，相同产物不重复写入；`--check` 不写工作区。

验证调度器在根安装器或源码模块变化时选择生成同步检查，构建器/清单变化才追加构建器隔离回归。源码改变但遗漏重新生成会失败；生成文件存在实际运行逻辑差异时，仍需按[风险与验证范围](#风险与验证范围)明确选择受影响测试和必要 Docker 场景，不因拆分源码自动全量。首次纯拆分以归一化版本后的字节等价确认运行代码未变，再验证构建、入口、自更新、菜单、文档和调度兼容性；这不代表新取得协议、公网或生产验收。

## REALITY 地区候选的开发门槛

地区文案统一为“国家或地区-城市”（例如 `美国-洛杉矶`、`韩国-首尔`），地区 ID 和菜单编号保持稳定。候选池每区最多 5 个，不要求为类别或数量补入不合格域名。修改 `SB_REALITY_REGION_CANDIDATES` 或 checker 固定版本后，必须从开发网络实际运行固定版本 checker；机构官网来源或菜单 mock 不能代替公网 TLS 证据。

准备 Bash >= 4.3、curl、OpenSSL、dig、jq 和 GNU coreutils；此开发工具无需 root，不安装依赖、不操作 sing-box 服务或配置。输出目录必须尚不存在；脚本验证 checker 的固定 commit、SHA-256 和语法后，逐域名执行与安装路径相同的 `check <domain> --json --timeout 3`，每域名总时限 90 秒，检查完整 DNS A/AAAA 集合。全部端点的 TCP 443、TLS 1.3、证书链/SAN/有效期、h2、X25519 必须 PASS，任何基础 FAIL/UNKNOWN、不完整报告或超时均使脚本非零退出。

```bash
candidate_report_dir="/tmp/sbv-reality-candidates-$(date -u +%Y%m%dT%H%M%SZ)-$$"
bash scripts/check-reality-region-candidates.sh "$candidate_report_dir" &&
  cp "$candidate_report_dir/summary.json" docs/verification/reality-region-candidates.json &&
  bash tests/reality_region_candidate_evidence.sh
bash tests/reality_region_candidate_evidence_contract.sh
bash tests/reality_region_candidates.sh
```

`summary.json` 保留逐域名观测时间、完整原报告 SHA-256、checker 身份、端点检查和附加风险的投影；原始 JSON/stderr 留在输出目录。仓库中的[证据快照](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/verification/reality-region-candidates.json)只证明记录时间的开发网络观测，没有未来可用性承诺。`WARN` 表示基础 TLS/兼容性已通过但仍有附加风险或未知项，必须保留，不得改写成总状态 PASS；收录不表示用户接受风险，安装时仍重新检测且默认拒绝附加风险。

CI 使用离线证据检查，核对候选身份和 checker 固定版本，并复用安装器的报告校验函数；新增、替换或变更 checker 后缺少相符证据会失败。这里不自动发起公网检查，也不将已提交快照作为安装许可。2026-11-05 的 23 个候选均通过基础门槛、总状态均为 WARN；首尔原 KB国民银行、新韩银行未取得充分握手证据，首尔市政府、延世大学未协商 h2，均已移出当前列表。真实 REALITY 握手和生产验收仍是独立边界。

## 文档维护与 Wiki 发布

`docs/wiki/*.md` 是 Wiki 的维护源。README 只保留项目简介、版本、主要能力、文档导航和许可证；安装命令、操作步骤、协议契约及验证边界写入对应 Wiki 页面。`AGENTS.md` 提供强制读取路由和基础门禁，本页维护开发交付细则，Operator Skill 维护 VPS 操作约束，`docs/agents/llms.txt` 提供导航。历史计划、设计稿和提示词流水可通过 Git 历史查询，不再作为当前操作手册维护。

新增、移除或重命名页面时，同步 `Home.md`、`_Sidebar.md` 和受影响链接；仅修改已有页面内容时只更新受影响的导航。Wiki 页面之间使用完整 Wiki URL，仓库源码链接使用 GitHub `blob/main` URL，便于在两处阅读。文档基础检查在仓库根目录执行：

```bash
bash tests/wiki_documentation.sh
```

其余检查按实际变化追加，不把下表当作每次发布的固定集合：

| 实际变化 | 追加检查 |
| --- | --- |
| 同步脚本版本或版本展示 | `bash -n install.sh`、`bash tests/readme_mentions_current_versions.sh`、`bash tests/version_metadata_is_consistent.sh` |
| Agent 命令或能力说明 | `bash tests/agent_docs_cover_capabilities.sh` |
| 可执行安装命令或 Bootstrap 下载/校验逻辑 | `bash tests/bootstrap_download.sh` |
| 协议能力矩阵或协议契约说明 | `bash tests/protocol_coverage_contract.sh` |
| 其他可执行行为 | 按[风险与验证范围](#风险与验证范围)选择相关测试、配置检查及必要运行态场景 |

普通文档与版本同步执行差异、链接、版本和语法检查。若改变验证、授权或安全交付门禁，仍按实际风险追加所需的独立审查及隔离验收。以上检查不代表重新取得服务或公网验收；使用开发验证工具前确认所需脚本及依赖实际存在，缺失时不能报告对应场景通过。

主仓库 PR 按上文完成审查并合并后，从已合并的 `main` 发布 Wiki。示例在仓库根目录运行：

```bash
wiki_checkout=$(mktemp -d /tmp/sing-box-vps-wiki.XXXXXXXX)
git clone https://github.com/KnowSky404/sing-box-vps.wiki.git "$wiki_checkout"
cp docs/wiki/*.md "$wiki_checkout/"
git -C "$wiki_checkout" diff --check
git -C "$wiki_checkout" diff --stat
```

检查完整差异后，在 Wiki checkout 中仅暂存本次管理的页面，用 Conventional Commits 提交；同样先完成对应 Wiki 提交的本地 `/review` 并解决问题，再正常推送，无入口时记录等效本地审查。保留额外页面，不要强推；移除或重命名页面时需明确处理旧页面和链接，不能只复制新文件。无差异时不创建空提交。另行 fresh clone，逐文件比较已发布页面和 `docs/wiki/` 的内容，并回读首页及关键页面。主仓库合并和 Wiki 发布是两个独立结果，分别记录提交号。

## 云端安全审查上下文

根目录 [SECURITY.md](https://github.com/KnowSky404/sing-box-vps/blob/main/SECURITY.md) 维护英文安全审查指南，供本地和云端 Codex 读取；`AGENTS.md`、Operator Skill 和 Agent 索引均指向它。指南涵盖 root 安装器的信任模型、输入到命令/文件的边界、下载与原子替换、凭据、CAS/锁、网络资源归属、SubMan 写入对账和发现报告要求。

实际自动触发的审查与合并条件见[审查与合并](#审查与合并)。本地和云端审查均按当前 checkout 的 `SECURITY.md` 核对审查范围、证据及授权边界。
