# 异常处理与变更事务

本文定义 `sing-box-vps` 中可恢复变更的错误传播、远程内容处理和回滚边界。`install.sh` 仍是运行时单一真源；本文不改变未迁移旧路径的既有接口。

## 失败分类

- 预期失败：网络不可达、输入无效、目标状态不满足前置条件或候选校验失败。底层函数 `return` 非零并保留上下文；事务层清理候选文件，未提交时目标保持不变。
- 用户取消：交互层将取消作为当前菜单动作结束，不把它伪装成成功，也不破坏主菜单循环。
- 未预期异常：命令返回了未处理的非零状态，或状态机无法继续。事务 trap 记录阶段和退出码，但不记录完整 `BASH_COMMAND`；随后按是否已提交决定清理或回滚。
- 信号中断：`INT`、`TERM`、`HUP` 分别按 `130`、`143`、`129` 传播。提交前只清理 staging；提交后先尝试回滚。trap 防重入，不调用会 `exit` 的旧 `log_error`。

Bootstrap 与运行时是两个边界。Bootstrap 负责下载完整脚本、执行 `bash -n` 和项目身份校验；校验通过后才启动 `install.sh` 或 `uninstall.sh`。脚本未启动时，脚本内部 trap 不可能处理下载错误，因此 Bootstrap 必须自行返回 curl/校验退出码，并明确说明系统未发生变更。

## `sbv` 自更新状态机

```text
PRECHECK
  -> STAGE -> VALIDATE -> BACKUP -> COMMIT -> POSTCHECK -> CLEANUP -> success
       |          |          |         |          |
       +----------+----------+---------+----------+
                 failure before commit -> CLEANUP -> unchanged
                 failure after commit  -> ROLLBACK -> POSTCHECK(old) -> CLEANUP
                                                     |                 |
                                                     +-> rolled_back    +-> rollback_failed/manual intervention
```

`manual_update_script()`、`ensure_sbv_command_installed()` 和同目录远程 Shell artifact 下载都遵守候选文件再替换的边界。`sbv` 更新的关键规则如下：

1. PRECHECK 使用同目录互斥锁；目标不存在可以创建，普通文件可以更新，符号链接和其他特殊文件默认拒绝。记录当前版本、SHA-256、权限和 UID/GID。
2. STAGE 使用目标目录内的 `mktemp` 文件。`curl` 只写候选文件，并设置 connect timeout、总 timeout 和有限重试；stderr 只保留有限、脱敏的诊断。
3. VALIDATE 检查非空和最小大小、`#!/usr/bin/env bash`、`bash -n`、唯一的 `YYYYMMDDXX` `SCRIPT_VERSION`、`PROJECT_AUTHOR` 和 `PROJECT_URL`。低版本候选被拒绝；健康目标与候选版本相同时为 no-op。候选 SHA-256 只用于本地完整性核对，不是远端签名。
4. BACKUP 在提交前创建 root-only 受保护备份；目标不存在时记录该状态，不伪造可恢复的旧文件。
5. COMMIT 设置执行权限和原所有者，然后使用同目录 `mv` 原子替换。只有 `mv` 成功后 `changed` 才为 `true`。
6. POSTCHECK 再次执行 Bash 语法、身份、版本、可执行权限和 SHA-256 检查。
7. ROLLBACK 只在提交后失败时触发。恢复后必须重新核对旧版本、旧 SHA-256、语法和执行权限；任何一步失败都返回 `rollback_failed` 并设置 `manual_intervention_required=true`，保留人工恢复所需文件。
8. CLEANUP 正常结束时删除候选、stderr、备份和锁。回滚失败时保留备份、候选留存副本和诊断文件，但仍释放锁。

状态字段定义：

- `changed`：是否已经发生过目标替换；回滚成功后仍表示曾提交过变更。
- `rolled_back`：提交后的失败是否完成旧目标恢复。
- `rollback_ok`：恢复后的所有最终校验是否全部通过。
- `manual_intervention_required`：自动恢复失败，不能继续假设服务或脚本安全。
- `unchanged`：没有提交过变更；通常意味着候选下载/校验失败，或提交前失败。
- `no-op`：健康目标已经是候选版本，没有备份、提交或无意义覆盖。

标准错误上下文至少包含：`operation`、`stage`、`code`、`message`、`detail`、`command_exit_code`、`hint`、`changed`、`rollback_attempted`、`rolled_back`、`rollback_ok`、`manual_intervention_required`、`current_version`、`candidate_version`、`target_path` 和 `log_file`。人类提示写 stderr；错误详情最多保留有限长度，并过滤 URL 用户信息、Token、密码和 Authorization 字段。

## 下载错误分类

| curl 状态 | 稳定代码 | 含义 |
| ---: | --- | --- |
| 6 | `download_dns_failure` | DNS 无法解析 |
| 7 | `download_connection_failed` | 建连失败 |
| 18 | `download_partial_transfer` | 传输未完整结束 |
| 28 | `download_timeout` | connect 或总时限到期 |
| 129/130/143 | `signal_interrupted` | HUP/INT/TERM 中断 |
| 其他非零 | `download_failed` | 其他下载失败 |

只读 `check_script_status()` 可以 best-effort：网络或响应异常显示“无法检测更新”，而不是让菜单退出；它必须与变更型下载的错误策略区分开。API 读请求、API 写请求、软件包/二进制安装和配置生成也要在其各自事务中保留真实退出码。

## `curl`/`wget` 调用清单

本轮按调用用途盘点了 `install.sh`、`uninstall.sh`、`utils/` 和验证脚本：

| 类型 | 当前调用 | 本轮边界 |
| --- | --- | --- |
| 可执行脚本或关键 artifact | README Bootstrap、`stage_sbv_candidate_from_url()`、`download_shell_artifact_atomically()` | 已迁移到同目录 staging、校验和原子替换；不直接写最终执行路径 |
| 只读 best-effort 查询 | `check_script_status()`、`probe_reality_sni_candidate()`、`get_public_ipv4()`、`get_public_ipv6()` | 不应改变配置；失败分别降级为无法检测、探测失败或空结果 |
| API 读请求 | `get_latest_version()`、`subman_api_request()` 的 GET | 保留为后续迁移项；应补充统一 timeout、HTTP/JSON 分类和 unavailable 语义 |
| API 写请求 | `register_warp()`、`subman_api_request()` 的 PUT/DELETE | 保留为后续迁移项；必须继续保护凭据并区分传输结果不确定与服务端拒绝 |
| 软件包或二进制安装 | `install_dependencies()` 的 apt/yum、`install_binary()` 的临时 `wget` | 不属于本轮 `sbv` 脚本修复；二进制下载不写脚本最终路径，但仍需后续统一 timeout、stderr 限长和回滚上下文 |
| 验证探针 | `dev/verification/remote/entrypoint.sh` 的本地代理 `curl` | 仅用于 Docker 运行时探测，不是生产安装路径 |

`uninstall.sh` 和 `utils/` 当前没有远程 `curl`/`wget` 调用。除上述已迁移的可执行 artifact 外，本轮不扩大到 API、软件包、二进制升级或配置写入事务。

## 变更操作检查清单

提交涉及关键路径的改动前，确认：

- [ ] 识别目标的不存在、普通文件、符号链接和特殊文件状态。
- [ ] 远程内容只进入同目录 staging，且有 timeout、有限重试和 stderr 脱敏。
- [ ] 候选完成大小、格式、语法、身份、版本和内容校验。
- [ ] 已记录原版本、hash、权限、owner，并在提交前创建可恢复备份。
- [ ] 最终提交使用原子替换；`changed` 只在替换成功后设置。
- [ ] postcheck 覆盖候选版本、hash、语法、身份和执行权限。
- [ ] 每个提交后失败分支都有验证过的 rollback；rollback 失败保留人工恢复材料。
- [ ] INT/TERM/HUP 不会留下锁或无用候选，不会把未完成变更报告成成功。
- [ ] CLI 返回非零，交互动作返回菜单；没有用 `2>/dev/null || true` 隐藏变更错误。
- [ ] 运行 `bash -n install.sh`、相关离线故障注入测试、全部适用本地测试和 `bash dev/verification/run.sh`。

## 后续迁移清单

本轮只迁移了 `sbv` 自更新、`ensure_sbv_command_installed()` 的脚本候选安装，以及媒体检测后端的远程 Shell artifact 下载。以下路径仍需按相同原则逐步迁移，避免扩大本轮回归面：

- `install.sh:register_warp()`：Cloudflare API 写请求仍需独立的 timeout、错误分类和凭据安全日志策略。
- `install.sh:measure_latency()`、`get_public_ipv4()`、`get_public_ipv6()`：只读 best-effort 查询应统一 unavailable 语义和 timeout。
- `install.sh:get_latest_version()`：GitHub API 读请求应明确 HTTP/JSON/网络失败分类。
- `install.sh:install_binary()`：`wget` 软件包/二进制安装已有临时目录和二进制原子替换，但还需统一 timeout、stderr 限长和 return-based 错误上下文。
- `install.sh:replace_singbox_binary_atomically()` 与 Agent upgrade：继续保持现有配置、服务活动状态和回滚契约，后续迁移时必须复用真实回归和 Docker 验证。
- `systemctl`、防火墙、QoS、ACME、Warp、SubMan API 写入和配置重建：按操作边界分别补充 prepare/validate/commit/postcheck/rollback，不用全局替换旧 `log_error`。
- `uninstall.sh` 的本地 `exec` 委托：当前没有远程下载最终路径问题；若未来增加远程 fallback，必须复用 Bootstrap 的完整下载和身份校验。
