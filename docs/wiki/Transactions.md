# 异常处理与变更事务

本文说明 `sing-box-vps` 可恢复变更的错误传播、远程内容处理和回滚边界。`install.sh` 是运行时单一真源。二进制安装、受管核心升级、WARP 注册和最新版本查询已完成有限范围的实现与验收，英文契约及中译见 [Runtime transaction SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/runtime-transactions.md)；实际结果与生产、真实提供商验收分别记录。

## 失败分类

- 预期失败：网络不可达、输入无效、目标状态不满足前置条件或候选校验失败。底层函数 `return` 非零并保留上下文；事务层清理候选文件，未提交时目标保持不变。
- 用户取消：交互层将取消作为当前菜单动作结束，不把它伪装成成功，也不破坏主菜单循环。
- 未预期异常：命令返回了未处理的非零状态，或状态机无法继续。事务 trap 记录阶段和退出码，但不记录完整 `BASH_COMMAND`；随后按是否已提交决定清理或回滚。
- 信号中断：`INT`、`TERM`、`HUP` 分别按 `130`、`143`、`129` 传播。提交前只清理 staging；提交后先尝试回滚。trap 防重入，不调用会 `exit` 的旧 `log_error`。

Bootstrap 与运行时是两个边界。`bootstrap.sh` 根据 `install` 或
`uninstall` 选择完整脚本，在私有 `mktemp -d` 目录中下载，执行 `bash -n`
和项目身份校验，校验通过后才启动 `install.sh` 或 `uninstall.sh`。脚本未
启动时，脚本内部 trap 不可能处理下载错误，因此 Bootstrap 必须自行返回
curl/校验退出码，并明确说明系统未发生变更。菜单里的“卸载 sing-box”只
删除服务、核心和配置并保留 `sbv`；独立卸载脚本的 purge 还会删除全局
`sbv`。

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

菜单 15 只在更新事务成功并完成清理后，通过 `exec` 启动全局 `sbv` 的新版菜单，沿用当前管理锁及其文件描述符，避免旧进程继续运行旧函数。目标文件为 no-op 但运行时版本落后时同样切换；运行时和目标都已是最新版时保留当前菜单。CLI 更新不启动菜单。若 `exec` 本身失败，保留当前菜单并报告自动切换失败，已提交的更新不回滚；更新事务失败时不尝试切换。

## 二进制安装与核心升级

`install_binary()` 使用目标目录内的私有随机 workspace 和同文件系统候选文件，不再清空固定 `/tmp/sing-box-install`，也不再使用无界 `wget`。官方归档下载设置连接/总时限、有限重试和重试预算；stderr 持续消费但只保留配置上限内的内容，错误提示不打印原文。

解压前检查完整 manifest：只接受预期版本/架构目录、唯一普通文件 `sing-box`、最多一个普通文件 `libcronet.so` 和安全相对路径；拒绝路径穿越、符号链接、硬链接、重复核心及特殊文件。仅解压选定成员，候选通过有界 `version` 检查且精确匹配目标版本后才允许发布。本地 hash 用于完整性核对，不代表远端发布者签名。

二进制、可选受管运行库和 marker 全部准备并备份旧状态后，才逐文件原子 rename。保留未由 sbv 管理的运行库，发布后验证版本/hash/权限/owner 及 marker。三个文件是操作级回滚组，不是一次文件系统级原子提交。提交失败或信号会恢复并验证旧文件，包括原先不存在的运行库/marker；rename 后信号窗口也受覆盖。回滚失败保留私有材料并要求人工处理；已校验提交后的清理失败明确说明已提交和恢复路径。

`update_singbox_binary_preserving_config()` 显式处理依赖和安装错误，在条件调用中也不会继续重启。变更前备份二进制、运行库和配置；配置意外变化、目标版本不符或配置校验失败均在目标重启前终止。服务重启失败恢复旧文件和此前的活动状态，回滚后检查内容及元数据，信号按真实状态传播并恢复调用方原 trap。apt/yum 自身的软件包变更不属于二进制回滚的承诺范围。

Agent upgrade 保留预检、私有 manifest 与持久化事务结果：成功需要目标版本、配置 hash 不变、目标核心校验和服务 active；失败区分完整回滚、回滚失败及结果落盘失败。Agent 预检继续拒绝降级，不能把已装 1.14.2 后请求 1.14.0 当作成功升级场景。各接口的 `changed` 按其自身契约解释，不能把 `sbv` 自更新“曾提交”字段直接套用为 Agent 的最终状态字段。

## WARP 注册与凭据恢复

注册前在 `${SB_PROJECT_DIR}.warp-registration.pending.json` 写入私有 `sent` receipt；路径位于项目快照之外，避免配置回滚丢失外部写入结果。POST 不自动重试。DNS/建连失败或明确 HTTP 4xx 拒绝可清理 receipt；超时、请求可能已发送、响应异常或服务端失败保留现场，再次调用不会重复 POST。不确定结果需要操作者对账，不能盲目删 receipt。此保护是客户端防重发，不是提供商的分布式 exactly-once 保证。

合法 HTTP/JSON 响应必须包含正确类型的必要字段、同族地址和三字节 client ID，随后原子保存为 `received`。本地保存失败后，再次调用先校验恢复密钥及响应，只重试本地保存，不重新注册。

凭据以安全 Bash 数据序列化到私有候选文件，经语法校验和 `.bak` 备份后原子发布，再核对 hash 和权限。提交后校验失败及 rename 后信号恢复旧凭据；保留真实 writer/信号状态和 received 恢复材料。日志不记录 Token、私钥或响应正文。

## 最新版本查询

`query_latest_singbox_release()` 使用私有临时文件、连接/总时限、响应大小限制和有界诊断，只接受单个 JSON 对象中的稳定数字 release tag。传输、HTTP、错误/多个 JSON 文档、错误类型和预发布 tag 分别按结果分类。

`get_latest_version()` 对普通查询失败显示 `unavailable` 并回退 `SB_SUPPORT_MAX_VERSION`；只在成功结果确实更高时警告。HUP/INT/TERM 及 curl 对应状态直接返回 129/130/143，保留 `SB_VERSION=latest`，调用方取消后不能继续按回退版本安装。查询的 best-effort 回退和变更操作失败是不同边界。

## 高级组件持久事务

组件 `create`、`replace`、`delete`、`rebuild` 和 `takeover` 在 `${SB_PROJECT_DIR}.component-write.lock` 中原子发布 `transaction.json`，再写入同目录的状态快照。`phase` 按 `prepare`、`snapshot`、`publish`、`resources`、`service`、`committed` 前进；监听资源变化时，防火墙 journal 与快照绑定，并记录 `firewall_expected`。正常提交先写 `committed` 再清理目录，故障或不可捕获中断不会把临时目录当作成功。

`sbv agent component recover --json --yes --expected-revision N` 只接受匹配 CAS revision、owner 已结束、journal schema/phase/快照可信的事务。发布或资源阶段按防火墙、状态/config、服务活动顺序补偿；缺失或不确定的外部日志、活动 owner、revision 不匹配和清理失败均保留事务目录并返回稳定错误。`component diagnose --json` 只报告 pending 与 phase 摘要，不泄漏组件配置或密钥。

实例写入/恢复与组件写入/恢复共享同一管理锁；任一持久事务目录 pending 时，另一类变更都会被拒绝，避免后续快照回滚覆盖已经提交的不同资源。

`sbv` 自更新的结构化错误上下文包含：`operation`、`stage`、`code`、`message`、`detail`、`command_exit_code`、`hint`、`changed`、`rollback_attempted`、`rolled_back`、`rollback_ok`、`manual_intervention_required`、`current_version`、`candidate_version`、`target_path` 和 `log_file`。人类提示写 stderr；错误详情最多保留有限长度，并过滤 URL 用户信息、Token、密码和 Authorization 字段。二进制、WARP、版本查询分别使用各自的 `operation`/`stage`/`code` 诊断和真实退出状态，Agent upgrade 保持既有 JSON 结果；不宣称所有历史函数采用相同的全局输出 schema。

## 下载错误分类

下表用于 `sbv` 和二进制下载；WARP 使用 `transport_<状态>` / `http_<状态>`，版本查询使用自身查询分类和 `signal_interrupted`，调用方仍保留真实退出码。

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

以下按调用用途列出运行时和验证脚本的当前边界：

| 类型 | 当前调用 | 当前边界 |
| --- | --- | --- |
| 远程入口 | `bootstrap.sh` | 按 `install`/`uninstall` 选择脚本，私有目录完整下载后执行 `bash -n` 和项目身份校验，最后才启动临时文件；不直接写安装最终路径 |
| 运行时可执行 artifact | `stage_sbv_candidate_from_url()`、`download_shell_artifact_atomically()` | 已迁移到同目录 staging、校验和原子替换；不直接写最终执行路径 |
| 只读 best-effort 查询 | `check_script_status()`、`get_public_ipv4()`、`get_public_ipv6()` | 均有请求时限；IP 探测仅接受合法同族地址，全部端点失败时返回非零且不输出候选；更新查询失败显示无法检测 |
| REALITY 候选探测 | `select_reality_sni_candidate()`、`run_reality_target_check()` | 校验固定 checker 下载与 JSON 报告，每个域名设总时限；失败不选择域名，信号清理受管子进程；附加风险须明确确认 |
| API 读请求 | `get_latest_version()`、`subman_api_request()` 的 GET | GitHub 查询有连接/总时限、响应大小及单文档校验，普通失败明确回退，信号取消传播；SubMan 有私有凭据文件、HTTP/JSON/Workspace 校验和错误分类 |
| API 写请求 | `register_warp()`、`subman_api_request()` 的 PUT/DELETE | WARP 有界且无自动重试，以 sent/received receipt 防重发并恢复本地保存；SubMan 区分传输结果不确定与服务端拒绝，条件写入及读回对账见下文引用 |
| 二进制安装 | `install_binary()` 的有界 `curl` | 私有 staging、完整归档/精确版本校验、全部候选准备、逐文件原子提交、postcheck/rollback 和信号清理 |
| 系统软件包 | `install_dependencies()` 的 apt/yum | 保留包管理器状态并由调用方显式处理；不宣称 OS 软件包可由二进制备份回滚 |
| 验证探针 | `dev/verification/remote/entrypoint.sh` 的本地代理 `curl` | 仅用于 Docker 运行时探测，不是生产安装路径 |

`uninstall.sh` 当前没有远程 `curl`/`wget` 调用。SubMan 的条件写入、结果不确定时读回对账及真实服务验收边界见[使用注意事项](https://github.com/KnowSky404/sing-box-vps/wiki/Notes)与[地址选择规范](https://github.com/KnowSky404/sing-box-vps/wiki/SubMan-Address-Selection)。这些已实现保护不等于全部路径都采用同一套下载事务。

## 变更操作检查清单

以下用于审查未来变更，不是本轮未完成任务。提交涉及关键路径的改动前，按操作边界确认：

- 识别目标的不存在、普通文件、符号链接和特殊文件状态。
- 远程内容只进入受控 staging，关键文件在目标同文件系统原子发布；请求有 timeout、有限重试或明确禁止自动重试，并保护 stderr。
- 候选完成大小、格式、语法、身份、版本和内容校验。
- 已记录原版本、hash、权限、owner，并在提交前创建可恢复备份。
- 最终提交使用原子替换；`changed` 只在替换成功后设置。
- postcheck 覆盖候选版本、hash、语法、身份和执行权限。
- 每个提交后失败分支都有验证过的 rollback；rollback 失败保留人工恢复材料。
- INT/TERM/HUP 不会留下锁或无用候选，不会把未完成变更报告成成功。
- CLI 返回非零，交互动作返回菜单；没有用 `2>/dev/null || true` 隐藏变更错误。
- 按 [AGENTS.md 第 4.2 节](https://github.com/KnowSky404/sing-box-vps/blob/main/AGENTS.md) 运行语法检查及受影响事务的离线故障注入测试；仅在服务、网络或生命周期行为变化时追加对应真实 Docker 场景。该清单不要求固定运行粗粒度 `run.sh` 或无关协议回归。

## 已完成验收与持续维护

原迁移清单已收敛为 [运行时事务 SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/runtime-transactions.zh-CN.md) 的 RT-01 至 RT-04：二进制下载与发布、受管升级、WARP 注册/保存、版本查询已实现并取得对应证据。`sbv` 自更新、全局命令候选安装、媒体检测 Shell artifact、REALITY checker、公网 IP 和 SubMan 的既有保护继续保留。

本轮结果：

| 层次 | 已取得证据 |
| --- | --- |
| 本地故障注入 | 二进制下载/归档/版本/prepare/commit/postcheck/信号/rollback；更新依赖和安装错误、配置保持；Agent upgrade 结果记录；WARP 不确定结果防重发、received 恢复、安全序列化、保存和信号回滚；版本 HTTP/JSON/传输分类及取消。对应 `tests/binary_install_transactions.sh`、`tests/binary_update_transactions.sh`、`tests/warp_registration_transactions.sh`、`tests/latest_version_lookup.sh` 与受影响既有回归均通过。 |
| 多平台 | Ubuntu 22.04 与 Rocky Linux 8 一次性容器的四项新增事务测试通过；Rocky 覆盖 Bash 4.4.20 / GNU coreutils 8.30。WARP/版本修复另行重跑，后续 writer 状态分支由定向本地检查覆盖。 |
| 真实 Docker 生命周期 | HTTP 1.14.2 首装、拒绝 Agent 降级、实际 1.14.0→1.14.2 升级及精确 HTTP marker；注入目标版本重启失败后完整回滚到 1.14.0，配置 hash 不变、服务 active、Agent 事务结果落盘，再次 HTTP marker 通过。容器已删除。 |

最终 Docker 受测运行时 SHA-256 为 `420ea43d54daa0001dac04bacd917fb7beaadd53e8d32572ffbfe27dedeb81d1`，核对时与工作区逐字一致。私有本地产物位于 `/tmp/sbv-spec-binary-docker-v2/`，`result.env` 为 `lifecycle_exit=0`；Agent 摘要位于 `agent-results/`，升级和回滚 probe bundle 位于 `upgraded/`、`rolled-back/`。多平台日志为 `/tmp/sbv-platform-ubuntu.log`、`/tmp/sbv-platform-rocky-final.log` 和两份 `*-updated.log`，修复重跑 hash 为 `adf3ca63eff293eea1abcf576884781a6b0f98f6fe411925a7fa4f61c0d9d11d`。这些是本轮本地证据，不是已发布的 Wiki 附件或永久存储。

真实 WARP 账户写入、生产升级、公网效果、主仓库审查/合并和 Wiki 发布保持独立，不能由 mock、容器成功或本页状态代替。此有限事务契约不要求执行真实账户注册或生产变更。

持续维护按影响选择：改动服务、防火墙、QoS、ACME、Warp、SubMan 或配置时，保留其已有操作事务，补足实际新增分支及调用方验证；不要把完成状态扩张成“全仓 systemctl 已全局重构”的承诺，也不要全局替换旧 `log_error`。卸载脚本目前没有远程 fallback，若以后增加，必须复用 Bootstrap 的完整下载与身份校验。版本元数据或文档变更只有满足 AGENTS.md 第 4.2 节才可复用先前证据。

## 生成基线与手工扩展

`managed-config.generated.json` 记录最近一次完整生成的受管投影，不包含合并后新增的手工扩展。全局生成先做三方合并，再校验完整候选并备份、发布；生成基线和 `.bak` 同处项目目录，纳入现有整目录快照及失败恢复。tag 冲突、无效基线、无法合并的同时修改均在发布前失败。实例操作从现场配置构造候选，仅替换原 store 中归属明确的 tag，不按协议类型批量删除手工入口。

计时提示只写 stderr，不改变成功/失败状态，也不改变事务的信号处理与回滚责任。计时进程关闭继承的管理锁描述符，避免操作完成后仍占锁；通过独立 Bash 和私有就绪管道启动，避免极快操作提前终止计时器时触发调用方的退出清理。

防火墙目标按配置分类和 tag 共同确定归属，使用当前协议状态、实例 tag、启用的高级组件及本次已校验的候选 tag，不将手工监听加入规则或引用。手工监听共存时，旧菜单改用按地址和传输区分的防火墙事务；临时日志位于项目目录旁的 `sing-box-vps.firewall-reconcile.*`，权限 600。成功或完整回滚后清理；回滚失败时保留日志并报告路径，中断也会尝试回滚。
