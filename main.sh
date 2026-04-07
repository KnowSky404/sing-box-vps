#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本
# Author: Gemini CLI
# Date: 2026-04-05

set -euo pipefail

# Constants and File Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_VERSION="2026040534"
readonly SB_SUPPORT_MAX_VERSION="1.13.5"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
readonly SINGBOX_CONFIG_DIR="/etc/sing-box"
readonly SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"

# Load common utilities
source "${SCRIPT_DIR}/utils/common.sh"

# Global Variables
SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
SB_PROTOCOL="vless+reality"
SB_NODE_NAME="vless_reality_$(hostname)"
SB_PORT="443"
SB_UUID=""
SB_PUBLIC_KEY=""
SB_PRIVATE_KEY=""
SB_SHORT_ID=""
SB_SNI="apple.com"

# --- Main Functions ---

# Print banner
show_banner() {
  clear
  echo "#############################################################"
  echo "#                                                           #"
  echo "#           sing-box-vps 一键安装管理脚本                   #"
  echo "#           脚本版本: ${SCRIPT_VERSION}                             #"
  echo "#           适配版本: ${SB_SUPPORT_MAX_VERSION} (sing-box)              #"
  echo "#           协议支持: VLESS + REALITY                       #"
  echo "#                                                           #"
  echo "#############################################################"
  echo ""
}

# Interactive Menu for configuration
interactive_config() {
  log_info "进入交互式配置阶段..."

  # 1. Version Info
  echo -e "当前脚本完美适配的 sing-box 版本为: ${GREEN}${SB_SUPPORT_MAX_VERSION}${NC}"
  read -rp "请输入要安装的版本 (默认: ${SB_SUPPORT_MAX_VERSION}, 输入 'latest' 获取最新): " input_version
  SB_VERSION=${input_version:-$SB_SUPPORT_MAX_VERSION}

  # 2. Node Name
  read -rp "请输入节点名称 (默认: ${SB_NODE_NAME}): " input_name
  SB_NODE_NAME=${input_name:-$SB_NODE_NAME}

  # 3. Port
  read -rp "请输入端口 (默认: ${SB_PORT}): " input_port
  SB_PORT=${input_port:-$SB_PORT}

  # 4. UUID (Auto-generated if empty)
  read -rp "请输入 REALITY 域名 (默认: ${SB_SNI}): " input_sni
  SB_SNI=${input_sni:-$SB_SNI}

  read -rp "请输入 UUID (留空则自动生成): " input_uuid
  SB_UUID=${input_uuid}

  log_success "配置已收集完成。"
}

# Output installation info
display_info() {
  local public_ip
  public_ip=$(curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me)
  
  local vless_link="vless://${SB_UUID}@${public_ip}:${SB_PORT}?security=reality&sni=${SB_SNI}&fp=chrome&pbk=${SB_PUBLIC_KEY}&sid=${SB_SHORT_ID_1}&flow=xtls-rprx-vision#${SB_NODE_NAME}"

  echo ""
  log_success "sing-box 安装与配置已完成！"
  echo "-------------------------------------------------------------"
  echo -e "${BLUE}节点名称:${NC} ${SB_NODE_NAME}"
  echo -e "${BLUE}协议类型:${NC} VLESS + REALITY"
  echo -e "${BLUE}公网地址:${NC} ${public_ip}"
  echo -e "${BLUE}监听端口:${NC} ${SB_PORT}"
  echo -e "${BLUE}UUID:${NC}     ${SB_UUID}"
  echo -e "${BLUE}SNI:${NC}      ${SB_SNI}"
  echo -e "${BLUE}TLS Fingerprint:${NC} chrome"
  echo -e "${BLUE}Public Key:${NC} ${SB_PUBLIC_KEY}"
  echo -e "${BLUE}Short IDs:${NC}  ${SB_SHORT_ID_1}, ${SB_SHORT_ID_2}"
  echo -e "${BLUE}配置文件:${NC} ${SINGBOX_CONFIG_FILE}"
  echo -e "${BLUE}日志查看:${NC} journalctl -u sing-box -f"
  echo "-------------------------------------------------------------"
  echo -e "${GREEN}VLESS 链接 (复制到客户端):${NC}"
  echo -e "${vless_link}"
  echo -e "${YELLOW}节点二维码 (扫描二维码以导入):${NC}"
  qrencode -t ansiutf8 "${vless_link}"
  echo "-------------------------------------------------------------"
}

# Entry point logic
main() {
  # Handle command line arguments
  if [[ $# -gt 0 ]]; then
    case "$1" in
      uninstall)
        check_root
        source "${SCRIPT_DIR}/scripts/uninstaller.sh"
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        ;;
    esac
  fi

  show_banner
  check_root

  echo "1. 安装 sing-box (VLESS+REALITY)"
  echo "2. 卸载 sing-box"
  echo "0. 退出"
  echo ""
  read -rp "请选择操作 [0-2]: " main_choice

  case "${main_choice}" in
    1)
      get_os_info
      get_arch
      log_info "检测到系统: ${OS_NAME} ${OS_VERSION}, 架构: ${ARCH}"
      interactive_config
      log_info "当前选择配置: 版本=${SB_VERSION}, 节点=${SB_NODE_NAME}, 端口=${SB_PORT}"
      
      source "${SCRIPT_DIR}/scripts/system_check.sh"
      source "${SCRIPT_DIR}/scripts/singbox_manager.sh"
      source "${SCRIPT_DIR}/scripts/config_generator.sh"

      log_info "正在启动 sing-box 服务..."
      systemctl restart sing-box
      display_info
      ;;
    2)
      source "${SCRIPT_DIR}/scripts/uninstaller.sh"
      ;;
    *)
      log_info "退出脚本。"
      exit 0
      ;;
  esac
}

main "$@"
