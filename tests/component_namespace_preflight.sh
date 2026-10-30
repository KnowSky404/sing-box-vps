#!/usr/bin/env bash

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR}"' EXIT
# These are isolated command mocks; this host test never enters a namespace.
# The core is intentionally absent; build compatibility has a separate fixture.
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TEST_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TEST_DIR}/core\"|" \
  "${REPO_ROOT}/install.sh" > "${TEST_DIR}/install.sh"
source "${TEST_DIR}/install.sh"
state=$(managed_component_state_default_json)
namespace=$(jq -cn --arg path "${TEST_DIR}/namespace-handle" '{id:"test-ns",role:"network_namespace",type:"default",tag:"test-ns",enabled:true,config:{path:$path},route_rules:[]}')
state=$(managed_component_state_candidate "${state}" create "${namespace}")
printf 'ordinary file fixture\n' > "${TEST_DIR}/namespace-handle"
nsenter() { printf '%s\n' "$*" >> "${TEST_DIR}/nsenter.calls"; return "${NAMESPACE_STATUS:-0}"; }
timeout() { [[ "$1" == 5 ]]; shift; "$@"; }
managed_component_network_namespaces_accessible "${state}"
grep -Fxq -- "--net=${TEST_DIR}/namespace-handle -- /bin/true" "${TEST_DIR}/nsenter.calls"
for status in 1 126 124; do
 NAMESPACE_STATUS=${status}
 if managed_component_network_namespaces_accessible "${state}" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
 [[ ! -s "${TEST_DIR}/out" ]]
 grep -Fq 'network_namespace_unavailable' "${TEST_DIR}/err"
 ! grep -Fq "${TEST_DIR}" "${TEST_DIR}/err"
done
unset NAMESPACE_STATUS
rm "${TEST_DIR}/namespace-handle"
if managed_component_network_namespaces_accessible "${state}" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
mkfifo "${TEST_DIR}/namespace-handle"
if managed_component_network_namespaces_accessible "${state}" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
# No namespace program is invoked for absent/special files.
[[ "$(wc -l < "${TEST_DIR}/nsenter.calls")" == 4 ]]
command() {
 if [[ "${1:-}" == -v && "${2:-}" == "${MISSING_NAMESPACE_TOOL}" ]]; then return 1; fi
 builtin command "$@"
}
for MISSING_NAMESPACE_TOOL in nsenter timeout; do
 if managed_component_network_namespaces_accessible "${state}" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
 grep -Fq '预检工具不可用' "${TEST_DIR}/err"
done
unset -f command
# Disabled records and unshare records require no existing external handle.
managed_component_network_namespaces_accessible "$(jq '.components[0].enabled=false' <<< "${state}")"
managed_component_network_namespaces_accessible "$(jq '.components[0].type="unshare" | .components[0].config={}' <<< "${state}")"
# Execute the real mutation boundary with only system/core dependencies mocked.
# All filesystem paths resolve inside TEST_DIR; no snapshot/publication is reached.
acquire_managed_write_lock() { return 0; }
managed_component_state_core_features_supported() { return 0; }
systemctl() { return 1; }
managed_component_transaction_begin() { touch "${TEST_DIR}/transaction-reached"; return 0; }
managed_component_write_state() { touch "${TEST_DIR}/publication-reached"; return 0; }
printf '%s\n' "${namespace}" > "${TEST_DIR}/input.json"
if managed_component_state_apply create 0 "${TEST_DIR}/input.json" '' n > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
[[ "${MANAGED_COMPONENT_LAST_ERROR}" == network_namespace_unavailable ]]
[[ ! -e "${TEST_DIR}/transaction-reached" && ! -e "${TEST_DIR}/publication-reached" ]]
[[ ! -e "${SB_COMPONENT_STATE_FILE}" && ! -e "${SINGBOX_CONFIG_FILE}" ]]
printf 'Namespace preflight host mocks passed (no namespace operations)\n'
