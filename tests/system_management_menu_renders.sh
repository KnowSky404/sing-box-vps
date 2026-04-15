#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

check_bbr_status() {
  BBR_STATUS="(已开启 BBR)"
}

output=$(system_management_menu <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")

if [[ "${plain_output}" != *"系统摘要"* ]]; then
  printf 'expected future system summary heading inside system management, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"系统管理"* ]]; then
  printf 'expected system management title to render, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"1. 开启 BBR"* ]]; then
  printf 'expected BBR option inside system management, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${plain_output}" != *"2. 协议栈管理"* ]]; then
  printf 'expected stack management option inside system management, got:\n%s\n' "${output}" >&2
  exit 1
fi

title_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "系统管理") { print NR; exit }')
summary_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "系统摘要") { print NR; exit }')
bbr_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "1. 开启 BBR") { print NR; exit }')
stack_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "2. 协议栈管理") { print NR; exit }')

if ! (( title_line < summary_line && summary_line < bbr_line && bbr_line < stack_line )); then
  printf 'expected future summary block to appear between the title and menu body, got:\n%s\n' "${output}" >&2
  exit 1
fi
