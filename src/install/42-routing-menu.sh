routing_notice() {
  local level=$1 message=$2 color="${BLUE}"
  [[ "${level}" != WARN ]] || color="${YELLOW}"
  printf '%b[%s]%b %s\n' "${color}" "${level}" "${NC}" "${message}" >&2
}

# Changes in this UI affect only a private draft until explicit application.
routing_draft_edit() {
  local draft=$1 filter=$2 next="${1}.next"
  shift 2
  if jq "$@" "${filter}" "${draft}" > "${next}" && routing_draft_validate "${next}"; then
    chmod 600 "${next}" && mv -f -- "${next}" "${draft}"
  else
    rm -f -- "${next}"
    routing_notice WARN '设置无效，草稿未修改。'
    return 1
  fi
}

routing_boolean_label() {
  case "${1:-false}" in true) printf '%b开启%b' "${GREEN}" "${NC}" ;; *) printf '%b关闭%b' "${YELLOW}" "${NC}" ;; esac
}

routing_policy_needs_adoption() {
  [[ ! -f "${SB_ROUTING_POLICY_FILE}" ]] ||
    jq -e '.schema_version != 2' "${SB_ROUTING_POLICY_FILE}" >/dev/null
}

routing_policy_overview() {
  local draft=$1 nodes
  nodes=$(routing_nodes_json) || return 1
  render_left_aligned_page_header '网络与分流' '只管理本 VPS 的服务端网络策略；修改先保存为草稿'
  render_summary_item 'Block CN' "$(routing_boolean_label "$(jq -r '.policy.server.block_cn' "${draft}")")"
  render_summary_item '默认出口（草稿）' "$(jq -r 'if .warp.enabled then (if .warp.mode=="all" then "WARP 全量" else "原生默认 + WARP 选择性分流" end) else "原生出口" end' "${draft}")"
  render_summary_item 'AI / 流媒体走 WARP' "$(jq -r '(.policy.server.warp_ai|tostring)+" / "+(.policy.server.warp_streaming|tostring)' "${draft}")"
  render_summary_item '独立出口节点 / 待修改' "$(jq '[.[]|select(.policy!="default")]|length' <<< "${nodes}") / $(jq '.node_overrides|length' "${draft}")"
  if routing_policy_needs_adoption; then
    echo '应用时启用当前服务端策略格式，并清理脚本原先生成的广告与私网限制；取消不会修改现有配置。'
  fi
  if jq -e '.warp.reregister' "${draft}" >/dev/null; then
    routing_notice WARN '应用时将重新注册 WARP；文件回滚不能撤销已发送的云端注册。'
  fi
}

routing_policy_preview() {
  local draft=$1
  routing_draft_validate "${draft}" || return 1
  routing_policy_overview "${draft}" || return 1
  echo '受管规则顺序：嗅探 → Block CN（域名、解析、IP）→ 节点出口 → 自定义 → AI / 流媒体 → 默认出口。'
  jq -r '.policy.server.rules[] | "规则: \(.id) [\(.kind)] → \(.action) / enabled=\(.enabled)"' "${draft}"
  jq -r '.policy.server.rule_sets[] | "规则源: \(.tag) [\(.type),\(.format)] → \(.action) / enabled=\(.enabled)"' "${draft}"
  jq -r '.node_overrides[] | "节点出口: \(.protocol)/\(.id) → \(.policy)"' "${draft}"
  echo '规则源 URL、账户密钥和节点凭据不在预览中展示。应用时执行完整配置与服务检查。'
}

routing_default_outbound_menu() {
  local draft=$1 choice
  while true; do
    render_left_aligned_page_header '默认出口与 WARP 管理' '影响全局默认策略；独立节点和自定义 WARP 依赖会保留'
    render_menu_item 1 '默认使用原生出口'
    render_menu_item 2 '原生默认，AI / 流媒体及自定义选择性使用 WARP'
    render_menu_item 3 '默认全部代理流量使用 WARP'
    render_menu_item 4 '设置 / 取消应用时重新注册 WARP 账户'
    render_menu_item 5 '节点出口设置（跟随全局 / 原生 / WARP）'
    render_menu_item 6 '高级：自定义服务端域名 / IP 分流'
    render_menu_item 7 '高级：WARP 规则源与既有资产'
    echo '0. 返回'
    choice=$(prompt_choice '请选择 [0-7]: ' 0 7 '') || return 0
    case "${choice}" in
      0) return ;;
      1) routing_draft_edit "${draft}" '.warp.enabled=false' || return 1 ;;
      2) routing_draft_edit "${draft}" '.warp.enabled=true | .warp.mode="selective"' || return 1 ;;
      3) routing_draft_edit "${draft}" '.warp.enabled=true | .warp.mode="all"' || return 1 ;;
      4) routing_draft_edit "${draft}" '.warp.reregister |= not' || return 1 ;;
      5) routing_node_policy_menu "${draft}" || return 1 ;;
      6) routing_collection_menu "${draft}" rules || return 1 ;;
      7) routing_sources_menu "${draft}" || return 1 ;;
    esac
  done
}

routing_presets_menu() {
  local draft=$1 choice
  while true; do
    render_left_aligned_page_header 'AI / 流媒体分流' '只在全局选择性 WARP 模式下生效'
    render_menu_item 1 '切换 AI 分流' '' "$(jq -r '.policy.server.warp_ai' "${draft}")"
    render_menu_item 2 '切换流媒体分流' '' "$(jq -r '.policy.server.warp_streaming' "${draft}")"
    echo '0. 返回'
    choice=$(prompt_choice '请选择 [0-2]: ' 0 2 '') || return 0
    case "${choice}" in
      0) return ;;
      1) routing_draft_edit "${draft}" '.policy.server.warp_ai |= not' || return 1 ;;
      2) routing_draft_edit "${draft}" '.policy.server.warp_streaming |= not' || return 1 ;;
    esac
  done
}

routing_collection_index() {
  local draft=$1 collection=$2 count choice
  count=$(jq --arg collection "${collection}" '.policy.server[$collection]|length' "${draft}") || return 1
  [[ "${count}" -gt 0 ]] || { routing_notice WARN '当前没有条目。' >&2; return 1; }
  choice=$(prompt_choice "请选择条目 [1-${count}]，0 取消: " 0 "${count}" '') || return 1
  [[ "${choice}" != 0 ]] || return 1
  printf '%s' "$((choice - 1))"
}

routing_rule_record_prompt() {
  local current=${1:-'{}'} id kind value action choice enabled=true
  id=$(jq -r '.id // ""' <<< "${current}") || return 1
  value=$(jq -r '.value // ""' <<< "${current}") || return 1
  kind=$(jq -r '.kind // "domain_suffix"' <<< "${current}") || return 1
  action=$(jq -r '.action // "warp"' <<< "${current}") || return 1
  enabled=$(jq -r 'if has("enabled") then .enabled else true end' <<< "${current}") || return 1
  read -rp '规则 ID（小写字母/数字/-/_，修改时留空保留）: ' choice || return 1
  id=${choice:-${id}}
  echo '匹配: 1 精确域名 / 2 域名后缀 / 3 IP CIDR' >&2
  case "${kind}" in domain) choice=1 ;; ip_cidr) choice=3 ;; *) choice=2 ;; esac
  choice=$(prompt_choice '匹配类型 [1-3]: ' 1 3 "${choice}") || return 1
  case "${choice}" in 1) kind=domain ;; 2) kind=domain_suffix ;; 3) kind=ip_cidr ;; esac
  read -rp '匹配值（纯域名或 CIDR，修改时留空保留）: ' choice || return 1
  value=${choice:-${value}}
  echo '动作: 1 原生 / 2 WARP / 3 拒绝' >&2
  case "${action}" in direct) choice=1 ;; reject) choice=3 ;; *) choice=2 ;; esac
  choice=$(prompt_choice '规则动作 [1-3]: ' 1 3 "${choice}") || return 1
  case "${choice}" in 1) action=direct ;; 2) action=warp ;; 3) action=reject ;; esac
  jq -cn --arg id "${id}" --arg kind "${kind}" --arg value "${value}" --arg action "${action}" --argjson enabled "${enabled}" \
    '{id:$id,kind:$kind,value:$value,action:$action,enabled:$enabled}'
}

routing_source_record_prompt() {
  local current=${1:-'{}'} tag type format location interval action choice enabled
  tag=$(jq -r '.tag // ""' <<< "${current}") || return 1
  type=$(jq -r '.type // "remote"' <<< "${current}") || return 1
  format=$(jq -r '.format // "binary"' <<< "${current}") || return 1
  location=$(jq -r '.url // .path // ""' <<< "${current}") || return 1
  interval=$(jq -r '.update_interval // "1d"' <<< "${current}") || return 1
  action=$(jq -r '.action // "warp"' <<< "${current}") || return 1
  enabled=$(jq -r 'if has("enabled") then .enabled else true end' <<< "${current}") || return 1
  read -rp '规则源标签（小写字母/数字/-/_，修改时留空保留）: ' choice || return 1
  tag=${choice:-${tag}}
  choice=$(prompt_choice '来源: 1 HTTPS 远程 / 2 本地文件: ' 1 2 "$([[ "${type}" == local ]] && printf 2 || printf 1)") || return 1
  case "${choice}" in 1) type=remote ;; 2) type=local ;; esac
  choice=$(prompt_choice '格式: 1 binary (.srs) / 2 source (.json): ' 1 2 "$([[ "${format}" == source ]] && printf 2 || printf 1)") || return 1
  case "${choice}" in 1) format=binary ;; 2) format=source ;; esac
  read -rp 'HTTPS URL 或本地绝对路径（修改时留空保留）: ' choice || return 1
  location=${choice:-${location}}
  read -rp '更新周期（如 1d，留空保留或使用 1d）: ' choice || return 1
  interval=${choice:-${interval}}
  case "${action}" in direct) choice=1 ;; reject) choice=3 ;; *) choice=2 ;; esac
  choice=$(prompt_choice '动作: 1 原生 / 2 WARP / 3 拒绝: ' 1 3 "${choice}") || return 1
  case "${choice}" in 1) action=direct ;; 2) action=warp ;; 3) action=reject ;; esac
  jq -cn --arg tag "${tag}" --arg type "${type}" --arg format "${format}" --arg location "${location}" \
    --arg interval "${interval}" --arg action "${action}" --argjson enabled "${enabled}" \
    '{tag:$tag,type:$type,format:$format,update_interval:$interval,action:$action,enabled:$enabled} +
      (if $type=="local" then {path:$location} else {url:$location} end)'
}

routing_collection_menu() {
  local draft=$1 collection=$2 choice index current record
  while true; do
    render_left_aligned_page_header "$([[ "${collection}" == rules ]] && printf '自定义域名与 IP 规则' || printf '本地 / 远程规则源')" '按列表顺序处理，自定义规则在预设之前生效'
    jq -r --arg collection "${collection}" '.policy.server[$collection]|to_entries[]|
      "\(.key+1). \(.value.id // .value.tag) [\(.value.kind // .value.type)] → \(.value.action) / enabled=\(.value.enabled)"' "${draft}"
    echo '1. 添加  2. 编辑  3. 启停  4. 删除  0. 返回'
    choice=$(prompt_choice '请选择 [0-4]: ' 0 4 '') || return 0
    [[ "${choice}" != 0 ]] || return 0
    index=''
    current='{}'
    if [[ "${choice}" != 1 ]]; then
      index=$(routing_collection_index "${draft}" "${collection}") || continue
      current=$(jq -c --arg collection "${collection}" --argjson index "${index}" '.policy.server[$collection][$index]' "${draft}") || return 1
    fi
    case "${choice}" in
      1|2)
        if [[ "${collection}" == rules ]]; then
          record=$(routing_rule_record_prompt "${current}") || continue
        else
          record=$(routing_source_record_prompt "${current}") || continue
        fi
        if [[ "${choice}" == 1 ]]; then
          routing_draft_edit "${draft}" '.policy.server[$collection] += [$record]' --arg collection "${collection}" --argjson record "${record}" || continue
        else
          routing_draft_edit "${draft}" '.policy.server[$collection][$index]=$record' --arg collection "${collection}" --argjson index "${index}" --argjson record "${record}" || continue
        fi
        ;;
      3) routing_draft_edit "${draft}" '.policy.server[$collection][$index].enabled |= not' --arg collection "${collection}" --argjson index "${index}" || continue ;;
      4) routing_draft_edit "${draft}" 'del(.policy.server[$collection][$index])' --arg collection "${collection}" --argjson index "${index}" || continue ;;
    esac
  done
}

routing_node_policy_menu() {
  local draft=$1 nodes count index node protocol id policy revision choice
  nodes=$(routing_nodes_json) || return 1
  count=$(jq 'length' <<< "${nodes}") || return 1
  [[ "${count}" -gt 0 ]] || { routing_notice WARN '当前没有节点。'; return 0; }
  jq -r 'to_entries[]|"\(.key+1). \(.value.name) [\(.value.protocol)/\(.value.id)] \(.value.policy)"+
    (if .value.editable then "" else "（legacy 只读）" end)' <<< "${nodes}"
  index=$(prompt_choice '选择节点（0 返回）: ' 0 "${count}" '') || return 0
  [[ "${index}" != 0 ]] || return 0
  node=$(jq -c --argjson index "$((index-1))" '.[$index]' <<< "${nodes}") || return 1
  jq -e '.editable' <<< "${node}" >/dev/null || { routing_notice WARN '此 legacy 表示不支持无损独立出口编辑，请先通过实例管理处理。'; return 0; }
  protocol=$(jq -r '.protocol' <<< "${node}"); id=$(jq -r '.id' <<< "${node}"); revision=$(jq -r '.revision' <<< "${node}")
  policy=$(jq -r --arg p "${protocol}" --arg id "${id}" --argjson node "${node}" \
    '([.node_overrides[]|select(.protocol==$p and .id==$id)][0].policy // $node.policy)' "${draft}") || return 1
  case "${policy}" in direct) choice=2 ;; warp) choice=3 ;; *) choice=1 ;; esac
  choice=$(prompt_choice '出口: 1 跟随全局 / 2 原生 / 3 WARP: ' 1 3 "${choice}") || return 0
  case "${choice}" in 2) policy=direct ;; 3) policy=warp ;; *) policy=default ;; esac
  routing_draft_edit "${draft}" '.node_overrides |= map(select(.protocol!=$p or .id!=$id)) |
    if $policy==$old then . else .node_overrides += [{protocol:$p,id:$id,policy:$policy,revision:$revision}] end' \
    --arg p "${protocol}" --arg id "${id}" --arg policy "${policy}" --arg old "$(jq -r '.policy' <<< "${node}")" --argjson revision "${revision}"
}

routing_legacy_assets_menu() {
  local draft=$1 field=$2 choice count index
  while true; do
    echo '既有 WARP 资产按原文件保留；新增条目请使用自定义规则或规则源管理。'
    jq -r --arg field "${field}" '.[$field]|split("\n")|to_entries[]|
      select(.value!="" and (.value|startswith("#")|not))|
      "行 \(.key+1): "+(if $field=="legacy_sources" then (.value|split("|")[0])+"（远程源）" else .value end)' "${draft}"
    echo '1. 删除指定行  0. 返回'
    choice=$(prompt_choice '请选择 [0-1]: ' 0 1 '') || return 0
    [[ "${choice}" != 0 ]] || return 0
    count=$(jq --arg field "${field}" '.[$field]|split("\n")|length' "${draft}") || return 1
    index=$(prompt_choice '原文件行号（0 取消）: ' 0 "${count}" '') || return 0
    [[ "${index}" != 0 ]] || continue
    routing_draft_edit "${draft}" '.[$field] |= (split("\n")|del(.[$index])|join("\n"))' \
      --arg field "${field}" --argjson index "$((index-1))" || continue
  done
}

routing_sources_menu() {
  local draft=$1 choice
  while true; do
    render_left_aligned_page_header '规则源管理' '来源、动作、更新周期及启停统一维护'
    echo '1. 本地 / 远程规则源增删改与启停'
    echo '2. 管理既有 WARP 域名列表'
    echo '3. 管理既有 WARP 远程源列表'
    echo '4. 查看资产路径与现有本地 WARP 文件'
    echo '0. 返回'
    choice=$(prompt_choice '请选择 [0-4]: ' 0 4 '') || return 0
    case "${choice}" in
      0) return ;;
      1) routing_collection_menu "${draft}" rule_sets || return 1 ;;
      2) routing_legacy_assets_menu "${draft}" legacy_domains || return 1 ;;
      3) routing_legacy_assets_menu "${draft}" legacy_sources || return 1 ;;
      4)
        printf '策略: %s\n既有域名: %s\n既有远程源: %s\n本地目录: %s\n' \
          "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}" "${SB_WARP_LOCAL_RULESET_DIR}"
        if [[ -d "${SB_WARP_LOCAL_RULESET_DIR}" && ! -L "${SB_WARP_LOCAL_RULESET_DIR}" ]]; then
          find "${SB_WARP_LOCAL_RULESET_DIR}" -maxdepth 1 -type f -print
        fi
        ;;
    esac
  done
}

routing_management_menu() (
  local workspace draft original choice
  umask 077
  if [[ -e "${SB_ROUTING_TRANSACTION_DIR}" || -L "${SB_ROUTING_TRANSACTION_DIR}" ]]; then
    echo '检测到未完成的规则事务；先恢复后才能管理。'
    [[ "$(prompt_yes_no '恢复规则事务 [y/n]（默认 n）: ' n)" == y ]] || return 0
    routing_policy_recover || return 1
  fi
  command -v jq >/dev/null 2>&1 || { routing_notice WARN '规则管理需要 jq；请先安装协议以准备依赖。'; return 0; }
  workspace=$(mktemp -d /tmp/sbv-routing-menu.XXXXXX) || return 1
  trap 'rm -rf -- "${workspace}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  draft="${workspace}/draft.json"; original="${workspace}/original.json"
  routing_draft_create "${draft}" && cp "${draft}" "${original}" || return 1
  while true; do
    routing_policy_overview "${draft}" || return 1
    if cmp -s "${draft}" "${original}"; then echo '草稿状态: 无修改'; else echo '草稿状态: 有待应用修改'; fi
    render_menu_item 1 'Block CN 开关（中国大陆域名与 IP）'
    render_menu_item 2 'WARP 开关与节点出口设置'
    render_menu_item 3 'AI / 流媒体设置'
    render_menu_item 4 '流媒体与出口检测'
    render_menu_item 5 '预览、应用与恢复'
    echo '0. 返回主菜单'
    choice=$(prompt_choice '请选择 [0-5]: ' 0 5 '') || return 0
    case "${choice}" in
      0)
        if ! cmp -s "${draft}" "${original}"; then
          [[ "$(prompt_yes_no '放弃未应用的草稿 [y/n]（默认 n）: ' n)" == y ]] || continue
        fi
        return 0
        ;;
      1) routing_draft_edit "${draft}" '.policy.server.block_cn |= not' || continue ;;
      2) routing_default_outbound_menu "${draft}" || return 1 ;;
      3) routing_presets_menu "${draft}" || return 1 ;;
      4) media_check_menu || routing_notice WARN '检测未完成，草稿和服务策略未修改。' ;;
      5)
        routing_policy_preview "${draft}" || return 1
        echo '1. 应用草稿  2. 恢复上次应用前的配置  0. 返回'
        choice=$(prompt_choice '请选择 [0-2]: ' 0 2 '') || return 0
        case "${choice}" in
          1)
            if cmp -s "${draft}" "${original}" && ! routing_policy_needs_adoption; then routing_notice INFO '没有待应用的修改。'; continue; fi
            [[ "$(prompt_yes_no '应用全部草稿并检查服务 [y/n]（默认 n）: ' n)" == y ]] || continue
            routing_policy_apply "${draft}" || continue
            ;;
          2)
            [[ "$(prompt_yes_no '放弃草稿并恢复上次配置 [y/n]（默认 n）: ' n)" == y ]] || continue
            routing_policy_restore_previous || continue
            ;;
          *) continue ;;
        esac
        routing_draft_create "${draft}" && cp "${draft}" "${original}" || return 1
        ;;
    esac
  done
)
