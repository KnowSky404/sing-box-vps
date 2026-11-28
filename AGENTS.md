# sing-box-vps 项目规约

本项目是面向 Linux VPS 的 root 安装器与管理工具。开始任务先识别类型、风险和授权；进入下列阶段**之前**读取当前 worktree 的对应本地章节及受影响 SPEC。多类任务取并集，任务恢复时将记录与 Git、检查及实际环境对账。链接是按需读取入口；远程 Wiki 和固定 Manifest 链接用于发布与溯源。必读内容缺失、规则冲突或必要证据未完成时，停止对应阶段并报告。

## 必读路由

| 阶段 | 当前 checkout 的必读依据 |
| --- | --- |
| 开发、修复、文档交付、任务恢复 | [任务准备与提交](docs/wiki/Development.md#任务准备与提交)、[项目与 Shell 规范](docs/wiki/Development.md#项目与-shell-规范) |
| 风险分级、选测或复用结果 | [风险与验证范围](docs/wiki/Development.md#风险与验证范围)；使用调度器时读[命令与计划](docs/wiki/Development.md#调度器命令与计划)，涉及 Docker 定点场景时读[场景契约](docs/specs/scoped-docker-verification.zh-CN.md) |
| 本地或云端安全审查，以及下载、凭据、事务、启停、恢复或只读诊断变更 | [安全审查与运行安全](SECURITY.md)；PR 审查还读[审查与合并](docs/wiki/Development.md#审查与合并) |
| 提交后审查、推送、开 PR、合并 | [审查与合并](docs/wiki/Development.md#审查与合并)；合并前读[集成复验](docs/wiki/Development.md#候选发布与交接) |
| GitHub 写操作与 Actions 操作（含单独运行或重跑） | [Actions 授权与定点验证](docs/wiki/Development.md#github-actions-授权与定点验证) |
| PRE、发布、生产操作与回滚 | [候选、发布与交接](docs/wiki/Development.md#候选发布与交接) |
| 所有 VPS 操作（含测试机日常排障） | [Operator Skill](skills/sing-box-vps-operator/SKILL.md)，并按其路由读运行手册 |
| 新增或变更 `sbv` 操作、安装器构建或 Wiki 维护 | 按影响读 [AI Native 同步](docs/wiki/Development.md#ai-native-命令与手册同步)、[单文件构建](docs/wiki/Development.md#模块化源码与单文件构建)、[Wiki 维护与发布](docs/wiki/Development.md#文档维护与-wiki-发布) |
| 修改 REALITY 地区候选或 checker 固定版本 | [开发网络证据门槛](docs/wiki/Development.md#reality-地区候选的开发门槛)，提交前执行新鲜 DNS/TLS 校验 |

[Agent 索引](docs/agents/llms.txt)导向使用手册；[SPEC 索引](docs/specs/README.zh-CN.md)列出实现契约和证据。[开发工作流](docs/wiki/Development.md)维护细则与固定 Manifest 版本。计划器旧提示 `AGENTS.md 4.2` 对应[风险与验证范围](docs/wiki/Development.md#风险与验证范围)。

## 开发与安全底线

- 开工记录原始需求、范围/非目标、验收、风险、授权、基线 SHA 和任务分支；阶段进度写脱敏 PR 或忽略的 `.task/task.md`。功能、修复及本规约迁移从最新远端默认分支创建独立任务分支与 worktree；保护用户变更，完成检查后仅以原子 Conventional Commits 提交相关改动。
- Bash 优先复用系统工具，遵守本地 Shell 规范。运行入口先检查 root 和依赖，验证输入、安全默认、幂等与最小权限。查询 sing-box 官方格式、API、迁移、版本兼容或示例先用 Context7，不足时优先查官方文档、仓库与 migration。
- 下载完整内容至私有临时区，关键产物以同目录 staging 校验并同文件系统原子替换。关键文件改前 `.bak`；变更须准备、验证、备份、提交、后检、回滚及清理，报告最终状态。底层返回状态，入口或不可恢复边界退出；不得吞掉变更错误。信号中断清理并报告目标状态；日志和共享证据须脱敏。
- 菜单与非交互 `sbv` 共享业务、dispatcher、锁、校验、CAS 及事务。新增/变更操作同步命令、嵌入目录、测试、生成参考和 Agent 手册/导航；遵循结构化输出和仅交互例外契约。修改嵌入目录后先构建安装器，再生成参考；提交前两项 `--check` 和命令契约测试。
- 每个实际交付仓库文件变更的对话轮次递增脚本版本一次，格式 `YYYYMMDDXX`；同步头部、`SCRIPT_VERSION` 和 README。编辑 `src/install/` 源码，生成并提交 `install.sh`，提交前运行构建 `--check`。只读工作不递增版本。

## 验证门禁

- 按行为、影响、数据及信任边界取最高 R0–R3，范围变化重判，无法界定升档。先记录最小充分检查、前置、排除项和预计耗时；必要检查通过且无新风险后停止。仅在受测输入、依赖、核心与环境等价时复用证据；修复后重跑失败及受影响项。
- 修改、生成、导出或重建配置须对受影响输出执行 `sing-box check`；服务、网络或生命周期变化须对应真实运行态，默认由本地隔离 Docker 验证，准备场景前置，专属 fixture 走独立容器流程。配置、mock、Docker、公网、外部服务与生产证据各自核对。仅核心适配/格式迁移、共享影响广泛或范围无法界定、明确要求全量或完整发布验收时执行全量。
- 本地和云端安全审查先读安全指南，检查完整差异及必要调用上下文；只读审查默认静态，确需验证才做最小隔离验证。

## 审查、授权与交付门禁

- 每次原子提交后立即本地 `/review`；入口不可用时完成并记录等效审查。每次推送或创建 PR 前，本地审查须覆盖当前 HEAD 的全部待推送提交和相对任务基线的完整差异并解决问题；新提交或差异变化重审。未完成或失败时禁止推送、开 PR。
- Actions 已授权的自动入口仅为面向 `main` 的 `PR contract`。外部 fork 须先审再批准运行。其他启用/恢复、自动入口、手动运行和重跑各需明确授权；手动运行仅限指定 workflow、ref、基线及范围。GitHub 写操作前只读核对工作流状态与直接/间接触发，无法排除未授权触发时停止。未经授权记 `not_run_not_authorized`；合并前核对适用 CI 证据，缺失留 PR，禁止绕过保护。
- 禁止手动召唤 Code Review 或 Security Review，禁止以草稿切换、空提交等方式重触发。当前 PR HEAD 已自动启动的 Security Review 须完成并解决问题；排队、运行、失败、取消或查询失败均不能按未触发放行。确认无自动机器人审查才记 `not_triggered`。无自动 Security Review 时按其余门禁合并；仅自动 Code Review 无额外等待，报告的问题仍须处理；旧 HEAD 不作当前证据。
- P0/P1 阻塞，P2 按验收和安全影响处理，P3 通常可延期；新增安全、隐私、完整性或验收失败不得延期。每候选反馈批处理并跨会话记录轮次，R0 不增加循环，R1 最多 2 轮，R2/R3 最多 3 轮自主修复；用尽仍阻塞则保留 PR 交 Owner。
- 合并前只读核对当前 head、基线、授权、必要验证、审查、检查、未解决意见及适用候选/恢复证据。按分支保护走 PR，只用 GitHub rebase 合并，禁止强推/删除 main 或绕过门禁。合并后核对远端集成 tree 及任务分支删除；仅清理已集成且无用户修改或待保留产物的任务 worktree/分支，报告障碍。
- DEV 用本地 mock/一次性 Docker；按风险验收稳定 PRE 候选，共享 PRE 一次一个。测试 SSH 用 `sing-box-test`，生产用 `sing-box-prod`，未知远程按生产处理。输入或环境变化时按影响使证据失效，集成有实质差异须复验。发布、生产变更、迁移和破坏性操作按各自授权执行；生产写入先出计划、备份/回滚并取得明确批准，随后核对实际版本、就绪及行为。分开记录实现、合并就绪、合并、发布就绪、部署与生产验证状态。
