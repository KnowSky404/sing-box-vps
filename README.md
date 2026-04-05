# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。

## 🚀 一键安装

在您的 VPS 上运行以下命令即可开始安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh)
```

脚本会自动：
1. 安装所有必要依赖（curl, wget, jq, qrencode 等）。
2. 下载并配置适配的 `sing-box` (当前适配：1.13.5)。
3. 生成安全的 **VLESS + REALITY** 配置。
4. 将自己安装为全局命令 **`sbv`**，方便您随时管理。

---

## 🎮 快速管理

安装完成后，您可以在任何目录下直接输入 `sbv` 来打开交互式管理菜单：

```bash
sbv
```

## ✨ 项目特性

- **模块化与单脚本兼顾**：开发时模块化，用户端提供全集成 `install.sh`。
- **环境自适应**：支持架构探测（amd64/arm64）及主流发行版（Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux）。
- **极简且安全**：默认开启流量嗅探、uTLS 指纹、多 ShortID 随机化及持久化密钥管理。
- **性能增强**：集成 **BBR** 一键开启功能，显著提升网络吞吐。
- **防火墙自动化**：安装或修改端口时，自动尝试在 `UFW`, `Firewalld` 或 `Iptables` 中放行。
- **智能交互**：支持脚本自更新检测、sing-box 版本比对、配置文件语法校验及交互式参数修改。
- **优雅展示**：终端直接显示节点信息、VLESS 分享链接及 **ANSI 二维码**。
- **规范存储**：统一使用 `/root/sing-box-vps/` 存放配置、密钥及 Debug 日志。

## 🛠️ 功能菜单

1. **安装/更新 sing-box**：自动化部署流程。
2. **卸载 sing-box**：彻底清理软件及服务。
3. **修改当前协议配置**：零重装修改端口、UUID、伪装域名及路由规则。
4. **开启 BBR 拥塞控制**：一键提升网络性能。
5. **服务管理**：启动、停止、重启 sing-box。
6. **状态与节点信息**：随时找回分享链接及二维码。
7. **实时日志**：直接查看服务 Debug 日志。
8. **脚本管理**：支持脚本版本自更新及彻底卸载。

## 📂 关键路径

- **工作目录**: `/root/sing-box-vps/`
- **配置文件**: `/root/sing-box-vps/config.json`
- **密钥文件**: `/root/sing-box-vps/reality.key`
- **日志文件**: `/root/sing-box-vps/sing-box.log`
- **全局命令**: `/usr/local/bin/sbv`

## ⚠️ 注意事项

- 本脚本必须以 `root` 用户身份运行。
- 脚本默认适配最佳稳定性版本，手动选择 `latest` 可能存在不兼容风险。

---

## 👨‍💻 作者

**KnowSky404**
- 项目地址: [https://github.com/KnowSky404/sing-box-vps](https://github.com/KnowSky404/sing-box-vps)

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
