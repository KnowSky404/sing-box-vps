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

setup_service() { :; }
open_all_protocol_ports() { :; }
systemctl() { :; }
validate_config_file() { return 0; }
check_config_valid() { :; }
refresh_vless_reality_qos_rules() { printf 'qos refreshed\n' > "${TMP_DIR}/qos.called"; }
register_warp() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}
load_current_config_state() {
  SB_PROTOCOL="vless+reality"
  SB_PORT="443"
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="selective"
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    { "type": "vless", "tag": "vless-in", "listen_port": 443 },
    { "type": "vless", "tag": "vless-reality-limited-10m", "listen_port": 8443 },
    { "type": "hysteria2", "tag": "hy2-in", "listen_port": 9443 }
  ],
  "route": { "rules": [] }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" <<'EOF'
INSTANCE_ID=limited-10m
ENABLED=1
NODE_NAME=limited-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=10
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2-node
PORT=9443
DOMAIN=hy2.example.com
PASSWORD=hy2-pass
USER_NAME=hy2-user
UP_MBPS=
DOWN_MBPS=
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

if ! REMOVE_OUTPUT=$(remove_protocol_menu 2>&1 <<'EOF'
1
2
y
EOF
); then
  printf 'expected remove_protocol_menu to succeed, got:\n%s\n' "${REMOVE_OUTPUT}" >&2
  exit 1
fi

if [[ -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" ]]; then
  printf 'expected limited instance to be removed\n' >&2
  exit 1
fi

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" ]]; then
  printf 'expected remaining main instance to stay installed\n' >&2
  exit 1
fi

if ! compgen -G "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env.bak.*" >/dev/null; then
  printf 'expected removed instance state backup next to original state file\n' >&2
  exit 1
fi

grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'DEFAULT_INSTANCE_ID=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTALLED_PROTOCOLS=vless-reality,hy2' "${SB_PROTOCOL_INDEX_FILE}"
test -f "${TMP_DIR}/qos.called"

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected remove flow to regenerate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,backup-node
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/backup-node.env" <<'EOF'
INSTANCE_ID=backup-node
ENABLED=1
NODE_NAME=backup-node
PORT=8444
UUID=33333333-3333-3333-3333-333333333333
SNI=www.microsoft.com
SHORT_ID_1=eeeeeeeeeeeeeeee
SHORT_ID_2=ffffffffffffffff
RATE_LIMIT_UP_MBPS=5
RATE_LIMIT_DOWN_MBPS=
EOF

rm -f "${TMP_DIR}/qos.called"

if ! REMOVE_ONLY_REALITY_OUTPUT=$(remove_protocol_menu 2>&1 <<'EOF'
1
2
y
EOF
); then
  printf 'expected remove_protocol_menu to remove an instance when vless-reality is the only protocol, got:\n%s\n' "${REMOVE_ONLY_REALITY_OUTPUT}" >&2
  exit 1
fi

if [[ -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/backup-node.env" ]]; then
  printf 'expected backup-node instance to be removed even when vless-reality is the only protocol\n' >&2
  exit 1
fi

grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTALLED_PROTOCOLS=vless-reality' "${SB_PROTOCOL_INDEX_FILE}"
test -f "${TMP_DIR}/qos.called"
