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

if [[ "${1:-}" == "generate" && "${2:-}" == "reality-keypair" ]]; then
  printf 'PrivateKey: private-key\n'
  printf 'PublicKey: public-key\n'
  exit 0
fi

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
INSTALLED_PROTOCOLS=vless-reality,hy2,anytls
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
PASSWORD=hy2-password
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=y
OBFS_TYPE=salamander
OBFS_PASSWORD=obfs-pass
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=https://example.com
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

load_protocol_state "vless-reality"

EXPORT_STDOUT="${TMP_DIR}/stdout.txt"
EXPECTED_EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"
declare -a matching_files=()

export_singbox_client_config > "${EXPORT_STDOUT}"

mapfile -t matching_files < <(find "${SB_PROJECT_DIR}" -type f -name 'sing-box-client.json' 2>/dev/null | sort)

if [[ ${#matching_files[@]} -ne 1 || "${matching_files[0]:-}" != "${EXPECTED_EXPORT_PATH}" ]]; then
  printf 'expected exported sing-box-client.json path %s, actual matches:\n' "${EXPECTED_EXPORT_PATH}" >&2
  if [[ ${#matching_files[@]} -eq 0 ]]; then
    printf '(none)\n' >&2
  else
    printf '%s\n' "${matching_files[@]}" >&2
  fi
  printf 'stdout was:\n%s\n' "$(cat "${EXPORT_STDOUT}")" >&2
  exit 1
fi

if [[ ! -f "${EXPECTED_EXPORT_PATH}" ]]; then
  printf 'expected exported config file at %s, stdout was:\n%s\n' "${EXPECTED_EXPORT_PATH}" "$(cat "${EXPORT_STDOUT}")" >&2
  exit 1
fi

if ! jq -e '.inbounds[] | select(.type == "mixed") | .listen == "127.0.0.1" and .listen_port == 2080' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected local mixed inbound 127.0.0.1:2080, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "selector" and .tag == "proxy") | .default == "auto"' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected selector outbound proxy default auto, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "urltest" and .tag == "auto")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected urltest outbound auto, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "vless" and .tag == "vless-reality-443")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected vless outbound tag vless-reality-443, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "hysteria2" and .tag == "hy2-8443") | .obfs.type == "salamander"' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected hysteria2 outbound hy2-8443 with salamander obfs, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "anytls" and .tag == "anytls-9443")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected anytls outbound tag anytls-9443, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.experimental.clash_api.external_controller == "127.0.0.1:9090"' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected clash_api external_controller 127.0.0.1:9090, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '(.route.rule_set // [])[] | select(.tag == "geoip-cn" and .type == "remote" and .format == "binary" and .url == "https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/srs/cn.srs")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rule_set geoip-cn with jsdelivr cn.srs URL, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '(.route.rule_set // [])[] | select(.tag == "geosite-cn")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rule_set geosite-cn, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '(.route.rules // [])[] | select(.rule_set? == "geosite-cn" and .outbound == "direct" and .action == "route")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rules geosite-cn -> direct with action route, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '(.route.rules // [])[] | select(.rule_set? == "geoip-cn" and .outbound == "direct" and .action == "route")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected route.rules geoip-cn -> direct with action route, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '(.dns.rules // [])[] | select(.rule_set? == "geosite-cn" and .server == "cn-dns")' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected dns.rules geosite-cn -> cn-dns, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi
