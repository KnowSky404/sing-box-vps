#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 2026040809
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="2026040809"
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
    vless+reality|mixed) return 0 ;;
    *) return 1 ;;
  esac
}

protocol_display_name() {
  case "$1" in
    vless+reality) printf 'VLESS + REALITY' ;;
    mixed) printf 'Mixed (HTTP/HTTPS/SOCKS)' ;;
    *) printf '%s' "$1" ;;
  esac
}

protocol_inbound_tag() {
  case "$1" in
    mixed) printf 'mixed-in' ;;
    *) printf 'vless-in' ;;
  esac
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
  if [[ -f "${SINGBOX_BIN_PATH}" ]]; then
    CURRENT_SB_VER=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
    if [[ "${CURRENT_SB_VER}" != "${SB_SUPPORT_MAX_VERSION}" ]]; then
      SB_VER_STATUS="${YELLOW}(当前版本: ${CURRENT_SB_VER}, 建议更新到: ${SB_SUPPORT_MAX_VERSION})${NC}"
    else
      SB_VER_STATUS="${GREEN}(已是适配的最佳版本: ${CURRENT_SB_VER})${NC}"
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
  if ! "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"; then
    log_error "配置文件校验失败，请检查配置细节。"
  fi
  log_success "配置文件校验成功。"
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

  if ! validate_protocol "${SB_PROTOCOL}"; then
    log_error "不支持的协议类型: ${SB_PROTOCOL}"
  fi
  
  # UUID
  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    [[ -z "${SB_UUID}" ]] && SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  else
    ensure_mixed_auth_credentials
  fi
  
  # Keys
  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    if [[ ! -f "${SB_KEY_FILE}" ]]; then
      log_info "正在生成新的 REALITY 密钥对..."
      local keypair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
      SB_PRIVATE_KEY=$(echo "${keypair}" | grep "PrivateKey" | awk '{print $2}')
      SB_PUBLIC_KEY=$(echo "${keypair}" | grep "PublicKey" | awk '{print $2}')
      echo "PRIVATE_KEY=${SB_PRIVATE_KEY}" > "${SB_KEY_FILE}"
      echo "PUBLIC_KEY=${SB_PUBLIC_KEY}" >> "${SB_KEY_FILE}"
    else
      log_info "使用现有密钥对..."
      SB_PRIVATE_KEY=$(grep "PRIVATE_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
      SB_PUBLIC_KEY=$(grep "PUBLIC_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    fi
  else
    SB_UUID=""
    SB_PUBLIC_KEY=""
    SB_PRIVATE_KEY=""
  fi
  
  # ShortIDs
  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    [[ -z "${SB_SHORT_ID_1}" ]] && SB_SHORT_ID_1=$(openssl rand -hex 8)
    [[ -z "${SB_SHORT_ID_2}" ]] && SB_SHORT_ID_2=$(openssl rand -hex 8)
  else
    SB_SHORT_ID_1=""
    SB_SHORT_ID_2=""
  fi

  # Endpoints Logic
  local w_key="" w_v4="" w_v6=""
  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    register_warp
    w_key=$(grep "WARP_PRIV_KEY" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v4=$(grep "WARP_V4" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
    w_v6=$(grep "WARP_V6" "${SB_WARP_KEY_FILE}" | cut -d'=' -f2- | tr -d '\r\n ')
  fi

  refresh_warp_route_assets

  # Build JSON with jq
  jq -n \
    --arg protocol "${SB_PROTOCOL}" \
    --arg inbound_tag "$(protocol_inbound_tag "${SB_PROTOCOL}")" \
    --arg uuid "${SB_UUID}" \
    --arg port "${SB_PORT}" \
    --arg sni "${SB_SNI}" \
    --arg priv_key "${SB_PRIVATE_KEY}" \
    --arg sid1 "${SB_SHORT_ID_1}" \
    --arg sid2 "${SB_SHORT_ID_2}" \
    --arg mixed_auth_enabled "${SB_MIXED_AUTH_ENABLED}" \
    --arg mixed_username "${SB_MIXED_USERNAME}" \
    --arg mixed_password "${SB_MIXED_PASSWORD}" \
    --arg adv_route "${SB_ADVANCED_ROUTE}" \
    --arg enable_warp "${SB_ENABLE_WARP}" \
    --arg warp_mode "${SB_WARP_ROUTE_MODE}" \
    --arg w_key "${w_key}" \
    --arg w_v4 "${w_v4}/32" \
    --arg w_v6 "${w_v6}/128" \
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
      "inbounds": [
        (
          if $protocol == "mixed" then
            {
              "type": "mixed",
              "tag": $inbound_tag,
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
            )
          else
            {
              "type": "vless",
              "tag": $inbound_tag,
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
            }
          end
        )
      ],
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
          [ { "inbound": $inbound_tag, "action": "sniff" } ] +
          (
            if $protocol == "vless+reality" then
              [ { "domain": [$sni], "action": "direct" } ]
            else
              []
            end
          ) +
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
    }' > "${SINGBOX_CONFIG_FILE}"
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
  local cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
  if [[ "${cc}" == "bbr" ]]; then
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
  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]]; then
    log_error "未找到配置文件，请先安装。"
  fi

  SB_PROTOCOL=$(jq -r '.inbounds[0].type' "${SINGBOX_CONFIG_FILE}")
  case "${SB_PROTOCOL}" in
    vless) SB_PROTOCOL="vless+reality" ;;
    mixed) SB_PROTOCOL="mixed" ;;
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
  else
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
  fi

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
    display_info
  done
}

# Helper to extract config values and display info
view_status_and_info() {
  log_info "正在从配置文件中读取信息..."
  load_current_config_state
  display_info
}

# New function: Update config only
update_config_only() {
  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]]; then
    log_error "未找到配置文件，请先执行安装流程。"
  fi

  log_info "正在读取当前配置..."
  load_current_config_state

  echo -e "\n${BLUE}--- 进入配置修改模式 ---${NC}"

  # 1. Update Port
  read -rp "新端口 (当前: ${SB_PORT}, 留空保持): " in_p
  [[ -n "${in_p}" ]] && SB_PORT="${in_p}" && check_port_conflict "${SB_PORT}"

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    # 2. Update UUID
    read -rp "新 UUID (当前: ${SB_UUID}, 留空保持): " in_uuid
    [[ -n "${in_uuid}" ]] && SB_UUID="${in_uuid}"

    # 3. Update SNI
    read -rp "新 REALITY 域名 (当前: ${SB_SNI}, 留空保持): " in_sni
    [[ -n "${in_sni}" ]] && SB_SNI="${in_sni}"
  else
    read -rp "是否启用用户名密码认证 [y/n] (当前: ${SB_MIXED_AUTH_ENABLED}, 默认建议 y): " in_auth
    if [[ -n "${in_auth}" ]]; then
      SB_MIXED_AUTH_ENABLED="${in_auth}"
    fi

    if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
      read -rp "新用户名 (当前: ${SB_MIXED_USERNAME}, 留空保持/自动生成): " in_user
      [[ -n "${in_user}" ]] && SB_MIXED_USERNAME="${in_user}"
      read -rp "新密码 (当前: 留空隐藏, 留空保持/自动生成): " in_pass
      [[ -n "${in_pass}" ]] && SB_MIXED_PASSWORD="${in_pass}"
    else
      log_warn "关闭 Mixed 认证会暴露开放代理，存在明显安全风险。"
      SB_MIXED_USERNAME=""
      SB_MIXED_PASSWORD=""
    fi
  fi

  # 4. Update Route
  read -rp "是否开启高级路由规则 (广告拦截/局域网绕行) [y/n] (当前: ${SB_ADVANCED_ROUTE}): " in_route
  [[ -n "${in_route}" ]] && SB_ADVANCED_ROUTE="${in_route}"

  # 5. Update Warp
  read -rp "是否开启 Cloudflare Warp (用于解锁/防送中) [y/n] (当前: ${SB_ENABLE_WARP}): " in_warp
  [[ -n "${in_warp}" ]] && SB_ENABLE_WARP="${in_warp}"

  if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
    echo "Warp 路由模式:"
    echo "1. 全量流量走 Warp"
    echo "2. 仅 AI/流媒体及自定义规则走 Warp"
    read -rp "请选择 [1-2] (当前: ${SB_WARP_ROUTE_MODE}): " in_warp_mode
    case "${in_warp_mode}" in
      1) SB_WARP_ROUTE_MODE="all" ;;
      2) SB_WARP_ROUTE_MODE="selective" ;;
      "") ;;
      *) log_warn "保留当前 Warp 路由模式: ${SB_WARP_ROUTE_MODE}" ;;
    esac
  fi

  save_warp_route_settings
  generate_config
  check_config_valid
  setup_service
  open_firewall_port "${SB_PORT}"
  systemctl restart sing-box
  log_success "配置及服务文件已更新并重启服务。"


  # Final display
  display_info
}

display_info() {
  local public_ip=$(curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me)
  local protocol_name
  protocol_name=$(protocol_display_name "${SB_PROTOCOL}")

  echo -e "\n${GREEN}服务状态与节点信息：${NC}"
  echo "-------------------------------------------------------------"
  echo -e "进程状态: $(systemctl is-active sing-box)"
  echo -e "协议: ${protocol_name}"
  echo -e "地址: ${public_ip}  端口: ${SB_PORT}"

  if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
    local vless_link="vless://${SB_UUID}@${public_ip}:${SB_PORT}?security=reality&sni=${SB_SNI}&fp=chrome&pbk=${SB_PUBLIC_KEY}&sid=${SB_SHORT_ID_1}&flow=xtls-rprx-vision#${SB_NODE_NAME}"
    echo -e "UUID: ${SB_UUID}"
    echo -e "SNI:  ${SB_SNI} (REALITY)"
    echo -e "PBK:  ${SB_PUBLIC_KEY:-[密钥丢失，请更新配置]}"
    echo -e "SID:  ${SB_SHORT_ID_1}, ${SB_SHORT_ID_2}"

    if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
      echo -e "Warp: 已开启 (${SB_WARP_ROUTE_MODE})"
    else
      echo -e "Warp: 未开启"
    fi
    echo -e "${YELLOW}VLESS 链接:${NC}\n${vless_link}\n"

    echo -e "${YELLOW}节点二维码:${NC}"
    qrencode -t ansiutf8 "${vless_link}"
  else
    if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
      echo -e "认证: 已启用"
      echo -e "用户名: ${SB_MIXED_USERNAME}"
      echo -e "密码: ${SB_MIXED_PASSWORD}"
      echo -e "HTTP 代理: http://${SB_MIXED_USERNAME}:${SB_MIXED_PASSWORD}@${public_ip}:${SB_PORT}"
      echo -e "SOCKS5 代理: socks5://${SB_MIXED_USERNAME}:${SB_MIXED_PASSWORD}@${public_ip}:${SB_PORT}"
    else
      echo -e "认证: 未启用"
      log_warn "当前 Mixed 代理未启用认证，请尽快确认防火墙限制或开启认证。"
      echo -e "HTTP 代理: http://${public_ip}:${SB_PORT}"
      echo -e "SOCKS5 代理: socks5://${public_ip}:${SB_PORT}"
    fi

    if [[ "${SB_ENABLE_WARP}" == "y" ]]; then
      echo -e "Warp: 已开启 (${SB_WARP_ROUTE_MODE})"
    else
      echo -e "Warp: 未开启"
    fi
    echo -e "说明: HTTPS 网站通过 HTTP 代理的 CONNECT 模式转发。"
  fi

  echo "--------------------------------"
  echo -e "配置文件: ${SINGBOX_CONFIG_FILE}"
  echo "-------------------------------------------------------------"
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
    echo -e "1. 安装/更新 sing-box (VLESS+REALITY / Mixed) ${SB_VER_STATUS}"
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
      1)
        if [[ -f "${SINGBOX_BIN_PATH}" ]]; then
          local installed_ver=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
          if [[ "${installed_ver}" == "${SB_SUPPORT_MAX_VERSION}" ]]; then
            log_info "检测到已安装适配的最佳版本: ${installed_ver}"
            read -rp "是否需要重新安装? [y/N]: " reinstall_choice
            if [[ ! "${reinstall_choice}" =~ ^[Yy]$ ]]; then
              continue
            fi
          fi
        fi

        get_os_info && get_arch
        read -rp "版本 (默认 ${SB_SUPPORT_MAX_VERSION}): " in_v
        SB_VERSION=${in_v:-$SB_SUPPORT_MAX_VERSION}
        echo "协议类型:"
        echo "1. VLESS + REALITY"
        echo "2. Mixed (HTTP/HTTPS/SOCKS)"
        read -rp "请选择 [1-2] (默认 1): " in_protocol
        case "${in_protocol}" in
          2) set_protocol_defaults "mixed" ;;
          *) set_protocol_defaults "vless+reality" ;;
        esac

        read -rp "端口 (默认 ${SB_PORT}): " in_p
        SB_PORT=${in_p:-$SB_PORT}
        check_port_conflict "${SB_PORT}"

        if [[ "${SB_PROTOCOL}" == "vless+reality" ]]; then
          read -rp "REALITY 域名 (默认 apple.com): " in_sni
          SB_SNI=${in_sni:-"apple.com"}
        else
          read -rp "是否启用用户名密码认证 [y/n] (默认 y，强烈建议开启): " in_auth
          SB_MIXED_AUTH_ENABLED=${in_auth:-"y"}
          if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
            read -rp "用户名 (留空自动生成): " in_user
            SB_MIXED_USERNAME="${in_user}"
            read -rp "密码 (留空自动生成): " in_pass
            SB_MIXED_PASSWORD="${in_pass}"
          else
            log_warn "你选择了关闭认证。开放的 HTTP/SOCKS 代理存在明显安全风险，请确认防火墙与访问源限制。"
          fi
        fi

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

        install_dependencies
        get_latest_version
        save_warp_route_settings
        install_binary
        generate_config
        check_config_valid
        setup_service
        open_firewall_port "${SB_PORT}"
        systemctl restart sing-box
        display_info
        ;;
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
