# TCP Fast Open 与 HY2 网络默认值

状态：实现完成；必要验证结果随交付 PR 记录。协议默认值不迁移现有记录，
不修改宿主机 sysctl，也不表示生产配置已应用。

## 契约

- 新建支持 TCP 的协议监听默认 TFO 开启，具体协议与客户端例外以
  [协议实例说明](../wiki/Protocol-Instances.md#tcp-fast-open-and-hy2-defaults) 为准。
  HY2、TUIC、Hysteria v1、QUIC transport 及 UDP-only 监听不加 TFO 默认值。
- typed record 增加兼容可选 boolean `listen.tcp_fast_open`，ShadowTLS 内层为
  `detour.listen.tcp_fast_open`。create 省略取支持范围内默认 true；
  显式 false 保留，replace 省略继承原字段，旧记录原本无字段仍然无字段。
  接管区分缺失、false 和 true，保持无损。原 schema_version 不变，不做批量迁移。
- REALITY 新建默认开，已有实例保留独立开关；支持的 TCP 客户端材料默认开，
  AnyTLS outbound 明确不支持而排除，Naive QUIC 及 V2Ray QUIC 不加默认值。
- HY2 安装和菜单新建默认 Salamander；空密码生成随机值，replace 保留旧开关。
  结构化写入的显式 obfs 对象为准，原已关闭实例不自动开启。
- 共用伪装 URL 输入列出已安装与本轮已配置 REALITY 的去重 SNI，以 r1/r2 选择，
  转为 HTTPS URL 后再单独检测；不更改 HY2 TLS 身份、证书或 ACME 域名。
- HTTP(S) 新值及全新安装默认值执行有界 HEAD 探测，校验 DNS/TLS，连接 5 秒，
  总计 10 秒，最多 3 次 HTTP(S) 重定向，接受最终 2xx/3xx。失败重输、EOF 失败，
  不写失败值。修改空输入离线保留；file: 兼容范围保持。
- `hy2.masquerade-check` 是相同候选/探测函数的只读结构化入口：
  无 --url 只列候选，有 --url 返回 http_available；失败非零退出，
  stdout 一个 JSON，错误不得回显可能带凭据的 URL。候选只含公开域名。
- obfs 开启时普通 QUIC/HTTP3 不可用，提示须明确，伪装地址不能当作 HTTPS
  身份伪装保证。HTTP(S) 探测不证明内容适用、HTTP3 或实际 HY2 连接。

## 验证边界

定向宿主测试覆盖新建/替换/接管、显式 false 和旧字段缺失、TCP/UDP/QUIC
选择、HY2 混淆默认值与密码、候选选择及错误/EOF/脱敏、规范与兼容 CLI。
受影响服务端/客户端配置须通过目标核心 `sing-box check`；监听、TLS、
导出与 HY2 混淆用相应隔离 Docker 协议探针验证。生产、公网可达性、真实
ACME、SubMan 写入、TFO SYN 数据及端到端延迟收益均为独立验收。
