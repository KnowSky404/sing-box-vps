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

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

GENERATE_CONFIG_COUNT_FILE="${TMP_DIR}/generate_config.count"
printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"

generate_config() {
  local current_count
  current_count=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${GENERATE_CONFIG_COUNT_FILE}"
}
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
save_warp_route_settings() { :; }
systemctl() { :; }
check_port_conflict() { :; }
load_current_config_state() {
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen_port": 8443
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=hy2
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=manual-pass-1234567890
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=y
OBFS_TYPE=salamander
OBFS_PASSWORD=manual-obfs-pass-1234567890
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

update_config_only <<'EOF'
1












EOF

if ! grep -Fq 'PASSWORD=manual-pass-1234567890' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 update to preserve manual password, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Fq 'OBFS_PASSWORD=manual-obfs-pass-1234567890' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 update to preserve manual obfs password, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected update flow to regenerate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi
