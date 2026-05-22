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
  printf 'inactive\n'
  exit 3
fi

exit 1
EOF
chmod +x "${TMP_DIR}/bin/systemctl"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

output=$(main_menu_service_status_summary)

if [[ "${output}" != "inactive / 未读取到配置" ]]; then
  printf 'expected missing config status, got: %s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" == *"Warp 未开启"* ]]; then
  printf 'expected missing config status not to imply Warp is configured, got: %s\n' "${output}" >&2
  exit 1
fi
