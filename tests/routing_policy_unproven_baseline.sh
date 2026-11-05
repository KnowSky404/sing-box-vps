#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${ROUTING_POLICY_TEST_REAL_CORE:-${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}}
[[ "$("${core}" version | head -n1)" == 'sing-box version 1.14.4' ]] || {
  printf 'Set ROUTING_POLICY_TEST_REAL_CORE to real sing-box 1.14.4\n' >&2; exit 1;
}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
# A private reproduction can load the pre-fix generator without touching the
# committed artifact; normal execution always exercises the assembled runtime.
if [[ -n "${SBV_BASELINE_REPRO_SOURCE:-}" ]]; then source "${SBV_BASELINE_REPRO_SOURCE}"; fi
trap 'printf "unproven baseline test failed at line %s\n" "${LINENO}" >&2' ERR
systemctl() {
  printf '%s\n' "$*" >> "${TMP_DIR}/service-calls"
  case "${1:-}" in
    is-active) [[ "${2:-}" == --quiet ]] || printf 'inactive\n'; return 3 ;;
    show) printf 'inactive\n' ;;
    stop) : ;;
    *) return 97 ;;
  esac
}
run_with_progress() { shift; "$@"; }
instance_firewall_prepare() {
  printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }
fail() { printf 'unproven routing ownership: %s\n' "$*" >&2; exit 1; }
baseline="${SB_PROJECT_DIR}/managed-config.generated.json"
reset_case() {
  rm -rf -- "${SB_PROJECT_DIR}" "${SB_ROUTING_PREVIOUS_DIR}" "${SB_ROUTING_TRANSACTION_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
  printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
  printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=Fixture\nPORT=13090\nAUTH_ENABLED=n\nUSERNAME=\nPASSWORD=\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
  SB_VERSION=1.14.4 SB_ENABLE_WARP=n SB_ADVANCED_ROUTE=n SB_WARP_ROUTE_MODE=selective
  SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv4
  save_stack_mode_state
  generate_config > "${TMP_DIR}/initial.log" 2>&1
}
assert_manual_not_adopted() {
  jq -e --argjson rule "${manual}" 'any(.route.rules[]; .==$rule)' "${SINGBOX_CONFIG_FILE}" >/dev/null || fail 'manual rule was lost'
  jq -e --argjson rule "${manual}" 'all(.route.rules[]; .!=$rule)' "${baseline}" >/dev/null || fail 'manual rule was claimed by generated ownership'
}
for path in direct after-node after-regeneration manual-ad; do
  reset_case
  manual='{"ip_is_private":true,"action":"reject"}'
  [[ "${path}" != manual-ad ]] || manual='{"domain_suffix":["ads.manual.invalid"],"action":"reject"}'
  jq --argjson rule "${manual}" '.route.rules += [$rule]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual.json"
  mv -- "${TMP_DIR}/manual.json" "${SINGBOX_CONFIG_FILE}"
  rm -- "${baseline}"
  rm -f -- "${baseline}.bak"
  [[ ! -e "${SB_ROUTING_POLICY_FILE}" ]]
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  if [[ "${path}" == after-node || "${path}" == after-regeneration ]]; then
    load_current_config_state
    ensure_existing_generated_config_baseline > "${TMP_DIR}/${path}-baseline.log" 2>&1
    assert_manual_not_adopted
    if [[ "${path}" == after-node ]]; then
      jq -n '{id:"added",name:"Added",tag:"mixed-added",listen:{address:"127.0.0.1",port:13091},
        authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}' > "${TMP_DIR}/node.json"
      apply_plain_proxy_instance_change mixed create 0 "${TMP_DIR}/node.json" n > "${TMP_DIR}/node-result.json" 2> "${TMP_DIR}/node.log"
      jq -e '.ok' "${TMP_DIR}/node-result.json" >/dev/null
    else
      load_current_config_state
      generate_config > "${TMP_DIR}/repeat-generation.log" 2>&1
    fi
    assert_manual_not_adopted
  fi
  routing_draft_create "${TMP_DIR}/draft.json"
  before=$(routing_state_fingerprint)
  if routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/${path}-apply.log" 2>&1; then
    assert_manual_not_adopted
    jq -e '.schema_version==2 and (.server.block_cn|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
  else
    [[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]] || fail 'rejection did not roll back exactly'
    jq -e --argjson rule "${manual}" 'any(.route.rules[]; .==$rule)' "${SINGBOX_CONFIG_FILE}" >/dev/null
  fi
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  printf 'Unproven manual rule preserved: %s\n' "${path}"
done
# Explicit v1 policy is positive ownership proof. Its retired generated private
# and ad rules must still be removed on deliberate server-only adoption.
reset_case
jq -n '{schema_version:1,
  server:{private_network_block:true,adblock:true,warp_ai:true,warp_streaming:true,rules:[],rule_sets:[]},
  client:{lan_direct:true,cn_direct:true,adblock:false},adblock:{url:"",domains:["old.ads.invalid"],allow:[]}}' > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}"
generate_config > "${TMP_DIR}/owned-generate.log" 2>&1
rm -- "${baseline}"
routing_draft_create "${TMP_DIR}/owned-draft.json"
routing_policy_apply "${TMP_DIR}/owned-draft.json" > "${TMP_DIR}/owned-apply.log" 2>&1
jq -e 'all(.route.rules[]; .ip_is_private!=true) and
  all(.route.rule_set[]; (.tag|startswith("sbv-adblock-")|not))' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e '.schema_version==2' "${SB_ROUTING_POLICY_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'Unproven-rule ownership and explicit legacy-policy cleanup passed\n'
