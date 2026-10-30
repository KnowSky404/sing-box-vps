# SPEC 状态索引

[English](README.md)

核对基线为 2026-10-30 的仓库提交 `c652169`。两份 `unified-node-naming` 文档是同一项功能的中英文契约，不是两个尚未实现的计划；地址选择规范维护在 Wiki 源文件中，不在这里重复保存。

| 契约或目标 | 实现状态 | 证据与剩余边界 |
| --- | --- | --- |
| [统一节点命名](unified-node-naming.zh-CN.md)（[English](unified-node-naming.md)） | 已实现，包含审查修复 | 第 9 节记录选定本地/mock 集合、受影响补充验证及真实 sing-box 1.14.2 配置检查；最终运行时 SHA-256 与基线 `install.sh` 一致。该集合未执行真实 SubMan 节点 ID/聚合成员保留或生产验收。 |
| [SubMan 地址选择](../wiki/SubMan-Address-Selection.md) | 已实现，监听地址与地址族契约继续有效 | `public_ip_detection.sh`、`subman_address_selection.sh` 及受影响 SubMan payload/API/编排测试覆盖隔离输入与失败分支；命名第 9 节包含历史 SubMan 回归结果。候选选择不证明公网连接或真实 SubMan 同步。 |
| [全协议/组件目标](../wiki/Protocol-Coverage.md) | 部分验证，不能整体宣称完成 | 生命周期和数据面证据按矩阵行及日期切片记录。Tailscale/OpenConnect 等外部控制面路径仍有认证及运行条件；公网和生产验收分别记录。 |
| [事务后续项](../wiki/Transactions.md#后续迁移清单) | 部分路径仍待统一 | 二进制下载时限与错误上下文、WARP 操作边界及剩余错误分类须结合当前调用方核对后再修改；已有防护不再作为待实现项。 |

保留命名 SPEC，因为它定义后续修改仍需遵守的身份稳定、快照一致性、冲突处理及错误传递约束。第 9 节的旧实施步骤和中间 hash 属于历史证据，不是当前脚本版本，也不要求重复整套回归。当前版本见根目录 [README](../../README.md)，命令支持情况以 `sbv agent capabilities --json` 为准。

本地/mock、真实核心配置检查、隔离 Docker、真实外部服务写入、公网连接、生产验收、当前 head 审查/合并及 Wiki 发布分别记录，不能互相替代。审查与合并证据在对应 PR，Wiki 发布有独立仓库提交；文档清理不授权生产变更或真实 SubMan 写入。
