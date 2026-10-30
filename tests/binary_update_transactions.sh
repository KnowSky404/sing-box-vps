#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

get_os_info() { OS_NAME=debian; }
get_arch() { ARCH=amd64; }
install_dependencies() { return "${MOCK_DEPENDENCY_STATUS}"; }
get_latest_version() { :; }
load_warp_route_settings() { :; }
display_status_summary() { :; }
ldconfig() { :; }
MOCK_DEPENDENCY_STATUS=0
MOCK_INSTALL_STATUS=0
MOCK_CORRUPT_CONFIG=n
MOCK_SIGNAL=n
SERVICE_STATE=active
RESTARTS=0
systemctl() {
  case "${1:-}" in
    is-active) printf '%s\n' "${SERVICE_STATE}"; [[ "${SERVICE_STATE}" == active ]] ;;
    restart) RESTARTS=$((RESTARTS + 1)); SERVICE_STATE=active ;;
    stop) SERVICE_STATE=inactive ;;
    *) return 1 ;;
  esac
}
validate_config_file() { :; }
install_binary() {
  cat > "${SINGBOX_BIN_PATH}" <<'EOF_NEW'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  marker) printf 'new\n' ;;
esac
EOF_NEW
  chmod 0755 "${SINGBOX_BIN_PATH}"
  printf 'new-library\n' > "$(singbox_library_path)"
  sha256sum "$(singbox_library_path)" | awk '{print $1}' > "${SB_NAIVE_LIBRARY_MARKER}"
  if [[ "${MOCK_CORRUPT_CONFIG}" == y ]]; then printf 'changed-config\n' > "${SINGBOX_CONFIG_FILE}"; fi
  if [[ "${MOCK_SIGNAL}" == y ]]; then kill -TERM "${BASHPID}"; fi
  return "${MOCK_INSTALL_STATUS}"
}
reset_old_state() {
  SB_VERSION=1.14.0
  MOCK_DEPENDENCY_STATUS=0; MOCK_INSTALL_STATUS=0; MOCK_CORRUPT_CONFIG=n; MOCK_SIGNAL=n
  SERVICE_STATE=active; RESTARTS=0
  cat > "${SINGBOX_BIN_PATH}" <<'EOF_OLD'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.13.18\n' ;;
  marker) printf 'old\n' ;;
esac
EOF_OLD
  chmod 0750 "${SINGBOX_BIN_PATH}"
  printf '{"inbounds":[]}\n' > "${SINGBOX_CONFIG_FILE}"
  chmod 0600 "${SINGBOX_CONFIG_FILE}"
  mkdir -p "$(dirname "$(singbox_library_path)")"
  printf 'old-library\n' > "$(singbox_library_path)"
  chmod 0640 "$(singbox_library_path)"
  sha256sum "$(singbox_library_path)" | awk '{print $1}' > "${SB_NAIVE_LIBRARY_MARKER}"
  chmod 0600 "${SB_NAIVE_LIBRARY_MARKER}"
  cp -p "${SINGBOX_BIN_PATH}" "${TMP_DIR}/before.binary"
  cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before.config"
  cp -p "$(singbox_library_path)" "${TMP_DIR}/before.library"
}
assert_old_state() {
  singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${TMP_DIR}/before.binary"
  singbox_file_matches_backup "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before.config"
  singbox_file_matches_backup "$(singbox_library_path)" "${TMP_DIR}/before.library"
  [[ "${SERVICE_STATE}" == active && "${RESTARTS}" == 0 ]]
  [[ -z "$(find "${TMP_DIR}/bin" -maxdepth 1 -name '.sing-box-update.*' -print -quit)" ]]
}
expect_failure() {
  local name=$1 expected=$2 actual
  if update_singbox_binary_preserving_config > "${TMP_DIR}/${name}.stdout" 2> "${TMP_DIR}/${name}.stderr"; then
    printf 'unexpected update success: %s\n' "${name}" >&2; exit 1
  else actual=$?; fi
  [[ "${actual}" == "${expected}" ]]
}

reset_old_state; MOCK_DEPENDENCY_STATUS=23
expect_failure dependencies 23
assert_old_state
reset_old_state; MOCK_INSTALL_STATUS=19
expect_failure install 19
assert_old_state
reset_old_state; MOCK_CORRUPT_CONFIG=y
expect_failure config_change 1
assert_old_state
reset_old_state; MOCK_SIGNAL=y
trap 'printf previous-handler >/dev/null' TERM
previous_term=$(trap -p TERM)
expect_failure signal 143
[[ "$(trap -p TERM)" == "${previous_term}" ]]
trap - TERM
assert_old_state
printf 'binary update: dependency/install failure, config preservation and signal rollback passed\n'
