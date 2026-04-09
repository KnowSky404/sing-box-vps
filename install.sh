#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 2026040903
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="2026040903"
readonly SB_SUPPORT_MAX_VERSION="1.13.6"
readonly SB_PROJECT_DIR="/root/sing-box-vps"
readonly SBV_LOG_FILE="${SB_PROJECT_DIR}/sbv.log"
readonly SB_KEY_FILE="${SB_PROJECT_DIR}/reality.key"
readonly SB_WARP_KEY_FILE="${SB_PROJECT_DIR}/warp.key"
readonly SB_WARP_ROUTE_SETTINGS_FILE="${SB_PROJECT_DIR}/warp-routing.env"
readonly SB_WARP_DOMAINS_FILE="${SB_PROJECT_DIR}/warp-domains.txt"
readonly SB_WARP_REMOTE_RULESETS_FILE="${SB_PROJECT_DIR}/warp-remote-rule-sets.txt"
readonly SB_WARP_LOCAL_RULESET_DIR="${SB_PROJECT_DIR}/rule-set/warp"
readonly SB_MEDIA_CHECK_DIR="${SB_PROJECT_DIR}/media-check"
readonly SB_MEDIA_CHECK_SCRIPT="${SB_MEDIA_CHECK_DIR}/region_restriction_check.sh"
readonly SB_PROTOCOL_STATE_DIR="${SB_PROJECT_DIR}/protocols"
readonly SB_PROTOCOL_INDEX_FILE="${SB_PROTOCOL_STATE_DIR}/index.env"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
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

# --- Global Variables ---
SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
SB_PROTOCOL="vless+reality"
SB_NODE_NAME="vless_reality_$(hostname)"
SB_PORT="443"
SB_UUID=""
SB_PUBLIC_KEY=""
SB_PRIVATE_KEY=""
SB_SHORT_ID_1=""
SB_SHORT_ID_2=""
SB_SNI="apple.com"
SB_MIXED_AUTH_ENABLED="y"
SB_MIXED_USERNAME=""
SB_MIXED_PASSWORD=""
SB_HY2_DOMAIN=""
SB_HY2_PASSWORD=""
SB_HY2_USER_NAME=""
SB_HY2_UP_MBPS="100"
SB_HY2_DOWN_MBPS="100"
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
SB_ADVANCED_ROUTE="y"
SB_ENABLE_WARP="n"
SB_WARP_ROUTE_MODE="all"
SB_WARP_CUSTOM_DOMAINS_JSON='[]'
SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
SB_WARP_LOCAL_RULE_SETS_JSON='[]'
SB_WARP_REMOTE_RULE_SETS_JSON='[]'
SB_WARP_RULE_SET_TAGS_JSON='[]'

# --- Common Utilities ---
# Register Cloudflare Warp account
register_warp() {
  if [[ -f "${SB_WARP_KEY_FILE}" ]]; then
    log_info "发现现有 Warp 账户信息，正在加载..."
    return 0
  fi

  log_info "正在注册 Cloudflare Warp 免费账户..."
  local keypair=$("${SINGBOX_BIN_PATH}" generate wg-keypair)
  local priv_key=$(echo "${keypair}" | grep -i "PrivateKey" | awk '{print $2}' | tr -d '\r\n ')
  local pub_key=$(echo "${keypair}" | grep -i "PublicKey" | awk '{print $2}' | tr -d '\r\n ')
  
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

  local warp_token=$(echo "${response}" | jq -r '.token')
  local warp_v4=$(echo "${response}" | jq -r '.config.interface.addresses.v4')
  local warp_v6=$(echo "${response}" | jq -r '.config.interface.addresses.v6')

  cat > "${SB_WARP_KEY_FILE}" <<EOF
WARP_ID=${warp_id}
WARP_TOKEN=${warp_token}
WARP_PRIV_KEY=${priv_key}
WARP_PUB_KEY=${pub_key}
WARP_V4=${warp_v4}
WARP_V6=${warp_v6}
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

trim_whitespace() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

validate_warp_route_mode() {
  case "$1" in
    all|selective) return 0 ;;
    *) return 1 ;;
  esac
}

validate_protocol() {
  case "$1" in
    vless+reality|mixed|hy2) return 0 ;;
    *) return 1 ;;
  esac
}

protocol_display_name() {
  case "$1" in
    vless+reality) printf 'VLESS + REALITY' ;;
    mixed) printf 'Mixed (HTTP/HTTPS/SOCKS)' ;;
    hy2) printf 'Hysteria2' ;;
    *) printf '%s' "$1" ;;
  esac
}

protocol_inbound_tag() {
  case "$1" in
    mixed) printf 'mixed-in' ;;
    hy2) printf 'hy2-in' ;;
    *) printf 'vless-in' ;;
  esac
}

normalize_protocol_id() {
  case "$1" in
    vless|vless+reality|vless-reality) printf 'vless-reality' ;;
    mixed) printf 'mixed' ;;
    hy2|hysteria2) printf 'hy2' ;;
    *) return 1 ;;
  esac
}

state_protocol_to_runtime() {
  case "$1" in
    vless-reality) printf 'vless+reality' ;;
    mixed) printf 'mixed' ;;
    hy2) printf 'hy2' ;;
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

write_protocol_index() {
  ensure_protocol_state_dir
  {
    write_env_assignment "INSTALLED_PROTOCOLS" "$1"
    write_env_assignment "PROTOCOL_STATE_VERSION" "1"
  } > "${SB_PROTOCOL_INDEX_FILE}"
}

extract_protocols_from_index() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 0
  local installed
  installed=$(grep '^INSTALLED_PROTOCOLS=' "${SB_PROTOCOL_INDEX_FILE}" 2>/dev/null | cut -d'=' -f2- || true)
  installed=${installed//\"/}
  installed=${installed//\'/}
  printf '%s' "${installed}"
}

list_installed_protocols() {
  local installed protocol
  installed=$(extract_protocols_from_index)
  [[ -z "${installed}" ]] && return 0

  IFS=',' read -r -a protocols <<< "${installed}"
  for protocol in "${protocols[@]}"; do
    protocol=$(trim_whitespace "${protocol}")
    [[ -n "${protocol}" ]] && printf '%s\n' "${protocol}"
  done
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

save_protocol_state() {
  local protocol
  protocol=$(normalize_protocol_id "$1")
  ensure_protocol_state_dir

  case "${protocol}" in
    vless-reality) save_vless_reality_state ;;
    mixed) save_mixed_state ;;
    hy2) save_hy2_state ;;
    *) log_error "不支持的协议状态保存类型: ${protocol}" ;;
  esac
}

migrate_legacy_single_protocol_state_if_needed() {
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" || ! -f "${SINGBOX_CONFIG_FILE}" ]] && return 0

  local legacy_type legacy_protocol
  legacy_type=$(jq -r '.inbounds[0].type // empty' "${SINGBOX_CONFIG_FILE}")

  case "${legacy_type}" in
    vless) legacy_protocol="vless-reality" ;;
    mixed) legacy_protocol="mixed" ;;
    *) return 0 ;;
  esac

  ensure_protocol_state_dir
  write_protocol_index "${legacy_protocol}"

  if [[ "${legacy_protocol}" == "vless-reality" ]]; then
    SB_PROTOCOL="vless+reality"
    SB_NODE_NAME="vless_reality_$(hostname)"
    SB_PORT=$(jq -r '.inbounds[0].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
    SB_UUID=$(jq -r '.inbounds[0].users[0].uuid // ""' "${SINGBOX_CONFIG_FILE}")
    SB_SNI=$(jq -r '.inbounds[0].tls.server_name // "apple.com"' "${SINGBOX_CONFIG_FILE}")
    SB_PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key // ""' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_1=$(jq -r '.inbounds[0].tls.reality.short_id[0] // ""' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_2=$(jq -r '.inbounds[0].tls.reality.short_id[1] // ""' "${SINGBOX_CONFIG_FILE}")
    if [[ -f "${SB_KEY_FILE}" ]]; then
      SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" 2>/dev/null | cut -d'=' -f2- | tr -d '\r\n ' || true)
    else
      SB_PUBLIC_KEY=""
    fi
    save_vless_reality_state
  fi
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
      return 1
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
  [[ -n "${in_domain}" ]] && SB_HY2_DOMAIN="${in_domain}"

  read -rp "新认证密码 (当前: 留空隐藏, 留空保持): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"

  read -rp "新用户名标识 (当前: ${SB_HY2_USER_NAME}, 留空保持): " in_user_name
  [[ -n "${in_user_name}" ]] && SB_HY2_USER_NAME="${in_user_name}"

  read -rp "上行带宽 Mbps (当前: ${SB_HY2_UP_MBPS}, 留空保持): " in_up
  [[ -n "${in_up}" ]] && SB_HY2_UP_MBPS="${in_up}"

  read -rp "下行带宽 Mbps (当前: ${SB_HY2_DOWN_MBPS}, 留空保持): " in_down
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

    read -rp "ACME 邮箱 (当前: ${SB_HY2_ACME_EMAIL}, 留空保持): " in_acme_email
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

prompt_protocol_update_fields() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) prompt_vless_reality_update ;;
    mixed) prompt_mixed_update ;;
    hy2) prompt_hy2_update ;;
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
    *) return 1 ;;
  esac
}

prompt_protocol_install_selection() {
  local installed_protocols=() selected_protocols=()
  local choice raw_choice protocol index

  mapfile -t installed_protocols < <(list_installed_protocols)

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
  for index in 1 2 3; do
    protocol=$(protocol_option_to_id "${index}") || continue
    if protocol_array_contains "${protocol}" "${installed_protocols[@]}"; then
      continue
    fi
    echo "${index}. $(protocol_display_name "$(state_protocol_to_runtime "${protocol}")")"
  done

  read -rp "请选择一个或多个协议 [1-3]，逗号分隔: " choice
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
}

prompt_vless_reality_install() {
  local in_p in_sni

  set_protocol_defaults "vless+reality"
  read -rp "端口 (默认 ${SB_PORT}): " in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  read -rp "REALITY 域名 (默认 ${SB_SNI}): " in_sni
  SB_SNI=${in_sni:-$SB_SNI}
}

prompt_mixed_install() {
  local in_p in_auth in_user in_pass

  set_protocol_defaults "mixed"
  read -rp "端口 (默认 ${SB_PORT}): " in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  read -rp "是否启用用户名密码认证 [y/n] (默认 y，强烈建议开启): " in_auth
  SB_MIXED_AUTH_ENABLED=${in_auth:-"y"}
  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    read -rp "用户名 (留空自动生成): " in_user
    SB_MIXED_USERNAME="${in_user}"
    read -rp "密码 (留空自动生成): " in_pass
    SB_MIXED_PASSWORD="${in_pass}"
    ensure_mixed_auth_credentials
  else
    log_warn "你选择了关闭认证。开放的 HTTP/SOCKS 代理存在明显安全风险，请确认防火墙与访问源限制。"
  fi
}

prompt_hy2_install() {
  local in_domain in_p in_password in_user_name in_up in_down in_obfs in_obfs_password in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path in_masquerade

  set_protocol_defaults "hy2"

  while [[ -z "${SB_HY2_DOMAIN}" ]]; do
    read -rp "Hysteria2 域名: " in_domain
    SB_HY2_DOMAIN=$(trim_whitespace "${in_domain}")
    [[ -z "${SB_HY2_DOMAIN}" ]] && log_warn "域名不能为空。"
  done

  read -rp "端口 (默认 ${SB_PORT}): " in_p
  SB_PORT=${in_p:-$SB_PORT}
  check_port_conflict "${SB_PORT}"

  read -rp "认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"
  read -rp "用户名标识 (默认 ${SB_HY2_USER_NAME}): " in_user_name
  SB_HY2_USER_NAME=${in_user_name:-$SB_HY2_USER_NAME}

  read -rp "上行带宽 Mbps (默认 ${SB_HY2_UP_MBPS}): " in_up
  SB_HY2_UP_MBPS=${in_up:-$SB_HY2_UP_MBPS}
  read -rp "下行带宽 Mbps (默认 ${SB_HY2_DOWN_MBPS}): " in_down
  SB_HY2_DOWN_MBPS=${in_down:-$SB_HY2_DOWN_MBPS}

  read -rp "是否启用 Salamander 混淆 [y/n] (默认 n): " in_obfs
  SB_HY2_OBFS_ENABLED=${in_obfs:-"n"}
  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    SB_HY2_OBFS_TYPE="salamander"
    read -rp "混淆密码 (留空自动生成): " in_obfs_password
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  read -rp "请选择 [1-2] (默认 1): " in_tls_mode
  case "${in_tls_mode}" in
    2) SB_HY2_TLS_MODE="manual" ;;
    *) SB_HY2_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    read -rp "请选择 [1-2] (默认 1): " in_acme_mode
    case "${in_acme_mode}" in
      2) SB_HY2_ACME_MODE="dns" ;;
      *) SB_HY2_ACME_MODE="http" ;;
    esac

    read -rp "ACME 邮箱: " in_acme_email
    SB_HY2_ACME_EMAIL="${in_acme_email}"
    read -rp "ACME 域名 (默认 ${SB_HY2_DOMAIN}): " in_acme_domain
    SB_HY2_ACME_DOMAIN=${in_acme_domain:-$SB_HY2_DOMAIN}

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "Cloudflare API Token: " in_cf_api_token
      SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_HY2_CERT_PATH}" ]]; do
      read -rp "证书路径: " in_cert_path
      SB_HY2_CERT_PATH=$(trim_whitespace "${in_cert_path}")
      [[ -z "${SB_HY2_CERT_PATH}" ]] && log_warn "证书路径不能为空。"
    done

    while [[ -z "${SB_HY2_KEY_PATH}" ]]; do
      read -rp "私钥路径: " in_key_path
      SB_HY2_KEY_PATH=$(trim_whitespace "${in_key_path}")
      [[ -z "${SB_HY2_KEY_PATH}" ]] && log_warn "私钥路径不能为空。"
    done
  fi

  read -rp "伪装地址 (留空跳过): " in_masquerade
  [[ -n "${in_masquerade}" ]] && SB_HY2_MASQUERADE="${in_masquerade}"

  ensure_hy2_materials
}

prompt_protocol_install_fields() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) prompt_vless_reality_install ;;
    mixed) prompt_mixed_install ;;
    hy2) prompt_hy2_install ;;
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
    SB_WARP_ROUTE_MODE="all"
    echo "Warp 路由模式:"
    echo "1. 全量流量走 Warp"
    echo "2. 仅 AI/流媒体及自定义规则走 Warp"
    read -rp "请选择 [1-2] (默认 1): " in_warp_mode
    case "${in_warp_mode}" in
      2) SB_WARP_ROUTE_MODE="selective" ;;
      *) SB_WARP_ROUTE_MODE="all" ;;
    esac
  fi
}

install_protocols_interactive() {
  local install_mode=$1
  local installed_protocols=() selected_protocols=()
  local protocol first_selected_protocol

  if [[ "${install_mode}" == "fresh" ]]; then
    get_os_info
    get_arch
    prompt_singbox_version
    prompt_protocol_install_selection
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
    prompt_protocol_install_selection
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
  show_post_config_connection_info
}

set_protocol_defaults() {
  case "$1" in
    mixed)
      SB_PROTOCOL="mixed"
      SB_NODE_NAME="mixed_$(hostname)"
      SB_PORT="1080"
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
      SB_NODE_NAME="hy2_$(hostname)"
      SB_PORT="8443"
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
      SB_HY2_UP_MBPS="100"
      SB_HY2_DOWN_MBPS="100"
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
      ;;
    *)
      SB_PROTOCOL="vless+reality"
      SB_NODE_NAME="vless_reality_$(hostname)"
      SB_PORT="443"
      SB_SNI="apple.com"
      SB_MIXED_AUTH_ENABLED="y"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
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

ensure_mixed_auth_credentials() {
  if [[ "${SB_MIXED_AUTH_ENABLED}" != "y" ]]; then
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
    return 0
  fi

  [[ -z "${SB_MIXED_USERNAME}" ]] && SB_MIXED_USERNAME=$(generate_random_token "proxy_" 3)
  [[ -z "${SB_MIXED_PASSWORD}" ]] && SB_MIXED_PASSWORD=$(generate_random_token "" 8)
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
  local w_key w_v4 w_v6

  if [[ ! -f "${SB_WARP_KEY_FILE}" ]]; then
    log_error "未找到 Warp 账户信息，请先在菜单中启用或注册 Warp。"
  fi

  w_key=$(grep "WARP_PRIV_KEY" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  w_v4=$(grep "WARP_V4" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  w_v6=$(grep "WARP_V6" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')

  if [[ -z "${w_key}" || -z "${w_v4}" || -z "${w_v6}" ]]; then
    log_error "Warp 账户信息不完整，请尝试重新注册 Warp。"
  fi

  jq -n \
    --arg proxy_port "${proxy_port}" \
    --arg w_key "${w_key}" \
    --arg w_v4 "${w_v4}/32" \
    --arg w_v6 "${w_v6}/128" \
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
    echo -e "\n${BLUE}--- 流媒体验证检测 ---${NC}"
    show_media_check_backend_info
    echo "1. 本机直出检测"
    echo "2. Warp 出口检测"
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
  SB_WARP_ROUTE_MODE="all"

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
  echo -e "\n${BLUE}--- Warp 路由模式 ---${NC}"
  echo "1. 全量流量走 Warp"
  echo "2. 仅 AI/流媒体及自定义规则走 Warp"
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
  remote_content=$(curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh 2>/dev/null) || true
  
  if [[ -z "${remote_content}" ]]; then
    SCRIPT_VER_STATUS="${RED}(无法检测更新)${NC}"
    return
  fi

  local remote_version
  remote_version=$(echo "${remote_content}" | grep -m1 "readonly SCRIPT_VERSION" | cut -d'"' -f2)
  
  if [[ "${remote_version}" -gt "${SCRIPT_VERSION}" ]]; then
    SCRIPT_VER_STATUS="${YELLOW}(有新版本: ${remote_version})${NC}"
  else
    SCRIPT_VER_STATUS="${GREEN}(已是最新)${NC}"
  fi
}

# Manual update script
manual_update_script() {
  log_info "正在从 GitHub 获取最新脚本..."
  if curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh -o "/usr/local/bin/sbv"; then
    chmod +x "/usr/local/bin/sbv"
    log_success "脚本已更新到最新版本，请重新运行 sbv。"
    exit 0
  else
    log_error "脚本更新失败，请检查网络。"
  fi
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
  if ss -tunlp | grep -q ":${port} "; then
    local process=$(ss -tunlp | grep ":${port} " | awk '{print $7}' | cut -d'"' -f2 | head -n1)
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
        while true; do
          SB_PORT=$((RANDOM % 55535 + 10000))
          ss -tunlp | grep -q ":${SB_PORT} " || break
        done
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
  
  # Install/Update 'sbv' command
  if [[ "$0" != "/usr/local/bin/sbv" && "$0" != "sbv" ]]; then
    log_info "正在将脚本安装为全局命令: sbv..."
    if curl -fsSL https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh -o "/usr/local/bin/sbv"; then
      chmod +x "/usr/local/bin/sbv"
      log_success "全局命令 sbv 安装/更新成功。"
    else
      log_warn "无法从远程下载脚本，尝试使用本地备份..."
      [[ -f "$0" ]] && cp -f "$0" "/usr/local/bin/sbv" && chmod +x "/usr/local/bin/sbv"
    fi
  fi
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
      SB_NODE_NAME="${NODE_NAME:-vless_reality_$(hostname)}"
      SB_PORT="${PORT:-443}"
      SB_UUID="${UUID:-}"
      SB_SNI="${SNI:-apple.com}"
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
      SB_HY2_UP_MBPS="100"
      SB_HY2_DOWN_MBPS="100"
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
      ;;
    mixed)
      SB_PROTOCOL="mixed"
      SB_NODE_NAME="${NODE_NAME:-mixed_$(hostname)}"
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
      SB_HY2_UP_MBPS="100"
      SB_HY2_DOWN_MBPS="100"
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
      ;;
    hy2)
      SB_PROTOCOL="hy2"
      SB_NODE_NAME="${NODE_NAME:-hy2_$(hostname)}"
      SB_PORT="${PORT:-8443}"
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
      SB_HY2_UP_MBPS="${UP_MBPS:-100}"
      SB_HY2_DOWN_MBPS="${DOWN_MBPS:-100}"
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
      ;;
  esac
}

ensure_vless_reality_materials() {
  if [[ -z "${SB_UUID}" ]]; then
    SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  fi

  if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
    if [[ -f "${SB_KEY_FILE}" ]]; then
      log_info "使用现有密钥对..."
      [[ -z "${SB_PRIVATE_KEY}" ]] && SB_PRIVATE_KEY=$(grep '^PRIVATE_KEY=' "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
      [[ -z "${SB_PUBLIC_KEY}" ]] && SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    fi
  fi

  if [[ -z "${SB_PRIVATE_KEY}" || -z "${SB_PUBLIC_KEY}" ]]; then
    log_info "正在生成新的 REALITY 密钥对..."
    local keypair
    keypair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
    SB_PRIVATE_KEY=$(echo "${keypair}" | grep "PrivateKey" | awk '{print $2}')
    SB_PUBLIC_KEY=$(echo "${keypair}" | grep "PublicKey" | awk '{print $2}')
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

  return 0
}

ensure_hy2_materials() {
  if [[ -z "${SB_HY2_USER_NAME}" ]]; then
    SB_HY2_USER_NAME="hy2-user"
  fi

  if [[ -z "${SB_HY2_PASSWORD}" ]]; then
    SB_HY2_PASSWORD=$(generate_random_token "" 8)
  fi

  if [[ -z "${SB_HY2_ACME_DOMAIN}" ]]; then
    SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
  fi

  if [[ "${SB_HY2_OBFS_ENABLED}" != "y" ]]; then
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
  elif [[ -z "${SB_HY2_OBFS_TYPE}" ]]; then
    SB_HY2_OBFS_TYPE="salamander"
  fi

  return 0
}

build_vless_inbound_json() {
  ensure_vless_reality_materials

  jq -n \
    --arg tag "vless-in" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg sni "${SB_SNI}" \
    --arg priv_key "${SB_PRIVATE_KEY}" \
    --arg sid1 "${SB_SHORT_ID_1}" \
    --arg sid2 "${SB_SHORT_ID_2}" \
    '{
      "type": "vless",
      "tag": $tag,
      "listen": "::",
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
    --arg port "${SB_PORT}" \
    --arg mixed_auth_enabled "${SB_MIXED_AUTH_ENABLED}" \
    --arg mixed_username "${SB_MIXED_USERNAME}" \
    --arg mixed_password "${SB_MIXED_PASSWORD}" \
    '{
      "type": "mixed",
      "tag": $tag,
      "listen": "::",
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

build_hy2_certificate_provider_json() {
  ensure_hy2_materials
  [[ "${SB_HY2_TLS_MODE}" == "manual" ]] && return 0

  jq -n \
    --arg tag "$(hy2_certificate_provider_tag)" \
    --arg domain "${SB_HY2_ACME_DOMAIN}" \
    --arg email "${SB_HY2_ACME_EMAIL}" \
    --arg acme_mode "${SB_HY2_ACME_MODE}" \
    --arg dns_provider "${SB_HY2_DNS_PROVIDER}" \
    --arg cf_api_token "${SB_HY2_CF_API_TOKEN}" \
    '{
      "type": "acme",
      "tag": $tag,
      "domain": [ $domain ],
      "email": $email
    } + (
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

build_hy2_inbound_json() {
  ensure_hy2_materials

  jq -n \
    --arg tag "hy2-in" \
    --arg port "${SB_PORT}" \
    --arg user_name "${SB_HY2_USER_NAME}" \
    --arg password "${SB_HY2_PASSWORD}" \
    --arg up_mbps "${SB_HY2_UP_MBPS}" \
    --arg down_mbps "${SB_HY2_DOWN_MBPS}" \
    --arg domain "${SB_HY2_DOMAIN}" \
    --arg tls_mode "${SB_HY2_TLS_MODE}" \
    --arg cert_path "${SB_HY2_CERT_PATH}" \
    --arg key_path "${SB_HY2_KEY_PATH}" \
    --arg obfs_enabled "${SB_HY2_OBFS_ENABLED}" \
    --arg obfs_type "${SB_HY2_OBFS_TYPE}" \
    --arg obfs_password "${SB_HY2_OBFS_PASSWORD}" \
    --arg masquerade "${SB_HY2_MASQUERADE}" \
    --arg cert_provider_tag "$(hy2_certificate_provider_tag)" \
    '{
      "type": "hysteria2",
      "tag": $tag,
      "listen": "::",
      "listen_port": ($port | tonumber),
      "users": [
        {
          "name": $user_name,
          "password": $password
        }
      ],
      "up_mbps": ($up_mbps | tonumber),
      "down_mbps": ($down_mbps | tonumber),
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
              "certificate_provider": $cert_provider_tag
            }
          end
        )
      )
    } + (
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

build_certificate_provider_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    hy2) build_hy2_certificate_provider_json ;;
  esac
}

build_inbound_for_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) build_vless_inbound_json ;;
    mixed) build_mixed_inbound_json ;;
    hy2) build_hy2_inbound_json ;;
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
  local w_key="" w_v4="" w_v6=""
  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    register_warp
    w_key=$(grep "WARP_PRIV_KEY" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v4=$(grep "WARP_V4" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v6=$(grep "WARP_V6" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  fi

  refresh_warp_route_assets
  local inbound_file provider_file protocol_rule_file protocol
  local inbounds_json certificate_providers_json protocol_rules_json

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
              "allowed_ips": [ "0.0.0.0/0", "::/0" ]
            }
          ],
          "mtu": 1280
        }
      ] else [] end),
      "inbounds": $inbounds,
      "outbounds": [
        { "type": "direct", "tag": "direct" },
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
uninstall_singbox() {
  log_info "正在卸载 sing-box..."
  systemctl stop sing-box &>/dev/null || true
  systemctl disable sing-box &>/dev/null || true
  rm -f "${SINGBOX_BIN_PATH}"
  rm -rf "${SINGBOX_CONFIG_DIR}"
  rm -f "${SINGBOX_SERVICE_FILE}"
  systemctl daemon-reload
  log_success "sing-box 软件卸载完成。"
}

# Uninstall script itself
uninstall_script() {
  read -rp "是否同时删除项目配置文件目录 (/root/sing-box-vps)? [y/N]: " del_cfg
  if [[ "${del_cfg}" =~ ^[Yy]$ ]]; then
    rm -rf "${SB_PROJECT_DIR}"
    log_info "配置文件目录已删除。"
  fi
  
  log_info "正在删除全局命令 sbv..."
  rm -f "/usr/local/bin/sbv"
  log_success "管理脚本已卸载。"
  exit 0
}

# --- UI & Main ---
show_banner() {
  clear
  echo -e "${BLUE}#############################################################${NC}"
  echo -e "${BLUE}#                                                           #${NC}"
  echo -e "${BLUE}#           ${GREEN}sing-box-vps 一键安装管理脚本${BLUE}                   #${NC}"
  echo -e "${BLUE}#  ${NC}可能是最简单的 VPS 一键安装脚本，专为稳定与安全设计 ${BLUE}   #${NC}"
  echo -e "${BLUE}#                                                           #${NC}"
  echo -e "${BLUE}#  ${NC}作者: ${YELLOW}KnowSky404${NC}                                         ${BLUE}#${NC}"
  echo -e "${BLUE}#  ${NC}项目: ${NC}https://github.com/KnowSky404/sing-box-vps          ${BLUE}#${NC}"
  echo -e "${BLUE}#  ${NC}版本: ${GREEN}${SCRIPT_VERSION}${NC}                                       ${BLUE}#${NC}"
  echo -e "${BLUE}#                                                           #${NC}"
  echo -e "${BLUE}#############################################################${NC}"
  echo ""
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

  printf 'all'
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

  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    first_protocol=$(list_installed_protocols | head -n1)
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
    *) log_error "当前配置中的协议类型不受脚本支持: ${SB_PROTOCOL}" ;;
  esac

  SB_PORT=$(jq -r '.inbounds[0].listen_port' "${SINGBOX_CONFIG_FILE}")

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    SB_NODE_NAME="vless_reality_$(hostname)"
    SB_UUID=$(jq -r '.inbounds[0].users[0].uuid' "${SINGBOX_CONFIG_FILE}")
    SB_SNI=$(jq -r '.inbounds[0].tls.server_name' "${SINGBOX_CONFIG_FILE}")
    SB_PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_1=$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${SINGBOX_CONFIG_FILE}")
    SB_SHORT_ID_2=$(jq -r '.inbounds[0].tls.reality.short_id[1]' "${SINGBOX_CONFIG_FILE}")
    SB_MIXED_AUTH_ENABLED="y"
    SB_MIXED_USERNAME=""
    SB_MIXED_PASSWORD=""
  elif [[ "${SB_PROTOCOL}" == "mixed" ]]; then
    SB_NODE_NAME="mixed_$(hostname)"
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
  else
    SB_NODE_NAME="hy2_$(hostname)"
    SB_HY2_DOMAIN=$(jq -r '.inbounds[0].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_PASSWORD=$(jq -r '.inbounds[0].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_USER_NAME=$(jq -r '.inbounds[0].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_UP_MBPS=$(jq -r '.inbounds[0].up_mbps // "100"' "${SINGBOX_CONFIG_FILE}")
    SB_HY2_DOWN_MBPS=$(jq -r '.inbounds[0].down_mbps // "100"' "${SINGBOX_CONFIG_FILE}")
    if jq -e '.inbounds[0].obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_OBFS_ENABLED="y"
      SB_HY2_OBFS_TYPE="salamander"
      SB_HY2_OBFS_PASSWORD=$(jq -r '.inbounds[0].obfs.password // ""' "${SINGBOX_CONFIG_FILE}")
    else
      SB_HY2_OBFS_ENABLED="n"
      SB_HY2_OBFS_TYPE=""
      SB_HY2_OBFS_PASSWORD=""
    fi
    if jq -e '.inbounds[0].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
      SB_HY2_TLS_MODE="acme"
    else
      SB_HY2_TLS_MODE="manual"
      SB_HY2_CERT_PATH=$(jq -r '.inbounds[0].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
      SB_HY2_KEY_PATH=$(jq -r '.inbounds[0].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
    fi
    SB_HY2_MASQUERADE=$(jq -r '.inbounds[0].masquerade // ""' "${SINGBOX_CONFIG_FILE}")
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

    echo -e "\n${BLUE}--- Cloudflare Warp 管理 ---${NC}"
    echo -e "当前状态: ${status}"
    echo -e "当前路由模式: ${SB_WARP_ROUTE_MODE}"
    echo "1. 开启 Warp"
    echo "2. 关闭 Warp"
    echo "3. 重新注册 Warp 账户 (获取新密钥和 IP)"
    echo "4. 切换 Warp 路由模式"
    echo "5. 添加自定义 Warp 域名"
    echo "6. 添加远程 Warp 规则集"
    echo "7. 查看 Warp 分流文件路径"
    echo "8. 查看当前生效的 Warp 分流来源"
    echo "9. 导入推荐 Warp 规则源"
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
    log_info "连接信息未自动展示，如需查看请进入菜单 8。"
  done
}

# Helper to extract config values and display info
view_status_and_info() {
  local selected_protocol

  log_info "正在从配置文件中读取信息..."
  load_current_config_state
  display_status_summary

  SELECTED_PROTOCOL=""
  if ! prompt_installed_protocol_selection; then
    return 0
  fi
  selected_protocol="${SELECTED_PROTOCOL}"
  load_protocol_state "${selected_protocol}"
  show_connection_info_menu
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
  show_post_config_connection_info
}

get_public_ip() {
  curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me
}

build_vless_link() {
  local public_ip=$1
  printf 'vless://%s@%s:%s?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&flow=xtls-rprx-vision#%s' \
    "${SB_UUID}" "${public_ip}" "${SB_PORT}" "${SB_SNI}" "${SB_PUBLIC_KEY:-[密钥丢失，请更新配置]}" "${SB_SHORT_ID_1}" "${SB_NODE_NAME}"
}

build_mixed_http_link() {
  local public_ip=$1

  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    printf 'http://%s:%s@%s:%s' "${SB_MIXED_USERNAME}" "${SB_MIXED_PASSWORD}" "${public_ip}" "${SB_PORT}"
  else
    printf 'http://%s:%s' "${public_ip}" "${SB_PORT}"
  fi
}

build_mixed_socks5_link() {
  local public_ip=$1

  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    printf 'socks5://%s:%s@%s:%s' "${SB_MIXED_USERNAME}" "${SB_MIXED_PASSWORD}" "${public_ip}" "${SB_PORT}"
  else
    printf 'socks5://%s:%s' "${public_ip}" "${SB_PORT}"
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
    "${server_host}" \
    "${SB_PORT}" \
    "${query}" \
    "${SB_NODE_NAME}"
}

show_hy2_connection_summary() {
  echo -e "\n${YELLOW}Hysteria2 参数摘要：${NC}"
  echo "域名: ${SB_HY2_DOMAIN}"
  echo "端口: ${SB_PORT}"
  echo "TLS 模式: ${SB_HY2_TLS_MODE}"
  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    echo "混淆: ${SB_HY2_OBFS_TYPE:-salamander}"
  else
    echo "混淆: 未启用"
  fi
  echo "带宽: ${SB_HY2_UP_MBPS} / ${SB_HY2_DOWN_MBPS} Mbps"
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

show_connection_info_menu() {
  local public_ip
  public_ip=$(get_public_ip)

  while true; do
    echo -e "\n${BLUE}--- 连接信息查看 ---${NC}"
    echo "1. 仅链接"
    echo "2. 仅二维码"
    echo "3. 链接 + 二维码"
    echo "0. 返回"
    read -rp "请选择 [0-3]: " info_choice

    case "${info_choice}" in
      1) show_connection_details "link" "${public_ip}" ;;
      2) show_connection_details "qr" "${public_ip}" ;;
      3) show_connection_details "both" "${public_ip}" ;;
      0) return ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}

show_post_config_connection_info() {
  local public_ip
  public_ip=$(get_public_ip)

  echo -e "\n${GREEN}连接信息：${NC}"
  echo "已按当前配置生成以下连接信息。后续如需再次查看，可进入菜单 8。"
  show_connection_details "both" "${public_ip}"
}

prompt_singbox_version() {
  local input_version

  read -rp "版本 (默认 ${SB_SUPPORT_MAX_VERSION}): " input_version
  SB_VERSION=${input_version:-$SB_SUPPORT_MAX_VERSION}
}

install_or_reconfigure_singbox() {
  install_protocols_interactive "fresh"
}

update_singbox_binary_preserving_config() {
  local installed_ver
  local reinstall_choice

  installed_ver=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
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
  log_info "连接信息未自动展示，如需查看请进入菜单 8。"
}

install_or_update_singbox() {
  if [[ -f "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_CONFIG_FILE}" ]]; then
    echo -e "\n${BLUE}--- sing-box 管理 ---${NC}"
    echo "1. 更新 sing-box 二进制并保留当前配置"
    echo "2. 安装新增协议"
    echo "0. 返回"
    read -rp "请选择 [0-2] (默认 1): " install_choice

    case "${install_choice:-1}" in
      2) install_protocols_interactive "additional" ;;
      0) return 0 ;;
      *) update_singbox_binary_preserving_config ;;
    esac
    return
  fi

  install_or_reconfigure_singbox
}

main() {
  [[ $# -gt 0 && "$1" == "uninstall" ]] && check_root && uninstall_singbox && exit 0

  show_banner
  check_root
  while true; do
    # Status checks
    check_script_status
    check_sb_version
    check_bbr_status

    echo ""
    echo -e "1. 安装协议 / 更新 sing-box ${SB_VER_STATUS}"
    echo "2. 卸载 sing-box"
    echo "3. 修改当前协议配置"
    echo -e "4. 开启 BBR 拥塞控制算法 ${BBR_STATUS}"
    echo "--------------------------------"
    echo "5. 启动 sing-box"
    echo "6. 停止 sing-box"
    echo "7. 重启 sing-box"
    echo "8. 查看状态与节点信息"
    echo "9. 查看实时日志"
    echo "--------------------------------"
    echo -e "10. 更新管理脚本 (sbv) ${SCRIPT_VER_STATUS}"
    echo "11. 卸载管理脚本 (sbv)"
    echo "12. 配置 Cloudflare Warp (解锁/防送中)"
    echo "13. 流媒体验证检测"
    echo "0. 退出"
    read -rp "请选择 [0-13]: " choice

    case "$choice" in
      1) install_or_update_singbox ;;
      2) uninstall_singbox ;;
      3) update_config_only ;;
      4) enable_bbr ;;
      5) systemctl start sing-box && log_success "服务已启动。" ;;
      6) systemctl stop sing-box && log_success "服务已停止。" ;;
      7) systemctl restart sing-box && log_success "服务已重启。" ;;
      8) view_status_and_info ;;
      9) journalctl -u sing-box -f || true ;;
      10) manual_update_script ;;
      11) uninstall_script ;;
      12) warp_management ;;
      13) media_check_menu ;;
      0) exit 0 ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}


main "$@"
