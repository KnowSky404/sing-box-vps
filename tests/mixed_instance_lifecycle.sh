#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 240

# Drive the public Agent command against a private fixture.  A legacy REALITY
# component remains beside Mixed so final deletion proves ownership isolation.
cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check)
    if [[ -n "${SBV_INSTANCE_CHECK_FAIL_FILE:-}" && -e "${SBV_INSTANCE_CHECK_FAIL_FILE}" ]]; then
      printf 'injected core-check failure\n' >&2
      exit 23
    fi
    exit 0
    ;;
  *) printf 'unexpected sing-box invocation: %s\n' "$*" >&2; exit 64 ;;
esac
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
state_file=${SBV_INSTANCE_SYSTEMCTL_STATE_FILE:?missing state file}
count_file=${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE:?missing count file}
log_file=${SBV_INSTANCE_SYSTEMCTL_LOG_FILE:?missing log file}
printf '%s\n' "$*" >> "${log_file}"
if [[ "$*" == 'show -p ActiveState --value sing-box' || "$*" == 'show sing-box --property=ActiveState --value' ]]; then
  cat "${state_file}"
  exit 0
fi
case "${1:-}:${2:-}:${3:-}" in
  is-active:--quiet:sing-box)
    [[ "$(<"${state_file}")" == active ]]
    ;;
  is-active:sing-box:)
    cat "${state_file}"
    [[ "$(<"${state_file}")" == active ]]
    ;;
  restart:sing-box:)
    count=$(<"${count_file}")
    count=$((count + 1))
    printf '%s\n' "${count}" > "${count_file}"
    if [[ -n "${SBV_INSTANCE_RESTART_FAIL_ONCE_FILE:-}" && -e "${SBV_INSTANCE_RESTART_FAIL_ONCE_FILE}" ]]; then
      rm -f "${SBV_INSTANCE_RESTART_FAIL_ONCE_FILE}"
      printf 'injected restart failure\n' >&2
      exit 55
    fi
    printf 'active\n' > "${state_file}"
    ;;
  stop:sing-box:)
    printf 'inactive\n' > "${state_file}"
    ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

# Source at top level.  Bash 4.2 otherwise drops readonly arrays created by a
# function-scoped `source`, which would make the registry appear unset under
# `set -u` during the public preflight.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
printf '0\n' > "${TMP_DIR}/systemctl.count"
: > "${TMP_DIR}/systemctl.log"
export SBV_INSTANCE_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
export SBV_INSTANCE_SYSTEMCTL_COUNT_FILE="${TMP_DIR}/systemctl.count"
export SBV_INSTANCE_SYSTEMCTL_LOG_FILE="${TMP_DIR}/systemctl.log"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed,vless-reality
PROTOCOL_STATE_VERSION=1
EOF_INDEX
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF_MIXED'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy-mixed-node
PORT=2080
AUTH_ENABLED=y
USERNAME=legacy-user
PASSWORD=legacy-password
EOF_MIXED
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF_REALITY'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy reality node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=www.cloudflare.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF_REALITY
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF_CONFIG'
{
  "log": {"level": "info"},
  "inbounds": [
    {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":2080,
     "users":[{"username":"legacy-user","password":"legacy-password"}]},
    {"type":"vless","tag":"vless-in","listen":"127.0.0.1","listen_port":443,
     "users":[{"uuid":"11111111-1111-1111-1111-111111111111","flow":"xtls-rprx-vision"}],
     "tls":{"enabled":true,"server_name":"www.cloudflare.com","reality":{"enabled":true,
       "private_key":"private-key","short_id":["aaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbb"]}}}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[
    {"domain_suffix":["priority-before.example"],"outbound":"direct"},
    {"inbound":"mixed-in","action":"sniff"},
    {"inbound":"mixed-in","action":"route","outbound":"direct"},
    {"domain_suffix":["priority-after.example"],"outbound":"direct"}
  ],"final":"direct"}
}
EOF_CONFIG
printf '[Unit]\nDescription=fixture sing-box\n' > "${SINGBOX_SERVICE_FILE}"

tree_fingerprint() {
  local root=$1
  if [[ ! -e "${root}" ]]; then
    printf '<absent>\n'
  elif [[ -f "${root}" ]]; then
    stat -c '%y %a %n' "${root}"
    sha256sum "${root}"
  else
    (
      cd "${root}"
      find . -mindepth 1 -printf '%y %m %p\n' | sort
      while IFS= read -r -d '' file; do sha256sum "${file}"; done < <(find . -type f -print0 | sort -z)
    )
  fi
}

managed_fingerprint() {
  tree_fingerprint "${SB_PROJECT_DIR}"
  tree_fingerprint "${SINGBOX_SERVICE_FILE}"
}

assert_mixed_route_priority() {
  jq -e '
    .route.rules as $rules |
    ([ $rules | to_entries[] | select(.value.domain_suffix == ["priority-before.example"]) | .key ] | first) as $before |
    ([ $rules | to_entries[] | select(.value.inbound == "mixed-in" and .value.action == "sniff") | .key ] | first) as $sniff |
    ([ $rules | to_entries[] | select(.value.inbound == "mixed-in" and .value.action == "route") | .key ] | first) as $route |
    ([ $rules | to_entries[] | select(.value.domain_suffix == ["priority-after.example"]) | .key ] | first) as $after |
    ($before < $sniff and $sniff < $route and $route < $after)
  ' "${SINGBOX_CONFIG_FILE}" >/dev/null
}

expect_success() {
  local label=$1 expected_revision=$2
  shift 2
  local output
  if ! output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly failed:\n%s\n' "${label}" "${output}" >&2
    cat "${TMP_DIR}/${label}.stderr" >&2
    return 1
  fi
  jq -e --argjson revision "${expected_revision}" \
    '.ok == true and .revision == $revision and .data.revision == $revision' <<< "${output}" >/dev/null || {
    printf '%s returned an unexpected success envelope:\n%s\n' "${label}" "${output}" >&2
    return 1
  }
  printf '%s' "${output}"
}

expect_failure() {
  local label=$1
  shift
  local output status
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded:\n%s\n' "${label}" "${output}" >&2
    return 1
  else
    status=$?
  fi
  ((status != 0)) || return 1
  printf '%s\n' "${output}" > "${TMP_DIR}/${label}.json"
  jq -e '.ok == false and (.error | type == "string") and (.data.ok == false)' <<< "${output}" >/dev/null || {
    printf '%s returned an unexpected failure envelope:\n%s\n' "${label}" "${output}" >&2
    return 1
  }
  if grep -Eq 'legacy-password|public-password|edge-password|beta-password' <<< "${output}"; then
    printf '%s leaked credentials\n' "${label}" >&2
    return 1
  fi
}

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 user=$5 password=$6 file=$7
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --argjson port "${port}" --arg user "${user}" --arg password "${password}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
      authentication:{enabled:true,username:$user,password:$password},
      outbound_policy:"default",dependencies:[]}' > "${file}"
}

declare -F agent_cli >/dev/null || { printf 'missing public Agent API: agent_cli\n' >&2; exit 1; }
make_record edge 'Edge mixed' mixed-edge 2081 edge-user edge-password "${TMP_DIR}/edge.json"
make_record beta 'Beta mixed' mixed-beta 2082 beta-user beta-password "${TMP_DIR}/beta.json"
make_record public 'Public mixed' mixed-public 2083 public-user public-password "${TMP_DIR}/public.json"
jq '.listen.address="0.0.0.0"' "${TMP_DIR}/public.json" > "${TMP_DIR}/public.tmp"
mv "${TMP_DIR}/public.tmp" "${TMP_DIR}/public.json"

firewall_log="${TMP_DIR}/firewall.log"
: > "${firewall_log}"
# Keep the test independent of host firewall backends while still exercising
# the lifecycle's prepare/apply/rollback ownership boundaries.
instance_firewall_prepare() {
  printf 'prepare\n' >> "${firewall_log}"
  if [[ -n "${SBV_INSTANCE_FIREWALL_PREPARE_FAIL_FILE:-}" && -e "${SBV_INSTANCE_FIREWALL_PREPARE_FAIL_FILE}" ]]; then
    return 1
  fi
  # The public transaction passes its persistent journal path as argument 3.
  # A small valid marker is enough for the test double to exercise rollback
  # dispatch without touching a host firewall backend.
  if [[ -n "${3:-}" ]]; then
    printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[{"backend":"ufw","state":"unavailable"}],"diagnostics":[{"code":"backend_unavailable","backend":"ufw","severity":"warning","secret":"must-not-appear-in-report"}]}' > "${3}"
  fi
  return 0
}
instance_firewall_apply() {
  printf 'apply\n' >> "${firewall_log}"
  [[ -z "${SBV_INSTANCE_FIREWALL_APPLY_FAIL_FILE:-}" || ! -e "${SBV_INSTANCE_FIREWALL_APPLY_FAIL_FILE}" ]]
}
instance_firewall_rollback() {
  printf 'rollback\n' >> "${firewall_log}"
  [[ -z "${SBV_INSTANCE_FIREWALL_ROLLBACK_FAIL_FILE:-}" || ! -e "${SBV_INSTANCE_FIREWALL_ROLLBACK_FAIL_FILE}" ]]
}
export SBV_INSTANCE_FIREWALL_LOG_FILE="${firewall_log}"

before_migration=$(managed_fingerprint)
before_restart_count=$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")

# Legacy migration uses virtual revision zero and publishes revision one.  It
# must retain existing credentials; because the active config changes, the
# healthy service is restarted once as part of the transaction.
migrate_json=$(expect_success migrate 1 migrate mixed --json --yes --expected-revision 0)
[[ "$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")" == "$((before_restart_count + 1))" ]]
[[ -f "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" ]]
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/mixed.env"
jq -e '
  .schema_version == 1 and .protocol == "mixed" and .revision == 1
  and .default_instance_id == "main" and (.instances | length) == 1
  and .instances[0].id == "main"
  and .instances[0].name == "legacy-mixed-node"
  and .instances[0].tag == "mixed-in"
  and .instances[0].listen == {address:"127.0.0.1",port:2080}
  and .instances[0].authentication == {enabled:true,username:"legacy-user",password:"legacy-password"}
' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
assert_mixed_route_priority

# The durable audit result is the final transaction payload, including the
# persisted path and success metadata returned by the public envelope.
migration_result_path=$(jq -r '.transaction.result_path' <<< "${migrate_json}")
[[ "${migration_result_path}" == "${SB_PROJECT_DIR}.instance-transactions/result-"*.json ]]
[[ -f "${migration_result_path}" ]]
jq -e --argjson expected "$(jq '.data' <<< "${migrate_json}")" '. == $expected' "${migration_result_path}" >/dev/null
jq -e '.transaction.firewall.backends == [{backend:"ufw",state:"unavailable"}] and
  .transaction.firewall.diagnostics == [{code:"backend_unavailable",severity:"warning",backend:"ufw"}]' \
  "${migration_result_path}" >/dev/null
! grep -Fq 'must-not-appear-in-report' "${migration_result_path}"
[[ "${migrate_json}" != *must-not-appear-in-report* ]]
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]

# Repeating migration at the current revision is a no-op.  In particular, it
# cannot rotate the backup, rewrite the config, touch the firewall, or restart.
after_migration=$(managed_fingerprint)
migration_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")
if [[ -f "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json.bak" ]]; then
  migration_backup_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json.bak")
else
  migration_backup_hash='<absent>'
fi
noop_restart_count=$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")
expect_success migrate_again 1 migrate mixed --json --yes --expected-revision 1 >/dev/null
[[ "$(managed_fingerprint)" == "${after_migration}" ]]
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")" == "${migration_store_hash}" ]]
if [[ -f "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json.bak" ]]; then
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json.bak")" == "${migration_backup_hash}" ]]
else
  [[ "${migration_backup_hash}" == '<absent>' ]]
fi
[[ "$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")" == "${noop_restart_count}" ]]

# Invalid requests are fail-closed and byte-preserving.
invalid_record="${TMP_DIR}/invalid.json"
jq '.unknown=true' "${TMP_DIR}/edge.json" > "${invalid_record}"
invalid_before=$(managed_fingerprint)
expect_failure invalid_record create mixed --json --yes --expected-revision 1 --file "${invalid_record}"
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]

invalid_before=$(managed_fingerprint)
expect_failure missing_yes create mixed --json --expected-revision 1 --file "${TMP_DIR}/edge.json"
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]

invalid_before=$(managed_fingerprint)
expect_failure unknown_flag create mixed --json --yes --expected-revision 1 --file "${TMP_DIR}/edge.json" --unexpected
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]

invalid_before=$(managed_fingerprint)
expect_failure public_without_confirmation create mixed --json --yes --expected-revision 1 --file "${TMP_DIR}/public.json"
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]

jq '.listen.port=2080' "${TMP_DIR}/edge.json" > "${TMP_DIR}/duplicate.json"
invalid_before=$(managed_fingerprint)
expect_failure duplicate_port create mixed --json --yes --expected-revision 1 --file "${TMP_DIR}/duplicate.json"
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]

invalid_before=$(managed_fingerprint)
expect_failure stale_revision create mixed --json --yes --expected-revision 0 --file "${TMP_DIR}/edge.json"
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]

# Create, replace, default and delete preserve the other instances and use a
# single monotonic revision.  Replace keeps the stable tag and identity.
expect_success create_edge 2 create mixed --json --yes --expected-revision 1 --file "${TMP_DIR}/edge.json" >/dev/null
assert_mixed_route_priority
jq -e '
  (.instances | length) == 2
  and any(.instances[]; .id == "main" and .authentication.password == "legacy-password")
  and any(.instances[]; .id == "edge" and .tag == "mixed-edge" and .listen.port == 2081)
' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
jq -e '.inbounds | any(.[]; .type == "mixed" and .tag == "mixed-edge" and .listen_port == 2081)' "${SINGBOX_CONFIG_FILE}" >/dev/null

before_noop=$(managed_fingerprint)
before_noop_count=$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")
expect_success replace_noop 2 replace mixed --json --yes --expected-revision 2 --file "${TMP_DIR}/edge.json" >/dev/null
[[ "$(managed_fingerprint)" == "${before_noop}" ]]
[[ "$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")" == "${before_noop_count}" ]]

make_record edge 'Edge mixed replaced' mixed-edge 2081 edge-user edge-password-2 "${TMP_DIR}/edge-replaced.json"
expect_success replace_edge 3 replace mixed --json --yes --expected-revision 2 --file "${TMP_DIR}/edge-replaced.json" >/dev/null
jq -e '
  any(.instances[]; .id == "edge" and .tag == "mixed-edge" and .name == "Edge mixed replaced" and .authentication.password == "edge-password-2")
  and any(.instances[]; .id == "main" and .authentication.password == "legacy-password")
' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null

expect_success create_beta 4 create mixed --json --yes --expected-revision 3 --file "${TMP_DIR}/beta.json" >/dev/null
jq -e '[.instances[].id] == ["main","edge","beta"]' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null

expect_success set_default_beta 5 default mixed --json --yes --expected-revision 4 --id beta >/dev/null
jq -e '.default_instance_id == "beta"' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null

expect_success delete_edge 6 delete mixed --json --yes --expected-revision 5 --id edge >/dev/null
assert_mixed_route_priority
jq -e '
  ([.instances[].id] | sort) == ["beta","main"]
  and any(.instances[]; .id == "beta" and .authentication.password == "beta-password")
' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
jq -e '.inbounds | any(.[]; .type == "mixed" and .tag == "mixed-beta") and any(.[]; .type == "vless" and .tag == "vless-in")' "${SINGBOX_CONFIG_FILE}" >/dev/null

# Transaction failures must run through private firewall hooks and restore the
# prior state when the core check or service restart fails.
touch "${TMP_DIR}/core-fail"
export SBV_INSTANCE_CHECK_FAIL_FILE="${TMP_DIR}/core-fail"
fault_before=$(managed_fingerprint)
expect_failure core_check_failure create mixed --json --yes --expected-revision 6 --allow-public --file "${TMP_DIR}/public.json"
[[ "$(managed_fingerprint)" == "${fault_before}" ]]
rm -f "${SBV_INSTANCE_CHECK_FAIL_FILE}"

touch "${TMP_DIR}/restart-fail"
export SBV_INSTANCE_RESTART_FAIL_ONCE_FILE="${TMP_DIR}/restart-fail"
fault_before=$(managed_fingerprint)
expect_failure restart_failure create mixed --json --yes --expected-revision 6 --allow-public --file "${TMP_DIR}/public.json"
[[ "$(managed_fingerprint)" == "${fault_before}" ]]
rm -f "${SBV_INSTANCE_RESTART_FAIL_ONCE_FILE}"

# A failed rollback is an operator-visible terminal state: the error is
# structured and recovery material is retained instead of being discarded.
# Run this before final deletion so the same fixture can continue after the
# retained journal is inspected and explicitly discarded by test cleanup.
touch "${TMP_DIR}/rollback-fail"
export SBV_INSTANCE_FIREWALL_ROLLBACK_FAIL_FILE="${TMP_DIR}/rollback-fail"
touch "${TMP_DIR}/rollback-restart-fail"
export SBV_INSTANCE_RESTART_FAIL_ONCE_FILE="${TMP_DIR}/rollback-restart-fail"
expect_failure rollback_failure create mixed --json --yes --expected-revision 6 --allow-public --file "${TMP_DIR}/public.json"
jq -e '(.error == "instance_rollback_failed" or .data.error == "instance_rollback_failed") and .transaction.status == "rollback_failed"' "${TMP_DIR}/rollback_failure.json" >/dev/null
if ! find "${SB_PROJECT_DIR}.instance-write.lock" "${SB_PROJECT_DIR}.instance-transactions" -type f \( -iname '*journal*' -o -iname '*recovery*' -o -name 'transaction.json' -o -name 'firewall.json' \) -print -quit 2>/dev/null | grep -q .; then
  printf 'rollback-failure path did not retain a recovery artifact\n' >&2
  exit 1
fi
# Recovery must reject while the rollback backend is still failing, retain the
# lock, then succeed after the operator clears the backend fault.
expect_failure recovery_still_faulted recover mixed --json --yes --expected-revision 6
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
failed_recovery_result=$(jq -r '.transaction.result_path' "${TMP_DIR}/recovery_still_faulted.json")
[[ -f "${failed_recovery_result}" ]]
jq -e '.transaction.status == "rollback_failed" and .transaction.result_persisted and
  .transaction.manual_intervention_required and (.transaction.firewall | type == "object")' \
  "${failed_recovery_result}" >/dev/null
(
  instance_transaction_persist_result() { return 71; }
  expect_failure recovery_audit_unavailable recover mixed --json --yes --expected-revision 6
  jq -e '.transaction.status == "rollback_failed" and (.transaction.result_persisted | not) and
    .transaction.audit_error == "instance_audit_failed" and .transaction.manual_intervention_required' \
    "${TMP_DIR}/recovery_audit_unavailable.json" >/dev/null
  [[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
)
rm -f "${SBV_INSTANCE_FIREWALL_ROLLBACK_FAIL_FILE}" "${SBV_INSTANCE_RESTART_FAIL_ONCE_FILE}"
unset SBV_INSTANCE_FIREWALL_ROLLBACK_FAIL_FILE SBV_INSTANCE_RESTART_FAIL_ONCE_FILE
expect_success recovery 6 recover mixed --json --yes --expected-revision 6 >/dev/null
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]

# Recovery fails closed when a synthetic stale journal has no snapshot.  The
# journal remains available for manual inspection; cleanup is confined to the
# temporary fixture after the assertion.
missing_snapshot_lock="${SB_PROJECT_DIR}.instance-write.lock"
mkdir -m 700 "${missing_snapshot_lock}"
jq -n --arg expected "6" --argjson pid 999999 --arg start "1" \
  '{schema_version:1,operation:"create",expected_revision:$expected,owner_pid:$pid,
    owner_start:$start,before_active:true,phase:"service"}' \
  > "${missing_snapshot_lock}/transaction.json"
expect_failure recovery_missing_snapshot recover mixed --json --yes --expected-revision 6
jq -e '.error == "instance_rollback_failed" and .transaction.status == "rollback_failed"' \
  "${TMP_DIR}/recovery_missing_snapshot.json" >/dev/null
[[ -d "${missing_snapshot_lock}" ]]
rm -rf -- "${missing_snapshot_lock}"

# Final deletion removes only Mixed from the active index/config and retains
# REALITY.  Deleting beta first must leave the legacy main instance intact.
expect_success delete_beta 7 delete mixed --json --yes --expected-revision 6 --id beta >/dev/null
jq -e '
  .revision == 7 and ([.instances[].id] | sort) == ["main"]
  ' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
jq -e '
  (.inbounds | any(.[]; .type == "mixed" and .tag == "mixed-in"))
  and (.inbounds | any(.[]; .type == "vless" and .tag == "vless-in"))
' "${SINGBOX_CONFIG_FILE}" >/dev/null

# Removing the final Mixed instance advances the CAS revision once more and
# removes Mixed from the index/config without touching REALITY.
expect_success delete_main 8 delete mixed --json --yes --expected-revision 7 --id main >/dev/null
indexed_protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${SB_PROTOCOL_INDEX_FILE}")
if [[ ",${indexed_protocols}," == *,mixed,* ]]; then
  printf 'final Mixed deletion left mixed in protocol index\n' >&2
  exit 1
fi
jq -e '
  (.inbounds | any(.[]; .type == "mixed")) == false
  and (.inbounds | any(.[]; .type == "vless" and .tag == "vless-in"))
' "${SINGBOX_CONFIG_FILE}" >/dev/null
grep -Eq '^INSTALLED=1$' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]
jq -e '.schema_version == 1 and .revision == 8 and .instances == [] and .default_instance_id == ""' \
  "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null

# The final delete leaves an empty revision tombstone so a later create cannot
# restart CAS at zero.  Recreating from that tombstone must publish revision 9.
invalid_before=$(managed_fingerprint)
expect_failure stale_after_final_delete create mixed --json --yes --expected-revision 0 --file "${TMP_DIR}/public.json"
[[ "$(managed_fingerprint)" == "${invalid_before}" ]]
expect_success recreate_after_final_delete 9 create mixed --json --yes --expected-revision 8 --allow-public --file "${TMP_DIR}/public.json" >/dev/null
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/mixed.env"
jq -e '.schema_version == 1 and .revision == 9 and [.instances[].id] == ["public"]' \
  "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null

# Interruption before atomic initial journal publication has no prepared
# artifacts and can safely release its directory under the shared kernel lock.
mkdir -m 700 "${SB_PROJECT_DIR}.instance-write.lock"
printf '{incomplete' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.next"
before_noop=$(managed_fingerprint)
expect_success recovery_initial_stage 9 recover mixed --json --yes --expected-revision 9 >/dev/null
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
[[ "$(managed_fingerprint)" == "${before_noop}" ]]

# A missing firewall journal cannot be compensated by a valid file snapshot.
mkdir -m 700 "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,operation:"create",expected_revision:"9",owner_pid:999999,
  owner_start:"1",before_active:true,phase:"service"}' \
  > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
create_managed_state_snapshot "${SB_PROJECT_DIR}.instance-write.lock/snapshot" >/dev/null
expect_failure recovery_missing_firewall recover mixed --json --yes --expected-revision 9
jq -e '.transaction.status=="rollback_failed" and .transaction.manual_intervention_required' \
  "${TMP_DIR}/recovery_missing_firewall.json" >/dev/null
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
rm -rf -- "${SB_PROJECT_DIR}.instance-write.lock"

# An explicitly rebuilt legacy fixture can delete its only Mixed instance
# directly: creating the first empty tombstone is a real lifecycle change.
rm -f -- "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=1 NODE_NAME=legacy PORT=2083 \
  AUTH_ENABLED=y USERNAME=public-user PASSWORD=public-password \
  > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
expect_success delete_legacy_directly 1 delete mixed --json --yes --expected-revision 0 --id main >/dev/null
jq -e '.revision==1 and .instances==[]' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]

# An inactive service stays inactive on both successful writes and rollback.
printf 'inactive\n' > "${SBV_INSTANCE_SYSTEMCTL_STATE_FILE}"
inactive_restarts=$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")
expect_success create_inactive 2 create mixed --json --yes --expected-revision 1 --file "${TMP_DIR}/edge.json" >/dev/null
[[ "$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")" == "${inactive_restarts}" ]]
touch "${TMP_DIR}/inactive-firewall-fail"
export SBV_INSTANCE_FIREWALL_APPLY_FAIL_FILE="${TMP_DIR}/inactive-firewall-fail"
inactive_before=$(managed_fingerprint)
expect_failure rollback_inactive create mixed --json --yes --expected-revision 2 --file "${TMP_DIR}/beta.json"
jq -e '.transaction.status=="rolled_back"' "${TMP_DIR}/rollback_inactive.json" >/dev/null
[[ "$(managed_fingerprint)" == "${inactive_before}" ]]
[[ "$(<"${SBV_INSTANCE_SYSTEMCTL_STATE_FILE}")" == inactive ]]
[[ "$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")" == "${inactive_restarts}" ]]
unset SBV_INSTANCE_FIREWALL_APPLY_FAIL_FILE

# Public readers and other writers cannot observe or replace a state while a
# management process owns the exclusive runtime lock.
exec {held_descriptor}>"${SB_PROJECT_DIR}.management.flock"
flock -x "${held_descriptor}"
if locked_output=$(SB_MANAGEMENT_LOCK_FD= agent_dispatch nodes --json 2>"${TMP_DIR}/read-lock.stderr"); then
  printf 'Agent reader bypassed the exclusive management lock\n' >&2
  exit 1
fi
jq -e '.error=="instance_write_busy" and .ok==false' <<< "${locked_output}" >/dev/null
exec {held_descriptor}>&-

printf 'mixed instance lifecycle checks passed; service restarts=%s\n' "$(<"${SBV_INSTANCE_SYSTEMCTL_COUNT_FILE}")"
