# 开发工作流

本流程适用于所有功能迭代和 Bug 修复。项目规约以 [AGENTS.md](https://github.com/KnowSky404/sing-box-vps/blob/main/AGENTS.md) 为准；纯文档等其他改动也可使用相同流程。

1. **准备**：检查当前工作区、已有 worktree 和分支，保留其他工作。获取远程默认分支的最新状态，从该基线为本次任务创建独立分支和 worktree；不要在默认分支直接开发或推送。
2. **实现与验证**：在任务 worktree 中完成修改，按 [AGENTS.md](https://github.com/KnowSky404/sing-box-vps/blob/main/AGENTS.md) 第 4.2 节的测试边界，根据实际行为影响选择最小充分验证集合，先说明选择依据。普通文档、版本展示和菜单文案不因位于安装器内就触发大范围回归；配置变化必须对受影响配置执行 `sing-box check`，服务、网络和生命周期变化必须覆盖对应真实运行态。仅在核心版本或格式迁移、共享逻辑广泛影响或范围无法可靠界定、明确要求全量或完整发布验收时执行全量。记录实际命令、通过、失败、未执行项及原因；符合复用条件的既有结果可复用。
3. **提交与本地审查**：只提交本次任务相关内容，使用原子的 Conventional Commits。每次原子提交后立即在本地运行 `/review`，记录审查范围、提交 SHA、结果和问题处理情况；如果当前环境没有该入口，审查对应提交的实际差异并记录这是等效本地审查。发现问题时，先修复、完成受影响验证并重新提交，再次本地审查，直到没有未解决问题。脚本版本和 README 版本按项目规约同步。
4. **推送、创建 PR 与远程审查**：每次推送（包括首次推送和修复后的追加推送）或创建 PR 前，必须先通过本地 `/review` 门禁：覆盖本次待推送的全部提交和任务分支相对基线的完整差异，结果对应当前 HEAD，且没有未解决问题。审查未完成或失败时不得推送或创建 PR；审查后产生新提交或差异变化时，先重新本地审查。推送与随后创建 PR 之间若 HEAD 和差异未变，可复用同一次已完成的本地审查；无 `/review` 入口时按上一步完成等效本地审查。门禁通过后，推送任务分支，创建面向默认分支的 PR，说明变更、验证结果和本地审查证据。只读核对当前 PR head 的必要检查、自动审查记录和未解决意见。远程只保留仓库自动触发的 GPT/Codex Security Review，不手动评论召唤 Code Review 或 Security Review，不通过切换草稿/可审查状态、空提交等方式人为重触发。已自动触发的当前 head Security Review 必须完成且没有未解决问题；排队、运行中、失败、取消或查询失败不能归类为未触发。远程 Code Review 不主动触发、不作为等待条件，已报告的问题仍须核实并处理。明确没有自动触发任何机器人审查时记录 `not_triggered`，本地审查、必要验证及 GitHub 必需检查通过后直接 rebase 合并；只有自动 Code Review 而无自动 Security Review 时，也不增加远程等待门禁。未触发不是安全审查通过，不能将旧 head 的报告冒充当前 head 证据。
5. **更新与合并**：解决必要的审查意见和检查失败；如果产生新提交，重新验证受影响内容，先通过本地审查门禁再推送，随后核对最新 head 的必要检查及自动审查状态。只等待实际自动触发的当前 head Security Review；没有自动触发机器人时按上一步直接合并，不补发手动审查请求。门禁满足后直接使用 GitHub 的 rebase 合并，无需再次请求合并确认。若默认分支变化造成冲突或要求更新，先安全解决，再重新验证和确认相应门禁。
6. **核对与清理**：确认 PR 已合并且远程默认分支包含合并结果，核实远程任务分支已自动删除；若未删除则删除它。检查任务 worktree 的未提交、未跟踪和需要保留的产物；确认安全后移除 worktree 和本地任务分支。不要删除其他工作区或用户数据，清理失败时报告剩余内容。

本地提交审查、PR 机器人审查、测试和实际部署是不同的证据；其中某项未执行或未完成时，不能用其他项代替。若权限、检查或审查阻塞合并，保留 PR 和工作区并说明阻塞原因。

验证入口支持计划预览、分支基线差异、本地测试组和显式 Docker 场景。选测仍以第 4.2 节的实际行为影响为准；自动映射无法判定的运行时改动必须先明确范围。提交后的任务使用 `--base` 并核对完整分支差异。失败后只重跑失败项和受修复影响的范围。

### CI 定点验证范围

`command-contract` 保留原契约门禁，并通过 `dev/verification/ci.sh BASE` 复用完整差异计划器，追加本次变更的宿主测试。CI 检出 PR head，并保留完整 Git 历史；计划、逐项日志和耗时上传为 `scoped-host-verification`。

未知影响需要本分支修改 `.github/verification-scope.txt`。第一行是 `base <merge-base SHA>`，后续每行只接受一个 `--test tests/<name>.sh` 或 `--scenario <name>`；SHA 可用 `git merge-base origin/main HEAD` 获取。旧任务未修改的范围、过期基线、helper/容器 fixture、越界路径和任意命令均不能作为有效宿主范围。自动检查继续追加；固定契约列表不能代替作者的影响判断。

在仓库根目录以具备 fixture 所需 root 权限的环境执行 `bash dev/verification/ci.sh origin/main` 可复现同一入口。CI 强制执行宿主检查，不接受继承的 `VERIFY_SKIP_LOCAL_TESTS` 跳过；明确记录选中的 Docker 未执行；运行态仍须另行执行对应场景并记录证据。`lifecycle_safety` 使用全新 SOCKS 基线，覆盖菜单/CLI 服务保护、真实停服和受管防火墙卸载，恢复安装后执行最终 smoke；原默认 17 场景集合不变。dispatcher 改动自动选分派测试并保留 `needs_scope`，其他探针/产物影响按实际追加。

### 小改动的执行与停止条件

测试范围以 `AGENTS.md` 第 4.2 节为单一规则源。开始前简短说明“行为变化 → 必要检查/场景与前置依赖 → 不执行范围及理由 → 预计耗时”。文档和版本变更以数分钟内完成为目标；本地测试预计超过 10 分钟、Docker 预计超过 20 分钟时先说明慢项和必要性。这些是调整计划的软预算，必要验证未完成仍需明确报告。

调度器比较完整安装器内容，仅 `# Version` 和 `SCRIPT_VERSION` 元数据变化时只选择本地版本与语法检查。其他运行时影响不能仅凭文件名猜测；先用 `--plan`，再明确必要的本地组和 Docker 场景。也可直接运行相关 `bash tests/<测试>.sh`。`VERIFY_SKIP_REMOTE=1` 是选中的本地测试执行后才跳过 Docker，不是轻量模式。单个协议不自动要求所有协议、共存或升级场景。

选定检查通过、完整差异已核对且无新增风险证据后，停止测试并进入提交/审查；同一 HEAD 的一次本地审查可以同时记录原子提交和分支完整差异，无需重复启动。提交号变化、仅追加文档或进入 PR 审查，不使未改变的受测内容自动失效。慢项先定位，不盲目重启全套。安全审查等待单独记录；待审时保留 PR 并报告，不反复跑测试，也不绕过合并门禁。


### 调度器命令与计划

Docker 定点场景已覆盖完整拆分路线图：原 HTTP 出站、规则集、Tor 三个叶子，新增 SSH/SOCKS/Selector/URLTest/Shadowsocks/Direct/Block/VLESS/ShadowTLS/SOCKS UDP 出站、Direct/Redirect/TProxy/透明策略，以及 13 个单协议探针、Naive/Snell 转换和纯协议共存。精确 ID、保留断言与分阶段证据见 [Docker 定点验证 SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/scoped-docker-verification.zh-CN.md)（[English](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/scoped-docker-verification.md)）。第二阶段 31 个新增叶子及重构 HTTP 共 32 个独立场景和聚合兼容均通过真实 Docker，SPEC 运行态验收为 33/33；逐项记录运行 ID 和耗时，计入场景内部安装，仅排除独立调度基线、最终 smoke 和传输，不声明原 17 场景全量通过。

```bash
# 单个出站：本地 upstream/marker 和创建/删除
bash dev/verification/run.sh --plan --base origin/main --scenario component_vless_outbound

# 单协议的真实 TCP/UDP，不安装其他十二个协议
bash dev/verification/run.sh --plan --base origin/main --scenario protocol_probe_hy2

# namespace / managed replace / policy route 清理
bash dev/verification/run.sh --plan --base origin/main --scenario component_tproxy_inbound

# 独立模式转换，不必选择完整协议共存
bash dev/verification/run.sh --plan --base origin/main --scenario protocol_naive_transition

# 显式外网边界，不作为普通组件或协议验证的隐式依赖
bash dev/verification/run.sh --plan --base origin/main --scenario protocol_probe_vless_reality
bash dev/verification/run.sh --plan --base origin/main --scenario component_tor_outbound
```

每个叶子前都重建 `fresh_install_socks`，组合请求也保留每次重置；协议叶子额外只安装目标协议，SOCKS 探针使用基线实例。最终只追加一次 `runtime_smoke`，探测最后安装状态。删除最后组件留下的空 store 仍有单调增加的 revision，不能将 HTTP 删除后的 revision 2 或规则集删除后的 revision 7 当成新的 revision 0。可选场景目录与默认全量清单分开；`--full` 保持原 17 场景，通过 aggregate 的共享断言覆盖协议/组件，不重复执行新叶子。

共享 fixture/断言、aggregate、dispatcher，以及外部 REALITY/Tor 场景变化保持 `needs_scope`，操作者按实际影响明确分配本地 `--test`/`--group` 与必要的 `--scenario`，或确实必要的 `--full`；不能仅因路径变化隐式启动全部调用方、完整共存或真实外网。普通本地叶子可映射对应场景和前置。REALITY 探针与 `protocol_coexistence` 使用外部 TLS cover，Tor 使用真实公网 circuit；mock、监听或本地 marker 均不能代替外网证据。HTTP/ShadowTLS 协议探针只声明 TCP，其他协议分别保留原生 UDP、XUDP 或 UoT 边界。

本次完整拆分验收需要每个新增叶子和 `multi_protocol_coexistence` 兼容路径的真实 Docker 结果，保留原 CAS 链及跨协议/组件断言；不因此重跑升级、卸载等无关原 17 场景。本轮 aggregate 实测 6164 秒，包含其内部 13 协议安装；随后 final smoke 50 秒通过。第一阶段三叶子约 601 秒保留为历史记录，不能将不同范围的单叶子、聚合和原 17 场景全量当作性能对照。

优先选择精确的 `--test tests/<名称>.sh`，需要整组覆盖时才使用 `--group`。单测试参数可重复，去重后执行；只接受已有独立宿主 Shell 测试的精确路径，拒绝 helper、容器专用 fixture、符号链接及越界路径，不展开通配符。它与 `--base` 组合时保留所有分支/工作区差异的自动检查，不能用来排除其他改动。显式测试和显式组一样代表操作者的影响判断，不能把一个任意测试当作完整覆盖；运行态变化仍需对应 Docker 场景。

普通文档只自动选择 `wiki_documentation.sh`，Agent 手册及升级手册追加能力说明检查，嵌入式/生成命令目录追加命令契约；显式 `--group docs` 仍保留整组。安装器/模块的日常修改选择 `install_build_sync.sh` 检查生成字节及语法，构建器/清单变化才追加 `install_build.sh` 的故障注入。计划器和选择器变化只自动选择 `verification_planner.sh`、`verification_trigger_rules.sh`、`verification_scenario_mapping.sh`；执行器/传输变化仍按相应范围验证。

2026-11-04 优化前清单审视：342 个 Shell 文件中，注册全量选择 199 项宿主测试及 17 种 Docker 场景；`menu` 有 28 项，`protocol:vless` 有 35 项，`protocol:hy2` 有 29 项。它们包含同协议下不同功能及一些跨模块文件名匹配，不是修改一处菜单/分享文案的默认单位。`multi_protocol_coexistence` 超过 3,500 行，混合多协议、组件、UDP、透明代理及真实 Tor 网络访问；`fresh_install_http` 也包含删除最后实例、取消和重建。只有大型场景能覆盖时，明确额外覆盖和预计耗时，不把它默认为轻量 smoke。这些原有成本是本次完整拆分的设计基线；共享断言、必要前置与数据面边界均继续保留。原两小时任务的耗时日志不可用，不能声称已复现该任务；SPEC 中的定向实测也不是与旧全量的对照基准。

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

`--base` 比较 `merge-base(ref, HEAD)` 到当前工作区，保留分支已提交改动以及暂存、未暂存、未跟踪文件；不会把仅上游新增的改动算作任务差异。默认不带 `--base` 时只看相对 HEAD 的工作区差异。`--changed-file <路径>...` 是工具显式输入，可重复，与 `--base` 互斥，不代表已经覆盖完整分支。

自动映射涵盖文档、版本元数据、Bootstrap、修改的独立宿主测试、以文件名静态引用的 helper 调用方，以及验证框架的相关测试。新增独立测试不会被漏掉；helper 自身不作为用例执行。动态构造的依赖、共享配置/系统操作及未映射的运行时逻辑需要人工影响判定。显式组/场景表示操作者做出了该判断，并不证明选择一定充分。

计划输出 `base`、`file`、`group`、`syntax`、`test`、`scenario` 和选择理由/未映射影响。`plan_status=needs_scope` 时预览仍成功，实际执行返回 2，且不运行任何测试或 Docker；错误参数、无效 ref 或未知组/场景同样在执行前返回 2。`--plan` 不运行测试、不探测 Docker、不创建结果目录。执行后保存 `dev/verification-runs/<时间>/plan.txt`、逐测试日志/耗时以及场景产物，首个失败立即返回，不自动重复全套。

场景根据本次运行已建立的状态补齐前置：独立 `runtime_smoke` 使用较轻的 `fresh_install_http`；VLESS 重配置需要 `fresh_install_vless` 基线；卸载验证先建立可核对旧 UUID 的 VLESS 安装；最终 smoke 在所有变更场景之后。若中途其他场景替换了安装，会重新准备必要基线，计划可能包含重复安装。定点叶子已覆盖各出站、宿主策略、单协议及模式转换；纯协议共存与原完整 aggregate 仍供确有组合影响时显式选择。需确认计划中的额外覆盖，不能仅凭名称推断耗时很短。

`--full` 运行的是 `selection.sh` 中的显式宿主安全清单和默认全量场景清单，不等同于执行 `tests/` 下所有脚本，也不自动证明公网或外部服务行为。独立 `hy2_instance_acme_runtime.sh` 是 Pebble/私有 CA 容器 fixture，现有注册场景不调用它；直接修改它或静态引用它的 helper 时，调度器保持 `needs_scope`，即使 `--full` 也不能代替其独立隔离运行。保留该未完成边界并按专属容器流程验证，不要在宿主执行它。

同样的宿主保护适用于 `routing_policy_runtime.sh`、`routing_policy_legacy_runtime.sh`、`routing_policy_manual_references_runtime.sh`、`component_runtime_acceptance.sh`、`selector_urltest_runtime.sh`、`acme_component_runtime.sh`、`namespace_core_runtime.sh`、`tailscale_openconnect_runtime.sh` 和 `cloudflared_runtime.sh`。它们要求新的可丢弃 Docker、显式标志及各自对端；生产 Cloudflared 还需要事先授权的专用临时资源和私密凭据文件。脚本或其 helper 发生变化时，计划保留独立隔离运行要求，普通组及 `--full` 均不能把它们当作宿主测试。具体范围、证据和条件见 [协议完成契约](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/full-protocol-completion.zh-CN.md)。

`bash tests/integration_subman_app.sh` 使用 `SUBMAN_SOURCE_DIR` 指定的 SubMan 已提交源码及其锁定依赖，在 `/tmp` 构建隔离 Worker/SQLite 联调，GitHub 对端保持隔离。`integration_subman_production.mjs` 不由普通测试入口执行；必须明确授权目标、私密凭据文件和生产验收标志，只创建、修改和清理本轮独有测试节点/聚合，使用条件写入并核对原业务与发布文件。凭据与完整分享材料不进入公开证据。

GitHub 对 `main` 启用 PR、线性历史和已解决审查对话保护，并对管理员生效，禁止强推和删除。仓库仅允许 rebase 合并，并自动删除已合并的远程分支。GPT/Codex 的审查结果写入 PR 评论，而非 GitHub 必需状态检查；执行者核对本地审查、必要检查，以及实际自动触发的当前 head Security Review。没有自动触发机器人时记录 `not_triggered` 并按上述直接合并分支处理，不手动补触发。

## AI Native 命令与手册同步

每个新增或调整的功能同时维护对应非交互命令、嵌入式 operation descriptor、定向测试、命令说明和受影响的 Agent 操作手册。菜单和 CLI 调用相同的业务函数与事务；新增菜单能力默认提供结构化入口。遗留的仅交互操作登记 `automation=interactive_only`、限制原因和入口，新增例外必须在 SPEC 中解释并接受审查。规范命令是 `sbv <resource> <verb> ... --json`，既有 `sbv agent ...` 保留兼容。

`sbv commands --json` 输出版本化目录；`sbv schema <operation-id> --json` 输出参数、确认、并发/CAS、输入契约、服务影响、敏感分类和文档位置。修改描述和实现后，按以下顺序更新和检查：

```bash
bash scripts/build-install.sh
bash scripts/build-command-docs.sh
bash scripts/build-install.sh --check
bash scripts/build-command-docs.sh --check
bash tests/command_catalog_contract.sh
bash tests/agent_docs_cover_capabilities.sh
bash tests/wiki_documentation.sh
```

[命令操作目录](https://github.com/KnowSky404/sing-box-vps/wiki/Command-Catalog) 由运行时嵌入式目录生成，不手工编辑。Agent-CLI 维护使用规则，Agent-Runbook 维护操作和恢复流程，`docs/agents/llms.txt` 与 operator skill 维护读取导航；按实际影响调整相关文档，不能用生成参考替代手写事务说明。具体契约见 [AI Native SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/ai-native-operations.md)。

`docs` 验证组包含命令契约和文档同步检查；GitHub 的 `Command contract` 工作流运行构建一致性、命令目录、文档和版本检查。该轻量门禁不执行全协议或生产验证，也不替代行为变化所需的运行态验证、当前 HEAD 本地审查和实际自动触发的远程安全审查。

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

版本在 `src/install/00-preamble.sh` 的文件头和 `SCRIPT_VERSION` 中更新，与根 README 同步；构建脚本原样复制到 `install.sh`。同一轮交付仍只递增一次。提交时包含模块和生成产物；新增或拆分片段时同时更新清单。构建检查会拒绝缺失、重复、遗漏或越界的模块路径及符号链接，不执行源码或清单中的内容。完整语法检查通过后才同目录原子替换产物，失败保持原文件，相同产物不重复写入；`--check` 不写工作区。

验证调度器在根安装器或源码模块变化时选择生成同步检查，构建器/清单变化才追加构建器隔离回归。源码改变但遗漏重新生成会失败；生成文件存在实际运行逻辑差异时，仍需按第 4.2 节明确选择受影响测试和必要 Docker 场景，不因拆分源码自动全量。首次纯拆分以归一化版本后的字节等价确认运行代码未变，再验证构建、入口、自更新、菜单、文档和调度兼容性；这不代表新取得协议、公网或生产验收。

## REALITY 地区候选的开发门槛

地区文案统一为“国家或地区-城市”（例如 `美国-洛杉矶`、`韩国-首尔`），地区 ID 和菜单编号保持稳定。候选池每区最多 5 个，不要求为类别或数量补入不合格域名。修改 `SB_REALITY_REGION_CANDIDATES` 后，必须从开发网络实际运行固定版本 checker；机构官网来源或菜单 mock 不能代替公网 TLS 证据。

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

`docs/wiki/*.md` 是 Wiki 的维护源。README 只保留项目简介、版本、主要能力、文档导航和许可证；安装命令、操作步骤、协议契约及验证边界写入对应 Wiki 页面。`AGENTS.md` 和 Operator Skill 保留自动化约束，`docs/agents/llms.txt` 只提供索引。历史计划、设计稿和提示词流水可通过 Git 历史查询，不再作为当前操作手册维护。

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
| 其他可执行行为 | 按第 4.2 节选择相关测试、配置检查及必要运行态场景 |

例如，只调整约束文件、审查指南和 Wiki 文案并同步版本时，执行差异、链接、版本和语法检查即可，不需要 Bootstrap、协议契约或 Docker。以上检查不代表重新取得服务或公网验收；使用开发验证工具前确认所需脚本及依赖实际存在，缺失时不能报告对应场景通过。

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

云端安全审查任务应明确要求：“先读 `AGENTS.md` 与 `SECURITY.md`，审查指定 base 到当前 head 的完整差异及必要调用上下文；按指南报告可达且有证据的安全问题，并注明 head SHA。默认静态分析，确有必要时才做最小隔离复现。”只使用仓库自动触发的 Security Review，不据此手动召唤机器人。新增指南不代表已配置云端任务或完成审计；生产、真实外部服务和敏感凭据不属于普通 PR 安全审查的授权范围。
