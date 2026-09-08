#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "VLESS plain SubMan sync failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"
state_file="${SB_PROTOCOL_STATE_DIR}/vless-plain.env"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"
jq -n '
  {schema_version:1,protocol:"vless-plain",revision:9,default_instance_id:"system-ws",instances:[
    {id:"system-ws",name:"System WS",tag:"vless-ws",listen:{address:"0.0.0.0",port:33611},
     authentication:{users:[{name:"alice",uuid:"11111111-1111-4111-8111-111111111111",flow:""},
       {name:"bob",uuid:"22222222-2222-4222-8222-222222222222",flow:""}]},
     tls:{enabled:true,server_name:"ws.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},
     client_trust:"system",transport:{type:"ws",path:"/vless",headers:{Host:"ws.example"}},outbound_policy:"default",dependencies:[]},
    {id:"certificate",name:"Certificate",tag:"vless-cert",listen:{address:"127.0.0.1",port:33612},
     authentication:{users:[{name:"cert",uuid:"33333333-3333-4333-8333-333333333333",flow:""}]},
     tls:{enabled:true,server_name:"cert.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},
     client_trust:"certificate",transport:{type:"ws",path:"/cert"},outbound_policy:"default",dependencies:[]},
    {id:"custom-header",name:"Custom header",tag:"vless-custom",listen:{address:"127.0.0.1",port:33613},
     authentication:{users:[{name:"custom",uuid:"44444444-4444-4444-8444-444444444444",flow:""}]},
     tls:{enabled:true,server_name:"custom.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},
     client_trust:"system",transport:{type:"ws",path:"/custom",headers:{Host:"custom.example","X-Extra":"do-not-drop"}},outbound_policy:"default",dependencies:[]},
    {id:"plaintext",name:"Plaintext",tag:"vless-plain",listen:{address:"127.0.0.1",port:33614},
     authentication:{users:[{name:"plain",uuid:"55555555-5555-4555-8555-555555555555",flow:""}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"
printf '%s\n' INSTALLED_PROTOCOLS=vless-plain PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
chmod 600 "${SB_PROTOCOL_INDEX_FILE}"

validate_structured_instance_store vless-plain "${store_file}"
save_plain_proxy_structured_marker vless-plain
SUBMAN_NODE_PREFIX='vless-sync'
list_subman_addresses_for_current_protocol() { printf 'IPv4|198.51.100.21\n'; }
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_node() {
  MOCK_KEYS+=("${1}")
  MOCK_PAYLOADS+=("${2}")
  return 0
}

push_subman_vless_plain_protocol y
[[ "${SUBMAN_VLESS_PLAIN_SYNCED}" == 3 ]]
[[ "${SUBMAN_VLESS_PLAIN_SKIPPED}" == 2 ]]
[[ "${SUBMAN_VLESS_PLAIN_FAILED}" == 0 ]]
[[ ${#MOCK_PAYLOADS[@]} -eq 3 ]]
printf '%s\n' "${MOCK_PAYLOADS[@]}" | jq -s -e \
  'all(.[]; .type=="vless" and .source=="single" and .enabled==true and (.raw|startswith("vless://")))' >/dev/null
! printf '%s\n' "${MOCK_KEYS[@]}" | grep -Eq 'alice|bob|cert|plain|secret'
! printf '%s\n' "${MOCK_PAYLOADS[@]}" | grep -Eq 'private.key|BEGIN PRIVATE KEY|X-Extra'
jq -e 'length==2 and (map(.code)|sort)==["vless_plain_tls_certificate_uri_unrepresentable","vless_plain_transport_uri_unrepresentable"] and
  all(.[]; .instance_id|IN("certificate","custom-header"))' <<< "${SUBMAN_VLESS_PLAIN_WARNINGS_JSON}" >/dev/null

if build_vless_plain_subman_uri_from_store "${store_file}" 198.51.100.21 certificate cert 'Certificate'; then
  printf 'certificate-trust VLESS URI was unexpectedly accepted\n' >&2
  exit 1
else
  uri_status=$?
  [[ "${uri_status}" == 31 ]]
fi
if build_vless_plain_subman_uri_from_store "${store_file}" 198.51.100.21 custom-header custom 'Custom'; then
  printf 'custom-header VLESS URI was unexpectedly accepted\n' >&2
  exit 1
else
  uri_status=$?
  [[ "${uri_status}" == 32 ]]
fi

push_subman_node() { return 73; }
if push_subman_vless_plain_instance system-ws 198.51.100.21 y IPv4; then
  printf 'VLESS SubMan producer failure was reported as success\n' >&2
  exit 1
fi
[[ "${SUBMAN_VLESS_PLAIN_SYNCED}" == 0 && "${SUBMAN_VLESS_PLAIN_SKIPPED}" == 0 && "${SUBMAN_VLESS_PLAIN_FAILED}" == 2 ]]

printf 'VLESS plain SubMan sync checks passed: synced=3 skipped=2 stable-user-keys=2\n'
