#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

load_current_config_state() {
  SB_ENABLE_WARP="y"
  SB_WARP_ROUTE_MODE="selective"
}

ensure_warp_routing_assets() {
  :
}

output=$(warp_management <<'EOF'
0
EOF
)

plain_output=$(strip_ansi "${output}")

if [[ "${plain_output}" != *"当前状态: 已开启"* ]]; then
  printf 'expected warp summary status text, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" == *'\\033[0;32m已开启\\033[0m'* ]]; then
  printf 'expected warp summary status to render ANSI color instead of literal escape text, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *$'\033[0;32m已开启\033[0m'* ]]; then
  printf 'expected warp summary status to contain rendered ANSI escapes, got:\n%s\n' "${output}" >&2
  exit 1
fi
