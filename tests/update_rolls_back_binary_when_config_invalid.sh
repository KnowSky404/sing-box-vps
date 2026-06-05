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
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.5\n'
    ;;
  check)
    exit 0
    ;;
  marker)
    printf 'old\n'
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_os_info() { OS_NAME=debian; }
get_arch() { ARCH=amd64; }
install_dependencies() { :; }
load_current_config_state() { :; }
setup_service() { :; }
display_status_summary() { :; }
systemctl() {
  if [[ "${1:-}" == "restart" ]]; then
    printf 'unexpected restart after invalid config\n' >&2
    exit 1
  fi
}
install_binary() {
  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.13\n'
    ;;
  check)
    exit 1
    ;;
  marker)
    printf 'new\n'
    ;;
esac
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}

SB_VERSION="1.13.13"
update_singbox_binary_preserving_config >/dev/null

if [[ "$("${SINGBOX_BIN_PATH}" marker)" != "old" ]]; then
  printf 'expected old sing-box binary to be restored when new binary rejects config\n' >&2
  exit 1
fi
