# WARP 媒体检测会话安全

## 问题与证据边界

旧版 `2026110602` 的菜单 `12 → 4 → 2` 从保存的账户资料构造第二个
WireGuard endpoint，通过临时 SOCKS 调用 RegionRestrictionCheck。启动前不要求
正式服务存在，因此已有正式 WARP 服务时也可能并行使用相同身份。旧清理只在
正常返回或显式错误分支执行，信号退出可能遗留实例、端口和含私钥配置。

本次代码核实只有此诊断路径独立运行临时 sing-box 并复制 WARP 身份；共享的
`warp_endpoint_json_for_generation` 仍用于正式配置生成和明确的网络事务，
不属于独立诊断隧道。状态/doctor/config-check 不建立隧道。

WireGuard 按公钥识别 peer，并从认证包更新其 endpoint。隔离 Linux WireGuard
对端及两个 sing-box 客户端使用新生成测试密钥，可以复现 endpoint 改变及原连接
超时。此结果证明风险机制，不证明 2026-11-11 生产断线的唯一根因；没有断线
时抓包、Cloudflare 对端记录或瞬时资源测量，资源压力等仍不能排除。

## 最小修复与限制

- 不再创建检测用 WireGuard、sing-box 或临时代理端口，不读取保存的 WARP 密钥。
- 只复用正式服务的已有认证 SOCKS/HTTP/Mixed 入口，访问地址限定 loopback。
  TLS HTTP 入口及其他协议本轮不适配；没有合适入口就明确拒绝。
- 正式服务必须 active，MainPID 的启动命令须匹配受管二进制及配置路径；配置
  修改时间不得晚于服务启动时间（使用 systemd D-Bus 微秒属性，兼容旧版 systemd）。未知/不可读元数据不能代替已加载配置证据。
- 保守解析路由：排除可证明不匹配该入口的规则，允许 sniff/reject，首个可能
  路由必须为入口或全局无条件 `warp-ep`；否则只在没有其他可能路由且 final
  为 `warp-ep` 时接受。空 inbound 列表按不限入口处理；DIRECT、条件匹配、invert、logical、selector 或未知动作
  不得被忽略。正式配置先通过 `sing-box check`，拒绝时不打印解析或凭据内容。
- 经私有 curl 配置携带认证，最后应用代理和空 noproxy，覆盖环境代理绕过。
  使用私有 PATH 包装器和后端 `-C` 扩展统一覆盖其 curl（包括没有使用 `$curlArgs` 的辅助请求）；
  `-P` 标记代理模式，使用不可达占位地址，只有受保护 curl 的最终配置能转发。
- 先经相同入口验证 HTTPS trace 的 `warp=on/plus`；此检查不能单独证明所有目标
  的出口，所以必须同时满足路由证明。每次 curl 核对 PID/配置摘要，检测末尾再
  检查服务快照。并发人工热改、进程替换或非受管配置加载存在不可原子化窗口；
  不支持检测期间修改服务/路由，变化使结果无效，不能当作稳定出口验收。
- 缓存后端不变，每次 HOME、缓存、Cookie 和临时文件移到独立的私有工作区。
  认证不进参数、日志或环境。仅杀本次独立进程组；EXIT、INT、TERM、HUP 清理，
  独立监护在父进程消失或 15 分钟上限后终止后代并清理目录。整个组被 SIGKILL
  或掉电后的残留无法由 trap 保证清理，不作相反承诺。
- 保持 `system.media` 为交互操作：外部后端没有稳定结构化结果，此修复不新增
  无法验证的自动化接口。操作目录、Agent 导航与管理文档同步前提和边界。

不新增生产入口、不改已有路由/地址族优先级、不注册/轮换账户。只有其他协议
入口的主机会安全拒绝；生产如需增加专用认证 WARP 入口，须另行说明影响、备份、
配置校验与回滚并获得批准。原有孤儿检测进程也需重新发现后单独批准清理。

## 定向验证

- `tests/media_warp_safety.sh` + Python fixture：路由拒绝、trace off、服务缺失、
  后端失败、正常/原生、INT/TERM/HUP、父进程退出、owner 被杀、超时和并发。
- `dev/verification/media-warp-runtime.sh`：`--network none` 容器内真实 WireGuard 对端，
  同身份争用复现，以及真实 SOCKS/Mixed/HTTP 认证入口经正式核心现有隧道；
  检查请求源地址、核心数量、监听端口、配置/保存密钥不变、stale 配置和隧道失效。
  systemd 元数据、Cloudflare trace 与媒体后端使用本地 fixture，不冒充真实供应商验收。
- 受影响既有用例：node/network independence、legacy WARP baseline repair、module
  storage、routing/media draft independence；生成产物、操作目录、语法及文档检查。
- 不要求无关协议/升级/卸载全量场景；不在生产重跑旧检测或更新生产脚本。

## 本轮验收记录（2026-11-11）

- 只读确认目标安装脚本与修复前 main 的完整 SHA-256 相同，均为 `2026110602`；
  正式核心 `1.14.2`。重新发现的旧临时实例仍与正式 endpoint 身份相等，未终止。
- 官方 `1.14.2`（release asset digest 核对一致）隔离复现：基线 `60000` 字节完整，
  第二客户端请求成功、对端 endpoint 改变，原流 `14000` 字节后超时，curl `28`。
- 修复后 SOCKS、Mixed、HTTP 认证入口均在同一真实核心中复用已有隧道；测试服务
  收到的 trace 与媒体请求来源均为隧道地址。无第二核心/新增监听，配置与保存的
  sidecar 摘要不变；隧道失效、服务配置过期均拒绝。HTTP 使用 CONNECT。
- 生命周期 fixture 覆盖成功、启动失败、后端失败、trace off、服务不可用/PID
  变化、原生检测、INT/TERM/HUP、父进程退出、owner SIGKILL、超时及并发隔离；
  检查无存活后代/工作区，认证不出现在输出或参数，普通 curl 与 `-C` 均受保护。
- 定向旧用例、生成产物、命令目录、Shell/Python 语法、版本一致性和文档导航通过。
  legacy baseline 用例按其固定要求使用官方 `1.14.4`，未改变项目支持版本。
- `1.14.2` 在无默认接口的容器会暂停 WireGuard；测试只给该隔离 netns 添加 dummy
  默认接口，不提供外网。HTTP 本地 fixture 以 CONNECT 验证实际隧道转发。
- 未部署生产、未重跑旧检测、未重启正式服务、未做真实 Cloudflare/流媒体或生产
  资源压力验收。旧控制机报告/备份在当前环境不可访问，不作为已读取证据。
