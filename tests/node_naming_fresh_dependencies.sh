#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

# A bare VPS may not have jq until install_dependencies. Names without an
# existing JSON preference or inventory must work before that stage.
jq() {
  printf 'jq-called\n' >> "${TMP_DIR}/jq-calls"
  printf 'fixture: jq not installed\n' >&2
  return 127
}
[[ "$(default_instance_node_name mixed)" == test-host-mixed-01 ]]
[[ "$(default_instance_node_name vless-reality)" == test-host-vless-reality-01 ]]
[[ ! -e "${TMP_DIR}/jq-calls" ]]

# Exercise the actual fresh-install dispatcher and Mixed prompt; stop at the
# package-install boundary so this fixture cannot install or activate anything.
load_stack_mode_state() { :; }
get_os_info() { :; }
get_arch() { :; }
prompt_singbox_version() { SB_VERSION=1.14.2; }
prompt_protocol_install_selection() { SELECTED_PROTOCOLS_CSV=mixed; }
prompt_global_instance_options() { :; }
prompt_port() { printf '12345'; }
prompt_yes_no() { printf n; }
check_port_conflict() { :; }
install_dependencies() { printf 'reached\n' > "${TMP_DIR}/dependencies"; return 88; }
abort_managed_state_transaction() {
  [[ "$1" == "${TMP_DIR}"/* ]] || return 1
  rm -rf -- "$1"
}
status=0
install_protocols_interactive fresh >"${TMP_DIR}/fresh.out" 2>"${TMP_DIR}/fresh.err" || status=$?
[[ "${status}" == 88 && -f "${TMP_DIR}/dependencies" ]]
[[ ! -e "${TMP_DIR}/jq-calls" ]]

# An explicit stored preference/inventory must still fail closed without its
# JSON parser, rather than ignoring administrator state or inventing a name.
printf '{"host_label":"retained-label"}\n' > "$(node_naming_config_file_path)"
if default_instance_node_name mixed >"${TMP_DIR}/configured.out" 2>"${TMP_DIR}/configured.err"; then
  printf 'stored naming preference was ignored without jq\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/configured.out" ]]
grep -Fq retained-label "$(node_naming_config_file_path)"
rm "$(node_naming_config_file_path)"
if default_instance_node_name mixed '{"instances":[]}' >"${TMP_DIR}/inventory.out" 2>"${TMP_DIR}/inventory.err"; then
  printf 'explicit inventory was ignored without jq\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/inventory.out" && -f "${TMP_DIR}/jq-calls" ]]
printf 'Fresh naming passed without jq; dependency installation remains reachable and explicit JSON state fails closed\n'
