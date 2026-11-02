
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
  tmpdir=$(mktemp -d)

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

agent_export_client_json() {
  local config_json export_path compatibility_warnings_json

  if ! config_json=$(build_singbox_client_config); then
    agent_json_error "client_config_generation_failed" "客户端配置生成失败；请检查已安装协议的状态、端口与认证字段，原导出文件和备份未改变。"
    return 1
  fi

  if ! validate_client_config_json "${config_json}"; then
    agent_json_error "client_config_validation_failed" "客户端配置未通过引用或核心 check 校验，未发布导出文件。"
    return 1
  fi

  compatibility_warnings_json=$(collect_client_export_warnings_json "${config_json}") || return 1

  export_path=$(client_export_file_path)
  if ! write_client_config_export "${config_json}"; then
    log_warn "agent export-client 写入失败: ${export_path}" >&2
    return 1
  fi

  jq -n \
    --arg path "${export_path}" \
    --argjson config "${config_json}" \
    --argjson warnings "${compatibility_warnings_json}" \
    '{
      "path": $path,
      "config": $config
    }
    + (if ($warnings | length) > 0 then {"warnings": $warnings} else {} end)'
}

agent_service_cli() {
  local command=${1:-}
  local json_flag=${2:-}
  local yes_flag=${3:-}
  local before_state after_state check_json restart_status

  if [[ "${command}" != "restart" ]]; then
    agent_json_error "unknown_service_command" "未知 service 子命令: ${command}"
    return 1
  fi

  agent_require_json_flag "${json_flag}" || return 1

  if [[ "${yes_flag}" != "--yes" ]]; then
    agent_json_error "confirmation_required" "service restart 需要 --yes 确认。"
    return 1
  fi

  before_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if ! check_json=$(agent_singbox_check_json); then
    after_state=$(systemctl is-active sing-box 2>/dev/null || true)
    jq -n \
      --arg before "${before_state:-unknown}" \
      --arg after "${after_state:-unknown}" \
      --argjson check "${check_json}" \
      '{
        ok: false,
        action: "service_restart",
        skipped: true,
        reason: "config_check_failed",
        service: {
          before: $before,
          after: $after
        },
        check: $check
      }'
    return 1
  fi

  if run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box; then
    restart_status=0
  else
    restart_status=$?
  fi
  after_state=$(systemctl is-active sing-box 2>/dev/null || true)

  if [[ "${restart_status}" != "0" || "${after_state}" != "active" ]]; then
    jq -n \
      --arg before "${before_state:-unknown}" \
      --arg after "${after_state:-unknown}" \
      --argjson exit_code "${restart_status}" \
      --argjson check "${check_json}" \
      '{
        ok: false,
        action: "service_restart",
        error: "service_restart_failed",
        skipped: false,
        service: {
          before: $before,
          after: $after,
          restart_exit_code: $exit_code
        },
        check: $check
      }'
    return 1
  fi

  jq -n \
    --arg before "${before_state:-unknown}" \
    --arg after "${after_state:-unknown}" \
    --argjson check "${check_json}" \
    '{
      ok: true,
      action: "service_restart",
      service: {
        before: $before,
        after: $after
      },
      check: $check
    }'
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
