
agent_warp_json() {
  local warp_enabled warp_route_mode account_registered has_client_id
  local domains_count exact_count suffix_count local_rules_count remote_rules_count
  local ai_domains_count ai_suffixes_count stream_domains_count stream_suffixes_count
  local saved_route_mode raw_line line

  warp_enabled="n"
  if [[ -f "${SINGBOX_CONFIG_FILE}" ]] && config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
    warp_enabled="y"
  fi
  warp_route_mode="selective"
  if [[ -f "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]; then
    saved_route_mode=$(grep '^WARP_ROUTE_MODE=' "${SB_WARP_ROUTE_SETTINGS_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ')
    if validate_warp_route_mode "${saved_route_mode}"; then
      warp_route_mode="${saved_route_mode}"
    fi
  elif [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    warp_route_mode=$(config_detect_warp_route_mode "${SINGBOX_CONFIG_FILE}")
  fi

  account_registered=false
  has_client_id=false

  if [[ -f "${SB_WARP_KEY_FILE}" ]]; then
    account_registered=true
    if grep -q '^WARP_CLIENT_ID=' "${SB_WARP_KEY_FILE}" 2>/dev/null; then
      has_client_id=true
    fi
  fi

  domains_count=0
  exact_count=0
  suffix_count=0
  if [[ -f "${SB_WARP_DOMAINS_FILE}" ]]; then
    while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
      line=${raw_line%%#*}
      line=$(trim_whitespace "${line}")
      [[ -z "${line}" ]] && continue
      domains_count=$((domains_count + 1))
      if [[ "${line}" == =* ]]; then
        exact_count=$((exact_count + 1))
      else
        suffix_count=$((suffix_count + 1))
      fi
    done < "${SB_WARP_DOMAINS_FILE}"
  fi

  local_rules_count=0
  if [[ -d "${SB_WARP_LOCAL_RULESET_DIR}" ]]; then
    local_rules_count=$(find "${SB_WARP_LOCAL_RULESET_DIR}" -maxdepth 1 -type f \( -name '*.json' -o -name '*.srs' \) | wc -l)
  fi

  remote_rules_count=0
  if [[ -f "${SB_WARP_REMOTE_RULESETS_FILE}" ]]; then
    while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
      line=${raw_line%%#*}
      line=$(trim_whitespace "${line}")
      [[ -z "${line}" ]] && continue
      remote_rules_count=$((remote_rules_count + 1))
    done < "${SB_WARP_REMOTE_RULESETS_FILE}"
  fi

  ai_domains_count=$(echo "${WARP_AI_ROUTE_DOMAINS_JSON}" | jq 'length')
  ai_suffixes_count=$(echo "${WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON}" | jq 'length')
  stream_domains_count=$(echo "${WARP_STREAM_ROUTE_DOMAINS_JSON}" | jq 'length')
  stream_suffixes_count=$(echo "${WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON}" | jq 'length')

  jq -n \
    --argjson enabled "$([[ "${warp_enabled}" == "y" ]] && printf 'true' || printf 'false')" \
    --arg route_mode "${warp_route_mode}" \
    --argjson account_registered "${account_registered}" \
    --argjson has_client_id "${has_client_id}" \
    --argjson domains_count "${domains_count}" \
    --argjson exact_count "${exact_count}" \
    --argjson suffix_count "${suffix_count}" \
    --argjson local_rule_sets_count "${local_rules_count}" \
    --argjson remote_rule_sets_count "${remote_rules_count}" \
    --argjson ai_domains_count "${ai_domains_count}" \
    --argjson ai_suffixes_count "${ai_suffixes_count}" \
    --argjson stream_domains_count "${stream_domains_count}" \
    --argjson stream_suffixes_count "${stream_suffixes_count}" \
    --arg key_file "${SB_WARP_KEY_FILE}" \
    --arg route_settings_file "${SB_WARP_ROUTE_SETTINGS_FILE}" \
    --arg domains_file "${SB_WARP_DOMAINS_FILE}" \
    --arg remote_rule_sets_file "${SB_WARP_REMOTE_RULESETS_FILE}" \
    --arg local_rule_set_dir "${SB_WARP_LOCAL_RULESET_DIR}" \
    '{
      "enabled": $enabled,
      "route_mode": $route_mode,
      "account": {
        "registered": $account_registered,
        "has_client_id": $has_client_id
      },
      "routing": {
        "custom_domains": {
          "total": $domains_count,
          "exact": $exact_count,
          "suffix": $suffix_count
        },
        "local_rule_sets_count": $local_rule_sets_count,
        "remote_rule_sets_count": $remote_rule_sets_count,
        "builtin": {
          "ai_domains": $ai_domains_count,
          "ai_suffixes": $ai_suffixes_count,
          "stream_domains": $stream_domains_count,
          "stream_suffixes": $stream_suffixes_count
        }
      },
      "paths": {
        "key_file": $key_file,
        "route_settings": $route_settings_file,
        "domains": $domains_file,
        "remote_rule_sets": $remote_rule_sets_file,
        "local_rule_set_dir": $local_rule_set_dir
      }
    }'
}

agent_singbox_check_json() {
  local stdout_file stderr_file exit_code binary_version

  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  if "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${stdout_file}" 2> "${stderr_file}"; then
    exit_code=0
  else
    exit_code=$?
  fi
  binary_version=$(detect_installed_singbox_version)

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg binary_version "${binary_version}" \
    --arg config_file "${SINGBOX_CONFIG_FILE}" \
    --arg stdout "$(cat "${stdout_file}")" \
    --arg stderr "$(cat "${stderr_file}")" \
    --argjson exit_code "${exit_code}" \
    '{
      schema: $schema,
      ok: ($exit_code == 0),
      exit_code: $exit_code,
      binary_version: $binary_version,
      config_file: $config_file,
      stdout: $stdout,
      stderr: $stderr
    }'

  rm -f "${stdout_file}" "${stderr_file}"
  return "${exit_code}"
}

agent_protocol_id() {
  protocol_registry_field "$1" agent_id
}

agent_trusted_indexed_protocols_raw() {
  local index_schema indexed_raw live_raw indexed protocol
  local indexed_protocols=() live_protocols=()

  [[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]] || return 1

  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    index_schema=$(sed -n 's/^PROTOCOL_STATE_VERSION=//p' "${SB_PROTOCOL_INDEX_FILE}") || return 1
    index_schema=${index_schema//\"/}
    index_schema=${index_schema//\'/}
    [[ "${index_schema:-1}" == "1" ]] || return 1
  fi

  indexed_raw=$(list_indexed_protocols_raw) || return 1
  while IFS= read -r indexed; do
    [[ -n "${indexed}" ]] || continue
    protocol=$(normalize_protocol_id "${indexed}") || return 1
    if protocol_array_contains "${protocol}" ${indexed_protocols[@]+"${indexed_protocols[@]}"}; then
      return 1
    fi
    indexed_protocols+=("${protocol}")
  done <<< "${indexed_raw}"

  live_raw=$(list_config_protocols) || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] && live_protocols+=("${protocol}")
  done <<< "${live_raw}"

  [[ ${#indexed_protocols[@]} -eq ${#live_protocols[@]} ]] || return 1
  [[ ${#indexed_protocols[@]} -gt 0 ]] || return 0
  for protocol in "${live_protocols[@]}"; do
    protocol_array_contains "${protocol}" "${indexed_protocols[@]}" || return 1
  done

  [[ ${#indexed_protocols[@]} -gt 0 ]] || return 0
  printf '%s\n' "${indexed_protocols[@]}"
}

agent_validate_indexed_protocol_states() {
  local indexed_protocols=$1 protocol state_file state_id normalized_state_id
  local expected_protocols=() plain_protocol plain_store_file plain_store_count

  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] && expected_protocols+=("${protocol}")
  done <<< "${indexed_protocols}"

  # A deleted plain proxy may leave a valid revisioned empty tombstone for
  # CAS continuity.  It is safe when its protocol is absent from the index; a
  # non-empty orphan would be an unowned inventory and must fail closed.
  for plain_protocol in mixed socks http shadowsocks trojan vmess vless-plain anytls hy2 snell tuic hysteria naive shadowtls; do
    if ! protocol_array_contains "${plain_protocol}" ${expected_protocols[@]+"${expected_protocols[@]}"}; then
      plain_store_file=$(plain_proxy_structured_store_file "${plain_protocol}") || return 1
      if [[ -e "${plain_store_file}" || -L "${plain_store_file}" ]]; then
        [[ -f "${plain_store_file}" && ! -L "${plain_store_file}" ]] || return 1
        validate_structured_instance_store "${plain_protocol}" "${plain_store_file}" || return 1
        plain_store_count=$(jq -r '.instances | length' "${plain_store_file}") || return 1
        [[ "${plain_store_count}" == "0" ]] || return 1
        jq -e '.revision > 0' "${plain_store_file}" >/dev/null 2>&1 || return 1
      fi
    fi
  done

  for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
    [[ -e "${state_file}" ]] || continue
    [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] && continue
    state_id=${state_file##*/}
    state_id=${state_id%.env}
    normalized_state_id=$(normalize_protocol_id "${state_id}") || return 1
    [[ "${normalized_state_id}" == "${state_id}" ]] || return 1
    protocol_array_contains "${state_id}" ${expected_protocols[@]+"${expected_protocols[@]}"} || return 1
    validate_protocol_state_schema "${state_id}" "${state_file}" || return 1
  done

  for protocol in ${expected_protocols[@]+"${expected_protocols[@]}"}; do
    state_file=$(protocol_state_file "${protocol}") || return 1
    [[ -f "${state_file}" ]] || return 1
    validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
    if [[ "${protocol}" == "vless-reality" ]]; then
      agent_validate_vless_state_inventory || return 1
    elif [[ "${protocol}" == "mixed" ]]; then
      # Schema-2 Mixed must expose the complete typed manifest.  Returning a
      # partial first-node view would make Agent status/links appear healthy
      # while silently omitting listeners or credentials.
      mixed_validate_state_inventory || return 1
    elif [[ "${protocol}" == "vless-plain" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls" ]]; then
      # Plain proxy protocols are structured-only. Validate the complete
      # manifest and compare every live tag before reporting them installed.
      plain_proxy_validate_state_inventory "${protocol}" || return 1
    elif [[ "${protocol}" == "anytls" ]]; then
      # AnyTLS retains its schema-1 ACME/provider state. Only the manual-TLS
      # schema-2 marker owns a typed instance store and live tag comparison.
      local anytls_state_schema
      anytls_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" | head -n1) || return 1
      anytls_state_schema=${anytls_state_schema//\"/}
      anytls_state_schema=${anytls_state_schema//\'/}
      if [[ "${anytls_state_schema}" == "2" ]]; then
        plain_proxy_validate_state_inventory anytls || return 1
      fi
    fi
  done
}

vless_reality_legacy_state_is_complete() {
  local state_file
  state_file=$(protocol_state_file "vless-reality") || return 1
  [[ -f "${state_file}" ]] || return 1

  (
    unset INSTALLED NODE_NAME PORT UUID SNI REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY SHORT_ID_1
    # shellcheck disable=SC1090
    source "${state_file}"
    [[ "${INSTALLED:-}" == "1" && -n "${NODE_NAME:-}" ]] || return 1
    validate_port_number "${PORT:-}" || return 1
    [[ "${UUID:-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 1
    [[ -n "${SNI:-}" && -n "${REALITY_PRIVATE_KEY:-}" && -n "${REALITY_PUBLIC_KEY:-}" && -n "${SHORT_ID_1:-}" ]]
  )
}

agent_legacy_vless_state_is_complete() {
  vless_reality_legacy_state_is_complete
}

vless_reality_loaded_connection_is_complete() {
  [[ -n "${SB_NODE_NAME}" ]] || return 1
  validate_port_number "${SB_PORT}" || return 1
  [[ "${SB_UUID}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 1
  [[ -n "${SB_SNI}" && -n "${SB_PRIVATE_KEY}" && -n "${SB_PUBLIC_KEY}" && -n "${SB_SHORT_ID_1}" ]]
}

agent_vless_instance_tag_if_complete() {
  local instance_id=$1

  load_vless_reality_instance_state "${instance_id}" || return 1
  [[ "${INSTANCE_ID:-}" == "${instance_id}" && "${ENABLED:-}" == "1" ]] || return 1
  vless_reality_loaded_connection_is_complete || return 1
  vless_reality_inbound_tag_for_instance "${instance_id}"
}

agent_vless_multi_instance_root_is_complete() {
  local state_file
  state_file=$(protocol_state_file "vless-reality") || return 1
  [[ -f "${state_file}" ]] || return 1

  (
    unset INSTALLED CONFIG_SCHEMA_VERSION DEFAULT_INSTANCE_ID INSTANCE_IDS REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY
    # shellcheck disable=SC1090
    source "${state_file}"
    [[ "${INSTALLED:-}" == "1" && "${CONFIG_SCHEMA_VERSION:-}" == "2" ]] || return 1
    [[ -n "${DEFAULT_INSTANCE_ID:-}" && -n "${INSTANCE_IDS:-}" ]] || return 1
    [[ -n "${REALITY_PRIVATE_KEY:-}" && -n "${REALITY_PUBLIC_KEY:-}" ]]
  )
}

agent_validate_vless_state_inventory() (
  local state_file schema instance_ids live_tags instance_id instance_state_file instance_state_id instance_tag live_tag
  local default_instance_id live_count instance_file instance_file_count=0
  local instance_id_list=() instance_tags=() live_tag_list=()

  state_file=$(protocol_state_file "vless-reality") || return 1
  [[ -f "${state_file}" ]] || return 1
  schema=$(sed -n 's/^CONFIG_SCHEMA_VERSION=//p' "${state_file}") || return 1
  schema=${schema//\"/}
  schema=${schema//\'/}
  live_count=$(config_protocol_inbound_count vless-reality "${SINGBOX_CONFIG_FILE}") || return 1
  live_tags=$(config_protocol_inbounds_jsonl vless-reality "${SINGBOX_CONFIG_FILE}" | jq -r '.tag // empty') || return 1
  [[ "${live_count}" =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r live_tag; do
    [[ -n "${live_tag}" ]] && live_tag_list+=("${live_tag}")
  done <<< "${live_tags}"
  if [[ ${#live_tag_list[@]} -ne ${live_count} ]]; then
    # Legacy tagless configurations use the same unique identity resolution as
    # takeover. Keep all completeness and exact file-set checks below intact.
    collect_vless_reality_config_instances || return 1
    live_tag_list=("${VLESS_CONFIG_INSTANCE_TAGS[@]}")
  fi
  [[ ${#live_tag_list[@]} -eq ${live_count} ]] || return 1

  case "${schema:-1}" in
    1)
      [[ "${live_count}" == "1" && "${live_tag_list[0]}" == "vless-in" ]] || return 1
      agent_legacy_vless_state_is_complete || return 1
      load_vless_reality_protocol_state || return 1
      [[ -z "${VLESS_REALITY_INSTANCE_IDS}" ]] || return 1
      for instance_file in "$(vless_reality_instance_dir)"/*.env; do
        if [[ -e "${instance_file}" ]]; then
          return 1
        fi
      done
      return 0
      ;;
    2)
      agent_vless_multi_instance_root_is_complete || return 1
      load_vless_reality_protocol_state || return 1
      [[ -n "${VLESS_REALITY_INSTANCE_IDS}" ]] || return 1
      default_instance_id=${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}
      validate_vless_reality_instance_id "${default_instance_id}" || return 1
      if ! instance_ids=$(list_vless_reality_instance_ids); then
        return 1
      fi
      [[ -n "${instance_ids}" ]] || return 1
      while IFS= read -r instance_id; do
        [[ -n "${instance_id}" ]] || continue
        validate_vless_reality_instance_id "${instance_id}" || return 1
        protocol_array_contains "${instance_id}" "${instance_id_list[@]}" && return 1
        instance_state_file=$(vless_reality_instance_state_file "${instance_id}") || return 1
        [[ -f "${instance_state_file}" ]] || return 1
        instance_tag=$(agent_vless_instance_tag_if_complete "${instance_id}") || return 1
        protocol_array_contains "${instance_tag}" "${instance_tags[@]}" && return 1
        instance_id_list+=("${instance_id}")
        instance_tags+=("${instance_tag}")
      done <<< "${instance_ids}"
      protocol_array_contains "${default_instance_id}" "${instance_id_list[@]}" || return 1

      for instance_file in "$(vless_reality_instance_dir)"/*.env; do
        [[ -e "${instance_file}" ]] || continue
        instance_state_id=${instance_file##*/}
        instance_state_id=${instance_state_id%.env}
        validate_vless_reality_instance_id "${instance_state_id}" || return 1
        protocol_array_contains "${instance_state_id}" "${instance_id_list[@]}" || return 1
        instance_file_count=$((instance_file_count + 1))
      done
      [[ ${instance_file_count} -eq ${#instance_id_list[@]} ]] || return 1
      [[ ${#instance_tags[@]} -eq ${live_count} ]] || return 1
      for live_tag in "${live_tag_list[@]}"; do
        protocol_array_contains "${live_tag}" "${instance_tags[@]}" || return 1
      done
      ;;
    *)
      return 1
      ;;
  esac
)

agent_installed_protocols_json() {
  local indexed_protocols=$1 protocol

  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    agent_protocol_id "${protocol}" || return 1
    printf '\n'
  done <<< "${indexed_protocols}" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

agent_status_json() {
  local indexed_protocols installed_protocols_json active_state installed_version warload_mode warload_enabled
  local host_stack bbr_algorithm bbr_enabled inbound_stack_mode outbound_stack_mode
  local reality_instance_count qos_filter_count subman_configured client_export_exists components_json

  if ! validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}"; then
    agent_json_error "live_inbound_inventory_untrusted" "现有配置包含无法完整识别的入站；未返回部分协议状态。"
    return 1
  fi
  if ! indexed_protocols=$(agent_trusted_indexed_protocols_raw); then
    agent_json_error "protocol_index_untrusted" "协议索引无法完整识别；未返回部分协议状态。"
    return 1
  fi
  if ! agent_validate_indexed_protocol_states "${indexed_protocols}"; then
    agent_json_error "protocol_state_untrusted" "协议状态无法完整读取；未返回部分协议状态。"
    return 1
  fi
  installed_protocols_json=$(agent_installed_protocols_json "${indexed_protocols}") || return 1
  if ! components_json=$(managed_component_inventory_json); then
    agent_json_error "component_state_untrusted" "高级组件状态无法完整读取；未返回部分组件状态。"
    return 1
  fi
  warload_mode="selective"
  warload_enabled=false
  if [[ -f "${SINGBOX_CONFIG_FILE}" ]] && config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
    warload_enabled=true
  fi
  if [[ -f "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]; then
    local saved_mode
    saved_mode=$(grep '^WARP_ROUTE_MODE=' "${SB_WARP_ROUTE_SETTINGS_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ')
    if validate_warp_route_mode "${saved_mode}"; then
      warload_mode="${saved_mode}"
    fi
  elif [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    warload_mode=$(config_detect_warp_route_mode "${SINGBOX_CONFIG_FILE}")
  fi
  active_state=$(systemctl is-active sing-box 2>/dev/null || true)
  installed_version=$("${SINGBOX_BIN_PATH}" version 2>/dev/null | head -n1 | awk '{print $3}' || true)
  host_stack=$(detect_host_ip_stack)
  load_stack_mode_state
  inbound_stack_mode="${SB_INBOUND_STACK_MODE}"
  outbound_stack_mode="${SB_OUTBOUND_STACK_MODE}"
  bbr_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
  bbr_enabled=false
  [[ "${bbr_algorithm}" == "bbr" ]] && bbr_enabled=true
  reality_instance_count=$(jq -r '[.inbounds[]? | select(.type == "vless" and .tls.reality? != null)] | length' "${SINGBOX_CONFIG_FILE}" 2>/dev/null || printf '0')
  [[ "${reality_instance_count}" =~ ^[0-9]+$ ]] || reality_instance_count=0
  qos_filter_count=0
  if [[ -f "${SB_REALITY_QOS_FILTER_STATE_FILE}" ]]; then
    qos_filter_count=$(awk 'NF { count++ } END { print count + 0 }' "${SB_REALITY_QOS_FILTER_STATE_FILE}")
  fi
  subman_configured=false
  [[ -f "$(subman_config_file_path)" ]] && subman_configured=true
  client_export_exists=false
  [[ -f "$(client_export_file_path)" ]] && client_export_exists=true

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg script_version "${SCRIPT_VERSION}" \
    --arg supported_version "${SB_SUPPORT_MAX_VERSION}" \
    --arg active_state "${active_state:-unknown}" \
    --arg sing_box_version "${installed_version}" \
    --arg project_dir "${SB_PROJECT_DIR}" \
    --arg config_file "${SINGBOX_CONFIG_FILE}" \
    --arg protocol_state_dir "${SB_PROTOCOL_STATE_DIR}" \
    --arg client_export_path "$(client_export_file_path)" \
    --arg upgrade_backup_root "${SB_UPGRADE_BACKUP_ROOT}" \
    --arg stack_state_file "${SB_STACK_STATE_FILE}" \
    --arg qos_state_file "${SB_REALITY_QOS_FILTER_STATE_FILE}" \
    --arg subman_config_file "$(subman_config_file_path)" \
    --arg host_stack "${host_stack}" \
    --arg inbound_stack_mode "${inbound_stack_mode}" \
    --arg outbound_stack_mode "${outbound_stack_mode}" \
    --arg bbr_algorithm "${bbr_algorithm}" \
    --argjson bbr_enabled "${bbr_enabled}" \
    --argjson reality_instance_count "${reality_instance_count}" \
    --argjson qos_filter_count "${qos_filter_count}" \
    --argjson subman_configured "${subman_configured}" \
    --argjson client_export_exists "${client_export_exists}" \
    --argjson protocols "${installed_protocols_json}" \
    --argjson components "${components_json}" \
    --argjson warp_enabled "$([[ "${warload_enabled}" == true ]] && printf 'true' || printf 'false')" \
    --arg warp_route_mode "${warload_mode}" \
    '{
      "schema": $schema,
      "script_version": $script_version,
      "supported_sing_box_version": $supported_version,
      "service": {
        "name": "sing-box",
        "active_state": $active_state
      },
      "sing_box": {
        "binary": "sing-box",
        "version": $sing_box_version
      },
      "paths": {
        "project": $project_dir,
        "config": $config_file,
        "protocol_state_dir": $protocol_state_dir,
        "client_export": $client_export_path,
        "upgrade_backups": $upgrade_backup_root,
        "stack_state": $stack_state_file,
        "reality_qos_state": $qos_state_file,
        "subman_config": $subman_config_file
      },
      "protocols": $protocols,
      "components": $components,
      "network_stack": {
        "host": $host_stack,
        "inbound": $inbound_stack_mode,
        "outbound": $outbound_stack_mode
      },
      "system": {
        "tcp_congestion_control": $bbr_algorithm,
        "bbr_enabled": $bbr_enabled
      },
      "reality": {
        "instances": $reality_instance_count,
        "qos_filters": $qos_filter_count
      },
      "integrations": {
        "subman_configured": $subman_configured,
        "client_export_exists": $client_export_exists
      },
      "warp": {
        "enabled": $warp_enabled,
        "route_mode": $warp_route_mode
      }
    }'
}

agent_doctor_json() {
  local status_json check_json check_status compatibility_json managed_instance_state
  local config_exists index_exists state_dir_exists service_file_exists

  check_status=0
  config_exists=false
  index_exists=false
  state_dir_exists=false
  service_file_exists=false

  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && config_exists=true
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && index_exists=true
  [[ -d "${SB_PROTOCOL_STATE_DIR}" ]] && state_dir_exists=true
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && service_file_exists=true

  status_json=$(agent_status_json)
  check_json=$(agent_singbox_check_json) || check_status=$?
  compatibility_json=$(agent_config_compatibility_json "${SB_SUPPORT_MAX_VERSION}")
  managed_instance_state=$(detect_existing_instance_state_read_only)

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --argjson status "${status_json}" \
    --argjson check "${check_json}" \
    --argjson compatibility "${compatibility_json}" \
    --arg managed_instance_state "${managed_instance_state}" \
    --argjson config_exists "${config_exists}" \
    --argjson index_exists "${index_exists}" \
    --argjson state_dir_exists "${state_dir_exists}" \
    --argjson service_file_exists "${service_file_exists}" \
    --argjson check_status "${check_status}" \
    '{
      schema: $schema,
      status: $status,
      diagnostics: {
        managed_instance_state: $managed_instance_state,
        config_file_exists: $config_exists,
        protocol_index_exists: $index_exists,
        protocol_state_dir_exists: $state_dir_exists,
        service_file_exists: $service_file_exists,
        check_exit_code: $check_status,
        check: $check,
        compatibility: $compatibility
      }
    }'
}

agent_shadowsocks_node_json() {
  local filter
  filter=$(structured_instance_record_jq_filter) || return 1
  jq -e "${filter}"'ss_auth' <<< "${SB_SHADOWSOCKS_AUTH_JSON:-null}" >/dev/null 2>&1 || return 1
  jq -n --arg id "${SB_INSTANCE_ID}" --arg name "${SB_NODE_NAME}" --arg tag "${SB_MIXED_INBOUND_TAG}" \
    --arg address "${SB_MIXED_LISTEN_ADDRESS}" --argjson port "${SB_PORT}" \
    --argjson revision "${SB_MIXED_STORE_REVISION}" --arg policy "${SB_OUTBOUND_POLICY}" \
    --argjson network "${SB_SHADOWSOCKS_NETWORK_JSON}" --argjson auth "${SB_SHADOWSOCKS_AUTH_JSON}" '
      {protocol:"shadowsocks",name:$name,port:$port,instance_id:$id,tag:$tag,
       instance_revision:$revision,listen:{address:$address,port:$port,network:$network},
       outbound_policy:$policy,method:$auth.method,auth_enabled:($auth.method!="none"),
       user_count:(if ($auth.users|length)==0 then 1 else ($auth.users|length) end),
       shareable:true,client_exportable:true}
    '
}

agent_shadowsocks_link_json() {
  local server=${1:-} summary links outbounds warnings store_file start_snapshot end_snapshot start_revision
  store_file=$(plain_proxy_structured_store_file shadowsocks) || return 1
  start_snapshot=$(structured_instance_store_snapshot_json shadowsocks "${store_file}") || return 1
  start_revision=$(jq -r '.revision | tostring' <<< "${start_snapshot}") || return 1
  [[ "${start_revision}" =~ ^[0-9]+$ && "${start_revision}" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  jq -e --arg id "${SB_INSTANCE_ID:-}" 'any(.instances[]; .id == $id)' <<< "${start_snapshot}" >/dev/null 2>&1 || return 1
  summary=$(agent_shadowsocks_node_json) || return 1
  links=$(build_shadowsocks_links_json "${server}") || return 1
  outbounds=$(build_shadowsocks_instance_outbounds "${SB_INSTANCE_ID}" "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json shadowsocks "${store_file}") || return 1
  [[ "${end_snapshot}" == "${start_snapshot}" ]] || return 1
  outbounds=$(jq -cs . <<< "${outbounds}") || return 1
  warnings=$(shadowsocks_share_warnings_json) || return 1
  jq -cn --argjson summary "${summary}" --argjson links "${links}" \
    --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" \
    '$summary + {links:$links,outbounds:$outbounds,warnings:$warnings}'
}

agent_trojan_node_json() {
  local public_ip=${1:-$(get_public_ip)} server share_result shareable=false
  local tls_json transport_json tls_enabled transport_type user_count
  tls_json=${SB_TROJAN_TLS_JSON:-}
  transport_json=${SB_TROJAN_TRANSPORT_JSON:-}
  [[ -n "${tls_json}" && -n "${transport_json}" ]] || return 1
  tls_enabled=$(jq -er 'if .enabled == true then "true" elif .enabled == false then "false" else empty end' <<< "${tls_json}") || return 1
  transport_type=$(jq -er '.type' <<< "${transport_json}") || return 1
  user_count=$(jq -er 'length' <<< "${SB_TROJAN_AUTH_JSON:-[]}") || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  if [[ -n "${server}" ]] && share_result=$(build_trojan_subman_links_and_warnings_json "${server}" "${SB_INSTANCE_ID:-}"); then
    if jq -e '.links | length > 0' <<< "${share_result}" >/dev/null; then
      shareable=true
    fi
  else
    shareable=false
  fi
  jq -n \
    --arg name "${SB_NODE_NAME:-Trojan}" \
    --arg id "${SB_INSTANCE_ID:-}" \
    --arg tag "${SB_MIXED_INBOUND_TAG:-}" \
    --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" \
    --arg port "${SB_PORT:-}" \
    --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg policy "${SB_OUTBOUND_POLICY:-default}" \
    --arg trust "${SB_TROJAN_CLIENT_TRUST:-system}" \
    --arg server_name "$(jq -r '.server_name // empty' <<< "${tls_json}")" \
    --arg transport_type "${transport_type}" \
    --argjson tls_enabled "${tls_enabled}" \
    --argjson user_count "${user_count}" \
    --argjson shareable "${shareable}" \
    '{
      protocol:"trojan",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,
      instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},
      user_count:$user_count,auth_enabled:($user_count > 0),tls_enabled:$tls_enabled,
      client_trust:$trust,transport_type:$transport_type,outbound_policy:$policy,
      shareable:$shareable,client_exportable:true
    } + (if $server_name == "" then {} else {server_name:$server_name} end)'
}

agent_trojan_link_json() (
  umask 077
  local server=${1:-} store_file snapshot end_snapshot instance_id links warnings='[]'
  local summary outbounds isolated_store link_result

  store_file=$(plain_proxy_structured_store_file trojan) || return 1
  snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}
  [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) ;;
    "") return 1 ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS} ;;
  esac
  summary=$(agent_trojan_node_json "${server}") || return 1
  link_result=$(build_trojan_subman_links_and_warnings_json "${server}" "${instance_id}") || return 1
  links=$(jq -c '.links' <<< "${link_result}") || return 1
  warnings=$(jq -c '.warnings' <<< "${link_result}") || return 1

  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  if ! jq --arg id "${instance_id}" \
      '. as $root | ($root.instances | map(select(.id == $id))) as $instances |
       $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${isolated_store}"; then
    return 1
  fi
  if ! outbounds=$(build_trojan_client_outbounds_from_store "${isolated_store}" "${server}"); then
    return 1
  fi
  end_snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  jq -cn --argjson summary "${summary}" --argjson links "${links}" \
    --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" \
    '$summary + {links:$links,outbounds:$outbounds,warnings:$warnings}'
)

agent_vmess_node_json() {
  local public_ip=${1:-$(get_public_ip)} server shareable=false tls_json transport_json tls_enabled transport_type user_count
  tls_json=${SB_VMESS_TLS_JSON:-}; transport_json=${SB_VMESS_TRANSPORT_JSON:-}
  [[ -n "${tls_json}" && -n "${transport_json}" ]] || return 1
  tls_enabled=$(jq -er 'if .enabled == true then "true" elif .enabled == false then "false" else empty end' <<< "${tls_json}") || return 1
  transport_type=$(jq -er '.type' <<< "${transport_json}") || return 1
  user_count=$(jq -er 'length' <<< "${SB_VMESS_AUTH_JSON:-[]}") || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) server=${public_ip} ;; *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;; esac
  if [[ -n "${server}" ]] && build_vmess_links_json "${server}" "${SB_INSTANCE_ID:-}" >/dev/null 2>&1; then shareable=true; fi
  jq -n --arg name "${SB_NODE_NAME:-VMess}" --arg id "${SB_INSTANCE_ID:-}" --arg tag "${SB_MIXED_INBOUND_TAG:-}" \
    --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg policy "${SB_OUTBOUND_POLICY:-default}" --arg trust "${SB_VMESS_CLIENT_TRUST:-system}" \
    --arg server_name "$(jq -r '.server_name // empty' <<< "${tls_json}")" --arg transport_type "${transport_type}" \
    --argjson tls_enabled "${tls_enabled}" --argjson user_count "${user_count}" --argjson shareable "${shareable}" \
    '{protocol:"vmess",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},user_count:$user_count,auth_enabled:($user_count>0),tls_enabled:$tls_enabled,client_trust:$trust,transport_type:$transport_type,outbound_policy:$policy,shareable:$shareable,client_exportable:true} + (if $server_name=="" then {} else {server_name:$server_name} end)'
}

agent_vmess_link_json() (
  umask 077
  local server=${1:-} store_file snapshot end_snapshot instance_id links outbounds isolated_store summary
  store_file=$(plain_proxy_structured_store_file vmess) || return 1
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}; [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) ;; "") return 1 ;; *) server=${SB_MIXED_LISTEN_ADDRESS} ;; esac
  summary=$(agent_vmess_node_json "${server}") || return 1
  links=$(build_vmess_links_json "${server}" "${instance_id}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_vmess_client_outbounds_from_store "${isolated_store}" "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  jq -cn --argjson summary "${summary}" --argjson links "${links}" --argjson outbounds "${outbounds}" --argjson warnings '[]' '$summary + {links:$links,outbounds:$outbounds,warnings:$warnings}'
)

agent_vless_plain_node_json() {
  local public_ip=${1:-$(get_public_ip)} server shareable=false tls_json transport_json tls_enabled transport_type user_count
  tls_json=${SB_VLESS_PLAIN_TLS_JSON:-}; transport_json=${SB_VLESS_PLAIN_TRANSPORT_JSON:-}
  [[ -n "${tls_json}" && -n "${transport_json}" ]] || return 1
  tls_enabled=$(jq -er 'if .enabled == true then "true" elif .enabled == false then "false" else empty end' <<< "${tls_json}") || return 1
  transport_type=$(jq -er '.type' <<< "${transport_json}") || return 1
  user_count=$(jq -er 'length' <<< "${SB_VLESS_PLAIN_AUTH_JSON:-[]}") || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) server=${public_ip} ;; *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;; esac
  if [[ -n "${server}" ]] && build_vless_plain_links_json "${server}" "${SB_INSTANCE_ID:-}" >/dev/null 2>&1; then shareable=true; fi
  jq -n --arg name "${SB_NODE_NAME:-VLESS}" --arg id "${SB_INSTANCE_ID:-}" --arg tag "${SB_MIXED_INBOUND_TAG:-}" \
    --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg policy "${SB_OUTBOUND_POLICY:-default}" --arg trust "${SB_VLESS_PLAIN_CLIENT_TRUST:-system}" \
    --arg server_name "$(jq -r '.server_name // empty' <<< "${tls_json}")" --arg transport_type "${transport_type}" \
    --argjson tls_enabled "${tls_enabled}" --argjson user_count "${user_count}" --argjson shareable "${shareable}" \
    '{protocol:"vless-plain",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},user_count:$user_count,auth_enabled:($user_count>0),tls_enabled:$tls_enabled,client_trust:$trust,transport_type:$transport_type,outbound_policy:$policy,shareable:$shareable,client_exportable:true} + (if $server_name=="" then {} else {server_name:$server_name} end)'
}

agent_vless_plain_link_json() (
  umask 077
  local server=${1:-} store_file snapshot end_snapshot instance_id links outbounds isolated_store summary
  store_file=$(plain_proxy_structured_store_file vless-plain) || return 1
  snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}; [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) ;; "") return 1 ;; *) server=${SB_MIXED_LISTEN_ADDRESS} ;; esac
  summary=$(agent_vless_plain_node_json "${server}") || return 1
  links=$(build_vless_plain_links_json "${server}" "${instance_id}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_vless_plain_client_outbounds_from_store "${isolated_store}" "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  jq -cn --argjson summary "${summary}" --argjson links "${links}" --argjson outbounds "${outbounds}" --argjson warnings '[]' '$summary + {links:$links,outbounds:$outbounds,warnings:$warnings}'
)

agent_anytls_node_json() {
  local public_ip=${1:-$(get_public_ip)} server tls_json tls_enabled user_count
  local client_trust tls_mode outbound_policy

  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  [[ "${SB_PROTOCOL}" == "anytls" ]] || return 1
  tls_json=${SB_ANYTLS_TLS_JSON:-}
  [[ -n "${tls_json}" ]] || return 1
  tls_enabled=$(jq -er 'if .enabled == true then "true" elif .enabled == false then "false" else empty end' <<< "${tls_json}") || return 1
  [[ "${tls_enabled}" == true ]] || return 1
  user_count=$(jq -er 'length' <<< "${SB_ANYTLS_AUTH_JSON:-[]}") || return 1
  client_trust=${SB_ANYTLS_CLIENT_TRUST:-system}
  [[ "${client_trust}" == certificate || "${client_trust}" == system ]] || return 1
  tls_mode=${SB_ANYTLS_TLS_MODE:-manual}
  [[ "${tls_mode}" == manual ]] || return 1
  outbound_policy=${SB_OUTBOUND_POLICY:-default}
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  [[ -n "${server}" ]] || return 1
  jq -n \
    --arg name "${SB_NODE_NAME:-AnyTLS}" \
    --arg id "${SB_INSTANCE_ID:-}" \
    --arg tag "${SB_MIXED_INBOUND_TAG:-}" \
    --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" \
    --arg port "${SB_PORT:-}" \
    --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg server "${server}" \
    --arg trust "${client_trust}" \
    --arg server_name "$(jq -r '.server_name' <<< "${tls_json}")" \
    --arg policy "${outbound_policy}" \
    --arg tls_mode "${tls_mode}" \
    --argjson user_count "${user_count}" \
    '{protocol:"anytls",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,
      instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},
      server:$server,user_count:$user_count,auth_enabled:($user_count>0),tls_enabled:true,
      server_name:$server_name,tls_mode:$tls_mode,client_trust:$trust,
      outbound_policy:$policy,shareable:false,client_exportable:true}'
}

agent_anytls_link_json() (
  umask 077
  local server=${1:-} store_file snapshot end_snapshot instance_id isolated_store summary outbounds warnings

  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file anytls) || return 1
  snapshot=$(structured_instance_store_snapshot_json anytls "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}
  [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${server:-$(get_public_ip)} ;;
    "") return 1 ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS} ;;
  esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_anytls_node_json "${server}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" \
    '. as $root | ($root.instances | map(select(.id == $id))) as $instances |
     $root | .default_instance_id=$id | .instances=$instances' \
    <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_anytls_client_outbounds_from_store "${isolated_store}" "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json anytls "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  warnings=$(jq -cn '[{code:"anytls_standard_uri_unavailable",message:"AnyTLS 当前没有可安全表达完整配置的标准分享 URI；请使用 sing-box outbound JSON。"}]') || return 1
  jq -cn --argjson summary "${summary}" --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" \
    '$summary + {links:{},outbounds:$outbounds,warnings:$warnings}'
)

build_hy2_uri_from_outbound() {
  local outbound=${1:-} name=${2:-Hysteria2} server port password sni query encoded
  [[ -n "${outbound}" ]] || return 1
  server=$(jq -er '.server' <<< "${outbound}") || return 1
  port=$(jq -er '.server_port' <<< "${outbound}") || return 1
  password=$(jq -er '.password' <<< "${outbound}") || return 1
  sni=$(jq -er '.tls.server_name' <<< "${outbound}") || return 1
  [[ -n "${password}" && -n "${sni}" ]] || return 1
  encoded=$(jq -rn --arg value "${password}" '$value|@uri') || return 1
  query="sni=$(jq -rn --arg value "${sni}" '$value|@uri')"
  if jq -e '.obfs? | type == "object"' <<< "${outbound}" >/dev/null 2>&1; then
    query="${query}&obfs=$(jq -rn --arg value "$(jq -er '.obfs.type' <<< "${outbound}")" '$value|@uri')"
    query="${query}&obfs-password=$(jq -rn --arg value "$(jq -er '.obfs.password' <<< "${outbound}")" '$value|@uri')"
  fi
  printf 'hy2://%s@%s:%s?%s#%s' "${encoded}" "$(format_share_host "${server}")" "${port}" "${query}" "$(jq -rn --arg value "${name}" '$value|@uri')"
}

agent_hy2_node_json() {
  local public_ip=${1:-$(get_public_ip)} server tls_json user_count shareable=false
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  [[ "${SB_PROTOCOL}" == "hy2" ]] || return 1
  plain_proxy_structured_state_active hy2 || return 1
  tls_json=${SB_HY2_TLS_JSON:-}
  [[ -n "${tls_json}" ]] || return 1
  jq -e '.enabled == true and .server_name != ""' <<< "${tls_json}" >/dev/null || return 1
  user_count=$(jq -er 'length' <<< "${SB_HY2_AUTH_JSON:-[]}") || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  [[ -n "${server}" ]] || return 1
  if [[ "${SB_HY2_CLIENT_TRUST:-system}" == system ]]; then shareable=true; fi
  jq -n --arg name "${SB_NODE_NAME:-Hysteria2}" --arg id "${SB_INSTANCE_ID:-}" \
    --arg tag "${SB_MIXED_INBOUND_TAG:-}" --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" \
    --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg server "${server}" --arg server_name "$(jq -r '.server_name' <<< "${tls_json}")" \
    --arg tls_mode "${SB_HY2_TLS_MODE:-manual}" --arg trust "${SB_HY2_CLIENT_TRUST:-system}" --arg policy "${SB_OUTBOUND_POLICY:-default}" \
    --arg up "${SB_HY2_UP_MBPS:-}" --arg down "${SB_HY2_DOWN_MBPS:-}" \
    --argjson user_count "${user_count}" --argjson shareable "${shareable}" \
    --argjson obfs_enabled "$([[ "${SB_HY2_OBFS_ENABLED:-n}" == y ]] && printf true || printf false)" \
    '{protocol:"hysteria2",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},server:$server,user_count:$user_count,auth_enabled:true,tls_enabled:true,server_name:$server_name,tls_mode:$tls_mode,client_trust:$trust,outbound_policy:$policy,shareable:$shareable,client_exportable:true,obfs_enabled:$obfs_enabled,rate_limit:{up_mbps:(if $up=="" then null else ($up|tonumber) end),down_mbps:(if $down=="" then null else ($down|tonumber) end)}}'
}

agent_hy2_link_json() (
  local node_name_digests
  umask 077
  local public_ip=${1:-$(get_public_ip)} store_file snapshot end_snapshot instance_id server outbounds links='{}' warnings='[]' summary key uri certificate_path compatibility_warnings
  local instance user_name node_name address_label outbound
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file hy2) || return 1
  snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}
  [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || return 1
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    "") return 1 ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS} ;;
  esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_hy2_node_json "${public_ip}") || return 1
  certificate_path=$(jq -r --arg id "${instance_id}" '.instances[] | select(.id == $id) | .tls.certificate_path // ""' <<< "${snapshot}") || return 1
  compatibility_warnings=$(hy2_ed25519_share_warning_json "${certificate_path}") || return 1
  warnings=$(jq -cn --argjson existing "${warnings}" --argjson additions "${compatibility_warnings}" \
    --arg instance_id "${instance_id}" \
    '$existing + ($additions | map(. + {instance_id:$instance_id}))') || return 1
  outbounds=$(build_client_hy2_outbounds "${public_ip}") || return 1
  outbounds=$(jq -cs --arg prefix "hy2-${instance_id}-user-" 'map(select(.tag | startswith($prefix)))' <<< "${outbounds}") || return 1
  jq -e 'length > 0' <<< "${outbounds}" >/dev/null || return 1
  if [[ "${SB_HY2_CLIENT_TRUST:-system}" == system ]]; then
    while IFS= read -r outbound; do
      key=$(jq -er '.tag' <<< "${outbound}") || return 1
      user_name=$(jq -er --arg key "${key}" '
        .id as $id |
        [.authentication.users[] | select(("hy2-" + $id + "-user-" + (.name | @base64)) == $key)] |
        select(length == 1) | .[0].name' <<< "${instance}") || return 1
      address_label=$(node_display_address_label "$(jq -r '.listen.address' <<< "${instance}")" "$(jq -r '.server' <<< "${outbound}")") || return 1
      node_name=$(structured_node_display_name hy2 "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
      uri=$(build_hy2_uri_from_outbound "${outbound}" "${node_name}") || return 1
      links=$(jq -cn --argjson links "${links}" --arg key "${key}" --arg uri "${uri}" '$links + {($key):$uri}') || return 1
    done < <(jq -c '.[]' <<< "${outbounds}")
  else
    warnings=$(jq -cn --argjson existing "${warnings}" '$existing + [{code:"hy2_uri_certificate_trust_unavailable",message:"Hysteria2 certificate trust 无法由标准 URI 表达；请使用完整客户端 outbound JSON。"}]') || return 1
  fi
  if jq -e --arg id "${instance_id}" '.instances[] | select(.id == $id) | (.bandwidth.up_mbps != null or .bandwidth.down_mbps != null or .masquerade != "")' <<< "${snapshot}" >/dev/null 2>&1; then
    warnings=$(jq -cn --argjson warnings "${warnings}" '$warnings + [{code:"hy2_uri_partial_options",message:"Hysteria2 带宽限制或 masquerade 无法由标准 URI 完整表达；请使用完整客户端 outbound JSON。"}]') || return 1
  fi
  end_snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  jq -cn --argjson summary "${summary}" --argjson links "${links}" --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" '$summary + {links:$links,outbounds:$outbounds,warnings:$warnings}'
)

agent_snell_node_json() {
  local public_ip=${1:-$(get_public_ip)} server user_count version obfs_mode mode
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" && "${SB_PROTOCOL}" == snell ]] || return 1
  plain_proxy_structured_state_active snell || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  [[ -n "${server}" ]] || return 1
  user_count=$(jq -er 'length' <<< "${SB_SNELL_USER_JSON:-[]}") || return 1
  version=${SB_SNELL_VERSION:-6}; obfs_mode=${SB_SNELL_OBFS_MODE:-}; mode=${SB_SNELL_MODE:-}
  jq -n --arg name "${SB_NODE_NAME:-Snell}" --arg id "${SB_INSTANCE_ID:-}" --arg tag "${SB_MIXED_INBOUND_TAG:-}" \
    --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg server "${server}" --argjson version "${version}" --arg obfs_mode "${obfs_mode}" --arg mode "${mode}" \
    --arg policy "${SB_OUTBOUND_POLICY:-default}" --argjson user_count "${user_count}" \
    '{protocol:"snell",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},server:$server,user_count:$user_count,auth_enabled:true,version:$version,obfs_mode:$obfs_mode,mode:$mode,udp_via_tcp_packet_api:true,outbound_policy:$policy,shareable:false,client_exportable:true}'
}

agent_snell_link_json() (
  umask 077
  local public_ip=${1:-$(get_public_ip)} store_file snapshot end_snapshot instance_id server isolated_store summary outbounds warnings
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file snell) || return 1
  snapshot=$(structured_instance_store_snapshot_json snell "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}; [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    "") return 1 ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS} ;;
  esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_snell_node_json "${public_ip}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_client_snell_outbounds "${server}" "${isolated_store}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json snell "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  warnings=$(jq -cn '[{code:"snell_standard_uri_unavailable",message:"Snell 当前没有可安全表达版本、obfs/shaping 与用户 key 的标准分享 URI；请使用 sing-box outbound JSON。"}]') || return 1
  jq -cn --argjson summary "${summary}" --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" '$summary + {links:{},outbounds:$outbounds,warnings:$warnings}'
)

agent_tuic_node_json() {
  local public_ip=${1:-$(get_public_ip)} server tls_json user_count shareable=false
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" && "${SB_PROTOCOL}" == tuic ]] || return 1
  plain_proxy_structured_state_active tuic || return 1
  tls_json=${SB_TUIC_TLS_JSON:-}
  [[ -n "${tls_json}" ]] || return 1
  jq -e '.enabled == true and .server_name != ""' <<< "${tls_json}" >/dev/null || return 1
  user_count=$(jq -er 'length' <<< "${SB_TUIC_AUTH_JSON:-[]}") || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  [[ -n "${server}" ]] || return 1
  jq -n \
    --arg name "${SB_NODE_NAME:-TUIC}" --arg id "${SB_INSTANCE_ID:-}" \
    --arg tag "${SB_MIXED_INBOUND_TAG:-}" --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" \
    --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg server "${server}" --arg server_name "$(jq -r '.server_name' <<< "${tls_json}")" \
    --arg trust "${SB_TUIC_CLIENT_TRUST:-system}" --arg cc "${SB_TUIC_CONGESTION_CONTROL:-bbr}" \
    --arg relay "${SB_TUIC_UDP_RELAY_MODE:-}" --arg auth_timeout "${SB_TUIC_AUTH_TIMEOUT_SECONDS:-0}" \
    --arg heartbeat "${SB_TUIC_HEARTBEAT_SECONDS:-0}" \
    --arg policy "${SB_OUTBOUND_POLICY:-default}" \
    --argjson user_count "${user_count}" \
    --argjson shareable "${shareable}" \
    --argjson zero_rtt "$([[ "${SB_TUIC_ZERO_RTT_HANDSHAKE:-n}" == y ]] && printf true || printf false)" \
    --argjson udp_over_stream "$([[ "${SB_TUIC_UDP_OVER_STREAM:-n}" == y ]] && printf true || printf false)" \
    '{protocol:"tuic",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber),network:["udp"]},server:$server,user_count:$user_count,auth_enabled:true,tls_enabled:true,server_name:$server_name,tls_mode:"manual",client_trust:$trust,congestion_control:$cc,auth_timeout_seconds:($auth_timeout|tonumber),heartbeat_seconds:($heartbeat|tonumber),udp_relay_mode:$relay,udp_over_stream:$udp_over_stream,zero_rtt_handshake:$zero_rtt,outbound_policy:$policy,shareable:$shareable,client_exportable:true}'
}

agent_tuic_link_json() (
  umask 077
  local public_ip=${1:-$(get_public_ip)} store_file snapshot end_snapshot instance_id server isolated_store summary outbounds warnings
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file tuic) || return 1
  snapshot=$(structured_instance_store_snapshot_json tuic "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}
  [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    "") return 1 ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS} ;;
  esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_tuic_node_json "${public_ip}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" \
    '. as $root | ($root.instances | map(select(.id == $id))) as $instances |
     $root | .default_instance_id=$id | .instances=$instances' \
    <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_client_tuic_outbounds "${server}" "${isolated_store}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json tuic "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  warnings=$(jq -cn '[{code:"tuic_standard_uri_unavailable",message:"TUIC 当前没有可安全表达 TLS、QUIC 与多用户选项的标准分享 URI；请使用 sing-box outbound JSON。"}]') || return 1
  jq -cn --argjson summary "${summary}" --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" \
    '$summary + {links:{},outbounds:$outbounds,warnings:$warnings}'
)

agent_hysteria_node_json() {
  local public_ip=${1:-$(get_public_ip)} server tls_json user_count
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" && "${SB_PROTOCOL}" == hysteria ]] || return 1
  plain_proxy_structured_state_active hysteria || return 1
  tls_json=${SB_HYSTERIA_TLS_JSON:-}; [[ -n "${tls_json}" ]] || return 1
  jq -e '.enabled == true and .server_name != ""' <<< "${tls_json}" >/dev/null || return 1
  user_count=$(jq -er 'length' <<< "${SB_HYSTERIA_AUTH_JSON:-[]}") || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  [[ -n "${server}" ]] || return 1
  jq -n --arg name "${SB_NODE_NAME:-Hysteria}" --arg id "${SB_INSTANCE_ID:-}" --arg tag "${SB_MIXED_INBOUND_TAG:-}" --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" --arg server "${server}" --arg server_name "$(jq -r '.server_name' <<< "${tls_json}")" --arg trust "${SB_HYSTERIA_CLIENT_TRUST:-system}" --arg up "${SB_HYSTERIA_UP_MBPS:-}" --arg down "${SB_HYSTERIA_DOWN_MBPS:-}" --arg obfs "$([[ "${SB_HYSTERIA_OBFS_ENABLED:-n}" == y ]] && printf true || printf false)" --arg policy "${SB_OUTBOUND_POLICY:-default}" --argjson user_count "${user_count}" '{protocol:"hysteria",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber),network:["udp"]},server:$server,user_count:$user_count,auth_enabled:true,tls_enabled:true,server_name:$server_name,tls_mode:"manual",client_trust:$trust,bandwidth:{up_mbps:($up|tonumber),down_mbps:($down|tonumber)},obfs_enabled:($obfs|fromjson),outbound_policy:$policy,shareable:false,client_exportable:true}'
}

agent_hysteria_link_json() (
  umask 077
  local public_ip=${1:-$(get_public_ip)} store_file snapshot end_snapshot instance_id server isolated_store summary outbounds warnings
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file hysteria) || return 1
  snapshot=$(structured_instance_store_snapshot_json hysteria "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}; [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) server=${public_ip} ;; "") return 1 ;; *) server=${SB_MIXED_LISTEN_ADDRESS} ;; esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_hysteria_node_json "${public_ip}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" '. as $root | ($root.instances|map(select(.id==$id))) as $instances | $root|.default_instance_id=$id|.instances=$instances' <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_client_hysteria_outbounds "${server}" "${isolated_store}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json hysteria "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  warnings=$(jq -cn '[{code:"hysteria_standard_uri_unavailable",message:"Hysteria 当前没有可安全表达 TLS、QUIC、obfs 与多用户 auth_str 的标准分享 URI；请使用 sing-box outbound JSON。"}]') || return 1
  jq -cn --argjson summary "${summary}" --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" '$summary + {links:{},outbounds:$outbounds,warnings:$warnings}'
)

agent_naive_node_json() {
  local public_ip=${1:-$(get_public_ip)} server tls_json user_count network_json
  local trust quic cc insecure_concurrency stream_receive_window quic_session_receive_window
  local extra_headers_count extra_headers_json
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" && "${SB_PROTOCOL}" == naive ]] || return 1
  plain_proxy_structured_state_active naive || return 1
  tls_json=${SB_NAIVE_TLS_JSON:-}; [[ -n "${tls_json}" ]] || return 1
  jq -e '.enabled == true and (.server_name | type == "string" and length > 0)' <<< "${tls_json}" >/dev/null || return 1
  user_count=$(jq -er 'length' <<< "${SB_NAIVE_AUTH_JSON:-[]}") || return 1
  network_json=${SB_NAIVE_NETWORK_JSON:-'["tcp","udp"]'}
  jq -e 'type == "array" and length > 0 and all(.[]; . == "tcp" or . == "udp")' <<< "${network_json}" >/dev/null || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;;
  esac
  [[ -n "${server}" ]] || return 1
  trust=${SB_NAIVE_CLIENT_TRUST:-system}
  quic=$([[ "${SB_NAIVE_QUIC:-n}" == y ]] && printf true || printf false)
  cc=${SB_NAIVE_QUIC_CONGESTION_CONTROL:-bbr}
  insecure_concurrency=${SB_NAIVE_INSECURE_CONCURRENCY:-0}
  stream_receive_window=${SB_NAIVE_STREAM_RECEIVE_WINDOW:-}
  quic_session_receive_window=${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW:-}
  extra_headers_json=${SB_NAIVE_EXTRA_HEADERS_JSON:-}
  if [[ -n "${extra_headers_json}" ]]; then
    extra_headers_count=$(jq -er 'length' <<< "${extra_headers_json}") || return 1
  else
    extra_headers_count=0
  fi
  jq -n \
    --arg name "${SB_NODE_NAME:-NaiveProxy}" --arg id "${SB_INSTANCE_ID:-}" \
    --arg tag "${SB_MIXED_INBOUND_TAG:-}" --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" \
    --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" \
    --arg server "${server}" --arg server_name "$(jq -r '.server_name' <<< "${tls_json}")" \
    --arg trust "${trust}" --arg cc "${cc}" --arg stream_receive_window "${stream_receive_window}" \
    --arg quic_session_receive_window "${quic_session_receive_window}" \
    --arg runtime "with_naive_outbound+libcronet" --arg policy "${SB_OUTBOUND_POLICY:-default}" --argjson network "${network_json}" \
    --argjson user_count "${user_count}" --argjson quic "${quic}" \
    --argjson insecure_concurrency "${insecure_concurrency}" --argjson extra_headers_count "${extra_headers_count}" \
    '{protocol:"naive",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,
      instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber),network:$network},
      server:$server,user_count:$user_count,auth_enabled:true,tls_enabled:true,
      server_name:$server_name,tls_mode:"manual",client_trust:$trust,network:$network,
      quic:$quic,quic_congestion_control:$cc,insecure_concurrency:$insecure_concurrency,
      stream_receive_window:$stream_receive_window,quic_session_receive_window:$quic_session_receive_window,
      extra_headers_count:$extra_headers_count,outbound_runtime:$runtime,
      outbound_policy:$policy,shareable:false,client_exportable:true}'
}

agent_naive_link_json() (
  umask 077
  local public_ip=${1:-$(get_public_ip)} store_file snapshot end_snapshot instance_id server isolated_store summary outbounds warnings
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file naive) || return 1
  snapshot=$(structured_instance_store_snapshot_json naive "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}
  [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in
    0.0.0.0|::) server=${public_ip} ;;
    "") return 1 ;;
    *) server=${SB_MIXED_LISTEN_ADDRESS} ;;
  esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_naive_node_json "${public_ip}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" \
    '. as $root | ($root.instances | map(select(.id == $id))) as $instances |
     $root | .default_instance_id=$id | .instances=$instances' \
    <<< "${snapshot}" > "${isolated_store}" || return 1
  outbounds=$(build_client_naive_outbounds "${server}" "${isolated_store}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json naive "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -sc '.' <<< "${outbounds}") || return 1
  warnings=$(jq -cn '[
    {code:"naive_standard_uri_unavailable",message:"NaiveProxy 当前没有可安全表达完整 TLS、HTTP/2/QUIC 与多用户配置的标准分享 URI；请使用完整客户端 outbound JSON。"},
    {code:"naive_libcronet_required",message:"NaiveProxy 客户端 outbound 需要带 with_naive_outbound 的 sing-box，并在运行时加载 libcronet.so；当前 Agent 不能证明运行库已部署。"}
  ]') || return 1
  jq -cn --argjson summary "${summary}" --argjson outbounds "${outbounds}" --argjson warnings "${warnings}" \
    '$summary + {links:{},outbounds:$outbounds,warnings:$warnings}'
)

agent_shadowtls_node_json() {
  local public_ip=${1:-$(get_public_ip)} server version user_count handshake wildcard strict trust
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" && "${SB_PROTOCOL}" == shadowtls ]] || return 1
  plain_proxy_structured_state_active shadowtls || return 1
  version=${SB_SHADOWTLS_VERSION:-3}
  user_count=$(jq -er 'length' <<< "${SB_SHADOWTLS_AUTH_JSON:-[]}") || return 1
  handshake=$(jq -er '.server' <<< "${SB_SHADOWTLS_HANDSHAKE_JSON:-}") || return 1
  wildcard=${SB_SHADOWTLS_WILDCARD_SNI:-off}; strict=$([[ "${SB_SHADOWTLS_STRICT_MODE:-n}" == y ]] && printf true || printf false)
  trust=${SB_SHADOWTLS_CLIENT_TRUST:-system}
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) server=${public_ip} ;; *) server=${SB_MIXED_LISTEN_ADDRESS:-} ;; esac
  [[ -n "${server}" ]] || return 1
  jq -n --arg name "${SB_NODE_NAME:-ShadowTLS}" --arg id "${SB_INSTANCE_ID:-}" --arg tag "${SB_MIXED_INBOUND_TAG:-}" --arg address "${SB_MIXED_LISTEN_ADDRESS:-}" --arg port "${SB_PORT:-}" --arg revision "${SB_MIXED_STORE_REVISION:-0}" --arg server "${server}" --arg handshake_server "${handshake}" --arg trust "${trust}" --arg wildcard "${wildcard}" --arg policy "${SB_OUTBOUND_POLICY:-default}" --arg detour "${SB_SHADOWTLS_DETOUR_TAG:-shadowtls-inner-${SB_INSTANCE_ID:-}}" --argjson version "${version}" --argjson user_count "${user_count}" --argjson strict "${strict}" '{protocol:"shadowtls",name:$name,port:($port|tonumber),instance_id:$id,tag:$tag,instance_revision:($revision|tonumber),listen:{address:$address,port:($port|tonumber)},server:$server,version:$version,handshake_server:$handshake_server,user_count:(if $version == 3 then $user_count else 1 end),auth_enabled:($version != 1),wildcard_sni:$wildcard,strict_mode:$strict,detour_tag:$detour,client_trust:$trust,outbound_policy:$policy,shareable:false,client_exportable:true}'
}

agent_shadowtls_link_json() (
  umask 077
  local public_ip=${1:-$(get_public_ip)} store_file snapshot end_snapshot instance_id server isolated_store summary bundle_json outbounds primary_tags warnings
  [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] || return 1
  store_file=$(plain_proxy_structured_store_file shadowtls) || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowtls "${store_file}") || return 1
  instance_id=${SB_INSTANCE_ID:-}; [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null || return 1
  [[ "$(jq -r '.revision|tostring' <<< "${snapshot}")" == "${SB_MIXED_STORE_REVISION:-}" ]] || return 1
  case "${SB_MIXED_LISTEN_ADDRESS:-}" in 0.0.0.0|::) server=${public_ip} ;; "") return 1 ;; *) server=${SB_MIXED_LISTEN_ADDRESS} ;; esac
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  summary=$(agent_shadowtls_node_json "${public_ip}") || return 1
  isolated_store=$(mktemp) || return 1
  trap 'rm -f -- "${isolated_store}"' EXIT
  jq --arg id "${instance_id}" '. as $root | ($root.instances|map(select(.id==$id))) as $instances | $root|.default_instance_id=$id|.instances=$instances' <<< "${snapshot}" > "${isolated_store}" || return 1
  bundle_json=$(build_client_shadowtls_bundle_json "${server}" "${isolated_store}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json shadowtls "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  outbounds=$(jq -c '.outbounds' <<< "${bundle_json}") || return 1
  primary_tags=$(jq -c '.primary_tags' <<< "${bundle_json}") || return 1
  warnings=$(jq -cn '[{code:"shadowtls_standard_uri_unavailable",message:"ShadowTLS 是 TLS 包装层组合协议，当前没有可安全表达握手映射、detour 与版本参数的标准分享 URI；请使用完整客户端 outbound JSON。"}]') || return 1
  if [[ "${SB_SHADOWTLS_CLIENT_TRUST:-system}" == certificate ]]; then
    warnings=$(jq -cn --argjson warnings "${warnings}" '$warnings + [{code:"shadowtls_uri_certificate_trust_unavailable",message:"ShadowTLS certificate trust 无法由标准 URI 表达；请使用完整客户端 outbound JSON。"}]') || return 1
  fi
  jq -cn --argjson summary "${summary}" --argjson outbounds "${outbounds}" --argjson primary_tags "${primary_tags}" --argjson warnings "${warnings}" '$summary + {links:{},outbounds:$outbounds,primary_outbound_tags:$primary_tags,warnings:$warnings}'
)

agent_node_summary_json_for_current_protocol() {
  local protocol api_protocol public_ip shareable="true" client_exportable="false"
  local auth_enabled="false" server_name="" tls_enabled="false" http_tls_json
  local node_name instance_id="" inbound_tag="" listen_address="" instance_revision="0" rate_up="" rate_down="" outbound_policy=""
  local tls_mode="" acme_mode="" obfs_enabled="false"

  protocol=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  api_protocol=$(agent_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  public_ip=${1:-$(get_public_ip)}
  if [[ "${protocol}" == shadowsocks ]]; then agent_shadowsocks_node_json; return $?; fi
  if [[ "${protocol}" == trojan ]]; then agent_trojan_node_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == vmess ]]; then agent_vmess_node_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == vless-plain ]]; then agent_vless_plain_node_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == anytls && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active anytls; then
    agent_anytls_node_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == hy2 && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; then
    agent_hy2_node_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == snell && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active snell; then
    agent_snell_node_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == tuic && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active tuic; then
    agent_tuic_node_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == hysteria && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hysteria; then
    agent_hysteria_node_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == naive && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active naive; then
    agent_naive_node_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == shadowtls && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active shadowtls; then
    agent_shadowtls_node_json "${public_ip}"; return $?
  fi

  node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "") || return 1

  case "${protocol}" in
    vless-reality)
      client_exportable="true"
      server_name="${SB_SNI}"
      instance_id="${SB_VLESS_INSTANCE_ID:-main}"
      rate_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      rate_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      outbound_policy="${SB_OUTBOUND_POLICY:-default}"
      ;;
    mixed|socks)
      client_exportable="true"
      [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]] && auth_enabled="true"
      instance_id="${SB_MIXED_INSTANCE_ID:-}"
      inbound_tag="${SB_MIXED_INBOUND_TAG:-}"
      listen_address="${SB_MIXED_LISTEN_ADDRESS:-}"
      instance_revision="${SB_MIXED_STORE_REVISION:-0}"
      ;;
    http)
      client_exportable="true"
      [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]] && auth_enabled="true"
      instance_id="${SB_MIXED_INSTANCE_ID:-}"
      inbound_tag="${SB_MIXED_INBOUND_TAG:-}"
      listen_address="${SB_MIXED_LISTEN_ADDRESS:-}"
      instance_revision="${SB_MIXED_STORE_REVISION:-0}"
      http_tls_json=${SB_HTTP_TLS_JSON:-}
      [[ -n "${http_tls_json}" ]] || return 1
      tls_enabled=$(jq -er 'if .enabled == true then "true" elif .enabled == false then "false" else empty end' <<< "${http_tls_json}") || return 1
      [[ "${tls_enabled}" == true ]] && shareable="false"
      ;;
    hy2)
      client_exportable="true"
      server_name="${SB_HY2_DOMAIN:-${public_ip}}"
      rate_up="${SB_HY2_UP_MBPS:-}"
      rate_down="${SB_HY2_DOWN_MBPS:-}"
      tls_mode="${SB_HY2_TLS_MODE:-}"
      acme_mode="${SB_HY2_ACME_MODE:-}"
      [[ "${SB_HY2_OBFS_ENABLED:-n}" == "y" ]] && obfs_enabled="true"
      ;;
    anytls)
      client_exportable="true"
      server_name="${SB_ANYTLS_DOMAIN:-${public_ip}}"
      tls_mode="${SB_ANYTLS_TLS_MODE:-}"
      acme_mode="${SB_ANYTLS_ACME_MODE:-}"
      ;;
    *)
      shareable="false"
      ;;
  esac

  jq -n \
    --arg protocol "${api_protocol}" \
    --arg name "${node_name}" \
    --arg port "${SB_PORT}" \
    --arg server_name "${server_name}" \
    --arg instance_id "${instance_id}" \
    --arg inbound_tag "${inbound_tag}" \
    --arg listen_address "${listen_address}" \
    --arg instance_revision "${instance_revision}" \
    --arg rate_up "${rate_up}" \
    --arg rate_down "${rate_down}" \
    --arg outbound_policy "${outbound_policy}" \
    --arg tls_mode "${tls_mode}" \
    --arg acme_mode "${acme_mode}" \
    --argjson obfs_enabled "${obfs_enabled}" \
    --argjson shareable "${shareable}" \
    --argjson client_exportable "${client_exportable}" \
    --argjson auth_enabled "${auth_enabled}" \
    --argjson tls_enabled "${tls_enabled}" \
    '{
      "protocol": $protocol,
      "name": $name,
      "port": ($port | tonumber),
      "shareable": $shareable,
      "client_exportable": $client_exportable
    }
    + (if $server_name != "" then {"server_name": $server_name} else {} end)
    + (if ($protocol == "mixed" or $protocol == "socks" or $protocol == "http") then {"auth_enabled": $auth_enabled} else {} end)
    + (if ($protocol == "mixed" or $protocol == "socks" or $protocol == "http") then {"instance_revision": ($instance_revision | tonumber)} else {} end)
    + (if ($protocol == "http") then {"tls_enabled": $tls_enabled} else {} end)
    + (if ($protocol == "mixed" or $protocol == "socks" or $protocol == "http") and $instance_id != "" then {
        "instance_id": $instance_id,
        "tag": $inbound_tag,
        "listen": {"address": $listen_address, "port": ($port | tonumber)}
      } else {} end)
    + (if $protocol == "vless-reality" then {
        "instance_id": $instance_id,
        "rate_limit": {
          "up_mbps": (if $rate_up == "" then null else (try ($rate_up | tonumber) catch null) end),
          "down_mbps": (if $rate_down == "" then null else (try ($rate_down | tonumber) catch null) end)
        },
        "outbound_policy": $outbound_policy
      } else {} end)
    + (if $protocol == "hysteria2" then {
        "rate_limit": {
          "up_mbps": (if $rate_up == "" then null else (try ($rate_up | tonumber) catch null) end),
          "down_mbps": (if $rate_down == "" then null else (try ($rate_down | tonumber) catch null) end)
        },
        "tls_mode": $tls_mode,
        "acme_mode": (if $tls_mode == "acme" then $acme_mode else null end),
        "obfs_enabled": $obfs_enabled
      } else {} end)
    + (if $protocol == "anytls" then {
        "tls_mode": $tls_mode,
        "acme_mode": (if $tls_mode == "acme" then $acme_mode else null end)
      } else {} end)'
}

agent_link_json_for_current_protocol() {
  local protocol api_protocol public_ip link_json outbound_json raw_link
  local address_label
  local node_name instance_id="" inbound_tag="" listen_address="" mixed_link_address="" instance_revision="0" rate_up="" rate_down="" outbound_policy="" http_tls_json http_tls_enabled
  local compatibility_warnings_json='[]' share_warnings

  protocol=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  api_protocol=$(agent_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  public_ip=${1:-$(get_public_ip)}
  if [[ "${protocol}" == shadowsocks ]]; then agent_shadowsocks_link_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == trojan ]]; then agent_trojan_link_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == vmess ]]; then agent_vmess_link_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == vless-plain ]]; then agent_vless_plain_link_json "${public_ip}"; return $?; fi
  if [[ "${protocol}" == anytls && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active anytls; then
    agent_anytls_link_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == hy2 && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; then
    agent_hy2_link_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == snell && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active snell; then
    agent_snell_link_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == tuic && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active tuic; then
    agent_tuic_link_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == hysteria && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hysteria; then
    agent_hysteria_link_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == naive && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active naive; then
    agent_naive_link_json "${public_ip}"; return $?
  fi
  if [[ "${protocol}" == shadowtls && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active shadowtls; then
    agent_shadowtls_link_json "${public_ip}"; return $?
  fi
  if [[ "${public_ip}" == *:* ]]; then
    address_label="IPv6"
  elif [[ "${public_ip}" == *.* ]]; then
    address_label="IPv4"
  else
    address_label=""
  fi
  node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "${address_label}") || return 1

  case "${protocol}" in
    vless-reality)
      instance_id="${SB_VLESS_INSTANCE_ID:-main}"
      rate_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      rate_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      outbound_policy="${SB_OUTBOUND_POLICY:-default}"
      raw_link=$(build_vless_link "${public_ip}" "${address_label}") || return 1
      link_json=$(jq -n --arg vless "${raw_link}" '{"vless": $vless}') || return 1
      ;;
    mixed)
      instance_id="${SB_MIXED_INSTANCE_ID:-}"
      inbound_tag="${SB_MIXED_INBOUND_TAG:-}"
      listen_address="${SB_MIXED_LISTEN_ADDRESS:-}"
      instance_revision="${SB_MIXED_STORE_REVISION:-0}"
      mixed_link_address="${public_ip}"
      case "${listen_address}" in
        0.0.0.0|::) mixed_link_address="${public_ip}" ;;
        "") ;;
        *) mixed_link_address="${listen_address}" ;;
      esac
      link_json=$(build_plain_proxy_links_json mixed "${mixed_link_address}") || return 1
      ;;
    socks)
      instance_id="${SB_MIXED_INSTANCE_ID:-}"
      inbound_tag="${SB_MIXED_INBOUND_TAG:-}"
      listen_address="${SB_MIXED_LISTEN_ADDRESS:-}"
      instance_revision="${SB_MIXED_STORE_REVISION:-0}"
      mixed_link_address="${public_ip}"
      case "${listen_address}" in
        0.0.0.0|::) mixed_link_address="${public_ip}" ;;
        "") ;;
        *) mixed_link_address="${listen_address}" ;;
      esac
      link_json=$(build_plain_proxy_links_json socks "${mixed_link_address}") || return 1
      compatibility_warnings_json=$(jq -n '[{
        code: "socks_plaintext_transport",
        message: "SOCKS5 导出使用明文代理链路，认证信息与非加密业务可能被读取；仅用于可信网络或受保护隧道。UoT 即使启用也不提供加密。"
      }]')
      ;;
    http)
      instance_id="${SB_MIXED_INSTANCE_ID:-}"
      inbound_tag="${SB_MIXED_INBOUND_TAG:-}"
      listen_address="${SB_MIXED_LISTEN_ADDRESS:-}"
      instance_revision="${SB_MIXED_STORE_REVISION:-0}"
      mixed_link_address="${public_ip}"
      case "${listen_address}" in
        0.0.0.0|::) mixed_link_address="${public_ip}" ;;
        "") ;;
        *) mixed_link_address="${listen_address}" ;;
      esac
      http_tls_json=${SB_HTTP_TLS_JSON:-}
      [[ -n "${http_tls_json}" ]] || return 1
      http_tls_enabled=$(jq -er 'if .enabled == true then "true" elif .enabled == false then "false" else empty end' <<< "${http_tls_json}") || return 1
      [[ "${http_tls_enabled}" == true || "${http_tls_enabled}" == false ]] || return 1
      plain_proxy_http_auth_representable || return 1
      link_json=$(build_plain_proxy_links_json http "${mixed_link_address}") || return 1
      ;;
    hy2)
      raw_link=$(build_hy2_link "${public_ip}" "${address_label}") || return 1
      link_json=$(jq -n --arg hy2 "${raw_link}" '{"hy2": $hy2}') || return 1
      compatibility_warnings_json=$(build_hy2_compatibility_warnings_json "share")
      ;;
    anytls)
      outbound_json=$(build_anytls_outbound_example "${public_ip}")
      link_json='{}'
      ;;
    *)
      link_json='{}'
      ;;
  esac

  if [[ "${protocol}" == mixed || "${protocol}" == socks || "${protocol}" == http ]]; then
    share_warnings=$(plain_proxy_share_warnings_json "${protocol}") || return 1
    compatibility_warnings_json=$(jq -cn --argjson existing "${compatibility_warnings_json}" \
      --argjson share "${share_warnings}" '$existing + $share') || return 1
  fi

  jq -n \
    --arg protocol "${api_protocol}" \
    --arg name "${node_name}" \
    --arg port "${SB_PORT}" \
    --arg instance_id "${instance_id}" \
    --arg inbound_tag "${inbound_tag}" \
    --arg listen_address "${listen_address}" \
    --arg instance_revision "${instance_revision}" \
    --arg rate_up "${rate_up}" \
    --arg rate_down "${rate_down}" \
    --arg outbound_policy "${outbound_policy}" \
    --argjson links "${link_json}" \
    --argjson outbound "${outbound_json:-null}" \
    --argjson warnings "${compatibility_warnings_json}" \
    '{
      "protocol": $protocol,
      "name": $name,
      "port": ($port | tonumber),
      "links": $links
    }
    + (if $protocol == "vless-reality" then {
        "instance_id": $instance_id,
        "rate_limit": {
          "up_mbps": (if $rate_up == "" then null else (try ($rate_up | tonumber) catch null) end),
          "down_mbps": (if $rate_down == "" then null else (try ($rate_down | tonumber) catch null) end)
        },
        "outbound_policy": $outbound_policy
      } else {} end)
    + (if ($protocol == "mixed" or $protocol == "socks" or $protocol == "http") and $instance_id != "" then {
        "instance_id": $instance_id,
        "tag": $inbound_tag,
        "listen": {"address": $listen_address, "port": ($port | tonumber)}
      } else {} end)
    + (if ($protocol == "mixed" or $protocol == "socks" or $protocol == "http") then {"instance_revision": ($instance_revision | tonumber)} else {} end)
    + (if $outbound != null then {"outbound": $outbound} else {} end)
    + (if ($warnings | length) > 0 then {"warnings": $warnings} else {} end)'
}
