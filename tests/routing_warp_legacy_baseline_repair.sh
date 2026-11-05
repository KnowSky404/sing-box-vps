#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${ROUTING_POLICY_TEST_REAL_CORE:-${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}}
[[ -x "${core}" && "$("${core}" version | head -n1)" == 'sing-box version 1.14.4' ]] || {
  printf 'Set ROUTING_POLICY_TEST_REAL_CORE to real sing-box 1.14.4\n' >&2; exit 1;
}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
fail() { printf 'legacy WARP baseline: %s\n' "$*" >&2; exit 1; }
# Provider POST and service activation are doubles. Configuration generation,
# sing-box check, journals, receipts, backups and rollback execute unchanged.
response='{"id":"new-id","token":"fixture-token","config":{"client_id":"hCaJ","interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110:8cde::1"}}}}'
run_singbox_generate_command() {
  printf '%s\n' 'PrivateKey: 8DcUSmPINFuK1xkA1TncAJh46Ra8Mq8o42XL3b+rT2s=' \
    'PublicKey: j/gT24P0qv0p5RFqYVehc7Y88S5fDhcJ8E3HGqpCPVg='
}
curl() {
  local output=''
  printf 'POST\n' >> "${TMP_DIR}/provider-calls"
  while [[ $# -gt 0 ]]; do
    case "$1" in -o) output=$2; shift 2 ;; *) shift ;; esac
  done
  printf '%s\n' "${response}" > "${output}"
  printf 200
}
systemctl() {
  printf '%s\n' "$*" >> "${TMP_DIR}/service-calls"
  case "${1:-}" in
    is-active)
      if [[ "$(cat "${TMP_DIR}/service-state")" == active ]]; then
        [[ "${2:-}" == --quiet ]] || printf 'active\n'
      else
        [[ "${2:-}" == --quiet ]] || printf 'inactive\n'; return 3
      fi ;;
    show) cat "${TMP_DIR}/service-state" ;;
    stop) printf 'inactive\n' > "${TMP_DIR}/service-state" ;;
    restart)
      if [[ -e "${TMP_DIR}/fail-once" ]]; then
        rm -- "${TMP_DIR}/fail-once"
        printf 'inactive\n' > "${TMP_DIR}/service-state"
        return 77
      fi
      printf 'active\n' > "${TMP_DIR}/service-state" ;;
    *) return 97 ;;
  esac
}
run_with_progress() { shift; "$@"; }
reset_legacy_fixture() {
  rm -rf -- "${SB_PROJECT_DIR}" "${SB_ROUTING_PREVIOUS_DIR}" "${SB_ROUTING_TRANSACTION_DIR}"
  rm -f -- "${SB_WARP_REGISTRATION_PENDING_FILE}" "${TMP_DIR}/provider-calls" "${TMP_DIR}/fail-once"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
  printf 'active\n' > "${TMP_DIR}/service-state"
  : > "${TMP_DIR}/service-calls"
  printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
  printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=Legacy\nPORT=13090\nAUTH_ENABLED=n\nUSERNAME=\nPASSWORD=\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
  SB_VERSION=1.14.4 SB_ENABLE_WARP=y SB_ADVANCED_ROUTE=n SB_WARP_ROUTE_MODE=all
  SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv4
  save_stack_mode_state
  save_warp_route_settings
  write_warp_credentials_atomic old-id fixture-old-token AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= 172.16.0.3 2606:4700:110::3 AAAA
  generate_config > "${TMP_DIR}/initial-generate.log" 2>&1
  rm -- "${SB_PROJECT_DIR}/managed-config.generated.json"
  rm -f -- "${SB_PROJECT_DIR}/managed-config.generated.json.bak"
  sed '/^WARP_CLIENT_ID=/d' "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/legacy-key"
  cp -- "${TMP_DIR}/legacy-key" "${SB_WARP_KEY_FILE}"
  chmod 600 "${SB_WARP_KEY_FILE}"
  [[ ! -e "${SB_ROUTING_POLICY_FILE}" ]]
  jq -e '.route.final=="warp-ep" and any(.endpoints[]; .tag=="warp-ep")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
}
reset_legacy_fixture
before=$(routing_state_fingerprint)
# Ordinary node generation, Block CN edits and diagnostic proxies may not repair
# invalid credentials or silently opt into the explicit migration fallback.
if generate_config > "${TMP_DIR}/node.log" 2>&1; then fail 'node generation accepted an invalid sidecar'; fi
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/provider-calls" ]]
if create_media_check_warp_proxy_config "${TMP_DIR}/media.json" 19081 > "${TMP_DIR}/media.log" 2>&1; then
  fail 'media probe accepted an invalid sidecar'
fi
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/provider-calls" ]]
routing_draft_create "${TMP_DIR}/block-draft.json"
routing_draft_edit "${TMP_DIR}/block-draft.json" '.policy.server.block_cn=true'
if routing_policy_apply "${TMP_DIR}/block-draft.json" > "${TMP_DIR}/block.log" 2>&1; then fail 'Block CN repaired WARP'; fi
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/provider-calls" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]

routing_draft_create "${TMP_DIR}/reregister.json"
routing_draft_edit "${TMP_DIR}/reregister.json" '.warp.reregister=true'
touch "${TMP_DIR}/fail-once"
if routing_policy_apply "${TMP_DIR}/reregister.json" > "${TMP_DIR}/first-repair.log" 2>&1; then fail 'restart failure unexpectedly committed'; fi
# Repair must reach the provider before the injected restart failure, then roll
# back every project byte while retaining the received provider response.
[[ -f "${TMP_DIR}/provider-calls" ]] || { cat "${TMP_DIR}/first-repair.log" >&2; fail 'explicit repair stopped before registration'; }
[[ "$(wc -l < "${TMP_DIR}/provider-calls")" == 1 && "$(routing_state_fingerprint)" == "${before}" ]]
[[ "$(cat "${TMP_DIR}/service-state")" == active && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
jq -e '.phase=="received"' "${SB_WARP_REGISTRATION_PENDING_FILE}" >/dev/null
cmp "${SB_WARP_KEY_FILE}" "${TMP_DIR}/legacy-key"
routing_policy_apply "${TMP_DIR}/reregister.json" > "${TMP_DIR}/retry-repair.log" 2>&1
[[ "$(wc -l < "${TMP_DIR}/provider-calls")" == 1 && ! -e "${SB_WARP_REGISTRATION_PENDING_FILE}" ]]
grep -Fq 'WARP_CLIENT_ID=hCaJ' "${SB_WARP_KEY_FILE}"
jq -e '.schema_version==2' "${SB_ROUTING_POLICY_FILE}" >/dev/null
jq -e '.phase=="committed" and (.warp_registration_deferred.receipt_sha256|length)==64' \
  "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# Explicitly disabling a legacy global WARP route needs the same read-only old
# projection, but does not authorize registering or replacing the stored key.
reset_legacy_fixture
routing_draft_create "${TMP_DIR}/disable.json"
routing_draft_edit "${TMP_DIR}/disable.json" '.warp.enabled=false'
routing_policy_apply "${TMP_DIR}/disable.json" > "${TMP_DIR}/disable.log" 2>&1
[[ ! -e "${TMP_DIR}/provider-calls" ]]
cmp "${SB_WARP_KEY_FILE}" "${TMP_DIR}/legacy-key"
jq -e '.route.final=="direct" and all(.endpoints[]; .tag!="warp-ep")' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
# A trusted pure baseline preserves a later manual MTU through account repair.
# Missing keys must first fail ordinary generation without laundering that MTU
# into the baseline; the explicit repair then uses the existing three-way merge.
reset_legacy_fixture
printf 'WARP_CLIENT_ID=AAAA\n' >> "${SB_WARP_KEY_FILE}"
generate_config > "${TMP_DIR}/trusted-baseline.log" 2>&1
jq '(.endpoints[] | select(.tag=="warp-ep")).mtu=1420' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual-mtu.json"
mv -- "${TMP_DIR}/manual-mtu.json" "${SINGBOX_CONFIG_FILE}"
rm -- "${SB_WARP_KEY_FILE}"
before=$(routing_state_fingerprint)
if generate_config > "${TMP_DIR}/missing-key-node.log" 2>&1; then fail 'node generation adopted a live endpoint'; fi
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/provider-calls" ]]
if create_media_check_warp_proxy_config "${TMP_DIR}/readonly-mtu.json" 19082 > "${TMP_DIR}/readonly-mtu.log" 2>&1; then
  fail 'missing credentials were reused by diagnostics'
fi
[[ ! -e "${TMP_DIR}/readonly-mtu.json" && "$(routing_state_fingerprint)" == "${before}" &&
   ! -e "${TMP_DIR}/provider-calls" ]]
routing_draft_create "${TMP_DIR}/trusted-repair.json"
routing_draft_edit "${TMP_DIR}/trusted-repair.json" '.warp.reregister=true'
routing_policy_apply "${TMP_DIR}/trusted-repair.json" > "${TMP_DIR}/trusted-repair.log" 2>&1
jq -e '.endpoints[]|select(.tag=="warp-ep")|.mtu==1420' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e '.endpoints[]|select(.tag=="warp-ep")|.mtu==1280' "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# With no trusted baseline, noncanonical valid transport settings cannot be
# adopted by shape and then erased by new canonical credentials. Refuse before
# provider contact, restoring the exact project instead.
for override in mtu listen_port; do
  reset_legacy_fixture
  jq --arg field "${override}" '(.endpoints[] | select(.tag=="warp-ep"))[$field] =
    (if $field=="mtu" then 1420 else 51821 end)' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/operator-endpoint.json"
  mv -- "${TMP_DIR}/operator-endpoint.json" "${SINGBOX_CONFIG_FILE}"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  routing_draft_create "${TMP_DIR}/noncanonical.json"
  routing_draft_edit "${TMP_DIR}/noncanonical.json" '.warp.reregister=true'
  before=$(routing_state_fingerprint)
  if routing_policy_apply "${TMP_DIR}/noncanonical.json" > "${TMP_DIR}/noncanonical-${override}.log" 2>&1; then
    fail "unproven endpoint ${override} was adopted"
  fi
  [[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/provider-calls" &&
     ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
done
# Global WARP can be off while one custom rule or one node still needs its
# endpoint. Removing that last dependency is a network edit, not registration;
# it must work with missing/legacy credentials and without an old baseline.
for dependency in custom node; do
  reset_legacy_fixture
  printf 'WARP_CLIENT_ID=AAAA\n' >> "${SB_WARP_KEY_FILE}"
  SB_ENABLE_WARP=n SB_WARP_ROUTE_MODE=selective
  save_warp_route_settings
  if [[ "${dependency}" == custom ]]; then
    jq -n '{schema_version:1,
      server:{private_network_block:false,adblock:false,warp_ai:true,warp_streaming:true,
        rules:[{id:"only-warp",kind:"domain",value:"fixture.invalid",action:"warp",enabled:true}],rule_sets:[]},
      client:{lan_direct:true,cn_direct:true,adblock:false},adblock:{url:"",domains:[],allow:[]}}' > "${SB_ROUTING_POLICY_FILE}"
  else
    policy=$(routing_policy_read_json)
    printf '%s\n' "${policy}" > "${SB_ROUTING_POLICY_FILE}"
    mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
    jq -n '{schema_version:1,protocol:"mixed",revision:1,default_instance_id:"main",instances:[
      {id:"main",name:"Legacy node",tag:"mixed-in",listen:{address:"127.0.0.1",port:13090},
       authentication:{enabled:false,username:"",password:""},outbound_policy:"warp",dependencies:[]}]}' \
      > "$(plain_proxy_structured_store_file mixed)"
    chmod 600 "$(plain_proxy_structured_store_file mixed)"
    save_plain_proxy_structured_marker mixed
  fi
  chmod 600 "${SB_ROUTING_POLICY_FILE}"
  # Prepare a fresh scoped fixture before discarding its generated baseline;
  # do not model a deleted live rule by replacing policy on an old config.
  rm -- "${SINGBOX_CONFIG_FILE}"
  rm -f -- "${SINGBOX_CONFIG_FILE}.bak"
  generate_config > "${TMP_DIR}/${dependency}-initial.log" 2>&1
  jq -e '.route.final=="direct" and any(.endpoints[]; .tag=="warp-ep")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  rm -- "${SB_PROJECT_DIR}/managed-config.generated.json"
  rm -f -- "${SB_PROJECT_DIR}/managed-config.generated.json.bak"
  if [[ "${dependency}" == custom ]]; then
    sed '/^WARP_CLIENT_ID=/d' "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/scoped-key"
    cp -- "${TMP_DIR}/scoped-key" "${SB_WARP_KEY_FILE}"
    chmod 600 "${SB_WARP_KEY_FILE}"
  else
    rm -- "${SB_WARP_KEY_FILE}"
  fi
  # Leaving the dependency unchanged cannot turn a Block CN edit into repair.
  routing_draft_create "${TMP_DIR}/${dependency}-block.json"
  routing_draft_edit "${TMP_DIR}/${dependency}-block.json" '.policy.server.block_cn=true'
  before=$(routing_state_fingerprint)
  if routing_policy_apply "${TMP_DIR}/${dependency}-block.json" > "${TMP_DIR}/${dependency}-block.log" 2>&1; then
    fail "Block CN repaired the unchanged ${dependency} WARP dependency"
  fi
  [[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/provider-calls" &&
     ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
  routing_draft_create "${TMP_DIR}/${dependency}-remove.json"
  if [[ "${dependency}" == custom ]]; then
    routing_draft_edit "${TMP_DIR}/${dependency}-remove.json" '.policy.server.rules=[]'
  else
    routing_draft_edit "${TMP_DIR}/${dependency}-remove.json" \
      '.node_overrides=[{protocol:"mixed",id:"main",policy:"default",revision:1}]'
  fi
  routing_policy_apply "${TMP_DIR}/${dependency}-remove.json" > "${TMP_DIR}/${dependency}-remove.log" 2>&1
  [[ ! -e "${TMP_DIR}/provider-calls" ]]
  jq -e '.route.final=="direct" and all(.endpoints[]; .tag!="warp-ep")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  if [[ "${dependency}" == custom ]]; then
    cmp "${SB_WARP_KEY_FILE}" "${TMP_DIR}/scoped-key"
  else
    [[ ! -e "${SB_WARP_KEY_FILE}" ]]
    jq -e '.revision==2 and .instances[0].outbound_policy=="default"' \
      "$(plain_proxy_structured_store_file mixed)" >/dev/null
  fi
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  printf 'Last %s WARP dependency removed without provider contact\n' "${dependency}"
done
printf 'Explicit legacy WARP repair/disable, strict readers and single-receipt retry passed\n'
