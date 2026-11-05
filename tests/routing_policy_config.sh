#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
# Allow this independently runnable regression during modular development,
# before the maintainer regenerates the committed standalone artifact.
source "${REPO_ROOT}/src/install/40-routing-policy.sh"
source "${REPO_ROOT}/src/install/20-config-ownership-and-apply.sh"
source "${REPO_ROOT}/src/install/22-config-generator-and-uninstall.sh"

fail() { printf 'routing policy config: %s\n' "$*" >&2; exit 1; }
policy_file=$(routing_policy_file_path)
policy=$(routing_policy_read_json)
routing_policy_validate_json "${policy}"
[[ ! -e "${policy_file}" ]] || fail 'reading defaults created policy state'
jq -e '.schema_version==2 and (.server.block_cn|not) and (has("client")|not) and (has("adblock")|not)' <<< "${policy}" >/dev/null

# Current policy renders only server-side China protection, scoped to managed
# listener tags and placed before any per-node or custom outbound decision.
blocked=$(jq -c '.server.block_cn=true | .server.rules=[
  {id:"force-native",kind:"domain_suffix",value:"fixture.invalid",action:"direct",enabled:true}]' <<< "${policy}")
rendered=$(routing_policy_render_server_json "${blocked}" '["node-a","node-b"]')
jq -e '.rule_sets|length==2' <<< "${rendered}" >/dev/null
jq -e '.protection_rules == [
  {inbound:["node-a","node-b"],rule_set:["sbv-block-geosite-cn"],action:"reject"},
  {inbound:["node-a","node-b"],action:"resolve",server:"local-dns"},
  {inbound:["node-a","node-b"],rule_set:["sbv-block-geoip-cn"],action:"reject"}] and
  .rules[3].outbound=="direct" and all(.rule_sets[];
    .http_client.detour=="direct" and .format=="binary" and .update_interval=="1d" and
    (.url|startswith("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/"))) and
  all(.rules[]; (has("ip_is_private")|not))' <<< "${rendered}" >/dev/null
routing_policy_render_server_json "${blocked}" '[]' |
  jq -e '.rules==[] and .rule_sets==[]' >/dev/null
if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
  jq -n --argjson rendered "${rendered}" '{
    dns:{servers:[{type:"local",tag:"local-dns"}]},
    inbounds:[{type:"mixed",tag:"node-a",listen:"127.0.0.1",listen_port:14301},
      {type:"mixed",tag:"node-b",listen:"127.0.0.1",listen_port:14302}],
    outbounds:[{type:"direct",tag:"direct"}],
    route:{rules:$rendered.rules,rule_set:$rendered.rule_sets,final:"direct",default_domain_resolver:"local-dns"}}
  ' > "${TMP_DIR}/block-cn.json"
  "${ROUTING_POLICY_TEST_REAL_CORE}" check -c "${TMP_DIR}/block-cn.json"
fi

# Fresh prompts must not require jq or silently enable external WARP setup.
jq() { return 91; }
routing_policy_prepare_install_defaults
[[ "${SB_ADVANCED_ROUTE}:${SB_ENABLE_WARP}:${SB_OUTBOUND_POLICY}" == n:n:default ]]
unset -f jq

# A historical ads marker is not evidence of actual private-address protection.
printf '%s\n' '{"route":{"rules":[{"geosite":"category-ads-all","action":"reject"}]}}' > "${SINGBOX_CONFIG_FILE}"
inferred=$(routing_policy_read_json)
jq -e '.schema_version==2 and (.server.block_cn | not)' <<< "${inferred}" >/dev/null
rm "${SINGBOX_CONFIG_FILE}"

for mutation in \
  '.unexpected=true' \
  '.adblock.url="http://example.com/ads.srs"' \
  '.adblock.allow=["bad\n.example"]' \
  '.server.rules=[{id:"rule",kind:"domain",value:"x.example",action:"shell",enabled:true}]' \
  '.server.rule_sets=[{tag:"bad",type:"local",format:"source",path:"/tmp/../secret",action:"reject",enabled:true,update_interval:"1d"}]'; do
  invalid=$(jq -c "${mutation}" <<< "${policy}")
  if routing_policy_validate_json "${invalid}"; then fail "unsafe policy accepted: ${mutation}"; fi
done
printf '%s\n' '$(touch must-not-execute)' > "${policy_file}"
if routing_policy_read_json >/dev/null 2>&1; then fail 'invalid JSON fell back to defaults'; fi
rm "${policy_file}"
printf '%s\n' "${policy}" > "${TMP_DIR}/outside-policy.json"
ln -s "${TMP_DIR}/outside-policy.json" "${policy_file}"
if routing_policy_read_json >/dev/null 2>&1; then fail 'symlinked policy accepted'; fi
rm "${policy_file}"

# Existing v1 files remain readable without changing their active protections.
policy=$(jq -cn '{schema_version:1,
 server:{private_network_block:true,adblock:false,warp_ai:true,warp_streaming:true,rules:[],rule_sets:[]},
 client:{lan_direct:true,cn_direct:true,adblock:false},adblock:{url:"",domains:[],allow:[]}}')
legacy_policy=${policy}
policy=$(jq -c '.server.adblock=true | .adblock.url="" | .adblock.domains=["ads.example","tracking.example"] | .adblock.allow=["allow.ads.example"]' <<< "${policy}")
ads=$(routing_policy_legacy_adblock_json "${policy}")
jq -e '.rule_sets[0].tag == "sbv-adblock-inline" and
  .rules[0].type == "logical" and .rules[0].mode == "and" and
  .rules[0].rules[1].invert == true and .rules[0].action == "reject" and
  all(.rules[]; (.outbound // "") != "direct")' <<< "${ads}" >/dev/null

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf 'sing-box version 1.14.2\n' ;;
  check)
    [[ "${2:-}" == -c && -f "${3:-}" ]]
    jq -e 'type == "object" and (.route.rules | type == "array")' "${3}" >/dev/null
    if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
      "${ROUTING_POLICY_TEST_REAL_CORE}" check -c "${3}" || exit $?
    fi
    printf 'checked\n' >> "${POLICY_CHECK_LOG:?}"
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sing-box"
export POLICY_CHECK_LOG="${TMP_DIR}/checks.log"

# Domain decisions retain their place before DNS. Resolve once at the first IP
# matcher, including opaque local/remote sources, for every supported action.
for action in direct warp reject; do
  ip_policy=$(jq -c --arg action "${action}" --arg path "${TMP_DIR}/ip-rules.json" '
    .server.private_network_block=false | .server.adblock=false |
    .server.rules=[
      {id:"domain-first",kind:"domain",value:"first.fixture.invalid",action:"reject",enabled:true},
      {id:"ip",kind:"ip_cidr",value:"1.1.1.0/24",action:$action,enabled:true},
      {id:"domain-last",kind:"domain_suffix",value:"last.fixture.invalid",action:"direct",enabled:true}] |
    .server.rule_sets=[{tag:"ip-source",type:"local",format:"source",path:$path,action:$action,enabled:true,update_interval:"1d"}]' <<< "${policy}")
  ip_render=$(routing_policy_render_server_json "${ip_policy}" '["probe-in"]')
  jq -e --arg action "${action}" '
    .protection_rules == [] and
    ([.rules[] | select(.action == "resolve")] | length) == 1 and
    .custom_rules[0].domain == ["first.fixture.invalid"] and
    .custom_rules[1] == {inbound:["probe-in"],action:"resolve",server:"local-dns"} and
    .custom_rules[2].ip_cidr == ["1.1.1.0/24"] and
    .custom_rules[3].domain_suffix == ["last.fixture.invalid"] and
    .custom_rules[4].rule_set == ["sbv-rule-ip-source"] and
    (if $action == "reject" then .custom_rules[2].action == "reject" and .custom_rules[4].action == "reject"
     else .custom_rules[2].outbound == (if $action == "warp" then "warp-ep" else "direct" end) and
       .custom_rules[4].outbound == .custom_rules[2].outbound end)' <<< "${ip_render}" >/dev/null
  for source_type in local remote; do
    source_policy=$(jq -c --arg source_type "${source_type}" '
      .server.rules |= map(select(.kind != "ip_cidr")) |
      if $source_type == "remote" then
        .server.rule_sets[0] |= (del(.path) | .type="remote" | .url="https://rules.fixture.invalid/ip.srs" | .format="binary")
      else . end' <<< "${ip_policy}")
    routing_policy_render_server_json "${source_policy}" '["probe-in"]' |
      jq -e '.custom_rules[0].domain == ["first.fixture.invalid"] and
        .custom_rules[1].domain_suffix == ["last.fixture.invalid"] and
        .custom_rules[2].action == "resolve" and .custom_rules[3].rule_set == ["sbv-rule-ip-source"]' >/dev/null
  done
done
disabled_ip_policy=$(jq -c '(.server.rules[] | select(.kind == "ip_cidr")).enabled=false |
  .server.rule_sets[0].enabled=false' <<< "${ip_policy}")
routing_policy_render_server_json "${disabled_ip_policy}" '["probe-in"]' |
  jq -e 'all(.rules[]; .action != "resolve")' >/dev/null
remote_ads_policy=$(jq -c '.server.adblock=true | .adblock.url="https://rules.fixture.invalid/ads.srs"' <<< "${ip_policy}")
routing_policy_render_server_json "${remote_ads_policy}" '["probe-in"]' |
  jq -e '.protection_rules[0].action == "resolve" and .protection_rules[1].action == "reject" and
    ([.rules[] | select(.action == "resolve")] | length) == 1 and
    .custom_rules[0].domain == ["first.fixture.invalid"]' >/dev/null
private_ip_policy=$(jq -c '.server.private_network_block=true' <<< "${remote_ads_policy}")
routing_policy_render_server_json "${private_ip_policy}" '["probe-in"]' |
  jq -e '.protection_rules[0].action == "resolve" and .protection_rules[1].ip_is_private and
    .protection_rules[2].action == "reject" and
    ([.rules[] | select(.action == "resolve")] | length) == 1' >/dev/null

# Exercise the real generator/merge/graph pipeline with controlled protocol
# fragments and a local check double; actual core acceptance is separate.
validate_live_inbound_inventory() { :; }
list_effective_protocols() { printf 'mixed\n'; }
load_protocol_state() { :; }
build_inbound_for_protocol() {
  printf '%s\n' \
    '{"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":13080}' \
    '{"type":"mixed","tag":"mixed-second","listen":"127.0.0.1","listen_port":13081}'
}
build_certificate_provider_for_protocol() { :; }
build_protocol_route_rules() {
  printf '%s\n' '[{"inbound":"mixed-in","action":"sniff"},{"inbound":"mixed-in","action":"route","outbound":"direct"},{"inbound":"mixed-second","action":"sniff"}]'
}
register_warp() {
  cat > "${SB_WARP_KEY_FILE}" <<'EOF'
WARP_PRIV_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
WARP_V4=172.16.0.2
WARP_V6=2606:4700:110:876a::2
WARP_CLIENT_ID=AAAA
EOF
}
# Existing prepared credentials are read by generation; provider registration
# is owned exclusively by explicit network application.
register_warp

routing_policy_component_precedence_test() (
  local workspace base_state state rules action target before cases='[]' name fresh_policy
  [[ "${SB_PROJECT_DIR}" == "${TMP_DIR}/project" ]]
  workspace=$(mktemp -d "${TMP_DIR}/component-precedence.XXXXXX")
  cp -a -- "${SB_PROJECT_DIR}" "${workspace}/original-project"
  trap 'rm -rf -- "${SB_PROJECT_DIR}"; mv -- "${workspace}/original-project" "${SB_PROJECT_DIR}"; rm -rf -- "${workspace}"' EXIT
  rm -rf -- "${SB_PROJECT_DIR}"
  mkdir -p -- "${SB_PROJECT_DIR}"
  fresh_policy=${legacy_policy}
  printf '%s\n' "${fresh_policy}" > "${policy_file}"
  chmod 600 "${policy_file}"
  base_state=$(managed_component_state_default_json | jq -c '.components=[
    {id:"component-in",role:"inbound",type:"direct",tag:"component-in",enabled:true,
     route_rules:[],config:{listen:"127.0.0.1",listen_port:13082}},
    {id:"component-out",role:"outbound",type:"direct",tag:"component-out",enabled:true,route_rules:[],config:{}}]')
  managed_component_state_validate_json "${base_state}"
  printf '%s\n' "${base_state}" > "${SB_COMPONENT_STATE_FILE}"
  chmod 600 "${SB_COMPONENT_STATE_FILE}"
  SB_ADVANCED_ROUTE=y
  SB_ENABLE_WARP=n
  SB_WARP_ROUTE_MODE=selective
  SB_OUTBOUND_STACK_MODE=prefer_ipv4
  generate_config >/dev/null
  cp -p -- "${SINGBOX_CONFIG_FILE}" "${workspace}/base-config.json"
  cp -p -- "${SB_PROJECT_DIR}/managed-config.generated.json" "${workspace}/base-generated.json"
  for action in route bypass reject hijack-dns; do
    for target in mixed-in component-in; do
      cp -p -- "${workspace}/base-config.json" "${SINGBOX_CONFIG_FILE}"
      cp -p -- "${workspace}/base-generated.json" "${SB_PROJECT_DIR}/managed-config.generated.json"
      rules=$(jq -cn --arg action "${action}" --arg target "${target}" '[
        {inbound:["component-in"],domain:["keep.fixture.invalid"],action:"reject"},
        ({inbound:[$target],action:$action} +
          (if $action == "hijack-dns" then {protocol:["dns"]}
           elif $action == "bypass" then {ip_cidr:["127.0.0.0/8"]}
           else {domain_suffix:["localhost"]} end) +
          (if $action == "route" or $action == "bypass" then {outbound:"direct"} else {} end))]')
      state=$(jq -c --argjson rules "${rules}" '.components[1].route_rules=$rules' <<< "${base_state}")
      managed_component_state_validate_json "${state}"
      printf '%s\n' "${state}" > "${SB_COMPONENT_STATE_FILE}"
      name="${action}-${target}"
      if [[ "${target}" == mixed-in && "${action}" =~ ^(route|bypass)$ ]]; then
        # The exact component-generated rule really is core-valid. Owning the
        # record must not grant it priority over private/address ad protection.
        jq --argjson rules "${rules}" '.route.rules=$rules + .route.rules' \
          "${workspace}/base-config.json" > "${workspace}/${name}.json"
        "${SINGBOX_BIN_PATH}" check -c "${workspace}/${name}.json"
        before=$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_COMPONENT_STATE_FILE}")
        if generate_config > "${workspace}/rejected.out" 2> "${workspace}/rejected.err"; then
          fail "owned component bypassed protection: ${name}"
        fi
        grep -Fq routing_policy_order_conflict "${workspace}/rejected.err"
        [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_COMPONENT_STATE_FILE}")" == "${before}" ]]
      else
        generate_config >/dev/null
        jq -e --argjson rules "${rules}" '.route.rules[:2] == $rules' "${SINGBOX_CONFIG_FILE}" >/dev/null
        cp -- "${SINGBOX_CONFIG_FILE}" "${workspace}/${name}.json"
      fi
      if [[ "${action}" == route ]]; then
        cases=$(jq -c --arg file "${workspace}/${name}.json" --arg name "${name}" \
          --arg host "$([[ "${action}" == direct ]] && printf '127.0.0.1' || printf localhost)" \
          --argjson reaches_marker "$([[ "${target}" == mixed-in ]] && printf true || printf false)" \
          '. + [{file:$file,name:$name,host:$host,reaches_marker:$reaches_marker}]' <<< "${cases}")
      fi
    done
  done
  # The core treats an explicit empty action as legacy route. It must follow
  # the same ordering checks as a missing/null action instead of appearing to
  # be a non-terminal manual annotation.
  for action in '""' null absent; do
    cp -p -- "${workspace}/base-generated.json" "${SB_PROJECT_DIR}/managed-config.generated.json"
    printf '%s\n' "${base_state}" > "${SB_COMPONENT_STATE_FILE}"
    if [[ "${action}" == absent ]]; then
      rules='[{"inbound":["mixed-in"],"outbound":"direct"}]'
    else
      rules=$(jq -cn --argjson action "${action}" '[{inbound:["mixed-in"],action:$action,outbound:"direct"}]')
    fi
    jq --argjson rules "${rules}" '.route.rules=$rules + .route.rules' \
      "${workspace}/base-config.json" > "${SINGBOX_CONFIG_FILE}"
    "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"
    before=$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_COMPONENT_STATE_FILE}")
    if generate_config > "${workspace}/empty-action.out" 2> "${workspace}/empty-action.err"; then
      fail "legacy ${action} manual route bypassed protection"
    fi
    grep -Fq routing_policy_order_conflict "${workspace}/empty-action.err"
    [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_COMPONENT_STATE_FILE}")" == "${before}" ]]
    jq '.route.rules |= map(select(.ip_is_private != true))' \
      "${workspace}/base-generated.json" > "${workspace}/empty-action-prior.json"
    jq '.route.rules |= map(select(.ip_is_private != true))' \
      "${SINGBOX_CONFIG_FILE}" > "${workspace}/empty-action-original.json"
    chmod 600 "${workspace}/empty-action-prior.json"
    if routing_policy_place_new_generated_rules "${workspace}/base-generated.json" "${SINGBOX_CONFIG_FILE}" \
      "${workspace}/empty-action-prior.json" "${workspace}/empty-action-original.json" '["mixed-in","mixed-second"]' \
      > "${workspace}/empty-action-placed.json" 2> "${workspace}/empty-action-place.err"; then
      fail "new protection insertion accepted legacy ${action} manual route"
    fi
    (
      load_current_config_state() { :; }
      systemctl() {
        case "${1:-}" in
          is-active) [[ "${2:-}" == --quiet ]] || printf 'inactive\n'; return 3 ;;
          show) printf 'inactive\n' ;;
          stop) : ;;
          *) return 93 ;;
        esac
      }
      printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
      routing_draft_create "${workspace}/empty-action-draft.json"
      jq '.policy.server.rules=[{id:"change",kind:"domain",value:"change.fixture.invalid",action:"reject",enabled:true}]' \
        "${workspace}/empty-action-draft.json" > "${workspace}/empty-action-edit.json"
      before=$(routing_state_fingerprint)
      if routing_policy_apply "${workspace}/empty-action-edit.json" > "${workspace}/empty-action-apply.out" 2> "${workspace}/empty-action-apply.err"; then
        fail "draft applied a legacy ${action} route ahead of protection"
      fi
      grep -Fq routing_policy_order_conflict "${workspace}/empty-action-apply.err"
      [[ "$(routing_state_fingerprint)" == "${before}" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
    )
    cp -- "${SINGBOX_CONFIG_FILE}" "${workspace}/empty-action-${action//\"/empty}.json"
    cases=$(jq -c --arg file "${workspace}/empty-action-${action//\"/empty}.json" \
      '. + [{file:$file,name:"legacy empty/null/missing action",reaches_marker:true}]' <<< "${cases}")
  done
  if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
    printf '%s\n' "${cases}" > "${workspace}/cases.json"
    python3 - "${ROUTING_POLICY_TEST_REAL_CORE}" "${workspace}/cases.json" <<'PY'
import http.server, json, pathlib, socket, subprocess, sys, threading, time

core, cases_file = sys.argv[1:]
marker = b"sbv-component-private-marker"
class Marker(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(marker)
    def log_message(self, *_args):
        pass

httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Marker)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
try:
    for case in json.loads(pathlib.Path(cases_file).read_text()):
        config = json.loads(pathlib.Path(case["file"]).read_text())
        config["inbounds"] = [item for item in config["inbounds"] if item["tag"] == "mixed-in"]
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        config["inbounds"][0]["listen_port"] = port
        config_file = pathlib.Path(case["file"]).with_suffix(".runtime.json")
        config_file.write_text(json.dumps(config))
        subprocess.run([core, "check", "-c", str(config_file)], check=True, capture_output=True)
        with config_file.with_suffix(".log").open("w") as log:
            process = subprocess.Popen([core, "run", "-c", str(config_file)], stdout=log, stderr=log)
            try:
                for _ in range(60):
                    if process.poll() is not None:
                        raise AssertionError(config_file.with_suffix(".log").read_text())
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=0.05):
                            break
                    except OSError:
                        time.sleep(0.05)
                else:
                    raise AssertionError("component precedence proxy did not start")
                host = case.get("host", "localhost")
                result = subprocess.run(["curl", "--noproxy", "", "--max-time", "3", "-sS", "--proxy", f"socks5h://127.0.0.1:{port}", f"http://{host}:{httpd.server_port}/"], capture_output=True)
                assert (result.returncode == 0 and result.stdout == marker) == case["reaches_marker"], (case, result.stderr, config_file.with_suffix(".log").read_text())
            finally:
                process.terminate()
                process.wait(5)
finally:
    httpd.shutdown()
    httpd.server_close()
PY
  fi
  printf 'Component and legacy-action precedence, disjoint scope and core runtime controls passed\n'
)

routing_policy_component_precedence_test
if [[ "${1:-}" == --component-precedence ]]; then exit 0; fi
SB_ADVANCED_ROUTE=y
SB_ENABLE_WARP=n
SB_WARP_ROUTE_MODE=selective
SB_OUTBOUND_STACK_MODE=prefer_ipv4
generate_config >/dev/null

# No policy file preserves the pre-existing legacy order and global scope.
jq -e '([.route.rules | to_entries[] | select(.value.outbound == "direct") | .key][0]) <
  ([.route.rules | to_entries[] | select(.value.ip_is_private == true) | .key][0]) and
  any(.route.rules[]; .ip_is_private == true and (has("inbound") | not)) and
  (.route.rule_set | all(.[]; (.tag | startswith("sbv-adblock-") | not)))' "${SINGBOX_CONFIG_FILE}" >/dev/null

policy=$(jq -c '.server.rules=[{id:"custom-warp",kind:"domain_suffix",value:"via-warp.example",action:"warp",enabled:true}]' <<< "${policy}")
routing_policy_requires_warp "${policy}"
printf '%s\n' "${policy}" > "${policy_file}"
chmod 600 "${policy_file}"
generate_config >/dev/null
jq -e '
  any(.endpoints[]; .tag == "warp-ep") and .route.final == "direct" and
  any(.route.rule_set[]; .tag == "sbv-adblock-inline") and
  ([.route.rules | to_entries[] | select(.value.action == "resolve") | .key][0]) <
    ([.route.rules | to_entries[] | select(.value.ip_is_private == true) | .key][0]) and
  ([.route.rules | to_entries[] | select(.value.ip_is_private == true) | .key][0]) <
    ([.route.rules | to_entries[] | select(.value.inbound == "mixed-in" and .value.outbound == "direct") | .key][0]) and
  ([.route.rules | to_entries[] | select(.value.action == "reject" and .value.type == "logical") | .key][0]) <
    ([.route.rules | to_entries[] | select(.value.inbound == "mixed-in" and .value.outbound == "direct") | .key][0]) and
  any(.route.rules[]; .domain_suffix == ["via-warp.example"] and .inbound == ["mixed-in","mixed-second"] and .outbound == "warp-ep") and
  all(.route.rules[] | select(.ip_is_private == true); .inbound == ["mixed-in","mixed-second"])
' "${SINGBOX_CONFIG_FILE}" >/dev/null

component_state=$(managed_component_state_default_json)
managed_component_live_route_rule_sets_match_state "${SINGBOX_CONFIG_FILE}" "${component_state}"
jq '.route.rule_set += [{type:"inline",tag:"sbv-adblock-forged",rules:[]}]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/forged.json"
if managed_component_live_route_rule_sets_match_state "${TMP_DIR}/forged.json" "${component_state}"; then
  fail 'arbitrary policy-like prefix was treated as owned'
fi
jq '(.route.rule_set[] | select(.tag == "sbv-adblock-inline")).rules=[{domain_suffix:["forged.example"]}]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/changed-set.json"
if managed_component_live_route_rule_sets_match_state "${TMP_DIR}/changed-set.json" "${component_state}"; then
  fail 'changed same-tag source was treated as owned'
fi

# Typed lifecycle updates do not call the global generator. The projection
# must extend scope for new tags, remove deleted tags, and seed an empty
# retained inventory without claiming any manual listener.
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=vless-reality\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\n' > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
before_index=$(sha256sum "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")
[[ "$(routing_policy_registered_tags_json mixed)" == '["vless-in"]' ]] || fail 'registered legacy tag was not collected'
[[ "$(sha256sum "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" == "${before_index}" ]] || fail 'registered tag collection changed state'
rm "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

# A component registered before this feature keeps exact ownership even when
# its legitimate tag uses the new policy namespace and appears in a baseline.
component_record='{"id":"existing-rules","role":"rule_set","type":"inline","tag":"sbv-rule-existing","enabled":true,"route_rules":[],"config":{"rules":[{"domain_suffix":["component.example"]}]}}'
existing_component_state=$(jq -c --argjson record "${component_record}" '.components=[$record]' <<< "${component_state}")
managed_component_state_validate_json "${existing_component_state}"
cp -p "${SB_PROJECT_DIR}/managed-config.generated.json" "${TMP_DIR}/baseline.saved"
mv "${policy_file}" "${TMP_DIR}/policy.saved"
jq -n --argjson record "${component_record}" '{route:{rule_set:[$record.config + {type:$record.type,tag:$record.tag}]}}' > "${TMP_DIR}/legacy-component.json"
cp "${TMP_DIR}/legacy-component.json" "${SB_PROJECT_DIR}/managed-config.generated.json"
chmod 600 "${SB_PROJECT_DIR}/managed-config.generated.json"
managed_component_live_route_rule_sets_match_state "${TMP_DIR}/legacy-component.json" "${existing_component_state}"
coexisting_component_projection "${TMP_DIR}/legacy-component.json" "${existing_component_state}" | \
  jq -e '.route.rule_set[0].tag == "sbv-rule-existing"' >/dev/null
collision_policy=$(jq -c '.server.rule_sets=[{tag:"existing",type:"remote",format:"binary",url:"https://rules.example/rules.srs",action:"reject",enabled:true,update_interval:"1d"}]' <<< "${policy}")
if routing_policy_owned_rule_sets_json "${collision_policy}" "${existing_component_state}" >/dev/null; then
  fail 'policy took over an existing component tag'
fi
mv "${TMP_DIR}/policy.saved" "${policy_file}"
mv "${TMP_DIR}/baseline.saved" "${SB_PROJECT_DIR}/managed-config.generated.json"
printf '%s\n' '{"instances":[{"tag":"mixed-in","outbound_policy":"direct"},{"tag":"mixed-second","outbound_policy":"default"}]}' > "${TMP_DIR}/old-store.json"
printf '%s\n' '{"instances":[{"tag":"mixed-in","outbound_policy":"direct"},{"tag":"mixed-second","outbound_policy":"default"},{"tag":"mixed-third","outbound_policy":"default"}]}' > "${TMP_DIR}/new-store.json"
jq '.inbounds += [{type:"mixed",tag:"mixed-third",listen:"127.0.0.1",listen_port:13083}] |
  .route.rules=[{inbound:"mixed-third",action:"sniff"}] + .route.rules' "${SINGBOX_CONFIG_FILE}" |
  routing_policy_project_instance_candidate mixed "${TMP_DIR}/old-store.json" "${TMP_DIR}/new-store.json" > "${TMP_DIR}/projected-add.json"
jq -e 'all(.route.rules[] | select(.ip_is_private == true or .type == "logical");
  (.inbound // .rules[0].inbound) == ["mixed-in","mixed-second","mixed-third"]) and
  any(.route.rules[]; .domain_suffix == ["via-warp.example"] and (.inbound | index("mixed-third")) != null)' \
  "${TMP_DIR}/projected-add.json" >/dev/null
validate_managed_component_graph "${TMP_DIR}/projected-add.json"
"${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/projected-add.json"

# Rebuilding the managed chain may not move an interleaved operator rule
# across an existing owned rule even if that listener has independent scope.
jq '.route.rules = (.route.rules[:1] + [{inbound:"operator-other",action:"route",outbound:"direct"}] + .route.rules[1:])' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/interleaved.json"
if routing_policy_project_instance_candidate mixed "${TMP_DIR}/old-store.json" "${TMP_DIR}/old-store.json" \
  < "${TMP_DIR}/interleaved.json" > "${TMP_DIR}/interleaved-result.json" 2> "${TMP_DIR}/interleaved.err"; then
  fail 'typed projection moved an interleaved manual rule'
fi
grep -Fq routing_policy_instance_projection_conflict "${TMP_DIR}/interleaved.err"

printf '%s\n' '{"instances":[]}' > "${TMP_DIR}/empty-store.json"
jq '.inbounds=[] | .route.rules |= map(select((.inbound | type) != "string"))' "${TMP_DIR}/projected-add.json" |
  routing_policy_project_instance_candidate mixed "${TMP_DIR}/new-store.json" "${TMP_DIR}/empty-store.json" > "${TMP_DIR}/projected-empty.json"
jq -e '.inbounds == [] and .route.rules == [] and .route.rule_set == []' "${TMP_DIR}/projected-empty.json" >/dev/null
validate_managed_component_graph "${TMP_DIR}/projected-empty.json"
"${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/projected-empty.json"

printf '%s\n' '{"instances":[{"tag":"mixed-recreated"}]}' > "${TMP_DIR}/recreated-store.json"
jq '.inbounds=[{type:"mixed",tag:"mixed-recreated",listen:"127.0.0.1",listen_port:13084}] |
  .route.rules=[{inbound:"mixed-recreated",action:"sniff"}]' "${TMP_DIR}/projected-empty.json" |
  routing_policy_project_instance_candidate mixed "${TMP_DIR}/empty-store.json" "${TMP_DIR}/recreated-store.json" > "${TMP_DIR}/projected-recreated.json"
jq -e 'any(.route.rules[]; .ip_is_private == true and .inbound == ["mixed-recreated"]) and
  any(.route.rule_set[]; .tag == "sbv-adblock-inline")' "${TMP_DIR}/projected-recreated.json" >/dev/null
validate_managed_component_graph "${TMP_DIR}/projected-recreated.json"
"${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/projected-recreated.json"

printf '%s\n' '{"instances":[]}' > "${TMP_DIR}/old-shadowtls.json"
printf '%s\n' '{"instances":[{"tag":"shadowtls-outer","detour":{"tag":"shadowtls-inner"}}]}' > "${TMP_DIR}/new-shadowtls.json"
jq '.inbounds=[{type:"mixed",tag:"shadowtls-inner",listen:"127.0.0.1",listen_port:13085}] |
  .route.rules=[{inbound:"shadowtls-inner",action:"sniff"}]' "${TMP_DIR}/projected-empty.json" |
  routing_policy_project_instance_candidate shadowtls "${TMP_DIR}/old-shadowtls.json" "${TMP_DIR}/new-shadowtls.json" > "${TMP_DIR}/projected-shadowtls.json"
jq -e 'all(.route.rules[] | select(.ip_is_private == true or .type == "logical");
  (.inbound // .rules[0].inbound) == ["shadowtls-inner"])' "${TMP_DIR}/projected-shadowtls.json" >/dev/null
"${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/projected-shadowtls.json"

# A separate operator listener/rule survives with its original position.
jq '.inbounds += [{type:"mixed",tag:"operator-mixed",listen:"127.0.0.1",listen_port:13082}] |
  .route.rules=[{inbound:"operator-mixed",action:"route",outbound:"direct"}] + .route.rules' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual.json"
mv "${TMP_DIR}/manual.json" "${SINGBOX_CONFIG_FILE}"
generate_config >/dev/null
jq -e '.route.rules[0].inbound == "operator-mixed" and
  any(.inbounds[]; .tag == "operator-mixed") and
  all(.route.rules[] | select(.ip_is_private == true); (.inbound | index("operator-mixed")) == null)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null

cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/scope-live.json"
scope_rules='[
  {inbound:[],domain_suffix:["localhost"],action:"route",outbound:"direct"},
  {inbound:null,domain_suffix:["localhost"],action:"route",outbound:"direct"},
  {domain_suffix:["localhost"],action:"route",outbound:"direct"},
  {inbound:["operator-mixed"],invert:true,action:"route",outbound:"direct"},
  {type:"logical",mode:"or",rules:[{inbound:["operator-mixed"]},{domain:["localhost"]}],action:"route",outbound:"direct"},
  {type:"logical",mode:"and",rules:[{inbound:["operator-mixed"],invert:true},{domain:["localhost"]}],action:"route",outbound:"direct"},
  {type:"logical",mode:"and",invert:true,rules:[{inbound:["operator-mixed"]},{domain:["localhost"]}],action:"route",outbound:"direct"},
  {type:"logical",mode:"or",rules:[{type:"logical",mode:"and",rules:[{inbound:["operator-mixed"]},{domain:["localhost"]}]},{inbound:[],domain:["localhost"]}],action:"route",outbound:"direct"}
]'
while IFS= read -r manual_rule; do
  jq --argjson rule "${manual_rule}" '.route.rules=[$rule] + .route.rules' \
    "${TMP_DIR}/scope-live.json" > "${SINGBOX_CONFIG_FILE}"
  before=$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" "${policy_file}")
  if generate_config > "${TMP_DIR}/scope.out" 2> "${TMP_DIR}/scope.err"; then
    fail "manual overlapping scope was accepted: ${manual_rule}"
  fi
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" "${policy_file}")" == "${before}" ]]
  grep -Fq routing_policy_order_conflict "${TMP_DIR}/scope.err"
  if routing_policy_project_instance_candidate mixed "${TMP_DIR}/old-store.json" "${TMP_DIR}/old-store.json" \
    < "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/scope-projected.json" 2> "${TMP_DIR}/scope-project.err"; then
    fail "typed projection accepted overlapping manual scope: ${manual_rule}"
  fi
  grep -Fq routing_policy_instance_projection_conflict "${TMP_DIR}/scope-project.err"
  # Directly exercise insertion of a new generated rule as well as the final
  # order guard, so a global manual rule can never become an owned scope label.
  jq '.route.rules |= map(select(.ip_is_private != true))' \
    "${SB_PROJECT_DIR}/managed-config.generated.json" > "${TMP_DIR}/scope-prior.json"
  chmod 600 "${TMP_DIR}/scope-prior.json"
  jq '.route.rules |= map(select(.ip_is_private != true))' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/scope-original.json"
  if routing_policy_place_new_generated_rules "${SB_PROJECT_DIR}/managed-config.generated.json" \
    "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/scope-prior.json" "${TMP_DIR}/scope-original.json" '["mixed-in","mixed-second"]' \
    > "${TMP_DIR}/scope-placed.json" 2> "${TMP_DIR}/scope-place.err"; then
    fail "new-rule insertion accepted overlapping manual scope: ${manual_rule}"
  fi
  # Run the public draft/apply boundary too: a rejected generated candidate
  # must restore policy/assets/snapshot state and the original manual order.
  (
    load_current_config_state() { :; }
    systemctl() {
      case "${1:-}" in
        is-active) [[ "${2:-}" == --quiet ]] || printf 'inactive\n'; return 3 ;;
        show) printf 'inactive\n' ;;
        stop) : ;;
        *) printf 'unexpected scope-test service operation: %s\n' "$*" >&2; return 93 ;;
      esac
    }
    printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
    routing_draft_create "${TMP_DIR}/scope-draft.json"
    jq '.policy.server.block_cn=true' "${TMP_DIR}/scope-draft.json" > "${TMP_DIR}/scope-edit.json"
    before=$(routing_state_fingerprint)
    if routing_policy_apply "${TMP_DIR}/scope-edit.json" > "${TMP_DIR}/scope-apply.out" 2> "${TMP_DIR}/scope-apply.err"; then
      fail "draft apply accepted overlapping manual scope: ${manual_rule}"
    fi
    if ! grep -Fq routing_policy_order_conflict "${TMP_DIR}/scope-apply.err"; then
      cat "${TMP_DIR}/scope-apply.err" >&2
      fail 'draft apply did not reach the ordering guard'
    fi
    if [[ "$(routing_state_fingerprint)" != "${before}" || -e "${SB_ROUTING_TRANSACTION_DIR}" ]]; then
      cat "${TMP_DIR}/scope-apply.err" >&2
      fail 'draft apply did not restore the original project state'
    fi
  )
done < <(jq -cn "${scope_rules}[]")

# Positive nonempty scopes, including an AND with a proven disjoint child,
# stay in their original position rather than being moved around filters.
scope_safe_rules='[
  {inbound:["operator-mixed"],action:"route",outbound:"direct"},
  {type:"logical",mode:"and",rules:[{inbound:["operator-mixed"]},{domain:["localhost"]}],action:"route",outbound:"direct"}
]'
while IFS= read -r manual_rule; do
  jq --argjson rule "${manual_rule}" '.route.rules=[$rule] + .route.rules' \
    "${TMP_DIR}/scope-live.json" > "${SINGBOX_CONFIG_FILE}"
  generate_config >/dev/null
  jq -e --argjson rule "${manual_rule}" '.route.rules[0] == $rule' "${SINGBOX_CONFIG_FILE}" >/dev/null
  routing_policy_project_instance_candidate mixed "${TMP_DIR}/old-store.json" "${TMP_DIR}/old-store.json" \
    < "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/scope-safe-projected.json"
  jq -e --argjson rule "${manual_rule}" '.route.rules[0] == $rule' "${TMP_DIR}/scope-safe-projected.json" >/dev/null
done < <(jq -cn "${scope_safe_rules}[]")
cp -p "${TMP_DIR}/scope-live.json" "${SINGBOX_CONFIG_FILE}"

# An unscoped manual terminating rule cannot precede filtering for managed
# nodes. Refuse publication instead of moving or deleting the operator rule.
jq '.route.rules=[{domain_suffix:["manual.example"],action:"route",outbound:"direct"}] + .route.rules' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual-conflict.json"
mv "${TMP_DIR}/manual-conflict.json" "${SINGBOX_CONFIG_FILE}"
before=$(sha256sum "${SINGBOX_CONFIG_FILE}")
if generate_config > "${TMP_DIR}/conflict.out" 2> "${TMP_DIR}/conflict.err"; then
  fail 'manual rule bypassing policy protection was accepted'
fi
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before}" ]] || fail 'conflict changed operator configuration'
grep -Fq routing_policy_order_conflict "${TMP_DIR}/conflict.err"
[[ -s "${POLICY_CHECK_LOG}" ]] || fail 'generator did not invoke candidate validation'

# Exercise the new phase through global generation, a repeated ownership merge,
# and typed inventory projection. Node-specific egress stays ahead of custom
# matching, while an independently scoped manual rule stays in its exact place.
(
  rm -f -- "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
  ip_policy=$(jq -c '.server.private_network_block=false | .server.adblock=false | .server.rule_sets=[] |
    .server.rules=[
      {id:"first",kind:"domain",value:"first.fixture.invalid",action:"reject",enabled:true},
      {id:"ip",kind:"ip_cidr",value:"1.1.1.0/24",action:"warp",enabled:true}]' <<< "${policy}")
  printf '%s\n' "${ip_policy}" > "${policy_file}"
  SB_ADVANCED_ROUTE=n
  generate_config >/dev/null
  jq -e 'all(.route.rules[]; .ip_is_private != true) and
    ([.route.rules[] | select(.action == "resolve")] | length) == 1 and
    ([.route.rules | to_entries[] | select(.value.inbound == "mixed-in" and .value.action == "route") | .key][0]) <
      ([.route.rules | to_entries[] | select(.value.domain == ["first.fixture.invalid"]) | .key][0]) and
    ([.route.rules | to_entries[] | select(.value.domain == ["first.fixture.invalid"]) | .key][0]) <
      ([.route.rules | to_entries[] | select(.value.action == "resolve") | .key][0]) and
    ([.route.rules | to_entries[] | select(.value.action == "resolve") | .key][0]) <
      ([.route.rules | to_entries[] | select(.value.ip_cidr == ["1.1.1.0/24"] and .value.outbound == "warp-ep") | .key][0])' \
    "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq '.inbounds += [{type:"mixed",tag:"operator-mixed",listen:"127.0.0.1",listen_port:13082}] |
    .route.rules=[{inbound:"operator-mixed",action:"route",outbound:"direct"}] + .route.rules' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/ip-manual.json"
  mv "${TMP_DIR}/ip-manual.json" "${SINGBOX_CONFIG_FILE}"
  generate_config >/dev/null
  jq -e '.route.rules[0] == {inbound:"operator-mixed",action:"route",outbound:"direct"}' \
    "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq '.inbounds += [{type:"mixed",tag:"mixed-third",listen:"127.0.0.1",listen_port:13083}] |
    .route.rules=[{inbound:"mixed-third",action:"sniff"}] + .route.rules' "${SINGBOX_CONFIG_FILE}" |
    routing_policy_project_instance_candidate mixed "${TMP_DIR}/old-store.json" "${TMP_DIR}/new-store.json" \
    > "${TMP_DIR}/ip-projected.json"
  jq -e '.route.rules[0] == {inbound:"operator-mixed",action:"route",outbound:"direct"} and
    ([.route.rules[] | select(.action == "resolve")] | length) == 1 and
    all(.route.rules[] | select(.action == "resolve" or .ip_cidr == ["1.1.1.0/24"]);
      .inbound == ["mixed-in","mixed-second","mixed-third"])' "${TMP_DIR}/ip-projected.json" >/dev/null
  validate_managed_component_graph "${TMP_DIR}/ip-projected.json"
  "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/ip-projected.json"
)

if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
  runtime_policy=$(jq -c '.adblock.url="" | .adblock.domains=["ads.fixture.invalid"] |
    .adblock.allow=["allow.ads.fixture.invalid"]' <<< "${policy}")
  routing_policy_render_server_json "${runtime_policy}" '["probe-in"]' > "${TMP_DIR}/runtime-policy.json"
  printf '%s\n' '{"version":3,"rules":[{"ip_cidr":["127.0.0.0/8","1.1.1.0/24"]}]}' > "${TMP_DIR}/ip-rules.json"
  "${ROUTING_POLICY_TEST_REAL_CORE}" rule-set compile --output "${TMP_DIR}/ip-rules.srs" "${TMP_DIR}/ip-rules.json"
  runtime_ip_policies='{}'
  for action in direct warp reject; do
    for source_type in cidr source binary; do
      custom_policy=$(jq -c --arg action "${action}" --arg source_type "${source_type}" \
        --arg path "${TMP_DIR}/ip-rules.$([[ "${source_type}" == binary ]] && printf srs || printf json)" '
        .server.private_network_block=false | .server.adblock=false | .server.rule_sets=[] |
        .server.rules=[{id:"domain-first",kind:"domain",value:"first.fixture.invalid",action:"reject",enabled:true}] |
        if $source_type == "cidr" then
          .server.rules += [{id:"ip",kind:"ip_cidr",value:"127.0.0.0/8",action:$action,enabled:true},
            {id:"public-ip",kind:"ip_cidr",value:"1.1.1.0/24",action:$action,enabled:true}]
        else .server.rule_sets=[{tag:"ip-source",type:"local",format:$source_type,path:$path,action:$action,enabled:true,update_interval:"1d"}]
        end |
        .server.rules += [{id:"domain-last",kind:"domain",value:"last.fixture.invalid",action:"reject",enabled:true}]' <<< "${runtime_policy}")
      custom_render=$(routing_policy_render_server_json "${custom_policy}" '["probe-in"]')
      runtime_ip_policies=$(jq -c --arg name "${action}-${source_type}" --argjson rendered "${custom_render}" \
        '.[$name]=$rendered' <<< "${runtime_ip_policies}")
    done
  done
  printf '%s\n' "${runtime_ip_policies}" > "${TMP_DIR}/runtime-ip-policies.json"
  jq -cn "{overlap:${scope_rules},disjoint:${scope_safe_rules}}" > "${TMP_DIR}/runtime-scope-rules.json"
  python3 "${REPO_ROOT}/tests/routing_policy_private_runtime.py" "${ROUTING_POLICY_TEST_REAL_CORE}" \
    "${TMP_DIR}/runtime-policy.json" "${TMP_DIR}/runtime-ip-policies.json" "${TMP_DIR}/runtime-scope-rules.json"
fi

printf 'Routing policy schema, generation, scope, ownership and conflict checks passed\n'
