#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
fail() { printf 'routing menu failed: %s\n' "$*" >&2; exit 1; }
forbidden_call() { printf '%s\n' "$1" >> "${TMP_DIR}/forbidden-calls"; return 98; }
register_warp() { forbidden_call register_warp; }
systemctl() { forbidden_call systemctl; }
generate_config() { forbidden_call generate_config; }
ensure_warp_routing_assets() { forbidden_call ensure_warp_routing_assets; }
save_warp_route_settings() { forbidden_call save_warp_route_settings; }
push_nodes_to_subman() { forbidden_call push_nodes_to_subman; }
media_check_menu() { printf 'called\n' >> "${TMP_DIR}/media-detection"; }
routing_nodes_json() { cat "${SB_PROJECT_DIR}/fixture-nodes.json"; }

# Persist accepted settings so the production snapshot reader must observe the
# result of each action. No provider, config generator or system service runs.
routing_policy_apply() {
  local candidate=$1 expected
  jq -c . "${candidate}" >> "${TMP_DIR}/apply-attempts.jsonl"
  routing_draft_validate "${candidate}" || return 90
  expected=$(jq -r '.fingerprint' "${candidate}")
  [[ "${expected}" == "$(routing_state_fingerprint)" ]] || return 91
  if [[ -e "${TMP_DIR}/fail-next-apply" ]]; then
    rm -- "${TMP_DIR}/fail-next-apply"
    return 97
  fi
  if ! jq -e --slurpfile nodes "${SB_PROJECT_DIR}/fixture-nodes.json" '
    all(.node_overrides[]; . as $change |
      any($nodes[0][]; .protocol==$change.protocol and .id==$change.id and .revision==$change.revision))
  ' "${candidate}" >/dev/null; then return 92; fi
  cp -- "${SB_ROUTING_POLICY_FILE}" "${TMP_DIR}/previous-policy.json"
  cp -- "${SB_WARP_ROUTE_SETTINGS_FILE}" "${TMP_DIR}/previous-warp.env"
  cp -- "${SB_PROJECT_DIR}/fixture-nodes.json" "${TMP_DIR}/previous-nodes.json"
  jq '.policy' "${candidate}" > "${SB_ROUTING_POLICY_FILE}"
  jq -r '"WARP_ROUTE_MODE="+.warp.mode, "WARP_ENABLED="+(if .warp.enabled then "y" else "n" end)' \
    "${candidate}" > "${SB_WARP_ROUTE_SETTINGS_FILE}"
  jq -rj '.legacy_domains' "${candidate}" > "${SB_WARP_DOMAINS_FILE}"
  jq -rj '.legacy_sources' "${candidate}" > "${SB_WARP_REMOTE_RULESETS_FILE}"
  jq --slurpfile candidate "${candidate}" 'map(. as $node |
    ([$candidate[0].node_overrides[] | select(.protocol==$node.protocol and .id==$node.id)][0]) as $change |
    if $change==null then . else .policy=$change.policy | .revision+=1 end)' \
    "${SB_PROJECT_DIR}/fixture-nodes.json" > "${TMP_DIR}/next-nodes.json"
  cp -- "${TMP_DIR}/next-nodes.json" "${SB_PROJECT_DIR}/fixture-nodes.json"
  if jq -e '.warp.reregister' "${candidate}" >/dev/null; then
    printf 'registered\n' >> "${TMP_DIR}/registrations"
  fi
  jq -c . "${candidate}" >> "${TMP_DIR}/applied.jsonl"
}
routing_policy_restore_previous() {
  cp -- "${TMP_DIR}/previous-policy.json" "${SB_ROUTING_POLICY_FILE}"
  cp -- "${TMP_DIR}/previous-warp.env" "${SB_WARP_ROUTE_SETTINGS_FILE}"
  cp -- "${TMP_DIR}/previous-nodes.json" "${SB_PROJECT_DIR}/fixture-nodes.json"
  printf 'restored\n' >> "${TMP_DIR}/restores"
}
reset_case() {
  rm -rf -- "${SB_PROJECT_DIR}"
  mkdir -p -- "${SB_PROJECT_DIR}"
  rm -f -- "${TMP_DIR}/apply-attempts.jsonl" "${TMP_DIR}/applied.jsonl" \
    "${TMP_DIR}/registrations" "${TMP_DIR}/restores" "${TMP_DIR}/fail-next-apply"
  printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[],"final":"direct"}}' > "${SINGBOX_CONFIG_FILE}"
  routing_policy_read_json > "${TMP_DIR}/initial-policy.json"
  cp -- "${TMP_DIR}/initial-policy.json" "${SB_ROUTING_POLICY_FILE}"
  printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=n\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
  printf '# preserved\nlegacy.example\n' > "${SB_WARP_DOMAINS_FILE}"
  printf '# retained\nfeed|https://rules.example/feed.srs?token=fixture-secret|1d\n' > "${SB_WARP_REMOTE_RULESETS_FILE}"
  printf '%s\n' '[{"protocol":"socks","id":"one","name":"Fixture node","tag":"socks-one","policy":"default","revision":7,"editable":true}]' > "${SB_PROJECT_DIR}/fixture-nodes.json"
}

reset_case
before=$(routing_state_fingerprint)
routing_management_menu > "${TMP_DIR}/readonly.output" 2>&1 <<'INPUT'
0
INPUT
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/apply-attempts.jsonl" ]]
output=$(strip_ansi "$(cat "${TMP_DIR}/readonly.output")")
grep -Eq '^1\. .*Block CN.*关闭' <<< "${output}"
grep -Eq '^2\. .*WARP.*关闭' <<< "${output}"
grep -Eq '^3\. .*AI.*流媒体.*开启' <<< "${output}"
! grep -Eq '草稿|待修改|^Block CN:|^默认出口|^AI / 流媒体走 WARP|fixture-secret|true|false' <<< "${output}"
! declare -F routing_client_menu routing_adblock_menu >/dev/null

# Rule inspection and diagnostics stay read-only and never expose source URLs.
routing_management_menu > "${TMP_DIR}/inspection.output" 2>&1 <<'INPUT'
5
1
0
4
0
INPUT
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/apply-attempts.jsonl" ]]
[[ -s "${TMP_DIR}/media-detection" ]]
! grep -Eq 'fixture-secret|草稿' "${TMP_DIR}/inspection.output"

# A switch commits immediately; returning requires no second apply or discard.
routing_management_menu > "${TMP_DIR}/immediate.output" 2>&1 <<'INPUT'
1
0
INPUT
jq -e '.server.block_cn' "${SB_ROUTING_POLICY_FILE}" >/dev/null
[[ "$(wc -l < "${TMP_DIR}/applied.jsonl")" == 1 ]]
output=$(strip_ansi "$(cat "${TMP_DIR}/immediate.output")")
grep -Eq '^1\. .*Block CN.*开启' <<< "${output}"
! grep -Eq '草稿|\[y/n\]' <<< "${output}"

# Default egress, re-registration and presets persist separately. Re-registration
# is one explicit action, never a sticky flag inherited by the next setting.
reset_case
current="${TMP_DIR}/current.json"
routing_draft_create "${current}"
routing_default_outbound_menu "${current}" > "${TMP_DIR}/warp.output" 2>&1 <<'INPUT'
2
4
n
4
y
3
0
INPUT
[[ "$(wc -l < "${TMP_DIR}/applied.jsonl")" == 3 && "$(wc -l < "${TMP_DIR}/registrations")" == 1 ]]
jq -s -e '.[0].warp=={enabled:true,mode:"selective",reregister:false} and
  .[1].warp.reregister and .[2].warp=={enabled:true,mode:"all",reregister:false}' "${TMP_DIR}/applied.jsonl" >/dev/null
jq -e '.warp=={enabled:true,mode:"all",reregister:false} and .node_overrides==[]' "${current}" >/dev/null
routing_presets_menu "${current}" > "${TMP_DIR}/presets.output" 2>&1 <<'INPUT'
1
2
0
INPUT
jq -e '(.server.warp_ai|not) and (.server.warp_streaming|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
[[ "$(wc -l < "${TMP_DIR}/registrations")" == 1 ]]
! grep -Eq 'true|false|草稿' "${TMP_DIR}/presets.output"

# Selecting the current setting is a no-op, with no apply or provider effect.
count=$(wc -l < "${TMP_DIR}/apply-attempts.jsonl")
routing_setting_apply "${current}" '.warp.enabled=true | .warp.mode="all"' > "${TMP_DIR}/noop.output" 2>&1
[[ "$(wc -l < "${TMP_DIR}/apply-attempts.jsonl")" == "${count}" ]]

# Choosing the existing native default does not adopt a policy on an untouched
# installation. The absence of a policy file is not a request for migration.
reset_case
rm -- "${SB_ROUTING_POLICY_FILE}"
before=$(routing_state_fingerprint)
routing_draft_create "${current}"
routing_default_outbound_menu "${current}" > "${TMP_DIR}/absent-policy-noop.output" 2>&1 <<'INPUT'
1
0
INPUT
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_POLICY_FILE}" &&
   ! -e "${TMP_DIR}/apply-attempts.jsonl" ]]

# An old policy's private-network and advertising restrictions likewise survive
# choosing a setting already marked current. Legacy cleanup remains explicit;
# actual setting changes warn about the accompanying conversion in the menu.
reset_case
jq '{schema_version:1,server:(.server | del(.block_cn) |
    . + {private_network_block:true,adblock:true}),
  client:{lan_direct:false,cn_direct:false,adblock:false},
  adblock:{url:"",domains:["ads.fixture.invalid"],allow:[]}}' \
  "${SB_ROUTING_POLICY_FILE}" > "${TMP_DIR}/legacy-policy.json"
cp -- "${TMP_DIR}/legacy-policy.json" "${SB_ROUTING_POLICY_FILE}"
before=$(routing_state_fingerprint)
routing_draft_create "${current}"
routing_default_outbound_menu "${current}" > "${TMP_DIR}/legacy-noop.output" 2>&1 <<'INPUT'
1
0
INPUT
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/apply-attempts.jsonl" ]]
cmp -- "${TMP_DIR}/legacy-policy.json" "${SB_ROUTING_POLICY_FILE}"
routing_management_menu > "${TMP_DIR}/legacy-overview.output" 2>&1 <<'INPUT'
0
INPUT
output=$(strip_ansi "$(cat "${TMP_DIR}/legacy-overview.output")")
grep -Eq '^5\. .*修改设置时将清理旧版限制' <<< "${output}"
grep -Fq '修改设置时将清理旧版限制' "${TMP_DIR}/legacy-noop.output"
routing_presets_menu "${current}" > "${TMP_DIR}/legacy-presets.output" 2>&1 <<'INPUT'
0
INPUT
grep -Fq '修改设置时将清理旧版限制' "${TMP_DIR}/legacy-presets.output"
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/apply-attempts.jsonl" ]]

# Failed changes are discarded before another independent action is committed.
reset_case
routing_draft_create "${current}"
touch "${TMP_DIR}/fail-next-apply"
if routing_setting_apply "${current}" '.policy.server.block_cn=true' > "${TMP_DIR}/failure.output" 2>&1; then
  fail 'failed application reported success'
fi
jq -e '(.policy.server.block_cn|not)' "${current}" >/dev/null
routing_setting_apply "${current}" '.policy.server.warp_ai=false' > "${TMP_DIR}/after-failure.output" 2>&1
jq -e '(.server.block_cn|not) and (.server.warp_ai|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
[[ "$(wc -l < "${TMP_DIR}/applied.jsonl")" == 1 ]]
# Validation failures likewise preserve current settings and clean the candidate.
count=$(wc -l < "${TMP_DIR}/apply-attempts.jsonl")
if routing_setting_apply "${current}" '.policy.client={lan_direct:true}' > "${TMP_DIR}/invalid.output" 2>&1; then
  fail 'removed client setting accepted'
fi
[[ "$(wc -l < "${TMP_DIR}/apply-attempts.jsonl")" == "${count}" ]]
jq -e '(.policy|has("client")|not) and (.policy.server.block_cn|not)' "${current}" >/dev/null
[[ ! -e "${current}.apply" && ! -e "${current}.apply.next" ]]

# A successful node edit consumes its override and revision. The next edit uses
# the updated live node instead of resubmitting the first operation.
reset_case
routing_draft_create "${current}"
routing_node_policy_menu "${current}" > "${TMP_DIR}/node-warp.output" 2>&1 <<'INPUT'
1
3
INPUT
jq -e '.[0].policy=="warp" and .[0].revision==8' "${SB_PROJECT_DIR}/fixture-nodes.json" >/dev/null
jq -e '.node_overrides==[]' "${current}" >/dev/null
routing_node_policy_menu "${current}" > "${TMP_DIR}/node-direct.output" 2>&1 <<'INPUT'
1
2
INPUT
jq -e '.[0].policy=="direct" and .[0].revision==9' "${SB_PROJECT_DIR}/fixture-nodes.json" >/dev/null
jq -s -e '.[0].node_overrides==[{protocol:"socks",id:"one",policy:"warp",revision:7}] and
  .[1].node_overrides==[{protocol:"socks",id:"one",policy:"direct",revision:8}]' "${TMP_DIR}/applied.jsonl" >/dev/null
[[ ! -e "${TMP_DIR}/forbidden-calls" ]]
printf 'Immediate network settings, inline status, no-op, failure isolation and node refresh passed\n'
