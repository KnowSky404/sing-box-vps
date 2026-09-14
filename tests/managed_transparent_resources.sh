#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

config_file="${TMP_DIR}/transparent-config.json"
jq -n '{
  inbounds:[
    {type:"tun",tag:"tun-probe",interface_name:"sbv-tun-probe",address:["172.19.0.1/30"],auto_route:true,strict_route:true},
    {type:"redirect",tag:"redirect-probe",listen:"127.0.0.1",listen_port:15081},
    {type:"tproxy",tag:"tproxy-probe",listen:"127.0.0.1",listen_port:15082,network:["tcp","udp"]}
  ],
  outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct",auto_detect_interface:true}
}' > "${config_file}"

inactive=$(managed_component_transparent_resources_json "${config_file}" inactive)
jq -e '
  .status == "not_assessed" and .reason == "service_inactive" and
  .service_active == false and
  ([.resources[] | select(.tag == "tun-probe" and .status == "not_assessed" and
    .resource_scope == "core_owned")] | length == 1) and
  ([.resources[] | select(.type == "redirect" or .type == "tproxy") |
    .resource_scope == "operator_policy_required" and .reason == "service_inactive"] | all)
' <<< "${inactive}" >/dev/null

# The probe treats the core's own default Linux values (table 2022 and rule
# priority 9000) as observed resources.  It does not need a real service for
# this contract test: the fake commands provide the same bounded JSON shape
# returned by iproute2/nftables.
cat > "${TMP_DIR}/bin/ip" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-j" && "${2:-}" == "rule" ]]; then
  printf '%s\n' '[{"priority":9000,"src":"all","table":"2022"},{"priority":120,"iif":"sbv-bridge0","table":"2200"},{"priority":121,"dst":"192.0.2.1","table":"main"}]'
elif [[ "${1:-}" == "-j" && "${2:-}" == "route" ]]; then
  printf '%s\n' '[{"dst":"default","dev":"sbv-tun-probe","table":"2022"},{"dst":"192.0.2.1","dev":"sbv-bridge0"},{"dst":"default","dev":"lo","table":"2200"}]'
elif [[ "${1:-}" == "-j" && "${2:-}" == "addr" ]]; then
  if [[ "${5:-}" == "sbv-ovpn-client" ]]; then
    printf '%s\n' '[{"ifname":"sbv-ovpn-client","addr_info":[{"family":"inet","local":"10.79.0.2","prefixlen":24}]}]'
  elif [[ "${5:-}" == "sbv-ovpn-server" ]]; then
    printf '%s\n' '[{"ifname":"sbv-ovpn-server","addr_info":[{"family":"inet","local":"10.79.0.1","prefixlen":24}]}]'
  else
    printf '%s\n' '[]'
  fi
elif [[ "${1:-}" == "-j" && "${2:-}" == "link" ]]; then
  if [[ "${5:-}" == "missing-tun" ]]; then
    printf '%s\n' '[]'
  elif [[ "${5:-}" == "missing-ovpn" ]]; then
    printf '%s\n' '[]'
  elif [[ "${5:-}" == "sbv-bridge0" ]]; then
    printf '%s\n' '[{"ifname":"sbv-bridge0","operstate":"UP"}]'
  elif [[ "${5:-}" == "sbv-ovpn-client" ]]; then
    printf '%s\n' '[{"ifname":"sbv-ovpn-client","operstate":"UP","mtu":1500}]'
  elif [[ "${5:-}" == "sbv-ovpn-server" ]]; then
    printf '%s\n' '[{"ifname":"sbv-ovpn-server","operstate":"UP","mtu":1500}]'
  else
    printf '%s\n' '[{"ifname":"sbv-tun-probe","operstate":"UP"}]'
  fi
else
  exit 1
fi
EOF
chmod 0755 "${TMP_DIR}/bin/ip"
cat > "${TMP_DIR}/bin/nft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '{"nftables":[]}'
EOF
chmod 0755 "${TMP_DIR}/bin/nft"

# sing-box treats an explicit zero as the default table/rule value.  The
# probe must normalize that representation before matching iproute2 output.
jq '.inbounds[0].iproute2_table_index = 0 |
  .inbounds[0].iproute2_rule_index = 0' "${config_file}" > "${config_file}.next"
mv -f "${config_file}.next" "${config_file}"
active=$(managed_component_transparent_resources_json "${config_file}" active)
jq -e '
  .status == "not_assessed" and .reason == "host_policy_rules_not_managed" and
  .service_active == true and
  ([.resources[] | select(.tag == "tun-probe") |
    .interface.status == "present" and .policy_routing.status == "present" and
    .rule.status == "present" and .auto_redirect_rules.status == "not_required"] | all) and
  ([.resources[] | select(.type == "redirect" or .type == "tproxy") |
    .resource_scope == "operator_policy_required" and .reason == "host_policy_rules_not_managed"] | all)
' <<< "${active}" >/dev/null

# A running service with a missing TUN interface must be a hard diagnostic
# failure; a passing core check alone is not evidence that the data plane is
# actually present.
jq '.inbounds[0].interface_name = "missing-tun"' "${config_file}" > "${config_file}.next"
mv -f "${config_file}.next" "${config_file}"
missing=$(managed_component_transparent_resources_json "${config_file}" active)
jq -e '.status == "unavailable" and .reason == "tun_runtime_resources_missing" and
  .resources[0].interface.status == "missing"' <<< "${missing}" >/dev/null

# Interface names are passed only after a strict kernel-name check; malformed
# live configuration cannot turn the read-only probe into an argument sink.
jq '.inbounds[0].interface_name = "bad name"' "${config_file}" > "${config_file}.next"
mv -f "${config_file}.next" "${config_file}"
if managed_component_transparent_resources_json "${config_file}" active >/dev/null 2>&1; then
  printf 'unsafe TUN interface name unexpectedly accepted\n' >&2
  exit 1
fi

# Bridge outbounds own a dynamically named TUN plus a pair of core-created
# iproute2 rules and a deterministic 192.0.2.x link route.  The probe resolves
# that name from the bounded route dump and verifies the explicit table/rule
# values without claiming host firewall/NAT ownership.
bridge_config_file="${TMP_DIR}/bridge-config.json"
jq -n '{inbounds:[],outbounds:[{type:"bridge",tag:"bridge-probe",interface:"lo",bridge_name:"sbv-bridge",iproute2_table_index:2200,iproute2_rule_index:120}],route:{final:"direct"}}' > "${bridge_config_file}"
bridge_active=$(managed_component_transparent_resources_json "${bridge_config_file}" active)
jq -e '
  .status == "available" and .reason == null and .service_active == true and
  ([.resources[] | select(.type == "bridge" and .tag == "bridge-probe") |
    .interface_name == "sbv-bridge0" and .bridge_port == "192.0.2.1" and
    .route_table == 2200 and .rule_priority == 120 and
    .interface.status == "present" and .policy_routing.status == "present" and
    .rule.status == "present" and .bridge_netfilter.status == "observed"] | length == 1)
' <<< "${bridge_active}" >/dev/null

jq '.outbounds[0].bridge_name = "missing-bridge"' "${bridge_config_file}" > "${bridge_config_file}.next"
mv -f "${bridge_config_file}.next" "${bridge_config_file}"
bridge_missing=$(managed_component_transparent_resources_json "${bridge_config_file}" active)
jq -e '.status == "unavailable" and .reason == "bridge_runtime_resources_missing" and
  .resources[0].interface.status == "missing"' <<< "${bridge_missing}" >/dev/null

# Named OpenVPN system endpoints are core-owned resources.  The probe observes
# the exact kernel interface, configured address/prefix, and MTU; it does not
# infer host routes or claim packet payload delivery.
openvpn_config_file="${TMP_DIR}/openvpn-system-config.json"
jq -n '{
  inbounds:[],
  endpoints:[
    {type:"openvpn-server",tag:"ovpn-server",system:true,name:"sbv-ovpn-server",address:["10.79.0.1/24"],mtu:1500},
    {type:"openvpn-client",tag:"ovpn-client",system:true,name:"sbv-ovpn-client",address:["10.79.0.2/24"],mtu:1500}
  ],
  outbounds:[],route:{final:"direct"}
}' > "${openvpn_config_file}"
openvpn_active=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '
  .status == "available" and .reason == null and .service_active == true and
  ([.resources[] | select(.system_interface == true and .tag == "ovpn-server") |
    .interface_name == "sbv-ovpn-server" and .interface.status == "present" and
    .interface_addresses.status == "present" and .mtu.status == "present" and
    .expected_addresses == ["10.79.0.1/24"] and .expected_mtu == 1500] | length == 1) and
  ([.resources[] | select(.system_interface == true and .tag == "ovpn-client") |
    .interface_name == "sbv-ovpn-client" and .interface.status == "present" and
    .interface_addresses.status == "present" and .mtu.status == "present" and
    .expected_addresses == ["10.79.0.2/24"] and .expected_mtu == 1500] | length == 1)
' <<< "${openvpn_active}" >/dev/null
managed_component_transparent_runtime_healthy "${openvpn_config_file}"

jq '.endpoints[0].name = "missing-ovpn"' "${openvpn_config_file}" > "${openvpn_config_file}.next"
mv -f "${openvpn_config_file}.next" "${openvpn_config_file}"
openvpn_missing=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '.status == "unavailable" and .reason == "openvpn_system_runtime_resources_missing" and
  ([.resources[] | select(.tag == "ovpn-server") |
    .interface_name == "missing-ovpn" and .interface.status == "missing" and
    .interface_addresses.status == "not_probed" and .mtu.status == "missing"] | length == 1)' \
  <<< "${openvpn_missing}" >/dev/null

jq '.endpoints[0].address = ["10.79.0.99/24"]' "${openvpn_config_file}" > "${openvpn_config_file}.next"
mv -f "${openvpn_config_file}.next" "${openvpn_config_file}"
openvpn_address_missing=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '.status == "unavailable" and .reason == "openvpn_system_runtime_resources_missing" and
  ([.resources[] | select(.tag == "ovpn-server") |
    .interface.status == "present" and .interface_addresses.status == "missing" and
    .mtu.status == "present"] | length == 1)' \
  <<< "${openvpn_address_missing}" >/dev/null

jq '.endpoints[0].address = ["10.79.0.1/24"] | .endpoints[0].mtu = 1400' \
  "${openvpn_config_file}" > "${openvpn_config_file}.next"
mv -f "${openvpn_config_file}.next" "${openvpn_config_file}"
openvpn_mtu_missing=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '.status == "unavailable" and .reason == "openvpn_system_runtime_resources_missing" and
  ([.resources[] | select(.tag == "ovpn-server") |
    .interface.status == "present" and .interface_addresses.status == "present" and
    .mtu.status == "missing"] | length == 1)' \
  <<< "${openvpn_mtu_missing}" >/dev/null

jq '.endpoints[0].mtu = 1500 | .endpoints[0].name = "bad name"' \
  "${openvpn_config_file}" > "${openvpn_config_file}.next"
mv -f "${openvpn_config_file}.next" "${openvpn_config_file}"
openvpn_invalid=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '.status == "not_assessed" and .reason == "openvpn_system_interface_name_invalid" and
  ([.resources[] | select(.tag == "ovpn-server") |
    .interface_name == "bad name" and .interface.status == "not_assessed" and
    .interface_addresses.status == "not_assessed" and .mtu.status == "not_assessed"] | length == 1)' \
  <<< "${openvpn_invalid}" >/dev/null

jq '.endpoints[0].name = ""' "${openvpn_config_file}" > "${openvpn_config_file}.next"
mv -f "${openvpn_config_file}.next" "${openvpn_config_file}"
openvpn_unset=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '.status == "not_assessed" and .reason == "openvpn_system_interface_name_unset" and
  ([.resources[] | select(.tag == "ovpn-server") |
    .interface_name == "" and .interface.status == "not_assessed" and
    .interface_addresses.status == "not_assessed" and .mtu.status == "not_assessed"] | length == 1)' \
  <<< "${openvpn_unset}" >/dev/null

# An unassessed endpoint must not suppress an independently named resource,
# regardless of endpoint order.  The named resource remains observable while
# the aggregate status retains the honest unset-name limitation.
jq '(.endpoints[0].name = "") | (.endpoints[1].name = "sbv-ovpn-client")' \
  "${openvpn_config_file}" > "${openvpn_config_file}.next"
mv -f "${openvpn_config_file}.next" "${openvpn_config_file}"
openvpn_mixed=$(managed_component_transparent_resources_json "${openvpn_config_file}" active)
jq -e '
  .status == "not_assessed" and .reason == "openvpn_system_interface_name_unset" and
  ([.resources[] | select(.tag == "ovpn-client") |
    .interface_name == "sbv-ovpn-client" and .interface.status == "present" and
    .interface_addresses.status == "present" and .mtu.status == "present"] | length == 1)
' <<< "${openvpn_mixed}" >/dev/null

# A failed iproute2 probe must remain a structured unavailable diagnostic; it
# must not try to read an absent route snapshot or block on stdin.
cat > "${TMP_DIR}/bin/ip" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod 0755 "${TMP_DIR}/bin/ip"
bridge_probe_failed=$(managed_component_transparent_resources_json "${bridge_config_file}" active)
jq -e '.status == "unavailable" and .reason == "iproute2_rule_probe_failed" and
  .resources[0].type == "bridge" and .resources[0].interface.status == "not_probed" and
  .resources[0].policy_routing.status == "not_probed" and .resources[0].rule.status == "not_probed"' \
  <<< "${bridge_probe_failed}" >/dev/null

# Redirect/TProxy-only diagnostics must not fail merely because iproute2 is
# unavailable: their host policy is explicitly outside installer ownership.
jq '{inbounds:[.inbounds[1]],outbounds:.outbounds,route:.route}' "${config_file}" > "${config_file}.next"
mv -f "${config_file}.next" "${config_file}"
cat > "${TMP_DIR}/bin/ip" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
chmod 0755 "${TMP_DIR}/bin/ip"
redirect_only=$(managed_component_transparent_resources_json "${config_file}" active)
jq -e '.status == "not_assessed" and .reason == "host_policy_rules_not_managed" and
  ([.resources[] | .resource_scope == "operator_policy_required" and
    .reason == "host_policy_rules_not_managed"] | all)' <<< "${redirect_only}" >/dev/null

printf '%s\n' 'managed transparent resource probes passed'
