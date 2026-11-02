
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
