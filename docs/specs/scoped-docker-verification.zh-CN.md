# Docker 定点验证契约

[English](scoped-docker-verification.md) · [SPEC 索引](README.zh-CN.md)

状态：已在本 SPEC 的有限运行态范围内通过验收（Accepted）。完整拆分路线图已实现，第二阶段 32 个独立选择的场景及聚合兼容均通过真实 Docker，共 33/33。第一阶段历史证据单独保留，不声明默认 17 场景全量或生产验收。

## 问题与基线

基线 `4aa3b27` 的 `multi_protocol_coexistence.sh` 有 3,536 行，安装 13 个协议族，执行 TCP/UDP 探针、透明代理宿主策略及多个组件适配器，最后还使用真实 Tor 网络。最终 smoke 又会探测全部已安装协议。只修改 HTTP 出站时，所需范围远小于这个聚合场景。

组件 store 使用一条连续 revision：HTTP 出站从 0 开始，SOCKS UDP 结束于 35，最后的规则集生命周期结束于 42。各协议 store 的 revision 相互独立。简单加条件跳过无关区块会破坏聚合场景中硬编码的 revision 和资源前置。拆分必须建立前置，不能删除断言或依赖上次验证的遗留状态。

Tor 区块允许最多 120 秒监听等待，以及 24 次最长 15 秒请求和 1 秒间隔：仅配置等待预算约 8 分 24 秒，尚未包含安装、下载及其他启动工作。这是静态成本分析，不是测得的成功运行时间。

## 不变量

- 保留 `multi_protocol_coexistence` 作为兼容和完整覆盖入口，维持原有协议组合及跨协议断言。
- 小改动使用显式叶子场景，仍保留真实核心校验、激活、数据面、事务/CAS 及清理证据。
- 普通组件选择不能隐式选择 Tor、完整共存、升级或无关协议 fixture。
- 外部服务验证仍是外部证据。mock、配置检查、监听端口或本地 marker 均不能替代可用的真实 Tor circuit。
- 复用现有串行 Docker 传输和 artifact envelope。新增场景是本地可丢弃容器验证，不授权生产修改、真实 SubMan 写入或无关宿主操作。
- 定点检查通过不代表完成全部协议验收。必要范围仍按 [AGENTS.md 第 4.2 节](../../AGENTS.md#42-测试边界与执行策略) 选择。

## 第一阶段：原有组件叶子

| 场景 ID | 必要基线 | 断言与证据 |
| --- | --- | --- |
| `component_http_outbound` | 全新 SOCKS 安装，空组件 registry 且 revision 为 0 | 创建 typed HTTP 出站及 owned route，检查 live 配置与服务激活，经带认证的 SOCKS→本地 HTTP proxy 取得准确 marker，核对 proxy 收到认证及自定义 header，最后删除并确认 route/outbound 消失。组件 revision 0→1→2。 |
| `component_rule_sets` | 全新 SOCKS 安装，空组件 registry 且 revision 为 0 | 创建/替换 inline、local、remote rule set；真实核心检查与 localhost HTTP 成功拉取；删除三项并确认投影清除、源文件保留。共七次组件变更，revision 0→7。 |
| `component_tor_outbound` | 全新 SOCKS 安装，空组件 registry 且 revision 为 0；可用 Tor executable 和外网 | 创建 typed Tor 出站及限定 ingress 的 route，检查核心与激活，通过带认证 SOCKS 请求 `https://check.torproject.org/` 并核对 Tor marker，记录诊断，最后删除并确认 route/outbound 消失。组件 revision 0→1→2。 |

共享基线场景是 `fresh_install_socks`，不要求安装全部协议；其基线断言继续显示在计划和产物中。最终 `runtime_smoke` 位于所有变更之后，探测最后的 SOCKS 安装。本次仅新增开发选测入口，不新增生产 `sbv` 操作或操作目录 descriptor。

### 场景组合与状态

每个叶子前都必须建立全新 SOCKS 基线，包括一次请求多个叶子的情况。调度器可以每个叶子前重置基线，也可以为每个叶子使用独立新容器。实现采用现有基线/重置机制，不能仅因前一场景安装过 SOCKS 就推断可以复用。

删除最后一个组件会留下 revision 单调增加的空 registry。HTTP 测试后的空 registry 是 revision 2，不是 0；规则集测试后是 revision 7。即使配置中已没有组件投影，也不能把删除后的状态当作新的 revision-0 基线。不得使用临时读取 revision 或自动重试来掩盖这一问题、绕过原本要验证的 CAS。

例如，HTTP 与规则集组合请求的顺序是：

```text
fresh_install_socks
component_http_outbound
fresh_install_socks
component_rule_sets
runtime_smoke
```

重复请求同一个叶子按既有请求规则去重；不同叶子之间必要的基线重置不去重。此前的 HTTP 安装、升级、聚合场景或组件删除均不能省略重置。无效选择在执行前失败。

## 第二阶段：完整可选范围

下列每个场景均从各自的 `fresh_install_socks` 开始。组件叶子只创建必要的本地 upstream、marker 和组件记录；协议叶子额外只安装目标协议，SOCKS 叶子直接使用基线实例。共享 HTTP/UDP marker 和 TLS cover fixture 独立拥有并清理子进程，不依赖原来创建它们的 Direct 或 ShadowTLS 组件。生成的服务端和探针客户端配置仍须经过真实核心检查。

| 场景 ID | 保留的运行态边界 |
| --- | --- |
| `component_ssh_outbound` | 临时 sshd、user/key 和独立 marker，认证出站数据面及 owned route 创建/删除。 |
| `component_socks_outbound` | 独立带认证 upstream SOCKS server、TCP marker 及实际 upstream request。 |
| `component_selector_outbound` | 经选中 owned outbound 取得 marker，核对 selector 投影及生命周期。 |
| `component_urltest_outbound` | 真实 URLTest 健康请求、选中路径 marker 及组件删除。 |
| `component_shadowsocks_outbound` | SS2022 upstream、真实 TCP marker、加密 upstream 与 route 防环。 |
| `component_shadowsocks_udp_outbound` | 独立 SS2022 upstream、UDP echo 和加密 UDP 数据面。 |
| `component_direct_outbound` | TCP marker、UDP 目的地 override 及 owned route 创建/删除。 |
| `component_block_outbound` | 明确断言 Block 拒绝，fallback 成功不能满足断言。 |
| `component_vless_outbound` | owned VLESS upstream/client fixture、真实 TCP 握手和 XUDP 载荷。 |
| `component_shadowtls_outbound` | 本地 TLS cover、inner upstream、真实 HTTP detour 及四次 CAS 变更，不安装无关 ShadowTLS inbound。 |
| `component_socks_udp_outbound` | 带认证 UDP-associate upstream 与 echo，核对真实 upstream request。 |
| `component_direct_inbound` | 独立 TCP/UDP Direct 组件和准确 marker，删除两个组件并确认监听/route 消失，registry 0→4。 |
| `component_redirect_inbound` | Redirect 数据面与 owned NAT chain，创建/删除、fixture 和监听清理，registry 0→2。 |
| `component_tproxy_inbound` | namespace/veth TCP/UDP、两次 managed replace、诊断，删除 owned chain、mark、policy rule 和 route，registry 0→4。 |
| `component_transparent_policy` | 不创建 Direct 组件的 Redirect/TProxy 组合及联合诊断，registry 0→6，完整清理 owned 资源。 |

协议探针均有明确 ID；`vless_reality` 是 VLESS REALITY 协议族在场景中的规范化后缀。

| 协议探针 ID | 数据面及额外依赖 |
| --- | --- |
| `protocol_probe_vless_reality` | 生成客户端的 TCP/UDP，复用现有仅交互测试 fixture 及外部 `www.cloudflare.com` TLS cover；须显式选择外网验收。 |
| `protocol_probe_mixed` | TCP/UDP。 |
| `protocol_probe_hy2` | TCP/原生 UDP，目标证书及客户端检查。 |
| `protocol_probe_anytls` | TCP 和 UoT 承载 UDP。 |
| `protocol_probe_socks` | 全新 SOCKS 基线的 TCP/UDP。 |
| `protocol_probe_http` | 仅 TCP，不声明 UDP。 |
| `protocol_probe_shadowsocks` | TCP/UDP。 |
| `protocol_probe_trojan` | TCP/UDP，目标证书及客户端检查。 |
| `protocol_probe_tuic` | TCP/原生 UDP，目标证书及客户端检查。 |
| `protocol_probe_vmess` | 生成客户端的 TCP/UDP。 |
| `protocol_probe_snell` | Snell v6 TCP/packet-API UDP；替换由独立场景验证。 |
| `protocol_probe_shadowtls` | 原有 HTTP-over-ShadowTLS 组合 TCP 探针，不声明 UDP/UoT。 |
| `protocol_probe_naive` | 初始 TCP 和 UoT UDP，模式转换由独立场景验证。 |
| `protocol_naive_transition` | 保存 TCP/UoT 证据，协议 CAS 1→2 后验证 UDP-only/HTTP3 传输承载 TCP；保留 libcronet 和证书前置。 |
| `protocol_snell_transition` | 保存 v6 TCP/UDP 证据，协议 CAS 1→2 替换为 v5，保留 v5→v4 客户端映射及两版 TCP/packet-API UDP。 |
| `protocol_coexistence` | 13 协议库存、导出认证/信任、监听和各协议探针，省略组件适配器及由独立场景选择的转换；包含须显式选择的 REALITY 外部 cover 边界。 |

协议 fixture 保留原验收路径，不新增生产操作目录能力，也不消除既有 `interactive_only` 限制。原生 UDP、XUDP、UoT 和 HTTP3 协商分别断言，不能以其他协议探针成功为仅支持 TCP 的协议补充 UDP 声明。协议探针和纯协议共存保留已安装配置/证书供最终 smoke 使用；Naive/Snell 转换分别保留 UDP-only/v5 最终态。fixture 清理移除 owned peer 和临时工作目录，不删除该安装状态。

### 选测与兼容

帮助和可选 registry 提供以上全部叶子。默认 `--full` 仍选择原来的 17 个场景，由 `multi_protocol_coexistence` 覆盖协议和组件断言，不重复执行新叶子。aggregate 与叶子共享断言体并显式传入 revision 基准；aggregate 保留原组件 revision 链和组合断言。兼容验收必须实际运行共享路径，不能只确认场景 ID 仍可选择。

普通本地叶子变化可选择对应叶子及其基线。共享 fixture/断言、aggregate、dispatcher 或外部 REALITY/Tor 场景变化保持 `needs_scope`，直到操作者按实际影响指定范围。helper 本身不是可执行场景，不能为消除未知影响而静默选择全部调用方、完整共存或外网。计划保持只读，并展示准确的重置/探针/smoke 顺序。

```bash
# 目标出站，同时保留完整分支差异自动检查。
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_vless_outbound

# 单协议探针，避免安装其他十二协议。
bash dev/verification/run.sh --plan --base origin/main \
  --scenario protocol_probe_hy2

# 无其他组件适配器的宿主网络策略验证。
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_tproxy_inbound

# 显式外部网络验收，不作为隐式依赖。
bash dev/verification/run.sh --plan --base origin/main \
  --scenario protocol_probe_vless_reality
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_tor_outbound
```

检查测试、前置和场景确实覆盖实际改动后，才去掉 `--plan`。开发验证不自动升级为完整发布验收。每个叶子都取得全新基线；最终 `runtime_smoke` 在全部变更后仅执行一次，探测最终安装状态。

## 已实现的拆分路线图

行号指基线场景，只用于设计定位，不作为运行时截取代码的 offset。共享 fixture 资源必须与最初创建它的组件测试分开。

| 单元 | 基线行范围 | 最小依赖及必须保留的边界 | 实现及当前验收 |
| --- | --- | --- | --- |
| 共享 HTTP marker 与 UDP echo | 743–949 | 从 Direct inbound 断言中分离纯 marker 进程；Selector、URLTest、Direct、Block、VLESS、Shadowsocks、SOCKS UDP 复用。 | 已实现；定向 Docker 通过（证据见下文） |
| 共享 TLS cover/证书 | 275–289、441–479 | owned 本地证书与 1090 cover、子进程清理；ShadowTLS outbound 不需要安装 ShadowTLS inbound。 | 已实现；定向 Docker 通过（证据见下文） |
| 纯协议/TLS 共存 | 291–500、1700–1765 | 保留 13 协议库存、导出认证/信任及监听检查；仅在新独立场景中省略无关组件适配器。 | 已实现；定向 Docker 通过（证据见下文） |
| 按协议 TCP/UDP 探针 | 1767–1894 | 单协议基线及生成客户端/core check；区分原生 UDP、XUDP 与 UoT。 | 已实现；定向 Docker 通过（证据见下文） |
| Naive TCP UoT/HTTP3 转换 | 1776–1871 | libcronet、证书、替换前产物，协议 CAS 1→2；HTTP3 协商与 UoT UDP 载荷分别证明。 | 已实现；定向 Docker 通过（证据见下文） |
| Snell v6/v5 转换 | 1895–1959 | 协议 CAS 1→2 替换前保存 v6 证据，保留 v5→v4 导出映射及 TCP/packet-API UDP 检查。 | 已实现；定向 Docker 通过（证据见下文） |
| Direct inbound TCP/UDP | 739–949 | 纯 TCP/UDP marker，独立 owned 组件创建/删除与资源清理。 | 已实现；定向 Docker 通过（证据见下文） |
| Redirect/TProxy/namespace 策略 | 950–1111 | 可丢弃 root 容器、veth/netns、iptables、policy route；保留 managed replace、失败清理及 owned chain、mark、rule、route 删除断言。 | 已实现；定向 Docker 通过（证据见下文） |
| HTTP outbound | 501–738 | SOCKS ingress、独立带认证本地 proxy/marker；叶子补充删除断言。 | 已实现；第二阶段 Docker 复验通过（历史证据另保留） |
| SSH outbound | 1112–1282 | SOCKS ingress、临时 sshd/user/key 及独立 marker。 | 已实现；定向 Docker 通过（证据见下文） |
| SOCKS outbound TCP | 1283–1536 | SOCKS ingress、独立 upstream SOCKS server 与 marker。 | 已实现；定向 Docker 通过（证据见下文） |
| Selector/URLTest | 1537–1699 | SOCKS ingress、纯 HTTP marker；URLTest 必须执行真实健康探测。 | 已实现；定向 Docker 通过（证据见下文） |
| Shadowsocks outbound TCP/UDP | 1960–2056、2967–3153 | SOCKS ingress、SS2022 inbound、TCP marker/UDP echo，保留 route 防环及加密 upstream 证据。 | 已实现；定向 Docker 通过（证据见下文） |
| Direct/Block outbound | 2057–2341 | SOCKS ingress 与 marker；Direct UDP 要证明目的地 override，Block 要断言拒绝而非 fallback 成功。 | 已实现；定向 Docker 通过（证据见下文） |
| VLESS outbound TCP/XUDP | 2342–2637 | SOCKS ingress、marker 及 owned upstream/client 进程；保留真实握手与 XUDP 载荷。 | 已实现；定向 Docker 通过（证据见下文） |
| Tor outbound | 2638–2746 | SOCKS ingress、Tor executable、真实公网 circuit，显式外网成本。 | 已实现；聚合 Docker 通过，第一阶段历史另保留 |
| ShadowTLS outbound | 2747–2966 | SOCKS ingress、纯 TLS cover、owned upstream/inner listener 与 HTTP detour，四次 CAS 变更。 | 已实现；定向 Docker 通过（证据见下文） |
| SOCKS outbound UDP | 3154–3534 | SOCKS ingress、带认证的 UDP-associate upstream 与 echo，核对真实 upstream request。 | 已实现；定向 Docker 通过（证据见下文） |
| Managed rule sets | 47–242、3535 调用 | 本地 HTTP 文件服务、typed 创建/替换/删除、fetch 与最终投影清除断言。 | 已实现；聚合 Docker 通过，第一阶段历史另保留 |

aggregate 与叶子共享断言体，使用明确的 revision 基准和 fixture 契约。本地契约检查组合及失败清理，不能替代真实数据面或内核资源断言。既有 managed replace/失败清理与显式注入故障后执行 `component recover` 命令的验收是不同边界，后者证据应单独记录。

## 验收与证据记录

1. **本地/静态及 mock**：验证全部叶子选测/分流、单选和组合请求的全新基线、最终 smoke、重复/无效请求、原全量清单兼容、只读计划、显式外网边界、owned 清理及失败/artifact 传播；检查语法、版本/构建同步、链接和完整差异。
2. **第二阶段真实 Docker**：在全新可丢弃基线上执行每个新增出站、策略、协议叶子和两个模式转换场景，保留服务端/客户端核心检查、服务状态、准确载荷、CAS、删除及清理证据，记录实际前置和逐场景结果/耗时。
3. **外部网络**：REALITY 探针/协议共存和 Tor 需显式选择并取得真实联网成功证据，本地 marker 或 mock 不能替代。外网不可用时明确验收未完成，不能静默换断言。
4. **聚合兼容**：共享断言抽取后实际执行 `multi_protocol_coexistence`，保留原库存、CAS 链及跨协议/组件检查。本次有限拆分验收不要求重跑无关升级、卸载等原全量场景；未执行的默认 17 场景全量仍是独立证据边界。
5. **完成条件**：第二阶段全部叶子及聚合兼容均取得真实 Docker 结果后，才能确认完整拆分通过验收。第一阶段历史结果和本地契约检查均不能代替第二阶段表格。

### 第一阶段历史验收

以下结果属于运行 `20261104042431`，保留其历史证据，不表示第二阶段代码已通过相同检查。

| 证据边界 | 结果及保留证据 |
| --- | --- |
| 本地/静态及 mock 选测/调度检查 | 通过：19 项所选宿主检查，语法、版本/构建同步及差异检查；最终选测策略调整后仅重跑 planner/atomic 检查。 |
| 真实 Docker HTTP outbound 叶子 | 通过：运行 `20261104042431`，真实认证 marker、CAS 0→1→2 及删除清理。 |
| 真实 Docker规则集叶子 | 通过：同一运行，真实 localhost HTTP fetch、CAS 0→7 及删除。 |
| 显式真实联网 Tor 叶子 | 通过：本轮显式选择真实 Tor 页面 marker、创建/删除、核心检查及最终 SOCKS smoke。 |
| 原聚合/注册全量集合 | 第一阶段未执行；第二阶段聚合兼容与默认全量保持独立边界。 |
| 当前 HEAD 审查、PR 合并、Wiki 发布 | 见实施 PR 与独立 Wiki 提交；这些门禁与测试证据分开。 |

本机三叶子 Docker 运行总计约 601 秒，包含三次全新 SOCKS 前置、最终 smoke 和产物传输。
按场景产物开始/结束时间戳计算：HTTP 约 59 秒、规则集 350 秒、Tor 66 秒、最终 smoke 7 秒；
叶子耗时不包含各自安装前置。Tor 耗时受公网线路影响。这是一次定向运行，不是与原全量的性能对比。
19 项宿主检查约两分钟，主要成本是原有产物 mock（93 秒）；修复旧清单数量假设后的续跑单独保留。
该历史运行未执行旧聚合/全量 Docker，不声明生产主机验收。

### 第二阶段当前验收

31 个新增叶子及重构后的 HTTP 叶子均独立通过，共 32 个场景，各自具备全新 SOCKS 基线和必要 fixture。聚合兼容也已通过，本 SPEC 的运行态验收共 33/33。下表秒数来自实际场景产物时间戳，只排除独立调度的 `fresh_install_socks` 前置、最终 smoke 和产物传输；场景内部安装计入耗时，包括单协议叶子的目标协议安装、纯共存的其余协议安装，以及 aggregate 内部的 13 协议安装。不能与第一阶段三叶子整轮 601 秒直接比较，也不能据此宣称相对默认 17 场景全量的加速比。

| 证据边界 | 当前结果 |
| --- | --- |
| 首轮集成宿主检查 | 通过：运行 `20261104073759` 的 27 项所选检查，覆盖计划、分流、产物、叶子/fixture 契约和相关文档；其 `VERIFY_SKIP_REMOTE` 只构成宿主证据。 |
| 修复后的定向续验 | 通过：Redirect 部分创建/所有权及 TProxy 非法 registry 清理、URLTest 独立健康请求、HTTP 共享函数搬移和叶子选择。仅重跑受影响契约，未改变输入的既有结果保留。 |
| 结构化协议探针检查 | 通过：新增 `tests/verification_protocol_probe_structured_basics.sh`、已有 HY2/AnyTLS 探针和矩阵检查；新增检查也在合入 archive-owner 基线后通过。 |
| 默认原 17 场景全量 | 本次有限拆分验收未执行也不要求，不声明全量通过。 |
| 当前 HEAD 本地/安全审查、PR 合并及 Wiki 发布 | 证据分别记录于实施 PR 与 Wiki 历史，与本运行态表格分开。 |

| 场景 | 真实 Docker 运行 | 场景秒数 | 结果 |
| --- | --- | --- | --- |
| `component_http_outbound` | `20261104074232` | 59 | 通过 |
| `component_block_outbound` | `20261104074232` | 59 | 通过 |
| `component_direct_inbound` | `20261104075528` | 180 | 通过 |
| `component_direct_outbound` | `20261104074232` | 59 | 通过 |
| `component_redirect_inbound` | `20261104075528` | 83 | 通过 |
| `component_selector_outbound` | `20261104074232` | 59 | 通过 |
| `component_shadowsocks_outbound` | `20261104074232` | 93 | 通过 |
| `component_shadowsocks_udp_outbound` | `20261104075528` | 93 | 通过 |
| `component_shadowtls_outbound` | `20261104075528` | 160 | 通过 |
| `component_socks_outbound` | `20261104074232` | 58 | 通过 |
| `component_socks_udp_outbound` | `20261104075528` | 59 | 通过 |
| `component_ssh_outbound` | `20261104074232` | 59 | 通过 |
| `component_tproxy_inbound` | `20261104075528` | 236 | 通过 |
| `component_transparent_policy` | `20261104075528` | 406 | 通过 |
| `component_urltest_outbound` | `20261104074232` | 58 | 通过 |
| `component_vless_outbound` | `20261104075528` | 64 | 通过 |
| `protocol_coexistence` | `20261104083008` | 459 | 通过 |
| `protocol_naive_transition` | `20261104083008` | 70 | 通过 |
| `protocol_probe_anytls` | `20261104083008` | 31 | 通过 |
| `protocol_probe_http` | `20261104083008` | 24 | 通过 |
| `protocol_probe_hy2` | `20261104083008` | 32 | 通过 |
| `protocol_probe_mixed` | `20261104083008` | 30 | 通过 |
| `protocol_probe_naive` | `20261104083008` | 33 | 通过 |
| `protocol_probe_shadowsocks` | `20261104083008` | 24 | 通过 |
| `protocol_probe_shadowtls` | `20261104083008` | 29 | 通过 |
| `protocol_probe_snell` | `20261104083008` | 29 | 通过 |
| `protocol_probe_socks` | `20261104083008` | 1 | 通过 |
| `protocol_probe_trojan` | `20261104083008` | 40 | 通过 |
| `protocol_probe_tuic` | `20261104083008` | 33 | 通过 |
| `protocol_probe_vless_reality` | `20261104082117` | 40 | 通过 |
| `protocol_probe_vmess` | `20261104083008` | 40 | 通过 |
| `protocol_snell_transition` | `20261104083008` | 67 | 通过 |
| `multi_protocol_coexistence` 兼容 | `20261104085357` | 6164 | 通过：保留原 CAS 0→42 及完整共享协议/组件断言编排。 |

普通出站各约 58–93 秒；ShadowTLS 出站 160 秒，Direct 入站 180 秒，TProxy 236 秒，透明策略组合 406 秒。单协议探针各 1–40 秒；Snell/Naive 转换分别 67/70 秒；纯协议共存 459 秒。以上仅为本机场景时间，只排除独立调度的基线、最终 smoke 和传输，不是整个开发任务的周转耗时。特别是 aggregate 的 6164 秒包含内部 13 协议安装；随后 final smoke 50 秒通过，远端执行和产物提取均退出 0。单协议加 SOCKS 基线、HTTP 组件叶子和完整 aggregate 覆盖不同范围，这些实测不是与原 17 场景全量的受控性能对照。

运行 `20261104082117` 已通过显式 REALITY 验收，随后 Mixed 探针因验证代码仍按旧标量认证/状态读取 typed 实例而失败。修复仅将 Mixed/HY2/AnyTLS 的验证探针取值适配到既有生产 exporter；`20261104083008` 从 Mixed 及其余协议/转换/共存场景续跑并全部通过。REALITY 的受测路径和依赖未变，复用已通过结果，没有重启全部已通过叶子。

首批组件运行 `20261104074232` 的远端退出为 0，完整 artifact bundle 已生成；运行期间编辑私有 driver 导致本地提取返回 2。随后直接恢复并提取原完整 bundle，`summary.log` 保留 `remote_status=success_from_recovered_complete_artifacts` 和 `recovery=original_complete_bundle_extracted_without_rerunning_scenarios`。保留此 driver 故障记录，不将最初执行描述成完全无故障；成功场景没有重跑。

HTTP fixture/断言函数后来只搬移位置，内容未变：`verification_atomic_http_fixture` 的 SHA-256 仍为 `61b9d04a7b011fce6591185957cc664e03d5c273002b164b8cd0cb66fba77e4b`，`verification_case_http_outbound` 仍为 `3ad78ba263640756ad1f3de7fa2d4fb1d5612aed217b80cf3fe112802a1e6694`。搬移后定向宿主检查通过，复用上表真实 HTTP 结果。交付 worktree 合入 archive-owner 基线 `1e0e781`；该上游修改仅涉及历史归档，不到达这些全新安装/组件路径，共享 storage gate 的判定保持不变，核心仍为 1.14.2。经过此影响核对后复用既有组件证据，不因 worktree 或 hash 变化重跑。

表中聚合兼容通过，已闭合本 SPEC 的有限运行态验收。第一阶段 Tor/规则集历史、当前显式 REALITY、当前独立叶子、聚合兼容、全量和生产仍分别记录。
