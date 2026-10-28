# 快速开始

需要 root 权限。支持 Debian 11+、Ubuntu 20.04+、CentOS 7+/Stream、AlmaLinux、Rocky Linux；提供 amd64/arm64 架构探测。当前适配核心版本见 [README](https://github.com/KnowSky404/sing-box-vps)，不要把上游 latest 自动视为已适配。

在 VPS 上复制这一行：

```bash
bash -c 'set -euo pipefail; umask 077; t=$(mktemp); trap '\''rm -f -- "$t"'\'' EXIT; curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -o "$t" https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/bootstrap.sh; bash -n "$t"; grep -Fqx '\''readonly PROJECT_AUTHOR="KnowSky404"'\'' "$t"; grep -Fqx '\''readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"'\'' "$t"; bash "$t" install'
```

首段命令先把仓库内的 [bootstrap.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/bootstrap.sh) 下载到权限受限的临时文件，检查 Bash 语法和项目身份，然后运行它。Bootstrap 再下载并校验 [install.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/install.sh)，校验失败不会执行安装器；两层临时文件都会清理。下载来源是仓库 `main` 分支；如需先审查源码，可克隆仓库后运行 `sudo bash install.sh`。

安装完成后，在任意目录输入 `sbv` 打开管理菜单。要彻底卸载，可从克隆的仓库运行 `sudo bash uninstall.sh --yes` 或 `sudo bash bootstrap.sh uninstall --yes`；菜单里的“卸载 sing-box”会删除服务、核心和配置，但会保留 `sbv` 管理命令，独立卸载脚本还会删除全局 `sbv`。
