#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

assert_equals() {
  local expected=$1
  local actual=$2
  local message=$3

  if [[ "${actual}" != "${expected}" ]]; then
    printf '%s: expected %s, got %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_equals "test-host-vless" "$(default_node_name_for_protocol "vless+reality")" "vless default node name"
assert_equals "test-host-hy2" "$(default_node_name_for_protocol "hy2")" "hy2 default node name"
assert_equals "test-host-anytls" "$(default_node_name_for_protocol "anytls")" "anytls default node name"
assert_equals "test-host-mixed" "$(default_node_name_for_protocol "mixed")" "mixed default node name"

assert_equals "test-host-vless-v4" "$(node_name_for_network_stack "test-host-vless" "IPv4")" "vless IPv4 node name"
assert_equals "test-host-vless-v6" "$(node_name_for_network_stack "test-host-vless" "IPv6")" "vless IPv6 node name"
assert_equals "gl-gb-lon-vless-v4" "$(node_name_for_network_stack "gl-gb-lon+vless" "IPv4")" "legacy plus vless IPv4 node name"
assert_equals "gl-gb-lon-hy2" "$(normalize_node_name "gl-gb-lon+hy2")" "legacy plus hy2 node name"

SB_VLESS_RATE_LIMIT_UP_MBPS=""
SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
assert_equals "test-host-vless" "$(vless_reality_display_node_name "test-host-vless" "")" "unlimited vless display node name"

SB_VLESS_RATE_LIMIT_UP_MBPS="10"
SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
assert_equals "test-host-vless-U10M" "$(vless_reality_display_node_name "test-host-vless" "")" "up limited vless display node name"

SB_VLESS_RATE_LIMIT_UP_MBPS=""
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
assert_equals "test-host-vless-D100M" "$(vless_reality_display_node_name "test-host-vless" "")" "down limited vless display node name"

SB_VLESS_RATE_LIMIT_UP_MBPS="10"
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
assert_equals "test-host-vless-U10M-D100M-v4" "$(vless_reality_display_node_name "test-host-vless" "IPv4")" "limited vless IPv4 display node name"

set_protocol_defaults "vless+reality"
assert_equals "test-host-vless" "${SB_NODE_NAME}" "set_protocol_defaults vless node name"

set_protocol_defaults "hy2"
assert_equals "test-host-hy2" "${SB_NODE_NAME}" "set_protocol_defaults hy2 node name"

set_protocol_defaults "anytls"
assert_equals "test-host-anytls" "${SB_NODE_NAME}" "set_protocol_defaults anytls node name"

set_protocol_defaults "mixed"
assert_equals "test-host-mixed" "${SB_NODE_NAME}" "set_protocol_defaults mixed node name"
