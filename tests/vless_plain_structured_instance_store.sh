#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 123
# Source at file scope so Bash 4.2 retains readonly registry arrays.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "VLESS structured store failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"
state_file="${SB_PROTOCOL_STATE_DIR}/vless-plain.env"
cert_file="${TMP_DIR}/vless.crt"
key_file="${TMP_DIR}/vless.key"
printf '%s\n' 'certificate fixture' > "${cert_file}"
printf '%s\n' 'private key fixture' > "${key_file}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"

jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {schema_version:1,protocol:"vless-plain",revision:7,default_instance_id:"vless-ws",instances:[
    {id:"vless-native",name:"VLESS native",tag:"vless-native",listen:{address:"127.0.0.1",port:33511},
     authentication:{users:[{name:"alice",uuid:"11111111-1111-4111-8111-111111111111",flow:""},
       {name:"bob",uuid:"22222222-2222-4222-8222-222222222222",flow:""}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"vless-ws",name:"VLESS WebSocket",tag:"vless-ws",listen:{address:"0.0.0.0",port:33512},
     authentication:{users:[{name:"ws-user",uuid:"33333333-3333-4333-8333-333333333333",flow:""}]},
     tls:{enabled:true,server_name:"vless.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
     transport:{type:"ws",path:"/vless",headers:{Host:"vless.example"}},outbound_policy:"direct",dependencies:[]},
    {id:"vless-quic",name:"VLESS QUIC",tag:"vless-quic",listen:{address:"127.0.0.1",port:33513},
     authentication:{users:[{name:"quic-user",uuid:"44444444-4444-4444-8444-444444444444",flow:""}]},
     tls:{enabled:true,server_name:"quic.example",certificate_path:$cert,key_path:$key},client_trust:"system",
     transport:{type:"quic"},outbound_policy:"warp",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"

[[ "$(structured_instance_store_protocol vless-plain)" == vless-plain ]]
[[ "$(normalize_protocol_id vless)" == vless-reality ]]
validate_structured_instance_store vless-plain "${store_file}"
plain_proxy_structured_state_active vless-plain
[[ "$(list_protocol_instance_ids vless-plain)" == $'vless-native\nvless-ws\nvless-quic' ]]
[[ "$(protocol_default_instance_id vless-plain)" == vless-ws ]]

load_plain_proxy_structured_instance vless-plain vless-ws
[[ "${SB_PROTOCOL}" == vless-plain && "${SB_INSTANCE_ID}" == vless-ws ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 && "${SB_PORT}" == 33512 ]]
jq -e 'length == 1 and .[0].uuid == "33333333-3333-4333-8333-333333333333" and .[0].flow == ""' \
  <<< "${SB_VLESS_PLAIN_AUTH_JSON}" >/dev/null
jq -e '.type == "ws" and .path == "/vless" and .headers.Host == "vless.example"' \
  <<< "${SB_VLESS_PLAIN_TRANSPORT_JSON}" >/dev/null
jq -e '.enabled == true and .server_name == "vless.example"' <<< "${SB_VLESS_PLAIN_TLS_JSON}" >/dev/null
[[ "${SB_VLESS_PLAIN_CLIENT_TRUST}" == certificate ]]

rendered=$(render_structured_instance_inbounds vless-plain "${store_file}" | jq -s .)
jq -e '
  length == 3 and
  any(.[]; .tag == "vless-native" and .type == "vless" and
    .users[0].uuid == "11111111-1111-4111-8111-111111111111" and
    .users[1].uuid == "22222222-2222-4222-8222-222222222222" and
    (has("tls") | not) and (has("transport") | not)) and
  any(.[]; .tag == "vless-ws" and .tls.enabled == true and
    .tls.alpn == ["http/1.1"] and .transport.type == "ws" and
    (.users[0] | has("flow") | not)) and
  any(.[]; .tag == "vless-quic" and .tls.alpn == ["h3"] and .transport.type == "quic")
' <<< "${rendered}" >/dev/null
routes=$(render_structured_instance_route_rules vless-plain "${store_file}")
jq -e 'length == 5 and any(.[]; .inbound == "vless-ws" and .outbound == "direct") and
  any(.[]; .inbound == "vless-quic" and .outbound == "warp-ep")' <<< "${routes}" >/dev/null

jq -c '.instances[1]' "${store_file}" > "${TMP_DIR}/instance.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/instance.json" vless-plain

reject_instance() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${TMP_DIR}/instance.json" > "${invalid_file}"
  if structured_instance_store_validate_instance_argument "${invalid_file}" vless-plain; then
    printf 'accepted invalid VLESS instance: %s\n' "${label}" >&2
    return 1
  fi
}

reject_store() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${store_file}" > "${invalid_file}"
  if validate_structured_instance_store vless-plain "${invalid_file}"; then
    printf 'accepted invalid VLESS store: %s\n' "${label}" >&2
    return 1
  fi
}

reject_instance bad_uuid '.authentication.users[0].uuid = "not-a-uuid"'
reject_instance bad_flow '.authentication.users[0].flow = "bad-flow"'
reject_instance flow_without_tls '.authentication.users[0].flow = "xtls-rprx-vision" | .tls = {enabled:false} | .client_trust = "system"'
reject_instance bad_transport_field '.transport.extra = "reject"'
reject_instance httpupgrade_transport '.transport = {type:"httpupgrade",path:"/upgrade"}'
reject_instance ws_early_data '.transport = {type:"ws",path:"/vless",max_early_data:1,early_data_header_name:"X-Early-Data"}'
reject_instance quic_without_tls '.transport = {type:"quic"} | .tls = {enabled:false} | .client_trust = "system"'
reject_store duplicate_names '.instances[0].authentication.users[1].name = "alice"'
reject_store duplicate_uuids '.instances[0].authentication.users[1].uuid = "11111111-1111-4111-8111-111111111111"'
reject_store unknown_record_field '.instances[0].unknown = true'
reject_store tls_unknown_field '.instances[1].tls.provider = "acme"'

printf 'VLESS plain structured instance store checks passed\n'
