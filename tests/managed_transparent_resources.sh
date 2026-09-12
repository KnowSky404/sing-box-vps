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
  printf '%s\n' '[{"priority":9000,"src":"all","table":"2022"}]'
elif [[ "${1:-}" == "-j" && "${2:-}" == "route" ]]; then
  printf '%s\n' '[{"dst":"default","dev":"sbv-tun-probe","table":"2022"}]'
elif [[ "${1:-}" == "-j" && "${2:-}" == "link" ]]; then
  if [[ "${5:-}" == "missing-tun" ]]; then
    printf '%s\n' '[]'
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
