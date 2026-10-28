# 验证记录与边界

本页保留有用的历史探针、运行目录和失败边界，供追溯使用，不是当前安装步骤。旧实现计划和逐步任务清单已移除，可从 Git 历史查阅。当前范围以[能力矩阵](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Coverage)和运行时 `sbv agent capabilities --json` 为准。以下命令包含历史核心路径，重新执行前须准备相应依赖。

## 2026-09-11：Hysteria v1/Hysteria2 Docker 数据面探针

`fresh_install_hysteria` 远程场景现在生成持久于验证容器生命周期的自签名 SAN 证书，安装 Hysteria v1 后用受管状态导出单用户客户端；导出器保留 `auth_str`、`up_mbps/down_mbps`、公开证书（不含私钥）和显式 `h3` ALPN。固定 1.14.0 核心的服务端 UDP listener、客户端 SOCKS listener、HTTP marker 与 SOCKS5 UDP ASSOCIATE marker 均在 Docker 回环内通过；`multi_protocol_coexistence` 对 Hysteria2、SS2022、Trojan QUIC、TUIC 与 VMess QUIC 也完成同一 UDP marker 回环，TUIC/VMess 客户端 exporter 的 `h3` ALPN 与服务端协商保持一致，同时 VMess/VLESS QUIC exporter 保留 `tcp+udp` proxy network。`fresh_install_vless_plain` 还验证同一受管实例从 TCP/none 替换为 TLS QUIC、协议索引保持 `vless-plain`，并完成 UDP marker 回环。完整 run `dev/verification-runs/20260911215408` 记录 15/15 场景、24 个常规协议探针结果（23/23 可执行探针成功，1 个既有 TUIC 结果为 `unsupported`），七个 `udp.result.env` 均为 `RESULT=success`，精确 payload 保存在对应 `udp-response.txt`。QUIC 选项输入允许 `0` 表示上游默认；这些结果仍只证明隔离容器/回环业务路径，不证明公网、生产、外部控制面或全协议目标完成。
## 2026-09-11：Snell v6 TCP 数据面探针

`multi_protocol_coexistence` 现在在 VMess 之后创建受管 Snell v6 typed instance（PSK、单用户 key、`mode:"default"`、TCP listener），并把 `snell` 加入 live protocol index 与配置类型断言。远程 entrypoint 先要求活动 schema-2 marker 和 schema-1 Snell store，严格核对选中的 tag、监听端口、版本、认证和 shaping 字段，再调用生产 `build_client_snell_outbounds` 生成探针副本；固定 1.14.0 客户端通过 `sing-box check` 后，经本地 SOCKS listener 访问 HTTP marker，`client.json` 保持 600 权限且不携带服务端私钥。

完整 Docker run `dev/verification-runs/20260911230518` 记录 15/15 场景、25 个常规 protocol result，其中 24/24 可执行探针成功，既有 TUIC 常规结果仍为 `unsupported`；共存场景的 Snell `result.env`、`client.check.txt`、精确 `http-response.txt` 和 typed index/store 均通过。七个既有 Hysteria/Hysteria2/SS2022/Trojan/TUIC/VMess/普通 VLESS UDP artifact 仍为成功；Snell 的 UDP packet API 本轮未单独宣称原生 UDP marker。证据限定在固定 1.14.0 核心、隔离 Docker 与回环业务路径，不代表公网可达、生产部署、外部认证、SubMan 或全协议目标完成。

## 2026-09-14：Snell UDP packet API 数据面探针

在 TCP 切片基础上，`multi_protocol_coexistence` 现在也调用共享 `verification_execute_protocol_udp_probe snell`。探针只接受活动 schema-2 marker、schema-1 store 和当前 v6 tag，复用生产 exporter 的 `network:["tcp","udp"]`，先执行固定 1.14.0 client `check`，再经 SOCKS5 UDP ASSOCIATE 发送精确 marker；Snell v6 listener 仍只有 TCP，UDP 语义由该认证 TCP 会话的 packet API 承载。

定向 Docker run `dev/verification-runs/20260914153908` 的 `multi_protocol_coexistence` 与 `runtime_smoke` 均成功；共存 artifact 中 `protocol-probes/snell/result.env`、`udp.result.env` 均为 `RESULT=success`，并保留 TCP/UDP 精确响应、client check、渲染配置与 journal 的 packet-connection 行。该证据只覆盖固定核心、隔离 Docker/回环和受管 exporter，不把 packet API 误写成原生 UDP listener，也不代表公网、生产、外部认证、SubMan 或完整协议目标完成。

在此基础上，定向 Docker run `dev/verification-runs/20260914185411` 的共存场景先保存 v6 的 `protocol-probes/snell-v6/` artifact，再以 `agent instance replace snell --expected-revision 1` 将同一 typed instance 替换为 v5 HTTP-obfs 记录；`snell-v5-replace.json` 报告 `revision:2`、`transaction.status:"success"` 与 `phase:"committed"`。固定 1.14.0 `snell-v5-check.txt` 和渲染配置通过，受管 store 保留 `obfs_host`，客户端 exporter 映射为 version 4、`obfs_mode:"http"`、`network:["tcp","udp"]`；v5 TCP 与 packet-API UDP 的 `result.env`、精确 marker、client check 和 journal 均成功。该证据仍限于隔离 Docker/回环，不把服务端 v5 renderer 的 host 元数据误写进核心配置，不宣称原生 UDP listener、公网、生产、外部认证、SubMan 或完整协议目标完成。

## 2026-09-14：AnyTLS UoT UDP 数据面探针

在既有 AnyTLS TCP marker 之上，`multi_protocol_coexistence` 新增共享
`verification_execute_protocol_udp_probe anytls`。探针由受管 AnyTLS marker/state
生成客户端 outbound，先执行 client `sing-box check`，并确认生成 JSON 不含
可配置的 `network`、`transport` 或 `multiplex` 字段；随后通过 SOCKS5 UDP
ASSOCIATE 发送精确 marker，经 AnyTLS UoT adapter 回到一次性 loopback UDP
echo，保留 `udp.result.env`、`udp-response.txt`、client check 与 stderr。

AnyTLS listener 仍是 TCP，UDP 结果表示 UoT adapter 的业务路径而非原生 UDP
监听。定向 Docker run `dev/verification-runs/20260914165733` 的共存场景与
runtime smoke 均成功，并保留 `inbound UoT connection` journal 行。该验证只
覆盖固定 1.14.0、隔离 Docker/loopback 和受管客户端导出，不能推出公网可达、
生产部署、外部认证、SubMan 或完整协议目标完成。

## 2026-09-23：TUIC TCP/UDP 探针注册修正与验证边界

TUIC 的受管 exporter 已经输出 `network:["tcp","udp"]`。协议 registry 的常规
probe 从 `quic_loopback` 修正为可执行的 `tcp_loopback`，共享 HTTP marker 因而覆盖
TCP proxy leg；专用 UDP helper 继续覆盖 QUIC/UDP listener 上的 native UDP leg。
`tests/protocol_coverage_contract.sh` 现在锁定该 registry 映射，避免 exporter、探针和
覆盖矩阵再次漂移。

完整安装器门禁 `dev/verification-runs/20260923141825` 的本地阶段通过，但远程
`multi_protocol_coexistence` 在 Tor outbound 首次启动遇到既有的
`127.0.0.1:1081` readiness race，整轮 `remote_status=failure`，不得作为全量通过。
随后定向 Docker run `dev/verification-runs/20260923165440`（共存与 runtime smoke）
`remote_status=success`，2/2 顶层场景、33 个 `result.env` 成功；TUIC 的
`protocol-probes/tuic/result.env`、`udp.result.env` 及精确 HTTP/UDP marker 均通过。
证据仅限固定 ARM64 sing-box 1.14.1、特权隔离 Docker 与 loopback，不代表公网、生产、
外部认证、真实 SubMan 或完整协议目标。

## 2026-09-23：Tor outbound listener readiness

`multi_protocol_coexistence` 在 Tor outbound 重启后先等待最多 120 秒的真实
`127.0.0.1:1081` listener，并保存 `tor-socks-listener.ss-lntp.txt`。这是启动同步
条件，不是数据面通过条件；随后仍必须由 `check.torproject.org` marker、Tor journal
以及 `tor-outbound.result.env` 的 `DATA_PLANE=tor_external_tcp` 共同证明业务路径。
完整门禁 `dev/verification-runs/20260923194712` 的两个顶层场景均为
`STATUS=success`/`EXIT_STATUS=0`。证据仅限固定 ARM64 sing-box 1.14.1、特权 Docker
与 loopback/外部 Tor circuit，不覆盖公网、生产、外部认证、真实 SubMan 或完整协议目标。

## 2026-09-24：双版本官方核心本地门禁

如需复核协议适配而不触发 Docker 远程阶段，可使用已校验的官方 ARM64 核心：

```bash
SINGBOX_BINARY_113=/tmp/sing-box-v1.13.18-cache/sing-box-1.13.18-linux-arm64/sing-box \
SINGBOX_BINARY_114=/tmp/sing-box-v1.14.1-cache/sing-box-1.14.1-linux-arm64/sing-box \
VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh \
  --changed-file install.sh tests/protocol_coverage_contract.sh
```

本轮运行目录为 `dev/verification-runs/20260923232318`。两版核心均参与配置 check、
export、启动、TCP/UDP marker、实例生命周期和版本兼容路径；Mixed、SOCKS、HTTP、
Shadowsocks、V2Ray transport、Trojan、VMess、VLESS plain、AnyTLS 及已实现组件合同的
本地输出均通过。该命令的 `summary.log` 只表示远程阶段被显式跳过；需要 Docker 远程证据
时继续参考 `dev/verification-runs/20260923194712`。

不要把这次本地结果扩展为 OpenVPN 系统/TUN、宿主透明控制、外部认证、公网/生产或真实
SubMan 证明；HTTPUpgrade 与 WS early-data 仍按运行时限制记录为 blocked。

## 2026-09-24：统一实例 read/rebuild/takeover 生命周期

普通代理实例的 Agent 只读入口与组件入口保持相同的 stdout envelope：

```bash
sbv agent instance view socks --json --id ID [--expected-revision N]
sbv agent instance diagnose socks --json --id ID [--expected-revision N]
sbv agent instance export socks --json --id ID [--expected-revision N]
```

`view` 返回不含密码、UUID、PSK、私钥或用户认证材料的实例摘要和安全记录；`diagnose`
在共享锁下额外执行当前配置的 `sing-box check`、实例状态/配置匹配和服务活动状态，失败时
保留结构化非零 envelope；`export` 标记 `sensitive:true`，返回完整 typed record 与该实例的
连接材料，只能在受信上下文使用。连接材料以 `127.0.0.1` 为本地基线，不代表公网地址或
可达性。三者均不会隐式迁移 legacy 状态、重写配置或生成凭据。

写入口的统一语义如下：

```bash
sbv agent instance rebuild socks --json --yes --expected-revision N
sbv agent instance takeover socks --json --yes --expected-revision 0 [--allow-public]
```

`rebuild` 只对已 active 的 typed store 工作，跳过“live projection 必须先匹配”的前置条件，
从受管记录重新渲染并递增 revision；其余写操作仍要求状态与 live 配置匹配。`takeover` 拒绝
已 active 的 marker/store、孤立或符号链接状态、缺少协议入站和不能由 typed adapter 无损表达
的字段；默认只接受 `127.0.0.0/8` 与 `::1`，公开监听必须显式 `--allow-public`。接管成功时
候选配置保持现有 `config.json` 字节不变，仅通过完整校验、状态快照、监听/防火墙 journal、
服务 postcheck 和 CAS 发布 typed store。`tests/instance_rebuild_takeover.sh` 覆盖公开确认、
凭据保留、revision 修复、active takeover/stale CAS 拒绝、read-only 脱敏与敏感 export；这
是本地 stub 核心证据；最终双版本本地门禁为 `dev/verification-runs/20260924084053`，
Docker 远程 16 场景为 `dev/verification-runs/20260924062005`。两者均不代表公网、生产、
外部认证或真实 SubMan。

## External Documentation

When current `sing-box` configuration syntax, migration behavior, or version compatibility is needed, use Context7 first. If Context7 cannot provide enough detail, use official `sing-box` documentation or the official repository before relying on third-party posts.
