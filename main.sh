#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本
# Author: Gemini CLI
# Date: 2026-04-05

set -euo pipefail

# Constants and File Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
readonly SINGBOX_CONFIG_DIR="/etc/sing-box"
readonly SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"
readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"

# Load common utilities
source "${SCRIPT_DIR}/utils/common.sh"

# Global Variables
SB_VERSION="latest"
SB_PROTOCOL="vless+reality"
SB_NODE_NAME="vless_reality_$(hostname)"
SB_PORT="443"
SB_UUID=""
SB_PUBLIC_KEY=""
SB_PRIVATE_KEY=""
SB_SHORT_ID=""
SB_SNI="www.google.com"

# --- Main Functions ---

# Print banner
show_banner() {
  clear
  echo "#############################################################"
  echo "#                                                           #"
  echo "#           sing-box-vps 一键安装管理脚本                   #"
  echo "#           协议支持: VLESS + REALITY                       #"
  echo "#                                                           #"
  echo "#############################################################"
  echo ""
}

# Interactive Menu for configuration
interactive_config() {
  log_info "进入交互式配置阶段..."

  # 1. Version Info
  read -rp "请输入要安装的 sing-box 版本 (默认: ${SB_VERSION}): " input_version
  SB_VERSION=${input_version:-$SB_VERSION}

  # 2. Node Name
  read -rp "请输入节点名称 (默认: ${SB_NODE_NAME}): " input_name
  SB_NODE_NAME=${input_name:-$SB_NODE_NAME}

  # 3. Port
  read -rp "请输入端口 (默认: ${SB_PORT}): " input_port
  SB_PORT=${input_port:-$SB_PORT}

  # 4. UUID (Auto-generated if empty)
  read -rp "请输入 UUID (留空则自动生成): " input_uuid
  SB_UUID=${input_uuid}

  log_success "配置已收集完成。"
}

# Output installation info
display_info() {
  local public_ip
  public_ip=$(curl -s https://api.ip.sb/ip || curl -s https://ifconfig.me)
  
  local vless_link="vless://${SB_UUID}@${public_ip}:${SB_PORT}?security=reality&sni=${SB_SNI}&fp=chrome&pbk=${SB_PUBLIC_KEY}&sid=${SB_SHORT_ID}&flow=xtls-rprx-vision#${SB_NODE_NAME}"

  echo ""
  log_success "sing-box 安装与配置已完成！"
  echo "-------------------------------------------------------------"
  echo -e "${BLUE}节点名称:${NC} ${SB_NODE_NAME}"
  echo -e "${BLUE}协议类型:${NC} VLESS + REALITY"
  echo -e "${BLUE}公网地址:${NC} ${public_ip}"
  echo -e "${BLUE}监听端口:${NC} ${SB_PORT}"
  echo -e "${BLUE}UUID:${NC}     ${SB_UUID}"
  echo -e "${BLUE}SNI:${NC}      ${SB_SNI}"
  echo -e "${BLUE}Public Key:${NC} ${SB_PUBLIC_KEY}"
  echo -e "${BLUE}Short ID:${NC}   ${SB_SHORT_ID}"
  echo -e "${BLUE}配置文件:${NC} ${SINGBOX_CONFIG_FILE}"
  echo -e "${BLUE}日志查看:${NC} journalctl -u sing-box -f"
  echo "-------------------------------------------------------------"
  echo -e "${GREEN}VLESS 链接 (复制到客户端):${NC}"
  echo -e "${vless_link}"
  echo "-------------------------------------------------------------"
}

# Entry point logic
main() {
  show_banner
  check_root
  get_os_info
  get_arch

  log_info "检测到系统: ${OS_NAME} ${OS_VERSION}, 架构: ${ARCH}"

  interactive_config

  log_info "当前选择配置: 版本=${SB_VERSION}, 节点=${SB_NODE_NAME}, 端口=${SB_PORT}"
  
  # Execute sub-modules
  source "${SCRIPT_DIR}/scripts/system_check.sh"
  source "${SCRIPT_DIR}/scripts/singbox_manager.sh"
  source "${SCRIPT_DIR}/scripts/config_generator.sh"

  # Restart service
  log_info "正在启动 sing-box 服务..."
  systemctl restart sing-box
  
  display_info
}

main "$@"
