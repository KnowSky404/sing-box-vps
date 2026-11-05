
agent_collect_nodes_json() {
  local mode=$1
  local public_ip original_protocol_state original_state_file original_instance_id
  local protocol node_json instance_id indexed_protocols instance_ids instance_record
  local nodes_json='[]'
  local installed_protocols=()
  local protocol_instance_records=()
  local tmpdir status=0

  if ! validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}"; then
    agent_json_error "live_inbound_inventory_untrusted" "现有配置包含无法完整识别的入站；未返回部分节点。"
    return 1
  fi
  if ! indexed_protocols=$(agent_trusted_indexed_protocols_raw); then
    agent_json_error "protocol_index_untrusted" "协议索引与现有配置无法完整对应；未返回部分节点。"
    return 1
  fi
  if ! agent_validate_indexed_protocol_states "${indexed_protocols}"; then
    agent_json_error "protocol_state_untrusted" "协议状态无法完整读取；未返回部分节点。"
    return 1
  fi
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    installed_protocols+=("${protocol}")
  done <<< "${indexed_protocols}"

  # Enumerate every managed instance before doing public-IP or other resource
  # work.  The records are the single input to the rendering loop below.
  for protocol in ${installed_protocols[@]+"${installed_protocols[@]}"}; do
    if ! instance_ids=$(list_protocol_instance_ids "${protocol}"); then
      agent_json_error "protocol_state_untrusted" "协议实例清单无法完整读取；未返回部分节点。"
      return 1
    fi
    while IFS= read -r instance_id; do
      [[ -n "${instance_id}" ]] || continue
      protocol_instance_records+=("${protocol}"$'\t'"${instance_id}")
    done <<< "${instance_ids}"
  done

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  original_state_file=""
  if [[ -n "${original_protocol_state}" ]]; then
    original_state_file=$(protocol_state_file "${original_protocol_state}" 2>/dev/null || true)
  fi
  original_instance_id=""
  if [[ -n "${original_state_file}" && -f "${original_state_file}" ]]; then
    if ! original_instance_id=$(protocol_default_instance_id "${original_protocol_state}"); then
      agent_json_error "protocol_state_untrusted" "当前协议默认实例无法完整读取；未返回节点。"
      return 1
    fi
  fi
  public_ip=$(get_public_ip)
  tmpdir=$(storage_mktemp -d)

  trap 'rm -rf "${tmpdir:-}"' RETURN

  for instance_record in ${protocol_instance_records[@]+"${protocol_instance_records[@]}"}; do
    IFS=$'\t' read -r protocol instance_id <<< "${instance_record}"
    if ! load_protocol_instance_state "${protocol}" "${instance_id}"; then
      status=1
      continue
    fi
    case "${mode}" in
      summary) node_json=$(agent_node_summary_json_for_current_protocol "${public_ip}") || status=1 ;;
      links) node_json=$(agent_link_json_for_current_protocol "${public_ip}") || status=1 ;;
      *) status=1; continue ;;
    esac

    if [[ -n "${node_json:-}" ]]; then
      if ! printf '%s\n' "${node_json}" >> "${tmpdir}/nodes.jsonl"; then
        status=1
      fi
    else
      status=1
    fi
  done

  if [[ -s "${tmpdir}/nodes.jsonl" ]]; then
    nodes_json=$(jq -s '.' "${tmpdir}/nodes.jsonl") || status=1
  fi
  if [[ -n "${original_state_file}" && -f "${original_state_file}" ]]; then
    load_protocol_instance_state "${original_protocol_state}" "${original_instance_id}" >/dev/null 2>&1 || status=1
  fi
  if rm -rf "${tmpdir}"; then
    tmpdir=""
  else
    status=1
  fi

  if [[ "${status}" != "0" ]]; then
    agent_json_error "protocol_state_untrusted" "协议状态无法完整读取；未返回部分节点。"
    return 1
  fi
  trap - RETURN

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg action "$([[ "${mode}" == "summary" ]] && printf 'nodes' || printf 'links')" \
    --argjson sensitive "$([[ "${mode}" == "links" ]] && printf 'true' || printf 'false')" \
    --arg public_address "${public_ip}" \
    --argjson nodes "${nodes_json}" \
    '{
      "schema": $schema,
      "action": $action,
      "sensitive": $sensitive,
      "public_address": $public_address,
      "nodes": $nodes
    }'

  return 0
}

service_menu_action() {
  local command=$1 response error
  if response=$(agent_dispatch service "${command}" --json --yes); then
    case "${command}" in
      start) log_success '服务已启动。' ;;
      stop) log_success '服务已停止。' ;;
      restart) log_success '服务已重启。' ;;
    esac
  else
    error=$(jq -r '.error // "service_operation_failed"' <<< "${response}") || error=service_operation_failed
    log_warn "服务操作未完成（${error}）；请检查配置、服务状态或待恢复事务。"
    return 1
  fi
}

agent_service_cli() {
  local command=${1:-} json=n confirmed=n lines=100 lines_set=n
  local before_state after_state check_json='null' operation_status=0 logs=''
  [[ $# -eq 0 ]] || shift

  case "${command}" in
    start|stop|restart|status|logs) ;;
    *) agent_json_error unknown_service_command "未知 service 子命令。"; return 1 ;;
  esac
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) [[ "${json}" == n ]] || break; json=y; shift ;;
      --yes) [[ "${confirmed}" == n ]] || break; confirmed=y; shift ;;
      --lines) [[ $# -ge 2 && "${lines_set}" == n ]] || break; lines=$2; lines_set=y; shift 2 ;;
      *) break ;;
    esac
  done
  if [[ $# -ne 0 || ( "${command}" != logs && "${lines_set}" == y ) ||
        ( ( "${command}" == status || "${command}" == logs ) && "${confirmed}" == y ) ]]; then
    agent_json_error invalid_arguments "service 参数无效；只接受该操作声明的参数。"
    return 1
  fi
  [[ "${json}" == y ]] || { agent_require_json_flag ''; return 1; }
  if [[ "${command}" == logs ]]; then
    if [[ ! "${lines}" =~ ^[1-9][0-9]{0,3}$ ]] || (( lines > 1000 )); then
      agent_json_error invalid_arguments "日志条数必须是 1 到 1000 的整数。"
      return 1
    fi
    if logs=$(SYSTEMD_COLORS=0 journalctl --unit sing-box --no-pager --quiet --lines "${lines}" --output short-iso 2>/dev/null); then
      operation_status=0
    else
      operation_status=$?
      logs=''
    fi
    printf '%s' "${logs}" | jq -n --rawfile logs /dev/stdin \
      --argjson lines "${lines}" --argjson exit_code "${operation_status}" '
      {ok:($exit_code==0),action:"service_logs",sensitive:true,lines:$lines,
       logs:$logs,journal_exit_code:$exit_code} +
      (if $exit_code==0 then {} else {error:"service_logs_unavailable",message:"无法读取服务日志；未返回部分日志。"} end)' || return 1
    [[ "${operation_status}" == 0 ]]
    return $?
  fi
  if [[ "${command}" != status && "${confirmed}" != y ]]; then
    agent_json_error confirmation_required "service ${command} 需要 --yes 确认。"
    return 1
  fi

  if before_state=$(systemctl is-active sing-box 2>/dev/null); then :; else before_state=${before_state:-unknown}; fi
  case "${before_state}" in
    active|inactive|failed|activating|deactivating|reloading) ;;
    *) before_state=unknown ;;
  esac
  if [[ "${command}" == status ]]; then
    jq -n --arg state "${before_state}" '{
      ok:($state!="unknown"),action:"service_status",sensitive:false,
      service:{active_state:$state,active:($state=="active")}} +
      (if $state=="unknown" then {error:"service_state_unavailable",message:"无法检测 sing-box 服务状态。"} else {} end)' || return 1
    [[ "${before_state}" != unknown ]]
    return $?
  fi
  if [[ "${before_state}" == unknown ]]; then
    agent_json_error service_state_unavailable "无法检测 sing-box 服务原状态；未执行服务操作。"
    return 1
  fi
  if [[ "${command}" != stop ]] && ! check_json=$(agent_singbox_check_json); then
    if after_state=$(systemctl is-active sing-box 2>/dev/null); then :; else after_state=${after_state:-unknown}; fi
    case "${after_state}" in active|inactive|failed|activating|deactivating|reloading) ;; *) after_state=unknown ;; esac
    jq -n --arg action "service_${command}" --arg before "${before_state}" \
      --arg after "${after_state}" --argjson check "${check_json}" '{
      ok:false,action:$action,skipped:true,reason:"config_check_failed",error:"config_check_failed",
      service:{before:$before,after:$after},check:$check}'
    return 1
  fi

  if run_with_progress "执行 sing-box ${command}（启动或重启时可能等待 ACME 签发）" systemctl "${command}" sing-box >&2; then
    operation_status=0
  else
    operation_status=$?
  fi
  if after_state=$(systemctl is-active sing-box 2>/dev/null); then :; else after_state=${after_state:-unknown}; fi
  case "${after_state}" in active|inactive|failed|activating|deactivating|reloading) ;; *) after_state=unknown ;; esac
  if [[ "${operation_status}" != 0 ||
        ( "${command}" == stop && "${after_state}" != inactive ) ||
        ( "${command}" != stop && "${after_state}" != active ) ]]; then
    jq -n --arg command "${command}" --arg before "${before_state}" --arg after "${after_state}" \
      --argjson exit_code "${operation_status}" --argjson check "${check_json}" '{
      ok:false,action:("service_"+$command),error:("service_"+$command+"_failed"),skipped:false,
      service:({before:$before,after:$after} + {($command+"_exit_code"):$exit_code}),check:$check}'
    return 1
  fi
  jq -n --arg action "service_${command}" --arg before "${before_state}" \
    --arg after "${after_state}" --argjson check "${check_json}" '{
    ok:true,action:$action,service:{before:$before,after:$after},check:$check}'
}

agent_push_nodes_to_subman_json() {
  local original_protocol_state protocol instance_id
  local address_entry address_label public_ip address_entries
  local instance_attempted instance_synced instance_stacked_synced
  local synced_count skipped_count failed_count shadowsocks_skipped_count trojan_skipped_count vmess_skipped_count vless_plain_skipped_count hy2_skipped_count ok_json
  local last_error_code last_error_disposition last_http_status last_retry_after unsupported_warning_json
  local subman_supported_protocol_count
  local compatibility_warnings_json
  local installed_protocols=()

  SUBMAN_NODE_RESULTS_JSON='[]'
  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  synced_count=0
  skipped_count=0
  failed_count=0
  shadowsocks_skipped_count=0
  trojan_skipped_count=0
  vmess_skipped_count=0
  vless_plain_skipped_count=0
  hy2_skipped_count=0
  subman_supported_protocol_count=0
  last_error_code=""
  last_error_disposition=""
  last_http_status=""
  last_retry_after=""
  compatibility_warnings_json=$(collect_hy2_compatibility_warnings_json "share")

  mapfile -t installed_protocols < <(list_installed_protocols)
  if [[ ${#installed_protocols[@]} -eq 0 ]]; then
    jq -n '{ok: false, synced: 0, skipped: 0, failed: 0, error: "no_installed_protocols"}'
    return 1
  fi

  for protocol in "${installed_protocols[@]}"; do
    protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || true)
    if [[ -z "${protocol}" ]]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! subman_type_for_protocol "${protocol}" >/dev/null; then
      skipped_count=$((skipped_count + 1))
      unsupported_warning_json=$(subman_unsupported_protocol_warning_json "${protocol}") || return 1
      compatibility_warnings_json=$(jq -cn \
        --argjson existing "${compatibility_warnings_json}" \
        --argjson addition "${unsupported_warning_json}" \
        '$existing + $addition') || return 1
      continue
    fi
    subman_supported_protocol_count=$((subman_supported_protocol_count + 1))

    if ! protocol_state_exists "${protocol}"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! load_protocol_state "${protocol}"; then
      failed_count=$((failed_count + 1))
      continue
    fi

    if [[ "${protocol}" == "vless-reality" ]]; then
      while IFS= read -r instance_id; do
        [[ -z "${instance_id}" ]] && continue
        instance_attempted=0
        instance_synced=0
        instance_stacked_synced=0
        if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
          record_subman_address_failure "${protocol}" "${instance_id}" y || return 1
          failed_count=$((failed_count + 1))
          last_error_code=${SUBMAN_LAST_ERROR_CODE}
          last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION}
          continue
        fi
        while IFS= read -r address_entry; do
          [[ -z "${address_entry}" ]] && continue
          address_label=${address_entry%%|*}
          public_ip=${address_entry#*|}
          instance_attempted=$((instance_attempted + 1))
          if push_subman_protocol_instance "${protocol}" "${public_ip}" "${instance_id}" "y" "${address_label}"; then
            synced_count=$((synced_count + 1))
            instance_synced=$((instance_synced + 1))
            if [[ -n "$(network_stack_suffix_from_label "${address_label}")" ]]; then
              instance_stacked_synced=$((instance_stacked_synced + 1))
            fi
          else
            failed_count=$((failed_count + 1))
            last_error_code=${SUBMAN_LAST_ERROR_CODE:-unknown_error}
            last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
            last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
            last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
          fi
        done <<< "${address_entries}"
        if subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}" && \
          push_subman_legacy_protocol_key_cleanup "${protocol}" "${instance_id}" "y"; then
          :
        elif subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}"; then
          failed_count=$((failed_count + 1))
          last_error_code=${SUBMAN_LAST_ERROR_CODE:-unknown_error}
          last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
          last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
          last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
        fi
      done < <(list_vless_reality_instance_ids)
      continue
    fi

    if [[ "${protocol}" == "shadowsocks" ]]; then
      push_subman_shadowsocks_protocol y || true
      synced_count=$((synced_count + ${SUBMAN_SHADOWSOCKS_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_SHADOWSOCKS_SKIPPED:-0}))
      shadowsocks_skipped_count=$((shadowsocks_skipped_count + ${SUBMAN_SHADOWSOCKS_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_SHADOWSOCKS_FAILED:-0}))
      if [[ -n "${SUBMAN_SHADOWSOCKS_WARNINGS_JSON:-}" ]]; then
        compatibility_warnings_json=$(jq -cn \
          --argjson existing "${compatibility_warnings_json}" \
          --argjson additions "${SUBMAN_SHADOWSOCKS_WARNINGS_JSON}" '$existing + $additions') || return 1
      fi
      if [[ "${SUBMAN_SHADOWSOCKS_FAILED:-0}" -gt 0 ]]; then
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-shadowsocks_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      continue
    fi

    if [[ "${protocol}" == "trojan" ]]; then
      if push_subman_trojan_protocol y; then
        :
      else
        # The protocol worker records per-instance failures in its counters;
        # retain those counters while keeping the aggregate operation running.
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-trojan_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      synced_count=$((synced_count + ${SUBMAN_TROJAN_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_TROJAN_SKIPPED:-0}))
      trojan_skipped_count=$((trojan_skipped_count + ${SUBMAN_TROJAN_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_TROJAN_FAILED:-0}))
      if [[ -n "${SUBMAN_TROJAN_WARNINGS_JSON:-}" ]]; then
        compatibility_warnings_json=$(jq -cn \
          --argjson existing "${compatibility_warnings_json}" \
          --argjson additions "${SUBMAN_TROJAN_WARNINGS_JSON}" '$existing + $additions') || return 1
      fi
      if [[ "${SUBMAN_TROJAN_FAILED:-0}" -gt 0 ]]; then
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-trojan_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      continue
    fi

    if [[ "${protocol}" == "vmess" ]]; then
      if push_subman_vmess_protocol y; then :; else
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-vmess_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      synced_count=$((synced_count + ${SUBMAN_VMESS_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_VMESS_SKIPPED:-0}))
      vmess_skipped_count=$((vmess_skipped_count + ${SUBMAN_VMESS_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_VMESS_FAILED:-0}))
      if [[ -n "${SUBMAN_VMESS_WARNINGS_JSON:-}" ]]; then
        compatibility_warnings_json=$(jq -cn --argjson existing "${compatibility_warnings_json}" --argjson additions "${SUBMAN_VMESS_WARNINGS_JSON}" '$existing + $additions') || return 1
      fi
      if [[ "${SUBMAN_VMESS_FAILED:-0}" -gt 0 ]]; then
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-vmess_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      continue
    fi

    if [[ "${protocol}" == "vless-plain" ]]; then
      if push_subman_vless_plain_protocol y; then :; else
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-vless_plain_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      synced_count=$((synced_count + ${SUBMAN_VLESS_PLAIN_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_VLESS_PLAIN_SKIPPED:-0}))
      vless_plain_skipped_count=$((vless_plain_skipped_count + ${SUBMAN_VLESS_PLAIN_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_VLESS_PLAIN_FAILED:-0}))
      if [[ -n "${SUBMAN_VLESS_PLAIN_WARNINGS_JSON:-}" ]]; then
        compatibility_warnings_json=$(jq -cn --argjson existing "${compatibility_warnings_json}" --argjson additions "${SUBMAN_VLESS_PLAIN_WARNINGS_JSON}" '$existing + $additions') || return 1
      fi
      if [[ "${SUBMAN_VLESS_PLAIN_FAILED:-0}" -gt 0 ]]; then
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-vless_plain_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      continue
    fi

    if [[ "${protocol}" == "hy2" ]] && [[ "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; then
      if push_subman_hy2_protocol y; then :; else
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-hy2_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      synced_count=$((synced_count + ${SUBMAN_HY2_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_HY2_SKIPPED:-0}))
      hy2_skipped_count=$((hy2_skipped_count + ${SUBMAN_HY2_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_HY2_FAILED:-0}))
      if [[ -n "${SUBMAN_HY2_WARNINGS_JSON:-}" ]]; then
        compatibility_warnings_json=$(jq -cn --argjson existing "${compatibility_warnings_json}" --argjson additions "${SUBMAN_HY2_WARNINGS_JSON}" '$existing + $additions') || return 1
      fi
      if [[ "${SUBMAN_HY2_FAILED:-0}" -gt 0 ]]; then
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-hy2_sync_failed}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
      continue
    fi

    if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
      record_subman_address_failure "${protocol}" "" y || return 1
      failed_count=$((failed_count + 1))
      last_error_code=${SUBMAN_LAST_ERROR_CODE}
      last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION}
      continue
    fi
    while IFS= read -r address_entry; do
      [[ -z "${address_entry}" ]] && continue
      address_label=${address_entry%%|*}
      public_ip=${address_entry#*|}
      if push_subman_protocol_instance "${protocol}" "${public_ip}" "" "y" "${address_label}"; then
        synced_count=$((synced_count + 1))
      else
        failed_count=$((failed_count + 1))
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-unknown_error}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
    done <<< "${address_entries}"
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi

  if (( synced_count == 0 && shadowsocks_skipped_count == 0 && trojan_skipped_count == 0 && vmess_skipped_count == 0 && vless_plain_skipped_count == 0 && hy2_skipped_count == 0 && failed_count == 0 && subman_supported_protocol_count > 0 )); then
    agent_json_error "public_ip_unavailable" "未获取到公网 IP，无法生成 SubMan 节点链接。"
    return 1
  fi

  ok_json=false
  if (( synced_count > 0 && failed_count == 0 )); then
    ok_json=true
  fi

  jq \
    --argjson ok "${ok_json}" \
    --argjson synced "${synced_count}" \
    --argjson skipped "${skipped_count}" \
    --argjson failed "${failed_count}" \
    --arg error_code "${last_error_code}" \
    --arg error_disposition "${last_error_disposition}" \
    --arg http_status "${last_http_status}" \
    --arg retry_after "${last_retry_after}" \
    --argjson warnings "${compatibility_warnings_json}" \
    '. as $results | {
      ok: $ok,
      synced: $synced,
      skipped: $skipped,
      failed: $failed,
      results: $results
    }
    + (if ($warnings | length) > 0 then {
        warnings: $warnings
      } else {} end)
    + (if $failed > 0 and $error_code != "" then {
        last_error: {
          code: $error_code,
          disposition: $error_disposition,
          http_status: (if $http_status == "" then null else $http_status end),
          retry_after: (if $retry_after == "" then null else $retry_after end)
        }
      } else {} end)' <<< "${SUBMAN_NODE_RESULTS_JSON:-[]}"

  if [[ "${ok_json}" != "true" ]]; then
    return 1
  fi
}

agent_subman_sync_json() {
  local config_file

  config_file=$(subman_config_file_path)
  if [[ ! -f "${config_file}" ]]; then
    agent_json_error "subman_config_missing" "未找到 SubMan 配置，请先在交互菜单中配置 SubMan。"
    return 1
  fi

  load_subman_config
  if [[ -z "${SUBMAN_API_URL}" || -z "${SUBMAN_API_TOKEN}" || -z "${SUBMAN_EXPECTED_GIST_ID:-}" ]]; then
    agent_json_error "subman_config_missing" "SubMan API URL、Token 或预期 Workspace Gist ID 为空；请在交互菜单中补全配置。"
    return 1
  fi

  agent_push_nodes_to_subman_json
}
