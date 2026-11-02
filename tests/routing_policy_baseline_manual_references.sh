#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${ROUTING_POLICY_TEST_REAL_CORE:-${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}}
[[ "$("${core}" version | head -n1)" == 'sing-box version 1.14.2' ]] || {
  printf 'Set ROUTING_POLICY_TEST_REAL_CORE to the real sing-box 1.14.2 executable\n' >&2; exit 1;
}
export REFERENCE_REAL_CORE="${core}" REFERENCE_CORE_LOG="${TMP_DIR}/core-checks.log" REFERENCE_PROJECT="${TMP_DIR}/project"
cat > "${TMP_DIR}/bin/sing-box" <<'CORE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == check && "${3:-}" == "${REFERENCE_PROJECT}/.managed-config.validation.candidate."* ]]; then
  [[ "$(stat -c %a "$3")" == 600 ]]
  jq -e 'any(.outbounds[]; .tag=="operator-egress") and
    any(.outbounds[]; .tag=="selector-managed" and .outbounds==["operator-egress"])' "$3" >/dev/null
  printf 'complete-context-checked\n' >> "${REFERENCE_CORE_LOG}"
fi
exec "${REFERENCE_REAL_CORE}" "$@"
CORE
chmod +x "${TMP_DIR}/bin/sing-box"
source "${TESTABLE_INSTALL}"
source "${REPO_ROOT}/src/install/40-routing-policy.sh"
trap 'printf "baseline manual-reference test failed at line %s\n" "${LINENO}" >&2' ERR

SERVICE_STATE="${TMP_DIR}/service.state"
SERVICE_CALLS="${TMP_DIR}/service.calls"
printf 'active\n' > "${SERVICE_STATE}"
: > "${SERVICE_CALLS}"
systemctl() {
  printf '%s\n' "$*" >> "${SERVICE_CALLS}"
  case "${1:-}" in
    is-active)
      if [[ "$(cat "${SERVICE_STATE}")" == active ]]; then
        [[ "${2:-}" == --quiet ]] || printf 'active\n'
      else
        [[ "${2:-}" == --quiet ]] || cat "${SERVICE_STATE}"
        return 3
      fi
      ;;
    show) cat "${SERVICE_STATE}" ;;
    restart)
      if [[ -e "${TMP_DIR}/restart-fail-once" ]]; then
        rm -- "${TMP_DIR}/restart-fail-once"
        printf 'inactive\n' > "${SERVICE_STATE}"
        return 72
      fi
      printf 'active\n' > "${SERVICE_STATE}" ;;
    stop) printf 'inactive\n' > "${SERVICE_STATE}" ;;
    *) return 1 ;;
  esac
}
run_with_progress() { shift; "$@"; }
instance_firewall_prepare() {
  printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=Legacy\nPORT=13090\nAUTH_ENABLED=n\nUSERNAME=\nPASSWORD=\n' \
  > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
policy=$(routing_policy_read_json | jq -c '.server.private_network_block=false')
printf '%s\n' "${policy}" > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}"
SB_ENABLE_WARP=n SB_ADVANCED_ROUTE=n SB_WARP_ROUTE_MODE=selective
SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv4
save_stack_mode_state
save_warp_route_settings
generate_config > "${TMP_DIR}/initial.log" 2>&1
jq '.outbounds += [{type:"direct",tag:"operator-egress",bind_interface:"lo"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual.json"
mv "${TMP_DIR}/manual.json" "${SINGBOX_CONFIG_FILE}"

# Use the real component API. Its selector references a valid operator-owned
# outbound that the pure generation baseline deliberately does not adopt.
record='{"id":"selector-managed","role":"outbound","type":"selector","tag":"selector-managed","enabled":true,"route_rules":[],"config":{"outbounds":["operator-egress"],"default":"operator-egress"}}'
printf '%s\n' "${record}" > "${TMP_DIR}/component.json"
if ! managed_component_state_apply create 0 "${TMP_DIR}/component.json" '' n > "${TMP_DIR}/component.log" 2>&1; then
  cat "${TMP_DIR}/component.log" >&2; exit 1
fi
validate_managed_component_graph "${SINGBOX_CONFIG_FILE}"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
manual=$(jq -cS '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}")
baseline="${SB_PROJECT_DIR}/managed-config.generated.json"
jq -e 'any(.outbounds[]; .tag=="selector-managed" and .outbounds==["operator-egress"]) and
  all(.outbounds[]; .tag!="operator-egress")' "${baseline}" >/dev/null
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-live.json"
cp -p "${baseline}" "${TMP_DIR}/before-baseline.json"
cp -p "${baseline}.bak" "${TMP_DIR}/before-baseline.bak"
jq -n '{id:"added",name:"Added",tag:"mixed-added",listen:{address:"127.0.0.1",port:13091},
  authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}' \
  > "${TMP_DIR}/record.json"

# The complete context passes validation before service activation. A later
# restart failure restores the old live config, pure baseline and prior backup.
touch "${TMP_DIR}/restart-fail-once"
if apply_plain_proxy_instance_change mixed create 0 "${TMP_DIR}/record.json" n \
  > "${TMP_DIR}/rollback.json" 2> "${TMP_DIR}/rollback.log"; then
  printf 'service failure was accepted\n' >&2; exit 1
fi
jq -e '.transaction.status=="rolled_back"' "${TMP_DIR}/rollback.json" >/dev/null
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-live.json"
cmp "${baseline}" "${TMP_DIR}/before-baseline.json"
cmp "${baseline}.bak" "${TMP_DIR}/before-baseline.bak"
[[ "$(cat "${SERVICE_STATE}")" == active && -s "${REFERENCE_CORE_LOG}" ]]

if ! apply_plain_proxy_instance_change mixed create 0 "${TMP_DIR}/record.json" n \
  > "${TMP_DIR}/created.json" 2> "${TMP_DIR}/created.log"; then
  cat "${TMP_DIR}/created.log" >&2; exit 1
fi
jq -e '.ok and .revision==1' "${TMP_DIR}/created.json" >/dev/null
jq -e 'any(.inbounds[]; .tag=="mixed-added") and all(.outbounds[]; .tag!="operator-egress") and
  any(.outbounds[]; .tag=="selector-managed" and .outbounds==["operator-egress"])' "${baseline}" >/dev/null
[[ "$(jq -cS '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}")" == "${manual}" ]]
[[ "$(find "${SB_PROJECT_DIR}" -maxdepth 1 -name '.managed-config.*.candidate.*' -print | wc -l)" == 0 ]]
validate_managed_component_graph "${SINGBOX_CONFIG_FILE}"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# A subsequent global policy edit must also retain the cross-ownership reference.
routing_draft_create "${TMP_DIR}/draft.json"
routing_draft_edit "${TMP_DIR}/draft.json" '.policy.server.private_network_block=true'
if ! routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/policy.log" 2>&1; then
  cat "${TMP_DIR}/policy.log" >&2; exit 1
fi
[[ "$(jq -cS '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}")" == "${manual}" ]]
jq -e 'any(.route.rules[]; .ip_is_private==true) and all(.outbounds[]; .tag!="operator-egress")' "${baseline}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# Resolving references against the complete context must not allow dangling
# references. The real API rejects an unknown selector member and rolls back.
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/valid-live.json"
cp -p "${baseline}" "${TMP_DIR}/valid-baseline.json"
cp -p "${baseline}.bak" "${TMP_DIR}/valid-baseline.bak"
jq '.id="selector-invalid" | .tag="selector-invalid" |
  .config={outbounds:["missing-egress"],default:"missing-egress"}' \
  "${TMP_DIR}/component.json" > "${TMP_DIR}/invalid-component.json"
if managed_component_state_apply create 1 "${TMP_DIR}/invalid-component.json" '' n > "${TMP_DIR}/dangling.log" 2>&1; then
  printf 'dangling component reference was accepted\n' >&2; exit 1
fi
[[ "${MANAGED_COMPONENT_LAST_ERROR}" == config_check_failed ]]
grep -Fq 'component_graph: unknown reference' "${TMP_DIR}/dangling.log"
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/valid-live.json"
cmp "${baseline}" "${TMP_DIR}/valid-baseline.json"
cmp "${baseline}.bak" "${TMP_DIR}/valid-baseline.bak"
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" && ! -e "${SB_PROJECT_DIR}.instance-write.lock" &&
   "$(find "${SB_PROJECT_DIR}" -maxdepth 1 -name '.managed-config.*.candidate.*' -print | wc -l)" == 0 ]]
printf 'Real component/manual references, typed baseline, global apply, rollback and dangling-ref rejection passed with sing-box 1.14.2\n'
