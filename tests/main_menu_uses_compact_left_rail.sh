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
first_divider=$(printf '%s\n' "${plain_output}" | awk '/^═+$/ { print; exit }')
deployment_title=$(printf '%s\n' "${plain_output}" | awk 'index($0, "部署管理") { print; exit }')
first_divider_chars=$(printf '%s' "${first_divider}" | wc -m | tr -d '[:space:]')

if [[ -z "${first_divider}" ]]; then
  printf 'expected main menu to render a top divider, got:\n%s\n' "${output}" >&2
  exit 1
fi

if (( first_divider_chars >= 120 )); then
  printf 'expected main menu top divider to stay compact instead of spanning 120 columns, got:\n%s\n' "${output}" >&2
  exit 1
fi

if (( first_divider_chars > 72 )); then
  printf 'expected main menu top divider to fit within compact UI width, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ -z "${deployment_title}" || ! "${deployment_title}" =~ ^[^[:space:]] ]]; then
  printf 'expected main menu section title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if (( $(estimate_text_width "${deployment_title}") > 72 )); then
  printf 'expected main menu section title to fit within compact UI width, got:\n%s\n' "${output}" >&2
  exit 1
fi
