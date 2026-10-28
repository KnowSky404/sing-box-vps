# Agent 命令参考

## 常用命令

| 操作 | 命令 |
| --- | --- |
| 打开交互菜单 | `sbv` |
| 查看状态 | `sbv agent status --json` |
| 检查运行配置 | `sbv agent check --json` |
| 查看 Agent 能力 | `sbv agent capabilities --json` |
| 检查指定核心版本的升级条件 | `sbv agent upgrade-check --json 1.14.0` |

主要支持 VLESS + REALITY、普通 VLESS、Mixed、SOCKS、HTTP、Shadowsocks、Trojan、VMess、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 和 ShadowTLS 入站。每种协议的运行条件、导出和验证范围见[能力矩阵](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Coverage)。

## Agent 非交互命令

适合在 SSH 会话中查询状态、导出配置或执行受控操作。常用只读命令见上方；完整命令和事务语义如下。


```bash
sbv agent capabilities --json
sbv agent upgrade-check --json 1.14.0
sbv agent upgrade --json 1.14.0 --yes
sbv agent status --json
sbv agent nodes --json
sbv agent links --json
sbv agent export-client --json
sbv agent check --json
sbv agent doctor --json
sbv agent service restart --json --yes
sbv agent warp --json
sbv agent subman-sync --json
sbv agent component list --json
sbv agent component diagnose --json
sbv agent component export --json --id ID [--expected-revision N]  # 敏感输出
sbv agent component recover --json --yes --expected-revision N
sbv agent component takeover --json --yes --expected-revision N [--allow-public]
sbv agent component rebuild --json --yes --expected-revision N
sbv agent component create|replace --json --yes --expected-revision N --file component.json [--allow-public]
sbv agent component delete --json --yes --expected-revision N --id ID
sbv agent instance view <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance diagnose <protocol> --json [--id ID] [--expected-revision N]
sbv agent instance export <protocol> --json [--id ID] [--expected-revision N]  # 敏感输出
sbv agent instance create|replace <protocol> --json --yes --expected-revision N --file record.json [--allow-public]
sbv agent instance delete|default <protocol> --json --yes --expected-revision N --id ID
sbv agent instance rebuild <protocol> --json --yes --expected-revision N
sbv agent instance takeover <protocol> --json --yes --expected-revision 0 [--allow-public]
sbv agent instance migrate mixed --json --yes --expected-revision N
sbv agent instance recover <protocol> --json --yes --expected-revision N
sbv update sbv
sbv update sing-box latest
sbv update sing-box 1.14.2
```

代码块中的 `create|replace`、`delete|default` 只是二选一记法，实际执行时
只保留一个操作词；`<protocol>` 替换为支持的协议 ID，并从同一状态快照
读取 `--expected-revision`。

其中 `<protocol>` 的只读入口支持 `vless-reality`、`mixed`、`socks`、`http`、`shadowsocks`、`trojan`、`vmess`、`vless-plain`、`anytls`、`hy2`、`snell`、`tuic`、`hysteria`、`naive` 和 `shadowtls`；写入口支持除 `vless-reality` 外的其余协议，只有 `mixed` 支持 `migrate`。`view` 和 `diagnose` 默认脱敏，`export`、`links`、`export-client` 与 `subman-sync` 应只在受信上下文使用。

- `capabilities`：输出协议、历史功能入口与 `mutation` / `sensitive` / 确认要求，Agent 应先据此选择操作。旧 `protocol_registry` 保持兼容，并为每个协议增加只读 `environment` 核心版本/构建依赖观察；`managed_registry` 将普通协议与高级组件按 role 合并，使用 `registry_kind` 区分来源。协议级 `available=null` 仍表示尚未完成实例预检，`validated.status=not_assessed` 表示没有该实例的数据面验证；环境依赖满足不等于已部署或连接通过。
- `upgrade-check`：只读检查固定目标版本的升级资格，返回 `ready`、`blockers[]`、当前核心校验、配置 hash、已知弃用项和兼容性 warning；不会协调或迁移协议状态，也不下载目标二进制，真正的目标版本 `sing-box check` 在 `upgrade` 替换服务进程前执行。
- `upgrade`：必须使用完整版本号和 `--yes`。创建持久备份后只替换核心二进制，逐字节保留服务端配置；备份清单覆盖全部普通 runtime 文件及 binary、`sbv`、service unit、metadata。每次实际变更返回 `transaction.id`、`transaction.result_path` 和 `transaction.result_persisted`，并在备份目录原子写入权限 `0600` 的 `transaction-result.json`。实际变更只有 `result_persisted=true` 才可接受事务状态；若目标版本已经安装，则返回 `changed=false`、`transaction.status=not_attempted`、`reason=already_installed`，且不会创建备份或事务文件。目标校验、版本、配置 hash 或服务状态不符合预期时尝试自动恢复旧二进制、意外变化的配置和升级前服务活动状态，返回非零与结构化回滚结果。仅当 `rolled_back=true` 且 `rollback_ok=true` 时才可视为自动恢复完成；`error=rollback_failed` 时必须停止并人工处理。
- `status`：输出脚本/核心/服务/路径/已安装协议，并包含入站与出站栈、BBR、REALITY 实例与 QoS 计数，以及客户端导出/SubMan 是否已配置；不返回凭据。索引、状态或 live 入站集合无法完整对应时返回非零及 `protocol_index_untrusted` / `protocol_state_untrusted`，不报告部分协议。
- `nodes`：输出所有协议的安全摘要；REALITY、Mixed、SOCKS、HTTP、Shadowsocks、Trojan、VMess、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 和 ShadowTLS 均逐实例输出，`instance_revision` 可用于下一次 CAS 写入；不包含 UUID、密钥、完整分享链接或密码，适合写入普通诊断日志。实例清单、状态与 live 入站不完整时不输出部分节点。
- `links`：逐协议、逐 REALITY/Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/Hysteria2/Hysteria/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS 实例输出完整连接材料，包括 VLESS/VMess/Hysteria2 分享链接、Mixed/SOCKS 链接，以及 Hysteria/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS outbound JSON；Hysteria、AnyTLS、Snell、TUIC、NaiveProxy、ShadowTLS 分别返回 `hysteria_standard_uri_unavailable`、`anytls_standard_uri_unavailable`、`snell_standard_uri_unavailable`、`tuic_standard_uri_unavailable`、`naive_standard_uri_unavailable`、`shadowtls_standard_uri_unavailable` warning；Naive 还返回 `naive_libcronet_required`，仅在受信任上下文使用，并沿用与 `nodes` 相同的全有或全无清单门禁。Hysteria2 手动 Ed25519 证书会附带稳定的 `warnings[].code`，提示分享链接无法表达 1.14+ 客户端兼容开关。
- `warp`：输出 Cloudflare Warp 状态（启用/路由模式/账户/自定义域名规则集统计），安全用于日常诊断。
- `export-client`：生成并通过 `sing-box check` 校验裸核客户端配置，写入 `/root/sing-box-vps/client/sing-box-client.json`，覆盖前创建 `.bak` 备份，同时以 JSON 返回路径和配置内容。对 1.14+ Hysteria2 Ed25519 节点会自动设置顶层 `disable_chrome_parrot: true` 并返回结构化 warning。包含 Mixed 或独立 SOCKS 时逐实例导出为 SOCKS5 + UoT v2，并返回明文传输 warning；Trojan/VMess/普通 VLESS/Hysteria v1/AnyTLS/Snell/TUIC/NaiveProxy/ShadowTLS 按用户完整导出传输与明确的证书信任方式，不读取服务端私钥，不自动关闭验证。Naive outbound 需要官方 `with_naive_outbound` 和 `libcronet.so`；VMess URI 与客户端 JSON 均保留 V2Ray `security`、`alter_id` 和 typed transport；Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy 与 ShadowTLS 无标准 URI，使用完整 outbound JSON。
- `check`：执行 `sing-box check` 校验服务端配置，并返回 stdout、stderr、退出码和是否通过。
- `doctor`：输出只读诊断报告，包含服务状态、路径存在性、协议状态和嵌入的配置校验结果。
- `service restart`：必须显式传入 `--yes`，先校验配置，通过后才重启服务，并返回重启前后的服务状态。
- `subman-sync`：非交互推送节点到 SubMan；配置缺失时返回结构化错误，不进入交互提示。API 失败时会在 `last_error` 返回稳定的 `code`、`disposition`、HTTP 状态与可用的 `Retry-After`，传输结果不确定时不会盲目重放写请求。Hysteria2、Trojan 与 VMess 使用独立逐实例/用户路径，Hysteria v1、TUIC、AnyTLS、Snell、NaiveProxy 明确跳过并返回原因；仅 TLS 系统信任且 URI 可无损表达的条目进入同步。
- `instance`：管理结构化 Mixed/SOCKS/HTTP/Shadowsocks/Trojan/VMess/VLESS plain/AnyTLS/Hysteria2/Snell/TUIC/Hysteria/NaiveProxy/ShadowTLS 实例。`view`/`diagnose` 是共享锁保护的只读入口，默认脱敏；`export` 是敏感入口，返回完整 typed record 与连接材料。Agent 的连接材料按 `127.0.0.1` 生成，仅表示本机/受信上下文的连接基线，不是公网地址或可达性证明。`rebuild` 在精确 CAS 下修复受管配置漂移并递增 revision；`takeover` 只接管无 active typed state 的可无损 live inventory，默认拒绝公网监听，必须显式 `--allow-public`。`migrate` 仅把 Mixed legacy schema 1 转成 revision 1；`create`/`replace`/`delete`/`default` 使用 `--expected-revision`，凭据通过私有文件输入；删除最后一个实例后保留 revision tombstone，下一次写入不能把 CAS 重置为 0；`recover` 只处理可验证的未完成事务。首次全新安装仍写 legacy schema 1，直到显式迁移。
- `component`：管理高级入站、Endpoint、可复用出站/分组、ACME provider、shared `http_client`、network namespace 和 typed `route.rule_set`。`list`/`diagnose` 只返回元数据、环境/资源和事务摘要；`export` 按 ID 返回完整记录，是敏感操作。`create`/`replace`/`delete`/`takeover`/`rebuild`/`recover` 使用独立 schema 1 revision/CAS 和持久事务目录 `/root/sing-box-vps.component-write.lock`，候选会执行引用图、监听资源与目标核心 `sing-box check`；非回环监听、TUN、隧道和 OpenVPN server 需要 `--allow-public`。高级组件不进入普通节点分享、客户端导出或 SubMan 同步。
- `instance <operation> socks`：使用 `view`/`diagnose`/敏感 `export` 读取，以及 `create`/`replace`/`delete`/`default`/`rebuild`/`takeover`/`recover`、`--expected-revision`、typed record、共享事务和回滚边界管理独立 SOCKS；记录只表达 SOCKS 入站的监听/认证，不含 HTTP 或 TLS。`migrate socks` 明确返回 invalid arguments；已有 live SOCKS 配置应使用 takeover，不把 legacy `.env` migration 语义套到该预设。实例生命周期、两核心 check/runtime、菜单、接管和 Agent/export 回归及最终 Docker/TCP 门禁已通过，但不应从注册表存在推断为全协议目标完成。
- `instance <operation> http`：操作与 SOCKS 相同，但完整记录必须包含 `tls: {enabled:false}` 或手工 TLS 的 `enabled/server_name/certificate_path/key_path`。非回环写入须显式 `--allow-public`，无 legacy migration。记录示例与限制见 [Agent Runbook](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-Runbook)。HTTP TLS 节点的 `shareable=false`、`client_exportable=true`，不将空链接视为可用 URI。
- `instance <operation> shadowsocks`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 `listen.network` 和 `authentication`，完整示例见 [Agent Runbook](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-Runbook#shadowsocks-inbound)。`nodes` 不输出密钥；敏感的 `links` 返回逐用户 URI、outbounds 与限制 warning。
- `instance <operation> vmess`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一 `name`/UUID/`security`/`alter_id` 用户、TLS 信任和 typed V2Ray transport（none/http/ws/grpc/quic）。分享和 SubMan 仅接受 TLS 系统信任且 URI 可无损表达的用户；完整边界见 [VMess 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#vmess-typed-instance-contract)。
- `instance <operation> anytls`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一用户名/密码、必需手工 TLS 证书路径、server name、客户端 `certificate`/`system` 信任和出站策略。AnyTLS 没有标准分享 URI，`links` 返回凭据 outbound JSON 与 `anytls_standard_uri_unavailable` warning；`nodes` 不返回密码。legacy AnyTLS 的 ACME/provider 配置不自动迁移到 typed store，接管会拒绝无法无损表达的字段；完整边界见 [AnyTLS 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#anytls-typed-instance-contract)。
- `instance <operation> hy2`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一用户名/密码、ACME 自动签发或手工 TLS、`certificate`/`system` 客户端信任、可独立设置的 `up_mbps`/`down_mbps`、Salamander obfs、masquerade 和出站策略。新增协议和实例创建默认提供 ACME HTTP-01 / Cloudflare DNS-01；自动证书使用系统信任，已有 ACME/provider 参数在新增实例时无损保留；标准 Hysteria2 URI 按用户生成，证书信任、URI 大小、带宽/masquerade 和 Ed25519 客户端开关均返回结构化 warning；完整边界见 [Hysteria2 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#hysteria2-typed-instance-contract)。
- `instance <operation> hysteria`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个唯一 `name`/`auth_str` 用户、必需手工 TLS、`certificate`/`system` 客户端信任、上下行 `up_mbps`/`down_mbps`、字符串 obfs 与 QUIC 参数。服务端渲染为 `type: hysteria` 的 UDP/QUIC 入站并自动加入 `alpn:["h3"]`；客户端按用户输出完整 outbound JSON，`links` 返回 `hysteria_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [Hysteria 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#hysteria-typed-instance-contract)。
- `instance <operation> snell`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含版本 `5`/`6`、PSK、0–128 个唯一用户 key、v5 `none/http` obfs（HTTP host 作为客户端元数据）或 v6 `default/unshaped/unsafe-raw` shaping。Snell listener 固定 TCP，UDP 业务依赖 packet API；客户端导出逐用户保留 `network:["tcp","udp"]` outbound JSON，`links` 返回 `snell_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [Snell 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#snell-typed-instance-contract)。
- `instance <operation> tuic`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个 UUID/密码用户、手工证书 TLS、客户端 `certificate`/`system` 信任、拥塞控制、auth timeout、heartbeat 和 zero-rtt。服务端是 QUIC/UDP 入站，`udp_relay_mode` (`native`/`quic`) 与 `udp_over_stream` 只在客户端出站生效，不会写入入站。客户端按用户输出完整 TUIC outbound JSON，`links` 返回 `tuic_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [TUIC 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#tuic-typed-instance-contract)。
- `instance <operation> naive`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 1–128 个用户名/密码用户、手工 TLS、客户端 `certificate`/`system` 信任、`listen.network`、QUIC 拥塞控制、窗口、并发和额外 headers。服务端按 TCP/UDP 选择渲染 Naive 入站；客户端按用户输出完整 Naive outbound JSON，`links` 返回 `naive_standard_uri_unavailable` 和 `naive_libcronet_required`，不执行 SubMan 同步。完整边界见 [NaiveProxy 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#naiveproxy-typed-instance-contract)。
- `instance <operation> shadowtls`：支持 `create`/`replace`/`delete`/`default`/`recover` 与 revision CAS，拒绝 `migrate`；记录包含 v1/v2/v3 凭据、握手服务器与 SNI 映射、strict/wildcard SNI、客户端 `certificate`/`system` 信任和 loopback Mixed detour。服务端渲染 ShadowTLS 外层与隐藏的 loopback Mixed 内层；客户端按用户输出完整 outbound JSON，`links` 返回 `shadowtls_standard_uri_unavailable`，不执行 SubMan 同步。完整边界见 [ShadowTLS 契约](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Instances#shadowtls-typed-instance-contract)。
- `update sbv`：从 GitHub 更新 `/usr/local/bin/sbv` 管理脚本；别名为 `sbv update-sbv`。
- `update sing-box [latest|x.y.z]`：普通运维更新入口，逐字节保留现有配置，目标核心校验通过后才重启服务，失败明确返回非零；别名为 `sbv update-sing-box [latest|x.y.z]`。自动化升级优先使用上面的固定版本 `agent upgrade`。

Mixed 实例写入使用类型化记录文件；`create` 和 `replace` 必须通过 `--file` 提供一个完整 JSON 对象，不接受命令行凭据。示例（`replace` 时 `id` 和 `tag` 必须保持原值，不能借此改身份）：

```json
{
  "id": "main",
  "name": "办公 Mixed",
  "tag": "mixed-in",
  "listen": {"address": "127.0.0.1", "port": 1080},
  "authentication": {
    "enabled": true,
    "username": "proxy-user",
    "password": "请替换为私有凭据"
  },
  "outbound_policy": "default",
  "dependencies": []
}
```

记录只允许上述字段；`listen`、`outbound_policy` 和 `dependencies` 也会参与候选配置及依赖检查，当前 `dependencies` 必须为空数组。写入成功后，根状态标记为 `CONFIG_SCHEMA_VERSION=2`，结构化文件以 `schema_version: 1`、`protocol: "mixed"`、单调 `revision`、`default_instance_id` 和 `instances[]` 封装该记录。`nodes`/`links` 是只读发现入口，可用于找到实例 `id`/tag；若输出 `instance_revision`，写入 CAS 应使用它，否则应从同一状态快照读取 revision（当前 `capabilities` 只声明需要 revision，不提供当前值），不能用猜测值覆盖并发修改。`recover` 是例外：必须使用未完成事务 journal 中原始的 `expected_revision`，不能拿当前 store revision 冒充恢复条件。

交互式管理会话在整个菜单期间持有排他管理 `flock`；需要先选择菜单 0 退出会话，其他 Agent 读写才能取得同一管理锁。Agent 只读操作使用共享锁，写入使用排他锁；锁冲突或未完成事务会返回结构化错误，不会静默绕过锁。

实例结果的 `transaction.firewall` 保留后端可用性和脱敏诊断，并同步写入持久 result 文件；事务目录清理后仍可审计。`unavailable` 不代表已开放防火墙，也不代表公网业务已验证。

已有 1.13.x 主机应先运行 `sbv update sbv` 更新管理脚本，再调用 `capabilities` 与 `upgrade-check`。1.14 对旧版 inline `tls.acme` 和远程规则集 `download_detour` 会给出弃用 warning，但两者到 1.16 才移除，因此 warning 本身不会阻止 1.13→1.14；其他真实不兼容会在目标 1.14 二进制的 `sing-box check` 阶段阻止重启并触发回滚。

### `sbv` 自更新的失败语义

`sbv update sbv` 和 `sbv update-sbv` 使用同一套事务流程：`PRECHECK → STAGE → VALIDATE → BACKUP → COMMIT → POSTCHECK → CLEANUP`。远程内容只会写入 `/usr/local/bin` 同目录的候选文件，候选必须通过非空/最小大小、预期 shebang、`bash -n`、唯一 `SCRIPT_VERSION`、项目身份和版本单调性校验，之后才会使用同目录原子 `mv` 提交。候选 SHA-256 仅用于本地提交前后完整性核对，不代表远端签名或供应链认证。

- 下载或校验失败：`changed=false`、`rollback_attempted=false`，原有 `sbv` 的内容、权限和所有者保持不变；CLI 返回非零，交互菜单展示错误摘要后继续运行。
- 当前版本相同且目标健康：安全 `no-op`，不会创建备份或替换目标文件。
- 提交后 postcheck 失败：自动恢复备份，并再次校验旧版本、SHA-256、Bash 语法和执行权限，报告 `rolled_back=true`。
- `rollback_failed`：自动恢复未通过，报告 `manual_intervention_required=true`，并保留 root-only 备份和候选恢复文件。请先按错误提示人工恢复并重新执行 `bash -n`、版本、SHA-256 与执行权限校验，再运行 `sbv`。

交互菜单 15 更新成功后会自动切换到新版管理菜单；如果磁盘文件已是最新版、当前进程仍运行旧版，也会切换。当前进程和文件都已是最新版时继续当前菜单。CLI 更新成功后正常退出，下次运行 `sbv` 即使用新版。自动切换失败时会保留当前菜单并提示退出后重新运行 `sbv`，已安装的更新仍然有效。错误摘要和脱敏诊断会写入 `/root/sing-box-vps/sbv.log`；日志写入失败不会覆盖原始更新错误。

首次从不含自动切换逻辑的旧版升级时，旧进程仍需退出后重新运行一次 `sbv`；进入新版后，后续菜单更新会自动切换。

Agent/Hermes 文档入口：

- [Agent 快速上下文](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/agents/llms.txt)
- [完整 Agent 运维手册](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-Runbook)
- [Hermes 单主机 1.13→1.14 演练](https://github.com/KnowSky404/sing-box-vps/wiki/Upgrade-Rehearsal)
- [可安装 Operator Skill](https://github.com/KnowSky404/sing-box-vps/blob/main/skills/sing-box-vps-operator/SKILL.md)

## 升级事务验收

升级前在 `/root/sing-box-vps-backups/` 创建仅 root 可读的持久备份。实际升级只有 `transaction.result_persisted=true` 且 `transaction.status=success` 才能接受成功。目标已安装时是无变更结果：`transaction.status=not_attempted`、`transaction.reason=already_installed`，不要求不存在的事务文件。失败时按 `rolled_back` 与 `rollback_ok` 判断恢复结果，不以退出码代替回读。
