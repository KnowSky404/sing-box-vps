# 统一协议管理：公共契约与增量状态设计

对应[完整实施记录](../plans/2026-09-06-unified-protocol-management.md)和[固定版本能力核对](2026-09-06-protocol-coverage.md)。运行时继续由独立的 `install.sh` 提供，不能依赖研发目录。

## 第一阶段已实现的公共契约

`SB_PROTOCOL_REGISTRY` 仅登记已有实际适配器的四个产品预设。它不是上游全部 type 的可用列表；尚未实现的能力在覆盖矩阵单独说明。

| 旧输入/alias | state_id | runtime_id | agent_id | family / preset | 上游角色/type |
|---|---|---|---|---|---|
| `vless`、`vless+reality`、`vless-reality` | `vless-reality` | `vless+reality` | `vless-reality` | vless / reality | inbound / vless |
| `mixed` | `mixed` | `mixed` | `mixed` | mixed / plain | inbound / mixed |
| `hy2`、`hysteria2` | `hy2` | `hy2` | `hysteria2` | hysteria2 / tls | inbound / hysteria2 |
| `anytls` | `anytls` | `anytls` | `anytls` | anytls / tls | inbound / anytls |

不能修改 `vless` 历史别名的含义来接入普通 VLESS。后续普通 VLESS 将使用独立的 preset/state ID，配置识别还必须检查完整 TLS/transport 对象。

注册表行是脚本内可信常量，以 `|` 分字段，列表以逗号分隔；显示文字不能包含分隔符。`protocol_registry_field` 提供 Bash 侧的命名字段查询，`protocol_registry_json` 提供结构化视图。这样安装前的 ID 查询不依赖 jq，也不从用户字符串执行函数。handler 分发表保持显式 `case` 调用；登记的 handler 名称仅用于 `declare -F` 完整性检查。

共用方包括：ID 归一化、运行时/Agent ID、显示名和默认 tag、安装菜单编号、客户端候选、SubMan 类型、Agent capabilities、Docker 探测支持判断和服务端 type 映射。具体协议的渲染、认证和连接探测仍需独立实现，不能仅增加一行元数据。

Agent 保留原 `protocols` 对象，增加 `protocol_registry`。当前实例是否具备二进制、构建标签、库、证书、端口和授权端点需要预检，因此静态元数据返回 `available=null`。同样，`validated.status=not_assessed` 不能解释为连接通过；运行证据应来自对应本次场景 artifact。`minimum_project_core` 是项目兼容范围，不是协议在上游历史上首次发布的版本。

片段边界如下：

- inbound handler 必须返回至少一个带非空 tag、type 匹配的 JSON 对象；空成功、日志混入、错误 type 和缺失 handler 都失败。
- certificate handler 的 `none` 契约允许无输出；`optional` 表示手工证书时无 provider，ACME 模式返回带 type/tag 的 provider 对象。不能用这个契约掩盖需要生成的 provider 缺失，具体 TLS 模式仍由对应 handler 和目标核心检查负责。
- route handler 必须返回且仅返回一个 JSON 数组；没有规则时显式返回 `[]`。
- 生成器先捕获完整协议发现结果并检查退出状态，然后准备候选。发现中途失败即使已经输出部分协议，也不会发布部分配置。
- 未知索引条目、未知索引版本和未知旧协议状态版本阻断协调/重建，文件保留并提示恢复兼容脚本。
- 索引存在但 live inbound 的状态文件缺失时，普通枚举不能删掉该索引条目。追加安装保留旧单 Mixed 自动恢复路径：仅当目录中只剩索引、默认 tag/监听及至多一个用户均可由旧格式表达时才重建状态；失败由既有重建事务恢复索引。自定义 tag/监听、多用户和新字段留待显式接管，不以丢字段方式迁移。

## 第二阶段：候选配置引用预检

`validate_managed_component_graph` 在服务端 candidate 完成后、目标核心 `check`、备份及发布之前运行；客户端交互和 Agent 导出在同一校验入口执行。失败由既有事务恢复生成器副作用，保留 live 配置、旧备份和导出文件。它只读一次候选 JSON，没有账户注册、凭据生成、状态写入或网络操作；错误只包含固定分类，不输出 tag、路径或 JSON 原文。

组件 tag 在 inbounds/outbounds/endpoints 之间唯一，Endpoint 可以被对应入站/出站引用。这是项目生成约束，不是上游允许配置的完整定义；不会据此重命名或拒绝只读检查中的旧配置。DNS、证书 provider、HTTP client、rule-set 和网络命名空间使用独立 tag 空间，不能因同名而误判重复或成环。受管组件要求显式非空 tag；证书与 DNS 保留上游允许的旧位置编号引用。

预检覆盖 detour、selector/urltest 成员及默认选择、route/DNS 的逻辑规则树、rule-set、证书与 inline/named HTTP client、显式 DNS resolver 和必要 Endpoint 引用。引用存在性与依赖边分开：普通路由匹配只检查引用，不当作启动环；普通出站的 resolver 仅在固定域名服务器等明确需要解析的位置产生依赖边，避免把 IP DNS 经 direct 的合法配置误判为循环。DNS transport 自身的显式 resolver 则按核心 manager 语义始终产生启动依赖，即使服务器为 IP。共享 selector DAG 使用邻接表和拓扑消除，不枚举全部路径。

此处不是完整 sing-box schema 实现，也不是外部配置 allowlist 或新的 JSON 透传管理入口。目标版本字段、构建依赖及协议参数仍必须通过真实核心 `check`；动态路由/透明接入的数据面环路必须通过后续资源预检和隔离连接验证。

### 现有入站清单保护

`validate_live_inbound_inventory` 是只读、无网络/状态写入的前置门禁；接受单个 JSON 对象中的入站数组，使用同一注册表的核心 `type`、`preset` 和 `multi_instance` 能力识别全部入站。未知类型、非 REALITY VLESS、重复的单实例协议、重复的非空显式 tag 或无法解析的清单均以固定脱敏分类失败。CLI 的历史 `vless` alias 含义不变，但不能拿这个 alias 将任意 live VLESS 认作 REALITY；上游两个开关默认均为 `false`，所以只有 `tls.enabled=true` 且 `tls.reality.enabled=true` 才是可接管的旧 REALITY 预设。

枚举必须全量成功后才输出清单；状态比较捕获退出码，不经进程替换吞掉失败。索引协调、健康判定、自动修复、接管和生成入口在修改/准备前检查。Agent 的 `status`、`nodes`、`links` 不输出未知 live 入站对应的部分清单；规范化索引必须与 live 协议集合完全一致且无重复，基础状态必须存在、可识别且没有孤立条目，失败分别返回 `protocol_index_untrusted` 或 `protocol_state_untrusted`。旧版 REALITY 状态必须在原始文件中具备安装标记、节点名、合法端口、UUID、SNI、密钥和 Short ID，不能用加载器默认值补成虚假节点；schema 2 的默认实例和实例清单必须有效，目录中的 `.env` 文件、文件名、内部 `INSTANCE_ID`、完整连接字段、有效 inbound tag 与 live VLESS tag 集合必须一一对应。三项 Agent 命令共享同一个只读验证器；`nodes`/`links` 还会在公网地址读取前捕获清单，并在任一状态加载或最终状态恢复失败时丢弃已经渲染的全部节点。失败不重写 live 配置、备份或状态，接管诊断也不再输出包含密码、UUID、私钥和 token 的原始快照。

这是清单层保护，不是字段的语义往返证明。额外用户、未建模参数以及出站、端点、DNS、证书与路由的完整可恢复性仍需后续保护；通用实例和删除引用保护也仍在下节的待实现范围。

## 后续通用实例与组合设计（尚未实现）

已实现的 REALITY 兼容基础：显式状态重建先读取旧受管实例元数据，再以有效 inbound tag 关联 live 入站。成功关联时保留稳定 ID、默认实例、节点名称及上下行 QoS；连接参数和可表示的路由策略按 live 配置恢复。私钥相同时复用旧公钥，歧义映射、无效 QoS 或未知状态版本拒绝重建。此机制同样用于期望状态比较，避免自定义 ID 在健康检查中被重命名；通用多协议实例模型仍待推广。

现有 `.env` 和 `vless-reality.d/*.env` 继续兼容读取，不做启动时全量迁移。新增实例采用同目录内可按实例备份的结构化数据状态；导入先经过字段 allowlist、类型和引用校验，不能 source 外部数据。状态需包含版本、稳定 ID、family/preset/role、名称、固定 tag、监听、认证、TLS/transport、出站策略及组件依赖。读、渲染、展示和导出不创建新的 UUID/密码/密钥。

迁移时以原 tag 和原实例 ID 为依据，保留路由引用、名称、端口、凭据、ShortID、QoS 与出站策略。对无法完整识别的 inbound/outbound/endpoint/rule、额外字段或更新格式，必须先保留并阻断有损发布，不能过滤掉后声称兼容。

组件构造按 role 分别输出 inbounds、outbounds、endpoints、route、certificate_providers、http_clients。依赖由稳定 ID 映射到固定 tag；检查全局 tag 唯一、引用存在、成员和 detour 环、依赖共享与删除保护。ShadowTLS 的内层/包装层作为一个受管组合准备、导出和回滚。通用 WireGuard 不调用 Warp 注册。

## 资源与事务扩展（尚未实现）

复用 `create_managed_state_snapshot`、配置 candidate 校验与原子发布边界，补上写锁、持久事务结果和受管资源清单。清单至少记录地址/地址族/传输/端口/实例归属、证书与组件引用、运行库、受管防火墙/QoS/路由规则及原服务活动状态。

事务依次执行资源计划、锁、持久快照、材料准备、候选状态、jq/目标核心 check、配置与资源发布、服务健康检查、提交。失败分别恢复文件和外部副作用，记录原始错误、失败阶段和是否需要人工介入；不能将目录恢复等同于全部系统资源已恢复。SIGINT/TERM/HUP 清理；SIGKILL/掉电由后续入口发现未完成持久事务。

精确端口规划区分 TCP/UDP 和 IPv4/IPv6 通配及双栈绑定。Mixed/SOCKS 只有 TCP 固定监听，UDP associate 属于业务能力；Hysteria2 的固定监听为 UDP。共享证书、端口和依赖组件按引用计数保护，卸载不清理不属于本项目的资源。

## SubMan 契约核对

本轮只读核对了本地 SubMan 的 `docs/api/openapi.yaml`、`src/lib/server/api/nodes.ts`、`docs/sing-box-export.md`；未修改该仓库或调用生产接口。

`PUT /api/nodes/by-key/{externalKey}` 请求必需 `name/type/raw`，可选 `tags/enabled/source`。API type 白名单为 `vless/vmess/trojan/ss/ssr/hysteria2/tuic/anytls/other`，但接受 raw 字符串不代表可无损导出。SS 的 API type 是 `ss`，不能直接发送 `shadowsocks`。SSR 在目标导出层被明确跳过；Mixed、高级接入和 Endpoint 不应伪装为 `other` 以宣称同步支持。

保留 revision、If-Match、提交确认和回读语义。未知写结果先 GET，不盲目重复 PUT。后续扩大协议时必须核对 URI 可表达字段、私有证书信任和 client_metadata 等限制；单节点不适配要报告 unsupported/skipped/warning，而不是丢参数或影响其他可同步节点。

## 未来协议扩展示例

以普通 VLESS 为例，交付需要同时完成以下内容：

1. 选择不会改变旧 alias 的新 preset ID，登记 role、family、版本/构建要求、监听/业务能力、分享/导出/SubMan 状态。
2. 明确普通 TCP/TLS/WS/HTTP/gRPC/HTTPUpgrade/QUIC 可用组合；不能把 REALITY 当任意协议的 TLS 开关。对应字段以 `v1.14.0/option/v2ray_transport.go` 和实际核心为准。
3. 实例参数校验、材料准备、安全状态写入、旧配置接管、编辑与删除 handler；未知字段阻断有损重建。
4. 纯配置构造、route/provider 明确空契约、客户端构造和 URI 保真 warning；所有产物由目标核心 check。
5. 菜单和 Agent 非交互参数、摘要脱敏、完整 links/export-client 敏感输出、SubMan 契约载荷。
6. 混合多实例生命周期、监听/引用冲突、失败回滚、并发和信号测试，以及实际 TCP/UDP 数据闭环。

完成前不得标记为已实现或已验证。每次原子提交之后审查实际提交范围；当前工具没有 `/review` 入口时记录等效代码审查，不声称已调用该命令。
