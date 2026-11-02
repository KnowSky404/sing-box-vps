#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
[[ -x "${core}" ]]
[[ "$("${core}" version | head -n 1)" == 'sing-box version 1.14.2' ]]
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
trap 'printf "component generation inventory context failed at line %s\n" "${LINENO}" >&2' ERR

# An inactive service keeps this a configuration/transaction test. No provider,
# firewall or service mutation is needed to update an inline rule-set body.
systemctl() { printf 'unexpected systemctl mutation\n' >&2; return 91; }
register_warp() { printf 'unexpected WARP registration\n' >&2; return 91; }
ensure_warp_routing_assets() { printf 'unexpected WARP asset initialization\n' >&2; return 91; }
instance_firewall_prepare() { printf 'unexpected firewall mutation\n' >&2; return 91; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
REALITY_PUBLIC_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
STATE
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'STATE'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=context-regression
PORT=18443
UUID=11111111-1111-1111-1111-111111111111
SNI=www.example.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
OUTBOUND_POLICY=warp
STATE
chmod 600 "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
printf 'WARP_PRIV_KEY=%s\nWARP_V4=172.16.0.2\nWARP_V6=2606:4700:110:8cde::2\nWARP_CLIENT_ID=AAAA\n' \
  'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' > "${SB_WARP_KEY_FILE}"
chmod 600 "${SB_WARP_KEY_FILE}"
SB_ENABLE_WARP=n SB_ADVANCED_ROUTE=n SB_INBOUND_STACK_MODE=ipv4_only SB_OUTBOUND_STACK_MODE=prefer_ipv4
save_stack_mode_state
write_protocol_index vless-reality
generate_config > "${TMP_DIR}/initial.log" 2>&1
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
instance_outbound_requires_warp
jq -cS '{inbounds,endpoints,rules:.route.rules}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/node.before"
sha256sum "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" \
  "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/state.before"
stat -c '%n %a %d:%i %y %z' "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/key.before"

# The transaction publishes new component state before rendering, while the
# live config still contains the previous component inventory. All nested live
# readers must use the same old inventory snapshot as the outer generator.
jq -n '{id:"inline-context",role:"rule_set",type:"inline",tag:"inline-context",enabled:true,
  route_rules:[],config:{rules:[{domain_suffix:["initial.example.test"]}]}}' > "${TMP_DIR}/component.json"
for operation in create replace; do
  if [[ "${operation}" == create ]]; then
    expected_revision=0
  else
    expected_revision=1
    jq '.config.rules[0].domain_suffix=["replacement.example.test"]' "${TMP_DIR}/component.json" \
      > "${TMP_DIR}/replacement.json"
    mv -- "${TMP_DIR}/replacement.json" "${TMP_DIR}/component.json"
  fi
  if ! managed_component_state_apply "${operation}" "${expected_revision}" "${TMP_DIR}/component.json" '' n \
    > "${TMP_DIR}/${operation}.stdout" 2> "${TMP_DIR}/${operation}.stderr"; then
    cat "${TMP_DIR}/${operation}.stderr" >&2
    printf 'component %s failed: %s\n' "${operation}" "${MANAGED_COMPONENT_LAST_ERROR}" >&2
    exit 1
  fi
  jq -e --arg operation "${operation}" --argjson revision "$((expected_revision + 1))" \
    '.operation == $operation and .revision == $revision and (.service_restarted | not)' \
    <<< "${MANAGED_COMPONENT_LAST_RESULT}" >/dev/null
  ! grep -q 'live_component_inventory' "${TMP_DIR}/${operation}.stderr"
  jq -e 'any(.endpoints[]; .tag == "warp-ep") and
    any(.route.rules[]; .inbound == "vless-in" and .action == "route" and .outbound == "warp-ep")' \
    "${SINGBOX_CONFIG_FILE}" >/dev/null
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  jq -cS '{inbounds,endpoints,rules:.route.rules}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/node.after"
  cmp "${TMP_DIR}/node.before" "${TMP_DIR}/node.after"
done
jq -e '.revision == 2 and .components[0].config.rules ==
  [{domain_suffix:["replacement.example.test"]}]' "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e '.route.rule_set == [{type:"inline",tag:"inline-context",
  rules:[{domain_suffix:["replacement.example.test"]}]}]' "${SINGBOX_CONFIG_FILE}" >/dev/null
sha256sum "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" \
  "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/state.after"
cmp "${TMP_DIR}/state.before" "${TMP_DIR}/state.after"
stat -c '%n %a %d:%i %y %z' "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/key.after"
cmp "${TMP_DIR}/key.before" "${TMP_DIR}/key.after"
[[ ! -e "${SB_ROUTING_POLICY_FILE}" && ! -e "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]

# The old-inventory context must not excuse real live/state drift. A manual
# change to the owned body still refuses the transaction without rewriting it.
jq '.route.rule_set[0].rules[0].domain_suffix=["operator.example.test"]' "${SINGBOX_CONFIG_FILE}" \
  > "${TMP_DIR}/operator.json"
mv -- "${TMP_DIR}/operator.json" "${SINGBOX_CONFIG_FILE}"
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_COMPONENT_STATE_FILE}" \
  "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/drift.before"
if managed_component_state_apply replace 2 "${TMP_DIR}/component.json" '' n \
  > "${TMP_DIR}/drift.stdout" 2> "${TMP_DIR}/drift.stderr"; then
  printf 'operator rule-set drift unexpectedly accepted\n' >&2
  exit 1
fi
sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_COMPONENT_STATE_FILE}" \
  "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_WARP_KEY_FILE}" > "${TMP_DIR}/drift.after"
cmp "${TMP_DIR}/drift.before" "${TMP_DIR}/drift.after"
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]
printf 'Component inline create/body replacement retains REALITY per-node WARP with global WARP off; live drift remains refused (sing-box 1.14.2)\n'
