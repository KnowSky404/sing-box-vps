#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SB_PROJECT_DIR="${SB_PROJECT_DIR:-/root/sing-box-vps}"
readonly SBV_BIN_PATH="${SBV_BIN_PATH:-/usr/local/bin/sbv}"
readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

check_root() {
  if [[ ${EUID} -ne 0 ]]; then
    print_error "本脚本必须以 root 身份运行。"
  fi
}

resolve_install_script() {
  local candidate

  for candidate in \
    "${SCRIPT_DIR}/install.sh" \
    "${SB_PROJECT_DIR}/install.sh" \
    "${SBV_BIN_PATH}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

main() {
  check_root

  local assume_yes="n"
  local install_script=""

  while (($# > 0)); do
    case "$1" in
      --purge)
        ;;
      --keep-config)
        print_error "保留配置的卸载模式尚未实现；未执行卸载。"
        ;;
      --yes)
        assume_yes="y"
        ;;
      *)
        print_error "不支持的参数: $1"
        ;;
    esac
    shift
  done

  if ! install_script=$(resolve_install_script); then
    print_error "未找到可用的管理脚本，无法继续卸载。请确认已安装 sing-box-vps，或改用 sbv 菜单卸载。"
  fi

  if [[ "${assume_yes}" != "y" ]]; then
    print_warn "即将彻底删除 sing-box 服务、配置目录、密钥和全局命令 sbv。"
    read -rp "确认继续吗？[y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      print_info "已取消卸载。"
      exit 0
    fi
  fi

  print_info "正在调用已安装管理脚本的内置彻底卸载逻辑..."
  exec bash "${install_script}" --internal-uninstall-purge --yes
}

main "$@"
