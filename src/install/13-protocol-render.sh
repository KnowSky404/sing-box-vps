
# --- Protocol State Helpers ---
list_effective_protocols() {
  local inventory_state_file=${1:-} installed
  installed=$(extract_protocols_from_index)

  if [[ -n "${installed}" ]]; then
    list_installed_protocols "${inventory_state_file}"
    return $?
  fi

  validate_protocol_index_for_rebuild || return 1
  runtime_protocol_to_state "${SB_PROTOCOL}" || return 1
  printf '\n'
}

load_protocol_state() {
  local protocol state_file state_mode=${2:-mutable} mixed_schema socks_schema
  protocol=$(normalize_protocol_id "$1") || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  mixed_schema=""
  socks_schema=""
  if [[ "${protocol}" == "mixed" && -f "${state_file}" ]]; then
    if grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=(2|\"2\"|'2')[[:space:]]*$" "${state_file}"; then
      mixed_schema=2
    else
      mixed_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" | head -n1) || return 1
      mixed_schema=${mixed_schema//\"/}
      mixed_schema=${mixed_schema//\'/}
    fi
  fi
  if [[ ("${protocol}" == "vless-plain" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "anytls" || "${protocol}" == "hy2" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls") && -f "${state_file}" ]]; then
    socks_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" | head -n1) || return 1
    socks_schema=${socks_schema//\"/}
    socks_schema=${socks_schema//\'/}
  fi
  validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
  if [[ "${protocol}" == "vless-reality" && "${state_mode}" != "read-only" ]]; then
    migrate_vless_reality_state_to_instances_if_needed
  fi
  state_file=$(protocol_state_file "${protocol}")

  if [[ ! -f "${state_file}" ]]; then
    [[ "${state_mode}" == "read-only" ]] && return 1
    if [[ "$(runtime_protocol_to_state "${SB_PROTOCOL}")" == "${protocol}" ]]; then
      return 0
    fi
    log_error "未找到协议状态文件: ${state_file}"
  fi

  # Schema-2 Mixed markers are data-only metadata.  Dispatch before sourcing
  # the file, and fail closed if a concurrent rewrite leaves a schema-2 marker
  # malformed; schema-1 legacy loading below remains unchanged.
  if [[ "${protocol}" == "mixed" && "${mixed_schema}" == "2" ]]; then
    mixed_structured_marker_is_valid "${state_file}" || return 1
    load_mixed_structured_instance || return 1
    return 0
  fi
  if [[ "${protocol}" == "mixed" ]]; then
    if mixed_structured_marker_is_valid "${state_file}"; then
      load_mixed_structured_instance || return 1
      return 0
    fi
    if grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=(2|\"2\"|'2')[[:space:]]*$" "${state_file}"; then
      mixed_schema=2
    else
      mixed_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" | head -n1) || return 1
      mixed_schema=${mixed_schema//\"/}
      mixed_schema=${mixed_schema//\'/}
    fi
    [[ "${mixed_schema}" == "2" ]] && return 1
  fi

  # SOCKS has no legacy .env representation.  Dispatch only a validated
  # schema-2 marker to the typed store and reject every older/unknown shape
  # before it can be sourced as shell code.
  if [[ "${protocol}" == "vless-plain" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || ("${protocol}" == "anytls" && "${socks_schema}" == "2") || ("${protocol}" == "hy2" && "${socks_schema}" == "2") || ("${protocol}" == "snell" && "${socks_schema}" == "2") || ("${protocol}" == "tuic" && "${socks_schema}" == "2") || ("${protocol}" == "hysteria" && "${socks_schema}" == "2") || ("${protocol}" == "naive" && "${socks_schema}" == "2") || ("${protocol}" == "shadowtls" && "${socks_schema}" == "2") ]]; then
    [[ "${socks_schema}" == "2" ]] || return 1
    plain_proxy_structured_marker_is_valid "${state_file}" || return 1
    load_plain_proxy_structured_instance "${protocol}" || return 1
    return 0
  fi

  unset ACME_EXTRA_JSON || true
  # shellcheck disable=SC1090
  source "${state_file}"

  case "${protocol}" in
    vless-reality)
      if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]]; then
        load_vless_reality_protocol_state
        load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" || true
        unset NODE_NAME PORT UUID SNI SHORT_ID_1 SHORT_ID_2
      fi
      SB_PROTOCOL="vless+reality"
      SB_NODE_NAME="${NODE_NAME:-${SB_NODE_NAME:-$(default_node_name_for_protocol "vless+reality")}}"
      SB_PORT="${PORT:-${SB_PORT:-443}}"
      SB_UUID="${UUID:-${SB_UUID:-}}"
      SB_SNI="${SNI:-${SB_SNI:-}}"
      SB_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-${SB_PRIVATE_KEY:-}}"
      SB_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-${SB_PUBLIC_KEY:-}}"
      SB_SHORT_ID_1="${SHORT_ID_1:-${SB_SHORT_ID_1:-}}"
      SB_SHORT_ID_2="${SHORT_ID_2:-${SB_SHORT_ID_2:-}}"
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
      SB_HY2_ACME_EXTRA_JSON='{}'
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
      SB_HY2_MASQUERADE=""
      SB_ANYTLS_DOMAIN=""
      SB_ANYTLS_PASSWORD=""
      SB_ANYTLS_USER_NAME=""
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
    mixed)
      if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]]; then
        load_mixed_structured_instance || return 1
        return 0
      fi
      SB_PROTOCOL="mixed"
      SB_NODE_NAME=$(normalize_node_name "${NODE_NAME:-$(default_node_name_for_protocol "mixed")}")
      SB_PORT="${PORT:-1080}"
      SB_UUID=""
      SB_SNI=""
      SB_PRIVATE_KEY=""
      SB_PUBLIC_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="${AUTH_ENABLED:-y}"
      SB_MIXED_USERNAME="${USERNAME:-}"
      SB_MIXED_PASSWORD="${PASSWORD:-}"
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
      SB_HY2_ACME_EXTRA_JSON='{}'
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
      SB_HY2_MASQUERADE=""
      SB_ANYTLS_DOMAIN=""
      SB_ANYTLS_PASSWORD=""
      SB_ANYTLS_USER_NAME=""
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
    hy2)
      SB_PROTOCOL="hy2"
      SB_NODE_NAME=$(normalize_node_name "${NODE_NAME:-$(default_node_name_for_protocol "hy2")}")
      SB_PORT="${PORT:-443}"
      SB_UUID=""
      SB_SNI=""
      SB_PRIVATE_KEY=""
      SB_PUBLIC_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_HY2_DOMAIN="${DOMAIN:-}"
      SB_HY2_PASSWORD="${PASSWORD:-}"
      SB_HY2_USER_NAME="${USER_NAME:-}"
      SB_HY2_UP_MBPS="${UP_MBPS:-}"
      SB_HY2_DOWN_MBPS="${DOWN_MBPS:-}"
      SB_HY2_OBFS_ENABLED="${OBFS_ENABLED:-n}"
      SB_HY2_OBFS_TYPE="${OBFS_TYPE:-}"
      SB_HY2_OBFS_PASSWORD="${OBFS_PASSWORD:-}"
      SB_HY2_TLS_MODE="${TLS_MODE:-acme}"
      SB_HY2_ACME_MODE="${ACME_MODE:-http}"
      SB_HY2_ACME_EMAIL="${ACME_EMAIL:-}"
      SB_HY2_ACME_DOMAIN="${ACME_DOMAIN:-}"
      SB_HY2_ACME_EXTRA_JSON=$(acme_extra_json_or_default "${ACME_EXTRA_JSON:-}")
      SB_HY2_DNS_PROVIDER="${DNS_PROVIDER:-cloudflare}"
      SB_HY2_CF_API_TOKEN="${CF_API_TOKEN:-}"
      SB_HY2_CERT_PATH="${CERT_PATH:-}"
      SB_HY2_KEY_PATH="${KEY_PATH:-}"
      SB_HY2_MASQUERADE="${MASQUERADE:-}"
      SB_ANYTLS_DOMAIN=""
      SB_ANYTLS_PASSWORD=""
      SB_ANYTLS_USER_NAME=""
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
    anytls)
      SB_PROTOCOL="anytls"
      SB_NODE_NAME=$(normalize_node_name "${NODE_NAME:-$(default_node_name_for_protocol "anytls")}")
      SB_PORT="${PORT:-443}"
      SB_UUID=""
      SB_SNI=""
      SB_PRIVATE_KEY=""
      SB_PUBLIC_KEY=""
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
      SB_HY2_ACME_EXTRA_JSON='{}'
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
      SB_HY2_MASQUERADE=""
      SB_ANYTLS_DOMAIN="${DOMAIN:-}"
      SB_ANYTLS_PASSWORD="${PASSWORD:-}"
      SB_ANYTLS_USER_NAME="${USER_NAME:-}"
      SB_ANYTLS_TLS_MODE="${TLS_MODE:-acme}"
      SB_ANYTLS_ACME_MODE="${ACME_MODE:-http}"
      SB_ANYTLS_ACME_EMAIL="${ACME_EMAIL:-}"
      SB_ANYTLS_ACME_DOMAIN="${ACME_DOMAIN:-}"
      SB_ANYTLS_ACME_EXTRA_JSON=$(acme_extra_json_or_default "${ACME_EXTRA_JSON:-}")
      SB_ANYTLS_DNS_PROVIDER="${DNS_PROVIDER:-cloudflare}"
      SB_ANYTLS_CF_API_TOKEN="${CF_API_TOKEN:-}"
      SB_ANYTLS_CERT_PATH="${CERT_PATH:-}"
      SB_ANYTLS_KEY_PATH="${KEY_PATH:-}"
      ;;
    snell)
      SB_PROTOCOL="snell"
      SB_NODE_NAME=$(normalize_node_name "${NODE_NAME:-$(default_node_name_for_protocol "snell")}")
      SB_PORT="${PORT:-1080}"
      SB_UUID=""
      SB_SNI=""
      SB_PRIVATE_KEY=""
      SB_PUBLIC_KEY=""
      SB_SHORT_ID_1=""
      SB_SHORT_ID_2=""
      SB_MIXED_AUTH_ENABLED="n"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
      SB_SNELL_VERSION="${SNELL_VERSION:-6}"
      SB_SNELL_PSK="${SNELL_PSK:-}"
      SB_SNELL_USER_JSON="${SNELL_USERS:-${SNELL_USER_JSON:-[]}}"
      SB_SNELL_OBFS_MODE="${SNELL_OBFS_MODE:-}"
      SB_SNELL_OBFS_HOST="${SNELL_OBFS_HOST:-}"
      SB_SNELL_MODE="${SNELL_MODE:-}"
      SB_OUTBOUND_POLICY="default"
      ;;
  esac
}

ensure_vless_reality_materials() {
  ensure_protocol_state_dir

  if [[ -z "${SB_UUID}" ]]; then
    SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  fi

  if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
    if [[ -f "${SB_KEY_FILE}" ]]; then
      log_info "使用现有密钥对..." >&2
      [[ -z "${SB_PRIVATE_KEY}" ]] && SB_PRIVATE_KEY=$(grep '^PRIVATE_KEY=' "${SB_KEY_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ' || true)
      [[ -z "${SB_PUBLIC_KEY}" ]] && SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ' || true)
    fi
  fi

  if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
    log_info "正在生成新的 REALITY 密钥对..." >&2
    local keypair
    keypair=$(run_singbox_generate_command "reality-keypair" "REALITY 密钥") || exit 1
    SB_PRIVATE_KEY=$(extract_generated_key_value "${keypair}" "private")
    SB_PUBLIC_KEY=$(extract_generated_key_value "${keypair}" "public")
    if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
      log_info "REALITY 密钥生成输出格式非法（原始输出未记录）。" >> "${SBV_LOG_FILE}"
      log_error "REALITY 密钥生成失败（输出格式非法），请查看 ${SBV_LOG_FILE}"
    fi
    {
      echo "PRIVATE_KEY=${SB_PRIVATE_KEY}"
      echo "PUBLIC_KEY=${SB_PUBLIC_KEY}"
    } > "${SB_KEY_FILE}"
  fi

  if [[ -z "${SB_SHORT_ID_1}" ]]; then
    SB_SHORT_ID_1=$(openssl rand -hex 8)
  fi

  if [[ -z "${SB_SHORT_ID_2}" ]]; then
    SB_SHORT_ID_2=$(openssl rand -hex 8)
  fi

  save_vless_reality_protocol_material_state_if_v2
  if [[ -n "${SB_VLESS_INSTANCE_ID:-}" ]] && [[ -f "$(vless_reality_instance_state_file "${SB_VLESS_INSTANCE_ID}")" ]]; then
    save_vless_reality_instance_state
  fi

  return 0
}

ensure_hy2_materials() {
  if [[ -z "${SB_HY2_USER_NAME}" ]]; then
    SB_HY2_USER_NAME="hy2-user"
  fi

  ensure_hy2_password

  if [[ -z "${SB_HY2_ACME_DOMAIN}" ]]; then
    SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
  fi

  ensure_hy2_obfs_settings

  return 0
}

ensure_anytls_materials() {
  if [[ -z "${SB_ANYTLS_USER_NAME}" ]]; then
    SB_ANYTLS_USER_NAME="anytls-user"
  fi

  if [[ -z "${SB_ANYTLS_PASSWORD}" ]]; then
    SB_ANYTLS_PASSWORD=$(generate_random_token "" 8)
  fi

  if [[ -z "${SB_ANYTLS_ACME_DOMAIN}" ]]; then
    SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
  fi

  return 0
}

generate_snell_psk() {
  # Snell v6 requires at least 12 bytes; hex output is portable and avoids
  # shell/JSON control characters while retaining sufficient entropy.
  generate_random_token "" 16
}

ensure_snell_materials() {
  local user_json
  if [[ -z "${SB_SNELL_PSK:-}" ]]; then
    SB_SNELL_PSK=$(generate_snell_psk)
  fi
  case "${SB_SNELL_VERSION:-6}" in
    5)
      SB_SNELL_VERSION=5
      [[ -n "${SB_SNELL_OBFS_MODE:-}" ]] || SB_SNELL_OBFS_MODE="none"
      [[ "${SB_SNELL_OBFS_MODE}" == "none" ]] && SB_SNELL_OBFS_HOST=""
      SB_SNELL_MODE=""
      ;;
    6)
      SB_SNELL_VERSION=6
      SB_SNELL_OBFS_MODE=""
      SB_SNELL_OBFS_HOST=""
      [[ -n "${SB_SNELL_MODE:-}" ]] || SB_SNELL_MODE="default"
      ;;
    *) return 1 ;;
  esac
  if [[ -z "${SB_SNELL_USER_JSON:-}" ]]; then
    SB_SNELL_USER_JSON='[]'
  fi
  user_json=$(jq -c . <<< "${SB_SNELL_USER_JSON}") || return 1
  SB_SNELL_USER_JSON=${user_json}
}

ensure_tuic_materials() {
  local user_json tls_json
  SB_TUIC_CONGESTION_CONTROL=${SB_TUIC_CONGESTION_CONTROL:-bbr}
  [[ "${SB_TUIC_CONGESTION_CONTROL}" == cubic || "${SB_TUIC_CONGESTION_CONTROL}" == new_reno || "${SB_TUIC_CONGESTION_CONTROL}" == bbr ]] || return 1
  SB_TUIC_AUTH_TIMEOUT_SECONDS=${SB_TUIC_AUTH_TIMEOUT_SECONDS:-3}
  SB_TUIC_HEARTBEAT_SECONDS=${SB_TUIC_HEARTBEAT_SECONDS:-10}
  [[ "${SB_TUIC_AUTH_TIMEOUT_SECONDS}" =~ ^[0-9]+$ && "${SB_TUIC_AUTH_TIMEOUT_SECONDS}" -le 86400 ]] || return 1
  [[ "${SB_TUIC_HEARTBEAT_SECONDS}" =~ ^[0-9]+$ && "${SB_TUIC_HEARTBEAT_SECONDS}" -le 86400 ]] || return 1
  SB_TUIC_ZERO_RTT_HANDSHAKE=${SB_TUIC_ZERO_RTT_HANDSHAKE:-n}
  SB_TUIC_UDP_RELAY_MODE=${SB_TUIC_UDP_RELAY_MODE:-native}
  SB_TUIC_UDP_OVER_STREAM=${SB_TUIC_UDP_OVER_STREAM:-n}
  [[ "${SB_TUIC_ZERO_RTT_HANDSHAKE}" == y || "${SB_TUIC_ZERO_RTT_HANDSHAKE}" == n ]] || return 1
  [[ "${SB_TUIC_UDP_RELAY_MODE}" == "" || "${SB_TUIC_UDP_RELAY_MODE}" == native || "${SB_TUIC_UDP_RELAY_MODE}" == quic ]] || return 1
  [[ "${SB_TUIC_UDP_OVER_STREAM}" == y || "${SB_TUIC_UDP_OVER_STREAM}" == n ]] || return 1
  if [[ "${SB_TUIC_UDP_OVER_STREAM}" == y ]]; then
    SB_TUIC_UDP_RELAY_MODE=""
  elif [[ -z "${SB_TUIC_UDP_RELAY_MODE}" ]]; then
    SB_TUIC_UDP_RELAY_MODE=native
  fi
  user_json=$(jq -c . <<< "${SB_TUIC_AUTH_JSON:-[]}") || return 1
  if [[ "${user_json}" == "[]" ]]; then
    user_json=$(jq -cn --arg uuid "$(tuic_generate_uuid)" --arg password "$(trojan_generate_password)" '[{name:"tuic-user-1",uuid:$uuid,password:$password}]') || return 1
  fi
  jq -e 'type == "array" and length >= 1 and length <= 128' <<< "${user_json}" >/dev/null || return 1
  SB_TUIC_AUTH_JSON=${user_json}
  tls_json=$(jq -c . <<< "${SB_TUIC_TLS_JSON:-'{"enabled":false}'}") || return 1
  jq -e 'type == "object" and .enabled == true and (keys|sort) == ["certificate_path","enabled","key_path","server_name"] and (.server_name|type=="string" and length>0) and (.certificate_path|type=="string" and startswith("/")) and (.key_path|type=="string" and startswith("/"))' <<< "${tls_json}" >/dev/null || return 1
  SB_TUIC_TLS_JSON=${tls_json}
  SB_TUIC_CLIENT_TRUST=${SB_TUIC_CLIENT_TRUST:-system}
  [[ "${SB_TUIC_CLIENT_TRUST}" == certificate || "${SB_TUIC_CLIENT_TRUST}" == system ]] || return 1
}

ensure_hysteria_materials() {
  local user_json tls_json obfs_password quic_json
  SB_HYSTERIA_UP_MBPS=${SB_HYSTERIA_UP_MBPS:-100}
  SB_HYSTERIA_DOWN_MBPS=${SB_HYSTERIA_DOWN_MBPS:-100}
  [[ "${SB_HYSTERIA_UP_MBPS}" =~ ^[1-9][0-9]*$ && "${SB_HYSTERIA_UP_MBPS}" -le 1000000 ]] || return 1
  [[ "${SB_HYSTERIA_DOWN_MBPS}" =~ ^[1-9][0-9]*$ && "${SB_HYSTERIA_DOWN_MBPS}" -le 1000000 ]] || return 1

  user_json=$(jq -c . <<< "${SB_HYSTERIA_AUTH_JSON:-[]}") || return 1
  if [[ "${user_json}" == "[]" ]]; then
    user_json=$(jq -cn --arg password "$(trojan_generate_password)" '[{name:"hysteria-user-1",auth_str:$password}]') || return 1
  fi
  jq -e 'type == "array" and length >= 1 and length <= 128 and
    all(.[]; type == "object" and (keys|sort) == ["auth_str","name"] and
      (.name|type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]")|not)) and
      (.auth_str|type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not))) and
    (map(.name)|unique|length) == length and (map(.auth_str)|unique|length) == length' <<< "${user_json}" >/dev/null || return 1
  SB_HYSTERIA_AUTH_JSON=${user_json}

  tls_json=$(jq -c . <<< "${SB_HYSTERIA_TLS_JSON:-'{"enabled":false}'}") || return 1
  jq -e 'type == "object" and .enabled == true and (keys|sort) == ["certificate_path","enabled","key_path","server_name"] and
    (.server_name|type == "string" and length > 0) and
    (.certificate_path|type == "string" and startswith("/")) and
    (.key_path|type == "string" and startswith("/"))' <<< "${tls_json}" >/dev/null || return 1
  SB_HYSTERIA_TLS_JSON=${tls_json}
  SB_HYSTERIA_CLIENT_TRUST=${SB_HYSTERIA_CLIENT_TRUST:-system}
  [[ "${SB_HYSTERIA_CLIENT_TRUST}" == certificate || "${SB_HYSTERIA_CLIENT_TRUST}" == system ]] || return 1

  SB_HYSTERIA_OBFS_ENABLED=${SB_HYSTERIA_OBFS_ENABLED:-n}
  [[ "${SB_HYSTERIA_OBFS_ENABLED}" == y || "${SB_HYSTERIA_OBFS_ENABLED}" == n ]] || return 1
  obfs_password=${SB_HYSTERIA_OBFS_PASSWORD:-}
  if [[ "${SB_HYSTERIA_OBFS_ENABLED}" == y ]]; then
    [[ -n "${obfs_password}" ]] || obfs_password=$(trojan_generate_password) || return 1
    [[ "${obfs_password}" != *$'\n'* && "${obfs_password}" != *$'\r'* ]] || return 1
  else
    obfs_password=""
  fi
  SB_HYSTERIA_OBFS_PASSWORD=${obfs_password}

  quic_json=$(jq -c . <<< "${SB_HYSTERIA_QUIC_JSON:-'{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'}") || return 1
  jq -e 'type == "object" and (keys|sort) == ["connection_receive_window","disable_path_mtu_discovery","initial_packet_size","max_concurrent_streams","stream_receive_window"] and
    (.initial_packet_size|type == "number" and floor == . and . >= 0 and . <= 65535) and
    (.max_concurrent_streams|type == "number" and floor == . and . >= 0 and . <= 65535) and
    (.disable_path_mtu_discovery|type == "boolean") and
    (.stream_receive_window|type == "string" and length <= 64 and (test("^$|^[0-9]+( ?(B|KB|MB|GB))$"))) and
    (.connection_receive_window|type == "string" and length <= 64 and (test("^$|^[0-9]+( ?(B|KB|MB|GB))$")))' <<< "${quic_json}" >/dev/null || return 1
  SB_HYSTERIA_QUIC_JSON=${quic_json}
}

ensure_naive_materials() {
  local user_json tls_json network_json extra_headers_json
  local window_pattern='^$|^[0-9]+( ?(B|KB|MB|GB))$'

  user_json=$(jq -c . <<< "${SB_NAIVE_AUTH_JSON:-[]}") || return 1
  if [[ "${user_json}" == "[]" ]]; then
    user_json=$(jq -cn --arg password "$(trojan_generate_password)" '[{name:"naive-user-1",username:"naive-user-1",password:$password}]') || return 1
  fi
  jq -e 'type == "array" and length >= 1 and length <= 128 and
    all(.[]; type == "object" and (keys|sort) == ["name","password","username"] and
      (.name|type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]")|not)) and
      (.username|type == "string" and length > 0 and utf8bytelength <= 4096 and (contains(":")|not) and (test("[\u0000-\u001F\u007F]")|not)) and
      (.password|type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not))) and
    (map(.name)|unique|length) == length and (map(.username)|unique|length) == length' <<< "${user_json}" >/dev/null || return 1
  SB_NAIVE_AUTH_JSON=${user_json}

  tls_json=$(jq -c . <<< "${SB_NAIVE_TLS_JSON:-'{"enabled":false}'}") || return 1
  jq -e 'type == "object" and .enabled == true and (keys|sort) == ["certificate_path","enabled","key_path","server_name"] and
    (.server_name|type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]")|not)) and
    (.certificate_path|type == "string" and startswith("/") and (test("[\u0000-\u001F\u007F]")|not)) and
    (.key_path|type == "string" and startswith("/") and (test("[\u0000-\u001F\u007F]")|not))' <<< "${tls_json}" >/dev/null || return 1
  SB_NAIVE_TLS_JSON=${tls_json}
  SB_NAIVE_CLIENT_TRUST=${SB_NAIVE_CLIENT_TRUST:-system}
  [[ "${SB_NAIVE_CLIENT_TRUST}" == certificate || "${SB_NAIVE_CLIENT_TRUST}" == system ]] || return 1

  network_json=$(jq -c . <<< "${SB_NAIVE_NETWORK_JSON:-'["tcp","udp"]'}") || return 1
  jq -e 'type == "array" and length >= 1 and length <= 2 and all(.[]; . == "tcp" or . == "udp") and . == (sort|unique)' <<< "${network_json}" >/dev/null || return 1
  SB_NAIVE_NETWORK_JSON=${network_json}
  SB_NAIVE_QUIC_CONGESTION_CONTROL=${SB_NAIVE_QUIC_CONGESTION_CONTROL:-bbr}
  [[ "${SB_NAIVE_QUIC_CONGESTION_CONTROL}" == bbr || "${SB_NAIVE_QUIC_CONGESTION_CONTROL}" == cubic || "${SB_NAIVE_QUIC_CONGESTION_CONTROL}" == reno ]] || return 1
  SB_NAIVE_QUIC=${SB_NAIVE_QUIC:-n}
  [[ "${SB_NAIVE_QUIC}" == y || "${SB_NAIVE_QUIC}" == n ]] || return 1
  SB_NAIVE_INSECURE_CONCURRENCY=${SB_NAIVE_INSECURE_CONCURRENCY:-0}
  [[ "${SB_NAIVE_INSECURE_CONCURRENCY}" =~ ^[0-9]+$ && "${SB_NAIVE_INSECURE_CONCURRENCY}" -le 1024 ]] || return 1
  SB_NAIVE_STREAM_RECEIVE_WINDOW=${SB_NAIVE_STREAM_RECEIVE_WINDOW:-}
  SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW=${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW:-}
  [[ "${SB_NAIVE_STREAM_RECEIVE_WINDOW}" =~ ${window_pattern} && "${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW}" =~ ${window_pattern} ]] || return 1
  extra_headers_json=$(jq -c . <<< "${SB_NAIVE_EXTRA_HEADERS_JSON:-'{}'}") || return 1
  jq -e 'type == "object" and length <= 64 and all(to_entries[];
    (.key | type == "string" and length > 0 and length <= 128 and (test("^[!#$%&\\u0027*+.^_`|~0-9A-Za-z-]+$"))) and
    (.value | type == "string" and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not)))' <<< "${extra_headers_json}" >/dev/null || return 1
  SB_NAIVE_EXTRA_HEADERS_JSON=${extra_headers_json}
}

stack_inbound_listen_address() {
  ensure_stack_mode_state_loaded

  case "${SB_INBOUND_STACK_MODE}" in
    ipv4_only) printf '0.0.0.0' ;;
    *) printf '::' ;;
  esac
}

build_vless_inbound_json_for_instance() {
  local instance_id=$1 tag alpn_json

  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${instance_id}" || return 1
  ensure_vless_reality_materials
  tag=$(vless_reality_inbound_tag_for_instance "${instance_id}")
  alpn_json=$(vless_reality_alpn_json_for_mode "${SB_VLESS_ALPN_MODE:-off}")

  jq -n \
    --arg tag "${tag}" \
    --arg instance_id "${instance_id}" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg sni "${SB_SNI}" \
    --arg priv_key "${SB_PRIVATE_KEY}" \
    --arg sid1 "${SB_SHORT_ID_1}" \
    --arg sid2 "${SB_SHORT_ID_2}" \
    --arg tcp_fast_open "${SB_VLESS_TCP_FAST_OPEN:-n}" \
    --argjson alpn "${alpn_json}" \
    '{
      "type": "vless",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber),
      "users": [ { "name": $instance_id, "uuid": $uuid, "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": $sni,
        "reality": {
          "enabled": true,
          "handshake": { "server": $sni, "server_port": 443 },
          "private_key": $priv_key,
          "short_id": [ $sid1, $sid2 ]
        }
      }
    }
    | if $tcp_fast_open == "y" then . + { "tcp_fast_open": true } else . end
    | if $alpn == null then . else .tls += { "alpn": $alpn } end'
}

build_vless_inbound_json_from_current_state() {
  local alpn_json

  ensure_vless_reality_materials
  SB_VLESS_ALPN_MODE="${SB_VLESS_ALPN_MODE:-off}"
  SB_VLESS_TCP_FAST_OPEN="${SB_VLESS_TCP_FAST_OPEN:-n}"
  alpn_json=$(vless_reality_alpn_json_for_mode "${SB_VLESS_ALPN_MODE}")

  VLESS_REALITY_DEFAULT_INSTANCE_ID="main"
  VLESS_REALITY_INSTANCE_IDS="main"
  SB_VLESS_INSTANCE_ID="main"
  SB_VLESS_INBOUND_TAG="vless-in"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state

  jq -n \
    --arg tag "vless-in" \
    --arg instance_id "main" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg sni "${SB_SNI}" \
    --arg priv_key "${SB_PRIVATE_KEY}" \
    --arg sid1 "${SB_SHORT_ID_1}" \
    --arg sid2 "${SB_SHORT_ID_2}" \
    --arg tcp_fast_open "${SB_VLESS_TCP_FAST_OPEN:-n}" \
    --argjson alpn "${alpn_json}" \
    '{
      "type": "vless",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber),
      "users": [ { "name": $instance_id, "uuid": $uuid, "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": $sni,
        "reality": {
          "enabled": true,
          "handshake": { "server": $sni, "server_port": 443 },
          "private_key": $priv_key,
          "short_id": [ $sid1, $sid2 ]
        }
      }
    }
    | if $tcp_fast_open == "y" then . + { "tcp_fast_open": true } else . end
    | if $alpn == null then . else .tls += { "alpn": $alpn } end'
}

build_vless_inbound_json() {
  local instance_id instance_ids=()

  migrate_vless_reality_state_to_instances_if_needed
  validate_vless_reality_instance_tags || return 1
  mapfile -t instance_ids < <(list_vless_reality_instance_ids)

  if [[ ${#instance_ids[@]} -eq 0 ]]; then
    build_vless_inbound_json_from_current_state
    return 0
  fi

  for instance_id in "${instance_ids[@]}"; do
    build_vless_inbound_json_for_instance "${instance_id}" || return 1
  done
}

build_mixed_inbound_json() {
  local state_file
  state_file=$(protocol_state_file "mixed") || return 1
  if [[ -f "${state_file}" ]] &&
     grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=(2|\"2\"|'2')[[:space:]]*$" "${state_file}"; then
    mixed_structured_state_active || return 1
    render_structured_instance_inbounds mixed "$(mixed_structured_store_file)"
    return $?
  fi
  ensure_mixed_auth_credentials

  jq -n \
    --arg tag "mixed-in" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg mixed_auth_enabled "${SB_MIXED_AUTH_ENABLED}" \
    --arg mixed_username "${SB_MIXED_USERNAME}" \
    --arg mixed_password "${SB_MIXED_PASSWORD}" \
    '{
      "type": "mixed",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber)
    } + (
      if $mixed_auth_enabled == "y" then
        {
          "users": [
            {
              "username": $mixed_username,
              "password": $mixed_password
            }
          ]
        }
      else
        {}
      end
    )'
}

build_socks_inbound_json() {
  local state_file
  state_file=$(protocol_state_file socks) || return 1
  plain_proxy_structured_state_active socks || {
    printf '[ERROR] SOCKS 结构化状态缺失或无效，未生成入站。\n' >&2
    return 1
  }
  render_structured_instance_inbounds socks "$(plain_proxy_structured_store_file socks)"
}

build_http_inbound_json() {
  plain_proxy_structured_state_active http || return 1
  render_structured_instance_inbounds http "$(plain_proxy_structured_store_file http)"
}

build_shadowsocks_inbound_json() {
  plain_proxy_structured_state_active shadowsocks || return 1
  render_structured_instance_inbounds shadowsocks "$(plain_proxy_structured_store_file shadowsocks)"
}

build_trojan_inbound_json() {
  local store_file
  plain_proxy_structured_state_active trojan || return 1
  store_file=$(plain_proxy_structured_store_file trojan) || return 1
  # render_structured_instance_inbounds captures and validates one snapshot;
  # client_trust remains metadata and is never emitted to the server.
  render_structured_instance_inbounds trojan "${store_file}"
}

build_vmess_inbound_json() {
  local store_file
  plain_proxy_structured_state_active vmess || return 1
  store_file=$(plain_proxy_structured_store_file vmess) || return 1
  # VMess security is client-side metadata; the server accepts only name/UUID
  # and alterId.  The renderer also derives transport ALPN from the typed
  # profile and never emits an explicit disabled TLS object.
  render_structured_instance_inbounds vmess "${store_file}"
}

build_vless_plain_inbound_json() {
  local store_file
  plain_proxy_structured_state_active vless-plain || return 1
  store_file=$(plain_proxy_structured_store_file vless-plain) || return 1
  render_structured_instance_inbounds vless-plain "${store_file}"
}

build_snell_inbound_json() {
  local store_file
  plain_proxy_structured_state_active snell || {
    printf '[ERROR] Snell 结构化状态缺失或无效，未生成入站。\n' >&2
    return 1
  }
  store_file=$(plain_proxy_structured_store_file snell) || return 1
  render_structured_instance_inbounds snell "${store_file}"
}

build_tuic_inbound_json() {
  local store_file
  plain_proxy_structured_state_active tuic || {
    printf '[ERROR] TUIC 结构化状态缺失或无效，未生成入站。\n' >&2
    return 1
  }
  store_file=$(plain_proxy_structured_store_file tuic) || return 1
  render_structured_instance_inbounds tuic "${store_file}"
}

build_hysteria_inbound_json() {
  local store_file
  plain_proxy_structured_state_active hysteria || {
    printf '[ERROR] Hysteria 结构化状态缺失或无效，未生成入站。\n' >&2
    return 1
  }
  store_file=$(plain_proxy_structured_store_file hysteria) || return 1
  render_structured_instance_inbounds hysteria "${store_file}"
}

build_naive_inbound_json() {
  local store_file
  plain_proxy_structured_state_active naive || {
    printf '[ERROR] NaiveProxy 结构化状态缺失或无效，未生成入站。\n' >&2
    return 1
  }
  store_file=$(plain_proxy_structured_store_file naive) || return 1
  render_structured_instance_inbounds naive "${store_file}"
}

build_shadowtls_inbound_json() {
  local store_file
  plain_proxy_structured_state_active shadowtls || {
    printf '[ERROR] ShadowTLS 结构化状态缺失或无效，未生成入站。\n' >&2
    return 1
  }
  store_file=$(plain_proxy_structured_store_file shadowtls) || return 1
  render_structured_instance_inbounds shadowtls "${store_file}"
}

build_shadowsocks_instance_outbounds() (
  umask 077
  local instance_id=${1:-} server=${2:-} snapshot temporary address
  structured_instance_store_validate_id "${instance_id}" || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowsocks "$(plain_proxy_structured_store_file shadowsocks)") || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id==$id)' <<< "${snapshot}" >/dev/null || return 1
  temporary=$(mktemp) || return 1
  trap 'rm -f -- "${temporary}"' EXIT
  jq -c --arg id "${instance_id}" '.instances |= map(select(.id==$id)) | .default_instance_id=$id' \
    <<< "${snapshot}" > "${temporary}" || return 1
  address=$(jq -er '.instances[0].listen.address' "${temporary}") || return 1
  case "${address}" in 0.0.0.0|::) ;; *) server=${address} ;; esac
  build_shadowsocks_client_outbounds_from_store "${temporary}" "${server}"
)

# SIP002: classic AEAD uses unpadded Base64URL userinfo; AEAD-2022 MUST
# instead percent-encode method and password separately. Never emit raw secrets.
build_shadowsocks_uri() {
  local outbound=${1:-} name=${2:-Shadowsocks}
  jq -ers --arg name "${name}" '
    select(length==1) | .[0] |
    select(type=="object" and .type=="shadowsocks") |
    select(.method|IN("none","aes-128-gcm","aes-192-gcm","aes-256-gcm",
      "chacha20-ietf-poly1305","xchacha20-ietf-poly1305","2022-blake3-aes-128-gcm",
      "2022-blake3-aes-256-gcm","2022-blake3-chacha20-poly1305")) |
    select(.password|type=="string" and utf8bytelength<=8193 and index("\u0000")==null) |
    select(.server|type=="string" and length>0 and (test("[\u0000-\u0020\u007F@/?#%\\[\\]]")|not)) |
    select(.server_port|type=="number" and floor==. and .>=1 and .<=65535) |
    (if .method|startswith("2022-") then (.method|@uri)+":"+(.password|@uri)
     else ((.method+":"+.password)|@base64|gsub("\\+";"-")|gsub("/";"_")|sub("=+$";"")) end) as $userinfo |
    "ss://"+$userinfo+"@"+(if .server|contains(":") then "["+.server+"]" else .server end)+
    ":"+(.server_port|tostring)+"#"+($name|@uri)
  ' <<< "${outbound}" 2>/dev/null
}

build_shadowsocks_links_json() {
  local node_name_digests
  local server=${1:-} instance_id=${2:-${SB_INSTANCE_ID:-}} outbounds outbound uri key result='{}'
  local store_file snapshot end_snapshot binding candidate_id user_name node_name address_label
  store_file=$(plain_proxy_structured_store_file shadowsocks) || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowsocks "${store_file}") || return 1
  outbounds=$(build_shadowsocks_instance_outbounds "${instance_id}" "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json shadowsocks "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
  while IFS= read -r outbound; do
    [[ -n "${outbound}" ]] || continue
    key=$(jq -er '.tag' <<< "${outbound}") || return 1
    binding=$(jq -ce --arg key "${key}" '
      [.instances[] as $instance |
       ($instance.authentication.users | if length == 0 then [{name:"",single:true}]
        else map(. + {single:false}) end)[] as $user |
       select(("shadowsocks-" + $instance.id + "-" +
         (if $user.single then "single" else "user-" + ($user.name | @base64) end)) == $key) |
       {instance_id:$instance.id,user_name:$user.name,listen_address:$instance.listen.address}] |
      select(length == 1) | .[0]' <<< "${snapshot}") || return 1
    candidate_id=$(jq -r '.instance_id' <<< "${binding}") || return 1
    user_name=$(jq -r '.user_name' <<< "${binding}") || return 1
    address_label=$(node_display_address_label "$(jq -r '.listen_address' <<< "${binding}")" "$(jq -r '.server' <<< "${outbound}")") || return 1
    node_name=$(structured_node_display_name shadowsocks "${snapshot}" "${candidate_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    uri=$(build_shadowsocks_uri "${outbound}" "${node_name}") || return 1
    result=$(jq -cn --argjson result "${result}" --arg key "${key}" --arg uri "${uri}" '$result+{($key):$uri}') || return 1
  done <<< "${outbounds}"
  jq -e 'length>0' <<< "${result}" >/dev/null || return 1
  printf '%s\n' "${result}"
}

shadowsocks_share_warnings_json() {
  jq -cn --argjson auth "${SB_SHADOWSOCKS_AUTH_JSON:-null}" --argjson network "${SB_SHADOWSOCKS_NETWORK_JSON:-null}" '
    (if $network != ["tcp","udp"] then [{code:"shadowsocks_uri_network_omitted",
      message:"SIP002 无法表达实例的单 TCP/UDP 限制；请使用完整客户端 JSON。"}] else [] end) +
    (if $auth.method=="none" then [{code:"shadowsocks_plaintext_transport",
      message:"Shadowsocks none 不提供加密或认证，只能用于可信网络或受保护隧道。"}] else [] end) +
    (if ($auth.method|startswith("2022-")) and
      any(([$auth.password]+[$auth.users[].password])[];
        ((length/4*3)-(if endswith("==") then 2 elif endswith("=") then 1 else 0 end)) >
        (if $auth.method=="2022-blake3-aes-128-gcm" then 16 else 32 end))
     then [{code:"shadowsocks_2022_psk_derived",
       message:"长 PSK 已按服务端 SHA-256 派生规则导出为客户端等效定长密钥；原始实例凭据未修改。"}]
     else [] end)
  '
}

hy2_certificate_provider_tag() {
  printf 'hy2-cert-provider'
}

build_acme_json_from_state() {
  local acme_email=$1
  local acme_domain=$2
  local acme_mode=$3
  local dns_provider=$4
  local api_token=$5
  local extra_json=${6:-}

  [[ -n "${extra_json}" ]] || extra_json='{}'
  jq -e 'type == "object"' >/dev/null 2>&1 <<< "${extra_json}" || return 1
  jq -n \
    --arg acme_email "${acme_email}" \
    --arg acme_domain "${acme_domain}" \
    --arg acme_data_directory "${SB_ACME_DATA_DIR}" \
    --arg acme_mode "${acme_mode}" \
    --arg dns_provider "${dns_provider}" \
    --arg api_token "${api_token}" \
    --argjson extra "${extra_json}" \
    '$extra
    | ((.domain // []) | if type == "array" then .[1:] else error("invalid ACME domain extras") end) as $additional_domains
    | del(.type, .tag, .domain, .email)
    | .domain = ([$acme_domain] + $additional_domains)
    | if has("data_directory") then . else .data_directory = $acme_data_directory end
    | if $acme_email != "" then .email = $acme_email else del(.email) end
    | if $acme_mode == "dns" then
        .dns01_challenge = (
          ((.dns01_challenge // {}) | if type == "object" then . else error("invalid dns01_challenge extras") end)
          + {provider: $dns_provider}
          + (if $api_token != "" then {api_token: $api_token} else {} end)
        )
      else
        del(.dns01_challenge)
      end'
}

build_hy2_acme_json() {
  if [[ "${SB_HY2_TLS_MODE}" != "acme" ]]; then
    return 0
  fi

  build_acme_json_from_state \
    "${SB_HY2_ACME_EMAIL}" \
    "${SB_HY2_ACME_DOMAIN}" \
    "${SB_HY2_ACME_MODE}" \
    "${SB_HY2_DNS_PROVIDER}" \
    "${SB_HY2_CF_API_TOKEN}" \
    "$(acme_extra_json_or_default "${SB_HY2_ACME_EXTRA_JSON:-}")"
}

build_hy2_certificate_provider_json() {
  local acme_json

  # Structured instances render their own inline providers, with no shared tag.
  if [[ "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; then return 0; fi
  if [[ "${SB_HY2_TLS_MODE}" != "acme" ]] || ! singbox_config_supports_1_14; then
    return 0
  fi

  acme_json=$(build_hy2_acme_json)
  jq -n \
    --arg tag "$(hy2_certificate_provider_tag)" \
    --argjson acme "${acme_json}" \
    '$acme + { "type": "acme", "tag": $tag }'
}

build_hy2_inbound_json() {
  if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active hy2; then
    render_structured_instance_inbounds hy2 "$(plain_proxy_structured_store_file hy2)"
    return $?
  fi
  ensure_hy2_materials
  local acme_json use_certificate_provider="n"
  acme_json=$(build_hy2_acme_json)
  if singbox_config_supports_1_14; then
    use_certificate_provider="y"
  fi

  jq -n \
    --arg tag "hy2-in" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg user_name "${SB_HY2_USER_NAME}" \
    --arg password "${SB_HY2_PASSWORD}" \
    --arg up_mbps "${SB_HY2_UP_MBPS}" \
    --arg down_mbps "${SB_HY2_DOWN_MBPS}" \
    --arg domain "${SB_HY2_DOMAIN}" \
    --arg tls_mode "${SB_HY2_TLS_MODE}" \
    --arg cert_path "${SB_HY2_CERT_PATH}" \
    --arg key_path "${SB_HY2_KEY_PATH}" \
    --arg certificate_provider "$(hy2_certificate_provider_tag)" \
    --arg use_certificate_provider "${use_certificate_provider}" \
    --argjson acme "${acme_json:-null}" \
    --arg obfs_enabled "${SB_HY2_OBFS_ENABLED}" \
    --arg obfs_type "${SB_HY2_OBFS_TYPE}" \
    --arg obfs_password "${SB_HY2_OBFS_PASSWORD}" \
    --arg masquerade "${SB_HY2_MASQUERADE}" \
    '{
      "type": "hysteria2",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber),
      "users": [
        {
          "name": $user_name,
          "password": $password
        }
      ],
      "tls": (
        {
          "enabled": true,
          "server_name": $domain,
          "alpn": ["h3"]
        } + (
          if $tls_mode == "manual" then
            {
              "certificate_path": $cert_path,
              "key_path": $key_path
            }
          elif $use_certificate_provider == "y" then
            {
              "certificate_provider": $certificate_provider
            }
          else
            {
              "acme": $acme
            }
          end
        )
      )
    } + (
      if ($up_mbps | length) > 0 and ($down_mbps | length) > 0 then
        {
          "up_mbps": ($up_mbps | tonumber),
          "down_mbps": ($down_mbps | tonumber)
        }
      else
        {}
      end
    ) + (
      if $obfs_enabled == "y" then
        {
          "obfs": {
            "type": $obfs_type,
            "password": $obfs_password
          }
        }
      else
        {}
      end
    ) + (
      if ($masquerade | length) > 0 then
        {
          "masquerade": $masquerade
        }
      else
        {}
      end
    )'
}

anytls_certificate_provider_tag() {
  printf 'anytls-cert-provider'
}

build_anytls_acme_json() {
  if [[ "${SB_ANYTLS_TLS_MODE}" != "acme" ]]; then
    return 0
  fi

  build_acme_json_from_state \
    "${SB_ANYTLS_ACME_EMAIL}" \
    "${SB_ANYTLS_ACME_DOMAIN}" \
    "${SB_ANYTLS_ACME_MODE}" \
    "${SB_ANYTLS_DNS_PROVIDER}" \
    "${SB_ANYTLS_CF_API_TOKEN}" \
    "$(acme_extra_json_or_default "${SB_ANYTLS_ACME_EXTRA_JSON:-}")"
}

build_anytls_certificate_provider_json() {
  local acme_json

  if [[ "${SB_ANYTLS_TLS_MODE}" != "acme" ]] || ! singbox_config_supports_1_14; then
    return 0
  fi

  acme_json=$(build_anytls_acme_json)
  jq -n \
    --arg tag "$(anytls_certificate_provider_tag)" \
    --argjson acme "${acme_json}" \
    '$acme + { "type": "acme", "tag": $tag }'
}

build_anytls_inbound_json() {
  if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active anytls; then
    render_structured_instance_inbounds anytls "$(plain_proxy_structured_store_file anytls)"
    return $?
  fi
  ensure_anytls_materials
  local acme_json use_certificate_provider="n"
  acme_json=$(build_anytls_acme_json)
  if singbox_config_supports_1_14; then
    use_certificate_provider="y"
  fi

  jq -n \
    --arg tag "anytls-in" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg user_name "${SB_ANYTLS_USER_NAME}" \
    --arg password "${SB_ANYTLS_PASSWORD}" \
    --arg domain "${SB_ANYTLS_DOMAIN}" \
    --arg tls_mode "${SB_ANYTLS_TLS_MODE}" \
    --arg cert_path "${SB_ANYTLS_CERT_PATH}" \
    --arg key_path "${SB_ANYTLS_KEY_PATH}" \
    --arg certificate_provider "$(anytls_certificate_provider_tag)" \
    --arg use_certificate_provider "${use_certificate_provider}" \
    --argjson acme "${acme_json:-null}" \
    '{
      "type": "anytls",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber),
      "users": [
        {
          "name": $user_name,
          "password": $password
        }
      ],
      "tls": (
        {
          "enabled": true,
          "server_name": $domain
        } + (
          if $tls_mode == "manual" then
            {
              "certificate_path": $cert_path,
              "key_path": $key_path
            }
          elif $use_certificate_provider == "y" then
            {
              "certificate_provider": $certificate_provider
            }
          else
            {
              "acme": $acme
            }
          end
        )
      )
    }'
}

build_certificate_provider_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1

  case "${protocol}" in
    vless-reality|vless-plain|mixed|socks|http|shadowsocks|trojan|vmess|snell|tuic|hysteria|naive|shadowtls) return 0 ;; # HTTP/VLESS/Trojan/VMess/Snell/TUIC/Hysteria/Naive/ShadowTLS use no certificate provider.
    hy2) build_hy2_certificate_provider_json ;;
    anytls) build_anytls_certificate_provider_json ;;
    *) return 1 ;;
  esac
}

build_inbound_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1

  case "${protocol}" in
    vless-reality) build_vless_inbound_json ;;
    vless-plain) build_vless_plain_inbound_json ;;
    mixed) build_mixed_inbound_json ;;
    socks) build_socks_inbound_json ;;
    http) build_http_inbound_json ;;
    shadowsocks) build_shadowsocks_inbound_json ;;
    trojan) build_trojan_inbound_json ;;
    vmess) build_vmess_inbound_json ;;
    hy2) build_hy2_inbound_json ;;
    anytls) build_anytls_inbound_json ;;
    snell) build_snell_inbound_json ;;
    tuic) build_tuic_inbound_json ;;
    hysteria) build_hysteria_inbound_json ;;
    naive) build_naive_inbound_json ;;
    shadowtls) build_shadowtls_inbound_json ;;
    *) return 1 ;;
  esac
}

build_vless_reality_route_rules_json() {
  local tmp_rules tmp_snis instance_id inbound_tag sni instance_ids
  tmp_rules=$(mktemp) || return 1
  if ! tmp_snis=$(mktemp); then
    rm -f "${tmp_rules}"
    return 1
  fi

  if ! load_vless_reality_protocol_state; then
    rm -f "${tmp_rules}" "${tmp_snis}"
    return 1
  fi
  if ! instance_ids=$(list_vless_reality_instance_ids); then
    rm -f "${tmp_rules}" "${tmp_snis}"
    return 1
  fi
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    if ! load_vless_reality_instance_state "${instance_id}"; then
      rm -f "${tmp_rules}" "${tmp_snis}"
      return 1
    fi
    inbound_tag=$(vless_reality_inbound_tag_for_instance "${instance_id}")
    if ! jq -n --arg inbound_tag "${inbound_tag}" '{ "inbound": $inbound_tag, "action": "sniff" }' >> "${tmp_rules}"; then
      rm -f "${tmp_rules}" "${tmp_snis}"
      return 1
    fi
    [[ -n "${SB_SNI}" ]] && printf '%s\n' "${SB_SNI}" >> "${tmp_snis}"
  done <<< "${instance_ids}"

  while IFS= read -r sni; do
    [[ -z "${sni}" ]] && continue
    if ! jq -n --arg sni "${sni}" '{ "domain": [ $sni ], "action": "direct" }' >> "${tmp_rules}"; then
      rm -f "${tmp_rules}" "${tmp_snis}"
      return 1
    fi
  done < <(sort -u "${tmp_snis}")

  if ! jq -s '.' "${tmp_rules}"; then
    rm -f "${tmp_rules}" "${tmp_snis}"
    return 1
  fi

  rm -f "${tmp_rules}" "${tmp_snis}"
}

build_vless_reality_instance_outbound_rules_json() {
  local tmp_rules instance_id inbound_tag outbound instance_ids
  tmp_rules=$(mktemp) || return 1

  if ! load_vless_reality_protocol_state; then
    rm -f "${tmp_rules}"
    return 1
  fi
  if ! instance_ids=$(list_vless_reality_instance_ids); then
    rm -f "${tmp_rules}"
    return 1
  fi
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    if ! load_vless_reality_instance_state "${instance_id}"; then
      rm -f "${tmp_rules}"
      return 1
    fi
    case "${SB_OUTBOUND_POLICY:-default}" in
      direct) outbound="direct" ;;
      warp)
        outbound="warp-ep"
        ;;
      *) continue ;;
    esac
    inbound_tag=$(vless_reality_inbound_tag_for_instance "${instance_id}")
    if ! jq -n \
      --arg inbound_tag "${inbound_tag}" \
      --arg outbound "${outbound}" \
      '{ "inbound": $inbound_tag, "action": "route", "outbound": $outbound }' >> "${tmp_rules}"; then
      rm -f "${tmp_rules}"
      return 1
    fi
  done <<< "${instance_ids}"

  if ! jq -s '.' "${tmp_rules}"; then
    rm -f "${tmp_rules}"
    return 1
  fi

  rm -f "${tmp_rules}"
}

build_vless_plain_route_rules_json() {
  local store_file
  plain_proxy_structured_state_active vless-plain || return 1
  store_file=$(plain_proxy_structured_store_file vless-plain) || return 1
  render_structured_instance_route_rules vless-plain "${store_file}"
}

vless_reality_has_warp_outbound_policy() {
  local instance_id

  load_vless_reality_protocol_state
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    load_vless_reality_instance_state "${instance_id}" || continue
    [[ "${SB_OUTBOUND_POLICY:-default}" == "warp" ]] && return 0
  done < <(list_vless_reality_instance_ids)

  return 1
}

instance_outbound_requires_warp() {
  local protocol state_file schema store_file

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    case "${protocol}" in
      vless-reality)
        vless_reality_has_warp_outbound_policy && return 0
        ;;
      vless-plain|mixed|socks|http|shadowsocks|trojan|vmess|anytls|hy2|snell|tuic|hysteria|naive|shadowtls)
        state_file=$(protocol_state_file "${protocol}") || return 1
        schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" 2>/dev/null || true)
        schema=${schema//\"/}
        schema=${schema//\'/}
        if [[ "${schema}" == "2" ]]; then
          plain_proxy_structured_state_active "${protocol}" || return 1
          store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
          jq -e 'any(.instances[]; .outbound_policy == "warp")' "${store_file}" >/dev/null 2>&1 && return 0
        fi
        ;;
    esac
  done < <(list_effective_protocols)

  return 1
}

build_protocol_route_rules() {
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1

  case "${protocol}" in
    vless-reality)
      build_vless_reality_route_rules_json
      ;;
    mixed)
      local state_file schema
      state_file=$(protocol_state_file "mixed") || return 1
      schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" 2>/dev/null || true)
      schema=${schema//\"/}
      schema=${schema//\'/}
      if [[ "${schema}" == "2" ]]; then
        mixed_structured_state_active || return 1
        render_structured_instance_route_rules mixed "$(mixed_structured_store_file)"
      else
        jq -n '[{ "inbound": "mixed-in", "action": "sniff" }]'
      fi
      ;;
      vless-plain|socks|http|shadowsocks|trojan|vmess|hysteria|naive|shadowtls)
      local state_file
      state_file=$(protocol_state_file "${protocol}") || return 1
      plain_proxy_structured_state_active "${protocol}" || return 1
      render_structured_instance_route_rules "${protocol}" "$(plain_proxy_structured_store_file "${protocol}")"
      ;;
    anytls)
      local state_file schema
      state_file=$(protocol_state_file "${protocol}") || return 1
      schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" 2>/dev/null | head -n1 || true)
      schema=${schema//\"/}
      schema=${schema//\'/}
      if [[ "${schema}" == "2" ]]; then
        plain_proxy_structured_state_active "${protocol}" || return 1
        render_structured_instance_route_rules "${protocol}" "$(plain_proxy_structured_store_file "${protocol}")"
      else
        jq -n '[{ "inbound": "anytls-in", "action": "sniff" }]'
      fi
      ;;
    hy2)
      local state_file schema
      state_file=$(protocol_state_file "${protocol}") || return 1
      schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" 2>/dev/null | head -n1 || true)
      schema=${schema//\"/}
      schema=${schema//\'/}
      if [[ "${schema}" == "2" ]]; then
        plain_proxy_structured_state_active hy2 || return 1
        render_structured_instance_route_rules hy2 "$(plain_proxy_structured_store_file hy2)"
      else
        jq -n '[{ "inbound": "hy2-in", "action": "sniff" }]'
      fi
      ;;
    snell)
      plain_proxy_structured_state_active snell || return 1
      render_structured_instance_route_rules snell "$(plain_proxy_structured_store_file snell)"
      ;;
    tuic)
      plain_proxy_structured_state_active tuic || return 1
      render_structured_instance_route_rules tuic "$(plain_proxy_structured_store_file tuic)"
      ;;
    hysteria)
      plain_proxy_structured_state_active hysteria || return 1
      render_structured_instance_route_rules hysteria "$(plain_proxy_structured_store_file hysteria)"
      ;;
    naive)
      plain_proxy_structured_state_active naive || return 1
      render_structured_instance_route_rules naive "$(plain_proxy_structured_store_file naive)"
      ;;
    *) return 1 ;;
  esac
}

# A stream of inbound/provider objects, or exactly one route array. Empty output
# is valid only for the explicit none/optional provider contract in the registry.
append_protocol_fragment() {
  local protocol=$1 kind=$2 destination=$3 fragment expected_type contract
  protocol_registry_require_handlers "${protocol}" || return 1
  expected_type=$(protocol_registry_field "${protocol}" type) || return 1
  contract=$(protocol_registry_field "${protocol}" certificate_contract) || return 1
  case "${kind}" in
    inbound) fragment=$(build_inbound_for_protocol "${protocol}") || return $? ;;
    certificate) fragment=$(build_certificate_provider_for_protocol "${protocol}") || return $? ;;
    route) fragment=$(build_protocol_route_rules "${protocol}") || return $? ;;
    *) return 1 ;;
  esac
  if ! jq -es --arg kind "${kind}" --arg expected_type "${expected_type}" --arg contract "${contract}" '
    def tagged: type == "object" and (.tag | type == "string" and length > 0);
    if $kind == "inbound" then
      length > 0 and (if $expected_type == "shadowtls" then
        all(.[]; tagged and ((.type == "shadowtls") or (.type == "mixed" and (.tag | startswith("shadowtls-inner-")))))
      else all(.[]; tagged and .type == $expected_type) end)
    elif $kind == "certificate" then
      if $contract == "none" then length == 0
      elif $contract == "optional" then all(.[]; tagged and (.type | type == "string" and length > 0))
      else false end
    else length == 1 and (.[0] | type == "array" and all(.[]; type == "object")) end
  ' >/dev/null 2>&1 <<< "${fragment}"; then
    printf '[ERROR] 协议生成器返回无效片段，未发布配置。\n' >&2
    return 1
  fi
  printf '%s\n' "${fragment}" >> "${destination}"
}
