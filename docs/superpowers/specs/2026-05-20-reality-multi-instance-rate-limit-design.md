# Reality Multi-Instance Rate Limit Design

**Date:** 2026-05-20

## Goal

让 `sing-box-vps` 的 VLESS + REALITY 支持多个独立节点实例，并允许用户在创建或修改每个 REALITY 实例时选择是否限速。

本次设计需要满足：

- 保持当前首次安装入口兼容，单协议安装 VLESS + REALITY 的用户仍能按原流程完成安装。
- 已安装 VLESS + REALITY 后，允许继续新增 REALITY 节点实例，而不是提示协议已安装后跳过。
- 每个 REALITY 实例可以独立选择端口、节点名、UUID、SNI 和限速配置。
- 限速必须支持灵活组合：
  - 上行不限速、下行限速
  - 上行限速、下行不限速
  - 上下行都限速
  - 上下行都不限速
- 旧的单 REALITY 状态与旧配置必须自动迁移为一个默认未限速实例。
- 仍然只运行一个 `sing-box` 服务，不增加第二个 systemd service，也不重复安装 sing-box。

## Non-Goals

- 不实现同一个端口内按 VLESS 用户标识限速。当前 sing-box 可以识别 VLESS 用户，但没有 per-user bandwidth action；Linux `tc`/`nftables` 也无法直接看到 REALITY 加密内的用户标识。
- 不在第一版实现按总流量配额、到期时间、在线设备数或并发连接数控制。
- 不要求第一版支持任意协议的通用限速。此设计只覆盖 VLESS + REALITY。

## Confirmed Decisions

### 1. 使用“多 REALITY 实例”模型

`vless-reality` 仍然是协议索引里的协议项，但它下面可以拥有多个实例。

示例：

- `vless-reality-main`
- `vless-reality-limited-10m`
- `vless-reality-upload-5m`

这些实例最终都会写入同一个 `config.json` 的 `inbounds` 数组，并由同一个 sing-box 进程监听。

### 2. 限速以端口为边界

每个限速实例使用独立端口。脚本通过系统层 QoS 对该端口进行限速。

理由：

- 端口是 Linux 网络层可以稳定识别的边界。
- REALITY/VLESS 用户信息位于应用层和加密协议内部，系统层无法直接用于 `tc` 规则匹配。
- 端口级限速可验证、可回滚、与 sing-box 升级耦合较低。

### 3. 上下行速率独立配置

实例状态中保存两个独立字段：

- `RATE_LIMIT_UP_MBPS`
- `RATE_LIMIT_DOWN_MBPS`

空值表示该方向不限速。

例如：

| 配置 | 含义 |
| --- | --- |
| `RATE_LIMIT_UP_MBPS=""`, `RATE_LIMIT_DOWN_MBPS=""` | 不限速 |
| `RATE_LIMIT_UP_MBPS=""`, `RATE_LIMIT_DOWN_MBPS="20"` | 只限制下行 20 Mbps |
| `RATE_LIMIT_UP_MBPS="5"`, `RATE_LIMIT_DOWN_MBPS=""` | 只限制上行 5 Mbps |
| `RATE_LIMIT_UP_MBPS="5"`, `RATE_LIMIT_DOWN_MBPS="20"` | 上行 5 Mbps，下行 20 Mbps |

交互上不使用一个简单的“是否限速”布尔值作为唯一状态。可以先问是否配置限速；若用户选择是，再分别询问上行和下行，留空表示该方向不限速。

## State Model

### 协议索引保持兼容

`/root/sing-box-vps/protocols/index.env` 继续记录：

```env
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
```

这保证已有多协议框架不用改成“协议实例索引”。

### REALITY 协议主状态

保留 `/root/sing-box-vps/protocols/vless-reality.env`，但它从单实例状态升级为协议主状态。

建议字段：

```env
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
REALITY_PRIVATE_KEY=...
REALITY_PUBLIC_KEY=...
```

REALITY 密钥默认协议级共享。这样旧节点链接不会因为新增实例而变化，也避免每个实例都重复生成密钥。

### REALITY 实例状态

新增实例目录：

```text
/root/sing-box-vps/protocols/vless-reality.d/
```

每个实例一个 env 文件：

```text
/root/sing-box-vps/protocols/vless-reality.d/main.env
/root/sing-box-vps/protocols/vless-reality.d/limited-10m.env
```

实例字段：

```env
INSTANCE_ID=main
ENABLED=1
NODE_NAME=hostname-vless
PORT=443
UUID=...
SNI=www.cloudflare.com
SHORT_ID_1=...
SHORT_ID_2=...
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
```

字段约束：

- `INSTANCE_ID` 只能使用小写字母、数字和短横线，避免文件路径和 tag 注入问题。
- `PORT` 必须在所有已安装协议和 REALITY 实例中唯一。
- `RATE_LIMIT_UP_MBPS` 和 `RATE_LIMIT_DOWN_MBPS` 为空或正整数。
- `ENABLED=0` 预留给后续禁用实例能力，第一版可以不暴露菜单。

## Migration

### 旧单实例状态迁移

若检测到旧的 `/root/sing-box-vps/protocols/vless-reality.env` 包含单实例字段：

- `NODE_NAME`
- `PORT`
- `UUID`
- `SNI`
- `SHORT_ID_1`
- `SHORT_ID_2`

且不存在 `vless-reality.d/main.env`，则迁移为：

- 主状态：
  - `CONFIG_SCHEMA_VERSION=2`
  - `DEFAULT_INSTANCE_ID=main`
  - `INSTANCE_IDS=main`
  - 保留 `REALITY_PRIVATE_KEY`
  - 保留 `REALITY_PUBLIC_KEY`
- 实例状态 `main.env`：
  - 使用旧字段填充节点名、端口、UUID、SNI、short id
  - `RATE_LIMIT_UP_MBPS=""`
  - `RATE_LIMIT_DOWN_MBPS=""`

迁移前备份旧状态文件为 `.bak.YYYYMMDDHHMMSS`。

### 旧配置迁移

若协议状态缺失但现有 `config.json` 中存在 VLESS + REALITY inbound，继续沿用现有接管逻辑重建状态。重建时生成 `main.env`，并默认未限速。

### 链接兼容

迁移后的默认实例必须生成与旧配置等价的 `vless://` 链接：

- 端口不变
- UUID 不变
- SNI 不变
- public key 不变
- short id 使用旧的第一个 short id
- 节点名不变

## Menu Flow

### 首次安装

用户选择 VLESS + REALITY 时：

1. 输入端口。
2. 选择或自动选择 SNI。
3. 输入节点名，默认沿用现有命名。
4. 询问是否配置限速，默认 `n`。
5. 若选择限速：
   - 询问上行 Mbps，留空表示上行不限速。
   - 询问下行 Mbps，留空表示下行不限速。
   - 若两个方向都留空，视为不限速并提示。
6. 保存为默认 `main` 实例。

### 追加安装入口

当前追加安装会跳过已安装协议。改为：

- 若用户选择未安装协议，走现有新增协议流程。
- 若用户选择已安装的 VLESS + REALITY，进入“新增 REALITY 节点实例”流程。
- 其他已安装协议仍保持跳过或提示已安装。

新增实例流程：

1. 输入实例 ID，默认根据节点名或端口生成，例如 `reality-8443`。
2. 输入节点名。
3. 输入端口，必须与现有协议/实例不冲突。
4. 选择 SNI，默认复用当前默认实例 SNI。
5. UUID 默认自动生成。
6. short id 默认自动生成。
7. 配置可选上下行限速。
8. 生成配置、校验、刷新 QoS、重启服务。

### 修改配置

修改协议时：

1. 选择 `VLESS + REALITY`。
2. 若只有一个实例，可以直接进入该实例修改；也可以显示实例列表以保持一致。
3. 若有多个实例，列出：
   - 节点名
   - 实例 ID
   - 端口
   - 限速摘要
4. 用户选择实例后可修改：
   - 节点名
   - 端口
   - SNI
   - 是否重新生成 UUID
   - 是否重新生成 short id
   - 上行 Mbps
   - 下行 Mbps

修改端口或限速后必须刷新 QoS 规则。

### 移除

移除菜单中选择 `VLESS + REALITY` 后：

- 若只有一个 REALITY 实例，行为等同当前移除整个 `vless-reality` 协议，但仍遵守“不能删除最后一个已安装协议”的规则。
- 若有多个实例，先列出实例并让用户选择移除哪个。
- 移除非最后一个实例时，只删除该实例状态、重生成配置、刷新 QoS、重启服务。
- 移除最后一个实例时，删除 `vless-reality` 协议项和主状态。

## Config Generation

每个 REALITY 实例生成一个 VLESS inbound。

示例：

```json
{
  "type": "vless",
  "tag": "vless-reality-main",
  "listen": "::",
  "listen_port": 443,
  "users": [
    {
      "name": "main",
      "uuid": "...",
      "flow": "xtls-rprx-vision"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "www.cloudflare.com",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "www.cloudflare.com",
        "server_port": 443
      },
      "private_key": "...",
      "short_id": ["..."]
    }
  }
}
```

Tag 规则：

- 默认实例可以继续兼容旧 tag `vless-in`，降低现有测试和路由规则的变更量。
- 新实例使用 `vless-reality-${INSTANCE_ID}`。
- 若默认实例也改为新 tag，必须同步更新路由规则、节点展示、客户端导出和测试。

## QoS Design

### 规则所有权

脚本管理自己的一组 QoS 规则，不覆盖用户已有 `tc`/`nftables` 配置。

建议使用固定前缀标识：

- nftables table/comment: `sing-box-vps`
- tc class/qdisc handle/comment 采用可识别 ID

### 应用时机

以下操作后刷新 QoS：

- 首次安装
- 新增 REALITY 实例
- 修改 REALITY 端口或限速
- 移除 REALITY 实例
- 重生成配置
- 修复/接管旧安装

刷新策略应是幂等的：

1. 读取所有 REALITY 实例状态。
2. 计算需要限速的端口和方向。
3. 移除脚本旧规则。
4. 重新应用当前规则。

### 方向语义

从 VPS 视角定义：

- 下行限速：服务端发给客户端的流量，通常对应 VPS 网卡 egress。
- 上行限速：客户端发给服务端的流量，通常对应 VPS 网卡 ingress。

Linux 上 egress 更直接，ingress 可能需要 `ifb` 或 nftables mark 配合 `tc`。实现计划阶段需要确认目标发行版对 `ifb`、`tc` 和 `nft` 的可用性。

如果某系统缺少必需能力：

- 不应生成无法验证的半成品规则。
- 应提示用户当前系统不支持该方向限速或缺少组件。
- sing-box 配置本身仍可生成，但限速状态应明确标记为未应用失败，避免误导。

## Connection Info And Export

节点信息查看必须列出所有 REALITY 实例。

示例：

```text
--- VLESS + REALITY ---
main | 443 | 不限速
vless://...

limited-10m | 8443 | 上行不限速 / 下行 10 Mbps
vless://...
```

客户端导出必须为每个 REALITY 实例生成一个 outbound。

SubMan 同步的 external key 也需要区分实例：

```text
sing-box-vps:<prefix>:vless-reality:main
sing-box-vps:<prefix>:vless-reality:limited-10m
```

旧的单实例 external key 可以继续用于默认 `main`，也可以迁移到带实例 ID 的新 key。为了避免 SubMan 中出现重复节点，第一版建议默认实例继续使用旧 key，新实例使用新 key。

## Validation

安装和修改流程必须校验：

- 实例 ID 格式合法。
- 实例 ID 不重复。
- 端口不与任何协议或 REALITY 实例冲突。
- 限速值为空或正整数。
- 至少保留一个协议；若只剩一个 REALITY 实例且它是最后协议，不允许删除。
- 生成配置后必须执行 `sing-box check`。
- QoS 应用失败时必须给出明确错误或警告。

## Testing

需要新增或更新测试：

1. 旧 `vless-reality.env` 自动迁移为 `vless-reality.d/main.env`。
2. 迁移后的默认链接保持端口、UUID、SNI、public key 和 short id 不变。
3. 首次安装 VLESS + REALITY 时可以选择不限速。
4. 首次安装时可以只填下行限速，生成状态中上行为空、下行为指定值。
5. 首次安装时可以只填上行限速。
6. 首次安装时可以同时填上下行限速。
7. 已安装 VLESS + REALITY 后，追加安装入口允许新增 REALITY 实例。
8. 多 REALITY 实例生成多个 VLESS inbound，端口和 tag 唯一。
9. 节点信息展示所有 REALITY 实例及限速摘要。
10. 客户端导出包含所有 REALITY 实例的 outbound。
11. 移除一个非最后 REALITY 实例后，其它实例保留。
12. 移除最后 REALITY 实例时遵守协议删除规则。
13. 修改限速后会触发 QoS 刷新入口。
14. `bash dev/verification/run.sh` 通过，并在命中远程规则时执行真实远程验证。

## Open Implementation Notes

- 实现计划需要决定 QoS 后端细节：优先 `tc + nftables`，还是在缺少 `nft` 时提供降级路径。
- 实现计划需要确认测试环境是否可安全验证 `tc` 规则；若本地容器权限不足，测试应覆盖规则生成逻辑，远程验证覆盖真实应用。
- `install.sh` 修改完成后必须按项目规约递增 `SCRIPT_VERSION`，并同步更新 `README.md` 中展示的脚本版本。
