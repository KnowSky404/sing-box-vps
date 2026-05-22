#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

detect_existing_instance_state() { printf 'healthy'; }
load_current_config_state() { SB_PROTOCOL="vless+reality"; SB_PORT="443"; }

mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"
cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
printf 'sing-box version 1.13.9\n'
EOF
chmod +x "${SINGBOX_BIN_PATH}"

output=$(install_or_update_singbox <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")
title_text_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print; exit }')

if [[ -z "${title_text_line}" || ! "${title_text_line}" =~ ^[^[:space:]] ]]; then
  printf 'expected install/update menu title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"部署管理"* ]]; then
  printf 'expected install/update submenu to use deployment management title, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"1. 更新 sing-box 二进制并保留当前配置"* ]]; then
  printf 'expected update option inside install/update menu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"2. 安装新增协议"* ]]; then
  printf 'expected add protocol option inside deployment submenu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"3. 修改已安装协议配置"* ]]; then
  printf 'expected protocol config option inside deployment submenu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"4. 移除已安装协议"* ]]; then
  printf 'expected remove protocol option inside deployment submenu, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"5. 卸载 sing-box"* ]]; then
  printf 'expected uninstall sing-box option inside deployment submenu, got:\n%s\n' "${output}" >&2
  exit 1
fi

update_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "1. 更新 sing-box 二进制并保留当前配置") { print NR; exit }')
add_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "2. 安装新增协议") { print NR; exit }')
config_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "3. 修改已安装协议配置") { print NR; exit }')
remove_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "4. 移除已安装协议") { print NR; exit }')
uninstall_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "5. 卸载 sing-box") { print NR; exit }')

if ! (( update_line < add_line && add_line < config_line && config_line < remove_line && remove_line < uninstall_line )); then
  printf 'expected deployment submenu options to follow lifecycle order, got:\n%s\n' "${output}" >&2
  exit 1
fi
