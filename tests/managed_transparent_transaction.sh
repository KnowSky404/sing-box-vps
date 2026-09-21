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
    case "${SBV_TRANSPARENT_HEALTH_MODE:-missing}" in
      eventual)
      count=$(<"${link_probe_count_file}")
      printf '%s\n' "$((count + 1))" > "${link_probe_count_file}"
      if (( count < 2 )); then
        printf '%s\n' '[]'
      else
        printf '%s\n' '[{"ifname":"sbv-health","operstate":"UP"}]'
      fi
      ;;
      present)
      printf '%s\n' '[{"ifname":"sbv-health","operstate":"UP"}]'
      ;;
      system-present)
      printf '%s\n' '[{"ifname":"sbv-oc","operstate":"UP"}]'
      ;;
      *)
      printf '%s\n' '[]'
      ;;
    esac
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
export SBV_TRANSPARENT_FIREWALL_ROLLBACKS="${TMP_DIR}/firewall-rollbacks.txt"
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
instance_firewall_rollback() {
  printf '%s\n' "${1:-missing}" >> "${SBV_TRANSPARENT_FIREWALL_ROLLBACKS}"
}
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

# Named system endpoints must use the same post-restart resource gate as TUN
# and OpenVPN.  Exercise both the fail-closed rollback and the successful
# commit path with an OpenConnect interface whose address/MTU are core-chosen.
delete_tun=$(agent_cli component delete --json --yes --expected-revision 1 \
  --id tun-health)
jq -e '.ok == true and .data.operation == "delete" and .data.revision == 2 and
  .data.service_restarted == true' <<< "${delete_tun}" >/dev/null
jq -e '.revision == 2 and ([.components[] | select(.id == "tun-health")] | length == 0)' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null

openconnect_record="${TMP_DIR}/openconnect-system.json"
jq -n '{id:"openconnect-system-health",role:"endpoint",type:"openconnect",
  tag:"oc-system-health",enabled:true,route_rules:[],config:
  {server:"vpn.example.com",system:true,name:"sbv-oc"}}' > "${openconnect_record}"
before_state=$(cat "${SB_COMPONENT_STATE_FILE}")
before_config=$(cat "${SINGBOX_CONFIG_FILE}")
export SBV_TRANSPARENT_HEALTH_MODE=system-missing
if failed=$(agent_cli component create --json --yes --expected-revision 2 \
  --file "${openconnect_record}"); then
  printf 'system endpoint transaction unexpectedly succeeded with missing core-owned resources\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "transparent_resource_check_failed" and
  .data.ok == false and .data.error == "transparent_resource_check_failed"' <<< "${failed}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${before_state}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${before_config}" ]]
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]

export SBV_TRANSPARENT_HEALTH_MODE=system-present
succeeded=$(agent_cli component create --json --yes --expected-revision 2 \
  --file "${openconnect_record}")
jq -e '.ok == true and .data.operation == "create" and
  .data.revision == 3 and .data.service_restarted == true' <<< "${succeeded}" >/dev/null
jq -e '.revision == 3 and any(.components[]; .id == "openconnect-system-health")' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.endpoints[]; .type == "openconnect" and .system == true and
  .name == "sbv-oc")' "${SINGBOX_CONFIG_FILE}" >/dev/null

# Keep the injected Redirect failure independent of the system-endpoint
# readiness fixture above; the Redirect transaction only needs an active
# service and a disposable ingress interface.
delete_openconnect=$(agent_cli component delete --json --yes --expected-revision 3 \
  --id openconnect-system-health)
jq -e '.ok == true and .data.operation == "delete" and .data.revision == 4' \
  <<< "${delete_openconnect}" >/dev/null

# A Redirect policy failure after listener-firewall application must roll back
# both externally managed resources, then restore the old config and service.
REDIRECT_TEST_CHAIN=''
REDIRECT_TEST_RULE=false
REDIRECT_TEST_JUMP_RULE=''
REDIRECT_TEST_FAIL_JUMP=true
iptables() {
  [[ "${1:-}" == -t && "${2:-}" == nat ]] || return 2
  shift 2
  local operation=${1:-} target
  shift || true
  case "${operation}" in
    -S)
      target=${1:-}
      if [[ -z "${target}" ]]; then
        [[ -n "${REDIRECT_TEST_CHAIN}" ]] && printf -- '-N %s\n' "${REDIRECT_TEST_CHAIN}"
        if [[ "${REDIRECT_TEST_RULE}" == true ]]; then
          printf -- '-A %s -i sbv-rph0 -p tcp -m multiport --dports 18081 -j REDIRECT --to-ports 19094\n' \
            "${REDIRECT_TEST_CHAIN}"
        fi
        [[ -n "${REDIRECT_TEST_JUMP_RULE}" ]] && printf -- '-A %s\n' "${REDIRECT_TEST_JUMP_RULE}"
      elif [[ "${target}" == PREROUTING ]]; then
        printf -- '-N PREROUTING\n'
        [[ -n "${REDIRECT_TEST_JUMP_RULE}" ]] && printf -- '-A %s\n' "${REDIRECT_TEST_JUMP_RULE}"
      elif [[ "${target}" == "${REDIRECT_TEST_CHAIN}" && -n "${REDIRECT_TEST_CHAIN}" ]]; then
        printf -- '-N %s\n' "${REDIRECT_TEST_CHAIN}"
        if [[ "${REDIRECT_TEST_RULE}" == true ]]; then
          printf -- '-A %s -i sbv-rph0 -p tcp -m multiport --dports 18081 -j REDIRECT --to-ports 19094\n' \
            "${REDIRECT_TEST_CHAIN}"
        fi
      else
        return 1
      fi
      :
      ;;
    -N)
      REDIRECT_TEST_CHAIN=${1:-}
      ;;
    -C)
      target=${1:-}
      shift || true
      if [[ "${target}" == "${REDIRECT_TEST_CHAIN}" && "${REDIRECT_TEST_RULE}" == true ]]; then
        return 0
      elif [[ "${target}" == PREROUTING && "${REDIRECT_TEST_JUMP_RULE}" == "PREROUTING $*" ]]; then
        return 0
      fi
      return 1
      ;;
    -A)
      target=${1:-}
      shift || true
      if [[ "${target}" == PREROUTING ]]; then
        if [[ "${REDIRECT_TEST_FAIL_JUMP}" == true ]]; then
          return 1
        fi
        REDIRECT_TEST_JUMP_RULE="PREROUTING $*"
      elif [[ "${target}" == "${REDIRECT_TEST_CHAIN}" ]]; then
        REDIRECT_TEST_RULE=true
      else
        return 1
      fi
      ;;
    -F)
      REDIRECT_TEST_RULE=false
      ;;
    -X)
      REDIRECT_TEST_CHAIN=''
      ;;
    -D)
      REDIRECT_TEST_JUMP_RULE=''
      ;;
    *) return 2 ;;
  esac
}

cat > "${TMP_DIR}/bin/ip" <<'EOF_IP'
#!/usr/bin/env bash
if [[ "${1:-}" == link && "${2:-}" == show && "${3:-}" == dev && "${4:-}" == sbv-rph0 ]]; then
  exit 0
fi
exit 64
EOF_IP
chmod 0755 "${TMP_DIR}/bin/ip"
: > "${SBV_TRANSPARENT_FIREWALL_ROLLBACKS}"
redirect_record="${TMP_DIR}/redirect-policy-transaction.json"
jq -n '{id:"redirect-policy-transaction",role:"inbound",type:"redirect",
  tag:"redirect-policy-transaction",enabled:true,route_rules:[],
  config:{listen:"0.0.0.0",listen_port:19094},
  host_policy:{ingress_interface:"sbv-rph0",destination_ports:[18081],management_ports:[22,19094]}}' \
  > "${redirect_record}"
inactive_before_state=$(cat "${SB_COMPONENT_STATE_FILE}")
inactive_before_config=$(cat "${SINGBOX_CONFIG_FILE}")
printf '%s\n' inactive > "${SBV_TRANSPARENT_SYSTEMCTL_STATE}"
if failed=$(agent_cli component create --json --yes --allow-public \
  --expected-revision 4 --file "${redirect_record}"); then
  printf 'first Redirect host policy unexpectedly succeeded while sing-box was inactive\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "host_policy_requires_active_service"' <<< "${failed}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${inactive_before_state}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${inactive_before_config}" ]]
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]
printf '%s\n' active > "${SBV_TRANSPARENT_SYSTEMCTL_STATE}"
before_state=$(cat "${SB_COMPONENT_STATE_FILE}")
before_config=$(cat "${SINGBOX_CONFIG_FILE}")
current_revision=$(jq -r '.revision' "${SB_COMPONENT_STATE_FILE}")
if failed=$(agent_cli component create --json --yes --allow-public \
  --expected-revision "${current_revision}" --file "${redirect_record}"); then
  printf 'Redirect transaction unexpectedly succeeded after injected PREROUTING jump failure\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "host_policy_apply_failed" and
  .data.ok == false and .data.error == "host_policy_apply_failed"' <<< "${failed}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${before_state}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${before_config}" ]]
[[ -z "${REDIRECT_TEST_CHAIN}" && "${REDIRECT_TEST_RULE}" == false &&
   -z "${REDIRECT_TEST_JUMP_RULE}" ]]
[[ "$(wc -l < "${SBV_TRANSPARENT_FIREWALL_ROLLBACKS}")" -eq 1 ]]
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]

printf '%s\n' 'managed transparent transaction checks passed'
