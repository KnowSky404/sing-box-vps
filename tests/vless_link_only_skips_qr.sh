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

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project"

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

SB_PROTOCOL="vless+reality"
SB_PORT="443"
SB_UUID="11111111-1111-1111-1111-111111111111"
SB_SNI="apple.com"
SB_PUBLIC_KEY="public-key"
SB_SHORT_ID_1="aaaaaaaaaaaaaaaa"
SB_NODE_NAME="vless_reality_test-host"

qrencode() {
  local current_count
  current_count=$(cat "${QRENCODE_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${QRENCODE_COUNT_FILE}"
}

output=$(show_connection_details "link" "203.0.113.10" 2>&1)
qrencode_calls=$(cat "${QRENCODE_COUNT_FILE}")

if (( qrencode_calls != 0 )); then
  printf 'expected link-only view to skip qrencode, got %s\n' "${qrencode_calls}" >&2
  exit 1
fi

if [[ "${output}" != *"REALITY 协议链接"* ]]; then
  printf 'expected REALITY link title in output, got: %s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"vless://"* ]]; then
  printf 'expected REALITY link in output, got: %s\n' "${output}" >&2
  exit 1
fi
