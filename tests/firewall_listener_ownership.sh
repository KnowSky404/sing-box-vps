#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\n' > "$(protocol_state_file mixed)"
managed_component_state_default_json | jq '.components=[{id:"owned-direct",role:"inbound",type:"direct",
  tag:"owned-direct",enabled:true,config:{listen:"192.0.2.10",listen_port:30007},route_rules:[]}]' > "${SB_COMPONENT_STATE_FILE}"
chmod 600 "${SB_COMPONENT_STATE_FILE}"
jq -n '{inbounds:[
  {type:"mixed",tag:"mixed-in",listen:"192.0.2.10",listen_port:30001},
  {type:"mixed",tag:"manual-mixed",listen:"192.0.2.20",listen_port:30001},
  {type:"socks",tag:"manual-socks",listen:"0.0.0.0",listen_port:30003},
  {type:"http",tag:"manual-http",listen:"0.0.0.0",listen_port:30004},
  {type:"direct",tag:"manual-direct",listen:"0.0.0.0",listen_port:30005},
  {type:"direct",tag:"owned-direct",listen:"192.0.2.10",listen_port:30007},
  {type:"mixed",tag:"new-mixed",listen:"0.0.0.0",listen_port:30008}],
  endpoints:[{type:"wireguard",tag:"manual-endpoint",listen_port:30006}],
  services:[{type:"resolved",tag:"manual-resolved",listen:"0.0.0.0",listen_port:30009}]}' > "${SINGBOX_CONFIG_FILE}"
all_plan=$(managed_listener_plan "${SINGBOX_CONFIG_FILE}")
plan=$(instance_firewall_plan_file "${SINGBOX_CONFIG_FILE}")
jq -e 'map(.owner)|unique==["mixed-in","owned-direct"]' <<< "${plan}" >/dev/null
jq -e 'any(.[]; .owner=="manual-mixed") and any(.[]; .owner=="manual-socks")' <<< "${all_plan}" >/dev/null
plan=$(instance_firewall_plan_file "${SINGBOX_CONFIG_FILE}" '["new-mixed"]')
jq -e 'map(.owner)|unique==["mixed-in","new-mixed","owned-direct"]' <<< "${plan}" >/dev/null
# A typed store gives per-tag ownership, including another Mixed client.
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "$(protocol_state_file mixed)"
printf '{"instances":[{"tag":"typed-mixed"}]}' > "$(mixed_structured_store_file)"
jq '.inbounds += [{type:"mixed",tag:"typed-mixed",listen:"0.0.0.0",listen_port:30010}]' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/typed.json"
cp "${TMP_DIR}/typed.json" "${SINGBOX_CONFIG_FILE}"
plan=$(instance_firewall_plan_file "${SINGBOX_CONFIG_FILE}")
jq -e 'map(.owner)|unique==["owned-direct","typed-mixed"]' <<< "${plan}" >/dev/null
# Custom default REALITY IDs and ShadowTLS companion tags are owned too;
# discovering them in a subshell must not alter the caller's active state.
printf 'INSTALLED_PROTOCOLS=mixed,vless-reality,shadowtls\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\nDEFAULT_INSTANCE_ID=custom\nINSTANCE_IDS=custom,second\n' > "$(protocol_state_file vless-reality)"
mkdir -p "$(vless_reality_instance_dir)"
printf 'INSTANCE_ID=custom\n' > "$(vless_reality_instance_state_file custom)"
printf 'INSTANCE_ID=second\nINBOUND_TAG=custom-second\n' > "$(vless_reality_instance_state_file second)"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "$(protocol_state_file shadowtls)"
printf '{"instances":[{"tag":"shadowtls-in","detour":{"tag":"shadowtls-inner"}}]}' > "$(plain_proxy_structured_store_file shadowtls)"
VLESS_REALITY_DEFAULT_INSTANCE_ID=stale
owners=$(managed_firewall_owner_tags_json)
jq -e '.==["custom-second","owned-direct","shadowtls-in","shadowtls-inner","typed-mixed","vless-in"]' <<< "${owners}" >/dev/null
[[ "${VLESS_REALITY_DEFAULT_INSTANCE_ID}" == stale ]]
printf 'INSTALLED_PROTOCOLS=mixed\n' > "${SB_PROTOCOL_INDEX_FILE}"
# The legacy apply path must use scoped reconciliation, never a broad allow
# for a port also used by a manual listener on another local address.
open_firewall_port() { printf 'unexpected broad allow\n' >> "${TMP_DIR}/broad"; }
instance_firewall_prepare() { instance_firewall_journal_path_valid "$3" || return 1; instance_firewall_plan_file "$2" > "${TMP_DIR}/prepared"; printf '{}\n' > "$3"; }
instance_firewall_apply() { return "${APPLY_STATUS:-0}"; }
instance_firewall_commit() { printf committed > "${TMP_DIR}/committed"; }
instance_firewall_rollback() { printf rollback > "${TMP_DIR}/rollback"; }
open_all_protocol_ports >"${TMP_DIR}/apply.out" 2>"${TMP_DIR}/apply.err"
[[ ! -e "${TMP_DIR}/broad" && -e "${TMP_DIR}/committed" ]]
jq -e 'map(.owner)|unique==["owned-direct","typed-mixed"]' "${TMP_DIR}/prepared" >/dev/null
APPLY_STATUS=23
if open_scoped_protocol_ports >"${TMP_DIR}/failure.out" 2>"${TMP_DIR}/failure.err"; then exit 1; else [[ $? == 23 ]]; fi
[[ -e "${TMP_DIR}/rollback" ]]
if compgen -G "${SB_PROJECT_DIR}.firewall-reconcile.*" > "${TMP_DIR}/remaining-journals"; then exit 1; fi
rm "${TMP_DIR}/rollback"
instance_firewall_apply() {
  printf '%s\n' "${BASHPID}" > "${TMP_DIR}/ready"
  while :; do sleep 0.05; done
}
open_scoped_protocol_ports >"${TMP_DIR}/signal.out" 2>"${TMP_DIR}/signal.err" &
scope_pid=$!
for ((attempt=0; attempt<100; attempt++)); do [[ ! -f "${TMP_DIR}/ready" ]] || break; sleep 0.05; done
[[ -f "${TMP_DIR}/ready" ]]
kill -TERM "$(cat "${TMP_DIR}/ready")"
if wait "${scope_pid}"; then exit 1; else [[ $? == 143 ]]; fi
[[ -e "${TMP_DIR}/rollback" && -d "${TMP_DIR}" ]]
if compgen -G "${SB_PROJECT_DIR}.firewall-reconcile.*" > "${TMP_DIR}/remaining-journals"; then exit 1; fi
printf 'Firewall ownership: manual clients/components excluded, candidate tags included, scoped apply and rollback passed\n'
