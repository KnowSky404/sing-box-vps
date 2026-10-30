# SPEC 状态索引

[English](README.md)

核对基线为 2026-10-30 的仓库提交 `f498234`。两份 `unified-node-naming` 文档是同一项功能的中英文契约，不是两个尚未实现的计划；地址选择规范维护在 Wiki 源文件中，不在这里重复保存。

| 契约或目标 | 实现状态 | 证据与剩余边界 |
| --- | --- | --- |
| [统一节点命名](unified-node-naming.zh-CN.md)（[English](unified-node-naming.md)） | 已实现，并在记录范围内完成验收 | 第 9 节保留原本地/核心证据；第 10 节补充真实 SubMan 应用/存储联调（五协议 30 个节点）及所有者授权的生产 VMess API/Gist 验收（六个测试候选与一个测试聚合），确认身份/成员保留并清理测试记录。这不是生产代理 VPS 或所有协议公网验收。 |
| [SubMan 地址选择](../wiki/SubMan-Address-Selection.md) | 已实现，并在记录范围内完成验收 | 隔离地址族/失败回归与应用/存储联调覆盖 IPv4、IPv6、具体监听地址；命名第 10 节单列代表性生产 VMess 测试，地址选择不证明公网代理连接。 |
| [全协议/组件验收](full-protocol-completion.zh-CN.md)（[English](full-protocol-completion.md)） | 15 个预设和 38 个组件适配已实现；FP-01–FP-11 定向验收完成 | 有限 FP-01–FP-11 矩阵分别记录本地组件/分组、授权 Cloudflare、受控 Headscale/ocserv 验收与 namespace 构建限制。原生命周期和数据面证据保留在[上游矩阵](../wiki/Protocol-Coverage.md)，公网和生产验收分别记录。 |
| [运行时事务](runtime-transactions.zh-CN.md)（[English](runtime-transactions.md)） | RT-01–RT-04 已实现并完成定向验收 | 运行时契约记录有界二进制下载/更新、WARP 注册、最新版本查询、失败/回滚及相应隔离运行证据；外部账户与生产代理主机变更分别验收。 |

保留命名 SPEC，因为它定义后续修改仍需遵守的身份稳定、快照一致性、冲突处理及错误传递约束。第 9 节的旧实施步骤和中间 hash 属于历史证据，不是当前脚本版本，也不要求重复整套回归。当前版本见根目录 [README](../../README.md)，命令支持情况以 `sbv agent capabilities --json` 为准。

本地/mock、真实核心配置检查、隔离 Docker、真实外部服务写入、公网连接、生产验收、当前 head 审查/合并及 Wiki 发布分别记录，不能互相替代。审查与合并证据在对应 PR，Wiki 发布有独立仓库提交；文档清理不授权生产变更或真实 SubMan 写入。
