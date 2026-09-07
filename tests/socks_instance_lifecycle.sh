#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 240

# Exercise standalone SOCKS beside an already-active Mixed component. Every
# command uses the public Agent envelope; no host firewall or systemd is used.
cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check) exit 0 ;;
  *) printf 'unexpected sing-box invocation: %s\n' "$*" >&2; exit 64 ;;
esac
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
state_file=${SBV_SOCKS_SYSTEMCTL_STATE_FILE:?missing state file}
count_file=${SBV_SOCKS_SYSTEMCTL_COUNT_FILE:?missing count file}
log_file=${SBV_SOCKS_SYSTEMCTL_LOG_FILE:?missing log file}
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
    printf '%s\n' "$((count + 1))" > "${count_file}"
    if [[ -n "${SBV_SOCKS_RESTART_FAIL_FILE:-}" && -f "${SBV_SOCKS_RESTART_FAIL_FILE}" ]]; then
      rm -f -- "${SBV_SOCKS_RESTART_FAIL_FILE}"
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

# Source at top level so Bash 4.2 retains the readonly protocol registry.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
printf '0\n' > "${TMP_DIR}/systemctl.count"
: > "${TMP_DIR}/systemctl.log"
export SBV_SOCKS_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
export SBV_SOCKS_SYSTEMCTL_COUNT_FILE="${TMP_DIR}/systemctl.count"
export SBV_SOCKS_SYSTEMCTL_LOG_FILE="${TMP_DIR}/systemctl.log"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF_INDEX
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF_MIXED'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_MIXED
cat > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" <<'EOF_MIXED_STORE'
{"schema_version":1,"protocol":"mixed","revision":4,"default_instance_id":"main","instances":[
  {"id":"main","name":"Existing Mixed","tag":"mixed-in","listen":{"address":"127.0.0.1","port":2080},
   "authentication":{"enabled":true,"username":"mixed-user","password":"mixed-password"},
   "outbound_policy":"default","dependencies":[]}
]}
EOF_MIXED_STORE
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF_CONFIG'
{
  "log":{"level":"info"},
  "inbounds":[
    {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":2080,
     "users":[{"username":"mixed-user","password":"mixed-password"}]}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "route":{"rules":[
    {"inbound":"mixed-in","action":"sniff"},
    {"inbound":"mixed-in","action":"route","outbound":"direct"}
  ],"final":"direct"}
}
EOF_CONFIG
printf '[Unit]\nDescription=fixture sing-box\n' > "${SINGBOX_SERVICE_FILE}"

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 address=$5 user=$6 password=$7 file=$8
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --arg address "${address}" --argjson port "${port}" --arg user "${user}" --arg password "${password}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},
      authentication:{enabled:true,username:$user,password:$password},
      outbound_policy:"default",dependencies:[]}' > "${file}"
}

firewall_log="${TMP_DIR}/firewall.log"
: > "${firewall_log}"
instance_firewall_prepare() {
  printf 'prepare\n' >> "${firewall_log}"
  if [[ -n "${3:-}" ]]; then
    printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "${3}"
  fi
}
instance_firewall_apply() { printf 'apply\n' >> "${firewall_log}"; }
instance_firewall_rollback() { printf 'rollback\n' >> "${firewall_log}"; }
export SBV_INSTANCE_FIREWALL_LOG_FILE="${firewall_log}"

expect_success() {
  local label=$1 expected_revision=$2 expected_protocol=$3
  shift 3
  local output
  if ! output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly failed:\n%s\n' "${label}" "${output}" >&2
    cat "${TMP_DIR}/${label}.stderr" >&2
    return 1
  fi
  jq -e --argjson revision "${expected_revision}" --arg protocol "${expected_protocol}" \
    '.ok == true and .protocol == $protocol and .revision == $revision and
     .data.ok == true and .data.protocol == $protocol and .data.revision == $revision' \
    <<< "${output}" >/dev/null || {
    printf '%s returned an unexpected envelope:\n%s\n' "${label}" "${output}" >&2
    return 1
  }
  printf '%s' "${output}"
}

expect_failure() {
  local label=$1 expected_protocol=$2
  shift 2
  local output status
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded:\n%s\n' "${label}" "${output}" >&2
    return 1
  else
    status=$?
  fi
  (( status != 0 )) || return 1
  printf '%s\n' "${output}" > "${TMP_DIR}/${label}.json"
  jq -e --arg protocol "${expected_protocol}" \
    '.ok == false and .protocol == $protocol and (.error | type == "string") and
     .data.ok == false and .data.protocol == $protocol' <<< "${output}" >/dev/null || {
    printf '%s returned an unexpected failure envelope:\n%s\n' "${label}" "${output}" >&2
    return 1
  }
  if grep -Eq 'mixed-password|alpha-password|beta-password|public-password' <<< "${output}"; then
    printf '%s leaked credentials\n' "${label}" >&2
    return 1
  fi
}

expect_confirmation_failure() {
  local label=$1
  shift
  local output status
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded:\n%s\n' "${label}" "${output}" >&2
    return 1
  else
    status=$?
  fi
  (( status != 0 )) || return 1
  printf '%s\n' "${output}" > "${TMP_DIR}/${label}.json"
  jq -e '.ok == false and .error == "confirmation_required" and
    .data.ok == false and .data.error == "confirmation_required"' <<< "${output}" >/dev/null
}

expect_untrusted_recovery_failure() {
  local label=$1
  shift
  local output status
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded:\n%s\n' "${label}" "${output}" >&2
    return 1
  else
    status=$?
  fi
  (( status != 0 )) || return 1
  printf '%s\n' "${output}" > "${TMP_DIR}/${label}.json"
  jq -e '.ok == false and .error == "instance_recovery_untrusted" and
    .data.ok == false and .data.error == "instance_recovery_untrusted"' <<< "${output}" >/dev/null
}

assert_mixed_preserved() {
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${mixed_marker_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")" == "${mixed_store_hash}" ]]
  [[ "$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed")],rules:[.route.rules[] | select(.inbound == "mixed-in")]}' "${SINGBOX_CONFIG_FILE}")" == "${mixed_config_snapshot}" ]]
}

declare -F agent_cli >/dev/null || { printf 'missing public Agent API: agent_cli\n' >&2; exit 1; }
make_record alpha 'Alpha SOCKS' socks-alpha 2081 127.0.0.1 alpha-user alpha-password "${TMP_DIR}/alpha.json"
make_record beta 'Beta SOCKS' socks-beta 2082 127.0.0.1 beta-user beta-password "${TMP_DIR}/beta.json"
make_record public 'Public SOCKS' socks-public 2083 0.0.0.0 public-user public-password "${TMP_DIR}/public.json"

mixed_marker_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
mixed_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")
mixed_config_snapshot=$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed")],rules:[.route.rules[] | select(.inbound == "mixed-in")]}' "${SINGBOX_CONFIG_FILE}")

# First SOCKS create starts from virtual revision zero without changing Mixed.
expect_success create_alpha 1 socks create socks --json --yes --expected-revision 0 --file "${TMP_DIR}/alpha.json" >/dev/null
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/socks.env"
jq -e '.schema_version == 1 and .protocol == "socks" and .revision == 1 and
  .default_instance_id == "alpha" and [.instances[].id] == ["alpha"]' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
assert_mixed_preserved

# Duplicate listeners and stale CAS are rejected without mutation.
jq '.listen.port=2080' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/duplicate.json"
before_invalid=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")
expect_failure duplicate_port socks create socks --json --yes --expected-revision 1 --file "${TMP_DIR}/duplicate.json"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${before_invalid}" ]]
expect_failure stale_revision socks create socks --json --yes --expected-revision 0 --file "${TMP_DIR}/beta.json"
expect_confirmation_failure missing_confirmation create socks --json --expected-revision 1 --file "${TMP_DIR}/beta.json"

expect_success create_beta 2 socks create socks --json --yes --expected-revision 1 --file "${TMP_DIR}/beta.json" >/dev/null
jq -e '([.instances[].id] | sort) == ["alpha","beta"] and .default_instance_id == "alpha"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
assert_mixed_preserved

make_record alpha 'Alpha SOCKS replaced' socks-alpha 2081 127.0.0.1 alpha-user alpha-password-2 "${TMP_DIR}/alpha-replaced.json"
expect_success replace_alpha 3 socks replace socks --json --yes --expected-revision 2 --file "${TMP_DIR}/alpha-replaced.json" >/dev/null
jq -e 'any(.instances[]; .id == "alpha" and .name == "Alpha SOCKS replaced" and .authentication.password == "alpha-password-2") and
  any(.instances[]; .id == "beta" and .authentication.password == "beta-password")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
assert_mixed_preserved

# An identical replacement is a no-op and does not restart the service.
before_noop_count=$(<"${SBV_SOCKS_SYSTEMCTL_COUNT_FILE}")
before_noop_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")
expect_success replace_noop 3 socks replace socks --json --yes --expected-revision 3 --file "${TMP_DIR}/alpha-replaced.json" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${before_noop_hash}" ]]
[[ "$(<"${SBV_SOCKS_SYSTEMCTL_COUNT_FILE}")" == "${before_noop_count}" ]]

expect_success set_default_beta 4 socks default socks --json --yes --expected-revision 3 --id beta >/dev/null
jq -e '.default_instance_id == "beta" and ([.instances[].id] | sort) == ["alpha","beta"]' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
before_restart_failure=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" "${SINGBOX_CONFIG_FILE}")
export SBV_SOCKS_RESTART_FAIL_FILE="${TMP_DIR}/restart-fail-once"
touch "${SBV_SOCKS_RESTART_FAIL_FILE}"
expect_failure restart_failure socks delete socks --json --yes --expected-revision 4 --id alpha
unset SBV_SOCKS_RESTART_FAIL_FILE
jq -e '.transaction.status=="rolled_back" and .transaction.phase=="service" and
  .transaction.operation_exit_code==55 and .transaction.manual_intervention_required==false and .revision==4' \
  "${TMP_DIR}/restart_failure.json" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" "${SINGBOX_CONFIG_FILE}")" == "${before_restart_failure}" ]]
[[ "$(<"${SBV_SOCKS_SYSTEMCTL_STATE_FILE}")" == active ]]
assert_mixed_preserved
expect_success delete_alpha 5 socks delete socks --json --yes --expected-revision 4 --id alpha >/dev/null
jq -e '.revision == 5 and [.instances[].id] == ["beta"] and .default_instance_id == "beta"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
assert_mixed_preserved

# Deleting the final SOCKS instance leaves a revisioned tombstone and removes
# only the SOCKS marker/config/index entry.
expect_success delete_beta 6 socks delete socks --json --yes --expected-revision 5 --id beta >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/socks.env" ]]
jq -e '.schema_version == 1 and .protocol == "socks" and .revision == 6 and
  .default_instance_id == "" and .instances == []' "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
indexed_protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${SB_PROTOCOL_INDEX_FILE}")
[[ ",${indexed_protocols}," != *,socks,* ]]
[[ ",${indexed_protocols}," == *,mixed,* ]]
jq -e '([.inbounds[] | select(.type == "socks")] | length) == 0 and
  any(.inbounds[]; .type == "mixed" and .tag == "mixed-in")' "${SINGBOX_CONFIG_FILE}" >/dev/null
assert_mixed_preserved

# Public listeners need their separate acknowledgement, even from a tombstone.
before_public=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")
expect_failure public_without_consent socks create socks --json --yes --expected-revision 6 --file "${TMP_DIR}/public.json"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${before_public}" ]]
expect_success create_public 7 socks create socks --json --yes --allow-public --expected-revision 6 --file "${TMP_DIR}/public.json" >/dev/null
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/socks.env"
jq -e '.revision == 7 and [.instances[].id] == ["public"] and .instances[0].listen.address == "0.0.0.0"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
assert_mixed_preserved
expect_success delete_public 8 socks delete socks --json --yes --expected-revision 7 --id public >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/socks.env" ]]
jq -e '.revision == 8 and .instances == [] and .default_instance_id == ""' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
assert_mixed_preserved

# Recovery is protocol-scoped: a SOCKS journal cannot be recovered through
# Mixed, while an old journal without protocol remains Mixed-compatible.
recovery_lock="${SB_PROJECT_DIR}.instance-write.lock"
mkdir -m 700 "${recovery_lock}"
jq -n --arg expected "8" --argjson pid 999999 --arg start "1" \
  '{schema_version:1,protocol:"socks",operation:"delete",expected_revision:$expected,
    owner_pid:$pid,owner_start:$start,before_active:true,phase:"service"}' \
  > "${recovery_lock}/transaction.json"
expect_untrusted_recovery_failure wrong_protocol_recovery recover mixed --json --yes --expected-revision 8
[[ -d "${recovery_lock}" ]]
rm -rf -- "${recovery_lock}"

mkdir -m 700 "${recovery_lock}"
jq -n --arg expected "8" --argjson pid 999999 --arg start "1" \
  '{schema_version:1,operation:"delete",expected_revision:$expected,
    owner_pid:$pid,owner_start:$start,before_active:true,phase:"prepare"}' \
  > "${recovery_lock}/transaction.json"
cp "${recovery_lock}/transaction.json" "${TMP_DIR}/legacy-journal.json"
for malformed_protocol in false null 1 '[]' '{}'; do
  jq --argjson protocol "${malformed_protocol}" '.protocol=$protocol' "${TMP_DIR}/legacy-journal.json" \
    > "${recovery_lock}/transaction.json"
  expect_untrusted_recovery_failure malformed_protocol_recovery recover mixed --json --yes --expected-revision 8
  [[ -d "${recovery_lock}" ]]
done
cp "${TMP_DIR}/legacy-journal.json" "${recovery_lock}/transaction.json"
expect_success old_mixed_recovery 8 mixed recover mixed --json --yes --expected-revision 8 >/dev/null
[[ ! -e "${recovery_lock}" ]]

if agent_cli instance migrate socks --json --yes --expected-revision 8 > "${TMP_DIR}/unsupported-migrate.json"; then
  printf 'SOCKS unexpectedly offered a legacy migration\n' >&2
  exit 1
fi
jq -e '.ok==false and .error=="invalid_arguments"' "${TMP_DIR}/unsupported-migrate.json" >/dev/null

printf 'socks instance lifecycle checks passed; service restarts=%s\n' "$(<"${SBV_SOCKS_SYSTEMCTL_COUNT_FILE}")"
