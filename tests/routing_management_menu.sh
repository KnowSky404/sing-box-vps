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
routing_policy_apply() { cp -- "$1" "${TMP_DIR}/applied-draft.json"; }
routing_policy_restore_previous() { forbidden_call routing_policy_restore_previous; }
media_check_menu() { printf 'called\n' >> "${TMP_DIR}/media-detection"; }
printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[{"ip_is_private":true,"action":"reject"}],"final":"direct"}}' > "${SINGBOX_CONFIG_FILE}"
printf '# preserved\nlegacy.example\n' > "${SB_WARP_DOMAINS_FILE}"
printf '# retained\nfeed|https://rules.example/feed.srs?token=fixture-secret|1d\n' > "${SB_WARP_REMOTE_RULESETS_FILE}"
printf 'WARP_ROUTE_MODE=selective\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
before=$(routing_state_fingerprint)
routing_management_menu > "${TMP_DIR}/readonly.output" 2>&1 <<'EOF'
5
0
4
0
EOF
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_POLICY_FILE}" ]]
[[ ! -e "${TMP_DIR}/forbidden-calls" && -s "${TMP_DIR}/media-detection" ]]
grep -Fq 'Block CN' "${TMP_DIR}/readonly.output"
grep -Fq 'WARP 开关与节点出口设置' "${TMP_DIR}/readonly.output"
! grep -Eq '客户端|局域网直连|广告拦截|fixture-secret' "${TMP_DIR}/readonly.output"
! declare -F routing_client_menu routing_adblock_menu >/dev/null

draft="${TMP_DIR}/draft.json"
routing_draft_create "${draft}"
jq -e '.policy.schema_version==2 and (.policy.server.block_cn|not) and
  (.policy|has("client")|not) and (.policy|has("adblock")|not) and (.warp.enabled|not)' "${draft}" >/dev/null
[[ "$(stat -c %a "${draft}")" == 600 ]]
routing_default_outbound_menu "${draft}" > "${TMP_DIR}/warp.output" <<'EOF'
2
4
0
EOF
jq -e '.warp=={enabled:true,mode:"selective",reregister:true} and (.node_overrides|length)==0' "${draft}" >/dev/null
routing_presets_menu "${draft}" > "${TMP_DIR}/presets.output" <<'EOF'
1
2
0
EOF
jq -e '(.policy.server.warp_ai|not) and (.policy.server.warp_streaming|not) and .warp.enabled' "${draft}" >/dev/null
# A node override belongs to the WARP menu and changes only the private draft.
(
  routing_nodes_json() {
    printf '%s\n' '[{"protocol":"socks","id":"one","name":"Fixture node","tag":"socks-one","policy":"default","revision":7,"editable":true}]'
  }
  routing_default_outbound_menu "${draft}" > "${TMP_DIR}/node-policy.output" <<'EOF'
5
1
3
0
EOF
)
jq -e '.node_overrides==[{protocol:"socks",id:"one",policy:"warp",revision:7}] and
  .warp=={enabled:true,mode:"selective",reregister:true}' "${draft}" >/dev/null
# Invalid removed-client fields and unexpected policy keys never enter a draft.
before_draft=$(sha256sum "${draft}")
if routing_draft_edit "${draft}" '.policy.client={lan_direct:true}' > /dev/null 2>&1; then fail 'removed client setting accepted'; fi
[[ "$(sha256sum "${draft}")" == "${before_draft}" ]]
# Canceling a pending Block CN change preserves every installed network byte.
routing_management_menu > "${TMP_DIR}/cancel.output" 2>&1 <<'EOF'
1
0
y
EOF
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/applied-draft.json" ]]
# Adoption of the server-only policy is an explicit action, even with unchanged
# visible switches. An old deployment can therefore clear retired owned rules.
routing_management_menu > "${TMP_DIR}/apply.output" 2>&1 <<'EOF'
5
1
y
0
EOF
jq -e '.policy.schema_version==2 and (.policy.server.block_cn|not)' "${TMP_DIR}/applied-draft.json" >/dev/null
[[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${TMP_DIR}/forbidden-calls" ]]
printf 'Server-only network menu, explicit adoption, draft isolation and cancellation passed\n'
