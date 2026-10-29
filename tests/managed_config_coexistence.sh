#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]' SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]' SB_WARP_REMOTE_RULE_SETS_JSON='[]' SB_WARP_RULE_SET_TAGS_JSON='[]'
}
ensure_stack_mode_state_loaded() { :; }
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
set_protocol_defaults mixed
SB_PORT=18080 SB_MIXED_AUTH_ENABLED=y SB_MIXED_USERNAME=managed-user SB_MIXED_PASSWORD=managed-secret SB_ADVANCED_ROUTE=n SB_ENABLE_WARP=n SB_INBOUND_STACK_MODE=ipv4_only
save_mixed_state
write_protocol_index mixed
generate_config >"${TMP_DIR}/initial.log"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
baseline="${SB_PROJECT_DIR}/managed-config.generated.json"
[[ "$(stat -c %a "${baseline}")" == 600 ]]
# Simulate a pre-upgrade installation with manual client-side extensions.
rm "${baseline}"
jq '(.outbounds[]|select(.tag=="direct").bind_interface)="lo" |
  (.dns.servers[]|select(.tag=="local-dns"))={type:"udp",tag:"local-dns",server:"127.0.0.1",server_port:53535} |
  .dns.servers += [{type:"local",tag:"manual-dns"}] |
  .outbounds += [{type:"socks",tag:"manual-proxy",server:"127.0.0.1",server_port:19090}] |
  .inbounds += [{type:"socks",tag:"manual-socks",listen:"127.0.0.1",listen_port:18091},{type:"direct",tag:"manual-client",listen:"127.0.0.1",listen_port:18090,override_address:"127.0.0.1",override_port:19091}] |
  .route.rules = [{inbound:"manual-client",action:"route",outbound:"manual-proxy"}] + .route.rules |
  .route.final="manual-proxy" | .route.default_domain_resolver="manual-dns" |
  .experimental={cache_file:{enabled:true,path:"/tmp/sbv-coexistence-cache.db"}}
' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/custom.json"
cp "${TMP_DIR}/custom.json" "${SINGBOX_CONFIG_FILE}"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
[[ "$(list_config_protocols)" == mixed ]]
# A manual restriction must not be broadened from stale wildcard state.
jq '(.inbounds[]|select(.tag=="mixed-in").listen)="127.0.0.1"' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/restricted.json"
cp "${TMP_DIR}/restricted.json" "${SINGBOX_CONFIG_FILE}"
if generate_config >"${TMP_DIR}/restricted.out" 2>"${TMP_DIR}/restricted.err"; then exit 1; fi
cmp "${TMP_DIR}/restricted.json" "${SINGBOX_CONFIG_FILE}"
[[ ! -e "${baseline}" ]]
cp "${TMP_DIR}/custom.json" "${SINGBOX_CONFIG_FILE}"
# A live-only credential rotation must never be reverted from stale state
# while establishing the first baseline, even alongside manual extensions.
jq '(.inbounds[]|select(.tag=="mixed-in").users[0].password)="rotated-secret"' \
  "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/rotated.json"
cp "${TMP_DIR}/rotated.json" "${SINGBOX_CONFIG_FILE}"
if generate_config >"${TMP_DIR}/rotated.out" 2>"${TMP_DIR}/rotated.err"; then exit 1; fi
cmp "${TMP_DIR}/rotated.json" "${SINGBOX_CONFIG_FILE}"
[[ ! -e "${baseline}" ]]
if grep -Eq 'managed-secret|rotated-secret' "${TMP_DIR}/rotated.out" "${TMP_DIR}/rotated.err"; then exit 1; else [[ "$?" == 1 ]]; fi
cp "${TMP_DIR}/custom.json" "${SINGBOX_CONFIG_FILE}"
generate_config >"${TMP_DIR}/legacy.log"
assert_manual_unchanged() {
  jq -S '{dns,experimental,client:[.inbounds[]|select(.tag=="manual-client" or .tag=="manual-socks")],
    outbounds:[.outbounds[]|select(.tag=="manual-proxy")],
    rules:[.route.rules[]|select(.inbound=="manual-client")],
    owned_extension:[.outbounds[]|select(.tag=="direct")|.bind_interface],
    final:.route.final,resolver:.route.default_domain_resolver}' "$1"
}
[[ "$(assert_manual_unchanged "${SINGBOX_CONFIG_FILE}")" == "$(assert_manual_unchanged "${TMP_DIR}/custom.json")" ]]
SB_PORT=18081
save_mixed_state
generate_config >"${TMP_DIR}/changed.log"
jq -e 'any(.inbounds[];.tag=="mixed-in" and .listen_port==18081)' "${SINGBOX_CONFIG_FILE}" >/dev/null
[[ "$(assert_manual_unchanged "${SINGBOX_CONFIG_FILE}")" == "$(assert_manual_unchanged "${TMP_DIR}/custom.json")" ]]
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
# Both an operator edit and a new managed edit target the same scalar.
jq '(.inbounds[]|select(.tag=="mixed-in").listen_port)=18082' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/conflict.json"
cp "${TMP_DIR}/conflict.json" "${SINGBOX_CONFIG_FILE}"
cp "${baseline}" "${TMP_DIR}/baseline.before"
SB_PORT=18083
save_mixed_state
if generate_config >"${TMP_DIR}/conflict.out" 2>"${TMP_DIR}/conflict.err"; then exit 1; fi
cmp "${TMP_DIR}/conflict.json" "${SINGBOX_CONFIG_FILE}"
cmp "${TMP_DIR}/baseline.before" "${baseline}"
grep -Fq '归属冲突' "${TMP_DIR}/conflict.err"
# State recovery imports only owned nodes; a manual SOCKS frontend remains
# outside the protocol store even while other protocol state is reconstructed.
rebuild_protocol_state_from_config
[[ ! -e "$(protocol_state_file socks)" ]]
[[ "$(list_indexed_protocols_raw)" == mixed ]]
[[ "$(assert_manual_unchanged "${SINGBOX_CONFIG_FILE}")" == "$(assert_manual_unchanged "${TMP_DIR}/custom.json")" ]]
# A valid operator-owned HTTP client is retained, while dangling references
# and unsupported endpoint types still fail the inventory boundary.
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-client-guards.json"
jq '.http_clients=[{tag:"manual-http",engine:"go"}] | .route.default_http_client="manual-http"' \
  "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/manual-http.json"
cp "${TMP_DIR}/manual-http.json" "${SINGBOX_CONFIG_FILE}"
managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
jq '.route.default_http_client="missing-http"' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/dangling-http.json"
if managed_component_state_matches_live_config "${TMP_DIR}/dangling-http.json"; then exit 1; fi
jq '.endpoints=[{type:"future-endpoint",tag:"unsupported"}]' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/unknown-endpoint.json"
if managed_component_state_matches_live_config "${TMP_DIR}/unknown-endpoint.json"; then exit 1; fi
cp "${TMP_DIR}/before-client-guards.json" "${SINGBOX_CONFIG_FILE}"
# A component create may not claim an existing operator-owned outbound.
jq -n '{id:"claim-manual",role:"outbound",type:"socks",tag:"manual-proxy",enabled:true,
  config:{server:"127.0.0.1",server_port:19090},route_rules:[]}' >"${TMP_DIR}/claim.json"
config_before=$(sha256sum "${SINGBOX_CONFIG_FILE}")
if managed_component_state_apply create 0 "${TMP_DIR}/claim.json" "" n >"${TMP_DIR}/claim.out" 2>"${TMP_DIR}/claim.err"; then exit 1; fi
[[ "${MANAGED_COMPONENT_LAST_ERROR}" == component_conflict ]]
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_before}" ]]
# A legacy component delete first captures old ownership inside the existing
# transaction, so removing its last owned outbound does not leave it live.
jq -n '{schema_version:1,revision:1,components:[{id:"owned",role:"outbound",type:"direct",
  tag:"owned-extra",enabled:true,config:{},route_rules:[]}]}' >"${SB_COMPONENT_STATE_FILE}"
chmod 600 "${SB_COMPONENT_STATE_FILE}"
jq '.outbounds += [{type:"direct",tag:"owned-extra"}]' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/legacy-component.json"
cp "${TMP_DIR}/legacy-component.json" "${SINGBOX_CONFIG_FILE}"
rm -f "${baseline}"
instance_firewall_prepare() {
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }
managed_component_state_apply delete 1 "" owned n >"${TMP_DIR}/component-delete.out" 2>"${TMP_DIR}/component-delete.err"
jq -e 'all(.outbounds[]; .tag!="owned-extra")' "${SINGBOX_CONFIG_FILE}" >/dev/null
[[ "$(assert_manual_unchanged "${SINGBOX_CONFIG_FILE}")" == "$(assert_manual_unchanged "${TMP_DIR}/custom.json")" ]]
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
# The first managed optional collection coexists with an existing manual
# client, and deleting the final managed entry keeps the manual collection.
jq '.http_clients=[{tag:"manual-http",engine:"go"}]' "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/first-http.json"
cp "${TMP_DIR}/first-http.json" "${SINGBOX_CONFIG_FILE}"
jq -n '{id:"first-http",role:"http_client",type:"shared",tag:"managed-http",enabled:true,
  config:{engine:"go"},route_rules:[]}' >"${TMP_DIR}/first-http-record.json"
managed_component_state_apply create 2 "${TMP_DIR}/first-http-record.json" "" n >"${TMP_DIR}/http-create.out" 2>"${TMP_DIR}/http-create.err"
jq -e '.http_clients==[{tag:"manual-http",engine:"go"},{tag:"managed-http",engine:"go"}]' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
managed_component_state_apply delete 3 "" first-http n >"${TMP_DIR}/http-delete.out" 2>"${TMP_DIR}/http-delete.err"
jq -e '.http_clients==[{tag:"manual-http",engine:"go"}]' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
# Optional tag collections use an empty absent baseline, but retain strict
# same-tag collision handling and remove only the last owned object.
for field in http_clients services certificate_providers network_namespaces endpoints; do
  printf '{"inbounds":[]}' >"${TMP_DIR}/optional.base"
  jq -n --arg field "${field}" '{inbounds:[],($field):[{tag:"manual",value:1}]}' >"${TMP_DIR}/optional.live"
  jq -n --arg field "${field}" '{inbounds:[],($field):[{tag:"managed",value:2}]}' >"${TMP_DIR}/optional.next"
  chmod 600 "${TMP_DIR}/optional.base"
  merge_generated_config_with_live "${TMP_DIR}/optional.next" "${TMP_DIR}/optional.live" "${TMP_DIR}/optional.base" >"${TMP_DIR}/optional.result"
  jq -e --arg field "${field}" '.[$field]==[{tag:"manual",value:1},{tag:"managed",value:2}]' "${TMP_DIR}/optional.result" >/dev/null
  cp "${TMP_DIR}/optional.next" "${TMP_DIR}/optional.base"
  cp "${TMP_DIR}/optional.result" "${TMP_DIR}/optional.live"
  printf '{"inbounds":[]}' >"${TMP_DIR}/optional.next"
  merge_generated_config_with_live "${TMP_DIR}/optional.next" "${TMP_DIR}/optional.live" "${TMP_DIR}/optional.base" >"${TMP_DIR}/optional.result"
  jq -e --arg field "${field}" '.[$field]==[{tag:"manual",value:1}]' "${TMP_DIR}/optional.result" >/dev/null
  printf '{"inbounds":[]}' >"${TMP_DIR}/optional.base"
  jq -n --arg field "${field}" '{inbounds:[],($field):[{tag:"manual",value:2}]}' >"${TMP_DIR}/optional.next"
  if merge_generated_config_with_live "${TMP_DIR}/optional.next" "${TMP_DIR}/optional.live" "${TMP_DIR}/optional.base" >"${TMP_DIR}/optional.result" 2>/dev/null; then exit 1; fi
done
# New tags may not steal a pre-existing manual component of the same name.
printf '{"inbounds":[],"outbounds":[{"type":"direct","tag":"shared"}]}' >"${TMP_DIR}/base.json"
printf '{"inbounds":[],"outbounds":[{"type":"direct","tag":"shared"},{"type":"direct","tag":"manual"}]}' >"${TMP_DIR}/live.json"
printf '{"inbounds":[],"outbounds":[{"type":"direct","tag":"shared"},{"type":"block","tag":"manual"}]}' >"${TMP_DIR}/next.json"
chmod 600 "${TMP_DIR}/base.json"
if merge_generated_config_with_live "${TMP_DIR}/next.json" "${TMP_DIR}/live.json" "${TMP_DIR}/base.json" >"${TMP_DIR}/result" 2>/dev/null; then exit 1; fi
# Ordered auth/TLS arrays are atomic; concurrent edits must not union users
# or silently broaden protocols/cipher lists.
printf '{"inbounds":[{"type":"mixed","tag":"shared","users":[{"username":"u","password":"old"}]}]}' >"${TMP_DIR}/auth.base"
printf '{"inbounds":[{"type":"mixed","tag":"shared","users":[{"username":"u","password":"manual"}]}]}' >"${TMP_DIR}/auth.live"
printf '{"inbounds":[{"type":"mixed","tag":"shared","users":[{"username":"u","password":"new"}]}]}' >"${TMP_DIR}/auth.next"
chmod 600 "${TMP_DIR}/auth.base"
if merge_generated_config_with_live "${TMP_DIR}/auth.next" "${TMP_DIR}/auth.live" "${TMP_DIR}/auth.base" >"${TMP_DIR}/result" 2>/dev/null; then exit 1; fi
if merge_generated_config_with_live "${TMP_DIR}/auth.next" "${TMP_DIR}/auth.live" "${TMP_DIR}/no-baseline" >"${TMP_DIR}/result" 2>/dev/null; then exit 1; fi
printf '{"inbounds":[{"type":"vless","tag":"owned","users":[{"name":"main","uuid":"unchanged","flow":"xtls-rprx-vision"}]}]}' >"${TMP_DIR}/metadata.next"
printf '{"inbounds":[{"type":"vless","tag":"owned","users":[{"uuid":"unchanged"}]}]}' >"${TMP_DIR}/metadata.live"
merge_generated_config_with_live "${TMP_DIR}/metadata.next" "${TMP_DIR}/metadata.live" "${TMP_DIR}/no-baseline" >"${TMP_DIR}/result"
jq -e '.inbounds[0].users==[{name:"main",uuid:"unchanged",flow:"xtls-rprx-vision"}]' "${TMP_DIR}/result" >/dev/null
for credential in password uuid psk auth auth_str short_id mac_key api_token private_key; do
  jq -n --arg credential "${credential}" '{inbounds:[{type:"mixed",tag:"owned",($credential):"revoked"}]}' >"${TMP_DIR}/credential.next"
  jq -n --arg credential "${credential}" '{inbounds:[{type:"mixed",tag:"owned",($credential):"replacement"}]}' >"${TMP_DIR}/credential.live"
  if merge_generated_config_with_live "${TMP_DIR}/credential.next" "${TMP_DIR}/credential.live" "${TMP_DIR}/no-baseline" >"${TMP_DIR}/result" 2>/dev/null; then exit 1; fi
done
printf '{"inbounds":[],"endpoints":[{"type":"wireguard","tag":"owned","peers":[{"public_key":"revoked"}]}]}' >"${TMP_DIR}/credential.next"
printf '{"inbounds":[],"endpoints":[{"type":"wireguard","tag":"owned","peers":[]}]}' >"${TMP_DIR}/credential.live"
if merge_generated_config_with_live "${TMP_DIR}/credential.next" "${TMP_DIR}/credential.live" "${TMP_DIR}/no-baseline" >"${TMP_DIR}/result" 2>/dev/null; then exit 1; fi
printf '{"inbounds":[],"route":{"rules":[{"inbound":"owned","action":"route","outbound":"direct"}]}}' >"${TMP_DIR}/rule.base"
printf '{"inbounds":[],"route":{"rules":[{"inbound":"owned","action":"route","outbound":"manual"}]}}' >"${TMP_DIR}/rule.live"
printf '{"inbounds":[],"route":{"rules":[{"inbound":"owned","action":"route","outbound":"warp-ep"}]}}' >"${TMP_DIR}/rule.next"
chmod 600 "${TMP_DIR}/rule.base"
if merge_generated_config_with_live "${TMP_DIR}/rule.next" "${TMP_DIR}/rule.live" "${TMP_DIR}/rule.base" >"${TMP_DIR}/result" 2>/dev/null; then exit 1; fi
# Deleting an owned tag keeps unrelated manual records and rule precedence.
printf '{"inbounds":[],"outbounds":[]}' >"${TMP_DIR}/next.json"
merge_generated_config_with_live "${TMP_DIR}/next.json" "${TMP_DIR}/live.json" "${TMP_DIR}/base.json" >"${TMP_DIR}/result"
jq -e '.outbounds==[{type:"direct",tag:"manual"}]' "${TMP_DIR}/result" >/dev/null
printf 'config coexistence: legacy adoption, manual client/DNS/routes, managed edits, conflicts and deletion passed with real core checks\n'
