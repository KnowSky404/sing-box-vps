#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

SUBMAN_NODE_PREFIX="edge-1"

SB_PROTOCOL="vless+reality"
SB_NODE_NAME="edge-1 vless"
SB_PORT="443"
SB_UUID="11111111-1111-1111-1111-111111111111"
SB_SNI="www.cloudflare.com"
SB_PUBLIC_KEY="public-key"
SB_SHORT_ID_1="abcd1234"

if [[ "$(subman_type_for_protocol "vless-reality")" != "vless" ]]; then
  printf 'expected vless-reality to map to vless\n' >&2
  exit 1
fi

vless_payload=$(build_subman_node_payload "vless-reality" "203.0.113.10")
if [[ "$(jq -r '.type' <<< "${vless_payload}")" != "vless" ]]; then
  printf 'expected vless payload type\n%s\n' "${vless_payload}" >&2
  exit 1
fi
if [[ "$(jq -r '.raw' <<< "${vless_payload}")" != vless://* ]]; then
  printf 'expected vless raw link\n%s\n' "${vless_payload}" >&2
  exit 1
fi
if [[ "$(jq -r '.enabled' <<< "${vless_payload}")" != "true" ]]; then
  printf 'expected enabled true\n%s\n' "${vless_payload}" >&2
  exit 1
fi
if ! jq -e '.tags | index("sing-box-vps") and index("edge-1")' <<< "${vless_payload}" >/dev/null; then
  printf 'expected sing-box-vps and prefix tags\n%s\n' "${vless_payload}" >&2
  exit 1
fi

SB_PROTOCOL="hy2"
SB_NODE_NAME="edge-1 hy2"
SB_PORT="8443"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="hy2-password"
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE="salamander"
SB_HY2_OBFS_PASSWORD="obfs-password"

if [[ "$(subman_type_for_protocol "hy2")" != "hysteria2" ]]; then
  printf 'expected hy2 to map to hysteria2\n' >&2
  exit 1
fi

hy2_payload=$(build_subman_node_payload "hy2" "203.0.113.10")
if [[ "$(jq -r '.type' <<< "${hy2_payload}")" != "hysteria2" ]]; then
  printf 'expected hysteria2 payload type\n%s\n' "${hy2_payload}" >&2
  exit 1
fi
if [[ "$(jq -r '.raw' <<< "${hy2_payload}")" != hy2://* ]]; then
  printf 'expected hy2 raw link\n%s\n' "${hy2_payload}" >&2
  exit 1
fi

if subman_type_for_protocol "mixed" >/dev/null; then
  printf 'expected mixed to be unsupported for SubMan sync\n' >&2
  exit 1
fi

if [[ "$(subman_external_key_for_protocol "hy2")" != "sing-box-vps:edge-1:hy2" ]]; then
  printf 'expected stable hy2 external key\n' >&2
  exit 1
fi
