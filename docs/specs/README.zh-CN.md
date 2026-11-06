# SPEC 状态索引

[English](README.md)

既有验收记录的核对基线为 2026-10-30 的仓库提交 `f498234`；新增的默认监听契约单列其验收要求。两份 `unified-node-naming` 文档是同一项功能的中英文契约，不是两个尚未实现的计划；地址选择规范维护在 Wiki 源文件中，不在这里重复保存。

| 契约或目标 | 实现状态 | 证据与剩余边界 |
| --- | --- | --- |
| [TCP Fast Open 与 HY2 默认值](protocol-network-defaults.zh-CN.md) | 已实现；定向验证随 PR 记录 | TFO 兼容可选字段、已有值保护、HY2 默认 Salamander 和共享伪装网站检测；不表示生产或性能验收。 |
| [生命周期与验证技术债治理](technical-debt-remediation.zh-CN.md)（[English](technical-debt-remediation.md)） | TD-01–TD-06 已实现；定向宿主/Docker 验收通过 | TD-01–TD-06 覆盖卸载/服务保护、防火墙归属回收、SubMan 中断、定点 CI 和真实接管测试入口；本地、Docker 与交付证据分别记录。 |
| [Docker 定点验证](scoped-docker-verification.zh-CN.md)（[English](scoped-docker-verification.md)） | 已实现并验收：第二阶段 32 个独立场景及聚合兼容通过 | 独立出站/策略叶子、13 协议探针、Naive/Snell 转换及纯协议共存使用全新 SOCKS 前置。SPEC 记录 33 项运行态成功结果及场景耗时，计入内部安装，仅排除独立调度基线、最终 smoke 和传输；第一阶段历史、显式 REALITY/Tor、原默认全量及生产保持独立边界。 |
| [统一存储与迁移](unified-storage.zh-CN.md)（[English](unified-storage.md)） | 已实现 | 私有统一根、旧布局迁移/恢复及专用运行态验收；不代表生产已迁移。 |
| [AI Native 操作架构](ai-native-operations.zh-CN.md)（[English](ai-native-operations.md)） | 统一操作目录与安全接口已实现；定向验收通过 | 结构化分流/服务入口、生成命令参考与开发同步门禁；定向本地/运行态证据在契约中记录，审查、Wiki 和生产状态分别核对。 |
| [服务端网络管理精简](server-only-network.zh-CN.md)（[English](server-only-network.md)） | 已实现；分范围记录证据 | 199 项宿主检查及三组隔离服务/核心验收通过；完整注册 Docker、当前 head 审查及交付状态在实施 PR 分别记录。 |
| [默认双栈监听](default-dual-stack-listeners.zh-CN.md)（[English](default-dual-stack-listeners.md)） | 新建默认值契约；已定义验收要求 | 全部结构化实例新建默认单个 `::`；显式地址、已有实例及全局模式的 legacy 生成行为保持。须完成本地默认值矩阵、目标核心检查及代表性 TCP/UDP 双地址族运行态探针；本索引不宣称已完成验收或生产变更。 |
| [统一节点命名](unified-node-naming.zh-CN.md)（[English](unified-node-naming.md)） | 已实现，并在记录范围内完成验收 | 第 9 节保留原本地/核心证据；第 10 节补充真实 SubMan 应用/存储联调（五协议 30 个节点）及所有者授权的生产 VMess API/Gist 验收（六个测试候选与一个测试聚合），确认身份/成员保留并清理测试记录。这不是生产代理 VPS 或所有协议公网验收。 |
| [SubMan 地址选择](../wiki/SubMan-Address-Selection.md) | 已实现，并在记录范围内完成验收 | 隔离地址族/失败回归与应用/存储联调覆盖 IPv4、IPv6、具体监听地址；命名第 10 节单列代表性生产 VMess 测试，地址选择不证明公网代理连接。 |
| [全协议/组件验收](full-protocol-completion.zh-CN.md)（[English](full-protocol-completion.md)） | 15 个预设和 38 个组件适配已实现；FP-01–FP-11 定向验收完成 | 有限 FP-01–FP-11 矩阵分别记录本地组件/分组、授权 Cloudflare、受控 Headscale/ocserv 验收与 namespace 构建限制。原生命周期和数据面证据保留在[上游矩阵](../wiki/Protocol-Coverage.md)，公网和生产验收分别记录。 |
| [运行时事务](runtime-transactions.zh-CN.md)（[English](runtime-transactions.md)） | RT-01–RT-04 已实现并完成定向验收 | 运行时契约记录有界二进制下载/更新、WARP 注册、最新版本查询、失败/回滚及相应隔离运行证据；外部账户与生产代理主机变更分别验收。 |

保留命名 SPEC，因为它定义后续修改仍需遵守的身份稳定、快照一致性、冲突处理及错误传递约束。第 9 节的旧实施步骤和中间 hash 属于历史证据，不是当前脚本版本，也不要求重复整套回归。当前版本见根目录 [README](../../README.md)，操作面以 `sbv commands --json` 与 `sbv schema <operation-id> --json` 为准，产品能力保留 `sbv agent capabilities --json`。

本地/mock、真实核心配置检查、隔离 Docker、真实外部服务写入、公网连接、生产验收、当前 head 审查/合并及 Wiki 发布分别记录，不能互相替代。审查与合并证据在对应 PR，Wiki 发布有独立仓库提交；文档清理不授权生产变更或真实 SubMan 写入。
