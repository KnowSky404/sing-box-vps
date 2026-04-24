#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

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

if [[ "${plain_output}" != *"1. 安装新协议"* ]]; then
  printf 'expected top-level install protocol option in sectioned main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"2. 更新 sing-box 版本"* ]]; then
  printf 'expected top-level update sing-box option in sectioned main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"15. 流媒体验证检测"* ]]; then
  printf 'expected media check option in sectioned main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

banner_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box-vps 一键安装管理脚本") { print NR; exit }')
brand_info_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "作者: KnowSky404 · 项目: https://github.com/KnowSky404/sing-box-vps") { print NR; exit }')
brand_meta_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "专为 VPS 稳定部署与安全运维设计 · 版本: ") { print NR; exit }')
deployment_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print NR; exit }')
exit_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "0. 退出") { print NR; exit }')

banner_text=$(printf '%s\n' "${plain_output}" | awk 'index($0, "sing-box-vps 一键安装管理脚本") { print; exit }')
if [[ -z "${banner_text}" || ! "${banner_text}" =~ ^[^[:space:]] ]]; then
  printf 'expected main banner title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ -z "${brand_info_line}" || -z "${brand_meta_line}" ]]; then
  printf 'expected compact brand info block at the top of the main menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! (( banner_line < brand_info_line && brand_info_line < brand_meta_line && brand_meta_line < deployment_line )); then
  printf 'expected title, author/project, and subtitle/version to appear before the deployment section, got:\n%s\n' "${output}" >&2
  exit 1
fi

if printf '%s\n' "${plain_output}" | awk '
  NR > '"${exit_line}"' && index($0, "作者: KnowSky404") { exit 0 }
  NR > '"${exit_line}"' && index($0, "项目: https://github.com/KnowSky404/sing-box-vps") { exit 0 }
  END { exit 1 }
'; then
  printf 'expected main menu footer to stop repeating author/project info, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"--------------------------------"* ]]; then
  printf 'expected future sectioned main menu to replace the legacy separator rows, got:\n%s\n' "${output}" >&2
  exit 1
fi

service_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "服务控制") { print NR; exit }')
diagnostics_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "连接与诊断") { print NR; exit }')
maintenance_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "脚本维护") { print NR; exit }')

if ! (( deployment_line < service_line && service_line < diagnostics_line && diagnostics_line < maintenance_line )); then
  printf 'expected future section labels to appear in grouped order, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "部署管理") { seen=1; next }
  seen && index($0, "1. 安装新协议") { found_install=1; next }
  seen && index($0, "2. 更新 sing-box 版本") { found_update=1; exit }
  seen && index($0, "服务控制") { exit }
  END { exit(found_install && found_update ? 0 : 1) }
'; then
  printf 'expected install and update options to stay within the deployment section, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "服务控制") { seen=1; next }
  seen && index($0, "9. 查看状态") { found=1; exit }
  seen && index($0, "连接与诊断") { exit }
  END { exit(found ? 0 : 1) }
'; then
  printf 'expected status option to stay within the service control section, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "连接与诊断") { seen=1; next }
  seen && index($0, "15. 流媒体验证检测") { found=1; exit }
  seen && index($0, "脚本维护") { exit }
  END { exit(found ? 0 : 1) }
'; then
  printf 'expected media check option to stay within the diagnostics section, got:\n%s\n' "${output}" >&2
  exit 1
fi
