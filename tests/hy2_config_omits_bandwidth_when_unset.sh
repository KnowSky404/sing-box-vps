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
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

register_warp() { :; }
ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=hy2
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=443
DOMAIN=hy2.example.com
PASSWORD=hy2-password
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

SB_ADVANCED_ROUTE="n"
SB_ENABLE_WARP="n"
SB_PROTOCOL="hy2"

generate_config

if ! jq -e '.inbounds[] | select(.type == "hysteria2")' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected generated config to contain a hy2 inbound, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi

if jq -e '.inbounds[] | select(.type == "hysteria2") | has("up_mbps")' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected hy2 inbound to omit up_mbps when unset, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi

if jq -e '.inbounds[] | select(.type == "hysteria2") | has("down_mbps")' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected hy2 inbound to omit down_mbps when unset, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi
