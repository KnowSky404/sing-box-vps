#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 20260405
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="20260405"
readonly SB_SUPPORT_MAX_VERSION="1.13.5"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
readonly SINGBOX_CONFIG_DIR="/etc/sing-box"
readonly SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"

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

# --- Common Utilities ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "本脚本必须以 root 用户执行。"
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
  mkdir -p "${temp_dir}"
  log_info "开始下载 sing-box ${SB_VERSION}..."
  wget -O "${temp_dir}/sb.tar.gz" "${download_url}"
  tar -xzf "${temp_dir}/sb.tar.gz" -C "${temp_dir}"
  mv -f "$(find "${temp_dir}" -name "sing-box" -type f)" "${SINGBOX_BIN_PATH}"
  chmod +x "${SINGBOX_BIN_PATH}"
  rm -rf "${temp_dir}"
  log_success "二进制文件安装成功。"
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
}

# --- Config Generator ---
generate_config() {
  log_info "正在生成 VLESS+REALITY 配置..."
  mkdir -p "${SINGBOX_CONFIG_DIR}"
  
  # UUID
  [[ -z "${SB_UUID}" ]] && SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
  
  # Keys
  local keypair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
  SB_PRIVATE_KEY=$(echo "${keypair}" | grep "PrivateKey" | awk '{print $2}')
  SB_PUBLIC_KEY=$(echo "${keypair}" | grep "PublicKey" | awk '{print $2}')
  
  # ShortIDs
  SB_SHORT_ID_1=$(openssl rand -hex 8)
  SB_SHORT_ID_2=$(openssl rand -hex 8)

  cat > "${SINGBOX_CONFIG_FILE}" <<EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SB_PORT},
      "sniff": true,
      "sniff_override_destination": true,
      "users": [ { "uuid": "${SB_UUID}", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "${SB_SNI}",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SB_SNI}", "server_port": 443 },
          "private_key": "${SB_PRIVATE_KEY}",
          "short_id": [ "${SB_SHORT_ID_1}", "${SB_SHORT_ID_2}" ]
        }
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" } ]
}
EOF
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
  log_success "卸载完成。"
}

# --- UI & Main ---
show_banner() {
  clear
  echo -e "${BLUE}#############################################################${NC}"
  echo -e "${BLUE}#                                                           #${NC}"
  echo -e "${BLUE}#           sing-box-vps 一键安装管理脚本                   #${NC}"
  echo -e "${BLUE}#           脚本版本: ${SCRIPT_VERSION}                              #${NC}"
  echo -e "${BLUE}#           适配版本: ${SB_SUPPORT_MAX_VERSION} (sing-box)               #${NC}"
  echo -e "${BLUE}#                                                           #${NC}"
  echo -e "${BLUE}#############################################################${NC}"
  echo ""
}

display_info() {
  local public_ip=$(curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me)
  local vless_link="vless://${SB_UUID}@${public_ip}:${SB_PORT}?security=reality&sni=${SB_SNI}&fp=chrome&pbk=${SB_PUBLIC_KEY}&sid=${SB_SHORT_ID_1}&flow=xtls-rprx-vision#${SB_NODE_NAME}"
  
  echo -e "\n${GREEN}安装成功！节点信息如下：${NC}"
  echo "-------------------------------------------------------------"
  echo -e "地址: ${public_ip}  端口: ${SB_PORT}"
  echo -e "UUID: ${SB_UUID}"
  echo -e "SNI:  ${SB_SNI} (REALITY)"
  echo -e "PBK:  ${SB_PUBLIC_KEY}"
  echo -e "SID:  ${SB_SHORT_ID_1}"
  echo "-------------------------------------------------------------"
  echo -e "${YELLOW}VLESS 链接:${NC}\n${vless_link}\n"
  
  echo -e "${YELLOW}节点二维码 (扫描二维码以导入):${NC}"
  qrencode -t ansiutf8 "${vless_link}"
  echo "-------------------------------------------------------------"
}

main() {
  [[ $# -gt 0 && "$1" == "uninstall" ]] && check_root && uninstall_singbox && exit 0

  show_banner
  check_root
  
  echo "1. 安装 sing-box (VLESS+REALITY)"
  echo "2. 卸载 sing-box"
  echo "0. 退出"
  read -rp "请选择 [0-2]: " choice

  case "$choice" in
    1)
      get_os_info && get_arch
      # Interactive
      read -rp "版本 (默认 ${SB_SUPPORT_MAX_VERSION}): " in_v
      SB_VERSION=${in_v:-$SB_SUPPORT_MAX_VERSION}
      read -rp "端口 (默认 443): " in_p
      SB_PORT=${in_p:-443}
      
      install_dependencies
      get_latest_version
      install_binary
      generate_config
      setup_service
      systemctl restart sing-box
      display_info
      ;;
    2) uninstall_singbox ;;
    *) exit 0 ;;
  esac
}

main "$@"
