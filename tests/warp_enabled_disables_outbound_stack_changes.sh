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

SB_ENABLE_WARP="y"
SB_OUTBOUND_STACK_MODE="prefer_ipv4"

output=$(configure_outbound_stack_mode 2>&1)

if [[ "${output}" != *"当前已开启 Warp，出站协议栈设置不生效，已禁止修改。"* ]]; then
  printf 'expected warp outbound lock hint, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${SB_OUTBOUND_STACK_MODE}" != "prefer_ipv4" ]]; then
  printf 'expected outbound stack mode to remain unchanged when warp is enabled, got %s\n' "${SB_OUTBOUND_STACK_MODE}" >&2
  exit 1
fi
