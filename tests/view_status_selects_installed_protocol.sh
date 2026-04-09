#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

SUMMARY_COUNT_FILE="${TMP_DIR}/summary.count"
SHOW_INFO_PROTOCOL_FILE="${TMP_DIR}/show_info.protocol"
printf '0\n' > "${SUMMARY_COUNT_FILE}"

display_status_summary() {
  local current_count
  current_count=$(cat "${SUMMARY_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${SUMMARY_COUNT_FILE}"
}

show_connection_info_menu() {
  printf '%s\n' "${SB_PROTOCOL}" > "${SHOW_INFO_PROTOCOL_FILE}"
}

load_current_config_state() {
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
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

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=hy2-pass
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

view_status_and_info <<'EOF'
2
EOF

if [[ "$(cat "${SUMMARY_COUNT_FILE}")" != "1" ]]; then
  printf 'expected status summary to render once, got %s\n' "$(cat "${SUMMARY_COUNT_FILE}")" >&2
  exit 1
fi

if [[ ! -f "${SHOW_INFO_PROTOCOL_FILE}" ]]; then
  printf 'expected connection info menu to be shown for the selected protocol\n' >&2
  exit 1
fi

if [[ "$(cat "${SHOW_INFO_PROTOCOL_FILE}")" != "hy2" ]]; then
  printf 'expected selected protocol to be hy2, got %s\n' "$(cat "${SHOW_INFO_PROTOCOL_FILE}")" >&2
  exit 1
fi
