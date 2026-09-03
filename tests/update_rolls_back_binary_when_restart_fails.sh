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
    printf 'sing-box version 1.13.18\n'
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

RESTART_COUNT=0
SERVICE_STATE=active
RECOVERY_RESTART_FAIL=n
RECOVERY_RESTART_EXIT_ZERO_INACTIVE=n
TARGET_RESTART_EXIT_ZERO=n
INSTALL_BINARY_VERSION=1.14.0

get_os_info() { OS_NAME=debian; }
get_arch() { ARCH=amd64; }
install_dependencies() { :; }
get_latest_version() { :; }
display_status_summary() { :; }
systemctl() {
  if [[ "${1:-}" == "is-active" ]]; then
    printf '%s\n' "${SERVICE_STATE}"
    [[ "${SERVICE_STATE}" == "active" ]]
  fi

  if [[ "${1:-}" == "restart" && "${2:-}" == "sing-box" ]]; then
    RESTART_COUNT=$((RESTART_COUNT + 1))
    if (( RESTART_COUNT == 1 )); then
      SERVICE_STATE=inactive
      if [[ "${TARGET_RESTART_EXIT_ZERO}" == "y" ]]; then
        return 0
      fi
      return 1
    fi
    if [[ "${RECOVERY_RESTART_FAIL}" == "y" ]]; then
      SERVICE_STATE=inactive
      return 1
    fi
    if [[ "${RECOVERY_RESTART_EXIT_ZERO_INACTIVE}" == "y" ]]; then
      SERVICE_STATE=inactive
      return 0
    fi
    SERVICE_STATE=active
    return 0
  fi

  if [[ "${1:-}" == "stop" && "${2:-}" == "sing-box" ]]; then
    SERVICE_STATE=inactive
    return 0
  fi
}
install_binary() {
  cat > "${SINGBOX_BIN_PATH}" <<EOF
#!/usr/bin/env bash

case "\${1:-}" in
  version)
    printf 'sing-box version ${INSTALL_BINARY_VERSION}\n'
    ;;
  check)
    exit 0
    ;;
  marker)
    printf 'new\n'
    ;;
esac
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}

SB_VERSION="1.14.0"
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected restart failure to return non-zero\n' >&2
  exit 1
fi

if [[ "$("${SINGBOX_BIN_PATH}" marker)" != "old" ]]; then
  printf 'expected old sing-box binary to be restored after restart failure\n' >&2
  exit 1
fi

if (( RESTART_COUNT != 2 )); then
  printf 'expected one failed target restart and one restored-binary restart, got %s\n' "${RESTART_COUNT}" >&2
  exit 1
fi
if [[ "${SERVICE_STATE}" != "active" ]]; then
  printf 'expected active service state to be restored, got %s\n' "${SERVICE_STATE}" >&2
  exit 1
fi

# An originally inactive service must remain inactive after a failed upgrade.
SERVICE_STATE=inactive
RECOVERY_RESTART_FAIL=n
RESTART_COUNT=0
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected inactive-service restart failure to return non-zero\n' >&2
  exit 1
fi
if [[ "$(${SINGBOX_BIN_PATH} marker)" != "old" || "${SERVICE_STATE}" != "inactive" ]]; then
  printf 'expected old binary and inactive service state to be restored\n' >&2
  exit 1
fi
if (( RESTART_COUNT != 1 )); then
  printf 'expected one failed target restart for inactive service, got %s\n' "${RESTART_COUNT}" >&2
  exit 1
fi

# If restoring the old service also fails, the function must report recovery failure.
SERVICE_STATE=active
RECOVERY_RESTART_FAIL=y
RESTART_COUNT=0
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected failed service recovery to return non-zero\n' >&2
  exit 1
fi
if [[ "$(${SINGBOX_BIN_PATH} marker)" != "old" ]]; then
  printf 'expected old sing-box binary even when service recovery fails\n' >&2
  exit 1
fi
if [[ "${SERVICE_STATE}" != "inactive" || "${RESTART_COUNT}" != "2" ]]; then
  printf 'expected failed recovery to leave inactive service and two restart attempts\n' >&2
  exit 1
fi

# A successful recovery restart command must still restore the active state.
SERVICE_STATE=active
RECOVERY_RESTART_FAIL=n
RECOVERY_RESTART_EXIT_ZERO_INACTIVE=y
TARGET_RESTART_EXIT_ZERO=n
RESTART_COUNT=0
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected inactive recovery result to return non-zero\n' >&2
  exit 1
fi
if [[ "$("${SINGBOX_BIN_PATH}" marker)" != "old" ]]; then
  printf 'expected old sing-box binary after inactive recovery result\n' >&2
  exit 1
fi
if [[ "${SERVICE_STATE}" != "inactive" || "${RESTART_COUNT}" != "2" ]]; then
  printf 'expected inactive recovery result and two restart attempts\n' >&2
  exit 1
fi

# A restart command that exits zero but never reaches active must also roll back.
SERVICE_STATE=active
RECOVERY_RESTART_FAIL=n
RECOVERY_RESTART_EXIT_ZERO_INACTIVE=n
TARGET_RESTART_EXIT_ZERO=y
RESTART_COUNT=0
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected non-active post-restart state to return non-zero\n' >&2
  exit 1
fi
if [[ "$(${SINGBOX_BIN_PATH} marker)" != "old" || "${SERVICE_STATE}" != "active" ]]; then
  printf 'expected post-restart health failure to restore old binary and active service\n' >&2
  exit 1
fi
if (( RESTART_COUNT != 2 )); then
  printf 'expected target and recovery restart attempts after post-restart health failure\n' >&2
  exit 1
fi

# A downloader/extractor that leaves the wrong binary in place must fail before
# configuration validation or a service restart and restore the previous binary.
SERVICE_STATE=active
RECOVERY_RESTART_FAIL=n
RECOVERY_RESTART_EXIT_ZERO_INACTIVE=n
TARGET_RESTART_EXIT_ZERO=n
INSTALL_BINARY_VERSION=1.13.18
RESTART_COUNT=0
if update_singbox_binary_preserving_config >/dev/null; then
  printf 'expected target-version mismatch to return non-zero\n' >&2
  exit 1
fi
if [[ "$("${SINGBOX_BIN_PATH}" marker)" != "old" || "${SERVICE_STATE}" != "active" ]]; then
  printf 'expected target-version mismatch to restore old binary without changing service state\n' >&2
  exit 1
fi
if (( RESTART_COUNT != 0 )); then
  printf 'expected no restart when the installed binary version mismatches the target\n' >&2
  exit 1
fi
