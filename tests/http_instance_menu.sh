#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

fixture="${TMP_DIR}/http.json"
jq -n '{schema_version:1,protocol:"http",revision:7,default_instance_id:"main",instances:[
  {id:"main",name:"Main",tag:"http-in",listen:{address:"127.0.0.1",port:1080},
   authentication:{enabled:true,username:"keep-user",password:"keep-secret"},outbound_policy:"default",
   tls:{enabled:false},dependencies:[]},
  {id:"edge",name:"Edge",tag:"http-edge",listen:{address:"127.0.0.1",port:1081},
   authentication:{enabled:true,username:"edge-user",password:"edge-secret"},outbound_policy:"direct",
   tls:{enabled:true,server_name:"proxy.example.com",certificate_path:"/etc/ssl/cert.pem",key_path:"/etc/ssl/key.pem"},dependencies:[]}
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

listed=$(printf '7\n0\n' | http_instance_management_menu)
grep -Fq 'main' <<< "${listed}"
grep -Fq 'edge' <<< "${listed}"
! grep -Fq 'keep-secret' <<< "${listed}"

one_shot_listed=$(http_instance_management_menu list)
[[ "$(grep -c '^main' <<< "${one_shot_listed}")" -eq 1 ]]
[[ "$(grep -c '^edge' <<< "${one_shot_listed}")" -eq 1 ]]

# Plain HTTP defaults to loopback/authentication and records its protocol in
# the shared CAS call; it must not silently become a SOCKS record.
: > "${calls}"
printf '%s\n' 1 '' '' '' '' '' '' '' '' n 0 | http_instance_management_menu >/dev/null
grep -Fq 'http create 7 n' "${calls}"
grep -Eq '"address":"127\.0\.0\.1"' "${calls}"
grep -Eq '"tls":\{"enabled":false\}' "${calls}"

# Replacing an HTTP record keeps credentials and immutable tag bytes, while
# enabling TLS adds explicit server name and referenced certificate paths.
tls_record="${TMP_DIR}/tls-record.json"
printf '%s\n' '' '' '' '' '' '' y proxy.example.com /etc/ssl/cert.pem /etc/ssl/key.pem | \
  plain_proxy_management_build_record http "${fixture}" replace main "${tls_record}"
jq -e '.id == "main" and .tag == "http-in" and .authentication.password == "keep-secret" and
  .tls == {enabled:true,server_name:"proxy.example.com",certificate_path:"/etc/ssl/cert.pem",key_path:"/etc/ssl/key.pem"}' \
  "${tls_record}" >/dev/null

# HTTP Basic credentials use the HTTP-specific 4096-byte bound (not the
# SOCKS/Mixed 255-byte bound) when the typed state is initially saved.
long_username=$(printf 'u%.0s' {1..256})
SB_INSTANCE_ID=http-long
SB_NODE_NAME=HTTP-long
SB_PORT=1082
SB_MIXED_INBOUND_TAG=http-long-in
SB_MIXED_LISTEN_ADDRESS=127.0.0.1
SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=${long_username}
SB_MIXED_PASSWORD=long-secret
SB_OUTBOUND_POLICY=default
SB_HTTP_TLS_JSON='{"enabled":false}'
save_http_state
jq -e --arg username "${long_username}" \
  '.instances[0].authentication.username == $username and .instances[0].tls.enabled == false' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null

# A non-loopback plaintext HTTP listener requires explicit consent and does
# not call the mutator when declined.
: > "${calls}"
printf '%s\n' 1 '' '' '' 0.0.0.0 '' '' '' '' n n 0 | http_instance_management_menu >/dev/null
[[ ! -s "${calls}" ]]

# Additional installation of a not-yet-installed HTTP protocol must enter the
# shared instance menu before any legacy managed snapshot/save is created.
additional_calls="${TMP_DIR}/additional-calls"
: > "${additional_calls}"
load_stack_mode_state() { :; }
migrate_legacy_single_protocol_state_if_needed() { :; }
load_current_config_state() { :; }
list_installed_protocols() { :; }
plain_proxy_inactive_store_snapshot() { return 1; }
prompt_protocol_install_selection() { SELECTED_PROTOCOLS_CSV=http; }
create_managed_state_snapshot() {
  printf 'legacy snapshot unexpectedly created\n' >> "${additional_calls}"
  return 1
}
save_http_state() {
  printf 'legacy HTTP save unexpectedly called\n' >> "${additional_calls}"
  return 1
}
declare -f http_instance_management_menu > "${TMP_DIR}/original-http-menu.sh"
http_instance_management_menu() {
  printf 'http %s\n' "${1:-}" >> "${additional_calls}"
}
install_protocols_interactive additional
grep -Fqx 'http create' "${additional_calls}"
! grep -Fq 'unexpectedly' "${additional_calls}"

# Combining HTTP with another additional protocol is rejected before the old
# transaction path, rather than silently flattening HTTP state.
: > "${additional_calls}"
prompt_protocol_install_selection() { SELECTED_PROTOCOLS_CSV=http,socks; }
install_protocols_interactive additional
[[ ! -s "${additional_calls}" ]]

# Recovery accepts only an HTTP journal and uses its captured expected
# revision; a SOCKS journal must fail closed without invoking recovery.
source "${TMP_DIR}/original-http-menu.sh"
mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"http",expected_revision:"4"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
printf '%s\n' 1 y | http_instance_management_menu recover >/dev/null
grep -Fq 'recover http 4' "${calls}"

: > "${calls}"
jq -n '{schema_version:1,protocol:"socks",expected_revision:"4"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
if printf '%s\n' 1 y | http_instance_management_menu recover >/dev/null 2>&1; then
  printf 'HTTP menu unexpectedly accepted a SOCKS recovery journal\n' >&2
  exit 1
fi
[[ ! -s "${calls}" ]]

printf 'http instance menu checks passed\n'
