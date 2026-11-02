
protocol_instance_state_schema() {
  local protocol=$1
  local state_file schema schema_count

  protocol=$(normalize_protocol_id "${protocol}") || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  [[ -f "${state_file}" ]] || return 1
  schema_count=$(awk '/^[[:space:]]*CONFIG_SCHEMA_VERSION=/{count++} END{print count + 0}' "${state_file}") || return 1
  if [[ "${schema_count}" == "0" ]]; then
    printf '1'
    return 0
  fi
  [[ "${schema_count}" == "1" ]] || return 1
  schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}") || return 1
  schema=${schema//\"/}
  schema=${schema//\'/}
  [[ "${schema}" =~ ^[0-9]+$ ]] || return 1
  [[ "${protocol}" != "vless-plain" && "${protocol}" != "socks" && "${protocol}" != "http" && "${protocol}" != "shadowsocks" && "${protocol}" != "trojan" && "${protocol}" != "vmess" && "${protocol}" != "snell" && "${protocol}" != "tuic" && "${protocol}" != "hysteria" && "${protocol}" != "naive" && "${protocol}" != "shadowtls" || "${schema}" == "2" ]] || return 1
  printf '%s' "${schema}"
}

vless_reality_instance_manifest_is_complete() {
  local instance_dir instance_file instance_file_id instance_file_count=0

  instance_dir=$(vless_reality_instance_dir) || return 1
  for instance_file in "${instance_dir}"/*.env; do
    [[ -e "${instance_file}" ]] || continue
    instance_file_id=${instance_file##*/}
    instance_file_id=${instance_file_id%.env}
    validate_vless_reality_instance_id "${instance_file_id}" || return 1
    protocol_array_contains "${instance_file_id}" "${VLESS_REBUILD_STATE_IDS[@]}" || return 1
    instance_file_count=$((instance_file_count + 1))
  done
  [[ "${instance_file_count}" -eq "${#VLESS_REBUILD_STATE_IDS[@]}" ]]
}

reset_protocol_state_source_variables() {
  reset_vless_reality_state_source_variables
  unset AUTH_ENABLED USERNAME PASSWORD DOMAIN USER_NAME UP_MBPS DOWN_MBPS
  unset OBFS_ENABLED OBFS_TYPE OBFS_PASSWORD TLS_MODE ACME_MODE ACME_EMAIL
  unset ACME_DOMAIN ACME_EXTRA_JSON DNS_PROVIDER CF_API_TOKEN CERT_PATH KEY_PATH
  unset MASQUERADE
  unset SNELL_VERSION SNELL_PSK SNELL_USERS SNELL_USER_JSON SNELL_OBFS_MODE SNELL_OBFS_HOST SNELL_MODE
  unset TUIC_USERS TUIC_USER_JSON TUIC_TLS TUIC_CLIENT_TRUST TUIC_CONGESTION_CONTROL TUIC_AUTH_TIMEOUT TUIC_HEARTBEAT TUIC_ZERO_RTT_HANDSHAKE TUIC_UDP_RELAY_MODE TUIC_UDP_OVER_STREAM
  unset HYSTERIA_USERS HYSTERIA_AUTH_JSON HYSTERIA_TLS HYSTERIA_CLIENT_TRUST HYSTERIA_UP_MBPS HYSTERIA_DOWN_MBPS HYSTERIA_OBFS_ENABLED HYSTERIA_OBFS_PASSWORD HYSTERIA_QUIC
  unset NAIVE_AUTH_JSON NAIVE_TLS NAIVE_CLIENT_TRUST NAIVE_NETWORK NAIVE_QUIC_CONGESTION_CONTROL NAIVE_QUIC NAIVE_INSECURE_CONCURRENCY NAIVE_STREAM_RECEIVE_WINDOW NAIVE_QUIC_SESSION_RECEIVE_WINDOW NAIVE_EXTRA_HEADERS
  unset SHADOWTLS_VERSION SHADOWTLS_PASSWORD SHADOWTLS_AUTH_JSON SHADOWTLS_HANDSHAKE_JSON SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON SHADOWTLS_STRICT_MODE SHADOWTLS_WILDCARD_SNI SHADOWTLS_DETOUR_TAG SHADOWTLS_DETOUR_PORT SHADOWTLS_CLIENT_TRUST SHADOWTLS_CLIENT_TLS_JSON
}

reset_protocol_instance_runtime_fields() {
  SB_INSTANCE_ID=""
  SB_NODE_NAME=""
  SB_PORT=""
  SB_UUID=""
  SB_PUBLIC_KEY=""
  SB_PRIVATE_KEY=""
  SB_SHORT_ID_1=""
  SB_SHORT_ID_2=""
  SB_SNI=""
  SB_VLESS_INSTANCE_ID=""
  SB_VLESS_INBOUND_TAG=""
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
  SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="n"
  SB_OUTBOUND_POLICY="default"
  SB_MIXED_AUTH_ENABLED="y"
  SB_MIXED_USERNAME=""
  SB_MIXED_PASSWORD=""
  SB_MIXED_INSTANCE_ID=""
  SB_MIXED_INBOUND_TAG=""
  SB_MIXED_LISTEN_ADDRESS=""
  SB_MIXED_STORE_REVISION="0"
  SB_HTTP_TLS_JSON=""
  SB_SHADOWSOCKS_AUTH_JSON=""
  SB_SHADOWSOCKS_NETWORK_JSON=""
  SB_TROJAN_AUTH_JSON='[]'
  SB_TROJAN_TLS_JSON='{"enabled":false}'
  SB_TROJAN_TRANSPORT_JSON='{"type":"none"}'
  SB_TROJAN_CLIENT_TRUST="certificate"
  SB_VMESS_AUTH_JSON='[]'
  SB_VMESS_TLS_JSON='{"enabled":false}'
  SB_VMESS_TRANSPORT_JSON='{"type":"none"}'
  SB_VMESS_CLIENT_TRUST="certificate"
  SB_VLESS_PLAIN_AUTH_JSON='[]'
  SB_VLESS_PLAIN_TLS_JSON='{"enabled":false}'
  SB_VLESS_PLAIN_TRANSPORT_JSON='{"type":"none"}'
  SB_VLESS_PLAIN_CLIENT_TRUST="certificate"
  SB_SNELL_VERSION="6"
  SB_SNELL_PSK=""
  SB_SNELL_USER_JSON='[]'
  SB_SNELL_OBFS_MODE=""
  SB_SNELL_OBFS_HOST=""
  SB_SNELL_MODE=""
  SB_TUIC_AUTH_JSON='[]'
  SB_TUIC_TLS_JSON='{"enabled":false}'
  SB_TUIC_CLIENT_TRUST="system"
  SB_TUIC_CONGESTION_CONTROL="bbr"
  SB_TUIC_AUTH_TIMEOUT_SECONDS="3"
  SB_TUIC_HEARTBEAT_SECONDS="10"
  SB_TUIC_ZERO_RTT_HANDSHAKE="n"
  SB_TUIC_UDP_RELAY_MODE="native"
  SB_TUIC_UDP_OVER_STREAM="n"
  SB_HYSTERIA_AUTH_JSON='[]'
  SB_HYSTERIA_TLS_JSON='{"enabled":false}'
  SB_HYSTERIA_CLIENT_TRUST="system"
  SB_HYSTERIA_UP_MBPS="100"
  SB_HYSTERIA_DOWN_MBPS="100"
  SB_HYSTERIA_OBFS_ENABLED="n"
  SB_HYSTERIA_OBFS_PASSWORD=""
  SB_HYSTERIA_QUIC_JSON='{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'
  SB_NAIVE_AUTH_JSON='[]'
  SB_NAIVE_TLS_JSON='{"enabled":false}'
  SB_NAIVE_CLIENT_TRUST="system"
  SB_NAIVE_NETWORK_JSON='["tcp","udp"]'
  SB_NAIVE_QUIC_CONGESTION_CONTROL="bbr"
  SB_NAIVE_QUIC="n"
  SB_NAIVE_INSECURE_CONCURRENCY="0"
  SB_NAIVE_STREAM_RECEIVE_WINDOW=""
  SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW=""
  SB_NAIVE_EXTRA_HEADERS_JSON='{}'
  SB_SHADOWTLS_VERSION="3"
  SB_SHADOWTLS_PASSWORD=""
  SB_SHADOWTLS_AUTH_JSON='[]'
  SB_SHADOWTLS_HANDSHAKE_JSON='{"server":"","server_port":443}'
  SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON='{}'
  SB_SHADOWTLS_STRICT_MODE="n"
  SB_SHADOWTLS_WILDCARD_SNI="off"
  SB_SHADOWTLS_DETOUR_TAG=""
  SB_SHADOWTLS_DETOUR_PORT=""
  SB_SHADOWTLS_CLIENT_TRUST="system"
  SB_SHADOWTLS_CLIENT_TLS_JSON='{"enabled":true,"server_name":"","certificate_path":""}'
  SB_ANYTLS_AUTH_JSON='[]'
  SB_ANYTLS_TLS_JSON='{"enabled":false}'
  SB_ANYTLS_CLIENT_TRUST="system"
  SB_HY2_DOMAIN=""
  SB_HY2_TLS_JSON='{"enabled":false}'
  SB_HY2_PASSWORD=""
  SB_HY2_USER_NAME=""
  SB_HY2_AUTH_JSON='[]'
  SB_HY2_CLIENT_TRUST="system"
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
}

list_vless_reality_managed_instance_ids() {
  load_vless_reality_existing_metadata || return 1
  [[ ${#VLESS_REBUILD_STATE_IDS[@]} -gt 0 ]] || return 1
  vless_reality_instance_manifest_is_complete || return 1
  printf '%s\n' "${VLESS_REBUILD_STATE_IDS[@]}"
}

read_vless_reality_default_instance_id() {
  reset_protocol_state_source_variables
  load_vless_reality_protocol_state || return 1
  [[ -n "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-}" ]] || return 1
  printf '%s\n' "${VLESS_REALITY_DEFAULT_INSTANCE_ID}"
}

list_protocol_instance_ids() {
  local protocol=${1:-} state_file schema instance_id instance_ids

  protocol=$(normalize_protocol_id "${protocol}") || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  [[ -f "${state_file}" ]] || return 1
  grep -Eq "^[[:space:]]*INSTALLED=(1|\"1\"|'1')[[:space:]]*$" "${state_file}" || return 1
  schema=$(protocol_instance_state_schema "${protocol}") || return 1

  case "${protocol}:${schema}" in
    vless-reality:1)
      printf 'main\n'
      ;;
    vless-reality:2)
      instance_ids=$(list_vless_reality_managed_instance_ids) || return 1
      printf '%s\n' "${instance_ids}"
      ;;
    mixed:1|hy2:1|anytls:1)
      printf 'main\n'
      ;;
    mixed:2)
      mixed_structured_state_active || return 1
      jq -r '.instances[].id' "$(mixed_structured_store_file)"
      ;;
    vless-plain:2|socks:2|http:2|shadowsocks:2|trojan:2|vmess:2|anytls:2|hy2:2|snell:2|tuic:2|hysteria:2|naive:2|shadowtls:2)
      plain_proxy_structured_state_active "${protocol}" || return 1
      jq -r '.instances[].id' "$(plain_proxy_structured_store_file "${protocol}")"
      ;;
    *)
      return 1
      ;;
  esac
}

list_installed_protocols_read_only() {
  local indexed_raw protocol normalized_protocol
  local indexed_protocols=()

  validate_protocol_index_for_rebuild || return 1
  indexed_raw=$(list_indexed_protocols_raw) || return 1
  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    normalized_protocol=$(normalize_protocol_id "${protocol}") || return 1
    if [[ ${#indexed_protocols[@]} -gt 0 ]] &&
       protocol_array_contains "${normalized_protocol}" "${indexed_protocols[@]}"; then
      return 1
    fi
    indexed_protocols+=("${normalized_protocol}")
  done <<< "${indexed_raw}"

  [[ ${#indexed_protocols[@]} -gt 0 ]] || return 0
  printf '%s\n' "${indexed_protocols[@]}"
}

protocol_default_instance_id() {
  local protocol=${1:-} state_file schema default_id instance_ids instance_id status

  protocol=$(normalize_protocol_id "${protocol}") || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  [[ -f "${state_file}" ]] || return 1
  schema=$(protocol_instance_state_schema "${protocol}") || return 1
  if instance_ids=$(list_protocol_instance_ids "${protocol}"); then
    :
  else
    status=$?
    if [[ "${protocol}" == "vless-reality" ]]; then
      log_warn "未找到可用的 VLESS + REALITY 实例，或实例状态清单无法完整读取。" >&2
    fi
    return "${status}"
  fi

  case "${protocol}:${schema}" in
    vless-reality:2)
      default_id=$(read_vless_reality_default_instance_id) || return 1
      ;;
    vless-reality:1|mixed:1|hy2:1|anytls:1)
      default_id="main"
      ;;
    mixed:2)
      mixed_structured_state_active || return 1
      default_id=$(jq -r '.default_instance_id' "$(mixed_structured_store_file)") || return 1
      ;;
    vless-plain:2|socks:2|http:2|shadowsocks:2|trojan:2|vmess:2|anytls:2|hy2:2|snell:2|tuic:2|hysteria:2|naive:2|shadowtls:2)
      plain_proxy_structured_state_active "${protocol}" || return 1
      default_id=$(jq -r '.default_instance_id' "$(plain_proxy_structured_store_file "${protocol}")") || return 1
      ;;
    *)
      return 1
      ;;
  esac

  while IFS= read -r instance_id; do
    [[ "${instance_id}" == "${default_id}" ]] && {
      printf '%s\n' "${default_id}"
      return 0
    }
  done <<< "${instance_ids}"
  return 1
}

load_protocol_instance_state() {
  local protocol=${1:-} instance_id=${2:-}
  local schema instance_ids listed_instance_id legacy_inbound_tag

  protocol=$(normalize_protocol_id "${protocol}") || return 1
  if [[ "${protocol}" == "mixed" || "${protocol}" == "vless-plain" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "anytls" || "${protocol}" == "hy2" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls" ]]; then
    structured_instance_store_validate_id "${instance_id}" || return 1
  else
    validate_vless_reality_instance_id "${instance_id}" || return 1
  fi
  schema=$(protocol_instance_state_schema "${protocol}") || return 1
  instance_ids=$(list_protocol_instance_ids "${protocol}") || return 1
  listed_instance_id=""
  while IFS= read -r listed_instance_id; do
    [[ "${listed_instance_id}" == "${instance_id}" ]] && break
    listed_instance_id=""
  done <<< "${instance_ids}"
  [[ "${listed_instance_id}" == "${instance_id}" ]] || return 1

  if [[ "${protocol}:${schema}" == "vless-reality:1" ]]; then
    vless_reality_legacy_state_is_complete || return 1
  fi

  # This adapter is deliberately read-only.  In particular, schema-1
  # REALITY must never enter the legacy migration path.
  reset_protocol_state_source_variables
  reset_protocol_instance_runtime_fields
  load_protocol_state "${protocol}" "read-only" || return 1

  case "${protocol}:${schema}" in
    vless-reality:2)
      load_vless_reality_protocol_state || return 1
      load_vless_reality_instance_state "${instance_id}" || return 1
      SB_INSTANCE_ID="${instance_id}"
      ;;
    vless-reality:1)
      legacy_inbound_tag=${INBOUND_TAG:-}
      SB_INSTANCE_ID="main"
      SB_VLESS_INSTANCE_ID="main"
      SB_VLESS_INBOUND_TAG="${legacy_inbound_tag}"
      SB_VLESS_RATE_LIMIT_UP_MBPS=""
      SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
      SB_VLESS_ALPN_MODE="off"
      SB_VLESS_TCP_FAST_OPEN="n"
      SB_OUTBOUND_POLICY="default"
      ;;
    mixed:1|hy2:1|anytls:1)
      SB_INSTANCE_ID="main"
      ;;
    mixed:2)
      load_mixed_structured_instance "${instance_id}" || return 1
      ;;
    vless-plain:2|socks:2|http:2|shadowsocks:2|trojan:2|vmess:2|anytls:2|hy2:2|snell:2|tuic:2|hysteria:2|naive:2|shadowtls:2)
      load_plain_proxy_structured_instance "${protocol}" "${instance_id}" || return 1
      ;;
    *)
      return 1
      ;;
  esac
  if [[ "${protocol}" == "vless-reality" ]]; then
    vless_reality_loaded_connection_is_complete || return 1
  fi
  return 0
}

vless_reality_config_id_in_use() {
  local target_id=$1

  vless_reality_config_id_exists "${target_id}" && return 0
  if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]] &&
     vless_reality_existing_state_index_for_id "${target_id}" >/dev/null; then
    return 0
  fi
  return 1
}

collect_vless_reality_config_instances() {
  local inbound_count inbound_index inbound_type inbound_json protocol tag raw_tag user_name candidate private_key existing_tag tag_suffix
  local fallback_number=1 state_index tag_index vless_inbound_count=0
  local candidate_index resolved_ids=()

  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" || return 1
  if ! load_vless_reality_existing_metadata; then
    printf '[ERROR] reality_metadata_untrusted: 受管 VLESS 实例元数据无效或关联不唯一；已保留原状态，禁止有损接管。\n' >&2
    return 1
  fi
  VLESS_CONFIG_INSTANCE_IDS=()
  VLESS_CONFIG_INSTANCE_INDICES=()
  VLESS_CONFIG_INSTANCE_TAGS=()
  VLESS_CONFIG_INSTANCE_CANDIDATES=()
  VLESS_CONFIG_PROTOCOLS=()
  VLESS_CONFIG_REALITY_PRIVATE_KEY=""
  VLESS_CONFIG_REALITY_PRIVATE_KEY_SET="n"
  VLESS_CONFIG_DEFAULT_INSTANCE_ID=""

  inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}") || return 1
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1
  vless_inbound_count=$(config_protocol_inbound_count vless-reality "${SINGBOX_CONFIG_FILE}") || return 1
  [[ "${vless_inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx]' "${SINGBOX_CONFIG_FILE}") || return 1
    if jq -e '.type | IN("direct","tun","redirect","tproxy","cloudflared")' <<< "${inbound_json}" >/dev/null; then continue; fi
    if manual_client_inbound_is_unmanaged "${inbound_json}"; then continue; fi
    if ! protocol=$(config_inbound_protocol "${inbound_json}" 2>/dev/null); then
      return 1
    fi
    [[ -n "${protocol}" ]] || return 1
    if ! protocol_array_contains "${protocol}" ${VLESS_CONFIG_PROTOCOLS[@]+"${VLESS_CONFIG_PROTOCOLS[@]}"}; then
      VLESS_CONFIG_PROTOCOLS+=("${protocol}")
    fi
    [[ "${protocol}" == "vless-reality" ]] || continue

    if ! jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality? | type == "object"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      return 1
    fi

    tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tag // ""' "${SINGBOX_CONFIG_FILE}") || return 1
    raw_tag="${tag}"
    user_name=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}") || return 1
    candidate=""
    state_index=""
    if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]] &&
       candidate_index=$(vless_reality_existing_state_index_for_tag "${tag}"); then
      candidate="${VLESS_REBUILD_STATE_IDS[${candidate_index}]}"
    elif [[ -z "${tag}" && "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" &&
            "${vless_inbound_count}" == "1" && ${#VLESS_REBUILD_STATE_IDS[@]} -eq 1 ]]; then
      candidate="${VLESS_REBUILD_STATE_IDS[0]}"
      tag="${VLESS_REBUILD_STATE_TAGS[0]}"
    elif [[ -z "${tag}" && "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "1" &&
            "${vless_inbound_count}" == "1" ]]; then
      candidate="main"
      tag="vless-in"
    elif [[ "${tag}" == "vless-in" ]]; then
      candidate="main"
    elif [[ "${tag}" == vless-reality-* ]]; then
      tag_suffix="${tag#vless-reality-}"
      if validate_vless_reality_instance_id "${tag_suffix}"; then
        candidate="${tag_suffix}"
      elif validate_vless_reality_instance_id "${user_name}"; then
        candidate="${user_name}"
      fi
    elif validate_vless_reality_instance_id "${user_name}"; then
      candidate="${user_name}"
    fi

    if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" && -n "${candidate}" ]]; then
      state_index=$(vless_reality_existing_state_index_for_id "${candidate}" 2>/dev/null || true)
      if [[ -n "${state_index}" ]]; then
        if [[ -z "${tag}" ]]; then
          tag="${VLESS_REBUILD_STATE_TAGS[${state_index}]}"
        fi
        tag_index=$(vless_reality_existing_state_index_for_tag "${tag}" 2>/dev/null || true)
        [[ -n "${tag_index}" && "${tag_index}" == "${state_index}" ]] || {
          printf '[ERROR] reality_metadata_untrusted: VLESS 实例 ID 与 live inbound tag 关联不一致；已保留原状态。\n' >&2
          return 1
        }
      fi
    fi

    if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" && -z "${raw_tag}" &&
          ${#VLESS_REBUILD_STATE_IDS[@]} -gt 0 && -z "${state_index}" ]]; then
      printf '[ERROR] reality_metadata_untrusted: 无 tag 的 VLESS 实例无法与现有受管实例唯一关联；已保留原状态。\n' >&2
      return 1
    fi

    if [[ -n "${candidate}" ]]; then
      if vless_reality_config_id_exists "${candidate}"; then
        return 1
      fi
      VLESS_CONFIG_INSTANCE_IDS+=("${candidate}")
    fi
    for existing_tag in "${VLESS_CONFIG_INSTANCE_TAGS[@]}"; do
      if [[ -n "${tag}" && "${existing_tag}" == "${tag}" ]]; then
        return 1
      fi
    done
    VLESS_CONFIG_INSTANCE_INDICES+=("${inbound_index}")
    VLESS_CONFIG_INSTANCE_TAGS+=("${tag}")
    VLESS_CONFIG_INSTANCE_CANDIDATES+=("${candidate}")

    private_key=$(jq -r --argjson idx "${inbound_index}" '(.inbounds[$idx].tls.reality.private_key // "") | if type == "string" then . else empty end' "${SINGBOX_CONFIG_FILE}") || return 1
    if [[ "${VLESS_CONFIG_REALITY_PRIVATE_KEY_SET}" == "n" ]]; then
      VLESS_CONFIG_REALITY_PRIVATE_KEY="${private_key}"
      VLESS_CONFIG_REALITY_PRIVATE_KEY_SET="y"
    elif [[ "${VLESS_CONFIG_REALITY_PRIVATE_KEY}" != "${private_key}" ]]; then
      return 1
    fi
  done

  for candidate_index in "${!VLESS_CONFIG_INSTANCE_CANDIDATES[@]}"; do
    candidate="${VLESS_CONFIG_INSTANCE_CANDIDATES[${candidate_index}]}"
    if [[ -z "${candidate}" ]]; then
      while vless_reality_config_id_in_use "imported-${fallback_number}"; do
        fallback_number=$((fallback_number + 1))
      done
      candidate="imported-${fallback_number}"
      fallback_number=$((fallback_number + 1))
      VLESS_CONFIG_INSTANCE_IDS+=("${candidate}")
    fi
    VLESS_CONFIG_INSTANCE_CANDIDATES[${candidate_index}]="${candidate}"
    resolved_ids+=("${candidate}")
  done

  VLESS_CONFIG_INSTANCE_IDS=(${resolved_ids[@]+"${resolved_ids[@]}"})

  if [[ ${#VLESS_CONFIG_INSTANCE_IDS[@]} -gt 0 ]]; then
    VLESS_CONFIG_DEFAULT_INSTANCE_ID="${VLESS_CONFIG_INSTANCE_IDS[0]}"
    if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]] &&
       vless_reality_config_id_exists "${VLESS_REBUILD_STATE_DEFAULT_ID}"; then
      VLESS_CONFIG_DEFAULT_INSTANCE_ID="${VLESS_REBUILD_STATE_DEFAULT_ID}"
    elif vless_reality_config_id_exists "main"; then
      VLESS_CONFIG_DEFAULT_INSTANCE_ID="main"
    fi
    for candidate_index in "${!VLESS_CONFIG_INSTANCE_TAGS[@]}"; do
      if [[ -z "${VLESS_CONFIG_INSTANCE_TAGS[${candidate_index}]}" ]]; then
        if [[ "${VLESS_CONFIG_INSTANCE_CANDIDATES[${candidate_index}]}" == "${VLESS_CONFIG_DEFAULT_INSTANCE_ID}" ]]; then
          VLESS_CONFIG_INSTANCE_TAGS[${candidate_index}]="vless-in"
        else
          VLESS_CONFIG_INSTANCE_TAGS[${candidate_index}]="vless-reality-${VLESS_CONFIG_INSTANCE_CANDIDATES[${candidate_index}]}"
        fi
      fi
    done
    for candidate_index in "${!VLESS_CONFIG_INSTANCE_TAGS[@]}"; do
      for existing_tag in "${VLESS_CONFIG_INSTANCE_TAGS[@]:0:${candidate_index}}"; do
        if [[ "${VLESS_CONFIG_INSTANCE_TAGS[${candidate_index}]}" == "${existing_tag}" ]]; then
          return 1
        fi
      done
    done
  fi
}

render_expected_protocol_state_snapshot() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 1

  local protocol inbound_index cert_provider_tag outbound_policy acme_extra_json
  local mixed_expected_port mixed_expected_username mixed_expected_password
  protocol=$(normalize_protocol_id "$1")
  inbound_index=$(find_config_inbound_index_by_protocol "${protocol}") || return 1

  case "${protocol}" in
    vless-reality)
      collect_vless_reality_config_instances || return 1
      printf 'DEFAULT_INSTANCE_ID=%s\n' "${VLESS_CONFIG_DEFAULT_INSTANCE_ID}"
      printf 'INSTANCE_IDS=%s\n' "$(IFS=,; printf '%s' "${VLESS_CONFIG_INSTANCE_IDS[*]}")"
      printf 'REALITY_PRIVATE_KEY=%s\n' "${VLESS_CONFIG_REALITY_PRIVATE_KEY}"
      for instance_index in "${!VLESS_CONFIG_INSTANCE_INDICES[@]}"; do
        inbound_index="${VLESS_CONFIG_INSTANCE_INDICES[${instance_index}]}"
        printf 'INSTANCE_%s_ID=%s\n' "$((instance_index + 1))" "${VLESS_CONFIG_INSTANCE_CANDIDATES[${instance_index}]}"
        printf 'INSTANCE_%s_TAG=%s\n' "$((instance_index + 1))" "${VLESS_CONFIG_INSTANCE_TAGS[${instance_index}]}"
        printf 'INSTANCE_%s_PORT=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_UUID=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].uuid // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_SNI=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" --arg fallback "" '.inbounds[$idx].tls.server_name // $fallback' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_SHORT_ID_1=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[0] // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_SHORT_ID_2=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[1] // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_ALPN_MODE=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '(.inbounds[$idx].tls.alpn // []) | if . == ["h2", "http/1.1"] then "h2_http1" elif . == ["http/1.1"] then "http1" else "off" end' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_TCP_FAST_OPEN=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" 'if .inbounds[$idx].tcp_fast_open == true then "y" else "n" end' "${SINGBOX_CONFIG_FILE}")"
        outbound_policy=$(vless_reality_outbound_policy_from_config "${VLESS_CONFIG_INSTANCE_TAGS[${instance_index}]}") || return 1
        printf 'INSTANCE_%s_OUTBOUND_POLICY=%s\n' "$((instance_index + 1))" "${outbound_policy}"
      done
      ;;
    mixed)
      mixed_expected_port=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // ""' "${SINGBOX_CONFIG_FILE}") || return 1
      if jq -e --argjson idx "${inbound_index}" '(.inbounds[$idx].users // []) | length > 0' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        mixed_expected_username=$(jq -j --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].username // "", "\u0001"' "${SINGBOX_CONFIG_FILE}") || return 1
        mixed_expected_username=${mixed_expected_username%$'\1'}
        mixed_expected_password=$(jq -j --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // "", "\u0001"' "${SINGBOX_CONFIG_FILE}") || return 1
        mixed_expected_password=${mixed_expected_password%$'\1'}
        jq -cn --arg port "${mixed_expected_port}" --arg username "${mixed_expected_username}" --arg password "${mixed_expected_password}" \
          '{port:$port,auth_enabled:"y",username:$username,password:$password}'
      else
        jq -cn --arg port "${mixed_expected_port}" \
          '{port:$port,auth_enabled:"n",username:"",password:""}'
      fi
      ;;
    hy2)
      cert_provider_tag=""
      printf 'PORT=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")"
      printf 'DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'PASSWORD=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'USER_NAME=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'UP_MBPS=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].up_mbps // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'DOWN_MBPS=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].down_mbps // ""' "${SINGBOX_CONFIG_FILE}")"
      if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        printf 'OBFS_ENABLED=y\n'
        printf 'OBFS_TYPE=salamander\n'
        printf 'OBFS_PASSWORD=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.password // ""' "${SINGBOX_CONFIG_FILE}")"
      else
        printf 'OBFS_ENABLED=n\n'
        printf 'OBFS_TYPE=\n'
        printf 'OBFS_PASSWORD=\n'
      fi

      if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        printf 'TLS_MODE=acme\n'
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'ACME_MODE=dns\n'
        else
          printf 'ACME_MODE=http\n'
        fi
        printf 'ACME_EMAIL=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
        acme_extra_json=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}") || return 1
        printf 'ACME_EXTRA_JSON=%s\n' "${acme_extra_json}"
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'DNS_PROVIDER=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")"
          printf 'CF_API_TOKEN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")"
        else
          printf 'DNS_PROVIDER=cloudflare\n'
          printf 'CF_API_TOKEN=\n'
        fi
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}" || return 1
        printf 'TLS_MODE=acme\n'
        printf 'ACME_MODE=%s\n' "${CERT_PROVIDER_ACME_MODE}"
        printf 'ACME_EMAIL=%s\n' "${CERT_PROVIDER_EMAIL}"
        printf 'ACME_DOMAIN=%s\n' "${CERT_PROVIDER_DOMAIN}"
        printf 'ACME_EXTRA_JSON=%s\n' "${CERT_PROVIDER_EXTRA_JSON}"
        printf 'DNS_PROVIDER=%s\n' "${CERT_PROVIDER_DNS_PROVIDER}"
        printf 'CF_API_TOKEN=%s\n' "${CERT_PROVIDER_CF_API_TOKEN}"
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      else
        printf 'TLS_MODE=manual\n'
        printf 'ACME_MODE=http\n'
        printf 'ACME_EMAIL=\n'
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'ACME_EXTRA_JSON={}\n'
        printf 'DNS_PROVIDER=cloudflare\n'
        printf 'CF_API_TOKEN=\n'
        printf 'CERT_PATH=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'KEY_PATH=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")"
      fi
      printf 'MASQUERADE=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].masquerade // ""' "${SINGBOX_CONFIG_FILE}")"
      ;;
    anytls)
      printf 'PORT=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")"
      printf 'DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'PASSWORD=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'USER_NAME=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")"
      if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        printf 'TLS_MODE=acme\n'
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'ACME_MODE=dns\n'
        else
          printf 'ACME_MODE=http\n'
        fi
        printf 'ACME_EMAIL=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
        acme_extra_json=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}") || return 1
        printf 'ACME_EXTRA_JSON=%s\n' "${acme_extra_json}"
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'DNS_PROVIDER=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")"
          printf 'CF_API_TOKEN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")"
        else
          printf 'DNS_PROVIDER=cloudflare\n'
          printf 'CF_API_TOKEN=\n'
        fi
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}" || return 1
        printf 'TLS_MODE=acme\n'
        printf 'ACME_MODE=%s\n' "${CERT_PROVIDER_ACME_MODE}"
        printf 'ACME_EMAIL=%s\n' "${CERT_PROVIDER_EMAIL}"
        printf 'ACME_DOMAIN=%s\n' "${CERT_PROVIDER_DOMAIN}"
        printf 'ACME_EXTRA_JSON=%s\n' "${CERT_PROVIDER_EXTRA_JSON}"
        printf 'DNS_PROVIDER=%s\n' "${CERT_PROVIDER_DNS_PROVIDER}"
        printf 'CF_API_TOKEN=%s\n' "${CERT_PROVIDER_CF_API_TOKEN}"
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      else
        printf 'TLS_MODE=manual\n'
        printf 'ACME_MODE=http\n'
        printf 'ACME_EMAIL=\n'
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'ACME_EXTRA_JSON={}\n'
        printf 'DNS_PROVIDER=cloudflare\n'
        printf 'CF_API_TOKEN=\n'
        printf 'CERT_PATH=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'KEY_PATH=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

render_saved_protocol_state_snapshot() {
  local protocol state_file
  protocol=$(normalize_protocol_id "$1")
  state_file=$(protocol_state_file "${protocol}")
  [[ -f "${state_file}" ]] || return 1

  case "${protocol}" in
    vless-reality)
      # shellcheck disable=SC1090
      (
        reset_vless_reality_state_source_variables
        source "${state_file}"
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" != "2" ]]; then
          printf 'DEFAULT_INSTANCE_ID=main\n'
          printf 'INSTANCE_IDS=main\n'
          printf 'REALITY_PRIVATE_KEY=%s\n' "${REALITY_PRIVATE_KEY:-}"
          printf 'INSTANCE_1_ID=main\n'
          printf 'INSTANCE_1_TAG=vless-in\n'
          printf 'INSTANCE_1_PORT=%s\n' "${PORT:-}"
          printf 'INSTANCE_1_UUID=%s\n' "${UUID:-}"
          printf 'INSTANCE_1_SNI=%s\n' "${SNI:-}"
          printf 'INSTANCE_1_SHORT_ID_1=%s\n' "${SHORT_ID_1:-}"
          printf 'INSTANCE_1_SHORT_ID_2=%s\n' "${SHORT_ID_2:-}"
          printf 'INSTANCE_1_ALPN_MODE=off\n'
          printf 'INSTANCE_1_TCP_FAST_OPEN=n\n'
          printf 'INSTANCE_1_OUTBOUND_POLICY=default\n'
          exit 0
        fi
        VLESS_REALITY_DEFAULT_INSTANCE_ID="${DEFAULT_INSTANCE_ID:-main}"
        VLESS_REALITY_INSTANCE_IDS=$(normalize_csv_list "${INSTANCE_IDS:-}")
        printf 'DEFAULT_INSTANCE_ID=%s\n' "${VLESS_REALITY_DEFAULT_INSTANCE_ID}"
        printf 'INSTANCE_IDS=%s\n' "${VLESS_REALITY_INSTANCE_IDS}"
        printf 'REALITY_PRIVATE_KEY=%s\n' "${REALITY_PRIVATE_KEY:-}"
        instance_index=0
        while IFS= read -r instance_id; do
          [[ -n "${instance_id}" ]] || continue
          load_vless_reality_instance_state "${instance_id}" || exit 1
          instance_index=$((instance_index + 1))
          printf 'INSTANCE_%s_ID=%s\n' "${instance_index}" "${SB_VLESS_INSTANCE_ID}"
          printf 'INSTANCE_%s_TAG=%s\n' "${instance_index}" "$(vless_reality_inbound_tag_for_instance "${instance_id}")"
          printf 'INSTANCE_%s_PORT=%s\n' "${instance_index}" "${SB_PORT}"
          printf 'INSTANCE_%s_UUID=%s\n' "${instance_index}" "${SB_UUID}"
          printf 'INSTANCE_%s_SNI=%s\n' "${instance_index}" "${SB_SNI}"
          printf 'INSTANCE_%s_SHORT_ID_1=%s\n' "${instance_index}" "${SB_SHORT_ID_1}"
          printf 'INSTANCE_%s_SHORT_ID_2=%s\n' "${instance_index}" "${SB_SHORT_ID_2}"
          printf 'INSTANCE_%s_ALPN_MODE=%s\n' "${instance_index}" "${SB_VLESS_ALPN_MODE}"
          printf 'INSTANCE_%s_TCP_FAST_OPEN=%s\n' "${instance_index}" "${SB_VLESS_TCP_FAST_OPEN}"
          printf 'INSTANCE_%s_OUTBOUND_POLICY=%s\n' "${instance_index}" "${SB_OUTBOUND_POLICY}"
        done < <(tr ',' '\n' <<< "${VLESS_REALITY_INSTANCE_IDS}")
      )
      ;;
    mixed)
      # shellcheck disable=SC1090
      (
        source "${state_file}"
        jq -cn --arg port "${PORT:-}" --arg auth_enabled "${AUTH_ENABLED:-}" \
          --arg username "${USERNAME:-}" --arg password "${PASSWORD:-}" \
          '{port:$port,auth_enabled:$auth_enabled,username:$username,password:$password}'
      )
      ;;
    hy2)
      # shellcheck disable=SC1090
      (
        source "${state_file}"
        printf 'PORT=%s\n' "${PORT:-}"
        printf 'DOMAIN=%s\n' "${DOMAIN:-}"
        printf 'PASSWORD=%s\n' "${PASSWORD:-}"
        printf 'USER_NAME=%s\n' "${USER_NAME:-}"
        printf 'UP_MBPS=%s\n' "${UP_MBPS:-}"
        printf 'DOWN_MBPS=%s\n' "${DOWN_MBPS:-}"
        printf 'OBFS_ENABLED=%s\n' "${OBFS_ENABLED:-}"
        printf 'OBFS_TYPE=%s\n' "${OBFS_TYPE:-}"
        printf 'OBFS_PASSWORD=%s\n' "${OBFS_PASSWORD:-}"
        printf 'TLS_MODE=%s\n' "${TLS_MODE:-}"
        printf 'ACME_MODE=%s\n' "${ACME_MODE:-}"
        printf 'ACME_EMAIL=%s\n' "${ACME_EMAIL:-}"
        printf 'ACME_DOMAIN=%s\n' "${ACME_DOMAIN:-}"
        printf 'ACME_EXTRA_JSON=%s\n' "$(acme_extra_json_or_default "${ACME_EXTRA_JSON:-}")"
        printf 'DNS_PROVIDER=%s\n' "${DNS_PROVIDER:-}"
        printf 'CF_API_TOKEN=%s\n' "${CF_API_TOKEN:-}"
        printf 'CERT_PATH=%s\n' "${CERT_PATH:-}"
        printf 'KEY_PATH=%s\n' "${KEY_PATH:-}"
        printf 'MASQUERADE=%s\n' "${MASQUERADE:-}"
      )
      ;;
    anytls)
      # shellcheck disable=SC1090
      (
        source "${state_file}"
        printf 'PORT=%s\n' "${PORT:-}"
        printf 'DOMAIN=%s\n' "${DOMAIN:-}"
        printf 'PASSWORD=%s\n' "${PASSWORD:-}"
        printf 'USER_NAME=%s\n' "${USER_NAME:-}"
        printf 'TLS_MODE=%s\n' "${TLS_MODE:-}"
        printf 'ACME_MODE=%s\n' "${ACME_MODE:-}"
        printf 'ACME_EMAIL=%s\n' "${ACME_EMAIL:-}"
        printf 'ACME_DOMAIN=%s\n' "${ACME_DOMAIN:-}"
        printf 'ACME_EXTRA_JSON=%s\n' "$(acme_extra_json_or_default "${ACME_EXTRA_JSON:-}")"
        printf 'DNS_PROVIDER=%s\n' "${DNS_PROVIDER:-}"
        printf 'CF_API_TOKEN=%s\n' "${CF_API_TOKEN:-}"
        printf 'CERT_PATH=%s\n' "${CERT_PATH:-}"
        printf 'KEY_PATH=%s\n' "${KEY_PATH:-}"
      )
      ;;
    *)
      return 1
      ;;
  esac
}

protocol_state_matches_config() {
  local protocol expected_snapshot saved_snapshot
  protocol=$(normalize_protocol_id "$1")

  # Schema-2 Mixed state is represented by the typed instance store.  Do this
  # before the legacy snapshot path, which intentionally only knows the
  # singleton .env fields and would compare just the first inbound.
  if [[ "${protocol}" == "mixed" ]]; then
    if mixed_structured_state_active >/dev/null 2>&1 || {
      local mixed_state_file mixed_state_schema
      mixed_state_file=$(protocol_state_file "mixed" 2>/dev/null || true)
      mixed_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${mixed_state_file}" 2>/dev/null | head -n1 || true)
      mixed_state_schema=${mixed_state_schema//\"/}
      mixed_state_schema=${mixed_state_schema//\'/}
      [[ "${mixed_state_schema}" == "2" ]]
    }; then
      mixed_structured_state_matches_config
      return $?
    fi
  fi
  if [[ "${protocol}" == "socks" ]]; then
    # SOCKS has no schema-1 fallback: compare the complete typed inventory,
    # including every tag, listener, credential tuple, and route policy.
    plain_proxy_structured_state_matches_config socks
    return $?
  fi
  if [[ "${protocol}" == "http" ]]; then
    # HTTP has no schema-1 fallback either: compare every typed inbound,
    # including authentication, route policy, and the complete TLS record.
    plain_proxy_structured_state_matches_config http
    return $?
  fi
  if [[ "${protocol}" == "shadowsocks" ]]; then
    # Shadowsocks has no legacy snapshot fallback: compare every typed
    # listener, network selection, authentication record, and route policy.
    plain_proxy_structured_state_matches_config shadowsocks
    return $?
  fi
  if [[ "${protocol}" == "trojan" ]]; then
    plain_proxy_structured_state_matches_config trojan
    return $?
  fi
  if [[ "${protocol}" == "vmess" ]]; then
    plain_proxy_structured_state_matches_config vmess
    return $?
  fi
  if [[ "${protocol}" == "vless-plain" ]]; then
    plain_proxy_structured_state_matches_config vless-plain
    return $?
  fi
  if [[ "${protocol}" == "anytls" ]]; then
    local anytls_state_file anytls_state_schema
    anytls_state_file=$(protocol_state_file "anytls" 2>/dev/null || true)
    anytls_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${anytls_state_file}" 2>/dev/null | head -n1 || true)
    anytls_state_schema=${anytls_state_schema//\"/}
    anytls_state_schema=${anytls_state_schema//\'/}
    if [[ "${anytls_state_schema}" == "2" ]]; then
      plain_proxy_structured_state_matches_config anytls
      return $?
    fi
  fi
  if [[ "${protocol}" == "hy2" ]]; then
    local hy2_state_file hy2_state_schema
    hy2_state_file=$(protocol_state_file "hy2" 2>/dev/null || true)
    hy2_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${hy2_state_file}" 2>/dev/null | head -n1 || true)
    hy2_state_schema=${hy2_state_schema//\"/}
    hy2_state_schema=${hy2_state_schema//\'/}
    if [[ "${hy2_state_schema}" == "2" ]]; then
      plain_proxy_structured_state_matches_config hy2
      return $?
    fi
  fi
  if [[ "${protocol}" == "snell" ]]; then
    plain_proxy_structured_state_matches_config snell
    return $?
  fi
  if [[ "${protocol}" == "tuic" ]]; then
    plain_proxy_structured_state_matches_config tuic
    return $?
  fi
  if [[ "${protocol}" == "hysteria" ]]; then
    plain_proxy_structured_state_matches_config hysteria
    return $?
  fi
  if [[ "${protocol}" == "naive" ]]; then
    plain_proxy_structured_state_matches_config naive
    return $?
  fi
  if [[ "${protocol}" == "shadowtls" ]]; then
    plain_proxy_structured_state_matches_config shadowtls
    return $?
  fi

  expected_snapshot=$(render_expected_protocol_state_snapshot "${protocol}") || return 1
  saved_snapshot=$(render_saved_protocol_state_snapshot "${protocol}") || return 1

  [[ "${saved_snapshot}" == "${expected_snapshot}" ]]
}

protocol_state_layer_matches_config() {
  local allow_legacy_download_detour=${1:-false}
  [[ "${allow_legacy_download_detour}" == true || "${allow_legacy_download_detour}" == false ]] || return 1
  [[ -f "${SINGBOX_CONFIG_FILE}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1
  validate_protocol_index_for_rebuild || return 1

  local config_protocols=()
  local indexed_protocols=()
  local normalized_indexed_protocols=()
  local protocol joined_config joined_index config_inventory

  config_inventory=$(list_config_protocols "${allow_legacy_download_detour}") || return 1
  [[ -n "${config_inventory}" ]] || return 1
  mapfile -t config_protocols <<< "${config_inventory}"
  [[ ${#config_protocols[@]} -gt 0 ]] || return 1

  mapfile -t indexed_protocols < <(list_indexed_protocols_raw)
  [[ ${#indexed_protocols[@]} -eq ${#config_protocols[@]} ]] || return 1

  for protocol in "${indexed_protocols[@]}"; do
    protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || true)
    [[ -n "${protocol}" ]] || return 1
    normalized_indexed_protocols+=("${protocol}")
  done

  joined_config=$(IFS=,; printf '%s' "${config_protocols[*]}")
  joined_index=$(IFS=,; printf '%s' "${normalized_indexed_protocols[*]}")
  [[ "${joined_config}" == "${joined_index}" ]] || return 1

  for protocol in "${config_protocols[@]}"; do
    protocol_state_exists "${protocol}" || return 1
    protocol_state_matches_config "${protocol}" || return 1
  done

  return 0
}

clear_protocol_state_cache() {
  local state_file

  rm -f "${SB_PROTOCOL_INDEX_FILE}"

  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
      [[ -e "${state_file}" ]] || continue
      rm -f "${state_file}"
    done
  fi
}

log_takeover_state_diagnostics() {
  local config_protocols=()
  local indexed_protocols=()
  local protocol config_inventory

  [[ -x "${SINGBOX_BIN_PATH}" ]] || log_warn "接管诊断: 缺少 sing-box 二进制 ${SINGBOX_BIN_PATH}"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] || log_warn "接管诊断: 缺少 systemd 服务文件 ${SINGBOX_SERVICE_FILE}"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || log_warn "接管诊断: 缺少配置文件 ${SINGBOX_CONFIG_FILE}"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || log_warn "接管诊断: 缺少协议索引 ${SB_PROTOCOL_INDEX_FILE}"

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if ! config_inventory=$(list_config_protocols); then
      log_warn "接管诊断: 配置包含无法完整识别的入站；未输出部分协议清单或原始配置。"
      return 1
    fi
    if [[ -n "${config_inventory}" ]]; then
      mapfile -t config_protocols <<< "${config_inventory}"
    fi
    if [[ ${#config_protocols[@]} -gt 0 ]]; then
      log_warn "接管诊断: 配置文件识别到的协议: $(IFS=,; printf '%s' "${config_protocols[*]}")"
    else
      log_warn "接管诊断: 配置文件中未识别到受支持协议。"
    fi
  fi

  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    validate_protocol_index_for_rebuild || return 1
    mapfile -t indexed_protocols < <(list_indexed_protocols_raw)
    if [[ ${#indexed_protocols[@]} -gt 0 ]]; then
      log_warn "接管诊断: 协议索引记录的协议: $(IFS=,; printf '%s' "${indexed_protocols[*]}")"
    else
      log_warn "接管诊断: 协议索引为空。"
    fi
  fi

  for protocol in "${config_protocols[@]}"; do
    if ! protocol_state_exists "${protocol}"; then
      log_warn "接管诊断: 缺少协议状态文件 $(protocol_state_file "${protocol}")"
      continue
    fi
    if ! protocol_state_matches_config "${protocol}"; then
      log_warn "接管诊断: 协议状态与配置不一致: ${protocol}"
      log_warn "接管诊断: 快照可能包含认证材料，已省略原始值；请在本机安全地检查配置与状态文件。"
    fi
  done
}
