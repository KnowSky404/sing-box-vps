# 全协议适配与统一协议管理实施记录

需求来源：[用户原始目标](https://microbin.knowsky.uk/raw/aQg19d)，2026-09-06。
起点为 `cc12c06`，工作区干净；保留参考基线 `0d0bdac` 之后的下载事务修复。
本文记录完整目标的进展；阶段提交不代表全协议已交付。

## 2026-09-07：独立 SOCKS 接入（当前阶段）

脚本与 README 版本统一为 `2026090709`。本阶段新增独立 `socks` inbound 预设，共享 Mixed 的类型化实例记录、CAS 写入、配置候选校验、持久事务和防火墙归属账本，不复制一套协议专用事务。SOCKS 新装直接使用 schema 2 marker 与 `schema_version: 1` JSON store；没有 legacy SOCKS `.env` 格式，`instance migrate socks` 明确拒绝，既有 live 配置走接管重建。旧 Mixed 的 legacy 迁移及包装函数继续保留。

实例提供创建、替换、删除、默认及恢复，默认回环监听并开启认证。非回环写入需要显式确认；恢复日志绑定协议，仅缺少 protocol 的历史日志按 Mixed 解释，显式 null/false/错误类型不作默认。SOCKS 与 Mixed 均参与 Warp 依赖判断；未索引 store 只接受合法、空且 revision 大于零的删除 tombstone。共享接管保留 ID/tag/名称/凭据/出站策略，省略 listen 时保持真实核心的回环默认，拒绝未建模字段；SOCKS 不接受 Mixed 专属的 `set_system_proxy` 字段。

菜单新增 18「管理 SOCKS 实例」，首次安装协议编号为 5。SOCKS 只提供 SOCKS5 分享链接及带 UoT v2 的客户端 outbound，不提供 HTTP 入口、TLS 或 SubMan 同步。核心支持事实先查 Context7 `/sagernet/sing-box`；该结果只有 testing 文档，随后按固定 v1.14.0 的 `protocol/socks/inbound.go`、`option/simple.go` 和 inbound 文档核实，并用真实 1.13.18/1.14.0 验证。

新增六项 Shell 回归覆盖共享 store、SOCKS 生命周期、真实核心运行、菜单、接管及导出。两版真实核心各通过 instances=2、exported=2、TCP=9、UDP=9、错误认证拒绝=1、失败候选保留旧服务=1；计数包含既有 Mixed 的流量保留检查，导出的两个 outbound 均生成并校验，其中一个用于实际客户端收发。这些是本机回环 SOCKS TCP/UDP 与导出 UoT v2 证据，不证明公网跨主机 UDP associate 或其他协议 UDP 数据路径。systemctl/firewall 在本地生命周期测试中仍为 mock；重启失败回滚另有 mock 故障注入（restarts=10）。

最终源码 SHA-256 `d711688daae51d938a02e737be7e521df6b8ea198c1e93b4f33d24d1feaf947c` 下，实际 Bash 4.2 直接执行两版 runtime 的 `--run` 分支均退出 0，日志为 `/tmp/sbv-socks-bash42.HD1NEM/`（1.13.18）及 `/tmp/sbv-socks-bash42.ZoFg4h/`（1.14.0），每个目录保留命令、stdout/stderr、退出码及一致的起止源码哈希。Bash 4.2 接管、菜单及事务专项也通过；菜单兼容补修处理了空数组展开、单次操作失败退出、删除确认实例 ID 和单次 list 循环问题。父代理独立复跑最终 Mixed/SOCKS 菜单测试通过。

冻结源码的 164 项普通 Shell 测试串行执行全部退出 0，逐项记录 `/tmp/sbv-socks-all.bpCBR9/results.tsv`，起止源码哈希一致；14 项验证框架测试也全部通过，日志 `/tmp/sing-box-vps-verification-suite.WadON6/`，合计 178/178。此前的并行运行、旧 capabilities 夹具及遗漏 SOCKS 的 runtime artifact 夹具曾失败，均不计作最终通过证据；对应夹具已补齐并重新执行。

最终默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/remote/entrypoint.sh` 在 `dev/verification-runs/20260907125254` 退出 0：65 项本地检查、10/10 Docker 场景、14/14 TCP 探针成功；新场景覆盖实际交互首次 SOCKS 安装与四协议安装后经 Agent 事务追加 SOCKS 的五协议共存。故障升级结果为 `status=rolled_back`、`rollback.result=success`。父代理在容器存活期间直接读取 `/tmp/sing-box-vps-verification.8yaSHN/install.sh` 哈希，与上述最终源码完全一致。此前 `20260907122042` 只有首次 SOCKS 安装与 runtime smoke 的局部 Docker 验证，不能代替本次完整门禁。

独立预审关闭了 SOCKS Warp 依赖遗漏、orphan store 忽略、跨协议恢复、协议诊断及导出 warning 误归属问题。warning 识别保留 legacy Mixed 的任意持久化节点名，不把 `socks-mixed` 误认作 Mixed；SOCKS 链接警告不宣称 URI 已配置 UoT。冻结源码复核未发现新增确认的 P1/P2，提交后仍须对精确提交范围审查。全协议目标继续进行，其他协议族和外部系统资源边界尚未完成；未推送、部署、操作生产或执行真实 SubMan 同步，用户未跟踪文件 `1`、`2` 均保留。

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

## 2026-09-07：结构化实例存储基础与 Mixed 类型化适配器

从 `bd8cd9f` 继续，基线门禁 `20260907081124` 为 local 模式退出 0，原有未跟踪文件 `1` 保持不动。只读追踪确认现有 Mixed 健康匹配只看第一个入站、重建循环最终只保留最后一个实例，生成器也固定 `mixed-in`；因此没有直接放开注册表多实例标记，而是先实现后续完整生命周期必需的结构化存储和纯渲染基础。本轮版本统一为 `2026090705`。

新增内部数据 API 支持 create/replace/delete/default 候选、稳定 ID/tag、默认实例、有序清单和 revision 条件写入。第一种类型化 handler 为 Mixed；其他协议明确拒绝，旧 `.env` 和 REALITY 实例目录不会自动转换。数据必须是单一 JSON 文档，严格 allowlist、类型、大小、地址、端口、认证 UTF-8 字节长度和 revision 精确整数范围；不是原始 core 配置透传。凭据通过私有数据捕获及 stdin/文件传递，错误只返回固定阶段/分类。Context7 返回 testing 文档，随后核对固定 [1.14 Mixed 文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/inbound/mixed.md)及 [SOCKS 出站文档](https://github.com/SagerNet/sing-box/blob/v1.14.0/docs/configuration/outbound/socks.md)，最终以两个固定核心运行确认实际渲染行为。

原子文件写入使用私有目录/文件、锁内 CAS、一次性有界输入捕获、同目录 staging、原子 `.bak` 与目标替换、内容/权限 postcheck 和回滚。no-op 保留 revision、目标 inode 和旧备份。TERM/INT/HUP 清理并恢复已尝试提交的文件；回滚失败保留原文件副本与恢复标记，不销毁恢复材料。不自动夺取遗留锁：不可捕获中断后需明确检查恢复记录，这不是完整服务资源事务或持久恢复管理器。未来启用写命令仍须复用既有 managed snapshot、完整配置候选、资源归属与服务发布流程。

`tests/structured_instance_store.sh` 覆盖数据注入边界、未知字段/schema、非法 IPv4/IPv6、默认实例、稳定 tag、revision 上限、并发两个写者、备份/no-op、commit/postcheck/TERM 失败、rollback_failed 材料保留、目标/备份符号链接拒绝及旧状态字节保持。主审与独立复核发现并修复末尾单冒号 IPv6、换行地址、空默认实例、revision 末端递增和输入重复读取的问题。两核心各运行两个不同认证的 Mixed 实例，分别通过 HTTP/SOCKS 请求同一 loopback 标记服务，共 8 次真实 TCP 请求；这是新存储渲染的数据面证据，不是现有菜单的多实例生命周期验收，也不包含 UDP 业务验证。

该存储尚未接入 Agent/菜单写命令、旧状态迁移、健康修复、接管、删除、防火墙归属或完整客户端导出，不把此项记作 Mixed 多实例完整支持。下一步必须将这些接入点成套实现，再调整能力注册表；全协议目标继续保持未完成。

验证：162 项非 helper Shell 全回归全部通过，记录为 `/tmp/sbv-structured-store-all.xnwzKw/summary.tsv`。完整默认门禁 `20260907083458` 的 46 项本地检查和 Docker 均退出 0。最后仅调整新原语的失败阶段说明与避免把旧认证字段放入 jq 命令行，随后以 `VERIFY_SKIP_LOCAL_TESTS=1` 复跑 Docker，证据 `dev/verification-runs/20260907083903` 为 9/9 场景与 12/12 既有 TCP 探针成功；未把该次跳过的本地门禁计为重跑。最终源码 SHA-256 为 `2c7071fa87cfa95ca52f7811372d77dfe0381b8be6dc815e8916f2fef1708d80`。新增测试另在 GNU Bash 4.2.53 临时运行时上运行通过（主机工具链，不等于完整 CentOS 系统验证），两版真实核心检查和 8/8 HTTP/SOCKS TCP 请求均通过；最后还补验了正确凭据成功/错误凭据拒绝以及成功编辑保留 ID/tag。独立定向复核无新增 P1/P2。未执行生产、远程推送或真实 SubMan 同步。

## 2026-09-07：监听资源规划与删除引用保护

从 `b650a91` 继续，基线 `bash dev/verification/run.sh` 为 `20260907084911` local 模式退出 0；保留原未跟踪文件 `1`。调用图再次确认 Mixed 多实例不能只接存储与生成器：健康匹配、接管、Agent、删除及系统资源都仍有单实例分支。本轮先完成已存在的资源误判/误删路径，作为通用多实例生命周期的必要接入，不改变注册表支持范围。版本本轮仅递增为 `2026090706`。

新增 `managed_listener_plan` 与冲突校验，直接使用注册表 `listen_networks`，识别固定 socket 的 tag 归属、TCP/UDP、规范化地址、地址族和双栈重叠。候选配置发布前与结构化 Mixed validate/candidate/publisher/renderer 已共用；非法/未知字段范围不输出部分计划或凭据。删除时读取 `.bak` 和剩余配置，按旧监听拥有的 transport/port 求差并保护新引用，后端失败保留原错误码、报告可能部分外部变更，不用文件回滚冒充系统已恢复。

Context7 查询仅提供 testing 概览，随后复核固定 [Mixed TCP listener](https://github.com/SagerNet/sing-box/blob/v1.14.0/protocol/mixed/inbound.go)、[TCP Listen](https://github.com/SagerNet/sing-box/blob/v1.14.0/common/listener/listener_tcp.go)、[UDP Listen](https://github.com/SagerNet/sing-box/blob/v1.14.0/common/listener/listener_udp.go) 及其固定依赖 [NetworkFromNetAddr](https://github.com/SagerNet/sing/blob/v0.9.0-beta.4/common/metadata/network.go)。1.13.18 的 TCP 路径也使用同一地址族选择方式。实际二进制仍为 1.13.18（revision `45ca32dcb966f07f97fc888fe8586e359dbe8405`）与 1.14.0（`0b8995879f29a9b98ee027bc17b75e101445b238`），本轮重新查询 latest stable 仍为 1.14.0。

新增 `tests/managed_listener_resources.sh`、`tests/firewall_listener_references.sh`，并在候选发布测试增加核心 mock 放行、资源冲突阻断且旧配置/备份/状态保持的用例。默认门禁加入两项。首轮 163 项回归全部退出 0，证据 `/tmp/sbv-listener-all.HQkXLo/summary.tsv`（已包含资源测试）；该次文件名过滤还排除了实际上可执行的 `subman_config_helpers.sh`，最终枚举纠正为仅排除两项真实 helper，不以这个早期集合冒充最终 164 项全量。

资源测试在 Bash 5 和实际 Bash 4.2.53 上使用两个核心各完成两地址同端口 TCP、同数字 UDP 的启动，4 次 TCP 标记请求，以及 IPv6 等价地址 check 成功但启动报 `address already in use` 的 2 次对照。主机默认不运行通配对照；在 `sing-box-vps-verify` 镜像（`6c1e402cdaa2`）、`--network none --read-only --tmpfs /tmp`、只读挂载仓库与核心的容器中设置 `SBV_TEST_ISOLATED_LISTENER_WILDCARD=1`，额外两次 `::`/IPv4 冲突对照通过。隔离执行总计 check=6、start=2、TCP business=4、等价 IPv6 contrasts=2、wildcard contrasts=2。该容器使用 jq 1.6；不操作宿主机防火墙，不把 UDP 监听当作 UDP 业务验证。Bash 4.2 的防火墙 mock 回归和原结构化实例测试（两核心、8 TCP 请求）也通过。

首次完整门禁 `20260907090000` 在本地 mock harness 阶段因与全回归争用 `/tmp/sing-box-vps-verification.lock` 退出 32；确认原任务已终止、锁已由任务清理后串行重跑。首次隔离资源测试发现旧缓存验证镜像未含 Python，未记通过；按仓库现有 Dockerfile 重建后上述隔离测试通过。

独立预审发现并关闭三项 P2：开放仍加反向传输规则导致新清理留下孤立规则、全量移除未确认 stop 成功、已提交后开放失败缺少阶段说明。现在开放与清理共用实际监听传输，全量 stop 失败恢复文件且保留原始 47 退出码，`ActiveState` 非 inactive 则拒绝清理；新 wrapper 明确报告已提交配置/防火墙可能部分变更/显式重启未执行。相应 mock 正反例、配置/索引/状态/旧备份 hash 保留断言已补齐。后续全回归发现 7 个安装 prompt/state 测试只 mock 配置生成计数，因此将其防火墙 mock 移到新的收集边界，不降低真实资源校验；另在 Bash 4.2 实跑删除入口修复索引协调和删除选择的初始空数组 `nounset`。测试 fixture 避免函数局部 readonly 及 here-doc 重定向的旧 Bash 作用域干扰，真实删除安全回归通过。

完整默认门禁 `bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `20260907090447` 退出 0，48 项本地检查及 9/9 Docker 场景、12/12 既有 TCP 探针通过。最后审查修复之后，另以 `VERIFY_SKIP_LOCAL_TESTS=1` 复跑 Docker，最终证据 `dev/verification-runs/20260907091817` 为 9/9 场景、12/12 探针成功，失败升级事务为 `status=rolled_back`、`rollback.result=success`；没有把该次跳过的本地门禁计为再次执行。在运行容器中直接取得的安装脚本 SHA-256 为 `4439061cd395f9d8ad159436a8104fdb7786d974c08a13218ffa2f253cde6f88`，与最终工作区源码一致。

最终修正枚举后的 164 项回归全部退出 0，两个核心环境变量均已传入，逐项证据 `/tmp/sbv-listener-final-all.JMX95i/summary.tsv`。最终 Bash 4.2.53 另重跑资源计划（两核心 check=4/start=2/TCP business=4/等价 IPv6 contrasts=2）、防火墙 mock 与真实删除入口的停止故障回归，全部通过；主机默认跳过通配启动对照，隔离 Docker 的额外双栈证据如上。预审发现的三项 P2 和两个旧 Bash 空数组问题均已修复，独立复核未发现新增 P1/P2。

边界：尚未实现精确防火墙创建归属账本、跨进程端口预留、完整配置/服务/防火墙持久事务、动态 SOCKS UDP/ACME 临时监听、高级接入资源或通用实例完整写入口。旧 prompt 的整数字端口占用询问尚未替换为完整资源计划；新增候选预检不宣称解决该交互限制。全协议目标仍未完成，未推送、部署、访问生产或执行 SubMan 同步。

### 2026-09-07 Mixed 客户端导出

从 `ca7e5e4` 继续，基线 `bash dev/verification/run.sh` 为 `20260907092728` local 模式退出 0；保留用户原未跟踪文件 `1`。本轮版本只递增一次为 `2026090707`。为推进总目标中明确要求的 Mixed 导出，不再沿用历史设计的排除规则；不将本轮功能冒充完整通用多实例生命周期。

注册表、Agent capabilities/nodes 与交互/Agent 导出现在一致支持旧 Mixed 单实例。SOCKS5 outbound 使用已保存的端口、认证标记及凭据，用户名/密码校验 1–255 字节；无认证时不输出 credential 字段。原始状态的必需字段缺失、无效或凭据超长会拒绝，不用 legacy loader 默认值补造，也不触发状态迁移或凭据生成。即使其他协议可用，无效 Mixed 也中止整份导出，原文件与备份保持不变。生成后依次执行组件图和目标核心 check，沿用私有临时文件、覆盖前备份及发布边界。Agent 候选生成失败返回稳定 `client_config_generation_failed` 错误 envelope。

最终复核进一步要求校验与渲染使用实例适配器同一次加载的原始字段，不二次读取 `.env`：故障注入在缺少 PORT 的快照加载后立即替换为完整新文件，仍须拒绝旧快照默认值。此回归及用户名/密码 255/256 字节、UTF-8 字节数、陈旧凭据、stderr 脱敏、直接调用 dispatcher 的跨协议恢复均通过 Bash 5 与实际 Bash 4.2.53。该保护不是跨进程锁或完整持久事务的替代。

显式开启 UoT v2，使 UDP payload 经现有 TCP 入口传输，不新增固定 UDP 防火墙开放；`network` 留空遵循上游 TCP/UDP 默认。Context7 查询之后按固定 1.13.18/1.14.0 文档及 Mixed `uot.NewRouter` 源码确认。交互输出及 Agent `warnings[].code=mixed_plaintext_transport` 明确提示凭据与非加密业务在代理链路上没有 TLS 保护；UoT 不提供加密。Mixed SubMan、独立 SOCKS 服务端管理和 Mixed 多实例的声明保持未支持。

真实运行测试将实际导出的 SOCKS5 outbound 原样放入精简隔离客户端配置；完整导出仍另行 check。1.13.18/1.14.0 同版本与双向跨版本、认证/无认证共 8 组均有 TCP marker 与 UDP echo payload 成功，合计完整导出 check=8、精简核心 check=16、TCP=8、UDP=8、直接服务端错误认证拒绝=4；父代理已独立复跑。它不证明完整配置的公网规则集下载、原生跨主机 UDP associate 或其他协议 UDP 数据路径。原有 Docker 场景仍单独计为 TCP 证据，未操作生产或 SubMan 服务。

回归证据：166 个实际 Shell 测试全部退出 0，逐项记录 `/tmp/sbv-mixed-export-all.0L4Qeo/summary.tsv`；最后同快照校验收紧后，11 个客户端导出专项再次全部通过，记录 `/tmp/sbv-mixed-export-final.2eT2cN/summary.tsv`。实际 Bash 4.2 另通过 Mixed-only、认证/失败回归和两个跨版本方向的 TCP/UDP 运行。最终默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `dev/verification-runs/20260907095126` 退出 0：51 项本地检查、9/9 Docker 场景、12/12 既有 TCP 探针通过，失败升级的持久事务为 `status=rolled_back`、`rollback.result=success`。直接从当次容器读取的脚本 SHA-256 为 `8f280f8576beb83648ea8eb7a44d25cb3591b1fcc4f198a957993c070e101a22`，与最终源码相同。独立预审及同快照收紧复核未发现新增 P1/P2。全协议目标仍在进行，尚未实现新协议族、完整多实例和系统资源事务；未推送或部署。

## 2026-09-07：Mixed 多实例生命周期接入与验收

本阶段把前述结构化 Mixed 基础接入现有运行时，脚本版本统一为 `2026090708`。这不是全协议目标完成的标志；除当前四种既有预设外的协议族仍未实现，Mixed 也不提供 TLS、独立 SOCKS 服务端管理或新的 SubMan 同步能力。

Mixed 的 schema 2 状态以 `protocols/instances/mixed.json` 为真源，实例拥有稳定 `id`、`tag`、名称、监听地址/端口、认证和出站策略，并保留默认实例与单调 revision。首次全新安装仍走 legacy schema 1 的 `mixed.env` 路径；只有显式 `migrate`、接管重建或后续实例写入才启用 schema 2。显式迁移把 legacy 的现有 ID（单实例为 `main`）、tag、监听地址/端口及用户名/密码带入结构化记录，不通过隐式读取或凭据生成改变旧实例。旧配置省略 `listen` 时按真实核心默认保留 `127.0.0.1`，不使用机器的全局公网监听地址；省略端口或含未建模字段时拒绝有损转换。schema 2 的根标记只按数据读取，拒绝重复元数据或命令内容，不再 `source` 执行。

Agent 写接口覆盖 `create`、`replace`、`delete`、`default`、`migrate` 和 `recover`，返回稳定 JSON envelope，并通过 `--expected-revision` 进行 CAS。`replace` 保持既有 ID/tag；`delete` 删除单个实例并重新选择默认实例，删除最后一个实例时移除 active `mixed.env`、索引项和 Mixed inbound，但保留空 JSON store（`schema_version: 1`）作为 revision tombstone，active marker 仍为 `CONFIG_SCHEMA_VERSION=2`，后续 `create` 以 tombstone revision 继续递增而不重置为 0；`migrate` 使用虚拟 revision 0 迁移 legacy 状态；`recover` 只接受可验证的未完成事务和匹配 journal 原始 revision，缺少防火墙 journal 时失败并要求人工恢复。非回环地址的明文 Mixed 记录必须显式 `--allow-public`；没有该确认时请求在准备阶段拒绝。

实例写入的事务顺序是 prepare → snapshot → publish → resources → service → committed：初次创建也先在目标同目录 staging，再通过原子发布建立文件；共享 `flock` 串行管理写入，`.instance-write.lock/transaction.json` 保存持久阶段和 before/after 信息，`.instance-transactions/` 保存原子 result。配置候选必须经过组件图、监听资源和目标核心 `check`；受管 UFW/iptables/ip6tables 防火墙由实例 ledger prepare/apply/rollback 参与。firewalld 仅作只读外部预检，事务禁止 add/delete/reload；缺少所需 allow 或既有归属账本时在 prepare 阶段失败并要求人工规则。`firewall-cmd` 的 reload 会影响运行时防火墙状态，命令语义以[官方手册](https://firewalld.org/documentation/man-pages/firewall-cmd.html)为准；UFW comment 不作为规则身份，地址语法以[Ubuntu ufw(8) 手册](https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html)为准。本记录不据此宣称 UFW runtime 已验证。配置、状态、受管防火墙或重启失败时使用原快照恢复，rollback 失败保留 journal 与恢复材料，并要求 `instance recover` 或人工检查；缺少防火墙 journal 时恢复本身失败并转人工处理。文件状态的 `.bak` 和回滚只覆盖文件原语，不能宣称其他进程端口、动态 relay、ACME 临时监听或系统防火墙具有完整事务。

防火墙采用单一前端策略：UFW 活动时只通过 UFW 管理，firewalld 活动时只做外部预检，两者都不活动才直接管理 iptables/ip6tables。两个前端同时活动或已有账本归属于非选中后端时拒绝写入，不自动迁移、删除旧规则。这样避免同时向 UFW 及其底层重复登记归属；规则查询区分入站/出站、目标/来源及 IPv6 等价地址，回滚时若用户已修改 comment 则报告不确定并保留该规则。

交互菜单新增 17「管理 Mixed 实例」，对 schema 2 提供逐实例创建、修改、删除、默认、迁移和恢复。旧的协议删除菜单在活动 Mixed 与其他协议同时选择时拒绝跨协议批量删除，并要求先通过 Mixed 实例入口逐个处理；单独选择 Mixed 才进入逐实例删除流程。该保护避免把其他协议或尚未确认的 Mixed 实例一起移除。

新增六项本地回归覆盖 schema 2 生命周期、两版核心运行、显式迁移、状态匹配、失败恢复、菜单与防火墙归属。预审关闭了隐式监听扩大、候选混入回滚备份、schema 2 标记执行/降级、UFW 目标/来源及 comment 归属误判、双重防火墙管理、操作退出 0 却无实际效果、失败恢复缺少持久审计等问题。最后的恢复审计补修在 Bash 5 与实际 Bash 4.2 下再次通过；持久结果保留脱敏 `transaction.firewall`，即使恢复或审计写入失败，也明确报告失败并保留恢复材料。

最终全量回归累计 172/172 通过：158 项普通测试的逐项记录为 `/tmp/sbv-mixed-lifecycle-ordinary.5S6CsR/summary.tsv`，14 项验证框架测试为 `/tmp/sbv-mixed-lifecycle-verification.Wlffu8/summary.tsv`。普通测试运行期间包含最后一次恢复审计小修，最新生命周期测试已覆盖该修复；不是把此前存在失败或源码漂移的运行直接记为最终成功。默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `dev/verification-runs/20260907113104` 退出 0：57 项本地检查、9/9 Docker 场景、12/12 既有 TCP 探针成功，失败升级结果为 `status=rolled_back`、`rollback.result=success`。直接从本次容器读取的安装脚本 SHA-256 为 `6a06a7c91f085faffc5370f881952e0e5bdfd6c46b68176e69dd3064838c57ef`，与最终源码一致。

Mixed 生命周期的真实 1.13.18/1.14.0 各完成 migration=1、instances=2、TCP=7、UDP=7、错误认证拒绝=1、失败候选保留旧服务=1；省略 `listen` 的旧配置在全局 `::` 默认下迁移后仍为 `127.0.0.1`。实际 Bash 4.2 通过直接执行 runtime 测试的 `--run` 分支复验两版核心，日志 `/tmp/sbv-mixed-lifecycle-bash42.aocZVs/`；不是只用旧 Bash 启动随后切回新 Bash 的外层 runner。这些是本机回环 TCP/UoT UDP payload 证据，不证明公网原生 UDP associate 或其他协议的 UDP 数据路径。

父代理另外以最终源码独立复跑 UFW 0.36.2：`/tmp/instance_firewall_ufw_runtime.sh`，证据 `/tmp/instance_firewall_ufw_runtime.final-source.log`，退出 0 且含 `REAL_UFW_INSTANCE_FIREWALL_OK`。实际覆盖 IPv4/IPv6 等价地址、创建/删除/回滚、保留不同目标的预存规则，以及外部 comment 替换和 marker 前后缀伪造时拒绝误删。镜像为 `sing-box-vps-verify:ufw-20260907`，容器使用 `--rm --network none --cap-add NET_ADMIN --cap-add NET_RAW`，仓库只读挂载；没有操作宿主防火墙。firewalld 仍只有只读预检及 mock 证据，不宣称真实运行验证。全协议目标继续进行；未推送、部署、操作生产或执行 SubMan 同步。

### 提交后补修：UFW 注释与规则字段隔离

`855647b` 的提交后审查发现，预存 UFW 入站规则的用户 comment 若含 `ALLOW OUT`，会被整行动作匹配错误地跳过，随后新增同目标规则可能覆盖用户 comment 并误纳入归属账本。修复先分离 comment，动作与地址族只从规则正文判断，端口只在动作之前的目标字段匹配；comment 仅用于完整归属标记比较。本轮脚本版本保持 `2026090708`，不因修复提交重复递增。

防火墙账本与 Mixed 生命周期回归均通过 Bash 5 和实际 Bash 4.2（生命周期 restarts=18）。父代理独立复跑扩展的真实 UFW 0.36.2 隔离测试：预存规则 comment 中的 `ALLOW OUT`、独立 `32126/tcp` token 及 IPv4 wildcard 的 `(v6) ALLOW IN` 均不会改变规则匹配，apply/rollback 保留用户 comment，仅删除本次真正新建的 owned 规则。证据 `/tmp/instance_firewall_ufw_runtime.comment-parser.parent-final.log` 含 `REAL_UFW_INSTANCE_FIREWALL_OK`，日志 SHA-256 为 `3c4e32b4664f244b85b805fd8b7af049984954748f1c1c43e9018730c2fadb71`；临时测试脚本 SHA-256 为 `69fa7af7531c6ac37aabff28edf41d9562968edc0df902e60b2de22c223f4247`。源码 SHA-256 为 `00ca08698551824e18d4e45f358a62b0aa13471413493c1c69f0fe89c156acca`。容器仍采用上述隔离配置，没有操作宿主机防火墙。

修复后的完整默认门禁 `SINGBOX_BINARY_113=… SINGBOX_BINARY_114=… bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh` 在 `dev/verification-runs/20260907115136` 退出 0：57 项本地检查、9/9 Docker 场景、12/12 既有 TCP 探针通过；失败升级结果仍为 `status=rolled_back`、`rollback.result=success`。直接读取运行容器中的脚本哈希与上述 `00ca0869…` 一致；本次两版 Mixed 生命周期 TCP/UoT UDP 和四种版本组合的客户端导出 runtime 也实际重跑通过。前述 172 项全量记录属于主提交验收，本次补修未冒称再次执行全部 172 项。独立防火墙复核未发现新增 P1/P2；未推送或部署，用户未跟踪文件 `1`、`2` 均保留。
