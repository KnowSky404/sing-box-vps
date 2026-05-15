#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

GENERATE_CONFIG_COUNT_FILE="${TMP_DIR}/generate_config.count"
printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"

generate_config() {
  local current_count
  current_count=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${GENERATE_CONFIG_COUNT_FILE}"
}

check_config_valid() { :; }
validate_config_file() { :; }
setup_service() { :; }
open_all_protocol_ports() { :; }
display_status_summary() { :; }
systemctl() { :; }
load_current_config_state() {
  SB_PROTOCOL="vless+reality"
  SB_PORT="443"
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="selective"
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    { "type": "vless", "tag": "vless-in", "listen_port": 443 },
    { "type": "hysteria2", "tag": "hy2-in", "listen_port": 8443 }
  ],
  "route": { "rules": [] }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
EOF

cat > "$(protocol_state_file vless-reality)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

cat > "$(protocol_state_file hy2)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=old-pass
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=
EOF

if ! REMOVE_OUTPUT=$(printf '2\ny\n' | remove_protocol_menu 2>&1); then
  printf 'expected remove_protocol_menu to succeed, got:\n%s\n' "${REMOVE_OUTPUT}" >&2
  exit 1
fi

if [[ -f "$(protocol_state_file hy2)" ]]; then
  printf 'expected selected hy2 state file to be removed, got:\n%s\n' "$(cat "$(protocol_state_file hy2)")" >&2
  exit 1
fi

if [[ ! -f "$(protocol_state_file vless-reality)" ]]; then
  printf 'expected unselected vless state file to remain\n' >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=vless-reality' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to keep only vless-reality, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi

if ! compgen -G "$(protocol_state_file hy2).bak.*" >/dev/null; then
  printf 'expected removed protocol state backup next to original state file\n' >&2
  exit 1
fi

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected remove flow to regenerate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi

if ! REMOVE_LAST_OUTPUT=$(printf '1\ny\n' | remove_protocol_menu 2>&1); then
  printf 'expected last-protocol remove attempt to return without shell failure, got:\n%s\n' "${REMOVE_LAST_OUTPUT}" >&2
  exit 1
fi

REMOVE_LAST_PLAIN_OUTPUT=$(strip_ansi "${REMOVE_LAST_OUTPUT}")
if [[ "${REMOVE_LAST_PLAIN_OUTPUT}" != *"至少保留一个协议"* ]]; then
  printf 'expected last-protocol removal to be rejected, got:\n%s\n' "${REMOVE_LAST_OUTPUT}" >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=vless-reality' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to remain unchanged after rejected last-protocol removal, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi
