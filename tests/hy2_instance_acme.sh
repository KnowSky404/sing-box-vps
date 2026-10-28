#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "HY2 ACME regression failed at line %s\n" "${LINENO}" >&2' ERR

core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
store="${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
mkdir -p "$(dirname "${store}")"
jq -n --arg directory "${TMP_DIR}/acme" '{schema_version:1,protocol:"hy2",revision:4,default_instance_id:"http",instances:[
  {id:"http",name:"HTTP certificate",tag:"hy2-http",listen:{address:"127.0.0.1",port:48443},
   authentication:{users:[{name:"alice",password:"http-password"}]},
   tls:{enabled:true,server_name:"hy2.example.com",acme:{domain:["hy2.example.com"],data_directory:$directory,disable_tls_alpn_challenge:true}},
   client_trust:"system",bandwidth:{up_mbps:null,down_mbps:null},obfs:{enabled:false,type:"",password:""},masquerade:"",
   outbound_policy:"default",dependencies:[]},
  {id:"dns",name:"DNS certificate",tag:"hy2-dns",listen:{address:"127.0.0.1",port:48444},
   authentication:{users:[{name:"bob",password:"dns-password"}]},
   tls:{enabled:true,server_name:"dns.example.com",acme:{domain:["dns.example.com","alt.example.com"],email:"admin@example.com",
     data_directory:$directory,dns01_challenge:{provider:"cloudflare",api_token:"fixture-dns-token",zone_token:"fixture-zone-token"}}},
   client_trust:"system",bandwidth:{up_mbps:10,down_mbps:null},obfs:{enabled:false,type:"",password:""},masquerade:"",
   outbound_policy:"direct",dependencies:[]}
]}' > "${store}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/hy2.env"
validate_structured_instance_store hy2 "${store}"
SB_VERSION=1.14.2
routes=$(render_structured_instance_route_rules hy2 "${store}")
render_structured_instance_inbounds hy2 "${store}" | jq -s --argjson routes "${routes}" \
  '{log:{disabled:true},inbounds:.,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$routes,final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"
jq -e 'all(.inbounds[]; .tls.certificate_provider.type=="acme" and .tls.alpn==["h3"] and (.tls|has("acme")|not)) and
  .inbounds[0].tls.certificate_provider.domain==["hy2.example.com"] and
  .inbounds[1].tls.certificate_provider.dns01_challenge.api_token=="fixture-dns-token"' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
plain_proxy_structured_state_matches_config hy2
plain_proxy_validate_state_inventory hy2
load_protocol_instance_state hy2 dns
[[ "${SB_HY2_TLS_MODE}" == acme && "${SB_HY2_ACME_MODE}" == dns && "${SB_HY2_CF_API_TOKEN}" == fixture-dns-token ]]
[[ -z "$(build_hy2_certificate_provider_json)" ]]
summary=$(agent_hy2_node_json 198.51.100.2)
jq -e '.tls_mode=="acme" and .shareable and .client_exportable and (tostring|contains("fixture-dns-token")|not)' <<< "${summary}" >/dev/null
links=$(agent_hy2_link_json 198.51.100.2)
jq -e '(.links|length)==1 and (.outbounds|length)==1 and
  (.outbounds[0].tls|keys|sort)==["enabled","server_name"] and
  (tostring|contains("fixture-dns-token")|not)' <<< "${links}" >/dev/null
outbounds=$(build_client_hy2_outbounds 198.51.100.2 | jq -s .)
jq -n --argjson outbounds "${outbounds}" '{outbounds:$outbounds}' > "${TMP_DIR}/client.json"
"${core}" check -c "${TMP_DIR}/client.json"
build_hy2_subman_links_and_warnings_json 198.51.100.2 dns > "${TMP_DIR}/links.json"
jq -e '(.links|length)==1 and (tostring|contains("fixture-dns-token")|not)' "${TMP_DIR}/links.json" >/dev/null
SUBMAN_NODE_PREFIX=hy2-acme-test
list_subman_addresses_for_current_protocol() { printf 'IPv4|198.51.100.2\n'; }
push_subman_node() { printf '%s\n' "$2" >> "${TMP_DIR}/subman-payloads.jsonl"; }
push_subman_hy2_protocol y
[[ "${SUBMAN_HY2_SYNCED}" == 2 && "${SUBMAN_HY2_FAILED}" == 0 ]]
! grep -Fq fixture-dns-token "${TMP_DIR}/subman-payloads.jsonl"

# Version selection changes only the runtime TLS representation; state and
# credentials remain identical, and intake recovers either representation.
SB_VERSION=1.13.18
render_structured_instance_inbounds hy2 "${store}" | jq -s --argjson routes "${routes}" \
  '{inbounds:.,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$routes,final:"direct"}}' > "${TMP_DIR}/server-113.json"
jq -e 'all(.inbounds[]; .tls.acme.domain and (.tls|has("certificate_provider")|not))' "${TMP_DIR}/server-113.json" >/dev/null
plain_proxy_structured_state_matches_config hy2 "${TMP_DIR}/server-113.json"
if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then "${SINGBOX_BINARY_113}" check -c "${TMP_DIR}/server-113.json"; fi
SB_VERSION=1.14.2

# A shared legacy ACME provider resolves losslessly, including alternate
# domains, its storage directory, and the separate Cloudflare zone token.
jq '.inbounds[1].tls.certificate_provider as $provider |
  .certificate_providers=[$provider+{tag:"legacy-provider"}] |
  .inbounds[1].tls.certificate_provider="legacy-provider"' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/shared.json"
plain_proxy_structured_state_matches_config hy2 "${TMP_DIR}/shared.json"

for expression in \
  '.instances[0].client_trust="certificate"' \
  '.instances[0].tls.certificate_path="/unexpected.pem"' \
  '.instances[0].tls.acme.domain=[]' \
  '.instances[0].tls.acme.disable_http_challenge="false"' \
  '.instances[0].tls.acme.unknown_option=true' \
  '.instances[1].tls.acme.dns01_challenge.api_token=""' \
  '.instances[1].tls.acme.dns01_challenge.provider="unsupported"'; do
  jq "${expression}" "${store}" > "${TMP_DIR}/invalid.json"
  if validate_structured_instance_store hy2 "${TMP_DIR}/invalid.json" 2>"${TMP_DIR}/invalid.stderr"; then
    printf 'invalid ACME record accepted: %s\n' "${expression}" >&2; exit 1
  fi
  ! grep -Fq fixture-dns-token "${TMP_DIR}/invalid.stderr"
done
for expression in \
  '.certificate_providers += .certificate_providers' \
  '.certificate_providers[0].type="unsupported"' \
  '.inbounds[1].tls.acme={domain:["conflict.example.com"]}' \
  '.inbounds[1].unknown_option=true' \
  '.inbounds[1].tls.alpn=["h2"]'; do
  jq "${expression}" "${TMP_DIR}/shared.json" > "${TMP_DIR}/invalid-config.json"
  if hy2_config_store_candidate "${TMP_DIR}/invalid-config.json" >"${TMP_DIR}/candidate.json" 2>"${TMP_DIR}/invalid.stderr"; then
    printf 'lossy ACME intake accepted: %s\n' "${expression}" >&2; exit 1
  fi
  ! grep -Fq fixture-dns-token "${TMP_DIR}/invalid.stderr"
done

# Whole-config regeneration must keep both instance-local providers and must
# not emit the legacy shared provider from whichever instance was loaded last.
ln -s "${core}" "${SINGBOX_BIN_PATH}"
write_protocol_index hy2
SB_ADVANCED_ROUTE=n
SB_ENABLE_WARP=n
generate_config > "${TMP_DIR}/generate.log" 2>&1
jq -e '([.inbounds[] | select(.type=="hysteria2")]|length)==2 and
  ((.certificate_providers // [])|length)==0 and
  all(.inbounds[]; .tls.certificate_provider.type=="acme")' "${SINGBOX_CONFIG_FILE}" >/dev/null
plain_proxy_structured_state_matches_config hy2
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'HY2 ACME record, renderer, intake, export and validation regressions passed\n'
