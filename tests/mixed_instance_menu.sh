#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope so Bash 4.2 keeps readonly registry arrays alive.
source "${TESTABLE_INSTALL}"

# Keep the production snapshot implementation available while individual
# menu tests replace it with controlled fixtures.
ORIGINAL_CAPTURE_FUNCTION_FILE="${TMP_DIR}/original-capture-function.sh"
declare -f mixed_management_capture_snapshot > "${ORIGINAL_CAPTURE_FUNCTION_FILE}"

fixture="${TMP_DIR}/mixed.json"
jq -n '{schema_version:1,protocol:"mixed",revision:7,default_instance_id:"main",instances:[
  {id:"main",name:"Main",tag:"mixed-in",listen:{address:"127.0.0.1",port:1080},
   authentication:{enabled:true,username:"keep-user",password:"keep-secret"},outbound_policy:"default",dependencies:[]},
  {id:"edge",name:"Edge",tag:"mixed-edge",listen:{address:"127.0.0.1",port:1081},
   authentication:{enabled:false,username:"",password:""},outbound_policy:"direct",dependencies:[]}
]}' > "${fixture}"

mixed_management_capture_snapshot() {
  cp -- "${fixture}" "$1"
}

calls="${TMP_DIR}/calls"
: > "${calls}"
apply_mixed_instance_change() {
  local operation=$1 revision=$2 input=$3 allow_public=${4:-n}
  printf '%s %s %s %s\n' "${operation}" "${revision}" "${allow_public}" \
    "$(jq -cS . "${input}" 2>/dev/null || printf '%s' "${input}")" >> "${calls}"
  jq -n --argjson revision "$((revision + 1))" '{ok:true,revision:$revision}'
}
recover_mixed_instance_transaction() {
  printf 'recover %s\n' "$1" >> "${calls}"
}

# Listing is ID-oriented and must not print credentials.
listed=$(printf '7\n0\n' | mixed_instance_management_menu)
grep -Fq 'main' <<< "${listed}"
grep -Fq 'edge' <<< "${listed}"
! grep -Fq 'keep-secret' <<< "${listed}"

# Create with all defaults: loopback, auth enabled, and the captured revision.
created=$(printf '%s\n' 1 '' '' '' '' '' '' '' '' 0 | mixed_instance_management_menu)
grep -Eq '^create 7 n .*address.*127\.0\.0\.1' "${calls}"
grep -Eq 'enabled.*true' "${calls}"

# Selecting an ID for replace preserves the tag and credentials when fields
# are left unchanged; the CAS revision remains the one captured before input.
: > "${calls}"
printf '%s\n' 2 edge '' '' '' '' 0 | mixed_instance_management_menu >/dev/null
grep -Eq '^replace 7 n .*id.*edge.*tag.*mixed-edge' "${calls}"

: > "${calls}"
printf '%s\n' 2 main '' '' '' '' '' '' 0 | mixed_instance_management_menu >/dev/null
grep -Fq 'keep-secret' "${calls}"

# Numeric selection is bounded and never treats zero, octal-looking, or huge
# values as an array index.
for invalid_target in 0 08 999999999999999999999; do
  if printf '%s\n' "${invalid_target}" | mixed_management_prompt_target "${fixture}" >/dev/null 2>&1; then
    printf 'invalid numeric target unexpectedly selected: %s\n' "${invalid_target}" >&2
    exit 1
  fi
done

# jq-based replace construction preserves a credential's trailing newline
# when all interactive fields are left unchanged.
newline_snapshot="${TMP_DIR}/newline-snapshot.json"
printf -v newline_password '%b' 'keep-secret\n'
jq --arg password "${newline_password}" \
  '.instances[0].authentication.password = $password' "${fixture}" > "${newline_snapshot}"
newline_record="${TMP_DIR}/newline-record.json"
printf '%s\n' '' '' '' '' '' '' | \
  mixed_management_build_record "${newline_snapshot}" replace main "${newline_record}"
jq -e --arg password "${newline_password}" \
  '.id == "main" and .tag == "mixed-in" and .authentication.password == $password' \
  "${newline_record}" >/dev/null

# A public plaintext listener requires explicit consent and does not call the
# mutator when declined.
: > "${calls}"
printf '%s\n' 1 '' '' '' 0.0.0.0 '' '' '' '' n 0 | mixed_instance_management_menu >/dev/null
[[ ! -s "${calls}" ]]

# Recovery reads the expected revision from the pending journal before trying
# to inspect the live state.
mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,expected_revision:"4"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
printf '%s\n' 1 y | mixed_instance_management_menu >/dev/null
grep -Fq 'recover 4' "${calls}"
rm -rf -- "${SB_PROJECT_DIR}.instance-write.lock"

# Legacy schema-1 values are shell-escaped by the existing writer and may
# legitimately contain shell punctuation or newlines.  The read-only
# takeover snapshot must preserve those bytes without printing them.
legacy_user='legacy$(user);'
legacy_password=$'line-one\nline-two'
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf -v legacy_user_q '%q' "${legacy_user}"
printf -v legacy_password_q '%q' "${legacy_password}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=legacy\nPORT=1080\nAUTH_ENABLED=y\nUSERNAME=%s\nPASSWORD=%s\n' \
  "${legacy_user_q}" "${legacy_password_q}" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
jq -n --arg user "${legacy_user}" --arg password "${legacy_password}" \
  '{inbounds:[{type:"mixed",tag:"mixed-in",listen:"127.0.0.1",listen_port:1080,users:[{username:$user,password:$password}]}],route:{rules:[]}}' > "${SINGBOX_CONFIG_FILE}"
source "${ORIGINAL_CAPTURE_FUNCTION_FILE}"
legacy_snapshot="${TMP_DIR}/legacy-snapshot.json"
mixed_management_capture_snapshot "${legacy_snapshot}"
jq -e --arg user "${legacy_user}" --arg password "${legacy_password}" \
  '.revision == 0 and .instances[0].authentication == {enabled:true,username:$user,password:$password}' \
  "${legacy_snapshot}" >/dev/null

# After deleting the last instance, an inactive empty store remains the CAS
# source for the next create.  The first new tag is still safe because the
# tombstone has no live identities.
rm -f -- "${SB_PROTOCOL_STATE_DIR}/mixed.env"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
jq -n '{schema_version:1,protocol:"mixed",revision:9,default_instance_id:"",instances:[]}' \
  > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json"
source "${ORIGINAL_CAPTURE_FUNCTION_FILE}"
: > "${calls}"
printf '%s\n' 1 '' '' '' '' '' '' '' '' 0 | mixed_instance_management_menu >/dev/null
grep -Eq '^create 9 n .*"id":"mixed-1".*"tag":"mixed-in"' "${calls}"

# No Mixed state and no tombstone but a valid config is the first-instance
# baseline: it must produce virtual revision zero rather than clobbering the
# other protocol's configuration.
rm -f -- "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json"
jq -n '{inbounds:[],route:{rules:[]}}' \
  > "${SINGBOX_CONFIG_FILE}"
empty_snapshot="${TMP_DIR}/empty-snapshot.json"
mixed_management_capture_snapshot "${empty_snapshot}"
jq -e '.revision == 0 and .instances == [] and .default_instance_id == ""' "${empty_snapshot}" >/dev/null

# A malformed captured state fails closed before showing a mutating menu.
mixed_management_capture_snapshot() { printf '{malformed\n' > "$1"; }
if printf '1\n' | mixed_instance_management_menu >/dev/null 2>&1; then
  printf 'malformed Mixed state unexpectedly entered management menu\n' >&2
  exit 1
fi

printf 'mixed instance menu checks passed\n'
