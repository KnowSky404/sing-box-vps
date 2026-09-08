#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 123
# Source at file scope so Bash 4.2 retains readonly registry arrays.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "VMess structured store failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
state_file="${SB_PROTOCOL_STATE_DIR}/vmess.env"
cert_file="${TMP_DIR}/vmess.crt"
key_file="${TMP_DIR}/vmess.key"
printf '%s\n' 'certificate fixture' > "${cert_file}"
printf '%s\n' 'private key fixture' > "${key_file}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"

jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {schema_version:1,protocol:"vmess",revision:7,default_instance_id:"vmess-ws",instances:[
    {id:"vmess-native",name:"VMess native",tag:"vmess-native",listen:{address:"127.0.0.1",port:33411},
     authentication:{users:[{name:"alice",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto"},
       {name:"bob",uuid:"22222222-2222-4222-8222-222222222222",alter_id:10,security:"aes-128-gcm"}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"vmess-ws",name:"VMess WebSocket",tag:"vmess-ws",listen:{address:"0.0.0.0",port:33412},
     authentication:{users:[{name:"ws-user",uuid:"33333333-3333-4333-8333-333333333333",alter_id:0,security:"chacha20-poly1305"}]},
     tls:{enabled:true,server_name:"vmess.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
     transport:{type:"ws",path:"/vmess",headers:{Host:"vmess.example"}},outbound_policy:"direct",dependencies:[]},
    {id:"vmess-quic",name:"VMess QUIC",tag:"vmess-quic",listen:{address:"127.0.0.1",port:33412},
     authentication:{users:[{name:"quic-user",uuid:"44444444-4444-4444-8444-444444444444",alter_id:0,security:"none"}]},
     tls:{enabled:true,server_name:"quic.example",certificate_path:$cert,key_path:$key},client_trust:"system",
     transport:{type:"quic"},outbound_policy:"warp",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"

[[ "$(structured_instance_store_protocol vmess)" == vmess ]]
validate_structured_instance_store vmess "${store_file}"
plain_proxy_structured_state_active vmess
[[ "$(list_protocol_instance_ids vmess)" == $'vmess-native\nvmess-ws\nvmess-quic' ]]
[[ "$(protocol_default_instance_id vmess)" == vmess-ws ]]

load_plain_proxy_structured_instance vmess vmess-ws
[[ "${SB_PROTOCOL}" == vmess && "${SB_INSTANCE_ID}" == vmess-ws ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 && "${SB_PORT}" == 33412 ]]
jq -e 'length == 1 and .[0].uuid == "33333333-3333-4333-8333-333333333333" and .[0].security == "chacha20-poly1305"' \
  <<< "${SB_VMESS_AUTH_JSON}" >/dev/null
jq -e '.type == "ws" and .path == "/vmess" and .headers.Host == "vmess.example"' \
  <<< "${SB_VMESS_TRANSPORT_JSON}" >/dev/null
jq -e '.enabled == true and .server_name == "vmess.example"' <<< "${SB_VMESS_TLS_JSON}" >/dev/null
[[ "${SB_VMESS_CLIENT_TRUST}" == certificate ]]

rendered=$(render_structured_instance_inbounds vmess "${store_file}" | jq -s .)
jq -e '
  length == 3 and
  any(.[]; .tag == "vmess-native" and .type == "vmess" and
    .users[0].uuid == "11111111-1111-4111-8111-111111111111" and
    .users[1].alterId == 10 and (has("tls") | not) and (has("transport") | not)) and
  any(.[]; .tag == "vmess-ws" and .tls.enabled == true and
    .tls.alpn == ["http/1.1"] and .transport.type == "ws") and
  any(.[]; .tag == "vmess-quic" and .tls.alpn == ["h3"] and .transport.type == "quic")
' <<< "${rendered}" >/dev/null
routes=$(render_structured_instance_route_rules vmess "${store_file}")
jq -e 'length == 5 and any(.[]; .inbound == "vmess-ws" and .outbound == "direct") and
  any(.[]; .inbound == "vmess-quic" and .outbound == "warp-ep")' <<< "${routes}" >/dev/null

jq -c '.instances[1]' "${store_file}" > "${TMP_DIR}/instance.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/instance.json" vmess

reject_instance() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${TMP_DIR}/instance.json" > "${invalid_file}"
  if structured_instance_store_validate_instance_argument "${invalid_file}" vmess; then
    printf 'accepted invalid VMess instance: %s\n' "${label}" >&2
    return 1
  fi
}

reject_store() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${store_file}" > "${invalid_file}"
  if validate_structured_instance_store vmess "${invalid_file}"; then
    printf 'accepted invalid VMess store: %s\n' "${label}" >&2
    return 1
  fi
}

reject_instance bad_uuid '.authentication.users[0].uuid = "not-a-uuid"'
reject_instance bad_alter_id '.authentication.users[0].alter_id = 65536'
reject_instance bad_security '.authentication.users[0].security = "aes-256-gcm"'
reject_instance bad_transport_field '.transport.extra = "reject"'
reject_instance httpupgrade_transport '.transport = {type:"httpupgrade",path:"/upgrade"}'
reject_instance ws_early_data '.transport = {type:"ws",path:"/vmess",max_early_data:1,early_data_header_name:"X-Early-Data"}'
reject_instance quic_without_tls '.transport = {type:"quic"} | .tls = {enabled:false} | .client_trust = "system"'
reject_store duplicate_names '.instances[0].authentication.users[1].name = "alice"'
reject_store duplicate_uuids '.instances[0].authentication.users[1].uuid = "11111111-1111-4111-8111-111111111111"'
reject_store unknown_record_field '.instances[0].unknown = true'
reject_store tls_unknown_field '.instances[1].tls.provider = "acme"'

printf 'VMess structured instance store checks passed\n'
