#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
[[ -x "${core}" ]] || { printf 'real sing-box core required\n' >&2; exit 1; }
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
trap 'printf "node/network isolation failed at line %s\n" "${LINENO}" >&2' ERR

get_os_info() { :; }
get_arch() { :; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
prompt_singbox_version() { SB_VERSION=1.14.2; }
prompt_protocol_install_selection() { SELECTED_PROTOCOLS_CSV=mixed; }
prompt_protocol_install_fields() {
  set_protocol_defaults mixed
  SB_PORT=18080 SB_MIXED_AUTH_ENABLED=n
}
prompt_global_instance_options() { printf 'unexpected network prompt\n' >&2; return 91; }
setup_service() { printf '[Service]\nExecStart=/fixture/sing-box\n' > "${SINGBOX_SERVICE_FILE}"; }
open_committed_protocol_ports() { :; }
systemctl() {
  case "${1:-}" in
    show) printf 'active\n' ;;
    is-active|restart) return 0 ;;
    *) return 91 ;;
  esac
}
register_warp() { printf 'called\n' >> "${TMP_DIR}/unexpected-register"; return 91; }
ensure_warp_routing_assets() { printf 'called\n' >> "${TMP_DIR}/unexpected-assets"; return 91; }
instance_firewall_prepare() {
  printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

# Exercise the actual fresh installation orchestration and configuration writer.
install_protocols_interactive fresh > "${TMP_DIR}/fresh.log" 2>&1 </dev/null
for path in "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_ROUTE_SETTINGS_FILE}" \
  "${SB_WARP_KEY_FILE}" "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}" \
  "${SB_WARP_LOCAL_RULESET_DIR}"; do
  [[ ! -e "${path}" && ! -L "${path}" ]]
done
! grep -Eq '分流|WARP|私网|网络设置' "${TMP_DIR}/fresh.log"
jq -e '.route.final == "direct" and (.endpoints | length) == 0 and
  all(.route.rules[]; (.ip_is_private // false) == false and .action != "reject")' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# Prepare an existing, valid server network configuration independently of nodes.
mkdir -p "${SB_WARP_LOCAL_RULESET_DIR}"
printf '# retained domain list\n=warp.fixture.invalid\n' > "${SB_WARP_DOMAINS_FILE}"
printf '# retained sources\n' > "${SB_WARP_REMOTE_RULESETS_FILE}"
printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=y\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
printf 'WARP_PRIV_KEY=%s\nWARP_V4=172.16.0.2\nWARP_V6=2606:4700:110:8cde::2\nWARP_CLIENT_ID=AAAA\n' \
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' > "${SB_WARP_KEY_FILE}"
policy=$(routing_policy_read_json | jq -c '.server.rules=[
  {id:"retained",kind:"domain",value:"deny.fixture.invalid",action:"reject",enabled:true}]')
printf '%s\n' "${policy}" > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_KEY_FILE}" "${SB_WARP_ROUTE_SETTINGS_FILE}" \
  "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}"
SB_ENABLE_WARP=y
generate_config > "${TMP_DIR}/existing.log" 2>&1
jq -c '.endpoints[] | select(.tag == "warp-ep")' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/endpoint.before"

network_fingerprint() {
  sha256sum "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_KEY_FILE}" "${SB_WARP_ROUTE_SETTINGS_FILE}" \
    "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}"
  # Equal bytes are insufficient: rewriting the same env or replacing a key
  # still crosses the node operation's ownership boundary.
  stat -c '%n %a %d:%i %y %z' "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_KEY_FILE}" \
    "${SB_WARP_ROUTE_SETTINGS_FILE}" "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}" \
    "${SB_WARP_LOCAL_RULESET_DIR}"
}
network_fingerprint > "${TMP_DIR}/network.before"

# The lifecycle must retain unrelated manual context while extending rule scope
# to the new managed listener. Existing node overrides remain independent.
jq '.inbounds += [{type:"mixed",tag:"operator-mixed",listen:"127.0.0.1",listen_port:18082}] |
  .route.rules = [{inbound:"operator-mixed",action:"route",outbound:"direct"}] + .route.rules' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual.json"
mv "${TMP_DIR}/manual.json" "${SINGBOX_CONFIG_FILE}"
jq -n '{id:"added",name:"Added Mixed",tag:"mixed-added",listen:{address:"127.0.0.1",port:18081},
  authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}' \
  > "${TMP_DIR}/record.json"
apply_plain_proxy_instance_change mixed create 0 "${TMP_DIR}/record.json" n > "${TMP_DIR}/create.json"
jq -e '.ok and .revision == 1' "${TMP_DIR}/create.json" >/dev/null
network_fingerprint > "${TMP_DIR}/network.after-create"
cmp "${TMP_DIR}/network.before" "${TMP_DIR}/network.after-create"
jq -e 'any(.route.rules[]; .domain == ["deny.fixture.invalid"] and
    (.inbound | index("mixed-added")) != null) and
  .route.rules[0] == {inbound:"operator-mixed",action:"route",outbound:"direct"}' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null

jq '.name="Renamed Mixed" | .listen.port=18083' "${TMP_DIR}/record.json" > "${TMP_DIR}/replacement.json"
apply_plain_proxy_instance_change mixed replace 1 "${TMP_DIR}/replacement.json" n > "${TMP_DIR}/replace.json"
jq -e '.ok and .revision == 2' "${TMP_DIR}/replace.json" >/dev/null
network_fingerprint > "${TMP_DIR}/network.after-replace"
cmp "${TMP_DIR}/network.before" "${TMP_DIR}/network.after-replace"
jq -c '.endpoints[] | select(.tag == "warp-ep")' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/endpoint.after"
cmp "${TMP_DIR}/endpoint.before" "${TMP_DIR}/endpoint.after"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"

# Diagnostics use existing credentials and check their private temporary config.
create_media_check_warp_proxy_config "${TMP_DIR}/media.json" 19080
network_fingerprint > "${TMP_DIR}/network.after-media"
cmp "${TMP_DIR}/network.before" "${TMP_DIR}/network.after-media"

# Missing separate credentials can retain the exact working live endpoint;
# invalid material must fail without account repair or config publication.
mv "${SB_WARP_KEY_FILE}" "${TMP_DIR}/saved-warp.key"
generate_config > "${TMP_DIR}/missing-key.log" 2>&1
[[ ! -e "${SB_WARP_KEY_FILE}" ]]
jq -c '.endpoints[] | select(.tag == "warp-ep")' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/endpoint.reused"
cmp "${TMP_DIR}/endpoint.before" "${TMP_DIR}/endpoint.reused"
printf 'WARP_PRIV_KEY=invalid\n' > "${SB_WARP_KEY_FILE}"
before=$(sha256sum "${SINGBOX_CONFIG_FILE}")
if generate_config > "${TMP_DIR}/invalid-key.log" 2>&1; then
  printf 'invalid WARP credentials unexpectedly accepted\n' >&2; exit 1
fi
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before}" ]]
[[ ! -e "${TMP_DIR}/unexpected-register" && ! -e "${TMP_DIR}/unexpected-assets" ]]
printf 'Node installation, create/replace and diagnostics preserve network state; real core checks passed\n'
