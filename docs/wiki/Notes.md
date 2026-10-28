# 使用注意事项

- 配置检查与隔离容器探针不证明公网可达或生产环境运行。具体测试范围见[能力矩阵](https://github.com/KnowSky404/sing-box-vps/wiki/Protocol-Coverage)。
- 本脚本必须以 `root` 用户身份运行。
- 脚本默认适配最佳稳定性版本，手动选择 `latest` 可能存在不兼容风险。
- `Mixed` 代理默认建议启用用户名密码认证；若关闭认证，请务必确认防火墙和来源访问控制策略。当前 Mixed 入口及导出 SOCKS5 链路未启用 TLS，用户名密码和非加密业务可能暴露，仅应在可信网络或受保护隧道内使用；UoT v2 只把 UDP 封装在 TCP 中，不提供加密，也不要求开放额外的服务端固定 UDP 端口。
- `Hysteria2` 支持 ACME 自动签发与手动证书路径两种 TLS 模式；使用 ACME `DNS-01` 时当前仅支持 Cloudflare。sing-box 1.14+ 客户端连接使用 Ed25519 手动证书的节点时必须禁用 Chrome QUIC 模拟；裸核配置导出会自动处理，分享链接和 SubMan 同步则会输出显式警告。
- `AnyTLS` legacy schema 1 仍支持 ACME 自动签发与手动证书路径；schema 2 typed 实例为可审计的手工证书路径、用户名/密码和 `certificate`/`system` 客户端信任。由于官方文档未定义标准分享 URI，Agent `links` 和客户端导出使用完整 sing-box outbound JSON，并显式将 `client_metadata` 设为空；无法无损表达的 ACME/provider live 配置会拒绝接管而保留原状态。
- SubMan 同步需在 `/root/sing-box-vps/subman.env` 配置 `SUBMAN_API_URL`、`SUBMAN_API_TOKEN`、`SUBMAN_NODE_PREFIX` 和 `SUBMAN_EXPECTED_GIST_ID`；预期 Gist ID 必须从目标 Workspace 核对，旧配置可通过交互同步补齐，Agent 不会自动绑定发现结果。写入前 GET 预检目标身份，以公开的 `PUT /api/nodes/by-key/:externalKey` 同步，并核对每次响应的 Gist、revision/ETag、键标记和 `Cache-Control: no-store`。完整外部键最多 **119 UTF-8 字节**（含实例、用户摘要和地址后缀），最多 **63 个不同普通标签**；超长键拒绝写入，请缩短前缀并明确处理旧身份，不会静默截断。
- SubMan 写入响应丢失或上游结果不确定时，先 GET 对比准确键和目标内容（含服务端去重命名），不盲目重发；Agent 保留逐节点同步、旧键清理结果和部分成功信息。双栈旧键清理先读取 revision，再通过条件删除接口提交。Gist 身份预检无法原子固定 API 的发现结果；节点更新也**不会自动重发布订阅或 sing-box 文件**，需在 SubMan 浏览器中检查并发布。当前集成验证使用本地 mock，不证明真实 Gist 同步或生产部署。
- 流媒体验证功能当前接入第三方项目 `1-stream/RegionRestrictionCheck`，脚本内已注明作者与仓库地址，后续可替换为自定义检测后端。
