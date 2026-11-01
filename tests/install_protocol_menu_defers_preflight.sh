#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

loader_definition=$(declare -f load_current_config_state)
installer_definition=$(declare -f install_protocols_interactive)
calls="${TMP_DIR}/calls"
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf '#!/usr/bin/env bash\nexit 0\n' > "${SINGBOX_BIN_PATH}"
chmod +x "${SINGBOX_BIN_PATH}"
touch "${SINGBOX_SERVICE_FILE}"
printf '%s\n' '{"inbounds":[{"type":"mixed","tag":"mixed-in","listen_port":32100}]}' > "${SINGBOX_CONFIG_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nPORT=32100\nAUTH_ENABLED=n\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
printf 'PROTOCOL_STATE_VERSION=1\nINSTALLED_PROTOCOLS=mixed\n' > "${SB_PROTOCOL_INDEX_FILE}"
cp -a "${SB_PROJECT_DIR}" "${TMP_DIR}/before"

# The real preview must not enter the mutating reconciliation or health path.
list_installed_protocols() { printf 'reconcile\n' >> "${calls}"; return 91; }
detect_existing_instance_state() {
  printf 'health %s\n' "${health_state}" >> "${calls}"
  [[ "${health_state}" != failed ]] || return 7
  printf '%s' "${health_state}"
}
install_protocols_interactive() { printf 'install %s %s\n' "$1" "${2:-}" >> "${calls}"; }
prompt_incomplete_instance_action() { printf 'incomplete\n' >> "${calls}"; }
install_or_reconfigure_singbox() { printf 'fresh\n' >> "${calls}"; }
health_state=healthy

: > "${calls}"
install_new_protocols_menu > "${TMP_DIR}/cancel.output" <<<'0'
[[ ! -s "${calls}" ]]
grep -Fq '当前已安装协议:' "${TMP_DIR}/cancel.output"
grep -Fxq -- '- Mixed (HTTP/HTTPS/SOCKS)' "${TMP_DIR}/cancel.output"
diff -ru "${TMP_DIR}/before" "${SB_PROJECT_DIR}"

# A selected protocol gets the complete health check once, before dispatch.
install_new_protocols_menu > "${TMP_DIR}/selected.output" 2> "${TMP_DIR}/selected.stderr" <<<'5'
[[ "$(cat "${calls}")" == $'health healthy\ninstall additional socks' ]]
grep -Fq '检查现有实例的配置及状态' "${TMP_DIR}/selected.stderr"

# A valid index is only a preview: failed/incomplete health cannot authorize
# an additional installation, and a fresh classification retains its route.
for health_state in incomplete fresh; do
  : > "${calls}"
  install_new_protocols_menu > /dev/null 2> "${TMP_DIR}/health.stderr" <<<'5'
  [[ "$(cat "${calls}")" == "$(printf 'health %s\n%s' "${health_state}" "${health_state}")" ]]
done
health_state=failed
: > "${calls}"
if install_new_protocols_menu > /dev/null 2> "${TMP_DIR}/failed.stderr" <<<'5'; then
  printf 'expected failed health check to block installation\n' >&2
  exit 1
else
  [[ $? == 7 ]]
fi
[[ "$(cat "${calls}")" == 'health failed' ]]

# Missing installation files skip preview and retain the detection dispatch.
rm "${SINGBOX_SERVICE_FILE}"
for health_state in incomplete fresh; do
  : > "${calls}"
  install_new_protocols_menu > "${TMP_DIR}/missing.output" 2> "${TMP_DIR}/missing.stderr" </dev/null
  [[ "$(cat "${calls}")" == "$(printf 'health %s\n%s' "${health_state}" "${health_state}")" ]]
  ! grep -Fq '可安装协议:' "${TMP_DIR}/missing.output"
done
touch "${SINGBOX_SERVICE_FILE}"

# Each invocation rereads the index. A previous inventory must not persist.
health_state=healthy
printf 'PROTOCOL_STATE_VERSION=1\nINSTALLED_PROTOCOLS=socks\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/socks.env"
: > "${calls}"
install_new_protocols_menu > "${TMP_DIR}/next.output" <<<'0'
[[ ! -s "${calls}" ]]
grep -Fxq -- '- SOCKS' "${TMP_DIR}/next.output"
! grep -Fxq -- '- Mixed (HTTP/HTTPS/SOCKS)' "${TMP_DIR}/next.output"
grep -Fxq '2. Mixed (HTTP/HTTPS/SOCKS)' "${TMP_DIR}/next.output"

# Explicit empty inventory is still a supplied snapshot, not a cache miss.
if prompt_protocol_install_selection additional '' > "${TMP_DIR}/empty.output" <<<'0'; then
  printf 'expected prompt cancellation\n' >&2
  exit 1
fi
[[ ! -s "${calls}" ]]
grep -Fxq '当前已安装协议: 无' "${TMP_DIR}/empty.output"

# Use new subshells to exercise the actual loader and installer independently
# of the dispatch stubs above. Supplied inventories avoid reconciliation.
(
  eval "${loader_definition}"
  : > "${calls}"
  migrate_legacy_single_protocol_state_if_needed() { :; }
  list_installed_protocols() { printf 'unexpected reconcile\n' >> "${calls}"; return 91; }
  load_protocol_state() { printf 'load %s\n' "$1" >> "${calls}"; }
  load_current_config_state mixed
  [[ "$(cat "${calls}")" == 'load mixed' ]]
)

(
  eval "${installer_definition}"
  : > "${calls}"
  migrate_legacy_single_protocol_state_if_needed() { :; }
  list_installed_protocols() { printf 'reconcile\n' >> "${calls}"; printf 'mixed\n'; }
  load_current_config_state() { printf 'load-list %s\n' "$1" >> "${calls}"; }
  mixed_instance_create_interactive() { printf 'create mixed\n' >> "${calls}"; }
  install_protocols_interactive additional mixed </dev/null
  [[ "$(cat "${calls}")" == $'reconcile\nload-list mixed\ncreate mixed' ]]

  : > "${calls}"
  install_protocols_interactive additional > "${TMP_DIR}/direct.output" <<<'2'
  [[ "$(cat "${calls}")" == $'reconcile\nload-list mixed\ncreate mixed' ]]
)

printf 'protocol install menu checks passed: deferred-health cancellation fresh-incomplete no-cache inventory-reuse\n'
