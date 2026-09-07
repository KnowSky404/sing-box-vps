#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

fixture="${TMP_DIR}/socks.json"
jq -n '{schema_version:1,protocol:"socks",revision:7,default_instance_id:"main",instances:[
  {id:"main",name:"Main",tag:"socks-in",listen:{address:"127.0.0.1",port:1080},
   authentication:{enabled:true,username:"keep-user",password:"keep-secret"},outbound_policy:"default",dependencies:[]},
  {id:"edge",name:"Edge",tag:"socks-edge",listen:{address:"127.0.0.1",port:1081},
   authentication:{enabled:false,username:"",password:""},outbound_policy:"direct",dependencies:[]}
]}' > "${fixture}"

plain_proxy_management_capture_snapshot() { cp -- "${fixture}" "$2"; }
calls="${TMP_DIR}/calls"
: > "${calls}"
apply_plain_proxy_instance_change() {
  local protocol=$1 operation=$2 revision=$3 input=$4 allow_public=${5:-n}
  printf '%s %s %s %s\n' "${protocol}" "${operation}" "${revision}" "${allow_public}" \
    "$(jq -cS . "${input}" 2>/dev/null || printf '%s' "${input}")" >> "${calls}"
  jq -n --argjson revision "$((revision + 1))" '{ok:true,revision:$revision}'
}
recover_plain_proxy_instance_transaction() { printf 'recover %s %s\n' "$1" "$2" >> "${calls}"; }

listed=$(printf '7\n0\n' | socks_instance_management_menu)
grep -Fq 'main' <<< "${listed}"
grep -Fq 'edge' <<< "${listed}"
! grep -Fq 'keep-secret' <<< "${listed}"

one_shot_listed=$(socks_instance_management_menu list)
[[ "$(grep -c '^main' <<< "${one_shot_listed}")" -eq 1 ]]
[[ "$(grep -c '^edge' <<< "${one_shot_listed}")" -eq 1 ]]

# Creation defaults to loopback + authentication and carries the captured CAS.
printf '%s\n' 1 '' '' '' '' '' '' '' '' 0 | socks_instance_management_menu >/dev/null
grep -Fq 'socks create 7 n' "${calls}"
grep -Fq '127.0.0.1' "${calls}"
grep -Eq 'enabled.*true' "${calls}"

# Targeting by numeric index remains bounded and the replacement preserves
# immutable identity and credentials when fields are left unchanged.
: > "${calls}"
printf '%s\n' 2 2 '' '' '' '' 0 | socks_instance_management_menu >/dev/null
grep -Fq 'socks replace 7 n' "${calls}"
grep -Fq '"id":"edge"' "${calls}"
grep -Fq '"tag":"socks-edge"' "${calls}"
: > "${calls}"
printf '%s\n' 2 main '' '' '' '' '' '' 0 | socks_instance_management_menu >/dev/null
grep -Fq 'keep-secret' "${calls}"

for invalid_target in 0 08 999999999999999999999; do
  if printf '%s\n' "${invalid_target}" | plain_proxy_management_prompt_target socks "${fixture}" >/dev/null 2>&1; then
    printf 'invalid numeric target unexpectedly selected: %s\n' "${invalid_target}" >&2
    exit 1
  fi
done

# A non-loopback address requires explicit consent and does not call the
# mutator when declined.
: > "${calls}"
printf '%s\n' 1 '' '' '' 0.0.0.0 '' '' '' '' n 0 | socks_instance_management_menu >/dev/null
[[ ! -s "${calls}" ]]

# Recovery uses the expected revision from the pending journal, not a live
# store revision that may already have advanced.
mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"mixed",expected_revision:"4"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
if printf '%s\n' 1 y | socks_instance_management_menu >/dev/null 2>&1; then
  printf 'SOCKS menu unexpectedly accepted a Mixed recovery journal\n' >&2
  exit 1
fi
[[ ! -s "${calls}" ]]
rm -rf -- "${SB_PROJECT_DIR}.instance-write.lock"

mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"socks",expected_revision:"4"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
printf '%s\n' 1 y | socks_instance_management_menu >/dev/null
grep -Fq 'recover socks 4' "${calls}"
rm -rf -- "${SB_PROJECT_DIR}.instance-write.lock"

printf 'socks instance menu checks passed\n'
