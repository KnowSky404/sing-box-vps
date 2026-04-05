#!/usr/bin/env bash

# sing-box-vps 一键安装管理脚本 (All-in-One Standalone)
# Version: 20260405
# GitHub: https://github.com/KnowSky404/sing-box-vps
# License: AGPL-3.0

set -euo pipefail

# --- Constants and File Paths ---
readonly SCRIPT_VERSION="2026040517"
readonly SB_SUPPORT_MAX_VERSION="1.13.5"
readonly SB_PROJECT_DIR="/root/sing-box-vps"
readonly SB_KEY_FILE="${SB_PROJECT_DIR}/reality.key"
readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"
readonly SINGBOX_CONFIG_DIR="${SB_PROJECT_DIR}"
readonly SINGBOX_CONFIG_FILE="${SB_PROJECT_DIR}/config.json"
readonly SINGBOX_LOG_FILE="${SB_PROJECT_DIR}/sing-box.log"
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
SB_ADVANCED_ROUTE="y"

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
  log_info "正在生成 VLESS+REALITY 配置 (适配 sing-box 1.13.0+)..."
  mkdir -p "${SINGBOX_CONFIG_DIR}"

  # UUID
  [[ -z "${SB_UUID}" ]] && SB_UUID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)

  # Keys
  if [[ ! -f "${SB_KEY_FILE}" ]]; then
    log_info "正在生成新的 REALITY 密钥对..."
    local keypair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
    SB_PRIVATE_KEY=$(echo "${keypair}" | grep "PrivateKey" | awk '{print $2}')
    SB_PUBLIC_KEY=$(echo "${keypair}" | grep "PublicKey" | awk '{print $2}')
    echo "PRIVATE_KEY=${SB_PRIVATE_KEY}" > "${SB_KEY_FILE}"
    echo "PUBLIC_KEY=${SB_PUBLIC_KEY}" >> "${SB_KEY_FILE}"
  else
    log_info "使用现有密钥对..."
    SB_PRIVATE_KEY=$(grep "PRIVATE_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2)
    SB_PUBLIC_KEY=$(grep "PUBLIC_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2)
  fi

  # ShortIDs
  SB_SHORT_ID_1=$(openssl rand -hex 8)
  SB_SHORT_ID_2=$(openssl rand -hex 8)

  # Route rules logic
  local route_rules='[ { "inbound": "vless-in", "action": "sniff" }'
  if [[ "${SB_ADVANCED_ROUTE}" == "y" ]]; then
    route_rules+=', { "geosite": "category-ads-all", "action": "reject" }, { "geoip": "private", "action": "reject" }'
  fi
  route_rules+=' ]'

  cat > "${SINGBOX_CONFIG_FILE}" <<EOF
{
  "log": {
    "level": "debug",
    "timestamp": true,
    "output": "${SINGBOX_LOG_FILE}"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${SB_PORT},
      "users": [ { "uuid": "${SB_UUID}", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "${SB_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SB_SNI}", "server_port": 443 },
          "private_key": "${SB_PRIVATE_KEY}",
          "short_id": [ "${SB_SHORT_ID_1}", "${SB_SHORT_ID_2}" ]
        }
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": ${route_rules}
  }
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

# Helper to extract config values and display info
view_status_and_info() {
  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]]; then
    log_error "未找到配置文件，请先安装。"
  fi

  log_info "正在从配置文件中读取信息..."
  SB_UUID=$(jq -r '.inbounds[0].users[0].uuid' "${SINGBOX_CONFIG_FILE}")
  SB_PORT=$(jq -r '.inbounds[0].listen_port' "${SINGBOX_CONFIG_FILE}")
  SB_SNI=$(jq -r '.inbounds[0].tls.server_name' "${SINGBOX_CONFIG_FILE}")
  SB_SHORT_ID_1=$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${SINGBOX_CONFIG_FILE}")
  SB_SHORT_ID_2=$(jq -r '.inbounds[0].tls.reality.short_id[1]' "${SINGBOX_CONFIG_FILE}")
  
  # Read Public Key from file
  if [[ -f "${SB_KEY_FILE}" ]]; then
    SB_PUBLIC_KEY=$(grep "PUBLIC_KEY" "${SB_KEY_FILE}" | cut -d'=' -f2)
  else
    # Fallback (though unlikely)
    log_warn "未找到密钥文件，请重新安装或更新配置以生成密钥文件。"
    SB_PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key' "${SINGBOX_CONFIG_FILE}")
    SB_PUBLIC_KEY="[密钥丢失，请更新配置]"
  fi

  display_info
}

# New function: Update config only
update_config_only() {
  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]]; then
    log_error "未找到配置文件，请先执行安装流程。"
  fi

  log_info "正在读取当前配置..."
  SB_UUID=$(jq -r '.inbounds[0].users[0].uuid' "${SINGBOX_CONFIG_FILE}")
  SB_PORT=$(jq -r '.inbounds[0].listen_port' "${SINGBOX_CONFIG_FILE}")
  SB_SNI=$(jq -r '.inbounds[0].tls.server_name' "${SINGBOX_CONFIG_FILE}")
  SB_PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key' "${SINGBOX_CONFIG_FILE}")
  SB_SHORT_ID_1=$(jq -r '.inbounds[0].tls.reality.short_id[0]' "${SINGBOX_CONFIG_FILE}")
  SB_SHORT_ID_2=$(jq -r '.inbounds[0].tls.reality.short_id[1]' "${SINGBOX_CONFIG_FILE}")

  # Generate PBK from Private Key
  SB_PUBLIC_KEY=$("${SINGBOX_BIN_PATH}" generate reality-keypair <<< "${SB_PRIVATE_KEY}" | grep "PublicKey" | awk '{print $2}')

  # Parse current route rules
  if jq -e '.route.rules[] | select(.geosite == "category-ads-all")' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
    SB_ADVANCED_ROUTE="y"
  else
    SB_ADVANCED_ROUTE="n"
  fi

  echo -e "\n${BLUE}--- 进入配置修改模式 ---${NC}"

  # 1. Update Port
  read -rp "新端口 (当前: ${SB_PORT}, 留空保持): " in_p
  [[ -n "${in_p}" ]] && SB_PORT="${in_p}" && check_port_conflict "${SB_PORT}"

  # 2. Update UUID
  read -rp "新 UUID (当前: ${SB_UUID}, 留空保持): " in_uuid
  [[ -n "${in_uuid}" ]] && SB_UUID="${in_uuid}"

  # 3. Update SNI
  read -rp "新 REALITY 域名 (当前: ${SB_SNI}, 留空保持): " in_sni
  [[ -n "${in_sni}" ]] && SB_SNI="${in_sni}"

  # 4. Update Route
  read -rp "是否开启高级路由规则 (广告拦截/局域网绕行) [y/n] (当前: ${SB_ADVANCED_ROUTE}): " in_route
  [[ -n "${in_route}" ]] && SB_ADVANCED_ROUTE="${in_route}"

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
  local vless_link="vless://${SB_UUID}@${public_ip}:${SB_PORT}?security=reality&sni=${SB_SNI}&fp=chrome&pbk=${SB_PUBLIC_KEY}&sid=${SB_SHORT_ID_1}&flow=xtls-rprx-vision#${SB_NODE_NAME}"

  echo -e "\n${GREEN}服务状态与节点信息：${NC}"
  echo "-------------------------------------------------------------"
  echo -e "进程状态: $(systemctl is-active sing-box)"
  echo -e "地址: ${public_ip}  端口: ${SB_PORT}"
  echo -e "UUID: ${SB_UUID}"
  echo -e "SNI:  ${SB_SNI} (REALITY)"
  echo -e "PBK:  ${SB_PUBLIC_KEY}"
  echo -e "SID:  ${SB_SHORT_ID_1}, ${SB_SHORT_ID_2}"
  echo "--------------------------------"
  echo -e "配置文件: ${SINGBOX_CONFIG_FILE}"
  echo -e "日志文件: ${SINGBOX_LOG_FILE}"
  echo "-------------------------------------------------------------"
  echo -e "${YELLOW}VLESS 链接:${NC}\n${vless_link}\n"

  echo -e "${YELLOW}节点二维码:${NC}"
  qrencode -t ansiutf8 "${vless_link}"
  echo "-------------------------------------------------------------"
}

main() {
  [[ $# -gt 0 && "$1" == "uninstall" ]] && check_root && uninstall_singbox && exit 0

  show_banner
  check_root

  # Status checks
  check_script_status
  check_sb_version
  check_bbr_status

  echo -e "1. 安装/更新 sing-box (VLESS+REALITY) ${SB_VER_STATUS}"
  echo "2. 卸载 sing-box"
  echo "3. 修改当前协议配置 (端口/UUID/域名)"
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
  echo "0. 退出"
  read -rp "请选择 [0-11]: " choice

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
      read -rp "端口 (默认 443): " in_p
      SB_PORT=${in_p:-443}
      check_port_conflict "${SB_PORT}"
      read -rp "REALITY 域名 (默认 apple.com): " in_sni
      SB_SNI=${in_sni:-"apple.com"}
      read -rp "是否开启高级路由规则 (广告拦截/局域网绕行) [y/n] (默认 y): " in_route
      SB_ADVANCED_ROUTE=${in_route:-"y"}

      install_dependencies
      get_latest_version
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
    9) journalctl -u sing-box -f ;;
    10) manual_update_script ;;
    11) uninstall_script ;;
    *) exit 0 ;;
  esac
  }



main "$@"
