#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
state=$(managed_component_state_default_json)
config="${TMP_DIR}/guard.json"

# A boolean expression before `as` changes the binding input in jq 1.8.
printf '%s\n' '{"route":{"rule_set":[]}}' > "${config}"
managed_component_live_route_rule_sets_match_state "${config}" "${state}"
printf '%s\n' '{"route":{"rule_set":[{"type":"local","tag":"warp-local-fixture","path":"/fixture.srs"}]}}' > "${config}"
managed_component_live_route_rule_sets_match_state "${config}" "${state}"
for document in \
  '{"route":false}' \
  '{"route":{"rule_set":false}}' \
  '{"route":{"rule_set":[{"type":"local","tag":"unknown","path":"/fixture.srs"}]}}' \
  '{"route":{"rule_set":[{"type":"local","tag":"warp-local-a"},{"type":"local","tag":"warp-local-a"}]}}'; do
  printf '%s\n' "${document}" > "${config}"
  if managed_component_live_route_rule_sets_match_state "${config}" "${state}"; then
    printf 'invalid/unowned rule sets accepted\n' >&2; exit 1
  fi
done

expected="${TMP_DIR}/expected.json"
jq -n '{route:{rules:[
  {inbound:["probe"],action:"sniff"},
  {inbound:["probe"],ip_is_private:true,action:"reject"},
  {inbound:["probe"],action:"route",outbound:"warp-ep"}]}}' > "${expected}"
routing_policy_validate_merged_order "${expected}" "${expected}" '["probe"]'
jq '.route.rules=[{inbound:["other"],action:"route",outbound:"direct"}]+.route.rules' "${expected}" > "${config}"
routing_policy_validate_merged_order "${expected}" "${config}" '["probe"]'
for filter in \
  '.route.rules |= reverse' \
  '.route.rules=[{inbound:["probe"],action:"route",outbound:"direct"}]+.route.rules'; do
  jq "${filter}" "${expected}" > "${config}"
  before=$(sha256sum "${config}")
  if routing_policy_validate_merged_order "${expected}" "${config}" '["probe"]' > "${TMP_DIR}/rejected.log" 2>&1; then
    printf 'unsafe routing order accepted\n' >&2; exit 1
  fi
  [[ "$(sha256sum "${config}")" == "${before}" ]]
done
printf 'rule-set ownership and route-order guards pass positive/negative cases (%s)\n' "$(jq --version)"
