#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 56
source_testable_install

check_bbr_status() {
  BBR_STATUS="(已开启 BBR)"
}

output=$(system_management_menu <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")

if [[ "${plain_output}" != *"系统管理"* ]]; then
  printf 'expected system management title to render in narrow terminal fallback, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"1. 开启 BBR"* ]]; then
  printf 'expected BBR option in narrow terminal fallback, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"2. 协议栈管理"* ]]; then
  printf 'expected stack management option in narrow terminal fallback, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"--- 系统管理 ---"* ]]; then
  printf 'expected narrow terminal fallback to replace the legacy dashed header, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" == *"1. 开启 BBR ("* ]]; then
  printf 'expected narrow terminal fallback to move BBR status out of the menu item line, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! printf '%s\n' "${plain_output}" | awk '
  index($0, "1. 开启 BBR") { bbr_line=NR }
  index($0, "2. 协议栈管理") { stack_line=NR }
  END { exit(bbr_line > 0 && stack_line > 0 && stack_line > bbr_line && stack_line <= bbr_line + 2 ? 0 : 1) }
'; then
  printf 'expected narrow terminal fallback to place key options on separate nearby lines, got:\n%s\n' "${output}" >&2
  exit 1
fi
