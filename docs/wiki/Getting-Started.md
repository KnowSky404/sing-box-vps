# 快速开始

需要 root 权限。支持 Debian 11+、Ubuntu 20.04+、CentOS 7+/Stream、AlmaLinux、Rocky Linux；提供 amd64/arm64 架构探测。当前适配核心版本见 [README](https://github.com/KnowSky404/sing-box-vps)，不要把上游 latest 自动视为已适配。

在 VPS 上复制这一行：

```bash
bash -c 'set -euo pipefail; umask 077; t=$(mktemp); trap '\''rm -f -- "$t"'\'' EXIT; curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -o "$t" https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/bootstrap.sh; bash -n "$t"; grep -Fqx '\''readonly PROJECT_AUTHOR="KnowSky404"'\'' "$t"; grep -Fqx '\''readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"'\'' "$t"; bash "$t" install'
```

首段命令先把仓库内的 [bootstrap.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/bootstrap.sh) 下载到权限受限的临时文件，检查 Bash 语法和项目身份，然后运行它。Bootstrap 再下载并校验 [install.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/install.sh)，校验失败不会执行安装器；两层临时文件都会清理。下载来源是仓库 `main` 分支；如需先审查源码，可克隆仓库后运行 `sudo bash install.sh`。

安装完成后，在任意目录输入 `sbv` 打开管理菜单。要彻底卸载，可从克隆的仓库运行 `sudo bash uninstall.sh --yes` 或 `sudo bash bootstrap.sh uninstall --yes`；菜单里的“卸载 sing-box”会删除服务、核心和配置，但会保留 `sbv` 管理命令，独立卸载脚本还会删除全局 `sbv`。

## REALITY SNI 探测

安装 VLESS + REALITY 使用 [reality-target-checker v0.3.0](https://github.com/KnowSky404/reality-target-checker) 选择候选 SNI。默认仍为检测自行提供的域名：输入 1–5 个纯域名，以空格或逗号分隔，按输入顺序选择首个检查通过且获接受的域名。安装时的 SNI 菜单选项 3 可改用网段/ASN 候选发现；更新和新增实例的选项 4 提供相同入口，默认仍保留或复用已有 SNI。手动输入和 TLS 校验路径仍可使用。安装器没有固定推荐域名，失败或取消时不填入默认域名、不修改当前 SNI。

发现模式需要明确输入一个严格对齐的 IPv4 CIDR，前缀长度限 `/24`–`/32`，主机预算为 256；例如文档地址 `192.0.2.0/24` 仅用于说明，执行时应替换为自己明确选择的实际范围。也可输入十进制 ASN：安装器先查询并展示 RIPE 公告快照，这一步不探测目标端口；之后必须明确选择公告 IPv4 前缀内的一个 `/24`–`/32` 子网，才开始发现。执行时继续携带 ASN 重新检查范围，不自动扫描整个 ASN。ASN/BGP 快照不保证实时或独占归属，也不证明目标在同机房、路由相邻或延迟更低。

发现只在所选 IPv4 范围内探测 TCP 443，从默认证书 SAN 和 PTR 收集域名，再固定 IP/SNI 复核。单次网络操作上限 3 秒，总预算 300 秒，外层截止时间 315 秒；并发 8，每秒最多启动 10 个任务，全局最多 256 对 IP/SNI，每对采样一次。任务启动频率不是逐请求或逐包限速，探测期间显示进度。没有 SNI 的站点可能不提供可用证书，通配 SAN 不会被猜测展开，所以发现是有限策略下的 best effort，不代表找全域名，也不提供延迟排名。

只有完整完成且返回 PASS/WARN 的发现报告才进入选择；超时、截断、UNKNOWN 或异常报告均停止，不使用其中的部分候选。安装器取合格候选中前 5 个有效且去重的 SNI，重新执行下面的完整 DNS 域名检查。固定 IP/SNI 的探测成功不等于通过域名连接时仍到达同一 IP，因此安装器不会直接采用发现报告或把发现 IP 写成握手目标；最终使用通过域名复核且获接受的 SNI。

每个域名检测 DNS A/AAAA 返回的地址、TLS 1.3、证书链/SAN/有效期、h2 和 X25519，并记录 ASN/CDN 等附加线索。默认检查两个地址族；无 IPv6 出站而目标有 AAAA 时可能无法完成，不能视为通过。每项网络操作最多 3 秒，每个域名整体最多 90 秒，达到上限、报告不完整、返回 FAIL/UNKNOWN 或下载校验失败均不选中。最多 5 个候选的探测上限约 7.5 分钟，另加一次下载；可改为手动输入并执行原有 TLS 校验。

WARN 表示基础和候选兼容性通过，但存在附加风险或未知项，例如未确认源 IP 的同 ASN 判断、CDN 线索或证书临近到期。安装器显示检查 ID，需要明确输入 `y` 才使用，默认拒绝；不会因非交互环境自动接受。发现后的域名复核同样遵循此规则。该检测不能证明不存在 CDN，也不能保证抗封锁或长期可用。DNS 和 Team Cymru ASN 查询通过系统解析器进行；ASN 计划还会向 RIPEstat 查询输入的 ASN。发现会让所选范围内的站点获知扫描端地址，检测不上传代理 UUID、密码或密钥。

域名检查需要 Bash >= 4.3、OpenSSL、curl、dig、GNU coreutils、jq 和 CA 信任库；发现另外需要已安装的 Python >= 3.9。安装器不会为发现自动安装 Python，缺少时可补齐依赖后重试，或使用候选域名检查/手动输入。新安装的基础依赖包含 Debian/Ubuntu 的 `dnsutils` 或 RHEL 系的 `bind-utils`；旧安装如缺 `dig`，按发行版安装该包后重试。CentOS 7 默认 Bash 4.2 不满足探测器要求，需管理员升级 Bash，或使用菜单的手动输入/TLS 校验路径。

上游尚未发布正式 Release，本次固定源码提交 `fc1c06ef4f46b81ad05b0aa2bf24378c64833682`（工具版本 `0.3.0`）。域名检查只下载 Bash；发现按需下载同提交的 Python 核心与 sources 模块，每个文件均使用独立固定的 SHA256：

| 文件 | SHA256 |
| --- | --- |
| `reality-target-checker.sh` | `f2446d5bc75ed77289a29adf8d85bc87efdbfa289e6a926f806b54b0fd79c1a3` |
| `reality-target-discover.py` | `f806106efff7f3cbe219175d4f0c09f388d5304158d0e0d43e9220fefea6374d` |
| `reality-target-sources.py` | `de028f4eec658eba6f789b30a51d558d9565337fccb02c2358ae76643f0ff33c` |

下载先写入权限受限临时目录中的 staging 文件，校验后才原子发布并执行；Bash 文件还检查语法。结束或中断时清理临时文件。升级探测器时须同时审查并更新提交、各执行文件摘要及对应 JSON 契约。
