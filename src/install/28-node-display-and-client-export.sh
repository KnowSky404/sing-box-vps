
display_status_summary() {
  echo -e "\n${GREEN}运行状态摘要：${NC}"
  echo "-------------------------------------------------------------"
  echo -e "sing-box: $(systemctl is-active sing-box)"
  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    echo -e "Warp: 已开启 (${SB_WARP_ROUTE_MODE})"
  else
    echo -e "Warp: 未开启"
  fi
  echo -e "配置文件: ${SINGBOX_CONFIG_FILE}"
  echo "-------------------------------------------------------------"
}

main_menu_service_status_summary() {
  local active_state warp_state

  active_state=$(systemctl is-active sing-box 2>/dev/null || true)
  [[ -n "${active_state}" ]] || active_state="unknown"

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    printf '%s / 未读取到配置' "${active_state}"
    return 0
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]] && config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
    warp_state="Warp 已开启"
  else
    warp_state="Warp 未开启"
  fi
  printf '%s / %s' "${active_state}" "${warp_state}"
}

show_link_info() {
  local public_ip=$1
  local address_label=${2:-}
  local instance_id rate_summary
  local header_label

  if [[ "${SB_PROTOCOL}" == trojan ]]; then
    local trojan_material
    trojan_material=$(agent_trojan_link_json "${public_ip}") || return 1
    printf '\nTrojan 实例 %s（连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID}"
    jq -r '.links | to_entries[] | .key + "\n" + .value' <<< "${trojan_material}" || return 1
    jq -r '.warnings[].message' <<< "${trojan_material}" >&2 || return 1
    printf 'Trojan 客户端 outbound JSON：\n'
    jq '.outbounds' <<< "${trojan_material}"
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == vmess ]]; then
    local vmess_links
    vmess_links=$(build_vmess_links_json "${public_ip}" "${SB_INSTANCE_ID:-}") || return 1
    printf '\nVMess 实例 %s（连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
    jq -r 'to_entries[] | .key + "\n" + .value' <<< "${vmess_links}" || return 1
    printf 'VMess 客户端 outbound JSON：\n'
    build_client_vmess_outbounds "${public_ip}" | jq -s '.'
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == vless || "${SB_PROTOCOL}" == vless-plain ]]; then
    local vless_plain_links
    vless_plain_links=$(build_vless_plain_links_json "${public_ip}" "${SB_INSTANCE_ID:-}") || return 1
    printf '\nVLESS 实例 %s（连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
    jq -r 'to_entries[] | .key + "\n" + .value' <<< "${vless_plain_links}" || return 1
    printf 'VLESS 客户端 outbound JSON：\n'
    build_client_vless_plain_outbounds "${public_ip}" | jq -s '.'
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == shadowsocks ]]; then
    local ss_links ss_warnings
    ss_links=$(build_shadowsocks_links_json "${public_ip}") || return 1
    ss_warnings=$(shadowsocks_share_warnings_json) || return 1
    jq -r 'to_entries[] | .key+"\n"+.value' <<< "${ss_links}" || return 1
    jq -r '.[].message' <<< "${ss_warnings}" >&2 || return 1
    return 0
  fi

  header_label="${address_label}"
  if protocol_uses_domain_connection_material; then
    header_label=""
  fi

  if [[ -n "${header_label}" ]]; then
    echo -e "\n${YELLOW}连接链接 ${header_label}：${NC}"
  else
    echo -e "\n${YELLOW}连接链接：${NC}"
  fi

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    local rendered_count=0
    local fallback_instance_id="${SB_VLESS_INSTANCE_ID:-main}"
    local fallback_node_name="${SB_NODE_NAME:-}"
    local fallback_port="${SB_PORT:-}"
    local fallback_uuid="${SB_UUID:-}"
    local fallback_sni="${SB_SNI:-}"
    local fallback_short_id_1="${SB_SHORT_ID_1:-}"
    local fallback_short_id_2="${SB_SHORT_ID_2:-}"
    local fallback_rate_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
    local fallback_rate_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
    local fallback_outbound_policy="${SB_OUTBOUND_POLICY:-default}"
    migrate_vless_reality_state_to_instances_if_needed
    while IFS= read -r instance_id; do
      [[ -z "${instance_id}" ]] && continue
      load_vless_reality_protocol_state
      load_vless_reality_instance_state "${instance_id}" || continue
      rate_summary=$(vless_reality_rate_limit_summary "${SB_VLESS_RATE_LIMIT_UP_MBPS}" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}")
      echo "REALITY 实例"
      echo "实例 ID: ${SB_VLESS_INSTANCE_ID}"
      echo "端口: ${SB_PORT}"
      echo "限速: ${rate_summary}"
      build_vless_link "${public_ip}" "${address_label}" || return 1
      echo ""
      rendered_count=$((rendered_count + 1))
    done < <(list_vless_reality_instance_ids)
    load_vless_reality_protocol_state
    if ! load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" >/dev/null 2>&1 && (( rendered_count == 0 )) && [[ -n "${fallback_node_name}" && -n "${fallback_uuid}" ]]; then
      SB_VLESS_INSTANCE_ID="${fallback_instance_id}"
      SB_NODE_NAME="${fallback_node_name}"
      SB_PORT="${fallback_port}"
      SB_UUID="${fallback_uuid}"
      SB_SNI="${fallback_sni}"
      SB_SHORT_ID_1="${fallback_short_id_1}"
      SB_SHORT_ID_2="${fallback_short_id_2}"
      SB_VLESS_RATE_LIMIT_UP_MBPS="${fallback_rate_up}"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="${fallback_rate_down}"
      SB_OUTBOUND_POLICY="${fallback_outbound_policy}"
      rate_summary=$(vless_reality_rate_limit_summary "${SB_VLESS_RATE_LIMIT_UP_MBPS:-}" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}")
      echo "REALITY 实例"
      echo "实例 ID: ${SB_VLESS_INSTANCE_ID:-main}"
      echo "端口: ${SB_PORT}"
      echo "限速: ${rate_summary}"
      build_vless_link "${public_ip}" "${address_label}" || return 1
      echo ""
    fi
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active hy2; then
      local hy2_material
      hy2_material=$(agent_hy2_link_json "${public_ip}") || return 1
      printf '\nHysteria2 实例 %s（连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
      jq -r '.links | to_entries[] | .key + "\n" + .value' <<< "${hy2_material}" || return 1
      jq -r '.warnings[]?.message' <<< "${hy2_material}" >&2 || return 1
      printf 'Hysteria2 客户端 outbound JSON：\n'
      jq '.outbounds' <<< "${hy2_material}"
      return $?
    fi
    echo "1. Hysteria2 协议链接"
    build_hy2_link "${public_ip}" "${address_label}" || return 1
    echo ""
    print_hy2_compatibility_warnings "share"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "anytls" ]]; then
    if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active anytls; then
      local anytls_material
      anytls_material=$(agent_anytls_link_json "${public_ip}") || return 1
      printf '\nAnyTLS 实例 %s（连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
      printf 'AnyTLS 客户端 outbound JSON：\n'
      jq '.outbounds' <<< "${anytls_material}"
      return $?
    fi
    echo "1. AnyTLS 客户端 outbound JSON 示例"
    build_anytls_outbound_example "${public_ip}"
    echo ""
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "snell" ]]; then
    local snell_material
    snell_material=$(agent_snell_link_json "${public_ip}") || return 1
    printf '\nSnell 实例 %s（无标准分享 URI；连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
    jq -r '.warnings[]?.message' <<< "${snell_material}" >&2 || return 1
    printf 'Snell 客户端 outbound JSON：\n'
    jq '.outbounds' <<< "${snell_material}"
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == "tuic" ]]; then
    local tuic_material
    tuic_material=$(agent_tuic_link_json "${public_ip}") || return 1
    printf '\nTUIC 实例 %s（无标准分享 URI；连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
    jq -r '.warnings[]?.message' <<< "${tuic_material}" >&2 || return 1
    printf 'TUIC 客户端 outbound JSON：\n'
    jq '.outbounds' <<< "${tuic_material}"
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == "hysteria" ]]; then
    local hysteria_material
    hysteria_material=$(agent_hysteria_link_json "${public_ip}") || return 1
    printf '\nHysteria 实例 %s（无标准分享 URI；连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
    jq -r '.warnings[]?.message' <<< "${hysteria_material}" >&2 || return 1
    printf 'Hysteria 客户端 outbound JSON：\n'
    jq '.outbounds' <<< "${hysteria_material}"
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == "naive" ]]; then
    local naive_material
    naive_material=$(agent_naive_link_json "${public_ip}") || return 1
    printf '\nNaiveProxy 实例 %s（无标准分享 URI；连接材料含凭据，请妥善保管）\n' "${SB_INSTANCE_ID:-}"
    jq -r '.warnings[]?.message' <<< "${naive_material}" >&2 || return 1
    printf 'NaiveProxy 客户端 outbound JSON：\n'
    jq '.outbounds' <<< "${naive_material}"
    return $?
  fi

  if [[ "${SB_PROTOCOL}" == "shadowtls" ]]; then
    local shadowtls_material
    shadowtls_material=$(agent_shadowtls_link_json "${public_ip}") || return 1
    printf '\nShadowTLS 实例 %s（TLS 包装层组合协议；无标准分享 URI）\n' "${SB_INSTANCE_ID:-}"
    jq -r '.warnings[]?.message' <<< "${shadowtls_material}" >&2 || return 1
    printf 'ShadowTLS 客户端 outbound JSON：\n'
    jq '.outbounds' <<< "${shadowtls_material}"
    return $?
  fi

  local plain_links share_warnings http_link socks_link warning_message
  plain_links=$(build_plain_proxy_links_json "${SB_PROTOCOL}" "${public_ip}") || return 1
  share_warnings=$(plain_proxy_share_warnings_json "${SB_PROTOCOL}") || return 1
  http_link=$(jq -r '.http // empty' <<< "${plain_links}") || return 1
  socks_link=$(jq -r '.socks5 // empty' <<< "${plain_links}") || return 1
  if [[ -n "${http_link}" ]]; then
    if [[ "${SB_PROTOCOL}" == http ]]; then
      printf '1. HTTP 代理链接\n%s\n' "${http_link}"
    else
      printf '1. Mixed HTTP 代理链接\n%s\n' "${http_link}"
    fi
  fi
  if [[ "${SB_PROTOCOL}" == mixed ]]; then
    printf '2. Mixed SOCKS5 代理链接\n%s\n' "${socks_link}"
  elif [[ "${SB_PROTOCOL}" == socks ]]; then
    printf '1. SOCKS5 代理链接\n%s\n' "${socks_link}"
  fi
  while IFS= read -r warning_message; do
    [[ -n "${warning_message}" ]] && log_warn "${warning_message}"
  done < <(jq -r '.[].message' <<< "${share_warnings}")
  if [[ "${SB_PROTOCOL}" == socks ]]; then
    log_warn "SOCKS5 代理链路未启用 TLS，认证信息与业务流量可能被读取；仅用于可信网络或受保护隧道。"
    return 0
  fi
  if [[ "${SB_PROTOCOL}" == http ]]; then
    if [[ "${SB_MIXED_AUTH_ENABLED}" != "y" ]]; then
      log_warn "当前 HTTP 代理未启用认证，请尽快确认防火墙限制或开启认证。"
    fi
    return 0
  fi
  if [[ "${SB_MIXED_AUTH_ENABLED}" != "y" ]]; then
    log_warn "当前 Mixed 代理未启用认证，请尽快确认防火墙限制或开启认证。"
  fi
}

show_qr_info() {
  local public_ip=$1
  local address_label=${2:-}
  local instance_id share_link
  local header_label

  if [[ "${SB_PROTOCOL}" == trojan || "${SB_PROTOCOL}" == vmess || "${SB_PROTOCOL}" == vless || "${SB_PROTOCOL}" == vless-plain || "${SB_PROTOCOL}" == shadowtls ]]; then
    log_info "${SB_PROTOCOL} 当前不展示二维码；请使用可用 URI 或完整客户端 JSON。"
    return 0
  fi

  header_label="${address_label}"
  if protocol_uses_domain_connection_material; then
    header_label=""
  fi

  if [[ -n "${header_label}" ]]; then
    echo -e "\n${YELLOW}连接二维码 ${header_label}：${NC}"
  else
    echo -e "\n${YELLOW}连接二维码：${NC}"
  fi

  if [[ "${SB_PROTOCOL}" == "mixed" || "${SB_PROTOCOL}" == "socks" || "${SB_PROTOCOL}" == "http" || "${SB_PROTOCOL}" == "shadowsocks" ]]; then
    local plain_label
    plain_label=$(plain_proxy_management_label "${SB_PROTOCOL}") || return 1
    log_info "${plain_label} 协议当前不提供二维码，请使用链接方式手动配置客户端。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "anytls" ]]; then
    log_info "AnyTLS 当前不展示二维码，请使用参数摘要与 outbound JSON 示例手动导入客户端。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "snell" ]]; then
    log_info "Snell 当前不展示二维码；请使用完整客户端 outbound JSON（无标准 URI）。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "tuic" ]]; then
    log_info "TUIC 当前不展示二维码；请使用完整客户端 outbound JSON（无标准 URI）。"
    return 0
  fi
  if [[ "${SB_PROTOCOL}" == "hysteria" ]]; then
    log_info "Hysteria 当前不展示二维码；请使用完整客户端 outbound JSON（无标准 URI）。"
    return 0
  fi
  if [[ "${SB_PROTOCOL}" == "naive" ]]; then
    log_info "NaiveProxy 当前不展示二维码；请使用完整客户端 outbound JSON（需要 with_naive_outbound 与 libcronet，无标准 URI）。"
    return 0
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    log_warn "未安装 qrencode，已跳过二维码展示。可安装后重新进入菜单 11 查看。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active hy2; then
      local hy2_material hy2_uri
      hy2_material=$(agent_hy2_link_json "${public_ip}") || return 1
      while IFS= read -r hy2_uri; do
        [[ -n "${hy2_uri}" ]] || continue
        echo "Hysteria2 实例二维码"
        qrencode -t ansiutf8 "${hy2_uri}"
      done < <(jq -r '.links[]?' <<< "${hy2_material}")
      jq -r '.warnings[]?.message' <<< "${hy2_material}" >&2 || return 1
      return 0
    fi
    echo "1. Hysteria2 协议二维码"
    share_link=$(build_hy2_link "${public_ip}" "${address_label}") || return 1
    qrencode -t ansiutf8 "${share_link}" || return 1
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    local rendered_count=0
    local fallback_instance_id="${SB_VLESS_INSTANCE_ID:-main}"
    local fallback_node_name="${SB_NODE_NAME:-}"
    local fallback_port="${SB_PORT:-}"
    local fallback_uuid="${SB_UUID:-}"
    local fallback_sni="${SB_SNI:-}"
    local fallback_short_id_1="${SB_SHORT_ID_1:-}"
    local fallback_short_id_2="${SB_SHORT_ID_2:-}"
    local fallback_rate_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
    local fallback_rate_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
    local fallback_outbound_policy="${SB_OUTBOUND_POLICY:-default}"
    migrate_vless_reality_state_to_instances_if_needed
    while IFS= read -r instance_id; do
      [[ -z "${instance_id}" ]] && continue
      load_vless_reality_protocol_state
      load_vless_reality_instance_state "${instance_id}" || continue
      echo "REALITY 实例二维码"
      echo "实例 ID: ${SB_VLESS_INSTANCE_ID}"
      share_link=$(build_vless_link "${public_ip}" "${address_label}") || return 1
      qrencode -t ansiutf8 "${share_link}" || return 1
      rendered_count=$((rendered_count + 1))
    done < <(list_vless_reality_instance_ids)
    load_vless_reality_protocol_state
    if ! load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" >/dev/null 2>&1 && (( rendered_count == 0 )) && [[ -n "${fallback_node_name}" && -n "${fallback_uuid}" ]]; then
      SB_VLESS_INSTANCE_ID="${fallback_instance_id}"
      SB_NODE_NAME="${fallback_node_name}"
      SB_PORT="${fallback_port}"
      SB_UUID="${fallback_uuid}"
      SB_SNI="${fallback_sni}"
      SB_SHORT_ID_1="${fallback_short_id_1}"
      SB_SHORT_ID_2="${fallback_short_id_2}"
      SB_VLESS_RATE_LIMIT_UP_MBPS="${fallback_rate_up}"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="${fallback_rate_down}"
      SB_OUTBOUND_POLICY="${fallback_outbound_policy}"
      echo "REALITY 实例二维码"
      echo "实例 ID: ${SB_VLESS_INSTANCE_ID:-main}"
      share_link=$(build_vless_link "${public_ip}" "${address_label}") || return 1
      qrencode -t ansiutf8 "${share_link}" || return 1
    fi
    return 0
  fi
}

show_connection_details() {
  local mode=$1
  local public_ip=${2:-}
  local address_label=${3-}

  if [[ -z "${public_ip}" ]] && ! public_ip=$(get_public_ip); then
    print_warn "未获取到公网 IP，暂时无法展示连接信息，请稍后重试。"
    return 0
  fi

  if [[ $# -lt 3 && -z "${address_label}" ]]; then
    if [[ "${public_ip}" == *:* ]]; then
      address_label="IPv6"
    elif [[ "${public_ip}" == *.* ]]; then
      address_label="IPv4"
    fi
  fi

  case "${mode}" in
    link)
      show_link_info "${public_ip}" "${address_label}" || return 1
      ;;
    qr)
      show_qr_info "${public_ip}" "${address_label}" || return 1
      ;;
    both)
      show_link_info "${public_ip}" "${address_label}" || return 1
      show_qr_info "${public_ip}" "${address_label}" || return 1
      ;;
    *)
      log_warn "未知的连接信息展示模式: ${mode}"
      return 1
      ;;
  esac
}

list_public_addresses_for_stack_mode() {
  local mode=${1:-} ipv4_address='' ipv6_address=''
  validate_inbound_stack_mode "${mode}" || return 1
  if [[ "${mode}" != ipv6_only ]]; then
    ipv4_address=$(get_public_ipv4) || ipv4_address=''
  fi
  if [[ "${mode}" != ipv4_only ]]; then
    ipv6_address=$(get_public_ipv6) || ipv6_address=''
  fi
  [[ -n "${ipv4_address}" || -n "${ipv6_address}" ]] || return 1
  if [[ -n "${ipv4_address}" ]]; then printf 'IPv4|%s\n' "${ipv4_address}"; fi
  if [[ -n "${ipv6_address}" ]]; then printf 'IPv6|%s\n' "${ipv6_address}"; fi
}

list_public_addresses_for_current_stack() {
  ensure_stack_mode_state_loaded || return 1
  list_public_addresses_for_stack_mode "${SB_INBOUND_STACK_MODE}"
}

listener_address_is_wildcard() {
  local canonical
  canonical=$(canonical_listener_address "${1:-}") || return 1
  [[ "${canonical}" == 0.0.0.0 || "${canonical}" == 0000:0000:0000:0000:0000:0000:0000:0000 ]]
}

protocol_uses_domain_connection_material() {
  case "$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)" in
    hy2|anytls|tuic|hysteria|naive) return 0 ;;
    *) return 1 ;;
  esac
}

list_subman_addresses_for_current_protocol() {
  local bound_address canonical protocol

  protocol=$(runtime_protocol_to_state "${SB_PROTOCOL:-}" 2>/dev/null || true)
  case "${protocol}" in
    mixed|socks|http|shadowsocks|trojan|vmess|vless-plain|anytls|hy2|snell|tuic|hysteria|naive|shadowtls)
      if plain_proxy_structured_state_active "${protocol}" >/dev/null 2>&1; then
        bound_address=${SB_MIXED_LISTEN_ADDRESS:-}
        canonical=$(canonical_listener_address "${bound_address}") || return 1
        # Structured stores render their own listener verbatim. Global stack
        # preferences cannot broaden or narrow that existing socket.
        case "${canonical}" in
          0.0.0.0) list_public_addresses_for_stack_mode ipv4_only ;;
          0000:0000:0000:0000:0000:0000:0000:0000) list_public_addresses_for_stack_mode dual_stack ;;
          *) printf '监听地址|%s\n' "${bound_address}" ;;
        esac
        return $?
      fi
      ;;
  esac

  list_public_addresses_for_current_stack
}

show_connection_details_for_detected_addresses() {
  local mode=$1
  local address_entries=()
  local entry label address public_ip

  if [[ ("${SB_PROTOCOL}" == mixed || "${SB_PROTOCOL}" == socks || "${SB_PROTOCOL}" == http || "${SB_PROTOCOL}" == shadowsocks || "${SB_PROTOCOL}" == trojan || "${SB_PROTOCOL}" == vmess || "${SB_PROTOCOL}" == vless-plain || "${SB_PROTOCOL}" == anytls || "${SB_PROTOCOL}" == hy2 || "${SB_PROTOCOL}" == snell || "${SB_PROTOCOL}" == tuic || "${SB_PROTOCOL}" == hysteria || "${SB_PROTOCOL}" == naive || "${SB_PROTOCOL}" == shadowtls) ]] && plain_proxy_structured_state_active "${SB_PROTOCOL}"; then
    address=${SB_MIXED_LISTEN_ADDRESS:-}
    if [[ -n "${address}" && "${address}" != '::' && "${address}" != 0.0.0.0 ]]; then
      show_connection_details "${mode}" "${address}" "监听地址"
      return $?
    fi
  fi

  if protocol_uses_domain_connection_material; then
    if ! public_ip=$(get_public_ip); then
      print_warn "未获取到公网 IP，暂时无法展示连接信息，请稍后重试。"
      return 0
    fi
    if [[ "${public_ip}" == *:* ]]; then
      label="IPv6"
    elif [[ "${public_ip}" == *.* ]]; then
      label="IPv4"
    else
      label=""
    fi
    show_connection_details "${mode}" "${public_ip}" "${label}"
    return 0
  fi

  mapfile -t address_entries < <(list_public_addresses_for_current_stack)

  if [[ ${#address_entries[@]} -eq 0 ]]; then
    show_connection_details "${mode}"
    return 0
  fi

  for entry in "${address_entries[@]}"; do
    label=${entry%%|*}
    address=${entry#*|}
    show_connection_details "${mode}" "${address}" "${label}"
  done
}

show_all_connection_details() {
  local mode=$1
  local installed_protocols=()
  local protocol original_protocol_state instance_id instance_ids

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  mapfile -t installed_protocols < <(list_installed_protocols)

  if [[ ${#installed_protocols[@]} -eq 0 ]]; then
    show_connection_details_for_detected_addresses "${mode}"
    return 0
  fi

  for protocol in "${installed_protocols[@]}"; do
    load_protocol_state "${protocol}" || return $?
    if [[ ("${protocol}" == mixed || "${protocol}" == socks || "${protocol}" == http || "${protocol}" == shadowsocks || "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain || "${protocol}" == anytls || "${protocol}" == hy2 || "${protocol}" == snell || "${protocol}" == tuic || "${protocol}" == hysteria || "${protocol}" == naive || "${protocol}" == shadowtls) ]] && plain_proxy_structured_state_active "${protocol}"; then
      instance_ids=$(list_protocol_instance_ids "${protocol}") || return $?
      while IFS= read -r instance_id; do
        [[ -n "${instance_id}" ]] || continue
        load_plain_proxy_structured_instance "${protocol}" "${instance_id}" || return $?
        printf '\n--- %s 实例 %s ---\n' "${protocol}" "${instance_id}"
        show_connection_details_for_detected_addresses "${mode}" || return $?
      done <<< "${instance_ids}"
      continue
    fi
    echo -e "\n${BLUE}--- $(protocol_display_name "${SB_PROTOCOL}") ---${NC}"
    show_connection_details_for_detected_addresses "${mode}"
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi
}

show_connection_info_menu() {
  while true; do
    echo
    render_left_aligned_page_header "节点信息查看" "按当前配置展示客户端连接信息"
    render_menu_group_start "展示方式"
    render_menu_item "1" "仅链接"
    render_menu_item "2" "仅二维码"
    render_menu_item "3" "链接 + 二维码"
    echo "0. 返回"
    info_choice=$(prompt_choice "请选择 [0-3]: " 0 3 "")

    case "${info_choice}" in
      1) show_all_connection_details "link" ;;
      2) show_all_connection_details "qr" ;;
      3) show_all_connection_details "both" ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

client_export_file_path() {
  printf '%s/client/sing-box-client.json' "${SB_PROJECT_DIR}"
}

build_singbox_client_config() {
  local original_protocol_state original_instance_id clash_api_secret public_ip tmpdir
  local installed_protocols_raw
  local installed_protocols=() exportable_protocols=()
  local remote_outbounds_json remote_tags_json
  local protocol protocol_label outbound_json protocol_tags shadowtls_bundle_json usable_protocol_count
  local routing_policy_json client_policy_json client_adblock_json
  local use_rule_set_http_client="n"
  local status=0

  [[ "$#" -le 1 ]] || return 1
  if [[ "$#" -eq 0 ]]; then
    routing_policy_json=$(routing_policy_read_json) || return 1
  else
    routing_policy_json=$1
  fi
  routing_policy_validate_json "${routing_policy_json}" || return 1
  client_policy_json=$(jq -c '.client' <<< "${routing_policy_json}") || return 1
  client_adblock_json=$(routing_policy_adblock_json "${routing_policy_json}" client) || return 1

  if singbox_config_supports_1_14; then
    use_rule_set_http_client="y"
  fi

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  original_instance_id=""
  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    if original_instance_id=$(protocol_default_instance_id "${original_protocol_state}"); then
      :
    else
      return $?
    fi
  fi
  if ! installed_protocols_raw=$(list_installed_protocols_read_only); then
    return 1
  fi
  if [[ -n "${installed_protocols_raw}" ]]; then
    mapfile -t installed_protocols <<< "${installed_protocols_raw}"
    for protocol in "${installed_protocols[@]}"; do
      [[ "$(protocol_registry_field "${protocol}" client_export)" == "true" ]] || continue
      exportable_protocols+=("${protocol}")
    done
  fi
  if [[ ${#exportable_protocols[@]} -eq 0 ]]; then
    if [[ ${#installed_protocols[@]} -gt 0 ]]; then
      log_warn "当前无可导出的 sing-box 裸核客户端节点；已安装协议没有注册客户端导出能力。" >&2
    else
      log_warn "当前无可导出的 sing-box 裸核客户端节点；请先安装支持客户端导出的协议。" >&2
    fi
    return 1
  fi

  clash_api_secret=$(generate_random_token "clash-" 16)
  public_ip=$(get_public_ip)
  tmpdir=$(mktemp -d)
  usable_protocol_count=0
  trap '
    if [[ -n "${original_protocol_state:-}" ]] && protocol_state_exists "${original_protocol_state}"; then
      load_protocol_instance_state "${original_protocol_state}" "${original_instance_id}" >/dev/null 2>&1
    fi
    rm -rf "${tmpdir:-}"
  ' RETURN

  for protocol in "${exportable_protocols[@]}"; do
    protocol_label=$(protocol_display_name "${protocol}") || return 1
    if ! protocol_state_exists "${protocol}"; then
      if [[ "${protocol}" == "mixed" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "vless-plain" || "${protocol}" == "anytls" || "${protocol}" == "hy2" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls" ]]; then
        log_warn "${protocol_label} 状态缺失，已中止客户端导出；原导出文件保持不变。" >&2
        status=1
        break
      fi
      log_warn "协议状态文件缺失，已跳过客户端导出协议: ${protocol}" >&2
      continue
    fi

    if [[ "${protocol}" == "shadowtls" ]]; then
      if ! shadowtls_bundle_json=$(build_client_shadowtls_bundle_json "${public_ip}"); then
        log_warn "${protocol_label} 客户端连接材料无效，已中止客户端导出；原导出文件保持不变。" >&2
        status=1
        break
      fi
      if ! outbound_json=$(jq -c '.outbounds[]' <<< "${shadowtls_bundle_json}") ||
         ! protocol_tags=$(jq -r '.primary_tags[]' <<< "${shadowtls_bundle_json}"); then
        log_warn "${protocol_label} 客户端组合连接材料无效，已中止客户端导出；原导出文件保持不变。" >&2
        status=1
        break
      fi
    elif ! outbound_json=$(build_client_outbounds_for_current_protocol "${protocol}" "${public_ip}"); then
      if [[ "${protocol}" == "mixed" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "vless-plain" || "${protocol}" == "anytls" || "${protocol}" == "hy2" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls" ]]; then
        log_warn "${protocol_label} 客户端连接材料无效，已中止客户端导出；原导出文件保持不变。" >&2
        status=1
        break
      fi
      log_warn "生成客户端导出协议失败，已跳过: ${protocol}" >&2
      continue
    else
      if ! protocol_tags=$(jq -r '.tag' <<< "${outbound_json}"); then
        log_warn "${protocol_label} 客户端连接材料标签无效，已中止客户端导出；原导出文件保持不变。" >&2
        status=1
        break
      fi
    fi

    printf '%s\n' "${outbound_json}" >> "${tmpdir}/outbounds.jsonl"
    printf '%s\n' "${protocol_tags}" >> "${tmpdir}/tags.txt"
    usable_protocol_count=$((usable_protocol_count + 1))
  done

  if (( status != 0 )); then
    :
  elif (( usable_protocol_count == 0 )); then
    log_warn "未找到可用的远程协议可供导出，请检查协议状态文件是否完整。" >&2
    status=1
  else
    remote_outbounds_json=$(jq -s '.' "${tmpdir}/outbounds.jsonl")
    remote_tags_json=$(jq -Rsc 'split("\n") | map(select(length > 0))' "${tmpdir}/tags.txt")

    jq -n \
      --argjson remote_outbounds "${remote_outbounds_json}" \
      --argjson remote_tags "${remote_tags_json}" \
      --arg clash_api_secret "${clash_api_secret}" \
      --arg use_rule_set_http_client "${use_rule_set_http_client}" \
      --argjson client_policy "${client_policy_json}" \
      --argjson adblock "${client_adblock_json}" \
      '{
        "log": {
          "level": "info",
          "timestamp": true
        },
        "dns": {
          "servers": [
            {
              "type": "https",
              "tag": "cn-dns",
              "server": "223.5.5.5",
              "server_port": 443,
              "path": "/dns-query"
            },
            {
              "type": "https",
              "tag": "remote-dns",
              "server": "1.1.1.1",
              "server_port": 443,
              "path": "/dns-query",
              "detour": "proxy"
            }
          ],
          "rules": ($adblock.rules + (if $client_policy.cn_direct then [
            {
              "rule_set": "geosite-cn",
              "server": "cn-dns"
            },
            {
              "rule_set": "geosite-geolocation-!cn",
              "server": "remote-dns"
            }
          ] else [] end)),
          "final": "remote-dns",
          "strategy": "prefer_ipv4"
        },
        "inbounds": [
          {
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "127.0.0.1",
            "listen_port": 2080,
            "set_system_proxy": false
          }
        ],
        "outbounds": (
          [
            {
              "type": "selector",
              "tag": "proxy",
              "outbounds": (["auto"] + $remote_tags),
              "default": "auto"
            },
            {
              "type": "urltest",
              "tag": "auto",
              "outbounds": $remote_tags,
              "url": "https://www.gstatic.com/generate_204",
              "interval": "3m"
            }
          ] + $remote_outbounds + [
            {
              "type": "direct",
              "tag": "direct"
            }
          ]
        ),
        "route": {
          "rule_set": (
            (if $client_policy.cn_direct then [
              {
                "tag": "geoip-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/cn.srs"
              },
              {
                "tag": "geosite-cn",
                "type": "remote",
                "format": "binary",
                "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/cn.srs"
              },
              {
                "tag": "geosite-geolocation-!cn",
                "type": "remote",
                "format": "binary",
                "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/geolocation-!cn.srs"
              }
            ] else [] end) + $adblock.rule_sets
            | map(
                if $use_rule_set_http_client == "y" and .type == "remote" then
                  . + {"http_client": {"detour": "proxy"}}
                elif .type == "remote" and has("download_detour") then
                  .download_detour = "proxy"
                else
                  .
                end
              )
          ),
          "rules": ([
            {
              "action": "sniff"
            },
            {
              "protocol": "dns",
              "action": "hijack-dns"
            }
          ] + $adblock.rules + (if $client_policy.lan_direct then [
            {
              "ip_is_private": true,
              "action": "route",
              "outbound": "direct"
            }
          ] else [] end) + (if $client_policy.cn_direct then [
            {
              "rule_set": "geosite-cn",
              "action": "route",
              "outbound": "direct"
            },
            {
              "rule_set": "geoip-cn",
              "action": "route",
              "outbound": "direct"
            },
            {
              "rule_set": "geosite-geolocation-!cn",
              "action": "route",
              "outbound": "proxy"
            }
          ] else [] end)),
          "final": "proxy",
          "auto_detect_interface": true,
          "default_domain_resolver": "cn-dns"
        },
        "experimental": {
          "cache_file": {
            "enabled": true,
            "path": "cache.db"
          },
          "clash_api": {
            "external_controller": "127.0.0.1:9090",
            "secret": $clash_api_secret
          }
        }
      }' || status=$?
  fi

  trap - RETURN
  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_instance_state "${original_protocol_state}" "${original_instance_id}" >/dev/null 2>&1 || status=1
  fi
  rm -rf "${tmpdir}"
  return "${status}"
}

write_client_config_export() {
  local config_json=$1
  local export_path export_dir tmp_file backup_path backup_tmp

  export_path=$(client_export_file_path)
  export_dir=$(dirname "${export_path}")
  mkdir -p "${export_dir}"
  tmp_file=$(mktemp "${export_dir}/.sing-box-client.json.tmp.XXXXXX")
  if ! printf '%s\n' "${config_json}" | jq '.' > "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  if [[ -f "${export_path}" ]]; then
    backup_path="${export_path}.bak"
    backup_tmp=$(mktemp "${export_dir}/.sing-box-client.json.bak.tmp.XXXXXX")
    if ! cp "${export_path}" "${backup_tmp}"; then
      rm -f "${tmp_file}" "${backup_tmp}"
      return 1
    fi
    if ! mv "${backup_tmp}" "${backup_path}"; then
      rm -f "${tmp_file}" "${backup_tmp}"
      return 1
    fi
  fi
  if ! mv "${tmp_file}" "${export_path}"; then
    rm -f "${tmp_file}"
    return 1
  fi
}

validate_client_config_json() {
  local config_json=$1
  local tmp_file

  tmp_file=$(mktemp)
  if ! printf '%s\n' "${config_json}" | jq '.' > "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  if ! validate_managed_component_graph "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  if ! "${SINGBOX_BIN_PATH}" check -c "${tmp_file}" >&2; then
    rm -f "${tmp_file}"
    return 1
  fi

  rm -f "${tmp_file}"
}

export_singbox_client_config() {
  local config_json export_path warnings_json warning_message

  if ! config_json=$(build_singbox_client_config); then
    log_warn "导出 sing-box 裸核客户端配置失败。" >&2
    return 1
  fi

  if ! validate_client_config_json "${config_json}"; then
    log_warn "导出的 sing-box 裸核客户端配置未通过引用或核心 check 校验。" >&2
    return 1
  fi

  warnings_json=$(collect_client_export_warnings_json "${config_json}") || return 1

  export_path=$(client_export_file_path)
  if ! write_client_config_export "${config_json}"; then
    log_warn "写入客户端配置文件失败: ${export_path}" >&2
    return 1
  fi

  print_success "sing-box 裸核客户端配置导出成功。"
  while IFS= read -r warning_message; do
    [[ -n "${warning_message}" ]] && log_warn "${warning_message}"
  done < <(jq -r '.[]?.message' <<< "${warnings_json}")
  printf '文件路径: %s\n' "${export_path}"
  printf 'WSL2 使用方式: 请将应用代理手动指向 127.0.0.1:2080\n'
  printf '系统代理: 未启用（set_system_proxy=false）\n'
  printf 'Clash API 地址: 127.0.0.1:9090\n'
  printf '%s\n' "${config_json}"
}
