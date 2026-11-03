# AI Native 操作架构

[English contract and acceptance](ai-native-operations.md)

本轮已先完成盘点和设计，再实现用户确认的范围：统一操作契约与可安全复用的接口，明确列出仍需交互的遗留操作。脚本版本为 `2026110302`。

## 现状与目标

原有 Agent 已支持实例/高级组件事务、诊断、连接材料、核心升级与 SubMan 同步，但没有统一分流写接口，服务只能重启。能力中的 `features=true` 容易被误解为可以非交互操作，未知顶层命令还会进入菜单。

新的工作流是：发现操作 → 查询契约 → 读取状态 → 准备私有输入 → 校验 → 显式确认与 CAS 提交 → 检查结果/恢复。菜单和机器入口复用既有业务事务，不通过模拟菜单输入实现自动化。

## 命令设计

| 入口 | 语义 |
| --- | --- |
| `sbv` / `sbv menu` | 交互菜单 |
| `sbv commands --json` | 完整版本化操作目录，包含自动化限制 |
| `sbv schema <operation-id> --json` | 单项参数、确认、CAS、服务影响、输入与敏感性说明 |
| `sbv <资源> <操作> ... --json` | 规范的非交互操作入口 |
| `sbv status/nodes/check ... --json` | 常用只读短命令，斜线仅表示任选其一 |
| `sbv agent ...` | 保留现有调用、结果和安全语义 |

未知命令或多余参数失败，不进入菜单。机器入口 stdout 只输出一个 JSON 对象，进度走 stderr。发现入口不依赖 root、已安装服务或事务清理；实际读写保留权限、锁与恢复保护。

操作描述不是所有协议记录的通用 JSON Schema。协议记录仍由类型化验证器检查，`schema` 明确提供的是操作契约。

## 单一操作目录

目录嵌入模块并随独立 `install.sh` 分发，不运行时下载。每项包含稳定 ID、规范命令、Agent 兼容入口、用法/参数、确认、并发/CAS、服务影响、输入契约、敏感性、外部写入和文档位置。

本轮目录共 56 项：44 项 `structured`、2 项 `legacy_cli`、10 项 `interactive_only`。后两类显式记录限制和菜单位置；旧功能布尔值只表示产品支持，不能代替自动化可用性或运行态证据。

## 已实现的安全接口

- 服务：`status/start/stop/restart/logs`；写操作要求 `--yes`，启动/重启先检查配置并核对最终活动状态，停止核对 inactive。日志默认 100 行、范围 1–1000、禁止 follow，标记为敏感输出。
- 分流：`view/export/nodes/validate/apply/restore/recover`；复用现有统一分流、节点出口、WARP 和规则事务。`view` 脱敏；`export` 敏感，取 `.data.draft` 保存为私有 JSON 后修改。
- `validate` 只检查草稿结构，不宣称已执行核心或运行态验证；`apply` 要求 `--yes` 和草稿中的同快照 fingerprint，真实配置检查由现有事务执行。
- `restore` 要求操作者读取的 fingerprint；`recover` 使用可信 journal 的恢复条件。待恢复状态允许能力发现和对应恢复，不放行其他操作。
- 规范 `sbv subman sync --json --yes` 要求显式外部写入确认，旧 `agent subman-sync --json` 保持兼容。

## 遗留边界

REALITY 实例/QoS 写操作、首装、协议批量移除、完整卸载、SubMan 配置、系统协议栈、BBR、媒体检测、二维码显示和脚本卸载仍按目录标记的入口操作。管理脚本与旧核心更新入口仍为文本 CLI。需要类型化状态迁移或宿主完整事务的能力另立范围，不把菜单函数包装成已可靠自动化的接口。

## 后续功能交付规则

新增或调整功能时，同一变更更新业务实现、对应非交互命令、操作描述、定向测试、生成参考和受影响的 Agent 手册/SPEC/导航。新功能默认必须提供非交互入口；新增例外必须在 SPEC 和审查中明确理由。

先运行 `bash scripts/build-install.sh`，再运行 `bash scripts/build-command-docs.sh`。两项 `--check` 和 `tests/command_catalog_contract.sh` 检查目录、真实路由、参数拒绝及生成文档；docs 验证组与轻量 GitHub 工作流执行相应门禁。运行态与协议测试仍按 AGENTS 4.2 的实际影响选择。

## 验证与交付边界

定向本地检查和真实隔离 systemd Docker 验证已通过。运行态包含 sing-box 1.14.2 配置检查、服务启停重启、真实 HTTP 规则拒绝/恢复、陈旧 CAS 拒绝和 pending journal 清理恢复。恢复场景使用完成事务移回 pending 位置准备，不能声称复现了真实信号中断。

审查修复了合法大节点清单超过 Linux 单参数大小上限的问题：分流查询改用私有文件传入节点 JSON，并以真实验证器和收集器覆盖 128 实例的大清单。媒体检测的实际入口为菜单 `12 → 4`，其下载/缓存及临时进程副作用与遗留服务影响已明确记录。

没有执行真实 WARP/SubMan 写入、公网或生产操作。详细日志、受测摘要、结果复用理由及验收范围见英文契约第 8 节；当前 head 审查、PR 合并和 Wiki 发布分别记录，不提前宣称完成。
