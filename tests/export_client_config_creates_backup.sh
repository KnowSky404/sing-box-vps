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
INSTALLED_PROTOCOLS=anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls_test-host
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-password
USER_NAME=anytls-user
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/anytls.pem
KEY_PATH=/etc/ssl/private/anytls.key
EOF

load_protocol_state "anytls"

EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"
BACKUP_PATH="${EXPORT_PATH}.bak"
mkdir -p "$(dirname "${EXPORT_PATH}")"
printf '%s\n' '{"legacy":true,"tag":"old-config"}' > "${EXPORT_PATH}"

export_singbox_client_config >/dev/null

if [[ ! -f "${BACKUP_PATH}" ]]; then
  printf 'expected backup file at %s\n' "${BACKUP_PATH}" >&2
  exit 1
fi

if ! grep -Fq '"legacy":true' "${BACKUP_PATH}"; then
  printf 'expected backup to preserve old content, got:\n%s\n' "$(cat "${BACKUP_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "anytls" and .tag == "anytls-9443")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected new export to contain anytls outbound, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi
