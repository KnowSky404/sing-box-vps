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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/qrencode" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "-t" && "${2:-}" == "ansiutf8" ]]; then
  printf 'QR:%s\n' "${3:-}"
else
  exit 1
fi
EOF
chmod +x "${TMP_DIR}/bin/qrencode"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ipv4() {
  printf '203.0.113.10\n'
}

get_public_ipv6() {
  return 0
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
NODE_NAME=vless_second_test-host
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=50
EOF

load_protocol_state "vless-reality"

OUTPUT_FILE="${TMP_DIR}/node-info.txt"
show_all_connection_details "both" > "${OUTPUT_FILE}"

if [[ "${SB_VLESS_INSTANCE_ID}" != "main" || "${SB_NODE_NAME}" != "vless_main_test-host" || "${SB_PORT}" != "443" ]]; then
  printf 'expected node info rendering to restore default REALITY state, got instance=%s name=%s port=%s\n' \
    "${SB_VLESS_INSTANCE_ID:-}" "${SB_NODE_NAME:-}" "${SB_PORT:-}" >&2
  exit 1
fi

if ! grep -Fq '实例 ID: main' "${OUTPUT_FILE}"; then
  printf 'expected node info to include main instance ID, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq '实例 ID: reality-2' "${OUTPUT_FILE}"; then
  printf 'expected node info to include second instance ID, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq '端口: 443' "${OUTPUT_FILE}" || ! grep -Fq '端口: 8443' "${OUTPUT_FILE}"; then
  printf 'expected node info to include both REALITY ports, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq '限速: 上行 20 Mbps / 下行 100 Mbps' "${OUTPUT_FILE}"; then
  printf 'expected node info to include main rate summary, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq '限速: 上行不限 / 下行 50 Mbps' "${OUTPUT_FILE}"; then
  printf 'expected node info to include second rate summary, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq 'vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=reality&sni=apple.com&fp=chrome&pbk=public-key&sid=aaaaaaaaaaaaaaaa&flow=xtls-rprx-vision#vless_main_test-host-v4' "${OUTPUT_FILE}"; then
  printf 'expected node info to include main REALITY link, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq 'vless://22222222-2222-2222-2222-222222222222@203.0.113.10:8443?security=reality&sni=www.cloudflare.com&fp=chrome&pbk=public-key&sid=cccccccccccccccc&flow=xtls-rprx-vision#vless_second_test-host-v4' "${OUTPUT_FILE}"; then
  printf 'expected node info to include second REALITY link, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq 'QR:vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443' "${OUTPUT_FILE}"; then
  printf 'expected node info to render main REALITY QR, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi

if ! grep -Fq 'QR:vless://22222222-2222-2222-2222-222222222222@203.0.113.10:8443' "${OUTPUT_FILE}"; then
  printf 'expected node info to render second REALITY QR, got:\n%s\n' "$(cat "${OUTPUT_FILE}")" >&2
  exit 1
fi
