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

SB_INBOUND_STACK_MODE="dual_stack"

detect_host_ip_stack() {
  printf 'dual\n'
}

dual_output=$(configure_inbound_stack_mode <<'EOF'
0
EOF
)

if [[ "${dual_output}" != *"1. 仅 IPv4"* ]]; then
  printf 'expected ipv4-only option for dual-stack host, got:\n%s\n' "${dual_output}" >&2
  exit 1
fi

if [[ "${dual_output}" != *"2. 仅 IPv6"* ]]; then
  printf 'expected ipv6-only option for dual-stack host, got:\n%s\n' "${dual_output}" >&2
  exit 1
fi

if [[ "${dual_output}" != *"3. 双栈"* ]]; then
  printf 'expected dual-stack option for dual-stack host, got:\n%s\n' "${dual_output}" >&2
  exit 1
fi

detect_host_ip_stack() {
  printf 'ipv4\n'
}

ipv4_output=$(configure_inbound_stack_mode <<'EOF'
0
EOF
)

if [[ "${ipv4_output}" != *"1. 仅 IPv4"* ]]; then
  printf 'expected ipv4-only option for ipv4 host, got:\n%s\n' "${ipv4_output}" >&2
  exit 1
fi

if [[ "${ipv4_output}" == *"仅 IPv6"* || "${ipv4_output}" == *"双栈"* ]]; then
  printf 'expected ipv4-only host to hide unsupported options, got:\n%s\n' "${ipv4_output}" >&2
  exit 1
fi
