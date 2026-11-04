# Docker 定点验证契约

[English](scoped-docker-verification.md) · [SPEC 索引](README.zh-CN.md)

状态：第一阶段已实现并完成定向本地/Docker 验收。第一阶段新增三个可独立选择的组件场景。下方路线图不表示全部共存测试已经拆分；本地/mock、真实 Docker、外部网络和交付证据分别记录。

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

## 第一阶段：有限实现范围

| 场景 ID | 必要基线 | 断言与证据 |
| --- | --- | --- |
| `component_http_outbound` | 全新 SOCKS 安装，空组件 registry 且 revision 为 0 | 创建 typed HTTP 出站及 owned route，检查 live 配置与服务激活，经带认证的 SOCKS→本地 HTTP proxy 取得准确 marker，核对 proxy 收到认证及自定义 header，最后删除并确认 route/outbound 消失。组件 revision 0→1→2。 |
| `component_rule_sets` | 全新 SOCKS 安装，空组件 registry 且 revision 为 0 | 创建/替换 inline、local、remote rule set；真实核心检查与 localhost HTTP 成功拉取；删除三项并确认投影清除、源文件保留。共七次组件变更，revision 0→7。 |
| `component_tor_outbound` | 全新 SOCKS 安装，空组件 registry 且 revision 为 0；可用 Tor executable 和外网 | 创建 typed Tor 出站及限定 ingress 的 route，检查核心与激活，通过带认证 SOCKS 请求 `https://check.torproject.org/` 并核对 Tor marker，记录诊断，最后删除并确认 route/outbound 消失。组件 revision 0→1→2。 |

共享基线场景是 `fresh_install_socks`，不要求安装全部协议；其基线断言继续显示在计划和产物中。最终 `runtime_smoke` 位于所有变更之后，探测最后的 SOCKS 安装。本次仅新增开发选测入口，不新增生产 `sbv` 操作或操作目录 descriptor。

### 场景组合与状态

每个叶子前都必须建立全新 SOCKS 基线，包括一次请求多个叶子的情况。调度器可以每个叶子前重置基线，也可以为每个叶子使用独立新容器。第一阶段采用现有基线/重置机制，不能仅因前一场景安装过 SOCKS 就推断可以复用。

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

### 选测与兼容

帮助及可选场景列表展示三个新增叶子。全量集合继续选择原来的 17 个注册场景，由原聚合入口覆盖对应断言，不额外重复执行三个新增叶子。可选场景 registry 与全量 registry 应分开，并以回归明确验证两者差别。

本地 HTTP/规则集叶子文件变化选择对应叶子及必要基线。共享共存 helper、聚合场景、dispatcher 或外部 Tor 叶子变化不能静默扩大成运行态大矩阵或外网请求；在操作者按实际影响提供显式范围前保持 `needs_scope`。共享 helper 本身不是可执行场景。计划保持只读，并显示准确执行顺序。

```bash
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_http_outbound

bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_rule_sets

# 显式外部网络验收，不作为隐式依赖。
bash dev/verification/run.sh --plan --base origin/main \
  --scenario component_tor_outbound
```

检查所选测试、前置和场景确实覆盖实际改动后，才去掉 `--plan` 执行。一次开发验证不会自动升级为完整发布验收。

## 后续拆分路线图

行号指基线场景，只用于设计定位，不作为运行时截取代码的 offset。共享 fixture 资源必须与最初创建它的组件测试分开。

| 单元 | 基线行范围 | 最小依赖及必须保留的边界 | 阶段 |
| --- | --- | --- | --- |
| 共享 HTTP marker 与 UDP echo | 743–949 | 从 Direct inbound 断言中分离纯 marker 进程；Selector、URLTest、Direct、Block、VLESS、Shadowsocks、SOCKS UDP 复用。 | 后续 |
| 共享 TLS cover/证书 | 275–289、441–479 | owned 本地证书与 1090 cover、子进程清理；ShadowTLS outbound 不需要安装 ShadowTLS inbound。 | 后续 |
| 纯协议/TLS 共存 | 291–500、1700–1765 | 保留 13 协议库存、导出认证/信任及监听检查；仅在新独立场景中省略无关组件适配器。 | 后续 |
| 按协议 TCP/UDP 探针 | 1767–1894 | 单协议基线及生成客户端/core check；区分原生 UDP、XUDP 与 UoT。 | 后续 |
| Naive TCP UoT/HTTP3 转换 | 1776–1871 | libcronet、证书、替换前产物，协议 CAS 1→2；HTTP3 协商与 UoT UDP 载荷分别证明。 | 后续 |
| Snell v6/v5 转换 | 1895–1959 | 协议 CAS 1→2 替换前保存 v6 证据，保留 v5→v4 导出映射及 TCP/packet-API UDP 检查。 | 后续 |
| Direct inbound TCP/UDP | 739–949 | 纯 TCP/UDP marker，独立 owned 组件创建/删除与资源清理。 | 后续 |
| Redirect/TProxy/namespace 策略 | 950–1111 | 可丢弃 root 容器、veth/netns、iptables、policy route；保留 replace/recovery 及 owned chain、mark、rule、route 删除断言。 | 后续 |
| HTTP outbound | 501–738 | SOCKS ingress、独立带认证本地 proxy/marker；叶子补充删除断言。 | 第一阶段 |
| SSH outbound | 1112–1282 | SOCKS ingress、临时 sshd/user/key 及独立 marker。 | 后续 |
| SOCKS outbound TCP | 1283–1536 | SOCKS ingress、独立 upstream SOCKS server 与 marker。 | 后续 |
| Selector/URLTest | 1537–1699 | SOCKS ingress、纯 HTTP marker；URLTest 必须执行真实健康探测。 | 后续 |
| Shadowsocks outbound TCP/UDP | 1960–2056、2967–3153 | SOCKS ingress、SS2022 inbound、TCP marker/UDP echo，保留 route 防环及加密 upstream 证据。 | 后续 |
| Direct/Block outbound | 2057–2341 | SOCKS ingress 与 marker；Direct UDP 要证明目的地 override，Block 要断言拒绝而非 fallback 成功。 | 后续 |
| VLESS outbound TCP/XUDP | 2342–2637 | SOCKS ingress、marker 及 owned upstream/client 进程；保留真实握手与 XUDP 载荷。 | 后续 |
| Tor outbound | 2638–2746 | SOCKS ingress、Tor executable、真实公网 circuit，显式外网成本。 | 第一阶段 |
| ShadowTLS outbound | 2747–2966 | SOCKS ingress、纯 TLS cover、owned upstream/inner listener 与 HTTP detour，四次 CAS 变更。 | 后续 |
| SOCKS outbound UDP | 3154–3534 | SOCKS ingress、带认证的 UDP-associate upstream 与 echo，核对真实 upstream request。 | 后续 |
| Managed rule sets | 47–242、3535 调用 | 本地 HTTP 文件服务、typed 创建/替换/删除、fetch 与最终投影清除断言。 | 第一阶段 |

后续抽取应让 aggregate 与叶子共享断言体，通过明确 revision 基准与 fixture 契约减少双份实现漂移，不能以静态字符串检查代替运行态断言。第一阶段不承诺每个后续单元都已有独立场景 ID。

## 验收与证据记录

1. **本地/静态及 mock**：验证独立/组合选择的叶子和全新基线顺序、最终 smoke、重复请求、无效 ID、全量原清单不重复新增叶子、只读计划、dispatcher 路由、清理以及失败/artifact 结果传播；检查语法、生成安装器/版本一致性、文档链接及真实差异。
2. **真实 Docker**：在干净可丢弃基线上执行 HTTP 出站和规则集叶子，保留 core check、服务状态、载荷/fetch marker、精确 CAS、删除检查及产物提取。记录测得耗时和实际前置，不据此声明公网验收。
3. **外部 Tor**：只有显式真实联网执行成功才形成 Tor 验收。未执行则明确记录未执行，不能用本地/mock 代替。
4. **原聚合/全量**：保留代码及通过调度/选择检查，不表示聚合或全量已运行。未执行的聚合/全量验收单列，不因本 SPEC 或 PR 变化自动启动。

| 证据边界 | 结果及保留证据 |
| --- | --- |
| 本地/静态及 mock 选测/调度检查 | 通过：19 项所选宿主检查，语法、版本/构建同步及差异检查；最终选测策略调整后仅重跑 planner/atomic 检查。 |
| 真实 Docker HTTP outbound 叶子 | 通过：运行 `20261104042431`，真实认证 marker、CAS 0→1→2 及删除清理。 |
| 真实 Docker规则集叶子 | 通过：同一运行，真实 localhost HTTP fetch、CAS 0→7 及删除。 |
| 显式真实联网 Tor 叶子 | 通过：本轮显式选择真实 Tor 页面 marker、创建/删除、核心检查及最终 SOCKS smoke。 |
| 原聚合/注册全量集合 | 默认不执行；原聚合覆盖仍属独立边界。 |
| 当前 HEAD 审查、PR 合并、Wiki 发布 | 见实施 PR 与独立 Wiki 提交；这些门禁与测试证据分开。 |

本机三叶子 Docker 运行总计约 601 秒，包含三次全新 SOCKS 前置、最终 smoke 和产物传输。
按场景产物开始/结束时间戳计算：HTTP 约 59 秒、规则集 350 秒、Tor 66 秒、最终 smoke 7 秒；
叶子耗时不包含各自安装前置。Tor 耗时受公网线路影响。这是一次定向运行，不是与原全量的性能对比。
19 项宿主检查约两分钟，主要成本是原有产物 mock（93 秒）；修复旧清单数量假设后的续跑单独保留。
本轮未执行旧聚合/全量 Docker，不声明生产主机验收。
