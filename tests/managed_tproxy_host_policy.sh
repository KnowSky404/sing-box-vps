#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

tproxy_record='{"id":"tproxy-policy-test","role":"inbound","type":"tproxy","tag":"tproxy-policy-test","enabled":true,"route_rules":[],"config":{"listen":"0.0.0.0","listen_port":1095,"network":["tcp","udp"]},"host_policy":{"ingress_interface":"sbv-tph0","destination_ports":[18081,18080],"management_ports":[22,2222,1095]}}'
managed_component_state_validate_record "${tproxy_record}"
if ! managed_component_requires_public_confirmation "${tproxy_record}"; then
  printf 'TProxy host policy unexpectedly bypassed explicit public exposure confirmation\n' >&2
  exit 1
fi

input_file="${TMP_DIR}/tproxy-policy.json"
printf '%s\n' "${tproxy_record}" > "${input_file}"
normalized=$(managed_component_normalize_input_file "${input_file}")
managed_component_state_validate_record "${normalized}"
state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${normalized}")
redirect_policy_plans=$(managed_component_redirect_host_policy_plan_json "${state}")
jq -e 'length == 0' <<< "${redirect_policy_plans}" >/dev/null || {
  printf 'TProxy host policy was also exposed as an installer-managed Redirect/NAT policy\n' >&2
  exit 1
}
rendered=$(managed_component_render_json "${state}")
jq -e '(.inbounds | length) == 1 and .inbounds[0].type == "tproxy" and
  .inbounds[0].listen == "0.0.0.0" and (.inbounds[0] | has("host_policy") | not)' \
  <<< "${rendered}" >/dev/null

plan=$(managed_component_tproxy_host_policy_plan_for_record "${normalized}")
managed_component_tproxy_host_policy_plan_validate_json "[${plan}]"
test_priority=$(jq -r '.rule_priority' <<< "${plan}")
test_mark=$(jq -r '.mark' <<< "${plan}")
test_table=$(jq -r '.route_table' <<< "${plan}")
test_route_state=absent
ip() {
  [[ "$*" == '-4 route show table all' ]] || return 1
  case "${test_route_state}" in
    present) printf 'local 0.0.0.0/0 dev lo table %s\n' "${test_table}" ;;
    conflict)
      printf 'local 0.0.0.0/0 dev lo table %s\n' "${test_table}"
      printf 'unicast 198.51.100.0/24 dev eth0 table %s\n' "${test_table}"
      ;;
    absent) ;;
    *) return 2 ;;
  esac
}
[[ "$(managed_component_tproxy_policy_route_status "${plan}")" == absent ]]
test_route_state=present
[[ "$(managed_component_tproxy_policy_route_status "${plan}")" == present ]]
test_route_state=conflict
[[ "$(managed_component_tproxy_policy_route_status "${plan}")" == conflict ]]
ip() {
  [[ "$*" == '-4 rule show' ]] || return 1
  printf '%s: from all fwmark %s/0xffffffff lookup %s\n' \
    "${test_priority}" "${test_mark}" "${test_table}"
}
[[ "$(managed_component_tproxy_policy_route_rule_status "${plan}")" == present ]]
ip() {
  [[ "$*" == '-4 rule show' ]] || return 1
  printf '%s: from 198.51.100.0/24 fwmark %s/0xffffffff lookup %s\n' \
    "${test_priority}" "${test_mark}" "${test_table}"
}
[[ "$(managed_component_tproxy_policy_route_rule_status "${plan}")" == conflict ]]
test_marker=$(jq -r '.marker' <<< "${plan}")
test_chain=$(jq -r '.chain' <<< "${plan}")
iptables() {
  [[ "$*" == '-t mangle -S PREROUTING' ]] || return 1
  printf '%s\n' "-A PREROUTING -m comment --comment ${test_marker} -j ${test_chain}"
}
ip() {
  [[ "$*" == '-4 rule show' ]] || return 1
  printf '%s\n' '0: from all lookup local'
  printf '%s: from all fwmark %s/0xffffffff lookup %s\n' \
    "${test_priority}" "${test_mark}" "${test_table}"
  printf '%s\n' '32766: from all lookup main'
}
precedence=$(managed_component_tproxy_policy_precedence_json "${plan}")
jq -e '.status == "unshadowed_in_observed_order" and
  .policy_routing_status == "unshadowed_in_observed_order" and
  .preceding_policy_rule_count == 0' <<< "${precedence}" >/dev/null
ip() {
  [[ "$*" == '-4 rule show' ]] || return 1
  printf '%s\n' '0: from all lookup local' '50: from all lookup 100'
  printf '%s: from all fwmark %s/0xffffffff lookup %s\n' \
    "${test_priority}" "${test_mark}" "${test_table}"
  printf '%s\n' '32766: from all lookup main'
}
precedence=$(managed_component_tproxy_policy_precedence_json "${plan}")
jq -e '.policy_routing_status == "not_assessed_earlier_rules_present" and
  .preceding_policy_rule_count == 1' <<< "${precedence}" >/dev/null
jq -e '.family == "ipv4" and .networks == ["tcp","udp"] and
  .interface == "sbv-tph0" and .destination_ports == [18080,18081] and
  .management_ports == [22,1095,2222] and .listen_port == 1095 and
  .mark_mask == "0xffffffff" and .route_table >= 10000 and
  .route_table <= 2000010000 and .rule_priority >= 10000 and
  .rule_priority < 30000 and (.mark | test("^0x5b[0-9a-f]{6}$"))' \
  <<< "${plan}" >/dev/null

reordered=$(jq -c '.config.network |= reverse |
  .host_policy.destination_ports |= reverse |
  .host_policy.management_ports |= reverse' <<< "${normalized}")
reordered_plan=$(managed_component_tproxy_host_policy_plan_for_record "${reordered}")
[[ "${plan}" == "${reordered_plan}" ]]

tampered=$(jq -c '.route_table += 1' <<< "${plan}")
if managed_component_tproxy_host_policy_plan_validate_json "[${tampered}]"; then
  printf 'TProxy plan validator accepted an unowned derived route table\n' >&2
  exit 1
fi
tampered=$(jq -c '.rule_priority = 32766' <<< "${plan}")
if managed_component_tproxy_host_policy_plan_validate_json "[${tampered}]"; then
  printf 'TProxy plan validator accepted a fwmark rule after the default main rule\n' >&2
  exit 1
fi
if managed_component_tproxy_host_policy_plan_validate_json $'[]\n[]'; then
  printf 'TProxy plan validator accepted multiple JSON documents\n' >&2
  exit 1
fi

bad_records=(
  "$(jq -c '.config.network = "tcp"' <<< "${normalized}")"
  "$(jq -c '.config.network = ["tcp","tcp"]' <<< "${normalized}")"
  "$(jq -c '.host_policy.management_ports = [2222,1095]' <<< "${normalized}")"
  "$(jq -c '.host_policy.destination_ports += [22]' <<< "${normalized}")"
  "$(jq -c '.host_policy.destination_ports = [1095]' <<< "${normalized}")"
  "$(jq -c '.host_policy.ingress_interface = "eth0+"' <<< "${normalized}")"
  "$(jq -c '.type = "direct"' <<< "${normalized}")"
)
for invalid in "${bad_records[@]}"; do
  if managed_component_state_validate_record "${invalid}"; then
    printf 'invalid TProxy host policy unexpectedly accepted: %s\n' "${invalid}" >&2
    exit 1
  fi
done

disabled_file="${TMP_DIR}/tproxy-policy-disabled.json"
jq -c '.enabled = false' <<< "${normalized}" > "${disabled_file}"
disabled=$(managed_component_normalize_input_file "${disabled_file}")
managed_component_state_validate_record "${disabled}"
if managed_component_requires_public_confirmation "${disabled}"; then
  printf 'disabled TProxy host policy unexpectedly required public exposure confirmation\n' >&2
  exit 1
fi
disabled_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${disabled}")
[[ "$(managed_component_tproxy_host_policy_plan_json "${disabled_state}")" == '[]' ]]
disabled_environment=$(managed_component_instance_environment_json "${disabled}")
jq -e '.requirements.managed_tproxy_host_policy == false and
  .requirements.tproxy_host_policy_scope == null' <<< "${disabled_environment}" >/dev/null
iptables() {
  case "$*" in
    '-t mangle -S'|'-j TPROXY -h'|'-m multiport -h') return 0 ;;
    *) return 1 ;;
  esac
}
ip() { [[ "$*" == '-4 rule show' ]] && return 1; return 1; }
enabled_environment=$(managed_component_instance_environment_json "${normalized}")
jq -e '.requirements.managed_tproxy_host_policy == true and
  any(.dependencies[]; .name == "iptables_mangle" and .status == "available") and
  any(.dependencies[]; .name == "iptables_tproxy_target" and .status == "available") and
  any(.dependencies[]; .name == "iptables_multiport_match" and .status == "available") and
  any(.dependencies[]; .name == "iproute2_policy_routing" and .status == "unavailable")' \
  <<< "${enabled_environment}" >/dev/null
iptables() { [[ "$*" == '-t mangle -S' ]]; }
ip() {
  case "$*" in
    '-4 rule show'|'link show dev sbv-tph0') return 0 ;;
    *) return 1 ;;
  esac
}
missing_extensions_environment=$(managed_component_instance_environment_json "${normalized}")
jq -e 'any(.dependencies[]; .name == "iptables_mangle" and .status == "available") and
  any(.dependencies[]; .name == "iptables_tproxy_target" and .status == "unavailable") and
  any(.dependencies[]; .name == "iptables_multiport_match" and .status == "unavailable") and
  any(.dependencies[]; .name == "iproute2_policy_routing" and .status == "available")' \
  <<< "${missing_extensions_environment}" >/dev/null

transaction_dir=${SB_COMPONENT_TRANSACTION_DIR}
mkdir -m 700 "${transaction_dir}"
mkdir -m 700 "${transaction_dir}/snapshot"
journal="${transaction_dir}/snapshot/component-tproxy-policy.json"
managed_component_tproxy_policy_journal_write "${journal}" '[]' "[${plan}]"
managed_component_tproxy_policy_journal_validate "${journal}"
managed_component_tproxy_policy_journal_set_status "${journal}" applying
jq -e '.schema_version == 1 and .status == "applying" and .before == [] and
  (.after | length) == 1 and .after[0].chain == "'"$(jq -r '.chain' <<< "${plan}")"'"' \
  "${journal}" >/dev/null

jq '.status = "unexpected"' "${journal}" > "${journal}.invalid"
chmod 600 "${journal}.invalid"
mv -f -- "${journal}.invalid" "${journal}"
if managed_component_tproxy_policy_journal_validate "${journal}"; then
  printf 'TProxy policy journal with an invalid status unexpectedly validated\n' >&2
  exit 1
fi

# Exercise an exact apply/compensate cycle with in-memory command mocks. This
# covers the persistent policy journal without touching the host network.
MOCK_TPROXY_CHAIN=''
MOCK_TPROXY_JUMP=''
MOCK_TPROXY_RULES=()
MOCK_TPROXY_ROUTE=false
MOCK_TPROXY_RULE=false
MOCK_TPROXY_MARK=''
MOCK_TPROXY_TABLE=''
MOCK_TPROXY_PRIORITY=''
iptables() {
  local action=${3:-} chain=${4:-} rule
  case "${action}" in
    -S)
      if [[ -n "${chain}" ]]; then
        [[ "${chain}" == "${MOCK_TPROXY_CHAIN}" ]] || return 1
        printf -- '-N %s\n' "${chain}"
        for rule in "${MOCK_TPROXY_RULES[@]}"; do
          printf -- '-A %s %s\n' "${chain}" "${rule}"
        done
      else
        printf '%s\n' '-P PREROUTING ACCEPT'
        [[ -z "${MOCK_TPROXY_CHAIN}" ]] || printf -- '-N %s\n' "${MOCK_TPROXY_CHAIN}"
        for rule in "${MOCK_TPROXY_RULES[@]}"; do
          printf -- '-A %s %s\n' "${MOCK_TPROXY_CHAIN}" "${rule}"
        done
        [[ -z "${MOCK_TPROXY_JUMP}" ]] ||
          printf -- '-A PREROUTING %s\n' "${MOCK_TPROXY_JUMP}"
      fi
      ;;
    -C)
      shift 4
      rule=$*
      if [[ "${chain}" == PREROUTING ]]; then
        [[ -n "${MOCK_TPROXY_CHAIN}" ]] || return 2
        [[ -n "${MOCK_TPROXY_JUMP}" && "${rule}" == "${MOCK_TPROXY_JUMP}" ]]
      else
        [[ "${chain}" == "${MOCK_TPROXY_CHAIN}" ]] || return 2
        local existing
        for existing in "${MOCK_TPROXY_RULES[@]}"; do
          [[ "${existing}" == "${rule}" ]] && return 0
        done
        return 1
      fi
      ;;
    -N)
      [[ -z "${MOCK_TPROXY_CHAIN}" ]] || return 1
      MOCK_TPROXY_CHAIN=${chain}
      ;;
    -A)
      shift 4
      rule=$*
      if [[ "${chain}" == PREROUTING ]]; then
        [[ -z "${MOCK_TPROXY_JUMP}" ]] || return 1
        MOCK_TPROXY_JUMP=${rule}
      else
        MOCK_TPROXY_RULES+=("${rule}")
      fi
      ;;
    -D)
      shift 4
      rule=$*
      if [[ "${chain}" == PREROUTING ]]; then
        [[ "${MOCK_TPROXY_JUMP}" == "${rule}" ]] || return 1
        MOCK_TPROXY_JUMP=''
      else
        local index
        for index in "${!MOCK_TPROXY_RULES[@]}"; do
          if [[ "${MOCK_TPROXY_RULES[${index}]}" == "${rule}" ]]; then
            unset "MOCK_TPROXY_RULES[index]"
            return 0
          fi
        done
        return 1
      fi
      ;;
    -F)
      [[ "${chain}" == "${MOCK_TPROXY_CHAIN}" ]] || return 1
      MOCK_TPROXY_RULES=()
      ;;
    -X)
      [[ "${chain}" == "${MOCK_TPROXY_CHAIN}" && -z "${MOCK_TPROXY_RULES[*]}" ]] || return 1
      MOCK_TPROXY_CHAIN=''
      ;;
    *) return 2 ;;
  esac
}
ip() {
  local route_table=''
  case "$*" in
    '-4 rule show')
      printf '%s\n' '0: from all lookup local'
      if [[ "${MOCK_TPROXY_RULE}" == true ]]; then
        printf '%s: from all fwmark %s/0xffffffff lookup %s\n' \
          "${MOCK_TPROXY_PRIORITY}" "${MOCK_TPROXY_MARK}" "${MOCK_TPROXY_TABLE}"
      fi
      printf '%s\n' '32766: from all lookup main' '32767: from all lookup default'
      ;;
    '-4 route show table all')
      if [[ "${MOCK_TPROXY_ROUTE}" == true ]]; then
        printf 'local 0.0.0.0/0 dev lo table %s\n' "${MOCK_TPROXY_TABLE}"
      fi
      return 0
      ;;
    'link show dev '*) return 0 ;;
    '-4 route add local 0.0.0.0/0 dev lo table '*)
      [[ "${MOCK_TPROXY_ROUTE}" == false ]] || return 1
      MOCK_TPROXY_TABLE=${9}
      MOCK_TPROXY_ROUTE=true
      ;;
    '-4 rule add priority '*)
      [[ "${MOCK_TPROXY_RULE}" == false ]] || return 1
      MOCK_TPROXY_PRIORITY=${5}
      MOCK_TPROXY_MARK=${7%/*}
      MOCK_TPROXY_TABLE=${9}
      MOCK_TPROXY_RULE=true
      ;;
    '-4 rule del priority '*)
      [[ "${MOCK_TPROXY_RULE}" == true && "${5}" == "${MOCK_TPROXY_PRIORITY}" &&
         "${7}" == "${MOCK_TPROXY_MARK}/0xffffffff" &&
         "${9}" == "${MOCK_TPROXY_TABLE}" ]] || return 1
      MOCK_TPROXY_RULE=false
      ;;
    '-4 route del local 0.0.0.0/0 dev lo table '*)
      [[ "${MOCK_TPROXY_ROUTE}" == true && "${9}" == "${MOCK_TPROXY_TABLE}" ]] || return 1
      MOCK_TPROXY_ROUTE=false
      ;;
    *) return 2 ;;
  esac
}
[[ "$(managed_component_tproxy_policy_probe "${plan}")" == absent ]]
functional_journal=${journal}
rm -f -- "${functional_journal}"
managed_component_tproxy_policy_journal_write "${functional_journal}" '[]' "[${plan}]"
managed_component_tproxy_policy_apply_journal "${functional_journal}"
[[ "$(managed_component_tproxy_policy_probe "${plan}")" == present ]]
managed_component_tproxy_policy_remove_delta "${functional_journal}"
managed_component_tproxy_policy_restore_before "${functional_journal}"
[[ "$(managed_component_tproxy_policy_probe "${plan}")" == absent ]]
[[ "${MOCK_TPROXY_CHAIN}" == '' && "${MOCK_TPROXY_ROUTE}" == false &&
   "${MOCK_TPROXY_RULE}" == false && "${MOCK_TPROXY_JUMP}" == '' ]]

# Simulate unavailable host controls without touching the development host.
iptables() { return 1; }
ip() { return 1; }
report=$(managed_component_tproxy_policy_diagnose_json "${state}")
jq -e '.status == "unavailable" and .resources[0].status == "unavailable" and
  .resources[0].resource_scope == "installer_owned_ipv4_tcp_udp_prerouting_policy_route"' \
  <<< "${report}" >/dev/null
if managed_component_tproxy_policy_preflight '[]' "$(managed_component_tproxy_host_policy_plan_json "${state}")"; then
  printf 'TProxy host policy preflight unexpectedly succeeded without iptables/iproute2\n' >&2
  exit 1
fi

printf '%s\n' 'managed TProxy host policy contract checks passed'
