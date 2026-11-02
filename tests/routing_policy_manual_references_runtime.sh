#!/usr/bin/env bash

# Container-only runtime proof for pure-baseline references to manual objects.
set -euo pipefail

if [[ "${SBV_MANUAL_REFERENCE_RUNTIME_ACCEPTANCE:-}" != 1 || ! -f /.dockerenv ||
      "$(cat /proc/1/comm)" != systemd || ! -f /run/sbv-manual-reference-runtime.sentinel ||
      -z "${SBV_MANUAL_REFERENCE_RUNTIME_SENTINEL:-}" ]] ||
   [[ "$(cat /run/sbv-manual-reference-runtime.sentinel)" != "${SBV_MANUAL_REFERENCE_RUNTIME_SENTINEL}" ]]; then
  printf 'manual-reference runtime requires its explicitly prepared disposable systemd container\n' >&2
  exit 64
fi
if [[ -e /root/sing-box-vps || -e /root/sing-box-vps.rules-write.lock ||
      -e /root/sing-box-vps.rules-previous || -e /root/sing-box-vps.instance-write.lock ||
      -e /etc/sing-box/config.json || -e /usr/local/etc/sing-box/config.json ||
      -e /etc/systemd/system/sing-box.service || ! -x /usr/local/bin/sing-box ||
      ! -f /tmp/install.sh || ! "${SBV_MANUAL_REFERENCE_RUNTIME_INSTALL_SHA:-}" =~ ^[a-f0-9]{64}$ ]] ||
   command systemctl cat sing-box >/dev/null 2>&1; then
  printf 'manual-reference runtime refuses an existing or unprepared installation\n' >&2
  exit 64
fi
[[ "$(sha256sum /tmp/install.sh | awk '{print $1}')" == "${SBV_MANUAL_REFERENCE_RUNTIME_INSTALL_SHA}" ]]

umask 077
readonly ARTIFACT_DIR=/tmp/sbv-routing-manual-reference-artifacts
readonly MIXED_PORT=19090
readonly ADDED_MIXED_PORT=19091
readonly OPERATOR_HTTP_PORT=19092
readonly MARKER_PORT=18090
mkdir -m 700 -- "${ARTIFACT_DIR}"
RUNTIME_PHASE=prepare
MARKER_PID=''

runtime_cleanup() {
  local result=$? marker_result=0
  trap - EXIT
  if [[ -n "${MARKER_PID}" ]]; then
    if kill -0 "${MARKER_PID}" 2>/dev/null; then kill -TERM "${MARKER_PID}" || result=1; fi
    wait "${MARKER_PID}" || marker_result=$?
    [[ "${marker_result}" == 0 || "${marker_result}" == 143 ]] || result=1
  fi
  if [[ -f /etc/systemd/system/sing-box.service ]]; then
    cp -a /etc/systemd/system/sing-box.service "${ARTIFACT_DIR}/service-unit.txt" || result=1
    command systemctl status sing-box --no-pager > "${ARTIFACT_DIR}/service-final.txt" 2>&1 || result=1
    command journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/service-journal.txt" 2>&1 || result=1
  fi
  if [[ -d /root/sing-box-vps ]]; then
    cp -a /root/sing-box-vps "${ARTIFACT_DIR}/project-final" || result=1
  fi
  if [[ -d /root/sing-box-vps.rules-previous ]]; then
    cp -a /root/sing-box-vps.rules-previous "${ARTIFACT_DIR}/previous-final" || result=1
  fi
  printf 'status=%s\nlast_phase=%s\n' "${result}" "${RUNTIME_PHASE}" > "${ARTIFACT_DIR}/result.env"
  exit "${result}"
}
trap runtime_cleanup EXIT
trap 'printf "manual-reference runtime failed at line %s during %s\n" "${LINENO}" "${RUNTIME_PHASE}" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

stage() {
  RUNTIME_PHASE=$1
  printf '[manual-reference runtime] %s\n' "${RUNTIME_PHASE}"
  printf '%s\t%s\n' "$(date -u +%FT%TZ)" "${RUNTIME_PHASE}" >> "${ARTIFACT_DIR}/stages.tsv"
}
wait_listener() {
  local port=$1 attempt
  for attempt in {1..80}; do
    if ss -H -lnt | awk -v port="${port}" '$4 ~ (":" port "$") {found=1} END {exit !found}'; then return 0; fi
    sleep 0.1
  done
  return 1
}
service_pid() { command systemctl show sing-box --property MainPID --value; }
restart_count() {
  awk -F '\t' -v phase="$1" '$1==phase && $2=="restart sing-box" {n++} END {print n+0}' \
    "${ARTIFACT_DIR}/systemctl-calls.tsv"
}
http_probe() {
  local port=$1 expected=$2 label=$3 response result=0
  response=$(curl --noproxy '' --proxy "http://127.0.0.1:${port}" --silent --show-error --fail \
    --connect-timeout 2 --max-time 5 "http://127.0.0.1:${MARKER_PORT}/marker" \
    2> "${ARTIFACT_DIR}/${label}.stderr") || result=$?
  printf '%s\n' "${response}" > "${ARTIFACT_DIR}/${label}.response"
  printf 'exit=%s\nexpected=%s\nproxy_port=%s\n' "${result}" "${expected}" "${port}" > "${ARTIFACT_DIR}/${label}.result"
  if [[ "${expected}" == allowed ]]; then [[ "${result}" == 0 && "${response}" == manual-reference-marker ]];
  else [[ "${result}" != 0 && "${response}" != manual-reference-marker ]]; fi
}
assert_manual_context() {
  local label=$1
  jq -S '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/${label}-manual-outbound.json"
  jq -S '.inbounds[] | select(.tag=="operator-http")' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/${label}-manual-inbound.json"
  cmp "${ARTIFACT_DIR}/manual-outbound-original.json" "${ARTIFACT_DIR}/${label}-manual-outbound.json"
  cmp "${ARTIFACT_DIR}/manual-inbound-original.json" "${ARTIFACT_DIR}/${label}-manual-inbound.json"
  jq -e '.route.final=="selector-managed" and
    any(.outbounds[]; .tag=="selector-managed" and .outbounds==["operator-egress"] and .default=="operator-egress")' \
    "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq -e 'all(.outbounds[]; .tag!="operator-egress") and all(.inbounds[]; .tag!="operator-http") and
    any(.outbounds[]; .tag=="selector-managed" and .outbounds==["operator-egress"] and .default=="operator-egress")' \
    "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
  validate_managed_component_graph "${SINGBOX_CONFIG_FILE}"
  "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/${label}.check" 2>&1
  [[ -z "$(find "${SB_PROJECT_DIR}" -maxdepth 1 -name '.managed-config.*.candidate.*' -print)" ]]
}

/usr/local/bin/sing-box version > "${ARTIFACT_DIR}/core-version.txt"
grep -Fqx 'sing-box version 1.14.2' "${ARTIFACT_DIR}/core-version.txt"
sha256sum /tmp/install.sh /usr/local/bin/sing-box "${BASH_SOURCE[0]}" > "${ARTIFACT_DIR}/sources.sha256"
source /tmp/install.sh
SB_VERSION=1.14.2
ensure_sbv_command_installed() { :; }
get_public_ip() { printf '203.0.113.10'; }
get_public_ipv4() { printf '203.0.113.10'; }
get_public_ipv6() { return 1; }
register_warp() { printf 'unexpected WARP registration in isolated manual-reference acceptance\n' >&2; return 98; }
systemctl() {
  printf '%s\t%s\n' "${RUNTIME_PHASE}" "$*" >> "${ARTIFACT_DIR}/systemctl-calls.tsv"
  if [[ "${RUNTIME_PHASE}" == typed-restart-failure && "${1:-}" == restart &&
        "${2:-}" == sing-box && ! -e "${ARTIFACT_DIR}/restart-injected-once" ]]; then
    : > "${ARTIFACT_DIR}/restart-injected-once"
    return 97
  fi
  command systemctl "$@"
}
cat > "${ARTIFACT_DIR}/proof-boundaries.txt" <<'EOF'
This is a prepared Mixed baseline plus bounded real component/typed/global
lifecycle acceptance, not another fresh install or protocol matrix. Actual
sing-box 1.14.2, systemd unit/activation, firewall, component API, typed append,
pure-baseline/context validation, restart failure/rollback, and local HTTP marker
traffic are exercised. Manual objects and a manual default selector are preserved
while only pure generated facts are persisted. Global sbv copying/public-IP lookup
use offline fixture boundaries. No WARP/provider, public endpoint, production or
external synchronization acceptance is claimed. Container networking is none.
EOF

stage mixed-baseline-prepare
mkdir -p -- "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=RuntimeMixed\nPORT=%s\nAUTH_ENABLED=n\nUSERNAME=\nPASSWORD=\n' \
  "${MIXED_PORT}" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
policy=$(routing_policy_read_json | jq '.server.block_cn=false')
printf '%s\n' "${policy}" > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}"
SB_ENABLE_WARP=n
SB_ADVANCED_ROUTE=n
SB_WARP_ROUTE_MODE=selective
SB_INBOUND_STACK_MODE=ipv4_only
SB_OUTBOUND_STACK_MODE=prefer_ipv4
save_stack_mode_state
save_warp_route_settings
generate_config > "${ARTIFACT_DIR}/initial-generate.log" 2>&1
before_manual_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
jq --argjson port "${OPERATOR_HTTP_PORT}" '.outbounds += [{type:"direct",tag:"operator-egress",bind_interface:"lo"}] |
  .inbounds += [{type:"http",tag:"operator-http",listen:"127.0.0.1",listen_port:$port}]' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/manual-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/manual-config.json" > "${ARTIFACT_DIR}/manual-publish.log" 2>&1
[[ "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_manual_baseline}" ]]
jq -S '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/manual-outbound-original.json"
jq -S '.inbounds[] | select(.tag=="operator-http")' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/manual-inbound-original.json"
setup_service > "${ARTIFACT_DIR}/service-setup.log" 2>&1
systemctl start sing-box
systemctl is-active --quiet sing-box
wait_listener "${MIXED_PORT}"
wait_listener "${OPERATOR_HTTP_PORT}"
python3 -u - "${MARKER_PORT}" <<'PY' > "${ARTIFACT_DIR}/marker-server.log" 2>&1 &
import http.server,sys
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b"manual-reference-marker\n"
        self.send_response(200); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,*_args): pass
http.server.ThreadingHTTPServer(("127.0.0.1",int(sys.argv[1])),Handler).serve_forever()
PY
MARKER_PID=$!
wait_listener "${MARKER_PORT}"

stage component-selector-create
component_before=$(service_pid)
printf '%s\n' '{"id":"selector-managed","role":"outbound","type":"selector","tag":"selector-managed","enabled":true,"route_rules":[],"config":{"outbounds":["operator-egress"],"default":"operator-egress"}}' \
  > "${ARTIFACT_DIR}/component-record.json"
managed_component_state_apply create 0 "${ARTIFACT_DIR}/component-record.json" '' n \
  > "${ARTIFACT_DIR}/component-create.log" 2>&1
[[ "$(restart_count component-selector-create)" == 1 && "$(service_pid)" != "${component_before}" ]]
systemctl is-active --quiet sing-box

stage operator-default-selection
before_pid=$(service_pid)
before_manual_default=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
jq '.route.final="selector-managed"' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/selector-default-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/selector-default-config.json" > "${ARTIFACT_DIR}/selector-default-publish.log" 2>&1
[[ "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_manual_default}" ]]
systemctl restart sing-box
systemctl is-active --quiet sing-box
[[ "$(restart_count operator-default-selection)" == 1 && "$(service_pid)" != "${before_pid}" ]]
assert_manual_context component-context
http_probe "${MIXED_PORT}" allowed baseline-mixed-marker
http_probe "${OPERATOR_HTTP_PORT}" allowed baseline-operator-marker
cp -a -- "${SB_PROJECT_DIR}" "${ARTIFACT_DIR}/before-typed-project"
before_fingerprint=$(routing_state_fingerprint)
before_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
before_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
before_baseline_backup=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json.bak")
jq -n --argjson port "${ADDED_MIXED_PORT}" '{id:"added",name:"Added",tag:"mixed-added",listen:{address:"127.0.0.1",port:$port},
  authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}' > "${ARTIFACT_DIR}/mixed-record.json"

stage typed-restart-failure
failure_before=$(service_pid)
if apply_plain_proxy_instance_change mixed create 0 "${ARTIFACT_DIR}/mixed-record.json" n \
  > "${ARTIFACT_DIR}/typed-failure.json" 2> "${ARTIFACT_DIR}/typed-failure.log"; then
  printf 'typed append unexpectedly committed after injected restart failure\n' >&2
  exit 1
fi
jq -e '.ok==false and .transaction.status=="rolled_back" and .transaction.manual_intervention_required==false' \
  "${ARTIFACT_DIR}/typed-failure.json" >/dev/null
[[ -f "${ARTIFACT_DIR}/restart-injected-once" && "$(restart_count typed-restart-failure)" == 2 ]]
failure_after=$(service_pid)
[[ "${failure_before}" != 0 && "${failure_after}" != 0 && "${failure_before}" != "${failure_after}" ]]
systemctl is-active --quiet sing-box
[[ "$(routing_state_fingerprint)" == "${before_fingerprint}" &&
   "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config}" &&
   "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_baseline}" &&
   "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json.bak")" == "${before_baseline_backup}" ]]
[[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" ]]
assert_manual_context rollback-context
http_probe "${MIXED_PORT}" allowed rollback-mixed-marker
http_probe "${OPERATOR_HTTP_PORT}" allowed rollback-operator-marker
printf 'failure\tbefore=%s\tafter=%s\trestarts=2\n' "${failure_before}" "${failure_after}" >> "${ARTIFACT_DIR}/service-pids.tsv"

stage typed-retry-success
success_before=$(service_pid)
apply_plain_proxy_instance_change mixed create 0 "${ARTIFACT_DIR}/mixed-record.json" n \
  > "${ARTIFACT_DIR}/typed-success.json" 2> "${ARTIFACT_DIR}/typed-success.log"
jq -e '.ok==true and .revision==1' "${ARTIFACT_DIR}/typed-success.json" >/dev/null
success_after=$(service_pid)
[[ "$(restart_count typed-retry-success)" == 1 && "${success_before}" != 0 &&
   "${success_after}" != 0 && "${success_before}" != "${success_after}" ]]
systemctl is-active --quiet sing-box
wait_listener "${ADDED_MIXED_PORT}"
assert_manual_context typed-context
jq -S '.inbounds[] | select(.tag=="mixed-added")' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/typed-added-inbound.json"
jq -e 'any(.inbounds[]; .tag=="mixed-added")' "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
http_probe "${ADDED_MIXED_PORT}" allowed typed-added-marker
http_probe "${OPERATOR_HTTP_PORT}" allowed typed-operator-marker
cp -a -- "${SB_PROJECT_DIR}" "${ARTIFACT_DIR}/after-typed-project"
printf 'success\tbefore=%s\tafter=%s\trestarts=1\n' "${success_before}" "${success_after}" >> "${ARTIFACT_DIR}/service-pids.tsv"

stage global-policy-apply
global_before=$(service_pid)
routing_draft_create "${ARTIFACT_DIR}/global-draft.json"
jq '.policy.server.rules=[{id:"private-fixture",kind:"ip_cidr",value:"127.0.0.0/8",action:"reject",enabled:true}]' "${ARTIFACT_DIR}/global-draft.json" > "${ARTIFACT_DIR}/global-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/global-edit.json" > "${ARTIFACT_DIR}/global-apply.log" 2>&1
global_after=$(service_pid)
[[ "$(restart_count global-policy-apply)" == 1 && "${global_before}" != 0 &&
   "${global_after}" != 0 && "${global_before}" != "${global_after}" ]]
systemctl is-active --quiet sing-box
wait_listener "${ADDED_MIXED_PORT}"
assert_manual_context global-context
jq -S '.inbounds[] | select(.tag=="mixed-added")' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/global-added-inbound.json"
cmp "${ARTIFACT_DIR}/typed-added-inbound.json" "${ARTIFACT_DIR}/global-added-inbound.json"
jq -e '.schema_version==2 and .server.rules[0].id=="private-fixture"' "${SB_ROUTING_POLICY_FILE}" >/dev/null
http_probe "${ADDED_MIXED_PORT}" blocked global-managed-private-blocked
http_probe "${OPERATOR_HTTP_PORT}" allowed global-operator-marker
printf 'global\tbefore=%s\tafter=%s\trestarts=1\n' "${global_before}" "${global_after}" >> "${ARTIFACT_DIR}/service-pids.tsv"
stage complete
printf 'Real component/manual references, typed rollback/retry and continuous global facts acceptance passed\n'
