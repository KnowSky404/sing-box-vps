# Routing drafts contain inert JSON and stay outside the installed project.
routing_error() {
  printf '[ERROR] %s\n' "$*" >&2
  return 1
}

routing_asset_text_json() {
  local file=$1
  if [[ -e "${file}" || -L "${file}" ]]; then
    [[ -f "${file}" && ! -L "${file}" && "$(wc -c < "${file}")" -le 1048576 ]] || return 1
    jq -Rs '.' "${file}"
  else
    printf '""\n'
  fi
}

routing_managed_parent_is_safe() {
  local target=$1 parent
  [[ "${target}" == "${SB_PROJECT_DIR}/"* && "${target}" != *'/../'* && "${target}" != *'/./'* ]] || return 1
  parent=$(dirname -- "${target}") || return 1
  while [[ "${parent}" == "${SB_PROJECT_DIR}" || "${parent}" == "${SB_PROJECT_DIR}/"* ]]; do
    [[ -d "${parent}" && ! -L "${parent}" ]] || return 1
    [[ "${parent}" != "${SB_PROJECT_DIR}" ]] || return 0
    parent=$(dirname -- "${parent}") || return 1
  done
  return 1
}

routing_path_is_managed() {
  local path=$1 relative protocol id
  relative=${path#"${SB_PROJECT_DIR}/"}
  case "${relative}" in
    config.json|config.json.bak|managed-config.generated.json|managed-config.generated.json.bak|routing-policy.json|routing-policy.json.bak|warp.key|warp.key.bak|warp-routing.env|warp-routing.env.bak|warp-domains.txt|warp-domains.txt.bak|warp-remote-rule-sets.txt|warp-remote-rule-sets.txt.bak|reality.key|reality.key.bak|stack-mode.env|stack-mode.env.bak|protocols/index.env|protocols/index.env.bak) return 0 ;;
  esac
  for protocol in vless-reality vless-plain mixed socks http shadowsocks trojan vmess anytls hy2 snell tuic hysteria naive shadowtls; do
    case "${relative}" in
      "protocols/${protocol}.env"|"protocols/${protocol}.env.bak"|"protocols/instances/${protocol}.json"|"protocols/instances/${protocol}.json.bak") return 0 ;;
    esac
  done
  case "${relative}" in
    protocols/vless-reality.d/*.env|protocols/vless-reality.d/*.env.bak)
      id=${relative#protocols/vless-reality.d/}; id=${id%.bak}; id=${id%.env}
      [[ "${id}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] && return 0
      ;;
    protocols|protocols/instances|protocols/vless-reality.d|rule-set|rule-set/warp) return 0 ;;
  esac
  return 1
}

routing_state_fingerprint() (
  local scope=${1:-all} workspace file count=0 kind mode
  [[ "${scope}" == all || "${scope}" == external || "${scope}" == without_media_cache ]] || return 1
  [[ ! -L "${SB_PROJECT_DIR}" ]] || return 1
  umask 077
  workspace=$(mktemp -d /tmp/sbv-routing-fingerprint.XXXXXX) || return 1
  trap 'rm -rf -- "${workspace}"' EXIT
  : > "${workspace}/paths"
  if [[ -d "${SB_PROJECT_DIR}" ]]; then
    find "${SB_PROJECT_DIR}" -mindepth 1 -print0 > "${workspace}/paths" || return 1
  elif [[ -e "${SB_PROJECT_DIR}" ]]; then
    return 1
  fi
  LC_ALL=C sort -z "${workspace}/paths" > "${workspace}/sorted" || return 1
  : > "${workspace}/hashes"
  if [[ -d "${SB_PROJECT_DIR}" ]]; then
    printf 'root:directory:%s\n' "$(stat -c '%a:%u:%g' -- "${SB_PROJECT_DIR}")" >> "${workspace}/hashes" || return 1
  else
    printf 'root:absent\n' >> "${workspace}/hashes" || return 1
  fi
  while IFS= read -r -d '' file; do
    # Runtime log messages are preserved separately during snapshot restoration.
    [[ "${file}" != "${SBV_LOG_FILE}" ]] || continue
    if [[ "${scope}" == external ]] && routing_path_is_managed "${file}"; then continue; fi
    # This comparison-only scope supports a diagnostic within an open draft.
    # Ordinary transaction and external-state hashes still include the cache.
    # Unknown children, links and unexpected object types remain observable.
    if [[ "${scope}" == without_media_cache ]]; then
      if [[ "${file}" == "${SB_MEDIA_CHECK_DIR}" && -d "${file}" && ! -L "${file}" ]]; then
        continue
      fi
      if [[ ( "${file}" == "${SB_MEDIA_CHECK_SCRIPT}" || "${file}" == "${SB_MEDIA_CHECK_SCRIPT}.bak" ) &&
            -f "${file}" && ! -L "${file}" ]]; then
        continue
      fi
    fi
    count=$((count + 1)); [[ "${count}" -le 4096 ]] || return 1
    printf '%s\0' "${file#"${SB_PROJECT_DIR}/"}" >> "${workspace}/hashes" || return 1
    mode=$(stat -c '%a:%u:%g' -- "${file}") || return 1
    if [[ -L "${file}" ]]; then
      printf 'link:%s:' "${mode}" >> "${workspace}/hashes" || return 1
      readlink -- "${file}" >> "${workspace}/hashes" || return 1
    elif [[ -f "${file}" ]]; then
      printf 'file:%s:' "${mode}" >> "${workspace}/hashes" || return 1
      sha256sum -- "${file}" >> "${workspace}/hashes" || return 1
    elif [[ -d "${file}" ]]; then
      printf 'directory:%s\n' "${mode}" >> "${workspace}/hashes" || return 1
    else
      return 1
    fi
  done < "${workspace}/sorted"
  sha256sum "${workspace}/hashes" | cut -d' ' -f1
)

routing_restore_project_snapshot() (
  local snapshot=$1 saved_log directory="${SB_ROUTING_TRANSACTION_DIR}" had_log=n
  saved_log=$(mktemp "${directory}/.current-log.XXXXXX") || return 1
  trap 'rm -f -- "${saved_log}"' EXIT
  if [[ -e "${SBV_LOG_FILE}" || -L "${SBV_LOG_FILE}" ]]; then
    [[ -f "${SBV_LOG_FILE}" && ! -L "${SBV_LOG_FILE}" ]] || return 1
    cp -p -- "${SBV_LOG_FILE}" "${saved_log}" || return 1
    had_log=y
  fi
  restore_managed_state_snapshot "${snapshot}" || return 1
  if [[ -f "${snapshot}/project.existed" ]]; then
    chmod --reference="${snapshot}/project" -- "${SB_PROJECT_DIR}" || return 1
    chown --reference="${snapshot}/project" -- "${SB_PROJECT_DIR}" || return 1
  fi
  if [[ "${had_log}" == y ]]; then
    [[ ! -L "${SBV_LOG_FILE}" ]] || return 1
    cp -p -- "${saved_log}" "${SBV_LOG_FILE}" || return 1
  else
    rm -f -- "${SBV_LOG_FILE}" || return 1
  fi
)

routing_nodes_json() (
  local workspace protocols protocol store snapshot ids id
  umask 077
  workspace=$(mktemp -d /tmp/sbv-routing-nodes.XXXXXX) || return 1
  trap 'rm -rf -- "${workspace}"' EXIT
  : > "${workspace}/nodes"
  if [[ ! -e "${SINGBOX_CONFIG_FILE}" && ! -e "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    printf '[]\n'
    return 0
  fi
  protocols=$(list_installed_protocols_read_only) || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    if [[ "${protocol}" == vless-reality ]]; then
      load_vless_reality_protocol_state || return 1
      if [[ "${CONFIG_SCHEMA_VERSION:-1}" != 2 ]]; then
        jq -cn '{protocol:"vless-reality",id:"main",name:"VLESS + REALITY (legacy)",
          tag:"vless-in",policy:"default",revision:0,editable:false}' >> "${workspace}/nodes" || return 1
        continue
      fi
      ids=$(list_vless_reality_instance_ids) || return 1
      while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        load_vless_reality_instance_state "${id}" || return 1
        jq -cn --arg protocol "${protocol}" --arg id "${id}" \
          --arg name "${SB_NODE_NAME:-${id}}" --arg tag "$(vless_reality_inbound_tag_for_instance "${id}")" \
          --arg policy "${SB_OUTBOUND_POLICY:-default}" \
          '{protocol:$protocol,id:$id,name:$name,tag:$tag,policy:$policy,revision:0,editable:true}' >> "${workspace}/nodes" || return 1
      done <<< "${ids}"
    elif plain_proxy_structured_state_active "${protocol}"; then
      store=$(plain_proxy_structured_store_file "${protocol}") || return 1
      snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${store}") || return 1
      jq -c --arg protocol "${protocol}" '.revision as $revision | .instances[] |
        {protocol:$protocol,id:.id,name:.name,tag:.tag,policy:.outbound_policy,revision:$revision,editable:true}' \
        <<< "${snapshot}" >> "${workspace}/nodes" || return 1
    else
      jq -cn --arg protocol "${protocol}" --arg tag "$(protocol_inbound_tag "${protocol}")" \
        '{protocol:$protocol,id:"main",name:$protocol,tag:$tag,policy:"default",revision:0,editable:false}' \
        >> "${workspace}/nodes" || return 1
    fi
  done <<< "${protocols}"
  jq -s '.' "${workspace}/nodes"
)

routing_draft_validate() {
  local file=$1 policy
  [[ -f "${file}" && ! -L "${file}" && "$(wc -c < "${file}")" -le 2359296 ]] || return 1
  jq -e '
    def exact($keys): type=="object" and (keys|sort)==($keys|sort);
    exact(["policy","warp","node_overrides","legacy_domains","legacy_sources","fingerprint"]) and
    (.fingerprint|type=="string" and test("^[a-f0-9]{64}$")) and
    (.legacy_domains|type=="string" and length<=1048576) and
    (.legacy_sources|type=="string" and length<=1048576) and
    (.warp|exact(["enabled","mode","reregister"]) and
      (.enabled|type=="boolean") and (.reregister|type=="boolean") and (.mode|IN("all","selective"))) and
    (.node_overrides|type=="array" and length<=128 and
      (map([.protocol,.id])|unique|length)==length and all(.[];
        exact(["protocol","id","policy","revision"]) and
        (.protocol|type=="string" and test("^[a-z0-9-]+$")) and
        (.id|type=="string" and test("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")) and
        (.policy|IN("default","direct","warp")) and
        (.revision|type=="number" and floor==. and .>=0 and .<=9007199254740990)))
  ' "${file}" >/dev/null || return 1
  policy=$(jq -c '.policy | select(.schema_version == 2)' "${file}") || return 1
  routing_policy_validate_json "${policy}"
}

routing_draft_create() {
  local file=$1 before after policy domains sources enabled=false mode=selective
  [[ ! -L "${file}" ]] || return 1
  before=$(routing_state_fingerprint) || return 1
  policy=$(routing_policy_read_json) || return 1
  policy=$(routing_policy_current_json "${policy}") || return 1
  domains=$(routing_asset_text_json "${SB_WARP_DOMAINS_FILE}") || return 1
  sources=$(routing_asset_text_json "${SB_WARP_REMOTE_RULESETS_FILE}") || return 1
  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then enabled=true; fi
    mode=$(load_warp_route_settings && printf '%s' "${SB_WARP_ROUTE_MODE}") || return 1
  fi
  after=$(routing_state_fingerprint) || return 1
  [[ "${before}" == "${after}" ]] || { routing_error '规则读取期间状态已变化，请重新进入。'; return 1; }
  (umask 077; jq -n --argjson policy "${policy}" --argjson enabled "${enabled}" --arg mode "${mode}" \
    --argjson domains "${domains}" --argjson sources "${sources}" --arg fingerprint "${before}" \
    '{policy:$policy,warp:{enabled:$enabled,mode:$mode,reregister:false},node_overrides:[],
      legacy_domains:$domains,legacy_sources:$sources,fingerprint:$fingerprint}' > "${file}") || return 1
  routing_draft_validate "${file}"
}

routing_publish_file() (
  local source=$1 target=$2 candidate=''
  [[ -f "${source}" && ! -L "${source}" && ! -L "${target}" ]] || return 1
  routing_managed_parent_is_safe "${target}" || return 1
  [[ ! -e "${target}.bak" || -f "${target}.bak" || -L "${target}.bak" ]] || return 1
  if [[ -f "${target}" ]] && cmp -s "${source}" "${target}"; then return 0; fi
  umask 077
  mkdir -p "$(dirname "${target}")" || return 1
  candidate=$(mktemp "$(dirname "${target}")/.routing-write.XXXXXX") || return 1
  trap 'rm -f -- "${candidate}"' EXIT
  cp -- "${source}" "${candidate}" && chmod 600 "${candidate}" || return 1
  if [[ -e "${target}" ]]; then
    [[ -f "${target}" ]] || return 1
    persist_file_backup "${target}" "${target}.bak" || return 1
  fi
  mv -f -- "${candidate}" "${target}"
)

routing_apply_node_overrides() (
  local draft=$1 work_dir=$2 protocols protocol changes revision store candidate ids id file
  protocols=$(jq -r '.node_overrides | map(.protocol) | unique[]' "${draft}") || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    changes=$(jq -c --arg p "${protocol}" '[.node_overrides[]|select(.protocol==$p)]' "${draft}") || return 1
    if [[ "${protocol}" == vless-reality ]]; then
      load_vless_reality_protocol_state || return 1
      ids=$(list_vless_reality_instance_ids) || return 1
      while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        grep -Fxq -- "${id}" <<< "${ids}" || return 1
        load_vless_reality_instance_state "${id}" || return 1
        file=$(vless_reality_instance_state_file "${id}") || return 1
        [[ -f "${file}" && ! -L "${file}" ]] || return 1
        candidate="${work_dir}/reality-policy.env"
        awk '!/^OUTBOUND_POLICY=/' "${file}" > "${candidate}" || return 1
        write_env_assignment OUTBOUND_POLICY "$(jq -r --arg id "${id}" '.[]|select(.id==$id)|.policy' <<< "${changes}")" >> "${candidate}" || return 1
        bash -n "${candidate}" || return 1
        routing_publish_file "${candidate}" "${file}" || return 1
      done < <(jq -r '.[].id' <<< "${changes}")
    else
      structured_instance_store_protocol "${protocol}" >/dev/null || return 1
      plain_proxy_structured_state_active "${protocol}" || return 1
      plain_proxy_structured_state_matches_config "${protocol}" "${SINGBOX_CONFIG_FILE}" || return 1
      store=$(plain_proxy_structured_store_file "${protocol}") || return 1
      revision=$(jq -er '.revision' "${store}") || return 1
      jq -e --argjson revision "${revision}" --slurpfile store "${store}" '
        all(.[]; . as $change | .revision==$revision and any($store[0].instances[]; .id==$change.id))' \
        <<< "${changes}" >/dev/null || return 1
      candidate="${work_dir}/${protocol}.json"
      jq --argjson changes "${changes}" '.revision += 1 | .instances |= map(. as $record |
        ([$changes[]|select(.id==$record.id)][0] // null) as $change |
        if $change==null then . else .outbound_policy=$change.policy end)' "${store}" > "${candidate}" || return 1
      validate_structured_instance_store "${protocol}" "${candidate}" || return 1
      publish_structured_instance_store "${protocol}" "${candidate}" "${revision}" >/dev/null || return 1
    fi
  done <<< "${protocols}"
)

routing_service_active_json() {
  local activity
  if activity=$(systemctl is-active sing-box); then
    [[ "${activity}" == active ]] || return 1
    printf true
  else
    case "${activity}" in inactive|failed) printf false ;; *) return 1 ;; esac
  fi
}

routing_transaction_valid() {
  local directory=$1
  [[ "${directory}" == "${SB_ROUTING_TRANSACTION_DIR}" || "${directory}" == "${SB_ROUTING_PREVIOUS_DIR}" ]] || return 1
  [[ -d "${directory}" && ! -L "${directory}" && "$(stat -c %a "${directory}")" == 700 &&
     -f "${directory}/transaction.json" && ! -L "${directory}/transaction.json" &&
     "$(stat -c %a "${directory}/transaction.json")" == 600 ]] || return 1
  jq -e 'type=="object" and .schema_version==1 and (.before_active|type=="boolean") and
    (.phase|IN("prepare","snapshot","publish","service","committed")) and
    (.service_changed|type=="boolean") and
    (.warp_registration_deferred == null or
      (.warp_registration_deferred | type=="object" and
        (keys|sort)==["credentials_sha256","receipt_sha256"] and
        all(.[]; type=="string" and test("^[a-f0-9]{64}$")))) and
    (.before_fingerprint|type=="string" and test("^[a-f0-9]{64}$")) and
    (.external_fingerprint|type=="string" and test("^[a-f0-9]{64}$")) and
    (.after_fingerprint|type=="string" and (.=="" or test("^[a-f0-9]{64}$")))' \
    "${directory}/transaction.json" >/dev/null
}

routing_transaction_defer_warp_registration() {
  local receipt=$1 directory="${SB_ROUTING_TRANSACTION_DIR}" receipt_hash credentials_hash
  [[ "${SB_ROUTING_DEFER_WARP_RECEIPT:-n}" == y && "${receipt}" == "${SB_WARP_REGISTRATION_PENDING_FILE}" ]] || return 1
  routing_transaction_valid "${directory}" || return 1
  jq -e '.phase=="snapshot" and .service_changed' "${directory}/transaction.json" >/dev/null || return 1
  warp_registration_receipt_matches_credentials "${receipt}" || return 1
  receipt_hash=$(sha256sum < "${receipt}" | cut -d' ' -f1) || return 1
  credentials_hash=$(sha256sum < "${SB_WARP_KEY_FILE}" | cut -d' ' -f1) || return 1
  jq --arg receipt "${receipt_hash}" --arg credentials "${credentials_hash}" \
    '.warp_registration_deferred={receipt_sha256:$receipt,credentials_sha256:$credentials}' \
    "${directory}/transaction.json" > "${directory}/transaction.next" || return 1
  chmod 600 "${directory}/transaction.next" && mv -f -- "${directory}/transaction.next" "${directory}/transaction.json"
}

routing_transaction_backup_legacy_reality_state() {
  local source=$1 directory="${SB_ROUTING_TRANSACTION_DIR}" target
  [[ "${SB_ROUTING_JOURNAL_LEGACY_BACKUP:-n}" == y &&
     "${source}" == "$(protocol_state_file vless-reality)" &&
     -f "${source}" && ! -L "${source}" ]] || return 1
  routing_transaction_valid "${directory}" || return 1
  jq -e '.phase=="snapshot" and .service_changed' "${directory}/transaction.json" >/dev/null || return 1
  managed_state_snapshot_is_valid "${directory}/snapshot" || return 1
  [[ -f "${directory}/snapshot/project.existed" && -d "${directory}/snapshot/project" &&
     ! -L "${directory}/snapshot/project" ]] || return 1
  target="${directory}/legacy-vless-reality.env.bak"
  [[ ! -e "${target}" && ! -L "${target}" ]] || return 1
  persist_file_backup "${source}" "${target}"
}

routing_transaction_finalize_warp_registration() {
  local directory="${SB_ROUTING_TRANSACTION_DIR}" receipt="${SB_WARP_REGISTRATION_PENDING_FILE}" expected
  routing_transaction_valid "${directory}" || return 1
  jq -e '.phase=="committed"' "${directory}/transaction.json" >/dev/null || return 1
  if jq -e '.warp_registration_deferred == null' "${directory}/transaction.json" >/dev/null; then return 0; fi
  [[ -f "${SB_WARP_KEY_FILE}" && ! -L "${SB_WARP_KEY_FILE}" && "$(stat -c %a "${SB_WARP_KEY_FILE}")" == 600 ]] || return 1
  expected=$(jq -r '.warp_registration_deferred.credentials_sha256' "${directory}/transaction.json") || return 1
  [[ "$(sha256sum < "${SB_WARP_KEY_FILE}" | cut -d' ' -f1)" == "${expected}" ]] || return 1
  # Absence is idempotent after cleanup succeeded but the process stopped
  # before moving its committed journal to the previous snapshot directory.
  [[ -e "${receipt}" || -L "${receipt}" ]] || return 0
  expected=$(jq -r '.warp_registration_deferred.receipt_sha256' "${directory}/transaction.json") || return 1
  [[ -f "${receipt}" && ! -L "${receipt}" &&
     "$(sha256sum < "${receipt}" | cut -d' ' -f1)" == "${expected}" ]] || return 1
  warp_registration_receipt_matches_credentials "${receipt}" || return 1
  rm -f -- "${receipt}"
}

routing_transaction_checkpoint() {
  local phase=$1 fingerprint=${2:-} directory="${SB_ROUTING_TRANSACTION_DIR}"
  routing_transaction_valid "${directory}" || return 1
  jq --arg phase "${phase}" --arg fingerprint "${fingerprint}" \
    '.phase=$phase | if $fingerprint!="" then .after_fingerprint=$fingerprint else . end' \
    "${directory}/transaction.json" > "${directory}/transaction.next" || return 1
  chmod 600 "${directory}/transaction.next" && mv -f -- "${directory}/transaction.next" "${directory}/transaction.json"
}

routing_transaction_restore() {
  local directory="${SB_ROUTING_TRANSACTION_DIR}" active expected actual
  routing_transaction_valid "${directory}" || return 1
  if [[ ! -f "${directory}/snapshot/snapshot.meta" ]]; then
    [[ "$(jq -r '.phase' "${directory}/transaction.json")" == prepare ]] || return 1
    rm -rf -- "${directory}"
    return $?
  fi
  active=$(jq -r '.before_active' "${directory}/transaction.json") || return 1
  expected=$(jq -r '.before_fingerprint' "${directory}/transaction.json") || return 1
  [[ "$(routing_state_fingerprint external)" == "$(jq -r ' .external_fingerprint' "${directory}/transaction.json")" ]] || {
    routing_error '事务期间手工文件或 ACME 状态已变化，未覆盖恢复；请保留日志人工核对。'; return 1;
  }
  routing_restore_project_snapshot "${directory}/snapshot" || return 1
  actual=$(routing_state_fingerprint) || return 1
  [[ "${actual}" == "${expected}" ]] || return 1
  if [[ "$(jq -r '.service_changed' "${directory}/transaction.json")" == false ]]; then
    [[ "$(routing_service_active_json)" == "${active}" ]] || return 1
  elif [[ "${active}" == true ]]; then
    run_with_progress '恢复原 sing-box 服务状态' systemctl restart sing-box >&2 || return 1
    systemctl is-active --quiet sing-box || return 1
  else
    systemctl stop sing-box || return 1
    singbox_service_confirmed_stopped || return 1
  fi
  rm -rf -- "${directory}"
}

routing_transaction_keep_previous() {
  local directory="${SB_ROUTING_TRANSACTION_DIR}"
  routing_transaction_valid "${directory}" || return 1
  [[ "$(jq -r '.phase' "${directory}/transaction.json")" == committed ]] || return 1
  routing_transaction_finalize_warp_registration || return 1
  if [[ -e "${SB_ROUTING_PREVIOUS_DIR}" || -L "${SB_ROUTING_PREVIOUS_DIR}" ]]; then
    routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}" || return 1
    rm -rf -- "${SB_ROUTING_PREVIOUS_DIR}" || return 1
  fi
  mv -- "${directory}" "${SB_ROUTING_PREVIOUS_DIR}"
}

routing_policy_recover() {
  local fingerprint expected active
  acquire_managed_write_lock exclusive allow-rules-recovery || return 1
  routing_transaction_valid "${SB_ROUTING_TRANSACTION_DIR}" || { routing_error '规则恢复日志不可信，已保留现场。'; return 1; }
  if [[ "$(jq -r '.phase' "${SB_ROUTING_TRANSACTION_DIR}/transaction.json")" == committed ]]; then
    fingerprint=$(routing_state_fingerprint) || return 1
    expected=$(jq -r '.after_fingerprint' "${SB_ROUTING_TRANSACTION_DIR}/transaction.json") || return 1
    [[ "${fingerprint}" == "${expected}" ]] || { routing_error '已提交规则状态发生变化，无法自动完成清理。'; return 1; }
    active=$(routing_service_active_json) || return 1
    [[ "${active}" == "$(jq -r '.before_active' "${SB_ROUTING_TRANSACTION_DIR}/transaction.json")" ]] || return 1
    routing_transaction_keep_previous || return 1
    log_success '规则已提交；恢复材料整理完成。'
  elif routing_transaction_restore; then
    log_success '未完成规则事务已回滚，原配置及服务状态已恢复。'
  else
    routing_error "规则回滚未完成；请保留 ${SB_ROUTING_TRANSACTION_DIR}。"
    return 1
  fi
}

routing_transaction_run() (
  local operation=$1 draft=${2:-} directory="${SB_ROUTING_TRANSACTION_DIR}"
  local expected fingerprint external_fingerprint before_active policy previous_policy server_changed=true
  local committed=n finished=n candidate='' warp_activation_requested=false current_nodes='[]'
  local SB_ROUTING_DEFER_WARP_RECEIPT=n
  local SB_ROUTING_JOURNAL_LEGACY_BACKUP=n
  local SB_ROUTING_BASELINE_WARP_FALLBACK=n
  umask 077
  acquire_managed_write_lock || return 1
  [[ ! -e "${directory}" && ! -L "${directory}" && ! -e "${SB_PROJECT_DIR}.instance-write.lock" &&
     ! -e "${SB_COMPONENT_TRANSACTION_DIR}" && -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" &&
     -f "${SINGBOX_SERVICE_FILE}" && -x "${SINGBOX_BIN_PATH}" && ! -L "${SBV_LOG_FILE}" ]] || {
    routing_error '请先安装有效协议或恢复未完成事务；规则未修改。'; return 1;
  }
  [[ ! -L "${SB_PROTOCOL_STATE_DIR}" && ! -L "${SB_PROTOCOL_STATE_DIR}/instances" &&
     ! -L "${SB_PROTOCOL_STATE_DIR}/vless-reality.d" && ! -L "${SB_PROJECT_DIR}/rule-set" &&
     ! -L "${SB_WARP_LOCAL_RULESET_DIR}" ]] || { routing_error '受管状态目录含符号链接，未执行规则写入。'; return 1; }
  fingerprint=$(routing_state_fingerprint) || return 1
  external_fingerprint=$(routing_state_fingerprint external) || return 1
  before_active=$(routing_service_active_json) || { routing_error '无法确认服务原状态，规则未修改。'; return 1; }
  case "${operation}" in
    apply)
      routing_draft_validate "${draft}" || { routing_error '规则候选无效，未修改。'; return 1; }
      expected=$(jq -r '.fingerprint' "${draft}") || return 1
      [[ "${expected}" == "${fingerprint}" ]] || { routing_error '配置已在读取后变化，请重试本次设置。'; return 1; }
      previous_policy=$(routing_policy_read_json) || return 1
      policy=$(jq -c '.policy' "${draft}") || return 1
      # A Block CN or preset edit does not authorize WARP account repair.
      # Prepare credentials only for an explicit new WARP dependency/mode or
      # re-registration request. Existing dependencies use read-only material.
      if jq -e 'any(.node_overrides[]; .policy == "warp")' "${draft}" >/dev/null; then
        current_nodes=$(routing_nodes_json) || return 1
      fi
      warp_activation_requested=$(jq -r --argjson old "${previous_policy}" --argjson nodes "${current_nodes}" \
        --argjson enabled "$(config_has_warp_enabled "${SINGBOX_CONFIG_FILE}" && printf true || printf false)" \
        --arg mode "$(load_warp_route_settings && printf '%s' "${SB_WARP_ROUTE_MODE}")" '
        [($old.server.rules + $old.server.rule_sets)[] | select(.enabled and .action == "warp")] as $old_dependencies |
        .warp.reregister or (.warp.enabled and (($enabled | not) or .warp.mode != $mode)) or
        any(.node_overrides[]; . as $change | .policy == "warp" and
          ([$nodes[] | select(.protocol == $change.protocol and .id == $change.id)][0].policy != "warp")) or
        any((.policy.server.rules + .policy.server.rule_sets)[]; . as $dependency |
          .enabled and .action == "warp" and ($old_dependencies | index($dependency)) == null)
      ' "${draft}") || return 1
      if [[ -f "${SB_ROUTING_POLICY_FILE}" ]] &&
         jq -e --argjson old "${previous_policy}" --argjson enabled "$(config_has_warp_enabled "${SINGBOX_CONFIG_FILE}" && printf true || printf false)" \
           --arg mode "$(load_warp_route_settings && printf '%s' "${SB_WARP_ROUTE_MODE}")" \
           --argjson domains "$(routing_asset_text_json "${SB_WARP_DOMAINS_FILE}")" \
           --argjson sources "$(routing_asset_text_json "${SB_WARP_REMOTE_RULESETS_FILE}")" \
           '.policy==$old and
             .warp.enabled==$enabled and .warp.mode==$mode and (.warp.reregister|not) and
             .node_overrides==[] and .legacy_domains==$domains and .legacy_sources==$sources' \
           "${draft}" >/dev/null; then
        server_changed=false
      fi
      ;;
    restore)
      routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}" || return 1
      expected=$(jq -r '.after_fingerprint' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json") || return 1
      [[ "${expected}" == "${fingerprint}" && "${before_active}" == "$(jq -r '.before_active' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json")" ]] || {
        routing_error '上次应用后配置或服务已有其他变更，不能覆盖恢复。'; return 1;
      }
      server_changed=$(jq -r '.service_changed' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json") || return 1
      ;;
    *) return 1 ;;
  esac
  mkdir -m 700 -- "${directory}" || return 1
  if ! jq -n --argjson active "${before_active}" --arg fingerprint "${fingerprint}" --arg external "${external_fingerprint}" --argjson service "${server_changed}" \
    '{schema_version:1,phase:"prepare",before_active:$active,service_changed:$service,warp_registration_deferred:null,before_fingerprint:$fingerprint,external_fingerprint:$external,after_fingerprint:""}' \
    > "${directory}/transaction.json" || ! chmod 600 "${directory}/transaction.json"; then
    rm -rf -- "${directory}" || return 1
    return 1
  fi
  routing_transaction_exit() {
    local result=$?
    trap - EXIT INT TERM HUP
    if [[ "${finished}" != y && "${committed}" != y ]]; then
      if routing_transaction_restore; then
        printf '[ERROR] 规则操作失败或中断；已回滚配置及原服务状态。\n' >&2
      else
        printf '[ERROR] 规则回滚未完成；恢复材料保留在 %s。\n' "${directory}" >&2
      fi
    elif [[ "${finished}" != y ]]; then
      printf '[WARN] 规则已提交，恢复材料整理未完成；请从菜单 12 恢复。\n' >&2
    fi
    [[ "${result}" -ne 0 || "${finished}" == y ]] || result=1
    exit "${result}"
  }
  trap routing_transaction_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  create_managed_state_snapshot "${directory}/snapshot" >/dev/null || return 1
  chmod --reference="${SB_PROJECT_DIR}" -- "${directory}/snapshot/project" || return 1
  chown --reference="${SB_PROJECT_DIR}" -- "${directory}/snapshot/project" || return 1
  routing_transaction_checkpoint snapshot || return 1
  if [[ "${operation}" == restore ]]; then
    routing_restore_project_snapshot "${SB_ROUTING_PREVIOUS_DIR}/snapshot" || return 1
    "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" >&2 || return 1
  else
    if [[ "${server_changed}" == true ]]; then
      SB_ROUTING_DEFER_WARP_RECEIPT=y
      SB_ROUTING_JOURNAL_LEGACY_BACKUP=y
      load_current_config_state || return 1
      # Read the canonical old endpoint only while establishing this explicit
      # transaction's baseline. This also permits removing the last custom or
      # per-node WARP dependency. It neither registers an account nor relaxes
      # final generation when the requested policy still requires WARP.
      SB_ROUTING_BASELINE_WARP_FALLBACK=y
      ensure_existing_generated_config_baseline || return 1
      SB_ROUTING_BASELINE_WARP_FALLBACK=n
    fi
    jq '.policy' "${draft}" > "${directory}/policy.json" || return 1
    routing_publish_file "${directory}/policy.json" "${SB_ROUTING_POLICY_FILE}" || return 1
    if [[ "${server_changed}" == true ]]; then
      jq -rj '.legacy_domains' "${draft}" > "${directory}/domains.txt" || return 1
      if [[ -e "${SB_WARP_DOMAINS_FILE}" || -s "${directory}/domains.txt" ]]; then
        routing_publish_file "${directory}/domains.txt" "${SB_WARP_DOMAINS_FILE}" || return 1
      fi
      jq -rj '.legacy_sources' "${draft}" > "${directory}/sources.txt" || return 1
      if [[ -e "${SB_WARP_REMOTE_RULESETS_FILE}" || -s "${directory}/sources.txt" ]]; then
        routing_publish_file "${directory}/sources.txt" "${SB_WARP_REMOTE_RULESETS_FILE}" || return 1
      fi
      SB_ENABLE_WARP=$(jq -r 'if .warp.enabled then "y" else "n" end' "${draft}") || return 1
      SB_WARP_ROUTE_MODE=$(jq -r '.warp.mode' "${draft}") || return 1
      printf 'WARP_ROUTE_MODE=%s\nWARP_ENABLED=%s\n' "${SB_WARP_ROUTE_MODE}" "${SB_ENABLE_WARP}" > "${directory}/warp.env" || return 1
      if [[ -e "${SB_WARP_ROUTE_SETTINGS_FILE}" || "${SB_ENABLE_WARP}" == y ]]; then
        routing_publish_file "${directory}/warp.env" "${SB_WARP_ROUTE_SETTINGS_FILE}" || return 1
      fi
      routing_apply_node_overrides "${draft}" "${directory}" || return 1
      if jq -e '.warp.reregister' "${draft}" >/dev/null; then
        if [[ "${SB_ENABLE_WARP}" != y ]] && ! instance_outbound_requires_warp && ! routing_policy_requires_warp "${policy}"; then
          routing_error '没有使用 WARP 的出口，未重新注册。'; return 1
        fi
        [[ ! -L "${SB_WARP_KEY_FILE}" ]] || return 1
        rm -f -- "${SB_WARP_KEY_FILE}" || return 1
      fi
      # Network activation owns account/asset preparation. Node and component
      # generation only consumes already prepared settings and credentials.
      if [[ "${warp_activation_requested}" == true ]]; then
        ensure_warp_routing_assets || return 1
        register_warp || return 1
      fi
      generate_config || return 1
    fi

  fi
  routing_transaction_checkpoint publish || return 1
  if [[ "${before_active}" == true && "${server_changed}" == true ]]; then
    routing_transaction_checkpoint service || return 1
    run_with_progress '应用合并后的规则并检查 sing-box 服务' systemctl restart sing-box >&2 || return 1
    systemctl is-active --quiet sing-box || return 1
  elif [[ "${before_active}" == false ]]; then
    # A pre-existing failed unit is also known to be inactive. Rule editing
    # must not require starting it or clearing that state; unknown states fail.
    [[ "$(routing_service_active_json)" == false ]] || return 1
  else
    systemctl is-active --quiet sing-box || return 1
  fi
  [[ "$(routing_state_fingerprint external)" == "${external_fingerprint}" ]] || {
    routing_error '事务期间手工文件或 ACME 状态发生变化，已保留事务供核对。'; return 1;
  }
  fingerprint=$(routing_state_fingerprint) || return 1
  routing_transaction_checkpoint committed "${fingerprint}" || return 1
  committed=y
  routing_transaction_keep_previous || return 1
  finished=y
  printf '[SUCCESS] 规则已应用；配置校验通过，服务原状态已保持。\n' >&2
)

routing_policy_apply() { routing_transaction_run apply "$@"; }
routing_policy_restore_previous() { routing_transaction_run restore; }
