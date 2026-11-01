#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
cat > "${TMP_DIR}/bin/sing-box" <<'CORE'
#!/usr/bin/env bash
exec "${HY2_TEST_CORE}" "$@"
CORE
cat > "${TMP_DIR}/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "${1:-}" in
  show) printf 'active\n' ;;
  is-active) exit 0 ;;
  restart) printf 'restart\n' >> "${HY2_TEST_SERVICE_LOG}" ;;
  *) exit 64 ;;
esac
SYSTEMCTL
chmod +x "${TMP_DIR}/bin/sing-box" "${TMP_DIR}/bin/systemctl"
export HY2_TEST_CORE="${core}" HY2_TEST_SERVICE_LOG="${TMP_DIR}/service.log"
source "${TESTABLE_INSTALL}"
trap 'printf "HY2 final deletion failed at line %s\n" "${LINENO}" >&2' ERR

instance_firewall_prepare() {
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_ACME_DATA_DIR}"
store="${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
jq -n --arg directory "${SB_ACME_DATA_DIR}" '{schema_version:1,protocol:"hy2",revision:1,
  default_instance_id:"hysteria2-1",instances:[{
    id:"hysteria2-1",name:"HY2 target",tag:"hysteria2-in",listen:{address:"0.0.0.0",port:48443},
    authentication:{users:[{name:"test",password:"fixture-password"}]},
    tls:{enabled:true,server_name:"hy2.example.com",acme:{domain:["hy2.example.com"],
      data_directory:$directory,disable_http_challenge:false,disable_tls_alpn_challenge:true}},
    client_trust:"system",bandwidth:{up_mbps:null,down_mbps:null},
    obfs:{enabled:false,type:"",password:""},masquerade:"",outbound_policy:"default",dependencies:[]
  }]}' > "${store}"
save_plain_proxy_structured_marker hy2
printf 'INSTALLED_PROTOCOLS=hy2\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
render_structured_instance_inbounds hy2 "${store}" | jq -s '
  .[0] as $target | {inbounds:[$target,
    {type:"socks",tag:"manual-socks",listen:"127.0.0.1",listen_port:49080}],
    outbounds:[{type:"direct",tag:"direct"},{type:"direct",tag:"manual-direct"}],
    route:{final:"direct",rules:[{inbound:"hysteria2-in",action:"sniff"}]},
    experimental:{cache_file:{enabled:false}}}
' > "${SINGBOX_CONFIG_FILE}"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
plain_proxy_structured_state_matches_config hy2
cp "${store}" "${TMP_DIR}/store.original"
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.original"
jq '.inbounds[0].listen="::" |
  .inbounds += [(.inbounds[0] | .tag="manual-hy2" | .listen="127.0.0.1" | .listen_port=48445 | .udp_fragment=true),
    (.inbounds[0] | .tag="manual-hy2-second" | .listen="127.0.0.1" | .listen_port=48447)] |
  .route.rules += [{inbound:"manual-hy2",action:"route",outbound:"manual-direct"}]' \
  "${TMP_DIR}/config.original" > "${SINGBOX_CONFIG_FILE}"
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.drifted"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
if plain_proxy_structured_state_matches_config hy2 >/dev/null 2>&1; then
  printf 'listener drift was incorrectly treated as equivalent\n' >&2; exit 1
fi

expect_unchanged() {
  local label=$1 operation=$2 id=$3
  cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"
  cp "${store}" "${TMP_DIR}/store.before"
  if apply_plain_proxy_instance_change hy2 "${operation}" 1 "${id}" n > "${TMP_DIR}/${label}.json" 2> "${TMP_DIR}/${label}.stderr"; then
    printf '%s unexpectedly accepted\n' "${label}" >&2; exit 1
  fi
  jq -e '.ok==false and .changed==false and .transaction.status=="unchanged" and
    .transaction.phase=="prepare"' "${TMP_DIR}/${label}.json" >/dev/null
  cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.before"
  cmp "${store}" "${TMP_DIR}/store.before"
  [[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" && ! -e "${HY2_TEST_SERVICE_LOG}" ]]
}

expect_unchanged non_delete default hysteria2-1
expect_unchanged wrong_id delete missing
jq '.inbounds[0].users[0].password="changed-fixture-password"' "${TMP_DIR}/config.drifted" > "${SINGBOX_CONFIG_FILE}"
expect_unchanged credential_drift delete hysteria2-1
jq '.inbounds[0].tag="renamed-hy2"' "${TMP_DIR}/config.drifted" > "${SINGBOX_CONFIG_FILE}"
expect_unchanged missing_owned_tag delete hysteria2-1
jq '.inbounds[0].type="socks"' "${TMP_DIR}/config.drifted" > "${SINGBOX_CONFIG_FILE}"
expect_unchanged changed_owned_type delete hysteria2-1
jq '.inbounds |= map(if .tag=="manual-hy2" then .tag="hy2-in" else . end)' \
  "${TMP_DIR}/config.drifted" > "${SINGBOX_CONFIG_FILE}"
expect_unchanged reserved_default_tag delete hysteria2-1

# A surviving managed instance must never be regenerated across drift.
jq '.instances += [(.instances[0] | .id="survivor" | .tag="hy2-survivor" | .listen.port=48444)]' \
  "${TMP_DIR}/store.original" > "${store}"
jq '.inbounds += [(.inbounds[0] | .tag="hy2-survivor" | .listen="0.0.0.0" | .listen_port=48444)]' \
  "${TMP_DIR}/config.drifted" > "${SINGBOX_CONFIG_FILE}"
expect_unchanged surviving_managed_instance delete hysteria2-1
cp "${TMP_DIR}/store.original" "${store}"
cp "${TMP_DIR}/config.drifted" "${SINGBOX_CONFIG_FILE}"
printf 'certificate-cache-fixture\n' > "${SB_ACME_DATA_DIR}/retained.cache"

result=$(run_with_progress 'Hysteria2 删除实例' apply_plain_proxy_instance_change hy2 delete 1 hysteria2-1 n)
jq -e '.ok and .changed and .revision==2 and .transaction.phase=="committed"' <<< "${result}" >/dev/null
jq -e '.revision==2 and .instances==[] and .default_instance_id==""' "${store}" >/dev/null
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]
jq '.inbounds |= map(select(.tag!="hysteria2-in")) |
  .route.rules |= map(select(.inbound!="hysteria2-in"))' "${TMP_DIR}/config.drifted" | jq -cS . > "${TMP_DIR}/expected.json"
jq -cS . "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/actual.json"
cmp "${TMP_DIR}/expected.json" "${TMP_DIR}/actual.json"
[[ "$(cat "${HY2_TEST_SERVICE_LOG}")" == restart ]]
[[ "$(cat "${SB_ACME_DATA_DIR}/retained.cache")" == certificate-cache-fixture ]]
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
[[ -z "$(extract_protocols_from_index)" ]]
cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.deleted"
cp "${store}" "${TMP_DIR}/store.deleted"
[[ -z "$(list_config_protocols)" ]]
[[ -z "$(list_installed_protocols)" ]]
cmp "${store}" "${TMP_DIR}/store.deleted"
cmp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config.deleted"

# Only a trusted active store or a positive empty revision establishes the
# manual ownership boundary. Legacy/default-tag/missing/bad/orphan stores
# retain their existing fail-closed handling.
manual=$(jq -c '.inbounds[] | select(.tag=="manual-hy2")' "${SINGBOX_CONFIG_FILE}")
manual_client_inbound_is_unmanaged "${manual}"
if manual_client_inbound_is_unmanaged "$(jq '.tag="hy2-in"' <<< "${manual}")"; then exit 1; fi
mv "${store}" "${TMP_DIR}/store.hidden"
if manual_client_inbound_is_unmanaged "${manual}" >/dev/null 2>&1; then exit 1; fi
ln -s "${TMP_DIR}/store.hidden" "${store}"
if manual_client_inbound_is_unmanaged "${manual}" >/dev/null 2>&1; then exit 1; fi
rm "${store}"
printf '{"invalid":true}\n' > "${store}"
if manual_client_inbound_is_unmanaged "${manual}" >/dev/null 2>&1; then exit 1; fi
cp "${TMP_DIR}/store.original" "${store}"
if manual_client_inbound_is_unmanaged "${manual}" >/dev/null 2>&1; then exit 1; fi
cp "${TMP_DIR}/store.deleted" "${store}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\n' > "${SB_PROTOCOL_STATE_DIR}/hy2.env"
if manual_client_inbound_is_unmanaged "${manual}" >/dev/null 2>&1; then exit 1; fi
rm "${SB_PROTOCOL_STATE_DIR}/hy2.env"
jq '.revision=0' "${TMP_DIR}/store.deleted" > "${store}"
if manual_client_inbound_is_unmanaged "${manual}" >/dev/null 2>&1; then exit 1; fi
cp "${TMP_DIR}/store.deleted" "${store}"

# Creating at the retained revision must keep both manual HY2 listeners out
# of the new store and preserve their complete live records and routes.
jq '.instances[0] | .id="recreated" | .tag="hy2-recreated" |
  .listen.address="127.0.0.1" | .listen.port=48446' "${TMP_DIR}/store.original" > "${TMP_DIR}/recreated.json"
result=$(apply_plain_proxy_instance_change hy2 create 2 "${TMP_DIR}/recreated.json" n)
jq -e '.ok and .changed and .revision==3' <<< "${result}" >/dev/null
jq -e '.revision==3 and .default_instance_id=="recreated" and
  (.instances|length)==1 and .instances[0].id=="recreated"' "${store}" >/dev/null
[[ "$(list_config_protocols)" == hy2 && "$(list_installed_protocols)" == hy2 ]]
jq '.inbounds |= map(select(.tag!="hy2-recreated")) |
  .route.rules |= map(select(.inbound!="hy2-recreated"))' "${SINGBOX_CONFIG_FILE}" | jq -cS . > "${TMP_DIR}/after-recreate.json"
cmp "${TMP_DIR}/actual.json" "${TMP_DIR}/after-recreate.json"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'HY2 final deletion accepts only owned address drift and preserves all remaining live configuration\n'
