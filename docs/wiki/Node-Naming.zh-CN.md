# 实例与节点命名

[English](https://github.com/KnowSky404/sing-box-vps/wiki/Node-Naming)

实例保存一个人类可读的基础名称，分享材料与 SubMan 从该基础名生成各用户、地址候选的名称。实例 ID、认证用户身份、内部及客户端 tag、links map key 和 SubMan 外部键继续承担原有职责。

## 新建默认名

新建交互实例默认采用：

```text
<主机显示标签>-<规范协议 ID>-<序号>
```

例如 `fra-01-hy2-01` 和 `fra-01-vless-reality-01`。序号至少两位，在协议当前清单中选择空闲生成名称。删除实例不重新编号其他实例。名称可以自定义；已有名称和旧状态恢复时的回退默认名不变。

主菜单 **11 → 5「设置新实例的主机显示标签」** 设置后续默认名称使用的标签。可选私有文件为 `/root/sing-box-vps/node-naming.json`，仅含 `host_label`：

```json
{"host_label":"fra-01"}
```

标签去除首尾空白后必须非空、不含控制字符且不超过 128 UTF-8 字节。无文件时使用当前 hostname；已有文件无效时明确报错。全新环境无偏好文件和实例清单时，默认名生成不要求提前安装 `jq`；读取已有 JSON 输入时需要 `jq`，缺失则明确提示。保存时先将旧文件备份为 `node-naming.json.bak`，再原子替换。此设置不修改已有实例名、不重启 sing-box、不推送 SubMan 节点。

## 候选名称

渲染时按与 SubMan 一致的 ECMAScript `String.prototype.trim()` 空白规则去除基础名的首尾空白；中间字符和保存值保留。先去除首尾空白，再检查剩余控制字符，因此 `"\tCustom\t"` 渲染为 `Custom`，中间含 Tab 则失败。U+FEFF 去除，U+0085 保留；去除后为空则失败。显示名按以下顺序生成：

```text
<实例名称>[-i-<实例摘要>][-u-<用户摘要>][-U<上行>M][-D<下行>M][-v4|-v6]
```

| 情况 | 行为 |
| --- | --- |
| 一个逻辑凭据 | 不加用户摘要，包含单凭据 Shadowsocks |
| 多个已配置用户 | 增加 `u-` 和用户身份 SHA-256 的至少前 12 位十六进制字符；与同实例其他已配置用户前缀冲突时每次增加 4 位 |
| 同一已捕获协议清单中实例基础名按相同空白规则规范化后重复 | 增加 `i-` 和 `协议:实例 ID` 的 SHA-256 前 12 位十六进制字符 |
| REALITY 限速或 HY2 带宽元数据 | 保留配置的 `U...M`、`D...M` 及各自协议语义 |
| 通配监听的 IPv4、IPv6 候选 | 根据原地址候选标签追加 `v4`、`v6` |
| 具体绑定地址 | 保留监听地址标签行为，不额外追加地址族后缀 |

用户后缀按已配置用户数决定，即使另一个用户因分享选项无法表达而跳过，也不会改变该计数。调整用户顺序不会改变摘要。实例摘要描述实例，实际分享材料描述候选；同一候选的 URI 备注、VMess `ps` 与 SubMan payload 使用同名。技术映射 key 和客户端配置 tag 保持稳定。

示例：

```text
fra-01-hy2-01-v4
fra-01-hy2-01-U20M-D80M-v4
fra-01-hy2-01-u-2bd806c97f0e-v6
```

最终名称最多 256 UTF-8 字节。追加后缀后过长时，仅在 Unicode 字符边界缩短渲染基础名，增加稳定的 `n-` 摘要并保留后缀；已保存实例名不变。本地同名处理限于捕获的协议清单；其他协议、机器或远端手工节点仍可能重名。SubMan 按原规则处理远端重名时，以返回名称为准。

## 更新已有节点

通过现有实例管理修改基础名。下一次明确执行 SubMan 同步时，如果原节点仍存在，使用原 externalKey 更新该节点。不要仅为改名先删除再重建，删除可能移除聚合引用。

主菜单 **11 → 4** 将保存的 `SUBMAN_NODE_PREFIX` 称为 **同步身份前缀**，原值及键格式保留。修改它会改变远端身份、保留旧节点；主机显示标签是独立设置。保存设置不执行同步；节点 API 写入也不会自动重新发布以前生成的订阅或客户端产物。

统一命名不新增协议支持、不改变分享和信任条件，也不联系生产服务。另见 [SubMan 地址选择](https://github.com/KnowSky404/sing-box-vps/wiki/SubMan-Address-Selection)、[交互管理](https://github.com/KnowSky404/sing-box-vps/wiki/Management) 和 [中文实现 SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/unified-node-naming.zh-CN.md)（[English SPEC](https://github.com/KnowSky404/sing-box-vps/blob/main/docs/specs/unified-node-naming.md)）。
