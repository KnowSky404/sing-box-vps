# 开发工作流

本流程适用于所有功能迭代和 Bug 修复。项目规约以 [AGENTS.md](https://github.com/KnowSky404/sing-box-vps/blob/main/AGENTS.md) 为准；纯文档等其他改动也可使用相同流程。

1. **准备**：检查当前工作区、已有 worktree 和分支，保留其他工作。获取远程默认分支的最新状态，从该基线为本次任务创建独立分支和 worktree；不要在默认分支直接开发或推送。
2. **实现与验证**：在任务 worktree 中完成修改，按 [AGENTS.md](https://github.com/KnowSky404/sing-box-vps/blob/main/AGENTS.md) 第 4.2 节的测试边界，根据实际行为影响选择最小充分验证集合，先说明选择依据。普通文档、版本展示和菜单文案不因位于安装器内就触发大范围回归；配置变化必须对受影响配置执行 `sing-box check`，服务、网络和生命周期变化必须覆盖对应真实运行态。仅在核心版本或格式迁移、共享逻辑广泛影响或范围无法可靠界定、明确要求全量或完整发布验收时执行全量。记录实际命令、通过、失败、未执行项及原因；符合复用条件的既有结果可复用。
3. **提交与本地审查**：只提交本次任务相关内容，使用原子的 Conventional Commits。每次原子提交后立即在本地运行 `/review`，记录审查范围、提交 SHA、结果和问题处理情况；如果当前环境没有该入口，审查对应提交的实际差异并记录这是等效本地审查。发现问题时，先修复、完成受影响验证并重新提交，再次本地审查，直到没有未解决问题。脚本版本和 README 版本按项目规约同步。
4. **推送、创建 PR 与远程审查**：每次推送（包括首次推送和修复后的追加推送）或创建 PR 前，必须先通过本地 `/review` 门禁：覆盖本次待推送的全部提交和任务分支相对基线的完整差异，结果对应当前 HEAD，且没有未解决问题。审查未完成或失败时不得推送或创建 PR；审查后产生新提交或差异变化时，先重新本地审查。推送与随后创建 PR 之间若 HEAD 和差异未变，可复用同一次已完成的本地审查；无 `/review` 入口时按上一步完成等效本地审查。门禁通过后，推送任务分支，创建面向默认分支的 PR，说明变更、验证结果和本地审查证据。检查当前 PR head 的检查、审查记录、审查线程和合并状态。等待 Codex 机器人针对当前 head 的安全审查完成并确认没有未解决问题；失败、取消或无法确认的安全审查需要排查并如实报告，不能视为通过。远程代码审查不作为合并前置门禁，无需等待其完成；已报告的问题仍须核实并处理。若安全审查未触发，排查并记录，不能把空的检查列表当作机器人已审查，也不能用远程审查代替推送前的本地审查。
5. **更新与合并**：解决必要的审查意见和检查失败；如果产生新提交，重新验证受影响内容，先通过本地审查门禁再推送，随后确认最新 PR head 的远程安全审查和检查已完成，必要时重新触发安全审查。门禁满足后直接使用 GitHub 的 rebase 合并，无需再次请求合并确认。若默认分支变化造成冲突或要求更新，先安全解决，再重新验证和确认审查。
6. **核对与清理**：确认 PR 已合并且远程默认分支包含合并结果，核实远程任务分支已自动删除；若未删除则删除它。检查任务 worktree 的未提交、未跟踪和需要保留的产物；确认安全后移除 worktree 和本地任务分支。不要删除其他工作区或用户数据，清理失败时报告剩余内容。

本地提交审查、PR 机器人审查、测试和实际部署是不同的证据；其中某项未执行或未完成时，不能用其他项代替。若权限、检查或审查阻塞合并，保留 PR 和工作区并说明阻塞原因。

验证入口支持计划预览、分支基线差异、本地测试组和显式 Docker 场景。选测仍以第 4.2 节的实际行为影响为准；自动映射无法判定的运行时改动必须先明确范围。提交后的任务使用 `--base` 并核对完整分支差异。失败后只重跑失败项和受修复影响的范围。

### 小改动的执行与停止条件

测试范围以 `AGENTS.md` 第 4.2 节为单一规则源。开始前简短说明“行为变化 → 必要检查/场景与前置依赖 → 不执行范围及理由 → 预计耗时”。文档和版本变更以数分钟内完成为目标；本地测试预计超过 10 分钟、Docker 预计超过 20 分钟时先说明慢项和必要性。这些是调整计划的软预算，必要验证未完成仍需明确报告。

调度器比较完整安装器内容，仅 `# Version` 和 `SCRIPT_VERSION` 元数据变化时只选择本地版本与语法检查。其他运行时影响不能仅凭文件名猜测；先用 `--plan`，再明确必要的本地组和 Docker 场景。也可直接运行相关 `bash tests/<测试>.sh`。`VERIFY_SKIP_REMOTE=1` 是选中的本地测试执行后才跳过 Docker，不是轻量模式。单个协议不自动要求所有协议、共存或升级场景。

选定检查通过、完整差异已核对且无新增风险证据后，停止测试并进入提交/审查；同一 HEAD 的一次本地审查可以同时记录原子提交和分支完整差异，无需重复启动。提交号变化、仅追加文档或进入 PR 审查，不使未改变的受测内容自动失效。慢项先定位，不盲目重启全套。安全审查等待单独记录；待审时保留 PR 并报告，不反复跑测试，也不绕过合并门禁。


### 调度器命令与计划

在仓库根目录运行。先预览，确认测试和场景满足本次影响，再去掉 `--plan` 执行同一组参数：

```bash
# 分支全部已提交改动 + 暂存/未暂存修改 + 未跟踪文件，只预览
bash dev/verification/run.sh --plan --base origin/main

# 菜单或自更新：明确本地回归组，按实际影响追加场景
bash dev/verification/run.sh --plan --base origin/main --group menu --group self-update

# 单协议本地检查；若改动影响运行态，再显式追加对应场景
bash dev/verification/run.sh --plan --base origin/main --group protocol:http --scenario fresh_install_http

# 调度器/传输变更：框架回归 + 轻量真实 Docker 安装与最终 smoke
bash dev/verification/run.sh --plan --base origin/main --group verification --scenario fresh_install_http

# 明确需要完整验收时才选已注册的全量集合
bash dev/verification/run.sh --plan --base origin/main --full
```

`--help` 列出支持的组和场景。组包括 `docs`、`version`、`bootstrap`、`menu`、`self-update`、`subman`、`verification` 和 `protocol:<协议>`。组只选择本地测试；服务、网络或生命周期变更仍需 `--scenario`。多个组/场景可重复指定，本地测试去重。`protocol:hy2` 与 `protocol:hysteria` 分别指 Hysteria2 和 Hysteria v1。

`--base` 比较 `merge-base(ref, HEAD)` 到当前工作区，保留分支已提交改动以及暂存、未暂存、未跟踪文件；不会把仅上游新增的改动算作任务差异。默认不带 `--base` 时只看相对 HEAD 的工作区差异。`--changed-file <路径>...` 是工具显式输入，可重复，与 `--base` 互斥，不代表已经覆盖完整分支。

自动映射涵盖文档、版本元数据、Bootstrap、修改的独立宿主测试、以文件名静态引用的 helper 调用方，以及验证框架的相关测试。新增独立测试不会被漏掉；helper 自身不作为用例执行。动态构造的依赖、共享配置/系统操作及未映射的运行时逻辑需要人工影响判定。显式组/场景表示操作者做出了该判断，并不证明选择一定充分。

计划输出 `base`、`file`、`group`、`syntax`、`test`、`scenario` 和选择理由/未映射影响。`plan_status=needs_scope` 时预览仍成功，实际执行返回 2，且不运行任何测试或 Docker；错误参数、无效 ref 或未知组/场景同样在执行前返回 2。`--plan` 不运行测试、不探测 Docker、不创建结果目录。执行后保存 `dev/verification-runs/<时间>/plan.txt`、逐测试日志/耗时以及场景产物，首个失败立即返回，不自动重复全套。

场景根据本次运行已建立的状态补齐前置：独立 `runtime_smoke` 使用较轻的 `fresh_install_http`；VLESS 重配置需要 `fresh_install_vless` 基线；卸载验证先建立可核对旧 UUID 的 VLESS 安装；最终 smoke 在所有变更场景之后。若中途其他场景替换了安装，会重新准备必要基线，计划可能包含重复安装。现有大型场景尚未拆分，需在计划中确认额外覆盖，不能仅凭名称推断耗时很短。

`--full` 运行的是 `selection.sh` 中的显式宿主安全清单和已注册场景，不等同于执行 `tests/` 下所有脚本，也不自动证明公网或外部服务行为。独立 `hy2_instance_acme_runtime.sh` 是 Pebble/私有 CA 容器 fixture，现有注册场景不调用它；直接修改它或静态引用它的 helper 时，调度器保持 `needs_scope`，即使 `--full` 也不能代替其独立隔离运行。保留该未完成边界并按专属容器流程验证，不要在宿主执行它。

GitHub 对 `main` 启用 PR、线性历史和已解决审查对话保护，并对管理员生效，禁止强推和删除。仓库仅允许 rebase 合并，并自动删除已合并的远程分支。Codex 的审查结果目前写入 PR 评论，而非 GitHub 必需状态检查；GitHub 设置本身不会阻止在机器人审查完成前合并，因此执行者必须主动核对本地审查通过、当前 head 的远程安全审查完成且无未解决问题，远程代码审查不作为等待条件。

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

云端安全审查任务应明确要求：“先读 `AGENTS.md` 与 `SECURITY.md`，审查指定 base 到当前 head 的完整差异及必要调用上下文；按指南报告可达且有证据的安全问题，并注明 head SHA。默认静态分析，确有必要时才做最小隔离复现。”新增指南不代表已配置云端任务或完成审计；生产、真实外部服务和敏感凭据不属于普通 PR 安全审查的授权范围。
