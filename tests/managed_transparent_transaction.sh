#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 128

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_CORE'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf '%s\n' 'sing-box version 1.14.0' ;;
  check) exit 0 ;;
  *) exit 64 ;;
esac
EOF_CORE
chmod 0755 "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
state_file=${SBV_TRANSPARENT_SYSTEMCTL_STATE:?missing state file}
count_file=${SBV_TRANSPARENT_SYSTEMCTL_COUNT:?missing count file}
case "${1:-}:${2:-}:${3:-}" in
  is-active:--quiet:sing-box)
    [[ "$(<"${state_file}")" == active ]]
    ;;
  is-active:sing-box:)
    cat "${state_file}"
    [[ "$(<"${state_file}")" == active ]]
    ;;
  restart:sing-box:)
    count=$(<"${count_file}")
    printf '%s\n' "$((count + 1))" > "${count_file}"
    printf '%s\n' active > "${state_file}"
    ;;
  stop:sing-box:)
    printf '%s\n' inactive > "${state_file}"
    ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod 0755 "${TMP_DIR}/bin/systemctl"

cat > "${TMP_DIR}/bin/ip" <<'EOF_IP'
#!/usr/bin/env bash
set -euo pipefail
link_probe_count_file=${SBV_TRANSPARENT_LINK_PROBE_COUNT:?missing link probe count file}
case "${1:-}:${2:-}" in
  -j:rule)
    printf '%s\n' '[{"priority":9000,"table":"2022"}]'
    ;;
  -j:route)
    printf '%s\n' '[{"dst":"default","dev":"sbv-health","table":"2022"}]'
    ;;
  -j:link)
    if [[ "${SBV_TRANSPARENT_HEALTH_MODE:-missing}" == eventual ]]; then
      count=$(<"${link_probe_count_file}")
      printf '%s\n' "$((count + 1))" > "${link_probe_count_file}"
      if (( count < 2 )); then
        printf '%s\n' '[]'
      else
        printf '%s\n' '[{"ifname":"sbv-health","operstate":"UP"}]'
      fi
    elif [[ "${SBV_TRANSPARENT_HEALTH_MODE:-missing}" == present ]]; then
      printf '%s\n' '[{"ifname":"sbv-health","operstate":"UP"}]'
    else
      printf '%s\n' '[]'
    fi
    ;;
  *) exit 64 ;;
esac
EOF_IP
chmod 0755 "${TMP_DIR}/bin/ip"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
export SBV_TRANSPARENT_SYSTEMCTL_STATE="${TMP_DIR}/systemctl.state"
export SBV_TRANSPARENT_SYSTEMCTL_COUNT="${TMP_DIR}/systemctl.count"
export SBV_TRANSPARENT_LINK_PROBE_COUNT="${TMP_DIR}/link-probe.count"
printf '%s\n' active > "${SBV_TRANSPARENT_SYSTEMCTL_STATE}"
printf '%s\n' 0 > "${SBV_TRANSPARENT_SYSTEMCTL_COUNT}"
printf '%s\n' 0 > "${SBV_TRANSPARENT_LINK_PROBE_COUNT}"
printf '%s\n' '[Unit]' > "${SINGBOX_SERVICE_FILE}"

managed_component_write_state "$(managed_component_state_default_json)"

generate_config() {
  local rendered
  rendered=$(managed_component_render_json) || return 1
  jq -n --argjson inbounds "$(jq -c '.inbounds' <<< "${rendered}")" \
    --argjson endpoints "$(jq -c '.endpoints' <<< "${rendered}")" \
    --argjson outbounds "$(jq -c '.outbounds' <<< "${rendered}")" \
    --argjson route_rules "$(jq -c '.route_rules' <<< "${rendered}")" \
    '{inbounds:$inbounds,endpoints:$endpoints,
      outbounds:([{type:"direct",tag:"direct"},{type:"block",tag:"block"}] + $outbounds),
      route:{final:"direct",rules:$route_rules}}' > "${SINGBOX_CONFIG_FILE}"
}
generate_config

instance_firewall_prepare() {
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "${3}"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }
instance_firewall_commit() { :; }
instance_transaction_firewall_summary() {
  jq -cn '{status:"not_attempted",backends:[],diagnostics:[]}'
}

tun_record="${TMP_DIR}/tun.json"
jq -n '{id:"tun-health",role:"inbound",type:"tun",tag:"tun-health",enabled:true,
  route_rules:[],config:{interface_name:"sbv-health",address:["172.19.0.1/30"],
  auto_route:true,strict_route:true}}' > "${tun_record}"

before_state=$(cat "${SB_COMPONENT_STATE_FILE}")
before_config=$(cat "${SINGBOX_CONFIG_FILE}")
export SBV_TRANSPARENT_HEALTH_MODE=missing
if failed=$(agent_cli component create --json --yes --allow-public --expected-revision 0 \
  --file "${tun_record}"); then
  printf 'TUN transaction unexpectedly succeeded with missing core-owned resources\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "transparent_resource_check_failed" and
  .data.ok == false and .data.error == "transparent_resource_check_failed"' <<< "${failed}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${before_state}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${before_config}" ]]
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]
[[ "$(<"${SBV_TRANSPARENT_SYSTEMCTL_COUNT}")" == 2 ]]

export SBV_TRANSPARENT_HEALTH_MODE=eventual
succeeded=$(agent_cli component create --json --yes --allow-public --expected-revision 0 \
  --file "${tun_record}")
jq -e '.ok == true and .data.operation == "create" and
  .data.revision == 1 and .data.service_restarted == true' <<< "${succeeded}" >/dev/null
jq -e '.revision == 1 and any(.components[]; .id == "tun-health")' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.inbounds[]; .type == "tun" and .interface_name == "sbv-health" and
  .auto_route == true)' "${SINGBOX_CONFIG_FILE}" >/dev/null
[[ "$(<"${SBV_TRANSPARENT_SYSTEMCTL_COUNT}")" == 3 ]]
[[ "$(<"${SBV_TRANSPARENT_LINK_PROBE_COUNT}")" -ge 3 ]]

printf '%s\n' 'managed transparent transaction checks passed'
