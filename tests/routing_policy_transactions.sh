#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
trap 'printf "routing transaction test failed at line %s\n" "${LINENO}" >&2' ERR

# These are real file/snapshot/CAS transactions. Only service activation and
# config generation are replaced; nothing may address the host installation.
[[ "${SB_PROJECT_DIR}" == "${TMP_DIR}/project" &&
   "${SINGBOX_SERVICE_FILE}" == "${TMP_DIR}/sing-box.service" &&
   "${SINGBOX_BIN_PATH}" == "${TMP_DIR}/bin/sing-box" ]]
SERVICE_STATE_FILE="${TMP_DIR}/service-state"
SERVICE_LOG="${TMP_DIR}/service-calls"
GENERATION_MODE=success
STORE_FILE="${SB_PROTOCOL_STATE_DIR}/instances/socks.json"
cat > "${SINGBOX_BIN_PATH}" <<'EOF_CORE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  check) jq -e 'type == "object"' "${3:?}" >/dev/null ;;
  version) printf 'sing-box version 1.14.2\n' ;;
  *) printf 'unexpected fixture core operation\n' >&2; exit 95 ;;
esac
EOF_CORE
chmod +x "${SINGBOX_BIN_PATH}"

systemctl() {
  printf '%s\n' "$*" >> "${SERVICE_LOG}"
  case "${1:-}" in
    is-active)
      if [[ "$(cat "${SERVICE_STATE_FILE}")" == active ]]; then
        [[ "${2:-}" == --quiet ]] || printf 'active\n'
        return 0
      fi
      [[ "${2:-}" == --quiet ]] || cat "${SERVICE_STATE_FILE}"
      return 3
      ;;
    show) cat "${SERVICE_STATE_FILE}" ;;
    restart)
      if [[ -f "${TMP_DIR}/restart-fail-always" || -f "${TMP_DIR}/restart-fail-once" ]]; then
        rm -f "${TMP_DIR}/restart-fail-once"
        printf 'inactive\n' > "${SERVICE_STATE_FILE}"
        return 71
      fi
      printf 'active\n' > "${SERVICE_STATE_FILE}"
      ;;
    stop) printf 'inactive\n' > "${SERVICE_STATE_FILE}" ;;
    *) printf 'unexpected fixture systemctl operation: %s\n' "$*" >&2; return 96 ;;
  esac
}
run_with_progress() { shift; "$@"; }
load_current_config_state() { :; }
ensure_existing_generated_config_baseline() { :; }
get_public_ip() { printf '203.0.113.10\n'; }
register_warp() {
  if [[ -e "${TMP_DIR}/forbid-register" ]]; then
    printf 'unexpected provider call\n' >> "${TMP_DIR}/provider-calls"
    return 96
  fi
}
generate_config() {
  local candidate="${TMP_DIR}/generated-candidate.json" inbounds rules
  inbounds=$(render_structured_instance_inbounds socks "${STORE_FILE}" | jq -s '.') || return 1
  rules=$(render_structured_instance_route_rules socks "${STORE_FILE}") || return 1
  jq --argjson inbounds "${inbounds}" --argjson rules "${rules}" \
    '.inbounds=$inbounds | .route.rules=$rules | .log={level:"debug"}' \
    "${SINGBOX_CONFIG_FILE}" > "${candidate}" || return 1
  routing_publish_file "${candidate}" "${SINGBOX_CONFIG_FILE}" || return 1
  case "${GENERATION_MODE}" in
    success) return 0 ;;
    failure) return 72 ;;
    receipt-failure)
      printf '{"phase":"received","id":"fixture-account","token":"fixture-token"}\n' \
        > "${SB_WARP_REGISTRATION_PENDING_FILE}"
      chmod 600 "${SB_WARP_REGISTRATION_PENDING_FILE}"
      return 73
      ;;
    external-failure)
      printf 'concurrent manual change\n' > "${SB_PROJECT_DIR}/manual/nested/state.env"
      printf 'renewed certificate\n' > "${SB_ACME_DATA_DIR}/fixture/cert.pem"
      return 74
      ;;
    interrupt) kill -INT "${BASHPID}"; return 97 ;;
    terminate) kill -TERM "${BASHPID}"; return 98 ;;
    *) return 99 ;;
  esac
}

tree_fingerprint() (
  cd -- "$1"
  find . -mindepth 1 ! -path './sbv.log' -printf '%y %m %p\n' | LC_ALL=C sort
  while IFS= read -r -d '' file; do sha256sum -- "${file}"; done \
    < <(find . -type f ! -path './sbv.log' -print0 | LC_ALL=C sort -z)
)

reset_case() {
  rm -rf -- "${SB_PROJECT_DIR}" "${SB_ROUTING_TRANSACTION_DIR}" "${SB_ROUTING_PREVIOUS_DIR}" \
    "${SB_PROJECT_DIR}.instance-write.lock" "${SB_COMPONENT_TRANSACTION_DIR}"
  rm -f -- "${TMP_DIR}/restart-fail-always" "${TMP_DIR}/restart-fail-once" \
    "${SB_WARP_REGISTRATION_PENDING_FILE}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_WARP_LOCAL_RULESET_DIR}" \
    "${SB_PROJECT_DIR}/manual/nested" "${SB_ACME_DATA_DIR}/fixture"
  jq -n '{schema_version:1,protocol:"socks",revision:7,default_instance_id:"one",instances:[
    {id:"one",name:"first node",tag:"socks-one",listen:{address:"127.0.0.1",port:33101},
     authentication:{enabled:true,username:"one",password:"fixture-one"},outbound_policy:"default",dependencies:[]},
    {id:"two",name:"second node",tag:"socks-two",listen:{address:"127.0.0.1",port:33102},
     authentication:{enabled:true,username:"two",password:"fixture-two"},outbound_policy:"default",dependencies:[]}
  ]}' > "${STORE_FILE}"
  chmod 600 "${STORE_FILE}"
  validate_structured_instance_store socks "${STORE_FILE}"
  save_plain_proxy_structured_marker socks
  write_protocol_index socks
  local inbounds rules
  inbounds=$(render_structured_instance_inbounds socks "${STORE_FILE}" | jq -s '.')
  rules=$(render_structured_instance_route_rules socks "${STORE_FILE}")
  jq -n --argjson inbounds "${inbounds}" --argjson rules "${rules}" \
    '{inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$rules,final:"direct"}}' \
    > "${SINGBOX_CONFIG_FILE}"
  cp -p "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
  chmod 600 "${SB_PROJECT_DIR}/managed-config.generated.json"
  printf 'manual state\n' > "${SB_PROJECT_DIR}/manual/nested/state.env"
  chmod 640 "${SB_PROJECT_DIR}/manual/nested/state.env"
  printf 'original certificate\n' > "${SB_ACME_DATA_DIR}/fixture/cert.pem"
  chmod 600 "${SB_ACME_DATA_DIR}/fixture/cert.pem"
  printf 'WARP_KEY=fixture-old-key\n' > "${SB_WARP_KEY_FILE}"
  printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=n\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
  printf '# retained WARP domains\nold.example.invalid\n' > "${SB_WARP_DOMAINS_FILE}"
  printf '# retained WARP sources\n' > "${SB_WARP_REMOTE_RULESETS_FILE}"
  printf '{"version":1,"rules":[]}\n' > "${SB_WARP_LOCAL_RULESET_DIR}/fixture.json"
  printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
  printf 'active\n' > "${SERVICE_STATE_FILE}"
  : > "${SERVICE_LOG}"
  GENERATION_MODE=success
  plain_proxy_structured_state_matches_config socks "${SINGBOX_CONFIG_FILE}"
}

new_draft() {
  routing_draft_create "${TMP_DIR}/draft.json"
  routing_draft_edit "${TMP_DIR}/draft.json" '.policy.server.block_cn |= not'
}

expect_rejection() {
  local label=$1 result=0
  shift
  "$@" > "${TMP_DIR}/last.stdout" 2> "${TMP_DIR}/last.stderr" || result=$?
  if [[ "${result}" == 0 ]]; then printf 'unexpected success: %s\n' "${label}" >&2; return 1; fi
  LAST_REJECTION_STATUS=${result}
}

assert_clean_rollback() {
  [[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${BEFORE_TREE}" ]] || {
    printf 'rollback changed project files or modes\n' >&2; return 1;
  }
  [[ "$(routing_state_fingerprint)" == "${BEFORE_FINGERPRINT}" ]]
  [[ "$(cat "${SERVICE_STATE_FILE}")" == "${BEFORE_ACTIVITY}" ]]
  [[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && ! -e "${SB_ROUTING_PREVIOUS_DIR}" ]]
  [[ -z "$(find "${SB_PROJECT_DIR}" -name '.routing-write.*' -print)" ]]
  [[ -z "$(find "${TMP_DIR}" -maxdepth 1 \( -name '.project.restore.*' -o -name '.project.previous.*' \) -print)" ]]
}

# Even when global WARP is already enabled and its credential file is missing,
# unrelated Block CN / preset edits must not register or repair an account.
reset_case
independent_policy=$(routing_policy_read_json)
printf '%s\n' "${independent_policy}" > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}"
printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=y\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
rm -- "${SB_WARP_KEY_FILE}"
touch "${TMP_DIR}/forbid-register"
for filter in '.policy.server.block_cn |= not' '.policy.server.warp_ai |= not'; do
  routing_draft_create "${TMP_DIR}/independent.json"
  routing_draft_edit "${TMP_DIR}/independent.json" "${filter}"
  routing_policy_apply "${TMP_DIR}/independent.json" > "${TMP_DIR}/independent.out" 2> "${TMP_DIR}/independent.err"
  [[ ! -e "${SB_WARP_KEY_FILE}" && ! -e "${TMP_DIR}/provider-calls" ]]
done
rm -- "${TMP_DIR}/forbid-register"

reset_case
# Atomic publication uses same-directory staging, private permissions and a
# backup; writing the same bytes again cannot rotate that backup or inode.
printf '{"old":true}\n' > "${SB_PROJECT_DIR}/atomic.json"
printf '{"new":true}\n' > "${TMP_DIR}/candidate.json"
routing_publish_file "${TMP_DIR}/candidate.json" "${SB_PROJECT_DIR}/atomic.json"
jq -e '.new == true' "${SB_PROJECT_DIR}/atomic.json" >/dev/null
jq -e '.old == true' "${SB_PROJECT_DIR}/atomic.json.bak" >/dev/null
[[ "$(stat -c %a "${SB_PROJECT_DIR}/atomic.json")" == 600 ]]
atomic_metadata=$(stat -c '%i:%a:%s:%Y' "${SB_PROJECT_DIR}/atomic.json")
atomic_backup=$(sha256sum "${SB_PROJECT_DIR}/atomic.json.bak")
routing_publish_file "${TMP_DIR}/candidate.json" "${SB_PROJECT_DIR}/atomic.json"
[[ "$(stat -c '%i:%a:%s:%Y' "${SB_PROJECT_DIR}/atomic.json")" == "${atomic_metadata}" ]]
[[ "$(sha256sum "${SB_PROJECT_DIR}/atomic.json.bak")" == "${atomic_backup}" ]]

# A path lexically inside the project must not grant access through a linked
# parent directory, even when the final target itself is a regular file.
mkdir -p "${TMP_DIR}/outside-publisher"
printf 'untouched external target\n' > "${TMP_DIR}/outside-publisher/state.json"
cp -p "${TMP_DIR}/outside-publisher/state.json" "${TMP_DIR}/outside-before.json"
ln -s "${TMP_DIR}/outside-publisher" "${SB_PROJECT_DIR}/linked-parent"
expect_rejection linked-parent routing_publish_file "${TMP_DIR}/candidate.json" "${SB_PROJECT_DIR}/linked-parent/state.json"
cmp "${TMP_DIR}/outside-before.json" "${TMP_DIR}/outside-publisher/state.json"
[[ "$(find "${TMP_DIR}/outside-publisher" -mindepth 1 -maxdepth 1 | wc -l)" == 1 ]]

reset_case
# Reading fresh defaults cannot persist policy or initialize WARP.
rm "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
policy=$(routing_policy_read_json)
jq -e '.schema_version==2 and (.server.block_cn|not)' <<< "${policy}" >/dev/null
[[ ! -e "${SB_ROUTING_POLICY_FILE}" ]]

reset_case
# Entering a submenu and returning without choosing a setting is read-only.
BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
routing_management_menu > "${TMP_DIR}/cancel.log" <<'EOF_CANCEL'
2
0
0
EOF_CANCEL
[[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${BEFORE_TREE}" ]]
[[ ! -e "${SB_ROUTING_POLICY_FILE}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" && ! -s "${SERVICE_LOG}" ]]

reset_case
new_draft
jq '.external_change=true' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/external.json"
mv "${TMP_DIR}/external.json" "${SINGBOX_CONFIG_FILE}"
BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
expect_rejection stale-draft routing_policy_apply "${TMP_DIR}/draft.json"
[[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${BEFORE_TREE}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
! grep -q '^restart\|^stop' "${SERVICE_LOG}"

reset_case
new_draft
BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
before_identity=$(jq -cS 'del(.revision) | .instances |= map(del(.outbound_policy))' "${STORE_FILE}")
routing_draft_edit "${TMP_DIR}/draft.json" '.node_overrides=[
  {protocol:"socks",id:"one",policy:"direct",revision:7},
  {protocol:"socks",id:"two",policy:"warp",revision:7}]'
routing_policy_apply "${TMP_DIR}/draft.json" > "${TMP_DIR}/combined.stdout" 2> "${TMP_DIR}/combined.stderr"
[[ "$(jq -cS 'del(.revision) | .instances |= map(del(.outbound_policy))' "${STORE_FILE}")" == "${before_identity}" ]]
jq -e '.revision==8 and [.instances[].outbound_policy]==["direct","warp"]' "${STORE_FILE}" >/dev/null
jq -e '.revision==7 and [.instances[].outbound_policy]==["default","default"]' "${STORE_FILE}.bak" >/dev/null
[[ "$(grep -c '^restart sing-box$' "${SERVICE_LOG}")" == 1 && "$(cat "${SERVICE_STATE_FILE}")" == active ]]
routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}"
[[ "${SB_ROUTING_PREVIOUS_DIR}" != "${SB_PROJECT_DIR}/"* ]]
[[ ! -e "${SB_ROUTING_PREVIOUS_DIR}/snapshot/project/.rules-write.lock" ]]
[[ -z "$(find "${SB_ROUTING_PREVIOUS_DIR}/snapshot/project" -name transaction.json -print)" ]]

# Explicit restore is a new transaction. It is allowed only while the recorded
# post-apply fingerprint and service activity still match.
: > "${SERVICE_LOG}"
routing_policy_restore_previous > "${TMP_DIR}/restore.stdout" 2> "${TMP_DIR}/restore.stderr"
[[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${BEFORE_TREE}" ]]
[[ "$(grep -c '^restart sing-box$' "${SERVICE_LOG}")" == 1 ]]

reset_case
new_draft
routing_policy_apply "${TMP_DIR}/draft.json" > /dev/null 2> "${TMP_DIR}/apply.stderr"
# A service change alone prevents an explicit undo, even if files still match.
service_change_tree=$(tree_fingerprint "${SB_PROJECT_DIR}")
printf 'inactive\n' > "${SERVICE_STATE_FILE}"
expect_rejection intervening-service routing_policy_restore_previous
[[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${service_change_tree}" ]]
printf 'active\n' > "${SERVICE_STATE_FILE}"
jq '.intervening_change=true' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/intervening.json"
mv "${TMP_DIR}/intervening.json" "${SINGBOX_CONFIG_FILE}"
BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
previous_tree=$(tree_fingerprint "${SB_ROUTING_PREVIOUS_DIR}")
expect_rejection intervening-state routing_policy_restore_previous
[[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${BEFORE_TREE}" ]]
[[ "$(tree_fingerprint "${SB_ROUTING_PREVIOUS_DIR}")" == "${previous_tree}" ]]

reset_case
new_draft
routing_policy_apply "${TMP_DIR}/draft.json" > /dev/null 2> "${TMP_DIR}/root-mode-apply.stderr"
root_before_mode=$(stat -c %a "${SB_PROJECT_DIR}")
root_before_fingerprint=$(routing_state_fingerprint)
if [[ "${root_before_mode}" == 700 ]]; then chmod 750 "${SB_PROJECT_DIR}"; else chmod 700 "${SB_PROJECT_DIR}"; fi
[[ "$(routing_state_fingerprint)" != "${root_before_fingerprint}" ]]
root_changed_mode=$(stat -c %a "${SB_PROJECT_DIR}")
expect_rejection intervening-root-mode routing_policy_restore_previous
[[ "$(stat -c %a "${SB_PROJECT_DIR}")" == "${root_changed_mode}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]

for external_path in manual/nested/state.env acme/fixture/cert.pem; do
  reset_case
  new_draft
  routing_policy_apply "${TMP_DIR}/draft.json" > /dev/null 2> "${TMP_DIR}/external-apply.stderr"
  printf 'external change after application\n' > "${SB_PROJECT_DIR}/${external_path}"
  BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
  expect_rejection "intervening-${external_path}" routing_policy_restore_previous
  [[ "$(tree_fingerprint "${SB_PROJECT_DIR}")" == "${BEFORE_TREE}" ]]
  [[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
done

for GENERATION_MODE in failure interrupt terminate receipt-failure; do
  generation_case=${GENERATION_MODE}
  reset_case
  GENERATION_MODE=${generation_case}
  new_draft
  if [[ "${GENERATION_MODE}" == receipt-failure ]]; then
    routing_draft_edit "${TMP_DIR}/draft.json" '.warp.enabled=true | .warp.reregister=true'
  fi
  BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
  BEFORE_FINGERPRINT=$(routing_state_fingerprint)
  BEFORE_ACTIVITY=active
  expect_rejection "${GENERATION_MODE}" routing_policy_apply "${TMP_DIR}/draft.json"
  case "${GENERATION_MODE}" in
    interrupt) [[ "${LAST_REJECTION_STATUS}" == 130 ]] ;;
    terminate) [[ "${LAST_REJECTION_STATUS}" == 143 ]] ;;
  esac
  assert_clean_rollback
  if [[ "${GENERATION_MODE}" == receipt-failure ]]; then
    jq -e '.phase=="received" and .id=="fixture-account"' "${SB_WARP_REGISTRATION_PENDING_FILE}" >/dev/null
    [[ "$(stat -c %a "${SB_WARP_REGISTRATION_PENDING_FILE}")" == 600 ]]
  fi
done

reset_case
new_draft
BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
BEFORE_FINGERPRINT=$(routing_state_fingerprint)
BEFORE_ACTIVITY=active
touch "${TMP_DIR}/restart-fail-once"
expect_rejection restart-failure routing_policy_apply "${TMP_DIR}/draft.json"
assert_clean_rollback
[[ "$(grep -c '^restart sing-box$' "${SERVICE_LOG}")" == 2 ]]

reset_case
printf 'inactive\n' > "${SERVICE_STATE_FILE}"
new_draft
routing_policy_apply "${TMP_DIR}/draft.json" > /dev/null 2> "${TMP_DIR}/inactive.stderr"
[[ "$(cat "${SERVICE_STATE_FILE}")" == inactive ]]
! grep -q '^restart\|^start' "${SERVICE_LOG}"

# Reapplying an unchanged current policy does not regenerate or restart.
routing_draft_create "${TMP_DIR}/draft.json"
server_before_noop=$(sha256sum "${SINGBOX_CONFIG_FILE}")
GENERATION_MODE=failure
: > "${SERVICE_LOG}"
routing_policy_apply "${TMP_DIR}/draft.json" > /dev/null 2> "${TMP_DIR}/noop.stderr"
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${server_before_noop}" ]]
! grep -q '^restart\|^start\|^stop' "${SERVICE_LOG}"
routing_policy_restore_previous > /dev/null 2> "${TMP_DIR}/noop-undo.stderr"
! grep -q '^restart\|^start\|^stop' "${SERVICE_LOG}"
[[ "$(find "${SB_ROUTING_PREVIOUS_DIR}" -name snapshot.meta -print | wc -l)" == 1 ]]

reset_case
printf 'failed\n' > "${SERVICE_STATE_FILE}"
[[ "$(routing_service_active_json)" == false ]]
new_draft
failed_before_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
routing_policy_apply "${TMP_DIR}/draft.json" > /dev/null 2> "${TMP_DIR}/failed-unit-apply.stderr"
[[ "$(cat "${SERVICE_STATE_FILE}")" == failed ]]
! grep -q '^restart\|^start\|^stop' "${SERVICE_LOG}"
routing_policy_restore_previous > /dev/null 2> "${TMP_DIR}/failed-unit-undo.stderr"
[[ "$(cat "${SERVICE_STATE_FILE}")" == failed &&
   "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${failed_before_config}" ]]
! grep -q '^restart\|^start\|^stop' "${SERVICE_LOG}"
printf 'activating\n' > "${SERVICE_STATE_FILE}"
if routing_service_active_json > /dev/null; then
  printf 'unknown unit state was treated as stopped\n' >&2; exit 1
fi

reset_case
new_draft
GENERATION_MODE=external-failure
expect_rejection concurrent-external-state routing_policy_apply "${TMP_DIR}/draft.json"
routing_transaction_valid "${SB_ROUTING_TRANSACTION_DIR}"
grep -Fxq 'concurrent manual change' "${SB_PROJECT_DIR}/manual/nested/state.env"
grep -Fxq 'renewed certificate' "${SB_ACME_DATA_DIR}/fixture/cert.pem"
expect_rejection concurrent-state-recovery-block routing_policy_recover
[[ -d "${SB_ROUTING_TRANSACTION_DIR}" ]]
# After an operator reconciles the external files, the original snapshot can
# safely recover the managed transaction without erasing runtime diagnostics.
cp -p "${SB_ROUTING_TRANSACTION_DIR}/snapshot/project/manual/nested/state.env" "${SB_PROJECT_DIR}/manual/nested/state.env"
cp -p "${SB_ROUTING_TRANSACTION_DIR}/snapshot/project/acme/fixture/cert.pem" "${SB_ACME_DATA_DIR}/fixture/cert.pem"
printf 'keep runtime diagnostic\n' > "${SBV_LOG_FILE}"
routing_policy_recover > "${TMP_DIR}/external-recover.stdout" 2> "${TMP_DIR}/external-recover.stderr"
grep -Fxq 'keep runtime diagnostic' "${SBV_LOG_FILE}"
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]

reset_case
new_draft
BEFORE_TREE=$(tree_fingerprint "${SB_PROJECT_DIR}")
BEFORE_FINGERPRINT=$(routing_state_fingerprint)
BEFORE_ACTIVITY=active
touch "${TMP_DIR}/restart-fail-always"
expect_rejection rollback-restart-failure routing_policy_apply "${TMP_DIR}/draft.json"
routing_transaction_valid "${SB_ROUTING_TRANSACTION_DIR}"
[[ -f "${SB_ROUTING_TRANSACTION_DIR}/snapshot/snapshot.meta" ]]
expect_rejection pending-rules-barrier acquire_managed_write_lock
rm "${TMP_DIR}/restart-fail-always"
routing_policy_recover > "${TMP_DIR}/recover.stdout" 2> "${TMP_DIR}/recover.stderr"
assert_clean_rollback

printf 'Routing transactions passed: real snapshots/CAS, drafts, rollback, service state, signals and recovery\n'
