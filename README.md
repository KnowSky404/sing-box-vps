# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。完美适配 **sing-box 1.13.x** 最新架构。

## 🚀 一键安装

在您的 VPS 上运行以下命令即可开始安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh)
```

脚本会自动：
1. 安装所有必要依赖（curl, wget, jq, qrencode 等）。
2. 下载并配置适配的 `sing-box` (当前适配：1.13.6)。
3. 生成安全的 **VLESS + REALITY** 或 **Mixed (HTTP/HTTPS/SOCKS)** 配置。
4. 将自己安装为全局命令 **`sbv`**，方便您随时管理。

---

## 🎮 快速管理

安装完成后，您可以在任何目录下直接输入 `sbv` 来打开交互式管理菜单：

```bash
sbv
```

## ✨ 项目特性

- **1.13.x 深度适配**：全面采用最新的 **Endpoint (端点化)** 架构，确保 WireGuard 及路由规则的最高效性能与稳定性。
- **双协议支持**：支持 **VLESS + REALITY** 与 **Mixed (HTTP/HTTPS/SOCKS)** 两种入站模式，适配节点分享与传统代理两类使用场景。
- **Cloudflare Warp 集成**：支持一键开启/关闭 Warp 出站，自动注册免费账户，完美解决 VPS **“送中”** 问题并解锁 Netflix/Disney+ 等流媒体。
- **Warp 路由分层**：支持 `全量走 Warp` 与 `选择性分流` 两种模式，内置主流 AI / 流媒体域名规则，并支持用户追加自定义域名、本地规则集和远程规则集。
- **模块化与单脚本兼顾**：开发时模块化，用户端提供全集成 `install.sh`。
- **环境自适应**：支持架构探测（amd64/arm64）及主流发行版（Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux）。
- **极简且安全**：默认开启流量嗅探、uTLS 指纹、多 ShortID 随机化及持久化密钥管理。
- **性能增强**：集成 **BBR** 一键开启功能，显著提升网络吞吐。
- **防火墙自动化**：安装或修改端口时，自动尝试在 `UFW`, `Firewalld` 或 `Iptables` 中放行。
- **工业级配置生成**：采用 **`jq` 安全注入** 模式生成 JSON，彻底规避特殊字符导致的转义错误。
- **优雅展示**：终端直接显示节点信息、VLESS 分享链接及 **ANSI 二维码**。
- **规范存储**：统一使用 `/root/sing-box-vps/` 存放配置、密钥及持久化参数。

## 🛠️ 功能菜单

1.  **安装/更新 sing-box**：自动化部署流程。
2.  **卸载 sing-box**：彻底清理软件及服务。
3.  **修改当前协议配置**：交互式修改端口、VLESS 参数或 Mixed 用户认证信息及高级路由开关。
4.  **配置 Cloudflare Warp**：一键开启/关闭/重新注册 Warp，并支持切换全量/选择性分流模式。
5.  **开启 BBR 拥塞控制**：一键提升网络性能。
6.  **服务管理**：启动、停止、重启 sing-box。
7.  **状态与节点信息**：随时找回分享链接及二维码。
8.  **实时日志**：直接查看服务运行详情。
9.  **脚本管理**：支持脚本版本自更新及彻底卸载。

## 📂 关键路径

- **工作目录**: `/root/sing-box-vps/`
- **配置文件**: `/root/sing-box-vps/config.json`
- **密钥文件**: `/root/sing-box-vps/reality.key` (REALITY) / `warp.key` (Warp)
- **Mixed 认证信息**: 存储于 `/root/sing-box-vps/config.json`
- **Warp 分流域名**: `/root/sing-box-vps/warp-domains.txt`
- **Warp 本地规则集目录**: `/root/sing-box-vps/rule-set/warp/`
- **Warp 远程规则集列表**: `/root/sing-box-vps/warp-remote-rule-sets.txt`
- **全局命令**: `/usr/local/bin/sbv`

## ⚠️ 注意事项

- 本脚本必须以 `root` 用户身份运行。
- 脚本默认适配最佳稳定性版本，手动选择 `latest` 可能存在不兼容风险。
- `Mixed` 代理默认建议启用用户名密码认证；若关闭认证，请务必确认防火墙和来源访问控制策略。

---

## 👨‍💻 作者

**KnowSky404**
- 项目地址: [https://github.com/KnowSky404/sing-box-vps](https://github.com/KnowSky404/sing-box-vps)

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
