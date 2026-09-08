#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

fixture="${TMP_DIR}/shadowsocks.json"
jq -n '{schema_version:1,protocol:"shadowsocks",revision:7,default_instance_id:"main",instances:[
  {id:"main",name:"Main",tag:"ss-in",listen:{address:"127.0.0.1",port:1080,network:["tcp","udp"]},
   authentication:{method:"aes-128-gcm",password:"keep-secret",users:[]},outbound_policy:"default",dependencies:[]},
  {id:"edge",name:"Edge",tag:"ss-edge",listen:{address:"127.0.0.1",port:1081,network:["tcp"]},
   authentication:{method:"2022-blake3-aes-128-gcm",password:"AAAAAAAAAAAAAAAAAAAAAA==",users:[{name:"edge-user",password:"BBBBBBBBBBBBBBBBBBBBBA=="}]},outbound_policy:"direct",dependencies:[]}
]}' > "${fixture}"

plain_proxy_management_capture_snapshot() { cp -- "${fixture}" "$2"; }
calls="${TMP_DIR}/calls"
captured_record="${TMP_DIR}/captured-record.json"
: > "${calls}"
apply_plain_proxy_instance_change() {
  local protocol=$1 operation=$2 revision=$3 input=$4 allow_public=${5:-n}
  cp -- "${input}" "${captured_record}"
  printf '%s %s %s %s\n' "${protocol}" "${operation}" "${revision}" "${allow_public}" \
    "$(jq -cS . "${input}" 2>/dev/null || printf '%s' "${input}")" >> "${calls}"
  jq -n --argjson revision "$((revision + 1))" '{ok:true,revision:$revision}'
}
recover_plain_proxy_instance_transaction() { printf 'recover %s %s\n' "$1" "$2" >> "${calls}"; }

listed=$(printf '7\n0\n' | shadowsocks_instance_management_menu)
grep -Fq 'main' <<< "${listed}"
grep -Fq 'edge' <<< "${listed}"
grep -Fq 'method=aes-128-gcm' <<< "${listed}"
grep -Fq 'network=tcp,udp' <<< "${listed}"
grep -Fq 'users=1' <<< "${listed}"
! grep -Fq 'keep-secret' <<< "${listed}"
! grep -Fq 'BBBBBBBB' <<< "${listed}"

one_shot_listed=$(shadowsocks_instance_management_menu list)
[[ "$(grep -c '^main' <<< "${one_shot_listed}")" -eq 1 ]]
[[ "$(grep -c '^edge' <<< "${one_shot_listed}")" -eq 1 ]]

# A new instance defaults to loopback, tcp+udp, and a generated 2022 AES-128
# PSK.  The mutator receives the captured revision and the Shadowsocks record.
: > "${calls}"
printf '%s\n' 1 '' '' '' '' '' 7 '' '' '' 0 | shadowsocks_instance_management_menu >/dev/null
grep -Fq 'shadowsocks create 7 n' "${calls}"
grep -Eq '"address":"127\.0\.0\.1"' "${calls}"
jq -e 'select(.authentication.method == "2022-blake3-aes-128-gcm") |
  .listen.network == ["tcp","udp"] and .authentication.password != "" and
  (.authentication.password | test("^[A-Za-z0-9+/]+={0,2}$")) and
  (.authentication.users | length == 0)' "${captured_record}" >/dev/null

# Classic AEAD multi-user creation is interactive, not a raw JSON passthrough:
# top-level password remains empty and each requested user is recorded.
multi_record="${TMP_DIR}/classic-multi.json"
printf '%s\n' '' '' '' '' '' 2 y 2 alice alice-pass bob bob-pass 2 | \
  plain_proxy_management_build_record shadowsocks "${fixture}" create '' "${multi_record}"
jq -e '.authentication.method == "aes-128-gcm" and .authentication.password == "" and
  .authentication.users == [{name:"alice",password:"alice-pass"},{name:"bob",password:"bob-pass"}] and
  .listen.network == ["tcp"]' "${multi_record}" >/dev/null

# Replacing an instance with blank prompts preserves the existing credentials,
# method, network, and tag bytes.
replace_record="${TMP_DIR}/replace.json"
printf '%s\n' '' '' '' '' '' '' '' | \
  plain_proxy_management_build_record shadowsocks "${fixture}" replace main "${replace_record}"
jq -e '.id == "main" and .tag == "ss-in" and
  .authentication.method == "aes-128-gcm" and
  .authentication.password == "keep-secret" and .authentication.users == [] and
  .listen.network == ["tcp","udp"]' "${replace_record}" >/dev/null

# A public listener requires explicit consent; declining it must not produce a
# record or reach the CAS mutator.
: > "${calls}"
public_record="${TMP_DIR}/public.json"
if printf '%s\n' '' '' '' 0.0.0.0 '' 1 '' n | \
    plain_proxy_management_build_record shadowsocks "${fixture}" create '' "${public_record}"; then
  printf 'public Shadowsocks listener was accepted without consent\n' >&2
  exit 1
else
  status=$?
  [[ "${status}" -eq 2 ]]
fi
[[ ! -e "${public_record}" || ! -s "${public_record}" ]]
[[ ! -s "${calls}" ]]

# Encrypted Shadowsocks is still a public exposure, but it is not plaintext;
# the consent text must describe the selected authentication method accurately.
encrypted_prompt="${TMP_DIR}/encrypted-prompt"
declare -f prompt_yes_no > "${TMP_DIR}/original-prompt-yes-no.sh"
prompt_yes_no() { printf '%s\n' "$1" > "${encrypted_prompt}"; printf n; }
encrypted_answer=$(plain_proxy_management_prompt_public_consent shadowsocks 0.0.0.0 '' \
  '{"method":"aes-128-gcm","password":"secret","users":[]}')
[[ "${encrypted_answer}" == n ]]
! grep -Fq '明文' "${encrypted_prompt}"
grep -Fq '公网暴露风险' "${encrypted_prompt}"
none_prompt="${TMP_DIR}/none-prompt"
prompt_yes_no() { printf '%s\n' "$1" > "${none_prompt}"; printf n; }
none_answer=$(plain_proxy_management_prompt_public_consent shadowsocks 0.0.0.0 '' \
  '{"method":"none","password":"","users":[]}')
[[ "${none_answer}" == n ]]
grep -Fq '明文' "${none_prompt}"
source "${TMP_DIR}/original-prompt-yes-no.sh"

# The shared consent helper keeps its historical plaintext wording for the
# other plaintext protocols, while HTTP TLS and encrypted SS describe their
# actual transport accurately.
declare -f prompt_yes_no > "${TMP_DIR}/original-prompt-yes-no-adjacent.sh"
prompt_yes_no() { printf '%s\n' "$1" > "${prompt_file}"; printf n; }
for adjacent_protocol in mixed socks; do
  prompt_file="${TMP_DIR}/${adjacent_protocol}-prompt"
  adjacent_answer=$(plain_proxy_management_prompt_public_consent "${adjacent_protocol}" 0.0.0.0)
  [[ "${adjacent_answer}" == n ]]
  grep -Fq '明文' "${prompt_file}"
done
prompt_file="${TMP_DIR}/http-plaintext-prompt"
http_plain_answer=$(plain_proxy_management_prompt_public_consent http 0.0.0.0 '{"enabled":false}')
[[ "${http_plain_answer}" == n ]]
grep -Fq '明文' "${prompt_file}"
prompt_file="${TMP_DIR}/http-tls-prompt"
http_tls_answer=$(plain_proxy_management_prompt_public_consent http 0.0.0.0 '{"enabled":true}')
[[ "${http_tls_answer}" == n ]]
grep -Fq '提供 TLS' "${prompt_file}"
! grep -Fq '明文' "${prompt_file}"
source "${TMP_DIR}/original-prompt-yes-no-adjacent.sh"

# SS prompt-only validation must not apply the old port-only conflict check;
# final typed rendering/transaction validation handles address/network scope.
declare -f check_port_conflict > "${TMP_DIR}/check-port-conflict.sh"
check_port_conflict() { printf 'unexpected SS port-only conflict check\n' >> "${TMP_DIR}/port-check"; return 1; }
: > "${TMP_DIR}/port-check"
printf '%s\n' '' '' '' '' '' | prompt_shadowsocks_install >/dev/null 2>/dev/null
[[ ! -s "${TMP_DIR}/port-check" ]]
source "${TMP_DIR}/check-port-conflict.sh"

# An oversized count is rejected by the bounded decimal shape before Bash
# arithmetic is evaluated.
if printf '%s\n' y 999999999999999999999999999999999999999 | \
    shadowsocks_prompt_auth aes-128-gcm '{}' >/dev/null 2>/dev/null; then
  printf 'oversized Shadowsocks user count was accepted\n' >&2
  exit 1
fi

# The shared save path accepts the structured Shadowsocks authentication
# contract without applying the old 255-byte SOCKS credential bound.
long_password=$(printf 'p%.0s' {1..300})
SB_INSTANCE_ID=long
SB_NODE_NAME=Long-SS
SB_PORT=1082
SB_MIXED_INBOUND_TAG=ss-long-in
SB_MIXED_LISTEN_ADDRESS=127.0.0.1
SB_OUTBOUND_POLICY=default
SB_SHADOWSOCKS_NETWORK_JSON='["tcp","udp"]'
SB_SHADOWSOCKS_AUTH_JSON=$(jq -cn --arg password "${long_password}" \
  '{method:"aes-128-gcm",password:$password,users:[]}')
save_shadowsocks_state
jq -e --arg password "${long_password}" \
  '.instances[0].authentication.password == $password' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" >/dev/null

# Recovery is protocol-scoped and uses the revision recorded in the journal.
mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"socks",expected_revision:"4"}' \
  > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
if printf '%s\n' 1 y | shadowsocks_instance_management_menu >/dev/null 2>&1; then
  printf 'Shadowsocks menu unexpectedly accepted a SOCKS recovery journal\n' >&2
  exit 1
fi
[[ ! -s "${calls}" ]]
rm -rf -- "${SB_PROJECT_DIR}.instance-write.lock"

mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"shadowsocks",expected_revision:"4"}' \
  > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
printf '%s\n' 1 y | shadowsocks_instance_management_menu >/dev/null
grep -Fq 'recover shadowsocks 4' "${calls}"

printf 'shadowsocks instance menu checks passed\n'
