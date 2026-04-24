# sing-box-vps

可能是最简单的 sing-box VPS 一键安装脚本，专为稳定性和安全性设计。完美适配 **sing-box 1.13.x** 最新架构。

## 📌 当前版本信息

- 脚本版本：`2026042409`
- sing-box 适配版本：`1.13.9`

## 🚀 一键安装

在您的 VPS 上运行以下命令即可开始安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh)
```

如需独立执行彻底卸载，可运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/uninstall.sh)
```

## 开发验证工作流

推荐先复制一份声明式目标配置：

```bash
cp configs/verification-target.env.example dev/verification-target.env
```

默认优先读取 `dev/verification-target.env`。若使用 SSH 主机别名，只需配置：

```bash
VERIFY_REMOTE_HOST_ALIAS=sing-box-test
```

当前仓库默认约定的测试机 SSH 别名也是 `sing-box-test`。新开开发会话时，优先复用这套目标配置，不再临时改回纯环境变量模式。

随后运行：

```bash
bash dev/verification/run.sh
```

只想验证本地调度与触发规则时，可运行：

```bash
VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh
```

核心脚本改动会自动触发远程验证；仅修改 `tests/`、`docs/`、`README.md` 不会占用测试机。

默认工作流已做分层优化：
- 核心脚本改动默认只跑协议探测快测
- 仅在改动 `dev/verification/run.sh`、`dev/verification/common.sh` 或 `dev/verification/remote/` 时，才追加远程调度与远程框架回归
- 远程验证默认优先收敛到 `runtime_smoke`；只有安装/重配相关改动才扩到 `fresh_install_vless` 与 `reconfigure_existing_install`

命中远程验证时，测试机会额外执行协议级闭环探测：在测试机本机启动临时客户端，连接测试机本机的服务端入站，再通过该客户端代理访问测试机本机 HTTP 探针服务。当前优先支持 `vless-reality` 与 `hy2`；未覆盖协议会在产物中标记为 `unsupported`。

脚本会自动：
1. 安装所有必要依赖（curl, wget, jq, qrencode 等）。
2. 下载并配置适配的 `sing-box` (当前适配：1.13.9)。
3. 生成安全的 **VLESS + REALITY**、**Mixed (HTTP/HTTPS/SOCKS)**、**Hysteria2** 或 **AnyTLS** 配置，并支持多协议共存。
4. 以 **`install.sh`** 作为唯一安装与维护真源，并将自己安装为全局命令 **`sbv`**，方便您随时管理。

---

## 🎮 快速管理

安装完成后，您可以在任何目录下直接输入 `sbv` 来打开交互式管理菜单：

```bash
sbv
```

## ✨ 项目特性

- **1.13.x 深度适配**：全面采用最新的 **Endpoint (端点化)** 架构，确保 WireGuard 及路由规则的最高效性能与稳定性。
- **多协议支持**：支持 **VLESS + REALITY**、**Mixed (HTTP/HTTPS/SOCKS)**、**Hysteria2** 与 **AnyTLS** 四种入站模式，并支持多协议同时安装。
- **Cloudflare Warp 集成**：支持一键开启/关闭 Warp 出站，自动注册免费账户，完美解决 VPS **“送中”** 问题并解锁 Netflix/Disney+ 等流媒体。
- **Warp 路由分层**：支持 `全量走 Warp` 与 `选择性分流` 两种模式，内置主流 AI / 流媒体域名规则，并支持用户追加自定义域名、本地规则集和远程规则集。
- **单一真源**：统一以 `install.sh` 作为安装与维护入口，避免历史旧入口与当前实现漂移。
- **环境自适应**：支持架构探测（amd64/arm64）及主流发行版（Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux）。
- **极简且安全**：默认开启流量嗅探、uTLS 指纹、多 ShortID 随机化及持久化密钥管理。
- **性能增强**：集成 **BBR** 一键开启功能，显著提升网络吞吐。
- **防火墙自动化**：安装或修改端口时，自动尝试在 `UFW`, `Firewalld` 或 `Iptables` 中放行。
- **工业级配置生成**：采用 **`jq` 安全注入** 模式生成 JSON，彻底规避特殊字符导致的转义错误。
- **协议级展示**：终端可按协议查看节点信息，支持 `VLESS` 与 `Hysteria2` 链接/ANSI 二维码展示，为 `Mixed` 输出代理链接与二维码提示，并为 `AnyTLS` 输出参数摘要和 sing-box outbound JSON 示例。
- **规范存储**：统一使用 `/root/sing-box-vps/` 存放配置、密钥及持久化参数。

## 🛠️ 功能菜单

1.  **安装协议 / 更新 sing-box**：首次安装时可选择一个或多个协议；已有安装时可选择更新二进制或继续追加新协议。
2.  **卸载 sing-box**：彻底清理软件及服务。
3.  **修改当前协议配置**：先选择已安装协议，再进入该协议自己的修改向导，仅更新目标协议状态。
4.  **配置 Cloudflare Warp**：一键开启/关闭/重新注册 Warp，并支持切换全量/选择性分流模式。
5.  **开启 BBR 拥塞控制**：一键提升网络性能。
6.  **服务管理**：启动、停止、重启 sing-box。
7.  **状态与节点信息**：先查看服务摘要，再选择已安装协议查看对应链接或二维码。
8.  **实时日志**：直接查看服务运行详情。
9.  **脚本管理**：支持脚本版本自更新及彻底卸载。
10. **流媒体验证检测**：支持本机直出与 Warp 出口两种检测模式。

## 📂 关键路径

- **工作目录**: `/root/sing-box-vps/`
- **配置文件**: `/root/sing-box-vps/config.json`
- **协议状态目录**: `/root/sing-box-vps/protocols/`
- **密钥文件**: `/root/sing-box-vps/reality.key` (REALITY) / `warp.key` (Warp)
- **协议状态文件**: `vless-reality.env` / `mixed.env` / `hy2.env` / `anytls.env`
- **Warp 分流域名**: `/root/sing-box-vps/warp-domains.txt`
- **Warp 本地规则集目录**: `/root/sing-box-vps/rule-set/warp/`
- **Warp 远程规则集列表**: `/root/sing-box-vps/warp-remote-rule-sets.txt`
- **流媒体验证脚本缓存**: `/root/sing-box-vps/media-check/region_restriction_check.sh`
- **全局命令**: `/usr/local/bin/sbv`

## ⚠️ 注意事项

- 本脚本必须以 `root` 用户身份运行。
- 脚本默认适配最佳稳定性版本，手动选择 `latest` 可能存在不兼容风险。
- `Mixed` 代理默认建议启用用户名密码认证；若关闭认证，请务必确认防火墙和来源访问控制策略。
- `Hysteria2` 首版支持 ACME 自动签发与手动证书路径两种 TLS 模式；使用 ACME `DNS-01` 时当前仅支持 Cloudflare。
- `AnyTLS` 当前同样支持 ACME 自动签发与手动证书路径两种 TLS 模式；由于官方文档未定义标准分享 URI，脚本默认输出参数摘要与 sing-box outbound JSON 示例。
- 流媒体验证功能当前接入第三方项目 `1-stream/RegionRestrictionCheck`，脚本内已注明作者与仓库地址，后续可替换为自定义检测后端。

---

## 👨‍💻 作者

**KnowSky404**
- 项目地址: [https://github.com/KnowSky404/sing-box-vps](https://github.com/KnowSky404/sing-box-vps)

## 开源协议

基于 [GNU Affero General Public License v3.0](LICENSE) 开源。
