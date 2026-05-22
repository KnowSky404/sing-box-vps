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

cat > "${TMP_DIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "is-active" ]]; then
  printf 'active\n'
  exit 0
fi

exit 1
EOF
chmod +x "${TMP_DIR}/bin/systemctl"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

SB_PROTOCOL="vless+reality"
SB_PORT="443"
SB_ENABLE_WARP="n"

output=$(display_status_summary "203.0.113.10")

if [[ "${output}" != *"运行状态摘要"* ]]; then
  printf 'expected runtime status heading, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"sing-box: active"* ]]; then
  printf 'expected sing-box process state, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"Warp: 未开启"* ]]; then
  printf 'expected Warp status, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" == *"协议:"* || "${output}" == *"地址:"* || "${output}" == *"端口:"* ]]; then
  printf 'expected service summary to hide protocol, address, and port details, got:\n%s\n' "${output}" >&2
  exit 1
fi
