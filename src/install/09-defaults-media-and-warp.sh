
set_protocol_defaults() {
  SB_MIXED_LISTEN_ADDRESS=${SB_DEFAULT_LISTEN_ADDRESS}
  case "$1" in
    socks)
      SB_PROTOCOL="socks"
      SB_NODE_NAME="$(default_node_name_for_protocol "socks")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="socks-in"
      SB_MIXED_STORE_REVISION="0"
      SB_OUTBOUND_POLICY="default"
      ;;
    shadowtls)
      SB_PROTOCOL="shadowtls"
      SB_NODE_NAME="$(default_node_name_for_protocol "shadowtls")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""; SB_UUID=""; SB_PUBLIC_KEY=""; SB_PRIVATE_KEY=""; SB_SHORT_ID_1=""; SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="n"; SB_MIXED_USERNAME=""; SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""; SB_MIXED_INSTANCE_ID=""; SB_MIXED_INBOUND_TAG="shadowtls-in"
      SB_MIXED_STORE_REVISION="0"
      SB_SHADOWTLS_VERSION="3"; SB_SHADOWTLS_PASSWORD=""; SB_SHADOWTLS_AUTH_JSON='[]'
      SB_SHADOWTLS_HANDSHAKE_JSON='{"server":"","server_port":443}'
      SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON='{}'; SB_SHADOWTLS_STRICT_MODE="n"; SB_SHADOWTLS_WILDCARD_SNI="off"
      SB_SHADOWTLS_DETOUR_TAG=""; SB_SHADOWTLS_DETOUR_PORT="$(pick_random_high_port)"
      SB_SHADOWTLS_CLIENT_TRUST="system"; SB_SHADOWTLS_CLIENT_TLS_JSON='{"enabled":true,"server_name":"","certificate_path":""}'
      SB_OUTBOUND_POLICY="default"
      ;;
    naive)
      SB_PROTOCOL="naive"
      SB_NODE_NAME="$(default_node_name_for_protocol "naive")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""; SB_UUID=""; SB_PUBLIC_KEY=""; SB_PRIVATE_KEY=""; SB_SHORT_ID_1=""; SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"; SB_MIXED_USERNAME=""; SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""; SB_MIXED_INSTANCE_ID=""; SB_MIXED_INBOUND_TAG="naive-in"
      SB_MIXED_STORE_REVISION="0"
      SB_NAIVE_AUTH_JSON='[]'; SB_NAIVE_TLS_JSON='{"enabled":false}'; SB_NAIVE_CLIENT_TRUST="system"
      SB_NAIVE_NETWORK_JSON='["tcp","udp"]'; SB_NAIVE_QUIC_CONGESTION_CONTROL="bbr"; SB_NAIVE_QUIC="n"
      SB_NAIVE_INSECURE_CONCURRENCY="0"; SB_NAIVE_STREAM_RECEIVE_WINDOW=""; SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW=""; SB_NAIVE_EXTRA_HEADERS_JSON='{}'
      SB_OUTBOUND_POLICY="default"
      ;;
    tuic)
      SB_PROTOCOL="tuic"
      SB_NODE_NAME="$(default_node_name_for_protocol "tuic")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="tuic-in"
      SB_MIXED_STORE_REVISION="0"
      SB_TUIC_AUTH_JSON='[]'
      SB_TUIC_TLS_JSON='{"enabled":false}'
      SB_TUIC_CLIENT_TRUST="system"
      SB_TUIC_CONGESTION_CONTROL="bbr"
      SB_TUIC_AUTH_TIMEOUT_SECONDS="3"
      SB_TUIC_HEARTBEAT_SECONDS="10"
      SB_TUIC_ZERO_RTT_HANDSHAKE="n"
      SB_TUIC_UDP_RELAY_MODE="native"
      SB_TUIC_UDP_OVER_STREAM="n"
      SB_OUTBOUND_POLICY="default"
      ;;
    hysteria)
      SB_PROTOCOL="hysteria"
      SB_NODE_NAME="$(default_node_name_for_protocol "hysteria")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""; SB_UUID=""; SB_PUBLIC_KEY=""; SB_PRIVATE_KEY=""; SB_SHORT_ID_1=""; SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"; SB_MIXED_USERNAME=""; SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""; SB_MIXED_INSTANCE_ID=""; SB_MIXED_INBOUND_TAG="hysteria-in"
      SB_MIXED_STORE_REVISION="0"
      SB_HYSTERIA_AUTH_JSON='[]'; SB_HYSTERIA_TLS_JSON='{"enabled":false}'; SB_HYSTERIA_CLIENT_TRUST="system"
      SB_HYSTERIA_UP_MBPS="100"; SB_HYSTERIA_DOWN_MBPS="100"; SB_HYSTERIA_OBFS_ENABLED="n"; SB_HYSTERIA_OBFS_PASSWORD=""
      SB_HYSTERIA_QUIC_JSON='{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'
      SB_OUTBOUND_POLICY="default"
      ;;
    vless-plain)
      SB_PROTOCOL="vless"
      SB_NODE_NAME="$(default_node_name_for_protocol "vless-plain")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="vless-plain-in"
      SB_MIXED_STORE_REVISION="0"
      SB_VLESS_PLAIN_AUTH_JSON='[]'
      SB_VLESS_PLAIN_TLS_JSON='{"enabled":false}'
      SB_VLESS_PLAIN_TRANSPORT_JSON='{"type":"none"}'
      SB_VLESS_PLAIN_CLIENT_TRUST="system"
      SB_OUTBOUND_POLICY="default"
      ;;
    vmess)
      SB_PROTOCOL="vmess"
      SB_NODE_NAME="$(default_node_name_for_protocol "vmess")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="vmess-in"
      SB_MIXED_STORE_REVISION="0"
      SB_VMESS_AUTH_JSON='[]'
      SB_VMESS_TLS_JSON='{"enabled":false}'
      SB_VMESS_TRANSPORT_JSON='{"type":"none"}'
      SB_VMESS_CLIENT_TRUST="system"
      SB_OUTBOUND_POLICY="default"
      ;;
    trojan)
      SB_PROTOCOL="trojan"
      SB_NODE_NAME="$(default_node_name_for_protocol "trojan")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="trojan-in"
      SB_MIXED_STORE_REVISION="0"
      SB_TROJAN_AUTH_JSON='[]'
      SB_TROJAN_TLS_JSON='{"enabled":false}'
      SB_TROJAN_TRANSPORT_JSON='{"type":"none"}'
      SB_TROJAN_CLIENT_TRUST="system"
      SB_OUTBOUND_POLICY="default"
      ;;
    http)
      SB_PROTOCOL="http"
      SB_NODE_NAME="$(default_node_name_for_protocol "http")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="http-in"
      SB_MIXED_STORE_REVISION="0"
      SB_HTTP_TLS_JSON='{"enabled":false}'
      SB_OUTBOUND_POLICY="default"
      ;;
    shadowsocks)
      SB_PROTOCOL="shadowsocks"
      SB_NODE_NAME="$(default_node_name_for_protocol "shadowsocks")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="ss-in"
      SB_MIXED_STORE_REVISION="0"
      SB_SHADOWSOCKS_AUTH_JSON=""
      SB_SHADOWSOCKS_NETWORK_JSON='["tcp","udp"]'
      SB_OUTBOUND_POLICY="default"
      ;;
    mixed)
      SB_PROTOCOL="mixed"
      SB_NODE_NAME="$(default_node_name_for_protocol "mixed")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      ;;
    hy2)
      SB_PROTOCOL="hy2"
      SB_NODE_NAME="$(default_node_name_for_protocol "hy2")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_HY2_DOMAIN=""
      SB_HY2_PASSWORD=""
      SB_HY2_USER_NAME="hy2-user"
      SB_HY2_UP_MBPS=""
      SB_HY2_DOWN_MBPS=""
      SB_HY2_OBFS_ENABLED="y"
      SB_HY2_OBFS_TYPE=""
      SB_HY2_OBFS_PASSWORD=""
      SB_HY2_TLS_MODE="acme"
      SB_HY2_ACME_MODE="http"
      SB_HY2_ACME_EMAIL=""
      SB_HY2_ACME_DOMAIN=""
      SB_HY2_ACME_EXTRA_JSON='{}'
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
      SB_HY2_MASQUERADE="https://www.cloudflare.com"
      ;;
    anytls)
      SB_PROTOCOL="anytls"
      SB_NODE_NAME="$(default_node_name_for_protocol "anytls")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_HY2_DOMAIN=""
      SB_HY2_PASSWORD=""
      SB_HY2_USER_NAME=""
      SB_HY2_UP_MBPS=""
      SB_HY2_DOWN_MBPS=""
      SB_HY2_OBFS_ENABLED="n"
      SB_HY2_OBFS_TYPE=""
      SB_HY2_OBFS_PASSWORD=""
      SB_HY2_TLS_MODE="acme"
      SB_HY2_ACME_MODE="http"
      SB_HY2_ACME_EMAIL=""
      SB_HY2_ACME_DOMAIN=""
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
      SB_HY2_MASQUERADE=""
      SB_ANYTLS_DOMAIN=""
      SB_ANYTLS_PASSWORD=""
      SB_ANYTLS_USER_NAME="anytls-user"
      SB_ANYTLS_TLS_MODE="acme"
      SB_ANYTLS_ACME_MODE="http"
      SB_ANYTLS_ACME_EMAIL=""
      SB_ANYTLS_ACME_DOMAIN=""
      SB_ANYTLS_ACME_EXTRA_JSON='{}'
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
      ;;
    snell)
      SB_PROTOCOL="snell"
      SB_NODE_NAME="$(default_node_name_for_protocol "snell")"
      SB_PORT="$(pick_random_high_port)"
      SB_SNI=""
      SB_UUID=""
      SB_PUBLIC_KEY=""
      SB_PRIVATE_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_INSTANCE_ID=""
      SB_MIXED_INSTANCE_ID=""
      SB_MIXED_INBOUND_TAG="snell-in"
      SB_MIXED_STORE_REVISION="0"
      SB_SNELL_VERSION="6"
      SB_SNELL_PSK=""
      SB_SNELL_USER_JSON='[]'
      SB_SNELL_OBFS_MODE=""
      SB_SNELL_OBFS_HOST=""
      SB_SNELL_MODE=""
      SB_OUTBOUND_POLICY="default"
      ;;
    *)
      SB_PROTOCOL="vless+reality"
      SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
      SB_PORT="443"
      SB_SNI=""
      SB_VLESS_ALPN_MODE="off"
      SB_VLESS_TCP_FAST_OPEN="n"
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_ANYTLS_DOMAIN=""
      SB_ANYTLS_PASSWORD=""
      SB_ANYTLS_USER_NAME=""
      SB_ANYTLS_TLS_MODE="acme"
      SB_ANYTLS_ACME_MODE="http"
      SB_ANYTLS_ACME_EMAIL=""
      SB_ANYTLS_ACME_DOMAIN=""
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
      ;;
  esac
}

generate_random_token() {
  local prefix=$1
  local length=$2
  local token

  token=$(openssl rand -hex "${length}" 2>/dev/null || true)
  token=${token:-$(date +%s)}
  printf '%s%s' "${prefix}" "${token}"
}

generate_hy2_secret() {
  generate_random_token "" 16
}

ensure_hy2_password() {
  if [[ -z "${SB_HY2_PASSWORD}" ]]; then
    SB_HY2_PASSWORD=$(generate_hy2_secret)
  fi
}

ensure_hy2_obfs_settings() {
  if [[ "${SB_HY2_OBFS_ENABLED}" != "y" ]]; then
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
    return 0
  fi

  [[ -z "${SB_HY2_OBFS_TYPE}" ]] && SB_HY2_OBFS_TYPE="salamander"
  [[ -z "${SB_HY2_OBFS_PASSWORD}" ]] && SB_HY2_OBFS_PASSWORD=$(generate_hy2_secret)
  return 0
}

ensure_mixed_auth_credentials() {
  if [[ "${SB_MIXED_AUTH_ENABLED}" != "y" ]]; then
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
    return 0
  fi

  [[ -z "${SB_MIXED_USERNAME}" ]] && SB_MIXED_USERNAME=$(generate_random_token "proxy_" 3)
  [[ -z "${SB_MIXED_PASSWORD}" ]] && SB_MIXED_PASSWORD=$(generate_random_token "" 8)
  return 0
}

show_media_check_backend_info() {
  echo -e "${BLUE}检测后端:${NC} ${MEDIA_CHECK_BACKEND_NAME}"
  echo -e "${BLUE}作者:${NC} ${MEDIA_CHECK_BACKEND_AUTHOR}"
  echo -e "${BLUE}项目地址:${NC} ${MEDIA_CHECK_BACKEND_REPO_URL}"
}

ensure_media_check_backend() {
  local result_status=0

  reset_sbv_update_context
  SBV_UPDATE_OPERATION='media_check_backend'
  SBV_UPDATE_TARGET_PATH=${SB_MEDIA_CHECK_SCRIPT}
  SBV_UPDATE_LOG_FILE=${SBV_LOG_FILE}
  if ! mkdir -p "${SB_MEDIA_CHECK_DIR}"; then
    set_sbv_update_error 'media_check_backend' 'precheck' 'target_directory_create_failed' \
      '无法创建流媒体验证脚本目标目录' "目标目录: ${SB_MEDIA_CHECK_DIR}" 1 \
      '检查目标目录权限和磁盘空间'
    SBV_UPDATE_TARGET_PATH=${SB_MEDIA_CHECK_SCRIPT}
    SBV_UPDATE_LOG_FILE=${SBV_LOG_FILE}
    report_sbv_update_error
    return 1
  fi

  if [[ -L "${SB_MEDIA_CHECK_SCRIPT}" ]]; then
    set_sbv_update_error 'media_check_backend' 'precheck' 'target_symlink_unsupported' \
      '流媒体验证脚本目标是符号链接，已安全拒绝更新' \
      "目标路径: ${SB_MEDIA_CHECK_SCRIPT}" 1 \
      '请先将目标替换为受管普通文件后再重试'
    report_sbv_update_error
    return 1
  fi
  if [[ -x "${SB_MEDIA_CHECK_SCRIPT}" ]]; then
    return 0
  fi

  log_info "正在下载流媒体验证脚本..."
  if download_shell_artifact_atomically \
    'media_check_backend' \
    "${MEDIA_CHECK_BACKEND_SCRIPT_URL}" \
    "${SB_MEDIA_CHECK_SCRIPT}"; then
    log_success "流媒体验证脚本已准备完成。"
    return 0
  else
    result_status=$?
  fi
  return "${result_status}"
}

pick_free_local_port() {
  local port

  for port in $(seq 20080 20120); do
    if ! ss -ltn 2>/dev/null | grep -q ":${port} "; then
      printf '%s' "${port}"
      return 0
    fi
  done

  return 1
}

warp_endpoint_json_from_saved_credentials() {
  local w_key w_v4 w_v6 w_client_id w_reserved='[]'
  [[ -f "${SB_WARP_KEY_FILE}" && ! -L "${SB_WARP_KEY_FILE}" &&
     "$(wc -c < "${SB_WARP_KEY_FILE}")" -le 65536 ]] || return 1
  # Saved credentials are data. Read only known single-line values; never source
  # the file, repair it, or contact the provider from a node/diagnostic operation.
  w_key=$(sed -n 's/^WARP_PRIV_KEY=//p' "${SB_WARP_KEY_FILE}") || return 1
  w_v4=$(sed -n 's/^WARP_V4=//p' "${SB_WARP_KEY_FILE}") || return 1
  w_v6=$(sed -n 's/^WARP_V6=//p' "${SB_WARP_KEY_FILE}") || return 1
  w_client_id=$(sed -n 's/^WARP_CLIENT_ID=//p' "${SB_WARP_KEY_FILE}") || return 1
  [[ "${w_key}" =~ ^[A-Za-z0-9+/]{43}=$ &&
     "${w_client_id}" =~ ^[A-Za-z0-9+/]{4}$ &&
     "${w_v4}" != *:* && "${w_v6}" == *:* ]] || return 1
  structured_instance_store_validate_address "${w_v4}" || return 1
  structured_instance_store_validate_address "${w_v6}" || return 1
  w_reserved=$(warp_client_id_to_reserved_json "${w_client_id}") || return 1
  jq -cn --arg key "${w_key}" --arg v4 "${w_v4}/32" --arg v6 "${w_v6}/128" \
    --argjson reserved "${w_reserved}" \
    '{type:"wireguard",tag:"warp-ep",address:[$v4,$v6],private_key:$key,
      peers:[{address:"engage.cloudflareclient.com",port:2408,
        public_key:"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        reserved:$reserved,allowed_ips:["0.0.0.0/0","::/0"]}],mtu:1280}'
}

warp_endpoint_json_from_live_config() {
  [[ -f "${SINGBOX_CONFIG_FILE}" && ! -L "${SINGBOX_CONFIG_FILE}" ]] || return 1
  jq -ce '[.endpoints[]? | select(.tag == "warp-ep")] |
    select(length == 1) | .[0] | select(.type == "wireguard" and
      (.private_key | type == "string" and test("^[A-Za-z0-9+/]{43}=$")) and
      (.address | type == "array" and length > 0) and
      (.peers | type == "array" and length > 0))' "${SINGBOX_CONFIG_FILE}" 2>/dev/null
}

warp_endpoint_json_for_diagnostic() {
  if [[ -e "${SB_WARP_KEY_FILE}" || -L "${SB_WARP_KEY_FILE}" ]]; then
    warp_endpoint_json_from_saved_credentials
  else
    # A temporary diagnostic can reuse the complete live endpoint without
    # making any ownership claim or persisting it in the generated baseline.
    warp_endpoint_json_from_live_config
  fi
}

warp_endpoint_json_for_generation() {
  if [[ -e "${SB_WARP_KEY_FILE}" || -L "${SB_WARP_KEY_FILE}" ]]; then
    if warp_endpoint_json_from_saved_credentials; then return 0; fi
  fi
  # Never copy arbitrary live endpoint options into a pure ownership record.
  # Only explicit network baseline preparation may bridge legacy credentials,
  # and only with the exact generated transport defaults. A later account
  # registration may replace key/address/reserved material, not operator MTU,
  # listen ports or other custom endpoint options.
  [[ "${SB_ROUTING_BASELINE_WARP_FALLBACK:-n}" == y ]] || return 1
  routing_transaction_valid "${SB_ROUTING_TRANSACTION_DIR}" || return 1
  jq -e '.phase=="snapshot" and .service_changed' \
    "${SB_ROUTING_TRANSACTION_DIR}/transaction.json" >/dev/null || return 1
  warp_endpoint_json_from_live_config | jq -ce '
    select((.address | length) == 2 and (.peers | length) == 1 and
      (.peers[0].reserved | type == "array" and length == 3 and
        all(.[]; type == "number" and floor == . and . >= 0 and . <= 255))) |
    . as $endpoint |
    {type:"wireguard",tag:"warp-ep",address:$endpoint.address,private_key:$endpoint.private_key,
     peers:[{address:"engage.cloudflareclient.com",port:2408,
       public_key:"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
       reserved:$endpoint.peers[0].reserved,allowed_ips:["0.0.0.0/0","::/0"]}],mtu:1280} |
    select(. == $endpoint)' || {
    printf '[ERROR] 现有 WARP Endpoint 含自定义传输设置或格式无法确认，不能安全建立旧配置归属；请恢复有效凭据或可信生成基线后重试。\n' >&2
    return 1
  }
}

create_media_check_warp_proxy_config() {
  local output_file=$1 proxy_port=$2 warp_endpoint
  warp_endpoint=$(warp_endpoint_json_for_diagnostic) || {
    log_warn 'WARP 凭据缺失或无效；请先在网络设置中配置 WARP，检测未修改账户。'
    return 1
  }

  jq -n \
    --arg proxy_port "${proxy_port}" \
    --argjson warp_endpoint "${warp_endpoint}" \
    '{
      "log": { "level": "warn", "timestamp": true },
      "endpoints": [$warp_endpoint],
      "inbounds": [
        {
          "type": "socks",
          "tag": "media-check-socks",
          "listen": "127.0.0.1",
          "listen_port": ($proxy_port | tonumber)
        }
      ],
      "outbounds": [
        { "type": "direct", "tag": "direct" }
      ],
      "route": {
        "rules": [
          { "inbound": "media-check-socks", "action": "sniff" }
        ],
        "final": "warp-ep"
      }
    }' > "${output_file}" || return 1
  "${SINGBOX_BIN_PATH}" check -c "${output_file}" >&2
}

run_media_check_backend() {
  local proxy_url=${1:-}
  local result_status=0

  if ensure_media_check_backend; then
    :
  else
    result_status=$?
    return "${result_status}"
  fi
  show_media_check_backend_info

  if [[ -n "${proxy_url}" ]]; then
    log_info "正在通过代理执行流媒体验证: ${proxy_url}"
    bash "${SB_MEDIA_CHECK_SCRIPT}" -P "${proxy_url}"
  else
    log_info "正在使用本机直出执行流媒体验证..."
    bash "${SB_MEDIA_CHECK_SCRIPT}"
  fi
}

run_media_check_via_warp() {
  local temp_dir proxy_config proxy_log proxy_port proxy_pid proxy_url ready="n"

  if ! command -v jq &>/dev/null; then
    log_warn "未检测到 jq，正在尝试自动安装以支持流媒体验证..."
    get_os_info && install_dependencies
  fi

  proxy_port=$(pick_free_local_port) || log_error "未找到可用的本地临时代理端口。"
  temp_dir=$(mktemp -d)
  proxy_config="${temp_dir}/media-check-warp.json"
  proxy_log="${temp_dir}/media-check-warp.log"
  proxy_url="socks5h://127.0.0.1:${proxy_port}"

  if ! create_media_check_warp_proxy_config "${proxy_config}" "${proxy_port}"; then
    rm -rf -- "${temp_dir}"
    return 1
  fi

  "${SINGBOX_BIN_PATH}" run -c "${proxy_config}" > "${proxy_log}" 2>&1 &
  proxy_pid=$!

  for _ in $(seq 1 20); do
    if ss -ltn 2>/dev/null | grep -q ":${proxy_port} "; then
      ready="y"
      break
    fi
    sleep 0.3
  done

  if [[ "${ready}" != "y" ]]; then
    kill "${proxy_pid}" 2>/dev/null || true
    wait "${proxy_pid}" 2>/dev/null || true
    cat "${proxy_log}" >&2 || true
    rm -rf "${temp_dir}"
    log_error "Warp 临时代理启动失败，请检查 Warp 配置。"
  fi

  run_media_check_backend "${proxy_url}" || {
    local exit_code=$?
    kill "${proxy_pid}" 2>/dev/null || true
    wait "${proxy_pid}" 2>/dev/null || true
    rm -rf "${temp_dir}"
    return "${exit_code}"
  }

  kill "${proxy_pid}" 2>/dev/null || true
  wait "${proxy_pid}" 2>/dev/null || true
  rm -rf "${temp_dir}"
}

media_check_menu() {
  while true; do
    echo
    render_left_aligned_page_header "流媒体验证检测" "验证流媒体与区域解锁情况"
    render_section_title "检测摘要"
    render_summary_item "检测后端" "${MEDIA_CHECK_BACKEND_NAME}"
    render_summary_item "作者" "${MEDIA_CHECK_BACKEND_AUTHOR}"
    render_summary_item "项目地址" "${MEDIA_CHECK_BACKEND_REPO_URL}"
    render_menu_group_start "操作选项"
    render_menu_item "1" "本机直出检测"
    render_menu_item "2" "Warp 出口检测"
    echo "0. 返回主菜单"
    media_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

    case "${media_choice}" in
      1)
        if ! run_media_check_backend; then
          log_warn "流媒体验证脚本执行失败，请检查网络或稍后重试。"
        fi
        ;;
      2)
        if ! run_media_check_via_warp; then
          log_warn "通过 Warp 执行流媒体验证失败，请检查 Warp 配置或稍后重试。"
        fi
        ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

sanitize_ruleset_tag() {
  local value=$1
  value=$(echo "${value}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
  printf '%s' "${value:-warp}"
}

detect_ruleset_format() {
  case "$1" in
    *.srs) printf 'binary' ;;
    *) printf 'source' ;;
  esac
}

save_warp_route_settings() {
  mkdir -p "${SB_PROJECT_DIR}"
  cat > "${SB_WARP_ROUTE_SETTINGS_FILE}" <<EOF
WARP_ROUTE_MODE=${SB_WARP_ROUTE_MODE}
WARP_ENABLED=${SB_ENABLE_WARP}
EOF
}

ensure_warp_routing_assets() {
  mkdir -p "${SB_WARP_LOCAL_RULESET_DIR}"

  if [[ ! -f "${SB_WARP_DOMAINS_FILE}" ]]; then
    cat > "${SB_WARP_DOMAINS_FILE}" <<'EOF'
# 自定义走 Warp 的域名列表
# 以 = 开头表示精确匹配；其他行默认按 domain_suffix 匹配
# openai.com
# =gemini.google.com
EOF
  fi

  if [[ ! -f "${SB_WARP_REMOTE_RULESETS_FILE}" ]]; then
    cat > "${SB_WARP_REMOTE_RULESETS_FILE}" <<'EOF'
# 远程规则集列表：tag|url|update_interval
# 例如：
# openai|https://example.com/openai.json|1d
EOF
  fi

  if [[ ! -f "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]; then
    save_warp_route_settings
  fi
}

load_warp_route_settings() {
  SB_WARP_ROUTE_MODE="selective"

  if [[ -f "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]; then
    local saved_mode
    saved_mode=$(grep '^WARP_ROUTE_MODE=' "${SB_WARP_ROUTE_SETTINGS_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ')
    if validate_warp_route_mode "${saved_mode}"; then
      SB_WARP_ROUTE_MODE="${saved_mode}"
      return 0
    fi
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    SB_WARP_ROUTE_MODE=$(config_detect_warp_route_mode "${SINGBOX_CONFIG_FILE}")
  fi
}

build_custom_warp_domain_json() {
  local exact_file suffix_file raw_line line
  exact_file=$(mktemp)
  suffix_file=$(mktemp)

  if [[ -f "${SB_WARP_DOMAINS_FILE}" ]]; then
    while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
      line=${raw_line%%#*}
      line=$(trim_whitespace "${line}")
      [[ -z "${line}" ]] && continue

      if [[ "${line}" == =* ]]; then
        line=$(trim_whitespace "${line#=}")
        [[ -n "${line}" ]] && printf '%s\n' "${line}" >> "${exact_file}"
      else
        printf '%s\n' "${line}" >> "${suffix_file}"
      fi
    done < "${SB_WARP_DOMAINS_FILE}"
  fi

  if [[ -s "${exact_file}" ]]; then
    SB_WARP_CUSTOM_DOMAINS_JSON=$(jq -Rsc 'split("\n") | map(select(length > 0))' "${exact_file}")
  else
    SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  fi

  if [[ -s "${suffix_file}" ]]; then
    SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON=$(jq -Rsc 'split("\n") | map(select(length > 0))' "${suffix_file}")
  else
    SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  fi

  rm -f "${exact_file}" "${suffix_file}"
}

build_local_warp_rule_sets_json() {
  local object_file file base_name tag format
  object_file=$(mktemp)
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'

  if [[ -d "${SB_WARP_LOCAL_RULESET_DIR}" ]]; then
    while IFS= read -r -d '' file; do
      base_name=$(basename "${file}")
      tag="warp-local-$(sanitize_ruleset_tag "${base_name%.*}")"
      format=$(detect_ruleset_format "${file}")
      jq -n \
        --arg tag "${tag}" \
        --arg path "${file}" \
        --arg format "${format}" \
        '{type: "local", tag: $tag, path: $path, format: $format}' >> "${object_file}"
    done < <(find "${SB_WARP_LOCAL_RULESET_DIR}" -maxdepth 1 -type f \( -name '*.json' -o -name '*.srs' \) -print0 | sort -z)
  fi

  if [[ -s "${object_file}" ]]; then
    SB_WARP_LOCAL_RULE_SETS_JSON=$(jq -s . "${object_file}")
  fi

  rm -f "${object_file}"
}

build_remote_warp_rule_sets_json() {
  local object_file raw_line line raw_tag raw_url raw_interval tag url update_interval format
  local use_http_client="n"
  object_file=$(mktemp)
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'

  if singbox_config_supports_1_14; then
    use_http_client="y"
  fi

  if [[ -f "${SB_WARP_REMOTE_RULESETS_FILE}" ]]; then
    while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
      line=${raw_line%%#*}
      line=$(trim_whitespace "${line}")
      [[ -z "${line}" ]] && continue

      IFS='|' read -r raw_tag raw_url raw_interval <<< "${line}"
      tag=$(sanitize_ruleset_tag "$(trim_whitespace "${raw_tag}")")
      url=$(trim_whitespace "${raw_url:-}")
      update_interval=$(trim_whitespace "${raw_interval:-1d}")

      if [[ -z "${url}" ]]; then
        log_warn "跳过无效的远程规则集配置: ${line}"
        continue
      fi

      format=$(detect_ruleset_format "${url}")
      jq -n \
        --arg tag "warp-remote-${tag}" \
        --arg url "${url}" \
        --arg format "${format}" \
        --arg update_interval "${update_interval:-1d}" \
        --arg use_http_client "${use_http_client}" \
        '{
          type: "remote",
          tag: $tag,
          url: $url,
          format: $format,
          update_interval: $update_interval
        } + (
          if $use_http_client == "y" then
            {http_client: {detour: "direct"}}
          else
            {download_detour: "direct"}
          end
        )' >> "${object_file}"
    done < "${SB_WARP_REMOTE_RULESETS_FILE}"
  fi

  if [[ -s "${object_file}" ]]; then
    SB_WARP_REMOTE_RULE_SETS_JSON=$(jq -s . "${object_file}")
  fi

  rm -f "${object_file}"
}

build_warp_rule_set_tags_json() {
  SB_WARP_RULE_SET_TAGS_JSON=$(jq -n \
    --argjson local_rule_sets "${SB_WARP_LOCAL_RULE_SETS_JSON}" \
    --argjson remote_rule_sets "${SB_WARP_REMOTE_RULE_SETS_JSON}" \
    '$local_rule_sets + $remote_rule_sets | map(.tag)')
}

refresh_warp_route_assets() {
  # Rendering an existing network policy must not create or repair its assets.
  build_custom_warp_domain_json || return 1
  build_local_warp_rule_sets_json || return 1
  build_remote_warp_rule_sets_json || return 1
  build_warp_rule_set_tags_json
}
