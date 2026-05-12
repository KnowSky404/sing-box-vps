#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

ensure_protocol_state_dir
write_protocol_index "vless-reality,mixed,hy2,anytls"

cat > "$(protocol_state_file vless-reality)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-vless'
PORT=443
UUID='11111111-1111-1111-1111-111111111111'
SNI='www.cloudflare.com'
REALITY_PRIVATE_KEY='private-key'
REALITY_PUBLIC_KEY='public-key'
SHORT_ID_1='abcd1234'
SHORT_ID_2='dcba4321'
EOF

cat > "$(protocol_state_file mixed)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-mixed'
PORT=2080
AUTH_ENABLED='y'
USERNAME='mixed-user'
PASSWORD='mixed-pass'
EOF

cat > "$(protocol_state_file hy2)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-hy2'
PORT=8443
DOMAIN='hy2.example.com'
PASSWORD='hy2-password'
USER_NAME='hy2-user'
UP_MBPS=''
DOWN_MBPS=''
OBFS_ENABLED='y'
OBFS_TYPE='salamander'
OBFS_PASSWORD='obfs-password'
TLS_MODE='self-signed'
ACME_MODE=''
ACME_EMAIL=''
ACME_DOMAIN=''
DNS_PROVIDER=''
CF_API_TOKEN=''
CERT_PATH=''
KEY_PATH=''
MASQUERADE='https://bing.com'
EOF

cat > "$(protocol_state_file anytls)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-anytls'
PORT=9443
DOMAIN='anytls.example.com'
PASSWORD='anytls-password'
USER_NAME='anytls-user'
TLS_MODE='self-signed'
ACME_MODE=''
ACME_EMAIL=''
ACME_DOMAIN=''
DNS_PROVIDER=''
CF_API_TOKEN=''
CERT_PATH=''
KEY_PATH=''
EOF

load_protocol_state "mixed"

prompt_subman_config_if_needed() {
  SUBMAN_API_URL="https://subman.example.com"
  SUBMAN_API_TOKEN="secret-token"
  SUBMAN_NODE_PREFIX="edge-1"
}

get_public_ip() {
  printf '203.0.113.10\n'
}

PUSH_KEYS_FILE="${TMP_DIR}/subman-push-keys.txt"
PUSH_PAYLOADS_FILE="${TMP_DIR}/subman-push-payloads.jsonl"
push_subman_node() {
  local external_key=$1
  local payload_json=$2

  printf '%s\n' "${external_key}" >> "${PUSH_KEYS_FILE}"
  printf '%s\n' "${payload_json}" >> "${PUSH_PAYLOADS_FILE}"
}

output=$(push_nodes_to_subman 2>&1)

if [[ "${output}" != *"SubMan 推送完成：已同步: 2，已跳过: 2，失败: 0"* ]]; then
  printf 'expected push summary for 2 synced, 2 skipped, 0 failed, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "$(wc -l < "${PUSH_KEYS_FILE}")" -ne 2 ]]; then
  printf 'expected exactly 2 pushed nodes, got keys:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if ! grep -Fxq "sing-box-vps:edge-1:vless-reality" "${PUSH_KEYS_FILE}"; then
  printf 'expected vless-reality external key, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if ! grep -Fxq "sing-box-vps:edge-1:hy2" "${PUSH_KEYS_FILE}"; then
  printf 'expected hy2 external key, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if grep -Eq "mixed|anytls" "${PUSH_KEYS_FILE}"; then
  printf 'expected mixed and anytls not to be pushed, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if [[ "$(jq -r 'select(.type == "vless") | .raw' "${PUSH_PAYLOADS_FILE}")" != vless://* ]]; then
  printf 'expected vless payload raw link, got:\n%s\n' "$(cat "${PUSH_PAYLOADS_FILE}")" >&2
  exit 1
fi

if [[ "$(jq -r 'select(.type == "hysteria2") | .raw' "${PUSH_PAYLOADS_FILE}")" != hy2://* ]]; then
  printf 'expected hy2 payload raw link, got:\n%s\n' "$(cat "${PUSH_PAYLOADS_FILE}")" >&2
  exit 1
fi

if [[ "${SB_PROTOCOL}" != "mixed" || "${SB_NODE_NAME}" != "edge-mixed" ]]; then
  printf 'expected original protocol state to be restored, got protocol=%s node=%s\n' "${SB_PROTOCOL}" "${SB_NODE_NAME}" >&2
  exit 1
fi
