#!/usr/bin/env bash
# Explicitly prepared disposable systemd-container acceptance; never a host test.
set -euo pipefail
if [[ "${SBV_AGENT_RUNTIME_ACCEPTANCE:-}" != 1 || ! -f /.dockerenv ||
      "$(cat /proc/1/comm)" != systemd || ! -f /run/sbv-agent-runtime.sentinel ||
      -z "${SBV_AGENT_RUNTIME_SENTINEL:-}" ||
      "$(cat /run/sbv-agent-runtime.sentinel)" != "${SBV_AGENT_RUNTIME_SENTINEL}" ]]; then
  printf 'agent runtime requires its explicitly prepared disposable systemd container\n' >&2
  exit 64
fi
if [[ -e /root/sing-box-vps || -e /etc/systemd/system/sing-box.service ||
      ! -x /usr/local/bin/sing-box || ! -f /tmp/install.sh ]] ||
   command systemctl cat sing-box >/dev/null 2>&1; then
  printf 'agent runtime refuses an existing or unprepared installation\n' >&2
  exit 64
fi
umask 077
readonly ARTIFACT_DIR=/tmp/sbv-agent-runtime-artifacts
mkdir -m 700 "${ARTIFACT_DIR}"
http_pid='' RUNTIME_PHASE=prepare
runtime_cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "${http_pid}" ]]; then
    if kill -0 "${http_pid}" 2>/dev/null; then kill -TERM "${http_pid}" || result=1; fi
    wait "${http_pid}" || { [[ "$?" == 143 ]] || result=1; }
  fi
  command journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/service-journal.txt" || result=1
  if [[ -d /root/sing-box-vps ]]; then cp -a /root/sing-box-vps "${ARTIFACT_DIR}/project-final" || result=1; fi
  printf 'status=%s\nlast_phase=%s\n' "${result}" "${RUNTIME_PHASE}" > "${ARTIFACT_DIR}/result.env"
  exit "${result}"
}
trap runtime_cleanup EXIT
trap 'printf "agent runtime failed at line %s phase %s\n" "${LINENO}" "${RUNTIME_PHASE}" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
stage() { RUNTIME_PHASE=$1; printf '[runtime] %s\n' "$1"; }
source /tmp/install.sh
/usr/local/bin/sing-box version > "${ARTIFACT_DIR}/core-version.txt"
grep -Fxq 'sing-box version 1.14.2' "${ARTIFACT_DIR}/core-version.txt"
sha256sum /tmp/install.sh /usr/local/bin/sing-box "${BASH_SOURCE[0]}" > "${ARTIFACT_DIR}/sources.sha256"
cat > "${ARTIFACT_DIR}/proof-boundaries.txt" <<'BOUNDARIES'
Real: sing-box 1.14.2, systemd service status/start/stop/restart/logs; canonical
CLI processes and JSON envelopes; routing view/export/validate/apply/restore,
CAS rejection, target-core checks, HTTP allow/reject and post-restore allow.
Prepared: installed dependencies/core, initial HTTP loopback installer answers,
local marker and hosts entries. Committed recovery journal is an actual completed
transaction moved back to the pending location to model interrupted cleanup.
No external network, rule-source download, real WARP/SubMan, public reachability
or production acceptance. The Docker container runs with --network none.
BOUNDARIES
# Prepare the same real installation baseline as the routing runtime fixture,
# without dependency/core downloads or operator prompts. Tested CLI calls below
# are fresh processes and do not inherit these function overrides.
install_dependencies() { command -v jq >/dev/null && command -v iptables >/dev/null; }
install_binary() { :; }
get_latest_version() { SB_VERSION=1.14.2; }
prompt_singbox_version() { SB_VERSION=1.14.2; }
prompt_protocol_install_selection() { SELECTED_PROTOCOLS_CSV=http; }
prompt_protocol_install_fields() {
  set_protocol_defaults http
  SB_PORT=19082 SB_MIXED_LISTEN_ADDRESS=127.0.0.1
  SB_MIXED_AUTH_ENABLED=n SB_HTTP_TLS_JSON='{"enabled":false}'
}
ensure_sbv_command_installed() { :; }
get_public_ip() { printf '203.0.113.10'; }
get_public_ipv4() { printf '203.0.113.10'; }
get_public_ipv6() { return 1; }
register_warp() { printf 'unexpected WARP registration\n' >&2; return 98; }
wait_listener() {
  local port=$1 attempt
  for attempt in {1..80}; do
    if ss -H -lnt | awk -v p="${port}" '$4 ~ (":"p"$") {f=1} END {exit !f}'; then return 0; fi
    sleep 0.1
  done
  return 1
}
json_call() {
  local name=$1
  shift
  bash /tmp/install.sh "$@" > "${ARTIFACT_DIR}/${name}.json" 2> "${ARTIFACT_DIR}/${name}.stderr"
  jq -se 'length==1 and .[0].ok==true' "${ARTIFACT_DIR}/${name}.json" >/dev/null
}
json_failure() {
  local name=$1 expected=$2
  shift 2
  if bash /tmp/install.sh "$@" > "${ARTIFACT_DIR}/${name}.json" 2> "${ARTIFACT_DIR}/${name}.stderr"; then
    printf 'expected failed CLI call: %s\n' "${name}" >&2; return 1
  fi
  jq -se --arg error "${expected}" 'length==1 and .[0].ok==false and .[0].error==$error' \
    "${ARTIFACT_DIR}/${name}.json" >/dev/null
}
probe() {
  local host=$1 expected=$2 response='' result=0
  response=$(curl --noproxy '' --proxy http://127.0.0.1:19082 --connect-timeout 2 --max-time 3 \
    --silent --show-error --fail "http://${host}:18080/" 2> "${ARTIFACT_DIR}/${RUNTIME_PHASE}-${host}.stderr") || result=$?
  if [[ "${expected}" == allow ]]; then [[ "${result}" == 0 && "${response}" == sbv-agent-marker ]]; else [[ "${result}" != 0 ]]; fi
}
assert_core() {
  /usr/local/bin/sing-box check -c /root/sing-box-vps/config.json > "${ARTIFACT_DIR}/${RUNTIME_PHASE}-check.log" 2>&1
  command systemctl is-active --quiet sing-box
  wait_listener 19082
}
python3 -u - <<'PY' > "${ARTIFACT_DIR}/http-marker.log" 2>&1 &
import http.server
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  body=b'sbv-agent-marker\n'
  self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
 def log_message(self,*_): pass
http.server.ThreadingHTTPServer(('127.0.0.1',18080),Handler).serve_forever()
PY
http_pid=$!
printf '\n127.0.0.1 blocked.fixture.invalid allowed.fixture.invalid\n' >> /etc/hosts
wait_listener 18080
stage prepare-http-baseline
install_protocols_interactive fresh > "${ARTIFACT_DIR}/baseline.log" 2>&1 </dev/null
assert_core
probe blocked.fixture.invalid allow

stage service-operations
json_call service-status service status --json
jq -e '.service.active_state=="active"' "${ARTIFACT_DIR}/service-status.json" >/dev/null
json_failure start-unconfirmed confirmation_required service start --json
json_call service-stop service stop --json --yes
jq -e '.service.after=="inactive"' "${ARTIFACT_DIR}/service-stop.json" >/dev/null
! ss -H -lnt | awk '$4 ~ /:19082$/ {f=1} END {exit !f}'
json_call service-start service start --json --yes
assert_core
probe blocked.fixture.invalid allow
json_call service-restart service restart --json --yes
jq -e '.check.ok and .service.after=="active"' "${ARTIFACT_DIR}/service-restart.json" >/dev/null
assert_core
json_call service-logs service logs --json --lines 20
jq -e '.sensitive and .lines==20 and (.logs|type=="string")' "${ARTIFACT_DIR}/service-logs.json" >/dev/null

stage routing-read-and-validate
json_call routing-view routing view --json
json_call routing-nodes routing nodes --json
json_call routing-export routing export --json
jq '.draft | .policy.server.warp_ai=false | .policy.server.warp_streaming=false |
  .policy.server.rules=[{id:"reject-marker",kind:"domain",value:"blocked.fixture.invalid",action:"reject",enabled:true}]' \
  "${ARTIFACT_DIR}/routing-export.json" > "${ARTIFACT_DIR}/draft.json"
json_call routing-validate routing validate --json --file "${ARTIFACT_DIR}/draft.json"
jq -e '.valid and (.config_check_performed|not)' "${ARTIFACT_DIR}/routing-validate.json" >/dev/null
sha256sum /root/sing-box-vps/config.json > "${ARTIFACT_DIR}/before-apply.sha256"
json_failure apply-unconfirmed confirmation_required routing apply --json --file "${ARTIFACT_DIR}/draft.json"
sha256sum --check "${ARTIFACT_DIR}/before-apply.sha256" >/dev/null

stage routing-apply
json_call routing-apply routing apply --json --yes --file "${ARTIFACT_DIR}/draft.json"
assert_core
probe blocked.fixture.invalid reject
probe allowed.fixture.invalid allow
json_failure stale-draft revision_conflict routing apply --json --yes --file "${ARTIFACT_DIR}/draft.json"
json_call routing-after-apply routing view --json
fingerprint=$(jq -r '.fingerprint' "${ARTIFACT_DIR}/routing-after-apply.json")
json_failure stale-restore revision_conflict routing restore --json --yes --expected-fingerprint "$(printf '%064d' 0)"

stage routing-restore
json_call routing-restore routing restore --json --yes --expected-fingerprint "${fingerprint}"
assert_core
probe blocked.fixture.invalid allow

stage pending-committed-cleanup-recovery
# Recreate only the pending-location boundary of a completed real transaction.
# This proves recovery dispatch/cleanup, not a signal interruption experiment.
routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}"
[[ "$(jq -r '.after_fingerprint' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json")" == "$(routing_state_fingerprint)" ]]
mv -- "${SB_ROUTING_PREVIOUS_DIR}" "${SB_ROUTING_TRANSACTION_DIR}"
json_call pending-discovery commands --json
json_failure pending-read routing_transaction_pending routing view --json
json_call routing-recover routing recover --json --yes
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
assert_core
probe blocked.fixture.invalid allow
stage complete
printf '%s\n' 'agent service and routing runtime passed'
