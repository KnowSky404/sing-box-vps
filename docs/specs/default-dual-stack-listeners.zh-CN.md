# 默认双栈监听契约

[English](default-dual-stack-listeners.md) · [SPEC 索引](README.zh-CN.md)

本契约定义新建服务端监听的默认值。下列验证内容是验收要求，不表示已完成测试、审查、合并、Wiki 发布或生产变更。

## 新建与已有配置保留

结构化 Mixed、SOCKS、HTTP、Shadowsocks、Trojan、VMess、普通 VLESS、AnyTLS、Hysteria2、Snell、TUIC、Hysteria、NaiveProxy 与 ShadowTLS 外层实例，在创建和追加安装菜单中默认使用 `listen.address:"::"`。全部 15 个协议预设的首次安装默认变量采用同一地址。Linux 上沿用项目的 sing-box TCP/UDP 双栈 socket 模型：单个 `::` 监听同时接受 IPv4 和 IPv6，等效接收 IPv4 通配 `0.0.0.0` 与 IPv6 通配 `::` 的连接。不得在同一端口额外添加 `0.0.0.0` 监听，以免 socket 冲突。

REALITY 与 legacy 单实例生成器的实际监听仍由全局入站模式决定。双栈主机全新安装默认 `dual_stack`；已有显式模式及单栈主机的回退行为保持原样。修改新建默认值不迁移已有状态，也不扩大已有实例的监听范围。

修改实例时，监听地址输入留空保留已存地址。显式 IPv4、IPv6 与回环输入具有优先权。Agent `create`/`replace` 必须提供完整私有 typed record，并保留显式 `listen.address`，不会使用交互默认值填补缺失字段。能力元数据同步描述新默认值；公网暴露确认和 `--allow-public` 要求继续生效。

ShadowTLS 内部 Mixed detour、客户端本地代理监听、本地管理 API 及高级组件的默认监听继续保持原有回环语义。本次不引入核心版本、状态格式、凭据、端口或 TLS 迁移。

## SubMan 与验收

[SubMan 地址选择](../wiki/SubMan-Address-Selection.md)继续遵循各实例的实际监听。对已支持的协议，`::` 在两族探测分别成功时可生成独立 IPv4、IPv6 候选；显式 `0.0.0.0` 仍仅发布 IPv4。HY2 连接选定 IP，同时保留配置域名作为 SNI。监听默认值不新增 SubMan 协议支持，不删除远端节点，也不证明公网可达。

验收必须覆盖全部结构化协议的新建默认值与首次安装预设默认值、显式地址和 replace 保留、能力元数据、SubMan 地址族选择、ShadowTLS 内层及客户端回环保留。生成的服务端和客户端输出必须通过目标核心 `sing-box check`；隔离 Linux 运行态探针必须覆盖代表性 TCP、UDP 监听的 IPv4 与 IPv6 连接。按 AGENTS.md 第 4.2 节选择最小充分本地与 Docker 范围。本地/mock、核心检查、Docker、真实 SubMan、公网及生产证据分别记录；本次不授权生产修改。
