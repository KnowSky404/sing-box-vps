# 快速开始

需要 root 权限。支持 Debian 11+、Ubuntu 20.04+、CentOS 7+/Stream、AlmaLinux、Rocky Linux；提供 amd64/arm64 架构探测。当前适配核心版本见 [README](https://github.com/KnowSky404/sing-box-vps)，不要把上游 latest 自动视为已适配。

在 VPS 上复制这一行：

```bash
bash -c 'set -euo pipefail; umask 077; t=$(mktemp); trap '\''rm -f -- "$t"'\'' EXIT; curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -o "$t" https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/bootstrap.sh; bash -n "$t"; grep -Fqx '\''readonly PROJECT_AUTHOR="KnowSky404"'\'' "$t"; grep -Fqx '\''readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"'\'' "$t"; bash "$t" install'
```

首段命令先把仓库内的 [bootstrap.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/bootstrap.sh) 下载到权限受限的临时文件，检查 Bash 语法和项目身份，然后运行它。Bootstrap 再下载并校验 [install.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/install.sh)，校验失败不会执行安装器；两层临时文件都会清理。下载来源是仓库 `main` 分支；如需先审查源码，可克隆仓库后运行 `sudo bash install.sh`。

安装完成后，在任意目录输入 `sbv` 打开管理菜单。要彻底卸载，可从克隆的仓库运行 `sudo bash uninstall.sh --yes` 或 `sudo bash bootstrap.sh uninstall --yes`；菜单里的“卸载 sing-box”会删除服务、核心和配置，但会保留 `sbv` 管理命令，独立卸载脚本还会删除全局 `sbv`。

## REALITY SNI 探测

安装 VLESS + REALITY 默认使用 [reality-target-checker](https://github.com/KnowSky404/reality-target-checker) 检测候选 SNI。输入 1–5 个纯域名，以空格或逗号分隔；按输入顺序选择首个检查通过且获接受的域名。工具不发现域名、不提供推荐列表或延迟排名，因此需要自行提供候选；安装器不再内置固定候选，也不会在失败后填入默认域名。更新和新增实例仍可保留或复用已有 SNI，探测失败时重新选择输入方式，不修改当前 SNI。

每个域名检测 DNS A/AAAA 返回的地址、TLS 1.3、证书链/SAN/有效期、h2 和 X25519，并记录 ASN/CDN 等附加线索。默认检查两个地址族；无 IPv6 出站而目标有 AAAA 时可能无法完成，不能视为通过。每项网络操作最多 3 秒，每个域名整体最多 90 秒，达到上限、报告不完整、返回 FAIL/UNKNOWN 或下载校验失败均不选中。最多 5 个候选的探测上限约 7.5 分钟，另加一次下载；可改为手动输入并执行原有 TLS 校验。

WARN 表示基础和候选兼容性通过，但存在附加风险或未知项，例如未确认源 IP 的同 ASN 判断、CDN 线索或证书临近到期。安装器显示检查 ID，需要明确输入 `y` 才使用，默认拒绝；不会因非交互环境自动接受。该检测不能证明不存在 CDN，也不能保证抗封锁或长期可用。DNS 和 Team Cymru ASN 查询通过系统解析器进行，不上传代理 UUID、密码或密钥。

探测需要 Bash >= 4.3、OpenSSL、curl、dig、GNU coreutils、jq 和 CA 信任库。新安装的基础依赖包含 Debian/Ubuntu 的 `dnsutils` 或 RHEL 系的 `bind-utils`；旧安装如缺 `dig`，按发行版安装该包后重试。CentOS 7 默认 Bash 4.2 不满足探测器要求，需管理员升级 Bash，或使用菜单的手动输入/TLS 校验路径。

上游尚未发布正式 Release，本次固定源码提交 `bd25e0f636b3faccce855f4447f99327415f2077`（工具版本 `0.1.0`），并固定脚本 SHA256 `b07d64452974fd140b6623fbb8efaba35ef5a6f44e84b90b2bedcb05901767dd`。在权限受限的临时目录下载 staging 文件，摘要和 Bash 语法校验后才原子发布并执行，结束或中断时清理；不是直接执行 main 分支的远程内容。升级探测器时须同时审查并更新提交、摘要及 JSON 契约。
