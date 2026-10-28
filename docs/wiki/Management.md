# 交互管理


Mixed/SOCKS 分享链接对用户名、密码按字节执行 URI 百分号编码，避免 `@`、`#`、`%`、空格或换行改变链接结构；服务端凭据保持不变。HTTP Basic 无法表达含冒号的用户名或含 ASCII 控制字符的认证：此时 Mixed 的 Agent `links` 只提供 SOCKS5，并返回 `mixed_http_auth_unrepresentable`，不生成不可用的 HTTP 链接。SOCKS5 URI 不携带 UoT v2 等客户端选项，返回 `socks5_uri_transport_options_omitted`；需要完整配置时使用 `export-client` JSON。百分号编码不是加密，链接仍是敏感材料。

1. **安装新协议**：首次安装或向现有实例追加 VLESS REALITY、Mixed、独立 SOCKS、独立 HTTP、Shadowsocks、Trojan、VMess、Hysteria2、Hysteria v1、AnyTLS、Snell、TUIC、NaiveProxy、ShadowTLS；协议选择注册表第 5 项为 SOCKS，第 6 项为 HTTP，第 9 项为 VMess，第 11 项为 Snell，第 12 项为 TUIC，第 13 项为 Hysteria v1，第 14 项为 NaiveProxy，第 15 项为 ShadowTLS。
2. **修改已安装协议配置**：选择协议后进入对应实例管理，支持修改、设置默认实例等操作；legacy ACME/provider 保留原配置编辑流程。检测到未完成事务时，此入口直接进入恢复流程。
3. **移除已安装协议**：移除指定协议或 REALITY 实例；存在多个 REALITY 实例时会明确询问“单实例”或“整个 VLESS 协议”，并同步清理 QoS 与已移除端口的防火墙放行。
4. **更新 sing-box 版本**：保留配置的核心更新；目标 `sing-box check` 通过才重启。
5. **卸载 sing-box**：清理核心、服务与运行配置，保留管理命令 `sbv`。
6. **启动 sing-box**。
7. **停止 sing-box**。
8. **重启 sing-box**。
9. **运行状态摘要**。
10. **查看实时日志**。
11. **查看节点信息**：链接/二维码、裸核客户端导出与 SubMan 同步。
12. **流媒体验证检测**：本机直出或 Warp 出口。
13. **配置 Cloudflare Warp**：账户、开关、全量/选择性路由、自定义域名及规则集。
14. **系统管理**：BBR，以及入站监听栈和出站/DNS 策略。
15. **更新管理脚本 `sbv`**。
16. **卸载管理脚本 `sbv`**。

原“实例与状态”分组已合并到现有协议入口：菜单 1 安装、菜单 2 管理、菜单 3 移除，主菜单不再重复列出每种协议。协议安装列表按编号 1–15 排列，原有编号和留空选择行为保持不变。

删除最后一个实例后，菜单 2 仍会显示保留的协议，并标注“暂无实例，可重新创建”；选择后可沿用保留的版本记录创建新实例。

Hysteria2 新增协议和创建实例默认提供 ACME 自动签发，也可选择已有手动证书。`server_name / SNI` 必填，填写与证书匹配的域名（如 `hy2.example.com`），不带 URL 前缀或路径。HTTP-01 需要域名解析到 VPS 且公网 TCP 80 可用于验证和续期；Cloudflare DNS-01 需要 DNS 编辑权限，无需开放 TCP 80，邮箱可留空。手动模式填写证书与私钥的本机绝对路径，自签名证书选择“信任此证书”。新建实例默认监听 `0.0.0.0`，接受外部 IPv4 连接；修改时留空保留原地址。HY2 服务端口需要允许 UDP，带宽、混淆与伪装网站均为可选项。

当脚本发现二进制、service、配置或协议状态层不完整时，会进入接管/修复流程，而不是把残缺实例直接当作全新安装覆盖。
