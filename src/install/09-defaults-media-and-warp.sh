
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

create_media_check_warp_proxy_config() {
  local output_file=$1
  local proxy_port=$2
  local w_key w_v4 w_v6 w_client_id w_reserved='[]'

  register_warp || return $?

  w_key=$(grep "WARP_PRIV_KEY" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  w_v4=$(grep "WARP_V4" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  w_v6=$(grep "WARP_V6" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  w_client_id=$(grep "WARP_CLIENT_ID" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  w_reserved=$(warp_client_id_to_reserved_json "${w_client_id}")

  if [[ -z "${w_key}" || -z "${w_v4}" || -z "${w_v6}" ]]; then
    log_error "Warp 账户信息不完整，请尝试重新注册 Warp。"
  fi

  jq -n \
    --arg proxy_port "${proxy_port}" \
    --arg w_key "${w_key}" \
    --arg w_v4 "${w_v4}/32" \
    --arg w_v6 "${w_v6}/128" \
    --argjson w_reserved "${w_reserved}" \
    '{
      "log": { "level": "warn", "timestamp": true },
      "endpoints": [
        {
          "type": "wireguard",
          "tag": "warp-ep",
          "address": [ $w_v4, $w_v6 ],
          "private_key": $w_key,
          "peers": [
            {
              "address": "engage.cloudflareclient.com",
              "port": 2408,
              "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
              "reserved": $w_reserved,
              "allowed_ips": [ "0.0.0.0/0", "::/0" ]
            }
          ],
          "mtu": 1280
        }
      ],
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
    }' > "${output_file}"
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

  create_media_check_warp_proxy_config "${proxy_config}" "${proxy_port}"

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
  ensure_warp_routing_assets
  build_custom_warp_domain_json
  build_local_warp_rule_sets_json
  build_remote_warp_rule_sets_json
  build_warp_rule_set_tags_json
}

show_warp_route_assets() {
  ensure_warp_routing_assets
  load_warp_route_settings

  echo -e "\n${BLUE}--- Warp 分流资产 ---${NC}"
  echo -e "当前模式: ${SB_WARP_ROUTE_MODE}"
  echo -e "自定义域名: ${SB_WARP_DOMAINS_FILE}"
  echo -e "本地规则集目录: ${SB_WARP_LOCAL_RULESET_DIR}"
  echo -e "远程规则集列表: ${SB_WARP_REMOTE_RULESETS_FILE}"
}

print_json_string_array() {
  local title=$1
  local json=$2

  echo "${title}:"
  if jq -e 'length > 0' >/dev/null <<< "${json}"; then
    jq -r '.[] | "  - " + .' <<< "${json}"
  else
    echo "  - 无"
  fi
}

print_json_rule_set_array() {
  local title=$1
  local json=$2

  echo "${title}:"
  if jq -e 'length > 0' >/dev/null <<< "${json}"; then
    jq -r '.[] | "  - [" + .tag + "] " + (.path // .url)' <<< "${json}"
  else
    echo "  - 无"
  fi
}

show_effective_warp_route_sources() {
  ensure_warp_routing_assets
  load_current_config_state
  load_warp_route_settings
  refresh_warp_route_assets

  echo -e "\n${BLUE}--- 当前生效的 Warp 分流来源 ---${NC}"
  echo -e "当前模式: ${SB_WARP_ROUTE_MODE}"

  if [[ "${SB_WARP_ROUTE_MODE}" == "all" ]]; then
    echo "说明: 当前为全量 Warp 模式，默认所有代理流量走 Warp。"
    if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
      echo "例外: REALITY 握手域名仍直连；私网地址按高级路由规则处理。"
    else
      echo "例外: 私网地址按高级路由规则处理。"
    fi
  else
    echo "说明: 当前为选择性 Warp 模式，仅命中以下来源的流量走 Warp。"
  fi

  print_json_string_array "内置 AI 精确域名" "${WARP_AI_ROUTE_DOMAINS_JSON}"
  print_json_string_array "内置 AI 域名后缀" "${WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON}"
  print_json_string_array "内置流媒体精确域名" "${WARP_STREAM_ROUTE_DOMAINS_JSON}"
  print_json_string_array "内置流媒体域名后缀" "${WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON}"
  print_json_string_array "自定义精确域名" "${SB_WARP_CUSTOM_DOMAINS_JSON}"
  print_json_string_array "自定义域名后缀" "${SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON}"
  print_json_rule_set_array "本地规则集" "${SB_WARP_LOCAL_RULE_SETS_JSON}"
  print_json_rule_set_array "远程规则集" "${SB_WARP_REMOTE_RULE_SETS_JSON}"
}

set_warp_route_mode_interactive() {
  echo
  render_left_aligned_page_header "Warp 路由模式" "选择当前实例的 Warp 出口策略"
  render_section_title "当前设置"
  render_summary_item "当前模式" "${SB_WARP_ROUTE_MODE}"
  render_menu_group_start "模式选项"
  render_menu_item "1" "全量流量走 Warp"
  render_menu_item "2" "仅 AI/流媒体及自定义规则走 Warp"
  if [[ "${SB_WARP_ROUTE_MODE}" == "all" ]]; then
    mode_choice=$(prompt_choice "请选择 [1-2] (当前: ${SB_WARP_ROUTE_MODE}): " 1 2 1)
  else
    mode_choice=$(prompt_choice "请选择 [1-2] (当前: ${SB_WARP_ROUTE_MODE}): " 1 2 2)
  fi

  case "${mode_choice}" in
    1) SB_WARP_ROUTE_MODE="all" ;;
    2) SB_WARP_ROUTE_MODE="selective" ;;
  esac

  save_warp_route_settings
  return 0
}

add_warp_domain_entry() {
  ensure_warp_routing_assets

  local domain_entry
  read -rp "请输入域名（= 前缀表示精确匹配，其余默认 suffix 匹配）: " domain_entry
  domain_entry=$(trim_whitespace "${domain_entry}")

  if [[ -z "${domain_entry}" ]]; then
    log_warn "域名为空，未写入。"
    return 1
  fi

  if ! [[ "${domain_entry}" =~ ^=?[A-Za-z0-9._-]+$ ]]; then
    log_warn "域名格式无效，未写入。"
    return 1
  fi

  if grep -Fxq "${domain_entry}" "${SB_WARP_DOMAINS_FILE}" 2>/dev/null; then
    log_warn "域名已存在于 Warp 分流列表。"
    return 1
  fi

  printf '%s\n' "${domain_entry}" >> "${SB_WARP_DOMAINS_FILE}"
  log_success "已写入 Warp 分流域名: ${domain_entry}"
  return 0
}

add_remote_warp_rule_set() {
  ensure_warp_routing_assets

  local tag url update_interval
  read -rp "请输入远程规则集标签: " tag
  tag=$(sanitize_ruleset_tag "$(trim_whitespace "${tag}")")

  if [[ -z "${tag}" ]]; then
    log_warn "标签为空，未写入。"
    return 1
  fi

  while true; do
    read -rp "请输入远程规则集 URL: " url
    url=$(trim_whitespace "${url}")
    validate_http_url "${url}" && break
    log_warn "远程规则集 URL 必须以 http:// 或 https:// 开头。"
  done

  while true; do
    read -rp "请输入更新周期 (默认 1d): " update_interval
    update_interval=$(trim_whitespace "${update_interval:-1d}")
    validate_update_interval "${update_interval}" && break
    log_warn "更新周期格式必须为正整数加单位 s/m/h/d，例如 1d。"
  done

  printf '%s|%s|%s\n' "${tag}" "${url}" "${update_interval:-1d}" >> "${SB_WARP_REMOTE_RULESETS_FILE}"
  log_success "已写入远程 Warp 规则集: ${tag}"
  return 0
}

import_recommended_warp_rule_sets() {
  ensure_warp_routing_assets

  local entry imported_count=0 skipped_count=0

  for entry in "${WARP_RECOMMENDED_RULESETS[@]}"; do
    if grep -Fxq "${entry}" "${SB_WARP_REMOTE_RULESETS_FILE}" 2>/dev/null; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    printf '%s\n' "${entry}" >> "${SB_WARP_REMOTE_RULESETS_FILE}"
    imported_count=$((imported_count + 1))
  done

  if [[ ${imported_count} -gt 0 ]]; then
    log_success "已导入 ${imported_count} 条推荐 Warp 规则源。"
  fi

  if [[ ${skipped_count} -gt 0 ]]; then
    log_info "已跳过 ${skipped_count} 条已存在的推荐 Warp 规则源。"
  fi

  [[ ${imported_count} -gt 0 ]]
}
