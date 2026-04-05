# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。

## 🚀 一键安装

在您的 VPS 上运行以下命令即可开始安装：

```bash
git clone https://github.com/KnowSky404/sing-box-vps.git && cd sing-box-vps && chmod +x main.sh && ./main.sh
```

## ✨ 项目特性

- **模块化设计**：代码结构清晰，易于维护和扩展。
- **环境自适应**：自动检测系统架构（amd64/arm64）及主流 Linux 发行版（Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux）。
- **极简且安全**：默认提供 **VLESS + REALITY** 协议，支持流量嗅探、uTLS 指纹及多 ShortID 随机化。
- **版本控制**：脚本内置适配的 `sing-box` 版本（当前适配：1.13.5），确保配置的兼容性与稳定性。
- **完整清理**：内置卸载功能，一键清理所有相关文件和服务，不留垃圾。

## 🛠️ 功能菜单

脚本运行后将进入交互式菜单：

1. **安装 sing-box**：自动安装依赖、下载二进制文件、生成安全配置并启动服务。
2. **卸载 sing-box**：停止服务并彻底删除所有组件。

## 📂 关键路径

- **配置文件**: `/etc/sing-box/config.json`
- **二进制路径**: `/usr/local/bin/sing-box`
- **服务状态**: `systemctl status sing-box`
- **实时日志**: `journalctl -u sing-box -f`

## ⚠️ 注意事项

- 本脚本必须以 `root` 用户身份运行。
- 默认使用 `apple.com` 作为 REALITY 的 SNI 域名，端口默认为 `443`。
- 如果您选择安装 `latest` 版本，可能会面临 `sing-box` 官方 Break 变动导致的兼容性风险。

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
