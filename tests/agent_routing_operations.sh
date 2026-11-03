#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
trap 'printf "agent routing test failed at line %s\n" "${LINENO}" >&2' ERR

FP_FILE="${TMP_DIR}/fingerprint"
FIXTURE="${TMP_DIR}/draft.json"
CALLS="${TMP_DIR}/calls"
printf '%064d\n' 1 > "${FP_FILE}"
policy=$(routing_policy_read_json)
jq -n --argjson policy "${policy}" --arg fingerprint "$(cat "${FP_FILE}")" \
  '{policy:$policy,warp:{enabled:false,mode:"selective",reregister:false},node_overrides:[],
    legacy_domains:"private.example.test",legacy_sources:"https://example.test/legacy?token=DUMMY_SECRET",
    fingerprint:$fingerprint}
    | .policy.server.rule_sets=[{tag:"private-source",type:"remote",format:"source",
      url:"https://example.test/rules?token=DUMMY_SECRET",action:"direct",enabled:true,update_interval:"1d"}]
    | .policy.server.rules=[{id:"private-rule",kind:"domain",value:"private.example.test",action:"reject",enabled:true}]' \
  > "${FIXTURE}"
chmod 600 "${FIXTURE}"
routing_draft_validate "${FIXTURE}"

routing_state_fingerprint() { cat "${FP_FILE}"; }
routing_draft_create() {
  jq --arg fingerprint "$(cat "${FP_FILE}")" '.fingerprint=$fingerprint' "${FIXTURE}" > "$1"
}
routing_nodes_json() {
  printf '%s\n' '[{"protocol":"http","id":"main","name":"office","tag":"http-in","policy":"default","revision":2,"editable":true,"password":"DUMMY_SECRET"}]'
}
routing_policy_apply() {
  printf 'apply\n' >> "${CALLS}"
  cp "$1" "${TMP_DIR}/observed-draft"
  if [[ -f "${TMP_DIR}/fail" ]]; then
    [[ ! -f "${TMP_DIR}/pending" ]] || mkdir "${SB_ROUTING_TRANSACTION_DIR}"
    printf 'fixture transaction failed\n'
    return 71
  fi
  printf '%064d\n' 2 > "${FP_FILE}"
  printf 'fixture operation progress\n'
}
routing_policy_restore_previous() {
  printf 'restore\n' >> "${CALLS}"
  printf '%064d\n' 1 > "${FP_FILE}"
}
routing_policy_recover() {
  printf 'recover\n' >> "${CALLS}"
  rm -rf -- "${SB_ROUTING_TRANSACTION_DIR}"
}
request() { agent_cli_run routing agent_routing_cli "$@"; }
failed() {
  local json
  if json=$(request "$@"); then
    printf 'expected routing failure: %s\n' "$*" >&2
    return 1
  fi
  jq -e '.ok==false and (.data|type=="object")' <<< "${json}" >/dev/null
  printf '%s\n' "${json}"
}

json=$(request view --json)
jq -e '.ok and .data.policy.server.block_cn==false and .data.nodes[0].id=="main"
  and .data.policy.server.rules[0].id=="private-rule"
  and .data.legacy_assets.sources_present' <<< "${json}" >/dev/null
[[ "${json}" != *DUMMY_SECRET* && "${json}" != *private.example.test* ]]
json=$(request export --json)
jq -e '.ok and .data.sensitive and (.data.draft.legacy_sources|contains("DUMMY_SECRET"))' <<< "${json}" >/dev/null
jq '.data.draft' <<< "${json}" > "${TMP_DIR}/exported.json"
chmod 600 "${TMP_DIR}/exported.json"
routing_draft_validate "${TMP_DIR}/exported.json"
json=$(request nodes --json)
jq -e '.ok and .data.nodes[0].revision==2 and (.data.nodes[0]|has("password")|not)' <<< "${json}" >/dev/null
json=$(request validate --json --file "${FIXTURE}")
jq -e '.ok and .data.valid and (.data.config_check_performed|not)' <<< "${json}" >/dev/null
[[ ! -e "${CALLS}" ]]

for operation in view export nodes validate apply restore recover unknown; do
  failed "${operation}" --json --json >/dev/null
done
failed validate --json --yes --file "${FIXTURE}" >/dev/null
failed apply --json --file "${FIXTURE}" >/dev/null
failed restore --json --yes --expected-fingerprint wrong >/dev/null
failed recover --json --yes --expected-fingerprint "$(cat "${FP_FILE}")" >/dev/null
failed view --json --file "${FIXTURE}" >/dev/null
[[ ! -e "${CALLS}" ]]

chmod 644 "${FIXTURE}"
json=$(failed validate --json --file "${FIXTURE}")
jq -e '.error=="invalid_draft"' <<< "${json}" >/dev/null
chmod 600 "${FIXTURE}"
ln -s "${FIXTURE}" "${TMP_DIR}/draft-link"
failed validate --json --file "${TMP_DIR}/draft-link" >/dev/null
printf '{}\n{}\n' > "${TMP_DIR}/invalid"
chmod 600 "${TMP_DIR}/invalid"
failed validate --json --file "${TMP_DIR}/invalid" >/dev/null
cat "${FIXTURE}" "${FIXTURE}" > "${TMP_DIR}/invalid"
failed validate --json --file "${TMP_DIR}/invalid" >/dev/null
[[ ! -e "${CALLS}" ]]

printf '%064d\n' 3 > "${FP_FILE}"
json=$(failed apply --json --yes --file "${FIXTURE}")
jq -e '.error=="revision_conflict"' <<< "${json}" >/dev/null
failed restore --json --yes --expected-fingerprint "$(printf '%064d' 1)" >/dev/null
[[ ! -e "${CALLS}" ]]
printf '%064d\n' 1 > "${FP_FILE}"
json=$(request apply --json --yes --file "${FIXTURE}" 2> "${TMP_DIR}/progress")
jq -e '.ok and .data.changed and (.data.recovery_required|not)' <<< "${json}" >/dev/null
cmp "${FIXTURE}" "${TMP_DIR}/observed-draft"
grep -Fq 'fixture operation progress' "${TMP_DIR}/progress"
json=$(request restore --json --yes --expected-fingerprint "$(cat "${FP_FILE}")")
jq -e '.ok and .data.changed' <<< "${json}" >/dev/null

touch "${TMP_DIR}/fail"
json=$(failed apply --json --yes --file "${FIXTURE}" 2> "${TMP_DIR}/failure-progress")
jq -e '.data.transaction_status=="failed" and (.data.changed|not)
  and (.data|has("rolled_back")|not)' <<< "${json}" >/dev/null
touch "${TMP_DIR}/pending"
json=$(failed apply --json --yes --file "${FIXTURE}" 2> "${TMP_DIR}/failure-progress")
jq -e '.data.recovery_required and .data.transaction_status=="recovery_required"' <<< "${json}" >/dev/null
json=$(failed view --json)
jq -e '.error=="routing_transaction_pending"' <<< "${json}" >/dev/null
failed recover --json >/dev/null
json=$(request recover --json --yes)
jq -e '.ok and (.data.recovery_required|not)' <<< "${json}" >/dev/null
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
mkdir "${SB_COMPONENT_TRANSACTION_DIR}"
failed recover --json --yes >/dev/null
rm -rf "${SB_COMPONENT_TRANSACTION_DIR}"
touch "${SB_PROJECT_DIR}.instance-write.lock"
failed view --json >/dev/null
rm "${SB_PROJECT_DIR}.instance-write.lock"

# Exercise the built artifact through main, canonical mapping and Agent guards.
# Keep filesystem/service mutations isolated; record lock choices and refuse
# menu entry so a dispatcher regression cannot touch the actual host.
LOCK_CALLS="${TMP_DIR}/locks"
acquire_managed_write_lock() {
  printf '%s\n' "${*:-exclusive}" >> "${LOCK_CALLS}"
  [[ ! -e "${TMP_DIR}/busy" ]]
}
show_banner() { printf 'unexpected menu entry\n' >&2; return 97; }
agent_current_user_is_root() { return 0; }
request() { main "$@"; }
json=$(request routing view --json)
jq -e '.ok and .command=="routing" and .data.action=="routing_view"' <<< "${json}" >/dev/null
[[ "$(tail -1 "${LOCK_CALLS}")" == shared ]]
json=$(request agent routing nodes --json)
jq -e '.ok and .data.action=="routing_nodes"' <<< "${json}" >/dev/null
[[ "$(tail -1 "${LOCK_CALLS}")" == shared ]]
json=$(request routing validate --json --file "${FIXTURE}")
jq -e '.ok and .data.valid' <<< "${json}" >/dev/null
[[ "$(tail -1 "${LOCK_CALLS}")" == shared ]]
rm "${TMP_DIR}/fail" "${TMP_DIR}/pending"
touch "${TMP_DIR}/busy"
json=$(failed routing apply --json --yes --file "${FIXTURE}")
jq -e '.error=="instance_write_busy"' <<< "${json}" >/dev/null
[[ "$(tail -1 "${LOCK_CALLS}")" == exclusive ]]
rm "${TMP_DIR}/busy"
json=$(request routing apply --json --yes --file "${FIXTURE}" 2> "${TMP_DIR}/progress")
jq -e '.ok and .data.changed' <<< "${json}" >/dev/null
[[ "$(tail -1 "${LOCK_CALLS}")" == exclusive ]]
json=$(request routing restore --json --yes --expected-fingerprint "$(cat "${FP_FILE}")")
jq -e '.ok and .data.changed' <<< "${json}" >/dev/null
[[ "$(tail -1 "${LOCK_CALLS}")" == exclusive ]]

mkdir "${SB_ROUTING_TRANSACTION_DIR}"
json=$(failed routing view --json)
jq -e '.error=="routing_transaction_pending"' <<< "${json}" >/dev/null
json=$(failed agent routing apply --json --yes --file "${FIXTURE}")
jq -e '.error=="routing_transaction_pending"' <<< "${json}" >/dev/null
json=$(request commands --json)
jq -e '.ok and .data.action=="commands"' <<< "${json}" >/dev/null
failed routing recover --json >/dev/null
[[ -d "${SB_ROUTING_TRANSACTION_DIR}" && "$(tail -1 "${LOCK_CALLS}")" == 'exclusive allow-rules-recovery' ]]
json=$(request agent routing recover --json --yes)
jq -e '.ok and (.data.recovery_required|not)' <<< "${json}" >/dev/null
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && "$(tail -1 "${LOCK_CALLS}")" == 'exclusive allow-rules-recovery' ]]

mkdir "${SB_COMPONENT_TRANSACTION_DIR}"
json=$(failed routing recover --json --yes)
jq -e '.error=="component_transaction_pending"' <<< "${json}" >/dev/null
rm -rf "${SB_COMPONENT_TRANSACTION_DIR}"
ln -s "${TMP_DIR}/absent" "${SB_COMPONENT_TRANSACTION_DIR}"
json=$(failed routing view --json)
jq -e '.error=="component_transaction_pending"' <<< "${json}" >/dev/null
rm "${SB_COMPONENT_TRANSACTION_DIR}"
ln -s "${TMP_DIR}/absent" "${SB_PROJECT_DIR}.instance-write.lock"
json=$(failed routing view --json)
jq -e '.error=="instance_transaction_pending"' <<< "${json}" >/dev/null
rm "${SB_PROJECT_DIR}.instance-write.lock"
agent_current_user_is_root() { return 1; }
json=$(failed routing view --json)
jq -e '.error=="root_required"' <<< "${json}" >/dev/null
json=$(request commands --json)
jq -e '.ok' <<< "${json}" >/dev/null
printf '%s\n' 'Agent routing operations passed'
