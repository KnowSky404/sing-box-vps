# PROMPT

目前这个仓库我想开发一个针对VPS一键安装sing-box服务的脚本,请先根据shell开发标准,以及项目背景,为我先生成一个 @GEMINI.md 文件吧,用来存放开发约束和项目背景,要求使用中文.我在你的基础之上我再去新增一些约束.

目前一键安装脚本需要包含的功能:
1. 获取当前系统的环境和架构信息,并安装所必须的工具,比如curl,wget等
2. 下载安装当前系统对应最新的sing-box软件
3. 然后安装对应的sing-box, 目前暂时只提供 vless+reality的协议
4. 完成安装后,自动输出安装信息,节点信息 文件路径,日志路径等等

其中脚本需要有交互的功能(至少下属条件是必须包含的,其他的根据你的理解来):
1. sing-box 版本信息,默认是最新的
2. 需要安装的协议,现在默认就提供 vless+reality这一个入站协议
3. 协议节点的名称: 默认协议名称+当前hostname
4. 协议端口:默认443
5. 协议UUID等等其他信息,默认自动生成之类的

目前还需要有两个版本的概念:
1. 当前脚本的版本,用来表示当前脚本的版本信息
2. 当前脚本支持的最新的sing-box版本,注意sing-box 不一定是使用最新的sing-box,而是当前脚本适配到的最新的sing-box版本信息. 因为sing-box每个版本可能有break变动,如果当前脚本的版本不支持的话,就可能会导致安装有问题

脚本版本需要使用日期来命名,比如 20260405 这样的, 当前版本需要适配的sing-box版本是 1.13.5,我们后续也先根据这个sing-box版本来开发

reality协议的默认使用的域名是 apple.com

继续做1和2吧 (1. 添加 uninstall 逻辑; 2. 增强配置生成的安全性)

@PROMPT.md 这个在改动完成之后也帮我同步提交吧,这个就是记录我每次发给你的提示词内容

当前项目的地址是 https://github.com/KnowSky404/sing-box-vps 帮我先更新一下 @README.md 文件,主要重点加入一键安装的脚本

修正 README.md 中的协议声明为 AGPL-3.0

更新安装方式为单脚本 curl 方式 (install.sh)

添加展示二维码功能 (qrencode)

规范安装路径：创建 sing-box-vps 目录并进入后再下载 install.sh

安装逻辑：增加下载清理步骤，确保每次安装环境纯净。

交互增强：增加 REALITY SNI 域名的交互式选择，默认 apple.com

功能增强：将 install.sh 安装为全局命令 sbv，方便用户在任意目录执行交互菜单。

功能扩展：完善 sbv 菜单，增加服务管理、配置解析找回及日志查看选项。

功能大升级：脚本自更新、版本对比提示、独立配置修改、智能端口冲突处理。

Bug修复：移除入站配置中不支持的 utls 字段，修复配置文件解析失败的问题。

版本规范：调整 SCRIPT_VERSION 格式为 YYYYMMDDXX，支持每日多次迭代对比。

配置修正：适配 sing-box 1.13.0+ 规范，将 sniff 逻辑从 inbound 迁移至 route 规则中。

功能优化：将脚本自更新逻辑整合进主菜单选项 9，并实时显示版本状态。

Bug修复：修复在通过 sbv 命令运行时，cp 自己导致冲突报错的问题。

交互优化：配置修改模式改为“静默读取+交互修改”，待完成后才展示最终新配置，避免重复刷屏。

功能美化：在 show_banner 中增加作者 KnowSky404、项目地址及项目描述信息。

功能大跃进：增加 BBR 加速、防火墙自动放行、广告/局域网分流规则以及配置语法校验。

功能优化：高级路由规则（广告拦截/局域网绕行）改为交互式可选项，支持在安装和修改配置时动态开启或关闭。

UI/逻辑优化：修正 Banner 布局对齐问题；在安装最新版时增加重复安装确认提示。

路径优化：将 sing-box 的配置文件和日志文件统一迁移至 /root/sing-box-vps 目录下，并开启日志文件记录。

同步修复：确保在修改配置流程中也同步更新 systemd 服务文件，以适配路径迁移。

Bug修复：修复检测脚本更新时由于管道提前关闭导致的 curl: (23) Failed writing body 错误。

功能完善：增加选项 11 用于卸载管理脚本自身，并支持在卸载时确认是否清理配置文件目录。

文档优化：简化 README.md 中的一键安装命令为 curl 管道方式，并强调 sbv 命令的便捷性。

Bug修复：修复 bash <(curl ...) 管道模式下 cp 命令因无法 stat 管道描述符导致的报错。改为检测到非 sbv 运行环境下，通过 curl 直接从远程安装 sbv 命令。

Bug修复：补全在代码合并中丢失的 view_status_and_info 函数，修复选项 8 报错问题。

Bug修复：修复解压 sing-box 时由于当前工作目录不存在导致的 tar: Cannot getcwd 错误。通过在解压前强制切换至 /tmp 解决。

功能大修复：1. 实现 REALITY 密钥持久化存储，修复查看信息时公钥由于重新生成而不匹配导致的连接失败；2. 将日志级别提升至 debug 并确保文件记录，解决日志静默问题。

文档更新：重构 README.md，完整展示当前版本的所有功能特性及管理命令。

功能调整：由于配置文件指定了日志输出到文件，将选项 9 的查看方式从 journalctl 切换为 tail -f。

功能回退：移除配置文件中的 output 日志文件输出，将选项 9 恢复为 journalctl 查看方式，并将日志级别调回 info。

功能大升级：增加 Cloudflare Warp 可选功能支持。通过 sing-box 内置 WireGuard 出站实现自动注册和路由分流，有效解决 IP 送中及流媒体解锁问题。

Bug修复：删除 install.sh 中残留的代码占位符 ...，修复脚本启动失败的问题。

功能补全：增加主菜单选项 12，提供专门的 Cloudflare Warp 管理子菜单，支持一键开关及重新注册。

功能增强：增强 Warp 注册逻辑的错误处理，增加对非 JSON 响应的捕获，方便排查 Cloudflare API 报错原因。

Bug修复：调整 Warp 注册 Payload 参数（固定 TOS 时间、增加随机安装 ID 和更新 UA），修复 Cloudflare API 返回 Invalid registration request 的问题。

功能大升级：1. 增加脚本专用运行日志 /root/sing-box-vps/sbv.log，用于记录详细的运行轨迹和 API 交互明细；2. 再次尝试更新 Warp 注册 API 路径及参数，解决 Invalid registration request 问题。

Bug修复：修复 Warp 注册时无法正确提取 WireGuard 密钥导致 Invalid registration request 的问题。优化提取正则并增加失败拦截逻辑。

Bug修复：修复 Warp 注册时由于 sing-box 命令写错 (应为 wg-keypair 而非 wireguard-keypair) 导致无法生成密钥的问题。

Bug修复：修复 Warp 注册成功但脚本解析报错的问题。适配 Cloudflare v0a2445 接口的返回结构，改用 id 字段作为成功标识并修正 JSON 提取路径。

Bug修复：修复 WireGuard 出站配置语法错误。在 sing-box 中，server、server_port 和 public_key 必须嵌套在 peers 数组中。

Bug修复：根据 sing-box 1.13.5 官方文档彻底修正 WireGuard 出站语法。1. 修正本地地址字段为 address 且补全 CIDR；2. 修正对端字段为 address 和 port；3. 补全 allowed_ips。

Bug修复：回归 sing-box 标准 Outbound WireGuard 结构。1. 使用 local_address 并补全 CIDR；2. 移除 peers 嵌套，将 server、server_port、peer_public_key 放回顶级字段。适配 1.13.5。

Bug修复：终极修复 WireGuard 1.13.5 语法。1. 顶级字段为 address；2. 嵌套使用 peers；3. peers 内部使用 server 和 server_port。

Bug修复：根据 1.13.5 官方文档最终确认 WireGuard Outbound 语法组合。顶级必须为 local_address，且 peers 内部必须使用 address 和 port。彻底解决 unknown field 报错。

架构升级：根据 sing-box 1.13.x 官方规范，将 WireGuard 从 Outbound 模式重构为 Endpoint 架构。1. 增加 endpoints 块存放配置；2. route.final 直接引用 endpoint 标签。彻底解决 1.13.x 版本中 WireGuard 出站字段不被识别的问题。

功能大修复：1. 经本地校验，确定 sing-box 1.13.x 的 WireGuard 配置必须使用 endpoints 架构；2. 移除已废弃的 geosite/geoip 路由规则，解决 1.12.0+ 版本中的报错问题。

Bug修复：修复 Warp 私钥 Base64 解解报错问题。在保存和提取 Warp 密钥时增加严格的 tr -d '
 ' 清理逻辑，确保 Base64 数据的纯净性。

Bug修复：使用正则提取方式 ([A-Za-z0-9+/]{42,44}=*) 彻底重写 Warp 密钥提取逻辑，防止任何细微的非法字符进入配置文件导致的 Base64 解码失败。

Bug修复：经本地环境实测确认，使用 awk '{print $2}' 配合 tr -d 进行密钥提取最为稳健。修复了之前正则逻辑可能导致的 Base64 补位符丢失及位长不足导致的解码失败问题。

功能大重构：经本地环境 100% 成功验证，将配置文件生成逻辑由 Heredoc 拼接彻底迁移至 jq --arg 安全注入模式。这完美解决了 Base64 密钥中特殊字符（如 /、+、\）导致的 Shell 转义破坏 JSON 的问题，极大提升了脚本的稳定性。
