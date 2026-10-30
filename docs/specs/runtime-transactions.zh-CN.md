# 运行时事务完成契约

[English](runtime-transactions.md) · [SPEC 索引](README.zh-CN.md)

状态：以下有限操作已于 2026-10-30 实现并完成对应验收。本地故障注入、平台检查和真实核心 Docker 生命周期分别记录。本记录不宣称已完成真实 Cloudflare WARP 账户注册、生产升级或公网验收。

## 范围与已完成验收

`install.sh` 仍为运行时单一真源。本契约完成 Transactions 指南原迁移清单中的二进制安装、受管升级、WARP 注册和最新版本查询；不把所有历史 `log_error`、`systemctl`、防火墙、QoS 或软件包命令改成同一个全局事务接口。

| 编号 | 操作 | 已完成的验收 |
| --- | --- | --- |
| RT-01 | `install_binary()` | 私有 staging、有界下载和诊断、严格归档及可执行版本校验；二进制/运行库/marker 全部准备后发布；原子文件替换、提交后校验、回滚和信号清理。 |
| RT-02 | `update_singbox_binary_preserving_config()` 与 Agent upgrade | 显式错误传播、受保护备份、配置保持不变、重启前目标核心校验、失败后的服务恢复、持久化 Agent 事务结果；Agent 预检继续拒绝降级。 |
| RT-03 | `register_warp()` 与凭据发布 | 每个未对账 receipt 只尝试一次 POST；HTTP/JSON 校验、明确不确定结果、已接收结果恢复、私有安全序列化、备份/校验/回滚及真实保存/信号退出码。 |
| RT-04 | `query_latest_singbox_release()` / `get_latest_version()` | 有界 HTTP 读取；传输、HTTP 和单 JSON 文档分类；普通查询失败明确回退适配版本；取消返回 129/130/143，不选择回退版本。 |

## RT-01：二进制与可选运行库发布

1. 使用私有随机目录和目标同文件系统的候选文件，不再复用或递归清空固定共享路径 `/tmp/sing-box-install`。
2. 官方 release 归档下载设置连接/总时限、有限重试和重试预算；持续消费 stderr，仅保留配置上限内的诊断，不输出远程响应或含凭据的原始错误。
3. 解压前检查完整 manifest：只接受预期版本/架构目录、唯一普通文件 `sing-box`、最多一个普通文件 `libcronet.so`、安全相对路径和普通文件/目录类型。拒绝路径穿越、符号链接、硬链接、重复核心和无效归档。
4. 只将选定成员解压到私有目录；使用有界 `version` 命令确认候选可执行文件的精确版本，再允许发布。信任边界仍为官方 release 来源；本地 hash 不是发布者签名。
   既有服务端配置含 namespace 声明或已知 namespace Dial 字段时，另行读取 staging 二进制构建元数据；在替换二进制、运行库或 marker 前，拒绝已复现的 Linux ARM64/1.14.2/`with_purego` 组合，以及该准确平台/版本下无法确认的构建。名为 `netns` 的普通 header 不算 namespace 使用。该门禁保护操作员已安装的兼容核心，覆盖更新或修复路径；见 [namespace 完成记录](full-protocol-completion.zh-CN.md)。
5. 先准备二进制、可选受管运行库和 hash marker，再提交任何二进制；保留未由 sbv 管理的现有运行库。备份旧文件及元数据，保留原 owner，并设置候选目标权限。
6. 每个文件通过同文件系统原子 rename 发布。三个文件构成操作级回滚组，不代表整个文件系统的一次原子 rename。发布后检查二进制版本/hash/元数据及运行库/marker 的 hash/元数据。
7. 失败或 INT/TERM/HUP 清理候选；已发布时恢复并验证旧文件，包括旧运行库/marker 不存在的情况。处理 rename 已成功、内存 commit 标志尚未更新时的信号窗口。回滚失败保留私有恢复材料并要求人工介入；已校验提交后的清理失败明确报告已提交状态和恢复路径，不宣称清理成功。

namespace 候选门禁另以真实官方 1.14.2 ARM64 二进制核对：既有服务端配置含 namespace 时，拒绝 `with_purego` 候选并允许兼容的 glibc 候选。该证据只是有界候选元数据检查，没有安装或激活运行时；结果和核心 hash 保留于 `/tmp/sbv-binary-namespace-actual.env` 与 `.sha256`。`binary_namespace_guard.sh` 另覆盖完整安装路径中不安全/未知候选的拒绝与产物不变、安全候选及普通 header 不误判。

## RT-02：受管核心升级

更新调用方显式处理依赖和二进制安装失败，在条件调用上下文中也不会丢失状态。变更前备份旧二进制、受管运行库/marker 与配置。配置发生意外变化，或目标核心/配置无效时，在目标服务重启前失败。

重启失败时恢复旧二进制、运行库、配置和此前的服务活动状态；恢复检查包括文件内容和元数据，失败时保留备份。信号按真实状态传播，并恢复调用方原有的信号处理器。软件包变更仍属于 apt/yum 自身边界，本契约不宣称能够回滚已安装的操作系统软件包。

Agent upgrade 保留现有预检、私有备份 manifest 和 JSON 结果契约。成功需要目标版本、配置不变、目标核心校验通过及服务 active；失败区分完整回滚、回滚失败和结果记录失败。Agent 的 `changed` 按其最终状态契约解释，不能直接套用其他操作 stderr 中同名字段的含义。

## RT-03：WARP 注册与本地凭据提交

POST 前在 `${SB_PROJECT_DIR}.warp-registration.pending.json` 写入私有 `sent` receipt。路径位于项目快照外，避免配置回滚丢失外部写入记录。POST 禁止自动重试。

DNS/建连失败或明确 HTTP 4xx 拒绝可以清理 receipt；请求可能已发送、超时、响应异常或服务端失败时保留 receipt，结果未对账前不能再次 POST。这是客户端防止重复发送的契约，不是提供商保证的分布式 exactly-once。不确定的远端结果必须由操作者对账，盲目删除 receipt 不是恢复流程。

校验 HTTP 状态、必要响应类型、地址族和三字节 client ID。取得合法响应后，原子保存 `received` 阶段及恢复数据。再次调用时验证保存的密钥对和响应，只重试本地保存，不再次注册。

凭据字段以不会被执行的 Bash 数据序列化，私有 staging 后校验语法，保存私有 `.bak`，原子发布并核对 hash 与权限。提交后校验失败或 rename 后信号恢复旧凭据。保存失败保留真实退出码，包括信号码；已接收结果继续保留以供恢复。日志不记录 Token、私钥或响应原文。

## RT-04：最新版本查询

查询使用私有临时文件、连接/总时限、响应大小限制和有界诊断。只接受包含稳定数字 release tag 的单个 JSON 对象。无效/多个文档、缺失/错误类型的 tag、预发布 tag、传输失败和非成功 HTTP 状态均明确分类。

普通失败显示 `unavailable` 并选择 `SB_SUPPORT_MAX_VERSION`；成功时仅对高于适配版本的结果警告。HUP/INT/TERM 及对应 curl 状态返回 129/130/143，保持 `SB_VERSION=latest`；安装/更新调用方据此停止，不在取消后继续按回退版本安装。

## 验证记录

最终真实核心 Docker 生命周期使用运行时 SHA-256：`420ea43d54daa0001dac04bacd917fb7beaadd53e8d32572ffbfe27dedeb81d1`，核对时与工作区逐字一致。后续仅版本元数据或文档变更，须满足 AGENTS.md 第 4.2 节才可复用结果。

| 证据 | 实际结果 | 本地产物 / 可复现检查 |
| --- | --- | --- |
| 二进制故障注入 | 传输 6/7/18/28；无效/穿越/链接/重复归档；错误可执行版本；prepare/commit/postcheck 故障；提交前后 TERM；旧文件不存在时回滚；回滚失败保留材料，均通过。 | `bash tests/binary_install_transactions.sh`；`/tmp/sbv-binary_install_transactions-final.log` |
| 更新故障注入 | 依赖/安装失败、配置意外变更和 TERM 均恢复文件且不意外重启目标服务；恢复原信号 trap。 | `bash tests/binary_update_transactions.sh`；`/tmp/sbv-binary_update_transactions-final.log` |
| 既有更新与 Agent 回归 | 安装元数据/运行库归属、配置保持、无效配置、重启失败/非 active、安装版本不符和 Agent 事务记录用例通过。 | `tests/update_binary_path_initializes_system_info.sh`、`tests/update_keeps_existing_config.sh`、`tests/update_skips_restart_when_config_invalid.sh`、两个 `tests/update_rolls_back_binary_when_*.sh`、`tests/agent_upgrade_commands.sh` |
| WARP 与版本 mock | 不确定 POST 不重发；received 恢复、响应校验、Token 惰性序列化、凭据回滚/rename 后信号和真实 writer 状态通过；版本传输/HTTP/JSON/回退/取消用例通过。 | `bash tests/warp_registration_transactions.sh`、`bash tests/latest_version_lookup.sh`、`tests/secret_diagnostics_redaction.sh`、`tests/register_warp_reregisters_when_client_id_missing.sh` |
| Ubuntu 22.04 / Rocky Linux 8 | 四项新增事务测试均在一次性容器通过。Rocky 使用 Bash 4.4.20、GNU coreutils 8.30。WARP/版本修复在两平台重跑，运行前后 hash 均为 `adf3ca63eff293eea1abcf576884781a6b0f98f6fe411925a7fa4f61c0d9d11d`；随后标准 Bash writer 状态传播修复由定向本地测试覆盖。 | `/tmp/sbv-platform-ubuntu.log`、`/tmp/sbv-platform-rocky-final.log`、`/tmp/sbv-platform-ubuntu-updated.log`、`/tmp/sbv-platform-rocky-updated.log` |
| 真实核心 Docker 生命周期 | HTTP 首装 1.14.2、拒绝 Agent 降级、实际 1.14.0→1.14.2 升级且配置不变/服务 active、精确 HTTP marker 均通过；注入目标版本重启失败后完整回滚到 1.14.0，再次 marker 通过。Agent 事务结果持久化，容器已删除。 | `/tmp/sbv-spec-binary-docker-v2/result.env` 为 `lifecycle_exit=0`；`agent-results/{downgrade,upgrade,rollback}.summary.json`；`upgraded/`、`rolled-back/` probe bundle；`/tmp/sbv-spec-binary-docker.sh` |

产物路径指向本轮私有本地验收记录，不是已发布的 Wiki 附件或永久外部存储。配置检查、本地 mock、平台行为、隔离数据面 marker、真实提供商效果和生产验收分别成立。本已完成契约不要求真实 WARP 账户写入或生产变更。

## 持续维护规则

后续修改受影响操作时保留上述断言，按 AGENTS.md 第 4.2 节的调用方和副作用选择验证。新增服务、网络、配置或外部写入行为补充相应验收，不把已完成清单扩张为全局重构，也不因改到 `install.sh` 就重测无关协议。
