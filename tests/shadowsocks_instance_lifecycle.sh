#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 240

# When the verification harness provides a pinned sing-box binary, use it for
# every lifecycle core check.  Local focused runs retain a deterministic mock
# fallback, but explicitly report that they did not produce real-core evidence.
SS_REAL_CORE=${SINGBOX_BINARY_114:-${SINGBOX_BINARY_113:-}}
export SBV_SS_REAL_CORE="${SS_REAL_CORE}"

# Exercise the typed Shadowsocks lifecycle beside already active Mixed and
# SOCKS components.  All service, core-check, and firewall operations are
# private doubles; this test does not claim real traffic evidence.
cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
case "${1:-}" in
  version)
    if [[ -n "${SBV_SS_REAL_CORE:-}" && -x "${SBV_SS_REAL_CORE}" ]]; then
      exec "${SBV_SS_REAL_CORE}" "$@"
    fi
    printf 'sing-box version 1.14.0\n'
    ;;
  check)
    if [[ -n "${SBV_SS_CHECK_FAIL_FILE:-}" && -e "${SBV_SS_CHECK_FAIL_FILE}" ]]; then
      printf 'injected core-check failure\n' >&2
      exit 23
    fi
    if [[ -n "${SBV_SS_REAL_CORE:-}" && -x "${SBV_SS_REAL_CORE}" ]]; then
      exec "${SBV_SS_REAL_CORE}" "$@"
    fi
    exit 0
    ;;
  *) printf 'unexpected sing-box invocation: %s\n' "$*" >&2; exit 64 ;;
esac
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
state_file=${SBV_SS_SYSTEMCTL_STATE_FILE:?missing state file}
count_file=${SBV_SS_SYSTEMCTL_COUNT_FILE:?missing count file}
log_file=${SBV_SS_SYSTEMCTL_LOG_FILE:?missing log file}
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
    if [[ -n "${SBV_SS_RESTART_FAIL_ONCE_FILE:-}" && -e "${SBV_SS_RESTART_FAIL_ONCE_FILE}" ]]; then
      rm -f -- "${SBV_SS_RESTART_FAIL_ONCE_FILE}"
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
export SBV_SS_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
export SBV_SS_SYSTEMCTL_COUNT_FILE="${TMP_DIR}/systemctl.count"
export SBV_SS_SYSTEMCTL_LOG_FILE="${TMP_DIR}/systemctl.log"

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
   "authentication":{"enabled":true,"username":"mixed-user","password":"mixed-password"},
   "outbound_policy":"default","dependencies":[]}
]}
EOF_MIXED_STORE
cat > "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" <<'EOF_SOCKS_STORE'
{"schema_version":1,"protocol":"socks","revision":2,"default_instance_id":"socks-main","instances":[
  {"id":"socks-main","name":"Existing SOCKS","tag":"socks-in","listen":{"address":"127.0.0.1","port":2081},
   "authentication":{"enabled":true,"username":"socks-user","password":"socks-password"},
   "outbound_policy":"default","dependencies":[]}
]}
EOF_SOCKS_STORE
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF_CONFIG'
{
  "log":{"level":"info"},
  "inbounds":[
    {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":2080,
     "users":[{"username":"mixed-user","password":"mixed-password"}]},
    {"type":"socks","tag":"socks-in","listen":"127.0.0.1","listen_port":2081,
     "users":[{"username":"socks-user","password":"socks-password"}]}
  ],
  "outbounds":[{"type":"direct","tag":"direct"}],
  "route":{"rules":[
    {"inbound":"mixed-in","action":"sniff"},
    {"inbound":"mixed-in","action":"route","outbound":"direct"},
    {"inbound":"socks-in","action":"sniff"},
    {"inbound":"socks-in","action":"route","outbound":"direct"}
  ],"final":"direct"}
}
EOF_CONFIG
printf '[Unit]\nDescription=fixture sing-box\n' > "${SINGBOX_SERVICE_FILE}"

# The mock firewall keeps a flattened TCP/UDP ledger.  This makes shared-port
# ownership observable: a TCP record may be removed while the UDP record on
# the same port remains owned by another Shadowsocks instance.
firewall_log="${TMP_DIR}/firewall.log"
firewall_candidate="${TMP_DIR}/firewall-candidate.json"
firewall_applied="${TMP_DIR}/firewall-applied.json"
firewall_before="${TMP_DIR}/firewall-before.json"
: > "${firewall_log}"
printf '[]\n' > "${firewall_applied}"
ss_firewall_ledger() {
  jq -c '[.inbounds[]? | select(.type == "shadowsocks") |
    . as $inbound | $inbound.network[] | {tag:$inbound.tag,port:$inbound.listen_port,transport:.}]
    | sort_by([.port,.transport,.tag])' "$1"
}
instance_firewall_prepare() {
  local old_config=${1:?} new_config=${2:?} journal=${3:?}
  printf 'prepare\n' >> "${firewall_log}"
  ss_firewall_ledger "${old_config}" > "${firewall_before}"
  ss_firewall_ledger "${new_config}" > "${firewall_candidate}"
  jq -n --argjson before "$(<"${firewall_before}")" --argjson after "$(<"${firewall_candidate}")" \
    '{schema_version:1,status:"prepared",backend_statuses:[],diagnostics:[],before_ledger:$before,after_ledger:$after}' > "${journal}"
}
instance_firewall_apply() {
  printf 'apply\n' >> "${firewall_log}"
  cp -- "${firewall_candidate}" "${firewall_applied}"
}
instance_firewall_rollback() {
  printf 'rollback\n' >> "${firewall_log}"
  if [[ -n "${SBV_SS_ROLLBACK_FAIL_FILE:-}" && -e "${SBV_SS_ROLLBACK_FAIL_FILE}" ]]; then
    return 71
  fi
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
    '.ok == true and .protocol == "shadowsocks" and .revision == $revision and
     .data.ok == true and .data.protocol == "shadowsocks" and .data.revision == $revision' \
    <<< "${output}" >/dev/null || {
    printf '%s returned an unexpected envelope:\n%s\n' "${label}" "${output}" >&2
    return 1
  }
  printf '%s' "${output}"
}

expect_success_as_protocol() {
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
  jq -e '.ok == false and .protocol == "shadowsocks" and (.error | type == "string") and
    .data.ok == false and .data.protocol == "shadowsocks"' <<< "${output}" >/dev/null || {
    printf '%s returned an unexpected failure envelope:\n%s\n' "${label}" "${output}" >&2
    return 1
  }
  if grep -Eq 'mixed-password|socks-password|alpha-password|beta-password|gamma-password|server-psk|user-psk' <<< "${output}"; then
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
  jq -e '.ok == false and .error == "instance_recovery_untrusted" and
    .data.ok == false and .data.error == "instance_recovery_untrusted"' <<< "${output}" >/dev/null
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

assert_base_preserved() {
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${mixed_marker_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")" == "${socks_marker_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")" == "${mixed_store_hash}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${socks_store_hash}" ]]
  [[ "$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed" or .type == "socks")],rules:[.route.rules[] | select(.inbound == "mixed-in" or .inbound == "socks-in")]}' "${SINGBOX_CONFIG_FILE}")" == "${base_config_snapshot}" ]]
}

assert_ss_ledger() {
  local expected=$1
  [[ "$(<"${firewall_applied}")" == "${expected}" ]]
}

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 address=$5 network=$6 method=$7 password=$8 users=$9 file=${10}
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --arg address "${address}" --argjson port "${port}" --argjson network "${network}" \
    --arg method "${method}" --arg password "${password}" --argjson users "${users}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port,network:$network},
      authentication:{method:$method,password:$password,users:$users},
      outbound_policy:"default",dependencies:[]}' > "${file}"
}

declare -F agent_cli >/dev/null || { printf 'missing public Agent API: agent_cli\n' >&2; exit 1; }
# Use deliberately longer-than-minimum keys: the canonical contract accepts
# PSKs of at least the method's salt length and preserves the original text.
server_psk=$(printf '\0%.0s' {1..24} | base64 | tr -d '\n')
user_psk=$(printf '\0%.0s' {1..40} | base64 | tr -d '\n')
make_record alpha 'Alpha Shadowsocks' ss-alpha 2082 127.0.0.1 '["tcp"]' aes-256-gcm alpha-password '[]' "${TMP_DIR}/alpha.json"
make_record beta 'Beta Shadowsocks' ss-beta 2082 127.0.0.1 '["udp"]' aes-256-gcm '' '[{"name":"beta-a","password":"beta-password-a"},{"name":"beta-b","password":"beta-password-b"}]' "${TMP_DIR}/beta.json"
make_record gamma 'Gamma Shadowsocks 2022' ss-gamma 2083 127.0.0.1 '["tcp","udp"]' 2022-blake3-aes-128-gcm "${server_psk}" '[{"name":"gamma-user","password":"'"${user_psk}"'"}]' "${TMP_DIR}/gamma.json"
make_record public 'Public Shadowsocks' ss-public 2084 0.0.0.0 '["tcp","udp"]' aes-256-gcm public-password '[]' "${TMP_DIR}/public.json"

mixed_marker_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
socks_marker_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")
mixed_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")
socks_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")
base_config_snapshot=$(jq -cS '{inbounds:[.inbounds[] | select(.type == "mixed" or .type == "socks")],rules:[.route.rules[] | select(.inbound == "mixed-in" or .inbound == "socks-in")]}' "${SINGBOX_CONFIG_FILE}")

# TCP and UDP may share one port only when ownership is disjoint by network.
expect_success create_alpha 1 create shadowsocks --json --yes --expected-revision 0 --file "${TMP_DIR}/alpha.json" >/dev/null
jq -e '.schema_version == 1 and .protocol == "shadowsocks" and .revision == 1 and
  .default_instance_id == "alpha" and .instances[0].authentication.users == [] and
  .instances[0].listen.network == ["tcp"]' "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_ss_ledger '[{"tag":"ss-alpha","port":2082,"transport":"tcp"}]'
assert_base_preserved

before_invalid=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")
jq '.listen.network=["udp","tcp"]' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/unsorted-network.json"
expect_failure unsorted_network create shadowsocks --json --yes --expected-revision 1 --file "${TMP_DIR}/unsorted-network.json"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")" == "${before_invalid}" ]]
jq '.listen.port=2081' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/duplicate-port.json"
expect_failure duplicate_cross_protocol_port create shadowsocks --json --yes --expected-revision 1 --file "${TMP_DIR}/duplicate-port.json"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")" == "${before_invalid}" ]]
expect_failure stale_revision create shadowsocks --json --yes --expected-revision 0 --file "${TMP_DIR}/beta.json"
expect_confirmation_failure missing_confirmation create shadowsocks --json --expected-revision 1 --file "${TMP_DIR}/beta.json"

expect_success create_beta 2 create shadowsocks --json --yes --expected-revision 1 --file "${TMP_DIR}/beta.json" >/dev/null
jq -e '([.instances[].id] | sort) == ["alpha","beta"] and .default_instance_id == "alpha" and
  any(.instances[]; .id == "beta" and .authentication.password == "" and (.authentication.users|length)==2)' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_ss_ledger '[{"tag":"ss-alpha","port":2082,"transport":"tcp"},{"tag":"ss-beta","port":2082,"transport":"udp"}]'
assert_base_preserved

expect_success create_gamma 3 create shadowsocks --json --yes --expected-revision 2 --file "${TMP_DIR}/gamma.json" >/dev/null
jq -e --arg server "${server_psk}" --arg user "${user_psk}" \
  'any(.instances[]; .id == "gamma" and .authentication.method == "2022-blake3-aes-128-gcm" and
    .authentication.password == $server and .authentication.users[0].password == $user and
    .listen.network == ["tcp","udp"])' "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_ss_ledger '[{"tag":"ss-alpha","port":2082,"transport":"tcp"},{"tag":"ss-beta","port":2082,"transport":"udp"},{"tag":"ss-gamma","port":2083,"transport":"tcp"},{"tag":"ss-gamma","port":2083,"transport":"udp"}]'
assert_base_preserved

# 2022 server and user PSKs must each meet their independent minimum lengths.
jq '.authentication.password="AQ=="' "${TMP_DIR}/gamma.json" > "${TMP_DIR}/short-server-key.json"
expect_failure short_server_key create shadowsocks --json --yes --expected-revision 3 --file "${TMP_DIR}/short-server-key.json"
jq '.authentication.users[0].password="AQ=="' "${TMP_DIR}/gamma.json" > "${TMP_DIR}/short-user-key.json"
expect_failure short_user_key create shadowsocks --json --yes --expected-revision 3 --file "${TMP_DIR}/short-user-key.json"

# None and 2022-ChaCha multi-user records are deliberately unsupported.
jq '.authentication={method:"none",password:"",users:[{name:"bad",password:"bad"}]}' "${TMP_DIR}/alpha.json" > "${TMP_DIR}/none-multi.json"
expect_failure unsupported_none_multi create shadowsocks --json --yes --expected-revision 3 --file "${TMP_DIR}/none-multi.json"
jq '.authentication={method:"2022-blake3-chacha20-poly1305",password:$p,users:[{name:"bad",password:$p}]}' \
  --arg p "${user_psk}" "${TMP_DIR}/alpha.json" > "${TMP_DIR}/chacha-multi.json"
expect_failure unsupported_chacha_multi create shadowsocks --json --yes --expected-revision 3 --file "${TMP_DIR}/chacha-multi.json"
assert_base_preserved

# Replacement preserves immutable tag identity and the other instances.
make_record alpha 'Alpha Shadowsocks replaced' ss-alpha 2082 127.0.0.1 '["tcp"]' 2022-blake3-aes-128-gcm "${server_psk}" '[{"name":"alpha-user","password":"'"${user_psk}"'"}]' "${TMP_DIR}/alpha-replaced.json"
expect_success replace_alpha 4 replace shadowsocks --json --yes --expected-revision 3 --file "${TMP_DIR}/alpha-replaced.json" >/dev/null
jq -e 'any(.instances[]; .id == "alpha" and .tag == "ss-alpha" and .authentication.method == "2022-blake3-aes-128-gcm") and
  any(.instances[]; .id == "beta" and (.authentication.users|length)==2) and any(.instances[]; .id == "gamma")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_base_preserved
before_noop_count=$(<"${SBV_SS_SYSTEMCTL_COUNT_FILE}")
before_noop_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json")
expect_success replace_noop 4 replace shadowsocks --json --yes --expected-revision 4 --file "${TMP_DIR}/alpha-replaced.json" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json")" == "${before_noop_hash}" ]]
[[ "$(<"${SBV_SS_SYSTEMCTL_COUNT_FILE}")" == "${before_noop_count}" ]]
expect_success set_default_gamma 5 default shadowsocks --json --yes --expected-revision 4 --id gamma >/dev/null
jq -e '.default_instance_id == "gamma"' "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null

# Candidate/core/restart failures leave the complete prior tree unchanged.
before_restart_failure=$(state_fingerprint 2>/dev/null || sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")
touch "${TMP_DIR}/restart-fail"
export SBV_SS_RESTART_FAIL_ONCE_FILE="${TMP_DIR}/restart-fail"
expect_failure restart_failure delete shadowsocks --json --yes --expected-revision 5 --id beta
unset SBV_SS_RESTART_FAIL_ONCE_FILE
jq -e '.error == "instance_apply_failed" and .transaction.status == "rolled_back"' "${TMP_DIR}/restart_failure.json" >/dev/null
[[ "$(state_fingerprint 2>/dev/null || sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")" == "${before_restart_failure}" ]]
assert_base_preserved

touch "${TMP_DIR}/ss-check-fail"
export SBV_SS_CHECK_FAIL_FILE="${TMP_DIR}/ss-check-fail"
expect_failure candidate_failure create shadowsocks --json --yes --expected-revision 5 --file "${TMP_DIR}/public.json"
unset SBV_SS_CHECK_FAIL_FILE
assert_base_preserved

before_rollback_failure=$(state_fingerprint 2>/dev/null || sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")
touch "${TMP_DIR}/restart-fail" "${TMP_DIR}/rollback-fail"
export SBV_SS_RESTART_FAIL_ONCE_FILE="${TMP_DIR}/restart-fail"
export SBV_SS_ROLLBACK_FAIL_FILE="${TMP_DIR}/rollback-fail"
expect_failure rollback_failure delete shadowsocks --json --yes --expected-revision 5 --id beta
jq -e '.error == "instance_rollback_failed" and .transaction.status == "rollback_failed" and
  .transaction.manual_intervention_required == true' "${TMP_DIR}/rollback_failure.json" >/dev/null
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
expect_failure recovery_still_failed recover shadowsocks --json --yes --expected-revision 5
[[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]
unset SBV_SS_ROLLBACK_FAIL_FILE SBV_SS_RESTART_FAIL_ONCE_FILE
expect_success recovery 5 recover shadowsocks --json --yes --expected-revision 5 >/dev/null
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
[[ "$(state_fingerprint 2>/dev/null || sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")" == "${before_rollback_failure}" ]]
assert_base_preserved

# Delete alpha first: beta's UDP ownership on the shared port must survive.
expect_success delete_alpha 6 delete shadowsocks --json --yes --expected-revision 5 --id alpha >/dev/null
jq -e '([.instances[].id] | sort) == ["beta","gamma"] and .default_instance_id == "gamma"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_ss_ledger '[{"tag":"ss-beta","port":2082,"transport":"udp"},{"tag":"ss-gamma","port":2083,"transport":"tcp"},{"tag":"ss-gamma","port":2083,"transport":"udp"}]'
assert_base_preserved
expect_success delete_beta 7 delete shadowsocks --json --yes --expected-revision 6 --id beta >/dev/null
assert_ss_ledger '[{"tag":"ss-gamma","port":2083,"transport":"tcp"},{"tag":"ss-gamma","port":2083,"transport":"udp"}]'
expect_success delete_gamma 8 delete shadowsocks --json --yes --expected-revision 7 --id gamma >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/shadowsocks.env" ]]
jq -e '.schema_version == 1 and .protocol == "shadowsocks" and .revision == 8 and .instances == [] and .default_instance_id == ""' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_ss_ledger '[]'
indexed_protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${SB_PROTOCOL_INDEX_FILE}")
[[ ",${indexed_protocols}," != *,shadowsocks,* && ",${indexed_protocols}," == *,mixed,* && ",${indexed_protocols}," == *,socks,* ]]
assert_base_preserved

# Tombstone CAS and public consent remain enforced after final deletion.
before_public=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")
expect_failure public_without_consent create shadowsocks --json --yes --expected-revision 8 --file "${TMP_DIR}/public.json"
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" "${SINGBOX_CONFIG_FILE}")" == "${before_public}" ]]
expect_success create_public 9 create shadowsocks --json --yes --allow-public --expected-revision 8 --file "${TMP_DIR}/public.json" >/dev/null
jq -e '.revision == 9 and [.instances[].id] == ["public"] and .instances[0].listen.address == "0.0.0.0"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_base_preserved
expect_success delete_public 10 delete shadowsocks --json --yes --expected-revision 9 --id public >/dev/null
jq -e '.revision == 10 and .instances == [] and .default_instance_id == ""' "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null
assert_base_preserved

# Recovery is protocol-scoped; old journals without protocol remain Mixed-
# compatible, while malformed protocol fields fail closed without deleting the lock.
recovery_lock="${SB_PROJECT_DIR}.instance-write.lock"
mkdir -m 700 "${recovery_lock}"
jq -n --arg expected 10 --argjson pid 999999 --arg start 1 \
  '{schema_version:1,protocol:"socks",operation:"delete",expected_revision:$expected,
    owner_pid:$pid,owner_start:$start,before_active:true,phase:"service"}' > "${recovery_lock}/transaction.json"
expect_untrusted_recovery_failure wrong_protocol_recovery recover shadowsocks --json --yes --expected-revision 10
[[ -d "${recovery_lock}" ]]
rm -rf -- "${recovery_lock}"

mkdir -m 700 "${recovery_lock}"
jq -n --arg expected 10 --argjson pid 999999 --arg start 1 \
  '{schema_version:1,operation:"delete",expected_revision:$expected,
    owner_pid:$pid,owner_start:$start,before_active:true,phase:"prepare"}' > "${recovery_lock}/transaction.json"
expect_success_as_protocol old_mixed_recovery 10 mixed recover mixed --json --yes --expected-revision 10 >/dev/null
[[ ! -e "${recovery_lock}" ]]

if agent_cli instance migrate shadowsocks --json --yes --expected-revision 10 > "${TMP_DIR}/unsupported-migrate.json"; then
  printf 'Shadowsocks unexpectedly offered a legacy migration\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "invalid_arguments"' "${TMP_DIR}/unsupported-migrate.json" >/dev/null

if [[ -n "${SBV_SS_REAL_CORE:-}" && -x "${SBV_SS_REAL_CORE}" ]]; then
  core_check_mode=real
else
  core_check_mode=mock
fi
printf 'shadowsocks instance lifecycle checks passed; service restarts=%s; core_check=%s\n' \
  "$(<"${SBV_SS_SYSTEMCTL_COUNT_FILE}")" "${core_check_mode}"
