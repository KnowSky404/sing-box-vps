#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 122
source "${TESTABLE_INSTALL}"
trap 'printf "Trojan instance menu failed at line %s\n" "${LINENO}" >&2' ERR
agent_print_help | grep -Fq 'mixed|socks|http|shadowsocks|trojan'

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/trojan.json"
state_file="${SB_PROTOCOL_STATE_DIR}/trojan.env"
cert_file="${TMP_DIR}/trojan.crt"
key_file="${TMP_DIR}/trojan.key"
printf 'public certificate\n' > "${cert_file}"
printf 'private key fixture\n' > "${key_file}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"

jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {schema_version:1,protocol:"trojan",revision:21,default_instance_id:"edge",instances:[
    {id:"loopback",name:"Loopback",tag:"trojan-loopback",listen:{address:"127.0.0.1",port:33601},authentication:{users:[{name:"local-user",password:"local-secret"}]},tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"edge",name:"TLS WebSocket",tag:"trojan-edge",listen:{address:"0.0.0.0",port:33602},authentication:{users:[{name:"edge-user",password:"edge-secret"},{name:"第二用户",password:"second-secret"}]},tls:{enabled:true,server_name:"edge.example",certificate_path:$cert,key_path:$key},client_trust:"system",transport:{type:"ws",path:"/edge",headers:{Host:"edge.example"}},outbound_policy:"direct",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${store_file}" "${state_file}"
printf '%s\n' INSTALLED_PROTOCOLS=trojan PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
chmod 600 "${SB_PROTOCOL_INDEX_FILE}"

validate_structured_instance_store trojan "${store_file}"
save_plain_proxy_structured_marker trojan

listed=$(trojan_instance_management_menu list)
grep -Fq 'loopback' <<< "${listed}"
grep -Fq 'edge' <<< "${listed}"
grep -Fq 'transport=none' <<< "${listed}"
grep -Fq 'transport=ws' <<< "${listed}"
grep -Eq 'client_trust=system|trust=system' <<< "${listed}"
grep -Fq 'users=2' <<< "${listed}"
! grep -Fq 'local-secret' <<< "${listed}"
! grep -Fq 'edge-secret' <<< "${listed}"
! grep -Fq 'certificate_path' <<< "${listed}"
! grep -Fq 'key_path' <<< "${listed}"
! grep -Fq 'Host' <<< "${listed}"

# Replace is typed and read-only blanks preserve the existing auth/TLS/trust,
# transport, tag, and outbound policy.  Prompt stubs model the same choices
# when the implementation offers the editable typed fields.
prompt_port() { printf '33602'; }
prompt_instance_outbound_policy() { printf 'direct'; }
prompt_yes_no() { printf y; }
prompt_choice() { printf 2; }
trojan_prompt_users() { SB_TROJAN_AUTH_JSON=$(jq -c '.instances[1].authentication.users' "${store_file}"); }
trojan_prompt_transport() { SB_TROJAN_TRANSPORT_JSON=$(jq -c '.instances[1].transport' "${store_file}"); }
replace_record="${TMP_DIR}/replace.json"
printf '\n\n\n\n\n\n\n' | plain_proxy_management_build_record trojan "${store_file}" replace edge "${replace_record}"
jq -e --arg cert "${cert_file}" --arg key "${key_file}" '
  .id == "edge" and .tag == "trojan-edge" and .outbound_policy == "direct" and
  .authentication.users == [{name:"edge-user",password:"edge-secret"},{name:"第二用户",password:"second-secret"}] and
  .tls == {enabled:true,server_name:"edge.example",certificate_path:$cert,key_path:$key} and
  .client_trust == "system" and .transport == {type:"ws",path:"/edge",headers:{Host:"edge.example"}}
' "${replace_record}" >/dev/null

# The same typed replacement path can explicitly change SNI, trust and
# transport while preserving stable identity, users and routing policy.
prompt_choice() { printf 1; }
trojan_prompt_transport() { SB_TROJAN_TRANSPORT_JSON='{"type":"grpc","service_name":"edited-service"}'; }
printf '\n\nedited.example\n\n\n' | plain_proxy_management_build_record trojan "${store_file}" replace edge "${replace_record}"
jq -e '.id == "edge" and .tag == "trojan-edge" and .outbound_policy == "direct" and
  (.authentication.users|length)==2 and .tls.server_name == "edited.example" and
  .client_trust == "certificate" and .transport == {type:"grpc",service_name:"edited-service"}' \
  "${replace_record}" >/dev/null

# The interactive surface is typed: it exposes TLS/transport fields and never
# asks the operator to paste an unvalidated JSON object.
prompt_choice() { printf 0; }
menu_text=$(printf '0\n' | trojan_instance_management_menu)
grep -Fq 'Trojan' <<< "${menu_text}"
grep -Eq 'TLS|传输' <<< "${menu_text}"
! grep -Fqi 'JSON' <<< "${menu_text}"
prompt_choice() { printf 2; }
real_trojan_instance_management_menu=$(declare -f trojan_instance_management_menu)

# The top-level menu routes Trojan to the typed handler without falling back
# to the legacy singleton editor.  Run the real dispatcher in a child shell;
# the mocked handler records the choice and the child exits at the next menu
# prompt, leaving this test process alive.
main_dispatch_marker="${TMP_DIR}/main-dispatch"
check_root() { :; }
acquire_managed_write_lock() { return 0; }
show_banner() { :; }
check_script_status() { :; }
check_sb_version() { :; }
check_bbr_status() { :; }
ensure_sbv_command_installed() { return 0; }
render_section_title() { :; }
render_menu_item() { :; }
render_main_menu_footer() { :; }
SB_VER_STATUS=''
SCRIPT_VER_STATUS=''
prompt_choice() {
  if [[ ! -e "${main_dispatch_marker}.entered" ]]; then
    : > "${main_dispatch_marker}.entered"
    printf '21\n'
  else
    printf '0\n'
  fi
}
trojan_instance_management_menu() {
  printf 'main %s\n' "${1:-}" > "${main_dispatch_marker}"
}
exit_script() { exit 0; }
set +e
( main ) >/dev/null 2>"${TMP_DIR}/main.stderr"
main_status=$?
set -e
if (( main_status != 0 )); then
  cat "${TMP_DIR}/main.stderr" >&2
  exit 1
fi
grep -Fq 'main ' "${main_dispatch_marker}"
! grep -Fq 'legacy' "${main_dispatch_marker}"

# update_config_only and remove_protocol_menu route structured Trojan state to
# the same CAS instance handler.  They must not invoke legacy save/generate.
route_calls="${TMP_DIR}/route-calls"
: > "${route_calls}"
load_current_config_state() { :; }
prompt_installed_protocol_selection() {
  SELECTED_PROTOCOL=trojan
  return 0
}
trojan_instance_management_menu() { printf '%s\n' "${1:-}" >> "${route_calls}"; }
update_config_only >/dev/null
grep -Fq 'replace' "${route_calls}"
list_installed_protocols() { printf 'trojan\n'; }
plain_proxy_structured_state_active() { [[ "${1:-}" == trojan ]]; }
printf '1\n' | remove_protocol_menu >/dev/null
grep -Fq 'delete' "${route_calls}"
eval "${real_trojan_instance_management_menu}"

# The node-information link surface has a dedicated Trojan branch: it prints
# sensitive links/outbounds only there and never falls through to Mixed's
# HTTP/SOCKS rendering.
agent_trojan_link_json() {
  jq -n '{links:{"trojan-edge-user":"trojan://u:p@example:443"},outbounds:[{type:"trojan",tag:"trojan-edge-user",password:"p"}],warnings:[{message:"Trojan warning"}]}'
}
SB_PROTOCOL=trojan
SB_INSTANCE_ID=edge
show_link_info_output=$(show_link_info '203.0.113.44' 'IPv4' 2>"${TMP_DIR}/show-link.stderr")
grep -Fq 'Trojan 实例 edge' <<< "${show_link_info_output}"
grep -Fq 'trojan://u:p@example:443' <<< "${show_link_info_output}"
grep -Fq 'trojan-edge-user' <<< "${show_link_info_output}"
grep -Fq 'Trojan warning' "${TMP_DIR}/show-link.stderr"

# Public plaintext requires an explicit acknowledgement and does not mutate.
prompt_file="${TMP_DIR}/consent-prompt"
prompt_yes_no() { printf '%s\n' "$1" > "${prompt_file}"; printf n; }
plain_answer=$(plain_proxy_management_prompt_public_consent trojan 0.0.0.0 '{"enabled":false}')
[[ "${plain_answer}" == n ]]
grep -Fq '明文' "${prompt_file}"
! grep -Fq 'TLS' "${prompt_file}"

# TLS public exposure is a distinct consent prompt, not mislabeled plaintext.
prompt_yes_no() { printf '%s\n' "$1" > "${prompt_file}"; printf n; }
tls_answer=$(plain_proxy_management_prompt_public_consent trojan 0.0.0.0 '{"enabled":true}')
[[ "${tls_answer}" == n ]]
grep -Fq 'TLS' "${prompt_file}"
! grep -Fq '明文' "${prompt_file}"

# Agent's typed lifecycle dispatch carries the Trojan protocol and expected CAS
# revision.  The mock is local-only and records no external API calls.
calls="${TMP_DIR}/cas-calls"
: > "${calls}"
apply_plain_proxy_instance_change() {
  printf '%s %s %s %s\n' "$1" "$2" "$3" "${5:-n}" >> "${calls}"
  jq -n --arg protocol "$1" --arg operation "$2" --argjson revision "$(($3 + 1))" \
    '{ok:true,protocol:$protocol,operation:$operation,revision:$revision}'
}
recover_plain_proxy_instance_transaction() {
  printf 'recover %s %s\n' "$1" "$2" >> "${calls}"
  jq -n '{ok:true,recovered:true}'
}
record_file="${TMP_DIR}/record.json"
jq -c '.instances[0]' "${store_file}" > "${record_file}"
create_output=$(agent_cli instance create trojan --json --yes --expected-revision 21 --file "${record_file}")
jq -e '.ok == true and .command == "instance" and .data.protocol == "trojan" and .data.revision == 22' <<< "${create_output}" >/dev/null
grep -Fq 'trojan create 21' "${calls}"

# Malformed/unsafe revision is rejected before any mutator call.
before_calls=$(<"${calls}")
invalid_output=$(agent_cli instance replace trojan --json --yes --expected-revision 01 --file "${record_file}" || true)
jq -e '.ok == false and .error == "invalid_arguments"' <<< "${invalid_output}" >/dev/null
[[ "$(<"${calls}")" == "${before_calls}" ]]

mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"mixed",expected_revision:"21"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
if trojan_instance_management_menu recover >/dev/null 2>&1; then
  printf 'Trojan menu accepted a Mixed recovery journal\n' >&2
  exit 1
fi
! grep -Fq 'recover trojan' "${calls}"
rm -rf -- "${SB_PROJECT_DIR}.instance-write.lock"

mkdir -p "${SB_PROJECT_DIR}.instance-write.lock"
jq -n '{schema_version:1,protocol:"trojan",expected_revision:"21"}' > "${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
prompt_choice() { printf 1; }
prompt_yes_no() { printf y; }
trojan_instance_management_menu recover >/dev/null
grep -Fq 'recover trojan 21' "${calls}"

printf 'Trojan instance menu checks passed: typed-list=2 CAS-revision=21 recovery=1\n'
