#!/usr/bin/env bash

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_DIR}"' EXIT
sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TEST_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TEST_DIR}/core\"|" \
  "${REPO_ROOT}/install.sh" > "${TEST_DIR}/install.sh"
cat > "${TEST_DIR}/core" <<'CORE'
#!/usr/bin/env bash
[[ "${1:-}" == version ]] || exit 1
printf 'sing-box version %s\nEnvironment: go1.26.8 linux/arm64\n' "${NAMESPACE_TEST_VERSION:-1.14.2}"
if [[ "${NAMESPACE_TEST_TAGS_MODE:-reported}" == reported ]]; then printf 'Tags: %s\n' "${NAMESPACE_TEST_TAGS-with_purego}"; fi
printf 'CGO: disabled\n'
CORE
chmod +x "${TEST_DIR}/core"
source "${TEST_DIR}/install.sh"
uname() { case "${1:-}" in -s) printf '%s\n' "${NAMESPACE_TEST_PLATFORM:-Linux}" ;; -m) printf '%s\n' "${NAMESPACE_TEST_ARCH:-aarch64}" ;; *) return 1 ;; esac; }
namespace_record() {
  local type=$1
  jq -cn --arg type "${type}" '{id:"fixture-ns",role:"network_namespace",type:$type,tag:"fixture-ns",enabled:true,config:(if $type=="default" then {path:"/proc/self/ns/net"} else {} end),route_rules:[]}'
}
state_for() { managed_component_state_candidate "$(managed_component_state_default_json)" create "$1"; }
for type in default unshare; do
  record=$(namespace_record "${type}")
  state=$(state_for "${record}")
  if managed_component_namespace_runtime_safe "${state}" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
  grep -Fq namespace_runtime_unsafe_build "${TEST_DIR}/err"
done
# Same namespace API with different versions/architectures/platforms is not
# disabled by inference from the tested ARM64 purego build.
for scenario in glibc other-version other-architecture other-platform missing-tags empty-tags; do
  export NAMESPACE_TEST_VERSION=1.14.2 NAMESPACE_TEST_TAGS=with_purego NAMESPACE_TEST_ARCH=aarch64 NAMESPACE_TEST_PLATFORM=Linux NAMESPACE_TEST_TAGS_MODE=reported
  expected=available
  case "${scenario}" in
    glibc) NAMESPACE_TEST_TAGS=with_quic ;;
    other-version) NAMESPACE_TEST_VERSION=1.14.1 ;;
    other-architecture) NAMESPACE_TEST_ARCH=x86_64 ;;
    other-platform) NAMESPACE_TEST_PLATFORM=Darwin ;;
    missing-tags) NAMESPACE_TEST_TAGS_MODE=omitted; expected=not_assessed ;;
    empty-tags) NAMESPACE_TEST_TAGS='' ;;
  esac
  dependency=$(namespace_runtime_build_dependency_json "${NAMESPACE_TEST_PLATFORM}" "${NAMESPACE_TEST_ARCH}" "${NAMESPACE_TEST_VERSION}" "$([[ "${NAMESPACE_TEST_TAGS_MODE}" == reported ]] && printf available || printf not_assessed)" "$(jq -cn --arg tag "${NAMESPACE_TEST_TAGS}" 'if $tag=="" then [] else [$tag] end')")
  [[ "$(jq -r .status <<< "${dependency}")" == "${expected}" ]]
  if [[ "${expected}" == not_assessed ]]; then
    status=0
    managed_component_namespace_runtime_safe "${state}" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err" || status=$?
    [[ "${status}" == 3 ]]
    grep -Fq namespace_runtime_build_not_assessed "${TEST_DIR}/err"
  else
    managed_component_namespace_runtime_safe "${state}"
  fi
done
unset NAMESPACE_TEST_VERSION NAMESPACE_TEST_TAGS NAMESPACE_TEST_ARCH NAMESPACE_TEST_PLATFORM NAMESPACE_TEST_TAGS_MODE
static=$(component_registry_static_json | jq '[.[] | select(.role=="network_namespace" or .state_id=="direct-outbound")]')
environments=$(component_registry_environment_bulk_json "${static}")
jq -e 'all(.[]|select(.state_id|startswith("network-namespace")); .status=="unavailable" and .reason=="namespace_runtime_unsafe_build") and any(.[];.state_id=="direct-outbound" and .status=="available")' <<< "${environments}" >/dev/null
record=$(jq -cn '{id:"bypass",role:"outbound",type:"direct",tag:"bypass",enabled:true,config:{netns:"/proc/self/ns/net"},route_rules:[]}')
base=$(jq -c '.[]|select(.state_id=="direct-outbound")' <<< "${environments}")
managed_component_instance_environment_json "${record}" "${base}" > "${TEST_DIR}/instance-environment.json"
jq -e '.status=="unavailable" and .reason=="namespace_runtime_unsafe_build"' "${TEST_DIR}/instance-environment.json" >/dev/null
export NAMESPACE_TEST_TAGS_MODE=omitted
unknown_environments=$(component_registry_environment_bulk_json "${static}")
jq -e 'all(.[]|select(.state_id|startswith("network-namespace")); .status=="not_assessed" and .reason=="namespace_runtime_build_not_assessed")' <<< "${unknown_environments}" >/dev/null
unknown_base=$(jq -c '.[]|select(.state_id=="direct-outbound")' <<< "${unknown_environments}")
managed_component_instance_environment_json "${record}" "${unknown_base}" > "${TEST_DIR}/unknown-instance.json"
jq -e '.status=="not_assessed" and .reason=="namespace_runtime_build_not_assessed"' "${TEST_DIR}/unknown-instance.json" >/dev/null
unset NAMESPACE_TEST_TAGS_MODE
# Each supported Dial field must participate in the same guard. Empty or
# disabled records do not acquire this runtime dependency.
for config in '{"netns":"/proc/self/ns/net"}' '{"control_dialer":{"netns":"/proc/self/ns/net"}}' '{"tunnel_dialer":{"netns":"/proc/self/ns/net"}}' \
  '{"http_client":{"netns":"/proc/self/ns/net"}}' '{"realm":{"http_client":{"netns":"/proc/self/ns/net"}}}'; do
  record=$(jq -cn --argjson config "${config}" '{id:"bypass",role:"outbound",type:"direct",tag:"bypass",enabled:true,config:$config,route_rules:[]}')
  managed_component_record_uses_namespace "${record}"
  if managed_component_namespace_runtime_safe "$(jq -cn --argjson record "${record}" '{components:[$record]}')" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
  managed_component_namespace_runtime_safe "$(jq -cn --argjson record "${record}" '{components:[$record|.enabled=false]}')"
done
# These nested paths are also reachable through accepted typed component
# records, not merely through an arbitrary object passed to the predicate.
http_client_ns_record='{"id":"nested-http","role":"http_client","type":"shared","tag":"nested-http","enabled":true,"route_rules":[],"config":{"engine":"go","netns":"/proc/self/ns/net"}}'
realm_ns_record='{"id":"nested-realm","role":"outbound","type":"hysteria2","tag":"nested-realm","enabled":true,"route_rules":[],"config":{"password":"fixture","tls":{"enabled":true,"server_name":"namespace.example.invalid","insecure":true},"realm":{"server_url":"https://realm.example.invalid","realm_id":"fixture","stun_servers":["stun.example.invalid"],"http_client":{"engine":"go","netns":"/proc/self/ns/net"}}}}'
for record in "${http_client_ns_record}" "${realm_ns_record}"; do
  managed_component_state_validate_record "${record}"
  managed_component_record_uses_namespace "${record}"
  if managed_component_namespace_runtime_safe "$(state_for "${record}")" > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
  grep -Fq namespace_runtime_unsafe_build "${TEST_DIR}/err"
done
header_ns_record='{"id":"header-http","role":"http_client","type":"shared","tag":"header-http","enabled":true,"route_rules":[],"config":{"engine":"go","headers":{"netns":"ordinary header"}}}'
managed_component_state_validate_record "${header_ns_record}"
if managed_component_record_uses_namespace "${header_ns_record}"; then exit 1; fi
managed_component_namespace_runtime_safe "$(state_for "${header_ns_record}")"
# Real mutation entry, all paths in TEST_DIR. No journal or publication may
# occur for either namespace type or the raw direct-outbound bypass.
acquire_managed_write_lock() { return 0; }
managed_component_state_core_features_supported() { return 0; }
systemctl() { return 1; }
managed_component_transaction_begin() { touch "${TEST_DIR}/transaction-reached"; return 1; }
for type in default unshare raw unknown realm http-client; do
  expected_error=namespace_runtime_unsafe_build
  unset NAMESPACE_TEST_TAGS_MODE
  if [[ "${type}" == raw ]]; then record='{"id":"raw","role":"outbound","type":"direct","tag":"raw","enabled":true,"config":{"netns":"/proc/self/ns/net"},"route_rules":[]}'
  elif [[ "${type}" == realm ]]; then record=${realm_ns_record}
  elif [[ "${type}" == http-client ]]; then record=${http_client_ns_record}
  elif [[ "${type}" == unknown ]]; then record=$(namespace_record default); export NAMESPACE_TEST_TAGS_MODE=omitted; expected_error=namespace_runtime_build_not_assessed
  else record=$(namespace_record "${type}"); fi
  printf '%s\n' "${record}" > "${TEST_DIR}/record.json"
  if managed_component_state_apply create 0 "${TEST_DIR}/record.json" '' n > "${TEST_DIR}/out" 2> "${TEST_DIR}/err"; then exit 1; fi
  [[ "${MANAGED_COMPONENT_LAST_ERROR}" == "${expected_error}" ]]
  [[ ! -e "${SB_COMPONENT_STATE_FILE}" && ! -e "${SINGBOX_CONFIG_FILE}" && ! -e "${TEST_DIR}/transaction-reached" ]]
done
printf 'Namespace exact-build guard, availability and bypass checks passed\n'
