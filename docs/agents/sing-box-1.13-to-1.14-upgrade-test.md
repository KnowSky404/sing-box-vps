# Hermes 单主机 sing-box 1.13 → 1.14 审计演练

本演练面向一台测试主机，默认 Hermes 已在目标主机的 root shell 中运行。若 Hermes 从控制机操作，把每条目标机命令包在 `ssh sing-box-test '...'` 中；不要使用旧的 `sing-box-test-0`/`sing-box-test-1` 别名。目标是证明升级过程可审计、可回滚，并确认配置没有被隐式重写。

## 安全分类

- 只读：`capabilities`, `upgrade-check`, `status`, `check`, `doctor`, `nodes`, `warp`。
- 有副作用：`upgrade`, 服务重启、客户端导出、SubMan 同步。
- 敏感：`links`, 客户端导出和 SubMan 输出包含可用连接材料。
- 仅交互：安装/追加/修改/移除协议，REALITY 多实例与 QoS，Warp、BBR、媒体检测，接管/修复和卸载。

生产主机必须先提交 operation plan 并等待明确批准。未知主机按生产处理。

## 能力矩阵

| 能力 | 入口 | 分类 | 审计要点 |
|---|---|---|---|
| VLESS + REALITY | 交互安装/修改；`nodes`/`links` | 修改为交互；摘要只读；links 敏感 | Reality key、SNI、ALPN、flow；不得手改生成 config |
| Mixed HTTP/SOCKS | 交互安装/修改；nodes/links | 修改交互；links 敏感 | 认证状态与端口；摘要不得含密码 |
| Hysteria2 | 交互安装/修改；nodes/links/export | 修改交互；export/links 敏感 | ACME/provider、obfs、masquerade、Ed25519 client warning |
| AnyTLS | 交互安装/修改；nodes/links/export | 修改交互；export/links 敏感 | ACME/provider、`client_metadata`、导出 check |
| Snell | 交互安装/修改；nodes/links/export | 修改交互；export/links 敏感 | 仅 1.14；v5/v6、PSK/user key、v5 obfs/v6 shaping、无标准 URI/SubMan |
| REALITY 多实例 | 交互菜单 | 交互/变更 | instance state、端口、ShortID、节点名逐实例一致 |
| REALITY QoS | 交互菜单 | 交互/变更 | `tc` 规则与 `reality-qos.filters` 无残留 |
| Warp | 菜单 13；`agent warp --json` | 查询只读；变更交互 | endpoint、路由模式、规则集、账户状态 |
| 入站/出站栈 | 系统管理菜单 | 交互/变更 | IPv4/IPv6 listen、DNS strategy、direct resolver |
| BBR | 系统管理菜单 | 交互/变更 | sysctl 变更需计划与证据 |
| 媒体检测 | 菜单 12 | 交互/外部网络 | 仅在获批环境执行，记录出口模式和结果 |
| 接管/修复 | 菜单/交互 | 交互/高风险 | 先 check、备份，再恢复 service/binary/state |
| 客户端导出 | `agent export-client --json` | 变更+敏感 | 写文件、覆盖前备份、check 通过；不改 server config |
| SubMan 同步 | `agent subman-sync --json` | 外部变更+敏感 | 需要凭据；记录稳定错误/重试语义，不记录 token/raw |
| 服务 start/stop/restart | 菜单；`agent service restart --json --yes` | 变更 | restart 前 check；必须记录前后状态 |
| sing-box 升级 | `agent upgrade --json ... --yes` | 变更/服务影响 | 自动备份、逐字节保留 config、失败恢复 binary |
| 卸载 | 菜单 5/16 | 破坏性变更/交互 | 必须单独批准；确认删除范围与备份可恢复性 |

## 0. 更新 Agent 操作面

旧主机上的 sing-box 可以保持 1.13.x，但必须先把管理脚本更新到包含结构化升级接口的版本：

```bash
sbv update sbv
```

该命令更新完会退出，随后开启一个新的 shell/命令调用并验证：

```bash
sbv agent capabilities --json | jq -e '.ok == true and (.script_version | tonumber) >= 2026090202'
```

若旧脚本没有 `update sbv`、更新来源不可验证、版本仍低于 `2026090202`，立即停止，不要退回交互式核心升级。应由操作者先通过仓库 README 中的官方入口更新 `sbv`。

## 1. 只读预检

```bash
hostname
command -v sbv
command -v sing-box
sing-box version
systemctl is-active sing-box
sbv agent capabilities --json
sbv agent status --json
sbv agent upgrade-check --json 1.14.0
sbv agent check --json
sbv agent doctor --json
```

预检必须确认：实例 healthy、当前为 1.13.x、目标为 1.14.0、`ready=true`、`blockers=[]`、当前配置 check 通过、没有未处理的残缺状态，并记录完整 JSON 输出。`upgrade-check` 不下载目标二进制，所以此时 `target_binary_validation.performed=false` 是预期值；目标 1.14 校验在有备份的升级事务中、重启服务前完成。若命令不存在、输出不是合法 JSON、服务非 active、当前 check 失败或出现 blocker，立即终止。

## 2. 升级前证据与批准门

升级接口会自动持久化 root-only 备份至 `/root/sing-box-vps-backups/`，不需要再把完整运行目录打包到 `/tmp`。执行前只记录不泄密的校验信息：

```bash
sha256sum /root/sing-box-vps/config.json /usr/local/bin/sing-box
stat -c '%n %s %Y %a %U:%G' /root/sing-box-vps/config.json
```

Hermes 此时应提交操作摘要：主机、当前/目标版本、`blockers`、warnings、预期服务重启、自动备份位置、成功条件与停止条件，并等待明确批准。不得把密钥、密码、完整 config、协议状态文件或 `links` 写入共享日志。备份包含敏感运行材料，不得复制到共享 artifact。

## 3. 结构化升级

```bash
evidence_dir=$(mktemp -d /root/sing-box-vps-upgrade-evidence.XXXXXXXX)
chmod 700 "${evidence_dir}"
set +e
sbv agent upgrade --json 1.14.0 --yes \
  > "${evidence_dir}/upgrade.json" \
  2> "${evidence_dir}/upgrade.stderr.log"
upgrade_status=$?
set -e
jq . "${evidence_dir}/upgrade.json"
```

成功条件：命令退出码为 0，JSON 合法，`schema_version="1.0"`、`ok=true`，目标版本为 `1.14.0`，`rolled_back=false`，`config_preserved=true`，配置 hash 与升级前一致，目标 binary check 通过，服务明确报告 active。`transaction.result_persisted` 必须为 true，`transaction.status` 必须为 `success`，其 `result_path` 应位于 JSON 返回的 `backup` 目录。`backup` 必须位于 `/root/sing-box-vps-backups/upgrade-*`，且 `SHA256SUMS` 校验通过；该清单覆盖 runtime 中的全部普通文件，以及 binary、`sbv`、service unit 和备份元数据。权限 `0600` 的 `transaction-result.json` 不纳入该静态清单，而是反向记录清单路径与 SHA-256，并保留 `backup_ready` 到终态的历史。

该操作只更新 binary；不得自动重写或迁移 `config.json`。1.13 的 inline `tls.acme` 与 `download_detour` 在 1.14 仍是弃用但兼容字段，计划在 1.16 移除。需要迁移时必须另行评审、备份和执行，不得把迁移伪装成 binary upgrade。

## 4. 升级后验证

```bash
sing-box version
sbv agent status --json
sbv agent check --json
sbv agent doctor --json
sha256sum /root/sing-box-vps/config.json
systemctl is-active sing-box
journalctl -u sing-box -n 100 --no-pager
backup=$(jq -r '.backup' "${evidence_dir}/upgrade.json")
case "${backup}" in
  /root/sing-box-vps-backups/upgrade-*) ;;
  *) printf 'unexpected backup path: %s\n' "${backup}" >&2; exit 1 ;;
esac
(cd "${backup}" && sha256sum -c SHA256SUMS)
transaction_result=$(jq -r '.transaction.result_path' "${evidence_dir}/upgrade.json")
case "${transaction_result}" in "${backup}"/transaction-result.json) ;; *) exit 1 ;; esac
jq -e '.schema_version == "1.0" and .status == "success" and .rollback.attempted == false' "${transaction_result}"
[[ "$(stat -c '%a' "${transaction_result}")" == "600" ]]
```

根据已安装协议分别执行真实客户端闭环探测；VLESS REALITY、Mixed、Hysteria2、AnyTLS、Snell、Warp 路由和 REALITY QoS 不能因 `sing-box check` 成功就推定业务可用。Snell 的 UDP 业务由 TCP 会话 packet API 承载，当前专项没有独立 UDP payload 探针。只有被明确批准时才执行媒体检测或 SubMan 写入。

## 5. 失败与回滚

若 target binary 下载失败、目标 check 失败、服务未恢复 active、JSON 缺字段或配置 hash 变化：

1. 不重复执行升级，不手工编辑运行配置。
2. 保存 `upgrade.json`、stderr、journal、版本和 hash 证据。
3. 只有 `rolled_back=true`、`rollback_ok=true`、`transaction.result_persisted=true` 且事务记录的终态为 `rolled_back` 时，才确认旧版本已恢复；同时核对旧 binary `sing-box check` 通过且服务回到升级前的 active/inactive 状态。
4. 确认服务仍使用旧 binary/旧配置，或保持 stopped 并报告人工介入。

若返回 `error=rollback_failed`、`rolled_back=false`、`rollback_ok=false` 或 `manual_intervention_required=true` 中任一状态，立即停止自动化。只有再次获得明确批准后，才能从 JSON 指向的备份目录人工恢复。恢复前必须校验路径前缀与 `SHA256SUMS`；不得猜测“最新备份”，不得覆盖未确认的配置。

终止条件：任何 secrets 泄露、备份不存在或校验失败、配置发生未授权变化、回滚状态不明确、服务状态不确定、或一次结构化升级失败。此时停止自动化并请求人工决定，不自动进行第二次升级。

## 1.14 兼容性边界

- ACME：1.14+ 新生成配置使用顶层 `certificate_providers`；旧 `tls.acme` 仅兼容，不应在本演练中自动迁移。
- 远程规则集：1.14+ 新生成结构使用 `http_client.detour`；旧 `download_detour` 仍保留兼容性，但计划在 1.16 移除。
- Hysteria2 Ed25519：这是客户端语义边界。1.14 client export 可设置顶层 `disable_chrome_parrot=true`；分享链接和 SubMan raw 不能表达该开关，必须读取结构化 warning。
- Snell：1.14-only 的 v5/v6 入站与 v4/v6 出站版本映射、PSK 长度和 obfs/shaping 字段必须在目标核心 check 前核验；没有标准 URI 或 SubMan sync 路径。
- VLESS Reality、Mixed、AnyTLS、Snell、WARP endpoint、DNS、路由、栈模式、BBR、媒体检测和 QoS 必须在升级后分别核验，不因 binary check 通过而推断业务可用。

## 交付报告模板

报告至少包含：主机与时间、`sbv` 脚本版本、当前/目标核心版本、预检结果与 warnings、批准记录、升级命令退出码、备份路径及 manifest 校验、升级 JSON、配置 hash 前后、check 结果、服务/journal 结果、协议闭环结果、回滚结果、敏感输出是否已脱敏，以及是否触发任何终止条件。
