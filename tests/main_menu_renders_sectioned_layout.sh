#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

show_banner() {
  :
}

check_root() {
  :
}

ensure_sbv_command_installed() {
  :
}

check_script_status() {
  SCRIPT_VER_STATUS="(脚本已是最新)"
}

check_sb_version() {
  SB_VER_STATUS="(sing-box 已安装)"
}

check_bbr_status() {
  BBR_STATUS="(已开启 BBR)"
}

clear() {
  :
}

exit_script() {
  exit 0
}

output=$(main 2>&1 <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")

if [[ "${plain_output}" != *"部署管理"* ]]; then
  printf 'expected future deployment section label in main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"服务控制"* ]]; then
  printf 'expected future service control section label in main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"连接与诊断"* ]]; then
  printf 'expected future connectivity and diagnostics section label in main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"脚本维护"* ]]; then
  printf 'expected future maintenance section label in main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"1. 安装协议 / 更新 sing-box"* ]]; then
  printf 'expected main install/update option in sectioned main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"14. 流媒体验证检测"* ]]; then
  printf 'expected media check option in sectioned main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"--------------------------------"* ]]; then
  printf 'expected future sectioned main menu to replace the legacy separator rows, got:\n%s\n' "${output}" >&2
  exit 1
fi

deployment_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print NR; exit }')
service_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "服务控制") { print NR; exit }')
diagnostics_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "连接与诊断") { print NR; exit }')
maintenance_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "脚本维护") { print NR; exit }')

if ! (( deployment_line < service_line && service_line < diagnostics_line && diagnostics_line < maintenance_line )); then
  printf 'expected future section labels to appear in grouped order, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "部署管理") { seen=1; next }
  seen && index($0, "1. 安装协议 / 更新 sing-box") { found=1; exit }
  seen && index($0, "服务控制") { exit }
  END { exit(found ? 0 : 1) }
'; then
  printf 'expected install/update option to stay within the deployment section, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "服务控制") { seen=1; next }
  seen && index($0, "8. 查看状态") { found=1; exit }
  seen && index($0, "连接与诊断") { exit }
  END { exit(found ? 0 : 1) }
'; then
  printf 'expected status option to stay within the service control section, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "连接与诊断") { seen=1; next }
  seen && index($0, "14. 流媒体验证检测") { found=1; exit }
  seen && index($0, "脚本维护") { exit }
  END { exit(found ? 0 : 1) }
'; then
  printf 'expected media check option to stay within the diagnostics section, got:\n%s\n' "${output}" >&2
  exit 1
fi
