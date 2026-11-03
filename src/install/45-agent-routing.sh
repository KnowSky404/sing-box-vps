# Structured routing is an adapter over the menu's existing draft/transaction API.
agent_routing_input_snapshot() {
  local input=$1 snapshot=$2 input_fd metadata owner mode size
  [[ -f "${input}" && ! -L "${input}" ]] || return 1
  exec {input_fd}< "${input}" || return 1
  if [[ ! -f "/proc/self/fd/${input_fd}" ]] ||
     ! metadata=$(stat -Lc '%u:%a:%s' -- "/proc/self/fd/${input_fd}"); then
    exec {input_fd}<&-
    return 1
  fi
  IFS=: read -r owner mode size <<< "${metadata}"
  if [[ "${owner}" != "${EUID}" || ! "${mode}" =~ ^[0-7]{3,4}$ ||
        ! "${size}" =~ ^[0-9]+$ ]] ||
     (( (8#${mode} & 077) != 0 || size < 1 || size > 2359296 )); then
    exec {input_fd}<&-
    return 1
  fi
  # Bound the read even if another root process appends after fstat. Consume the
  # opened descriptor rather than reopening a possibly replaced input path.
  if ! head -c 2359297 <&"${input_fd}" > "${snapshot}"; then
    exec {input_fd}<&-
    return 1
  fi
  exec {input_fd}<&-
  [[ "$(wc -c < "${snapshot}")" -le 2359296 ]] &&
    jq -s -e 'length==1 and (.[0]|type=="object")' "${snapshot}" >/dev/null &&
    routing_draft_validate "${snapshot}"
}

agent_routing_cli() (
  local operation=${1:-} json=n confirmed=n input='' expected=''
  local workspace draft fingerprint before after='' status=0 recovery=false
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) [[ "${json}" == n ]] || break; json=y; shift ;;
      --yes) [[ "${confirmed}" == n ]] || break; confirmed=y; shift ;;
      --file) [[ $# -ge 2 && -z "${input}" ]] || break; input=$2; shift 2 ;;
      --expected-fingerprint) [[ $# -ge 2 && -z "${expected}" ]] || break; expected=$2; shift 2 ;;
      *) break ;;
    esac
  done
  if [[ $# -ne 0 || "${json}" != y ]]; then
    agent_json_error invalid_arguments '用法: routing view|export|nodes|validate|apply|restore|recover --json [--yes] [--file 私有草稿] [--expected-fingerprint HASH]'
    return 1
  fi
  case "${operation}" in
    view|export|nodes)
      [[ "${confirmed}" == n && -z "${input}${expected}" ]] || {
        agent_json_error invalid_arguments 'routing 读取操作仅接收 --json。'; return 1;
      }
      ;;
    validate|apply)
      [[ -n "${input}" && -z "${expected}" ]] || {
        agent_json_error invalid_arguments 'routing validate/apply 需要 --file，CAS 使用草稿内 fingerprint。'; return 1;
      }
      [[ "${operation}" != validate || "${confirmed}" == n ]] || {
        agent_json_error invalid_arguments 'routing validate 不接收 --yes。'; return 1;
      }
      ;;
    restore)
      [[ -z "${input}" && "${expected}" =~ ^[a-f0-9]{64}$ ]] || {
        agent_json_error invalid_arguments 'routing restore 需要 --expected-fingerprint HASH，且不接收 --file。'; return 1;
      }
      ;;
    recover)
      [[ -z "${input}${expected}" ]] || {
        agent_json_error invalid_arguments 'routing recover 使用持久 journal，不接收 --file 或 fingerprint。'; return 1;
      }
      ;;
    *) agent_json_error unknown_routing_command '未知 routing 操作。'; return 1 ;;
  esac
  case "${operation}" in
    apply|restore|recover)
      [[ "${confirmed}" == y ]] || {
        agent_json_error confirmation_required 'routing 写操作需要显式 --yes。'; return 1;
      }
      ;;
  esac
  if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" || -L "${SB_PROJECT_DIR}.instance-write.lock" ||
        -e "${SB_COMPONENT_TRANSACTION_DIR}" || -L "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
    agent_json_error transaction_pending '请先恢复实例或组件事务；规则未修改。'
    return 1
  fi
  if [[ "${operation}" != recover && ( -e "${SB_ROUTING_TRANSACTION_DIR}" || -L "${SB_ROUTING_TRANSACTION_DIR}" ) ]]; then
    agent_json_error routing_transaction_pending '请先执行 sbv routing recover --json --yes。'
    return 1
  fi
  umask 077
  workspace=$(mktemp -d /tmp/sbv-agent-routing.XXXXXX) || {
    agent_json_error staging_failed '无法建立私有规则工作目录。'; return 1;
  }
  trap 'rm -rf -- "${workspace}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  draft="${workspace}/draft.json"
  case "${operation}" in
    validate|apply)
      if ! agent_routing_input_snapshot "${input}" "${draft}"; then
        agent_json_error invalid_draft '草稿必须是当前用户拥有的私有普通 JSON 文件，且通过现有规则校验；未修改。'
        return 1
      fi
      fingerprint=$(jq -r '.fingerprint' "${draft}") || return 1
      if [[ "${operation}" == validate ]]; then
        jq -n --arg fingerprint "${fingerprint}" '{ok:true,action:"routing_validate",valid:true,
          fingerprint:$fingerprint,config_check_performed:false,mutation:false}'
        return $?
      fi
      ;;
    view|export)
      if ! routing_draft_create "${draft}"; then
        agent_json_error routing_read_failed '无法取得一致的规则快照；未返回部分草稿。'
        return 1
      fi
      fingerprint=$(jq -r '.fingerprint' "${draft}") || return 1
      if [[ "${operation}" == export ]]; then
        jq '{ok:true,action:"routing_export",sensitive:true,fingerprint:.fingerprint,draft:.}' "${draft}"
        return $?
      fi
      if ! routing_nodes_json > "${workspace}/nodes.json" || [[ "${fingerprint}" != "$(routing_state_fingerprint)" ]]; then
        agent_json_error routing_read_failed '规则清单在读取期间变化；未返回部分状态。'
        return 1
      fi
      # Explicit allowlist: URLs, source paths, legacy texts and credentials
      # must never leak through this non-sensitive discovery operation.
      jq --slurpfile nodes "${workspace}/nodes.json" '{ok:true,action:"routing_view",fingerprint:.fingerprint,
        policy:{schema_version:.policy.schema_version,server:{
          block_cn:.policy.server.block_cn,warp_ai:.policy.server.warp_ai,
          warp_streaming:.policy.server.warp_streaming,
          rules:[.policy.server.rules[]|{id,kind,action,enabled}],
          rule_sets:[.policy.server.rule_sets[]|{tag,type,format,action,enabled,update_interval}]}},
        warp:{enabled:.warp.enabled,mode:.warp.mode},
        nodes:[$nodes[0][]|{protocol,id,name,tag,policy,revision,editable}],
        legacy_assets:{domains_present:(.legacy_domains!=""),sources_present:(.legacy_sources!="")}}' "${draft}"
      return $?
      ;;
    nodes)
      if ! fingerprint=$(routing_state_fingerprint) || ! routing_nodes_json > "${workspace}/nodes.json" ||
         [[ "${fingerprint}" != "$(routing_state_fingerprint)" ]]; then
        agent_json_error routing_read_failed '无法取得一致的节点出口清单；未返回部分状态。'
        return 1
      fi
      jq -n --arg fingerprint "${fingerprint}" --slurpfile nodes "${workspace}/nodes.json" \
        '{ok:true,action:"routing_nodes",fingerprint:$fingerprint,
          nodes:[$nodes[0][]|{protocol,id,name,tag,policy,revision,editable}]}'
      return $?
      ;;
  esac

  if ! before=$(routing_state_fingerprint); then
    agent_json_error routing_read_failed '无法取得当前规则 fingerprint；未开始写入。'
    return 1
  fi
  case "${operation}" in
    apply)
      [[ "${fingerprint}" == "${before}" ]] || {
        agent_json_error revision_conflict '草稿 fingerprint 已过期；未修改。'; return 1;
      }
      routing_policy_apply "${draft}" >&2 || status=$?
      ;;
    restore)
      [[ "${expected}" == "${before}" ]] || {
        agent_json_error revision_conflict '当前 fingerprint 与预期不符；未修改。'; return 1;
      }
      routing_policy_restore_previous >&2 || status=$?
      ;;
    recover) routing_policy_recover >&2 || status=$? ;;
  esac
  [[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && ! -L "${SB_ROUTING_TRANSACTION_DIR}" ]] || recovery=true
  after=$(routing_state_fingerprint) || status=1
  if [[ "${recovery}" == true ]]; then status=1; fi
  # A failed call does not by itself prove rollback. Preserve fingerprints and
  # journal presence so the caller can distinguish unchanged state from damage.
  jq -n --arg action "routing_${operation}" --arg before "${before}" --arg after "${after}" \
    --argjson status "${status}" --argjson recovery "${recovery}" \
    '{ok:($status==0),action:$action,fingerprint_before:$before,
      fingerprint_after:(if $after=="" then null else $after end),
      changed:(if $after=="" then null else $before!=$after end),
      recovery_required:$recovery,
      transaction_status:(if $recovery then "recovery_required" elif $status==0 then "completed" else "failed" end)}
    + (if $status==0 then {} else {error:"routing_operation_failed"} end)'
  [[ "${status}" == 0 ]]
)
