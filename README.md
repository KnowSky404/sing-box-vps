# sing-box-vps

面向 VPS 的 sing-box 安装与管理脚本，提供交互菜单和 Agent 命令，用于部署协议、维护服务和导出客户端配置。

- 脚本版本：`2026103007`
- sing-box 适配版本：`1.14.2`

## 主要能力

- 15 个入站预设，支持多协议、多实例管理。
- 配置校验、关键变更备份与失败回滚。
- 客户端配置导出、Warp 分流和 SubMan 节点同步。

协议条件与验证范围见 [Wiki 能力矩阵](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Coverage)。

## 一键安装

在 VPS 上以 root 用户执行以下命令（需已安装 `curl`）：

```bash
bash -c 'set -euo pipefail; umask 077; t=$(mktemp); trap '\''rm -f -- "$t"'\'' EXIT; curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 -o "$t" https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/bootstrap.sh; bash -n "$t"; grep -Fqx '\''readonly PROJECT_AUTHOR="KnowSky404"'\'' "$t"; grep -Fqx '\''readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"'\'' "$t"; bash "$t" install'
```

命令会先下载并检查 [bootstrap.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/bootstrap.sh)，再由它下载、检查并启动 [install.sh](https://github.com/KnowSky404/sing-box-vps/blob/main/install.sh)。

安装完成后，在任意目录运行以下命令打开管理菜单：

```bash
sbv
```

支持的系统、安装流程与卸载说明见 [Wiki 快速安装](https://github.com/KnowSky404/sing-box-vps/wiki/Getting-Started)。

## 文档

**[Wiki 首页](https://github.com/KnowSky404/sing-box-vps/wiki)** · **[快速安装](https://github.com/KnowSky404/sing-box-vps/wiki/Getting-Started)**

[交互管理](https://github.com/KnowSky404/sing-box-vps/wiki/Management) · [Agent 命令](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-CLI) · [运维与排错](https://github.com/KnowSky404/sing-box-vps/wiki/Agent-Runbook) · [开发工作流](https://github.com/KnowSky404/sing-box-vps/wiki/Development)

安全审查上下文与报告要求见 [SECURITY.md](SECURITY.md)。
实现契约、完成状态与待验收边界见 [SPEC 索引](docs/specs/README.zh-CN.md)（[English](docs/specs/README.md)）。

## 开源协议

由 [KnowSky404](https://github.com/KnowSky404) 维护，基于 [AGPL-3.0](LICENSE) 开源。
