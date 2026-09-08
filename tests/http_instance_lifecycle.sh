#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 240

# Exercise standalone HTTP beside an existing structured Mixed listener. The
# service, core check, and firewall are private test doubles.
cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check)
    if [[ -n "${SBV_HTTP_CHECK_FAIL_FILE:-}" && -e "${SBV_HTTP_CHECK_FAIL_FILE}" ]]; then
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
state_file=${SBV_HTTP_SYSTEMCTL_STATE_FILE:?missing state file}
count_file=${SBV_HTTP_SYSTEMCTL_COUNT_FILE:?missing count file}
log_file=${SBV_HTTP_SYSTEMCTL_LOG_FILE:?missing log file}
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
    if [[ -n "${SBV_HTTP_RESTART_FAIL_ONCE_FILE:-}" && -e "${SBV_HTTP_RESTART_FAIL_ONCE_FILE}" ]]; then
      rm -f "${SBV_HTTP_RESTART_FAIL_ONCE_FILE}"
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

# Source at top level so Bash 4.2 retains the readonly protocol registry.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
printf '0\n' > "${TMP_DIR}/systemctl.count"
: > "${TMP_DIR}/systemctl.log"
export SBV_HTTP_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
export SBV_HTTP_SYSTEMCTL_COUNT_FILE="${TMP_DIR}/systemctl.count"
export SBV_HTTP_SYSTEMCTL_LOG_FILE="${TMP_DIR}/systemctl.log"

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

cert_alpha="${TMP_DIR}/alpha.crt"
key_alpha="${TMP_DIR}/alpha.key"
cert_beta="${TMP_DIR}/beta.crt"
key_beta="${TMP_DIR}/beta.key"
printf 'alpha certificate\n' > "${cert_alpha}"
printf 'alpha key\n' > "${key_alpha}"
printf 'beta certificate\n' > "${cert_beta}"
printf 'beta key\n' > "${key_beta}"

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 address=$5 user=$6 password=$7 cert=$8 key=$9 file=${10}
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --arg address "${address}" --argjson port "${port}" --arg user "${user}" --arg password "${password}" \
    --arg cert "${cert}" --arg key "${key}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},
      authentication:{enabled:true,username:$user,password:$password},
      outbound_policy:"default",
      tls:{enabled:true,server_name:"proxy.example.test",certificate_path:$cert,key_path:$key},
      dependencies:[]}' > "${file}"
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
instance_firewall_rollback() {
  printf 'rollback\n' >> "${firewall_log}"
  [[ -z "${SBV_HTTP_ROLLBACK_FAIL_FILE:-}" || ! -e "${SBV_HTTP_ROLLBACK_FAIL_FILE}" ]]
}
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
  if grep -Eq 'mixed-password|alpha-password|beta-password|gamma-password|public-password' <<< "${output}"; then
    printf '%s leaked credentials\n' "${label}" >&2
    return 1
  fi
}

expect_recovery_precheck_failure() {
  local label=$1 expected_code=$2 journal_dir=$3
  shift 3
  local output status journal_hash
  journal_hash=$(sha256sum "${journal_dir}/transaction.json")
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded:\n%s\n' "${label}" "${output}" >&2
    return 1
  else
    status=$?
  fi
  (( status != 0 )) || return 1
  printf '%s\n' "${output}" > "${TMP_DIR}/${label}.json"
  jq -e --arg code "${expected_code}" \
    '.ok == false and .error == $code and .data.ok == false and .data.error == $code' \
    <<< "${output}" >/dev/null
  [[ "$(sha256sum "${journal_dir}/transaction.json")" == "${journal_hash}" ]]
}

state_fingerprint() {
  (
    cd "${SB_PROJECT_DIR}"
    find . -mindepth 1 \
      ! -path './.instance-transactions' ! -path './.instance-transactions/*' \
      ! -path './.instance-write.lock' ! -path './.instance-write.lock/*' \
      -printf '%y %m %p\n' | sort
    while IFS= read -r -d '' file; do sha256sum "${file}"; done < <(
      find . -type f \
        ! -path './.instance-transactions/*' ! -path './.instance-write.lock/*' \
        -print0 | sort -z
    )
  )
  stat -c '%y %a %n' "${SINGBOX_SERVICE_FILE}"
  sha256sum "${SINGBOX_SERVICE_FILE}"
}

assert_mixed_preserved() {
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${mixed_marker_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")" == "${mixed_store_hash}" ]]
  [[ "$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed")],rules:[.route.rules[] | select(.inbound == "mixed-in")]}' "${SINGBOX_CONFIG_FILE}")" == "${mixed_config_snapshot}" ]]
}

declare -F agent_cli >/dev/null || { printf 'missing public Agent API: agent_cli\n' >&2; exit 1; }
make_record alpha 'Alpha HTTP' http-alpha 2081 127.0.0.1 alpha-user alpha-password "${cert_alpha}" "${key_alpha}" "${TMP_DIR}/alpha.json"
make_record beta 'Beta HTTP' http-beta 2082 127.0.0.1 beta-user beta-password "${cert_beta}" "${key_beta}" "${TMP_DIR}/beta.json"
make_record gamma 'Gamma HTTP' http-gamma 2083 127.0.0.1 gamma-user gamma-password "${cert_alpha}" "${key_alpha}" "${TMP_DIR}/gamma.json"
make_record public 'Public HTTP' http-public 2084 0.0.0.0 public-user public-password "${cert_beta}" "${key_beta}" "${TMP_DIR}/public.json"

mixed_marker_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
mixed_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")
mixed_config_snapshot=$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed")],rules:[.route.rules[] | select(.inbound == "mixed-in")]}' "${SINGBOX_CONFIG_FILE}")

# Create two HTTP instances and retain their typed TLS references.
expect_success create_alpha 1 http create http --json --yes --expected-revision 0 --file "${TMP_DIR}/alpha.json" >/dev/null
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/http.env"
jq -e --arg cert "${cert_alpha}" --arg key "${key_alpha}" \
  '.schema_version == 1 and .protocol == "http" and .revision == 1 and
   .default_instance_id == "alpha" and .instances[0].tls.enabled == true and
   .instances[0].tls.certificate_path == $cert and .instances[0].tls.key_path == $key' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
assert_mixed_preserved
[[ -f "${cert_alpha}" && -f "${key_alpha}" ]]

expect_success create_beta 2 http create http --json --yes --expected-revision 1 --file "${TMP_DIR}/beta.json" >/dev/null
jq -e '([.instances[].id] | sort) == ["alpha","beta"] and .default_instance_id == "alpha" and
  any(.instances[]; .id == "beta" and .tls.enabled == true)' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
jq -e '([.inbounds[] | select(.type == "http")] | length) == 2 and
  any(.inbounds[]; .type == "mixed" and .tag == "mixed-in")' "${SINGBOX_CONFIG_FILE}" >/dev/null
assert_mixed_preserved
[[ -f "${cert_beta}" && -f "${key_beta}" ]]

# Malformed HTTP credentials and immutable tags fail before publication.
jq '.authentication.username="bad:user"' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/bad-colon.json"
before_invalid=$(state_fingerprint)
expect_failure malformed_auth_colon http create http --json --yes --expected-revision 2 --file "${TMP_DIR}/bad-colon.json"
[[ "$(state_fingerprint)" == "${before_invalid}" ]]
jq '.authentication.password="bad\u0001password"' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/bad-control.json"
expect_failure malformed_auth_control http create http --json --yes --expected-revision 2 --file "${TMP_DIR}/bad-control.json"
[[ "$(state_fingerprint)" == "${before_invalid}" ]]
jq '.tag="http-alpha-renamed"' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/changed-tag.json"
expect_failure immutable_tag http replace http --json --yes --expected-revision 2 --file "${TMP_DIR}/changed-tag.json"
[[ "$(state_fingerprint)" == "${before_invalid}" ]]

make_record alpha 'Alpha HTTP replaced' http-alpha 2081 127.0.0.1 alpha-user alpha-password-2 "${cert_alpha}" "${key_alpha}" "${TMP_DIR}/alpha-replaced.json"
expect_success replace_alpha 3 http replace http --json --yes --expected-revision 2 --file "${TMP_DIR}/alpha-replaced.json" >/dev/null
jq -e 'any(.instances[]; .id == "alpha" and .tag == "http-alpha" and
  .name == "Alpha HTTP replaced" and .authentication.password == "alpha-password-2") and
  any(.instances[]; .id == "beta" and .tls.certificate_path != "")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
assert_mixed_preserved
[[ -f "${cert_alpha}" && -f "${key_alpha}" && -f "${cert_beta}" && -f "${key_beta}" ]]

expect_success set_default_beta 4 http default http --json --yes --expected-revision 3 --id beta >/dev/null
jq -e '.default_instance_id == "beta"' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null

# A restart failure rolls back cleanly; a coupled firewall failure retains the
# transaction for explicit recovery.
before_restart_failure=$(state_fingerprint)
touch "${TMP_DIR}/restart-fail"
export SBV_HTTP_RESTART_FAIL_ONCE_FILE="${TMP_DIR}/restart-fail"
expect_failure restart_failure http create http --json --yes --expected-revision 4 --file "${TMP_DIR}/gamma.json"
jq -e '.error == "instance_apply_failed" and .transaction.status == "rolled_back"' "${TMP_DIR}/restart_failure.json" >/dev/null
[[ "$(state_fingerprint)" == "${before_restart_failure}" ]]
assert_mixed_preserved
[[ -f "${cert_alpha}" && -f "${key_alpha}" ]]

before_rollback_failure=$(state_fingerprint)
touch "${TMP_DIR}/restart-fail" "${TMP_DIR}/rollback-fail"
export SBV_HTTP_RESTART_FAIL_ONCE_FILE="${TMP_DIR}/restart-fail"
export SBV_HTTP_ROLLBACK_FAIL_FILE="${TMP_DIR}/rollback-fail"
expect_failure rollback_failure http create http --json --yes --expected-revision 4 --file "${TMP_DIR}/gamma.json"
jq -e '.error == "instance_rollback_failed" and .transaction.status == "rollback_failed" and
  .transaction.manual_intervention_required == true' "${TMP_DIR}/rollback_failure.json" >/dev/null
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
expect_failure recovery_still_failed http recover http --json --yes --expected-revision 4
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
rm -f "${SBV_HTTP_ROLLBACK_FAIL_FILE}"
unset SBV_HTTP_ROLLBACK_FAIL_FILE SBV_HTTP_RESTART_FAIL_ONCE_FILE
expect_success recovery 4 http recover http --json --yes --expected-revision 4 >/dev/null
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
[[ "$(state_fingerprint)" == "${before_rollback_failure}" ]]
assert_mixed_preserved
[[ -f "${cert_alpha}" && -f "${key_alpha}" && -f "${cert_beta}" && -f "${key_beta}" ]]

expect_success delete_alpha 5 http delete http --json --yes --expected-revision 4 --id alpha >/dev/null
jq -e '([.instances[].id] | sort) == ["beta"] and .default_instance_id == "beta"' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
assert_mixed_preserved
expect_success delete_beta 6 http delete http --json --yes --expected-revision 5 --id beta >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/http.env" ]]
jq -e '.schema_version == 1 and .protocol == "http" and .revision == 6 and
  .instances == [] and .default_instance_id == ""' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
indexed_protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${SB_PROTOCOL_INDEX_FILE}")
[[ ",${indexed_protocols}," != *,http,* && ",${indexed_protocols}," == *,mixed,* ]]
jq -e '([.inbounds[] | select(.type == "http")] | length) == 0 and
  any(.inbounds[]; .type == "mixed" and .tag == "mixed-in")' "${SINGBOX_CONFIG_FILE}" >/dev/null
assert_mixed_preserved
[[ -f "${cert_alpha}" && -f "${key_alpha}" && -f "${cert_beta}" && -f "${key_beta}" ]]

# Public HTTP requires explicit consent even when reviving a tombstone.
before_public=$(state_fingerprint)
expect_failure public_without_consent http create http --json --yes --expected-revision 6 --file "${TMP_DIR}/public.json"
[[ "$(state_fingerprint)" == "${before_public}" ]]
expect_success create_public 7 http create http --json --yes --allow-public --expected-revision 6 --file "${TMP_DIR}/public.json" >/dev/null
jq -e '.revision == 7 and [.instances[].id] == ["public"] and .instances[0].listen.address == "0.0.0.0"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
assert_mixed_preserved
expect_success delete_public 8 http delete http --json --yes --expected-revision 7 --id public >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/http.env" ]]
jq -e '.revision == 8 and .instances == [] and .default_instance_id == ""' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
assert_mixed_preserved
[[ -f "${cert_alpha}" && -f "${key_alpha}" && -f "${cert_beta}" && -f "${key_beta}" ]]

# A conditional route is not a managed fallback merely because it targets a
# known HTTP tag. Missing sniff rules may be prepended, but the generated
# unconditional route must remain after retained custom routing rules.
route_fixture_old_config="${TMP_DIR}/route-fixture-old.json"
route_fixture_old_store="${TMP_DIR}/route-fixture-old-store.json"
route_fixture_new_store="${TMP_DIR}/route-fixture-new-store.json"
jq -n '{
  log:{level:"info"},
  inbounds:[{type:"http",tag:"http-alpha",listen:"127.0.0.1",listen_port:2091}],
  outbounds:[{type:"direct",tag:"direct"}],
  route:{rules:[
    {inbound:"http-alpha",action:"route",outbound:"direct",ip_is_private:true},
    {inbound:"http-beta",action:"reject",ip_is_private:true}
  ],final:"direct"}
}' > "${route_fixture_old_config}"
jq -n '{
  schema_version:1,protocol:"http",revision:1,default_instance_id:"http-alpha",
  instances:[{id:"http-alpha",name:"Alpha",tag:"http-alpha",
    listen:{address:"127.0.0.1",port:2091},
    authentication:{enabled:false,username:"",password:""},
    outbound_policy:"direct",tls:{enabled:false},dependencies:[]}]
}' > "${route_fixture_old_store}"
jq -n '{
  schema_version:1,protocol:"http",revision:2,default_instance_id:"http-alpha",
  instances:[
    {id:"http-alpha",name:"Alpha",tag:"http-alpha",
      listen:{address:"127.0.0.1",port:2091},
      authentication:{enabled:false,username:"",password:""},
      outbound_policy:"direct",tls:{enabled:false},dependencies:[]},
    {id:"http-beta",name:"Beta",tag:"http-beta",
      listen:{address:"127.0.0.1",port:2092},
      authentication:{enabled:false,username:"",password:""},
      outbound_policy:"direct",tls:{enabled:false},dependencies:[]}
  ]
}' > "${route_fixture_new_store}"
route_fixture_candidate=$(plain_proxy_instance_config_candidate http \
  "${route_fixture_old_config}" "${route_fixture_old_store}" "${route_fixture_new_store}")
jq -e '
  .route.rules == [
    {inbound:"http-alpha",action:"sniff"},
    {inbound:"http-beta",action:"sniff"},
    {inbound:"http-alpha",action:"route",outbound:"direct",ip_is_private:true},
    {inbound:"http-beta",action:"reject",ip_is_private:true},
    {inbound:"http-alpha",action:"route",outbound:"direct"},
    {inbound:"http-beta",action:"route",outbound:"direct"}
  ]
' <<< "${route_fixture_candidate}" >/dev/null

# Recovery refuses a journal owned by another protocol, but accepts the old
# journal shape where the protocol field was absent (legacy Mixed semantics).
recovery_lock="${SB_PROJECT_DIR}.instance-write.lock"
mkdir -m 700 "${recovery_lock}"
jq -n --arg expected "8" --argjson pid 999999 --arg start "1" \
  '{schema_version:1,protocol:"mixed",operation:"delete",expected_revision:$expected,
    owner_pid:$pid,owner_start:$start,before_active:true,phase:"prepare"}' \
  > "${recovery_lock}/transaction.json"
expect_recovery_precheck_failure wrong_protocol_recovery instance_recovery_untrusted "${recovery_lock}" \
  recover http --json --yes --expected-revision 8
[[ -d "${recovery_lock}" ]]
rm -rf -- "${recovery_lock}"

mkdir -m 700 "${recovery_lock}"
jq -n --arg expected "8" --argjson pid 999999 --arg start "1" \
  '{schema_version:1,operation:"delete",expected_revision:$expected,
    owner_pid:$pid,owner_start:$start,before_active:true,phase:"prepare"}' \
  > "${recovery_lock}/transaction.json"
expect_success old_mixed_recovery 8 mixed recover mixed --json --yes --expected-revision 8 >/dev/null
[[ ! -e "${recovery_lock}" ]]

printf 'http instance lifecycle checks passed; service restarts=%s\n' "$(<"${SBV_HTTP_SYSTEMCTL_COUNT_FILE}")"
