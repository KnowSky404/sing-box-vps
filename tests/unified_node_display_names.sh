#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SBV_TEST_MODE=1
source "${REPO_ROOT}/install.sh"

assert_eq() {
  local actual=$1 expected=$2 message=$3
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

SB_NODE_NAME="hk-vps-vless"
SB_PROTOCOL="vless+reality"
SB_VLESS_RATE_LIMIT_UP_MBPS="40"
SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
assert_eq "$(display_node_name_for_protocol "vless-reality" "${SB_NODE_NAME}" "IPv6")" "hk-vps-vless-U40M-v6" "vless upload-only name"

SB_VLESS_RATE_LIMIT_UP_MBPS=""
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
assert_eq "$(display_node_name_for_protocol "vless-reality" "${SB_NODE_NAME}" "IPv4")" "hk-vps-vless-D100M-v4" "vless download-only name"

SB_VLESS_RATE_LIMIT_UP_MBPS="40"
SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
assert_eq "$(display_node_name_for_protocol "vless-reality" "${SB_NODE_NAME}" "")" "hk-vps-vless-U40M-D100M" "vless both-limits name"

SB_NODE_NAME="hk-vps-hy2"
SB_HY2_UP_MBPS="20"
SB_HY2_DOWN_MBPS="80"
assert_eq "$(display_node_name_for_protocol "hy2" "${SB_NODE_NAME}" "IPv4")" "hk-vps-hy2-U20M-D80M-v4" "hy2 bandwidth name"

SB_NODE_NAME="hk-vps-anytls"
assert_eq "$(display_node_name_for_protocol "anytls" "${SB_NODE_NAME}" "IPv6")" "hk-vps-anytls-v6" "anytls stack name"

SB_NODE_NAME="hk-vps-mixed"
assert_eq "$(display_node_name_for_protocol "mixed" "${SB_NODE_NAME}" "address")" "hk-vps-mixed" "unknown stack omitted"
