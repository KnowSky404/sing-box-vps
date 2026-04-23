#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

output=$(show_node_info_action_menu <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")
title_text_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "节点信息查看") { print; exit }')
section_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "操作选项") { print NR; exit }')
view_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "1. 查看连接链接 / 二维码") { print NR; exit }')
export_line=$(printf '%s\n' "${plain_output}" | awk 'index($0, "2. 导出 sing-box 裸核客户端配置") { print NR; exit }')

if [[ -z "${title_text_line}" || ! "${title_text_line}" =~ ^[^[:space:]] ]]; then
  printf 'expected node info action menu title to render flush-left, got:\n%s\n' "${output}" >&2
  exit 1
fi

if ! (( section_line < view_line && view_line < export_line )); then
  printf 'expected node info action menu options to stay grouped under the action section, got:\n%s\n' "${output}" >&2
  exit 1
fi
