#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 2026090401
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="2026090401"
readonly SB_SUPPORT_MAX_VERSION="1.14.0"
readonly SB_CONFIG_SCHEMA_1_14_MIN_VERSION="1.14.0"
readonly AGENT_OUTPUT_SCHEMA_VERSION="1"
readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
readonly UI_COMPACT_MAX_WIDTH=72
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
readonly SB_REALITY_QOS_FILTER_STATE_FILE="${SB_PROJECT_DIR}/reality-qos.filters"
readonly SB_REALITY_QOS_FILTER_PREF_START="32001"
readonly SB_REALITY_QOS_BURST="512k"
readonly SB_ACME_DATA_DIR="${SB_PROJECT_DIR}/acme"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
readonly SBV_BIN_PATH="/usr/local/bin/sbv"
readonly SBV_UPDATE_URL="https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh"
readonly SBV_SCRIPT_MIN_SIZE="1024"
readonly SBV_ARTIFACT_MIN_SIZE="128"
readonly SBV_CURL_CONNECT_TIMEOUT="10"
readonly SBV_CURL_MAX_TIME="60"
readonly SBV_CURL_RETRY_COUNT="2"
readonly SBV_CURL_RETRY_DELAY="1"
readonly SBV_CURL_STDERR_MAX_BYTES="4096"
readonly SINGBOX_CONFIG_DIR="${SB_PROJECT_DIR}"
readonly SINGBOX_CONFIG_FILE="${SB_PROJECT_DIR}/config.json"
readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"
readonly SB_UPGRADE_BACKUP_ROOT="/root/sing-box-vps-backups"
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
SB_NODE_NAME="$(hostname)-vless"
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
SB_ADVANCED_ROUTE="y"
SB_ENABLE_WARP="n"
SB_WARP_ROUTE_MODE="selective"
SB_OUTBOUND_POLICY="default"
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
SUBMAN_LAST_HTTP_STATUS=""
SUBMAN_LAST_ERROR_CODE=""
SUBMAN_LAST_ERROR_DISPOSITION=""
SUBMAN_LAST_RETRY_AFTER=""
SUBMAN_LAST_REVISION=""
SUBMAN_LAST_NODE_ID=""

# --- Return-based update transaction context ---
SBV_UPDATE_OPERATION=""
SBV_UPDATE_STAGE=""
SBV_UPDATE_ERROR_CODE=""
SBV_UPDATE_ERROR_MESSAGE=""
SBV_UPDATE_ERROR_DETAIL=""
SBV_UPDATE_COMMAND_EXIT_CODE="0"
SBV_UPDATE_HINT=""
SBV_UPDATE_CHANGED="false"
SBV_UPDATE_ROLLBACK_ATTEMPTED="false"
SBV_UPDATE_ROLLED_BACK="false"
SBV_UPDATE_ROLLBACK_OK="false"
SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED="false"
SBV_UPDATE_CURRENT_VERSION=""
SBV_UPDATE_CANDIDATE_VERSION=""
SBV_UPDATE_TARGET_PATH="${SBV_BIN_PATH}"
SBV_UPDATE_LOG_FILE="${SBV_LOG_FILE}"
SBV_UPDATE_TARGET_EXISTS="false"
SBV_UPDATE_TARGET_MODE=""
SBV_UPDATE_TARGET_UID=""
SBV_UPDATE_TARGET_GID=""
SBV_UPDATE_TARGET_HASH=""
SBV_UPDATE_TARGET_VERSION=""
SBV_UPDATE_EXPECTED_MODE=""
SBV_UPDATE_EXPECTED_UID=""
SBV_UPDATE_EXPECTED_GID=""
SBV_UPDATE_CANDIDATE_PATH=""
SBV_UPDATE_CANDIDATE_HASH=""
SBV_UPDATE_CURL_STDERR_PATH=""
SBV_UPDATE_BACKUP_PATH=""
SBV_UPDATE_ROLLBACK_PATH=""
SBV_UPDATE_LOCK_PATH=""
SBV_UPDATE_LOCK_HELD="false"
SBV_UPDATE_COMMITTED="false"
SBV_UPDATE_NOOP="false"
SBV_UPDATE_PRESERVE_ARTIFACTS="false"
SBV_UPDATE_SIGNAL_NAME=""
SBV_UPDATE_SIGNAL_CODE="0"
SBV_UPDATE_TRAP_ACTIVE="false"
SBV_UPDATE_TRAP_RUNNING="false"
SBV_UPDATE_PREVIOUS_INT_TRAP=""
SBV_UPDATE_PREVIOUS_TERM_TRAP=""
SBV_UPDATE_PREVIOUS_HUP_TRAP=""
SBV_UPDATE_PREVIOUS_ERR_TRAP=""
SBV_VALIDATED_SCRIPT_VERSION=""
SBV_SCRIPT_VALIDATION_CODE=""
SBV_SCRIPT_VALIDATION_DETAIL=""

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

singbox_version_at_least() {
  local version=${1#v}
  local minimum=${2#v}
  local version_major version_minor version_patch
  local minimum_major minimum_minor minimum_patch

  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "${minimum}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

  IFS='.' read -r version_major version_minor version_patch <<< "${version}"
  IFS='.' read -r minimum_major minimum_minor minimum_patch <<< "${minimum}"

  if (( 10#${version_major} != 10#${minimum_major} )); then
    (( 10#${version_major} > 10#${minimum_major} ))
    return
  fi

  if (( 10#${version_minor} != 10#${minimum_minor} )); then
    (( 10#${version_minor} > 10#${minimum_minor} ))
    return
  fi

  (( 10#${version_patch} >= 10#${minimum_patch} ))
}

resolve_config_target_singbox_version() {
  local installed_version candidate

  installed_version=$(detect_installed_singbox_version)
  candidate=${installed_version#v}
  if [[ ! "${candidate}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    candidate=${SB_VERSION:-}
  fi
  candidate=${candidate#v}

  if [[ "${candidate}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${candidate}"
    return 0
  fi

  printf '%s' "${SB_SUPPORT_MAX_VERSION}"
}

singbox_config_supports_1_14() {
  local target_version

  target_version=$(resolve_config_target_singbox_version)
  singbox_version_at_least "${target_version}" "${SB_CONFIG_SCHEMA_1_14_MIN_VERSION}"
}

print_cli_help() {
  cat <<'EOF'
用法:
  sbv
  sbv --help
  sbv update sbv
  sbv update sing-box [latest|x.y.z]
  sbv update-sbv
  sbv update-sing-box [latest|x.y.z]
  sbv agent help
  sbv agent capabilities --json
  sbv agent upgrade-check --json x.y.z
  sbv agent upgrade --json x.y.z --yes
  sbv uninstall

说明:
  不带参数时打开交互式管理菜单。
  update sbv                 更新管理脚本 /usr/local/bin/sbv。
  update sing-box            更新 sing-box 二进制并保留现有配置。
  update-sing-box [version]  update sing-box 的短别名，版本可为 latest 或 x.y.z。
  agent                      输出适合自动化读取的 JSON 状态、节点、能力和受保护升级结果。
EOF
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

validate_instance_outbound_policy() {
  case "$1" in
    default|direct|warp) return 0 ;;
    *) return 1 ;;
  esac
}

outbound_policy_display_name() {
  case "$1" in
    direct) printf '强制 direct 出口' ;;
    warp) printf '强制 Warp 出口' ;;
    *) printf '跟随全局路由' ;;
  esac
}

prompt_instance_outbound_policy() {
  local prompt=${1:-"请选择出站策略"}
  local current=${2:-default}
  local default_choice choice

  validate_instance_outbound_policy "${current}" || current="default"
  if [[ ! -t 0 ]]; then
    printf '%s' "${current}"
    return 0
  fi

  case "${current}" in
    direct) default_choice=2 ;;
    warp) default_choice=3 ;;
    *) default_choice=1 ;;
  esac

  echo "实例出站策略:" >&2
  echo "1. 跟随全局路由" >&2
  echo "2. 强制 direct 出口" >&2
  echo "3. 强制 Warp 出口" >&2
  choice=$(prompt_choice "${prompt} [1-3] (当前: $(outbound_policy_display_name "${current}")): " 1 3 "${default_choice}")
  case "${choice}" in
    2) printf 'direct' ;;
    3) printf 'warp' ;;
    *) printf 'default' ;;
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
    hy2) suffix="hy2" ;;
    anytls) suffix="anytls" ;;
    mixed) suffix="mixed" ;;
    *) suffix="${protocol}" ;;
  esac

  printf '%s-%s' "$(hostname)" "${suffix}"
}

normalize_node_name() {
  local node_name=$1

  node_name=$(trim_whitespace "${node_name}")
  case "${node_name}" in
    *+vless) node_name="${node_name%+vless}-vless" ;;
    *+hy2) node_name="${node_name%+hy2}-hy2" ;;
    *+anytls) node_name="${node_name%+anytls}-anytls" ;;
    *+mixed) node_name="${node_name%+mixed}-mixed" ;;
  esac

  printf '%s' "${node_name}"
}

network_stack_suffix_from_label() {
  case "$1" in
    IPv4|ipv4|v4) printf 'v4' ;;
    IPv6|ipv6|v6) printf 'v6' ;;
    *) printf '' ;;
  esac
}

node_name_for_network_stack() {
  local base_name=$1
  local address_label=${2:-}
  local stack_suffix

  base_name=$(normalize_node_name "${base_name}")
  stack_suffix=$(network_stack_suffix_from_label "${address_label}")
  if [[ -n "${stack_suffix}" ]]; then
    printf '%s-%s' "${base_name}" "${stack_suffix}"
  else
    printf '%s' "${base_name}"
  fi
}

bandwidth_limit_name_suffix() {
  local up_mbps=${1:-}
  local down_mbps=${2:-}
  local parts=()

  if [[ -n "${up_mbps}" ]]; then
    parts+=("U${up_mbps}M")
  fi
  if [[ -n "${down_mbps}" ]]; then
    parts+=("D${down_mbps}M")
  fi

  if [[ ${#parts[@]} -eq 0 ]]; then
    printf ''
  else
    local IFS='-'
    printf '%s' "${parts[*]}"
  fi
}

display_node_name_for_protocol() {
  local protocol=$1
  local base_name=${2:-}
  local address_label=${3:-}
  local up_mbps="" down_mbps="" bandwidth_suffix="" node_name

  protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  base_name=$(normalize_node_name "${base_name}")
  if [[ -z "${base_name}" ]]; then
    printf ''
    return 0
  fi

  case "${protocol}" in
    vless-reality)
      up_mbps="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      down_mbps="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      ;;
    hy2)
      up_mbps="${SB_HY2_UP_MBPS:-}"
      down_mbps="${SB_HY2_DOWN_MBPS:-}"
      ;;
  esac

  bandwidth_suffix=$(bandwidth_limit_name_suffix "${up_mbps}" "${down_mbps}")
  node_name="${base_name}"
  if [[ -n "${bandwidth_suffix}" ]]; then
    node_name="${node_name}-${bandwidth_suffix}"
  fi

  node_name_for_network_stack "${node_name}" "${address_label}"
}

vless_reality_display_node_name() {
  local base_name=$1
  local address_label=${2:-}

  display_node_name_for_protocol "vless-reality" "${base_name}" "${address_label}"
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

  unset INSTANCE_ID ENABLED NODE_NAME PORT UUID SNI SHORT_ID_1 SHORT_ID_2
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

  # shellcheck disable=SC1090
  source "${state_file}"

  if [[ "${CONFIG_SCHEMA_VERSION:-1}" != "1" || -z "${PORT:-}" || -z "${UUID:-}" ]]; then
    return 0
  fi

  backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
  cp "${state_file}" "${backup_state_file}"

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
  tmp_state=$(mktemp)
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
  local route_count outbound

  route_count=$(jq -r --arg tag "${inbound_tag}" '[.route.rules[]? | select(.inbound == $tag and .action == "route")] | length' "${SINGBOX_CONFIG_FILE}") || return 1
  if [[ "${route_count}" == "0" ]]; then
    printf 'default'
    return 0
  fi
  [[ "${route_count}" == "1" ]] || return 1
  outbound=$(jq -r --arg tag "${inbound_tag}" 'first(.route.rules[]? | select(.inbound == $tag and .action == "route") | .outbound) // ""' "${SINGBOX_CONFIG_FILE}") || return 1
  case "${outbound}" in
    direct) printf 'direct' ;;
    warp|warp-ep) printf 'warp' ;;
    *) return 1 ;;
  esac
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
  if [[ -z "${SB_UUID}" ]]; then
    SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  fi

  if [[ -z "${SB_SHORT_ID_1}" ]]; then
    SB_SHORT_ID_1=$(openssl rand -hex 8)
  fi

  if [[ -z "${SB_SHORT_ID_2}" && "${SB_VLESS_PRESERVE_SINGLE_SHORT_ID:-n}" != "y" ]]; then
    SB_SHORT_ID_2=$(openssl rand -hex 8)
  fi

  VLESS_REALITY_DEFAULT_INSTANCE_ID="${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}"
  VLESS_REALITY_INSTANCE_IDS="${VLESS_REALITY_INSTANCE_IDS:-${SB_VLESS_INSTANCE_ID:-main}}"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state
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
    write_env_assignment "ACME_EXTRA_JSON" "$(acme_extra_json_or_default "${SB_HY2_ACME_EXTRA_JSON:-}")"
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
    write_env_assignment "ACME_EXTRA_JSON" "$(acme_extra_json_or_default "${SB_ANYTLS_ACME_EXTRA_JSON:-}")"
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
  migrate_vless_reality_state_to_instances_if_needed
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
    choice=$(prompt_choice "请选择 [0-${#protocols[@]}]: " 0 "${#protocols[@]}" "")

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
  local in_node in_p in_uuid current_port

  read -rp "新节点名称 (当前: ${SB_NODE_NAME}, 留空保持): " in_node
  in_node=$(trim_whitespace "${in_node:-}")
  [[ -n "${in_node}" ]] && SB_NODE_NAME="${in_node}"

  current_port="${SB_PORT}"
  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${current_port}" ]]; then
    if [[ "${in_p}" != "${current_port}" ]] && port_in_configured_protocol_state "${in_p}"; then
      log_error "端口已被现有协议配置占用: ${in_p}"
    fi
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  read -rp "新 UUID (当前: ${SB_UUID}, 留空保持): " in_uuid
  in_uuid=$(trim_whitespace "${in_uuid:-}")
  [[ -n "${in_uuid}" ]] && SB_UUID="${in_uuid}"

  prompt_reality_sni_update
  prompt_vless_reality_rate_limit_update_fields
  prompt_vless_reality_advanced_update_fields
  validate_current_reality_sni_alpn_or_warn
  SB_OUTBOUND_POLICY=$(prompt_instance_outbound_policy "新出站策略" "${SB_OUTBOUND_POLICY:-default}")
}

validate_reality_sni_syntax() {
  local domain=${1:-}

  [[ -n "${domain}" ]] || return 1
  [[ "${domain}" != *"://"* ]] || return 1
  [[ "${domain}" != *"/"* ]] || return 1
  [[ "${domain}" != *":"* ]] || return 1
  [[ "${domain}" != *[[:space:]]* ]] || return 1
  [[ "${domain}" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

probe_reality_sni_tls() {
  local domain=$1
  local output timeout_cmd=()

  if ! validate_reality_sni_syntax "${domain}"; then
    printf 'SNI 必须是纯域名，例如 www.example.com'
    return 1
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    printf '未检测到 openssl，无法执行 TLS 1.3/证书校验'
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout 7)
  fi

  if ! output=$(printf '' | "${timeout_cmd[@]}" openssl s_client \
    -connect "${domain}:443" \
    -servername "${domain}" \
    -verify_hostname "${domain}" \
    -verify_return_error \
    -tls1_3 \
    -brief 2>&1); then
    if grep -qi 'certificate verify failed\|hostname mismatch\|verify error' <<< "${output}"; then
      printf 'TLS 证书校验失败或证书主机名不匹配'
    elif grep -qi 'wrong version number\|protocol version\|tlsv1 alert protocol version\|no protocols available' <<< "${output}"; then
      printf '目标站点未成功协商 TLS 1.3'
    elif grep -qi 'timed out\|timeout' <<< "${output}"; then
      printf '连接 443/TLS 超时'
    else
      printf '无法完成 443/TLS 1.3 握手'
    fi
    return 1
  fi

  if ! grep -Eqi 'Protocol version: TLSv1\.3|Protocol[[:space:]]*:[[:space:]]*TLSv1\.3' <<< "${output}"; then
    printf '目标站点未成功协商 TLS 1.3'
    return 1
  fi

  return 0
}

probe_reality_sni_alpn() {
  local domain=$1
  local mode=${2:-off}
  local alpn_value output timeout_cmd=()

  case "${mode}" in
    h2_http1) alpn_value="h2,http/1.1" ;;
    http1) alpn_value="http/1.1" ;;
    off|"") return 0 ;;
    *)
      printf '未知 ALPN 预设: %s' "${mode}"
      return 1
      ;;
  esac

  if ! validate_reality_sni_syntax "${domain}"; then
    printf 'SNI 必须是纯域名，例如 www.example.com'
    return 1
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    printf '未检测到 openssl，无法执行 ALPN 校验'
    return 1
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout 7)
  fi

  if ! output=$(printf '' | "${timeout_cmd[@]}" openssl s_client \
    -connect "${domain}:443" \
    -servername "${domain}" \
    -tls1_3 \
    -alpn "${alpn_value}" 2>&1); then
    printf '无法完成 ALPN/TLS 1.3 握手'
    return 1
  fi

  case "${mode}" in
    h2_http1)
      grep -Eq 'ALPN protocol: (h2|http/1\.1)' <<< "${output}" || {
        printf '目标站点未协商 h2 或 http/1.1'
        return 1
      }
      ;;
    http1)
      grep -Eq 'ALPN protocol: http/1\.1' <<< "${output}" || {
        printf '目标站点未协商 http/1.1'
        return 1
      }
      ;;
  esac
}

confirm_reality_sni_warning_continue() {
  local reason=$1
  local choice

  log_warn "Reality SNI 校验未通过：${reason}" >&2
  if [[ "${SB_REALITY_SNI_VALIDATION_ASSUME_YES:-0}" == "1" ]]; then
    log_warn "当前为非交互输入，已继续使用该 SNI。" >&2
    return 0
  fi

  choice=$(prompt_yes_no "是否仍然继续使用该 SNI [y/n] (默认 n): " "n")
  [[ "${choice}" == "y" ]]
}

read_manual_reality_sni_with_validation() {
  local default_sni=$1
  local prompt=$2
  local manual_sni reason

  while true; do
    read -rp "${prompt}" manual_sni
    manual_sni=$(trim_whitespace "${manual_sni:-}")
    manual_sni=${manual_sni:-${default_sni}}

    if reason=$(probe_reality_sni_tls "${manual_sni}"); then
      SB_SNI="${manual_sni}"
      return 0
    fi

    if confirm_reality_sni_warning_continue "${reason}"; then
      SB_SNI="${manual_sni}"
      return 0
    fi
  done
}

validate_current_reality_sni_alpn_or_warn() {
  local reason

  SB_VLESS_ALPN_MODE="${SB_VLESS_ALPN_MODE:-off}"
  validate_vless_reality_alpn_mode "${SB_VLESS_ALPN_MODE}" || SB_VLESS_ALPN_MODE="off"

  if [[ "${SB_VLESS_ALPN_MODE}" == "off" ]]; then
    return 0
  fi

  if reason=$(probe_reality_sni_alpn "${SB_SNI}" "${SB_VLESS_ALPN_MODE}"); then
    log_success "Reality SNI ALPN 校验通过: ${SB_SNI} ($(vless_reality_alpn_mode_display_name "${SB_VLESS_ALPN_MODE}"))"
    return 0
  fi

  if ! confirm_reality_sni_warning_continue "${reason}"; then
    log_warn "已关闭 ALPN 预设以避免继续使用不兼容的 SNI/ALPN 组合。"
    SB_VLESS_ALPN_MODE="off"
  fi
}

probe_reality_sni_candidate() {
  local domain=$1
  local time_total reason

  if ! reason=$(probe_reality_sni_tls "${domain}"); then
    log_warn "Reality SNI TLS 校验失败: ${domain} (${reason})" >&2
    return 1
  fi

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
  local choice selected_sni

  echo "[VLESS + REALITY] REALITY 域名选择:"
  echo "1. 自动探测推荐 SNI (默认)"
  echo "2. 手动输入"
  choice=$(prompt_choice "请选择 [1-2] (默认 1): " 1 2 1)

  case "${choice}" in
    2)
      read_manual_reality_sni_with_validation "${SB_REALITY_SNI_FALLBACK}" \
        "[VLESS + REALITY] REALITY 域名 (默认 ${SB_REALITY_SNI_FALLBACK}): "
      ;;
    *)
      selected_sni=$(select_reality_sni_candidate)
      SB_SNI="${selected_sni}"
      log_success "已选择 Reality SNI: ${SB_SNI}"
      ;;
  esac
}

prompt_reality_sni_update() {
  local choice selected_sni

  echo "[VLESS + REALITY] REALITY SNI 更新方式:"
  echo "1. 保留当前 SNI: ${SB_SNI} (默认)"
  echo "2. 自动探测推荐 SNI"
  echo "3. 手动输入"
  choice=$(prompt_choice "请选择 [1-3] (默认 1): " 1 3 1)

  case "${choice}" in
    2)
      selected_sni=$(select_reality_sni_candidate)
      SB_SNI="${selected_sni}"
      log_success "已选择 Reality SNI: ${SB_SNI}"
      ;;
    3)
      read_manual_reality_sni_with_validation "${SB_SNI}" \
        "[VLESS + REALITY] 新 REALITY SNI (当前: ${SB_SNI}, 留空保持): "
      ;;
    *)
      log_info "保留当前 Reality SNI: ${SB_SNI}"
      ;;
  esac
}

prompt_reality_sni_for_new_instance() {
  local default_sni=$1
  local choice selected_sni

  default_sni=${default_sni:-${SB_REALITY_SNI_FALLBACK}}

  echo "[VLESS + REALITY] REALITY SNI 选择:"
  echo "1. 复用现有 SNI: ${default_sni} (默认)"
  echo "2. 自动探测推荐 SNI"
  echo "3. 手动输入"
  choice=$(prompt_choice "请选择 [1-3] (默认 1): " 1 3 1)

  case "${choice}" in
    2)
      selected_sni=$(select_reality_sni_candidate)
      SB_SNI="${selected_sni}"
      log_success "已选择 Reality SNI: ${SB_SNI}"
      ;;
    3)
      read_manual_reality_sni_with_validation "${default_sni}" \
        "[VLESS + REALITY] REALITY SNI (默认 ${default_sni}): "
      ;;
    *)
      SB_SNI="${default_sni}"
      log_info "复用 Reality SNI: ${SB_SNI}"
      ;;
  esac
}

prompt_vless_reality_rate_limit_fields() {
  local in_limit in_up in_down

  SB_VLESS_RATE_LIMIT_UP_MBPS="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"

  in_limit=$(prompt_yes_no "[VLESS + REALITY] 是否配置限速 [y/n] (默认 n): " "n")
  if [[ "${in_limit}" != "y" ]]; then
    SB_VLESS_RATE_LIMIT_UP_MBPS=""
    SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
    return 0
  fi

  in_up=$(prompt_optional_positive_integer "[VLESS + REALITY] 上行带宽 Mbps (留空表示上行不限速): " "" "上行带宽")
  in_down=$(prompt_optional_positive_integer "[VLESS + REALITY] 下行带宽 Mbps (留空表示下行不限速): " "" "下行带宽")

  SB_VLESS_RATE_LIMIT_UP_MBPS="${in_up}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${in_down}"

  if [[ -z "${SB_VLESS_RATE_LIMIT_UP_MBPS}" && -z "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" ]]; then
    log_warn "上下行均为空，将按不限速保存。"
  fi
}

prompt_vless_reality_rate_limit_update_fields() {
  local choice in_up in_down current_summary

  SB_VLESS_RATE_LIMIT_UP_MBPS="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
  current_summary=$(vless_reality_rate_limit_summary \
    "${SB_VLESS_RATE_LIMIT_UP_MBPS}" \
    "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}")

  echo "[VLESS + REALITY] 当前限速: ${current_summary}"
  echo "1. 保留当前限速 (默认)"
  echo "2. 重新设置限速"
  echo "3. 清空限速"
  choice=$(prompt_choice "请选择 [1-3] (默认 1): " 1 3 1)

  case "${choice}" in
    2)
      in_up=$(prompt_optional_positive_integer "[VLESS + REALITY] 上行带宽 Mbps (留空表示上行不限速): " "" "上行带宽")
      in_down=$(prompt_optional_positive_integer "[VLESS + REALITY] 下行带宽 Mbps (留空表示下行不限速): " "" "下行带宽")

      SB_VLESS_RATE_LIMIT_UP_MBPS="${in_up}"
      SB_VLESS_RATE_LIMIT_DOWN_MBPS="${in_down}"
      ;;
    3)
      SB_VLESS_RATE_LIMIT_UP_MBPS=""
      SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
      ;;
    *)
      log_info "保留当前 REALITY 限速: ${current_summary}"
      ;;
  esac
}

prompt_vless_reality_advanced_update_fields() {
  local choice tfo_choice current_alpn current_tfo

  SB_VLESS_ALPN_MODE="${SB_VLESS_ALPN_MODE:-off}"
  validate_vless_reality_alpn_mode "${SB_VLESS_ALPN_MODE}" || SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="${SB_VLESS_TCP_FAST_OPEN:-n}"
  [[ "${SB_VLESS_TCP_FAST_OPEN}" == "y" || "${SB_VLESS_TCP_FAST_OPEN}" == "n" ]] || SB_VLESS_TCP_FAST_OPEN="n"

  current_alpn=$(vless_reality_alpn_mode_display_name "${SB_VLESS_ALPN_MODE}")
  current_tfo="关闭"
  [[ "${SB_VLESS_TCP_FAST_OPEN}" == "y" ]] && current_tfo="开启"

  echo "[VLESS + REALITY] 高级配置:"
  echo "- 当前 ALPN: ${current_alpn}"
  echo "- 当前 TCP Fast Open: ${current_tfo}"
  echo "ALPN 预设:"
  echo "1. 保留当前 ALPN (默认)"
  echo "2. 关闭"
  echo "3. h2 + http/1.1"
  echo "4. http/1.1"
  choice=$(prompt_choice "请选择 ALPN [1-4] (默认 1): " 1 4 1)
  case "${choice}" in
    2) SB_VLESS_ALPN_MODE="off" ;;
    3) SB_VLESS_ALPN_MODE="h2_http1" ;;
    4) SB_VLESS_ALPN_MODE="http1" ;;
    *) ;;
  esac

  tfo_choice=$(prompt_yes_no "是否启用 TCP Fast Open [y/n] (当前: ${SB_VLESS_TCP_FAST_OPEN}, 留空保持): " "${SB_VLESS_TCP_FAST_OPEN}")
  SB_VLESS_TCP_FAST_OPEN="${tfo_choice}"
}

prompt_mixed_update() {
  local in_p in_auth in_user in_pass

  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${SB_PORT}" ]]; then
    SB_PORT="${in_p}"
    check_port_conflict "${SB_PORT}"
  fi

  in_auth=$(prompt_yes_no "是否启用用户名密码认证 [y/n] (当前: ${SB_MIXED_AUTH_ENABLED}, 留空保持): " "${SB_MIXED_AUTH_ENABLED}")
  SB_MIXED_AUTH_ENABLED="${in_auth}"

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

  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${SB_PORT}" ]]; then
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

  in_up=$(prompt_update_optional_positive_integer "上行带宽 Mbps (当前: ${SB_HY2_UP_MBPS:-未限制}, 留空清空限制): " "上行带宽")
  SB_HY2_UP_MBPS="${in_up}"

  in_down=$(prompt_update_optional_positive_integer "下行带宽 Mbps (当前: ${SB_HY2_DOWN_MBPS:-未限制}, 留空清空限制): " "下行带宽")
  SB_HY2_DOWN_MBPS="${in_down}"

  in_obfs=$(prompt_yes_no "是否启用 obfs / Salamander 混淆 [y/n] (当前: ${SB_HY2_OBFS_ENABLED}, 留空保持): " "${SB_HY2_OBFS_ENABLED}")
  SB_HY2_OBFS_ENABLED="${in_obfs}"

  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    if [[ -n "${SB_HY2_OBFS_PASSWORD}" ]]; then
      read -rp "obfs / Salamander 混淆密码 (当前: 已设置，留空保持；输入新值则覆盖): " in_obfs_password
    else
      read -rp "obfs / Salamander 混淆密码 (当前: 未设置，留空自动生成；输入新值则使用输入值): " in_obfs_password
    fi
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
    [[ -z "${SB_HY2_OBFS_TYPE}" ]] && SB_HY2_OBFS_TYPE="salamander"
  else
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  in_tls_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_HY2_TLS_MODE}, 留空保持): " 1 2)
  case "${in_tls_mode}" in
    1) SB_HY2_TLS_MODE="acme" ;;
    2) SB_HY2_TLS_MODE="manual" ;;
    "") ;;
  esac

  if [[ -z "${in_tls_mode}" ]]; then
    :
  elif [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_HY2_ACME_MODE}, 留空保持): " 1 2)
    case "${in_acme_mode}" in
      1) SB_HY2_ACME_MODE="http" ;;
      2) SB_HY2_ACME_MODE="dns" ;;
      "") ;;
    esac

    in_acme_email=$(prompt_optional_email "ACME 邮箱 (当前: ${SB_HY2_ACME_EMAIL}, 留空保持，用于证书通知): " "${SB_HY2_ACME_EMAIL}")
    SB_HY2_ACME_EMAIL="${in_acme_email}"
    in_acme_domain=$(prompt_optional_domain "ACME 域名 (当前: ${SB_HY2_ACME_DOMAIN:-${SB_HY2_DOMAIN}}, 留空保持): " "${SB_HY2_ACME_DOMAIN:-${SB_HY2_DOMAIN}}")
    SB_HY2_ACME_DOMAIN="${in_acme_domain}"

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token (当前: 留空隐藏, 留空保持): " in_cf_api_token
      [[ -n "${in_cf_api_token}" ]] && SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    else
      SB_HY2_CF_API_TOKEN=""
    fi

    SB_HY2_CERT_PATH=""
    SB_HY2_KEY_PATH=""
  else
    in_cert_path=$(prompt_required_path "证书路径 (当前: ${SB_HY2_CERT_PATH}, 留空保持): " "${SB_HY2_CERT_PATH}")
    SB_HY2_CERT_PATH="${in_cert_path}"
    in_key_path=$(prompt_required_path "私钥路径 (当前: ${SB_HY2_KEY_PATH}, 留空保持): " "${SB_HY2_KEY_PATH}")
    SB_HY2_KEY_PATH="${in_key_path}"
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

  in_p=$(prompt_port "新端口 (当前: ${SB_PORT}, 留空保持): " "${SB_PORT}")
  if [[ "${in_p}" != "${SB_PORT}" ]]; then
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
  in_tls_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_ANYTLS_TLS_MODE}, 留空保持): " 1 2)
  case "${in_tls_mode}" in
    1) SB_ANYTLS_TLS_MODE="acme" ;;
    2) SB_ANYTLS_TLS_MODE="manual" ;;
    "") ;;
  esac

  if [[ -z "${in_tls_mode}" ]]; then
    :
  elif [[ "${SB_ANYTLS_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_optional_choice "请选择 [1-2] (当前: ${SB_ANYTLS_ACME_MODE}, 留空保持): " 1 2)
    case "${in_acme_mode}" in
      1) SB_ANYTLS_ACME_MODE="http" ;;
      2) SB_ANYTLS_ACME_MODE="dns" ;;
      "") ;;
    esac

    in_acme_email=$(prompt_optional_email "ACME 邮箱 (当前: ${SB_ANYTLS_ACME_EMAIL}, 留空保持，用于证书通知): " "${SB_ANYTLS_ACME_EMAIL}")
    SB_ANYTLS_ACME_EMAIL="${in_acme_email}"
    in_acme_domain=$(prompt_optional_domain "ACME 域名 (当前: ${SB_ANYTLS_ACME_DOMAIN:-${SB_ANYTLS_DOMAIN}}, 留空保持): " "${SB_ANYTLS_ACME_DOMAIN:-${SB_ANYTLS_DOMAIN}}")
    SB_ANYTLS_ACME_DOMAIN="${in_acme_domain}"

    if [[ "${SB_ANYTLS_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token (当前: 留空隐藏, 留空保持): " in_cf_api_token
      [[ -n "${in_cf_api_token}" ]] && SB_ANYTLS_CF_API_TOKEN="${in_cf_api_token}"
    else
      SB_ANYTLS_CF_API_TOKEN=""
    fi

    SB_ANYTLS_CERT_PATH=""
    SB_ANYTLS_KEY_PATH=""
  else
    in_cert_path=$(prompt_required_path "证书路径 (当前: ${SB_ANYTLS_CERT_PATH}, 留空保持): " "${SB_ANYTLS_CERT_PATH}")
    SB_ANYTLS_CERT_PATH="${in_cert_path}"
    in_key_path=$(prompt_required_path "私钥路径 (当前: ${SB_ANYTLS_KEY_PATH}, 留空保持): " "${SB_ANYTLS_KEY_PATH}")
    SB_ANYTLS_KEY_PATH="${in_key_path}"
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
  local protocol current_protocol_state instance_id
  current_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    if [[ "${protocol}" == "vless-reality" ]]; then
      load_vless_reality_protocol_state
      migrate_vless_reality_state_to_instances_if_needed
      while IFS= read -r instance_id; do
        [[ -z "${instance_id}" ]] && continue
        load_vless_reality_instance_state "${instance_id}" || continue
        open_firewall_port "${SB_PORT}"
      done < <(list_vless_reality_instance_ids)
    else
      load_protocol_state "${protocol}"
      open_firewall_port "${SB_PORT}"
    fi
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
      if [[ "${install_mode}" == "additional" && "${protocol}" == "vless-reality" ]]; then
        echo "${index}. 新增 VLESS + REALITY 节点"
      fi
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
        if [[ "${install_mode}" == "additional" && "${protocol}" == "vless-reality" ]]; then
          selected_protocols+=("${protocol}")
        fi
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
      if [[ "${install_mode}" == "additional" && "${protocol}" == "vless-reality" ]]; then
        if ! protocol_array_contains "${protocol}" "${selected_protocols[@]}"; then
          selected_protocols+=("${protocol}")
        fi
        continue
      fi
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
  local in_node in_p

  set_protocol_defaults "vless+reality"
  SB_VLESS_INSTANCE_ID="main"
  SB_VLESS_INBOUND_TAG=""
  SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
  echo -e "\n${BLUE}--- 配置 VLESS + REALITY ---${NC}"
  read -rp "[VLESS + REALITY] 节点名称 (默认 ${SB_NODE_NAME}): " in_node
  in_node=$(trim_whitespace "${in_node:-}")
  [[ -n "${in_node}" ]] && SB_NODE_NAME="${in_node}"

  SB_PORT=$(prompt_port "[VLESS + REALITY] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  prompt_reality_sni_install
  prompt_vless_reality_rate_limit_fields
  prompt_vless_reality_advanced_update_fields
  validate_current_reality_sni_alpn_or_warn
  SB_OUTBOUND_POLICY=$(prompt_instance_outbound_policy "[VLESS + REALITY] 出站策略" "${SB_OUTBOUND_POLICY:-default}")
}

prompt_vless_reality_instance_create() {
  local in_id in_node in_port default_id default_sni selected_id selected_node selected_port

  migrate_vless_reality_state_to_instances_if_needed
  load_vless_reality_protocol_state
  default_id="reality-$(date +%H%M%S)"

  while true; do
    read -rp "[VLESS + REALITY] 新实例 ID (默认 ${default_id}): " in_id
    SB_VLESS_INSTANCE_ID=$(trim_whitespace "${in_id:-${default_id}}")
    if ! validate_vless_reality_instance_id "${SB_VLESS_INSTANCE_ID}"; then
      log_warn "实例 ID 只能包含小写字母、数字和短横线。"
      continue
    fi
    if vless_reality_instance_id_exists "${SB_VLESS_INSTANCE_ID}"; then
      log_warn "实例 ID 已存在: ${SB_VLESS_INSTANCE_ID}"
      continue
    fi
    break
  done
  selected_id="${SB_VLESS_INSTANCE_ID}"

  SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
  read -rp "[VLESS + REALITY] 节点名称 (默认 ${SB_NODE_NAME}): " in_node
  SB_NODE_NAME=$(trim_whitespace "${in_node:-${SB_NODE_NAME}}")
  selected_node="${SB_NODE_NAME}"

  while true; do
    SB_PORT=$(prompt_port "[VLESS + REALITY] 端口: " "")
    port_in_configured_protocol_state "${SB_PORT}" && { log_warn "端口已被现有协议配置占用: ${SB_PORT}"; continue; }
    check_port_conflict "${SB_PORT}"
    break
  done
  selected_port="${SB_PORT}"

  default_sni=""
  if load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" 2>/dev/null; then
    default_sni="${SB_SNI}"
  fi
  SB_VLESS_INSTANCE_ID="${selected_id}"
  SB_VLESS_INBOUND_TAG=""
  SB_NODE_NAME="${selected_node}"
  SB_PORT="${selected_port}"
  prompt_reality_sni_for_new_instance "${default_sni:-${SB_REALITY_SNI_FALLBACK}}"

  SB_UUID=""
  SB_SHORT_ID_1=""
  SB_SHORT_ID_2=""
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
  SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="n"
  prompt_vless_reality_rate_limit_fields
  prompt_vless_reality_advanced_update_fields
  validate_current_reality_sni_alpn_or_warn
  SB_OUTBOUND_POLICY=$(prompt_instance_outbound_policy "[VLESS + REALITY] 出站策略" "${SB_OUTBOUND_POLICY:-default}")
  if vless_reality_bandwidth_profile_exists "${SB_VLESS_RATE_LIMIT_UP_MBPS}" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" "${SB_VLESS_INSTANCE_ID}"; then
    log_warn "已存在相同类型且带宽配置完全相同的 VLESS + REALITY 节点，已取消创建。"
    return 0
  fi
  ensure_vless_reality_materials
  append_vless_reality_instance_id "${SB_VLESS_INSTANCE_ID}"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state
}

prompt_mixed_install() {
  local in_p in_auth in_user in_pass

  set_protocol_defaults "mixed"
  echo -e "\n${BLUE}--- 配置 Mixed ---${NC}"
  SB_PORT=$(prompt_port "[Mixed] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  SB_MIXED_AUTH_ENABLED=$(prompt_yes_no "[Mixed] 是否启用用户名密码认证 [y/n] (默认 y，强烈建议开启): " "y")
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

  SB_PORT=$(prompt_port "[Hysteria2] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  read -rp "[Hysteria2] 认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"
  read -rp "[Hysteria2] 用户名标识 (默认 ${SB_HY2_USER_NAME}): " in_user_name
  SB_HY2_USER_NAME=${in_user_name:-$SB_HY2_USER_NAME}

  SB_HY2_UP_MBPS=$(prompt_optional_positive_integer "[Hysteria2] 上行带宽 Mbps (留空表示不限制): " "" "上行带宽")
  SB_HY2_DOWN_MBPS=$(prompt_optional_positive_integer "[Hysteria2] 下行带宽 Mbps (留空表示不限制): " "" "下行带宽")

  SB_HY2_OBFS_ENABLED=$(prompt_yes_no "[Hysteria2] 是否启用 obfs / Salamander 混淆 [y/n] (默认 y): " "y")
  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    SB_HY2_OBFS_TYPE="salamander"
    read -rp "[Hysteria2] obfs / Salamander 混淆密码 (留空自动生成): " in_obfs_password
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  in_tls_mode=$(prompt_choice "[Hysteria2] 请选择 [1-2] (默认 1): " 1 2 1)
  case "${in_tls_mode}" in
    2) SB_HY2_TLS_MODE="manual" ;;
    *) SB_HY2_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_choice "[Hysteria2] 请选择 [1-2] (默认 1): " 1 2 1)
    case "${in_acme_mode}" in
      2) SB_HY2_ACME_MODE="dns" ;;
      *) SB_HY2_ACME_MODE="http" ;;
    esac

    SB_HY2_ACME_EMAIL=$(prompt_optional_email "[Hysteria2] ACME 邮箱 (可留空，用于证书通知): " "")
    SB_HY2_ACME_DOMAIN=$(prompt_optional_domain "[Hysteria2] ACME 域名 (默认 ${SB_HY2_DOMAIN}): " "${SB_HY2_DOMAIN}")

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "[Hysteria2] Cloudflare API Token: " in_cf_api_token
      SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_HY2_CERT_PATH}" ]]; do
      SB_HY2_CERT_PATH=$(prompt_required_path "[Hysteria2] 证书路径: ")
    done

    while [[ -z "${SB_HY2_KEY_PATH}" ]]; do
      SB_HY2_KEY_PATH=$(prompt_required_path "[Hysteria2] 私钥路径: ")
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

  SB_PORT=$(prompt_port "[AnyTLS] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  read -rp "[AnyTLS] 用户名标识 (默认 ${SB_ANYTLS_USER_NAME}): " in_user_name
  SB_ANYTLS_USER_NAME=${in_user_name:-$SB_ANYTLS_USER_NAME}

  read -rp "[AnyTLS] 认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_ANYTLS_PASSWORD="${in_password}"

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  in_tls_mode=$(prompt_choice "[AnyTLS] 请选择 [1-2] (默认 1): " 1 2 1)
  case "${in_tls_mode}" in
    2) SB_ANYTLS_TLS_MODE="manual" ;;
    *) SB_ANYTLS_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_ANYTLS_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_choice "[AnyTLS] 请选择 [1-2] (默认 1): " 1 2 1)
    case "${in_acme_mode}" in
      2) SB_ANYTLS_ACME_MODE="dns" ;;
      *) SB_ANYTLS_ACME_MODE="http" ;;
    esac

    SB_ANYTLS_ACME_EMAIL=$(prompt_optional_email "[AnyTLS] ACME 邮箱 (可留空，用于证书通知): " "")
    SB_ANYTLS_ACME_DOMAIN=$(prompt_optional_domain "[AnyTLS] ACME 域名 (默认 ${SB_ANYTLS_DOMAIN}): " "${SB_ANYTLS_DOMAIN}")

    if [[ "${SB_ANYTLS_ACME_MODE}" == "dns" ]]; then
      read -rp "[AnyTLS] Cloudflare API Token: " in_cf_api_token
      SB_ANYTLS_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_ANYTLS_CERT_PATH}" ]]; do
      SB_ANYTLS_CERT_PATH=$(prompt_required_path "[AnyTLS] 证书路径: ")
    done

    while [[ -z "${SB_ANYTLS_KEY_PATH}" ]]; do
      SB_ANYTLS_KEY_PATH=$(prompt_required_path "[AnyTLS] 私钥路径: ")
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

  SB_ADVANCED_ROUTE=$(prompt_yes_no "是否开启高级路由规则 (广告拦截/局域网绕行) [y/n] (默认 y): " "y")
  SB_ENABLE_WARP=$(prompt_yes_no "是否开启 Cloudflare Warp (用于解锁/防送中) [y/n] (默认 n): " "n")

  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    SB_WARP_ROUTE_MODE="selective"
    echo "Warp 路由模式:"
    echo "1. 全量流量走 Warp"
    echo "2. 仅 AI/流媒体及自定义规则走 Warp"
    in_warp_mode=$(prompt_choice "请选择 [1-2] (默认 2): " 1 2 2)
    case "${in_warp_mode}" in
      1) SB_WARP_ROUTE_MODE="all" ;;
      *) SB_WARP_ROUTE_MODE="selective" ;;
    esac
  fi
}

install_protocols_interactive() {
  local install_mode=$1
  local installed_protocols=() selected_protocols=()
  local protocol first_selected_protocol snapshot_dir

  load_stack_mode_state

  if [[ "${install_mode}" == "fresh" ]]; then
    get_os_info
    get_arch
    prompt_singbox_version
    prompt_protocol_install_selection "fresh" || return 0
    IFS=',' read -r -a selected_protocols <<< "${SELECTED_PROTOCOLS_CSV}"
    snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"

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
    snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"

    for protocol in "${selected_protocols[@]}"; do
      if [[ "${protocol}" == "vless-reality" ]] && protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
        prompt_vless_reality_instance_create
      else
        prompt_protocol_install_fields "${protocol}"
        save_protocol_state "${protocol}"
      fi
      if ! protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
        installed_protocols+=("${protocol}")
      fi
    done

    write_protocol_index "$(IFS=,; printf '%s' "${installed_protocols[*]}")"
  fi

  if ! save_warp_route_settings || ! generate_config; then
    abort_managed_state_transaction "${snapshot_dir}" "配置生成或校验失败"
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "安装配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
  if protocol_array_contains "vless-reality" "${selected_protocols[@]}"; then
    refresh_vless_reality_qos_rules
  fi
  setup_service
  first_selected_protocol="${selected_protocols[0]}"
  if [[ -n "${first_selected_protocol:-}" ]]; then
    load_protocol_state "${first_selected_protocol}"
  fi
  open_all_protocol_ports
  systemctl restart sing-box
  log_info "连接信息未自动展示，如需查看请进入菜单 11。"
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
    *)
      SB_PROTOCOL="vless+reality"
      SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
      SB_PORT="443"
      SB_SNI="${SB_REALITY_SNI_FALLBACK}"
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

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "本脚本必须以 root 用户执行。"
  fi
}

sanitize_sbv_detail() {
  local detail=${1:-}
  local sanitized

  if ! sanitized=$(printf '%s' "${detail}" | tr '\r\n' ' ' | sed -E \
    's#(https?://)[^/@[:space:]]+@#\1[REDACTED]@#g; s#((Proxy-Authorization|Authorization):[[:space:]]*).*$#\1[REDACTED]#I; s#([?&](token|password|secret|key)=)[^&[:space:]]+#\1[REDACTED]#gI'); then
    sanitized='unavailable'
  fi

  sanitized=${sanitized:0:400}
  if [[ -z "${sanitized}" ]]; then
    sanitized='no detail available'
  fi
  printf '%s' "${sanitized}"
}

read_sbv_detail_file() {
  local detail=''

  if [[ -f "${1:-}" ]]; then
    if ! detail=$(head -c "${SBV_CURL_STDERR_MAX_BYTES}" -- "${1}" 2>/dev/null | \
      tr '\r\n' ' '); then
      detail='unable to read diagnostic output'
    fi
  else
    detail='no diagnostic output captured'
  fi

  sanitize_sbv_detail "${detail}"
}

append_sbv_update_log() {
  local level=$1
  local message=$2

  if ! mkdir -p "${SB_PROJECT_DIR}" 2>/dev/null; then
    return 1
  fi
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "${message}" \
    >> "${SBV_LOG_FILE}" 2>/dev/null
}

reset_sbv_update_context() {
  SBV_UPDATE_OPERATION=''
  SBV_UPDATE_STAGE='precheck'
  SBV_UPDATE_ERROR_CODE=''
  SBV_UPDATE_ERROR_MESSAGE=''
  SBV_UPDATE_ERROR_DETAIL=''
  SBV_UPDATE_COMMAND_EXIT_CODE='0'
  SBV_UPDATE_HINT=''
  SBV_UPDATE_CHANGED='false'
  SBV_UPDATE_ROLLBACK_ATTEMPTED='false'
  SBV_UPDATE_ROLLED_BACK='false'
  SBV_UPDATE_ROLLBACK_OK='false'
  SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED='false'
  SBV_UPDATE_CURRENT_VERSION=''
  SBV_UPDATE_CANDIDATE_VERSION=''
  SBV_UPDATE_TARGET_PATH="${SBV_BIN_PATH}"
  SBV_UPDATE_LOG_FILE="${SBV_LOG_FILE}"
  SBV_UPDATE_TARGET_EXISTS='false'
  SBV_UPDATE_TARGET_MODE=''
  SBV_UPDATE_TARGET_UID=''
  SBV_UPDATE_TARGET_GID=''
  SBV_UPDATE_TARGET_HASH=''
  SBV_UPDATE_TARGET_VERSION=''
  SBV_UPDATE_EXPECTED_MODE=''
  SBV_UPDATE_EXPECTED_UID=''
  SBV_UPDATE_EXPECTED_GID=''
  SBV_UPDATE_CANDIDATE_PATH=''
  SBV_UPDATE_CANDIDATE_HASH=''
  SBV_UPDATE_CURL_STDERR_PATH=''
  SBV_UPDATE_BACKUP_PATH=''
  SBV_UPDATE_ROLLBACK_PATH=''
  SBV_UPDATE_LOCK_PATH=''
  SBV_UPDATE_LOCK_HELD='false'
  SBV_UPDATE_COMMITTED='false'
  SBV_UPDATE_NOOP='false'
  SBV_UPDATE_PRESERVE_ARTIFACTS='false'
  SBV_UPDATE_SIGNAL_NAME=''
  SBV_UPDATE_SIGNAL_CODE='0'
  SBV_UPDATE_TRAP_ACTIVE='false'
  SBV_UPDATE_TRAP_RUNNING='false'
  SBV_UPDATE_PREVIOUS_INT_TRAP=''
  SBV_UPDATE_PREVIOUS_TERM_TRAP=''
  SBV_UPDATE_PREVIOUS_HUP_TRAP=''
  SBV_UPDATE_PREVIOUS_ERR_TRAP=''
  SBV_VALIDATED_SCRIPT_VERSION=''
  SBV_SCRIPT_VALIDATION_CODE=''
  SBV_SCRIPT_VALIDATION_DETAIL=''
}

set_sbv_update_error() {
  local operation=${1:-${SBV_UPDATE_OPERATION:-sbv_update}}
  local stage=${2:-${SBV_UPDATE_STAGE:-unknown}}
  local code=${3:-update_failed}
  local message=${4:-操作失败}
  local detail=${5:-}
  local command_exit_code=${6:-0}
  local hint=${7:-}

  SBV_UPDATE_OPERATION=${operation}
  SBV_UPDATE_STAGE=${stage}
  SBV_UPDATE_ERROR_CODE=${code}
  SBV_UPDATE_ERROR_MESSAGE=${message}
  SBV_UPDATE_ERROR_DETAIL=$(sanitize_sbv_detail "${detail}")
  SBV_UPDATE_COMMAND_EXIT_CODE=${command_exit_code}
  SBV_UPDATE_HINT=${hint}
}

report_sbv_update_error() {
  local result='unchanged'
  local operation=${SBV_UPDATE_OPERATION:-sbv_update}
  local display_operation=${operation}
  local detail=${SBV_UPDATE_ERROR_DETAIL:-no detail available}

  case "${operation}" in
    sbv_update|ensure_sbv_local|ensure_sbv_remote) display_operation='sbv 自更新' ;;
    media_check_backend) display_operation='流媒体验证脚本下载' ;;
  esac

  if [[ "${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}" == 'true' ]]; then
    result='rollback_failed'
  elif [[ "${SBV_UPDATE_ROLLED_BACK}" == 'true' && "${SBV_UPDATE_ROLLBACK_OK}" == 'true' ]]; then
    result='rolled_back'
  fi

  printf '[ERROR] %s 失败\n' "${display_operation}" >&2
  printf '操作: %s\n' "${operation}" >&2
  printf '操作阶段: %s\n' "${SBV_UPDATE_STAGE:-unknown}" >&2
  printf '错误代码: %s\n' "${SBV_UPDATE_ERROR_CODE:-update_failed}" >&2
  printf '错误消息: %s\n' "${SBV_UPDATE_ERROR_MESSAGE:-操作失败}" >&2
  printf '底层退出码: %s\n' "${SBV_UPDATE_COMMAND_EXIT_CODE:-0}" >&2
  printf '错误详情: %s\n' "${detail}" >&2
  printf '上下文:\n' >&2
  printf '  operation: %s\n' "${operation}" >&2
  printf '  stage: %s\n' "${SBV_UPDATE_STAGE:-unknown}" >&2
  printf '  code: %s\n' "${SBV_UPDATE_ERROR_CODE:-update_failed}" >&2
  printf '  message: %s\n' "${SBV_UPDATE_ERROR_MESSAGE:-操作失败}" >&2
  printf '  detail: %s\n' "${detail}" >&2
  printf '  command_exit_code: %s\n' "${SBV_UPDATE_COMMAND_EXIT_CODE:-0}" >&2
  printf '  hint: %s\n' "${SBV_UPDATE_HINT:-}" >&2
  printf '状态:\n' >&2
  printf '  changed: %s\n' "${SBV_UPDATE_CHANGED}" >&2
  printf '  rollback_attempted: %s\n' "${SBV_UPDATE_ROLLBACK_ATTEMPTED}" >&2
  printf '  rolled_back: %s\n' "${SBV_UPDATE_ROLLED_BACK}" >&2
  printf '  rollback_ok: %s\n' "${SBV_UPDATE_ROLLBACK_OK}" >&2
  printf '  manual_intervention_required: %s\n' \
    "${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}" >&2
  printf '  处理结果: %s\n' "${result}" >&2
  printf '版本:\n' >&2
  printf '  current_version: %s\n' "${SBV_UPDATE_CURRENT_VERSION:-unknown}" >&2
  printf '  candidate_version: %s\n' "${SBV_UPDATE_CANDIDATE_VERSION:-unknown}" >&2
  printf '路径:\n' >&2
  printf '  target_path: %s\n' "${SBV_UPDATE_TARGET_PATH}" >&2
  printf '  target_sha256: %s\n' "${SBV_UPDATE_TARGET_HASH:-unknown}" >&2
  printf '  target_mode: %s\n' "${SBV_UPDATE_TARGET_MODE:-unknown}" >&2
  if [[ -n "${SBV_UPDATE_TARGET_UID}" && -n "${SBV_UPDATE_TARGET_GID}" ]]; then
    printf '  target_owner: %s:%s\n' "${SBV_UPDATE_TARGET_UID}" "${SBV_UPDATE_TARGET_GID}" >&2
  else
    printf '  target_owner: unknown\n' >&2
  fi
  if [[ -n "${SBV_UPDATE_BACKUP_PATH}" ]]; then
    printf '  backup_path: %s\n' "${SBV_UPDATE_BACKUP_PATH}" >&2
  fi
  if [[ -n "${SBV_UPDATE_CANDIDATE_PATH}" ]]; then
    printf '  candidate_path: %s\n' "${SBV_UPDATE_CANDIDATE_PATH}" >&2
  fi
  printf '  candidate_sha256: %s\n' "${SBV_UPDATE_CANDIDATE_HASH:-unknown}" >&2
  if [[ -n "${SBV_UPDATE_HINT}" ]]; then
    printf '建议: %s\n' "${SBV_UPDATE_HINT}" >&2
  fi
  printf '日志: %s\n' "${SBV_UPDATE_LOG_FILE}" >&2
  printf '  log_file: %s\n' "${SBV_UPDATE_LOG_FILE}" >&2

  append_sbv_update_log 'ERROR' \
    "${operation} ${SBV_UPDATE_ERROR_CODE:-update_failed}: ${SBV_UPDATE_ERROR_MESSAGE}; result=${result}; changed=${SBV_UPDATE_CHANGED}; rollback_attempted=${SBV_UPDATE_ROLLBACK_ATTEMPTED}; rolled_back=${SBV_UPDATE_ROLLED_BACK}; rollback_ok=${SBV_UPDATE_ROLLBACK_OK}; manual_intervention_required=${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}; detail=${detail}" \
    || true
}

extract_sbv_script_version() {
  local script_file=$1
  local match_count
  local script_version

  [[ -f "${script_file}" ]] || return 1
  match_count=$(grep -Ec '^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="[0-9]{10}"[[:space:]]*$' \
    "${script_file}" 2>/dev/null || true)
  [[ "${match_count}" == '1' ]] || return 1
  script_version=$(sed -nE \
    's/^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="([0-9]{10})"[[:space:]]*$/\1/p' \
    "${script_file}")
  [[ "${script_version}" =~ ^[0-9]{10}$ ]] || return 1
  printf '%s' "${script_version}"
}

set_sbv_script_validation_failure() {
  SBV_SCRIPT_VALIDATION_CODE=$1
  SBV_SCRIPT_VALIDATION_DETAIL=$2
  return 1
}

validate_sbv_script_file() {
  local script_file=$1
  local file_size
  local first_line=''
  local syntax_detail=''
  local script_version=''

  SBV_SCRIPT_VALIDATION_CODE=''
  SBV_SCRIPT_VALIDATION_DETAIL=''
  SBV_VALIDATED_SCRIPT_VERSION=''

  if [[ ! -f "${script_file}" ]]; then
    set_sbv_script_validation_failure 'candidate_missing' '候选文件不存在或不是普通文件'
    return 1
  fi
  if [[ -L "${script_file}" ]]; then
    set_sbv_script_validation_failure 'candidate_symlink' '候选文件是符号链接，已拒绝'
    return 1
  fi
  if ! file_size=$(wc -c < "${script_file}"); then
    set_sbv_script_validation_failure 'candidate_unreadable' '无法读取候选文件大小'
    return 1
  fi
  if (( file_size < SBV_SCRIPT_MIN_SIZE )); then
    set_sbv_script_validation_failure 'candidate_too_small' \
      "候选文件大小 ${file_size} 字节，小于最小要求 ${SBV_SCRIPT_MIN_SIZE} 字节"
    return 1
  fi
  IFS= read -r first_line < "${script_file}" || true
  if [[ "${first_line}" != '#!/usr/bin/env bash' ]]; then
    set_sbv_script_validation_failure 'candidate_shebang_invalid' \
      '候选文件缺少预期的 #!/usr/bin/env bash shebang'
    return 1
  fi
  if LC_ALL=C grep -Eiq '^[[:space:]]*(<!doctype[[:space:]]+html|<html|<body)' \
    "${script_file}"; then
    set_sbv_script_validation_failure 'candidate_html' '候选内容看起来是 HTML 或网关错误页'
    return 1
  fi
  if ! syntax_detail=$(bash -n -- "${script_file}" 2>&1); then
    set_sbv_script_validation_failure 'candidate_syntax_invalid' \
      "Bash 语法校验失败: ${syntax_detail}"
    return 1
  fi
  if ! script_version=$(extract_sbv_script_version "${script_file}"); then
    set_sbv_script_validation_failure 'candidate_version_invalid' \
      '必须存在且只能存在一个 YYYYMMDDXX 格式的 SCRIPT_VERSION'
    return 1
  fi
  if ! grep -Fqx 'readonly PROJECT_AUTHOR="KnowSky404"' "${script_file}"; then
    set_sbv_script_validation_failure 'candidate_identity_mismatch' \
      'PROJECT_AUTHOR 与 sing-box-vps 身份不匹配'
    return 1
  fi
  if ! grep -Fqx 'readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"' \
    "${script_file}"; then
    set_sbv_script_validation_failure 'candidate_identity_mismatch' \
      'PROJECT_URL 与 sing-box-vps 身份不匹配'
    return 1
  fi

  SBV_VALIDATED_SCRIPT_VERSION=${script_version}
  return 0
}

calculate_sbv_sha256() {
  command -v sha256sum >/dev/null 2>&1 || return 127
  sha256sum -- "$1" | awk '{print $1}'
}

get_sbv_file_metadata() {
  local metadata

  if ! metadata=$(stat -c '%a:%u:%g' -- "$1"); then
    return 1
  fi
  IFS=: read -r SBV_UPDATE_TARGET_MODE SBV_UPDATE_TARGET_UID SBV_UPDATE_TARGET_GID <<< \
    "${metadata}"
  [[ -n "${SBV_UPDATE_TARGET_MODE}" && -n "${SBV_UPDATE_TARGET_UID}" && \
    -n "${SBV_UPDATE_TARGET_GID}" ]]
}

sbv_update_signal_handler() {
  local signal_name=$1

  if [[ "${SBV_UPDATE_TRAP_RUNNING}" == 'true' ]]; then
    return 0
  fi
  SBV_UPDATE_TRAP_RUNNING='true'
  SBV_UPDATE_SIGNAL_NAME=${signal_name}
  case "${signal_name}" in
    INT) SBV_UPDATE_SIGNAL_CODE='130' ;;
    TERM) SBV_UPDATE_SIGNAL_CODE='143' ;;
    HUP) SBV_UPDATE_SIGNAL_CODE='129' ;;
    *) SBV_UPDATE_SIGNAL_CODE='1' ;;
  esac
  SBV_UPDATE_TRAP_RUNNING='false'
}

sbv_update_unexpected_error_handler() {
  local command_exit_code=${1:-1}

  if [[ "${SBV_UPDATE_TRAP_RUNNING}" == 'true' || \
    "${SBV_UPDATE_TRAP_ACTIVE}" != 'true' ]]; then
    return 0
  fi
  SBV_UPDATE_TRAP_RUNNING='true'
  if [[ -z "${SBV_UPDATE_ERROR_CODE}" ]]; then
    set_sbv_update_error \
      "${SBV_UPDATE_OPERATION:-sbv_update}" \
      "${SBV_UPDATE_STAGE:-unknown}" \
      'unexpected_error' \
      '更新过程中发生未预期异常' \
      '某个底层命令失败，详细命令内容未记录以避免泄露敏感信息' \
      "${command_exit_code}" \
      '检查日志中的阶段信息，并确认目标脚本及保留的恢复文件状态'
  fi
  SBV_UPDATE_TRAP_RUNNING='false'
}

install_sbv_update_traps() {
  SBV_UPDATE_PREVIOUS_INT_TRAP=$(trap -p INT || true)
  SBV_UPDATE_PREVIOUS_TERM_TRAP=$(trap -p TERM || true)
  SBV_UPDATE_PREVIOUS_HUP_TRAP=$(trap -p HUP || true)
  SBV_UPDATE_PREVIOUS_ERR_TRAP=$(trap -p ERR || true)
  trap 'sbv_update_signal_handler INT' INT
  trap 'sbv_update_signal_handler TERM' TERM
  trap 'sbv_update_signal_handler HUP' HUP
  trap 'sbv_update_unexpected_error_handler "$?"' ERR
  SBV_UPDATE_TRAP_ACTIVE='true'
}

restore_sbv_update_traps() {
  [[ "${SBV_UPDATE_TRAP_ACTIVE}" == 'true' ]] || return 0

  trap - INT TERM HUP ERR
  if [[ -n "${SBV_UPDATE_PREVIOUS_INT_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_INT_TRAP}" || true
  fi
  if [[ -n "${SBV_UPDATE_PREVIOUS_TERM_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_TERM_TRAP}" || true
  fi
  if [[ -n "${SBV_UPDATE_PREVIOUS_HUP_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_HUP_TRAP}" || true
  fi
  if [[ -n "${SBV_UPDATE_PREVIOUS_ERR_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_ERR_TRAP}" || true
  fi
  SBV_UPDATE_TRAP_ACTIVE='false'
}

prepare_sbv_update() {
  local target_dir
  local target_version=''

  SBV_UPDATE_STAGE='precheck'
  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  SBV_UPDATE_LOCK_PATH="${target_dir}/.sbv-update.lock"

  if [[ ! -d "${target_dir}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_directory_missing' \
      'sbv 目标目录不存在' "目标目录: ${target_dir}" 1 \
      '确认 /usr/local/bin 存在且当前用户具有 root 权限'
    return 1
  fi
  if [[ -L "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_symlink_unsupported' \
      'sbv 目标是符号链接，已安全拒绝更新' "目标路径: ${SBV_BIN_PATH}" 1 \
      '请先将符号链接解析为受管普通文件后再更新'
    return 1
  fi
  if [[ -e "${SBV_BIN_PATH}" && ! -f "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_not_regular' \
      'sbv 目标不是普通文件，已安全拒绝更新' "目标路径: ${SBV_BIN_PATH}" 1 \
      '移除目录或特殊文件后再重试；目标未发生变更'
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'curl_unavailable' \
      '找不到 curl，无法下载候选脚本' 'curl command not found' 127 \
      '安装 curl 后重试'
    return 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'sha256sum_unavailable' \
      '找不到 sha256sum，无法核对候选完整性' 'sha256sum command not found' 127 \
      '安装提供 sha256sum 的系统工具后重试'
    return 1
  fi
  if ! mkdir "${SBV_UPDATE_LOCK_PATH}" 2>/dev/null; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'update_in_progress' \
      '已有另一个 sbv 更新事务正在运行' "锁路径: ${SBV_UPDATE_LOCK_PATH}" 1 \
      '等待现有更新结束后再重试；未取得锁时目标未发生变更'
    return 1
  fi
  SBV_UPDATE_LOCK_HELD='true'

  if [[ -f "${SBV_BIN_PATH}" ]]; then
    SBV_UPDATE_TARGET_EXISTS='true'
    if ! get_sbv_file_metadata "${SBV_BIN_PATH}"; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_metadata_failed' \
        '无法读取现有 sbv 的权限或所有者' "目标路径: ${SBV_BIN_PATH}" 1 \
        '检查目标文件及 /usr/local/bin 的权限'
      return 1
    fi
    if ! SBV_UPDATE_TARGET_HASH=$(calculate_sbv_sha256 "${SBV_BIN_PATH}"); then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_hash_failed' \
        '无法计算现有 sbv 的 SHA-256' "目标路径: ${SBV_BIN_PATH}" 1 \
        '检查目标文件是否可读'
      return 1
    fi
    if target_version=$(extract_sbv_script_version "${SBV_BIN_PATH}"); then
      SBV_UPDATE_TARGET_VERSION=${target_version}
      SBV_UPDATE_CURRENT_VERSION=${target_version}
    else
      SBV_UPDATE_CURRENT_VERSION=${SCRIPT_VERSION}
    fi
  else
    SBV_UPDATE_CURRENT_VERSION=${SCRIPT_VERSION}
  fi
  return 0
}

create_sbv_candidate() {
  local target_dir

  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if ! SBV_UPDATE_CANDIDATE_PATH=$(mktemp "${target_dir}/.sbv-candidate.XXXXXXXXXX"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'candidate_create_failed' \
      '无法创建同目录候选文件' "候选目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    return 1
  fi
  if ! SBV_UPDATE_CURL_STDERR_PATH=$(mktemp "${target_dir}/.sbv-curl-stderr.XXXXXXXXXX"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'diagnostic_file_create_failed' \
      '无法创建下载诊断文件' "诊断目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    return 1
  fi
  return 0
}

classify_sbv_download_error() {
  case "${1:-}" in
    6) printf 'download_dns_failure' ;;
    7) printf 'download_connection_failed' ;;
    18) printf 'download_partial_transfer' ;;
    28) printf 'download_timeout' ;;
    130|143|129) printf 'signal_interrupted' ;;
    *) printf 'download_failed' ;;
  esac
}

stage_sbv_candidate_from_url() {
  local url=$1
  local curl_status=0
  local detail=''

  if ! create_sbv_candidate; then
    return 1
  fi
  if curl -fsSL \
    --connect-timeout "${SBV_CURL_CONNECT_TIMEOUT}" \
    --max-time "${SBV_CURL_MAX_TIME}" \
    --retry "${SBV_CURL_RETRY_COUNT}" \
    --retry-delay "${SBV_CURL_RETRY_DELAY}" \
    -o "${SBV_UPDATE_CANDIDATE_PATH}" "${url}" \
    2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    curl_status=0
  else
    curl_status=$?
  fi
  SBV_UPDATE_COMMAND_EXIT_CODE=${curl_status}
  if [[ "${SBV_UPDATE_SIGNAL_CODE}" != '0' ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'download' 'signal_interrupted' \
      "下载过程中收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${SBV_UPDATE_SIGNAL_CODE}" \
      '重新运行更新；提交前目标脚本保持不变'
    return "${SBV_UPDATE_SIGNAL_CODE}"
  fi
  if [[ "${curl_status}" != '0' ]]; then
    detail=$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'download' "$(classify_sbv_download_error "${curl_status}")" \
      '下载最新 sbv 脚本失败' "${detail}" "${curl_status}" \
      '检查 DNS、IPv4/IPv6 出口、路由或 HTTPS_PROXY；原脚本未发生变更'
    return "${curl_status}"
  fi
  return 0
}

stage_sbv_candidate_from_file() {
  local source_file=$1

  if ! create_sbv_candidate; then
    return 1
  fi
  if [[ ! -f "${source_file}" || -L "${source_file}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'source_not_regular' \
      '当前脚本来源不是可读取的普通文件' "来源路径: ${source_file}" 1 \
      '请从真实文件路径运行 install.sh'
    return 1
  fi
  if ! cp -p -- "${source_file}" "${SBV_UPDATE_CANDIDATE_PATH}" 2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'candidate_copy_failed' \
      '无法将当前脚本复制到候选文件' \
      "$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")" 1 \
      '检查目标目录的磁盘空间和权限'
    return 1
  fi
  return 0
}

sbv_target_is_healthy() {
  [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]] || return 1
  [[ -f "${SBV_BIN_PATH}" && -x "${SBV_BIN_PATH}" ]] || return 1
  validate_sbv_script_file "${SBV_BIN_PATH}"
}

validate_sbv_candidate() {
  local candidate_version
  local validation_code
  local validation_detail

  SBV_UPDATE_STAGE='validate'
  if ! validate_sbv_script_file "${SBV_UPDATE_CANDIDATE_PATH}"; then
    validation_code=${SBV_SCRIPT_VALIDATION_CODE:-candidate_invalid}
    validation_detail=${SBV_SCRIPT_VALIDATION_DETAIL:-候选文件校验失败}
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'validate' "${validation_code}" \
      '候选 sbv 脚本校验失败' "${validation_detail}" 1 \
      '拒绝提交候选文件；原脚本未发生变更'
    return 1
  fi
  candidate_version=${SBV_VALIDATED_SCRIPT_VERSION}
  SBV_UPDATE_CANDIDATE_VERSION=${candidate_version}
  if ! SBV_UPDATE_CANDIDATE_HASH=$(calculate_sbv_sha256 "${SBV_UPDATE_CANDIDATE_PATH}"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'validate' 'candidate_hash_failed' \
      '无法计算候选 sbv 的 SHA-256' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '拒绝提交候选文件；原脚本未发生变更'
    return 1
  fi

  if [[ "${SBV_UPDATE_CURRENT_VERSION}" =~ ^[0-9]{10}$ ]] && \
    (( 10#${candidate_version} < 10#${SBV_UPDATE_CURRENT_VERSION} )); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'validate' 'candidate_version_downgrade' \
      '候选 sbv 版本低于当前版本，已拒绝降级' \
      "当前版本: ${SBV_UPDATE_CURRENT_VERSION}; 候选版本: ${candidate_version}" 1 \
      '确认远端分支和当前版本来源后再重试'
    return 1
  fi

  if [[ "${candidate_version}" == "${SBV_UPDATE_CURRENT_VERSION}" ]] && \
    sbv_target_is_healthy; then
    SBV_UPDATE_NOOP='true'
  fi
  return 0
}

create_sbv_backup() {
  local target_dir

  SBV_UPDATE_STAGE='backup'
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" != 'true' ]]; then
    return 0
  fi
  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if ! SBV_UPDATE_BACKUP_PATH=$(mktemp "${target_dir}/.sbv-backup.XXXXXXXXXX"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_create_failed' \
      '无法创建受保护的 sbv 备份' "备份目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限；原脚本未发生变更'
    return 1
  fi
  if ! cp -p -- "${SBV_BIN_PATH}" "${SBV_UPDATE_BACKUP_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_copy_failed' \
      '无法创建现有 sbv 的备份' "目标路径: ${SBV_BIN_PATH}" 1 \
      '检查目标文件是否可读；原脚本未发生变更'
    return 1
  fi
  if ! chmod 0600 "${SBV_UPDATE_BACKUP_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_protect_failed' \
      '无法设置 sbv 备份的 root-only 权限' \
      "备份路径: ${SBV_UPDATE_BACKUP_PATH}" 1 \
      '检查文件系统权限；原脚本未发生变更'
    return 1
  fi
  if ! chown 0:0 "${SBV_UPDATE_BACKUP_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_protect_failed' \
      '无法将 sbv 备份设置为 root 所有' \
      "备份路径: ${SBV_UPDATE_BACKUP_PATH}" 1 \
      '检查文件系统权限；原脚本未发生变更'
    return 1
  fi
  return 0
}

prepare_sbv_candidate_for_commit() {
  local candidate_mode='0755'

  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' && \
    -x "${SBV_BIN_PATH}" ]]; then
    candidate_mode=${SBV_UPDATE_TARGET_MODE}
  fi
  SBV_UPDATE_EXPECTED_MODE=${candidate_mode}
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]]; then
    SBV_UPDATE_EXPECTED_UID=${SBV_UPDATE_TARGET_UID}
    SBV_UPDATE_EXPECTED_GID=${SBV_UPDATE_TARGET_GID}
  fi
  if ! chmod "${candidate_mode}" "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'candidate_chmod_failed' \
      '无法设置候选 sbv 的执行权限' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '检查目标目录的权限；原脚本未发生变更'
    return 1
  fi
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]] && \
    ! chown "${SBV_UPDATE_TARGET_UID}:${SBV_UPDATE_TARGET_GID}" \
      "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'candidate_chown_failed' \
      '无法保留 sbv 原有所有者' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '检查 chown 权限；原脚本未发生变更'
    return 1
  fi
  return 0
}

commit_sbv_candidate() {
  SBV_UPDATE_STAGE='commit'
  if ! prepare_sbv_candidate_for_commit; then
    return 1
  fi
  if ! mv -f -- "${SBV_UPDATE_CANDIDATE_PATH}" "${SBV_BIN_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'atomic_replace_failed' \
      '无法原子替换 sbv 目标文件' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '检查目标目录权限和文件系统状态；原脚本未发生变更'
    return 1
  fi
  SBV_UPDATE_COMMITTED='true'
  SBV_UPDATE_CHANGED='true'
  return 0
}

postcheck_sbv_update() {
  local actual_hash
  local actual_mode
  local actual_uid
  local actual_gid

  SBV_UPDATE_STAGE='postcheck'
  if [[ ! -f "${SBV_BIN_PATH}" || -L "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'target_missing_after_commit' \
      '提交后未找到有效的 sbv 目标文件' "目标路径: ${SBV_BIN_PATH}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if ! validate_sbv_script_file "${SBV_BIN_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_validation_failed' \
      '提交后的 sbv 脚本校验失败' \
      "${SBV_SCRIPT_VALIDATION_DETAIL:-目标校验失败}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ "${SBV_VALIDATED_SCRIPT_VERSION}" != "${SBV_UPDATE_CANDIDATE_VERSION}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_version_mismatch' \
      '提交后的 sbv 版本与候选版本不一致' \
      "目标版本: ${SBV_VALIDATED_SCRIPT_VERSION}; 候选版本: ${SBV_UPDATE_CANDIDATE_VERSION}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if ! actual_hash=$(calculate_sbv_sha256 "${SBV_BIN_PATH}"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_hash_failed' \
      '无法计算提交后 sbv 的 SHA-256' "目标路径: ${SBV_BIN_PATH}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ "${actual_hash}" != "${SBV_UPDATE_CANDIDATE_HASH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_hash_mismatch' \
      '提交后的 sbv SHA-256 与候选不一致' \
      "候选哈希: ${SBV_UPDATE_CANDIDATE_HASH}; 目标哈希: ${actual_hash}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ ! -x "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_not_executable' \
      '提交后的 sbv 不可执行' "目标路径: ${SBV_BIN_PATH}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]]; then
    if ! actual_mode=$(stat -c '%a' -- "${SBV_BIN_PATH}") || \
      ! actual_uid=$(stat -c '%u' -- "${SBV_BIN_PATH}") || \
      ! actual_gid=$(stat -c '%g' -- "${SBV_BIN_PATH}"); then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_metadata_failed' \
        '无法读取提交后 sbv 的权限或所有者' "目标路径: ${SBV_BIN_PATH}" 1 \
        '事务将尝试恢复更新前的脚本'
      return 1
    fi
    if [[ "${actual_mode}" != "${SBV_UPDATE_EXPECTED_MODE}" || \
      "${actual_uid}" != "${SBV_UPDATE_EXPECTED_UID}" || \
      "${actual_gid}" != "${SBV_UPDATE_EXPECTED_GID}" ]]; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_metadata_mismatch' \
        '提交后的 sbv 权限或所有者与预期不一致' \
        "实际: ${actual_mode}:${actual_uid}:${actual_gid}; 预期: ${SBV_UPDATE_EXPECTED_MODE}:${SBV_UPDATE_EXPECTED_UID}:${SBV_UPDATE_EXPECTED_GID}" 1 \
        '事务将尝试恢复更新前的脚本'
      return 1
    fi
  fi
  return 0
}

restore_sbv_backup() {
  local target_dir
  local restore_path

  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" != 'true' ]]; then
    if ! rm -f -- "${SBV_BIN_PATH}"; then
      return 1
    fi
    return 0
  fi
  [[ -f "${SBV_UPDATE_BACKUP_PATH}" ]] || return 1
  if ! restore_path=$(mktemp "${target_dir}/.sbv-rollback.XXXXXXXXXX"); then
    return 1
  fi
  SBV_UPDATE_ROLLBACK_PATH=${restore_path}
  if ! cp -p -- "${SBV_UPDATE_BACKUP_PATH}" "${restore_path}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  if ! chmod "${SBV_UPDATE_TARGET_MODE}" "${restore_path}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  if ! chown "${SBV_UPDATE_TARGET_UID}:${SBV_UPDATE_TARGET_GID}" "${restore_path}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  if ! mv -f -- "${restore_path}" "${SBV_BIN_PATH}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  SBV_UPDATE_ROLLBACK_PATH=''
  return 0
}

verify_sbv_rollback() {
  local restored_hash

  if [[ "${SBV_UPDATE_TARGET_EXISTS}" != 'true' ]]; then
    [[ ! -e "${SBV_BIN_PATH}" && ! -L "${SBV_BIN_PATH}" ]] || return 1
    return 0
  fi
  [[ -f "${SBV_BIN_PATH}" && -x "${SBV_BIN_PATH}" ]] || return 1
  validate_sbv_script_file "${SBV_BIN_PATH}" || return 1
  [[ "${SBV_VALIDATED_SCRIPT_VERSION}" == "${SBV_UPDATE_TARGET_VERSION}" ]] || return 1
  restored_hash=$(calculate_sbv_sha256 "${SBV_BIN_PATH}") || return 1
  [[ "${restored_hash}" == "${SBV_UPDATE_TARGET_HASH}" ]] || return 1
  [[ "$(stat -c '%a' -- "${SBV_BIN_PATH}")" == "${SBV_UPDATE_TARGET_MODE}" ]] || return 1
  [[ "$(stat -c '%u' -- "${SBV_BIN_PATH}")" == "${SBV_UPDATE_TARGET_UID}" ]] || return 1
  [[ "$(stat -c '%g' -- "${SBV_BIN_PATH}")" == "${SBV_UPDATE_TARGET_GID}" ]] || return 1
  return 0
}

preserve_sbv_recovery_artifacts() {
  local target_dir
  local retained_candidate=''

  SBV_UPDATE_PRESERVE_ARTIFACTS='true'
  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if [[ -f "${SBV_BIN_PATH}" ]]; then
    if retained_candidate=$(mktemp "${target_dir}/.sbv-candidate-retained.XXXXXXXXXX"); then
      if cp -p -- "${SBV_BIN_PATH}" "${retained_candidate}" && \
        chmod 0600 "${retained_candidate}" && chown 0:0 "${retained_candidate}"; then
        SBV_UPDATE_CANDIDATE_PATH=${retained_candidate}
      else
        rm -f -- "${retained_candidate}" || true
      fi
    fi
  fi
}

cleanup_sbv_update() {
  if [[ "${SBV_UPDATE_PRESERVE_ARTIFACTS}" != 'true' ]]; then
    rm -f -- \
      "${SBV_UPDATE_CANDIDATE_PATH}" \
      "${SBV_UPDATE_CURL_STDERR_PATH}" \
      "${SBV_UPDATE_ROLLBACK_PATH}" \
      "${SBV_UPDATE_BACKUP_PATH}" 2>/dev/null || true
  fi
  if [[ "${SBV_UPDATE_LOCK_HELD}" == 'true' ]]; then
    rmdir "${SBV_UPDATE_LOCK_PATH}" 2>/dev/null || true
    SBV_UPDATE_LOCK_HELD='false'
  fi
}

finish_sbv_update_failure() {
  local result_status=${1:-1}
  local original_status=${result_status}
  local original_error_code=''

  if [[ -z "${SBV_UPDATE_ERROR_CODE}" ]]; then
    if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" "${SBV_UPDATE_STAGE:-unknown}" \
        'signal_interrupted' "更新过程中收到 ${SBV_UPDATE_SIGNAL_NAME}" \
        "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${SBV_UPDATE_SIGNAL_CODE}" \
        '重新运行更新；提交前目标脚本保持不变'
    else
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" "${SBV_UPDATE_STAGE:-unknown}" \
        'update_failed' 'sbv 更新事务失败' '未提供额外诊断信息' "${result_status}" \
        '原脚本未发生变更，检查日志后重试'
    fi
  fi

  if [[ "${SBV_UPDATE_COMMITTED}" == 'true' ]]; then
    SBV_UPDATE_ROLLBACK_ATTEMPTED='true'
    if restore_sbv_backup && verify_sbv_rollback; then
      SBV_UPDATE_ROLLED_BACK='true'
      SBV_UPDATE_ROLLBACK_OK='true'
    else
      original_error_code=${SBV_UPDATE_ERROR_CODE:-update_failed}
      SBV_UPDATE_ERROR_CODE='rollback_failed'
      SBV_UPDATE_ERROR_MESSAGE='提交后失败且自动恢复未通过最终校验'
      SBV_UPDATE_ERROR_DETAIL=$(sanitize_sbv_detail \
        "${SBV_UPDATE_ERROR_DETAIL}; 原始错误码: ${original_error_code}")
      SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED='true'
      result_status=1
      preserve_sbv_recovery_artifacts
      SBV_UPDATE_HINT='请使用保留的 backup_path 和 candidate_path 人工恢复，并重新校验 bash -n、版本、SHA-256 与执行权限'
    fi
  fi

  cleanup_sbv_update
  restore_sbv_update_traps
  report_sbv_update_error
  if [[ "${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}" != 'true' ]]; then
    result_status=${original_status}
  fi
  return "${result_status}"
}

finish_sbv_update_success() {
  cleanup_sbv_update
  restore_sbv_update_traps
  if [[ "${SBV_UPDATE_NOOP}" == 'true' ]]; then
    printf '[INFO] sbv 已是当前版本 %s，事务 no-op，目标文件未替换（changed: false）。\n' \
      "${SBV_UPDATE_CURRENT_VERSION}"
  else
    printf '[SUCCESS] sbv 已完成原子更新到版本 %s（changed: true）。候选 SHA-256 已在本地提交后核对。\n' \
      "${SBV_UPDATE_CANDIDATE_VERSION}"
  fi
  return 0
}

sbv_update_transaction() {
  local operation=$1
  local source_kind=$2
  local source=$3
  local result_status=1

  reset_sbv_update_context
  SBV_UPDATE_OPERATION=${operation}
  SBV_UPDATE_TARGET_PATH=${SBV_BIN_PATH}
  SBV_UPDATE_LOG_FILE=${SBV_LOG_FILE}
  install_sbv_update_traps

  if prepare_sbv_update; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi

  SBV_UPDATE_STAGE='stage'
  case "${source_kind}" in
    url)
      if stage_sbv_candidate_from_url "${source}"; then
        :
      else
        result_status=$?
        finish_sbv_update_failure "${result_status}" || return $?
        return 0
      fi
      ;;
    file)
      if stage_sbv_candidate_from_file "${source}"; then
        :
      else
        result_status=$?
        finish_sbv_update_failure "${result_status}" || return $?
        return 0
      fi
      ;;
    *)
      set_sbv_update_error "${operation}" 'stage' 'source_kind_invalid' \
        '未知的 sbv 候选来源类型' "来源类型: ${source_kind}" 1 \
        '使用 file 或 url 来源'
      finish_sbv_update_failure 1 || return $?
      return 0
      ;;
  esac
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi

  if validate_sbv_candidate; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ "${SBV_UPDATE_NOOP}" == 'true' ]]; then
    finish_sbv_update_success
    return 0
  fi
  if create_sbv_backup; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if commit_sbv_candidate; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  SBV_UPDATE_STAGE='postcheck'
  if postcheck_sbv_update; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  finish_sbv_update_success
}

finish_sbv_artifact_failure() {
  local result_status=${1:-1}

  cleanup_sbv_update
  restore_sbv_update_traps
  report_sbv_update_error
  return "${result_status}"
}

finish_sbv_artifact_success() {
  cleanup_sbv_update
  restore_sbv_update_traps
  return 0
}

download_shell_artifact_atomically() {
  local operation=$1
  local url=$2
  local target=$3
  local target_dir
  local target_name
  local lock_path
  local lock_status=0
  local curl_status=0
  local detail=''
  local file_size
  local first_line=''
  local syntax_detail=''
  local target_existed='false'
  local old_mode='0755'
  local old_uid=''
  local old_gid=''
  local old_hash=''
  local actual_mode=''
  local actual_uid=''
  local actual_gid=''
  local restore_hash=''
  local retained_candidate=''
  local result_status=1
  local expected_mode='755'
  local postcheck_failed='false'
  local postcheck_code='postcheck_failed'

  reset_sbv_update_context
  SBV_UPDATE_OPERATION=${operation}
  SBV_UPDATE_TARGET_PATH=${target}
  SBV_UPDATE_LOG_FILE=${SBV_LOG_FILE}
  target_dir=$(dirname -- "${target}")
  target_name=${target##*/}
  lock_path="${target_dir}/.${target_name}.update.lock"
  SBV_UPDATE_LOCK_PATH=${lock_path}

  if [[ ! -d "${target_dir}" ]]; then
    set_sbv_update_error "${operation}" 'precheck' 'target_directory_missing' \
      '可执行 artifact 目标目录不存在' "目标目录: ${target_dir}" 1 \
      '检查目标目录的权限'
    report_sbv_update_error
    return 1
  fi
  if [[ -L "${target}" || ( -e "${target}" && ! -f "${target}" ) ]]; then
    set_sbv_update_error "${operation}" 'precheck' 'target_not_regular' \
      '可执行 artifact 目标不是普通文件' "目标路径: ${target}" 1 \
      '检查目标路径后重试；目标未发生变更'
    report_sbv_update_error
    return 1
  fi

  install_sbv_update_traps
  if mkdir "${lock_path}" 2>/dev/null; then
    :
  else
    lock_status=$?
    if [[ -e "${lock_path}" || -L "${lock_path}" ]]; then
      set_sbv_update_error "${operation}" 'precheck' 'update_in_progress' \
        '已有另一个可执行 artifact 更新事务正在运行' "锁路径: ${lock_path}" 1 \
        '等待现有更新结束后再重试；未取得锁时目标未发生变更'
      lock_status=1
    else
      set_sbv_update_error "${operation}" 'precheck' 'lock_create_failed' \
        '无法创建可执行 artifact 更新锁' "锁路径: ${lock_path}" "${lock_status}" \
        '检查目标目录的写权限、磁盘空间和文件系统状态；目标未发生变更'
    fi
    finish_sbv_artifact_failure "${lock_status}" || return $?
    return 0
  fi
  SBV_UPDATE_LOCK_HELD='true'
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'precheck' 'signal_interrupted' \
      "更新过程中收到 ${SBV_UPDATE_SIGNAL_NAME}" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -L "${target}" || ( -e "${target}" && ! -f "${target}" ) ]]; then
    set_sbv_update_error "${operation}" 'precheck' 'target_not_regular' \
      '加锁后发现 artifact 目标不是普通文件' "目标路径: ${target}" 1 \
      '检查目标路径后重试；目标未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi

  SBV_UPDATE_STAGE='stage'
  if ! SBV_UPDATE_CANDIDATE_PATH=$(mktemp "${target_dir}/.${target_name}.candidate.XXXXXXXXXX"); then
    set_sbv_update_error "${operation}" 'stage' 'candidate_create_failed' \
      '无法创建可执行 artifact 候选文件' "候选目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if ! SBV_UPDATE_CURL_STDERR_PATH=$(mktemp "${target_dir}/.${target_name}.stderr.XXXXXXXXXX"); then
    set_sbv_update_error "${operation}" 'stage' 'diagnostic_file_create_failed' \
      '无法创建下载诊断文件' "诊断目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if curl -fsSL \
    --connect-timeout "${SBV_CURL_CONNECT_TIMEOUT}" \
    --max-time "${SBV_CURL_MAX_TIME}" \
    --retry "${SBV_CURL_RETRY_COUNT}" \
    --retry-delay "${SBV_CURL_RETRY_DELAY}" \
    -o "${SBV_UPDATE_CANDIDATE_PATH}" "${url}" \
    2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    curl_status=0
  else
    curl_status=$?
  fi
  SBV_UPDATE_COMMAND_EXIT_CODE=${curl_status}
  if [[ "${SBV_UPDATE_SIGNAL_CODE}" != '0' ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'download' 'signal_interrupted' \
      "下载过程中收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi
  if [[ "${curl_status}" != '0' ]]; then
    detail=$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")
    set_sbv_update_error "${operation}" 'download' "$(classify_sbv_download_error "${curl_status}")" \
      '下载可执行 artifact 失败' "${detail}" "${curl_status}" \
      '检查 DNS、IPv4/IPv6 出口、路由或 HTTPS_PROXY；原文件未发生变更'
    finish_sbv_artifact_failure "${curl_status}" || return $?
    return 0
  fi

  SBV_UPDATE_STAGE='validate'
  if ! file_size=$(wc -c < "${SBV_UPDATE_CANDIDATE_PATH}"); then
    set_sbv_update_error "${operation}" 'validate' 'artifact_size_check_failed' \
      '无法读取下载的 artifact 大小' "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if (( file_size < SBV_ARTIFACT_MIN_SIZE )); then
    set_sbv_update_error "${operation}" 'validate' 'artifact_too_small' \
      '下载的可执行 artifact 为空或过小' "文件大小: ${file_size} 字节" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  IFS= read -r first_line < "${SBV_UPDATE_CANDIDATE_PATH}" || true
  if [[ ! "${first_line}" =~ ^#!.*(bash|sh)([[:space:]]|$) ]]; then
    set_sbv_update_error "${operation}" 'validate' 'artifact_shebang_invalid' \
      '远程 artifact 缺少可识别的 Shell shebang' "首行: ${first_line}" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if LC_ALL=C grep -Eiq '^[[:space:]]*(<!doctype[[:space:]]+html|<html|<body)' \
    "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${operation}" 'validate' 'artifact_html' \
      '远程 artifact 看起来是 HTML 或网关错误页' 'HTML marker detected' 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if ! syntax_detail=$(bash -n -- "${SBV_UPDATE_CANDIDATE_PATH}" 2>&1); then
    set_sbv_update_error "${operation}" 'validate' 'artifact_syntax_invalid' \
      '远程 artifact 未通过 Bash 语法校验' "${syntax_detail}" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'validate' 'signal_interrupted' \
      "校验过程中收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi

  if [[ -f "${target}" ]]; then
    target_existed='true'
    SBV_UPDATE_TARGET_EXISTS='true'
    if ! get_sbv_file_metadata "${target}"; then
      set_sbv_update_error "${operation}" 'backup' 'target_metadata_failed' \
        '无法读取现有 artifact 的权限或所有者' "目标路径: ${target}" 1 \
        '检查目标文件权限；原文件未发生变更'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    old_mode=${SBV_UPDATE_TARGET_MODE}
    old_uid=${SBV_UPDATE_TARGET_UID}
    old_gid=${SBV_UPDATE_TARGET_GID}
    if ! old_hash=$(calculate_sbv_sha256 "${target}"); then
      set_sbv_update_error "${operation}" 'backup' 'target_hash_failed' \
        '无法计算现有 artifact 的 SHA-256' "目标路径: ${target}" 1 \
        '检查目标文件是否可读；原文件未发生变更'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    SBV_UPDATE_TARGET_HASH=${old_hash}
    if ! SBV_UPDATE_TARGET_VERSION=$(extract_sbv_script_version "${target}"); then
      SBV_UPDATE_TARGET_VERSION='unknown'
    fi
    SBV_UPDATE_CURRENT_VERSION=${SBV_UPDATE_TARGET_VERSION}
    if ! SBV_UPDATE_BACKUP_PATH=$(mktemp "${target_dir}/.${target_name}.backup.XXXXXXXXXX"); then
      set_sbv_update_error "${operation}" 'backup' 'backup_create_failed' \
        '无法创建现有 artifact 的受保护备份' "目标目录: ${target_dir}" 1 \
        '原文件未发生变更；检查目标目录的权限'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    if ! cp -p -- "${target}" "${SBV_UPDATE_BACKUP_PATH}"; then
      set_sbv_update_error "${operation}" 'backup' 'backup_copy_failed' \
        '无法复制现有 artifact 到受保护备份' "目标路径: ${target}" 1 \
        '原文件未发生变更；检查目标目录的权限'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    if ! chmod 0600 "${SBV_UPDATE_BACKUP_PATH}" || \
      ! chown 0:0 "${SBV_UPDATE_BACKUP_PATH}"; then
      set_sbv_update_error "${operation}" 'backup' 'backup_protect_failed' \
        '无法将 artifact 备份设置为 root-only' \
        "备份路径: ${SBV_UPDATE_BACKUP_PATH}" 1 \
        '检查文件系统权限；原文件未发生变更'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
  else
    SBV_UPDATE_CURRENT_VERSION='unknown'
  fi

  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'backup' 'signal_interrupted' \
      "备份阶段收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi

  if [[ "${target_existed}" == 'true' && -x "${target}" ]]; then
    expected_mode=${old_mode}
  fi
  SBV_UPDATE_EXPECTED_MODE=${expected_mode}
  if ! chmod "${expected_mode}" "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${operation}" 'commit' 'candidate_chmod_failed' \
      '无法设置 artifact 执行权限' "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if [[ "${target_existed}" == 'true' ]] && \
    ! chown "${old_uid}:${old_gid}" "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${operation}" 'commit' 'candidate_chown_failed' \
      '无法保留 artifact 原有所有者' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'commit' 'signal_interrupted' \
      "提交前收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi
  if [[ "${target_existed}" == 'true' ]]; then
    SBV_UPDATE_EXPECTED_UID=${old_uid}
    SBV_UPDATE_EXPECTED_GID=${old_gid}
  else
    SBV_UPDATE_EXPECTED_MODE='755'
  fi
  SBV_UPDATE_STAGE='commit'
  if ! mv -f -- "${SBV_UPDATE_CANDIDATE_PATH}" "${target}"; then
    set_sbv_update_error "${operation}" 'commit' 'atomic_replace_failed' \
      '无法原子替换可执行 artifact' "目标路径: ${target}" 1 \
      '原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  SBV_UPDATE_COMMITTED='true'
  SBV_UPDATE_CHANGED='true'

  SBV_UPDATE_STAGE='postcheck'
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    postcheck_failed='true'
    postcheck_code='signal_interrupted'
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    detail="信号: ${SBV_UPDATE_SIGNAL_NAME}"
    SBV_UPDATE_COMMAND_EXIT_CODE=${result_status}
  elif [[ ! -f "${target}" || -L "${target}" ]]; then
    postcheck_failed='true'
    postcheck_code='postcheck_target_invalid'
    detail="目标路径: ${target}"
    SBV_UPDATE_COMMAND_EXIT_CODE='1'
  elif ! bash -n -- "${target}" 2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    postcheck_failed='true'
    postcheck_code='postcheck_syntax_invalid'
    detail=$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")
    SBV_UPDATE_COMMAND_EXIT_CODE='1'
  elif [[ ! -x "${target}" ]]; then
    postcheck_failed='true'
    postcheck_code='postcheck_not_executable'
    detail="目标路径: ${target}"
    SBV_UPDATE_COMMAND_EXIT_CODE='1'
  elif [[ "${target_existed}" == 'true' ]]; then
    if ! actual_mode=$(stat -c '%a' -- "${target}") || \
      ! actual_uid=$(stat -c '%u' -- "${target}") || \
      ! actual_gid=$(stat -c '%g' -- "${target}"); then
      postcheck_failed='true'
      postcheck_code='postcheck_metadata_failed'
      detail="目标路径: ${target}"
      SBV_UPDATE_COMMAND_EXIT_CODE='1'
    elif [[ "${actual_mode}" != "${SBV_UPDATE_EXPECTED_MODE}" || \
      "${actual_uid}" != "${old_uid}" || \
      "${actual_gid}" != "${old_gid}" ]]; then
      postcheck_failed='true'
      postcheck_code='postcheck_metadata_mismatch'
      detail="实际: ${actual_mode}:${actual_uid}:${actual_gid}; 预期: ${SBV_UPDATE_EXPECTED_MODE}:${old_uid}:${old_gid}"
      SBV_UPDATE_COMMAND_EXIT_CODE='1'
    fi
  fi
  if [[ "${postcheck_failed}" != 'true' ]]; then
    finish_sbv_artifact_success
    return 0
  fi

  SBV_UPDATE_ROLLBACK_ATTEMPTED='true'
  if [[ "${target_existed}" == 'true' ]]; then
    if SBV_UPDATE_ROLLBACK_PATH=$(mktemp "${target_dir}/.${target_name}.rollback.XXXXXXXXXX") && \
      cp -p -- "${SBV_UPDATE_BACKUP_PATH}" "${SBV_UPDATE_ROLLBACK_PATH}" && \
      chmod "${old_mode}" "${SBV_UPDATE_ROLLBACK_PATH}" && \
      chown "${old_uid}:${old_gid}" "${SBV_UPDATE_ROLLBACK_PATH}" && \
      mv -f -- "${SBV_UPDATE_ROLLBACK_PATH}" "${target}" && \
      [[ -f "${target}" && ! -L "${target}" ]] && \
      bash -n -- "${target}" && \
      [[ "$(stat -c '%a' -- "${target}")" == "${old_mode}" ]] && \
      [[ "$(stat -c '%u' -- "${target}")" == "${old_uid}" ]] && \
      [[ "$(stat -c '%g' -- "${target}")" == "${old_gid}" ]] && \
      restore_hash=$(calculate_sbv_sha256 "${target}") && [[ "${restore_hash}" == "${old_hash}" ]]; then
      SBV_UPDATE_ROLLBACK_PATH=''
      SBV_UPDATE_ROLLED_BACK='true'
      SBV_UPDATE_ROLLBACK_OK='true'
      set_sbv_update_error "${operation}" 'postcheck' "${postcheck_code}" \
        '提交后的 artifact 校验失败，已恢复原文件' "${detail}" \
        "${SBV_UPDATE_COMMAND_EXIT_CODE:-1}" \
        '原文件已恢复，未保留无效远程内容'
      result_status=${SBV_UPDATE_COMMAND_EXIT_CODE:-1}
      finish_sbv_artifact_failure "${result_status}" || return $?
      return 0
    fi
  elif rm -f -- "${target}" && [[ ! -e "${target}" && ! -L "${target}" ]]; then
    SBV_UPDATE_ROLLED_BACK='true'
    SBV_UPDATE_ROLLBACK_OK='true'
    set_sbv_update_error "${operation}" 'postcheck' "${postcheck_code}" \
      '提交后的 artifact 校验失败，已删除原本不存在的无效目标' "${detail}" \
      "${SBV_UPDATE_COMMAND_EXIT_CODE:-1}" \
      '原目标原本不存在；请重新运行下载'
    result_status=${SBV_UPDATE_COMMAND_EXIT_CODE:-1}
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi

  if [[ -f "${target}" && ! -L "${target}" ]]; then
    if retained_candidate=$(mktemp "${target_dir}/.${target_name}.candidate-retained.XXXXXXXXXX") && \
      cp -p -- "${target}" "${retained_candidate}" && \
      chmod 0600 "${retained_candidate}" && chown 0:0 "${retained_candidate}"; then
      SBV_UPDATE_CANDIDATE_PATH=${retained_candidate}
    else
      rm -f -- "${retained_candidate}" 2>/dev/null || true
    fi
  fi
  SBV_UPDATE_PRESERVE_ARTIFACTS='true'
  set_sbv_update_error "${operation}" 'postcheck' 'rollback_failed' \
    '提交后的 artifact 校验失败且自动恢复失败' "${detail}" \
    "${SBV_UPDATE_COMMAND_EXIT_CODE:-1}" \
    '保留的备份和候选文件可能需要人工恢复'
  SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED='true'
  finish_sbv_artifact_failure 1 || return $?
  return 0
}

# Check for script update status. This is a read-only best-effort operation;
# unlike a mutating update it reports unavailable instead of propagating a
# network failure into the menu loop.
check_script_status() {
  local remote_content=''
  local remote_version=''

  if ! remote_content=$(curl -fsSL \
    --connect-timeout 5 \
    --max-time 15 \
    --retry 1 \
    --retry-delay 1 \
    "${SBV_UPDATE_URL}" 2>/dev/null); then
    SCRIPT_VER_STATUS="${RED}(无法检测更新: 网络不可用)${NC}"
    return 0
  fi

  if ! remote_version=$(printf '%s\n' "${remote_content}" | sed -nE \
    's/^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="([0-9]{10})"[[:space:]]*$/\1/p' \
    | awk 'NF { count += 1; value = $0 } END { if (count == 1) print value }'); then
    SCRIPT_VER_STATUS="${RED}(无法检测更新: 响应解析失败)${NC}"
    return 0
  fi
  if [[ -z "${remote_version}" ]]; then
    SCRIPT_VER_STATUS="${RED}(无法检测更新: 响应无有效版本)${NC}"
    return 0
  fi

  if (( 10#${remote_version} > 10#${SCRIPT_VERSION} )); then
    SCRIPT_VER_STATUS="${YELLOW}(有新版本: ${remote_version})${NC}"
  else
    SCRIPT_VER_STATUS="${GREEN}(已是最新)${NC}"
  fi
  return 0
}

manual_update_script() {
  local result_status=0

  log_info "正在从 GitHub 获取最新脚本..."
  if sbv_update_transaction 'sbv_update' url "${SBV_UPDATE_URL}"; then
    if [[ "${SBV_UPDATE_NOOP}" == 'true' ]]; then
      log_info "当前 sbv 已是最新版本。"
    else
      log_success "脚本已原子更新到 ${SBV_UPDATE_CANDIDATE_VERSION}，请重新运行 sbv。"
    fi
    return 0
  else
    result_status=$?
  fi
  return "${result_status}"
}

ensure_sbv_command_installed() {
  local source_file=$0
  local result_status=0

  if [[ "${source_file}" == "${SBV_BIN_PATH}" || "${source_file}" == 'sbv' ]]; then
    return 0
  fi

  if [[ -f "${source_file}" && ! -L "${source_file}" ]]; then
    log_info "正在同步全局命令: sbv..."
    if sbv_update_transaction 'ensure_sbv_local' file "${source_file}"; then
      log_success "全局命令 sbv 已同步为当前脚本版本。"
      return 0
    else
      result_status=$?
    fi
    log_warn "当前脚本同步失败（退出码 ${result_status}），将尝试远程候选。"
  fi

  log_info "正在安装全局命令: sbv..."
  if sbv_update_transaction 'ensure_sbv_remote' url "${SBV_UPDATE_URL}"; then
    log_success "全局命令 sbv 安装成功。"
    return 0
  else
    result_status=$?
  fi

  if [[ -f "${source_file}" && ! -L "${source_file}" ]]; then
    log_warn "全局命令安装失败（退出码 ${result_status}），请稍后重试或人工安装。"
  else
    log_warn "全局命令安装失败（退出码 ${result_status}），后续可重新运行一键安装命令。"
  fi
  return "${result_status}"
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
  local current_cc
  current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
  if [[ "${current_cc}" == "bbr" ]]; then
    log_success "BBR 拥塞控制已开启。"
  else
    log_warn "BBR 拥塞控制未开启，正在尝试开启..."
    set_sysctl_conf_value "net.core.default_qdisc" "fq" "/etc/sysctl.conf"
    set_sysctl_conf_value "net.ipv4.tcp_congestion_control" "bbr" "/etc/sysctl.conf"
    sysctl -p /etc/sysctl.conf
    log_success "BBR 开启成功。"
  fi
}

set_sysctl_conf_value() {
  local key=$1
  local value=$2
  local config_file=${3:-/etc/sysctl.conf}
  local escaped_key
  local escaped_value

  escaped_key=$(printf '%s' "${key}" | sed 's/[][\/.^$*]/\\&/g')
  escaped_value=$(printf '%s' "${value}" | sed 's/[\/&]/\\&/g')

  touch "${config_file}"
  if grep -qE "^[[:space:]]*${escaped_key}[[:space:]]*=" "${config_file}"; then
    sed -i -E "s|^[[:space:]]*${escaped_key}[[:space:]]*=.*|${key}=${escaped_value}|" "${config_file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${config_file}"
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
    if ! iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT &>/dev/null; then
      iptables -I INPUT -p tcp --dport "${port}" -j ACCEPT &>/dev/null
    fi
    if ! iptables -C INPUT -p udp --dport "${port}" -j ACCEPT &>/dev/null; then
      iptables -I INPUT -p udp --dport "${port}" -j ACCEPT &>/dev/null
    fi
    log_warn "裸 iptables 规则通常只对当前运行时生效；如需持久化，请确认系统已配置规则保存机制。"
  fi
  
  log_success "端口 ${port} 防火墙配置尝试完成。"
}

# Close firewall port (reverse of open_firewall_port)
close_firewall_port() {
  local port=$1
  log_info "正在尝试关闭端口 ${port}..."

  # UFW
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw delete allow "${port}/tcp" &>/dev/null || true
    ufw delete allow "${port}/udp" &>/dev/null || true
  fi

  # Firewalld
  if command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null; then
    firewall-cmd --permanent --remove-port="${port}/tcp" &>/dev/null || true
    firewall-cmd --permanent --remove-port="${port}/udp" &>/dev/null || true
    firewall-cmd --reload &>/dev/null || true
  fi

  # Iptables
  if command -v iptables &>/dev/null; then
    iptables -D INPUT -p tcp --dport "${port}" -j ACCEPT &>/dev/null || true
    iptables -D INPUT -p udp --dport "${port}" -j ACCEPT &>/dev/null || true
  fi

  log_info "端口 ${port} 防火墙规则清理尝试完成。"
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
    echo "1. 保留占用进程并改用随机端口"
    echo "2. 使用随机端口"
    echo "3. 手动输入新端口"
    port_choice=$(prompt_choice "请选择操作 [1-3]: " 1 3 "")
    
    case "${port_choice}" in
      1|2)
        SB_PORT="$(pick_random_high_port)"
        log_success "已保留占用进程，并自动切换到随机端口: ${SB_PORT}"
        ;;
      3)
        SB_PORT=$(prompt_port "请输入新端口: " "")
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
      apt-get install -y curl wget jq tar openssl uuid-runtime qrencode iproute2
      ;;
    centos|almalinux|rocky)
      yum install -y curl wget jq tar openssl util-linux qrencode iproute
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

replace_singbox_binary_atomically() {
  local source_file=$1
  local target_dir
  local staged_binary=""

  [[ -f "${source_file}" ]] || return 1
  target_dir=$(dirname "${SINGBOX_BIN_PATH}")
  [[ -d "${target_dir}" ]] || return 1
  staged_binary=$(mktemp "${target_dir}/.sing-box.restore.XXXXXXXX") || return 1

  if ! cp -p -- "${source_file}" "${staged_binary}" ||
     ! chmod 0755 "${staged_binary}" ||
     ! mv -f -- "${staged_binary}" "${SINGBOX_BIN_PATH}"; then
    rm -f -- "${staged_binary}"
    return 1
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
  
  if ! replace_singbox_binary_atomically "${bin_path}"; then
    log_error "安装 sing-box 二进制失败。"
  fi
  
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

  if ! ensure_sbv_command_installed; then
    log_warn "全局命令 sbv 未能完成同步；当前安装流程继续，但请稍后手动重试。"
  fi
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
  local protocol state_file state_mode=${2:-mutable}
  protocol=$(normalize_protocol_id "$1")
  if [[ "${protocol}" == "vless-reality" && "${state_mode}" != "read-only" ]]; then
    migrate_vless_reality_state_to_instances_if_needed
  fi
  state_file=$(protocol_state_file "${protocol}")

  if [[ ! -f "${state_file}" ]]; then
    if [[ "$(runtime_protocol_to_state "${SB_PROTOCOL}")" == "${protocol}" ]]; then
      return 0
    fi
    log_error "未找到协议状态文件: ${state_file}"
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
      SB_SNI="${SNI:-${SB_SNI:-$SB_REALITY_SNI_FALLBACK}}"
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
  local protocol

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    case "${protocol}" in
      vless-reality)
        vless_reality_has_warp_outbound_policy && return 0
        ;;
    esac
  done < <(list_effective_protocols)

  return 1
}

build_protocol_route_rules() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality)
      build_vless_reality_route_rules_json
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

managed_state_snapshot_is_valid() {
  local snapshot_dir=$1

  [[ "${snapshot_dir}" == /tmp/sing-box-vps-state.* ]] || return 1
  [[ -d "${snapshot_dir}" && -f "${snapshot_dir}/snapshot.meta" ]] || return 1
  grep -Fqx 'SNAPSHOT_VERSION=1' "${snapshot_dir}/snapshot.meta" || return 1
  grep -Fqx "PROJECT_DIR=${SB_PROJECT_DIR}" "${snapshot_dir}/snapshot.meta" || return 1
}

persist_file_backup() {
  local source_file=$1
  local backup_file=$2
  local backup_dir backup_name backup_candidate

  [[ -f "${source_file}" ]] || return 1
  backup_dir=$(dirname "${backup_file}")
  backup_name=$(basename "${backup_file}")
  mkdir -p "${backup_dir}" || return 1
  backup_candidate=$(mktemp "${backup_dir}/.${backup_name}.candidate.XXXXXX") || return 1
  if ! cp -p "${source_file}" "${backup_candidate}" ||
     ! chmod 600 "${backup_candidate}" ||
     ! mv -f "${backup_candidate}" "${backup_file}"; then
    rm -f "${backup_candidate}"
    return 1
  fi
}

create_managed_state_snapshot() {
  local snapshot_dir

  snapshot_dir=$(mktemp -d /tmp/sing-box-vps-state.XXXXXX) || return 1
  chmod 700 "${snapshot_dir}" || {
    rm -rf "${snapshot_dir}"
    return 1
  }
  if ! mkdir -p "${snapshot_dir}/project"; then
    rm -rf "${snapshot_dir}"
    return 1
  fi
  if [[ -d "${SB_PROJECT_DIR}" ]]; then
    if ! cp -a "${SB_PROJECT_DIR}/." "${snapshot_dir}/project/"; then
      rm -rf "${snapshot_dir}"
      return 1
    fi
    : > "${snapshot_dir}/project.existed"
  fi
  if ! {
    printf 'SNAPSHOT_VERSION=1\n'
    printf 'PROJECT_DIR=%s\n' "${SB_PROJECT_DIR}"
  } > "${snapshot_dir}/snapshot.meta"; then
    rm -rf "${snapshot_dir}"
    return 1
  fi
  chmod 600 "${snapshot_dir}/snapshot.meta" || {
    rm -rf "${snapshot_dir}"
    return 1
  }

  printf '%s' "${snapshot_dir}"
}

discard_managed_state_snapshot() {
  local snapshot_dir=$1

  managed_state_snapshot_is_valid "${snapshot_dir}" || return 1
  rm -rf "${snapshot_dir}"
}

restore_managed_state_snapshot() {
  local snapshot_dir=$1
  local project_parent project_base restore_candidate restore_previous
  local current_existed="n"

  managed_state_snapshot_is_valid "${snapshot_dir}" || return 1
  [[ -n "${SB_PROJECT_DIR}" && "${SB_PROJECT_DIR}" != "/" ]] || return 1
  project_parent=$(dirname "${SB_PROJECT_DIR}")
  project_base=$(basename "${SB_PROJECT_DIR}")
  mkdir -p "${project_parent}" || return 1

  restore_candidate=$(mktemp -d "${project_parent}/.${project_base}.restore.XXXXXX") || return 1
  if [[ -f "${snapshot_dir}/project.existed" ]]; then
    if ! cp -a "${snapshot_dir}/project/." "${restore_candidate}/"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
  fi

  restore_previous=$(mktemp -d "${project_parent}/.${project_base}.previous.XXXXXX") || {
    rm -rf "${restore_candidate}"
    return 1
  }
  rmdir "${restore_previous}" || {
    rm -rf "${restore_candidate}" "${restore_previous}"
    return 1
  }

  if [[ -e "${SB_PROJECT_DIR}" || -L "${SB_PROJECT_DIR}" ]]; then
    if ! mv "${SB_PROJECT_DIR}" "${restore_previous}"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
    current_existed="y"
  fi

  if [[ -f "${snapshot_dir}/project.existed" ]]; then
    if ! mv "${restore_candidate}" "${SB_PROJECT_DIR}"; then
      [[ "${current_existed}" == "y" ]] && mv "${restore_previous}" "${SB_PROJECT_DIR}" 2>/dev/null || true
      rm -rf "${restore_candidate}"
      return 1
    fi
  elif ! rmdir "${restore_candidate}"; then
    [[ "${current_existed}" == "y" ]] && mv "${restore_previous}" "${SB_PROJECT_DIR}" 2>/dev/null || true
    return 1
  fi

  if [[ "${current_existed}" == "y" ]] && ! rm -rf "${restore_previous}"; then
    return 1
  fi
}

rollback_managed_state_snapshot() {
  local snapshot_dir=$1

  if ! restore_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "配置状态回滚失败；事务快照保留在 ${snapshot_dir}。"
    return 1
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "配置状态已恢复，但临时事务快照未能删除: ${snapshot_dir}。"
    return 1
  fi
}

abort_managed_state_transaction() {
  local snapshot_dir=$1
  local failure_message=$2

  if rollback_managed_state_snapshot "${snapshot_dir}"; then
    log_error "${failure_message}，已恢复变更前的配置状态。"
    return 1
  fi
  log_error "${failure_message}，且自动回滚失败；事务快照保留在 ${snapshot_dir}。"
  return 1
}

# --- Config Generator ---
generate_config_candidate() {
  local inbound_file="" provider_file="" protocol_rule_file="" instance_outbound_rule_file=""
  local config_candidate="" backup_candidate="" protocol
  local exit_cleanup_command
  local inbounds_json certificate_providers_json protocol_rules_json instance_outbound_rules_json

  # Force ensure jq is installed
  if ! command -v jq &>/dev/null; then
    log_warn "未检测到 jq，正在尝试自动安装以确保配置生成安全..."
    get_os_info && install_dependencies
  fi

  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    log_warn "无法生成配置：缺少可执行的 sing-box 二进制 ${SINGBOX_BIN_PATH}。"
    return 1
  fi

  log_info "正在生成配置 (目标 sing-box $(resolve_config_target_singbox_version)，Endpoint 架构 & 安全注入)..."
  mkdir -p "${SINGBOX_CONFIG_DIR}" || return 1
  ensure_warp_routing_assets || return 1
  load_warp_route_settings || return 1

  # Endpoints Logic
  local w_key="" w_v4="" w_v6="" w_client_id="" w_reserved='[]' enable_warp_endpoint
  enable_warp_endpoint="${SB_ENABLE_WARP}"
  if [[ "${enable_warp_endpoint}" != "y" ]] && instance_outbound_requires_warp; then
    enable_warp_endpoint="y"
  fi

  if [[ "${enable_warp_endpoint}" == "y" ]]; then
    register_warp || return 1
    w_key=$(grep "WARP_PRIV_KEY" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v4=$(grep "WARP_V4" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v6=$(grep "WARP_V6" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_client_id=$(grep "WARP_CLIENT_ID" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_reserved=$(warp_client_id_to_reserved_json "${w_client_id}")
  fi

  refresh_warp_route_assets || return 1
  ensure_stack_mode_state_loaded || return 1

  inbound_file=$(mktemp) || return 1
  if ! provider_file=$(mktemp); then
    rm -f "${inbound_file}"
    return 1
  fi
  if ! protocol_rule_file=$(mktemp); then
    rm -f "${inbound_file}" "${provider_file}"
    return 1
  fi
  if ! instance_outbound_rule_file=$(mktemp); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}"
    return 1
  fi
  if ! config_candidate=$(mktemp "${SINGBOX_CONFIG_DIR}/.config.json.candidate.XXXXXX"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}"
    return 1
  fi
  printf -v exit_cleanup_command 'rm -f -- %q %q %q %q %q' \
    "${inbound_file}" "${provider_file}" "${protocol_rule_file}" \
    "${instance_outbound_rule_file}" "${config_candidate}"
  trap "${exit_cleanup_command}" EXIT

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    if ! load_protocol_state "${protocol}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! build_inbound_for_protocol "${protocol}" >> "${inbound_file}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! build_certificate_provider_for_protocol "${protocol}" >> "${provider_file}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! build_protocol_route_rules "${protocol}" >> "${protocol_rule_file}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if [[ "${protocol}" == "vless-reality" ]]; then
      if ! build_vless_reality_instance_outbound_rules_json >> "${instance_outbound_rule_file}"; then
        rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
        return 1
      fi
    fi
  done < <(list_effective_protocols)

  if ! inbounds_json=$(jq -s . "${inbound_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! certificate_providers_json=$(jq -s . "${provider_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! protocol_rules_json=$(jq -s 'add // []' "${protocol_rule_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! instance_outbound_rules_json=$(jq -s 'add // []' "${instance_outbound_rule_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  if ! jq -n \
    --arg adv_route "${SB_ADVANCED_ROUTE}" \
    --arg enable_warp "${SB_ENABLE_WARP}" \
    --arg enable_warp_endpoint "${enable_warp_endpoint}" \
    --arg warp_mode "${SB_WARP_ROUTE_MODE}" \
    --arg w_key "${w_key}" \
    --arg w_v4 "${w_v4}/32" \
    --arg w_v6 "${w_v6}/128" \
    --argjson w_reserved "${w_reserved}" \
    --arg outbound_stack_mode "${SB_OUTBOUND_STACK_MODE}" \
    --argjson inbounds "${inbounds_json}" \
    --argjson certificate_providers "${certificate_providers_json}" \
    --argjson protocol_rules "${protocol_rules_json}" \
    --argjson instance_outbound_rules "${instance_outbound_rules_json}" \
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
      "endpoints": (if $enable_warp_endpoint == "y" then [
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
          $instance_outbound_rules +
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
    )' > "${config_candidate}"; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  if ! jq -e . "${config_candidate}" >/dev/null; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! "${SINGBOX_BIN_PATH}" check -c "${config_candidate}"; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! chmod 600 "${config_candidate}"; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    if ! backup_candidate=$(mktemp "${SINGBOX_CONFIG_DIR}/.config.json.backup.XXXXXX"); then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! cp -p "${SINGBOX_CONFIG_FILE}" "${backup_candidate}" ||
       ! chmod 600 "${backup_candidate}" ||
       ! mv -f "${backup_candidate}" "${SINGBOX_CONFIG_FILE}.bak"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}" "${backup_candidate}"
      return 1
    fi
  fi

  if ! mv -f "${config_candidate}" "${SINGBOX_CONFIG_FILE}"; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}"
  trap - EXIT
}

generate_config() {
  local snapshot_dir

  snapshot_dir=$(create_managed_state_snapshot) || return 1
  if ! (generate_config_candidate); then
    rollback_managed_state_snapshot "${snapshot_dir}" || true
    return 1
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "配置已发布，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
}

# --- Uninstaller ---
perform_singbox_runtime_uninstall() {
  log_info "正在彻底卸载 sing-box 环境..."
  if command -v tc >/dev/null 2>&1; then
    clear_vless_reality_qos_rules
  fi
  systemctl stop sing-box &>/dev/null || true
  systemctl disable sing-box &>/dev/null || true
  rm -f "${SINGBOX_SERVICE_FILE}"
  systemctl daemon-reload
  rm -f "${SINGBOX_BIN_PATH}"
  rm -rf "${SINGBOX_CONFIG_DIR}"
  print_success "sing-box 服务、二进制和配置目录已彻底删除。"
}

perform_full_uninstall() {
  perform_singbox_runtime_uninstall
  rm -f "${SBV_BIN_PATH}"
  print_success "全局命令 sbv 已删除。"
}

uninstall_singbox() {
  echo ""
  print_warn "该操作会彻底删除 sing-box 服务、配置目录和密钥，但会保留全局命令 sbv。"
  read -rp "确认继续吗？[y/N]: " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "已取消卸载。"
    return 0
  fi

  perform_singbox_runtime_uninstall
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

compact_ui_width() {
  local width

  width=$(term_columns)
  if (( width < 1 )); then
    width=1
  elif (( width > UI_COMPACT_MAX_WIDTH )); then
    width=${UI_COMPACT_MAX_WIDTH}
  fi

  printf '%s' "${width}"
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

  width=$(compact_ui_width)
  divider=$(repeat_char "═" "${width}")

  echo -e "${BLUE}${divider}${NC}"
  echo -e "${GREEN}${title}${NC}"
  if [[ -n "${subtitle}" ]]; then
    echo -e "${BLUE}${subtitle}${NC}"
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

  width=$(compact_ui_width)
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

  width=$(compact_ui_width)
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
  local selected_inbound selected_outbound snapshot_dir
  selected_inbound="${SB_INBOUND_STACK_MODE}"
  selected_outbound="${SB_OUTBOUND_STACK_MODE}"

  if [[ -f "${SINGBOX_CONFIG_FILE}" || -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    load_current_config_state
    SB_INBOUND_STACK_MODE="${selected_inbound}"
    SB_OUTBOUND_STACK_MODE="${selected_outbound}"
  fi

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    save_stack_mode_state
    log_success "协议栈设置已保存，将在首次安装或下次生成配置时生效。"
    return 0
  fi

  snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
  if ! save_stack_mode_state || ! generate_config; then
    abort_managed_state_transaction "${snapshot_dir}" "协议栈配置生成或校验失败"
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "协议栈配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
  refresh_vless_reality_qos_rules
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
    choice=$(prompt_choice "请选择 [0-${#available_modes[@]}]: " 0 "${#available_modes[@]}" "")

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
    choice=$(prompt_choice "请选择 [0-${#available_modes[@]}]: " 0 "${#available_modes[@]}" "")

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
    stack_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

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
    system_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

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
        any(.route.rules[]?; (.outbound // "") == "warp-ep" and (has("inbound") | not))
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

normalize_acme_extra_json() {
  local acme_json=$1

  if ! jq -n -e --argjson acme "${acme_json}" '$acme | type == "object"' >/dev/null 2>&1; then
    return 1
  fi
  if jq -n -e --argjson acme "${acme_json}" '$acme.http_client? | type == "string"' >/dev/null 2>&1; then
    return 1
  fi

  jq -cnS \
    --argjson acme "${acme_json}" \
    --arg default_data_directory "${SB_ACME_DATA_DIR}" \
    '$acme
    | if .domain == null then
        del(.domain)
      elif (.domain | type) != "array" or (.domain | length) == 0 then
        error("invalid ACME domain")
      elif (.domain | length) == 1 then
        del(.domain)
      else
        .
      end
    | del(.type, .tag, .email)
    | if .data_directory == $default_data_directory then del(.data_directory) else . end
    | if .dns01_challenge == null then
        del(.dns01_challenge)
      elif (.dns01_challenge | type) == "object" then
        .dns01_challenge |= del(.provider, .api_token)
        | if .dns01_challenge == {} then del(.dns01_challenge) else . end
      else
        .
      end'
}

inline_acme_extra_json_from_config() {
  local config_file=$1
  local inbound_index=$2
  local acme_json

  acme_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme' "${config_file}") || return 1
  normalize_acme_extra_json "${acme_json}"
}

# Resolve an inbound certificate provider into the state fields consumed by all
# protocol readers.  A certificate_provider may be either a shared tag or an
# inline object, but only an ACME provider can be represented by the script's
# state model.  Returning an error for anything else prevents a later rewrite
# from silently changing the certificate configuration.
load_certificate_provider_from_config() {
  local config_file=$1
  local inbound_index=$2
  local provider_kind provider_tag provider_count provider_json provider_type server_name

  CERT_PROVIDER_MODE="none"
  CERT_PROVIDER_TAG=""
  CERT_PROVIDER_EMAIL=""
  CERT_PROVIDER_DOMAIN=""
  CERT_PROVIDER_EXTRA_JSON='{}'
  CERT_PROVIDER_ACME_MODE="http"
  CERT_PROVIDER_DNS_PROVIDER="cloudflare"
  CERT_PROVIDER_CF_API_TOKEN=""
  CERT_PROVIDER_ERROR=""

  if ! provider_kind=$(jq -r --argjson idx "${inbound_index}" '
    .inbounds[$idx].tls.certificate_provider? |
    if . == null then "none"
    elif type == "string" then "shared"
    elif type == "object" then "inline"
    else "invalid"
    end
  ' "${config_file}"); then
    CERT_PROVIDER_ERROR="无法读取 certificate_provider"
    return 1
  fi

  case "${provider_kind}" in
    none)
      return 0
      ;;
    shared)
      provider_tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 shared certificate_provider tag"
        return 1
      }
      provider_count=$(jq -r --arg tag "${provider_tag}" '[.certificate_providers[]? | select(type == "object" and .tag == $tag)] | length' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 shared certificate_provider 映射"
        return 1
      }
      if [[ "${provider_count}" != "1" ]]; then
        CERT_PROVIDER_ERROR="shared certificate_provider 未唯一映射"
        return 1
      fi
      provider_json=$(jq -c --arg tag "${provider_tag}" 'first(.certificate_providers[]? | select(type == "object" and .tag == $tag)) // null' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 shared certificate_provider"
        return 1
      }
      CERT_PROVIDER_TAG="${provider_tag}"
      ;;
    inline)
      provider_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider' "${config_file}") || {
        CERT_PROVIDER_ERROR="无法读取 inline certificate_provider"
        return 1
      }
      ;;
    *)
      CERT_PROVIDER_ERROR="certificate_provider 类型不受支持"
      return 1
      ;;
  esac

  provider_type=$(jq -n -r --argjson provider "${provider_json}" '$provider.type // ""' 2>/dev/null) || {
    CERT_PROVIDER_ERROR="无法读取 certificate_provider type"
    return 1
  }
  if [[ "${provider_type}" != "acme" ]]; then
    CERT_PROVIDER_ERROR="certificate_provider 不是 ACME provider"
    return 1
  fi

  if ! CERT_PROVIDER_EXTRA_JSON=$(normalize_acme_extra_json "${provider_json}"); then
    if jq -n -e --argjson provider "${provider_json}" '$provider.http_client? | type == "string"' >/dev/null 2>&1; then
      CERT_PROVIDER_ERROR="暂不支持引用 shared http_client 的 ACME provider"
    else
      CERT_PROVIDER_ERROR="无法保留 ACME provider 的扩展字段"
    fi
    return 1
  fi

  server_name=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${config_file}") || {
    CERT_PROVIDER_ERROR="无法读取 certificate_provider fallback domain"
    return 1
  }
  CERT_PROVIDER_MODE="acme"
  if ! CERT_PROVIDER_EMAIL=$(jq -n -r --argjson provider "${provider_json}" '$provider.email // ""' 2>/dev/null); then
    CERT_PROVIDER_ERROR="无法读取 ACME provider email"
    return 1
  fi
  if ! CERT_PROVIDER_DOMAIN=$(jq -n -r --argjson provider "${provider_json}" --arg fallback "${server_name}" '$provider.domain[0] // $fallback' 2>/dev/null); then
    CERT_PROVIDER_ERROR="无法读取 ACME provider domain"
    return 1
  fi
  if jq -n -e --argjson provider "${provider_json}" '$provider.dns01_challenge? != null' &>/dev/null; then
    CERT_PROVIDER_ACME_MODE="dns"
    if ! CERT_PROVIDER_DNS_PROVIDER=$(jq -n -r --argjson provider "${provider_json}" '$provider.dns01_challenge.provider // "cloudflare"' 2>/dev/null); then
      CERT_PROVIDER_ERROR="无法读取 ACME DNS provider"
      return 1
    fi
    if ! CERT_PROVIDER_CF_API_TOKEN=$(jq -n -r --argjson provider "${provider_json}" '$provider.dns01_challenge.api_token // ""' 2>/dev/null); then
      CERT_PROVIDER_ERROR="无法读取 ACME DNS API token"
      return 1
    fi
  fi
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
      if ! SB_HY2_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" 0); then
        log_error "当前 Hysteria2 tls.acme 扩展字段无法安全保留。"
      fi
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
    elif jq -e '.inbounds[0].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" 0; then
        log_error "当前 Hysteria2 certificate_provider 无法安全解析: ${CERT_PROVIDER_ERROR}"
      fi
      SB_HY2_TLS_MODE="acme"
      SB_HY2_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
      SB_HY2_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
      SB_HY2_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
      SB_HY2_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
      SB_HY2_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
      SB_HY2_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
      SB_HY2_CERT_PATH=""
      SB_HY2_KEY_PATH=""
    else
      SB_HY2_TLS_MODE="manual"
      SB_HY2_ACME_MODE="http"
      SB_HY2_ACME_EMAIL=""
      SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
      SB_HY2_ACME_EXTRA_JSON='{}'
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
      if ! SB_ANYTLS_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" 0); then
        log_error "当前 AnyTLS tls.acme 扩展字段无法安全保留。"
      fi
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
    elif jq -e '.inbounds[0].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" 0; then
        log_error "当前 AnyTLS certificate_provider 无法安全解析: ${CERT_PROVIDER_ERROR}"
      fi
      SB_ANYTLS_TLS_MODE="acme"
      SB_ANYTLS_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
      SB_ANYTLS_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
      SB_ANYTLS_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
      SB_ANYTLS_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
      SB_ANYTLS_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
      SB_ANYTLS_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
      SB_ANYTLS_CERT_PATH=""
      SB_ANYTLS_KEY_PATH=""
    else
      SB_ANYTLS_TLS_MODE="manual"
      SB_ANYTLS_ACME_MODE="http"
      SB_ANYTLS_ACME_EMAIL=""
      SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
      SB_ANYTLS_ACME_EXTRA_JSON='{}'
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
  local apply_change should_reload status warp_was_enabled snapshot_dir

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
    w_choice=$(prompt_choice "请选择 [0-9]: " 0 9 "")

    case "${w_choice}" in
      7)
        show_warp_route_assets
        continue
        ;;
      8)
        show_effective_warp_route_sources
        continue
        ;;
      0) return ;;
    esac

    snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"

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
      9)
        if import_recommended_warp_rule_sets; then
          apply_change="y"
          [[ "${warp_was_enabled}" == "y" || "${SB_ENABLE_WARP}" == "y" ]] && should_reload="y"
        fi
        ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac

    if [[ "${apply_change}" == "n" ]]; then
      if ! rollback_managed_state_snapshot "${snapshot_dir}"; then
        log_error "取消 Warp 变更时无法恢复配置状态；事务快照保留在 ${snapshot_dir}。"
      fi
      continue
    fi

    if ! save_warp_route_settings; then
      abort_managed_state_transaction "${snapshot_dir}" "Warp 设置写入失败"
    fi

    if [[ "${should_reload}" != "y" ]]; then
      if ! discard_managed_state_snapshot "${snapshot_dir}"; then
        log_warn "Warp 分流资产已保存，但临时事务快照未能删除: ${snapshot_dir}。"
      fi
      log_success "Warp 分流资产已更新，待下次开启 Warp 或重载配置时生效。"
      continue
    fi

    if ! generate_config; then
      abort_managed_state_transaction "${snapshot_dir}" "Warp 配置生成或校验失败"
    fi
    if ! discard_managed_state_snapshot "${snapshot_dir}"; then
      log_warn "Warp 配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
    fi
    setup_service
    systemctl restart sing-box
    log_success "Warp 配置已更新并重启服务。"

    load_current_config_state
    display_status_summary
    log_info "连接信息未自动展示，如需查看请进入菜单 11。"
  done
}

# Helper to extract config values and display info
view_status() {
  load_current_config_state
  display_status_summary
}

# New function: Update config only
update_config_only() {
  local selected_protocol selected_instance snapshot_dir

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
  if [[ "${selected_protocol}" == "vless-reality" ]]; then
    SELECTED_VLESS_INSTANCE_ID=""
    if ! prompt_vless_reality_instance_selection; then
      return 0
    fi
    selected_instance="${SELECTED_VLESS_INSTANCE_ID}"
    load_vless_reality_protocol_state
    load_vless_reality_instance_state "${selected_instance}" || log_error "加载 REALITY 实例失败: ${selected_instance}"
    echo -e "当前正在修改: $(protocol_display_name "${SB_PROTOCOL}") / ${SB_NODE_NAME} (${SB_VLESS_INSTANCE_ID})"
  else
    echo -e "当前正在修改: $(protocol_display_name "${SB_PROTOCOL}")"
  fi
  snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
  prompt_protocol_update_fields "${selected_protocol}"
  if ! save_protocol_state "${selected_protocol}" || ! generate_config; then
    abort_managed_state_transaction "${snapshot_dir}" "协议配置生成或校验失败"
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "协议配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
  if [[ "${selected_protocol}" == "vless-reality" ]]; then
    refresh_vless_reality_qos_rules
  fi
  setup_service
  open_all_protocol_ports
  load_protocol_state "${selected_protocol}"
  systemctl restart sing-box
  log_success "配置及服务文件已更新并重启服务。"
  log_info "连接信息未自动展示，如需查看请进入菜单 11。"
}

remove_protocol_menu() {
  local protocols=() selected_protocols=() remaining_protocols=()
  local selected_protocol display_str confirm
  local state_file backup_state_file transaction_dir
  local joined_protocols first_remaining protocol
  local reality_instances=() instance_state_file backup_instance_state_file
  local selected_instance first_remaining_instance removed_instance_port
  local reality_remove_mode="instance" choice removed_port
  local removed_ports=() idx raw_choice raw_choices chosen_protocol display_list

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_error "未找到配置文件或协议状态，请先执行安装流程。"
  fi

  migrate_legacy_single_protocol_state_if_needed
  load_current_config_state
  mapfile -t protocols < <(list_installed_protocols)

  if [[ ${#protocols[@]} -eq 0 ]]; then
    log_error "当前未检测到已安装协议。"
  fi

  echo -e "\n${BLUE}--- 移除已安装协议 ---${NC}"
  echo "可用协议:"
  for idx in "${!protocols[@]}"; do
    echo "$((idx + 1)). $(protocol_display_name "$(state_protocol_to_runtime "${protocols[$idx]}")")"
  done
  echo "0. 返回"
  echo "留空则移除所有已安装协议。"
  read -rp "请选择一个或多个协议 [0-${#protocols[@]}]，逗号分隔: " choice

  if [[ -z "$(trim_whitespace "${choice}")" ]]; then
    selected_protocols=("${protocols[@]}")
  elif [[ "$(trim_whitespace "${choice}")" == "0" ]]; then
    return 0
  else
    IFS="," read -r -a raw_choices <<< "${choice}"
    for raw_choice in "${raw_choices[@]}"; do
      raw_choice=$(trim_whitespace "${raw_choice}")
      [[ -z "${raw_choice}" ]] && continue
      if [[ "${raw_choice}" =~ ^[1-9][0-9]*$ ]] && (( raw_choice >= 1 && raw_choice <= ${#protocols[@]} )); then
        chosen_protocol="${protocols[$((raw_choice - 1))]}"
        if ! protocol_array_contains "${chosen_protocol}" "${selected_protocols[@]}"; then
          selected_protocols+=("${chosen_protocol}")
        fi
      else
        log_warn "跳过无效选项: ${raw_choice}"
      fi
    done
  fi

  if [[ ${#selected_protocols[@]} -eq 0 ]]; then
    log_info "未选择任何协议。"
    return 0
  fi

  # Selecting only VLESS + REALITY keeps the historical per-instance removal
  # flow when more than one managed instance exists, while still exposing an
  # explicit whole-protocol option. Multi-select and blank keep their newer
  # whole-protocol semantics.
  if [[ ${#selected_protocols[@]} -eq 1 && "${selected_protocols[0]}" == "vless-reality" ]]; then
    migrate_vless_reality_state_to_instances_if_needed
    mapfile -t reality_instances < <(list_vless_reality_instance_ids)
    if [[ ${#reality_instances[@]} -gt 1 ]]; then
      echo "检测到多个 REALITY 实例:"
      echo "1. 移除单个 REALITY 实例 (默认)"
      echo "2. 移除整个 VLESS + REALITY 协议"
      echo "0. 返回"
      read -rp "请选择移除范围 [1]: " reality_remove_mode
      reality_remove_mode=$(trim_whitespace "${reality_remove_mode}")
      case "${reality_remove_mode}" in
        ""|1) reality_remove_mode="instance" ;;
        2) reality_remove_mode="protocol" ;;
        0) return 0 ;;
        *)
          log_warn "无效选项，已取消移除。"
          return 0
          ;;
      esac
    fi
    if [[ ${#reality_instances[@]} -gt 1 && "${reality_remove_mode}" == "instance" ]]; then
      SELECTED_VLESS_INSTANCE_ID=""
      if ! prompt_vless_reality_instance_selection; then
        return 0
      fi
      selected_instance="${SELECTED_VLESS_INSTANCE_ID}"
      load_vless_reality_instance_state "${selected_instance}" || \
        log_error "未找到 REALITY 实例状态: ${selected_instance}"
      removed_instance_port="${SB_PORT}"
      read -rp "确认移除 REALITY 实例 ${SB_NODE_NAME} (${selected_instance})? [y/N]: " confirm
      if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        log_info "已取消移除 REALITY 实例。"
        return 0
      fi

      instance_state_file=$(vless_reality_instance_state_file "${selected_instance}") || \
        log_error "REALITY 实例 ID 非法: ${selected_instance}"
      state_file=$(protocol_state_file "vless-reality")
      [[ -f "${instance_state_file}" ]] || log_error "未找到 REALITY 实例状态文件: ${instance_state_file}"
      [[ -f "${state_file}" ]] || log_error "未找到协议状态文件: ${state_file}"

      transaction_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
      backup_instance_state_file="${instance_state_file}.bak.$(date +%Y%m%d%H%M%S)"
      if ! mv "${instance_state_file}" "${backup_instance_state_file}"; then
        abort_managed_state_transaction "${transaction_dir}" "REALITY 实例状态备份失败"
      fi

      load_vless_reality_protocol_state
      remove_vless_reality_instance_id_from_list "${selected_instance}"
      first_remaining_instance="${VLESS_REALITY_INSTANCE_IDS%%,*}"
      if [[ "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" == "${selected_instance}" ]]; then
        VLESS_REALITY_DEFAULT_INSTANCE_ID="${first_remaining_instance}"
      fi
      if ! save_vless_reality_protocol_state; then
        abort_managed_state_transaction "${transaction_dir}" "REALITY 协议状态写入失败"
      fi

      if ! generate_config; then
        abort_managed_state_transaction "${transaction_dir}" "移除 REALITY 实例后配置生成或校验失败"
      fi

      if ! discard_managed_state_snapshot "${transaction_dir}"; then
        log_warn "REALITY 实例移除已提交，但临时事务快照未能删除: ${transaction_dir}。"
      fi
      setup_service
      load_protocol_state "vless-reality"
      open_all_protocol_ports
      refresh_vless_reality_qos_rules
      systemctl restart sing-box
      close_firewall_port "${removed_instance_port}"
      log_success "已移除 REALITY 实例: ${selected_instance}。原状态已备份到: ${backup_instance_state_file}"
      return 0
    fi
  fi

  display_list=()
  for selected_protocol in "${selected_protocols[@]}"; do
    display_list+=("$(protocol_display_name "$(state_protocol_to_runtime "${selected_protocol}")")")
  done
  display_str=$(IFS=", "; printf "%s" "${display_list[*]}")
  read -rp "确认移除下列协议: ${display_str}? [y/N]: " confirm
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    log_info "已取消移除协议。"
    return 0
  fi

  transaction_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
  if [[ ${#selected_protocols[@]} -eq ${#protocols[@]} ]]; then
    if ! persist_file_backup "${SINGBOX_CONFIG_FILE}" "${SINGBOX_CONFIG_FILE}.bak" ||
       ! persist_file_backup "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_INDEX_FILE}.bak"; then
      abort_managed_state_transaction "${transaction_dir}" "无法为当前配置和协议索引创建持久备份"
    fi
  fi

  for selected_protocol in "${selected_protocols[@]}"; do
    if [[ "${selected_protocol}" == "vless-reality" ]]; then
      migrate_vless_reality_state_to_instances_if_needed
      mapfile -t reality_instances < <(list_vless_reality_instance_ids)
      if [[ ${#reality_instances[@]} -gt 0 ]]; then
        for instance_id in "${reality_instances[@]}"; do
          if ! instance_state_file=$(vless_reality_instance_state_file "${instance_id}"); then
            abort_managed_state_transaction "${transaction_dir}" "REALITY 实例 ID 非法: ${instance_id}"
          fi
          if [[ ! -f "${instance_state_file}" ]]; then
            abort_managed_state_transaction "${transaction_dir}" "未找到 REALITY 实例状态: ${instance_id}"
          fi
          backup_instance_state_file="${instance_state_file}.bak.$(date +%Y%m%d%H%M%S)"
          if ! mv "${instance_state_file}" "${backup_instance_state_file}"; then
            abort_managed_state_transaction "${transaction_dir}" "REALITY 实例状态备份失败: ${instance_id}"
          fi
          # Capture removed instance port for firewall cleanup
          removed_ports+=("$(sed -n 's/^PORT=//p' "${backup_instance_state_file}" 2>/dev/null || true)")
        done
        state_file=$(protocol_state_file "vless-reality")
        if [[ -f "${state_file}" ]]; then
          backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
          if ! mv "${state_file}" "${backup_state_file}"; then
            abort_managed_state_transaction "${transaction_dir}" "VLESS + REALITY 协议状态备份失败"
          fi
          VLESS_REALITY_INSTANCE_IDS=""
          VLESS_REALITY_DEFAULT_INSTANCE_ID=""
        else
          abort_managed_state_transaction "${transaction_dir}" "未找到 VLESS + REALITY 协议状态"
        fi
      else
        abort_managed_state_transaction "${transaction_dir}" "未找到可移除的 REALITY 实例状态"
      fi
    else
      state_file=$(protocol_state_file "${selected_protocol}")
      if [[ -f "${state_file}" ]]; then
        backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
        if ! mv "${state_file}" "${backup_state_file}"; then
          abort_managed_state_transaction "${transaction_dir}" "协议状态备份失败: ${selected_protocol}"
        fi
        # Capture removed protocol port for firewall cleanup
        removed_ports+=("$(sed -n 's/^PORT=//p' "${backup_state_file}" 2>/dev/null || true)")
      else
        abort_managed_state_transaction "${transaction_dir}" "未找到协议状态: ${selected_protocol}"
      fi
    fi
  done

  for protocol in "${protocols[@]}"; do
    if protocol_array_contains "${protocol}" "${selected_protocols[@]}"; then
      continue
    fi
    remaining_protocols+=("${protocol}")
  done

  if [[ ${#remaining_protocols[@]} -gt 0 ]]; then
    joined_protocols=$(IFS=,; printf "%s" "${remaining_protocols[*]}")
    if ! write_protocol_index "${joined_protocols}"; then
      abort_managed_state_transaction "${transaction_dir}" "协议索引写入失败"
    fi
  else
    rm -f "${SB_PROTOCOL_INDEX_FILE}"
    rm -f "${SINGBOX_CONFIG_FILE}"
    if command -v tc >/dev/null 2>&1; then
      clear_vless_reality_qos_rules
    fi
    systemctl stop sing-box &>/dev/null || true
    systemctl disable sing-box &>/dev/null || true
    for removed_port in "${removed_ports[@]}"; do
      [[ -n "${removed_port}" ]] && close_firewall_port "${removed_port}"
    done
    if ! discard_managed_state_snapshot "${transaction_dir}"; then
      log_warn "协议移除已提交，但临时事务快照未能删除: ${transaction_dir}。"
    fi
    log_info "所有协议已移除，sing-box 服务已停止。"
    return 0
  fi

  if ! generate_config; then
    abort_managed_state_transaction "${transaction_dir}" "移除协议后配置生成或校验失败"
  fi

  if ! discard_managed_state_snapshot "${transaction_dir}"; then
    log_warn "协议移除已提交，但临时事务快照未能删除: ${transaction_dir}。"
  fi
  setup_service
  first_remaining="${remaining_protocols[0]}"
  load_protocol_state "${first_remaining}"
  open_all_protocol_ports
  refresh_vless_reality_qos_rules
  systemctl restart sing-box
  for removed_port in "${removed_ports[@]}"; do
    [[ -n "${removed_port}" ]] && close_firewall_port "${removed_port}"
  done
  log_success "已移除协议: ${display_str}。"
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
  local address_label=${2:-}
  local share_host node_name advanced_query alpn_value
  share_host=$(format_share_host "${public_ip}")
  node_name=$(vless_reality_display_node_name "${SB_NODE_NAME}" "${address_label}")
  advanced_query=""
  alpn_value=$(vless_reality_alpn_link_value_for_mode "${SB_VLESS_ALPN_MODE:-off}")
  [[ -n "${alpn_value}" ]] && advanced_query="${advanced_query}&alpn=${alpn_value}"
  [[ "${SB_VLESS_TCP_FAST_OPEN:-n}" == "y" ]] && advanced_query="${advanced_query}&tfo=1"

  printf 'vless://%s@%s:%s?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s%s&flow=xtls-rprx-vision#%s' \
    "${SB_UUID}" "${share_host}" "${SB_PORT}" "${SB_SNI}" "${SB_PUBLIC_KEY:-[密钥丢失，请更新配置]}" "${SB_SHORT_ID_1}" "${advanced_query}" "${node_name}"
}

vless_reality_rate_limit_summary() {
  local up_mbps=${1:-}
  local down_mbps=${2:-}
  local up_text down_text

  if [[ -n "${up_mbps}" ]]; then
    up_text="上行 ${up_mbps} Mbps"
  else
    up_text="上行不限"
  fi

  if [[ -n "${down_mbps}" ]]; then
    down_text="下行 ${down_mbps} Mbps"
  else
    down_text="下行不限"
  fi

  printf '%s / %s' "${up_text}" "${down_text}"
}

build_vless_link_for_instance() {
  local instance_id=$1
  local public_ip=$2
  local address_label=${3:-}
  local link_output status=0

  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${instance_id}" || return 1
  link_output=$(build_vless_link "${public_ip}" "${address_label}") || status=$?
  load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" >/dev/null 2>&1 || true

  if (( status != 0 )); then
    return "${status}"
  fi
  printf '%s' "${link_output}"
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

hy2_manual_certificate_algorithm() {
  local algorithm

  [[ "${SB_HY2_TLS_MODE:-}" == "manual" ]] || return 1
  [[ -n "${SB_HY2_CERT_PATH:-}" && -r "${SB_HY2_CERT_PATH}" ]] || return 1
  command -v openssl >/dev/null 2>&1 || return 1

  algorithm=$(LC_ALL=C openssl x509 -in "${SB_HY2_CERT_PATH}" -noout -text 2>/dev/null \
    | awk -F': ' '/Public Key Algorithm:/ {print $2; exit}' || true)
  algorithm=$(trim_whitespace "${algorithm}")
  [[ -n "${algorithm}" ]] || return 1

  printf '%s' "${algorithm}"
}

hy2_manual_certificate_uses_ed25519() {
  local algorithm

  algorithm=$(hy2_manual_certificate_algorithm) || return 1
  [[ "${algorithm^^}" == "ED25519" ]]
}

hy2_client_needs_chrome_parrot_disabled() {
  singbox_config_supports_1_14 && hy2_manual_certificate_uses_ed25519
}

build_hy2_compatibility_warnings_json() {
  local context=${1:-share}
  local algorithm code message

  if [[ "${SB_HY2_TLS_MODE:-}" != "manual" ]]; then
    printf '[]'
    return 0
  fi

  if ! algorithm=$(hy2_manual_certificate_algorithm); then
    jq -n '[{
      code: "hy2_certificate_algorithm_unknown",
      message: "无法识别 Hysteria2 手动证书的公钥算法；请确认 1.14+ 客户端与证书算法兼容。"
    }]'
    return 0
  fi

  if [[ "${algorithm^^}" != "ED25519" ]]; then
    printf '[]'
    return 0
  fi

  if [[ "${context}" == "export" ]]; then
    if ! singbox_config_supports_1_14; then
      printf '[]'
      return 0
    fi
    code="hy2_ed25519_chrome_parrot_disabled"
    message="检测到 Hysteria2 手动 Ed25519 证书；导出的 1.14+ 客户端配置已设置 disable_chrome_parrot=true。"
  else
    code="hy2_ed25519_share_link_requires_client_override"
    message="检测到 Hysteria2 手动 Ed25519 证书；分享链接无法携带 disable_chrome_parrot，1.14+ 客户端必须手动启用该选项。"
  fi

  jq -n \
    --arg code "${code}" \
    --arg message "${message}" \
    '[{code: $code, message: $message}]'
}

collect_hy2_compatibility_warnings_json() (
  local context=${1:-share}

  if ! protocol_state_exists "hy2" || ! load_protocol_state "hy2" "read-only"; then
    printf '[]'
    return 0
  fi

  build_hy2_compatibility_warnings_json "${context}"
)

print_hy2_compatibility_warnings() {
  local context=${1:-share}
  local warnings_json warning_message

  warnings_json=$(collect_hy2_compatibility_warnings_json "${context}")
  while IFS= read -r warning_message; do
    [[ -n "${warning_message}" ]] && log_warn "${warning_message}"
  done < <(jq -r '.[]?.message' <<< "${warnings_json}")
}

build_hy2_link() {
  local public_ip=$1
  local address_label=${2:-}
  local server_host query node_name
  server_host=${SB_HY2_DOMAIN:-${public_ip}}
  node_name=$(display_node_name_for_protocol "hy2" "${SB_NODE_NAME}" "${address_label}")
  query="sni=${SB_HY2_DOMAIN:-${server_host}}"

  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    query="${query}&obfs=${SB_HY2_OBFS_TYPE:-salamander}&obfs-password=${SB_HY2_OBFS_PASSWORD}"
  fi

  printf 'hy2://%s@%s:%s?%s#%s' \
    "${SB_HY2_PASSWORD}" \
    "$(format_share_host "${server_host}")" \
    "${SB_PORT}" \
    "${query}" \
    "${node_name}"
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
  local protocol prefix instance_id address_label stack_suffix key
  protocol=$(normalize_protocol_id "$1")
  instance_id=${2:-}
  address_label=${3:-}
  prefix=$(subman_node_prefix)

  if [[ "${protocol}" == "vless-reality" && -n "${instance_id}" && "${instance_id}" != "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" ]]; then
    key=$(printf 'sing-box-vps:%s:%s:%s' "${prefix}" "${protocol}" "${instance_id}")
  else
    key=$(printf 'sing-box-vps:%s:%s' "${prefix}" "${protocol}")
  fi

  stack_suffix=$(network_stack_suffix_from_label "${address_label}")
  if [[ -n "${stack_suffix}" ]]; then
    key="${key}:${stack_suffix}"
  fi

  printf '%s' "${key}"
}

build_subman_raw_for_protocol() {
  local protocol public_ip address_label instance_id
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2
  address_label=${3:-}
  instance_id=${4:-}

  case "${protocol}" in
    vless-reality)
      if [[ -n "${instance_id}" ]]; then
        build_vless_link_for_instance "${instance_id}" "${public_ip}" "${address_label}"
      else
        build_vless_link "${public_ip}" "${address_label}"
      fi
      ;;
    hy2) build_hy2_link "${public_ip}" "${address_label}" ;;
    *) return 1 ;;
  esac
}

build_subman_node_payload() {
  local protocol public_ip address_label instance_id node_type raw_link node_name prefix
  protocol=$(normalize_protocol_id "$1")
  public_ip=$2
  address_label=${3:-}
  instance_id=${4:-}
  if [[ "${protocol}" == "vless-reality" && -n "${instance_id}" ]]; then
    load_vless_reality_protocol_state
    load_vless_reality_instance_state "${instance_id}" || return 1
  fi
  node_type=$(subman_type_for_protocol "${protocol}") || return 1
  raw_link=$(build_subman_raw_for_protocol "${protocol}" "${public_ip}" "${address_label}" "${instance_id}") || return 1
  if [[ "${protocol}" == "vless-reality" && -n "${instance_id}" ]]; then
    load_vless_reality_protocol_state
    load_vless_reality_instance_state "${instance_id}" || return 1
  fi
  prefix=$(subman_node_prefix)
  node_name=$(trim_whitespace "$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME:-}" "${address_label}")")
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

push_subman_protocol_instance() {
  local protocol=$1
  local public_ip=$2
  local instance_id=${3:-}
  local quiet=${4:-n}
  local address_label=${5:-}
  local external_key payload_json

  if ! external_key=$(subman_external_key_for_protocol "${protocol}" "${instance_id}" "${address_label}"); then
    [[ "${quiet}" == "y" ]] || print_warn "生成 SubMan 外部键失败: ${protocol}"
    return 1
  fi

  if ! payload_json=$(build_subman_node_payload "${protocol}" "${public_ip}" "${address_label}" "${instance_id}"); then
    [[ "${quiet}" == "y" ]] || print_warn "生成 SubMan 节点载荷失败: ${protocol}"
    return 1
  fi

  if [[ "${quiet}" == "y" ]]; then
    push_subman_node "${external_key}" "${payload_json}" >/dev/null
  else
    push_subman_node "${external_key}" "${payload_json}"
  fi
}

reset_subman_api_result() {
  SUBMAN_LAST_HTTP_STATUS=""
  SUBMAN_LAST_ERROR_CODE=""
  SUBMAN_LAST_ERROR_DISPOSITION=""
  SUBMAN_LAST_RETRY_AFTER=""
  SUBMAN_LAST_REVISION=""
  SUBMAN_LAST_NODE_ID=""
  SUBMAN_LAST_RESPONSE_BODY=""
  SUBMAN_LAST_RESPONSE_ETAG=""
  SUBMAN_LAST_RESPONSE_REVISION=""
}

subman_set_client_error() {
  SUBMAN_LAST_ERROR_CODE=$1
  SUBMAN_LAST_ERROR_DISPOSITION=$2
}

validate_subman_node_request() {
  local external_key=$1
  local payload_json=$2
  local external_key_bytes

  external_key_bytes=$(printf '%s' "${external_key}" | wc -c | tr -d '[:space:]')
  if [[ -z "${external_key}" || "${external_key_bytes}" -gt 256 ]]; then
    subman_set_client_error "invalid_external_key" "invalid-request"
    return 1
  fi

  if ! jq -e '
    type == "object"
    and (.name | type == "string" and utf8bytelength > 0 and utf8bytelength <= 256)
    and (.type | type == "string" and IN("vless", "vmess", "trojan", "ss", "ssr", "hysteria2", "tuic", "anytls", "other"))
    and (.raw | type == "string" and utf8bytelength > 0 and utf8bytelength <= 16384)
    and ((.enabled // true) | type == "boolean")
    and ((.source // "single") | IN("single", "subscription"))
    and ((.tags // []) | type == "array" and length <= 64)
    and all((.tags // [])[];
      if type == "string" then
        utf8bytelength > 0 and utf8bytelength <= 128 and (ascii_downcase | startswith("external:") | not)
      elif type == "object" then
        (.label | type == "string" and utf8bytelength > 0 and utf8bytelength <= 128 and (ascii_downcase | startswith("external:") | not))
      else
        false
      end
    )
  ' >/dev/null 2>&1 <<< "${payload_json}"; then
    subman_set_client_error "invalid_node_payload" "invalid-request"
    return 1
  fi
}

subman_api_request() {
  local method=$1
  local path=$2
  local payload_json=${3:-}
  local if_match=${4:-}
  local api_url endpoint tmp_dir request_dir config_file payload_file headers_file body_file stderr_file
  local escaped_token escaped_if_match http_status curl_status

  reset_subman_api_result
  api_url=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  if [[ -z "${api_url}" ]]; then
    subman_set_client_error "api_url_missing" "invalid-request"
    return 1
  fi
  if [[ -z "${SUBMAN_API_TOKEN:-}" ]]; then
    subman_set_client_error "api_token_missing" "auth-required"
    return 1
  fi

  endpoint="${api_url}${path}"
  tmp_dir=${TMPDIR:-/tmp}
  if ! request_dir=$(mktemp -d "${tmp_dir%/}/subman-api.XXXXXX"); then
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi
  if ! chmod 700 "${request_dir}"; then
    rm -rf -- "${request_dir}" || true
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi
  config_file="${request_dir}/curl.conf"
  payload_file="${request_dir}/payload.json"
  headers_file="${request_dir}/headers.txt"
  body_file="${request_dir}/body.json"
  stderr_file="${request_dir}/curl.stderr"
  if ! {
    : > "${headers_file}"
    : > "${body_file}"
    : > "${stderr_file}"
    chmod 600 "${headers_file}" "${body_file}" "${stderr_file}"
  }; then
    rm -rf -- "${request_dir}" || true
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi

  escaped_token=${SUBMAN_API_TOKEN//\\/\\\\}
  escaped_token=${escaped_token//\"/\\\"}
  if ! {
    printf 'header = "Authorization: Bearer %s"\n' "${escaped_token}"
    if [[ -n "${payload_json}" ]]; then
      printf 'header = "Content-Type: application/json"\n'
    fi
    if [[ -n "${if_match}" ]]; then
      escaped_if_match=${if_match//\\/\\\\}
      escaped_if_match=${escaped_if_match//\"/\\\"}
      printf 'header = "If-Match: %s"\n' "${escaped_if_match}"
    fi
  } > "${config_file}" || ! chmod 600 "${config_file}"; then
    rm -rf -- "${request_dir}" || true
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi

  if [[ -n "${payload_json}" ]]; then
    if ! printf '%s' "${payload_json}" > "${payload_file}" || ! chmod 600 "${payload_file}"; then
      rm -rf -- "${request_dir}" || true
      subman_set_client_error "temporary_file_failed" "operator-repair"
      return 1
    fi
  fi

  if [[ -n "${payload_json}" ]]; then
    if http_status=$(curl -sS --config "${config_file}" -X "${method}" "${endpoint}" \
      --data-binary "@${payload_file}" -D "${headers_file}" -o "${body_file}" \
      -w '%{http_code}' 2> "${stderr_file}"); then
      curl_status=0
    else
      curl_status=$?
    fi
  else
    if http_status=$(curl -sS --config "${config_file}" -X "${method}" "${endpoint}" \
      -D "${headers_file}" -o "${body_file}" -w '%{http_code}' 2> "${stderr_file}"); then
      curl_status=0
    else
      curl_status=$?
    fi
  fi

  SUBMAN_LAST_HTTP_STATUS=${http_status:-000}
  SUBMAN_LAST_RESPONSE_BODY=$(cat "${body_file}")
  SUBMAN_LAST_RESPONSE_ETAG=$(awk 'BEGIN { IGNORECASE=1 } /^ETag:/ { sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); value=$0 } END { print value }' "${headers_file}")
  SUBMAN_LAST_RESPONSE_REVISION=$(awk 'BEGIN { IGNORECASE=1 } /^X-SubMan-Revision:/ { sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); value=$0 } END { print value }' "${headers_file}")
  SUBMAN_LAST_RETRY_AFTER=$(awk 'BEGIN { IGNORECASE=1 } /^Retry-After:/ { sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); value=$0 } END { print value }' "${headers_file}")
  [[ "${SUBMAN_LAST_RETRY_AFTER}" =~ ^[0-9]+$ ]] || SUBMAN_LAST_RETRY_AFTER=""
  if ! rm -rf -- "${request_dir}"; then
    subman_set_client_error "temporary_cleanup_failed" "operator-repair"
    return 1
  fi

  if [[ "${curl_status}" -ne 0 ]]; then
    subman_set_client_error "transport_error" "unknown-outcome"
    return 1
  fi
}

capture_subman_api_error() {
  local error_code error_disposition
  error_code=$(jq -r 'if (.error.code | type) == "string" then .error.code else empty end' 2>/dev/null <<< "${SUBMAN_LAST_RESPONSE_BODY}" || true)
  error_disposition=$(jq -r 'if (.error.disposition | type) == "string" then .error.disposition else empty end' 2>/dev/null <<< "${SUBMAN_LAST_RESPONSE_BODY}" || true)
  SUBMAN_LAST_ERROR_CODE=${error_code:-unexpected_response}
  SUBMAN_LAST_ERROR_DISPOSITION=${error_disposition:-operator-repair}
}

report_subman_api_failure() {
  local action=$1
  local detail="HTTP ${SUBMAN_LAST_HTTP_STATUS:-000}"

  [[ -n "${SUBMAN_LAST_ERROR_CODE}" ]] && detail="${detail}, ${SUBMAN_LAST_ERROR_CODE}"
  [[ -n "${SUBMAN_LAST_ERROR_DISPOSITION}" ]] && detail="${detail}/${SUBMAN_LAST_ERROR_DISPOSITION}"
  if [[ -n "${SUBMAN_LAST_RETRY_AFTER}" ]]; then
    detail="${detail}, Retry-After ${SUBMAN_LAST_RETRY_AFTER}s"
  fi
  print_warn "SubMan ${action}失败: ${detail}"
  if [[ "${SUBMAN_LAST_ERROR_DISPOSITION}" == "unknown-outcome" ]]; then
    print_warn "请求结果不确定；请先在 SubMan 查询节点状态，不要直接盲目重试。"
  fi
}

validate_subman_workspace_response() {
  local response_kind=$1
  local expected_external_key=${2:-}
  local body_revision expected_etag external_label
  local jq_filter

  case "${response_kind}" in
    node)
      jq_filter='(.data.id | type == "string" and length > 0) and (.data.tags | type == "array")'
      ;;
    list)
      jq_filter='(.data | type == "array")'
      ;;
    delete)
      jq_filter='(.data.deleted == true)'
      ;;
    *)
      subman_set_client_error "unexpected_response" "operator-repair"
      return 1
      ;;
  esac

  if ! jq -e "${jq_filter} and (.workspace.file == \"subman.json\") and (.workspace.revision | type == \"number\" and . >= 0 and floor == .)" \
    >/dev/null 2>&1 <<< "${SUBMAN_LAST_RESPONSE_BODY}"; then
    subman_set_client_error "unexpected_response" "operator-repair"
    return 1
  fi

  body_revision=$(jq -r '.workspace.revision' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
  expected_etag="\"subman-revision-${body_revision}\""
  if [[ "${SUBMAN_LAST_RESPONSE_REVISION}" != "${body_revision}" || "${SUBMAN_LAST_RESPONSE_ETAG}" != "${expected_etag}" ]]; then
    subman_set_client_error "revision_contract_mismatch" "operator-repair"
    return 1
  fi

  if [[ "${response_kind}" == "node" && -n "${expected_external_key}" ]]; then
    external_label="external:${expected_external_key}"
    if ! jq -e --arg label "${external_label}" '
      any(.data.tags[]?; (if type == "string" then . else .label end) == $label)
    ' >/dev/null 2>&1 <<< "${SUBMAN_LAST_RESPONSE_BODY}"; then
      subman_set_client_error "external_key_contract_mismatch" "operator-repair"
      return 1
    fi
  fi

  SUBMAN_LAST_REVISION=${body_revision}
  if [[ "${response_kind}" == "node" ]]; then
    SUBMAN_LAST_NODE_ID=$(jq -r '.data.id' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
  fi
}

push_subman_node() {
  local external_key=$1
  local payload_json=$2
  local encoded_key

  reset_subman_api_result
  if ! validate_subman_node_request "${external_key}" "${payload_json}"; then
    report_subman_api_failure "节点推送"
    return 1
  fi

  encoded_key=$(jq -rn --arg value "${external_key}" '$value | @uri')
  if ! subman_api_request "PUT" "/api/nodes/by-key/${encoded_key}" "${payload_json}"; then
    report_subman_api_failure "节点推送"
    return 1
  fi
  if [[ "${SUBMAN_LAST_HTTP_STATUS}" != "200" ]]; then
    capture_subman_api_error
    report_subman_api_failure "节点推送"
    return 1
  fi
  if ! validate_subman_workspace_response "node" "${external_key}"; then
    report_subman_api_failure "节点推送"
    return 1
  fi

  print_success "SubMan 节点推送成功: HTTP 200, Workspace revision ${SUBMAN_LAST_REVISION}"
}

delete_subman_node_by_external_key() {
  local external_key=$1
  local quiet=${2:-n}
  local external_label node_id node_count encoded_node_id attempt if_match

  external_label="external:${external_key}"
  for attempt in 1 2; do
    if ! subman_api_request "GET" "/api/nodes"; then
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点查询"
      return 1
    fi
    if [[ "${SUBMAN_LAST_HTTP_STATUS}" != "200" ]]; then
      capture_subman_api_error
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点查询"
      return 1
    fi
    if ! validate_subman_workspace_response "list"; then
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点查询"
      return 1
    fi

    node_count=$(jq -r --arg label "${external_label}" '[
      .data[]
      | select(any(.tags[]?; (if type == "string" then . else .label end) == $label))
      | .id
    ] | unique | length' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
    if [[ "${node_count}" -eq 0 ]]; then
      [[ "${quiet}" == "y" ]] || print_info "SubMan 旧节点无需清理: ${external_key}"
      return 0
    fi
    if [[ "${node_count}" -ne 1 ]]; then
      subman_set_client_error "external_key_ambiguous" "operator-repair"
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
      return 1
    fi

    node_id=$(jq -r --arg label "${external_label}" '
      [.data[] | select(any(.tags[]?; (if type == "string" then . else .label end) == $label)) | .id]
      | unique[0]
    ' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
    if_match=${SUBMAN_LAST_RESPONSE_ETAG}
    encoded_node_id=$(jq -rn --arg value "${node_id}" '$value | @uri')
    if ! subman_api_request "DELETE" "/api/nodes/${encoded_node_id}" "" "${if_match}"; then
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
      return 1
    fi
    if [[ "${SUBMAN_LAST_HTTP_STATUS}" == "200" ]]; then
      if validate_subman_workspace_response "delete"; then
        [[ "${quiet}" == "y" ]] || print_success "SubMan 旧节点已删除: ${external_key}, Workspace revision ${SUBMAN_LAST_REVISION}"
        return 0
      fi
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
      return 1
    fi

    capture_subman_api_error
    if [[ "${attempt}" -eq 1 && "${SUBMAN_LAST_ERROR_DISPOSITION}" == "state-conflict" ]]; then
      continue
    fi
    if [[ "${SUBMAN_LAST_ERROR_CODE}" == "entity_not_found" || "${SUBMAN_LAST_ERROR_CODE}" == "entity_deleted" || "${SUBMAN_LAST_ERROR_CODE}" == "not_found" ]]; then
      return 0
    fi
    [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
    return 1
  done
}

push_subman_legacy_protocol_key_cleanup() {
  local protocol=$1
  local instance_id=${2:-}
  local quiet=${3:-n}
  local external_key

  if ! external_key=$(subman_external_key_for_protocol "${protocol}" "${instance_id}" ""); then
    [[ "${quiet}" == "y" ]] || print_warn "生成 SubMan 旧节点清理键失败: ${protocol}"
    return 1
  fi

  delete_subman_node_by_external_key "${external_key}" "${quiet}"
}

subman_instance_ready_for_legacy_cleanup() {
  local attempted=$1
  local synced=$2
  local stacked_synced=$3

  (( attempted > 0 && synced == attempted && stacked_synced == attempted ))
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
      "client_metadata": "",
      "tls": {
        "enabled": true,
        "server_name": $sni
      }
    }'
}

client_outbound_tag_for_protocol() {
  local protocol address_label=${2:-}
  protocol=$(normalize_protocol_id "$1")
  if [[ -n "${SB_NODE_NAME:-}" ]]; then
    display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "${address_label}"
    return 0
  fi

  printf '%s' "$(default_node_name_for_protocol "$(state_protocol_to_runtime "${protocol}")")"
}

build_client_vless_reality_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local outbound_tag=${2:-$(client_outbound_tag_for_protocol "vless-reality")}
  local alpn_json

  alpn_json=$(vless_reality_alpn_json_for_mode "${SB_VLESS_ALPN_MODE:-off}")

  jq -n \
    --arg tag "${outbound_tag}" \
    --arg server "${public_ip}" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg server_name "${SB_SNI}" \
    --arg public_key "${SB_PUBLIC_KEY}" \
    --arg short_id "${SB_SHORT_ID_1}" \
    --arg tcp_fast_open "${SB_VLESS_TCP_FAST_OPEN:-n}" \
    --argjson alpn "${alpn_json}" \
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
    }
    | if $tcp_fast_open == "y" then . + { "tcp_fast_open": true } else . end
    | if $alpn == null then . else .tls += { "alpn": $alpn } end'
}

build_client_vless_reality_outbound_for_instance() {
  local instance_id=$1
  local public_ip=${2:-$(get_public_ip)}
  local outbound_tag=${3:-}

  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${instance_id}" || return 1
  build_client_vless_reality_outbound "${public_ip}" "${outbound_tag:-$(client_outbound_tag_for_protocol "vless-reality")}"
}

vless_reality_client_tag_is_used() {
  local candidate=$1
  shift || true
  local used

  for used in "$@"; do
    [[ "${used}" == "${candidate}" ]] && return 0
  done

  return 1
}

unique_vless_reality_client_tag() {
  local base_tag=$1
  local instance_id=$2
  local port=$3
  shift 3 || true
  local candidate counter

  candidate=${base_tag}
  if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
    printf '%s' "${candidate}"
    return 0
  fi

  candidate="${base_tag}-${instance_id}"
  if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
    printf '%s' "${candidate}"
    return 0
  fi

  candidate="${base_tag}-${port}"
  if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
    printf '%s' "${candidate}"
    return 0
  fi

  counter=2
  while true; do
    candidate="${base_tag}-${instance_id}-${counter}"
    if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
      printf '%s' "${candidate}"
      return 0
    fi
    counter=$((counter + 1))
  done
}

build_client_vless_reality_outbounds() {
  local public_ip=${1:-$(get_public_ip)}
  local instance_id outbound_json base_tag outbound_tag
  local status=0 count=0
  local used_tags=()

  migrate_vless_reality_state_to_instances_if_needed
  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    load_vless_reality_protocol_state
    if ! load_vless_reality_instance_state "${instance_id}"; then
      status=1
      continue
    fi
    base_tag=$(client_outbound_tag_for_protocol "vless-reality")
    outbound_tag=$(unique_vless_reality_client_tag "${base_tag}" "${instance_id}" "${SB_PORT}" "${used_tags[@]}")
    if outbound_json=$(build_client_vless_reality_outbound "${public_ip}" "${outbound_tag}"); then
      printf '%s\n' "${outbound_json}"
      used_tags+=("${outbound_tag}")
      count=$((count + 1))
    else
      status=$?
    fi
  done < <(list_vless_reality_instance_ids)

  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" >/dev/null 2>&1 || true

  if (( count == 0 )); then
    log_warn "未找到可用的 VLESS + REALITY 实例，已跳过客户端导出协议: vless-reality" >&2
    return 1
  fi

  return "${status}"
}

build_client_hy2_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local server_host tls_server_name disable_chrome_parrot="n"
  server_host=${public_ip}
  tls_server_name=${SB_HY2_DOMAIN:-${public_ip}}
  if hy2_client_needs_chrome_parrot_disabled; then
    disable_chrome_parrot="y"
  fi

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
    --arg disable_chrome_parrot "${disable_chrome_parrot}" \
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
      if $disable_chrome_parrot == "y" then
        { "disable_chrome_parrot": true }
      else
        {}
      end
    ) + (
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
  local protocol original_protocol_state outbound_json build_status restore_original_state public_ip
  protocol=$(normalize_protocol_id "$1")
  public_ip=${2:-$(get_public_ip)}
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
      if outbound_json=$(build_client_vless_reality_outbounds "${public_ip}"); then
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
      build_vless_link "${public_ip}" "${address_label}"
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
      build_vless_link "${public_ip}" "${address_label}"
      echo ""
    fi
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    echo "1. Hysteria2 协议链接"
    build_hy2_link "${public_ip}" "${address_label}"
    echo ""
    print_hy2_compatibility_warnings "share"
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
  local address_label=${2:-}
  local instance_id
  local header_label

  header_label="${address_label}"
  if protocol_uses_domain_connection_material; then
    header_label=""
  fi

  if [[ -n "${header_label}" ]]; then
    echo -e "\n${YELLOW}连接二维码 ${header_label}：${NC}"
  else
    echo -e "\n${YELLOW}连接二维码：${NC}"
  fi

  if [[ "${SB_PROTOCOL}" == "mixed" ]]; then
    log_info "Mixed 协议当前不提供二维码，请使用链接方式手动配置客户端。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "anytls" ]]; then
    log_info "AnyTLS 当前不展示二维码，请使用参数摘要与 outbound JSON 示例手动导入客户端。"
    return 0
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    log_warn "未安装 qrencode，已跳过二维码展示。可安装后重新进入菜单 11 查看。"
    return 0
  fi

  if [[ "${SB_PROTOCOL}" == "hy2" ]]; then
    echo "1. Hysteria2 协议二维码"
    qrencode -t ansiutf8 "$(build_hy2_link "${public_ip}" "${address_label}")"
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
      qrencode -t ansiutf8 "$(build_vless_link "${public_ip}" "${address_label}")"
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
      qrencode -t ansiutf8 "$(build_vless_link "${public_ip}" "${address_label}")"
    fi
    return 0
  fi
}

show_connection_details() {
  local mode=$1
  local public_ip=${2:-$(get_public_ip)}
  local address_label=${3-}

  if [[ $# -lt 3 && -z "${address_label}" ]]; then
    if [[ "${public_ip}" == *:* ]]; then
      address_label="IPv6"
    elif [[ "${public_ip}" == *.* ]]; then
      address_label="IPv4"
    fi
  fi

  case "${mode}" in
    link)
      show_link_info "${public_ip}" "${address_label}"
      ;;
    qr)
      show_qr_info "${public_ip}" "${address_label}"
      ;;
    both)
      show_link_info "${public_ip}" "${address_label}"
      show_qr_info "${public_ip}" "${address_label}"
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
      [[ -n "${ipv4_address}" ]] && printf 'IPv4|%s\n' "${ipv4_address}"
      ;;
    ipv6_only)
      ipv6_address=$(get_public_ipv6)
      [[ -n "${ipv6_address}" ]] && printf 'IPv6|%s\n' "${ipv6_address}"
      ;;
    *)
      ipv4_address=$(get_public_ipv4)
      ipv6_address=$(get_public_ipv6)
      [[ -n "${ipv4_address}" ]] && printf 'IPv4|%s\n' "${ipv4_address}"
      [[ -n "${ipv6_address}" ]] && printf 'IPv6|%s\n' "${ipv6_address}"
      ;;
  esac

  if [[ -z "${ipv4_address:-}" && -z "${ipv6_address:-}" ]]; then
    fallback_address=$(get_public_ip)
    [[ -n "${fallback_address}" ]] && printf '地址|%s\n' "${fallback_address}"
  fi
}

protocol_uses_domain_connection_material() {
  case "$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)" in
    hy2|anytls) return 0 ;;
    *) return 1 ;;
  esac
}

list_subman_addresses_for_current_protocol() {
  local public_ip address_entries=()

  if protocol_uses_domain_connection_material; then
    public_ip=$(get_public_ip)
    if [[ -n "${public_ip}" ]]; then
      printf '地址|%s\n' "${public_ip}"
    fi
    return 0
  fi

  mapfile -t address_entries < <(list_public_addresses_for_current_stack)
  if [[ ${#address_entries[@]} -eq 0 ]]; then
    public_ip=$(get_public_ip)
    if [[ -n "${public_ip}" ]]; then
      printf '地址|%s\n' "${public_ip}"
    fi
    return 0
  fi

  printf '%s\n' "${address_entries[@]}"
}

show_connection_details_for_detected_addresses() {
  local mode=$1
  local address_entries=()
  local entry label address public_ip

  if protocol_uses_domain_connection_material; then
    public_ip=$(get_public_ip)
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
  local original_protocol_state clash_api_secret public_ip tmpdir
  local installed_protocols=() exportable_protocols=()
  local remote_outbounds_json remote_tags_json
  local protocol outbound_json usable_protocol_count
  local use_rule_set_http_client="n"
  local status=0

  if singbox_config_supports_1_14; then
    use_rule_set_http_client="y"
  fi

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
      --arg use_rule_set_http_client "${use_rule_set_http_client}" \
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
          "rule_set": (
            [
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
            ]
            | map(
                if $use_rule_set_http_client == "y" then
                  . + {"http_client": {"detour": "proxy"}}
                else
                  .
                end
              )
          ),
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
  print_hy2_compatibility_warnings "export"
  printf '文件路径: %s\n' "${export_path}"
  printf 'WSL2 使用方式: 请将应用代理手动指向 127.0.0.1:2080\n'
  printf '系统代理: 未启用（set_system_proxy=false）\n'
  printf 'Clash API 地址: 127.0.0.1:9090\n'
  printf '%s\n' "${config_json}"
}

agent_print_help() {
  cat <<'EOF'
用法:
  sbv agent help
  sbv agent capabilities --json
  sbv agent upgrade-check --json x.y.z
  sbv agent upgrade --json x.y.z --yes
  sbv agent status --json
  sbv agent nodes --json
  sbv agent links --json
  sbv agent export-client --json
  sbv agent check --json
  sbv agent doctor --json
  sbv agent service restart --json --yes
  sbv agent subman-sync --json
  sbv agent warp --json

说明:
  capabilities  输出协议、功能入口以及只读/变更/敏感分类。
  upgrade-check 只读评估固定目标版本的升级就绪状态，不下载或替换二进制。
  upgrade       创建持久备份并执行受 --yes 保护的二进制升级，输出结构化结果。
  status        输出服务、版本、路径和已安装协议。
  nodes         输出节点摘要，不包含完整分享链接或密码。
  links         输出完整连接材料，适合受信任 Agent 获取节点信息。
  export-client 生成并校验 sing-box 裸核客户端配置，写入固定路径并输出 JSON。
  warp          输出 Cloudflare Warp 状态，包括启用/路由模式/账户/规则统计。
  check         执行 sing-box check 并输出结构化结果。
  doctor        输出只读诊断信息和配置校验结果。
  service       执行带 --yes 保护的服务操作，目前支持 restart。
  subman-sync   非交互推送节点到 SubMan，缺少配置时返回结构化错误。
EOF
}

agent_require_json_flag() {
  if [[ "${1:-}" != "--json" ]]; then
    agent_json_error "json_required" "agent 子命令当前仅支持 --json 输出。"
    return 1
  fi
}

agent_json_error() {
  local error=$1
  local message=$2

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg error "${error}" \
    --arg message "${message}" \
    '{schema: $schema, ok: false, error: $error, message: $message}'
}

agent_emit_json_envelope() {
  local command=$1
  local status=$2
  local payload=${3:-}
  local timestamp
  local command_ok=false
  local payload_ok
  local effective_ok=false

  [[ "${status}" == "0" ]] && command_ok=true
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  if [[ -z "${payload}" ]] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "${payload}"; then
    jq -n \
      --arg schema_version "1.0" \
      --arg command "${command}" \
      --arg timestamp "${timestamp}" \
      '{
        schema: "1",
        schema_version: $schema_version,
        command: $command,
        timestamp: $timestamp,
        ok: false,
        data: {},
        error: "internal_error",
        message: "agent 命令未生成有效 JSON 对象。"
      }'
    [[ "${status}" == "0" ]] && return 1
    return "${status}"
  fi

  payload_ok=$(jq -r 'if (.ok | type) == "boolean" then .ok else empty end' <<< "${payload}")
  if [[ "${command_ok}" == "true" && "${payload_ok:-true}" == "true" ]]; then
    effective_ok=true
  fi

  jq -n \
    --arg schema_version "1.0" \
    --arg command "${command}" \
    --arg timestamp "${timestamp}" \
    --argjson effective_ok "${effective_ok}" \
    --argjson payload "${payload}" \
    '(
      $payload + {
        schema: "1",
        schema_version: $schema_version,
        command: $command,
        timestamp: $timestamp,
        ok: $effective_ok,
        data: $payload
      }
    )'
  [[ "${effective_ok}" == "true" ]] && return 0
  return 1
}

agent_cli_run() {
  local command=$1
  shift
  local payload status

  if payload=$("$@"); then
    status=0
  else
    status=$?
  fi
  agent_emit_json_envelope "${command}" "${status}" "${payload}"
  return $?
}

agent_cli_error() {
  local command=$1
  local error=$2
  local message=$3
  local payload

  payload=$(agent_json_error "${error}" "${message}")
  agent_emit_json_envelope "${command}" 1 "${payload}"
  return 1
}

agent_file_sha256() {
  local file=$1

  if [[ ! -f "${file}" ]]; then
    printf ''
    return 0
  fi

  sha256sum "${file}" | awk '{print $1}'
}

detect_existing_instance_state_read_only() {
  local has_bin="n"
  local has_service="n"
  local has_config="n"
  local has_index="n"
  local has_state="n"
  local state_file

  [[ -x "${SINGBOX_BIN_PATH}" ]] && has_bin="y"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && has_service="y"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && has_config="y"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && has_index="y"

  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
      [[ -e "${state_file}" ]] || continue
      [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] && continue
      has_state="y"
      break
    done
  fi

  if [[ "${has_bin}" == "n" && "${has_service}" == "n" && "${has_config}" == "n" && "${has_index}" == "n" && "${has_state}" == "n" ]]; then
    printf 'fresh'
    return 0
  fi

  if [[ "${has_bin}" == "y" && "${has_service}" == "y" && "${has_config}" == "y" && "${has_index}" == "y" && "${has_state}" == "y" ]] && \
    protocol_state_layer_matches_config; then
    printf 'healthy'
    return 0
  fi

  printf 'incomplete'
}

agent_capabilities_json() {
  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg script_version "${SCRIPT_VERSION}" \
    --arg supported_version "${SB_SUPPORT_MAX_VERSION}" \
    --arg backup_root "${SB_UPGRADE_BACKUP_ROOT}" \
    '{
      schema: $schema,
      ok: true,
      action: "capabilities",
      script_version: $script_version,
      supported_sing_box_version: $supported_version,
      multi_protocol_coexistence: true,
      protocols: {
        "vless-reality": {
          multi_instance: true,
          per_instance_outbound: ["default", "direct", "warp"],
          qos: {upload_mbps: true, download_mbps: true},
          share_link: true,
          qr: true,
          client_export: true,
          subman_sync: true
        },
        mixed: {
          http: true,
          socks5: true,
          authentication: true,
          share_links: ["http", "socks5"],
          qr: false,
          client_export: false,
          subman_sync: false
        },
        hysteria2: {
          tls_modes: ["acme_http01", "acme_cloudflare_dns01", "manual"],
          bandwidth: true,
          obfs: true,
          share_link: true,
          qr: true,
          client_export: true,
          subman_sync: true
        },
        anytls: {
          tls_modes: ["acme_http01", "acme_cloudflare_dns01", "manual"],
          standard_share_uri: false,
          outbound_example: true,
          qr: false,
          client_export: true,
          subman_sync: false
        }
      },
      features: {
        warp: {
          route_modes: ["all", "selective"],
          account_registration: true,
          custom_domains: true,
          local_rule_sets: true,
          remote_rule_sets: true
        },
        network_stack: {
          inbound: ["ipv4_only", "ipv6_only", "dual_stack"],
          outbound: ["ipv4_only", "ipv6_only", "prefer_ipv4", "prefer_ipv6"]
        },
        system: {bbr: true, firewall_port_management: true},
        connection_material: {links: true, ansi_qr: true, bare_core_client_export: true},
        lifecycle: {
          service_start_stop_restart_status_logs: true,
          managed_instance_takeover_repair: true,
          core_upgrade_and_uninstall: true,
          script_self_update_and_uninstall: true
        },
        diagnostics: {config_check: true, doctor: true, media_check: true},
        subman: {supported_protocols: ["vless-reality", "hysteria2"], idempotent_sync: true}
      },
      commands: {
        capabilities: {mutation: false, sensitive: false},
        status: {mutation: false, sensitive: false},
        nodes: {mutation: false, sensitive: false},
        links: {mutation: false, sensitive: true},
        warp: {mutation: false, sensitive: false},
        check: {mutation: false, sensitive: false},
        doctor: {mutation: false, sensitive: false},
        "upgrade-check": {mutation: false, sensitive: false},
        upgrade: {mutation: true, sensitive: false, confirmation: "--yes", service_impact: "restart"},
        "export-client": {mutation: true, sensitive: true},
        "service restart": {mutation: true, sensitive: false, confirmation: "--yes"},
        "subman-sync": {mutation: true, sensitive: true, external_write: true}
      },
      interactive_features: {
        protocol_install_update_remove: true,
        managed_instance_takeover_repair: true,
        reality_multi_instance_and_qos: true,
        warp_mutation: true,
        inbound_outbound_stack_management: true,
        bbr: true,
        media_check: true,
        service_start_stop_and_logs: true,
        script_self_update_and_uninstall: true,
        sing_box_uninstall: true
      },
      upgrade: {
        backup_root: $backup_root,
        manifest_scope: "all_regular_runtime_files_and_control_files",
        rewrites_server_config: false,
        target_binary_check_before_restart: true,
        automatic_binary_rollback_on_failure: true,
        restores_previous_service_activity: true
      }
    }'
}

agent_config_compatibility_json() {
  local target_version=$1
  local inline_acme_count=0
  local download_detour_count=0
  local certificate_provider_count=0
  local http_client_count=0
  local classification="neutral"
  local warnings_json='[]'
  local hy2_warnings_json='[]'

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]] || ! jq -e '.' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
    jq -n \
      --arg classification "unreadable" \
      '{
        schema: {classification: $classification, legacy: false, modern_1_14: false},
        legacy: {tls_acme_count: 0, download_detour_count: 0},
        modern: {certificate_provider_count: 0, http_client_count: 0},
        warnings: [{code: "config_json_unreadable", message: "配置文件不存在或不是有效 JSON。"}]
      }'
    return 0
  fi

  inline_acme_count=$(jq -r '[(.inbounds // [])[] | select(.tls.acme? != null)] | length' "${SINGBOX_CONFIG_FILE}")
  download_detour_count=$(jq -r '[(.route.rule_set // [])[] | select(.download_detour? != null)] | length' "${SINGBOX_CONFIG_FILE}")
  certificate_provider_count=$(jq -r '(.certificate_providers // []) | length' "${SINGBOX_CONFIG_FILE}")
  http_client_count=$(jq -r '[(.route.rule_set // [])[] | select(.http_client? != null)] | length' "${SINGBOX_CONFIG_FILE}")

  if (( inline_acme_count > 0 || download_detour_count > 0 )); then
    classification="legacy_1_13"
  fi
  if (( certificate_provider_count > 0 || http_client_count > 0 )); then
    if [[ "${classification}" == "legacy_1_13" ]]; then
      classification="mixed"
    else
      classification="modern_1_14"
    fi
  fi

  if singbox_version_at_least "${target_version}" "${SB_CONFIG_SCHEMA_1_14_MIN_VERSION}"; then
    if (( inline_acme_count > 0 )); then
      warnings_json=$(jq -n --argjson warnings "${warnings_json}" '
        $warnings + [{
          code: "inline_acme_deprecated",
          message: "tls.acme 在 sing-box 1.14 中仍兼容但已弃用，计划在 1.16 移除。",
          removal_version: "1.16.0"
        }]')
    fi
    if (( download_detour_count > 0 )); then
      warnings_json=$(jq -n --argjson warnings "${warnings_json}" '
        $warnings + [{
          code: "download_detour_deprecated",
          message: "远程规则集 download_detour 在 sing-box 1.14 中仍兼容但已弃用，计划在 1.16 移除。",
          removal_version: "1.16.0"
        }]')
    fi
    hy2_warnings_json=$(collect_hy2_compatibility_warnings_json "share" 2>/dev/null || printf '[]')
    warnings_json=$(jq -n \
      --argjson warnings "${warnings_json}" \
      --argjson hy2_warnings "${hy2_warnings_json}" \
      '$warnings + $hy2_warnings')
  fi

  jq -n \
    --arg classification "${classification}" \
    --argjson inline_acme_count "${inline_acme_count}" \
    --argjson download_detour_count "${download_detour_count}" \
    --argjson certificate_provider_count "${certificate_provider_count}" \
    --argjson http_client_count "${http_client_count}" \
    --argjson warnings "${warnings_json}" \
    '{
      schema: {
        classification: $classification,
        legacy: ($classification == "legacy_1_13" or $classification == "mixed"),
        modern_1_14: ($classification == "modern_1_14" or $classification == "mixed")
      },
      legacy: {
        tls_acme_count: $inline_acme_count,
        download_detour_count: $download_detour_count
      },
      modern: {
        certificate_provider_count: $certificate_provider_count,
        http_client_count: $http_client_count
      },
      warnings: $warnings
    }'
}

agent_upgrade_check_json() {
  local target_input=$1
  local target_version
  local current_version
  local active_state
  local managed_instance_state
  local check_json
  local check_status=0
  local compatibility_json
  local config_sha256
  local blockers_json
  local direction="unknown"
  local target_supported=false
  local ready=false

  if ! target_version=$(normalize_singbox_version_input "${target_input}") || [[ "${target_version}" == "latest" ]]; then
    agent_json_error "invalid_version" "upgrade-check 需要完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。"
    return 1
  fi

  current_version=$(detect_installed_singbox_version)
  current_version=${current_version#v}
  active_state=$(systemctl is-active sing-box 2>/dev/null || true)
  managed_instance_state=$(detect_existing_instance_state_read_only)
  config_sha256=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
  compatibility_json=$(agent_config_compatibility_json "${target_version}")

  if check_json=$(agent_singbox_check_json); then
    check_status=0
  else
    check_status=$?
  fi

  if singbox_version_at_least "${SB_SUPPORT_MAX_VERSION}" "${target_version}"; then
    target_supported=true
  fi

  if [[ "${current_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if [[ "${current_version}" == "${target_version}" ]]; then
      direction="same"
    elif singbox_version_at_least "${target_version}" "${current_version}"; then
      direction="upgrade"
    else
      direction="downgrade"
    fi
  fi

  blockers_json=$(jq -n \
    --arg current "${current_version}" \
    --arg direction "${direction}" \
    --arg managed_instance_state "${managed_instance_state}" \
    --arg active_state "${active_state:-unknown}" \
    --argjson target_supported "${target_supported}" \
    --argjson current_check_ok "$([[ "${check_status}" == "0" ]] && printf 'true' || printf 'false')" \
    '[
      if $target_supported != true then "target_unsupported" else empty end,
      if ($current | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not) then "current_version_unknown" else empty end,
      if $direction == "downgrade" then "downgrade_not_allowed" else empty end,
      if $managed_instance_state != "healthy" then "managed_instance_not_healthy" else empty end,
      if $active_state != "active" then "service_not_active" else empty end,
      if $current_check_ok != true then "current_config_check_failed" else empty end
    ]')

  if [[ "$(jq 'length' <<< "${blockers_json}")" == "0" ]]; then
    ready=true
  fi

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg current "${current_version}" \
    --arg target "${target_version}" \
    --arg direction "${direction}" \
    --arg active_state "${active_state:-unknown}" \
    --arg managed_instance_state "${managed_instance_state}" \
    --arg config_path "${SINGBOX_CONFIG_FILE}" \
    --arg config_sha256 "${config_sha256}" \
    --argjson target_supported "${target_supported}" \
    --argjson ready "${ready}" \
    --argjson current_check "${check_json}" \
    --argjson compatibility "${compatibility_json}" \
    --argjson blockers "${blockers_json}" \
    '{
      schema: $schema,
      ok: $ready,
      ready: $ready,
      action: "sing_box_upgrade_check",
      apply: false,
      current: $current,
      target: $target,
      direction: $direction,
      target_supported: $target_supported,
      blockers: $blockers,
      managed_instance_state: $managed_instance_state,
      service: {active_state: $active_state},
      config: {
        path: $config_path,
        sha256: $config_sha256,
        schema: $compatibility.schema,
        will_be_rewritten: false
      },
      legacy: $compatibility.legacy,
      modern: $compatibility.modern,
      current_check: $current_check,
      target_binary_validation: {
        performed: false,
        stage: "upgrade_before_restart"
      },
      migration_required: false,
      warnings: $compatibility.warnings
    }'

  [[ "${ready}" == "true" ]]
}

create_agent_upgrade_backup() {
  local current_version=$1
  local target_version=$2
  local transaction_id
  local backup_dir
  local manifest_file
  local relative_path
  local runtime_file_list

  transaction_id=$(printf 'tx-%s-%s-%s' "$(date -u '+%Y%m%dT%H%M%SZ')" "$$" "${RANDOM}")

  if ! mkdir -p "${SB_UPGRADE_BACKUP_ROOT}" || ! chmod 700 "${SB_UPGRADE_BACKUP_ROOT}"; then
    return 1
  fi
  backup_dir=$(mktemp -d "${SB_UPGRADE_BACKUP_ROOT}/upgrade-${current_version}-to-${target_version}.XXXXXXXX") || return 1
  if ! chmod 700 "${backup_dir}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  if [[ -d "${SB_PROJECT_DIR}" ]]; then
    if ! cp -a "${SB_PROJECT_DIR}" "${backup_dir}/runtime"; then
      rm -rf -- "${backup_dir}"
      return 1
    fi
  fi
  if [[ -f "${SINGBOX_BIN_PATH}" ]] && ! cp -p "${SINGBOX_BIN_PATH}" "${backup_dir}/sing-box"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -f "${SBV_BIN_PATH}" ]] && ! cp -p "${SBV_BIN_PATH}" "${backup_dir}/sbv"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -f "${SINGBOX_SERVICE_FILE}" ]] && ! cp -p "${SINGBOX_SERVICE_FILE}" "${backup_dir}/sing-box.service"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  if ! jq -n \
    --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg script_version "${SCRIPT_VERSION}" \
    --arg transaction_id "${transaction_id}" \
    --arg current_version "${current_version}" \
    --arg target_version "${target_version}" \
    --arg source_config "${SINGBOX_CONFIG_FILE}" \
    --arg manifest_path "${backup_dir}/SHA256SUMS" \
    '{
      created_at: $created_at,
      script_version: $script_version,
      transaction_id: $transaction_id,
      old_version: $current_version,
      new_version: $target_version,
      current_version: $current_version,
      target_version: $target_version,
      source_config: $source_config,
      manifest_path: $manifest_path,
      manifest_scope: "all_regular_runtime_files_and_control_files",
      contains_sensitive_runtime_material: true
    }' > "${backup_dir}/metadata.json"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  manifest_file="${backup_dir}/SHA256SUMS"
  runtime_file_list="${backup_dir}/.runtime-files"
  if ! : > "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -d "${backup_dir}/runtime" ]] && \
    ! (cd "${backup_dir}" && find runtime -type f -print0) > "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if ! (
    cd "${backup_dir}" || exit 1
    while IFS= read -r -d '' relative_path; do
      sha256sum "${relative_path}" || exit 1
    done < .runtime-files
    for relative_path in sing-box sbv sing-box.service metadata.json; do
      if [[ -f "${relative_path}" ]]; then
        sha256sum "${relative_path}" || exit 1
      fi
    done
  ) > "${manifest_file}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if ! rm -f "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if ! chmod 600 "${manifest_file}" "${backup_dir}/metadata.json" || ! chmod -R go-rwx "${backup_dir}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  printf '%s' "${backup_dir}"
}

write_agent_upgrade_transaction_result() {
  local backup_dir=$1
  local status=$2
  local rollback_attempted=$3
  local rollback_result=$4
  local completed_at=${5:-}
  local failure_reason=${6:-}
  local operation_exit_code=${7:-}
  local metadata_file="${backup_dir}/metadata.json"
  local result_file="${backup_dir}/transaction-result.json"
  local temp_file
  local transaction_id
  local old_version
  local new_version
  local started_at
  local manifest_path
  local manifest_sha256
  local status_history_json
  local status_event_at

  [[ -f "${metadata_file}" && -f "${backup_dir}/SHA256SUMS" ]] || return 1
  transaction_id=$(jq -r '.transaction_id // empty' "${metadata_file}")
  old_version=$(jq -r '.old_version // .current_version // empty' "${metadata_file}")
  new_version=$(jq -r '.new_version // .target_version // empty' "${metadata_file}")
  started_at=$(jq -r '.created_at // empty' "${metadata_file}")
  manifest_path=$(jq -r '.manifest_path // empty' "${metadata_file}")
  manifest_sha256=$(agent_file_sha256 "${backup_dir}/SHA256SUMS")
  [[ -n "${transaction_id}" && -n "${old_version}" && -n "${new_version}" && -n "${started_at}" && -n "${manifest_sha256}" ]] || return 1

  status_event_at="${completed_at:-${started_at}}"
  status_history_json='[]'
  if [[ -f "${result_file}" ]]; then
    status_history_json=$(jq -c '.status_history // []' "${result_file}" 2>/dev/null || printf '[]')
  fi
  status_history_json=$(jq -c \
    --arg status "${status}" \
    --arg at "${status_event_at}" \
    --argjson history "${status_history_json}" \
    '$history + [{status: $status, at: $at}]' <<< '{}') || return 1

  temp_file=$(mktemp "${backup_dir}/.transaction-result.XXXXXXXX") || return 1
  if ! jq -n \
    --arg schema_version "1.0" \
    --arg transaction_id "${transaction_id}" \
    --arg old_version "${old_version}" \
    --arg new_version "${new_version}" \
    --arg started_at "${started_at}" \
    --arg completed_at "${completed_at}" \
    --arg status "${status}" \
    --arg backup_path "${backup_dir}" \
    --arg manifest_path "${manifest_path}" \
    --arg manifest_sha256 "${manifest_sha256}" \
    --arg rollback_result "${rollback_result}" \
    --arg failure_reason "${failure_reason}" \
    --arg operation_exit_code "${operation_exit_code}" \
    --argjson status_history "${status_history_json}" \
    --argjson rollback_attempted "${rollback_attempted}" \
    '{
      schema_version: $schema_version,
      transaction_id: $transaction_id,
      old_version: $old_version,
      new_version: $new_version,
      started_at: $started_at,
      completed_at: (if $completed_at == "" then null else $completed_at end),
      status: $status,
      backup_path: $backup_path,
      manifest_path: $manifest_path,
      manifest_sha256: $manifest_sha256,
      manifest: {path: $manifest_path, sha256: $manifest_sha256},
      status_history: $status_history,
      rollback: {attempted: $rollback_attempted, result: $rollback_result},
      failure_reason: (if $failure_reason == "" then null else $failure_reason end),
      operation_exit_code: (if $operation_exit_code == "" then null else ($operation_exit_code | tonumber) end)
    }' > "${temp_file}"; then
    rm -f "${temp_file}"
    return 1
  fi
  if ! chmod 600 "${temp_file}" || ! mv -f "${temp_file}" "${result_file}"; then
    rm -f "${temp_file}"
    return 1
  fi
}

restore_agent_upgrade_backup() {
  local backup_dir=$1
  local restore_config=${2:-n}
  local service_was_active=${3:-n}
  local status=0
  local artifacts_restored="y"

  case "${backup_dir}" in
    "${SB_UPGRADE_BACKUP_ROOT}"/upgrade-*) ;;
    *) return 1 ;;
  esac

  [[ -f "${backup_dir}/sing-box" && -f "${backup_dir}/SHA256SUMS" ]] || return 1
  (cd "${backup_dir}" && sha256sum -c SHA256SUMS >/dev/null 2>&1) || return 1
  if replace_singbox_binary_atomically "${backup_dir}/sing-box"; then
    :
  else
    status=1
    artifacts_restored="n"
  fi

  if [[ -f "${backup_dir}/sing-box.service" ]]; then
    if ! cp -p "${backup_dir}/sing-box.service" "${SINGBOX_SERVICE_FILE}"; then
      status=1
      artifacts_restored="n"
    fi
  fi
  if [[ "${restore_config}" == "y" && -f "${backup_dir}/runtime/config.json" ]]; then
    if ! cp -p "${backup_dir}/runtime/config.json" "${SINGBOX_CONFIG_FILE}"; then
      status=1
      artifacts_restored="n"
    fi
  fi

  if ! systemctl daemon-reload >/dev/null 2>&1; then
    status=1
    artifacts_restored="n"
  fi
  if [[ "${artifacts_restored}" != "y" ]]; then
    systemctl stop sing-box >/dev/null 2>&1 || status=1
    return 1
  fi
  if [[ "${service_was_active}" == "y" ]]; then
    systemctl restart sing-box >/dev/null 2>&1 || status=1
  else
    systemctl stop sing-box >/dev/null 2>&1 || status=1
  fi

  return "${status}"
}

agent_upgrade_cli() {
  local json_flag=${1:-}
  local target_input=${2:-}
  local yes_flag=${3:-}
  local target_version
  local preflight_json
  local current_version
  local before_hash
  local before_service_state
  local backup_dir
  local operation_log
  local operation_excerpt
  local operation_status=0
  local after_version
  local after_hash
  local after_service_state
  local after_check_json
  local after_check_status=0
  local config_preserved=false
  local changed=false
  local rollback_ok=false
  local final_changed=false
  local manual_intervention_required=false
  local restore_config="n"
  local failure_reason="upgrade_failed"
  local output_error
  local transaction_id
  local transaction_result_file
  local transaction_manifest_path
  local transaction_manifest_sha256
  local transaction_status
  local transaction_rollback_result
  local transaction_result_persisted=false

  if [[ "${json_flag}" != "--json" ]]; then
    agent_json_error "json_required" "upgrade 当前仅支持 --json 输出。"
    return 1
  fi
  if [[ "${yes_flag}" != "--yes" ]]; then
    agent_json_error "confirmation_required" "upgrade 会备份、替换二进制并重启服务，需要 --yes 确认。"
    return 1
  fi
  if ! target_version=$(normalize_singbox_version_input "${target_input}") || [[ "${target_version}" == "latest" ]]; then
    agent_json_error "invalid_version" "upgrade 需要完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。"
    return 1
  fi
  if ! singbox_version_at_least "${SB_SUPPORT_MAX_VERSION}" "${target_version}"; then
    agent_json_error "unsupported_version" "目标版本 ${target_version} 高于当前脚本适配上限 ${SB_SUPPORT_MAX_VERSION}。"
    return 1
  fi

  if ! preflight_json=$(agent_upgrade_check_json "${target_version}"); then
    if jq -e '.managed_instance_state == "healthy" and .current_check.ok != true' >/dev/null 2>&1 <<< "${preflight_json}"; then
      jq -n \
        --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
        --argjson preflight "${preflight_json}" \
        '{schema: $schema, ok: false, error: "config_check_failed", reason: "config_check_failed", preflight: $preflight}'
    else
      jq -n \
        --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
        --argjson preflight "${preflight_json}" \
        '{schema: $schema, ok: false, error: "preflight_failed", reason: "preflight_failed", preflight: $preflight}'
    fi
    return 1
  fi

  current_version=$(jq -r '.current' <<< "${preflight_json}")
  before_hash=$(jq -r '.config.sha256' <<< "${preflight_json}")
  before_service_state=$(jq -r '.service.active_state' <<< "${preflight_json}")

  if [[ "${current_version}" == "${target_version}" ]]; then
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg current "${current_version}" \
      --arg target "${target_version}" \
      --arg config_hash "${before_hash}" \
      --argjson check "$(jq -c '.current_check' <<< "${preflight_json}")" \
      --argjson warnings "$(jq -c '.warnings' <<< "${preflight_json}")" \
      '{
        schema: $schema,
        ok: true,
        action: "sing_box_upgrade",
        changed: false,
        restarted: false,
        rolled_back: false,
        current: $current,
        target: $target,
        installed: $current,
        backup: null,
        config_preserved: true,
        config: {sha256_before: $config_hash, sha256_after: $config_hash},
        check: $check,
        warnings: $warnings,
        transaction: {
          id: null,
          result_path: null,
          status: "not_attempted",
          result_persisted: false,
          reason: "already_installed",
          manifest: {path: null, sha256: null},
          rollback: {attempted: false, result: "not_attempted"}
        }
      }'
    return 0
  fi

  if ! backup_dir=$(create_agent_upgrade_backup "${current_version}" "${target_version}"); then
    agent_json_error "backup_failed" "无法创建升级备份，已取消升级。"
    return 1
  fi

  transaction_id=$(jq -r '.transaction_id' "${backup_dir}/metadata.json")
  transaction_result_file="${backup_dir}/transaction-result.json"
  transaction_manifest_path=$(jq -r '.manifest_path' "${backup_dir}/metadata.json")
  transaction_manifest_sha256=$(agent_file_sha256 "${backup_dir}/SHA256SUMS")
  if ! write_agent_upgrade_transaction_result \
    "${backup_dir}" \
    "backup_ready" \
    false \
    "not_attempted"; then
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg backup "${backup_dir}" \
      --arg transaction_id "${transaction_id}" \
      --arg transaction_result_file "${transaction_result_file}" \
      --arg transaction_manifest_path "${transaction_manifest_path}" \
      --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
      '{
        schema: $schema,
        ok: false,
        error: "transaction_record_failed",
        backup: $backup,
        transaction: {
          id: $transaction_id,
          result_path: $transaction_result_file,
          status: "backup_ready",
          result_persisted: false,
          manifest_path: $transaction_manifest_path,
          manifest_sha256: $transaction_manifest_sha256,
          manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
          rollback: {attempted: false, result: "not_attempted"}
        }
      }'
    return 1
  fi

  if ! operation_log=$(mktemp); then
    transaction_status="failed"
    transaction_rollback_result="not_attempted"
    if write_agent_upgrade_transaction_result \
      "${backup_dir}" \
      "${transaction_status}" \
      false \
      "${transaction_rollback_result}" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "temporary_log_failed"; then
      transaction_result_persisted=true
      output_error="temporary_log_failed"
    else
      output_error="transaction_record_failed"
    fi
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg error "${output_error}" \
      --arg backup "${backup_dir}" \
      --arg transaction_id "${transaction_id}" \
      --arg transaction_result_file "${transaction_result_file}" \
      --arg transaction_manifest_path "${transaction_manifest_path}" \
      --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
      --arg transaction_status "${transaction_status}" \
      --argjson transaction_result_persisted "${transaction_result_persisted}" \
      '{
        schema: $schema,
        ok: false,
        error: $error,
        failure_reason: "temporary_log_failed",
        backup: $backup,
        transaction: {
          id: $transaction_id,
          result_path: $transaction_result_file,
          status: $transaction_status,
          result_persisted: $transaction_result_persisted,
          manifest_path: $transaction_manifest_path,
          manifest_sha256: $transaction_manifest_sha256,
          manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
          rollback: {attempted: false, result: "not_attempted"}
        }
      }'
    return 1
  fi
  set +e
  (
    set -e
    SB_VERSION="${target_version}"
    update_singbox_binary_preserving_config
  ) > "${operation_log}" 2>&1
  operation_status=$?
  set -e

  after_version=$(detect_installed_singbox_version)
  after_version=${after_version#v}
  after_hash=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
  after_service_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if after_check_json=$(agent_singbox_check_json); then
    after_check_status=0
  else
    after_check_status=$?
  fi

  [[ -n "${before_hash}" && "${before_hash}" == "${after_hash}" ]] && config_preserved=true
  [[ "${after_version}" == "${target_version}" ]] && changed=true
  operation_excerpt=$(sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g' "${operation_log}" | tail -n 80)

  if [[ "${operation_status}" == "0" && "${changed}" == "true" && "${config_preserved}" == "true" && "${after_check_status}" == "0" && "${after_service_state}" == "active" ]]; then
    transaction_status="success"
    transaction_rollback_result="not_attempted"
    if write_agent_upgrade_transaction_result \
      "${backup_dir}" \
      "${transaction_status}" \
      false \
      "${transaction_rollback_result}" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "" \
      "${operation_status}"; then
      transaction_result_persisted=true
    fi
    rm -f "${operation_log}"
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg current "${current_version}" \
      --arg target "${target_version}" \
      --arg installed "${after_version}" \
      --arg backup "${backup_dir}" \
      --arg transaction_id "${transaction_id}" \
      --arg transaction_result_file "${transaction_result_file}" \
      --arg transaction_manifest_path "${transaction_manifest_path}" \
      --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
      --argjson transaction_result_persisted "${transaction_result_persisted}" \
      --arg before_hash "${before_hash}" \
      --arg after_hash "${after_hash}" \
      --arg before_service "${before_service_state}" \
      --arg after_service "${after_service_state}" \
      --arg operation_log "${operation_excerpt}" \
      --argjson check "${after_check_json}" \
      --argjson warnings "$(jq -c '.warnings' <<< "${preflight_json}")" \
      '{
        schema: $schema,
        ok: true,
        action: "sing_box_upgrade",
        changed: true,
        restarted: true,
        rolled_back: false,
        current: $current,
        target: $target,
        installed: $installed,
        backup: $backup,
        transaction: {
          id: $transaction_id,
          result_path: $transaction_result_file,
          status: "success",
          result_persisted: $transaction_result_persisted,
          manifest_path: $transaction_manifest_path,
          manifest_sha256: $transaction_manifest_sha256,
          manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
          rollback: {attempted: false, result: "not_attempted"}
        },
        config_preserved: true,
        config: {sha256_before: $before_hash, sha256_after: $after_hash},
        service: {before: $before_service, after: $after_service},
        check: $check,
        warnings: $warnings,
        operation_log: $operation_log
      } + (if $transaction_result_persisted then {} else {ok: false, error: "transaction_record_failed"} end)'
    if [[ "${transaction_result_persisted}" != "true" ]]; then
      return 1
    fi
    return 0
  fi

  if [[ "${config_preserved}" != "true" ]]; then
    restore_config="y"
    failure_reason="config_changed"
  elif grep -Fq "现有配置未通过 sing-box" "${operation_log}"; then
    failure_reason="config_check_failed"
  elif grep -Fq "sing-box 服务重启失败或未保持 active" "${operation_log}"; then
    failure_reason="service_not_active"
  elif grep -Fq "安装后的 sing-box 版本" "${operation_log}"; then
    failure_reason="target_version_not_installed"
  elif [[ "${after_check_status}" != "0" ]]; then
    failure_reason="config_check_failed"
  elif [[ "${after_service_state}" != "active" ]]; then
    failure_reason="service_not_active"
  elif [[ "${after_version}" != "${target_version}" ]]; then
    failure_reason="target_version_not_installed"
  fi

  if restore_agent_upgrade_backup \
    "${backup_dir}" \
    "${restore_config}" \
    "$([[ "${before_service_state}" == "active" ]] && printf 'y' || printf 'n')"; then
    rollback_ok=true
  fi

  after_version=$(detect_installed_singbox_version)
  after_version=${after_version#v}
  after_hash=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
  after_service_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if after_check_json=$(agent_singbox_check_json); then
    after_check_status=0
  else
    after_check_status=$?
  fi
  [[ -n "${before_hash}" && "${before_hash}" == "${after_hash}" ]] && config_preserved=true || config_preserved=false
  if [[ "${after_version}" != "${current_version}" || "${config_preserved}" != "true" || "${after_check_status}" != "0" ]] || \
    [[ "${after_service_state}" != "${before_service_state}" ]]; then
    rollback_ok=false
    final_changed=true
  fi
  output_error="${failure_reason}"
  if [[ "${rollback_ok}" != "true" ]]; then
    output_error="rollback_failed"
    manual_intervention_required=true
  fi
  if [[ "${rollback_ok}" == "true" ]]; then
    transaction_status="rolled_back"
    transaction_rollback_result="success"
  else
    transaction_status="rollback_failed"
    transaction_rollback_result="failed"
  fi
  if write_agent_upgrade_transaction_result \
    "${backup_dir}" \
    "${transaction_status}" \
    true \
    "${transaction_rollback_result}" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${failure_reason}" \
    "${operation_status}"; then
    transaction_result_persisted=true
  else
    output_error="transaction_record_failed"
  fi
  rm -f "${operation_log}"

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg error "${output_error}" \
    --arg failure_reason "${failure_reason}" \
    --arg current "${current_version}" \
    --arg target "${target_version}" \
    --arg installed "${after_version}" \
    --arg backup "${backup_dir}" \
    --arg transaction_id "${transaction_id}" \
    --arg transaction_result_file "${transaction_result_file}" \
    --arg transaction_manifest_path "${transaction_manifest_path}" \
    --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
    --arg transaction_status "${transaction_status}" \
    --arg transaction_rollback_result "${transaction_rollback_result}" \
    --argjson transaction_result_persisted "${transaction_result_persisted}" \
    --arg before_hash "${before_hash}" \
    --arg after_hash "${after_hash}" \
    --arg before_service "${before_service_state}" \
    --arg after_service "${after_service_state}" \
    --arg operation_log "${operation_excerpt}" \
    --argjson operation_exit_code "${operation_status}" \
    --argjson changed "${final_changed}" \
    --argjson config_preserved "${config_preserved}" \
    --argjson rollback_ok "${rollback_ok}" \
    --argjson manual_intervention_required "${manual_intervention_required}" \
    --argjson check "${after_check_json}" \
    --argjson warnings "$(jq -c '.warnings' <<< "${preflight_json}")" \
    '{
      schema: $schema,
      ok: false,
      error: $error,
      reason: $error,
      failure_reason: $failure_reason,
      action: "sing_box_upgrade",
      changed: $changed,
      restarted: false,
      rollback_attempted: true,
      rolled_back: $rollback_ok,
      rollback_ok: $rollback_ok,
      manual_intervention_required: $manual_intervention_required,
      current: $current,
      target: $target,
      installed: $installed,
      backup: $backup,
      transaction: {
        id: $transaction_id,
        result_path: $transaction_result_file,
        status: $transaction_status,
        result_persisted: $transaction_result_persisted,
        manifest_path: $transaction_manifest_path,
        manifest_sha256: $transaction_manifest_sha256,
        manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
        rollback: {attempted: true, result: $transaction_rollback_result}
      },
      config_preserved: $config_preserved,
      config: {sha256_before: $before_hash, sha256_after: $after_hash},
      service: {before: $before_service, after: $after_service},
      check: $check,
      warnings: $warnings,
      operation_exit_code: $operation_exit_code,
      operation_log: $operation_log
    }'
  return 1
}

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
  local protocol
  protocol=$(normalize_protocol_id "$1") || return 1

  case "${protocol}" in
    hy2) printf 'hysteria2' ;;
    *) printf '%s' "${protocol}" ;;
  esac
}

agent_installed_protocols_json() {
  local protocol

  while IFS= read -r protocol; do
    [[ -n "${protocol}" ]] || continue
    agent_protocol_id "${protocol}" || return 1
    printf '\n'
  done < <(list_indexed_protocols_raw) | jq -Rsc 'split("\n") | map(select(length > 0))'
}

agent_status_json() {
  local installed_protocols_json active_state installed_version warload_mode warload_enabled
  local host_stack bbr_algorithm bbr_enabled inbound_stack_mode outbound_stack_mode
  local reality_instance_count qos_filter_count subman_configured client_export_exists

  installed_protocols_json=$(agent_installed_protocols_json)
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

agent_node_summary_json_for_current_protocol() {
  local protocol api_protocol public_ip shareable="true" client_exportable="false"
  local auth_enabled="false" server_name=""
  local node_name instance_id="" rate_up="" rate_down="" outbound_policy=""
  local tls_mode="" acme_mode="" obfs_enabled="false"

  protocol=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  api_protocol=$(agent_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  public_ip=${1:-$(get_public_ip)}
  node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "")

  case "${protocol}" in
    vless-reality)
      client_exportable="true"
      server_name="${SB_SNI}"
      instance_id="${SB_VLESS_INSTANCE_ID:-main}"
      rate_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      rate_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      outbound_policy="${SB_OUTBOUND_POLICY:-default}"
      ;;
    mixed)
      [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]] && auth_enabled="true"
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
    --arg rate_up "${rate_up}" \
    --arg rate_down "${rate_down}" \
    --arg outbound_policy "${outbound_policy}" \
    --arg tls_mode "${tls_mode}" \
    --arg acme_mode "${acme_mode}" \
    --argjson obfs_enabled "${obfs_enabled}" \
    --argjson shareable "${shareable}" \
    --argjson client_exportable "${client_exportable}" \
    --argjson auth_enabled "${auth_enabled}" \
    '{
      "protocol": $protocol,
      "name": $name,
      "port": ($port | tonumber),
      "shareable": $shareable,
      "client_exportable": $client_exportable
    }
    + (if $server_name != "" then {"server_name": $server_name} else {} end)
    + (if $protocol == "mixed" then {"auth_enabled": $auth_enabled} else {} end)
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
  local protocol api_protocol public_ip link_json outbound_json
  local address_label
  local node_name instance_id="" rate_up="" rate_down="" outbound_policy=""
  local compatibility_warnings_json='[]'

  protocol=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  api_protocol=$(agent_protocol_id "${protocol}" 2>/dev/null || printf '%s' "${protocol}")
  public_ip=${1:-$(get_public_ip)}
  if [[ "${public_ip}" == *:* ]]; then
    address_label="IPv6"
  elif [[ "${public_ip}" == *.* ]]; then
    address_label="IPv4"
  else
    address_label=""
  fi
  node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME}" "${address_label}")

  case "${protocol}" in
    vless-reality)
      instance_id="${SB_VLESS_INSTANCE_ID:-main}"
      rate_up="${SB_VLESS_RATE_LIMIT_UP_MBPS:-}"
      rate_down="${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-}"
      outbound_policy="${SB_OUTBOUND_POLICY:-default}"
      link_json=$(jq -n --arg vless "$(build_vless_link "${public_ip}" "${address_label}")" '{"vless": $vless}')
      ;;
    mixed)
      link_json=$(jq -n \
        --arg http "$(build_mixed_http_link "${public_ip}")" \
        --arg socks5 "$(build_mixed_socks5_link "${public_ip}")" \
        '{"http": $http, "socks5": $socks5}')
      ;;
    hy2)
      link_json=$(jq -n --arg hy2 "$(build_hy2_link "${public_ip}" "${address_label}")" '{"hy2": $hy2}')
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

  jq -n \
    --arg protocol "${api_protocol}" \
    --arg name "${node_name}" \
    --arg port "${SB_PORT}" \
    --arg instance_id "${instance_id}" \
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
    + (if $outbound != null then {"outbound": $outbound} else {} end)
    + (if ($warnings | length) > 0 then {"warnings": $warnings} else {} end)'
}

agent_collect_nodes_json() {
  local mode=$1
  local public_ip original_protocol_state protocol node_json instance_id
  local installed_protocols=()
  local tmpdir status=0 rendered_instances=0

  public_ip=$(get_public_ip)
  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  mapfile -t installed_protocols < <(list_indexed_protocols_raw)
  tmpdir=$(mktemp -d)

  trap '
    if [[ -n "${original_protocol_state:-}" ]] && protocol_state_exists "${original_protocol_state}"; then
      load_protocol_state "${original_protocol_state}" "read-only"
    fi
    rm -rf "${tmpdir:-}"
  ' RETURN

  for protocol in "${installed_protocols[@]}"; do
    if ! load_protocol_state "${protocol}" "read-only"; then
      status=1
      continue
    fi

    if [[ "${protocol}" == "vless-reality" ]]; then
      rendered_instances=0
      while IFS= read -r instance_id; do
        [[ -n "${instance_id}" ]] || continue
        if ! load_vless_reality_instance_state "${instance_id}"; then
          status=1
          continue
        fi
        node_json=""
        case "${mode}" in
          summary) node_json=$(agent_node_summary_json_for_current_protocol "${public_ip}") || status=1 ;;
          links) node_json=$(agent_link_json_for_current_protocol "${public_ip}") || status=1 ;;
          *) status=1; continue ;;
        esac
        if [[ -n "${node_json}" ]]; then
          printf '%s\n' "${node_json}" >> "${tmpdir}/nodes.jsonl"
          rendered_instances=$((rendered_instances + 1))
        fi
      done < <(list_vless_reality_instance_ids)
      if (( rendered_instances == 0 )); then
        SB_VLESS_INSTANCE_ID="main"
        SB_VLESS_RATE_LIMIT_UP_MBPS=""
        SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
        SB_OUTBOUND_POLICY="default"
        case "${mode}" in
          summary) node_json=$(agent_node_summary_json_for_current_protocol "${public_ip}") || status=1 ;;
          links) node_json=$(agent_link_json_for_current_protocol "${public_ip}") || status=1 ;;
          *) status=1; node_json="" ;;
        esac
        if [[ -n "${node_json}" ]]; then
          printf '%s\n' "${node_json}" >> "${tmpdir}/nodes.jsonl"
          rendered_instances=1
        fi
      fi
      (( rendered_instances > 0 )) || status=1
      load_protocol_state "vless-reality" "read-only" || status=1
      continue
    fi

    case "${mode}" in
      summary) node_json=$(agent_node_summary_json_for_current_protocol "${public_ip}") || status=1 ;;
      links) node_json=$(agent_link_json_for_current_protocol "${public_ip}") || status=1 ;;
      *) status=1; continue ;;
    esac

    [[ -n "${node_json:-}" ]] && printf '%s\n' "${node_json}" >> "${tmpdir}/nodes.jsonl"
  done

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg action "$([[ "${mode}" == "summary" ]] && printf 'nodes' || printf 'links')" \
    --argjson sensitive "$([[ "${mode}" == "links" ]] && printf 'true' || printf 'false')" \
    --arg public_address "${public_ip}" \
    --argjson nodes "$(if [[ -s "${tmpdir}/nodes.jsonl" ]]; then jq -s '.' "${tmpdir}/nodes.jsonl"; else jq -n '[]'; fi)" \
    '{
      "schema": $schema,
      "action": $action,
      "sensitive": $sensitive,
      "public_address": $public_address,
      "nodes": $nodes
    }'

  trap - RETURN
  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}" "read-only"
  fi
  rm -rf "${tmpdir}"
  return "${status}"
}

agent_export_client_json() {
  local config_json export_path compatibility_warnings_json

  if ! config_json=$(build_singbox_client_config); then
    log_warn "agent export-client 生成配置失败。" >&2
    return 1
  fi

  if ! validate_client_config_json "${config_json}"; then
    log_warn "agent export-client 配置未通过 sing-box check 校验。" >&2
    return 1
  fi

  export_path=$(client_export_file_path)
  if ! write_client_config_export "${config_json}"; then
    log_warn "agent export-client 写入失败: ${export_path}" >&2
    return 1
  fi

  compatibility_warnings_json=$(collect_hy2_compatibility_warnings_json "export")

  jq -n \
    --arg path "${export_path}" \
    --argjson config "${config_json}" \
    --argjson warnings "${compatibility_warnings_json}" \
    '{
      "path": $path,
      "config": $config
    }
    + (if ($warnings | length) > 0 then {"warnings": $warnings} else {} end)'
}

agent_service_cli() {
  local command=${1:-}
  local json_flag=${2:-}
  local yes_flag=${3:-}
  local before_state after_state check_json restart_status

  if [[ "${command}" != "restart" ]]; then
    agent_json_error "unknown_service_command" "未知 service 子命令: ${command}"
    return 1
  fi

  agent_require_json_flag "${json_flag}" || return 1

  if [[ "${yes_flag}" != "--yes" ]]; then
    agent_json_error "confirmation_required" "service restart 需要 --yes 确认。"
    return 1
  fi

  before_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if ! check_json=$(agent_singbox_check_json); then
    after_state=$(systemctl is-active sing-box 2>/dev/null || true)
    jq -n \
      --arg before "${before_state:-unknown}" \
      --arg after "${after_state:-unknown}" \
      --argjson check "${check_json}" \
      '{
        ok: false,
        action: "service_restart",
        skipped: true,
        reason: "config_check_failed",
        service: {
          before: $before,
          after: $after
        },
        check: $check
      }'
    return 1
  fi

  if systemctl restart sing-box; then
    restart_status=0
  else
    restart_status=$?
  fi
  after_state=$(systemctl is-active sing-box 2>/dev/null || true)

  if [[ "${restart_status}" != "0" || "${after_state}" != "active" ]]; then
    jq -n \
      --arg before "${before_state:-unknown}" \
      --arg after "${after_state:-unknown}" \
      --argjson exit_code "${restart_status}" \
      --argjson check "${check_json}" \
      '{
        ok: false,
        action: "service_restart",
        error: "service_restart_failed",
        skipped: false,
        service: {
          before: $before,
          after: $after,
          restart_exit_code: $exit_code
        },
        check: $check
      }'
    return 1
  fi

  jq -n \
    --arg before "${before_state:-unknown}" \
    --arg after "${after_state:-unknown}" \
    --argjson check "${check_json}" \
    '{
      ok: true,
      action: "service_restart",
      service: {
        before: $before,
        after: $after
      },
      check: $check
    }'
}

agent_push_nodes_to_subman_json() {
  local original_protocol_state protocol instance_id
  local address_entry address_label public_ip
  local instance_attempted instance_synced instance_stacked_synced
  local synced_count skipped_count failed_count ok_json
  local last_error_code last_error_disposition last_http_status last_retry_after
  local compatibility_warnings_json
  local installed_protocols=()

  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  synced_count=0
  skipped_count=0
  failed_count=0
  last_error_code=""
  last_error_disposition=""
  last_http_status=""
  last_retry_after=""
  compatibility_warnings_json=$(collect_hy2_compatibility_warnings_json "share")

  mapfile -t installed_protocols < <(list_installed_protocols)
  if [[ ${#installed_protocols[@]} -eq 0 ]]; then
    jq -n '{ok: false, synced: 0, skipped: 0, failed: 0, error: "no_installed_protocols"}'
    return 1
  fi

  for protocol in "${installed_protocols[@]}"; do
    protocol=$(normalize_protocol_id "${protocol}" 2>/dev/null || true)
    if [[ -z "${protocol}" ]]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! subman_type_for_protocol "${protocol}" >/dev/null; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! protocol_state_exists "${protocol}"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if ! load_protocol_state "${protocol}"; then
      failed_count=$((failed_count + 1))
      continue
    fi

    if [[ "${protocol}" == "vless-reality" ]]; then
      while IFS= read -r instance_id; do
        [[ -z "${instance_id}" ]] && continue
        instance_attempted=0
        instance_synced=0
        instance_stacked_synced=0
        while IFS= read -r address_entry; do
          [[ -z "${address_entry}" ]] && continue
          address_label=${address_entry%%|*}
          public_ip=${address_entry#*|}
          instance_attempted=$((instance_attempted + 1))
          if push_subman_protocol_instance "${protocol}" "${public_ip}" "${instance_id}" "y" "${address_label}"; then
            synced_count=$((synced_count + 1))
            instance_synced=$((instance_synced + 1))
            if [[ -n "$(network_stack_suffix_from_label "${address_label}")" ]]; then
              instance_stacked_synced=$((instance_stacked_synced + 1))
            fi
          else
            failed_count=$((failed_count + 1))
            last_error_code=${SUBMAN_LAST_ERROR_CODE:-unknown_error}
            last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
            last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
            last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
          fi
        done < <(list_subman_addresses_for_current_protocol)
        if subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}" && \
          push_subman_legacy_protocol_key_cleanup "${protocol}" "${instance_id}" "y"; then
          :
        elif subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}"; then
          failed_count=$((failed_count + 1))
          last_error_code=${SUBMAN_LAST_ERROR_CODE:-unknown_error}
          last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
          last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
          last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
        fi
      done < <(list_vless_reality_instance_ids)
      continue
    fi

    while IFS= read -r address_entry; do
      [[ -z "${address_entry}" ]] && continue
      address_label=${address_entry%%|*}
      public_ip=${address_entry#*|}
      if push_subman_protocol_instance "${protocol}" "${public_ip}" "" "y" "${address_label}"; then
        synced_count=$((synced_count + 1))
      else
        failed_count=$((failed_count + 1))
        last_error_code=${SUBMAN_LAST_ERROR_CODE:-unknown_error}
        last_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION:-operator-repair}
        last_http_status=${SUBMAN_LAST_HTTP_STATUS:-}
        last_retry_after=${SUBMAN_LAST_RETRY_AFTER:-}
      fi
    done < <(list_subman_addresses_for_current_protocol)
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi

  if (( synced_count == 0 && failed_count == 0 )); then
    agent_json_error "public_ip_unavailable" "未获取到公网 IP，无法生成 SubMan 节点链接。"
    return 1
  fi

  ok_json=false
  if (( synced_count > 0 && failed_count == 0 )); then
    ok_json=true
  fi

  jq -n \
    --argjson ok "${ok_json}" \
    --argjson synced "${synced_count}" \
    --argjson skipped "${skipped_count}" \
    --argjson failed "${failed_count}" \
    --arg error_code "${last_error_code}" \
    --arg error_disposition "${last_error_disposition}" \
    --arg http_status "${last_http_status}" \
    --arg retry_after "${last_retry_after}" \
    --argjson warnings "${compatibility_warnings_json}" \
    '{
      ok: $ok,
      synced: $synced,
      skipped: $skipped,
      failed: $failed
    }
    + (if ($warnings | length) > 0 then {
        warnings: $warnings
      } else {} end)
    + (if $failed > 0 and $error_code != "" then {
        last_error: {
          code: $error_code,
          disposition: $error_disposition,
          http_status: (if $http_status == "" then null else $http_status end),
          retry_after: (if $retry_after == "" then null else $retry_after end)
        }
      } else {} end)'

  if [[ "${ok_json}" != "true" ]]; then
    return 1
  fi
}

agent_subman_sync_json() {
  local config_file

  config_file=$(subman_config_file_path)
  if [[ ! -f "${config_file}" ]]; then
    agent_json_error "subman_config_missing" "未找到 SubMan 配置，请先在交互菜单中配置 SubMan。"
    return 1
  fi

  load_subman_config
  if [[ -z "${SUBMAN_API_URL}" || -z "${SUBMAN_API_TOKEN}" ]]; then
    agent_json_error "subman_config_missing" "SubMan API URL 或 Token 为空。"
    return 1
  fi

  agent_push_nodes_to_subman_json
}

agent_cli() {
  local command=${1:-help}
  shift || true
  local service_command

  case "${command}" in
    help|-h|--help)
      if [[ $# -ne 0 ]]; then
        agent_cli_error "help" "invalid_arguments" "用法: sbv agent help"
        return $?
      fi
      agent_print_help
      ;;
    capabilities)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "capabilities" "invalid_arguments" "用法: sbv agent capabilities --json"
        return $?
      fi
      agent_cli_run "capabilities" agent_capabilities_json
      ;;
    upgrade-check)
      if [[ $# -ne 2 || "${1:-}" != "--json" ]]; then
        agent_cli_error "upgrade-check" "invalid_arguments" "用法: sbv agent upgrade-check --json x.y.z"
        return $?
      fi
      agent_cli_run "upgrade-check" agent_upgrade_check_json "${2}"
      ;;
    upgrade)
      if [[ $# -lt 2 || $# -gt 3 || "${1:-}" != "--json" ]]; then
        agent_cli_error "upgrade" "invalid_arguments" "用法: sbv agent upgrade --json x.y.z --yes"
        return $?
      fi
      agent_cli_run "upgrade" agent_upgrade_cli "$@"
      ;;
    status)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "status" "invalid_arguments" "用法: sbv agent status --json"
        return $?
      fi
      agent_cli_run "status" agent_status_json
      ;;
    nodes)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "nodes" "invalid_arguments" "用法: sbv agent nodes --json"
        return $?
      fi
      agent_cli_run "nodes" agent_collect_nodes_json "summary"
      ;;
    links)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "links" "invalid_arguments" "用法: sbv agent links --json"
        return $?
      fi
      agent_cli_run "links" agent_collect_nodes_json "links"
      ;;
    export-client)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "export-client" "invalid_arguments" "用法: sbv agent export-client --json"
        return $?
      fi
      agent_cli_run "export-client" agent_export_client_json
      ;;
    warp)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "warp" "invalid_arguments" "用法: sbv agent warp --json"
        return $?
      fi
      agent_cli_run "warp" agent_warp_json
      ;;
    check)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "check" "invalid_arguments" "用法: sbv agent check --json"
        return $?
      fi
      agent_cli_run "check" agent_singbox_check_json
      ;;
    doctor)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "doctor" "invalid_arguments" "用法: sbv agent doctor --json"
        return $?
      fi
      agent_cli_run "doctor" agent_doctor_json
      ;;
    service)
      service_command=${1:-service}
      if [[ $# -lt 1 || $# -gt 3 ]]; then
        agent_cli_error "service ${service_command}" "invalid_arguments" "用法: sbv agent service restart --json --yes"
        return $?
      fi
      agent_cli_run "service ${service_command}" agent_service_cli "$@"
      ;;
    subman-sync)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "subman-sync" "invalid_arguments" "用法: sbv agent subman-sync --json"
        return $?
      fi
      agent_cli_run "subman-sync" agent_subman_sync_json
      ;;
    *)
      agent_cli_error "${command}" "unknown_command" "未知 agent 子命令: ${command}"
      return $?
      ;;
  esac
}

agent_command_name_from_args() {
  local command=${1:-help}

  if [[ "${command}" == "service" && -n "${2:-}" ]]; then
    printf 'service %s' "${2}"
  else
    printf '%s' "${command}"
  fi
}

agent_current_user_is_root() {
  [[ ${EUID} -eq 0 ]]
}

agent_dispatch() {
  local command

  case "${1:-help}" in
    help|-h|--help)
      agent_cli "$@"
      return $?
      ;;
  esac

  command=$(agent_command_name_from_args "$@")
  if ! agent_current_user_is_root; then
    agent_cli_error "${command}" "root_required" "Agent 命令必须以 root 用户执行。"
    return $?
  fi

  agent_cli "$@"
}

push_nodes_to_subman() {
  local original_protocol_state protocol instance_id
  local address_entry address_label public_ip
  local instance_attempted instance_synced instance_stacked_synced
  local synced_count skipped_count failed_count
  local installed_protocols=()

  prompt_subman_config_if_needed
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

    if [[ "${protocol}" == "hy2" ]]; then
      print_hy2_compatibility_warnings "share"
    fi

    if [[ "${protocol}" == "vless-reality" ]]; then
      while IFS= read -r instance_id; do
        [[ -z "${instance_id}" ]] && continue
        instance_attempted=0
        instance_synced=0
        instance_stacked_synced=0
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
        done < <(list_subman_addresses_for_current_protocol)
        if subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}" && \
          push_subman_legacy_protocol_key_cleanup "${protocol}" "${instance_id}" "n"; then
          :
        elif subman_instance_ready_for_legacy_cleanup "${instance_attempted}" "${instance_synced}" "${instance_stacked_synced}"; then
          failed_count=$((failed_count + 1))
        fi
      done < <(list_vless_reality_instance_ids)
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
    done < <(list_subman_addresses_for_current_protocol)
  done

  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    load_protocol_state "${original_protocol_state}"
  fi

  if (( synced_count == 0 && failed_count == 0 )); then
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
    render_menu_item "2" "导出 sing-box 裸核客户端配置"
    render_menu_item "3" "推送节点到 SubMan"
    echo "0. 返回"
    node_info_choice=$(prompt_choice "请选择 [0-3]: " 0 3 "")

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

vless_reality_config_id_exists() {
  local target_id=$1
  local existing_id
  for existing_id in "${VLESS_CONFIG_INSTANCE_IDS[@]}"; do
    [[ "${existing_id}" == "${target_id}" ]] && return 0
  done
  return 1
}

collect_vless_reality_config_instances() {
  local inbound_count inbound_index inbound_type protocol tag user_name candidate private_key existing_tag tag_suffix
  local fallback_number=1
  local candidate_index resolved_ids=()

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

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // empty' "${SINGBOX_CONFIG_FILE}") || return 1
    if ! protocol=$(normalize_protocol_id "${inbound_type}" 2>/dev/null); then
      return 1
    fi
    [[ -n "${protocol}" ]] || return 1
    if ! protocol_array_contains "${protocol}" "${VLESS_CONFIG_PROTOCOLS[@]}"; then
      VLESS_CONFIG_PROTOCOLS+=("${protocol}")
    fi
    [[ "${protocol}" == "vless-reality" ]] || continue

    if ! jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality? | type == "object"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      return 1
    fi

    tag=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tag // ""' "${SINGBOX_CONFIG_FILE}") || return 1
    user_name=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}") || return 1
    candidate=""
    if [[ "${tag}" == "vless-in" ]]; then
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
      while vless_reality_config_id_exists "imported-${fallback_number}"; do
        fallback_number=$((fallback_number + 1))
      done
      candidate="imported-${fallback_number}"
      fallback_number=$((fallback_number + 1))
      VLESS_CONFIG_INSTANCE_IDS+=("${candidate}")
    fi
    VLESS_CONFIG_INSTANCE_CANDIDATES[${candidate_index}]="${candidate}"
    resolved_ids+=("${candidate}")
  done

  VLESS_CONFIG_INSTANCE_IDS=("${resolved_ids[@]}")

  if [[ ${#VLESS_CONFIG_INSTANCE_IDS[@]} -gt 0 ]]; then
    VLESS_CONFIG_DEFAULT_INSTANCE_ID="${VLESS_CONFIG_INSTANCE_IDS[0]}"
    if vless_reality_config_id_exists "main"; then
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
        printf 'INSTANCE_%s_SNI=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" --arg fallback "${SB_REALITY_SNI_FALLBACK}" '.inbounds[$idx].tls.server_name // $fallback' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_SHORT_ID_1=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[0] // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_SHORT_ID_2=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[1] // ""' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_ALPN_MODE=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" '(.inbounds[$idx].tls.alpn // []) | if . == ["h2", "http/1.1"] then "h2_http1" elif . == ["http/1.1"] then "http1" else "off" end' "${SINGBOX_CONFIG_FILE}")"
        printf 'INSTANCE_%s_TCP_FAST_OPEN=%s\n' "$((instance_index + 1))" "$(jq -r --argjson idx "${inbound_index}" 'if .inbounds[$idx].tcp_fast_open == true then "y" else "n" end' "${SINGBOX_CONFIG_FILE}")"
        outbound_policy=$(vless_reality_outbound_policy_from_config "${VLESS_CONFIG_INSTANCE_TAGS[${instance_index}]}") || return 1
        printf 'INSTANCE_%s_OUTBOUND_POLICY=%s\n' "$((instance_index + 1))" "${outbound_policy}"
      done
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

managed_config_acme_is_state_representable() {
  local config_file=$1
  local inbound_count inbound_index inbound_type

  # Invalid JSON is handled by the existing candidate generation transaction;
  # this guard only prevents a valid config from losing ACME fields that the
  # protocol state model cannot reproduce.
  jq -e '.' "${config_file}" &>/dev/null || return 0
  inbound_count=$(jq -r '(.inbounds // []) | length' "${config_file}") || return 1
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // ""' "${config_file}") || return 1
    case "${inbound_type}" in
      hysteria2|anytls) ;;
      *) continue ;;
    esac

    if jq -e --argjson idx "${inbound_index}" '
      .inbounds[$idx].tls.acme? != null and
      .inbounds[$idx].tls.certificate_provider? != null
    ' "${config_file}" &>/dev/null; then
      return 1
    fi

    if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${config_file}" &>/dev/null; then
      inline_acme_extra_json_from_config "${config_file}" "${inbound_index}" >/dev/null || return 1
    elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${config_file}" &>/dev/null; then
      (load_certificate_provider_from_config "${config_file}" "${inbound_index}") || return 1
    fi
  done

  return 0
}

attempt_managed_instance_auto_heal() {
  local indexed_protocols=()
  local protocol
  local snapshot_dir

  [[ -x "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" && -f "${SINGBOX_CONFIG_FILE}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1

  # Detection must not reconcile away an indexed protocol whose state file is
  # missing. That is an incomplete instance requiring takeover, not safe drift
  # that can be regenerated from the remaining state files.
  mapfile -t indexed_protocols < <(list_indexed_protocols_raw)
  [[ ${#indexed_protocols[@]} -gt 0 ]] || return 1

  for protocol in "${indexed_protocols[@]}"; do
    protocol_state_exists "${protocol}" || return 1
  done

  protocol_state_layer_matches_config && return 0

  if ! managed_config_acme_is_state_representable "${SINGBOX_CONFIG_FILE}"; then
    log_warn "当前配置包含协议状态无法无损表达的 ACME 字段，已跳过自动重建并转入接管流程。"
    return 1
  fi

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

  snapshot_dir=$(create_managed_state_snapshot) || return 1

  if ! generate_config; then
    rollback_managed_state_snapshot "${snapshot_dir}" || true
    return 1
  fi

  discard_managed_state_snapshot "${snapshot_dir}" || true
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

restore_protocol_state_layer_from_backup() {
  local backup_dir=$1
  local state_dir_existed=$2
  local restore_candidate restore_previous

  restore_candidate=$(mktemp -d "${SB_PROJECT_DIR}/.protocol-state-restore.XXXXXX") || return 1
  if [[ "${state_dir_existed}" == "y" ]]; then
    if ! cp -a "${backup_dir}/." "${restore_candidate}/"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
  fi

  restore_previous="${SB_PROTOCOL_STATE_DIR}.restore-old.$$"
  if [[ -e "${SB_PROTOCOL_STATE_DIR}" ]]; then
    if ! mv "${SB_PROTOCOL_STATE_DIR}" "${restore_previous}"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
  fi
  if [[ "${state_dir_existed}" == "y" ]]; then
    if ! mv "${restore_candidate}" "${SB_PROTOCOL_STATE_DIR}"; then
      [[ -e "${restore_previous}" ]] && mv "${restore_previous}" "${SB_PROTOCOL_STATE_DIR}" || true
      rm -rf "${restore_candidate}"
      return 1
    fi
  else
    rmdir "${restore_candidate}" || return 1
  fi
  if [[ -e "${restore_previous}" ]]; then
    rm -rf "${restore_previous}" || return 1
  fi
}

abort_protocol_state_rebuild() {
  local backup_dir=$1
  local state_dir_existed=$2

  if ! restore_protocol_state_layer_from_backup "${backup_dir}" "${state_dir_existed}"; then
    return 1
  fi
  rm -rf "${backup_dir}"
  return 0
}

rebuild_protocol_state_from_config() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 0

  local rebuilt_protocols=()
  local inbound_count inbound_index inbound_type protocol
  local vless_instance_index=0 instance_id key_file_private
  local backup_dir state_dir_existed="n"

  backup_dir=$(mktemp -d) || return 1
  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    state_dir_existed="y"
    if ! cp -a "${SB_PROTOCOL_STATE_DIR}/." "${backup_dir}/"; then
      rm -rf "${backup_dir}"
      return 1
    fi
  fi

  if ! collect_vless_reality_config_instances; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  if ! inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}"); then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  if [[ ! "${inbound_count}" =~ ^[0-9]+$ ]]; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi

  clear_protocol_state_cache
  ensure_protocol_state_dir
  if ! rm -rf "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi

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
        instance_id="${VLESS_CONFIG_INSTANCE_CANDIDATES[${vless_instance_index}]}"
        SB_VLESS_INSTANCE_ID="${instance_id}"
        SB_VLESS_INBOUND_TAG="${VLESS_CONFIG_INSTANCE_TAGS[${vless_instance_index}]}"
        SB_VLESS_RATE_LIMIT_UP_MBPS=""
        SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
        SB_VLESS_ALPN_MODE=$(jq -r --argjson idx "${inbound_index}" '
          (.inbounds[$idx].tls.alpn // []) |
          if . == ["h2", "http/1.1"] then "h2_http1"
          elif . == ["http/1.1"] then "http1"
          else "off"
          end
        ' "${SINGBOX_CONFIG_FILE}")
        SB_VLESS_TCP_FAST_OPEN=$(jq -r --argjson idx "${inbound_index}" 'if .inbounds[$idx].tcp_fast_open == true then "y" else "n" end' "${SINGBOX_CONFIG_FILE}")
        if ! SB_OUTBOUND_POLICY=$(vless_reality_outbound_policy_from_config "${SB_VLESS_INBOUND_TAG}"); then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        if (( vless_instance_index == 0 )); then
          SB_PRIVATE_KEY="${VLESS_CONFIG_REALITY_PRIVATE_KEY}"
          if [[ -f "${SB_KEY_FILE}" ]]; then
            key_file_private=$(grep '^PRIVATE_KEY=' "${SB_KEY_FILE}" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r\n ' || true)
            if [[ -n "${SB_PRIVATE_KEY}" && "${key_file_private}" == "${SB_PRIVATE_KEY}" ]]; then
              SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r\n ' || true)
            else
              SB_PUBLIC_KEY=""
            fi
          else
            SB_PUBLIC_KEY=""
          fi
          VLESS_REALITY_DEFAULT_INSTANCE_ID="${VLESS_CONFIG_DEFAULT_INSTANCE_ID}"
          VLESS_REALITY_INSTANCE_IDS="$(IFS=,; printf '%s' "${VLESS_CONFIG_INSTANCE_IDS[*]}")"
          if ! save_vless_reality_protocol_state; then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
        fi
        if ! save_vless_reality_instance_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        vless_instance_index=$((vless_instance_index + 1))
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
        if ! save_mixed_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        ;;
      hy2)
        SB_PROTOCOL="hy2"
        SB_NODE_NAME="$(default_node_name_for_protocol "hy2")"
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
          if ! SB_HY2_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"); then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_HY2_CERT_PATH=""
          SB_HY2_KEY_PATH=""
        elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"; then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_HY2_TLS_MODE="acme"
          SB_HY2_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
          SB_HY2_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
          SB_HY2_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
          SB_HY2_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
          SB_HY2_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
          SB_HY2_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
          SB_HY2_CERT_PATH=""
          SB_HY2_KEY_PATH=""
        else
          SB_HY2_TLS_MODE="manual"
          SB_HY2_ACME_MODE="http"
          SB_HY2_ACME_EMAIL=""
          SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
          SB_HY2_ACME_EXTRA_JSON='{}'
          SB_HY2_DNS_PROVIDER="cloudflare"
          SB_HY2_CF_API_TOKEN=""
          SB_HY2_CERT_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
          SB_HY2_KEY_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
        fi
        SB_HY2_MASQUERADE=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].masquerade // ""' "${SINGBOX_CONFIG_FILE}")
        if ! save_hy2_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
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
          if ! SB_ANYTLS_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"); then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_ANYTLS_ACME_EMAIL=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_ACME_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_CERT_PATH=""
          SB_ANYTLS_KEY_PATH=""
        elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"; then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_ANYTLS_TLS_MODE="acme"
          SB_ANYTLS_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
          SB_ANYTLS_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
          SB_ANYTLS_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
          SB_ANYTLS_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
          SB_ANYTLS_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
          SB_ANYTLS_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
          SB_ANYTLS_CERT_PATH=""
          SB_ANYTLS_KEY_PATH=""
        else
          SB_ANYTLS_TLS_MODE="manual"
          SB_ANYTLS_ACME_MODE="http"
          SB_ANYTLS_ACME_EMAIL=""
          SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
          SB_ANYTLS_ACME_EXTRA_JSON='{}'
          SB_ANYTLS_DNS_PROVIDER="cloudflare"
          SB_ANYTLS_CF_API_TOKEN=""
          SB_ANYTLS_CERT_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_KEY_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
        fi
        if ! save_anytls_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        ;;
      *)
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
        ;;
    esac

    if ! protocol_array_contains "${protocol}" "${rebuilt_protocols[@]}"; then
      rebuilt_protocols+=("${protocol}")
    fi
  done

  if [[ ${#rebuilt_protocols[@]} -eq 0 ]]; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi

  if ! write_protocol_index "$(IFS=,; printf '%s' "${rebuilt_protocols[*]}")"; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  if ! protocol_state_layer_matches_config; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  rm -rf "${backup_dir}"
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
    if ! ensure_sbv_command_installed; then
      log_warn "接管流程未能同步全局命令 sbv；请稍后手动重试。"
    fi
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
  local installed_target_ver
  local reinstall_choice
  local binary_backup=""
  local before_service_state
  local restore_status=0

  installed_ver=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
  get_os_info
  get_arch
  install_dependencies
  if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
    SB_ENABLE_WARP="y"
  else
    SB_ENABLE_WARP="n"
  fi
  load_warp_route_settings

  log_info "检测到现有安装，默认仅更新 sing-box 二进制并保留当前配置。"
  echo -e "当前版本: ${installed_ver}"

  if [[ -z "${SB_VERSION:-}" ]]; then
    prompt_singbox_version
  fi
  get_latest_version

  if [[ "${SB_VERSION}" == "${installed_ver}" ]]; then
    read -rp "目标版本与当前版本一致 (${installed_ver})，是否仍重新安装二进制? [y/N]: " reinstall_choice
    if [[ ! "${reinstall_choice}" =~ ^[Yy]$ ]]; then
      return 0
    fi
  fi

  before_service_state=$(systemctl is-active sing-box 2>/dev/null || true)

  if ! binary_backup=$(mktemp); then
    log_error "创建 sing-box 二进制临时备份失败，已取消更新。"
  fi
  if ! cp -p "${SINGBOX_BIN_PATH}" "${binary_backup}"; then
    rm -f "${binary_backup}"
    log_error "备份现有 sing-box 二进制失败，已取消更新。"
  fi

  install_binary

  installed_target_ver=$(detect_installed_singbox_version)
  installed_target_ver=${installed_target_ver#v}
  if [[ -z "${installed_target_ver}" || "${installed_target_ver}" != "${SB_VERSION#v}" ]]; then
    log_warn "安装后的 sing-box 版本 (${installed_target_ver:-未知}) 与目标版本 ${SB_VERSION#v} 不一致，服务未重启。"
    if replace_singbox_binary_atomically "${binary_backup}" 2>/dev/null; then
      rm -f "${binary_backup}"
      log_warn "已自动恢复更新前的 sing-box 二进制。"
    else
      log_warn "自动恢复旧 sing-box 二进制失败，请从备份 ${binary_backup} 手动恢复。"
    fi
    return 1
  fi

  log_info "正在使用 sing-box ${SB_VERSION} 校验现有配置..."
  if ! validate_config_file; then
    log_warn "现有配置未通过 sing-box ${SB_VERSION} 校验。配置已保留，服务未重启。"
    log_warn "这通常意味着新版本存在 breaking changes，请按 sing-box migration 文档迁移配置后再重载服务。"
    if replace_singbox_binary_atomically "${binary_backup}" 2>/dev/null; then
      log_warn "已自动恢复更新前的 sing-box 二进制。"
    else
      log_warn "自动恢复旧 sing-box 二进制失败，请从备份 ${binary_backup} 手动恢复。"
      return 1
    fi
    rm -f "${binary_backup}"
    return 1
  fi
  log_success "现有配置通过 sing-box ${SB_VERSION} 校验。"
  if ! systemctl restart sing-box || [[ "$(systemctl is-active sing-box 2>/dev/null || true)" != "active" ]]; then
    log_warn "sing-box 服务重启失败或未保持 active。"
    if ! replace_singbox_binary_atomically "${binary_backup}" 2>/dev/null; then
      log_warn "自动恢复旧 sing-box 二进制失败，请从备份 ${binary_backup} 手动恢复。"
      return 1
    fi
    if [[ "${before_service_state}" == "active" ]]; then
      if ! systemctl restart sing-box >/dev/null 2>&1 ||
         [[ "$(systemctl is-active sing-box 2>/dev/null || true)" != "active" ]]; then
        restore_status=1
      fi
    else
      if ! systemctl stop sing-box >/dev/null 2>&1 ||
         [[ "$(systemctl is-active sing-box 2>/dev/null || true)" == "active" ]]; then
        restore_status=1
      fi
    fi
    if [[ "${restore_status}" != "0" ]]; then
      log_warn "恢复更新前 sing-box 服务状态失败，请手动检查服务状态；旧二进制备份保留在 ${binary_backup}。"
      return 1
    fi
    rm -f "${binary_backup}"
    log_warn "已恢复更新前的 sing-box 二进制及服务状态。"
    return 1
  fi
  rm -f "${binary_backup}"
  log_success "sing-box 已更新到 ${SB_VERSION}，当前配置已保留。"
  display_status_summary
  log_info "连接信息未自动展示，如需查看请进入菜单 11。"
}

cli_update_singbox() {
  local version_arg=${1:-}
  local normalized_version
  local existing_instance_state

  if ! normalized_version=$(normalize_singbox_version_input "${version_arg}"); then
    log_warn "无效版本号: ${version_arg}。请输入 latest、${SB_SUPPORT_MAX_VERSION} 或完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。" >&2
    return 1
  fi

  existing_instance_state=$(detect_existing_instance_state)
  case "${existing_instance_state}" in
    healthy)
      ;;
    incomplete)
      log_warn "检测到残缺的 sing-box 实例；请先运行 sbv 交互菜单完成接管或修复后再更新。" >&2
      return 1
      ;;
    *)
      log_warn "未检测到已安装的 sing-box 实例；请先运行 sbv 完成安装。" >&2
      return 1
      ;;
  esac

  SB_VERSION="${normalized_version}"
  update_singbox_binary_preserving_config
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
  install_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

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
    render_left_aligned_page_header "部署管理" "维护 sing-box 核心与已安装协议"
    render_section_title "安装摘要"
    render_summary_item "当前版本" "${installed_ver}"
    render_summary_item "当前协议" "$(protocol_display_name "${SB_PROTOCOL}")"
    render_summary_item "当前端口" "${SB_PORT}"
    render_section_title "操作选项"
    render_menu_item "1" "更新 sing-box 二进制并保留当前配置"
    render_menu_item "2" "安装新增协议"
    render_menu_item "3" "修改已安装协议配置"
    render_menu_item "4" "移除已安装协议"
    render_menu_item "5" "卸载 sing-box"
    echo "0. 返回"
    install_choice=$(prompt_choice "请选择 [0-5] (默认 1): " 0 5 1)

    case "${install_choice}" in
      2) install_new_protocols_menu ;;
      3) update_config_only ;;
      4) remove_protocol_menu ;;
      5) uninstall_singbox ;;
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
  local update_status=0

  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help|help)
        print_cli_help
        exit 0
        ;;
      agent)
        shift
        agent_dispatch "$@"
        exit $?
        ;;
      update)
        shift
        case "${1:-}" in
          sbv|script)
            check_root
            if manual_update_script; then
              exit 0
            else
              update_status=$?
              exit "${update_status}"
            fi
            ;;
          sing-box|singbox)
            shift || true
            check_root
            cli_update_singbox "${1:-}"
            exit $?
            ;;
          *)
            log_warn "未知 update 子命令: ${1:-}" >&2
            print_cli_help >&2
            exit 1
            ;;
        esac
        ;;
      update-sbv|update-script)
        check_root
        if manual_update_script; then
          exit 0
        else
          update_status=$?
          exit "${update_status}"
        fi
        ;;
      update-sing-box|update-singbox)
        shift
        check_root
        cli_update_singbox "${1:-}"
        exit $?
        ;;
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
  if ! ensure_sbv_command_installed; then
    log_warn "全局命令 sbv 未能完成同步；当前管理菜单继续运行，请稍后手动重试。"
  fi
  while true; do
    # Status checks
    check_script_status
    check_sb_version
    check_bbr_status

    render_section_title "部署管理"
    render_menu_item "1" "安装新协议"
    render_menu_item "2" "修改已安装协议配置"
    render_menu_item "3" "移除已安装协议"
    render_menu_item "4" "更新 sing-box 版本" "" "${SB_VER_STATUS}"
    render_menu_item "5" "卸载 sing-box"

    render_section_title "服务控制"
    render_menu_item "6" "启动 sing-box"
    render_menu_item "7" "停止 sing-box"
    render_menu_item "8" "重启 sing-box"
    render_menu_item "9" "运行状态摘要" "" "$(main_menu_service_status_summary)"
    render_menu_item "10" "查看实时日志"

    render_section_title "节点与诊断"
    render_menu_item "11" "查看节点信息"
    render_menu_item "12" "流媒体验证检测"

    render_section_title "网络与系统"
    render_menu_item "13" "配置 Cloudflare Warp" "(解锁/防送中)"
    render_menu_item "14" "系统管理"

    render_section_title "脚本维护"
    render_menu_item "15" "更新管理脚本 (sbv)" "" "${SCRIPT_VER_STATUS}"
    render_menu_item "16" "卸载管理脚本 (sbv)"
    echo "0. 退出"
    render_main_menu_footer
    choice=$(prompt_choice "请选择 [0-16]: " 0 16 "")

    case "$choice" in
      1) install_new_protocols_menu ;;
      2) update_config_only ;;
      3) remove_protocol_menu ;;
      4) update_singbox_version_menu ;;
      5) uninstall_singbox ;;
      6) systemctl start sing-box && log_success "服务已启动。" ;;
      7) systemctl stop sing-box && log_success "服务已停止。" ;;
      8) systemctl restart sing-box && log_success "服务已重启。" ;;
      9) view_status ;;
      10) journalctl -u sing-box -f || true ;;
      11) view_node_info ;;
      12) media_check_menu ;;
      13) warp_management ;;
      14) system_management_menu ;;
      15)
        if manual_update_script; then
          :
        else
          update_status=$?
          log_warn "sbv 自更新失败（退出码 ${update_status}），已返回管理菜单。"
        fi
        ;;
      16) uninstall_script ;;
      0) exit_script ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}


[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"
