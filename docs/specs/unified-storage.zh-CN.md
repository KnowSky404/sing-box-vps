# 统一运行时存储与旧布局迁移

状态：已实现。以下契约对应本次实现，验收证据见第 8 节及交付 PR；生产迁移另行授权。

## 1. 现状与目标

当前业务根为 `/root/sing-box-vps`，协议实例、配置、密钥、ACME、WARP、规则集和日志混合存放；管理锁、事务目录及 WARP pending 文件在业务根旁边，升级备份在 `/root/sing-box-vps-backups`。脚本和核心分别在 `/usr/local/bin/sbv`、`/usr/local/bin/sing-box`，可选库在 `/usr/local/lib/libcronet.so`；临时文件还分散在 `/tmp`。来源是 `src/install/00-preamble.sh` 以及各事务、安装、升级模块。

目标是将本项目维护的实际文件集中到 root 账户主目录的 `.sing-box-vps`；按账户数据库解析主目录，不能受调用者 HOME、sudo 环境或 systemd 工作目录影响。当前脚本仍只支持 root 操作，不引入多用户安装。

用户已确认系统集成边界：系统 PATH 下保留命令入口/链接，systemd 标准位置保留服务入口；系统软件包、journal、sysctl、防火墙和路由等仍由系统管理。用户提供的外部证书和输入文件不自动搬运。

## 2. 布局和不变量

```text
<root-home>/.sing-box-vps/
  bin/                 sbv、sing-box 实际可执行文件及其原子更新 staging
  lib/                 项目维护的 libcronet.so
  runtime/             可整体快照/恢复的配置、协议、组件、WARP、ACME 和规则集
  modules/             可重新下载的辅助检查器等模块
  logs/                管理脚本日志
  backups/             当前布局升级备份、迁移备份、legacy 历史恢复材料
  tmp/                 Bootstrap、下载、探测、临时快照
  runtime.*            现有管理锁、持久事务及结果；均在统一根内
  migrations/          迁移 journal、完成记录及恢复入口
```

`SB_DATA_ROOT` 是统一根，`SB_PROJECT_DIR` 仅表示 `runtime/`。现有快照递归复制并原子替换 `SB_PROJECT_DIR`；锁、bin、备份及 tmp 必须在其外，以免递归复制、锁 inode 失效或丢失恢复材料。保留现有 runtime.* 事务命名，避免同时改变事务格式。

统一根及私有目录使用 root 所有、0700；秘密文件和迁移记录使用 0600。拒绝不可信所有权、可被非 root 写入的父目录和目标符号链接。运行时不从仓库下载维护源码；`install.sh` 仍是单文件分发产物。

启用 SELinux 的系统还需要项目专属的持久文件上下文规则，使私有目录下的核心、管理脚本、库与 systemd 单元能被正确访问。规则元数据由系统 SELinux 存储管理，实际 payload 仍只有统一根中的一份。不得关闭 SELinux、放宽 `/root` 整体或覆盖管理员冲突规则；安装、迁移、更新与恢复须在执行/激活前应用并校验相应标签，缺失工具或失败时明确拒绝。

全局入口独立于实际 artifact：更新器原子替换内部普通文件；全局符号链接保持为入口，内部目标若被替换成符号链接则拒绝写入；系统入口仅在确认是本项目所有后发布或清理。服务使用新的核心和配置绝对路径，设置工作目录及私有临时/库搜索环境。核心组件的默认状态/缓存通过服务 HOME、XDG、WorkingDirectory、TMPDIR 收入统一根：例如 Tailscale 默认位于 runtime/tailscale，Tor 的缺省临时状态位于 tmp。辅助检查器还使用私有模块 HOME、XDG 目录和工作目录，避免相对 Cookie/缓存写入操作者目录；明确配置的外部路径保留。

## 3. 升级入口和操作面

旧自更新器只会替换 `/usr/local/bin/sbv`；新脚本第一次启动必须识别旧布局，不能把旧安装误判为空安装或直接覆盖。识别范围也包括卸载核心后仅保留旧普通 sbv 与管理锁的正常状态；未知全局文件不自动接管。历史固定目录始终是 /root/sing-box-vps，不随新 root 账户主目录变化。克隆后以 bash ./install.sh 相对路径启动同样支持迁移，脚本叶节点符号链接仍拒绝。

提供结构化 `sbv storage status --json`、`sbv storage migrate --json --yes`、`sbv storage recover --json --yes`，兼容 `sbv agent storage ...`，在嵌入式目录声明确认、锁、服务影响和恢复边界。status 返回旧/新布局、阻塞原因、迁移阶段与恢复材料位置，不返回秘密。

help、commands、schema 等发现操作保持只读可用。普通操作遇旧布局或未完成迁移必须报 `storage_migration_required`/`storage_recovery_required`，不能读取空的新目录或开始其他写入。菜单明确提供同一业务迁移/恢复入口；不得通过自动回答提示伪装结构化支持。

菜单自更新可能继承旧管理锁 FD。迁移必须验证其实际路径并保持旧锁，同时获取新根管理锁；不得在锁路径变化时盲目沿用 FD，也不得释放后与旧进程并发修改。

## 4. 迁移事务

1. **prepare**：盘点固定旧目录、历史备份、核心、脚本、受管库及 unit；校验目录权限/链接、目标冲突、工具和容量。同时持有旧、新布局锁。新旧数据同时存在时拒绝覆盖。
2. 发现未完成实例、组件、规则或 WARP 注册事务时拒绝迁移，提示先使用已保留或固定旧版运行时恢复；旧自更新可能已经覆盖全局旧脚本，不能假设迁移备份含旧版本。历史已提交结果、rules-previous 也不能被当作新格式直接恢复。
3. **validate**：先记录原服务活动状态并暂停活动服务，保证 ACME/模块数据复制一致；停机窗口包含复制和校验。随后在统一根内私有 staging 复制完整旧数据及当前新脚本、核心和已证明受管的库。按路径字段重写旧根内部的引用，保留外部路径、协议身份、revision、凭据和未知文件。旧树中的符号链接、设备、FIFO 或 socket 当前不自动搬运，需先确认来源并用旧运行时调和。准备服务候选并执行 `bash -n` 和状态格式检查。为让文件引用可解析，可先在 journal 保护下发布新根内部的候选目录；在替换系统入口或启动新服务前，必须对实际候选位置执行目标核心 `sing-box check`，失败立即回滚。
4. **backup**：将旧脚本、unit、入口和服务原活动状态写入受保护的迁移 journal。历史升级备份原封归档为 legacy；保留校验清单，不冒充新布局可直接回滚的备份。
5. **commit**：必要时停止服务；逐项原子发布已验证 artifact、runtime 与入口。每项副作用记录阶段，信号/掉电后普通操作受 journal 阻挡。
6. **postcheck**：再次检查配置；原活动服务必须启动成功并确认 active，原停止服务保持停止。校验入口目标和文件摘要，写入完成记录。
7. **rollback/recover**：恢复旧入口、unit、原路径与服务状态。文件恢复不代表服务恢复成功；失败时保留 journal 和备份，明确 `rollback_failed`，允许显式 recover 重试。不得静默继续。
8. **cleanup**：成功后旧内容归入统一根的迁移备份；不得留一套继续可写的旧数据。旧路径兼容需要单独记录，不允许依赖隐藏双写。仅删除已确认由该事务创建的 staging/入口。旧根旁的归档只接受 management.flock、instance-transactions、rules-previous，以及准确 6 位随机后缀的 firewall-reconcile 和 8 位后缀的 warp-register；未识别的同前缀用户文件保持原位。

迁移要求旧数据、统一根与系统入口的父目录位于同一文件系统，以便使用可回滚的原子 rename；独立挂载的 `/usr/local` 等布局当前明确拒绝，不能以非原子复制冒充完成。对旧 Tor/Tailscale 状态与 Taildrop、ACME/OriginCA 证书存储、API dashboard 等缺省可写目录，以及无法确定原工作目录的相对受管路径，要求操作者先定位并配置明确路径后再迁移，不能静默创建新身份或新证书账户。文件路径审计以固定 1.14.2 官方配置结构为准，覆盖 DNS hosts/DHCP lease、CA 目录、DERP mesh PSK、SSM 缓存、OCM/CCM 凭据与用量、API dashboard、namespace 与 unshare pid 文件；网络 URL、HTTP/WS 路径、任意 headers/extra_headers 及其他官方自由数据 map、进程匹配条件和 certificate.store 枚举保持原义；namespace 逻辑名仍按核心语义解析，不误当作工作目录下的相对文件。受管文件路径在归属匹配前规范化重复斜杠，外部路径保留原字符串；含 . 或 .. 组件的文件路径需先规范化。

自定义旧 unit 的工作目录、文件系统视图或环境，以及任意有效 systemd drop-in，当前明确拒绝自动迁移；须由操作者先调和。不能保留会覆盖新目录设置的旧 directive 后仍报告迁移成功。读取 drop-in 信息失败同样拒绝，不能当作没有 drop-in。

### 路径与历史数据

只重写明确的路径字段（如 data_directory、state_directory、certificate_path、key_path、config_path、private_key_path、本地规则集 path，以及 legacy CERT_PATH/KEY_PATH/ACME_EXTRA_JSON）。不要全局替换文本；密码、UUID、节点名、网络 URL 和用户外部证书路径保持不变。Hysteria2 masquerade 的本地 file: URI 仅在可无损识别的本地主机/旧受管根范围内迁移，不把 HTTP(S) URL 当作文件路径处理。生成基线与实时配置同步重写，不借迁移重建用户配置。

旧运行目录内的历史 .bak 及归档旧树保留历史语义，不作为新布局自动恢复输入；新操作产生的 .bak 才携带新路径。历史升级备份包含绝对路径和 SHA256SUMS；保留原字节与原路径清单，登记为历史离线恢复材料。旧事务不能通过简单文本替换改造成新事务。未识别的外部路径不得删除；不能无损转换时明确阻止迁移并给出原因。

## 5. 新安装、更新和卸载

新安装不创建旧根、旧备份根或系统目录中的 artifact 临时文件。Bootstrap 与内部探测使用统一 tmp，下载继续完整校验后原子发布。模块和核心实际文件均在统一根内。

核心卸载仍保留管理命令及恢复备份；彻底卸载按明确确认删除受管运行时与命令，保留恢复目录时对应项目 SELinux 规则也保留，供重装幂等复用；迁移/升级备份的保留或删除必须明确报告，不能删除外部文件或非受管入口。单独卸载管理脚本不得隐式删除仍在服务使用的核心/配置。

## 6. 实施顺序与验收

1. 本 SPEC、双语索引与路径审计。
2. 路径常量、私有目录、临时文件、模块默认目录、系统入口和卸载。
3. 迁移/恢复事务、共享入口门禁、操作目录与手册。
4. 适配隔离测试路径，新增迁移故障和运行态场景，生成 install.sh 与命令参考。
5. 注册全量回归（本次真实涉及配置/状态迁移），另加迁移专用 Docker；当前 HEAD 本地审查、PR、远程安全审查和 rebase 合并按 AGENTS.md 执行。

必须覆盖：fresh、旧更新后第一次执行、活动/停止服务迁移、重复迁移、冲突/符号链接/权限拒绝、旧 pending 事务拒绝、新旧管理锁并发、热切换 FD、路径字段迁移且秘密/外部输入不变、历史备份摘要不变、临时文件收拢、快照无递归、自更新、故障回滚、中断恢复与卸载。受影响配置全部执行 sing-box check。

结果分别记录宿主/mock、核心 check、Docker 服务/生命周期、外部服务、公网、生产、review/merge 与 Wiki 发布。未执行项不得记为通过。

## 7. 默认目录依据

SELinux 持久映射及应用依据 [RHEL Using SELinux](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/epub/using_selinux/proc_creating-a-local-selinux-policy-module_writing-a-custom-selinux-policy)、[semanage fcontext](https://github.com/SELinuxProject/selinux/blob/main/python/semanage/semanage-fcontext.8) 和 [restorecon](https://github.com/SELinuxProject/selinux/blob/main/policycoreutils/setfiles/restorecon.8)。

文件字段审计采用固定 [1.14.2 option 结构](https://github.com/SagerNet/sing-box/tree/v1.14.2/option) 及对应运行实现；namespace 的逻辑名与路径区分见 [namespace manager](https://github.com/SagerNet/sing-box/blob/v1.14.2/common/netns/manager_linux.go)。

Tailscale 的默认 state_directory 为相对的 tailscale，官方配置见 [Tailscale endpoint](https://github.com/SagerNet/sing-box/blob/v1.14.2/docs/configuration/endpoint/tailscale.md)。Tor 的目录结论来自固定 1.14.2 源码链：[sing-box Tor outbound](https://github.com/SagerNet/sing-box/blob/v1.14.2/protocol/tor/outbound.go)、锁定 sing 的 [filemanager](https://github.com/SagerNet/sing/blob/87c33f17688f/service/filemanager/manager.go) 和 bine 的 [Tor startup](https://github.com/cretz/bine/blob/v0.2.0/tor/tor.go)。未显式配置 DataDir 时，其临时目录跟随 os.TempDir，因此服务 TMPDIR 将其约束在统一根的 tmp；这是源码推导，不能替代真实 Tor 网络验收。

## 8. 本次验证记录（2026-11-03）

本次涉及存储路径和持久配置迁移，按 AGENTS.md 4.2 执行注册的全量宿主清单与 Docker 场景集，并补充独立容器验证。最终清单、失败修复后的定向复测、内容摘要和当前 HEAD 审查结果记录于本次 PR；不能只凭调度入口返回成功认定通过。

| 验证边界 | 已确认结果 |
| --- | --- |
| 迁移隔离测试 | 27 个场景通过：路径字段、密钥/摘要保留、冲突与权限、双锁/继承 FD、恢复入口 CAS、管理器残留、相对入口、DNS hosts、对象/URI 伪装目录、完整文件路径审计及故障恢复。 |
| 迁移专用 Docker | 真实旧更新器交接、活动/停止服务、HY2 本地 file URI、真实 systemd 203/EXEC 故障回滚均通过；另有当前迁移模块的管理器残留与自定义 ExecStartPre 拒绝验证。 |
| SELinux | AlmaLinux 9.5 独立内核 Enforcing 下复现未标记核心的 203/EXEC；项目标签修复后新服务、原子更新、失败回滚、标签漂移修复及活动旧布局迁移/归档后重启通过。最终入口与管理员规则保护的证据在交付 PR 单独记录。 |
| 独立运行态 | Agent 操作、三组路由策略、组件 shared/resolved/default/unshare 通过；兼容构建差异单独记录。 |
| 模块目录与网络 | 媒体工具 HOME/cwd/XDG/TMPDIR 隔离测试通过；受控 Tailscale/OpenConnect 存储与重启身份通过；HTTP TCP/HY2 UDP 双栈通过；真实 REALITY checker/TLS/DNS/握手和信号清理通过。 |
| 构建与目录契约 | install 源码/生成产物、命令目录生成、操作契约、Bootstrap 和版本一致性通过。 |
| 外部与生产 | 未执行真实 Cloudflared 资源写入、外部 SubMan 同步、公网可达性或生产迁移；受控 VPN 存储验证不表示完整 VPN 矩阵通过。 |

测试容器和本地 mock 使用隔离数据与虚构凭证。固定下载经过现有摘要验证；离线缓存只替代传输，不替代真实核心、systemd 或探针。由于根目录包含密钥、Token 和配置，测试的完整 artifact bundle 保留在私有开发路径，不作为公共 Wiki 附件发布。

## 9. 旧核心属主与阻塞诊断修正（2026-11-04）

旧系统入口仍须为 root 所有的普通文件，父目录须可信。status 与 migrate 共用检查；
status 新增 `blocker_details`，每项包含 `code`、`entry`、`path`、`reason`，
`blockers` 同步列出唯一错误码。status 的成功仅表示读取成功，不表示可以迁移。
migrate 保留 `migration_failed`，stderr 报告具体拒绝路径。检查不修改属主，
不接受源符号链接。经过校验的新核心、受管库和标记发布为 root:root，失败回滚
仍保留旧字节与元数据；未受管外部库不在修复范围。生产修复须先与可信发布产物
逐字节核验、私有备份并获得授权，服务恢复与公网验收分别记录。
