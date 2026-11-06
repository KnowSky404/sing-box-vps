
protocol_state_file() {
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1
  printf '%s/%s.env' "${SB_PROTOCOL_STATE_DIR}" "${protocol}"
}

ensure_protocol_state_dir() {
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
}

write_env_assignment() {
  local key=$1
  local value=${2-}
  local escaped
  printf -v escaped '%q' "${value}"
  printf '%s=%s\n' "${key}" "${escaped}"
}

acme_extra_json_or_default() {
  local value=${1:-}

  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '{}'
  fi
}

vless_reality_instance_dir() {
  printf '%s/vless-reality.d' "${SB_PROTOCOL_STATE_DIR}"
}

validate_vless_reality_instance_id() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

validate_port_number() {
  local port=$1
  [[ "${port}" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

validate_optional_positive_integer() {
  local value=$1
  [[ -z "${value}" || "${value}" =~ ^[1-9][0-9]*$ ]]
}

validate_vless_reality_alpn_mode() {
  case "${1:-off}" in
    off|h2_http1|http1) return 0 ;;
    *) return 1 ;;
  esac
}

vless_reality_alpn_json_for_mode() {
  local mode=${1:-off}

  case "${mode}" in
    h2_http1) jq -n '["h2", "http/1.1"]' ;;
    http1) jq -n '["http/1.1"]' ;;
    *) jq -n 'null' ;;
  esac
}

vless_reality_alpn_mode_display_name() {
  case "${1:-off}" in
    h2_http1) printf 'h2 + http/1.1' ;;
    http1) printf 'http/1.1' ;;
    *) printf '关闭' ;;
  esac
}

vless_reality_alpn_link_value_for_mode() {
  case "${1:-off}" in
    h2_http1) printf 'h2,http/1.1' ;;
    http1) printf 'http/1.1' ;;
    *) printf '' ;;
  esac
}

validate_optional_email() {
  local value=$1
  [[ -z "${value}" || "${value}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

validate_non_empty_path() {
  local value=$1
  [[ -n "${value}" && "${value}" != *$'\n'* && "${value}" == /* ]]
}

validate_http_url() {
  local value=$1
  [[ "${value}" =~ ^https?://[^[:space:]/$.?#][^[:space:]]*$ ]]
}

hy2_reality_masquerade_candidates() (
  local instance_id sni ids
  {
    if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
      jq -r '.inbounds[]? | select(.type == "vless" and .tls.reality.enabled == true) |
        .tls.server_name // .tls.reality.handshake.server // empty' "${SINGBOX_CONFIG_FILE}" || return 1
    fi
    ids=$(list_vless_reality_instance_ids) || return 1
    while IFS= read -r instance_id; do
      [[ -n "${instance_id}" ]] || continue
      load_vless_reality_instance_state "${instance_id}" || return 1
      printf '%s\n' "${SB_SNI}"
    done <<< "${ids}"
  } | sort -u | while IFS= read -r sni; do
    if validate_reality_sni_syntax "${sni}"; then printf 'https://%s\n' "${sni}"; fi
  done
)

probe_hy2_masquerade_url() {
  local url=$1 status escaped_url
  [[ "${url}" != *[[:cntrl:]]* ]] || return 1
  escaped_url=${url//\\/\\\\}
  escaped_url=${escaped_url//\"/\\\"}
  # Keep URL credentials and query values out of curl's process arguments.
  status=$(printf 'url = "%s"\n' "${escaped_url}" | \
    curl --silent --globoff --head --location --max-redirs 3 --output /dev/null \
      --write-out '%{http_code}' --connect-timeout 5 --max-time 10 \
      --proto '=http,https' --proto-redir '=http,https' --config - 2>/dev/null) || return 1
  [[ "${status}" =~ ^[23][0-9][0-9]$ ]]
}

prompt_hy2_masquerade_url() {
  local prompt=$1 current=${2:-} operation=${3:-replace} value candidate_text index
  local candidates=()
  if candidate_text=$(hy2_reality_masquerade_candidates); then
    if [[ -n "${candidate_text}" ]]; then mapfile -t candidates <<< "${candidate_text}"; fi
  else
    log_warn '无法读取 REALITY SNI 候选，可直接输入伪装 URL。' >&2
  fi
  for ((index=0; index<${#candidates[@]}; index++)); do
    printf '[Hysteria2] r%s: %s（REALITY SNI 候选，仅作伪装网站，不替代 HY2 证书域名）\n' \
      "$((index + 1))" "${candidates[index]}" >&2
  done
  [[ ${#candidates[@]} -eq 0 ]] || echo '[Hysteria2] 可输入 r1 等编号选择候选，选择后单独检测 HTTP(S) 可用性。' >&2
  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    if [[ -z "${value}" ]]; then
      if [[ "${operation}" != create || -z "${current}" ]]; then
        printf '%s' "${current}"
        return 0
      fi
      value=${current}
    fi
    if [[ "${value}" =~ ^r([1-9][0-9]{0,2})$ ]]; then
      index=$((10#${BASH_REMATCH[1]} - 1))
      if (( index >= ${#candidates[@]} )); then
        log_warn '无此 REALITY SNI 候选编号，请重新输入。' >&2
        continue
      fi
      value=${candidates[index]}
    fi
    # Preserve the administrator's URL, including case-sensitive paths.
    if [[ "${value,,}" == file:* && "${value}" != *[[:cntrl:]]* ]]; then
      printf '%s' "${value}"
      return 0
    fi
    if ! validate_http_url "${value,,}" || [[ "${value}" == *[[:cntrl:]]* ]]; then
      log_warn '伪装网站 URL 必须包含 http:// 或 https://，例如 https://www.cloudflare.com；本地目录使用 file:///绝对路径。请重新输入。' >&2
    elif probe_hy2_masquerade_url "${value}"; then
      printf '%s' "${value}"
      return 0
    else
      log_warn '伪装网站 HTTP(S) 检测失败（DNS、TLS、超时或非 2xx/3xx 响应），请重新输入；修改时留空保留原地址。' >&2
    fi
  done
}

validate_update_interval() {
  local value=$1
  [[ "${value}" =~ ^[1-9][0-9]*[smhd]$ ]]
}

prompt_choice() {
  local prompt=$1 min=$2 max=$3 default=${4:-}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    if [[ -z "${value}" && -n "${default}" ]]; then
      printf '%s' "${default}"
      return 0
    fi
    if [[ "${value}" =~ ^[0-9]+$ && "${value}" -ge "${min}" && "${value}" -le "${max}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "请输入 ${min}-${max} 范围内的数字。" >&2
  done
}

prompt_yes_no() {
  local prompt=$1 default=${2:-}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    value=${value,,}
    if [[ -z "${value}" && -n "${default}" ]]; then
      printf '%s' "${default}"
      return 0
    fi
    case "${value}" in
      y|n)
        printf '%s' "${value}"
        return 0
        ;;
      *)
        log_warn "请输入 y 或 n。" >&2
        ;;
    esac
  done
}

prompt_port() {
  local prompt=$1 default=${2:-}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    [[ -z "${value}" && -n "${default}" ]] && value="${default}"
    if validate_port_number "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "端口必须为 1-65535 的数字。" >&2
  done
}

prompt_optional_positive_integer() {
  local prompt=$1 default=${2:-} label=${3:-数值}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    [[ -z "${value}" && -n "${default}" ]] && value="${default}"
    if validate_optional_positive_integer "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "${label}必须为空或正整数。" >&2
  done
}

prompt_optional_nonnegative_integer() {
  local prompt=$1 default=${2:-} label=${3:-数值}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    [[ -z "${value}" && -n "${default}" ]] && value="${default}"
    if [[ -z "${value}" || "${value}" =~ ^[0-9]+$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "${label}必须为空或非负整数。" >&2
  done
}

prompt_update_optional_positive_integer() {
  local prompt=$1 label=${2:-数值}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    if validate_optional_positive_integer "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "${label}必须为空或正整数。" >&2
  done
}

prompt_optional_choice() {
  local prompt=$1 min=$2 max=$3
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    if [[ -z "${value}" ]]; then
      printf ''
      return 0
    fi
    if [[ "${value}" =~ ^[0-9]+$ && "${value}" -ge "${min}" && "${value}" -le "${max}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "请输入 ${min}-${max} 范围内的数字，或留空保持当前设置。" >&2
  done
}

prompt_optional_email() {
  local prompt=$1 default=${2:-}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    [[ -z "${value}" && -n "${default}" ]] && value="${default}"
    if validate_optional_email "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "邮箱格式不正确，请输入 user@example.com 或留空。" >&2
  done
}

prompt_required_path() {
  local prompt=$1
  local default=${2:-}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    [[ -z "${value}" && -n "${default}" ]] && value="${default}"
    if validate_non_empty_path "${value}"; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "路径必须为绝对路径，例如 /etc/ssl/certs/fullchain.pem。" >&2
  done
}

prompt_optional_domain() {
  local prompt=$1 default=${2:-}
  local value

  while true; do
    read -rp "${prompt}" value || return 1
    value=$(trim_whitespace "${value}")
    [[ -z "${value}" && -n "${default}" ]] && value="${default}"
    if [[ -z "${value}" || "${value}" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
      printf '%s' "${value}"
      return 0
    fi
    log_warn "域名格式不正确，例如 example.com。" >&2
  done
}

vless_reality_instance_state_file() {
  local instance_id=$1
  validate_vless_reality_instance_id "${instance_id}" || return 1
  printf '%s/%s.env' "$(vless_reality_instance_dir)" "${instance_id}"
}

normalize_csv_list() {
  local value=$1
  value=${value//\"/}
  value=${value//\'/}
  value=${value//\\,/,}
  printf '%s' "${value}"
}

load_vless_reality_protocol_state() {
  local state_file
  state_file=$(protocol_state_file "vless-reality")

  VLESS_REALITY_DEFAULT_INSTANCE_ID="main"
  VLESS_REALITY_INSTANCE_IDS=""
  SB_PRIVATE_KEY=""
  SB_PUBLIC_KEY=""

  [[ -f "${state_file}" ]] || return 0

  unset INSTALLED CONFIG_SCHEMA_VERSION DEFAULT_INSTANCE_ID INSTANCE_IDS
  unset REALITY_PRIVATE_KEY REALITY_PUBLIC_KEY
  # shellcheck disable=SC1090
  source "${state_file}"
  VLESS_REALITY_DEFAULT_INSTANCE_ID="${DEFAULT_INSTANCE_ID:-main}"
  VLESS_REALITY_INSTANCE_IDS=$(normalize_csv_list "${INSTANCE_IDS:-}")
  SB_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-${SB_PRIVATE_KEY:-}}"
  SB_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-${SB_PUBLIC_KEY:-}}"
}

save_vless_reality_protocol_state() {
  local state_file
  state_file=$(protocol_state_file "vless-reality")
  ensure_protocol_state_dir

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "2"
    write_env_assignment "DEFAULT_INSTANCE_ID" "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}"
    printf 'INSTANCE_IDS=%s\n' "${VLESS_REALITY_INSTANCE_IDS:-main}"
    write_env_assignment "REALITY_PRIVATE_KEY" "${SB_PRIVATE_KEY}"
    write_env_assignment "REALITY_PUBLIC_KEY" "${SB_PUBLIC_KEY}"
  } > "${state_file}"
}

load_vless_reality_instance_state() {
  local instance_id=$1
  local state_file
  state_file=$(vless_reality_instance_state_file "${instance_id}") || return 1

  SB_VLESS_INSTANCE_ID="${instance_id}"
  SB_VLESS_INBOUND_TAG=""
  SB_NODE_NAME=""
  SB_PORT=""
  SB_UUID=""
  SB_SNI=""
  SB_SHORT_ID_1=""
  SB_SHORT_ID_2=""
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
  SB_OUTBOUND_POLICY="default"
  SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="n"

  [[ -f "${state_file}" ]] || return 1

  unset INSTANCE_ID INBOUND_TAG ENABLED NODE_NAME PORT UUID SNI SHORT_ID_1 SHORT_ID_2
  unset RATE_LIMIT_UP_MBPS RATE_LIMIT_DOWN_MBPS ALPN_MODE TCP_FAST_OPEN OUTBOUND_POLICY

  # shellcheck disable=SC1090
  source "${state_file}"
  SB_VLESS_INSTANCE_ID="${INSTANCE_ID:-${instance_id}}"
  SB_VLESS_INBOUND_TAG="${INBOUND_TAG:-}"
  SB_NODE_NAME=$(normalize_node_name "${NODE_NAME:-}")
  SB_PORT="${PORT:-}"
  SB_UUID="${UUID:-}"
  SB_SNI="${SNI:-}"
  SB_SHORT_ID_1="${SHORT_ID_1:-}"
  SB_SHORT_ID_2="${SHORT_ID_2:-}"
  SB_VLESS_RATE_LIMIT_UP_MBPS="${RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${RATE_LIMIT_DOWN_MBPS:-}"
  if validate_vless_reality_alpn_mode "${ALPN_MODE:-off}"; then
    SB_VLESS_ALPN_MODE="${ALPN_MODE:-off}"
  else
    SB_VLESS_ALPN_MODE="off"
  fi
  case "${TCP_FAST_OPEN:-n}" in
    y|n) SB_VLESS_TCP_FAST_OPEN="${TCP_FAST_OPEN:-n}" ;;
    *) SB_VLESS_TCP_FAST_OPEN="n" ;;
  esac
  if validate_instance_outbound_policy "${OUTBOUND_POLICY:-default}"; then
    SB_OUTBOUND_POLICY="${OUTBOUND_POLICY:-default}"
  else
    SB_OUTBOUND_POLICY="default"
  fi
}

save_vless_reality_instance_state() {
  local instance_id=${SB_VLESS_INSTANCE_ID:-main}
  local state_file
  validate_vless_reality_instance_id "${instance_id}" || log_error "REALITY 实例 ID 非法: ${instance_id}"
  mkdir -p "$(vless_reality_instance_dir)"
  state_file=$(vless_reality_instance_state_file "${instance_id}") || return 1

  {
    write_env_assignment "INSTANCE_ID" "${instance_id}"
    write_env_assignment "INBOUND_TAG" "${SB_VLESS_INBOUND_TAG:-}"
    write_env_assignment "ENABLED" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "UUID" "${SB_UUID}"
    write_env_assignment "SNI" "${SB_SNI}"
    write_env_assignment "SHORT_ID_1" "${SB_SHORT_ID_1}"
    write_env_assignment "SHORT_ID_2" "${SB_SHORT_ID_2}"
    printf 'RATE_LIMIT_UP_MBPS=%s\n' "${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
    printf 'RATE_LIMIT_DOWN_MBPS=%s\n' "${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
    write_env_assignment "ALPN_MODE" "${SB_VLESS_ALPN_MODE:-off}"
    write_env_assignment "TCP_FAST_OPEN" "${SB_VLESS_TCP_FAST_OPEN:-n}"
    write_env_assignment "OUTBOUND_POLICY" "${SB_OUTBOUND_POLICY:-default}"
  } > "${state_file}"
}

save_vless_reality_protocol_material_state_if_v2() {
  local state_file current_private_key current_public_key
  state_file=$(protocol_state_file "vless-reality")

  [[ -f "${state_file}" ]] || return 0
  grep -Eq '^CONFIG_SCHEMA_VERSION=(2|'"'2'"'|'\''2'\'')$' "${state_file}" || return 0

  current_private_key="${SB_PRIVATE_KEY}"
  current_public_key="${SB_PUBLIC_KEY}"
  load_vless_reality_protocol_state
  SB_PRIVATE_KEY="${current_private_key}"
  SB_PUBLIC_KEY="${current_public_key}"
  save_vless_reality_protocol_state
}

migrate_vless_reality_state_to_instances_if_needed() {
  local state_file instance_dir main_state backup_state_file
  state_file=$(protocol_state_file "vless-reality")
  instance_dir=$(vless_reality_instance_dir)
  main_state="${instance_dir}/main.env"

  [[ -f "${state_file}" ]] || return 0
  [[ ! -f "${main_state}" ]] || return 0

  reset_vless_reality_state_source_variables
  # shellcheck disable=SC1090
  source "${state_file}"

  if [[ "${CONFIG_SCHEMA_VERSION:-1}" != "1" || -z "${PORT:-}" || -z "${UUID:-}" ]]; then
    return 0
  fi

  if [[ "${SB_ROUTING_JOURNAL_LEGACY_BACKUP:-n}" == y ]]; then
    # A surrounding rules transaction owns this migration. Keep its backup
    # inside the durable journal, outside concurrent operator-file detection.
    routing_transaction_backup_legacy_reality_state "${state_file}" || return 1
  else
    backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${state_file}" "${backup_state_file}" || return 1
  fi

  SB_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
  SB_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
  VLESS_REALITY_DEFAULT_INSTANCE_ID="main"
  VLESS_REALITY_INSTANCE_IDS="main"
  save_vless_reality_protocol_state

  SB_VLESS_INSTANCE_ID="main"
  SB_NODE_NAME=$(normalize_node_name "${NODE_NAME:-$(default_node_name_for_protocol "vless+reality")}")
  SB_PORT="${PORT:-443}"
  SB_UUID="${UUID:-}"
  SB_SNI="${SNI:-}"
  SB_SHORT_ID_1="${SHORT_ID_1:-}"
  SB_SHORT_ID_2="${SHORT_ID_2:-}"
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
  SB_OUTBOUND_POLICY="default"
  save_vless_reality_instance_state
}

list_vless_reality_instance_ids() {
  local instance_dir
  load_vless_reality_protocol_state

  if [[ -n "${VLESS_REALITY_INSTANCE_IDS}" ]]; then
    tr ',' '\n' <<< "${VLESS_REALITY_INSTANCE_IDS}" | sed '/^$/d'
    return 0
  fi

  instance_dir=$(vless_reality_instance_dir)
  [[ -d "${instance_dir}" ]] || return 0

  find "${instance_dir}" -maxdepth 1 -type f -name '*.env' \
    | sed 's|.*/||; s|\.env$||' \
    | sort
}

vless_reality_instance_id_exists() {
  local target=$1 instance_id
  while IFS= read -r instance_id; do
    [[ "${instance_id}" == "${target}" ]] && return 0
  done < <(list_vless_reality_instance_ids)
  return 1
}

vless_reality_bandwidth_profile_exists() {
  local target_up=${1:-}
  local target_down=${2:-}
  local exclude_instance_id=${3:-}
  local instance_id
  local saved_instance_id saved_node_name saved_port saved_uuid saved_sni
  local saved_short_id_1 saved_short_id_2 saved_rate_limit_up saved_rate_limit_down
  local saved_alpn_mode saved_tcp_fast_open

  saved_instance_id="${SB_VLESS_INSTANCE_ID:-}"
  saved_node_name="${SB_NODE_NAME:-}"
  saved_port="${SB_PORT:-}"
  saved_uuid="${SB_UUID:-}"
  saved_sni="${SB_SNI:-}"
  saved_short_id_1="${SB_SHORT_ID_1:-}"
  saved_short_id_2="${SB_SHORT_ID_2:-}"
  saved_rate_limit_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  saved_rate_limit_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
  saved_alpn_mode="${SB_VLESS_ALPN_MODE:-off}"
  saved_tcp_fast_open="${SB_VLESS_TCP_FAST_OPEN:-n}"

  migrate_vless_reality_state_to_instances_if_needed
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    [[ -n "${exclude_instance_id}" && "${instance_id}" == "${exclude_instance_id}" ]] && continue
    load_vless_reality_instance_state "${instance_id}" || continue
    if [[ "${SB_VLESS_RATE_LIMIT_UP_MBPS:-}" == "${target_up}" && "${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}" == "${target_down}" ]]; then
      SB_VLESS_INSTANCE_ID="${saved_instance_id}"
      SB_NODE_NAME="${saved_node_name}"
      SB_PORT="${saved_port}"
      SB_UUID="${saved_uuid}"
      SB_SNI="${saved_sni}"
      SB_SHORT_ID_1="${saved_short_id_1}"
      SB_SHORT_ID_2="${saved_short_id_2}"
      SB_VLESS_RATE_LIMIT_UP_MBPS="${saved_rate_limit_up}"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="${saved_rate_limit_down}"
      SB_VLESS_ALPN_MODE="${saved_alpn_mode}"
      SB_VLESS_TCP_FAST_OPEN="${saved_tcp_fast_open}"
      return 0
    fi
  done < <(list_vless_reality_instance_ids)

  SB_VLESS_INSTANCE_ID="${saved_instance_id}"
  SB_NODE_NAME="${saved_node_name}"
  SB_PORT="${saved_port}"
  SB_UUID="${saved_uuid}"
  SB_SNI="${saved_sni}"
  SB_SHORT_ID_1="${saved_short_id_1}"
  SB_SHORT_ID_2="${saved_short_id_2}"
  SB_VLESS_RATE_LIMIT_UP_MBPS="${saved_rate_limit_up}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${saved_rate_limit_down}"
  SB_VLESS_ALPN_MODE="${saved_alpn_mode}"
  SB_VLESS_TCP_FAST_OPEN="${saved_tcp_fast_open}"
  return 1
}

build_vless_reality_qos_plan() {
  local state_file instance_id up down direction
  local saved_instance_id saved_node_name saved_port saved_uuid saved_sni
  local saved_short_id_1 saved_short_id_2 saved_rate_limit_up saved_rate_limit_down
  local saved_alpn_mode saved_tcp_fast_open
  state_file=$(protocol_state_file "vless-reality")
  [[ -f "${state_file}" ]] || return 0

  saved_instance_id="${SB_VLESS_INSTANCE_ID:-}"
  saved_node_name="${SB_NODE_NAME:-}"
  saved_port="${SB_PORT:-}"
  saved_uuid="${SB_UUID:-}"
  saved_sni="${SB_SNI:-}"
  saved_short_id_1="${SB_SHORT_ID_1:-}"
  saved_short_id_2="${SB_SHORT_ID_2:-}"
  saved_rate_limit_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  saved_rate_limit_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
  saved_alpn_mode="${SB_VLESS_ALPN_MODE:-off}"
  saved_tcp_fast_open="${SB_VLESS_TCP_FAST_OPEN:-n}"

  migrate_vless_reality_state_to_instances_if_needed

  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    load_vless_reality_instance_state "${instance_id}" || continue
    up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
    down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
    [[ -z "${up}" && -z "${down}" ]] && continue

    if [[ -n "${up}" && -n "${down}" ]]; then
      direction="both"
    elif [[ -n "${up}" ]]; then
      direction="up"
    else
      direction="down"
    fi

    printf '%s|%s|%s|%s\n' "${SB_PORT}" "${direction}" "${up}" "${down}"
  done < <(list_vless_reality_instance_ids)

  SB_VLESS_INSTANCE_ID="${saved_instance_id}"
  SB_NODE_NAME="${saved_node_name}"
  SB_PORT="${saved_port}"
  SB_UUID="${saved_uuid}"
  SB_SNI="${saved_sni}"
  SB_SHORT_ID_1="${saved_short_id_1}"
  SB_SHORT_ID_2="${saved_short_id_2}"
  SB_VLESS_RATE_LIMIT_UP_MBPS="${saved_rate_limit_up}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${saved_rate_limit_down}"
  SB_VLESS_ALPN_MODE="${saved_alpn_mode}"
  SB_VLESS_TCP_FAST_OPEN="${saved_tcp_fast_open}"
}

detect_default_network_interface() {
  local iface

  if ! command -v ip >/dev/null 2>&1; then
    return 1
  fi

  iface=$(ip route show default 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "dev" && (i + 1) <= NF) {
          print $(i + 1)
          exit
        }
      }
    }
  ')
  if [[ -z "${iface}" ]]; then
    iface=$(ip -6 route show default 2>/dev/null | awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "dev" && (i + 1) <= NF) {
            print $(i + 1)
            exit
          }
        }
      }
    ')
  fi
  [[ -n "${iface}" ]] || return 1
  printf '%s\n' "${iface}"
}

vless_reality_qos_hook_for_direction() {
  local direction=$1

  case "${direction}" in
    up) printf 'ingress' ;;
    down) printf 'egress' ;;
    *) return 1 ;;
  esac
}

clear_vless_reality_qos_rules() {
  local iface direction protocol pref port rate hook

  [[ -f "${SB_REALITY_QOS_FILTER_STATE_FILE}" ]] || return 0

  while IFS='|' read -r iface direction protocol pref port rate; do
    [[ -z "${iface}" || -z "${direction}" || -z "${protocol}" || -z "${pref}" ]] && continue
    hook=$(vless_reality_qos_hook_for_direction "${direction}") || continue
    tc filter del dev "${iface}" "${hook}" pref "${pref}" protocol "${protocol}" >/dev/null 2>&1 || true
  done < "${SB_REALITY_QOS_FILTER_STATE_FILE}"

  rm -f "${SB_REALITY_QOS_FILTER_STATE_FILE}"
}

ensure_vless_reality_qos_clsact() {
  local iface=$1

  if tc qdisc show dev "${iface}" 2>/dev/null | grep -qw 'clsact'; then
    return 0
  fi

  if ! tc qdisc add dev "${iface}" clsact >/dev/null 2>&1; then
    log_warn "REALITY 限速规则未应用：无法在网卡 ${iface} 上创建 clsact qdisc。"
    return 1
  fi
}

apply_vless_reality_qos_filter() {
  local iface=$1 direction=$2 port=$3 rate=$4 protocol=$5 pref=$6 state_file=$7
  local quiet=${8:-n}
  local hook port_match

  hook=$(vless_reality_qos_hook_for_direction "${direction}") || return 1
  case "${direction}" in
    up) port_match="dst_port" ;;
    down) port_match="src_port" ;;
    *) return 1 ;;
  esac

  if tc filter add dev "${iface}" "${hook}" protocol "${protocol}" pref "${pref}" \
    flower ip_proto tcp "${port_match}" "${port}" \
    action police rate "${rate}mbit" burst "${SB_REALITY_QOS_BURST}" conform-exceed drop >/dev/null 2>&1; then
    printf '%s|%s|%s|%s|%s|%s\n' "${iface}" "${direction}" "${protocol}" "${pref}" "${port}" "${rate}" >> "${state_file}"
    return 0
  fi

  if [[ "${quiet}" != "y" ]]; then
    log_warn "REALITY 限速规则应用失败：${iface} ${direction} ${protocol} port ${port} rate ${rate}Mbps。"
  fi
  return 1
}

apply_vless_reality_qos_filter_with_retry() {
  local iface=$1 direction=$2 port=$3 rate=$4 protocol=$5 start_pref=$6 state_file=$7
  local pref attempt max_attempts

  pref="${start_pref}"
  max_attempts=100
  for ((attempt = 0; attempt < max_attempts; attempt++)); do
    if apply_vless_reality_qos_filter "${iface}" "${direction}" "${port}" "${rate}" "${protocol}" "${pref}" "${state_file}" "y"; then
      printf '%s\n' "${pref}"
      return 0
    fi
    pref=$((pref + 1))
  done

  log_warn "REALITY 限速规则应用失败：${iface} ${direction} ${protocol} port ${port} rate ${rate}Mbps，已重试 ${max_attempts} 个 pref。"
  return 1
}

apply_vless_reality_qos_plan() {
  local plan=$1 iface tmp_state line port direction up down protocol pref used_pref failures

  clear_vless_reality_qos_rules

  [[ -n "${plan}" ]] || return 0

  iface=$(detect_default_network_interface) || {
    log_warn "REALITY 限速规则未应用：未能识别默认出口网卡。"
    return 0
  }

  ensure_vless_reality_qos_clsact "${iface}" || return 0

  mkdir -p "$(dirname "${SB_REALITY_QOS_FILTER_STATE_FILE}")"
  tmp_state=$(storage_mktemp)
  pref="${SB_REALITY_QOS_FILTER_PREF_START}"
  failures=0

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS='|' read -r port direction up down <<< "${line}"

    if [[ "${direction}" == "up" || "${direction}" == "both" ]]; then
      for protocol in ip ipv6; do
        if used_pref=$(apply_vless_reality_qos_filter_with_retry "${iface}" "up" "${port}" "${up}" "${protocol}" "${pref}" "${tmp_state}"); then
          pref=$((used_pref + 1))
        else
          pref=$((pref + 100))
          failures=$((failures + 1))
        fi
      done
    fi

    if [[ "${direction}" == "down" || "${direction}" == "both" ]]; then
      for protocol in ip ipv6; do
        if used_pref=$(apply_vless_reality_qos_filter_with_retry "${iface}" "down" "${port}" "${down}" "${protocol}" "${pref}" "${tmp_state}"); then
          pref=$((used_pref + 1))
        else
          pref=$((pref + 100))
          failures=$((failures + 1))
        fi
      done
    fi
  done <<< "${plan}"

  if [[ -s "${tmp_state}" ]]; then
    mv "${tmp_state}" "${SB_REALITY_QOS_FILTER_STATE_FILE}"
  else
    rm -f "${tmp_state}"
  fi

  if (( failures > 0 )); then
    log_warn "REALITY 限速规则部分应用失败，请确认系统 iproute2/tc 支持 flower police。"
  else
    log_success "REALITY 端口限速规则已应用。"
  fi
}

refresh_vless_reality_qos_rules() {
  local plan
  plan=$(build_vless_reality_qos_plan)

  if [[ -z "${plan}" ]]; then
    if command -v tc >/dev/null 2>&1; then
      clear_vless_reality_qos_rules
    fi
    log_info "REALITY 未配置限速，跳过 QoS 规则。"
    return 0
  fi

  if ! command -v tc >/dev/null 2>&1; then
    log_warn "未检测到 tc，REALITY 限速规则未应用。"
    return 0
  fi

  apply_vless_reality_qos_plan "${plan}"
}

append_vless_reality_instance_id() {
  local instance_id=$1 ids=()
  local existing

  while IFS= read -r existing; do
    [[ -n "${existing}" ]] && ids+=("${existing}")
  done < <(list_vless_reality_instance_ids)

  if ! protocol_array_contains "${instance_id}" "${ids[@]}"; then
    ids+=("${instance_id}")
  fi

  VLESS_REALITY_INSTANCE_IDS=$(IFS=,; printf '%s' "${ids[*]}")
}

prompt_vless_reality_instance_selection() {
  local instances=() instance_id index choice rate_summary
  mapfile -t instances < <(list_vless_reality_instance_ids)
  if [[ ${#instances[@]} -eq 0 ]]; then
    log_error "当前未检测到 REALITY 实例。"
  fi

  echo -e "\n${BLUE}--- REALITY 实例 ---${NC}"
  index=1
  for instance_id in "${instances[@]}"; do
    load_vless_reality_instance_state "${instance_id}" || continue
    rate_summary=$(vless_reality_rate_limit_summary "${SB_VLESS_RATE_LIMIT_UP_MBPS}" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}")
    echo "${index}. ${SB_NODE_NAME} | ${instance_id} | ${SB_PORT} | ${rate_summary}"
    index=$((index + 1))
  done
  echo "0. 返回"
  choice=$(prompt_choice "请选择 REALITY 实例: " 0 "${#instances[@]}" "")
  [[ "${choice}" == "0" ]] && return 1
  SELECTED_VLESS_INSTANCE_ID="${instances[$((choice - 1))]}"
}

remove_vless_reality_instance_id_from_list() {
  local remove_id=$1 ids=() instance_id
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" || "${instance_id}" == "${remove_id}" ]] && continue
    ids+=("${instance_id}")
  done < <(list_vless_reality_instance_ids)
  VLESS_REALITY_INSTANCE_IDS=$(IFS=,; printf '%s' "${ids[*]}")
}

port_in_configured_protocol_state() {
  local target_port=$1 protocol state_file instance_id port

  validate_port_number "${target_port}" || return 1

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    if [[ "${protocol}" == "vless-reality" ]]; then
      while IFS= read -r instance_id; do
        [[ -z "${instance_id}" ]] && continue
        port=""
        state_file=$(vless_reality_instance_state_file "${instance_id}") || continue
        if [[ -f "${state_file}" ]]; then
          port=$(grep -E '^PORT=' "${state_file}" | tail -n1 | cut -d= -f2- || true)
          port=${port#\'}
          port=${port%\'}
          port=${port#\"}
          port=${port%\"}
          [[ "${port}" == "${target_port}" ]] && return 0
        fi
      done < <(list_vless_reality_instance_ids)
      continue
    fi

    state_file=$(protocol_state_file "${protocol}")
    if [[ -f "${state_file}" ]]; then
      port=$(grep -E '^PORT=' "${state_file}" | tail -n1 | cut -d= -f2- || true)
      port=${port#\'}
      port=${port%\'}
      port=${port#\"}
      port=${port%\"}
      [[ "${port}" == "${target_port}" ]] && return 0
    fi
  done < <(list_installed_protocols)

  return 1
}

vless_reality_inbound_tag_for_instance() {
  local instance_id=$1
  if [[ -n "${SB_VLESS_INBOUND_TAG:-}" ]]; then
    printf '%s' "${SB_VLESS_INBOUND_TAG}"
    return 0
  fi
  if [[ "${instance_id}" == "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" ]]; then
    printf 'vless-in'
  else
    printf 'vless-reality-%s' "${instance_id}"
  fi
}

validate_vless_reality_instance_tags() {
  local instance_id inbound_tag
  local tags=()

  load_vless_reality_protocol_state
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    load_vless_reality_instance_state "${instance_id}" || return 1
    inbound_tag=$(vless_reality_inbound_tag_for_instance "${instance_id}")
    if protocol_array_contains "${inbound_tag}" "${tags[@]}"; then
      return 1
    fi
    tags+=("${inbound_tag}")
  done < <(list_vless_reality_instance_ids)
}

vless_reality_outbound_policy_from_config() {
  local inbound_tag=$1
  local config_file=${2:-${SINGBOX_CONFIG_FILE}}
  local route_count outbound

  route_count=$(jq -r --arg tag "${inbound_tag}" '[.route.rules[]? | select(.inbound == $tag and .action == "route")] | length' "${config_file}") || return 1
  if [[ "${route_count}" == "0" ]]; then
    printf 'default'
    return 0
  fi
  [[ "${route_count}" == "1" ]] || return 1
  outbound=$(jq -r --arg tag "${inbound_tag}" 'first(.route.rules[]? | select(.inbound == $tag and .action == "route") | .outbound) // ""' "${config_file}") || return 1
  case "${outbound}" in
    direct) printf 'direct' ;;
    warp|warp-ep) printf 'warp' ;;
    *) return 1 ;;
  esac
}
