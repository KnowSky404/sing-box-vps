#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

redirect_record='{"id":"redirect-policy-test","role":"inbound","type":"redirect","tag":"redirect-policy-test","enabled":true,"route_rules":[],"config":{"listen":"0.0.0.0","listen_port":1094},"host_policy":{"ingress_interface":"sbv-rph0","destination_ports":[443,80],"management_ports":[22,2222,1094]}}'
managed_component_state_validate_record "${redirect_record}"
if managed_component_requires_public_confirmation "${redirect_record}"; then
  :
else
  printf 'explicit redirect host policy unexpectedly bypassed public confirmation\n' >&2
  exit 1
fi

normalized_file="${TMP_DIR}/redirect-policy.json"
printf '%s\n' "${redirect_record}" > "${normalized_file}"
normalized=$(managed_component_normalize_input_file "${normalized_file}")
managed_component_state_validate_record "${normalized}"
state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${normalized}")
rendered=$(managed_component_render_json "${state}")
jq -e '
  (.inbounds | length) == 1 and
  .inbounds[0].type == "redirect" and .inbounds[0].listen == "0.0.0.0" and
  (.inbounds[0] | has("host_policy") | not)
' <<< "${rendered}" >/dev/null

plan=$(managed_component_redirect_host_policy_plan_for_record "${normalized}")
managed_component_redirect_host_policy_plan_validate_json "[${plan}]"
bad_plan=$(jq -c '.destination_ports = [22]' <<< "${plan}")
if managed_component_redirect_host_policy_plan_validate_json "[${bad_plan}]"; then
  printf 'Redirect journal plan unexpectedly allowed a management-port capture\n' >&2
  exit 1
fi
if managed_component_redirect_host_policy_plan_validate_json $'[\n]\n[]'; then
  printf 'Redirect journal plan unexpectedly accepted multiple JSON documents\n' >&2
  exit 1
fi
reordered=$(jq -c '.host_policy.destination_ports |= reverse' <<< "${normalized}")
reordered_plan=$(managed_component_redirect_host_policy_plan_for_record "${reordered}")
[[ "$(jq -r '.chain' <<< "${plan}")" == "$(jq -r '.chain' <<< "${reordered_plan}")" ]]
jq -e '.family == "ipv4" and .transport == "tcp" and
  .interface == "sbv-rph0" and .destination_ports == [80,443] and
  .management_ports == [22,1094,2222] and .listen_port == 1094' <<< "${plan}" >/dev/null

bad_overlap=$(jq -c '.host_policy.management_ports += [80]' <<< "${normalized}")
bad_loopback=$(jq -c '.config.listen = "127.0.0.1"' <<< "${normalized}")
bad_interface=$(jq -c '.host_policy.ingress_interface = "eth0+"' <<< "${normalized}")
bad_tproxy=$(jq -c '.type = "tproxy"' <<< "${normalized}")
bad_listener_capture=$(jq -c '.host_policy.destination_ports = [1094] |
  .host_policy.management_ports = [22]' <<< "${normalized}")
for bad in "${bad_overlap}" "${bad_loopback}" "${bad_interface}" "${bad_tproxy}" "${bad_listener_capture}"; do
  if managed_component_state_validate_record "${bad}"; then
    printf 'invalid Redirect host policy unexpectedly accepted: %s\n' "${bad}" >&2
    exit 1
  fi
done

disabled_file="${TMP_DIR}/redirect-policy-disabled.json"
jq -c '.enabled = false' <<< "${redirect_record}" > "${disabled_file}"
disabled=$(managed_component_normalize_input_file "${disabled_file}")
[[ "$(jq -r '.enabled' <<< "${disabled}")" == false ]]
managed_component_state_validate_record "${disabled}"
if managed_component_requires_public_confirmation "${disabled}"; then
  printf 'disabled Redirect host policy unexpectedly required public exposure confirmation\n' >&2
  exit 1
fi
disabled_environment=$(managed_component_instance_environment_json "${disabled}")
jq -e '.requirements.managed_redirect_host_policy == false and
  .requirements.redirect_host_policy_scope == null' \
  <<< "${disabled_environment}" >/dev/null
disabled_state=$(managed_component_state_candidate \
  "$(managed_component_state_default_json)" create "${disabled}")
[[ "$(managed_component_redirect_host_policy_plan_json "${disabled_state}")" == '[]' ]]
disabled_rendered=$(managed_component_render_json "${disabled_state}")
jq -e '.inbounds == []' <<< "${disabled_rendered}" >/dev/null

# Simulate an unavailable host firewall read-only.  Diagnose must say
# unavailable and preflight must fail closed without attempting a mutation.
iptables() {
  return 1
}
report=$(managed_component_redirect_policy_diagnose_json "${state}")
jq -e '.status == "unavailable" and .resources[0].status == "unavailable" and
  .resources[0].resource_scope == "installer_owned_ipv4_tcp_prerouting"' \
  <<< "${report}" >/dev/null
if managed_component_redirect_policy_preflight '[]' "$(managed_component_redirect_host_policy_plan_json "${state}")"; then
  printf 'Redirect host policy preflight unexpectedly succeeded without iptables access\n' >&2
  exit 1
fi

transaction_dir="${SB_COMPONENT_TRANSACTION_DIR}"
mkdir -m 700 "${transaction_dir}"
mkdir -m 700 "${transaction_dir}/snapshot"
journal="${transaction_dir}/snapshot/component-redirect-policy.json"
managed_component_redirect_policy_journal_write "${journal}" '[]' "[${plan}]"
managed_component_redirect_policy_journal_validate "${journal}"
managed_component_redirect_policy_journal_set_status "${journal}" applying
jq -e '.schema_version == 1 and .status == "applying" and
  .before == [] and (.after | length) == 1 and .after[0].chain == "'"$(jq -r '.chain' <<< "${plan}")"'"' \
  "${journal}" >/dev/null

jq '.status = "unexpected"' "${journal}" > "${journal}.invalid"
chmod 600 "${journal}.invalid"
mv -f -- "${journal}.invalid" "${journal}"
if managed_component_redirect_policy_journal_validate "${journal}"; then
  printf 'Redirect policy journal with an invalid status unexpectedly validated\n' >&2
  exit 1
fi

printf '%s\n' 'managed Redirect host policy contract checks passed'
