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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "check" ]]; then
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

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,reality-2
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=vless_main_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=20
RATE_LIMIT_DOWN_MBPS=100
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/reality-2.env" <<'EOF'
INSTANCE_ID=reality-2
ENABLED=1
NODE_NAME=vless_main_test-host
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=50
EOF

load_protocol_state "vless-reality"

EXPORT_STDOUT="${TMP_DIR}/stdout.txt"
EXPECTED_EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"

export_singbox_client_config > "${EXPORT_STDOUT}"

if [[ "${SB_VLESS_INSTANCE_ID}" != "main" || "${SB_NODE_NAME}" != "vless_main_test-host" || "${SB_PORT}" != "443" ]]; then
  printf 'expected client export to restore default REALITY state, got instance=%s name=%s port=%s\n' \
    "${SB_VLESS_INSTANCE_ID:-}" "${SB_NODE_NAME:-}" "${SB_PORT:-}" >&2
  exit 1
fi

if [[ ! -f "${EXPECTED_EXPORT_PATH}" ]]; then
  printf 'expected exported config file at %s, stdout was:\n%s\n' "${EXPECTED_EXPORT_PATH}" "$(cat "${EXPORT_STDOUT}")" >&2
  exit 1
fi

if [[ "$(jq '[.outbounds[] | select(.type == "vless")] | length' "${EXPECTED_EXPORT_PATH}")" != "2" ]]; then
  printf 'expected exactly two VLESS outbounds, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "selector" and .tag == "proxy") | (.outbounds | index("vless_main_test-host") != null and index("vless_main_test-host-reality-2") != null)' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected selector to include both REALITY outbound tags, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "urltest" and .tag == "auto") | (.outbounds | index("vless_main_test-host") != null and index("vless_main_test-host-reality-2") != null)' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected urltest to include both REALITY outbound tags, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "vless" and .tag == "vless_main_test-host") | .server == "203.0.113.10" and .server_port == 443 and .uuid == "11111111-1111-1111-1111-111111111111" and .tls.server_name == "apple.com" and .tls.reality.public_key == "public-key" and .tls.reality.short_id == "aaaaaaaaaaaaaaaa"' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected main REALITY outbound fields, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "vless" and .tag == "vless_main_test-host-reality-2") | .server == "203.0.113.10" and .server_port == 8443 and .uuid == "22222222-2222-2222-2222-222222222222" and .tls.server_name == "www.cloudflare.com" and .tls.reality.public_key == "public-key" and .tls.reality.short_id == "cccccccccccccccc"' "${EXPECTED_EXPORT_PATH}" >/dev/null; then
  printf 'expected second REALITY outbound fields, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if [[ "$(jq -r '[.outbounds[] | select(.type == "vless") | .tag] | length == (unique | length)' "${EXPECTED_EXPORT_PATH}")" != "true" ]]; then
  printf 'expected VLESS outbound tags to be unique, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

rm -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/"*.env
rm -f "${EXPECTED_EXPORT_PATH}"

if export_singbox_client_config > "${TMP_DIR}/empty-stdout.txt" 2> "${TMP_DIR}/empty-stderr.txt"; then
  printf 'expected client export with zero REALITY instances to fail clearly\nstdout:\n%s\nstderr:\n%s\n' \
    "$(cat "${TMP_DIR}/empty-stdout.txt")" "$(cat "${TMP_DIR}/empty-stderr.txt")" >&2
  exit 1
fi

if [[ -f "${EXPECTED_EXPORT_PATH}" ]]; then
  printf 'expected zero-instance REALITY export not to write a client config, got:\n%s\n' "$(cat "${EXPECTED_EXPORT_PATH}")" >&2
  exit 1
fi

if ! grep -Fq '未找到可用的 VLESS + REALITY 实例' "${TMP_DIR}/empty-stderr.txt"; then
  printf 'expected zero-instance REALITY export to explain missing instances, got stderr:\n%s\n' "$(cat "${TMP_DIR}/empty-stderr.txt")" >&2
  exit 1
fi
