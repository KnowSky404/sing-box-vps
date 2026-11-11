# 运行目录与备份

统一目录及旧版迁移见 [目录迁移](https://github.com/KnowSky404/sing-box-vps/wiki/Storage-Layout)。先执行 `sbv storage status --json`；迁移或恢复需显式 `--yes`，普通操作不会静默迁移。


- **工作目录**: `/root/.sing-box-vps/runtime/`
- **配置文件**: `/root/.sing-box-vps/runtime/config.json`
- **脚本生成基线及其备份**: `/root/.sing-box-vps/runtime/managed-config.generated.json` / `managed-config.generated.json.bak`（权限 600，包含敏感运行材料）
- **上一版配置备份**: `/root/.sing-box-vps/runtime/config.json.bak`
- **最后协议删除前的索引备份**: `/root/.sing-box-vps/runtime/protocols/index.env.bak`
- **协议状态目录**: `/root/.sing-box-vps/runtime/protocols/`
- **密钥文件**: `/root/.sing-box-vps/runtime/reality.key` (REALITY) / `warp.key` (Warp)
- **协议状态文件**: `vless-reality.env` / `vless-reality.d/` / `mixed.env` / `instances/mixed.json` / `socks.env` / `instances/socks.json` / `http.env` / `instances/http.json` / `shadowsocks.env` / `instances/shadowsocks.json` / `trojan.env` / `instances/trojan.json` / `vmess.env` / `instances/vmess.json` / `vless-plain.env` / `instances/vless-plain.json` / `hy2.env` / `anytls.env` / `instances/anytls.json` / `snell.env` / `instances/snell.json` / `tuic.env` / `instances/tuic.json` / `hysteria.env` / `instances/hysteria.json` / `naive.env` / `instances/naive.json` / `shadowtls.env` / `instances/shadowtls.json`
- **Trojan 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/trojan.json`（schema 1 store，`trojan.env` 为 schema 2 active marker）
- **VMess 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/vmess.json`（schema 1 store，`vmess.env` 为 schema 2 active marker）
- **AnyTLS 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/anytls.json`（schema 1 store，`anytls.env` 为 schema 2 active marker；仅保留手工 TLS，无法无损接管 ACME/provider）
- **Hysteria2 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/hy2.json`（schema 1 store，`hy2.env` 为 schema 2 active marker；支持手工 TLS 与逐实例 ACME；保留用户、带宽、obfs、masquerade）
- **Snell 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/snell.json`（schema 1 store，`snell.env` 为 schema 2 active marker；记录版本、PSK、用户 key、v5 obfs 或 v6 shaping；无标准 URI/SubMan 同步）
- **TUIC 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/tuic.json`（schema 1 store，`tuic.env` 为 schema 2 active marker；记录 UUID/密码用户、手工 TLS、QUIC 参数与客户端出站 relay/udp-over-stream；无标准 URI/SubMan 同步）
- **Hysteria 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/hysteria.json`（schema 1 store，`hysteria.env` 为 schema 2 active marker；记录 `name`/`auth_str` 用户、手工 TLS、上下行带宽、obfs 与 QUIC 参数；无标准 URI/SubMan 同步）
- **NaiveProxy 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/naive.json`（schema 1 store，`naive.env` 为 schema 2 active marker；记录用户名/密码用户、手工 TLS、客户端信任、TCP/UDP 网络和 Naive/QUIC 出站选项；无标准 URI/SubMan 同步，官方 outbound 需要 `with_naive_outbound` 与 `libcronet.so`）
- **ShadowTLS 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/shadowtls.json`（schema 1 store，`shadowtls.env` 为 schema 2 active marker；记录 v1/v2/v3 凭据、握手映射、strict/wildcard SNI、loopback Mixed detour 和客户端信任；无标准 URI/SubMan 同步）
- **Mixed 结构化实例状态**: `/root/.sing-box-vps/runtime/protocols/instances/mixed.json`（显式迁移或实例写入后启用）
- **Mixed 事务恢复材料**: `/root/.sing-box-vps/runtime.instance-write.lock`、`/root/.sing-box-vps/runtime.instance-transactions/`
- **高级组件状态**: `/root/.sing-box-vps/runtime/components.json`（schema 1、独立 revision；list/diagnose 脱敏，export 敏感）
- **高级组件事务材料**: `/root/.sing-box-vps/runtime.component-write.lock`（持久 journal、快照与外部资源恢复材料）
- **REALITY QoS 状态**: `/root/.sing-box-vps/runtime/reality-qos.filters`
- **Warp 分流域名**: `/root/.sing-box-vps/runtime/warp-domains.txt`
- **Warp 本地规则集目录**: `/root/.sing-box-vps/runtime/rule-set/warp/`
- **Warp 远程规则集列表**: `/root/.sing-box-vps/runtime/warp-remote-rule-sets.txt`
- **流媒体验证脚本缓存**: `/root/.sing-box-vps/modules/media-check/region_restriction_check.sh`
- **SubMan API 配置**: `/root/.sing-box-vps/runtime/subman.env`
- **Agent 升级备份**: `/root/.sing-box-vps/backups/upgrades/`（包含敏感运行材料，仅 root 可读）
- **内部脚本与核心**: `/root/.sing-box-vps/bin/sbv`、`/root/.sing-box-vps/bin/sing-box`
- **内部服务单元**: `/root/.sing-box-vps/systemd/sing-box.service`
- **管理日志**: `/root/.sing-box-vps/logs/sbv.log`
- **辅助模块默认 HOME/工作目录**: 每次媒体检测独立使用 `/root/.sing-box-vps/tmp/` 下的私有工作区，Cookie/缓存随检测清理；后端脚本仍持久缓存于 `modules/media-check/`。临时 REALITY 检查器也位于统一 `tmp/` 工作区
- **全局命令**: `/usr/local/bin/sbv`（仅链接），核心和系统服务入口也链接至统一根
