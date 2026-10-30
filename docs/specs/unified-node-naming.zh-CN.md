# 实例与节点统一命名 SPEC

[English](unified-node-naming.md)

状态：已实现并通过本文契约验收。第 9 节保留历史本地/mock 和目标核心检查，第 10 节记录真实应用/存储联调及已明确授权的生产 SubMan 身份与聚合保留验收。协议与事务契约分别见 [SPEC 状态索引](README.zh-CN.md)。

## 1. 问题与目标

早期展示路径在保存的节点名称后追加带宽和地址族后缀；新增的结构化多用户协议则独立使用主机前缀、协议、实例 ID 和用户摘要生成 SubMan 名称。本地分享链接还可能追加内部 outbound tag。因此，修改实例名称后，SubMan 名称可能不变，同一候选在分享和同步中也可能使用不同名字。

以保存的实例名称作为人类可读的基础名称。分享和 SubMan 候选必须由同一个格式化器、同一份已捕获实例数据生成名称。显示名称与身份分离，使改名可以更新原有远端节点。

## 2. 范围与身份边界

| 字段 | 职责 | 兼容要求 |
| --- | --- | --- |
| 实例 `id` | 定位、更新本地实例 | 保留原值 |
| 实例 `name` | 人类可读的基础名称 | 保留原值；通过现有实例管理修改 |
| 认证用户名 | 稳定用户身份 | 保留；不通过显示名规范化修改用户身份 |
| 入口、客户端 outbound `tag` | 配置身份和引用 | 保留原值及构造规则 |
| links map 的 key | 关联 outbound 与分享材料 | 保留技术 key |
| 候选显示名 | 区分导出的用户、地址候选 | 从捕获的实例生成 |
| SubMan `externalKey` | 更新同一个远端节点 | 保留各协议现有格式 |

本地实例统一命名覆盖已支持的协议；SubMan 同步继续以协议注册表的能力为准。本次不新增 URI 格式，不改变分享条件，也不扩大可同步协议范围。

本次不新增用户显示别名字段、不迁移实例状态、不自动删除远端节点、不修改生产主机，也不自动重新发布订阅。现有生成配置的技术 tag 及其引用保持稳定。

## 3. 新建实例默认名

新建交互实例采用：

```text
<主机显示标签>-<规范协议 ID>-<序号>
```

示例：`fra-01-vless-reality-01`、`fra-01-vless-plain-01`、`fra-01-hy2-01`、`fra-01-trojan-01`。

1. 使用注册表的规范协议 ID，明确区分 `vless-reality` 与 `vless-plain`；旧 CLI 别名 `vless` 不变。
2. 从已捕获的协议实例清单中，选取第一个尚未使用的生成名称；序号从 1 开始，至少两位。
3. 创建时保存选定或用户输入的名称；主机标签、hostname、默认实例或清单顺序变化时，不重新计算已保存名称。
4. 删除实例不重新编号其他实例。后续创建可以复用空闲名称；名称不是身份分配账本。
5. 已有名称、ID 分配规则和旧状态恢复、迁移时的回退名称不变。不从用户名称反向推断 ID。

可选设置 `/root/sing-box-vps/node-naming.json`：

```json
{"host_label":"fra-01"}
```

对象仅接受 `host_label` 字段。主机标签去除首尾空白后必须非空、为 UTF-8、不含控制字符且不超过 128 UTF-8 字节。文件不存在时使用当前 hostname；文件存在但格式无效或不安全时明确失败，不静默使用另一个默认值。全新安装既没有该文件也没有现有实例清单时，首个默认名仅依赖 Shell 和 hostname，不得在原依赖安装阶段之前要求 `jq`；读取已有 JSON 偏好或清单时明确依赖 `jq`，缺失时给出清晰提示。本功能不调整依赖安装顺序。主菜单 **11 → 5「设置新实例的主机显示标签」** 独立提供该显示设置，与 **11 → 4** 的 SubMan 连接设置分开。

保存时先暂存、校验 JSON，已有文件备份为 `.bak`，再以私有权限原子替换。失败后原设置应继续可用。修改仅影响后续新建实例默认名，不重写已有实例、不重启核心、不联系 SubMan。

## 4. 共用候选名称生成

结构化格式化器显式接收：

```text
structured_node_display_name(protocol, snapshot_json, instance_id, user_name, address_label[, prepared_context])
```

snapshot 为调用方已经捕获、校验的不可变清单；不得逐用户重新读取可变状态文件、加载其他实例，或从无关 `SB_*` 全局变量获取结构化带宽值。可选第六个参数为从同一 snapshot 和选定实例预先生成的命名上下文；每个实例只准备一次用户摘要映射，再由各候选复用，避免在每个用户循环里重新计算其他用户摘要。上下文显式传递身份及规范化信息，不增加可变全局缓存，也不跨 snapshot 或实例复用。

按以下顺序组合：

```text
<实例名称>[-i-<实例摘要>][-u-<用户摘要>][-U<上行>M][-D<下行>M][-v4|-v6]
```

- **基础名称**：从已保存实例 `name` 派生，仅按与 SubMan 一致的 ECMAScript `String.prototype.trim()` 语义去除首尾空白；先去除首尾空白，再检查剩余基础名的 ASCII 控制字符，因此保存值 `"\tCustom\t"` 渲染为 `Custom`，但中间仍含 Tab 时失败。合法名称的中间字符和已保存值保留，去除后为空则失败。精确空白集合为 U+0009–U+000D、U+0020、U+00A0、U+1680、U+2000–U+200A、U+2028、U+2029、U+202F、U+205F、U+3000、U+FEFF；U+0085 保留。不将基础名替换为 SubMan 前缀、协议名、ID 或技术 tag。
- **同名实例**：使用相同的 ECMAScript 首尾空白规则比较基础名；同一 snapshot 中多个实例具有相同规范化基础名时，各候选追加 `-i-` 和 `<规范协议 ID>:<实例 ID>` 的 SHA-256 前 12 位十六进制摘要。
- **用户**：仅当实例配置了多个逻辑凭据时，追加 `-u-` 和用户名 SHA-256 的至少前 12 位十六进制摘要；若该前缀与同实例已配置的其他用户冲突，则每次增加 4 位，直到该实例内可区分；完整摘要仍冲突时失败。Shadowsocks 无逐用户记录时计为一个逻辑凭据。单凭据不显示 `single-<摘要>`。计数包括因 URI 条件不满足而跳过的其他用户，避免过滤结果使同一候选改名；用户排序不改变摘要。
- **带宽**：保留 REALITY 限速和 HY2 带宽元数据的 `U...M`、`D...M` 写法；结构化 HY2 从捕获的实例读取。两者保持各自协议语义，不把 HY2 带宽元数据解释为保证的流量限速。
- **地址族**：沿用 `IPv4`、`IPv6` 候选标签转换。具体绑定地址使用原来的监听地址标签，因此不增加地址族后缀；不得从 IP 推导新的 externalKey 后缀。

同一候选的 URI fragment（VMess 为 `ps`）与 SubMan payload `name` 必须一致。本地分享和专用 SubMan 路径仅共享命名，保留各自现有信任要求、可保真表达条件、长度、警告和跳过规则。若某个现有分享生成器不能直接消费捕获的 snapshot，则接受输出前重新核对清单；并发变化可能混合名称和其他凭据时，明确失败。

实例摘要仍表示实例，不表示其多个用户、地址候选之一。菜单和 Agent 摘要保留这种区别；实际分享材料展示候选名称。links map 的技术 key 和客户端 outbound tag 不转换为显示名称。

## 5. 长度与冲突

最终候选名称包含全部后缀，最多 **256 UTF-8 字节**。先计算后缀；完整名称过长时，仅在 Unicode 码点边界缩短渲染出来的基础名，并在后缀前增加 `-n-<摘要>`。摘要为未缩短完整候选名的 SHA-256 前 12 位十六进制字符。缩短前为摘要和全部后缀预留字节。

不得修改已保存名称、移除区分后缀或截断 `externalKey`。摘要提供实用的确定性区分，不构成数学上的绝对唯一保证。

其他协议、机器或手工维护的远端节点不在本地 snapshot 的冲突清单中；继续使用 SubMan 现有重名处理，以返回名称为准，不声称本地格式化能避免所有远端冲突。

## 6. SubMan 设置与更新

保留 `SUBMAN_NODE_PREFIX` 字段、原值及现有键格式；界面名称改为 **同步身份前缀**，说明修改会改变 externalKey、保留旧节点。它与主机显示标签独立。

显示改名后保持原候选 externalKey。下一次明确执行同步时，如果原节点存在，使用 by-key PUT 更新原节点，不先删除再重建。Workspace 校验、119 字节外部键上限、条件操作和写入结果不确定时的回读对账保持不变。

远端节点 ID 和聚合引用是否保留，需要在联调中核实，不能从 mock 名称比较推断。保存显示或连接设置不推送节点；节点 API 同步不自动重新发布以前生成的订阅、客户端产物。

## 7. 实现顺序

1. 增加纯格式化器、长度处理、新建默认名 helper 和可选主机标签设置；保留旧回退与身份函数。
2. 将结构化本地分享及所有当前 SubMan 推送路径接入 snapshot 命名；技术 tag 和分享条件不变。
3. 更新新建默认名、设置文案和操作文档，完成定向兼容回归。
4. 本轮脚本版本只同步递增一次；完成当前 HEAD 本地审查后创建 PR；当前 head 远程安全审查及仓库门禁满足后再合并。

## 8. 验收与验证

必须覆盖：

- 新建默认名区分协议、实例并使用主机标签。
- 无偏好文件和实例清单时，全新默认名在未安装 `jq` 前也可生成；已有 JSON 偏好、清单缺少解析器时明确提示。
- 128 用户实例复用预先准备的摘要上下文，输出与未准备上下文时一致，避免逐候选重复计算其他用户摘要。
- 标签只影响未来默认名；无文件使用 hostname，无效文件失败，保存失败保留原文件。
- 已有自定义名称成为实际分享和 SubMan 名称的基础。
- 单用户、多用户、用户重排、跳过其他用户符合规则；Shadowsocks 零用户记录凭据不增加无意义后缀。
- 仅渲染基础名按 ECMAScript 去除首尾空白；U+FEFF 去除，U+0085 保留，仅含空白则失败；snapshot 内规范化后同名实例获得确定性实例后缀。
- 用户短摘要冲突时确定性扩展，externalKey 不变，也不依赖用户顺序。
- 结构化 HY2 带宽来自捕获实例，不受残留全局变量影响。
- IPv4、IPv6 和具体监听地址保留现有地址、外部键语义。
- 中文、emoji 保持合法 UTF-8，最终名不超过 256 字节；缩短不改保存值、不丢失区分后缀。
- 修改基础名后，实例、用户 ID、externalKey、技术 tag、links map key、凭据及配置引用保持不变。
- 同一捕获候选的 URI 备注、VMess `ps` 与 payload 名称一致。
- 分享信任、跳过条件、API 失败处理和 snapshot 一致性继续由现有回归覆盖。

执行新格式化器、默认名、设置测试，修改的交互测试，实际结构化分享入口测试，定向 SubMan payload、API、编排测试，以及文档、版本和语法检查。若受影响生成配置内容发生变化，对相应输出执行目标 `sing-box check`；若实现改变安装控制流、服务、网络或生命周期行为，按 AGENTS.md 第 4.2 节追加对应 Docker 场景。仅命名不要求无关协议矩阵或完整发布验收。

本地、mock、真实核心校验、Docker、真实 SubMan 联调、生产验收及 Wiki 发布分别记录。本文本身不证明这些检查或远端操作已经完成。

## 9. 实现与验证记录

本次实现版本为 `2026103003`，基线为 `061bc8e8f3c68b574b3ee6ad902abaa2b8761077`。
此前已验证运行时 SHA-256：`93eeb20a4869e089fb3b9db4f904c337f4b04600cf6748a96db5e250851df465`。
第一次审查修复后的运行时 SHA-256：`ac37a4caf8cc242937e3dafd2626d6110f57a175567897b9c1fc911b7041d556`。
最终运行时 SHA-256：`bbff3f359dc53538c7e45eafab75d61ad22628200db737cf583735920eb81103`。

选定本地检查 **35/35 通过**，合计 608 秒：

| 范围 | 已完成检查 |
| --- | --- |
| 命名契约与集成 | `node_naming_contract.sh`、`node_naming_settings.sh`、`node_naming_creation_defaults.sh`、`node_naming_share_subman_parity.sh`、`node_naming_generic_payload.sh` |
| 原默认名与展示 | `default_node_names_follow_hostname_protocol_format.sh`、`vless_reality_new_instance_default_node_name.sh`、`install_prompts_include_protocol_name.sh`、`node_info_action_menu_renders.sh`、`unified_node_display_names.sh` |
| 受影响创建菜单 | Mixed、SOCKS、HTTP、Shadowsocks、Trojan 的 `*_instance_menu.sh`，以及 `hy2_instance_acme_menu.sh` |
| 原真实分享调用方 | Trojan、VMess、普通 VLESS、Shadowsocks 的 `*_agent_share.sh`，以及 `structured_hy2_instance_management.sh` |
| SubMan | 全部十个 `tests/subman_*.sh`：地址选择、API、配置、payload、重配、Shadowsocks、同步编排、Trojan、普通 VLESS、VMess |
| 核心与配置边界 | `export_client_config_1_14_compatibility.sh` 使用真实 sing-box **1.14.2** 检查生成的旧 HY2 客户端配置；结构化配置序列化器和技术 tag 生成规则未改动，另有旧长 tag 保留断言 |
| 文档与版本 | `wiki_documentation.sh`、`readme_mentions_current_versions.sh`、`version_metadata_is_consistent.sh`，以及 `bash -n install.sh` |

完整选定集合最初对应运行时 SHA-256
`bc957b86801f7510d821ebb78c273ea1eb7f05785e746e8128b69e30c4322673`。
审查前补充了设置边界：拒绝非普通文件的配置/备份路径，并在无效标签阻止默认名生成时明确提示。
命名契约、设置和创建默认名三项在上述此前已验证运行时重新通过；当时其余受测命名、分享、API 代码及依赖未变，因此复用了原结果。
原提示测试在基线分支也缺少最后的伪装地址回答，本次已补齐 fixture。

本轮未执行 Docker 运行态、真实 SubMan 写入、实际远端节点 ID/聚合成员保留验收、生产验收或自动重新发布。
未改变监听、凭据、服务生命周期或执行状态迁移。本地 mock 和核心配置检查不能替代这些独立边界。

当前 HEAD 的本地审查、远程安全审查和合并记录在对应 PR；Wiki 发布记录在其独立提交。
门禁记录与本文行为证据分开维护，避免为了记录被审查提交的 SHA 而再次改变被审查的 head。

### 本地审查后的补充验证

对 `ff125e9` 的本地审查确认三项问题：首次安装 Mixed 时默认名提前依赖 `jq`、128 用户重复计算其他用户摘要，以及合法首尾制表符在清理前被拒绝。
三项均已修复，**21 项受影响检查在上述第一次审查修复后的运行时通过**：

- 父代理执行六个 `node_naming_*.sh`（含新增 `node_naming_fresh_dependencies.sh`）、五项原默认名/展示/交互检查，以及三项文档/版本检查。
- 独立执行 `subman_shadowsocks_sync.sh`、`subman_trojan_sync.sh`、`subman_vmess_sync.sh`、`subman_vless_plain_sync.sh`、`subman_sync_orchestration.sh`、`shadowsocks_agent_share.sh`、`structured_hy2_instance_management.sh`，对应同一份冻结运行时。
- 128 用户契约确认准备阶段仅计算 128 次原始用户摘要，随后 128 个候选渲染不重复计算原始用户摘要；覆盖唯一名字、用户重排和无效上下文拒绝。
- 四协议真实通用分享/payload fixture 保留带首尾制表符的存储名称，渲染时去除边缘空白；NUL 和内部控制字符继续拒绝。
- 独立命名合成基准生成 128 个唯一名字，共 256 次 SHA 调用：128 次用户摘要和 128 次最终显示名摘要。准备与渲染合计 **10.539 秒**，审查复现约 **110 秒**。这不是端到端同步耗时。

复用此前核心配置检查：本次修复只调整默认名计算、显示名准备和空白处理，未改变客户端 JSON 序列化器或技术 tag 构造。
推送前仍须对最终 HEAD 重新本地审查；结果及远程安全门禁记录在 PR。

### 旧路径错误传递验证

对 `fa4d33a` 的审查又复现一项旧路径问题：名称被拒绝后，调用方仍可能生成空 URI 备注或回退 payload 名称。
最终运行时在旧 REALITY、schema-1 HY2 的 URI 构建器、通用 payload/Agent、链接/二维码菜单和组合展示模式传递失败。
被拒绝的 URI 不会传给 `qrencode`，也不会写入 SubMan。

以下八项检查在最终运行时
`bbff3f359dc53538c7e45eafab75d61ad22628200db737cf583735920eb81103` 通过：
`node_naming_legacy_failures.sh`、`unified_node_display_names.sh`、`subman_payload_generation.sh`、
`subman_sync_orchestration.sh`、`agent_cli_outputs_machine_readable_node_info.sh`、
`agent_cli_multi_instance_status.sh`、`vless_reality_node_info_shows_instances.sh` 和
`export_client_config_1_14_compatibility.sh`（再次使用真实 sing-box 1.14.2）。
新增回归对每个旧协议覆盖有效名称及五种拒绝名称、条件调用中显式失败、机器输出不部分成功、无无效同步写入，以及链接/二维码/组合菜单行为。

摘要上下文、结构化分享和默认名代码与 21 项补充检查对应内容未变，复用其结果。
语法和文档检查也通过。最终完整分支审查和远程安全证据按精确 head 记录在 PR。

## 10. 真实应用与已授权生产验收

2026-10-30 使用 `tests/integration_subman_app.sh`、私密 helper 和带显式生产门禁的
`tests/integration_subman_production.mjs` 完成命名及地址选择验收。

隔离联调运行 SubMan 提交 `ed6fa5a9b353fb7cf355552eff16c63b417c01c2` 的真实 Worker
HTTP 路由和 SQLite Durable Object，只有 GitHub Gist 传输使用隔离对端，不将其称为真实
GitHub 联调。Shadowsocks、Trojan、VMess、普通 VLESS、HY2 五协议，各覆盖两个用户及
IPv4/IPv6/具体监听地址，共生成 30 个由应用分配 ID 的节点。改名并同步后，30 个节点
ID、外部键和聚合成员完全保持，Unicode URI/payload/存储名称一致，已有发布文件不变。
观测到 revision 62、61 次 provider patch，没有非预期外部请求。Worker bundle SHA-256：
`c4799325e1060a4cfd8cc5cf1ee67f342119d89948b41a3ebcdf3d838613662c`。

所有者另行授权在既有生产 Workspace 验收。脚本先核对准确 Workspace、强 revision ETag
及 GitHub 所有权，再创建六个带唯一前缀的 VMess 用户/地址候选和一个独立测试聚合。
真实 by-key 改名同步后，六个远端 ID、外部键和聚合成员保持不变，原业务记录与发布文件
内容不变。验收后只删除测试聚合和六个测试节点，原聚合保留。revision 从 19 增至 39，
正常变更 tombstone 保留。该证据覆盖代表性的生产 VMess API/Gist 路径，不是生产代理
VPS 部署，也不声称所有协议公网连接已通过。

两个联调使用的冻结运行时 SHA-256 为
`657ea370f56523445d4be5ecd8ce22d98b7864e3949fb8153a384d4ab87efaac`。
之后的事务及 namespace 修改未改变命名、地址选择和同步函数，按 AGENTS.md 第 4.2 节
复用这些结果。私密验收报告保留在
`/tmp/sbv-subman-app-acceptance-20261030-final/acceptance.json` 与
`/tmp/sbv-subman-production-acceptance-20261030/acceptance.json`；凭据和完整分享材料
不是发布产物。生产 helper 不由普通测试组选择，写入前必须提供显式目标、私密凭据文件
及生产验收标志。
