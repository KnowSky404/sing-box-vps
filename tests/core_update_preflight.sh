#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

cat > "${SINGBOX_BIN_PATH}" <<'CORE'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.2\n' ;;
  check) [[ ! -e "${0}.invalid" ]] ;;
esac
CORE
chmod +x "${SINGBOX_BIN_PATH}"
printf 'unit\n' > "${SINGBOX_SERVICE_FILE}"
printf '{"inbounds":[],"route":{"rules":[]}}\n' > "${SINGBOX_CONFIG_FILE}"
# Rebuilding state is unrelated to a binary-only update and must not run.
protocol_state_layer_matches_config() { printf 'unexpected state rendering\n' >&2; return 99; }
attempt_managed_instance_auto_heal() { printf 'unexpected repair\n' >&2; return 99; }
[[ "$(detect_existing_binary_update_state)" == healthy ]]
touch "${SINGBOX_BIN_PATH}.invalid"
[[ "$(detect_existing_binary_update_state)" == incomplete ]]
rm "${SINGBOX_BIN_PATH}.invalid" "${SINGBOX_SERVICE_FILE}"
[[ "$(detect_existing_binary_update_state)" == incomplete ]]
printf 'unit\n' > "${SINGBOX_SERVICE_FILE}"

# Deterministic tool presence, independent of optional host packages.
command() {
  if [[ "${1:-}" == -v ]]; then
    [[ "${2:-}" != "${MISSING_TOOL:-}" ]]
  else builtin command "$@"; fi
}
storage_selinux_active() { [[ "${MOCK_SELINUX:-n}" == y ]]; }
OS_NAME=debian
PACKAGE_CALLS=0
run_with_progress() { PACKAGE_CALLS=$((PACKAGE_CALLS + 1)); return "${PACKAGE_STATUS:-0}"; }
install_dependencies missing_only >/dev/null
[[ "${PACKAGE_CALLS}" == 0 ]]
MISSING_TOOL=curl
install_dependencies missing_only >/dev/null
[[ "${PACKAGE_CALLS}" == 2 ]]
PACKAGE_STATUS=23
if install_dependencies missing_only >/dev/null; then exit 1; else [[ $? == 23 ]]; fi
PACKAGE_STATUS=0; MISSING_TOOL=semanage; MOCK_SELINUX=y
install_dependencies missing_only >/dev/null
[[ "${PACKAGE_CALLS}" == 5 ]]
unset -f command

get_os_info() { :; }
get_arch() { ARCH=amd64; }
install_dependencies() { :; }
get_latest_version() { :; }
load_warp_route_settings() { :; }
install_binary() { touch "${TMP_DIR}/unexpected-install"; return 99; }
systemctl() { [[ "${1:-}" == is-active ]] && printf 'active\n'; }
detect_existing_instance_state_read_only() { printf healthy; }
agent_singbox_check_json() { printf '{"ok":true}'; }
cat > "${SINGBOX_CONFIG_FILE}" <<'CONFIG'
{"route":{"rules":[{"domain":["fixture.invalid"],"action":"direct"},{"type":"logical","mode":"or","rules":[{"action":"direct"}]}]}}
CONFIG
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before.json"
[[ "$(singbox_legacy_direct_action_count)" == 2 ]]
SB_VERSION=1.14.4
if update_singbox_binary_preserving_config > "${TMP_DIR}/update.log" 2>&1; then exit 1; fi
grep -q 'code=legacy_direct_action changed=false' "${TMP_DIR}/update.log"
[[ ! -e "${TMP_DIR}/unexpected-install" ]]
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before.json"
if agent_upgrade_check_json 1.14.4 > "${TMP_DIR}/check.json"; then exit 1; fi
jq -e '.ready==false and (.blockers|index("legacy_direct_action")!=null) and .legacy.direct_action_count==2' "${TMP_DIR}/check.json" >/dev/null
agent_upgrade_check_json 1.14.2 > "${TMP_DIR}/check.json"
jq -e '.ready==true' "${TMP_DIR}/check.json" >/dev/null
jq 'walk(if type=="object" and .action?=="direct" then .action="route"|.outbound="direct" else . end)' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/modern.json"
cp "${TMP_DIR}/modern.json" "${SINGBOX_CONFIG_FILE}"
agent_upgrade_check_json 1.14.4 > "${TMP_DIR}/check.json"
jq -e '.ready==true and .legacy.direct_action_count==0' "${TMP_DIR}/check.json" >/dev/null
printf 'core update: fast read-only gate, dependency fallback and legacy action preflight passed\n'
