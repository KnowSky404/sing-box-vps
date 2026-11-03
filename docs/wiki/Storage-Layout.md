# 统一目录与旧版升级迁移

项目实际文件统一存放在 root 账户主目录的 `.sing-box-vps`，通常为 `/root/.sing-box-vps`。路径不跟随调用者 HOME 或当前目录变化。

| 子目录 | 内容 |
| --- | --- |
| `runtime/` | 配置、协议实例、密钥、ACME、WARP、组件及规则集 |
| `bin/`、`lib/` | 管理脚本、核心和受管可选库 |
| `modules/` | 可重新下载的辅助检查模块 |
| `logs/`、`tmp/` | 管理日志、下载/探测/临时快照 |
| `backups/upgrades/` | 新布局核心升级备份 |
| `backups/`、`migrations/` | 旧布局备份、迁移 journal 和恢复材料 |
| `runtime.*` | 管理锁、实例/组件/规则事务及结果 |
| `systemd/` | 服务单元实际文件 |

`/usr/local/bin/sbv`、`/usr/local/bin/sing-box` 和 `/etc/systemd/system/sing-box.service` 为系统入口，实际 payload 在统一根。系统包、journal、sysctl 与内核网络资源仍由系统管理；外部手工证书和输入文件保留原路径。

## 从旧版本升级

旧版更新脚本后，数据可能仍在 `/root/sing-box-vps`、`/root/sing-box-vps-backups`。包括仅保留旧普通 sbv、核心已卸载的旧状态。新脚本发现旧布局会阻止普通操作，避免按空的新目录重建。先查看状态，再明确迁移：

```bash
sbv storage status --json
sbv storage migrate --json --yes
```

兼容 `sbv agent storage ...`。菜单启动时提供同一迁移入口；帮助和操作目录不触发迁移。迁移暂停原活动服务以复制一致状态，复制和校验计入停机窗口；停止的服务保持停止。冲突、权限/链接异常或旧事务未完成时拒绝覆盖；不要手工合并状态或删除锁绕过保护。旧事务需使用已保留或固定旧版本运行时恢复；旧自更新可能已覆盖全局旧脚本。当前自动迁移要求旧数据、新根和系统入口父目录在同一文件系统；旧 Tor/Tailscale/Taildrop、ACME/OriginCA 或 API dashboard 的隐式目录、相对文件路径和隐式 cache_file 位置需先定位为明确路径，避免生成新身份、证书账户或丢失状态。自定义工作目录/环境的旧服务单元及有效 drop-in 需先由操作者调和；自动迁移会拒绝这些情形。

受管路径随数据调整，密码、实例身份和外部引用保持。仅迁移已识别的旧目录旁文件，未知同前缀用户文件原位保留；旧树含符号链接或特殊文件时需先调和。历史升级备份按原字节归档，仅作为离线恢复材料，不能直接输入新布局的升级恢复流程。

辅助检查模块使用私有 HOME/XDG/工作目录和临时目录；流媒体 Cookie 不会落在调用者当前目录。

## 故障恢复

未完成迁移保留 journal 并阻止普通操作。读取 status 后执行：

```bash
sbv storage recover --json --yes
```

恢复目标是旧布局和原服务活动状态。`rollback_failed` 表示仍需保留备份和 journal；目录恢复不代表服务恢复。管理员在中断后替换的外部命令或库遇到 ownership_conflict 会被保留，迁移 journal 也会保留，不能强行覆盖。完成后重新检查 status，再决定是否迁移。

核心卸载保留管理入口和备份；彻底卸载明确报告保留的恢复材料。外部输入不删除。完整设计见 [统一存储 SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/unified-storage.zh-CN.md)。仓库与 Docker 验证不表示生产主机已迁移。
