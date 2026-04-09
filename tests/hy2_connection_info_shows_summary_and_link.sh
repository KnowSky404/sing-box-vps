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

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

QRENCODE_COUNT_FILE="${TMP_DIR}/qrencode.count"
printf '0\n' > "${QRENCODE_COUNT_FILE}"

SB_PROTOCOL="hy2"
SB_NODE_NAME="hy2_test-host"
SB_PORT="8443"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="hy2-password"
SB_HY2_USER_NAME="hy2-user"
SB_HY2_UP_MBPS="100"
SB_HY2_DOWN_MBPS="50"
SB_HY2_OBFS_ENABLED="y"
SB_HY2_OBFS_TYPE="salamander"
SB_HY2_OBFS_PASSWORD="obfs-pass"
SB_HY2_TLS_MODE="manual"

qrencode() {
  local current_count
  current_count=$(cat "${QRENCODE_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${QRENCODE_COUNT_FILE}"
}

output=$(show_connection_details "both" "203.0.113.10" 2>&1)

if [[ "${output}" != *"Hysteria2 协议链接"* ]]; then
  printf 'expected hy2 link title in output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"域名: hy2.example.com"* ]]; then
  printf 'expected hy2 summary to include domain, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"hy2://"* ]]; then
  printf 'expected hy2 share link in output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "$(cat "${QRENCODE_COUNT_FILE}")" != "1" ]]; then
  printf 'expected hy2 QR path to call qrencode exactly once, got %s\n' "$(cat "${QRENCODE_COUNT_FILE}")" >&2
  exit 1
fi
