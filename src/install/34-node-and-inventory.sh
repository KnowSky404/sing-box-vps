
push_nodes_to_subman() {
  local original_protocol_state protocol instance_id
  local address_entry address_label public_ip address_entries
  local instance_attempted instance_synced instance_stacked_synced
  local synced_count skipped_count failed_count shadowsocks_skipped_count trojan_skipped_count vmess_skipped_count vless_plain_skipped_count hy2_skipped_count trojan_status
  local subman_supported_protocol_count
  local installed_protocols=()

  prompt_subman_config_if_needed || return 1
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

  mapfile -t installed_protocols < <(list_installed_protocols)
  if [[ ${#installed_protocols[@]} -eq 0 ]]; then
    print_warn "未发现已安装协议，无法推送 SubMan 节点。"
    printf 'SubMan 推送完成：已同步: 0，已跳过: 0，失败: 0\n'
    return 1
  fi

  for protocol in "${installed_protocols[@]}"; do
    protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || true)
    if [[ -z "${protocol}" ]]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! subman_type_for_protocol "${protocol}" >/dev/null; then
      print_warn "SubMan 暂不支持协议，已跳过: ${protocol}"
      skipped_count=$((skipped_count + 1))
      continue
    fi
    subman_supported_protocol_count=$((subman_supported_protocol_count + 1))

    if ! protocol_state_exists "${protocol}"; then
      print_warn "协议状态文件缺失，已跳过 SubMan 推送: ${protocol}"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! load_protocol_state "${protocol}"; then
      print_warn "加载协议状态失败，已跳过 SubMan 推送: ${protocol}"
      failed_count=$((failed_count + 1))
      continue
    fi

    if [[ "${protocol}" == "hy2" ]]; then
      print_hy2_compatibility_warnings "share"
    fi

    if [[ "${protocol}" == "vless-reality" ]]; then
      while IFS= read -r instance_id; do
        [[ -z "${instance_id}" ]] && continue
        instance_attempted=0
        instance_synced=0
        instance_stacked_synced=0
        if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
          record_subman_address_failure "${protocol}" "${instance_id}" n || return 1
          failed_count=$((failed_count + 1))
          continue
        fi
        while IFS= read -r address_entry; do
          [[ -z "${address_entry}" ]] && continue
          address_label=${address_entry%%|*}
          public_ip=${address_entry#*|}
          instance_attempted=$((instance_attempted + 1))
          if push_subman_protocol_instance "${protocol}" "${public_ip}" "${instance_id}" "n" "${address_label}"; then
            synced_count=$((synced_count + 1))
            instance_synced=$((instance_synced + 1))
            if [[ -n "$(network_stack_suffix_from_label "${address_label}")" ]]; then
              instance_stacked_synced=$((instance_stacked_synced + 1))
            fi
          else
            failed_count=$((failed_count + 1))
          fi
        done <<< "${address_entries}"
        if subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}" && \
          push_subman_legacy_protocol_key_cleanup "${protocol}" "${instance_id}" "n"; then
          :
        elif subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}"; then
          failed_count=$((failed_count + 1))
        fi
      done < <(list_vless_reality_instance_ids)
      continue
    fi

    if [[ "${protocol}" == "trojan" ]]; then
      trojan_status=0
      push_subman_trojan_protocol n || trojan_status=$?
      synced_count=$((synced_count + ${SUBMAN_TROJAN_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_TROJAN_SKIPPED:-0}))
      trojan_skipped_count=$((trojan_skipped_count + ${SUBMAN_TROJAN_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_TROJAN_FAILED:-0}))
      if (( trojan_status != 0 && ${SUBMAN_TROJAN_FAILED:-0} == 0 )); then
        failed_count=$((failed_count + 1))
      fi
      continue
    fi

    if [[ "${protocol}" == "vmess" ]]; then
      push_subman_vmess_protocol n || true
      synced_count=$((synced_count + ${SUBMAN_VMESS_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_VMESS_SKIPPED:-0}))
      vmess_skipped_count=$((vmess_skipped_count + ${SUBMAN_VMESS_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_VMESS_FAILED:-0}))
      continue
    fi

    if [[ "${protocol}" == "vless-plain" ]]; then
      push_subman_vless_plain_protocol n || true
      synced_count=$((synced_count + ${SUBMAN_VLESS_PLAIN_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_VLESS_PLAIN_SKIPPED:-0}))
      vless_plain_skipped_count=$((vless_plain_skipped_count + ${SUBMAN_VLESS_PLAIN_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_VLESS_PLAIN_FAILED:-0}))
      continue
    fi

    if [[ "${protocol}" == "hy2" ]] && [[ "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; then
      push_subman_hy2_protocol n || true
      synced_count=$((synced_count + ${SUBMAN_HY2_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_HY2_SKIPPED:-0}))
      hy2_skipped_count=$((hy2_skipped_count + ${SUBMAN_HY2_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_HY2_FAILED:-0}))
      continue
    fi

    if [[ "${protocol}" == "shadowsocks" ]]; then
      push_subman_shadowsocks_protocol n || true
      synced_count=$((synced_count + ${SUBMAN_SHADOWSOCKS_SYNCED:-0}))
      skipped_count=$((skipped_count + ${SUBMAN_SHADOWSOCKS_SKIPPED:-0}))
      shadowsocks_skipped_count=$((shadowsocks_skipped_count + ${SUBMAN_SHADOWSOCKS_SKIPPED:-0}))
      failed_count=$((failed_count + ${SUBMAN_SHADOWSOCKS_FAILED:-0}))
      continue
    fi

    if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
      record_subman_address_failure "${protocol}" "" n || return 1
      failed_count=$((failed_count + 1))
      continue
    fi
    while IFS= read -r address_entry; do
      [[ -z "${address_entry}" ]] && continue
      address_label=${address_entry%%|*}
      public_ip=${address_entry#*|}
      if push_subman_protocol_instance "${protocol}" "${public_ip}" "" "n" "${address_label}"; then
        synced_count=$((synced_count + 1))
      else
        failed_count=$((failed_count + 1))
      fi
    done <<< "${address_entries}"
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi

  if (( synced_count == 0 && shadowsocks_skipped_count == 0 && trojan_skipped_count == 0 && vmess_skipped_count == 0 && vless_plain_skipped_count == 0 && hy2_skipped_count == 0 && failed_count == 0 && subman_supported_protocol_count > 0 )); then
    log_warn "未获取到公网 IP，无法生成 SubMan 节点链接。"
    return 1
  fi

  printf 'SubMan 推送完成：已同步: %s，已跳过: %s，失败: %s\n' "${synced_count}" "${skipped_count}" "${failed_count}"

  if (( synced_count == 0 || failed_count > 0 )); then
    return 1
  fi
}

show_node_info_action_menu() {
  while true; do
    echo
    render_left_aligned_page_header "节点与订阅" "选择要执行的节点信息操作"
    render_menu_group_start "操作选项"
    render_menu_item "1" "查看连接链接 / 二维码"
    render_menu_item "2" "推送节点到 SubMan"
    render_menu_item "3" "设置或修改 SubMan 连接"
    render_menu_item "4" "设置新实例的主机显示标签"
    echo "0. 返回"
    node_info_choice=$(prompt_choice "请选择 [0-4]: " 0 4 "")

    case "${node_info_choice}" in
      1) show_connection_info_menu ;;
      2) push_nodes_to_subman || true ;;
      3) configure_subman_interactive || true ;;
      4) configure_node_naming_interactive || true ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

view_node_info() {
  log_info "正在从配置文件中读取节点信息..."
  load_current_config_state
  show_node_info_action_menu
}

prompt_singbox_version() {
  local input_version normalized_version

  while true; do
    read -rp "版本 (默认 ${SB_SUPPORT_MAX_VERSION}，可输入 latest 或 x.y.z): " input_version
    if normalized_version=$(normalize_singbox_version_input "${input_version}"); then
      SB_VERSION="${normalized_version}"
      return 0
    fi
    log_warn "无效版本号: ${input_version}。请输入 latest、${SB_SUPPORT_MAX_VERSION} 或完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。"
  done
}

validate_live_inbound_inventory() {
  local config_file=$1 state_file=${2:-} allow_legacy_download_detour=${3:-false}
  local registry advanced_types component_state inventory_status allow_structured_hy2=false

  [[ -e "${config_file}" || -L "${config_file}" ]] || return 0
  [[ "${allow_legacy_download_detour}" == true || "${allow_legacy_download_detour}" == false ]] || return 1
  registry=$(protocol_registry_static_json) || return 1
  advanced_types=$(component_registry_inbound_types_json) || return 1
  if plain_proxy_structured_state_active hy2 >/dev/null 2>&1 ||
     plain_proxy_inactive_store_snapshot hy2 >/dev/null 2>&1; then
    allow_structured_hy2=true
  fi
  # This is an inventory gate, not a full field/route round-trip validator.
  # Accept only real core type names here; CLI aliases (especially vless)
  # cannot prove that a live inbound uses the corresponding managed preset.
  if ! inventory_status=$(jq -rs --argjson registry "${registry}" --argjson advanced_types "${advanced_types}" --argjson allow_structured_hy2 "${allow_structured_hy2}" '
    if length != 1 or (.[0] | type) != "object" then "invalid_document"
    else .[0] |
      if has("inbounds") and (.inbounds | type) != "array" then "invalid_inbounds"
      else (.inbounds // []) as $inbounds |
        if any($inbounds[]; type != "object" or (.type | type) != "string") then "invalid_inbounds"
        elif any($inbounds[]; has("tag") and (.tag | type) != "string") then "invalid_inbound_tag"
        else [
          $inbounds[] as $inbound |
          {inbound: $inbound, adapters:
            (if ($advanced_types | index($inbound.type)) != null then
               [{state_id:("advanced-" + $inbound.type), managed:true}]
             else
               [$registry[] |
                select(.role == "inbound" and .type == $inbound.type and
                  (if .type == "vless" then
                    ((.preset == "reality") == ($inbound.tls.reality? != null))
                  else true end))]
             end)}
        ] as $items |
          if any($items[]; (.adapters | length) == 0) then "unsupported_inbound_type"
          elif any($items[]; (.adapters | length) != 1) then "ambiguous_inbound_type"
          elif any($items[]; .adapters[0].preset == "reality" and
            ((.inbound.tls | type) != "object" or .inbound.tls.enabled != true or
             (.inbound.tls.reality | type) != "object" or .inbound.tls.reality.enabled != true))
            then "unsupported_inbound_preset"
          elif any($items | group_by(.adapters[0].state_id)[];
            length > 1 and .[0].adapters[0].managed != true and (
              (.[0].adapters[0].state_id == "hy2" and ($allow_structured_hy2 | not)) or
              (.[0].adapters[0].state_id != "hy2" and .[0].adapters[0].multi_instance != true)
            ))
            then "unsupported_inbound_multiplicity"
          elif ([$inbounds[].tag // empty | select(length > 0)] | length) !=
               ([$inbounds[].tag // empty | select(length > 0)] | unique | length)
            then "duplicate_inbound_tag"
          else "ok" end
        end
      end
    end
  ' "${config_file}" 2>/dev/null); then
    inventory_status="invalid_json_or_inventory"
  fi
  if [[ "${inventory_status}" != "ok" ]]; then
    printf '[ERROR] live_inbound_inventory: %s; 已保留配置和状态，禁止有损重建；请使用支持该入站的脚本或先备份并人工迁移。\n' "${inventory_status}" >&2
    return 1
  fi
  if ! managed_component_state_matches_live_config \
    "${config_file}" "${state_file}" "${allow_legacy_download_detour}"; then
    # Preserve the long-standing inventory error for an advanced inbound that
    # is present in the live config but has no owned component record. This
    # keeps takeover/rebuild fail-closed while distinguishing endpoint-only
    # ownership drift as a component-state error.
    if [[ -n "${state_file}" ]]; then
      if [[ -f "${state_file}" && ! -L "${state_file}" && -r "${state_file}" ]]; then
        component_state=$(jq -cS '.' "${state_file}" 2>/dev/null || printf '{}')
      elif [[ ! -e "${state_file}" ]]; then
        component_state=$(managed_component_state_default_json 2>/dev/null || printf '{}')
      else
        component_state='{}'
      fi
    else
      component_state=$(managed_component_state_json 2>/dev/null || printf '{}')
    fi
    if jq -e --argjson advanced_types "${advanced_types}" --argjson state "${component_state}" '
      any(.inbounds[]?; . as $inbound |
        ($advanced_types | index($inbound.type)) != null and
        (any($state.components[]?;
          .role == "inbound" and .type == $inbound.type and
          .tag == ($inbound.tag // "") and .enabled == true) | not))
    ' "${config_file}" >/dev/null 2>&1; then
      printf '[ERROR] live_inbound_inventory: unsupported_inbound_type; 已保留配置和状态，禁止有损重建；请使用支持该入站的脚本或先备份并人工迁移。\n' >&2
    else
      printf '[ERROR] live_component_inventory: advanced component state/config mismatch; 已保留配置和状态，禁止有损重建。\n' >&2
    fi
    return 1
  fi
  if ! jq -e '
    (.inbounds // []) as $inbounds |
    ([$inbounds[] | select(.type == "shadowtls")]) as $outers |
    ([$inbounds[] | select(.type == "mixed" and ((.tag // "") | startswith("shadowtls-inner-")))]) as $inners |
    (all($inners[]; . as $inner | ([ $outers[] | select(.detour == $inner.tag) ] | length) == 1)) and
    (all($outers[]; . as $outer | ($outer.detour | type == "string") and ([ $inners[] | select(.tag == $outer.detour) ] | length) == 1)) and
    (all($inbounds[]; (((.tag // "") | startswith("shadowtls-inner-")) | not) or (.type == "mixed")))
  ' "${config_file}" >/dev/null 2>&1; then
    printf '[ERROR] live_inbound_inventory: shadowtls_composite_invalid; 已保留配置和状态，禁止有损重建。\n' >&2
    return 1
  fi
}

list_config_protocols() {
  local allow_legacy_download_detour=${1:-false}
  validate_live_inbound_inventory \
    "${SINGBOX_CONFIG_FILE}" "" "${allow_legacy_download_detour}" || return 1
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 0

  local protocols=()
  local inbound_count inbound_index inbound_json protocol

  inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}") || return 1
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx]' "${SINGBOX_CONFIG_FILE}") || return 1
    if jq -e '.type | IN("direct","tun","redirect","tproxy","cloudflared")' <<< "${inbound_json}" >/dev/null 2>&1; then
      # Advanced inbounds have their own typed component state and must not
      # pollute the share-link protocol index.
      continue
    fi
    if manual_client_inbound_is_unmanaged "${inbound_json}"; then continue; fi
    protocol=$(config_inbound_protocol "${inbound_json}") || return 1

    if ! protocol_array_contains "${protocol}" ${protocols[@]+"${protocols[@]}"}; then
      protocols+=("${protocol}")
    fi
  done

  [[ ${#protocols[@]} -gt 0 ]] || return 0
  printf '%s\n' "${protocols[@]}"
}

find_config_inbound_index_by_protocol() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 1

  local target_protocol inbound_count inbound_index inbound_json protocol
  target_protocol=$(normalize_protocol_id "$1")

  inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}")
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx]' "${SINGBOX_CONFIG_FILE}")
    protocol=$(config_inbound_protocol "${inbound_json}" 2>/dev/null || true)
    if [[ "${protocol}" == "${target_protocol}" ]]; then
      printf '%s' "${inbound_index}"
      return 0
    fi
  done

  return 1
}

vless_reality_config_id_exists() {
  local target_id=$1
  local existing_id
  for existing_id in "${VLESS_CONFIG_INSTANCE_IDS[@]}"; do
    [[ "${existing_id}" == "${target_id}" ]] && return 0
  done
  return 1
}

reset_vless_reality_state_source_variables() {
  unset INSTALLED CONFIG_SCHEMA_VERSION DEFAULT_INSTANCE_ID INSTANCE_IDS
  unset REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY PRIVATE_KEY PUBLIC_KEY
  unset INSTANCE_ID INBOUND_TAG ENABLED NODE_NAME PORT UUID SNI SHORT_ID_1 SHORT_ID_2
  unset RATE_LIMIT_UP_MBPS RATE_LIMIT_DOWN_MBPS ALPN_MODE TCP_FAST_OPEN OUTBOUND_POLICY
}

load_vless_reality_existing_metadata() {
  local state_file instance_dir normalized_ids instance_id state_index tag existing_tag
  local state_schema
  local state_ids=()

  VLESS_REBUILD_STATE_SCHEMA="none"
  VLESS_REBUILD_STATE_DEFAULT_ID=""
  VLESS_REBUILD_STATE_PRIVATE_KEY=""
  VLESS_REBUILD_STATE_PUBLIC_KEY=""
  VLESS_REBUILD_STATE_IDS=()
  VLESS_REBUILD_STATE_TAGS=()
  VLESS_REBUILD_STATE_NODE_NAMES=()
  VLESS_REBUILD_STATE_RATE_UP=()
  VLESS_REBUILD_STATE_RATE_DOWN=()

  state_file=$(protocol_state_file "vless-reality") || return 1
  [[ -f "${state_file}" ]] || return 0

  reset_vless_reality_state_source_variables
  # shellcheck disable=SC1090
  source "${state_file}" || return 1
  state_schema="${CONFIG_SCHEMA_VERSION:-1}"

  case "${state_schema}" in
    1) ;;
    2) ;;
    *) return 1 ;;
  esac

  if [[ "${state_schema}" == "1" ]]; then
    VLESS_REBUILD_STATE_SCHEMA="1"
    VLESS_REBUILD_STATE_DEFAULT_ID="main"
    VLESS_REBUILD_STATE_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-${PRIVATE_KEY:-}}"
    VLESS_REBUILD_STATE_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-${PUBLIC_KEY:-}}"
    VLESS_REBUILD_STATE_NODE_NAMES=("$(normalize_node_name "${NODE_NAME:-}")")
    return 0
  fi

  VLESS_REBUILD_STATE_SCHEMA="2"
  VLESS_REBUILD_STATE_DEFAULT_ID="${DEFAULT_INSTANCE_ID:-}"
  VLESS_REBUILD_STATE_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
  VLESS_REBUILD_STATE_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
  normalized_ids=$(normalize_csv_list "${INSTANCE_IDS:-}")
  [[ -n "${normalized_ids}" ]] || return 1
  IFS=',' read -r -a state_ids <<< "${normalized_ids}"
  [[ ${#state_ids[@]} -gt 0 ]] || return 1
  [[ -n "${VLESS_REBUILD_STATE_DEFAULT_ID}" ]] || return 1

  instance_dir=$(vless_reality_instance_dir) || return 1
  for instance_id in "${state_ids[@]}"; do
    instance_id=$(trim_whitespace "${instance_id}")
    validate_vless_reality_instance_id "${instance_id}" || return 1
    if [[ ${#VLESS_REBUILD_STATE_IDS[@]} -gt 0 ]]; then
      for existing_tag in "${VLESS_REBUILD_STATE_IDS[@]}"; do
        [[ "${existing_tag}" == "${instance_id}" ]] && return 1
      done
    fi
    state_file="${instance_dir}/${instance_id}.env"
    [[ -f "${state_file}" ]] || return 1

    reset_vless_reality_state_source_variables
    # shellcheck disable=SC1090
    source "${state_file}" || return 1
    [[ "${INSTANCE_ID:-}" == "${instance_id}" && "${ENABLED:-}" == "1" ]] || return 1
    validate_optional_positive_integer "${RATE_LIMIT_UP_MBPS:-}" || return 1
    validate_optional_positive_integer "${RATE_LIMIT_DOWN_MBPS:-}" || return 1
    tag="${INBOUND_TAG:-}"
    if [[ -z "${tag}" ]]; then
      if [[ "${instance_id}" == "${VLESS_REBUILD_STATE_DEFAULT_ID}" ]]; then
        tag="vless-in"
      else
        tag="vless-reality-${instance_id}"
      fi
    fi
    [[ -n "${tag}" && "${tag}" != *$'\n'* ]] || return 1
    if [[ ${#VLESS_REBUILD_STATE_TAGS[@]} -gt 0 ]]; then
      for existing_tag in "${VLESS_REBUILD_STATE_TAGS[@]}"; do
        [[ "${existing_tag}" == "${tag}" ]] && return 1
      done
    fi

    VLESS_REBUILD_STATE_IDS+=("${instance_id}")
    VLESS_REBUILD_STATE_TAGS+=("${tag}")
    VLESS_REBUILD_STATE_NODE_NAMES+=("$(normalize_node_name "${NODE_NAME:-}")")
    VLESS_REBUILD_STATE_RATE_UP+=("${RATE_LIMIT_UP_MBPS:-}")
    VLESS_REBUILD_STATE_RATE_DOWN+=("${RATE_LIMIT_DOWN_MBPS:-}")
  done

  for state_index in "${!VLESS_REBUILD_STATE_IDS[@]}"; do
    [[ "${VLESS_REBUILD_STATE_IDS[${state_index}]}" == "${VLESS_REBUILD_STATE_DEFAULT_ID}" ]] && return 0
  done
  return 1
}

vless_reality_existing_state_index_for_tag() {
  local target_tag=$1 state_index matched_index=""

  [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]] || return 1
  for state_index in "${!VLESS_REBUILD_STATE_TAGS[@]}"; do
    if [[ "${VLESS_REBUILD_STATE_TAGS[${state_index}]}" == "${target_tag}" ]]; then
      [[ -z "${matched_index}" ]] || return 1
      matched_index="${state_index}"
    fi
  done
  [[ -n "${matched_index}" ]] || return 1
  printf '%s' "${matched_index}"
}

vless_reality_existing_state_index_for_id() {
  local target_id=$1 state_index

  [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]] || return 1
  for state_index in "${!VLESS_REBUILD_STATE_IDS[@]}"; do
    [[ "${VLESS_REBUILD_STATE_IDS[${state_index}]}" == "${target_id}" ]] || continue
    printf '%s' "${state_index}"
    return 0
  done
  return 1
}
