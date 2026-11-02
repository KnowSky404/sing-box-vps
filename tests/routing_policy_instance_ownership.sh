#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${ROUTING_POLICY_TEST_REAL_CORE:-${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}}
[[ "$("${core}" version | head -n1)" == 'sing-box version 1.14.2' ]] || {
  printf 'Set ROUTING_POLICY_TEST_REAL_CORE to the real sing-box 1.14.2 executable\n' >&2
  exit 1
}
ln -s "${core}" "${TMP_DIR}/bin/sing-box"
source_testable_install
# Prefer current modules during development; the standalone artifact remains
# independently testable in a private fixture containing no module sources.
if [[ -f "${REPO_ROOT}/src/install/40-routing-policy.sh" ]]; then
  source "${REPO_ROOT}/src/install/40-routing-policy.sh"
  source "${REPO_ROOT}/src/install/32-instance-transactions.sh"
fi
set -E
trap 'printf "instance ownership test failed at line %s\n" "${LINENO}" >&2' ERR
[[ "${SB_PROJECT_DIR}" == "${TMP_DIR}/project" &&
   "${SINGBOX_BIN_PATH}" == "${TMP_DIR}/bin/sing-box" &&
   "${SINGBOX_SERVICE_FILE}" == "${TMP_DIR}/sing-box.service" ]]

fail() { printf 'instance ownership: %s\n' "$*" >&2; exit 1; }
systemctl() {
  case "${1:-}" in
    show) printf 'inactive\n' ;;
    is-active) [[ "${2:-}" == --quiet ]] || printf 'inactive\n'; return 3 ;;
    stop) : ;;
    *) printf 'unexpected ownership-test service call: %s\n' "$*" >&2; return 93 ;;
  esac
}
instance_firewall_prepare() {
  printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "$3"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

no_pending_journal() {
  [[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" &&
     ! -e "${SB_ROUTING_TRANSACTION_DIR}" && ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]
}

probe_node() {
  local tag=$1 expected=$2
  python3 - "${core}" "${SINGBOX_CONFIG_FILE}" "${tag}" "${expected}" <<'PY'
import http.server, json, pathlib, socket, subprocess, sys, tempfile, threading, time

core, config_file, tag, expected = sys.argv[1:]
expected = expected == "true"
marker = b"instance-ownership-private-marker"
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
    with tempfile.TemporaryDirectory(prefix="sbv-instance-owner-probe.", dir="/tmp") as tmp:
        config = json.loads(pathlib.Path(config_file).read_text())
        config["inbounds"] = [inbound for inbound in config["inbounds"] if inbound["tag"] == tag]
        assert len(config["inbounds"]) == 1
        assert not config.get("endpoints"), "runtime fixture must never start a WARP tunnel"
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        config["inbounds"][0]["listen_port"] = port
        path = pathlib.Path(tmp) / "config.json"
        path.write_text(json.dumps(config))
        subprocess.run([core, "check", "-c", str(path)], check=True, capture_output=True)
        log_path = pathlib.Path(tmp) / "core.log"
        with log_path.open("w") as log:
            process = subprocess.Popen([core, "run", "-c", str(path)], stdout=log, stderr=log)
            try:
                for _ in range(60):
                    if process.poll() is not None:
                        raise AssertionError(log_path.read_text())
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=0.05):
                            break
                    except OSError:
                        time.sleep(0.05)
                else:
                    raise AssertionError("ownership probe did not start")
                result = subprocess.run(["curl", "--noproxy", "", "--max-time", "3", "-sS", "--proxy", f"socks5h://127.0.0.1:{port}", f"http://localhost:{httpd.server_port}/"], capture_output=True)
                reached = result.returncode == 0 and result.stdout == marker
                print(f"tag={tag} reached_marker={str(reached).lower()} expected={str(expected).lower()}")
                assert reached == expected, (result.stderr, log_path.read_text())
            finally:
                process.terminate()
                process.wait(5)
finally:
    httpd.shutdown()
    httpd.server_close()
PY
}

reset_fixture() {
  rm -rf -- "${SB_PROJECT_DIR}" "${SB_ROUTING_TRANSACTION_DIR}" "${SB_ROUTING_PREVIOUS_DIR}" \
    "${SB_PROJECT_DIR}.instance-write.lock" "${SB_COMPONENT_TRANSACTION_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
  printf '[Service]\nExecStart=fixture\n' > "${SINGBOX_SERVICE_FILE}"
  printf 'manual data must survive\n' > "${SB_PROJECT_DIR}/operator.note"
  chmod 640 "${SB_PROJECT_DIR}/operator.note"
  printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=n\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
}

make_store() {
  local protocol=$1 policy=$2 port=$3 file
  file=$(plain_proxy_structured_store_file "${protocol}")
  jq -n --arg protocol "${protocol}" --arg policy "${policy}" --argjson port "${port}" '
    {schema_version:1,protocol:$protocol,revision:1,default_instance_id:"one",instances:[
      {id:"one",name:$protocol,tag:($protocol+"-one"),listen:{address:"127.0.0.1",port:$port},
       authentication:{enabled:false,username:"",password:""},outbound_policy:$policy,dependencies:[]}]}' > "${file}"
  chmod 600 "${file}"
  validate_structured_instance_store "${protocol}" "${file}"
  save_plain_proxy_structured_marker "${protocol}"
}

two_protocol_fixture() {
  local socks_policy=${1:-default} mixed_policy=${2:-default} policy tags rendered inbounds bindings endpoints='[]'
  reset_fixture
  make_store socks "${socks_policy}" 33091
  make_store mixed "${mixed_policy}" 33092
  write_protocol_index socks,mixed
  policy=$(routing_policy_read_json | jq -c '.server.private_network_block=false |
    .server.warp_ai=false | .server.warp_streaming=false |
    .server.rules=[{id:"local-block",kind:"domain",value:"localhost",action:"reject",enabled:true}]')
  printf '%s\n' "${policy}" > "${SB_ROUTING_POLICY_FILE}"
  chmod 600 "${SB_ROUTING_POLICY_FILE}"
  tags='["mixed-one","socks-one"]'
  rendered=$(routing_policy_render_server_json "${policy}" "${tags}")
  inbounds=$({ render_structured_instance_inbounds mixed "$(plain_proxy_structured_store_file mixed)";
    render_structured_instance_inbounds socks "$(plain_proxy_structured_store_file socks)"; } | jq -s '.')
  bindings=$({ render_structured_instance_route_rules mixed "$(plain_proxy_structured_store_file mixed)";
    render_structured_instance_route_rules socks "$(plain_proxy_structured_store_file socks)"; } | jq -s 'add')
  if [[ "${socks_policy}" == warp || "${mixed_policy}" == warp ]]; then
    endpoints='[{"type":"wireguard","tag":"warp-ep","system":false,"address":["172.16.0.2/32"],"private_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","peers":[{"address":"127.0.0.1","port":51999,"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=","allowed_ips":["0.0.0.0/0"]}]}]'
    printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=y\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
  fi
  jq -n --argjson inbounds "${inbounds}" --argjson bindings "${bindings}" --argjson rendered "${rendered}" --argjson endpoints "${endpoints}" '
    {log:{level:"debug"},dns:{servers:[{type:"local",tag:"local-dns"}],strategy:"ipv4_only"},
     inbounds:$inbounds,endpoints:$endpoints,outbounds:[{type:"direct",tag:"direct",domain_resolver:"local-dns"}],
     route:{rules:([$bindings[]|select(.action=="sniff")]+$rendered.protection_rules+
       [$bindings[]|select(.action=="route")]+$rendered.custom_rules),
       rule_set:$rendered.rule_sets,final:"direct",default_domain_resolver:"local-dns"}}' > "${SINGBOX_CONFIG_FILE}"
  cp -p "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"
  chmod 600 "${SB_PROJECT_DIR}/managed-config.generated.json"
  validate_managed_component_graph "${SINGBOX_CONFIG_FILE}"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
}

append_fallback() {
  local tag=$1 copies=${2:-1}
  jq --arg tag "${tag}" --argjson copies "${copies}" '.route.rules +=
    [range($copies) | {inbound:$tag,action:"route",outbound:"direct"}]' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual-candidate.json"
  mv -- "${TMP_DIR}/manual-candidate.json" "${SINGBOX_CONFIG_FILE}"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
}

edit_socks() {
  jq '.instances[0] | .name += " edited"' "$(plain_proxy_structured_store_file socks)" > "${TMP_DIR}/edited.json"
  apply_plain_proxy_instance_change socks replace 1 "${TMP_DIR}/edited.json" n \
    > "${TMP_DIR}/result.json" 2> "${TMP_DIR}/transaction.err"
}

assert_unchanged() {
  local before=$1
  [[ "$(routing_state_fingerprint)" == "${before}" ]] || fail 'rejection changed project data'
  no_pending_journal || fail 'rejection left a pending journal'
  jq -e '.ok==false and (.transaction.manual_intervention_required|not)' "${TMP_DIR}/result.json" >/dev/null
}

assert_binding() {
  local tag=$1 outbound=$2
  jq -e --arg tag "${tag}" --arg outbound "${outbound}" '
    ([.route.rules[]|select(.inbound==$tag and .action=="route" and .outbound==$outbound)]|length)==1 and
    ([.route.rules|to_entries[]|select(.value.inbound==$tag and .value.action=="route")|.key][0]) <
      ([.route.rules|to_entries[]|select(.value.domain==["localhost"] and .value.action=="reject")|.key][0])' "${SINGBOX_CONFIG_FILE}" >/dev/null
}

for variant in foreign missing-baseline duplicate-manual; do
  two_protocol_fixture
  copies=1
  [[ "${variant}" != duplicate-manual ]] || copies=2
  append_fallback mixed-one "${copies}"
  [[ "${variant}" != missing-baseline ]] || rm -- "${SB_PROJECT_DIR}/managed-config.generated.json"
  probe_node mixed-one false
  before=$(routing_state_fingerprint)
  if edit_socks; then
    # An exact unknown fallback may remain after the operator's rejecting rule;
    # moving/deduplicating it or adding it to the pure baseline claims authority.
    probe_node mixed-one false
    jq -e --argjson copies "${copies}" '
      ([.route.rules[]|select(.inbound=="mixed-one" and .action=="route" and .outbound=="direct")]|length)==$copies and
      ([.route.rules|to_entries[]|select(.value.domain==["localhost"] and .value.action=="reject")|.key][0]) <
        ([.route.rules|to_entries[]|select(.value.inbound=="mixed-one" and .value.action=="route")|.key]|min)' "${SINGBOX_CONFIG_FILE}" >/dev/null
    if [[ -f "${SB_PROJECT_DIR}/managed-config.generated.json" ]]; then
      jq -e 'all(.route.rules[]; .inbound!="mixed-one" or .action!="route")' \
        "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
    fi
    no_pending_journal
  else
    assert_unchanged "${before}"
  fi
done

# A global observational prefix remains ahead of the owned chain. The same
# manual rule interleaved between owned anchors cannot be crossed by rebuilding.
for placement in prefix interleaved; do
  two_protocol_fixture
  jq --arg placement "${placement}" '{action:"sniff",timeout:"100ms"} as $prefix |
    if $placement=="prefix" then .route.rules=[$prefix]+.route.rules
    else .route.rules=(.route.rules[:1]+[$prefix]+.route.rules[1:]) end' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/manual-prefix.json"
  mv -- "${TMP_DIR}/manual-prefix.json" "${SINGBOX_CONFIG_FILE}"
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  before=$(routing_state_fingerprint)
  if edit_socks; then
    [[ "${placement}" == prefix ]] || fail 'interleaved manual sniff was crossed'
    jq -e '.route.rules[0]=={action:"sniff",timeout:"100ms"}' "${SINGBOX_CONFIG_FILE}" >/dev/null
    probe_node mixed-one false
    no_pending_journal
  else
    [[ "${placement}" == interleaved ]] || { cat "${TMP_DIR}/transaction.err" >&2; fail 'non-terminal global prefix rejected'; }
    assert_unchanged "${before}"
  fi
done

# The raw affected-protocol producer used to prune a shape-matching unknown
# fallback before the policy projector could distinguish it from owned state.
two_protocol_fixture
append_fallback socks-one
before=$(routing_state_fingerprint)
if edit_socks; then fail 'same-protocol unknown fallback was adopted or dropped'; fi
assert_unchanged "${before}"
probe_node socks-one false

# A single authoritative binding is valid; a duplicate live binding cannot be
# silently collapsed based on tag/action shape even when one appears in baseline.
two_protocol_fixture default direct
append_fallback mixed-one
before=$(routing_state_fingerprint)
before_rules=$(jq -cS '.route.rules' "${SINGBOX_CONFIG_FILE}")
if edit_socks; then
  [[ "$(jq -cS '.route.rules' "${SINGBOX_CONFIG_FILE}")" == "${before_rules}" ]] || fail 'duplicate foreign authoritative binding was moved or collapsed'
  no_pending_journal
else
  assert_unchanged "${before}"
fi

for policy in direct warp; do
  outbound=$([[ "${policy}" == warp ]] && printf warp-ep || printf direct)
  for layout in moved missing; do
    two_protocol_fixture default "${policy}"
    # State authorizes the value, while the operator's live position remains
    # authoritative. Moving a unique binding behind a reject or removing it
    # must not let an unrelated edit restore its old, more permissive priority.
    jq --arg layout "${layout}" '
      [.route.rules[]|select(.inbound=="mixed-one" and .action=="route")] as $binding |
      .route.rules |= map(select(.inbound!="mixed-one" or .action!="route")) |
      if $layout=="moved" then .route.rules += $binding else . end' \
      "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/operator-order.json"
    mv -- "${TMP_DIR}/operator-order.json" "${SINGBOX_CONFIG_FILE}"
    "${core}" check -c "${SINGBOX_CONFIG_FILE}"
    [[ "${policy}" != direct ]] || probe_node mixed-one false
    before=$(routing_state_fingerprint)
    before_rules=$(jq -cS '.route.rules' "${SINGBOX_CONFIG_FILE}")
    if edit_socks; then
      [[ "${policy}" != direct ]] || probe_node mixed-one false
      [[ "$(jq -cS '.route.rules' "${SINGBOX_CONFIG_FILE}")" == "${before_rules}" ]] || fail "${layout} foreign ${policy} binding was restored or reordered"
      no_pending_journal
    else
      assert_unchanged "${before}"
    fi
  done
  two_protocol_fixture default "${policy}"
  if ! edit_socks; then cat "${TMP_DIR}/transaction.err" >&2; fail "trusted foreign ${policy} binding rejected"; fi
  assert_binding mixed-one "${outbound}"
  [[ "${policy}" != direct ]] || probe_node mixed-one true
  no_pending_journal
  two_protocol_fixture default "${policy}"
  rm -- "${SB_PROJECT_DIR}/managed-config.generated.json"
  if ! edit_socks; then cat "${TMP_DIR}/transaction.err" >&2; fail "trusted foreign ${policy} state rejected without baseline"; fi
  assert_binding mixed-one "${outbound}"
  [[ ! -e "${SB_PROJECT_DIR}/managed-config.generated.json" ]]
  no_pending_journal
  # The affected old store itself authorizes its exact binding, even before
  # any pure baseline has been established. It must not need shape guessing.
  two_protocol_fixture "${policy}" default
  rm -- "${SB_PROJECT_DIR}/managed-config.generated.json"
  if ! edit_socks; then cat "${TMP_DIR}/transaction.err" >&2; fail "trusted affected ${policy} binding rejected without baseline"; fi
  assert_binding socks-one "${outbound}"
  [[ ! -e "${SB_PROJECT_DIR}/managed-config.generated.json" ]]
  no_pending_journal
done

for scope in global disjoint; do
  reset_fixture
  printf 'INSTALLED_PROTOCOLS=\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
  structured_instance_store_empty_json socks | jq '.revision=7' > "$(plain_proxy_structured_store_file socks)"
  chmod 600 "$(plain_proxy_structured_store_file socks)"
  policy=$(routing_policy_read_json)
  printf '%s\n' "${policy}" > "${SB_ROUTING_POLICY_FILE}"
  chmod 600 "${SB_ROUTING_POLICY_FILE}"
  jq -n '{dns:{servers:[{type:"local",tag:"local-dns"}],strategy:"ipv4_only"},
    inbounds:[{type:"http",tag:"operator-http",listen:"127.0.0.1",listen_port:33093}],
    outbounds:[{type:"direct",tag:"direct",domain_resolver:"local-dns"}],
    route:{rules:[],final:"direct",default_domain_resolver:"local-dns"}}' > "${SB_PROJECT_DIR}/managed-config.generated.json"
  chmod 600 "${SB_PROJECT_DIR}/managed-config.generated.json"
  jq --arg scope "${scope}" '.route.rules=[{action:"route",outbound:"direct"} +
    (if $scope=="disjoint" then {inbound:"operator-http"} else {} end)]' \
    "${SB_PROJECT_DIR}/managed-config.generated.json" > "${SINGBOX_CONFIG_FILE}"
  # Preserve the operator listener in live context only, not the pure baseline.
  jq '.inbounds=[]' "${SB_PROJECT_DIR}/managed-config.generated.json" > "${TMP_DIR}/pure-empty.json"
  mv -- "${TMP_DIR}/pure-empty.json" "${SB_PROJECT_DIR}/managed-config.generated.json"
  chmod 600 "${SB_PROJECT_DIR}/managed-config.generated.json"
  jq -n '{id:"one",name:"first",tag:"socks-one",listen:{address:"127.0.0.1",port:33091},
    authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}' > "${TMP_DIR}/first.json"
  before=$(routing_state_fingerprint)
  if apply_plain_proxy_instance_change socks create 7 "${TMP_DIR}/first.json" n \
    > "${TMP_DIR}/result.json" 2> "${TMP_DIR}/transaction.err"; then
    [[ "${scope}" == disjoint ]] || fail 'first-node activation accepted a global route ahead of filtering'
    jq -e '.route.rules[0]=={inbound:"operator-http",action:"route",outbound:"direct"}' "${SINGBOX_CONFIG_FILE}" >/dev/null
    probe_node socks-one false
    no_pending_journal
  else
    [[ "${scope}" == global ]] || { cat "${TMP_DIR}/transaction.err" >&2; fail 'disjoint first-node control rejected'; }
    assert_unchanged "${before}"
  fi
done

printf 'Typed instance rule ownership, first-node activation and real core filtering controls passed\n'
