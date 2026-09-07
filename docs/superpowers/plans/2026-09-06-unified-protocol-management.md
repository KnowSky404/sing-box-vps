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
- 第一阶段最终版：`bash dev/verification/run.sh --changed-file install.sh dev/verification/common.sh dev/verification/run.sh dev/verification/remote/entrypoint.sh`，退出 0；证据 `dev/verification-runs/20260907030237`，9/9 场景、12/12 TCP 业务探测成功，包含旧 Mixed 恢复和 Bash 4.2 修复后的代码。Hysteria2 使用 QUIC 传输承载该 TCP 业务；未因此声称 UDP 业务已验证。
- 第一阶段最终版全部非 helper 的 `tests/*.sh`：157/157 通过；逐项退出码 `/tmp/sing-box-vps-final-tests-20260907-bash42fix/summary.tsv`。
- `SINGBOX_BINARY_113=/tmp/sbv-real-schema-final.6rMcum/sing-box-1.13.18-linux-arm64/sing-box SINGBOX_BINARY_114=/tmp/sing-box-v1.14.0-cache/sing-box-1.14.0-linux-arm64/sing-box bash tests/export_client_config_1_14_compatibility.sh`：退出 0，两个实际核心均接受对应客户端配置。
- 本轮版本统一递增为 `2026090601`；目标核心保持稳定 `1.14.0`。阶段内不重复递增。
- 回归发现并修复验证 fixture 的独立 metadata 加载和原固定测试计数；没有改用跳过或 mock 替代真实 Docker 验证。
- 预审期间的 Docker 复验 `dev/verification-runs/20260906170645` 为 9/9 场景、12/12 TCP 探测成功，但当时全量 Shell 为 155/156：发现旧单 Mixed 仅残留索引时不能追加安装的回归。实现现已恢复该明确写入口的无损旧状态恢复，补上索引/凭据保留、状态写入失败回滚和拒绝自定义字段测试，并通过上述最终全量复验。
- 旧 Mixed 恢复还通过了两个实际核心的输入/重新渲染 `check`，同时断言原配置字节和用户名/密码不变；命令 `bash /tmp/sbv-legacy-mixed-real-check.sh`，退出 0。此项为受控配置恢复证据，不替代网络连接探针。
- 2026-09-07 的额外兼容检查在官方 `bash:4.2` 容器复现空 alias 数组的 `nounset` 错误；已修复为空时不展开数组。`tests/protocol_registry_legacy_bash.sh` 在 Bash `4.2.53` 和主机 `5.2.21` 均通过，前者使用只读仓库、无网络容器及临时 `/tmp`。镜像 digest 为 `sha256:326c3fb7e7009e1aa6aad242056abc11c372ac0a2b57dcb29ca5bc8feedf5579`；这证明注册表的旧 Bash 语义兼容，不等于完整 CentOS 系统服务验证。

后续仍需完成阶段 2–5 的所有未勾选要求；本阶段的通过结果不作为新增协议或高级接入已实现的证据。
