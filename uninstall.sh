#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SB_PROJECT_DIR="${SB_PROJECT_DIR:-/root/sing-box-vps}"
readonly SBV_BIN_PATH="${SBV_BIN_PATH:-/usr/local/bin/sbv}"
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

  local mode="purge"
  local assume_yes="n"
  local install_script=""

  while (($# > 0)); do
    case "$1" in
      --purge)
        mode="purge"
        ;;
      --keep-config)
        mode="keep-config"
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
    echo "卸载模式:"
    echo "1. 彻底删除（默认，已实现）"
    echo "2. 保留配置（预留，暂未实现）"
    read -rp "请选择 [1/2，默认 1]: " choice
    case "${choice:-1}" in
      1) mode="purge" ;;
      2) mode="keep-config" ;;
      *) print_error "无效选项。" ;;
    esac
  fi

  if [[ "${mode}" == "keep-config" ]]; then
    print_warn "保留配置的卸载模式尚未实现，请先使用彻底删除模式。"
    exit 1
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
