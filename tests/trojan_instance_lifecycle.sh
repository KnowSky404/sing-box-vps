#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 240

TROJAN_REAL_CORE=${SINGBOX_BINARY_114:-${SINGBOX_BINARY_113:-}}
export SBV_TROJAN_REAL_CORE="${TROJAN_REAL_CORE}"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_CORE'
#!/usr/bin/env bash
case "${1:-}" in
  version)
    if [[ -n "${SBV_TROJAN_REAL_CORE:-}" && -x "${SBV_TROJAN_REAL_CORE}" ]]; then
      exec "${SBV_TROJAN_REAL_CORE}" "$@"
    fi
    printf 'sing-box version 1.14.0\n'
    ;;
  check)
    if [[ -n "${SBV_TROJAN_CHECK_FAIL_FILE:-}" && -e "${SBV_TROJAN_CHECK_FAIL_FILE}" ]]; then
      printf 'injected core-check failure\n' >&2
      exit 23
    fi
    if [[ -n "${SBV_TROJAN_REAL_CORE:-}" && -x "${SBV_TROJAN_REAL_CORE}" ]]; then
      exec "${SBV_TROJAN_REAL_CORE}" "$@"
    fi
    exit 0
    ;;
  *) exit 64 ;;
esac
EOF_CORE
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
state_file=${SBV_TROJAN_SYSTEMCTL_STATE_FILE:?missing state file}
count_file=${SBV_TROJAN_SYSTEMCTL_COUNT_FILE:?missing count file}
log_file=${SBV_TROJAN_SYSTEMCTL_LOG_FILE:?missing log file}
printf '%s\n' "$*" >> "${log_file}"
if [[ "$*" == 'show -p ActiveState --value sing-box' || "$*" == 'show sing-box --property=ActiveState --value' ]]; then
  cat "${state_file}"
  exit 0
fi
case "${1:-}:${2:-}:${3:-}" in
  is-active:--quiet:sing-box) [[ "$(<"${state_file}")" == active ]] ;;
  is-active:sing-box:) cat "${state_file}"; [[ "$(<"${state_file}")" == active ]] ;;
  restart:sing-box:)
    count=$(<"${count_file}")
    printf '%s\n' "$((count + 1))" > "${count_file}"
    if [[ -n "${SBV_TROJAN_RESTART_FAIL_FILE:-}" && -e "${SBV_TROJAN_RESTART_FAIL_FILE}" ]]; then
      rm -f -- "${SBV_TROJAN_RESTART_FAIL_FILE}"
      exit 55
    fi
    printf 'active\n' > "${state_file}"
    ;;
  stop:sing-box:) printf 'inactive\n' > "${state_file}" ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

# Source at top level for Bash 4.2 registry compatibility.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
printf '0\n' > "${TMP_DIR}/systemctl.count"
: > "${TMP_DIR}/systemctl.log"
export SBV_TROJAN_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
export SBV_TROJAN_SYSTEMCTL_COUNT_FILE="${TMP_DIR}/systemctl.count"
export SBV_TROJAN_SYSTEMCTL_LOG_FILE="${TMP_DIR}/systemctl.log"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed,socks
PROTOCOL_STATE_VERSION=1
EOF_INDEX
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF_MIXED'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_MIXED
cat > "${SB_PROTOCOL_STATE_DIR}/socks.env" <<'EOF_SOCKS'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_SOCKS
cat > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" <<'EOF_MIXED_STORE'
{"schema_version":1,"protocol":"mixed","revision":4,"default_instance_id":"main","instances":[
  {"id":"main","name":"Existing Mixed","tag":"mixed-in","listen":{"address":"127.0.0.1","port":2080},
   "authentication":{"enabled":true,"username":"mixed-user","password":"mixed-password"},"outbound_policy":"default","dependencies":[]}
]}
EOF_MIXED_STORE
cat > "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" <<'EOF_SOCKS_STORE'
{"schema_version":1,"protocol":"socks","revision":2,"default_instance_id":"socks-main","instances":[
  {"id":"socks-main","name":"Existing SOCKS","tag":"socks-in","listen":{"address":"127.0.0.1","port":2081},
   "authentication":{"enabled":true,"username":"socks-user","password":"socks-password"},"outbound_policy":"default","dependencies":[]}
]}
EOF_SOCKS_STORE
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF_CONFIG'
{
  "log":{"level":"info"},
  "inbounds":[
    {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":2080,"users":[{"username":"mixed-user","password":"mixed-password"}]},
    {"type":"socks","tag":"socks-in","listen":"127.0.0.1","listen_port":2081,"users":[{"username":"socks-user","password":"socks-password"}]}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "route":{"rules":[
    {"inbound":"mixed-in","action":"sniff"},{"inbound":"mixed-in","action":"route","outbound":"direct"},
    {"inbound":"socks-in","action":"sniff"},{"inbound":"socks-in","action":"route","outbound":"direct"}
  ],"final":"direct"}
}
EOF_CONFIG
printf '[Unit]\nDescription=fixture sing-box\n' > "${SINGBOX_SERVICE_FILE}"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=trojan.example' \
  -keyout "${TMP_DIR}/trojan.key" -out "${TMP_DIR}/trojan.crt" >/dev/null 2>&1
cp -- "${TMP_DIR}/trojan.crt" "${TMP_DIR}/trojan-alt.crt"
cp -- "${TMP_DIR}/trojan.key" "${TMP_DIR}/trojan-alt.key"

firewall_log="${TMP_DIR}/firewall.log"
firewall_candidate="${TMP_DIR}/firewall-candidate.json"
firewall_applied="${TMP_DIR}/firewall-applied.json"
firewall_before="${TMP_DIR}/firewall-before.json"
: > "${firewall_log}"
printf '[]\n' > "${firewall_applied}"
trojan_firewall_ledger() {
  jq -c '[.inbounds[]? | select(.type == "trojan") |
    {tag,port:.listen_port,transport:(.transport.type // "none"),network:(if .transport.type == "quic" then "udp" else "tcp" end)}]
    | sort_by([.port,.network,.tag])' "$1"
}
instance_firewall_prepare() {
  local old_config=${1:?} new_config=${2:?} journal=${3:?}
  printf 'prepare\n' >> "${firewall_log}"
  trojan_firewall_ledger "${old_config}" > "${firewall_before}"
  trojan_firewall_ledger "${new_config}" > "${firewall_candidate}"
  jq -n --argjson before "$(<"${firewall_before}")" --argjson after "$(<"${firewall_candidate}")" \
    '{schema_version:1,status:"prepared",backend_statuses:[],diagnostics:[],before_ledger:$before,after_ledger:$after}' > "${journal}"
}
instance_firewall_apply() { printf 'apply\n' >> "${firewall_log}"; cp -- "${firewall_candidate}" "${firewall_applied}"; }
instance_firewall_rollback() {
  printf 'rollback\n' >> "${firewall_log}"
  if [[ -n "${SBV_TROJAN_ROLLBACK_FAIL_FILE:-}" && -e "${SBV_TROJAN_ROLLBACK_FAIL_FILE}" ]]; then return 71; fi
  cp -- "${firewall_before}" "${firewall_applied}"
}
export SBV_INSTANCE_FIREWALL_LOG_FILE="${firewall_log}"

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
    '.ok == true and .protocol == "trojan" and .revision == $revision and
     .data.ok == true and .data.protocol == "trojan" and .data.revision == $revision' <<< "${output}" >/dev/null
}
expect_failure() {
  local label=$1
  shift
  local output status
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded:\n%s\n' "${label}" "${output}" >&2
    return 1
  else status=$?; fi
  (( status != 0 )) || return 1
  printf '%s\n' "${output}" > "${TMP_DIR}/${label}.json"
  jq -e '.ok == false and .protocol == "trojan" and (.error|type=="string") and
    .data.ok == false and .data.protocol == "trojan"' <<< "${output}" >/dev/null
  if grep -Eq 'mixed-password|socks-password|native-password|ws-password|quic-password|public-password' <<< "${output}"; then
    printf '%s leaked credentials\n' "${label}" >&2
    return 1
  fi
}
expect_confirmation_failure() {
  local label=$1
  shift
  local output
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then return 1; fi
  jq -e '.ok == false and .error == "confirmation_required" and
    .data.ok == false and .data.error == "confirmation_required"' <<< "${output}" >/dev/null
}
expect_untrusted_recovery_failure() {
  local label=$1
  shift
  local output
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then return 1; fi
  jq -e '.ok == false and .error == "instance_recovery_untrusted" and
    .data.ok == false and .data.error == "instance_recovery_untrusted"' <<< "${output}" >/dev/null
}
state_fingerprint() {
  (
    cd "${SB_PROJECT_DIR}"
    find . -mindepth 1 ! -path './.instance-transactions' ! -path './.instance-transactions/*' \
      ! -path './.instance-write.lock' ! -path './.instance-write.lock/*' -printf '%y %m %p\n' | sort
    while IFS= read -r -d '' file; do sha256sum "${file}"; done < <(
      find . -type f ! -path './.instance-transactions/*' ! -path './.instance-write.lock/*' -print0 | sort -z)
  )
  stat -c '%y %a %n' "${SINGBOX_SERVICE_FILE}"
  sha256sum "${SINGBOX_SERVICE_FILE}"
}
assert_base_preserved() {
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${mixed_marker_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")" == "${socks_marker_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")" == "${mixed_store_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${socks_store_hash}" ]]
  [[ "$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed" or .type == "socks")],rules:[.route.rules[] | select(.inbound == "mixed-in" or .inbound == "socks-in")]}' "${SINGBOX_CONFIG_FILE}")" == "${base_config_snapshot}" ]]
}
assert_trojan_ledger() { [[ "$(<"${firewall_applied}")" == "$1" ]]; }
make_record() {
  local id=$1 name=$2 tag=$3 port=$4 address=$5 tls=$6 cert=$7 key=$8 transport=$9 users=${10} file=${11}
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson tls "${tls}" --arg cert "${cert}" --arg key "${key}" \
    --argjson transport "${transport}" --argjson users "${users}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},
      tls:($tls + (if $tls.enabled then {certificate_path:$cert,key_path:$key} else {} end)),
      client_trust:(if $tls.enabled then "certificate" else "system" end),transport:$transport,
      outbound_policy:"default",dependencies:[]}' > "${file}"
}

declare -F agent_cli >/dev/null || { printf 'missing public Agent API: agent_cli\n' >&2; exit 1; }
make_record native 'Native Trojan' trojan-native 2082 127.0.0.1 '{"enabled":false}' '' '' '{"type":"none"}' '[{"name":"native-user","password":"native-password"}]' "${TMP_DIR}/native.json"
make_record ws 'WebSocket Trojan' trojan-ws 2083 127.0.0.1 '{"enabled":true,"server_name":"trojan.example"}' "${TMP_DIR}/trojan.crt" "${TMP_DIR}/trojan.key" '{"type":"ws","path":"/trojan","headers":{"Host":"trojan.example"}}' '[{"name":"ws-user","password":"ws-password"}]' "${TMP_DIR}/ws.json"
make_record quic 'QUIC Trojan' trojan-quic 2082 127.0.0.1 '{"enabled":true,"server_name":"trojan.example"}' "${TMP_DIR}/trojan-alt.crt" "${TMP_DIR}/trojan-alt.key" '{"type":"quic"}' '[{"name":"quic-user","password":"quic-password"}]' "${TMP_DIR}/quic.json"
make_record public 'Public Trojan' trojan-public 2084 0.0.0.0 '{"enabled":true,"server_name":"trojan.example"}' "${TMP_DIR}/trojan.crt" "${TMP_DIR}/trojan.key" '{"type":"grpc","service_name":"trojan"}' '[{"name":"public-user","password":"public-password"}]' "${TMP_DIR}/public.json"

mixed_marker_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
socks_marker_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")
mixed_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")
socks_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")
base_config_snapshot=$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed" or .type == "socks")],rules:[.route.rules[] | select(.inbound == "mixed-in" or .inbound == "socks-in")]}' "${SINGBOX_CONFIG_FILE}")

expect_success create_native 1 create trojan --json --yes --expected-revision 0 --file "${TMP_DIR}/native.json"
jq -e '.revision == 1 and .default_instance_id == "native" and .instances[0].tls == {enabled:false} and .instances[0].client_trust == "system" and .instances[0].transport.type == "none"' "${SB_PROTOCOL_STATE_DIR}/instances/trojan.json" >/dev/null
assert_trojan_ledger '[{"tag":"trojan-native","port":2082,"transport":"none","network":"tcp"}]'
assert_base_preserved
expect_confirmation_failure missing_confirmation create trojan --json --expected-revision 1 --file "${TMP_DIR}/ws.json"
expect_failure stale_revision create trojan --json --yes --expected-revision 0 --file "${TMP_DIR}/ws.json"
expect_success create_ws 2 create trojan --json --yes --expected-revision 1 --file "${TMP_DIR}/ws.json"
expect_success create_quic 3 create trojan --json --yes --expected-revision 2 --file "${TMP_DIR}/quic.json"
jq -e '([.instances[].id]|sort)==["native","quic","ws"] and
  any(.instances[]; .id=="ws" and .tls.enabled and .client_trust=="certificate" and .transport.type=="ws") and
  any(.instances[]; .id=="quic" and .transport.type=="quic")' "${SB_PROTOCOL_STATE_DIR}/instances/trojan.json" >/dev/null
assert_trojan_ledger '[{"tag":"trojan-native","port":2082,"transport":"none","network":"tcp"},{"tag":"trojan-quic","port":2082,"transport":"quic","network":"udp"},{"tag":"trojan-ws","port":2083,"transport":"ws","network":"tcp"}]'
assert_base_preserved

# Stable tags, credentials, routing, and TLS references survive replacement.
jq '.name="WebSocket Trojan replaced" | .authentication.users[0].password="ws-password-2" | .transport.headers.Host="trojan.example"' \
  "${TMP_DIR}/ws.json" > "${TMP_DIR}/ws-replaced.json"
expect_success replace_ws 4 replace trojan --json --yes --expected-revision 3 --file "${TMP_DIR}/ws-replaced.json"
jq -e 'any(.instances[]; .id=="ws" and .tag=="trojan-ws" and .name=="WebSocket Trojan replaced" and .authentication.users[0].password=="ws-password-2") and any(.instances[]; .id=="quic")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/trojan.json" >/dev/null
assert_base_preserved
before_noop=$(<"${SBV_TROJAN_SYSTEMCTL_COUNT_FILE}")
expect_success replace_noop 4 replace trojan --json --yes --expected-revision 4 --file "${TMP_DIR}/ws-replaced.json"
[[ "$(<"${SBV_TROJAN_SYSTEMCTL_COUNT_FILE}")" == "${before_noop}" ]]
expect_success set_default_quic 5 default trojan --json --yes --expected-revision 4 --id quic

# Core-check and restart failures must leave the managed tree unchanged.
before_restart_failure=$(state_fingerprint)
touch "${TMP_DIR}/restart-fail"
export SBV_TROJAN_RESTART_FAIL_FILE="${TMP_DIR}/restart-fail"
expect_failure restart_failure delete trojan --json --yes --expected-revision 5 --id ws
unset SBV_TROJAN_RESTART_FAIL_FILE
jq -e '.error=="instance_apply_failed" and .transaction.status=="rolled_back"' "${TMP_DIR}/restart_failure.json" >/dev/null
[[ "$(state_fingerprint)" == "${before_restart_failure}" ]]
assert_base_preserved
touch "${TMP_DIR}/core-fail"
export SBV_TROJAN_CHECK_FAIL_FILE="${TMP_DIR}/core-fail"
expect_failure candidate_failure create trojan --json --yes --expected-revision 5 --file "${TMP_DIR}/public.json"
unset SBV_TROJAN_CHECK_FAIL_FILE
[[ "$(state_fingerprint)" == "${before_restart_failure}" ]]

before_rollback_failure=$(state_fingerprint)
touch "${TMP_DIR}/restart-fail" "${TMP_DIR}/rollback-fail"
export SBV_TROJAN_RESTART_FAIL_FILE="${TMP_DIR}/restart-fail"
export SBV_TROJAN_ROLLBACK_FAIL_FILE="${TMP_DIR}/rollback-fail"
expect_failure rollback_failure delete trojan --json --yes --expected-revision 5 --id ws
jq -e '.error=="instance_rollback_failed" and .transaction.status=="rollback_failed" and .transaction.manual_intervention_required==true' \
  "${TMP_DIR}/rollback_failure.json" >/dev/null
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
expect_failure recovery_still_failed recover trojan --json --yes --expected-revision 5
unset SBV_TROJAN_RESTART_FAIL_FILE SBV_TROJAN_ROLLBACK_FAIL_FILE
expect_success recovery 5 recover trojan --json --yes --expected-revision 5
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
[[ "$(state_fingerprint)" == "${before_rollback_failure}" ]]
assert_base_preserved

# Delete TCP owner while retaining the UDP QUIC owner on the shared port.
expect_success delete_native 6 delete trojan --json --yes --expected-revision 5 --id native
assert_trojan_ledger '[{"tag":"trojan-quic","port":2082,"transport":"quic","network":"udp"},{"tag":"trojan-ws","port":2083,"transport":"ws","network":"tcp"}]'
expect_success delete_ws 7 delete trojan --json --yes --expected-revision 6 --id ws
assert_trojan_ledger '[{"tag":"trojan-quic","port":2082,"transport":"quic","network":"udp"}]'
expect_success delete_quic 8 delete trojan --json --yes --expected-revision 7 --id quic
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/trojan.env" ]]
jq -e '.protocol=="trojan" and .revision==8 and .instances==[] and .default_instance_id==""' "${SB_PROTOCOL_STATE_DIR}/instances/trojan.json" >/dev/null
assert_trojan_ledger '[]'
assert_base_preserved
[[ -f "${TMP_DIR}/trojan.crt" && -f "${TMP_DIR}/trojan.key" && -f "${TMP_DIR}/trojan-alt.crt" && -f "${TMP_DIR}/trojan-alt.key" ]]

before_public=$(state_fingerprint)
expect_failure public_without_consent create trojan --json --yes --expected-revision 8 --file "${TMP_DIR}/public.json"
[[ "$(state_fingerprint)" == "${before_public}" ]]
expect_success create_public 9 create trojan --json --yes --allow-public --expected-revision 8 --file "${TMP_DIR}/public.json"
expect_success delete_public 10 delete trojan --json --yes --expected-revision 9 --id public
[[ -f "${TMP_DIR}/trojan.crt" && -f "${TMP_DIR}/trojan.key" ]]

recovery_lock="${SB_PROJECT_DIR}.instance-write.lock"
mkdir -m 700 "${recovery_lock}"
jq -n --arg expected 10 --argjson pid 999999 --arg start 1 \
  '{schema_version:1,protocol:"mixed",operation:"delete",expected_revision:$expected,owner_pid:$pid,owner_start:$start,before_active:true,phase:"service"}' \
  > "${recovery_lock}/transaction.json"
expect_untrusted_recovery_failure wrong_protocol recover trojan --json --yes --expected-revision 10
rm -rf -- "${recovery_lock}"
mkdir -m 700 "${recovery_lock}"
jq -n --arg expected 10 --argjson pid 999999 --arg start 1 \
  '{schema_version:1,operation:"delete",expected_revision:$expected,owner_pid:$pid,owner_start:$start,before_active:true,phase:"prepare"}' \
  > "${recovery_lock}/transaction.json"
if output=$(agent_cli instance recover mixed --json --yes --expected-revision 10 2>"${TMP_DIR}/old-recovery.stderr"); then
  jq -e '.ok==true and .protocol=="mixed" and .revision==10' <<< "${output}" >/dev/null
else
  printf 'old missing-protocol journal was not Mixed-compatible\n' >&2
  exit 1
fi
[[ ! -e "${recovery_lock}" ]]

printf 'Trojan instance lifecycle checks passed; service restarts=%s; core_check=%s\n' \
  "$(<"${SBV_TROJAN_SYSTEMCTL_COUNT_FILE}")" \
  "$([[ -n "${SBV_TROJAN_REAL_CORE:-}" && -x "${SBV_TROJAN_REAL_CORE}" ]] && printf real || printf mock)"
