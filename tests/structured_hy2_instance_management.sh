#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
state_file="${SB_PROTOCOL_STATE_DIR}/hy2.env"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
openssl req -x509 -newkey ed25519 -nodes \
  -keyout "${TMP_DIR}/hy2.key" -out "${TMP_DIR}/hy2.crt" \
  -subj /CN=hy2.example -days 1 >/dev/null 2>&1
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"
jq -n --arg certificate_path "${TMP_DIR}/hy2.crt" --arg key_path "${TMP_DIR}/hy2.key" '
  {schema_version:1,protocol:"hy2",revision:9,default_instance_id:"edge",instances:[
    {id:"edge",name:"Edge",tag:"hy2-edge",listen:{address:"0.0.0.0",port:443},
     authentication:{users:[{name:"alice",password:"p@ss"},{name:"bob",password:"p2"}]},
     tls:{enabled:true,server_name:"hy2.example",certificate_path:$certificate_path,key_path:$key_path},
     client_trust:"system",bandwidth:{up_mbps:10,down_mbps:null},
     obfs:{enabled:true,type:"salamander",password:"obfs"},masquerade:"https://example.com",
     outbound_policy:"default",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"

validate_structured_instance_store hy2 "${store_file}"
save_plain_proxy_structured_marker hy2
load_protocol_instance_state hy2 edge
[[ "${SB_INSTANCE_ID}" == edge ]]
[[ "${SB_HY2_UP_MBPS}" == 10 && -z "${SB_HY2_DOWN_MBPS}" ]]

jq -n '{inbounds:[{type:"hysteria2",tag:"hy2-edge"},{type:"hysteria2",tag:"hy2-edge-alt"}]}' > "${TMP_DIR}/typed-duplicate-config.json"
validate_live_inbound_inventory "${TMP_DIR}/typed-duplicate-config.json"

inbound=$(render_structured_instance_inbounds hy2 "${store_file}")
jq -e '.type=="hysteria2" and .tls.alpn==["h3"] and .up_mbps==10 and (has("down_mbps") | not)' <<< "${inbound}" >/dev/null
outbounds=$(build_client_hy2_outbounds 198.51.100.2 "${store_file}")
[[ "$(jq -s 'length' <<< "${outbounds}")" == 2 ]]

rendered=$(render_structured_instance_inbounds hy2 "${store_file}" | jq -s .)
routes=$(render_structured_instance_route_rules hy2 "${store_file}")
jq -n --argjson inbounds "${rendered}" --argjson routes "${routes}" \
  '{inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$routes,final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"
printf '%s\n' INSTALLED_PROTOCOLS=hy2 PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
candidate=$(plain_proxy_config_store_candidate hy2 "${SINGBOX_CONFIG_FILE}" "${store_file}")
jq -e '.revision==9 and .default_instance_id=="edge" and (.instances|length)==1' <<< "${candidate}" >/dev/null
rebuild_protocol_state_from_config
plain_proxy_structured_state_matches_config hy2
[[ "$(jq -r '.revision' "${store_file}")" == 9 ]]

uri=$(build_hy2_subman_uri_from_store "${store_file}" 198.51.100.2 edge alice Edge)
[[ "${uri}" == hy2://* && "${uri}" == *'obfs=salamander'* ]]
links=$(build_hy2_subman_links_and_warnings_json 198.51.100.2 edge)
jq -e '.links|length==2' <<< "${links}" >/dev/null
jq -e '.warnings|length==4 and ([.[]|select(.code=="hy2_uri_partial_options")]|length)==2 and ([.[]|select(.code=="hy2_ed25519_share_link_requires_client_override")]|length)==2' <<< "${links}" >/dev/null

SB_PROTOCOL=hy2
agent_links=$(agent_hy2_link_json 198.51.100.2)
jq -e '([.warnings[]|select(.code=="hy2_ed25519_share_link_requires_client_override")]|length)==1' <<< "${agent_links}" >/dev/null

SUBMAN_NODE_PREFIX=hy2-sync
list_subman_addresses_for_current_protocol() { printf 'IPv4|198.51.100.2\n'; }
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_node() {
  MOCK_KEYS+=("${1}")
  MOCK_PAYLOADS+=("${2}")
}

push_subman_hy2_protocol y
[[ "${SUBMAN_HY2_SYNCED}" == 2 ]]
[[ "${SUBMAN_HY2_SKIPPED}" == 0 && "${SUBMAN_HY2_FAILED}" == 0 ]]
[[ ${#MOCK_PAYLOADS[@]} -eq 2 ]]
jq -e '([.[]|select(.code=="hy2_ed25519_share_link_requires_client_override")]|length)==2' <<< "${SUBMAN_HY2_WARNINGS_JSON}" >/dev/null
printf '%s\n' "${MOCK_PAYLOADS[@]}" | jq -s -e 'all(.[]; .type=="hysteria2" and .source=="single" and (.raw|startswith("hy2://")))' >/dev/null
! printf '%s\n' "${MOCK_KEYS[@]}" | grep -Eq 'alice|bob|p@ss|obfs'

printf 'structured Hysteria2 instance checks passed: users=2 independent-rate-limit=1\n'
