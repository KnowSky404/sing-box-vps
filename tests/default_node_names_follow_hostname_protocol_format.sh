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

assert_equals "test-host+vless" "$(default_node_name_for_protocol "vless+reality")" "vless default node name"
assert_equals "test-host+hys" "$(default_node_name_for_protocol "hy2")" "hy2 default node name"
assert_equals "test-host+anytls" "$(default_node_name_for_protocol "anytls")" "anytls default node name"
assert_equals "test-host+mixed" "$(default_node_name_for_protocol "mixed")" "mixed default node name"

set_protocol_defaults "vless+reality"
assert_equals "test-host+vless" "${SB_NODE_NAME}" "set_protocol_defaults vless node name"

set_protocol_defaults "hy2"
assert_equals "test-host+hys" "${SB_NODE_NAME}" "set_protocol_defaults hy2 node name"

set_protocol_defaults "anytls"
assert_equals "test-host+anytls" "${SB_NODE_NAME}" "set_protocol_defaults anytls node name"

set_protocol_defaults "mixed"
assert_equals "test-host+mixed" "${SB_NODE_NAME}" "set_protocol_defaults mixed node name"
