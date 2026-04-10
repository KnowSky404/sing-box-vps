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

SB_PROTOCOL="vless+reality"
SB_INBOUND_STACK_MODE="dual_stack"
SB_PORT="443"
SB_UUID="11111111-1111-1111-1111-111111111111"
SB_SNI="apple.com"
SB_PUBLIC_KEY="public-key"
SB_SHORT_ID_1="aaaaaaaaaaaaaaaa"
SB_NODE_NAME="vless_reality_test-host"

get_public_ipv4() {
  printf '203.0.113.10\n'
}

get_public_ipv6() {
  printf '2001:db8::10\n'
}

detect_host_ip_stack() {
  printf 'dual\n'
}

output=$(show_connection_details_for_detected_addresses "link" 2>&1)

if [[ "${output}" != *"IPv4 地址"* ]]; then
  printf 'expected IPv4 node info label in dual-stack output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"IPv6 地址"* ]]; then
  printf 'expected IPv6 node info label in dual-stack output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"203.0.113.10"* ]]; then
  printf 'expected IPv4 address in output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"2001:db8::10"* ]]; then
  printf 'expected IPv6 address in output, got:\n%s\n' "${output}" >&2
  exit 1
fi
