#!/usr/bin/env bash

set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

systemctl() {
  printf '%s\n' "$*" >> "${TMP_DIR}/systemctl.calls"
  case "$1" in
    stop)
      [[ "${STOP_MODE}" != fail && "${STOP_MODE}" != missing ]] || return 17
      [[ "${STOP_MODE}" == noop ]] || printf 'inactive' > "${TMP_DIR}/service-state"
      ;;
    show)
      [[ "${STOP_MODE}" != unavailable ]] || return 23
      if [[ "$*" == *LoadState* ]]; then
        [[ "${STOP_MODE}" == missing ]] && printf 'not-found' || printf loaded
      else
        cat "${TMP_DIR}/service-state"
      fi
      ;;
    disable) [[ "${STOP_MODE}" != disable-fail ]] ;;
    daemon-reload) : ;;
    *) return 99 ;;
  esac
}
managed_component_redirect_policy_uninstall() { printf redirect >> "${TMP_DIR}/cleanup.calls"; }
managed_component_tproxy_policy_uninstall() { printf tproxy >> "${TMP_DIR}/cleanup.calls"; }
clear_vless_reality_qos_rules() { :; }

reset_fixture() {
  mkdir -p "${SB_PROJECT_DIR}"
  printf '{"inbounds":[],"outbounds":[],"route":{"rules":[]}}\n' > "${SINGBOX_CONFIG_FILE}"
  printf 'binary' > "${SINGBOX_BIN_PATH}"
  printf 'unit' > "${SINGBOX_SERVICE_FILE}"
  printf active > "${TMP_DIR}/service-state"
  : > "${TMP_DIR}/systemctl.calls"
  : > "${TMP_DIR}/cleanup.calls"
  STOP_MODE=success
}

for STOP_MODE_CASE in fail noop unavailable disable-fail; do
  reset_fixture
  STOP_MODE=${STOP_MODE_CASE}
  before_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}")
  if perform_singbox_runtime_uninstall > "${TMP_DIR}/output" 2>&1; then
    printf 'uninstall accepted unconfirmed service state: %s\n' "${STOP_MODE}" >&2
    exit 1
  fi
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}")" == "${before_hash}" ]]
  [[ ! -s "${TMP_DIR}/cleanup.calls" ]]
done

reset_fixture
printf 'invalid-ledger' > "${INSTANCE_FIREWALL_LEDGER_FILE}"
chmod 600 "${INSTANCE_FIREWALL_LEDGER_FILE}"
if perform_singbox_runtime_uninstall > "${TMP_DIR}/output" 2>&1; then exit 1; fi
[[ ! -s "${TMP_DIR}/systemctl.calls" && -f "${SINGBOX_CONFIG_FILE}" ]]
rm "${INSTANCE_FIREWALL_LEDGER_FILE}"

reset_fixture
STOP_MODE=missing
printf inactive > "${TMP_DIR}/service-state"
perform_singbox_runtime_uninstall > "${TMP_DIR}/output" 2>&1
[[ ! -e "${SB_PROJECT_DIR}" && ! -e "${SINGBOX_BIN_PATH}" && ! -e "${SINGBOX_SERVICE_FILE}" ]]
! grep -q '^disable' "${TMP_DIR}/systemctl.calls"
printf 'uninstall service guards passed\n'
