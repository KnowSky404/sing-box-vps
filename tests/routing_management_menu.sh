#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

fail() { printf 'routing menu failed: %s\n' "$*" >&2; exit 1; }
forbidden_call() {
  printf '%s\n' "$1" >> "${TMP_DIR}/forbidden-calls"
  return 98
}
register_warp() { forbidden_call register_warp; }
systemctl() { forbidden_call systemctl; }
generate_config() { forbidden_call generate_config; }
ensure_warp_routing_assets() { forbidden_call ensure_warp_routing_assets; }
save_warp_route_settings() { forbidden_call save_warp_route_settings; }
push_nodes_to_subman() { forbidden_call push_nodes_to_subman; }
export_singbox_client_config() { forbidden_call export_singbox_client_config; }
view_node_info() { forbidden_call view_node_info; }
routing_policy_apply() { forbidden_call routing_policy_apply; }
routing_policy_restore_previous() { forbidden_call routing_policy_restore_previous; }

mkdir -p "${SB_WARP_LOCAL_RULESET_DIR}"
printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[{"ip_is_private":true,"action":"reject"}],"final":"direct"},"fixture_note":"fixture-live-secret"}' > "${SINGBOX_CONFIG_FILE}"
printf '# Existing domains\nlegacy.example\n=exact.example\n' > "${SB_WARP_DOMAINS_FILE}"
printf '# Existing sources\nlegacy-feed|https://rules.example/legacy.srs?token=fixture-url-secret|1d\n' > "${SB_WARP_REMOTE_RULESETS_FILE}"
printf 'WARP_ROUTE_MODE=selective\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
printf '%s\n' '{"version":3,"rules":[{"domain_suffix":["local.example"]}]}' > "${SB_WARP_LOCAL_RULESET_DIR}/local.json"

# Hash metadata and bytes, excluding access times that legitimate reads update.
project_digest() {
  python3 - "${SB_PROJECT_DIR}" <<'PY'
import hashlib, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
for path in [root, *sorted(root.rglob('*'))]:
    meta = path.lstat()
    digest.update(repr((str(path.relative_to(root)), meta.st_mode, meta.st_mtime_ns, meta.st_size)).encode())
    if stat.S_ISREG(meta.st_mode): digest.update(path.read_bytes())
    elif stat.S_ISLNK(meta.st_mode): digest.update(os.readlink(path).encode())
print(digest.hexdigest())
PY
}
before_project=$(project_digest)
before_state=$(routing_state_fingerprint)

# Exercise the real main-menu dispatch to entry 13, overview, preview, cancel
# and return. Status probes and command installation are independent boundaries.
check_root() { :; }
acquire_managed_write_lock() { :; }
ensure_sbv_command_installed() { :; }
check_script_status() { SCRIPT_VER_STATUS=''; }
check_sb_version() { SB_VER_STATUS=''; }
check_bbr_status() { BBR_STATUS=''; }
main_menu_service_status_summary() { printf active; }
exit_script() { exit 0; }
(main) > "${TMP_DIR}/readonly.output" 2>&1 <<'EOF'
13
1
10
0
0
0
EOF
grep -Fq '13. 规则与分流管理' "${TMP_DIR}/readonly.output"
grep -Fq '普通分享链接不携带规则' "${TMP_DIR}/readonly.output"
! grep -Fq 'fixture-url-secret' "${TMP_DIR}/readonly.output"
! grep -Fq 'fixture-live-secret' "${TMP_DIR}/readonly.output"
[[ "$(project_digest)" == "${before_project}" ]] || fail 'read-only navigation wrote into the installed project'
[[ ! -e "${SB_ROUTING_POLICY_FILE}" && ! -e "${TMP_DIR}/forbidden-calls" ]]

draft="${TMP_DIR}/draft.json"
routing_draft_create "${draft}"
[[ "$(stat -c '%a' "${draft}")" == 600 ]]
jq -e '.policy.server.private_network_block and (.policy.server.adblock|not) and
  .policy.client.lan_direct and .policy.client.cn_direct and (.warp.enabled|not) and
  (.legacy_domains|contains("legacy.example")) and (.legacy_sources|contains("legacy-feed|"))' "${draft}" >/dev/null

# Default and preset edits affect only their own draft fields and do not register
# an account or activate a new outbound before applying.
routing_default_outbound_menu "${draft}" > "${TMP_DIR}/default.output" <<'EOF'
2
4
0
EOF
jq -e '.warp=={enabled:true,mode:"selective",reregister:true} and
  .policy.client.lan_direct and (.node_overrides|length)==0' "${draft}" >/dev/null
routing_presets_menu "${draft}" > "${TMP_DIR}/presets.output" <<'EOF'
1
2
0
EOF
jq -e '(.policy.server.warp_ai|not) and (.policy.server.warp_streaming|not) and .warp.enabled' "${draft}" >/dev/null

# A disabled rule remains disabled while editing its matcher and outbound.
routing_collection_menu "${draft}" rules > "${TMP_DIR}/rules.output" 2>&1 <<'EOF'
1
first-rule
2
original.example
3
3
1
2
1

1
edited.example
2
0
EOF
jq -e '.policy.server.rules==[{id:"first-rule",kind:"domain",value:"edited.example",action:"warp",enabled:false}]' "${draft}" >/dev/null

# Switching a source from HTTPS to a local file removes the old URL and keeps
# its disabled state. Other collections and legacy asset text remain intact.
routing_collection_menu "${draft}" rule_sets > "${TMP_DIR}/sources.output" 2>&1 <<EOF
1
custom-feed
1
1
https://rules.example/custom.srs?token=fixture-url-secret
6h
2
3
1
2
1

2
2
${TMP_DIR}/local-source.json
2h
3
0
EOF
jq -e --arg path "${TMP_DIR}/local-source.json" '
  .policy.server.rule_sets==[{tag:"custom-feed",type:"local",format:"source",path:$path,
    update_interval:"2h",action:"reject",enabled:false}] and
  (.policy.server.rules|length)==1 and (.legacy_domains|contains("legacy.example"))' "${draft}" >/dev/null

# Deletion changes only the selected draft collection or legacy-file text;
# the installed files and the original editable draft remain untouched.
copy_draft="${TMP_DIR}/deleted-draft.json"
cp "${draft}" "${copy_draft}"
routing_collection_menu "${copy_draft}" rules > "${TMP_DIR}/deleted.output" <<'EOF'
4
1
0
EOF
routing_collection_menu "${copy_draft}" rule_sets >> "${TMP_DIR}/deleted.output" <<'EOF'
4
1
0
EOF
routing_legacy_assets_menu "${copy_draft}" legacy_domains >> "${TMP_DIR}/deleted.output" <<'EOF'
1
2
0
EOF
jq -e '.policy.server.rules==[] and .policy.server.rule_sets==[] and
  .legacy_domains=="# Existing domains\n=exact.example\n" and
  (.legacy_sources|contains("legacy-feed|"))' "${copy_draft}" >/dev/null
jq -e '(.policy.server.rules|length)==1 and (.policy.server.rule_sets|length)==1 and
  (.legacy_domains|contains("legacy.example"))' "${draft}" >/dev/null

routing_adblock_menu "${draft}" > "${TMP_DIR}/adblock.output" 2>&1 <<'EOF'
1
2
4
ADS.Example
6
Allowed.Example
3
-
0
EOF
jq -e '.policy.server.adblock and .policy.client.adblock and
  .policy.adblock=={url:"",domains:["ads.example"],allow:["allowed.example"]}' "${draft}" >/dev/null
routing_client_menu "${draft}" > "${TMP_DIR}/client.output" <<'EOF'
1
2
3
0
EOF
jq -e '.policy.client=={lan_direct:false,cn_direct:false,adblock:false} and .policy.server.adblock' "${draft}" >/dev/null

# Inventory is an independent read-only source. The editor stages only a typed,
# revision-bound override; restoring the original value removes that override.
routing_nodes_json() {
  printf '%s\n' '[{"protocol":"mixed","id":"main","name":"Fixture","tag":"mixed-in","policy":"warp","revision":7,"editable":true},{"protocol":"hy2","id":"legacy","name":"Legacy","tag":"legacy-hy2","policy":"default","revision":0,"editable":false}]'
}
routing_node_policy_menu "${draft}" > "${TMP_DIR}/node.output" <<'EOF'
1
2
EOF
jq -e '.node_overrides==[{protocol:"mixed",id:"main",policy:"direct",revision:7}]' "${draft}" >/dev/null
routing_node_policy_menu "${draft}" >> "${TMP_DIR}/node.output" <<'EOF'
1
3
EOF
jq -e '.node_overrides==[]' "${draft}" >/dev/null
routing_node_policy_menu "${draft}" >> "${TMP_DIR}/node.output" <<'EOF'
1
1
EOF
jq -e '.node_overrides==[{protocol:"mixed",id:"main",policy:"default",revision:7}]' "${draft}" >/dev/null
cp "${draft}" "${TMP_DIR}/before-legacy.json"
routing_node_policy_menu "${draft}" >> "${TMP_DIR}/node.output" 2>&1 <<'EOF'
2
EOF
cmp -s "${draft}" "${TMP_DIR}/before-legacy.json" || fail 'legacy node selection changed the draft'
routing_policy_preview "${draft}" > "${TMP_DIR}/edited-preview.output" 2>&1
! grep -Fq 'fixture-url-secret' "${TMP_DIR}/edited-preview.output"
[[ "$(project_digest)" == "${before_project}" ]] || fail 'editing or preview changed the installed project'
[[ "$(routing_state_fingerprint)" == "${before_state}" ]]
[[ ! -e "${TMP_DIR}/forbidden-calls" && ! -e "${SB_ROUTING_POLICY_FILE}" ]]

# Declining a dirty exit, including its blank/default-N response, retains the
# draft. A subsequent preview still displays the edited private-network setting.
declare -f prompt_yes_no | sed '1s/^prompt_yes_no /actual_prompt_yes_no /' > "${TMP_DIR}/actual-yes-no.sh"
source "${TMP_DIR}/actual-yes-no.sh"
prompt_yes_no() {
  printf '%s|default=%s\n' "$1" "${2:-}" >> "${TMP_DIR}/confirmations"
  actual_prompt_yes_no "$@"
}
routing_management_menu > "${TMP_DIR}/dirty.output" 2>&1 <<'EOF'
6
0

1
0
y
EOF
[[ "$(grep -c '放弃未应用的草稿.*default=n' "${TMP_DIR}/confirmations")" == 2 ]]
[[ "$(grep -c '草稿状态: 有待应用修改' "${TMP_DIR}/dirty.output")" -ge 3 ]]
[[ "$(project_digest)" == "${before_project}" ]] || fail 'cancelling a draft changed the installed project'

# Preview and a declined apply perform no activation. A later explicit yes
# invokes exactly one apply and never exports links/configs or writes to SubMan.
routing_policy_apply() {
  routing_draft_validate "$1" || return 1
  cp "$1" "${TMP_DIR}/applied-draft.json"
  printf 'apply\n' >> "${TMP_DIR}/apply-calls"
}
: > "${TMP_DIR}/confirmations"
routing_management_menu > "${TMP_DIR}/apply.output" 2>&1 <<'EOF'
6
10
1

10
1
y
0
EOF
[[ "$(grep -c '^apply$' "${TMP_DIR}/apply-calls")" == 1 ]]
[[ "$(grep -c '应用全部草稿.*default=n' "${TMP_DIR}/confirmations")" == 2 ]]
jq -e '(.policy.server.private_network_block|not)' "${TMP_DIR}/applied-draft.json" >/dev/null
[[ "$(project_digest)" == "${before_project}" && ! -e "${TMP_DIR}/forbidden-calls" ]]
printf 'Routing menu passed: read-only entry, isolated draft edits, explicit discard/apply and stable live assets\n'
