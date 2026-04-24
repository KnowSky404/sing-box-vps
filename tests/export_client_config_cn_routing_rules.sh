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

if ! grep -Fq "readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"" "${TESTABLE_INSTALL}"; then
  printf 'failed to rewrite SB_PROJECT_DIR in %s\n' "${TESTABLE_INSTALL}" >&2
  exit 1
fi

if ! grep -Fq "readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"" "${TESTABLE_INSTALL}"; then
  printf 'failed to rewrite SINGBOX_BIN_PATH in %s\n' "${TESTABLE_INSTALL}" >&2
  exit 1
fi

if ! grep -Fq "readonly SBV_BIN_PATH=\"${TMP_DIR}/bin/sbv\"" "${TESTABLE_INSTALL}"; then
  printf 'failed to rewrite SBV_BIN_PATH in %s\n' "${TESTABLE_INSTALL}" >&2
  exit 1
fi

if ! grep -Fq "readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"" "${TESTABLE_INSTALL}"; then
  printf 'failed to rewrite SINGBOX_SERVICE_FILE in %s\n' "${TESTABLE_INSTALL}" >&2
  exit 1
fi

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
export_singbox_client_config >/dev/null

EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"

if ! jq -e '.dns.servers[] | select(.tag == "cn-dns" and .type == "https" and .server == "223.5.5.5" and .server_port == 443 and .path == "/dns-query")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected cn-dns https://223.5.5.5:443/dns-query, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.dns.servers[] | select(.tag == "remote-dns" and .type == "https" and .server == "1.1.1.1" and .server_port == 443 and .path == "/dns-query")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected remote-dns https://1.1.1.1:443/dns-query, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.dns.final == "remote-dns"' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected dns.final remote-dns, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.final == "proxy"' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected route.final proxy, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.rule_set[] | select(.tag == "geoip-cn")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rule_set geoip-cn, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.rule_set[] | select(.tag == "geosite-geolocation-cn")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rule_set geosite-geolocation-cn, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.dns.rules[] | select(.rule_set == "geosite-geolocation-cn" and .server == "cn-dns")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected dns.rules geosite-geolocation-cn -> cn-dns, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.rules[] | select(.rule_set == "geosite-geolocation-cn" and .outbound == "direct" and .action == "route")' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rules geosite-geolocation-cn -> direct, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.route.default_domain_resolver == "remote-dns"' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected route.default_domain_resolver remote-dns, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.inbounds[] | select(.type == "mixed" and .set_system_proxy == false)' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected mixed inbound set_system_proxy false, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi
