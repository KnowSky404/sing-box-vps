#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]' SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]' SB_WARP_REMOTE_RULE_SETS_JSON='[]' SB_WARP_RULE_SET_TAGS_JSON='[]'
}
setup_service() { :; }
open_committed_protocol_ports() { :; }
refresh_vless_reality_qos_rules() { :; }
display_status_summary() { :; }
systemctl() {
  case "${1:-}" in
    is-active)
      [[ "${2:-}" == --quiet ]] || printf 'active\n'
      ;;
    show) printf 'active\n' ;;
    *) : ;;
  esac
}
[[ "${SINGBOX_SERVICE_FILE}" == "${TMP_DIR}/sing-box.service" ]]
printf '[Service]\nExecStart=/fixture/sing-box\n' > "${SINGBOX_SERVICE_FILE}"
test_warp_key=$(openssl rand -base64 32)
register_warp() {
  printf 'WARP_PRIV_KEY=%s\nWARP_V4=172.16.0.2\nWARP_V6=2606:4700:110:8cde::2\nWARP_CLIENT_ID=hCaJ\n' \
    "${test_warp_key}" > "${SB_WARP_KEY_FILE}"
  chmod 600 "${SB_WARP_KEY_FILE}"
}
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
set_protocol_defaults mixed
SB_PORT=18080 SB_MIXED_AUTH_ENABLED=n SB_ADVANCED_ROUTE=n SB_ENABLE_WARP=n
SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv6 SB_WARP_ROUTE_MODE=all
save_stack_mode_state
save_warp_route_settings
save_mixed_state
write_protocol_index mixed
generate_config >"${TMP_DIR}/initial.log"
jq 'del(.dns.strategy,.route.final) | .outbounds += [{type:"direct",tag:"manual-direct",bind_interface:"lo"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual.json"
cp "${TMP_DIR}/manual.json" "${SINGBOX_CONFIG_FILE}"
rm "${SB_PROJECT_DIR}/managed-config.generated.json"
SB_OUTBOUND_STACK_MODE=ipv4_only
apply_stack_mode_changes >"${TMP_DIR}/stack.log" 2>&1
jq -e '.dns.strategy=="ipv4_only" and
  any(.outbounds[]; .tag=="direct" and .domain_resolver.strategy=="ipv4_only")' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
rm "${SB_PROJECT_DIR}/managed-config.generated.json"
routing_draft_create "${TMP_DIR}/enable-draft.json"
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-enable.json"
routing_default_outbound_menu "${TMP_DIR}/enable-draft.json" >"${TMP_DIR}/enable-draft.log" 2>&1 <<'INPUT'
3
0
INPUT
jq -e '.warp.enabled==true and .warp.mode=="all"' "${TMP_DIR}/enable-draft.json" >/dev/null
if cmp -s "${TMP_DIR}/before-enable.json" "${SINGBOX_CONFIG_FILE}"; then
  printf 'WARP menu change did not immediately publish configuration\n' >&2
  exit 1
fi
jq -e '.route.final=="warp-ep" and any(.endpoints[]; .tag=="warp-ep") and
  any(.outbounds[]; .tag=="manual-direct" and .bind_interface=="lo")' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
rm "${SB_PROJECT_DIR}/managed-config.generated.json"
routing_draft_create "${TMP_DIR}/disable-draft.json"
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/before-disable.json"
routing_default_outbound_menu "${TMP_DIR}/disable-draft.json" >"${TMP_DIR}/disable-draft.log" 2>&1 <<'INPUT'
1
0
INPUT
jq -e '.warp.enabled==false' "${TMP_DIR}/disable-draft.json" >/dev/null
if cmp -s "${TMP_DIR}/before-disable.json" "${SINGBOX_CONFIG_FILE}"; then
  printf 'native-outbound menu change did not immediately publish configuration\n' >&2
  exit 1
fi
jq -e '.route.final=="direct" and all(.endpoints[]?; .tag!="warp-ep") and
  any(.outbounds[]; .tag=="manual-direct" and .bind_interface=="lo")' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'Legacy global settings: stack and immediate routing menu changes preserve manual records and pass real core checks\n'
