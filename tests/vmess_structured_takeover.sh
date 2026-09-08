#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 124
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "VMess structured takeover failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED_PROTOCOLS=vmess\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=vmess-takeover.example' \
  -addext 'subjectAltName=DNS:vmess-takeover.example' \
  -keyout "${TMP_DIR}/vmess.key" -out "${TMP_DIR}/vmess.crt" >/dev/null 2>&1
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/vmess.env"

jq -n --arg cert "${TMP_DIR}/vmess.crt" --arg key "${TMP_DIR}/vmess.key" '
  {schema_version:1,protocol:"vmess",revision:5,default_instance_id:"vmess-web",instances:[
    {id:"vmess-native",name:"Native display",tag:"vmess-native",listen:{address:"127.0.0.1",port:33421},
     authentication:{users:[{name:"alice",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"aes-128-gcm"}]},
     tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"direct",dependencies:[]},
    {id:"vmess-web",name:"Web display",tag:"vmess-web",listen:{address:"127.0.0.1",port:33422},
     authentication:{users:[{name:"web",uuid:"22222222-2222-4222-8222-222222222222",alter_id:5,security:"chacha20-poly1305"}]},
     tls:{enabled:true,server_name:"vmess-takeover.example",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",transport:{type:"ws",path:"/vmess",headers:{Host:"vmess-takeover.example"}},
     outbound_policy:"direct",dependencies:[]}
  ]}
' > "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
chmod 600 "${SB_PROTOCOL_STATE_DIR}/vmess.env" "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"

jq -n --arg cert "${TMP_DIR}/vmess.crt" --arg key "${TMP_DIR}/vmess.key" '
  {log:{level:"warn"},inbounds:[
    {type:"vmess",tag:"vmess-native",listen:"127.0.0.1",listen_port:33421,
     users:[{name:"alice",uuid:"11111111-1111-4111-8111-111111111111",alterId:0}]},
    {type:"vmess",tag:"vmess-web",listen:"127.0.0.1",listen_port:33422,
     users:[{name:"web",uuid:"22222222-2222-4222-8222-222222222222",alterId:5}],
     tls:{enabled:true,server_name:"vmess-takeover.example",certificate_path:$cert,key_path:$key},
     transport:{type:"ws",path:"/vmess",headers:{Host:"vmess-takeover.example"}}}
  ],outbounds:[{type:"direct",tag:"direct"}],route:{rules:[
    {inbound:"vmess-native",action:"sniff"},{inbound:"vmess-native",action:"route",outbound:"direct"},
    {inbound:"vmess-web",action:"route",outbound:"direct"}
  ],final:"direct"}}
' > "${SINGBOX_CONFIG_FILE}"

before_config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
candidate=$(vmess_config_store_candidate)
jq -e '
  .protocol == "vmess" and .revision == 5 and .default_instance_id == "vmess-web" and
  (.instances | length) == 2 and
  any(.instances[]; .tag == "vmess-native" and .id == "vmess-native" and
    .authentication.users[0].security == "aes-128-gcm") and
  any(.instances[]; .tag == "vmess-web" and .client_trust == "certificate" and
    .transport.type == "ws")
' <<< "${candidate}" >/dev/null
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]

rebuild_protocol_state_from_config
plain_proxy_structured_state_active vmess
plain_proxy_validate_state_inventory vmess
plain_proxy_structured_state_matches_config vmess
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]
jq -e '
  .protocol == "vmess" and .revision == 5 and .default_instance_id == "vmess-web" and
  any(.instances[]; .tag == "vmess-native" and .name == "Native display" and
    .authentication.users[0].security == "aes-128-gcm") and
  any(.instances[]; .tag == "vmess-web" and .name == "Web display" and .client_trust == "certificate")
' "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" >/dev/null

# The renderer's ALPN is part of the typed contract. A self-rendered config
# is accepted and retains the client-only security metadata from the store.
rendered=$(render_structured_instance_inbounds vmess "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" | jq -s .)
jq --argjson inbounds "${rendered}" '.inbounds=$inbounds' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/self-rendered.json"
self_candidate=$(vmess_config_store_candidate "${TMP_DIR}/self-rendered.json" "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json")
jq -e 'any(.instances[]; .tag == "vmess-web" and .authentication.users[0].security == "chacha20-poly1305" and .transport.type == "ws")' \
  <<< "${self_candidate}" >/dev/null
jq -e 'any(.[]; .tag == "vmess-web" and .tls.alpn == ["http/1.1"])' <<< "${rendered}" >/dev/null

jq '.inbounds |= map(if .tag == "vmess-web" then .tls.alpn=["h2"] else . end)' \
  "${TMP_DIR}/self-rendered.json" > "${TMP_DIR}/bad-alpn.json"
if vmess_config_store_candidate "${TMP_DIR}/bad-alpn.json" "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" \
  >/dev/null 2>"${TMP_DIR}/bad-alpn.stderr"; then
  printf 'accepted mismatched VMess TLS ALPN during takeover\n' >&2
  exit 1
fi
jq '.inbounds[0].multiplex={enabled:true}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-field.json"
if vmess_config_store_candidate "${TMP_DIR}/bad-field.json" "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" \
  >/dev/null 2>"${TMP_DIR}/bad-field.stderr"; then
  printf 'accepted unsupported VMess inbound field during takeover\n' >&2
  exit 1
fi

core_checks=0
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${core_binary}" && -x "${core_binary}" ]]; then
    "${core_binary}" check -c "${SINGBOX_CONFIG_FILE}"
    core_checks=$((core_checks + 1))
  fi
done

printf 'VMess structured takeover checks passed; real core checks=%s\n' "${core_checks}"
