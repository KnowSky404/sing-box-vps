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

SB_NODE_NAME="hk-vps+hy2"
assert_eq "$(display_node_name_for_protocol "hy2" "${SB_NODE_NAME}" "IPv4")" "hk-vps-hy2-U20M-D80M-v4" "legacy hy2 plus name normalized"

SB_NODE_NAME="hk-vps-anytls"
assert_eq "$(display_node_name_for_protocol "anytls" "${SB_NODE_NAME}" "IPv6")" "hk-vps-anytls-v6" "anytls stack name"

SB_NODE_NAME="hk-vps-mixed"
assert_eq "$(display_node_name_for_protocol "mixed" "${SB_NODE_NAME}" "address")" "hk-vps-mixed" "unknown stack omitted"

SB_PROTOCOL="hy2"
SB_NODE_NAME="hk-vps-hy2"
SB_PORT="8443"
SB_HY2_PASSWORD="secret"
SB_HY2_DOMAIN=""
SB_HY2_OBFS_ENABLED="n"
SB_HY2_OBFS_TYPE=""
SB_HY2_OBFS_PASSWORD=""
SB_HY2_UP_MBPS="20"
SB_HY2_DOWN_MBPS="80"
hy2_link=$(build_hy2_link "203.0.113.10" "IPv4")
if [[ "${hy2_link}" != *"#hk-vps-hy2-U20M-D80M-v4" ]]; then
  printf 'FAIL: hy2 link did not use unified display name: %s\n' "${hy2_link}" >&2
  exit 1
fi

hy2_outbound=$(build_client_hy2_outbound "203.0.113.10")
assert_eq "$(jq -r '.tag' <<< "${hy2_outbound}")" "hk-vps-hy2-U20M-D80M" "hy2 client tag"

SB_PROTOCOL="anytls"
SB_NODE_NAME="hk-vps-anytls"
SB_PORT="9443"
SB_ANYTLS_PASSWORD="secret"
SB_ANYTLS_DOMAIN=""
anytls_outbound=$(build_client_anytls_outbound "203.0.113.10")
assert_eq "$(jq -r '.tag' <<< "${anytls_outbound}")" "hk-vps-anytls" "anytls client tag"

SUBMAN_NODE_PREFIX="hk-vps"
SB_PROTOCOL="hy2"
SB_NODE_NAME="hk-vps-hy2"
SB_PORT="8443"
SB_HY2_PASSWORD="secret"
SB_HY2_UP_MBPS="20"
SB_HY2_DOWN_MBPS="80"
subman_payload=$(build_subman_node_payload "hy2" "203.0.113.10" "IPv4")
assert_eq "$(jq -r '.name' <<< "${subman_payload}")" "hk-vps-hy2-U20M-D80M-v4" "subman payload name"

agent_links=$(agent_link_json_for_current_protocol "203.0.113.10")
assert_eq "$(jq -r '.name' <<< "${agent_links}")" "hk-vps-hy2-U20M-D80M-v4" "agent link name"
