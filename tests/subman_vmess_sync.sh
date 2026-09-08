#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "VMess SubMan sync failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
state_file="${SB_PROTOCOL_STATE_DIR}/vmess.env"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"
jq -n '
  {schema_version:1,protocol:"vmess",revision:9,default_instance_id:"system-ws",instances:[
    {id:"system-ws",name:"System WS",tag:"vmess-ws",listen:{address:"0.0.0.0",port:33601},
     authentication:{users:[{name:"alice",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto"},
       {name:"bob",uuid:"22222222-2222-4222-8222-222222222222",alter_id:7,security:"aes-128-gcm"}]},
     tls:{enabled:true,server_name:"ws.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},
     client_trust:"system",transport:{type:"ws",path:"/vmess",headers:{Host:"ws.example"}},outbound_policy:"default",dependencies:[]},
    {id:"certificate",name:"Certificate",tag:"vmess-cert",listen:{address:"127.0.0.1",port:33602},
     authentication:{users:[{name:"cert",uuid:"33333333-3333-4333-8333-333333333333",alter_id:0,security:"auto"}]},
     tls:{enabled:true,server_name:"cert.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},
     client_trust:"certificate",transport:{type:"ws",path:"/cert"},outbound_policy:"default",dependencies:[]},
    {id:"plaintext",name:"Plaintext",tag:"vmess-plain",listen:{address:"127.0.0.1",port:33603},
     authentication:{users:[{name:"plain",uuid:"44444444-4444-4444-8444-444444444444",alter_id:0,security:"none"}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"
printf '%s\n' INSTALLED_PROTOCOLS=vmess PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
chmod 600 "${SB_PROTOCOL_INDEX_FILE}"

validate_structured_instance_store vmess "${store_file}"
save_plain_proxy_structured_marker vmess
SUBMAN_NODE_PREFIX='vmess-sync'
list_subman_addresses_for_current_protocol() { printf 'IPv4|198.51.100.21\n'; }
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_node() {
  MOCK_KEYS+=("${1}")
  MOCK_PAYLOADS+=("${2}")
  return 0
}

push_subman_vmess_protocol y
[[ "${SUBMAN_VMESS_SYNCED}" == 3 ]]
[[ "${SUBMAN_VMESS_SKIPPED}" == 1 ]]
[[ "${SUBMAN_VMESS_FAILED}" == 0 ]]
[[ ${#MOCK_PAYLOADS[@]} -eq 3 ]]
printf '%s\n' "${MOCK_PAYLOADS[@]}" | jq -s -e \
  'all(.[]; .type=="vmess" and .source=="single" and .enabled==true and (.raw|startswith("vmess://")))' >/dev/null
! printf '%s\n' "${MOCK_KEYS[@]}" | grep -Eq 'alice|bob|cert|plain|secret'
! printf '%s\n' "${MOCK_PAYLOADS[@]}" | grep -Eq 'private.key|BEGIN PRIVATE KEY'
jq -e 'length==1 and .[0].code=="vmess_tls_certificate_uri_unrepresentable" and .[0].instance_id=="certificate"' \
  <<< "${SUBMAN_VMESS_WARNINGS_JSON}" >/dev/null

if build_vmess_subman_uri_from_store "${store_file}" 198.51.100.21 certificate cert 'Certificate'; then
  printf 'certificate-trust VMess URI was unexpectedly accepted\n' >&2
  exit 1
else
  status=$?
  [[ "${status}" == 31 ]]
fi

push_subman_node() { return 73; }
if push_subman_vmess_instance system-ws 198.51.100.21 y IPv4; then
  printf 'VMess SubMan producer failure was reported as success\n' >&2
  exit 1
fi
[[ "${SUBMAN_VMESS_SYNCED}" == 0 && "${SUBMAN_VMESS_SKIPPED}" == 0 && "${SUBMAN_VMESS_FAILED}" == 2 ]]
printf 'VMess SubMan sync checks passed: synced=3 skipped=1 stable-user-keys=2\n'
