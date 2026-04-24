#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

perl -0pe '
  s/^\s*main "\$@"\s*$//m;
  s|readonly SB_PROJECT_DIR="/root/sing-box-vps"|readonly SB_PROJECT_DIR="'"${TMP_DIR}"'/project"|;
  s|readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"|readonly SINGBOX_BIN_PATH="'"${TMP_DIR}"'/bin/sing-box"|;
  s|readonly SBV_BIN_PATH="/usr/local/bin/sbv"|readonly SBV_BIN_PATH="'"${TMP_DIR}"'/bin/sbv"|;
  s|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|readonly SINGBOX_SERVICE_FILE="'"${TMP_DIR}"'/sing-box.service"|;
' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() {
  printf '203.0.113.10\n'
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
PORT=65123
DOMAIN=hy2.example.com
PASSWORD=hy2-password
USER_NAME=hy2-user
UP_MBPS=
DOWN_MBPS=
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
TLS_MODE=acme
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=hy2.example.com
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=
KEY_PATH=
MASQUERADE=https://example.com
EOF

load_protocol_state "hy2"
export_singbox_client_config >/dev/null

EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"

if ! jq -e '.outbounds[] | select(.type == "hysteria2" and .tag == "hy2-65123") | .server == "203.0.113.10"' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected exported hy2 outbound server to use detected public IP, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "hysteria2" and .tag == "hy2-65123") | .tls.server_name == "hy2.example.com"' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected exported hy2 outbound tls.server_name to keep configured domain, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi
