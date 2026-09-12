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
mkdir -p "${TMP_DIR}/lib"
printf 'old-libcronet\n' > "${TMP_DIR}/lib/libcronet.so"
sha256sum "${TMP_DIR}/lib/libcronet.so" | awk '{print $1}' > "${TMP_DIR}/project/libcronet.sha256"

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
    printf 'sing-box version 1.13.18\n'
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
  printf 'new-libcronet\n' > "$(singbox_library_path)"
  sha256sum "$(singbox_library_path)" | awk '{print $1}' > "${SB_NAIVE_LIBRARY_MARKER}"
}

SB_VERSION="1.13.18"
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected invalid target config to return non-zero\n' >&2
  exit 1
fi

if [[ "$("${SINGBOX_BIN_PATH}" marker)" != "old" ]]; then
  printf 'expected old sing-box binary to be restored when new binary rejects config\n' >&2
  exit 1
fi
if [[ "$(cat "$(singbox_library_path)")" != "old-libcronet" ]]; then
  printf 'expected old libcronet.so to be restored when new binary rejects config\n' >&2
  exit 1
fi
if [[ "$(cat "${SB_NAIVE_LIBRARY_MARKER}")" != "$(sha256sum "$(singbox_library_path)" | awk '{print $1}')" ]]; then
  printf 'expected the restored libcronet.so marker to match the old library\n' >&2
  exit 1
fi

rm -f "$(singbox_library_path)" "${SB_NAIVE_LIBRARY_MARKER}"
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected a second invalid target config to return non-zero\n' >&2
  exit 1
fi
if [[ -e "$(singbox_library_path)" || -e "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
  printf 'expected a library introduced by a failed upgrade to be removed on rollback\n' >&2
  exit 1
fi
