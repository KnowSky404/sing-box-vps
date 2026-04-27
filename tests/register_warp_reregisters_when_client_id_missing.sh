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

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${SB_WARP_KEY_FILE:-${TMP_DIR}/project/warp.key}" <<'EOF'
WARP_ID=legacy-id
WARP_TOKEN=legacy-token
WARP_PRIV_KEY=legacy-private
WARP_PUB_KEY=legacy-public
WARP_V4=172.16.0.2
WARP_V6=2606:4700:110:8cde:1234:5678:90ab:cdef
EOF

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

run_singbox_generate_command() {
  cat <<'EOF'
PrivateKey: 8DcUSmPINFuK1xkA1TncAJh46Ra8Mq8o42XL3b+rT2s=
PublicKey: j/gT24P0qv0p5RFqYVehc7Y88S5fDhcJ8E3HGqpCPVg=
EOF
}

curl() {
  cat <<'EOF'
{"id":"new-id","token":"new-token","config":{"client_id":"hCaJ","interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110:8cde:1234:5678:90ab:cdef"}}}}
EOF
}

register_warp

if ! grep -Fqx 'WARP_CLIENT_ID=hCaJ' "${SB_WARP_KEY_FILE}"; then
  printf 'expected register_warp to persist WARP_CLIENT_ID after legacy key refresh, got:\n%s\n' \
    "$(cat "${SB_WARP_KEY_FILE}")" >&2
  exit 1
fi

if ! grep -Fqx 'WARP_PRIV_KEY=8DcUSmPINFuK1xkA1TncAJh46Ra8Mq8o42XL3b+rT2s=' "${SB_WARP_KEY_FILE}"; then
  printf 'expected register_warp to refresh legacy warp key file, got:\n%s\n' \
    "$(cat "${SB_WARP_KEY_FILE}")" >&2
  exit 1
fi
