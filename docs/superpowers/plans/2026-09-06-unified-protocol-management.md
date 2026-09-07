# 全协议适配与统一协议管理实施记录

需求来源：[用户原始目标](https://microbin.knowsky.uk/raw/aQg19d)，2026-09-06。
起点为 `cc12c06`，工作区干净；保留参考基线 `0d0bdac` 之后的下载事务修复。
本文记录完整目标的进展；阶段提交不代表全协议已交付。

## 验收范围

- [ ] 核对 latest stable、目标 release 注册代码、移除 stub、构建标签、平台和运行库；固定版本与来源，保留 1.13.x 路径。
- [ ] 覆盖矩阵分列核心支持、项目 implemented、环境 available、实测 validated，逐项记录部署/接管/编辑/删除/导出/分享/SubMan/限制与证据。
- [ ] 集中协议 family、preset/security/transport、role、内部 ID、公开 ID、alias 和 handler 契约；菜单、Agent、导出、验证共享注册表。
- [ ] 推广稳定实例 ID；兼容 index.env、旧协议状态与 vless-reality.d，保留凭据、名称、端口、tag、路由、QoS、出站策略；未知格式阻断有损重建。
- [ ] 统一 inbounds/outbounds/endpoints/route/certificate_providers/http_clients 组合；检查 tag、引用、环、版本、依赖；渲染不创建凭据或注册账户。
- [ ] 完整管理 mixed/socks/http/shadowsocks/vmess/trojan/naive/hysteria/shadowtls/vless/tuic/hysteria2/anytls/snell。区分普通 VLESS 与旧 REALITY alias；合法 TLS/传输组合、SS2022 密钥、ShadowTLS 完整内外层、Naive 运行库。
- [ ] 高级管理 direct inbound/tun/redirect/tproxy/cloudflared，保留管理连接，明确系统资源归属，隔离验证。
- [ ] 管理 wireguard/tailscale/openconnect/openvpn-client/openvpn-server Endpoint；WireGuard 与 Warp 注册解耦；外部认证和控制面测试条件明示。
- [ ] 管理适用上游代理、ssh/tor/direct/bridge/selector/urltest，保护成员、detour、Endpoint 引用；按源码核实 block/dns/ShadowsocksR 历史边界。
- [ ] 真实客户端配置和组合依赖导出、私有证书最小信任、目标核心 check；无服务端私钥；URI 无损/部分/不支持、IPv6/编码/特殊字符测试。
- [ ] Agent envelope `schema_version=1.0`/`schema=1`、旧命令语义、敏感字段与 stdout/stderr 分离；只读不写状态；新写命令参数校验和确认。
- [ ] 只读审阅 SubMan OpenAPI；保留 VLESS/Hysteria2 幂等/revision/确认/回读/错误契约；其他逐节点准确 unsupported/skipped/warning，部分成功不污染可同步节点。
- [ ] 复用托管事务：预检、锁、持久快照、候选、jq/check、发布、资源、健康检查、提交；失败恢复文件、资源、原服务活动状态。
- [ ] 端口按地址/地址族/TCP/UDP/归属检查，规则与证书引用保护；运行库进入升级 manifest/备份/回滚/卸载；no-op 无虚假事务。
- [ ] 保留原始错误阶段/退出码；可捕获信号清理；不可捕获中断后持久恢复；下载、证书、规则集故障有界超时/可信来源/脱敏。
- [ ] 现有全回归及新增生命周期、兼容迁移、多实例、失败注入、并发、注入、部分同步测试；真实目标二进制服务端/客户端 check。
- [ ] 隔离真实 TCP/UDP 闭环、Endpoint/透明流量路径；Docker 调度/probe/scenarios 共享能力；缺少授权端点的结果记 blocked/skipped，不计通过。
- [ ] README、Agent 文档、状态/资源/事务设计、协议扩展示例、实际命令/版本/证据/限制、原子提交及逐提交等效审查。

DNS Server、证书服务、管理 API、USB/IP 独立服务不扩展为本轮产品功能。生产 VPS、真实 SubMan 同步、Cloudflare 账户和隧道资源不在授权范围。

## 实施阶段

1. 上游核对与公共契约：接回原四协议，集中能力与调度，保持行为兼容。
2. 通用实例、TLS/传输、资源、配置组合、客户端和事务基础。
3. 普通代理及组合协议的完整生命周期和真实连接。
4. 高级入站、Endpoint、上游出站及实际数据路径。
5. 全回归、故障注入、Agent/SubMan 与文档验收。

## 已确认的架构落点和风险

- `normalize_protocol_id` 的 `vless` 必须继续指向 REALITY；普通 VLESS 应使用明确的新 preset ID。
- 菜单编号、Agent capabilities、客户端候选和 probe 白名单各自固定四协议，须接入同一注册表。
- `protocol_inbound_tag` 默认回落为 `vless-in`，builder 对未知协议可能返回空成功，须明确失败。
- `reconcile_protocol_index_if_needed` 会忽略未知 ID；`generate_config_candidate` 通过进程替换读取列表会吞掉发现失败，须先捕获完整列表再准备/发布。
- 现有 `source` 状态读取仅适用于本地受管旧状态；新外部导入必须作为数据校验，不能复用不可信 source。
- `generate_config_candidate` 包含 Warp 注册与材料准备；下一阶段分离准备和渲染，不重写已有凭据。
- 快照现有覆盖项目目录，未形成资源账本/持久恢复状态；需扩展现有事务，不能旁路发布。
- `list_config_protocols` 与接管只认识旧协议；扩大识别前必须先建立未知配置/字段保留保护。

## 证据与进展

第一阶段已接入原四协议注册表、公共 ID/菜单/导出/Agent/SubMan 类型/验证元数据，补上未知索引和状态版本、缺失 handler、空/错误片段与协议发现失败的阻断。配置对象识别、通用多实例、资源账本和完整协议实现仍属于后续阶段，未将它们记为完成。

- 基线 `cc12c06`：155/155 Shell 回归，9/9 Docker 场景、12/12 TCP 业务探测；固定副本 `/tmp/sing-box-vps-baseline-cc12c06`，运行目录 `dev/verification-runs/20260906162844`（在该副本下）。
- 第一阶段审查修复后的版本：`bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/run.sh dev/verification/remote/entrypoint.sh`，退出 0；证据 `dev/verification-runs/20260907031322`，9/9 场景、12/12 TCP 业务探测成功，包含旧 Mixed 恢复、Bash 4.2 修复及过期索引恢复失败保护。Hysteria2 使用 QUIC 传输承载该 TCP 业务；未因此声称 UDP 业务已验证。
- 第一阶段审查修复后的全部非 helper 的 `tests/*.sh`：157/157 通过；逐项退出码 `/tmp/sing-box-vps-post-reviewfix-tests-20260907/summary.tsv`。
- `SINGBOX_BINARY_113=/tmp/sbv-real-schema-final.6rMcum/sing-box-1.13.18-linux-arm64/sing-box SINGBOX_BINARY_114=/tmp/sing-box-v1.14.0-cache/sing-box-1.14.0-linux-arm64/sing-box bash tests/export_client_config_1_14_compatibility.sh`：退出 0，两个实际核心均接受对应客户端配置。
- 本轮版本统一递增为 `2026090601`；目标核心保持稳定 `1.14.0`。阶段内不重复递增。
- 回归发现并修复验证 fixture 的独立 metadata 加载和原固定测试计数；没有改用跳过或 mock 替代真实 Docker 验证。
- 预审期间的 Docker 复验 `dev/verification-runs/20260906170645` 为 9/9 场景、12/12 TCP 探测成功，但当时全量 Shell 为 155/156：发现旧单 Mixed 仅残留索引时不能追加安装的回归。实现现已恢复该明确写入口的无损旧状态恢复，补上索引/凭据保留、状态写入失败回滚和拒绝自定义字段测试，并通过上述最终全量复验。
- 旧 Mixed 恢复还通过了两个实际核心的输入/重新渲染 `check`，同时断言原配置字节和用户名/密码不变；命令 `bash /tmp/sbv-legacy-mixed-real-check.sh`，退出 0。此项为受控配置恢复证据，不替代网络连接探针。
- 2026-09-07 的额外兼容检查在官方 `bash:4.2` 容器复现空 alias 数组的 `nounset` 错误；已修复为空时不展开数组。`tests/protocol_registry_legacy_bash.sh` 在 Bash `4.2.53` 和主机 `5.2.21` 均通过，前者使用只读仓库、无网络容器及临时 `/tmp`。镜像 digest 为 `sha256:326c3fb7e7009e1aa6aad242056abc11c372ac0a2b57dcb29ca5bc8feedf5579`；这证明注册表的旧 Bash 语义兼容，不等于完整 CentOS 系统服务验证。
- 原子提交 `380eedd`（`feat: centralize protocol capability contracts`）随后进行了实际提交范围的等效 `/review`（本工具面没有该命令入口）。审查发现旧过期索引分支先删除索引且吞掉恢复失败；已停止后续功能接入，改为直接复用保留原索引的重建事务，补上空 inbounds 和原始退出码 `47` 的回归测试。独立复核确认索引字节保留、错误传播及旧过期条目清理均通过，上述完整门禁也已复跑。
- 修复已形成原子提交 `223ca06`（`fix: preserve protocol indexes when recovery fails`），提交后等效实际范围审查确认该 P1 已解决、无新增 findings。
- 补充上游角色/版本交叉复核修正了覆盖矩阵：Bridge 从 1.14.0 才存在且只处理 L3；direct inbound 的目标覆盖字段仍然有效，移除仅适用于 direct outbound。证据为固定 tag 源码、1.13.18 对 Bridge type 的实际拒绝，以及两核心对受控 direct inbound 配置的 `check`。

后续仍需完成阶段 2–5 的所有未勾选要求；本阶段的通过结果不作为新增协议或高级接入已实现的证据。

## 2026-09-07：第二阶段候选配置图预检

新增 `validate_managed_component_graph`，接入服务端 candidate 和交互/Agent 客户端候选的核心检查之前；同一 jq 解析完成组件 tag、typed reference 和显式依赖环检查。引用完整性与启动依赖区分，DNS/HTTP/provider 等按各自命名空间解析。错误输出不含配置内容、tag 或凭据。Agent 导出失败返回 `client_config_validation_failed`，不覆盖旧导出或备份。

本轮版本同步为 `2026090701`，仅递增一次。再次查询官方 releases/latest，稳定版仍为 `v1.14.0`（非 draft/prerelease，发布时间 2026-08-31）；使用固定源码 `0b8995879f29a9b98ee027bc17b75e101445b238` 和 1.13.18/1.14.0 实际二进制交叉验证。Context7 只返回 testing 分支及不完整引用资料，因此补读 release tag 的 `option/`、dialer、DNS/HTTP manager 源码。

已执行的新增针对性验证：

- `tests/managed_component_graph.sh`：43 项图单元断言；传入 `SINGBOX_BINARY_113`/`SINGBOX_BINARY_114` 后，两份完整正例均通过两个实际核心 `check`。主机 jq 1.7 与只读、无网络的 Debian 12 验证镜像 jq 1.6 均通过图断言。两版核心路径沿用上文记录。
- `tests/managed_component_graph_core_startup.sh`：在两版核心完成 8 次实际对照；悬空 route final、DNS final、DNS 缺失依赖和 DNS 环均可通过 `check`，但启动退出 1，而新预检已在发布前拒绝。使用无入站监听、无远程规则集及无外部账户的受控配置；不是协议业务数据面证明。
- `tests/generate_config_commits_validated_candidate.sh` 和 `tests/export_client_config_validates_generated_config.sh`：在核心 mock 放行的情况下，真实图预检阻断重复 tag/悬空引用，验证 live 文件、旧 `.bak`、协议状态、导出文件保持，生成器副作用回滚，Agent stdout 仍为有效 envelope。
- 官方 `bash:4.2` 无网络只读容器中 `bash -n /work/install.sh` 通过；此项仅为旧 Bash 语法检查，不是旧发行版的完整服务测试。
- 默认门禁加入两个图测试及客户端发布测试，运行器调度断言从 32 项更新为 35 项；不依赖提交后空 diff，最终使用显式 `--changed-file install.sh dev/verification/common.sh`。
- 最终完整门禁：在上述两个实际核心环境变量下运行 `bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh`，退出 0。证据 `dev/verification-runs/20260907033515`，9/9 Docker 场景、12/12 TCP 业务探针成功，包含 1.13.18 → 1.14.0 升级及注入重启失败后的回滚。Hysteria2 的 QUIC 传输不作为 UDP 业务已经验证的证据。
- 全部 159 个非 helper 的 Shell 测试均退出 0，日志与逐项退出码位于 `/tmp/sing-box-vps-all-tests-20260907-graph-final/summary.tsv`；该次全量传入两核心路径，新增启动对照执行 8 次，没有跳过。单独无网络 jq 1.6 容器只执行图断言，不计为真实核心启动比较。

边界不变：这只是阶段二的候选组合基础，不代表通用实例、所有协议、任意 live 配置无损接管或资源事务已经完成。下一步仍需先实现未知对象/字段的无损保护，再推广结构化实例、纯渲染、资源归属和完整生命周期。

## 2026-09-07：现有入站清单的无损保护

新增 `validate_live_inbound_inventory`，在协议枚举、健康判定、索引协调、自动修复、显式接管、状态重建和配置生成的资源准备之前检查完整 live 入站清单。未知核心类型、非 REALITY 的 VLESS、重复的当前单实例协议、重复显式 tag 和损坏的 JSON/清单结构均固定分类失败；枚举先捕获完整结果与退出码，不输出“已识别前半段”。旧 `vless` CLI alias 继续表示 REALITY，REALITY 多实例继续可用。接管诊断不再打印含 UUID、密码、私钥或 token 的原始状态快照。

本轮版本同步为 `2026090702`，仅递增一次。`tests/live_inbound_inventory_guards.sh` 覆盖全部入口的 fail-closed、配置/索引/状态 hash 与 mode 保持、资源准备及重启未调用、诊断脱敏、合法四协议清单和旧 alias。固定 1.13.18 与 1.14.0 实际核心都先接受 Mixed + Shadowsocks 受控配置，随后脚本门禁拒绝将其中未知 Shadowsocks 当作可管理对象；这证明修复针对真实可运行的丢失路径，而不是仅拒绝无效 fixture。

首次提交后的精确范围审查发现两个问题：sing-box 的 TLS/REALITY `enabled` 布尔值省略时默认为 `false`，不能只拒绝显式 `false`；Agent 的 `status`、`nodes` 和 `links` 也不能绕过完整清单校验后返回部分协议。后续修复要求两级开关都显式为 `true`，并使三个 Agent 命令在无法信任 live 清单时返回 `live_inbound_inventory_untrusted` 结构化错误；负例覆盖省略/禁用开关、部分结果阻断、凭据脱敏，以及公网地址和资源准备均未触发。该修复提交的精确范围审查无 finding。

继续收口既有索引/状态风险的提交经精确审查后发现五项缺口：VLESS 实例枚举仍使用会吞退出码的进程替换，索引 schema/重复项/配置集合不一致未检查，缺失 VLESS 根状态会回退到默认值，孤立未知状态被忽略，成功输出后的状态恢复失败未传播。最终实现改为先只读构建统一可信清单：规范化索引与 live 协议集合必须完全相等，索引和基础状态必须完整且没有重复/孤立项；REALITY 实例清单在公网读取前一次性捕获并验证。节点先写入临时集合，任何加载、实例枚举或最终恢复失败都会清理临时结果并返回固定结构化错误。新增负例逐项复现上述路径，并检查不泄漏已渲染的 Hysteria2 密码或连接材料。

该修复的再次精确审查又复现两项 REALITY 特有缺口：只有 schema 标记的旧根状态仍会被默认节点名、端口和 SNI 补成伪节点；schema 2 只检查清单所列文件，没有核对实例目录、文件内部 ID 和 live VLESS tag 集合。最终收敛为 `status`、`nodes`、`links` 共用的只读 REALITY inventory 验证器：schema 1 直接检查原始连接字段且拒绝实例目录残留；schema 2 校验根密钥、默认实例、清单唯一性、每个完整且启用的实例、目录精确集合、文件名/内部 ID 一致性，以及实例 tag 与 live VLESS tag 的精确集合。负例覆盖空壳旧状态、孤立实例、内部 ID 错配、live tag 错配和凭据不泄漏，并保留两实例成功对照。提交前聚焦复核确认上述两项 P1 均已关闭，未发现新的 P1/P2；状态字段与 live 参数的完整语义往返、密钥数学一致性及既有 shell 状态文件信任边界仍明确保留为范围外风险。

最终 160 个非 helper Shell 测试在两核心环境变量下全部通过，证据为 `/tmp/sing-box-vps-all-tests-20260907-vless-inventory-postreview.tKCE65/summary.tsv`。最终 `bash dev/verification/run.sh --changed-file install.sh --changed-file dev/verification/common.sh` 退出 0，证据目录 `dev/verification-runs/20260907063120`：44 个本地触发测试通过，Docker 9/9 场景和 12/12 TCP 业务探针成功。正常升级从 1.13.18 到 1.14.0，服务前后均为 active 且目标核心 `check` 通过；注入服务失败的场景返回非零，但事务结果持久化并以 `rolled_back=true`、`rollback_ok=true` 恢复 1.13.18、active 服务和通过的核心 `check`。Hysteria2 的 QUIC 仍不作为独立 UDP payload 验证证据。

边界：本项只完成 live inbound inventory 层保护。额外用户/协议字段，以及未知 outbound、endpoint、DNS、证书和 route/rule 的语义往返保护仍未完成；已有 VLESS 状态的名称、QoS 与稳定 ID 在显式重建中的保留也仍需修复。它不代表新增 Shadowsocks 或其他协议已经实现。

## 2026-09-07：REALITY 重建保留既有实例元数据

针对原目标第五节的兼容要求，修复显式重建清空实例目录后重置稳定 ID、节点名和 QoS 的问题。先读取旧受管状态元数据，通过 inbound tag 唯一关联 live VLESS，保留实例身份、默认实例、名称和限速；连接字段仍从 live 配置读取。旧 schema 1 仅为对应主实例保留名称，根状态中与 live 私钥匹配的公钥可直接复用。期望状态比较使用同样的关联与默认实例选择。加载器清除旧 raw env 变量，避免 manifest/tag 从前次读取串入。

扩展既有 takeover 测试，覆盖自定义 ID/默认实例/含空格名称/QoS、二次重建幂等、tag 歧义拒绝、非法 QoS 拒绝、保存失败整树回滚及 schema 1 名称隔离。传入两核心路径时，临时真实 REALITY 密钥用于重建状态的服务端和客户端配置 `check`。本轮脚本与 README 统一为 `2026090703`。

首轮全量回归发现两个无 tag 旧配置接管用例失败：重建后的自动 `imported-*` ID 在健康检查中发生漂移。修复后，单个旧实例可唯一复用既有身份，schema 1 的无 tag/无用户名主实例保留名称；多个无 tag 入站则需要用户名与既有 ID 唯一对应，否则在替换状态前拒绝。补充配置字节不变、二次重建状态树不变和多匿名入站拒绝断言。

最终验证：160 个非 helper Shell 测试在 `SINGBOX_BINARY_113`/`SINGBOX_BINARY_114` 两个实际核心路径下全部退出 0，逐项记录为 `/tmp/sbv-reality-metadata-final.vtBj7I/summary.tsv`。`bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 退出 0，44 个本地门禁测试通过，证据目录 `dev/verification-runs/20260907065820` 包含 9/9 Docker 场景与 12/12 TCP 业务探针成功；包含 1.13.18 → 1.14.0 升级，以及失败注入后 `rolled_back=true`、`rollback_ok=true` 恢复 1.13.18。重建状态渲染的服务端与客户端配置均通过两个真实核心 `check`；Bash 4.2 只读无网络容器的语法检查也通过。Hysteria2 QUIC 仍不计作独立 UDP payload 验证，未操作生产 VPS 或执行 SubMan 同步。

提交 `7acf762` 的精确范围审查发现一项遗漏：旧配置省略 tag 时，重建与健康检查认可内部稳定 tag，但 Agent 清单验证仍直接要求 live tag 非空。修复使 Agent 仅在缺 tag 时复用同一唯一身份关联，随后仍执行完整字段、实例文件集合和 tag 集合检查。新增断言覆盖 tagless 接管后的 `status`、`nodes`、`links` 成功，配置/状态读取不变，多匿名入站拒绝，以及用户名与已有 ID 唯一对应的多实例成功。该后续修复沿用本轮 `2026090703`，不再递增版本。

审查后验证：25 项 Agent/接管/REALITY/清单保护相关测试全部退出 0，记录为 `/tmp/sbv-reality-agent-postreview.pFPefg/summary.tsv`；最终再次执行上述完整门禁，`dev/verification-runs/20260907071014` 的 44 项本地测试、9/9 Docker 场景与 12/12 TCP 探针均成功。前述 160 项全量结果对应首个元数据保留提交；六行 Agent 修复使用相关回归与完整 Docker 门禁复验，未将前次全量结果伪称为再次执行。独立定向复核确认 P1 已关闭，未发现新 P1/P2。

后续仍须实现未知字段和非入站组件的完整无损保护，以及通用实例、资源事务和新增协议全生命周期；本项没有将这些验收要求记为完成。

## 2026-09-07：统一只读实例适配入口

继续第二阶段，先将现有格式接入共享的实例枚举、默认实例和只读加载接口，实例身份使用协议与 ID 二元组。旧单实例协议/schema 1 REALITY 内部以 `main` 表达；schema 2 REALITY 保留原有身份与顺序。Agent 节点/分享遍历和 REALITY 客户端导出使用该接口，不再各自组织 REALITY 特例循环。既有公开 JSON 字段及 CLI alias 不变。

REALITY 导出不再为读取 schema 1 自动执行迁移；完整枚举或任一构建失败均不输出有效前缀。新枚举对清单/默认实例/文件集合错误拒绝，但显式接管清理旧孤立残留的原有契约保留。读取前清空原始状态变量，避免跨协议可选字段污染。此阶段不创建通用 JSON 透传状态、不增加 supported 协议行，也不把非 REALITY 多实例写入记为完成。

新增 `tests/protocol_instance_adapter.sh` 并接入默认门禁；覆盖单实例与多实例身份、旧 alias、缺省 schema 1、可选字段污染、名称/凭据/QoS 保留、只读与导出不迁移、失败时无部分输出及两版实际核心客户端检查。版本本轮统一递增为 `2026090704`。

首轮 161 项回归只有零 REALITY 实例的既有诊断断言失败：导出已正确拒绝且没有写文件，但提前默认实例预检丢失了明确提示。已恢复固定脱敏提示并保留失败退出码。独立预审另发现 schema 2 清单完整但 UUID 缺失时底层客户端构造仍能成功输出空字段；现将 Agent 既有连接完整性检查提取为共享校验，在通用 REALITY 加载后执行。负例覆盖 UUID、SNI、端口、首个 Short ID 和公钥缺失，第二 Short ID 保持可选。只读状态在预检后消失时也直接返回失败，不进入深层退出或使用先前实例值。

预审继续发现 schema 1 的节点名、端口和 SNI 缺失会被旧加载器默认值掩盖；通用入口现在先验证原始旧状态，再加载运行时字段，补齐三个缺失字段的拒绝用例。新测试在官方 Bash 4.2.53 镜像提取的临时运行时上实际执行，发现并修复新只读索引及客户端标签列表的空数组 `nounset` 问题，全部新适配器检查通过；测试在顶层 source 脚本以匹配实际入口，避免 Bash 4.2 对函数内 readonly 数组的作用域差异。这是 Bash 版本兼容运行证据，不代表完整 CentOS 系统验收。

定向复核又复现 Agent 可信清单首项、空索引孤立状态和空安装枚举的同源 Bash 4.2 问题。修复安全空展开和空清单提前返回，并直接覆盖真实 Agent helper 的首项、空清单、孤立状态拒绝及空节点结果；新增测试在 Bash 4.2.53 与两版核心路径下通过。

验证证据：161 项全量回归全部通过，记录为 `/tmp/sbv-instance-adapter-reviewed.VEZLE5/summary.tsv`；最后的必填字段及 Bash 兼容修复另以 28 项相关回归复验，记录为 `/tmp/sbv-adapter-bash42-related.Y1PPqT/summary.tsv`。完整默认门禁 `dev/verification-runs/20260907075359` 的 45 项本地检查及 Docker 均通过；最后 Agent 空数组修复后，以 `VERIFY_SKIP_LOCAL_TESTS=1` 单独复跑 Docker（不把跳过的本地检查计为重新通过），最终证据 `dev/verification-runs/20260907075939` 为 9/9 场景、12/12 TCP 业务探针成功，含正常升级和失败回滚。容器中的脚本 SHA-256 与最终源码一致：`a9dec9b25a791de43db3976883e3d52cf85c1a90e2d10e8940ecf7e0499eb3a9`。新旧实例客户端片段通过真实 1.13.18 / 1.14.0 `check`；Hysteria2 QUIC 不作为独立 UDP payload 验证证据。

本项未执行生产操作、推送或 SubMan 同步，也未完成全协议目标；后续仍需通用多实例持久化/写入口、未知字段及非入站组件无损保护、资源事务，以及新增协议完整生命周期。

提交 `bbf6a3d` 的精确范围等效 `/review` 发现跨协议客户端导出在目标实例加载失败时提前返回，跳过原运行态恢复。修复将目标解析/加载失败保存到统一状态码，跳过渲染但继续恢复原协议；初始失败码优先保留。新增回归从 Mixed 出发，逐项移除 REALITY 默认实例的 UUID、SNI、Short ID 和端口，断言失败无输出、原协议/实例/名称/端口/密码恢复、REALITY 字段清空，且后续 Hysteria2 导出成功。实际 Bash 4.2.53 两核心环境测试通过，修复沿用本轮 `2026090704`。

该审查修复的完整门禁再次退出 0：`dev/verification-runs/20260907080539` 包含 45 项本地检查、9/9 Docker 场景及 12/12 TCP 探针成功，失败升级事务结果为 `rolled_back` 且 rollback `result=success`。已核对运行容器源码与待提交脚本 SHA-256 一致：`7d34399104d4a6aa967995a1423fc032cc83d2a42d9deeae842e66b06b9e84a6`。独立定向复核确认状态恢复 P2 已关闭；前述 161 项全量回归并未在这个小修复后重新执行，不混作最终完整重跑证据。
