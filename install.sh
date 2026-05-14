#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 2026051402
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="2026051402"
readonly SB_SUPPORT_MAX_VERSION="1.13.11"
readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
readonly SB_PROJECT_DIR="/root/sing-box-vps"
readonly SBV_LOG_FILE="${SB_PROJECT_DIR}/sbv.log"
readonly SB_KEY_FILE="${SB_PROJECT_DIR}/reality.key"
readonly SB_WARP_KEY_FILE="${SB_PROJECT_DIR}/warp.key"
readonly SB_WARP_ROUTE_SETTINGS_FILE="${SB_PROJECT_DIR}/warp-routing.env"
readonly SB_WARP_DOMAINS_FILE="${SB_PROJECT_DIR}/warp-domains.txt"
readonly SB_WARP_REMOTE_RULESETS_FILE="${SB_PROJECT_DIR}/warp-remote-rule-sets.txt"
readonly SB_WARP_LOCAL_RULESET_DIR="${SB_PROJECT_DIR}/rule-set/warp"
readonly SB_STACK_STATE_FILE="${SB_PROJECT_DIR}/stack-mode.env"
readonly SB_MEDIA_CHECK_DIR="${SB_PROJECT_DIR}/media-check"
readonly SB_MEDIA_CHECK_SCRIPT="${SB_MEDIA_CHECK_DIR}/region_restriction_check.sh"
readonly SB_PROTOCOL_STATE_DIR="${SB_PROJECT_DIR}/protocols"
readonly SB_PROTOCOL_INDEX_FILE="${SB_PROTOCOL_STATE_DIR}/index.env"
readonly SB_ACME_DATA_DIR="${SB_PROJECT_DIR}/acme"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
readonly SBV_BIN_PATH="/usr/local/bin/sbv"
readonly SINGBOX_CONFIG_DIR="${SB_PROJECT_DIR}"
readonly SINGBOX_CONFIG_FILE="${SB_PROJECT_DIR}/config.json"
readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"
readonly WARP_AI_ROUTE_DOMAINS_JSON='["gemini.google.com","aistudio.google.com","generativelanguage.googleapis.com","copilot.microsoft.com"]'
readonly WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON='["openai.com","chatgpt.com","oaistatic.com","oaiusercontent.com","anthropic.com","claude.ai","perplexity.ai","x.ai","cursor.com","cursor.sh","google.com","googleapis.com","gstatic.com","googleusercontent.com","gvt1.com","recaptcha.net"]'
readonly WARP_STREAM_ROUTE_DOMAINS_JSON='[]'
readonly WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON='["netflix.com","nflxvideo.net","nflximg.net","nflxext.com","nflxso.net","disneyplus.com","disney-plus.net","dssott.com","bamgrid.com","hulu.com","huluim.com","hulustream.com","max.com","primevideo.com","amazonvideo.com","media-amazon.com"]'
readonly WARP_RECOMMENDED_RULESETS=(
  "openai|https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/sing/geo/geosite/openai.srs|1d"
  "google-gemini|https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/sing/geo/geosite/google-gemini.srs|1d"
  "google|https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/sing/geo/geosite/google.srs|1d"
  "googlefcm|https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/sing/geo/geosite/googlefcm.srs|1d"
  "google-ip|https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/refs/heads/sing/geo/geoip/google.srs|1d"
)
readonly MEDIA_CHECK_BACKEND_NAME="RegionRestrictionCheck"
readonly MEDIA_CHECK_BACKEND_AUTHOR="1-stream"
readonly MEDIA_CHECK_BACKEND_REPO_URL="https://github.com/1-stream/RegionRestrictionCheck"
readonly MEDIA_CHECK_BACKEND_SCRIPT_URL="https://raw.githubusercontent.com/1-stream/RegionRestrictionCheck/main/check.sh"
readonly SB_HIGH_PORT_MIN="60000"
readonly SB_HIGH_PORT_MAX="65535"
readonly SB_REALITY_SNI_FALLBACK="www.apple.com"
SB_REALITY_SNI_CANDIDATES=(
  "www.apple.com"
  "www.microsoft.com"
  "www.cloudflare.com"
  "www.amazon.com"
  "www.bing.com"
  "www.github.com"
  "www.ubuntu.com"
  "www.debian.org"
)

# --- Global Variables ---
SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
SB_PROTOCOL="vless+reality"
SB_NODE_NAME="$(hostname)+vless"
SB_PORT="443"
SB_UUID=""
SB_PUBLIC_KEY=""
SB_PRIVATE_KEY=""
SB_SHORT_ID_1=""
SB_SHORT_ID_2=""
SB_SNI="${SB_REALITY_SNI_FALLBACK}"
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
SB_ANYTLS_USER_NAME=""
SB_ANYTLS_TLS_MODE="acme"
SB_ANYTLS_ACME_MODE="http"
SB_ANYTLS_ACME_EMAIL=""
SB_ANYTLS_ACME_DOMAIN=""
SB_ANYTLS_DNS_PROVIDER="cloudflare"
SB_ANYTLS_CF_API_TOKEN=""
SB_ANYTLS_CERT_PATH=""
SB_ANYTLS_KEY_PATH=""
SB_ADVANCED_ROUTE="y"
SB_ENABLE_WARP="n"
SB_WARP_ROUTE_MODE="selective"
SB_INBOUND_STACK_MODE=""
SB_OUTBOUND_STACK_MODE=""
SB_WARP_CUSTOM_DOMAINS_JSON='[]'
SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
SB_WARP_LOCAL_RULE_SETS_JSON='[]'
SB_WARP_REMOTE_RULE_SETS_JSON='[]'
SB_WARP_RULE_SET_TAGS_JSON='[]'
SUBMAN_API_URL=""
SUBMAN_API_TOKEN=""
SUBMAN_NODE_PREFIX=""

# --- Common Utilities ---
warp_client_id_to_reserved_json() {
  local client_id decoded_bytes reserved_json
  client_id=$(trim_whitespace "${1:-}")

  if [[ -z "${client_id}" ]]; then
    printf '[]'
    return 0
  fi

  if ! decoded_bytes=$(printf '%s' "${client_id}" | base64 -d 2>/dev/null | od -An -t u1 -v 2>/dev/null); then
    log_error "Warp client_id 解码失败，请尝试重新注册 Warp。"
  fi

  reserved_json=$(printf '%s\n' "${decoded_bytes}" | tr -s '[:space:]' '\n' | sed '/^$/d' | jq -Rsc \
    'split("\n") | map(select(length > 0) | tonumber)')

  if ! jq -e 'length == 3' >/dev/null 2>&1 <<< "${reserved_json}"; then
    log_error "Warp client_id 长度异常，请尝试重新注册 Warp。"
  fi

  printf '%s' "${reserved_json}"
}

# Register Cloudflare Warp account
register_warp() {
  if [[ -f "${SB_WARP_KEY_FILE}" ]]; then
    if grep -q '^WARP_CLIENT_ID=' "${SB_WARP_KEY_FILE}"; then
      log_info "发现现有 Warp 账户信息，正在加载..."
      return 0
    fi

    log_warn "发现旧版 Warp 账户信息缺少 client_id，正在自动重新注册..."
    rm -f "${SB_WARP_KEY_FILE}"
  fi

  log_info "正在注册 Cloudflare Warp 免费账户..."
  local keypair priv_key pub_key
  keypair=$(run_singbox_generate_command "wg-keypair" "WireGuard 密钥") || exit 1
  priv_key=$(extract_generated_key_value "${keypair}" "private")
  pub_key=$(extract_generated_key_value "${keypair}" "public")
  
  if [[ -z "${priv_key}" || -z "${pub_key}" || ${#priv_key} -lt 40 ]]; then
    log_info "无法从 sing-box 提取合法密钥。原始输出: ${keypair}" >> "${SBV_LOG_FILE}"
    log_error "WireGuard 密钥生成失败（格式非法），请查看 ${SBV_LOG_FILE}"
  fi

  local install_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  local tos_date=$(date -u +%FT%T.000Z)
  
  local url="https://api.cloudflareclient.com/v0a2445/reg"
  local payload="{\"key\":\"${pub_key}\",\"install_id\":\"${install_id}\",\"fcm_token\":\"\",\"referrer\":\"\",\"warp_enabled\":false,\"tos\":\"${tos_date}\",\"type\":\"Linux\",\"locale\":\"en_US\"}"
  
  log_info "Warp 注册请求 URL: ${url}"
  log_info "Warp 注册请求 Data (已脱敏): {\"install_id\":\"${install_id}\", ...}" >> "${SBV_LOG_FILE}"

  local response=$(curl -sX POST "${url}" \
    -H "User-Agent: okhttp/4.12.0" \
    -H "Content-Type: application/json" \
    -d "${payload}")

  log_info "Warp 注册原始响应: ${response}" >> "${SBV_LOG_FILE}"

  if [[ -z "${response}" ]]; then
    log_error "Cloudflare API 无响应，请查看 ${SBV_LOG_FILE}"
  fi

  # Check success by existence of "id" field
  local warp_id=$(echo "${response}" | jq -r '.id // empty')
  if [[ -z "${warp_id}" || "${warp_id}" == "null" ]]; then
    local err_msg=$(echo "${response}" | jq -r '.errors[0].message // "未知错误"')
    log_warn "收到非预期响应，详情请查看日志: ${SBV_LOG_FILE}"
    log_error "Warp 注册失败: ${err_msg}"
  fi

  local warp_token warp_v4 warp_v6 warp_client_id
  warp_token=$(echo "${response}" | jq -r '.token')
  warp_v4=$(echo "${response}" | jq -r '.config.interface.addresses.v4')
  warp_v6=$(echo "${response}" | jq -r '.config.interface.addresses.v6')
  warp_client_id=$(echo "${response}" | jq -r '.config.client_id // empty')

  if [[ -z "${warp_client_id}" || "${warp_client_id}" == "null" ]]; then
    log_error "Warp 注册响应缺少 client_id，请查看 ${SBV_LOG_FILE}"
  fi

  cat > "${SB_WARP_KEY_FILE}" <<EOF
WARP_ID=${warp_id}
WARP_TOKEN=${warp_token}
WARP_PRIV_KEY=${priv_key}
WARP_PUB_KEY=${pub_key}
WARP_V4=${warp_v4}
WARP_V6=${warp_v6}
WARP_CLIENT_ID=${warp_client_id}
EOF
  log_success "Warp 账户注册成功。"
}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { 
  echo -e "${BLUE}[INFO]${NC} $1"
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "${SBV_LOG_FILE}"
}
log_success() { 
  echo -e "${GREEN}[SUCCESS]${NC} $1"
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "${SBV_LOG_FILE}"
}
log_warn() { 
  echo -e "${YELLOW}[WARN]${NC} $1"
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "${SBV_LOG_FILE}"
}
log_error() { 
  echo -e "${RED}[ERROR]${NC} $1"
  mkdir -p "${SB_PROJECT_DIR}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "${SBV_LOG_FILE}"
  exit 1
}

print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

trim_whitespace() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

normalize_singbox_version_input() {
  local input_version
  input_version=$(trim_whitespace "${1:-}")

  if [[ -z "${input_version}" ]]; then
    printf '%s' "${SB_SUPPORT_MAX_VERSION}"
    return 0
  fi

  if [[ "${input_version}" == "latest" ]]; then
    printf '%s' "${input_version}"
    return 0
  fi

  input_version="${input_version#v}"
  if [[ "${input_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${input_version}"
    return 0
  fi

  return 1
}

extract_generated_key_value() {
  local output=$1
  local key_kind=$2
  local key_label

  if [[ "${key_kind}" == "private" ]]; then
    key_label='[Pp]rivate'
  else
    key_label='[Pp]ublic'
  fi

  printf '%s\n' "${output}" | sed -nE \
    "s/^[[:space:]]*${key_label}([[:space:]]+|)[Kk]ey[[:space:]]*:?[[:space:]]*([^[:space:]]+)[[:space:]]*$/\\2/p" \
    | head -n 1
}

run_singbox_generate_command() {
  local subcommand=$1
  local label=$2
  local output

  if ! output=$("${SINGBOX_BIN_PATH}" generate "${subcommand}" 2>&1); then
    log_info "${label}生成原始输出: ${output}" >> "${SBV_LOG_FILE}"
    log_error "${label}生成失败，请查看 ${SBV_LOG_FILE}" >&2
  fi

  printf '%s' "${output}"
}

validate_warp_route_mode() {
  case "$1" in
    all|selective) return 0 ;;
    *) return 1 ;;
  esac
}

validate_inbound_stack_mode() {
  case "$1" in
    ipv4_only|ipv6_only|dual_stack) return 0 ;;
    *) return 1 ;;
  esac
}

validate_outbound_stack_mode() {
  case "$1" in
    ipv4_only|ipv6_only|prefer_ipv4|prefer_ipv6) return 0 ;;
    *) return 1 ;;
  esac
}

inbound_stack_mode_display_name() {
  case "$1" in
    ipv4_only) printf '仅 IPv4' ;;
    ipv6_only) printf '仅 IPv6' ;;
    dual_stack) printf '双栈' ;;
    *) printf '%s' "$1" ;;
  esac
}

outbound_stack_mode_display_name() {
  case "$1" in
    ipv4_only) printf '仅 IPv4' ;;
    ipv6_only) printf '仅 IPv6' ;;
    prefer_ipv4) printf 'IPv4 优先' ;;
    prefer_ipv6) printf 'IPv6 优先' ;;
    *) printf '%s' "$1" ;;
  esac
}

host_ip_stack_display_name() {
  case "$1" in
    dual) printf 'IPv4 / IPv6 双栈' ;;
    ipv6) printf '仅 IPv6' ;;
    *) printf '仅 IPv4' ;;
  esac
}

detect_host_ip_stack() {
  local has_ipv4="n"
  local has_ipv6="n"

  if command -v ip &>/dev/null; then
    if ip -o -4 addr show scope global 2>/dev/null | grep -q .; then
      has_ipv4="y"
    fi

    if ip -o -6 addr show scope global 2>/dev/null | grep -q .; then
      has_ipv6="y"
    fi
  fi

  if [[ "${has_ipv4}" == "y" && "${has_ipv6}" == "y" ]]; then
    printf 'dual'
  elif [[ "${has_ipv6}" == "y" ]]; then
    printf 'ipv6'
  else
    printf 'ipv4'
  fi
}

port_is_in_use() {
  local port=$1

  ss -H -tunlp 2>/dev/null | grep -Eq ":${port}[[:space:]]"
}

pick_random_high_port() {
  local port attempt

  for attempt in $(seq 1 128); do
    port=$((RANDOM % (SB_HIGH_PORT_MAX - SB_HIGH_PORT_MIN + 1) + SB_HIGH_PORT_MIN))
    if ! port_is_in_use "${port}"; then
      printf '%s' "${port}"
      return 0
    fi
  done

  for port in $(seq "${SB_HIGH_PORT_MIN}" "${SB_HIGH_PORT_MAX}"); do
    if ! port_is_in_use "${port}"; then
      printf '%s' "${port}"
      return 0
    fi
  done

  log_error "未找到 ${SB_HIGH_PORT_MIN}-${SB_HIGH_PORT_MAX} 范围内的可用端口。"
}

default_inbound_stack_mode() {
  case "$1" in
    dual) printf 'dual_stack' ;;
    ipv6) printf 'ipv6_only' ;;
    *) printf 'ipv4_only' ;;
  esac
}

default_outbound_stack_mode() {
  printf 'prefer_ipv4'
}

host_supports_inbound_stack_mode() {
  local host_stack=$1
  local inbound_stack_mode=$2

  case "${host_stack}:${inbound_stack_mode}" in
    dual:ipv4_only|dual:ipv6_only|dual:dual_stack|ipv4:ipv4_only|ipv6:ipv6_only) return 0 ;;
    *) return 1 ;;
  esac
}

infer_inbound_stack_mode_from_config() {
  local config_file=$1
  local host_stack=$2
  local listen_address

  listen_address=$(jq -r '.inbounds[0].listen // empty' "${config_file}" 2>/dev/null || true)
  case "${listen_address}" in
    0.0.0.0) printf 'ipv4_only' ;;
    ::)
      if [[ "${host_stack}" == "ipv6" ]]; then
        printf 'ipv6_only'
      else
        printf 'dual_stack'
      fi
      ;;
    *)
      default_inbound_stack_mode "${host_stack}"
      ;;
  esac
}

infer_outbound_stack_mode_from_config() {
  local config_file=$1
  local outbound_stack_mode

  outbound_stack_mode=$(jq -r '.dns.strategy // first(.outbounds[]? | select(.tag == "direct") | .domain_resolver.strategy) // empty' "${config_file}" 2>/dev/null || true)
  if validate_outbound_stack_mode "${outbound_stack_mode}"; then
    printf '%s' "${outbound_stack_mode}"
    return 0
  fi

  default_outbound_stack_mode
}

save_stack_mode_state() {
  mkdir -p "${SB_PROJECT_DIR}"
  cat > "${SB_STACK_STATE_FILE}" <<EOF
STACK_STATE_VERSION=1
INBOUND_STACK_MODE=${SB_INBOUND_STACK_MODE}
OUTBOUND_STACK_MODE=${SB_OUTBOUND_STACK_MODE}
EOF
}

load_stack_mode_state() {
  local host_stack saved_inbound saved_outbound

  host_stack=$(detect_host_ip_stack)
  SB_INBOUND_STACK_MODE=$(default_inbound_stack_mode "${host_stack}")
  SB_OUTBOUND_STACK_MODE=$(default_outbound_stack_mode)

  if [[ -f "${SB_STACK_STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SB_STACK_STATE_FILE}"
    saved_inbound=${INBOUND_STACK_MODE:-}
    saved_outbound=${OUTBOUND_STACK_MODE:-}

    if validate_inbound_stack_mode "${saved_inbound}" && host_supports_inbound_stack_mode "${host_stack}" "${saved_inbound}"; then
      SB_INBOUND_STACK_MODE="${saved_inbound}"
    fi

    if validate_outbound_stack_mode "${saved_outbound}"; then
      SB_OUTBOUND_STACK_MODE="${saved_outbound}"
    fi
    return 0
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    SB_INBOUND_STACK_MODE=$(infer_inbound_stack_mode_from_config "${SINGBOX_CONFIG_FILE}" "${host_stack}")
    SB_OUTBOUND_STACK_MODE=$(infer_outbound_stack_mode_from_config "${SINGBOX_CONFIG_FILE}")
  fi
}

ensure_stack_mode_state_loaded() {
  local inbound_valid="n"
  local outbound_valid="n"
  local current_inbound=${SB_INBOUND_STACK_MODE:-}
  local current_outbound=${SB_OUTBOUND_STACK_MODE:-}
  local host_stack

  host_stack=$(detect_host_ip_stack)

  if validate_inbound_stack_mode "${current_inbound}" && host_supports_inbound_stack_mode "${host_stack}" "${current_inbound}"; then
    inbound_valid="y"
  fi

  if validate_outbound_stack_mode "${current_outbound}"; then
    outbound_valid="y"
  fi

  if [[ "${inbound_valid}" == "y" && "${outbound_valid}" == "y" ]]; then
    return 0
  fi

  load_stack_mode_state

  if [[ "${inbound_valid}" == "y" ]]; then
    SB_INBOUND_STACK_MODE="${current_inbound}"
  fi

  if [[ "${outbound_valid}" == "y" ]]; then
    SB_OUTBOUND_STACK_MODE="${current_outbound}"
  fi
}

validate_protocol() {
  case "$1" in
    vless+reality|mixed|hy2|anytls) return 0 ;;
    *) return 1 ;;
  esac
}

protocol_display_name() {
  case "$1" in
    vless+reality) printf 'VLESS + REALITY' ;;
    mixed) printf 'Mixed (HTTP/HTTPS/SOCKS)' ;;
    hy2) printf 'Hysteria2' ;;
    anytls) printf 'AnyTLS' ;;
    *) printf '%s' "$1" ;;
  esac
}

default_node_name_for_protocol() {
  local protocol suffix

  protocol=${1:-vless+reality}
  case "${protocol}" in
    vless+reality) suffix="vless" ;;
    hy2) suffix="hys" ;;
    anytls) suffix="anytls" ;;
    mixed) suffix="mixed" ;;
    *) suffix="${protocol}" ;;
  esac

  printf '%s+%s' "$(hostname)" "${suffix}"
}

protocol_inbound_tag() {
  case "$1" in
    mixed) printf 'mixed-in' ;;
    hy2) printf 'hy2-in' ;;
    anytls) printf 'anytls-in' ;;
    *) printf 'vless-in' ;;
  esac
}

normalize_protocol_id() {
  case "$1" in
    vless|vless+reality|vless-reality) printf 'vless-reality' ;;
    mixed) printf 'mixed' ;;
    hy2|hysteria2) printf 'hy2' ;;
    anytls) printf 'anytls' ;;
    *) return 1 ;;
  esac
}

state_protocol_to_runtime() {
  case "$1" in
    vless-reality) printf 'vless+reality' ;;
    mixed) printf 'mixed' ;;
    hy2) printf 'hy2' ;;
    anytls) printf 'anytls' ;;
    *) return 1 ;;
  esac
}

runtime_protocol_to_state() {
  normalize_protocol_id "$1"
}

protocol_state_file() {
  local protocol
  protocol=$(normalize_protocol_id "$1")
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

subman_config_file_path() {
  printf '%s/subman.env' "${SB_PROJECT_DIR}"
}

normalize_subman_api_url() {
  local url
  url=$(trim_whitespace "${1:-}")
  while [[ "${url}" == */ ]]; do
    url=${url%/}
  done
  printf '%s' "${url}"
}

load_subman_config() {
  local config_file
  config_file=$(subman_config_file_path)

  SUBMAN_API_URL=""
  SUBMAN_API_TOKEN=""
  SUBMAN_NODE_PREFIX=""

  [[ -f "${config_file}" ]] || return 0

  # shellcheck disable=SC1090
  source "${config_file}"
  SUBMAN_API_URL=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  SUBMAN_API_TOKEN=${SUBMAN_API_TOKEN:-}
  SUBMAN_NODE_PREFIX=$(trim_whitespace "${SUBMAN_NODE_PREFIX:-}")
}

write_subman_config() {
  local config_file config_dir tmp_file
  config_file=$(subman_config_file_path)
  config_dir=$(dirname "${config_file}")
  mkdir -p "${config_dir}"
  tmp_file=$(mktemp "${config_dir}/.subman.env.tmp.XXXXXX")
  chmod 600 "${tmp_file}"
  {
    write_env_assignment "SUBMAN_API_URL" "${SUBMAN_API_URL}"
    write_env_assignment "SUBMAN_API_TOKEN" "${SUBMAN_API_TOKEN}"
    write_env_assignment "SUBMAN_NODE_PREFIX" "${SUBMAN_NODE_PREFIX}"
  } > "${tmp_file}"
  mv "${tmp_file}" "${config_file}"
  chmod 600 "${config_file}"
}

prompt_subman_config_if_needed() {
  local input_url input_token input_prefix

  load_subman_config

  while [[ -z "${SUBMAN_API_URL}" ]]; do
    read -rp "SubMan API 地址: " input_url
    SUBMAN_API_URL=$(normalize_subman_api_url "${input_url}")
    [[ -z "${SUBMAN_API_URL}" ]] && log_warn "SubMan API 地址不能为空。"
  done

  while [[ -z "${SUBMAN_API_TOKEN}" ]]; do
    read -rp "SubMan API Token: " input_token
    SUBMAN_API_TOKEN=$(trim_whitespace "${input_token}")
    [[ -z "${SUBMAN_API_TOKEN}" ]] && log_warn "SubMan API Token 不能为空。"
  done

  if [[ -z "${SUBMAN_NODE_PREFIX}" ]]; then
    read -rp "SubMan 节点前缀 (默认: $(hostname)): " input_prefix
    SUBMAN_NODE_PREFIX=$(trim_whitespace "${input_prefix}")
    [[ -z "${SUBMAN_NODE_PREFIX}" ]] && SUBMAN_NODE_PREFIX=$(hostname)
  fi

  write_subman_config
}

write_protocol_index() {
  local recorded_version
  recorded_version=$(resolve_protocol_index_singbox_version)
  ensure_protocol_state_dir
  {
    printf 'INSTALLED_PROTOCOLS=%s\n' "$1"
    printf 'PROTOCOL_STATE_VERSION=1\n'
    if [[ -n "${recorded_version}" ]]; then
      printf 'INSTALLED_SINGBOX_VERSION=%s\n' "${recorded_version}"
    fi
  } > "${SB_PROTOCOL_INDEX_FILE}"
}

extract_protocols_from_index() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
  local installed
  installed=$(grep '^INSTALLED_PROTOCOLS=' "${SB_PROTOCOL_INDEX_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  installed=${installed//\"/}
  installed=${installed//\'/}
  installed=${installed//\\,/,}
  printf '%s' "${installed}"
}

extract_recorded_singbox_version_from_index() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0

  local recorded_version
  recorded_version=$(grep '^INSTALLED_SINGBOX_VERSION=' "${SB_PROTOCOL_INDEX_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  recorded_version=${recorded_version//\"/}
  recorded_version=${recorded_version//\'/}
  recorded_version=$(trim_whitespace "${recorded_version}")
  printf '%s' "${recorded_version}"
}

detect_installed_singbox_version() {
  [[ -x "${SINGBOX_BIN_PATH}" ]] || return 0

  local installed_version
  installed_version=$("${SINGBOX_BIN_PATH}" version 2>/dev/null | head -n1 | awk '{print $3}' || true)
  installed_version=$(trim_whitespace "${installed_version}")
  printf '%s' "${installed_version}"
}

resolve_protocol_index_singbox_version() {
  local installed_version recorded_version

  installed_version=$(detect_installed_singbox_version)
  if [[ -n "${installed_version}" ]]; then
    printf '%s' "${installed_version}"
    return 0
  fi

  recorded_version=$(extract_recorded_singbox_version_from_index)
  if [[ -n "${recorded_version}" ]]; then
    printf '%s' "${recorded_version}"
  fi
}

list_indexed_protocols_raw() {
  local installed protocol
  installed=$(extract_protocols_from_index)
  [[ -z "${installed}" ]] && return 0

  IFS=',' read -r -a protocols <<< "${installed}"
  for protocol in "${protocols[@]}"; do
    protocol=$(trim_whitespace "${protocol}")
    [[ -n "${protocol}" ]] && printf '%s\n' "${protocol}"
  done
}

protocol_state_exists() {
  local protocol
  protocol=$(normalize_protocol_id "$1")
  [[ -f "$(protocol_state_file "${protocol}")" ]]
}

reconcile_protocol_index_if_needed() {
  local indexed_protocols=() valid_protocols=()
  local protocol joined_protocols current_protocols

  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0

  mapfile -t indexed_protocols < <(list_indexed_protocols_raw)
  current_protocols=$(extract_protocols_from_index)

  for protocol in "${indexed_protocols[@]}"; do
    protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || true)
    [[ -z "${protocol}" ]] && continue
    if protocol_state_exists "${protocol}"; then
      if ! protocol_array_contains "${protocol}" "${valid_protocols[@]}"; then
        valid_protocols+=("${protocol}")
      fi
    else
      log_warn "协议状态文件缺失，已从索引移除: ${protocol}" >&2
    fi
  done

  if [[ ${#valid_protocols[@]} -eq 0 ]]; then
    if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
      rm -f "${SB_PROTOCOL_INDEX_FILE}"
      migrate_legacy_single_protocol_state_if_needed
    fi
    return 0
  fi

  joined_protocols=$(IFS=,; printf '%s' "${valid_protocols[*]}")
  if [[ "${joined_protocols}" != "${current_protocols}" ]]; then
    write_protocol_index "${joined_protocols}"
  fi
}

list_installed_protocols() {
  reconcile_protocol_index_if_needed
  list_indexed_protocols_raw
}

list_exportable_client_protocols() {
  local protocol

  while IFS= read -r protocol; do
    case "${protocol}" in
      vless-reality|hy2|anytls) printf '%s\n' "${protocol}" ;;
    esac
  done < <(list_installed_protocols)
}

save_vless_reality_state() {
  local state_file
  state_file=$(protocol_state_file "vless-reality")

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "UUID" "${SB_UUID}"
    write_env_assignment "SNI" "${SB_SNI}"
    write_env_assignment "REALITY_PRIVATE_KEY" "${SB_PRIVATE_KEY}"
    write_env_assignment "REALITY_PUBLIC_KEY" "${SB_PUBLIC_KEY}"
    write_env_assignment "SHORT_ID_1" "${SB_SHORT_ID_1}"
    write_env_assignment "SHORT_ID_2" "${SB_SHORT_ID_2}"
  } > "${state_file}"
}

save_mixed_state() {
  local state_file
  state_file=$(protocol_state_file "mixed")

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "AUTH_ENABLED" "${SB_MIXED_AUTH_ENABLED}"
    write_env_assignment "USERNAME" "${SB_MIXED_USERNAME}"
    write_env_assignment "PASSWORD" "${SB_MIXED_PASSWORD}"
  } > "${state_file}"
}

save_hy2_state() {
  local state_file
  state_file=$(protocol_state_file "hy2")

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "DOMAIN" "${SB_HY2_DOMAIN}"
    write_env_assignment "PASSWORD" "${SB_HY2_PASSWORD}"
    write_env_assignment "USER_NAME" "${SB_HY2_USER_NAME}"
    write_env_assignment "UP_MBPS" "${SB_HY2_UP_MBPS}"
    write_env_assignment "DOWN_MBPS" "${SB_HY2_DOWN_MBPS}"
    write_env_assignment "OBFS_ENABLED" "${SB_HY2_OBFS_ENABLED}"
    write_env_assignment "OBFS_TYPE" "${SB_HY2_OBFS_TYPE}"
    write_env_assignment "OBFS_PASSWORD" "${SB_HY2_OBFS_PASSWORD}"
    write_env_assignment "TLS_MODE" "${SB_HY2_TLS_MODE}"
    write_env_assignment "ACME_MODE" "${SB_HY2_ACME_MODE}"
    write_env_assignment "ACME_EMAIL" "${SB_HY2_ACME_EMAIL}"
    write_env_assignment "ACME_DOMAIN" "${SB_HY2_ACME_DOMAIN}"
    write_env_assignment "DNS_PROVIDER" "${SB_HY2_DNS_PROVIDER}"
    write_env_assignment "CF_API_TOKEN" "${SB_HY2_CF_API_TOKEN}"
    write_env_assignment "CERT_PATH" "${SB_HY2_CERT_PATH}"
    write_env_assignment "KEY_PATH" "${SB_HY2_KEY_PATH}"
    write_env_assignment "MASQUERADE" "${SB_HY2_MASQUERADE}"
  } > "${state_file}"
}

save_anytls_state() {
  local state_file
  state_file=$(protocol_state_file "anytls")

  {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "1"
    write_env_assignment "NODE_NAME" "${SB_NODE_NAME}"
    write_env_assignment "PORT" "${SB_PORT}"
    write_env_assignment "DOMAIN" "${SB_ANYTLS_DOMAIN}"
    write_env_assignment "PASSWORD" "${SB_ANYTLS_PASSWORD}"
    write_env_assignment "USER_NAME" "${SB_ANYTLS_USER_NAME}"
    write_env_assignment "TLS_MODE" "${SB_ANYTLS_TLS_MODE}"
    write_env_assignment "ACME_MODE" "${SB_ANYTLS_ACME_MODE}"
    write_env_assignment "ACME_EMAIL" "${SB_ANYTLS_ACME_EMAIL}"
    write_env_assignment "ACME_DOMAIN" "${SB_ANYTLS_ACME_DOMAIN}"
    write_env_assignment "DNS_PROVIDER" "${SB_ANYTLS_DNS_PROVIDER}"
    write_env_assignment "CF_API_TOKEN" "${SB_ANYTLS_CF_API_TOKEN}"
    write_env_assignment "CERT_PATH" "${SB_ANYTLS_CERT_PATH}"
    write_env_assignment "KEY_PATH" "${SB_ANYTLS_KEY_PATH}"
  } > "${state_file}"
}

save_protocol_state() {
  local protocol
  protocol=$(normalize_protocol_id "$1")
  ensure_protocol_state_dir

  case "${protocol}" in
    vless-reality) save_vless_reality_state ;;
    mixed) save_mixed_state ;;
    hy2) save_hy2_state ;;
    anytls) save_anytls_state ;;
    *) log_error "不支持的协议状态保存类型: ${protocol}" ;;
  esac
}

migrate_legacy_single_protocol_state_if_needed() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" || ! -f "${SINGBOX_CONFIG_FILE}" ]] && return 0
  rebuild_protocol_state_from_config
}

prompt_installed_protocol_selection() {
  local protocols=() choice selected_protocol index
  mapfile -t protocols < <(list_installed_protocols)

  if [[ ${#protocols[@]} -eq 0 ]]; then
    log_error "当前未检测到已安装协议。"
  fi

  while true; do
    echo -e "\n${BLUE}--- 已安装协议 ---${NC}"
    for index in "${!protocols[@]}"; do
      selected_protocol=$(state_protocol_to_runtime "${protocols[$index]}")
      echo "$((index + 1)). $(protocol_display_name "${selected_protocol}")"
    done
    echo "0. 返回"
    read -rp "请选择 [0-${#protocols[@]}]: " choice

    if [[ "${choice}" == "0" ]]; then
      return 0
    fi

    if [[ "${choice}" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#protocols[@]} )); then
      SELECTED_PROTOCOL="${protocols[$((choice - 1))]}"
      return 0
    fi

    log_warn "无效选项，请重新选择。"
  done
}

prompt_vless_reality_update() {
  local in_p in_uuid in_sni

  read -rp "新端口 (当前: ${SB_PORT}, 留空保持): " in_p
  if [[ -n "${in_p}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新 UUID (当前: ${SB_UUID}, 留空保持): " in_uuid
  [[ -n "${in_uuid}" ]] && SB_UUID="${in_uuid}"

  read -rp "新 REALITY 域名 (当前: ${SB_SNI}, 留空保持): " in_sni
  [[ -n "${in_sni}" ]] && SB_SNI="${in_sni}"
}

probe_reality_sni_candidate() {
  local domain=$1
  local time_total

  time_total=$(curl -o /dev/null -sS -L \
    --connect-timeout 3 \
    --max-time 6 \
    --retry 0 \
    --write-out '%{time_appconnect}' \
    "https://${domain}/" 2>/dev/null) || return 1

  awk -v value="${time_total}" 'BEGIN {
    if (value <= 0) {
      exit 1
    }
    printf "%d\n", value * 1000
  }'
}

select_reality_sni_candidate() {
  local domain latency best_domain best_latency

  best_domain=""
  best_latency=""

  for domain in "${SB_REALITY_SNI_CANDIDATES[@]}"; do
    if latency=$(probe_reality_sni_candidate "${domain}"); then
      log_info "Reality SNI 探测可用: ${domain} (${latency}ms)" >&2
      if [[ -z "${best_latency}" || "${latency}" -lt "${best_latency}" ]]; then
        best_domain="${domain}"
        best_latency="${latency}"
      fi
    else
      log_warn "Reality SNI 探测失败: ${domain}" >&2
    fi
  done

  if [[ -n "${best_domain}" ]]; then
    printf '%s' "${best_domain}"
    return 0
  fi

  log_warn "所有候选 Reality SNI 探测失败，回退到 ${SB_REALITY_SNI_FALLBACK}。" >&2
  printf '%s' "${SB_REALITY_SNI_FALLBACK}"
}

prompt_reality_sni_install() {
  local choice manual_sni selected_sni

  echo "[VLESS + REALITY] REALITY 域名选择:"
  echo "1. 自动探测推荐 SNI (默认)"
  echo "2. 手动输入"
  read -rp "请选择 [1-2]: " choice
  choice=${choice:-1}

  case "${choice}" in
    2)
      read -rp "[VLESS + REALITY] REALITY 域名 (默认 ${SB_REALITY_SNI_FALLBACK}): " manual_sni
      manual_sni=$(trim_whitespace "${manual_sni:-}")
      SB_SNI=${manual_sni:-$SB_REALITY_SNI_FALLBACK}
      ;;
    *)
      selected_sni=$(select_reality_sni_candidate)
      SB_SNI="${selected_sni}"
      log_success "已选择 Reality SNI: ${SB_SNI}"
      ;;
  esac
}

prompt_mixed_update() {
  local in_p in_auth in_user in_pass

  read -rp "新端口 (当前: ${SB_PORT}, 留空保持): " in_p
  if [[ -n "${in_p}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "是否启用用户名密码认证 [y/n] (当前: ${SB_MIXED_AUTH_ENABLED}, 留空保持): " in_auth
  [[ -n "${in_auth}" ]] && SB_MIXED_AUTH_ENABLED="${in_auth}"

  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    read -rp "新用户名 (当前: ${SB_MIXED_USERNAME}, 留空保持/自动生成): " in_user
    [[ -n "${in_user}" ]] && SB_MIXED_USERNAME="${in_user}"
    read -rp "新密码 (当前: 留空隐藏, 留空保持/自动生成): " in_pass
    [[ -n "${in_pass}" ]] && SB_MIXED_PASSWORD="${in_pass}"
    ensure_mixed_auth_credentials
  else
    log_warn "关闭 Mixed 认证会暴露开放代理，存在明显安全风险。"
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
  fi
}

prompt_hy2_update() {
  local in_p in_domain in_password in_user_name in_up in_down in_obfs in_obfs_password in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path in_masquerade

  read -rp "新端口 (当前: ${SB_PORT}, 留空保持): " in_p
  if [[ -n "${in_p}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新域名 (当前: ${SB_HY2_DOMAIN}, 留空保持): " in_domain
  if [[ -n "${in_domain}" ]]; then
    in_domain=$(trim_whitespace "${in_domain}")
    if validate_tls_domain_points_to_server "Hysteria2" "${in_domain}"; then
      SB_HY2_DOMAIN="${in_domain}"
    else
      log_warn "已保留当前 Hysteria2 域名: ${SB_HY2_DOMAIN}"
    fi
  fi

  read -rp "新认证密码 (当前: 留空隐藏, 留空保持): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"

  read -rp "新用户名标识 (当前: ${SB_HY2_USER_NAME}, 留空保持): " in_user_name
  [[ -n "${in_user_name}" ]] && SB_HY2_USER_NAME="${in_user_name}"

  read -rp "上行带宽 Mbps (当前: ${SB_HY2_UP_MBPS:-未限制}, 留空保持): " in_up
  [[ -n "${in_up}" ]] && SB_HY2_UP_MBPS="${in_up}"

  read -rp "下行带宽 Mbps (当前: ${SB_HY2_DOWN_MBPS:-未限制}, 留空保持): " in_down
  [[ -n "${in_down}" ]] && SB_HY2_DOWN_MBPS="${in_down}"

  read -rp "是否启用 Salamander 混淆 [y/n] (当前: ${SB_HY2_OBFS_ENABLED}, 留空保持): " in_obfs
  if [[ -n "${in_obfs}" ]]; then
    SB_HY2_OBFS_ENABLED="${in_obfs}"
  fi

  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    read -rp "混淆密码 (当前: 留空隐藏, 留空保持): " in_obfs_password
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
    [[ -z "${SB_HY2_OBFS_TYPE}" ]] && SB_HY2_OBFS_TYPE="salamander"
  else
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  read -rp "请选择 [1-2] (当前: ${SB_HY2_TLS_MODE}, 留空保持): " in_tls_mode
  case "${in_tls_mode}" in
    1) SB_HY2_TLS_MODE="acme" ;;
    2) SB_HY2_TLS_MODE="manual" ;;
    "") ;;
    *) log_warn "保留当前 TLS 模式: ${SB_HY2_TLS_MODE}" ;;
  esac

  if [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    read -rp "请选择 [1-2] (当前: ${SB_HY2_ACME_MODE}, 留空保持): " in_acme_mode
    case "${in_acme_mode}" in
      1) SB_HY2_ACME_MODE="http" ;;
      2) SB_HY2_ACME_MODE="dns" ;;
      "") ;;
      *) log_warn "保留当前 ACME 模式: ${SB_HY2_ACME_MODE}" ;;
    esac

    read -rp "ACME 邮箱 (当前: ${SB_HY2_ACME_EMAIL}, 留空保持，用于证书通知): " in_acme_email
    [[ -n "${in_acme_email}" ]] && SB_HY2_ACME_EMAIL="${in_acme_email}"
    read -rp "ACME 域名 (当前: ${SB_HY2_ACME_DOMAIN:-${SB_HY2_DOMAIN}}, 留空保持): " in_acme_domain
    [[ -n "${in_acme_domain}" ]] && SB_HY2_ACME_DOMAIN="${in_acme_domain}"

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token (当前: 留空隐藏, 留空保持): " in_cf_api_token
      [[ -n "${in_cf_api_token}" ]] && SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    else
      SB_HY2_CF_API_TOKEN=""
    fi

    SB_HY2_CERT_PATH=""
    SB_HY2_KEY_PATH=""
  else
    read -rp "证书路径 (当前: ${SB_HY2_CERT_PATH}, 留空保持): " in_cert_path
    [[ -n "${in_cert_path}" ]] && SB_HY2_CERT_PATH="${in_cert_path}"
    read -rp "私钥路径 (当前: ${SB_HY2_KEY_PATH}, 留空保持): " in_key_path
    [[ -n "${in_key_path}" ]] && SB_HY2_KEY_PATH="${in_key_path}"
    SB_HY2_ACME_MODE="http"
    SB_HY2_ACME_EMAIL=""
    SB_HY2_ACME_DOMAIN=""
    SB_HY2_CF_API_TOKEN=""
  fi

  read -rp "伪装地址 (当前: ${SB_HY2_MASQUERADE}, 留空保持): " in_masquerade
  [[ -n "${in_masquerade}" ]] && SB_HY2_MASQUERADE="${in_masquerade}"

  ensure_hy2_materials
}

prompt_anytls_update() {
  local in_p in_domain in_password in_user_name in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path

  read -rp "新端口 (当前: ${SB_PORT}, 留空保持): " in_p
  if [[ -n "${in_p}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新域名 (当前: ${SB_ANYTLS_DOMAIN}, 留空保持): " in_domain
  if [[ -n "${in_domain}" ]]; then
    in_domain=$(trim_whitespace "${in_domain}")
    if validate_tls_domain_points_to_server "AnyTLS" "${in_domain}"; then
      SB_ANYTLS_DOMAIN="${in_domain}"
    else
      log_warn "已保留当前 AnyTLS 域名: ${SB_ANYTLS_DOMAIN}"
    fi
  fi

  read -rp "新认证密码 (当前: 留空隐藏, 留空保持): " in_password
  [[ -n "${in_password}" ]] && SB_ANYTLS_PASSWORD="${in_password}"

  read -rp "新用户名标识 (当前: ${SB_ANYTLS_USER_NAME}, 留空保持): " in_user_name
  [[ -n "${in_user_name}" ]] && SB_ANYTLS_USER_NAME="${in_user_name}"

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  read -rp "请选择 [1-2] (当前: ${SB_ANYTLS_TLS_MODE}, 留空保持): " in_tls_mode
  case "${in_tls_mode}" in
    1) SB_ANYTLS_TLS_MODE="acme" ;;
    2) SB_ANYTLS_TLS_MODE="manual" ;;
    "") ;;
    *) log_warn "保留当前 TLS 模式: ${SB_ANYTLS_TLS_MODE}" ;;
  esac

  if [[ "${SB_ANYTLS_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    read -rp "请选择 [1-2] (当前: ${SB_ANYTLS_ACME_MODE}, 留空保持): " in_acme_mode
    case "${in_acme_mode}" in
      1) SB_ANYTLS_ACME_MODE="http" ;;
      2) SB_ANYTLS_ACME_MODE="dns" ;;
      "") ;;
      *) log_warn "保留当前 ACME 模式: ${SB_ANYTLS_ACME_MODE}" ;;
    esac

    read -rp "ACME 邮箱 (当前: ${SB_ANYTLS_ACME_EMAIL}, 留空保持，用于证书通知): " in_acme_email
    [[ -n "${in_acme_email}" ]] && SB_ANYTLS_ACME_EMAIL="${in_acme_email}"
    read -rp "ACME 域名 (当前: ${SB_ANYTLS_ACME_DOMAIN:-${SB_ANYTLS_DOMAIN}}, 留空保持): " in_acme_domain
    [[ -n "${in_acme_domain}" ]] && SB_ANYTLS_ACME_DOMAIN="${in_acme_domain}"

    if [[ "${SB_ANYTLS_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token (当前: 留空隐藏, 留空保持): " in_cf_api_token
      [[ -n "${in_cf_api_token}" ]] && SB_ANYTLS_CF_API_TOKEN="${in_cf_api_token}"
    else
      SB_ANYTLS_CF_API_TOKEN=""
    fi

    SB_ANYTLS_CERT_PATH=""
    SB_ANYTLS_KEY_PATH=""
  else
    read -rp "证书路径 (当前: ${SB_ANYTLS_CERT_PATH}, 留空保持): " in_cert_path
    [[ -n "${in_cert_path}" ]] && SB_ANYTLS_CERT_PATH="${in_cert_path}"
    read -rp "私钥路径 (当前: ${SB_ANYTLS_KEY_PATH}, 留空保持): " in_key_path
    [[ -n "${in_key_path}" ]] && SB_ANYTLS_KEY_PATH="${in_key_path}"
    SB_ANYTLS_ACME_MODE="http"
    SB_ANYTLS_ACME_EMAIL=""
    SB_ANYTLS_ACME_DOMAIN=""
    SB_ANYTLS_CF_API_TOKEN=""
  fi

  ensure_anytls_materials
}

prompt_protocol_update_fields() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) prompt_vless_reality_update ;;
    mixed) prompt_mixed_update ;;
    hy2) prompt_hy2_update ;;
    anytls) prompt_anytls_update ;;
    *) log_error "不支持的协议修改类型: ${protocol}" ;;
  esac
}

open_all_protocol_ports() {
  local protocol current_protocol_state
  current_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    load_protocol_state "${protocol}"
    open_firewall_port "${SB_PORT}"
  done < <(list_effective_protocols)

  if [[ -n "${current_protocol_state}" ]]; then
    load_protocol_state "${current_protocol_state}"
  fi
}

protocol_array_contains() {
  local target=$1
  shift || true

  local item
  for item in "$@"; do
    [[ "${item}" == "${target}" ]] && return 0
  done

  return 1
}

protocol_option_to_id() {
  case "$1" in
    1) printf 'vless-reality' ;;
    2) printf 'mixed' ;;
    3) printf 'hy2' ;;
    4) printf 'anytls' ;;
    *) return 1 ;;
  esac
}

prompt_protocol_install_selection() {
  local install_mode=${1:-additional}
  local installed_protocols=() selected_protocols=()
  local choice raw_choice protocol index

  SELECTED_PROTOCOLS_CSV=""

  if [[ "${install_mode}" != "fresh" ]]; then
    mapfile -t installed_protocols < <(list_installed_protocols)
  fi

  echo -e "\n${BLUE}--- 协议安装 ---${NC}"
  if [[ ${#installed_protocols[@]} -gt 0 ]]; then
    echo "当前已安装协议:"
    for protocol in "${installed_protocols[@]}"; do
      echo "- $(protocol_display_name "$(state_protocol_to_runtime "${protocol}")")"
    done
  else
    echo "当前已安装协议: 无"
  fi

  echo "可安装协议:"
  for index in 1 2 3 4; do
    protocol=$(protocol_option_to_id "${index}") || continue
    if protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
      continue
    fi
    echo "${index}. $(protocol_display_name "$(state_protocol_to_runtime "${protocol}")")"
  done

  echo "0. 返回上一级"
  echo "留空则安装全部可用协议。"
  read -rp "请选择一个或多个协议 [1-4]，逗号分隔: " choice

  if [[ -z "$(trim_whitespace "${choice}")" ]]; then
    for index in 1 2 3 4; do
      protocol=$(protocol_option_to_id "${index}") || continue
      if protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
        continue
      fi
      selected_protocols+=("${protocol}")
    done
  fi

  if [[ "$(trim_whitespace "${choice}")" == "0" ]]; then
    return 1
  fi

  IFS=',' read -r -a raw_choices <<< "${choice}"

  for raw_choice in "${raw_choices[@]}"; do
    raw_choice=$(trim_whitespace "${raw_choice}")
    [[ -z "${raw_choice}" ]] && continue

    protocol=$(protocol_option_to_id "${raw_choice}") || {
      log_warn "跳过无效协议选项: ${raw_choice}"
      continue
    }

    if protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
      log_warn "协议已安装，跳过: $(protocol_display_name "$(state_protocol_to_runtime "${protocol}")")"
      continue
    fi

    if ! protocol_array_contains "${protocol}" "${selected_protocols[@]}"; then
      selected_protocols+=("${protocol}")
    fi
  done

  if [[ ${#selected_protocols[@]} -eq 0 ]]; then
    log_error "未选择任何可安装协议。"
  fi

  SELECTED_PROTOCOLS_CSV=$(IFS=,; printf '%s' "${selected_protocols[*]}")
  return 0
}

prompt_vless_reality_install() {
  local in_p

  set_protocol_defaults "vless+reality"
  echo -e "\n${BLUE}--- 配置 VLESS + REALITY ---${NC}"
  printf '[VLESS + REALITY] 端口 (默认 %s): ' "${SB_PORT}"
  read -r in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  prompt_reality_sni_install
}

prompt_mixed_install() {
  local in_p in_auth in_user in_pass

  set_protocol_defaults "mixed"
  echo -e "\n${BLUE}--- 配置 Mixed ---${NC}"
  printf '[Mixed] 端口 (默认 %s): ' "${SB_PORT}"
  read -r in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  read -rp "[Mixed] 是否启用用户名密码认证 [y/n] (默认 y，强烈建议开启): " in_auth
  SB_MIXED_AUTH_ENABLED=${in_auth:-"y"}
  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    read -rp "[Mixed] 用户名 (留空自动生成): " in_user
    SB_MIXED_USERNAME="${in_user}"
    read -rp "[Mixed] 密码 (留空自动生成): " in_pass
    SB_MIXED_PASSWORD="${in_pass}"
    ensure_mixed_auth_credentials
  else
    log_warn "你选择了关闭认证。开放的 HTTP/SOCKS 代理存在明显安全风险，请确认防火墙与访问源限制。"
  fi
}

prompt_hy2_install() {
  local in_domain in_p in_password in_user_name in_up in_down in_obfs in_obfs_password in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path in_masquerade

  set_protocol_defaults "hy2"
  echo -e "\n${BLUE}--- 配置 Hysteria2 ---${NC}"

  while [[ -z "${SB_HY2_DOMAIN}" ]]; do
    if [[ -n "${SB_SHARED_TLS_DOMAIN:-}" ]]; then
      read -rp "[Hysteria2] 域名 (默认 ${SB_SHARED_TLS_DOMAIN}): " in_domain
      in_domain=${in_domain:-$SB_SHARED_TLS_DOMAIN}
    else
      read -rp "[Hysteria2] 域名: " in_domain
    fi
    SB_HY2_DOMAIN=$(trim_whitespace "${in_domain}")
    [[ -z "${SB_HY2_DOMAIN}" ]] && log_warn "域名不能为空。"
    if [[ -n "${SB_HY2_DOMAIN}" ]] && ! validate_tls_domain_points_to_server "Hysteria2" "${SB_HY2_DOMAIN}"; then
      SB_HY2_DOMAIN=""
    fi
  done
  SB_SHARED_TLS_DOMAIN="${SB_HY2_DOMAIN}"

  printf '[Hysteria2] 端口 (默认 %s): ' "${SB_PORT}"
  read -r in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  read -rp "[Hysteria2] 认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"
  read -rp "[Hysteria2] 用户名标识 (默认 ${SB_HY2_USER_NAME}): " in_user_name
  SB_HY2_USER_NAME=${in_user_name:-$SB_HY2_USER_NAME}

  read -rp "[Hysteria2] 上行带宽 Mbps (留空表示不限制): " in_up
  SB_HY2_UP_MBPS="${in_up}"
  read -rp "[Hysteria2] 下行带宽 Mbps (留空表示不限制): " in_down
  SB_HY2_DOWN_MBPS="${in_down}"

  read -rp "[Hysteria2] 是否启用 Salamander 混淆 [y/n] (默认 n): " in_obfs
  SB_HY2_OBFS_ENABLED=${in_obfs:-"n"}
  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    SB_HY2_OBFS_TYPE="salamander"
    read -rp "[Hysteria2] 混淆密码 (留空自动生成): " in_obfs_password
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  read -rp "[Hysteria2] 请选择 [1-2] (默认 1): " in_tls_mode
  case "${in_tls_mode}" in
    2) SB_HY2_TLS_MODE="manual" ;;
    *) SB_HY2_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    read -rp "[Hysteria2] 请选择 [1-2] (默认 1): " in_acme_mode
    case "${in_acme_mode}" in
      2) SB_HY2_ACME_MODE="dns" ;;
      *) SB_HY2_ACME_MODE="http" ;;
    esac

    read -rp "[Hysteria2] ACME 邮箱 (可留空，用于证书通知): " in_acme_email
    SB_HY2_ACME_EMAIL="${in_acme_email}"
    read -rp "[Hysteria2] ACME 域名 (默认 ${SB_HY2_DOMAIN}): " in_acme_domain
    SB_HY2_ACME_DOMAIN=${in_acme_domain:-$SB_HY2_DOMAIN}

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "[Hysteria2] Cloudflare API Token: " in_cf_api_token
      SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_HY2_CERT_PATH}" ]]; do
      read -rp "[Hysteria2] 证书路径: " in_cert_path
      SB_HY2_CERT_PATH=$(trim_whitespace "${in_cert_path}")
      [[ -z "${SB_HY2_CERT_PATH}" ]] && log_warn "证书路径不能为空。"
    done

    while [[ -z "${SB_HY2_KEY_PATH}" ]]; do
      read -rp "[Hysteria2] 私钥路径: " in_key_path
      SB_HY2_KEY_PATH=$(trim_whitespace "${in_key_path}")
      [[ -z "${SB_HY2_KEY_PATH}" ]] && log_warn "私钥路径不能为空。"
    done
  fi

  read -rp "[Hysteria2] 伪装地址 (默认 ${SB_HY2_MASQUERADE}，留空使用默认): " in_masquerade
  [[ -n "${in_masquerade}" ]] && SB_HY2_MASQUERADE="${in_masquerade}"

  ensure_hy2_materials
}

prompt_anytls_install() {
  local in_domain in_p in_password in_user_name in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path

  set_protocol_defaults "anytls"
  echo -e "\n${BLUE}--- 配置 AnyTLS ---${NC}"

  while [[ -z "${SB_ANYTLS_DOMAIN}" ]]; do
    if [[ -n "${SB_SHARED_TLS_DOMAIN:-}" ]]; then
      read -rp "[AnyTLS] 域名 (默认 ${SB_SHARED_TLS_DOMAIN}): " in_domain
      in_domain=${in_domain:-$SB_SHARED_TLS_DOMAIN}
    else
      read -rp "[AnyTLS] 域名: " in_domain
    fi
    SB_ANYTLS_DOMAIN=$(trim_whitespace "${in_domain}")
    [[ -z "${SB_ANYTLS_DOMAIN}" ]] && log_warn "域名不能为空。"
    if [[ -n "${SB_ANYTLS_DOMAIN}" ]] && ! validate_tls_domain_points_to_server "AnyTLS" "${SB_ANYTLS_DOMAIN}"; then
      SB_ANYTLS_DOMAIN=""
    fi
  done
  SB_SHARED_TLS_DOMAIN="${SB_ANYTLS_DOMAIN}"

  printf '[AnyTLS] 端口 (默认 %s): ' "${SB_PORT}"
  read -r in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  read -rp "[AnyTLS] 用户名标识 (默认 ${SB_ANYTLS_USER_NAME}): " in_user_name
  SB_ANYTLS_USER_NAME=${in_user_name:-$SB_ANYTLS_USER_NAME}

  read -rp "[AnyTLS] 认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_ANYTLS_PASSWORD="${in_password}"

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  read -rp "[AnyTLS] 请选择 [1-2] (默认 1): " in_tls_mode
  case "${in_tls_mode}" in
    2) SB_ANYTLS_TLS_MODE="manual" ;;
    *) SB_ANYTLS_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_ANYTLS_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    read -rp "[AnyTLS] 请选择 [1-2] (默认 1): " in_acme_mode
    case "${in_acme_mode}" in
      2) SB_ANYTLS_ACME_MODE="dns" ;;
      *) SB_ANYTLS_ACME_MODE="http" ;;
    esac

    read -rp "[AnyTLS] ACME 邮箱 (可留空，用于证书通知): " in_acme_email
    SB_ANYTLS_ACME_EMAIL="${in_acme_email}"
    read -rp "[AnyTLS] ACME 域名 (默认 ${SB_ANYTLS_DOMAIN}): " in_acme_domain
    SB_ANYTLS_ACME_DOMAIN=${in_acme_domain:-$SB_ANYTLS_DOMAIN}

    if [[ "${SB_ANYTLS_ACME_MODE}" == "dns" ]]; then
      read -rp "[AnyTLS] Cloudflare API Token: " in_cf_api_token
      SB_ANYTLS_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_ANYTLS_CERT_PATH}" ]]; do
      read -rp "[AnyTLS] 证书路径: " in_cert_path
      SB_ANYTLS_CERT_PATH=$(trim_whitespace "${in_cert_path}")
      [[ -z "${SB_ANYTLS_CERT_PATH}" ]] && log_warn "证书路径不能为空。"
    done

    while [[ -z "${SB_ANYTLS_KEY_PATH}" ]]; do
      read -rp "[AnyTLS] 私钥路径: " in_key_path
      SB_ANYTLS_KEY_PATH=$(trim_whitespace "${in_key_path}")
      [[ -z "${SB_ANYTLS_KEY_PATH}" ]] && log_warn "私钥路径不能为空。"
    done
  fi

  ensure_anytls_materials
}

prompt_protocol_install_fields() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) prompt_vless_reality_install ;;
    mixed) prompt_mixed_install ;;
    hy2) prompt_hy2_install ;;
    anytls) prompt_anytls_install ;;
    *) log_error "不支持的协议安装类型: ${protocol}" ;;
  esac
}

prompt_global_instance_options() {
  local in_route in_warp in_warp_mode

  read -rp "是否开启高级路由规则 (广告拦截/局域网绕行) [y/n] (默认 y): " in_route
  SB_ADVANCED_ROUTE=${in_route:-"y"}
  read -rp "是否开启 Cloudflare Warp (用于解锁/防送中) [y/n] (默认 n): " in_warp
  SB_ENABLE_WARP=${in_warp:-"n"}

  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    SB_WARP_ROUTE_MODE="selective"
    echo "Warp 路由模式:"
    echo "1. 全量流量走 Warp"
    echo "2. 仅 AI/流媒体及自定义规则走 Warp"
    read -rp "请选择 [1-2] (默认 2): " in_warp_mode
    case "${in_warp_mode}" in
      1) SB_WARP_ROUTE_MODE="all" ;;
      *) SB_WARP_ROUTE_MODE="selective" ;;
    esac
  fi
}

install_protocols_interactive() {
  local install_mode=$1
  local installed_protocols=() selected_protocols=()
  local protocol first_selected_protocol

  load_stack_mode_state

  if [[ "${install_mode}" == "fresh" ]]; then
    get_os_info
    get_arch
    prompt_singbox_version
    prompt_protocol_install_selection "fresh" || return 0
    IFS=',' read -r -a selected_protocols <<< "${SELECTED_PROTOCOLS_CSV}"

    for protocol in "${selected_protocols[@]}"; do
      prompt_protocol_install_fields "${protocol}"
      save_protocol_state "${protocol}"
    done

    prompt_global_instance_options
    write_protocol_index "${SELECTED_PROTOCOLS_CSV}"
    install_dependencies
    get_latest_version
    install_binary
  else
    migrate_legacy_single_protocol_state_if_needed
    load_current_config_state
    mapfile -t installed_protocols < <(list_installed_protocols)
    prompt_protocol_install_selection "additional" || return 0
    IFS=',' read -r -a selected_protocols <<< "${SELECTED_PROTOCOLS_CSV}"

    for protocol in "${selected_protocols[@]}"; do
      prompt_protocol_install_fields "${protocol}"
      save_protocol_state "${protocol}"
      if ! protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
        installed_protocols+=("${protocol}")
      fi
    done

    write_protocol_index "$(IFS=,; printf '%s' "${installed_protocols[*]}")"
  fi

  save_warp_route_settings
  generate_config
  check_config_valid
  setup_service
  first_selected_protocol="${selected_protocols[0]}"
  if [[ -n "${first_selected_protocol:-}" ]]; then
    load_protocol_state "${first_selected_protocol}"
  fi
  open_all_protocol_ports
  systemctl restart sing-box
  display_status_summary
  log_info "连接信息未自动展示，如需查看请进入菜单 10。"
}

set_protocol_defaults() {
  case "$1" in
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
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
      ;;
    *)
      SB_PROTOCOL="vless+reality"
      SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
      SB_PORT="443"
      SB_SNI="${SB_REALITY_SNI_FALLBACK}"
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
  mkdir -p "${SB_MEDIA_CHECK_DIR}"

  if [[ -x "${SB_MEDIA_CHECK_SCRIPT}" ]]; then
    return 0
  fi

  log_info "正在下载流媒体验证脚本..."
  if ! curl -fsSL "${MEDIA_CHECK_BACKEND_SCRIPT_URL}" -o "${SB_MEDIA_CHECK_SCRIPT}"; then
    log_error "下载流媒体验证脚本失败，请检查网络。"
  fi

  chmod +x "${SB_MEDIA_CHECK_SCRIPT}"
  log_success "流媒体验证脚本已准备完成。"
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

  register_warp

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

  ensure_media_check_backend
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
    read -rp "请选择 [0-2]: " media_choice

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
  object_file=$(mktemp)
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'

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
        '{type: "remote", tag: $tag, url: $url, format: $format, download_detour: "direct", update_interval: $update_interval}' >> "${object_file}"
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
  read -rp "请选择 [1-2] (当前: ${SB_WARP_ROUTE_MODE}): " mode_choice

  case "${mode_choice}" in
    1) SB_WARP_ROUTE_MODE="all" ;;
    2) SB_WARP_ROUTE_MODE="selective" ;;
    *) log_warn "未修改 Warp 路由模式。"; return 1 ;;
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
  read -rp "请输入远程规则集 URL: " url
  read -rp "请输入更新周期 (默认 1d): " update_interval

  tag=$(sanitize_ruleset_tag "$(trim_whitespace "${tag}")")
  url=$(trim_whitespace "${url}")
  update_interval=$(trim_whitespace "${update_interval:-1d}")

  if [[ -z "${tag}" || -z "${url}" ]]; then
    log_warn "标签或 URL 为空，未写入。"
    return 1
  fi

  if ! [[ "${url}" =~ ^https?:// ]]; then
    log_warn "远程规则集 URL 必须以 http:// 或 https:// 开头。"
    return 1
  fi

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

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "本脚本必须以 root 用户执行。"
  fi
}

# Check for script update status
check_script_status() {
  local remote_content
  local remote_version
  remote_content=$(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh 2>/dev/null) || true
  
  if [[ -z "${remote_content}" ]]; then
    SCRIPT_VER_STATUS="${RED}(无法检测更新)${NC}"
    return
  fi

  remote_version=$(echo "${remote_content}" | grep -m1 "readonly SCRIPT_VERSION" | cut -d'"' -f2 || true)

  if [[ -z "${remote_version}" || ! "${remote_version}" =~ ^[0-9]{10}$ ]]; then
    SCRIPT_VER_STATUS="${RED}(无法检测更新)${NC}"
    return
  fi
  
  if [[ "${remote_version}" -gt "${SCRIPT_VERSION}" ]]; then
    SCRIPT_VER_STATUS="${YELLOW}(有新版本: ${remote_version})${NC}"
  else
    SCRIPT_VER_STATUS="${GREEN}(已是最新)${NC}"
  fi
}

# Manual update script
manual_update_script() {
  log_info "正在从 GitHub 获取最新脚本..."
  if curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh -o "${SBV_BIN_PATH}" \
    && [[ -s "${SBV_BIN_PATH}" ]]; then
    chmod +x "${SBV_BIN_PATH}"
    log_success "脚本已更新到最新版本，请重新运行 sbv。"
    exit 0
  else
    log_error "脚本更新失败，请检查网络。"
  fi
}

ensure_sbv_command_installed() {
  if [[ "$0" == "${SBV_BIN_PATH}" || "$0" == "sbv" ]]; then
    return 0
  fi

  if [[ -f "$0" ]]; then
    if [[ ! -x "${SBV_BIN_PATH}" ]] || ! cmp -s "$0" "${SBV_BIN_PATH}" 2>/dev/null; then
      log_info "正在同步全局命令: sbv..."
      if cp -f "$0" "${SBV_BIN_PATH}" 2>/dev/null; then
        chmod +x "${SBV_BIN_PATH}"
        log_success "全局命令 sbv 已同步为当前脚本版本。"
        return 0
      fi
    else
      return 0
    fi
  fi

  log_info "正在安装全局命令: sbv..."
  if curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh -o "${SBV_BIN_PATH}" \
    && [[ -s "${SBV_BIN_PATH}" ]]; then
    chmod +x "${SBV_BIN_PATH}"
    log_success "全局命令 sbv 安装成功。"
    return 0
  fi

  log_warn "无法从远程下载脚本，尝试使用当前脚本安装 sbv..."
  if [[ -f "$0" ]] && cp -f "$0" "${SBV_BIN_PATH}" 2>/dev/null; then
    chmod +x "${SBV_BIN_PATH}"
    log_success "已使用当前脚本安装全局命令 sbv。"
    return 0
  fi

  if [[ -f "$0" ]]; then
    log_warn "当前环境无法写入 ${SBV_BIN_PATH}，后续可手动安装 sbv。"
  else
    log_warn "全局命令 sbv 安装失败，后续可重新运行一键安装命令。"
  fi
}

exit_script() {
  echo ""
  log_info "已退出脚本。后续可运行 sbv 再次进入管理菜单。"
  exit 0
}

# Check for sing-box version
check_sb_version() {
  local current_sb_ver

  if [[ -f "${SINGBOX_BIN_PATH}" ]]; then
    current_sb_ver=$("${SINGBOX_BIN_PATH}" version 2>/dev/null | head -n1 | awk '{print $3}' || true)
    if [[ -z "${current_sb_ver}" ]]; then
      SB_VER_STATUS="${YELLOW}(版本检测失败)${NC}"
    elif [[ "${current_sb_ver}" != "${SB_SUPPORT_MAX_VERSION}" ]]; then
      SB_VER_STATUS="${YELLOW}(当前版本: ${current_sb_ver}, 建议更新到: ${SB_SUPPORT_MAX_VERSION})${NC}"
    else
      SB_VER_STATUS="${GREEN}(已是适配的最佳版本: ${current_sb_ver})${NC}"
    fi
  else
    SB_VER_STATUS="${RED}(未安装)${NC}"
  fi
}

# Check and Enable BBR
enable_bbr() {
  local current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
  if [[ "${current_cc}" == "bbr" ]]; then
    log_success "BBR 拥塞控制已开启。"
  else
    log_warn "BBR 拥塞控制未开启，正在尝试开启..."
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    log_success "BBR 开启成功。"
  fi
}

# Open firewall port
open_firewall_port() {
  local port=$1
  log_info "正在尝试放行端口 ${port}..."
  
  # UFW
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "${port}/tcp" &>/dev/null
    ufw allow "${port}/udp" &>/dev/null
  fi
  
  # Firewalld
  if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    firewall-cmd --permanent --add-port="${port}/tcp" &>/dev/null
    firewall-cmd --permanent --add-port="${port}/udp" &>/dev/null
    firewall-cmd --reload &>/dev/null
  fi
  
  # Iptables
  if command -v iptables &>/dev/null; then
    iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT &>/dev/null
    iptables -I INPUT -p udp --dport "${port}" -j ACCEPT &>/dev/null
  fi
  
  log_success "端口 ${port} 防火墙配置尝试完成。"
}

# Verify configuration file
check_config_valid() {
  log_info "正在校验配置文件有效性..."
  if ! validate_config_file; then
    log_error "配置文件校验失败，请检查配置细节。"
  fi
  log_success "配置文件校验成功。"
}

validate_config_file() {
  "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"
}

# Check for port conflict
check_port_conflict() {
  local port=$1
  if port_is_in_use "${port}"; then
    local process
    process=$(ss -tunlp | grep ":${port} " | awk '{print $7}' | cut -d'"' -f2 | head -n1)
    log_warn "端口 ${port} 已被进程 [${process}] 占用。"
    echo "1. 尝试自动停止该进程"
    echo "2. 使用随机端口"
    echo "3. 手动输入新端口"
    read -rp "请选择操作 [1-3]: " port_choice
    
    case "${port_choice}" in
      1)
        local pid=$(ss -tunlp | grep ":${port} " | awk '{print $7}' | cut -d',' -f2 | cut -d'=' -f2 | head -n1)
        kill -9 "${pid}" && log_success "进程已终止。"
        ;;
      2)
        SB_PORT="$(pick_random_high_port)"
        log_success "已自动切换到随机端口: ${SB_PORT}"
        ;;
      3)
        read -rp "请输入新端口: " SB_PORT
        check_port_conflict "${SB_PORT}"
        ;;
    esac
  fi
}

get_os_info() {
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
  elif [[ -f /etc/redhat-release ]]; then
    OS_NAME="centos"
    OS_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -n1)
  else
    log_error "不支持的操作系统。"
  fi
}

get_arch() {
  local arch_raw
  arch_raw=$(uname -m)
  case "${arch_raw}" in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) log_error "不支持的架构: ${arch_raw}" ;;
  esac
}

# --- System Check & Dependencies ---
install_dependencies() {
  log_info "正在安装必要的基础依赖..."
  case "${OS_NAME}" in
    debian|ubuntu)
      apt-get update -y
      apt-get install -y curl wget jq tar openssl uuid-runtime qrencode
      ;;
    centos|almalinux|rocky)
      yum install -y curl wget jq tar openssl util-linux qrencode
      ;;
  esac
  log_success "基础依赖安装完成。"
}

# --- Sing-box Manager ---
get_latest_version() {
  if [[ "${SB_VERSION}" == "latest" ]]; then
    log_info "正在获取最新版本号..."
    local latest_tag=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name | sed 's/^v//')
    if [[ -z "${latest_tag}" || "${latest_tag}" == "null" ]]; then
      SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
    else
      SB_VERSION="${latest_tag}"
      if [[ "${SB_VERSION}" != "${SB_SUPPORT_MAX_VERSION}" ]]; then
        log_warn "注意：最新版本 (${SB_VERSION}) 高于适配版本 (${SB_SUPPORT_MAX_VERSION})，可能存在兼容性风险。"
        sleep 2
      fi
    fi
  fi
}

install_binary() {
  local download_url="https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-${ARCH}.tar.gz"
  local temp_dir="/tmp/sing-box-install"
  
  # Ensure we are in a valid directory before cleanup/extraction
  cd /tmp
  
  # Cleanup before start
  rm -rf "${temp_dir}"
  mkdir -p "${temp_dir}"
  
  log_info "开始下载 sing-box ${SB_VERSION}..."
  if ! wget -O "${temp_dir}/sb.tar.gz" "${download_url}"; then
    log_error "下载 sing-box 失败。"
  fi
  
  log_info "正在解压并安装..."
  if ! tar -xzf "${temp_dir}/sb.tar.gz" -C "${temp_dir}"; then
    log_error "解压失败。"
  fi
  
  local bin_path=$(find "${temp_dir}" -name "sing-box" -type f)
  if [[ -z "${bin_path}" ]]; then
    log_error "找不到 sing-box 二进制文件。"
  fi
  
  mv -f "${bin_path}" "${SINGBOX_BIN_PATH}"
  chmod +x "${SINGBOX_BIN_PATH}"
  
  # Final Cleanup
  rm -rf "${temp_dir}"
  log_success "二进制文件安装成功并已清理临时文件。"
}

setup_service() {
  log_info "配置 systemd 服务..."
  cat > "${SINGBOX_SERVICE_FILE}" <<EOF
[Unit]
Description=sing-box service
After=network.target nss-lookup.target
[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sing-box >/dev/null 2>&1

  ensure_sbv_command_installed
}

service_file_needs_repair() {
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] || return 0
  grep -Fqx "ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}" "${SINGBOX_SERVICE_FILE}" || return 0
  return 1
}

# --- Protocol State Helpers ---
list_effective_protocols() {
  local installed
  installed=$(extract_protocols_from_index)

  if [[ -n "${installed}" ]]; then
    list_installed_protocols
    return 0
  fi

  runtime_protocol_to_state "${SB_PROTOCOL}"
  printf '\n'
}

load_protocol_state() {
  local protocol state_file
  protocol=$(normalize_protocol_id "$1")
  state_file=$(protocol_state_file "${protocol}")

  if [[ ! -f "${state_file}" ]]; then
    if [[ "$(runtime_protocol_to_state "${SB_PROTOCOL}")" == "${protocol}" ]]; then
      return 0
    fi
    log_error "未找到协议状态文件: ${state_file}"
  fi

  # shellcheck disable=SC1090
  source "${state_file}"

  case "${protocol}" in
    vless-reality)
      SB_PROTOCOL="vless+reality"
      SB_NODE_NAME="${NODE_NAME:-$(default_node_name_for_protocol "vless+reality")}"
      SB_PORT="${PORT:-443}"
      SB_UUID="${UUID:-}"
      SB_SNI="${SNI:-$SB_REALITY_SNI_FALLBACK}"
      SB_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
      SB_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
      SB_SHORT_ID_1="${SHORT_ID_1:-}"
      SB_SHORT_ID_2="${SHORT_ID_2:-}"
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
    mixed)
      SB_PROTOCOL="mixed"
      SB_NODE_NAME="${NODE_NAME:-$(default_node_name_for_protocol "mixed")}"
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
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
      ;;
    hy2)
      SB_PROTOCOL="hy2"
      SB_NODE_NAME="${NODE_NAME:-$(default_node_name_for_protocol "hy2")}"
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
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
      ;;
    anytls)
      SB_PROTOCOL="anytls"
      SB_NODE_NAME="${NODE_NAME:-$(default_node_name_for_protocol "anytls")}"
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
      SB_ANYTLS_DNS_PROVIDER="${DNS_PROVIDER:-cloudflare}"
      SB_ANYTLS_CF_API_TOKEN="${CF_API_TOKEN:-}"
      SB_ANYTLS_CERT_PATH="${CERT_PATH:-}"
      SB_ANYTLS_KEY_PATH="${KEY_PATH:-}"
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
      [[ -z "${SB_PRIVATE_KEY}" ]] && SB_PRIVATE_KEY=$(grep '^PRIVATE_KEY=' "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
      [[ -z "${SB_PUBLIC_KEY}" ]] && SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    fi
  fi

  if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
    log_info "正在生成新的 REALITY 密钥对..." >&2
    local keypair
    keypair=$(run_singbox_generate_command "reality-keypair" "REALITY 密钥") || exit 1
    SB_PRIVATE_KEY=$(extract_generated_key_value "${keypair}" "private")
    SB_PUBLIC_KEY=$(extract_generated_key_value "${keypair}" "public")
    if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
      log_info "REALITY 密钥生成原始输出: ${keypair}" >> "${SBV_LOG_FILE}"
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

  # Persist generated REALITY materials so later info views reuse the active link data.
  save_vless_reality_state

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

stack_inbound_listen_address() {
  ensure_stack_mode_state_loaded

  case "${SB_INBOUND_STACK_MODE}" in
    ipv4_only) printf '0.0.0.0' ;;
    *) printf '::' ;;
  esac
}

build_vless_inbound_json() {
  ensure_vless_reality_materials

  jq -n \
    --arg tag "vless-in" \
    --arg listen "$(stack_inbound_listen_address)" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg sni "${SB_SNI}" \
    --arg priv_key "${SB_PRIVATE_KEY}" \
    --arg sid1 "${SB_SHORT_ID_1}" \
    --arg sid2 "${SB_SHORT_ID_2}" \
    '{
      "type": "vless",
      "tag": $tag,
      "listen": $listen,
      "listen_port": ($port | tonumber),
      "users": [ { "uuid": $uuid, "flow": "xtls-rprx-vision" } ],
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
    }'
}

build_mixed_inbound_json() {
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

hy2_certificate_provider_tag() {
  printf 'hy2-cert-provider'
}

build_hy2_acme_json() {
  if [[ "${SB_HY2_TLS_MODE}" != "acme" ]]; then
    return 0
  fi

  jq -n \
    --arg acme_email "${SB_HY2_ACME_EMAIL}" \
    --arg acme_domain "${SB_HY2_ACME_DOMAIN}" \
    --arg acme_data_directory "${SB_ACME_DATA_DIR}" \
    --arg acme_mode "${SB_HY2_ACME_MODE}" \
    --arg dns_provider "${SB_HY2_DNS_PROVIDER}" \
    --arg cf_api_token "${SB_HY2_CF_API_TOKEN}" \
    '{
      "domain": [ $acme_domain ],
      "data_directory": $acme_data_directory
    } + (
      if $acme_email != "" then
        { "email": $acme_email }
      else
        {}
      end
    ) + (
      if $acme_mode == "dns" then
        {
          "dns01_challenge": {
            "provider": $dns_provider,
            "api_token": $cf_api_token
          }
        }
      else
        {}
      end
    )'
}

build_hy2_certificate_provider_json() {
  return 0
}

build_hy2_inbound_json() {
  ensure_hy2_materials
  local acme_json
  acme_json=$(build_hy2_acme_json)

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

  jq -n \
    --arg acme_email "${SB_ANYTLS_ACME_EMAIL}" \
    --arg acme_domain "${SB_ANYTLS_ACME_DOMAIN}" \
    --arg acme_data_directory "${SB_ACME_DATA_DIR}" \
    --arg acme_mode "${SB_ANYTLS_ACME_MODE}" \
    --arg dns_provider "${SB_ANYTLS_DNS_PROVIDER}" \
    --arg cf_api_token "${SB_ANYTLS_CF_API_TOKEN}" \
    '{
      "domain": [ $acme_domain ],
      "data_directory": $acme_data_directory
    } + (
      if $acme_email != "" then
        { "email": $acme_email }
      else
        {}
      end
    ) + (
      if $acme_mode == "dns" then
        {
          "dns01_challenge": {
            "provider": $dns_provider,
            "api_token": $cf_api_token
          }
        }
      else
        {}
      end
    )'
}

build_anytls_certificate_provider_json() {
  return 0
}

build_anytls_inbound_json() {
  ensure_anytls_materials
  local acme_json
  acme_json=$(build_anytls_acme_json)

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
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    hy2) build_hy2_certificate_provider_json ;;
    anytls) build_anytls_certificate_provider_json ;;
  esac
}

build_inbound_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) build_vless_inbound_json ;;
    mixed) build_mixed_inbound_json ;;
    hy2) build_hy2_inbound_json ;;
    anytls) build_anytls_inbound_json ;;
  esac
}

build_protocol_route_rules() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality)
      jq -n \
        --arg inbound_tag "vless-in" \
        --arg sni "${SB_SNI}" \
        '[
          { "inbound": $inbound_tag, "action": "sniff" },
          { "domain": [ $sni ], "action": "direct" }
        ]'
      ;;
    mixed)
      jq -n '[{ "inbound": "mixed-in", "action": "sniff" }]'
      ;;
    hy2)
      jq -n '[{ "inbound": "hy2-in", "action": "sniff" }]'
      ;;
    anytls)
      jq -n '[{ "inbound": "anytls-in", "action": "sniff" }]'
      ;;
  esac
}

# --- Config Generator ---
generate_config() {
  # Force ensure jq is installed
  if ! command -v jq &>/dev/null; then
    log_warn "未检测到 jq，正在尝试自动安装以确保配置生成安全..."
    get_os_info && install_dependencies
  fi

  log_info "正在生成配置 (适配 1.13.x Endpoint 架构 & 安全注入)..."
  mkdir -p "${SINGBOX_CONFIG_DIR}"
  ensure_warp_routing_assets
  load_warp_route_settings

  # Endpoints Logic
  local w_key="" w_v4="" w_v6="" w_client_id="" w_reserved='[]'
  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    register_warp
    w_key=$(grep "WARP_PRIV_KEY" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v4=$(grep "WARP_V4" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v6=$(grep "WARP_V6" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_client_id=$(grep "WARP_CLIENT_ID" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_reserved=$(warp_client_id_to_reserved_json "${w_client_id}")
  fi

  refresh_warp_route_assets
  local inbound_file provider_file protocol_rule_file protocol
  local inbounds_json certificate_providers_json protocol_rules_json

  ensure_stack_mode_state_loaded

  inbound_file=$(mktemp)
  provider_file=$(mktemp)
  protocol_rule_file=$(mktemp)

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    load_protocol_state "${protocol}"
    build_inbound_for_protocol "${protocol}" >> "${inbound_file}"
    build_certificate_provider_for_protocol "${protocol}" >> "${provider_file}" 2>/dev/null || true
    build_protocol_route_rules "${protocol}" >> "${protocol_rule_file}"
  done < <(list_effective_protocols)

  inbounds_json=$(jq -s . "${inbound_file}")
  certificate_providers_json=$(jq -s . "${provider_file}")
  protocol_rules_json=$(jq -s 'add // []' "${protocol_rule_file}")

  jq -n \
    --arg adv_route "${SB_ADVANCED_ROUTE}" \
    --arg enable_warp "${SB_ENABLE_WARP}" \
    --arg warp_mode "${SB_WARP_ROUTE_MODE}" \
    --arg w_key "${w_key}" \
    --arg w_v4 "${w_v4}/32" \
    --arg w_v6 "${w_v6}/128" \
    --argjson w_reserved "${w_reserved}" \
    --arg outbound_stack_mode "${SB_OUTBOUND_STACK_MODE}" \
    --argjson inbounds "${inbounds_json}" \
    --argjson certificate_providers "${certificate_providers_json}" \
    --argjson protocol_rules "${protocol_rules_json}" \
    --argjson ai_domains "${WARP_AI_ROUTE_DOMAINS_JSON}" \
    --argjson ai_domain_suffixes "${WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON}" \
    --argjson stream_domains "${WARP_STREAM_ROUTE_DOMAINS_JSON}" \
    --argjson stream_domain_suffixes "${WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON}" \
    --argjson custom_domains "${SB_WARP_CUSTOM_DOMAINS_JSON}" \
    --argjson custom_domain_suffixes "${SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON}" \
    --argjson local_rule_sets "${SB_WARP_LOCAL_RULE_SETS_JSON}" \
    --argjson remote_rule_sets "${SB_WARP_REMOTE_RULE_SETS_JSON}" \
    --argjson warp_rule_set_tags "${SB_WARP_RULE_SET_TAGS_JSON}" \
    '{
      "log": { "level": "info", "timestamp": true },
      "dns": {
        "servers": [
          {
            "type": "local",
            "tag": "local-dns"
          }
        ],
        "strategy": $outbound_stack_mode
      },
      "endpoints": (if $enable_warp == "y" then [
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
      ] else [] end),
      "inbounds": $inbounds,
      "outbounds": [
        {
          "type": "direct",
          "tag": "direct",
          "domain_resolver": {
            "server": "local-dns",
            "strategy": $outbound_stack_mode
          }
        },
        { "type": "block", "tag": "block" }
      ],
      "route": {
        "rule_set": (
          if $enable_warp == "y" and $warp_mode == "selective" then
            $local_rule_sets + $remote_rule_sets
          else
            []
          end
        ),
        "rules": (
          $protocol_rules +
          (if $adv_route == "y" then [ { "ip_is_private": true, "action": "reject" } ] else [] end) +
          (
            if $enable_warp == "y" and $warp_mode == "selective" then
              [
                {
                  "domain": $ai_domains,
                  "domain_suffix": $ai_domain_suffixes,
                  "action": "route",
                  "outbound": "warp-ep"
                },
                {
                  "domain": $stream_domains,
                  "domain_suffix": $stream_domain_suffixes,
                  "action": "route",
                  "outbound": "warp-ep"
                }
              ] +
              (
                if ($custom_domains | length) > 0 or ($custom_domain_suffixes | length) > 0 then
                  [
                    {
                      "domain": $custom_domains,
                      "domain_suffix": $custom_domain_suffixes,
                      "action": "route",
                      "outbound": "warp-ep"
                    }
                  ]
                else
                  []
                end
              ) +
              (
                if ($warp_rule_set_tags | length) > 0 then
                  [
                    {
                      "rule_set": $warp_rule_set_tags,
                      "action": "route",
                      "outbound": "warp-ep"
                    }
                  ]
                else
                  []
                end
              )
            else
              []
            end
          )
        ),
        "final": (if $enable_warp == "y" and $warp_mode == "all" then "warp-ep" else "direct" end)
      }
    } + (
      if ($certificate_providers | length) > 0 then
        { "certificate_providers": $certificate_providers }
      else
        {}
      end
    )' > "${SINGBOX_CONFIG_FILE}"

  rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}"
}

# --- Uninstaller ---
perform_full_uninstall() {
  log_info "正在彻底卸载 sing-box 环境..."
  systemctl stop sing-box &>/dev/null || true
  systemctl disable sing-box &>/dev/null || true
  rm -f "${SINGBOX_SERVICE_FILE}"
  systemctl daemon-reload
  rm -f "${SINGBOX_BIN_PATH}"
  rm -f "${SBV_BIN_PATH}"
  rm -rf "${SINGBOX_CONFIG_DIR}"
  print_success "sing-box、配置目录和全局命令 sbv 已彻底删除。"
}

uninstall_singbox() {
  echo ""
  print_warn "该操作会彻底删除 sing-box 服务、配置目录、密钥和全局命令 sbv。"
  read -rp "确认继续吗？[y/N]: " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "已取消卸载。"
    return 0
  fi

  perform_full_uninstall
  exit 0
}

# Uninstall script itself
uninstall_script() {
  local deleted_cfg="n"
  read -rp "是否同时删除项目配置文件目录 (/root/sing-box-vps)? [y/N]: " del_cfg
  if [[ "${del_cfg}" =~ ^[Yy]$ ]]; then
    rm -rf "${SB_PROJECT_DIR}"
    deleted_cfg="y"
    print_info "配置文件目录已删除。"
  fi
  
  if [[ "${deleted_cfg}" == "y" ]]; then
    print_info "正在删除全局命令 sbv..."
  else
    log_info "正在删除全局命令 sbv..."
  fi
  rm -f "${SBV_BIN_PATH}"
  if [[ "${deleted_cfg}" == "y" ]]; then
    print_success "管理脚本已卸载。"
  else
    log_success "管理脚本已卸载。"
  fi
  exit 0
}

# --- UI & Main ---
term_columns() {
  local cols=${COLUMNS:-}

  if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
    printf '%s' "${cols}"
    return 0
  fi

  if command -v tput >/dev/null 2>&1; then
    cols=$(tput cols 2>/dev/null || true)
    if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
      printf '%s' "${cols}"
      return 0
    fi
  fi

  cols=$(stty size 2>/dev/null | awk '{print $2}' || true)
  if [[ "${cols}" =~ ^[0-9]+$ ]] && (( cols > 0 )); then
    printf '%s' "${cols}"
    return 0
  fi

  printf '80'
}

repeat_char() {
  local char=$1
  local count=$2
  local output=""
  local i

  for ((i = 0; i < count; i++)); do
    output+="${char}"
  done

  printf '%s' "${output}"
}

safe_clear_screen() {
  if [[ -z "${TERM:-}" ]] || [[ "${TERM}" == "dumb" ]]; then
    return 0
  fi

  if [[ ! -t 1 ]]; then
    return 0
  fi

  if command -v clear >/dev/null 2>&1; then
    clear 2>/dev/null || true
  fi
}

is_ascii_text() {
  LC_ALL=C grep -q '^[ -~]*$' <<< "${1}"
}

estimate_text_width() {
  local text=$1
  local char_count byte_count extra_bytes

  if is_ascii_text "${text}"; then
    printf '%s' "${#text}"
    return 0
  fi

  char_count=$(printf '%s' "${text}" | wc -m | tr -d '[:space:]')
  byte_count=$(printf '%s' "${text}" | wc -c | tr -d '[:space:]')

  if [[ ! "${char_count}" =~ ^[0-9]+$ ]] || [[ ! "${byte_count}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${#text}"
    return 0
  fi

  extra_bytes=$((byte_count - char_count))
  printf '%s' "$((char_count + (extra_bytes / 2)))"
}

print_centered_text() {
  local text=$1
  local color=${2:-}
  local width text_length padding

  width=$(term_columns)
  padding=0
  text_length=$(estimate_text_width "${text}")

  if (( width > text_length )); then
    padding=$(((width - text_length) / 2))
  fi

  printf '%*s' "${padding}" ''
  if [[ -n "${color}" ]]; then
    printf '%b%s%b\n' "${color}" "${text}" "${NC}"
  else
    printf '%s\n' "${text}"
  fi
}

render_page_header() {
  local title=$1
  local subtitle=${2:-}
  local width divider

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  fi
  divider=$(repeat_char "═" "${width}")

  echo -e "${BLUE}${divider}${NC}"
  print_centered_text "${title}" "${GREEN}"
  if [[ -n "${subtitle}" ]]; then
    print_centered_text "${subtitle}" "${BLUE}"
  fi
  echo -e "${BLUE}${divider}${NC}"
}

render_section_title() {
  local title=$1
  local width divider

  width=$(term_columns)
  if (( width < 56 )); then
    echo -e "\n${BLUE}${title}${NC}"
    return 0
  fi

  divider=$(repeat_char "·" 8)
  echo -e "\n${BLUE}${divider} ${title} ${divider}${NC}"
}

render_menu_item() {
  local number=$1
  local label=$2
  local hint=${3:-}
  local status=${4:-}
  local width line

  width=$(term_columns)
  line="${number}. ${label}"

  if [[ -n "${status}" ]]; then
    if (( width >= 72 )); then
      echo -e "${line} ${GREEN}${status}${NC}"
    else
      echo "${line}"
      echo -e "   ${GREEN}${status}${NC}"
    fi
    return 0
  fi

  if [[ -n "${hint}" ]]; then
    if (( width >= 72 )); then
      echo -e "${line} ${BLUE}${hint}${NC}"
    else
      echo "${line}"
      echo -e "   ${BLUE}${hint}${NC}"
    fi
    return 0
  fi

  echo "${line}"
}

render_summary_item() {
  local label=$1
  local value=${2:-}
  printf '%s: %b\n' "${label}" "${value}"
}

render_main_menu_brand_block() {
  local width divider brand_info brand_meta brand_info_width brand_meta_width
  local project_url_without_scheme project_url_base project_url_path
  local current_path_line path_segment candidate
  local -a project_path_segments

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  fi
  divider=$(repeat_char "═" "${width}")
  brand_info="作者: ${PROJECT_AUTHOR} · 项目: ${PROJECT_URL}"
  brand_meta="专为 VPS 稳定部署与安全运维设计 · 版本: ${SCRIPT_VERSION}"
  brand_info_width=$(estimate_text_width "${brand_info}")
  brand_meta_width=$(estimate_text_width "${brand_meta}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}sing-box-vps 一键安装管理脚本${NC}"

  if (( brand_info_width <= width && brand_meta_width <= width )); then
    echo -e "${YELLOW}${brand_info}${NC}"
    echo -e "${BLUE}${brand_meta}${NC}"
  else
    echo -e "${YELLOW}作者: ${PROJECT_AUTHOR}${NC}"
    echo -e "${YELLOW}项目:${NC}"
    project_url_without_scheme=${PROJECT_URL#*://}
    project_url_base="${PROJECT_URL%%://*}://${project_url_without_scheme%%/*}/"
    if [[ "${project_url_without_scheme}" == */* ]]; then
      project_url_path=${project_url_without_scheme#*/}
    else
      project_url_path=""
    fi

    echo -e "${YELLOW}${project_url_base}${NC}"

    if [[ -n "${project_url_path}" ]]; then
      IFS='/' read -r -a project_path_segments <<< "${project_url_path}"
      current_path_line=""

      for path_segment in "${project_path_segments[@]}"; do
        if [[ -z "${current_path_line}" ]]; then
          candidate="${path_segment}"
        else
          candidate="${current_path_line}/${path_segment}"
        fi

        if (( $(estimate_text_width "${candidate}") <= width )); then
          current_path_line="${candidate}"
        else
          [[ -n "${current_path_line}" ]] && echo -e "${YELLOW}${current_path_line}${NC}"
          current_path_line="${path_segment}"
        fi
      done

      [[ -n "${current_path_line}" ]] && echo -e "${YELLOW}${current_path_line}${NC}"
    fi

    echo -e "${BLUE}专为 VPS 稳定部署与安全运维设计${NC}"
    echo -e "${BLUE}版本: ${SCRIPT_VERSION}${NC}"
  fi

  echo -e "${BLUE}${divider}${NC}"
}

render_left_aligned_page_header() {
  local title=$1
  local subtitle=${2:-}
  local width divider

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  fi
  divider=$(repeat_char "═" "${width}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}${title}${NC}"
  if [[ -n "${subtitle}" ]]; then
    echo -e "${BLUE}${subtitle}${NC}"
  fi
  echo -e "${BLUE}${divider}${NC}"
}

render_menu_group_start() {
  local title=${1:-}

  if [[ -n "${title}" ]]; then
    render_section_title "${title}"
  else
    echo
  fi
}

show_banner() {
  safe_clear_screen
  render_main_menu_brand_block
  echo
}

render_main_menu_footer() {
  :
}

# Helper: Check BBR Status
check_bbr_status() {
  local cc
  cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || true)

  if [[ -z "${cc}" ]]; then
    BBR_STATUS="${YELLOW}(状态未知)${NC}"
  elif [[ "${cc}" == "bbr" ]]; then
    BBR_STATUS="${GREEN}(已开启 BBR)${NC}"
  else
    BBR_STATUS="${YELLOW}(未开启 BBR)${NC}"
  fi
}

apply_stack_mode_changes() {
  local selected_inbound selected_outbound
  selected_inbound="${SB_INBOUND_STACK_MODE}"
  selected_outbound="${SB_OUTBOUND_STACK_MODE}"

  if [[ -f "${SINGBOX_CONFIG_FILE}" || -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    load_current_config_state
    SB_INBOUND_STACK_MODE="${selected_inbound}"
    SB_OUTBOUND_STACK_MODE="${selected_outbound}"
  fi

  save_stack_mode_state

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_success "协议栈设置已保存，将在首次安装或下次生成配置时生效。"
    return 0
  fi

  generate_config
  check_config_valid
  setup_service
  open_all_protocol_ports
  systemctl restart sing-box
  log_success "协议栈设置已保存并重启服务。"
}

configure_inbound_stack_mode() {
  local host_stack choice selected_mode
  local available_modes=()
  local index

  ensure_stack_mode_state_loaded
  host_stack=$(detect_host_ip_stack)

  case "${host_stack}" in
    dual) available_modes=(ipv4_only ipv6_only dual_stack) ;;
    ipv6) available_modes=(ipv6_only) ;;
    *) available_modes=(ipv4_only) ;;
  esac

  while true; do
    echo
    render_left_aligned_page_header "入站协议栈" "按主机能力选择监听栈"
    render_section_title "当前设置"
    render_summary_item "系统网络能力" "$(host_ip_stack_display_name "${host_stack}")"
    render_summary_item "当前入站协议栈" "$(inbound_stack_mode_display_name "${SB_INBOUND_STACK_MODE}")"
    render_section_title "可选模式"

    for index in "${!available_modes[@]}"; do
      render_menu_item "$((index + 1))" "$(inbound_stack_mode_display_name "${available_modes[$index]}")"
    done
    echo "0. 返回"
    read -rp "请选择 [0-${#available_modes[@]}]: " choice

    if [[ "${choice}" == "0" ]]; then
      return 0
    fi

    if [[ "${choice}" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#available_modes[@]} )); then
      selected_mode="${available_modes[$((choice - 1))]}"
      [[ "${selected_mode}" == "${SB_INBOUND_STACK_MODE}" ]] && return 0
      SB_INBOUND_STACK_MODE="${selected_mode}"
      apply_stack_mode_changes
      return 0
    fi

    log_warn "无效选项，请重新选择。"
  done
}

configure_outbound_stack_mode() {
  local choice selected_mode
  local available_modes=(ipv4_only ipv6_only prefer_ipv4 prefer_ipv6)
  local index

  ensure_stack_mode_state_loaded

  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    log_warn "当前已开启 Warp，出站协议栈设置不生效，已禁止修改。"
    return 0
  fi

  while true; do
    echo
    render_left_aligned_page_header "出站协议栈" "调整 sing-box 的 DNS 与直连出站策略"
    render_section_title "当前设置"
    render_summary_item "当前出站协议栈" "$(outbound_stack_mode_display_name "${SB_OUTBOUND_STACK_MODE}")"
    render_section_title "可选模式"

    for index in "${!available_modes[@]}"; do
      render_menu_item "$((index + 1))" "$(outbound_stack_mode_display_name "${available_modes[$index]}")"
    done
    echo "0. 返回"
    read -rp "请选择 [0-${#available_modes[@]}]: " choice

    if [[ "${choice}" == "0" ]]; then
      return 0
    fi

    if [[ "${choice}" =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#available_modes[@]} )); then
      selected_mode="${available_modes[$((choice - 1))]}"
      [[ "${selected_mode}" == "${SB_OUTBOUND_STACK_MODE}" ]] && return 0
      SB_OUTBOUND_STACK_MODE="${selected_mode}"
      apply_stack_mode_changes
      return 0
    fi

    log_warn "无效选项，请重新选择。"
  done
}

stack_management_menu() {
  local host_stack
  local warp_status

  while true; do
    if [[ -f "${SINGBOX_CONFIG_FILE}" || -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
      load_current_config_state
    else
      ensure_stack_mode_state_loaded
      SB_ENABLE_WARP="n"
    fi

    host_stack=$(detect_host_ip_stack)
    if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
      warp_status="已开启 (出站协议栈当前不生效)"
    else
      warp_status="未开启"
    fi

    echo
    render_left_aligned_page_header "协议栈管理" "统一调整入站 / 出站网络栈策略"
    render_section_title "协议栈摘要"
    render_summary_item "系统网络能力" "$(host_ip_stack_display_name "${host_stack}")"
    render_summary_item "当前入站协议栈" "$(inbound_stack_mode_display_name "${SB_INBOUND_STACK_MODE}")"
    render_summary_item "当前出站协议栈" "$(outbound_stack_mode_display_name "${SB_OUTBOUND_STACK_MODE}")"
    render_summary_item "Warp 状态" "${warp_status}"
    render_section_title "操作选项"
    render_menu_item "1" "修改入站协议栈"
    render_menu_item "2" "修改出站协议栈"
    echo "0. 返回上一级"
    read -rp "请选择 [0-2]: " stack_choice

    case "${stack_choice}" in
      1) configure_inbound_stack_mode || true ;;
      2) configure_outbound_stack_mode || true ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

system_management_menu() {
  while true; do
    check_bbr_status
    echo
    render_left_aligned_page_header "系统管理" "维护内核优化与网络协议栈设置"
    render_section_title "系统摘要"
    render_summary_item "BBR 状态" "${BBR_STATUS}"
    render_section_title "操作选项"
    render_menu_item "1" "开启 BBR"
    render_menu_item "2" "协议栈管理"
    echo "0. 返回主菜单"
    read -rp "请选择 [0-2]: " system_choice

    case "${system_choice}" in
      1) enable_bbr ;;
      2) stack_management_menu ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

# Detect whether the current config enables Warp.
# Prefer the current endpoint-based schema, but keep compatibility with older configs.
config_has_warp_enabled() {
  local config_file=$1

  jq -e '
    (
      any(.endpoints[]?; .tag == "warp-ep") and
      (
        (.route.final // "") == "warp-ep" or
        any(.route.rules[]?; (.outbound // "") == "warp-ep")
      )
    ) or any(.outbounds[]?; .tag == "warp")
  ' "${config_file}" &>/dev/null
}

config_detect_warp_route_mode() {
  local config_file=$1

  if jq -e '(.route.final // "") == "warp-ep"' "${config_file}" &>/dev/null; then
    printf 'all'
    return 0
  fi

  if jq -e 'any(.route.rules[]?; (.outbound // "") == "warp-ep")' "${config_file}" &>/dev/null; then
    printf 'selective'
    return 0
  fi

  printf 'selective'
}

# Detect whether advanced route rules are enabled in either the current or legacy schema.
config_has_advanced_route() {
  local config_file=$1

  jq -e '
    any(
      .route.rules[]?;
      (.ip_is_private == true and .action == "reject") or
      (.geosite == "category-ads-all")
    )
  ' "${config_file}" &>/dev/null
}

load_current_config_state() {
  local first_protocol
  local installed_protocols=()

  migrate_legacy_single_protocol_state_if_needed

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_error "未找到配置文件，请先安装。"
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if config_has_advanced_route "${SINGBOX_CONFIG_FILE}"; then
      SB_ADVANCED_ROUTE="y"
    else
      SB_ADVANCED_ROUTE="n"
    fi

    if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
      SB_ENABLE_WARP="y"
    else
      SB_ENABLE_WARP="n"
    fi

    load_warp_route_settings
  fi

  load_stack_mode_state

  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    mapfile -t installed_protocols < <(list_installed_protocols)
    first_protocol="${installed_protocols[0]:-}"
    if [[ -n "${first_protocol}" ]]; then
      load_protocol_state "${first_protocol}"
      return 0
    fi
  fi

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]]; then
    log_error "未找到配置文件，请先安装。"
  fi

  SB_PROTOCOL=$(jq -r '.inbounds[0].type' "${SINGBOX_CONFIG_FILE}")
  case "${SB_PROTOCOL}" in
    vless) SB_PROTOCOL="vless+reality" ;;
    mixed) SB_PROTOCOL="mixed" ;;
    hysteria2) SB_PROTOCOL="hy2" ;;
    anytls) SB_PROTOCOL="anytls" ;;
    *) log_error "当前配置中的协议类型不受脚本支持: ${SB_PROTOCOL}" ;;
  esac

  SB_PORT=$(jq -r '.inbounds[0].listen_port' "${SINGBOX_CONFIG_FILE}")

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
    SB_UUID=$(jq -r '.inbounds[0].users[0].uuid' "${SINGBOX_CONFIG_FILE}")
    SB_SNI=$(jq -r '.inbounds[0].tls.server_name' "${SINGBOX_CONFIG_FILE}")
    SB_PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_1=$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_2=$(jq -r '.inbounds[0].tls.reality.short_id[1]' "${SINGBOX_CONFIG_FILE}")
    SB_MIXED_AUTH_ENABLED="y"
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
  elif [[ "${SB_PROTOCOL}" == "mixed" ]]; then
    SB_NODE_NAME="$(default_node_name_for_protocol "mixed")"
    SB_UUID=""
    SB_SNI=""
    SB_PRIVATE_KEY=""
    SB_SHORT_ID_1=""
    SB_SHORT_ID_2=""
    if jq -e '(.inbounds[0].users // []) | length > 0' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=$(jq -r '.inbounds[0].users[0].username // ""' "${SINGBOX_CONFIG_FILE}")
      SB_MIXED_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    else
      SB_MIXED_AUTH_ENABLED="n"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
    fi
  elif [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    SB_NODE_NAME="$(default_node_name_for_protocol "hy2")"
    SB_HY2_DOMAIN=$(jq -r '.inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_USER_NAME=$(jq -r '.inbounds[0].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_UP_MBPS=$(jq -r '.inbounds[0].up_mbps // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_DOWN_MBPS=$(jq -r '.inbounds[0].down_mbps // ""' "${SINGBOX_CONFIG_FILE}")
    if jq -e '.inbounds[0].obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_OBFS_ENABLED="y"
      SB_HY2_OBFS_TYPE="salamander"
      SB_HY2_OBFS_PASSWORD=$(jq -r '.inbounds[0].obfs.password // ""' "${SINGBOX_CONFIG_FILE}")
    else
      SB_HY2_OBFS_ENABLED="n"
      SB_HY2_OBFS_TYPE=""
      SB_HY2_OBFS_PASSWORD=""
    fi
    if jq -e '.inbounds[0].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_TLS_MODE="acme"
      SB_HY2_ACME_EMAIL=$(jq -r '.inbounds[0].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_ACME_DOMAIN=$(jq -r '.inbounds[0].tls.acme.domain[0] // .inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
      if jq -e '.inbounds[0].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        SB_HY2_ACME_MODE="dns"
        SB_HY2_DNS_PROVIDER=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_CF_API_TOKEN=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
      else
        SB_HY2_ACME_MODE="http"
        SB_HY2_DNS_PROVIDER="cloudflare"
        SB_HY2_CF_API_TOKEN=""
      fi
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
    elif jq -e '.inbounds[0].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_TLS_MODE="acme"
      cert_provider_tag=$(jq -r '.inbounds[0].tls.certificate_provider // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_ACME_EMAIL=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .email) // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_ACME_DOMAIN=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .domain[0]) // .inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
      if jq -e --arg tag "${cert_provider_tag}" 'any(.certificate_providers[]?; .tag == $tag and .dns01_challenge? != null)' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        SB_HY2_ACME_MODE="dns"
        SB_HY2_DNS_PROVIDER=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .dns01_challenge.provider) // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_CF_API_TOKEN=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .dns01_challenge.api_token) // ""' "${SINGBOX_CONFIG_FILE}")
      else
        SB_HY2_ACME_MODE="http"
        SB_HY2_DNS_PROVIDER="cloudflare"
        SB_HY2_CF_API_TOKEN=""
      fi
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
    else
      SB_HY2_TLS_MODE="manual"
      SB_HY2_ACME_MODE="http"
      SB_HY2_ACME_EMAIL=""
      SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
      SB_HY2_DNS_PROVIDER="cloudflare"
      SB_HY2_CF_API_TOKEN=""
      SB_HY2_CERT_PATH=$(jq -r '.inbounds[0].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_KEY_PATH=$(jq -r '.inbounds[0].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
    fi
    SB_HY2_MASQUERADE=$(jq -r '.inbounds[0].masquerade // ""' "${SINGBOX_CONFIG_FILE}")
    SB_ANYTLS_DOMAIN=""
    SB_ANYTLS_PASSWORD=""
    SB_ANYTLS_USER_NAME=""
  else
    SB_NODE_NAME="$(default_node_name_for_protocol "anytls")"
    SB_ANYTLS_DOMAIN=$(jq -r '.inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_ANYTLS_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    SB_ANYTLS_USER_NAME=$(jq -r '.inbounds[0].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
    if jq -e '.inbounds[0].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_ANYTLS_TLS_MODE="acme"
      SB_ANYTLS_ACME_EMAIL=$(jq -r '.inbounds[0].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
      SB_ANYTLS_ACME_DOMAIN=$(jq -r '.inbounds[0].tls.acme.domain[0] // .inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
      if jq -e '.inbounds[0].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        SB_ANYTLS_ACME_MODE="dns"
        SB_ANYTLS_DNS_PROVIDER=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_CF_API_TOKEN=$(jq -r '.inbounds[0].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
      else
        SB_ANYTLS_ACME_MODE="http"
        SB_ANYTLS_DNS_PROVIDER="cloudflare"
        SB_ANYTLS_CF_API_TOKEN=""
      fi
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
    else
      SB_ANYTLS_TLS_MODE="manual"
      SB_ANYTLS_ACME_MODE="http"
      SB_ANYTLS_ACME_EMAIL=""
      SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
      SB_ANYTLS_DNS_PROVIDER="cloudflare"
      SB_ANYTLS_CF_API_TOKEN=""
      SB_ANYTLS_CERT_PATH=$(jq -r '.inbounds[0].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
      SB_ANYTLS_KEY_PATH=$(jq -r '.inbounds[0].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
    fi
  fi

  if [[ "${SB_PROTOCOL}" == "vless+reality" && -f "${SB_KEY_FILE}" ]]; then
    SB_PUBLIC_KEY=$(grep "PUBLIC_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  elif [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    SB_PUBLIC_KEY="[密钥丢失，请更新配置]"
  else
    SB_PUBLIC_KEY=""
  fi
}

# Cloudflare Warp Management
warp_management() {
  local apply_change should_reload status warp_was_enabled

  while true; do
    apply_change="n"
    should_reload="n"

    load_current_config_state
    ensure_warp_routing_assets
    warp_was_enabled="${SB_ENABLE_WARP}"

    if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
      status="${GREEN}已开启${NC}"
    else
      status="${YELLOW}未开启${NC}"
    fi

    echo
    render_left_aligned_page_header "Cloudflare Warp 管理" "调整 Warp 出口与分流资产"
    render_section_title "Warp 摘要"
    render_summary_item "当前状态" "${status}"
    render_summary_item "当前路由模式" "${SB_WARP_ROUTE_MODE}"
    render_summary_item "域名列表文件" "${SB_WARP_DOMAINS_FILE}"
    render_section_title "操作选项"
    render_menu_item "1" "开启 Warp"
    render_menu_item "2" "关闭 Warp"
    render_menu_item "3" "重新注册 Warp 账户" "(获取新密钥和 IP)"
    render_menu_item "4" "切换 Warp 路由模式"
    render_menu_item "5" "添加自定义 Warp 域名"
    render_menu_item "6" "添加远程 Warp 规则集"
    render_menu_item "7" "查看 Warp 分流文件路径"
    render_menu_item "8" "查看当前生效的 Warp 分流来源"
    render_menu_item "9" "导入推荐 Warp 规则源"
    echo "0. 返回主菜单"
    read -rp "请选择 [0-9]: " w_choice

    case "${w_choice}" in
      1)
        SB_ENABLE_WARP="y"
        log_info "正在开启 Warp..."
        apply_change="y"
        should_reload="y"
        ;;
      2)
        SB_ENABLE_WARP="n"
        log_info "正在关闭 Warp..."
        apply_change="y"
        should_reload="y"
        ;;
      3)
        rm -f "${SB_WARP_KEY_FILE}"
        SB_ENABLE_WARP="y"
        log_info "正在重新注册 Warp..."
        apply_change="y"
        should_reload="y"
        ;;
      4)
        if set_warp_route_mode_interactive; then
          log_success "Warp 路由模式已更新为: ${SB_WARP_ROUTE_MODE}"
          apply_change="y"
          [[ "${warp_was_enabled}" == "y" || "${SB_ENABLE_WARP}" == "y" ]] && should_reload="y"
        fi
        ;;
      5)
        if add_warp_domain_entry; then
          apply_change="y"
          [[ "${warp_was_enabled}" == "y" || "${SB_ENABLE_WARP}" == "y" ]] && should_reload="y"
        fi
        ;;
      6)
        if add_remote_warp_rule_set; then
          apply_change="y"
          [[ "${warp_was_enabled}" == "y" || "${SB_ENABLE_WARP}" == "y" ]] && should_reload="y"
        fi
        ;;
      7)
        show_warp_route_assets
        continue
        ;;
      8)
        show_effective_warp_route_sources
        continue
        ;;
      9)
        if import_recommended_warp_rule_sets; then
          apply_change="y"
          [[ "${warp_was_enabled}" == "y" || "${SB_ENABLE_WARP}" == "y" ]] && should_reload="y"
        fi
        ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。"; continue ;;
    esac

    if [[ "${apply_change}" == "n" ]]; then
      continue
    fi

    save_warp_route_settings

    if [[ "${should_reload}" != "y" ]]; then
      log_success "Warp 分流资产已更新，待下次开启 Warp 或重载配置时生效。"
      continue
    fi

    generate_config
    check_config_valid
    setup_service
    systemctl restart sing-box
    log_success "Warp 配置已更新并重启服务。"

    load_current_config_state
    display_status_summary
    log_info "连接信息未自动展示，如需查看请进入菜单 10。"
  done
}

# Helper to extract config values and display info
view_status() {
  log_info "正在从配置文件中读取信息..."
  load_current_config_state
  display_status_summary
}

# New function: Update config only
update_config_only() {
  local selected_protocol

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_error "未找到配置文件或协议状态，请先执行安装流程。"
  fi

  migrate_legacy_single_protocol_state_if_needed

  log_info "正在读取当前配置..."
  load_current_config_state

  echo -e "\n${BLUE}--- 进入配置修改模式 ---${NC}"
  SELECTED_PROTOCOL=""
  if ! prompt_installed_protocol_selection; then
    return 0
  fi
  selected_protocol="${SELECTED_PROTOCOL}"

  load_protocol_state "${selected_protocol}"
  echo -e "当前正在修改: $(protocol_display_name "${SB_PROTOCOL}")"
  prompt_protocol_update_fields "${selected_protocol}"
  save_protocol_state "${selected_protocol}"

  generate_config
  check_config_valid
  setup_service
  open_all_protocol_ports
  load_protocol_state "${selected_protocol}"
  systemctl restart sing-box
  log_success "配置及服务文件已更新并重启服务。"
  display_status_summary
  log_info "连接信息未自动展示，如需查看请进入菜单 10。"
}

get_public_ip() {
  get_public_ipv4 || get_public_ipv6
}

get_public_ipv4() {
  curl -4 -s https://api.ip.sb/ip 2>/dev/null || curl -4 -s https://ifconfig.me 2>/dev/null || true
}

get_public_ipv6() {
  curl -6 -s https://api.ip.sb/ip 2>/dev/null || curl -6 -s https://ifconfig.me 2>/dev/null || true
}

normalize_ip_list() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | sed '/^$/d' | sort -u
}

get_public_ip_candidates() {
  local ipv4_address ipv6_address

  ipv4_address=$(get_public_ipv4 || true)
  ipv6_address=$(get_public_ipv6 || true)

  {
    printf '%s\n' "${ipv4_address}"
    printf '%s\n' "${ipv6_address}"
  } | normalize_ip_list
}

resolve_domain_ip_candidates() {
  local domain=$1
  local resolved_any="n"

  if command -v getent >/dev/null 2>&1; then
    getent ahosts "${domain}" 2>/dev/null | awk '{print $1}' | normalize_ip_list || true
    resolved_any="y"
  fi

  if command -v dig >/dev/null 2>&1; then
    {
      dig +short A "${domain}" 2>/dev/null || true
      dig +short AAAA "${domain}" 2>/dev/null || true
    } | normalize_ip_list
    resolved_any="y"
  fi

  if [[ "${resolved_any}" == "n" ]] && command -v nslookup >/dev/null 2>&1; then
    nslookup "${domain}" 2>/dev/null | awk '/^Address: / {print $2}' | normalize_ip_list || true
  fi
}

ip_lists_have_match() {
  local public_ips=$1
  local domain_ips=$2
  local public_ip domain_ip

  while IFS= read -r public_ip; do
    [[ -z "${public_ip}" ]] && continue
    while IFS= read -r domain_ip; do
      [[ -z "${domain_ip}" ]] && continue
      [[ "${public_ip}" == "${domain_ip}" ]] && return 0
    done <<< "${domain_ips}"
  done <<< "${public_ips}"

  return 1
}

confirm_domain_ip_mismatch() {
  local protocol_name=$1
  local domain=$2
  local public_ips=$3
  local domain_ips=$4
  local answer

  log_warn "${protocol_name} 域名解析结果与本机公网出口 IP 不匹配。"
  echo "域名: ${domain}"
  echo "本机公网出口 IP:"
  if [[ -n "${public_ips}" ]]; then
    printf '  - %s\n' ${public_ips}
  else
    echo "  - 未获取到"
  fi
  echo "域名解析 IP:"
  if [[ -n "${domain_ips}" ]]; then
    printf '  - %s\n' ${domain_ips}
  else
    echo "  - 未解析到"
  fi
  log_warn "如果继续，ACME HTTP-01 签发或客户端连接可能失败。CDN、反代、DNS-01 或手动证书场景可确认继续。"
  read -rp "仍要继续使用该域名吗？[y/N]: " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

validate_tls_domain_points_to_server() {
  local protocol_name=$1
  local domain=$2
  local public_ips domain_ips

  public_ips=$(get_public_ip_candidates | normalize_ip_list || true)
  domain_ips=$(resolve_domain_ip_candidates "${domain}" | normalize_ip_list || true)

  if [[ -n "${public_ips}" && -n "${domain_ips}" ]] && ip_lists_have_match "${public_ips}" "${domain_ips}"; then
    return 0
  fi

  confirm_domain_ip_mismatch "${protocol_name}" "${domain}" "${public_ips}" "${domain_ips}"
}

format_share_host() {
  local host=$1

  if [[ "${host}" == *:* && "${host}" != \[*\] ]]; then
    printf '[%s]' "${host}"
  else
    printf '%s' "${host}"
  fi
}

build_vless_link() {
  local public_ip=$1
  local share_host
  share_host=$(format_share_host "${public_ip}")

  printf 'vless://%s@%s:%s?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&flow=xtls-rprx-vision#%s' \
    "${SB_UUID}" "${share_host}" "${SB_PORT}" "${SB_SNI}" "${SB_PUBLIC_KEY:-[密钥丢失，请更新配置]}" "${SB_SHORT_ID_1}" "${SB_NODE_NAME}"
}

build_mixed_http_link() {
  local public_ip=$1
  local share_host
  share_host=$(format_share_host "${public_ip}")

  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    printf 'http://%s:%s@%s:%s' "${SB_MIXED_USERNAME}" "${SB_MIXED_PASSWORD}" "${share_host}" "${SB_PORT}"
  else
    printf 'http://%s:%s' "${share_host}" "${SB_PORT}"
  fi
}

build_mixed_socks5_link() {
  local public_ip=$1
  local share_host
  share_host=$(format_share_host "${public_ip}")

  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    printf 'socks5://%s:%s@%s:%s' "${SB_MIXED_USERNAME}" "${SB_MIXED_PASSWORD}" "${share_host}" "${SB_PORT}"
  else
    printf 'socks5://%s:%s' "${share_host}" "${SB_PORT}"
  fi
}

build_hy2_link() {
  local public_ip=$1
  local server_host query
  server_host=${SB_HY2_DOMAIN:-${public_ip}}
  query="sni=${SB_HY2_DOMAIN:-${server_host}}"

  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    query="${query}&obfs=${SB_HY2_OBFS_TYPE:-salamander}&obfs-password=${SB_HY2_OBFS_PASSWORD}"
  fi

  printf 'hy2://%s@%s:%s?%s#%s' \
    "${SB_HY2_PASSWORD}" \
    "$(format_share_host "${server_host}")" \
    "${SB_PORT}" \
    "${query}" \
    "${SB_NODE_NAME}"
}

subman_node_prefix() {
  local prefix
  prefix=$(trim_whitespace "${SUBMAN_NODE_PREFIX:-}")
  [[ -z "${prefix}" ]] && prefix=$(hostname)
  printf '%s' "${prefix}"
}

subman_type_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) printf 'vless' ;;
    hy2) printf 'hysteria2' ;;
    *) return 1 ;;
  esac
}

subman_external_key_for_protocol() {
  local protocol prefix
  protocol=$(normalize_protocol_id "$1")
  prefix=$(subman_node_prefix)
  printf 'sing-box-vps:%s:%s' "${prefix}" "${protocol}"
}

build_subman_raw_for_protocol() {
  local protocol public_ip
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2

  case "${protocol}" in
    vless-reality) build_vless_link "${public_ip}" ;;
    hy2) build_hy2_link "${public_ip}" ;;
    *) return 1 ;;
  esac
}

build_subman_node_payload() {
  local protocol public_ip node_type raw_link node_name prefix
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2
  node_type=$(subman_type_for_protocol "${protocol}") || return 1
  raw_link=$(build_subman_raw_for_protocol "${protocol}" "${public_ip}") || return 1
  prefix=$(subman_node_prefix)
  node_name=$(trim_whitespace "${SB_NODE_NAME:-}")
  [[ -z "${node_name}" ]] && node_name="${prefix} ${protocol}"

  jq -n \
    --arg name "${node_name}" \
    --arg type "${node_type}" \
    --arg raw "${raw_link}" \
    --arg prefix "${prefix}" \
    '{
      "name": $name,
      "type": $type,
      "raw": $raw,
      "enabled": true,
      "tags": ["sing-box-vps", $prefix],
      "source": "single"
    }'
}

push_subman_node() {
  local external_key=$1
  local payload_json=$2
  local api_url encoded_key response http_status response_body endpoint config_file tmp_dir
  local escaped_token

  api_url=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  if [[ -z "${api_url}" ]]; then
    print_warn "SubMan API 地址为空，无法推送节点。"
    return 1
  fi
  if [[ -z "${SUBMAN_API_TOKEN:-}" ]]; then
    print_warn "SubMan API Token 为空，无法推送节点。"
    return 1
  fi

  encoded_key=$(jq -rn --arg value "${external_key}" '$value | @uri')
  endpoint="${api_url}/api/nodes/by-key/${encoded_key}"
  tmp_dir=${TMPDIR:-/tmp}
  if ! config_file=$(mktemp "${tmp_dir%/}/subman-curl.XXXXXX"); then
    print_warn "SubMan 节点推送失败: 无法创建临时 curl 配置。"
    return 1
  fi
  if ! chmod 600 "${config_file}"; then
    rm -f "${config_file}"
    print_warn "SubMan 节点推送失败: 无法保护临时 curl 配置。"
    return 1
  fi
  escaped_token=${SUBMAN_API_TOKEN//\\/\\\\}
  escaped_token=${escaped_token//\"/\\\"}
  if ! {
    printf 'header = "Authorization: Bearer %s"\n' "${escaped_token}"
    printf 'header = "Content-Type: application/json"\n'
  } > "${config_file}"; then
    rm -f "${config_file}"
    print_warn "SubMan 节点推送失败: 无法写入临时 curl 配置。"
    return 1
  fi

  if ! response=$(curl -sS --config "${config_file}" -X PUT "${endpoint}" \
    --data "${payload_json}" \
    -w 'HTTP_STATUS:%{http_code}' 2>&1); then
    rm -f "${config_file}"
    response=${response//${SUBMAN_API_TOKEN}/[REDACTED]}
    print_warn "SubMan 节点推送失败: curl 请求异常。"
    [[ -n "${response}" ]] && printf '%s\n' "${response}"
    return 1
  fi
  rm -f "${config_file}"

  http_status=${response##*HTTP_STATUS:}
  response_body=${response%"HTTP_STATUS:${http_status}"}
  response_body=${response_body//${SUBMAN_API_TOKEN}/[REDACTED]}

  if [[ ! "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
    print_warn "SubMan 节点推送失败: HTTP ${http_status}"
    [[ -n "${response_body}" ]] && printf '%s\n' "${response_body}"
    return 1
  fi

  print_success "SubMan 节点推送成功: HTTP ${http_status}"
  [[ -n "${response_body}" ]] && printf '%s\n' "${response_body}"
}

build_anytls_outbound_example() {
  local public_ip=$1
  local server_host
  server_host=${SB_ANYTLS_DOMAIN:-${public_ip}}

  jq -n \
    --arg server "${server_host}" \
    --arg port "${SB_PORT}" \
    --arg password "${SB_ANYTLS_PASSWORD}" \
    --arg sni "${SB_ANYTLS_DOMAIN:-${server_host}}" \
    '{
      "type": "anytls",
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $password,
      "tls": {
        "enabled": true,
        "server_name": $sni
      }
    }'
}

client_outbound_tag_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1")
  if [[ -n "${SB_NODE_NAME:-}" ]]; then
    printf '%s' "${SB_NODE_NAME}"
    return 0
  fi

  printf '%s' "$(default_node_name_for_protocol "$(state_protocol_to_runtime "${protocol}")")"
}

build_client_vless_reality_outbound() {
  local public_ip=${1:-$(get_public_ip)}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "vless-reality")" \
    --arg server "${public_ip}" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg server_name "${SB_SNI}" \
    --arg public_key "${SB_PUBLIC_KEY}" \
    --arg short_id "${SB_SHORT_ID_1}" \
    '{
      "type": "vless",
      "tag": $tag,
      "server": $server,
      "server_port": ($port | tonumber),
      "uuid": $uuid,
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": $server_name,
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": $public_key,
          "short_id": $short_id
        }
      }
    }'
}

build_client_hy2_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local server_host tls_server_name
  server_host=${public_ip}
  tls_server_name=${SB_HY2_DOMAIN:-${public_ip}}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "hy2")" \
    --arg server "${server_host}" \
    --arg port "${SB_PORT}" \
    --arg password "${SB_HY2_PASSWORD}" \
    --arg server_name "${tls_server_name}" \
    --arg up_mbps "${SB_HY2_UP_MBPS}" \
    --arg down_mbps "${SB_HY2_DOWN_MBPS}" \
    --arg obfs_enabled "${SB_HY2_OBFS_ENABLED}" \
    --arg obfs_type "${SB_HY2_OBFS_TYPE}" \
    --arg obfs_password "${SB_HY2_OBFS_PASSWORD}" \
    '{
      "type": "hysteria2",
      "tag": $tag,
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $password,
      "tls": {
        "enabled": true,
        "server_name": $server_name
      }
    } + (
      if ($up_mbps | length) > 0 then
        { "up_mbps": ($up_mbps | tonumber) }
      else
        {}
      end
    ) + (
      if ($down_mbps | length) > 0 then
        { "down_mbps": ($down_mbps | tonumber) }
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
    )'
}

build_client_anytls_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local server_host
  server_host=${SB_ANYTLS_DOMAIN:-${public_ip}}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "anytls")" \
    --arg server "${server_host}" \
    --arg port "${SB_PORT}" \
    --arg password "${SB_ANYTLS_PASSWORD}" \
    --arg server_name "${SB_ANYTLS_DOMAIN:-${server_host}}" \
    '{
      "type": "anytls",
      "tag": $tag,
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $password,
      "tls": {
        "enabled": true,
        "server_name": $server_name
      }
    }'
}

build_client_outbound_json_for_protocol() {
  local protocol original_protocol_state outbound_json build_status restore_original_state
  protocol=$(normalize_protocol_id "$1")
  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  build_status=0
  restore_original_state="n"

  case "${protocol}" in
    vless-reality|hy2|anytls) ;;
    *)
      log_error "不支持的客户端导出协议: ${protocol}"
      ;;
  esac

  if [[ -n "${original_protocol_state}" && "${original_protocol_state}" != "${protocol}" ]] && protocol_state_exists "${original_protocol_state}"; then
    restore_original_state="y"
  fi

  load_protocol_state "${protocol}"

  case "${protocol}" in
    vless-reality)
      if outbound_json=$(build_client_vless_reality_outbound); then
        :
      else
        build_status=$?
      fi
      ;;
    hy2)
      if outbound_json=$(build_client_hy2_outbound); then
        :
      else
        build_status=$?
      fi
      ;;
    anytls)
      if outbound_json=$(build_client_anytls_outbound); then
        :
      else
        build_status=$?
      fi
      ;;
  esac

  if [[ "${restore_original_state}" == "y" ]]; then
    load_protocol_state "${original_protocol_state}"
  fi

  if (( build_status != 0 )); then
    return "${build_status}"
  fi

  printf '%s\n' "${outbound_json}"
}

show_hy2_connection_summary() {
  echo -e "\n${YELLOW}Hysteria2 参数摘要：${NC}"
  echo "域名: ${SB_HY2_DOMAIN}"
  echo "端口: ${SB_PORT}"
  echo "TLS 模式: ${SB_HY2_TLS_MODE}"
  echo "伪装: ${SB_HY2_MASQUERADE:-未配置}"
  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    echo "混淆: ${SB_HY2_OBFS_TYPE:-salamander}"
  else
    echo "混淆: 未启用"
  fi
  if [[ -n "${SB_HY2_UP_MBPS}" && -n "${SB_HY2_DOWN_MBPS}" ]]; then
    echo "带宽: ${SB_HY2_UP_MBPS} / ${SB_HY2_DOWN_MBPS} Mbps"
  else
    echo "带宽: 不限制（由客户端协商）"
  fi
}

show_anytls_connection_summary() {
  echo -e "\n${YELLOW}AnyTLS 参数摘要：${NC}"
  echo "域名: ${SB_ANYTLS_DOMAIN}"
  echo "端口: ${SB_PORT}"
  echo "用户名标识: ${SB_ANYTLS_USER_NAME}"
  echo "TLS 模式: ${SB_ANYTLS_TLS_MODE}"
}

display_status_summary() {
  local public_ip protocol_name
  public_ip=${1:-$(get_public_ip)}
  protocol_name=$(protocol_display_name "${SB_PROTOCOL}")

  echo -e "\n${GREEN}服务状态摘要：${NC}"
  echo "-------------------------------------------------------------"
  echo -e "进程状态: $(systemctl is-active sing-box)"
  echo -e "协议: ${protocol_name}"
  echo -e "地址: ${public_ip}"
  echo -e "端口: ${SB_PORT}"
  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    echo -e "Warp: 已开启 (${SB_WARP_ROUTE_MODE})"
  else
    echo -e "Warp: 未开启"
  fi
  echo -e "配置文件: ${SINGBOX_CONFIG_FILE}"
  echo "-------------------------------------------------------------"
}

show_link_info() {
  local public_ip=$1

  echo -e "\n${YELLOW}连接链接：${NC}"
  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    echo "1. REALITY 协议链接"
    build_vless_link "${public_ip}"
    echo ""
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    echo "1. Hysteria2 协议链接"
    build_hy2_link "${public_ip}"
    echo ""
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "anytls" ]]; then
    echo "1. AnyTLS 客户端 outbound JSON 示例"
    build_anytls_outbound_example "${public_ip}"
    echo ""
    return 0
  fi

  echo "1. Mixed HTTP 代理链接"
  build_mixed_http_link "${public_ip}"
  echo ""
  echo "2. Mixed SOCKS5 代理链接"
  build_mixed_socks5_link "${public_ip}"
  echo ""
  if [[ "${SB_MIXED_AUTH_ENABLED}" != "y" ]]; then
    log_warn "当前 Mixed 代理未启用认证，请尽快确认防火墙限制或开启认证。"
  fi
}

show_qr_info() {
  local public_ip=$1

  echo -e "\n${YELLOW}连接二维码：${NC}"
  if [[ "${SB_PROTOCOL}" == "mixed" ]]; then
    log_info "Mixed 协议当前不提供二维码，请使用链接方式手动配置客户端。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "anytls" ]]; then
    log_info "AnyTLS 当前不展示二维码，请使用参数摘要与 outbound JSON 示例手动导入客户端。"
    return 0
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    log_warn "未安装 qrencode，已跳过二维码展示。可安装后重新进入菜单 10 查看。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    echo "1. Hysteria2 协议二维码"
    qrencode -t ansiutf8 "$(build_hy2_link "${public_ip}")"
    return 0
  fi

  echo "1. REALITY 协议二维码"
  qrencode -t ansiutf8 "$(build_vless_link "${public_ip}")"
}

show_connection_details() {
  local mode=$1
  local public_ip=${2:-$(get_public_ip)}

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    show_hy2_connection_summary
  elif [[ "${SB_PROTOCOL}" == "anytls" ]]; then
    show_anytls_connection_summary
  fi

  case "${mode}" in
    link)
      show_link_info "${public_ip}"
      ;;
    qr)
      show_qr_info "${public_ip}"
      ;;
    both)
      show_link_info "${public_ip}"
      show_qr_info "${public_ip}"
      ;;
    *)
      log_warn "未知的连接信息展示模式: ${mode}"
      return 1
      ;;
  esac
}

list_public_addresses_for_current_stack() {
  local ipv4_address ipv6_address fallback_address

  ensure_stack_mode_state_loaded

  case "${SB_INBOUND_STACK_MODE}" in
    ipv4_only)
      ipv4_address=$(get_public_ipv4)
      [[ -n "${ipv4_address}" ]] && printf 'IPv4 地址|%s\n' "${ipv4_address}"
      ;;
    ipv6_only)
      ipv6_address=$(get_public_ipv6)
      [[ -n "${ipv6_address}" ]] && printf 'IPv6 地址|%s\n' "${ipv6_address}"
      ;;
    *)
      ipv4_address=$(get_public_ipv4)
      ipv6_address=$(get_public_ipv6)
      [[ -n "${ipv4_address}" ]] && printf 'IPv4 地址|%s\n' "${ipv4_address}"
      [[ -n "${ipv6_address}" ]] && printf 'IPv6 地址|%s\n' "${ipv6_address}"
      ;;
  esac

  if [[ -z "${ipv4_address:-}" && -z "${ipv6_address:-}" ]]; then
    fallback_address=$(get_public_ip)
    [[ -n "${fallback_address}" ]] && printf '地址|%s\n' "${fallback_address}"
  fi
}

show_connection_details_for_detected_addresses() {
  local mode=$1
  local address_entries=()
  local entry label address

  mapfile -t address_entries < <(list_public_addresses_for_current_stack)

  if [[ ${#address_entries[@]} -eq 0 ]]; then
    show_connection_details "${mode}"
    return 0
  fi

  for entry in "${address_entries[@]}"; do
    label=${entry%%|*}
    address=${entry#*|}
    echo -e "\n${BLUE}${label}:${NC} ${address}"
    show_connection_details "${mode}" "${address}"
  done
}

show_all_connection_details() {
  local mode=$1
  local installed_protocols=()
  local protocol original_protocol_state

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  mapfile -t installed_protocols < <(list_installed_protocols)

  if [[ ${#installed_protocols[@]} -eq 0 ]]; then
    show_connection_details_for_detected_addresses "${mode}"
    return 0
  fi

  for protocol in "${installed_protocols[@]}"; do
    load_protocol_state "${protocol}"
    echo -e "\n${BLUE}--- $(protocol_display_name "${SB_PROTOCOL}") ---${NC}"
    show_connection_details_for_detected_addresses "${mode}"
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi
}

show_connection_info_menu() {
  local public_ip
  public_ip=$(get_public_ip)

  while true; do
    echo
    render_left_aligned_page_header "节点信息查看" "按当前配置展示客户端连接信息"
    render_section_title "信息摘要"
    render_summary_item "当前协议" "$(protocol_display_name "${SB_PROTOCOL}")"
    render_summary_item "当前端口" "${SB_PORT}"
    render_summary_item "当前出口地址" "${public_ip:-未检测到}"
    render_menu_group_start "展示方式"
    render_menu_item "1" "仅链接"
    render_menu_item "2" "仅二维码"
    render_menu_item "3" "链接 + 二维码"
    echo "0. 返回"
    read -rp "请选择 [0-3]: " info_choice

    case "${info_choice}" in
      1) show_all_connection_details "link" "${public_ip}" ;;
      2) show_all_connection_details "qr" "${public_ip}" ;;
      3) show_all_connection_details "both" "${public_ip}" ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

client_export_file_path() {
  printf '%s/client/sing-box-client.json' "${SB_PROJECT_DIR}"
}

build_singbox_client_config() {
  local original_protocol_state clash_api_secret public_ip tmpdir
  local installed_protocols=() exportable_protocols=()
  local remote_outbounds_json remote_tags_json
  local protocol outbound_json usable_protocol_count
  local status=0

  mapfile -t installed_protocols < <(list_installed_protocols)
  mapfile -t exportable_protocols < <(list_exportable_client_protocols)
  if [[ ${#exportable_protocols[@]} -eq 0 ]]; then
    if [[ ${#installed_protocols[@]} -gt 0 ]]; then
      log_warn "当前无可导出的 sing-box 裸核客户端节点；已安装协议中仅 vless-reality、hy2、anytls 支持导出，mixed 不支持导出。" >&2
    else
      log_warn "当前无可导出的 sing-box 裸核客户端节点；请先安装 vless-reality、hy2 或 anytls 后再导出。" >&2
    fi
    return 1
  fi

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  clash_api_secret=$(generate_random_token "clash-" 16)
  public_ip=$(get_public_ip)
  tmpdir=$(mktemp -d)
  usable_protocol_count=0
  trap '
    if [[ -n "${original_protocol_state:-}" ]] && protocol_state_exists "${original_protocol_state}"; then
      load_protocol_state "${original_protocol_state}"
    fi
    rm -rf "${tmpdir:-}"
  ' RETURN

  for protocol in "${exportable_protocols[@]}"; do
    if ! protocol_state_exists "${protocol}"; then
      log_warn "协议状态文件缺失，已跳过客户端导出协议: ${protocol}" >&2
      continue
    fi

    if ! outbound_json=$(build_client_outbound_json_for_protocol "${protocol}" "${public_ip}"); then
      log_warn "生成客户端导出协议失败，已跳过: ${protocol}" >&2
      continue
    fi

    printf '%s\n' "${outbound_json}" >> "${tmpdir}/outbounds.jsonl"
    printf '%s\n' "$(jq -r '.tag' <<< "${outbound_json}")" >> "${tmpdir}/tags.txt"
    usable_protocol_count=$((usable_protocol_count + 1))
  done

  if (( usable_protocol_count == 0 )); then
    log_warn "未找到可用的远程协议可供导出，请检查协议状态文件是否完整。" >&2
    status=1
  else
    remote_outbounds_json=$(jq -s '.' "${tmpdir}/outbounds.jsonl")
    remote_tags_json=$(jq -Rsc 'split("\n") | map(select(length > 0))' "${tmpdir}/tags.txt")

    jq -n \
      --argjson remote_outbounds "${remote_outbounds_json}" \
      --argjson remote_tags "${remote_tags_json}" \
      --arg clash_api_secret "${clash_api_secret}" \
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
          "rules": [
            {
              "rule_set": "geosite-cn",
              "server": "cn-dns"
            },
            {
              "rule_set": "geosite-geolocation-!cn",
              "server": "remote-dns"
            }
          ],
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
          "rule_set": [
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
          ],
          "rules": [
            {
              "action": "sniff"
            },
            {
              "protocol": "dns",
              "action": "hijack-dns"
            },
            {
              "ip_is_private": true,
              "action": "route",
              "outbound": "direct"
            },
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
          ],
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
    load_protocol_state "${original_protocol_state}"
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

  if ! "${SINGBOX_BIN_PATH}" check -c "${tmp_file}"; then
    rm -f "${tmp_file}"
    return 1
  fi

  rm -f "${tmp_file}"
}

export_singbox_client_config() {
  local config_json export_path

  if ! config_json=$(build_singbox_client_config); then
    log_warn "导出 sing-box 裸核客户端配置失败。" >&2
    return 1
  fi

  if ! validate_client_config_json "${config_json}"; then
    log_warn "导出的 sing-box 裸核客户端配置未通过 sing-box check 校验。" >&2
    return 1
  fi

  export_path=$(client_export_file_path)
  if ! write_client_config_export "${config_json}"; then
    log_warn "写入客户端配置文件失败: ${export_path}" >&2
    return 1
  fi

  print_success "sing-box 裸核客户端配置导出成功。"
  printf '文件路径: %s\n' "${export_path}"
  printf 'WSL2 使用方式: 请将应用代理手动指向 127.0.0.1:2080\n'
  printf '系统代理: 未启用（set_system_proxy=false）\n'
  printf 'Clash API 地址: 127.0.0.1:9090\n'
  printf '%s\n' "${config_json}"
}

push_nodes_to_subman() {
  local public_ip original_protocol_state protocol external_key payload_json
  local synced_count skipped_count failed_count
  local installed_protocols=()

  prompt_subman_config_if_needed
  public_ip=$(get_public_ip)
  if [[ -z "${public_ip}" ]]; then
    log_warn "未获取到公网 IP，无法生成 SubMan 节点链接。"
    return 1
  fi
  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  synced_count=0
  skipped_count=0
  failed_count=0

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

    if ! external_key=$(subman_external_key_for_protocol "${protocol}"); then
      print_warn "生成 SubMan 外部键失败: ${protocol}"
      failed_count=$((failed_count + 1))
      continue
    fi

    if ! payload_json=$(build_subman_node_payload "${protocol}" "${public_ip}"); then
      print_warn "生成 SubMan 节点载荷失败: ${protocol}"
      failed_count=$((failed_count + 1))
      continue
    fi

    if push_subman_node "${external_key}" "${payload_json}"; then
      synced_count=$((synced_count + 1))
    else
      failed_count=$((failed_count + 1))
    fi
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi

  printf 'SubMan 推送完成：已同步: %s，已跳过: %s，失败: %s\n' "${synced_count}" "${skipped_count}" "${failed_count}"

  if (( synced_count == 0 || failed_count > 0 )); then
    return 1
  fi
}

show_node_info_action_menu() {
  while true; do
    echo
    render_left_aligned_page_header "节点信息查看" "选择要执行的节点信息操作"
    render_menu_group_start "操作选项"
    render_menu_item "1" "查看连接链接 / 二维码"
    render_menu_item "2" "导出 sing-box 裸核客户端配置"
    render_menu_item "3" "推送节点到 SubMan"
    echo "0. 返回"
    read -rp "请选择 [0-3]: " node_info_choice

    case "${node_info_choice}" in
      1) show_connection_info_menu ;;
      2) export_singbox_client_config || true ;;
      3) push_nodes_to_subman || true ;;
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

list_config_protocols() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 0

  local protocols=()
  local inbound_count inbound_index inbound_type protocol

  inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}")
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 0

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // empty' "${SINGBOX_CONFIG_FILE}")
    protocol=$(normalize_protocol_id "${inbound_type}" 2>/dev/null || true)
    [[ -n "${protocol}" ]] || continue

    if ! protocol_array_contains "${protocol}" "${protocols[@]}"; then
      protocols+=("${protocol}")
    fi
  done

  printf '%s\n' "${protocols[@]}"
}

find_config_inbound_index_by_protocol() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 1

  local target_protocol inbound_count inbound_index inbound_type protocol
  target_protocol=$(normalize_protocol_id "$1")

  inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}")
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // empty' "${SINGBOX_CONFIG_FILE}")
    protocol=$(normalize_protocol_id "${inbound_type}" 2>/dev/null || true)
    if [[ "${protocol}" == "${target_protocol}" ]]; then
      printf '%s' "${inbound_index}"
      return 0
    fi
  done

  return 1
}

render_expected_protocol_state_snapshot() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 1

  local protocol inbound_index cert_provider_tag
  protocol=$(normalize_protocol_id "$1")
  inbound_index=$(find_config_inbound_index_by_protocol "${protocol}") || return 1

  case "${protocol}" in
    vless-reality)
      printf 'PORT=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")"
      printf 'UUID=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].uuid // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'SNI=%s\n' "$(jq -r --argjson idx "${inbound_index}" --arg fallback "${SB_REALITY_SNI_FALLBACK}" '.inbounds[$idx].tls.server_name // $fallback' "${SINGBOX_CONFIG_FILE}")"
      printf 'REALITY_PRIVATE_KEY=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.private_key // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'SHORT_ID_1=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[0] // ""' "${SINGBOX_CONFIG_FILE}")"
      printf 'SHORT_ID_2=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[1] // ""' "${SINGBOX_CONFIG_FILE}")"
      ;;
    mixed)
      printf 'PORT=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "1080"' "${SINGBOX_CONFIG_FILE}")"
      if jq -e --argjson idx "${inbound_index}" '(.inbounds[$idx].users // []) | length > 0' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
        printf 'AUTH_ENABLED=y\n'
        printf 'USERNAME=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].username // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'PASSWORD=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")"
      else
        printf 'AUTH_ENABLED=n\n'
        printf 'USERNAME=\n'
        printf 'PASSWORD=\n'
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
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'DNS_PROVIDER=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")"
          printf 'CF_API_TOKEN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")"
        else
          printf 'DNS_PROVIDER=cloudflare\n'
          printf 'CF_API_TOKEN=\n'
        fi
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      elif cert_provider_tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider // ""' "${SINGBOX_CONFIG_FILE}"); [[ -n "${cert_provider_tag}" ]]; then
        printf 'TLS_MODE=acme\n'
        if jq -e --arg tag "${cert_provider_tag}" 'any(.certificate_providers[]?; .tag == $tag and .dns01_challenge? != null)' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'ACME_MODE=dns\n'
        else
          printf 'ACME_MODE=http\n'
        fi
        printf 'ACME_EMAIL=%s\n' "$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .email) // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .domain[0]) // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
        if jq -e --arg tag "${cert_provider_tag}" 'any(.certificate_providers[]?; .tag == $tag and .dns01_challenge? != null)' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'DNS_PROVIDER=%s\n' "$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .dns01_challenge.provider) // "cloudflare"' "${SINGBOX_CONFIG_FILE}")"
          printf 'CF_API_TOKEN=%s\n' "$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .dns01_challenge.api_token) // ""' "${SINGBOX_CONFIG_FILE}")"
        else
          printf 'DNS_PROVIDER=cloudflare\n'
          printf 'CF_API_TOKEN=\n'
        fi
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      else
        cert_provider_tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider // ""' "${SINGBOX_CONFIG_FILE}")
        printf 'TLS_MODE=manual\n'
        printf 'ACME_MODE=http\n'
        printf 'ACME_EMAIL=\n'
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
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
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          printf 'DNS_PROVIDER=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")"
          printf 'CF_API_TOKEN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")"
        else
          printf 'DNS_PROVIDER=cloudflare\n'
          printf 'CF_API_TOKEN=\n'
        fi
        printf 'CERT_PATH=\n'
        printf 'KEY_PATH=\n'
      else
        printf 'TLS_MODE=manual\n'
        printf 'ACME_MODE=http\n'
        printf 'ACME_EMAIL=\n'
        printf 'ACME_DOMAIN=%s\n' "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")"
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
        source "${state_file}"
        printf 'PORT=%s\n' "${PORT:-}"
        printf 'UUID=%s\n' "${UUID:-}"
        printf 'SNI=%s\n' "${SNI:-}"
        printf 'REALITY_PRIVATE_KEY=%s\n' "${REALITY_PRIVATE_KEY:-}"
        printf 'SHORT_ID_1=%s\n' "${SHORT_ID_1:-}"
        printf 'SHORT_ID_2=%s\n' "${SHORT_ID_2:-}"
      )
      ;;
    mixed)
      # shellcheck disable=SC1090
      (
        source "${state_file}"
        printf 'PORT=%s\n' "${PORT:-}"
        printf 'AUTH_ENABLED=%s\n' "${AUTH_ENABLED:-}"
        printf 'USERNAME=%s\n' "${USERNAME:-}"
        printf 'PASSWORD=%s\n' "${PASSWORD:-}"
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

  expected_snapshot=$(render_expected_protocol_state_snapshot "${protocol}") || return 1
  saved_snapshot=$(render_saved_protocol_state_snapshot "${protocol}") || return 1

  [[ "${saved_snapshot}" == "${expected_snapshot}" ]]
}

protocol_state_layer_matches_config() {
  [[ -f "${SINGBOX_CONFIG_FILE}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1

  local config_protocols=()
  local indexed_protocols=()
  local normalized_indexed_protocols=()
  local protocol joined_config joined_index

  mapfile -t config_protocols < <(list_config_protocols)
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
  local protocol
  local expected_snapshot
  local saved_snapshot

  [[ -x "${SINGBOX_BIN_PATH}" ]] || log_warn "接管诊断: 缺少 sing-box 二进制 ${SINGBOX_BIN_PATH}"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] || log_warn "接管诊断: 缺少 systemd 服务文件 ${SINGBOX_SERVICE_FILE}"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || log_warn "接管诊断: 缺少配置文件 ${SINGBOX_CONFIG_FILE}"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || log_warn "接管诊断: 缺少协议索引 ${SB_PROTOCOL_INDEX_FILE}"

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    mapfile -t config_protocols < <(list_config_protocols)
    if [[ ${#config_protocols[@]} -gt 0 ]]; then
      log_warn "接管诊断: 配置文件识别到的协议: $(IFS=,; printf '%s' "${config_protocols[*]}")"
    else
      log_warn "接管诊断: 配置文件中未识别到受支持协议。"
    fi
  fi

  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
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
      expected_snapshot=$(render_expected_protocol_state_snapshot "${protocol}" 2>/dev/null || true)
      saved_snapshot=$(render_saved_protocol_state_snapshot "${protocol}" 2>/dev/null || true)

      if [[ -n "${expected_snapshot}" ]]; then
        log_warn "接管诊断: ${protocol} 配置期望快照:"
        while IFS= read -r line; do
          log_warn "  ${line}"
        done <<< "${expected_snapshot}"
      fi

      if [[ -n "${saved_snapshot}" ]]; then
        log_warn "接管诊断: ${protocol} 当前状态快照:"
        while IFS= read -r line; do
          log_warn "  ${line}"
        done <<< "${saved_snapshot}"
      fi
    fi
  done
}

attempt_managed_instance_auto_heal() {
  local indexed_protocols=()
  local protocol
  local config_backup=""

  [[ -x "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" && -f "${SINGBOX_CONFIG_FILE}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1

  mapfile -t indexed_protocols < <(list_installed_protocols)
  [[ ${#indexed_protocols[@]} -gt 0 ]] || return 1

  for protocol in "${indexed_protocols[@]}"; do
    protocol_state_exists "${protocol}" || return 1
  done

  protocol_state_layer_matches_config && return 0

  log_warn "检测到托管实例配置与协议状态不一致，正在尝试按协议状态自动重建运行配置。"

  if config_has_advanced_route "${SINGBOX_CONFIG_FILE}"; then
    SB_ADVANCED_ROUTE="y"
  else
    SB_ADVANCED_ROUTE="n"
  fi

  if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
    SB_ENABLE_WARP="y"
  else
    SB_ENABLE_WARP="n"
  fi

  load_warp_route_settings
  load_stack_mode_state

  config_backup=$(mktemp)
  cp "${SINGBOX_CONFIG_FILE}" "${config_backup}"

  if ! generate_config || ! validate_config_file; then
    cp "${config_backup}" "${SINGBOX_CONFIG_FILE}"
    rm -f "${config_backup}"
    return 1
  fi

  rm -f "${config_backup}"
  return 0
}

detect_existing_instance_state() {
  local has_bin="n"
  local has_service="n"
  local has_config="n"
  local has_index="n"
  local has_state="n"
  local has_sbv="n"
  local state_file

  [[ -x "${SINGBOX_BIN_PATH}" ]] && has_bin="y"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && has_service="y"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && has_config="y"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && has_index="y"
  [[ -x "${SBV_BIN_PATH}" ]] && has_sbv="y"

  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
      [[ -e "${state_file}" ]] || continue
      [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] && continue
      has_state="y"
      break
    done
  fi

  if [[ "${has_bin}" == "n" && "${has_service}" == "n" && "${has_config}" == "n" && "${has_index}" == "n" && "${has_state}" == "n" ]]; then
    printf '%s' "fresh"
    return 0
  fi

  if [[ "${has_bin}" == "y" && "${has_service}" == "y" && "${has_config}" == "y" ]]; then
    if protocol_state_layer_matches_config; then
      printf '%s' "healthy"
    elif attempt_managed_instance_auto_heal && protocol_state_layer_matches_config; then
      printf '%s' "healthy"
    else
      printf '%s' "incomplete"
    fi
    return 0
  fi

  printf '%s' "incomplete"
}

rebuild_protocol_state_from_config() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 0

  local rebuilt_protocols=()
  local inbound_count inbound_index inbound_type protocol cert_provider_tag

  inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}")
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 0

  clear_protocol_state_cache
  ensure_protocol_state_dir

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // empty' "${SINGBOX_CONFIG_FILE}")
    protocol=$(normalize_protocol_id "${inbound_type}" 2>/dev/null || true)
    [[ -n "${protocol}" ]] || continue

    case "${protocol}" in
      vless-reality)
        SB_PROTOCOL="vless+reality"
        SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
        SB_UUID=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].uuid // ""' "${SINGBOX_CONFIG_FILE}")
        SB_SNI=$(jq -r --argjson idx "${inbound_index}" --arg fallback "${SB_REALITY_SNI_FALLBACK}" '.inbounds[$idx].tls.server_name // $fallback' "${SINGBOX_CONFIG_FILE}")
        SB_PRIVATE_KEY=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.private_key // ""' "${SINGBOX_CONFIG_FILE}")
        SB_SHORT_ID_1=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[0] // ""' "${SINGBOX_CONFIG_FILE}")
        SB_SHORT_ID_2=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[1] // ""' "${SINGBOX_CONFIG_FILE}")
        if [[ -f "${SB_KEY_FILE}" ]]; then
          SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ' || true)
        else
          SB_PUBLIC_KEY=""
        fi
        save_vless_reality_state
        ;;
      mixed)
        SB_PROTOCOL="mixed"
        SB_NODE_NAME="$(default_node_name_for_protocol "mixed")"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "1080"' "${SINGBOX_CONFIG_FILE}")
        if jq -e --argjson idx "${inbound_index}" '(.inbounds[$idx].users // []) | length > 0' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_MIXED_AUTH_ENABLED="y"
          SB_MIXED_USERNAME=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].username // ""' "${SINGBOX_CONFIG_FILE}")
          SB_MIXED_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
        else
          SB_MIXED_AUTH_ENABLED="n"
          SB_MIXED_USERNAME=""
          SB_MIXED_PASSWORD=""
        fi
        save_mixed_state
        ;;
      hy2)
        SB_PROTOCOL="hy2"
        SB_NODE_NAME="$(default_node_name_for_protocol "hy2")"
        cert_provider_tag=""
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_USER_NAME=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_UP_MBPS=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].up_mbps // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_DOWN_MBPS=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].down_mbps // ""' "${SINGBOX_CONFIG_FILE}")
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_HY2_OBFS_ENABLED="y"
          SB_HY2_OBFS_TYPE="salamander"
          SB_HY2_OBFS_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.password // ""' "${SINGBOX_CONFIG_FILE}")
        else
          SB_HY2_OBFS_ENABLED="n"
          SB_HY2_OBFS_TYPE=""
          SB_HY2_OBFS_PASSWORD=""
        fi

        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_HY2_TLS_MODE="acme"
          SB_HY2_ACME_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
          SB_HY2_ACME_EMAIL=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
          if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
            SB_HY2_ACME_MODE="dns"
            SB_HY2_DNS_PROVIDER=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
            SB_HY2_CF_API_TOKEN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
          else
            SB_HY2_ACME_MODE="http"
            SB_HY2_DNS_PROVIDER="cloudflare"
            SB_HY2_CF_API_TOKEN=""
          fi
          SB_HY2_CERT_PATH=""
          SB_HY2_KEY_PATH=""
        elif cert_provider_tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider // ""' "${SINGBOX_CONFIG_FILE}"); [[ -n "${cert_provider_tag}" ]]; then
          SB_HY2_TLS_MODE="acme"
          SB_HY2_ACME_DOMAIN=$(jq -r --argjson idx "${inbound_index}" --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .domain[0]) // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
          SB_HY2_ACME_EMAIL=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .email) // ""' "${SINGBOX_CONFIG_FILE}")
          if jq -e --arg tag "${cert_provider_tag}" 'any(.certificate_providers[]?; .tag == $tag and .dns01_challenge? != null)' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
            SB_HY2_ACME_MODE="dns"
            SB_HY2_DNS_PROVIDER=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .dns01_challenge.provider) // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
            SB_HY2_CF_API_TOKEN=$(jq -r --arg tag "${cert_provider_tag}" 'first(.certificate_providers[]? | select(.tag == $tag) | .dns01_challenge.api_token) // ""' "${SINGBOX_CONFIG_FILE}")
          else
            SB_HY2_ACME_MODE="http"
            SB_HY2_DNS_PROVIDER="cloudflare"
            SB_HY2_CF_API_TOKEN=""
          fi
          SB_HY2_CERT_PATH=""
          SB_HY2_KEY_PATH=""
        else
          SB_HY2_TLS_MODE="manual"
          SB_HY2_ACME_MODE="http"
          SB_HY2_ACME_EMAIL=""
          SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
          SB_HY2_DNS_PROVIDER="cloudflare"
          SB_HY2_CF_API_TOKEN=""
          SB_HY2_CERT_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
          SB_HY2_KEY_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
        fi
        SB_HY2_MASQUERADE=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].masquerade // ""' "${SINGBOX_CONFIG_FILE}")
        save_hy2_state
        ;;
      anytls)
        SB_PROTOCOL="anytls"
        SB_NODE_NAME="$(default_node_name_for_protocol "anytls")"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_USER_NAME=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_ANYTLS_TLS_MODE="acme"
          if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
            SB_ANYTLS_ACME_MODE="dns"
            SB_ANYTLS_DNS_PROVIDER=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
            SB_ANYTLS_CF_API_TOKEN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
          else
            SB_ANYTLS_ACME_MODE="http"
            SB_ANYTLS_DNS_PROVIDER="cloudflare"
            SB_ANYTLS_CF_API_TOKEN=""
          fi
          SB_ANYTLS_ACME_EMAIL=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_ACME_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_CERT_PATH=""
          SB_ANYTLS_KEY_PATH=""
        else
          SB_ANYTLS_TLS_MODE="manual"
          SB_ANYTLS_ACME_MODE="http"
          SB_ANYTLS_ACME_EMAIL=""
          SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
          SB_ANYTLS_DNS_PROVIDER="cloudflare"
          SB_ANYTLS_CF_API_TOKEN=""
          SB_ANYTLS_CERT_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_KEY_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
        fi
        save_anytls_state
        ;;
    esac

    if ! protocol_array_contains "${protocol}" "${rebuilt_protocols[@]}"; then
      rebuilt_protocols+=("${protocol}")
    fi
  done

  [[ ${#rebuilt_protocols[@]} -gt 0 ]] || return 1

  write_protocol_index "$(IFS=,; printf '%s' "${rebuilt_protocols[*]}")"
  return 0
}

take_over_existing_instance() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || log_error "未找到配置文件，无法接管现有实例。请先按全新安装处理。"
  ensure_takeover_validation_binary
  check_config_valid
  rebuild_protocol_state_from_config || log_error "当前配置未识别到可接管的受支持协议。"
  restore_runtime_artifacts_for_takeover
  if [[ "$(detect_existing_instance_state)" != "healthy" ]]; then
    log_takeover_state_diagnostics
    log_error "接管后实例状态仍不完整，请根据以上诊断信息检查现场。"
  fi
  restart_service_after_takeover
  log_success "现有实例接管完成。"
}

resolve_takeover_binary_repair_version() {
  local recorded_version
  recorded_version=$(extract_recorded_singbox_version_from_index)

  if [[ -n "${recorded_version}" ]]; then
    SB_VERSION="${recorded_version}"
    log_info "接管修复将按本地记录的 sing-box 版本恢复二进制: ${SB_VERSION}"
    return 0
  fi

  SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
  log_warn "未找到本地记录的 sing-box 版本；将回退到当前适配版本 ${SB_VERSION} 进行二进制修复。"
}

ensure_takeover_validation_binary() {
  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    resolve_takeover_binary_repair_version
    get_os_info
    get_arch
    install_dependencies
    install_binary
  fi
}

restore_runtime_artifacts_for_takeover() {
  if service_file_needs_repair; then
    setup_service
  fi

  if [[ ! -x "${SBV_BIN_PATH}" ]]; then
    ensure_sbv_command_installed
  fi
}

restart_service_after_takeover() {
  systemctl restart sing-box
}

install_or_reconfigure_singbox() {
  install_protocols_interactive "fresh"
}

update_singbox_binary_preserving_config() {
  local installed_ver
  local reinstall_choice

  installed_ver=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
  get_os_info
  get_arch
  install_dependencies
  load_current_config_state

  log_info "检测到现有安装，默认仅更新 sing-box 二进制并保留当前配置。"
  echo -e "当前版本: ${installed_ver}"
  echo -e "当前协议: $(protocol_display_name "${SB_PROTOCOL}")"
  echo -e "当前端口: ${SB_PORT}"

  prompt_singbox_version
  get_latest_version

  if [[ "${SB_VERSION}" == "${installed_ver}" ]]; then
    read -rp "目标版本与当前版本一致 (${installed_ver})，是否仍重新安装二进制? [y/N]: " reinstall_choice
    if [[ ! "${reinstall_choice}" =~ ^[Yy]$ ]]; then
      return 0
    fi
  fi

  install_binary

  log_info "正在使用 sing-box ${SB_VERSION} 校验现有配置..."
  if ! validate_config_file; then
    log_warn "现有配置未通过 sing-box ${SB_VERSION} 校验。配置已保留，服务未重启。"
    log_warn "这通常意味着新版本存在 breaking changes，请按 sing-box migration 文档迁移配置后再重载服务。"
    return 0
  fi

  log_success "现有配置通过 sing-box ${SB_VERSION} 校验。"
  setup_service
  systemctl restart sing-box
  log_success "sing-box 已更新到 ${SB_VERSION}，当前配置已保留。"
  display_status_summary
  log_info "连接信息未自动展示，如需查看请进入菜单 10。"
}

prompt_incomplete_instance_action() {
  local existing_instance_state
  local install_choice

  echo
  render_left_aligned_page_header "sing-box 管理" "发现现有实例缺少关键组件"
  render_section_title "实例检测"
  echo "检测到残缺的现有实例。"
  render_section_title "操作选项"
  render_menu_item "1" "接管现有实例"
  render_menu_item "2" "按全新安装处理"
  echo "0. 返回"
  read -rp "请选择 [0-2]: " install_choice

  case "${install_choice}" in
    1) take_over_existing_instance ;;
    2) install_or_reconfigure_singbox ;;
    0) return 0 ;;
    *) log_warn "无效选项，请重新选择。" ;;
  esac
}

install_new_protocols_menu() {
  local existing_instance_state

  existing_instance_state=$(detect_existing_instance_state)

  case "${existing_instance_state}" in
    healthy)
      install_protocols_interactive "additional"
      ;;
    incomplete)
      prompt_incomplete_instance_action
      ;;
    *)
      install_or_reconfigure_singbox
      ;;
  esac
}

update_singbox_version_menu() {
  local existing_instance_state

  existing_instance_state=$(detect_existing_instance_state)

  case "${existing_instance_state}" in
    healthy)
      update_singbox_binary_preserving_config
      ;;
    incomplete)
      prompt_incomplete_instance_action
      ;;
    *)
      log_warn "未检测到已安装的 sing-box 实例，将进入安装流程。"
      install_or_reconfigure_singbox
      ;;
  esac
}

install_or_update_singbox() {
  local existing_instance_state
  local install_choice
  local installed_ver

  existing_instance_state=$(detect_existing_instance_state)

  if [[ "${existing_instance_state}" == "healthy" ]]; then
    installed_ver=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
    load_current_config_state

    echo
    render_left_aligned_page_header "sing-box 管理" "更新核心或为现有实例补充协议"
    render_section_title "安装摘要"
    render_summary_item "当前版本" "${installed_ver}"
    render_summary_item "当前协议" "$(protocol_display_name "${SB_PROTOCOL}")"
    render_summary_item "当前端口" "${SB_PORT}"
    render_section_title "操作选项"
    render_menu_item "1" "更新 sing-box 二进制并保留当前配置"
    render_menu_item "2" "安装新增协议"
    echo "0. 返回"
    read -rp "请选择 [0-2] (默认 1): " install_choice

    case "${install_choice:-1}" in
      2) install_new_protocols_menu ;;
      0) return 0 ;;
      *) update_singbox_version_menu ;;
    esac
    return
  fi

  if [[ "${existing_instance_state}" == "incomplete" ]]; then
    prompt_incomplete_instance_action
    return
  fi

  install_or_reconfigure_singbox
}

main() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      uninstall)
        check_root
        uninstall_singbox
        exit 0
        ;;
      --internal-uninstall-purge)
        check_root
        if [[ "${2:-}" == "--yes" ]]; then
          perform_full_uninstall
        else
          uninstall_singbox
        fi
        exit 0
        ;;
    esac
  fi

  show_banner
  check_root
  ensure_sbv_command_installed
  while true; do
    # Status checks
    check_script_status
    check_sb_version
    check_bbr_status

    render_section_title "部署管理"
    render_menu_item "1" "安装新协议"
    render_menu_item "2" "更新 sing-box 版本" "" "${SB_VER_STATUS}"
    render_menu_item "3" "卸载 sing-box"
    render_menu_item "4" "修改当前协议配置"
    render_menu_item "5" "系统管理"

    render_section_title "服务控制"
    render_menu_item "6" "启动 sing-box"
    render_menu_item "7" "停止 sing-box"
    render_menu_item "8" "重启 sing-box"
    render_menu_item "9" "查看状态"

    render_section_title "连接与诊断"
    render_menu_item "10" "查看节点信息"
    render_menu_item "11" "查看实时日志"
    render_menu_item "15" "流媒体验证检测"

    render_section_title "脚本维护"
    render_menu_item "12" "更新管理脚本 (sbv)" "" "${SCRIPT_VER_STATUS}"
    render_menu_item "13" "卸载管理脚本 (sbv)"
    render_menu_item "14" "配置 Cloudflare Warp" "(解锁/防送中)"
    echo "0. 退出"
    render_main_menu_footer
    read -rp "请选择 [0-15]: " choice

    case "$choice" in
      1) install_new_protocols_menu ;;
      2) update_singbox_version_menu ;;
      3) uninstall_singbox ;;
      4) update_config_only ;;
      5) system_management_menu ;;
      6) systemctl start sing-box && log_success "服务已启动。" ;;
      7) systemctl stop sing-box && log_success "服务已停止。" ;;
      8) systemctl restart sing-box && log_success "服务已重启。" ;;
      9) view_status ;;
      10) view_node_info ;;
      11) journalctl -u sing-box -f || true ;;
      12) manual_update_script ;;
      13) uninstall_script ;;
      14) warp_management ;;
      15) media_check_menu ;;
      0) exit_script ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}


main "$@"
