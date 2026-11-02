#!/usr/bin/env bash

# Container-only acceptance of a real schema-1 REALITY rules migration.
set -euo pipefail

if [[ "${SBV_LEGACY_RUNTIME_ACCEPTANCE:-}" != 1 || ! -f /.dockerenv ||
      "$(cat /proc/1/comm)" != systemd || ! -f /run/sbv-routing-legacy-runtime.sentinel ||
      -z "${SBV_LEGACY_RUNTIME_SENTINEL:-}" ]] ||
   [[ "$(cat /run/sbv-routing-legacy-runtime.sentinel)" != "${SBV_LEGACY_RUNTIME_SENTINEL}" ]]; then
  printf 'legacy routing runtime requires its explicitly prepared disposable systemd container\n' >&2
  exit 64
fi
if [[ -e /root/sing-box-vps || -e /root/sing-box-vps.rules-write.lock ||
      -e /root/sing-box-vps.rules-previous || -e /root/sing-box-vps.instance-write.lock ||
      -e /etc/sing-box/config.json || -e /usr/local/etc/sing-box/config.json ||
      -e /etc/systemd/system/sing-box.service || ! -x /usr/local/bin/sing-box ||
      ! -f /tmp/install.sh || ! "${SBV_LEGACY_RUNTIME_INSTALL_SHA:-}" =~ ^[a-f0-9]{64}$ ]] ||
   command systemctl cat sing-box >/dev/null 2>&1; then
  printf 'legacy routing runtime refuses an existing or unprepared installation\n' >&2
  exit 64
fi
[[ "$(sha256sum /tmp/install.sh | awk '{print $1}')" == "${SBV_LEGACY_RUNTIME_INSTALL_SHA}" ]]

umask 077
readonly ARTIFACT_DIR=/tmp/sbv-routing-legacy-artifacts
readonly REALITY_PORT=19444
readonly CONTROL_PROXY_PORT=19084
readonly MARKER_PORT=18084
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
trap 'printf "legacy routing runtime failed at line %s during %s\n" "${LINENO}" "${RUNTIME_PHASE}" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

stage() {
  RUNTIME_PHASE=$1
  printf '[legacy runtime] %s\n' "${RUNTIME_PHASE}"
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
control_marker() {
  local label=$1 response
  response=$(curl --noproxy '' --proxy "http://127.0.0.1:${CONTROL_PROXY_PORT}" \
    --silent --show-error --fail --connect-timeout 2 --max-time 5 \
    "http://127.0.0.1:${MARKER_PORT}/marker" 2> "${ARTIFACT_DIR}/${label}.stderr")
  [[ "${response}" == legacy-routing-marker ]]
  printf '%s\n' "${response}" > "${ARTIFACT_DIR}/${label}.response"
}
no_timestamped_backup() {
  [[ -z "$(find "${SB_PROTOCOL_STATE_DIR}" -maxdepth 1 -name 'vless-reality.env.bak.*' -print)" ]]
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
register_warp() { printf 'unexpected WARP registration in isolated legacy acceptance\n' >&2; return 98; }
systemctl() {
  printf '%s\t%s\n' "${RUNTIME_PHASE}" "$*" >> "${ARTIFACT_DIR}/systemctl-calls.tsv"
  if [[ "${RUNTIME_PHASE}" == legacy-first-apply-failure && "${1:-}" == restart &&
        "${2:-}" == sing-box && ! -e "${ARTIFACT_DIR}/restart-injected-once" ]]; then
    : > "${ARTIFACT_DIR}/restart-injected-once"
    return 97
  fi
  command systemctl "$@"
}
cat > "${ARTIFACT_DIR}/proof-boundaries.txt" <<'EOF'
Real sing-box 1.14.2 generation/checks, schema-1 indexed REALITY state, actual
service unit, systemd start/restarts, routing migration/apply/rollback/recover and
private journal backup are exercised. The old working configuration is prepared
with the real renderer, then its original schema-1 env is restored and only the
known preparation-generated state/baseline/backups are removed before testing.
A manually named loopback HTTP control listener proves real service traffic and
operator-config preservation; it is outside managed REALITY policy scope. No
REALITY public handshake or data-plane private filtering is claimed. Global sbv
copying and public-IP lookup use prepared offline boundaries. No WARP/provider,
external network, production, fresh-install or full-suite acceptance is claimed.
EOF

stage legacy-service-prepare
mkdir -p -- "${SB_PROTOCOL_STATE_DIR}"
pair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
private=$(awk '/PrivateKey/ {print $2}' <<< "${pair}")
public=$(awk '/PublicKey/ {print $2}' <<< "${pair}")
[[ -n "${private}" && -n "${public}" ]]
printf 'PRIVATE_KEY=%s\nPUBLIC_KEY=%s\n' "${private}" "${public}" > "${SB_KEY_FILE}"
chmod 600 "${SB_KEY_FILE}"
cat > "${ARTIFACT_DIR}/legacy-original.env" <<EOF
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy-runtime
PORT=${REALITY_PORT}
UUID=11111111-1111-1111-1111-111111111111
SNI=example.com
REALITY_PRIVATE_KEY=${private}
REALITY_PUBLIC_KEY=${public}
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF
cp -p -- "${ARTIFACT_DIR}/legacy-original.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
write_protocol_index vless-reality
SB_ENABLE_WARP=n
SB_ADVANCED_ROUTE=n
SB_WARP_ROUTE_MODE=selective
SB_INBOUND_STACK_MODE=ipv4_only
SB_OUTBOUND_STACK_MODE=prefer_ipv4
save_stack_mode_state
save_warp_route_settings
load_protocol_state vless-reality
generate_config > "${ARTIFACT_DIR}/prepare-generate.log" 2>&1
jq --argjson port "${CONTROL_PROXY_PORT}" '.inbounds += [{type:"http",tag:"operator-http-control",listen:"127.0.0.1",listen_port:$port}]' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/legacy-control-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/legacy-control-config.json" > "${ARTIFACT_DIR}/control-publish.log" 2>&1
# Establish the untouched pre-migration installation, not an adopted v2 state.
cp -p -- "${ARTIFACT_DIR}/legacy-original.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
rm -rf -- "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
rm -f -- "${SB_PROJECT_DIR}/managed-config.generated.json" "${SB_PROJECT_DIR}/managed-config.generated.json.bak"
shopt -s nullglob
PREP_BACKUPS=("${SB_PROTOCOL_STATE_DIR}"/vless-reality.env.bak.*)
if [[ "${#PREP_BACKUPS[@]}" != 0 ]]; then rm -f -- "${PREP_BACKUPS[@]}"; fi
shopt -u nullglob
printf 'preserve this operator file\n' > "${SB_PROJECT_DIR}/operator-note.txt"
[[ ! -e "${SB_ROUTING_POLICY_FILE}" ]]
no_timestamped_backup
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/legacy.check" 2>&1
jq -S '[.inbounds[] | select(.type=="vless" and .tls.reality.enabled==true)]' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/legacy-reality-inbound.json"
jq -e 'length==1' "${ARTIFACT_DIR}/legacy-reality-inbound.json" >/dev/null
setup_service > "${ARTIFACT_DIR}/service-setup.log" 2>&1
systemctl start sing-box
systemctl is-active --quiet sing-box
wait_listener "${REALITY_PORT}"
wait_listener "${CONTROL_PROXY_PORT}"
python3 -u - "${MARKER_PORT}" <<'PY' > "${ARTIFACT_DIR}/marker-server.log" 2>&1 &
import http.server,sys
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b"legacy-routing-marker\n"
        self.send_response(200); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,*_args): pass
http.server.ThreadingHTTPServer(("127.0.0.1",int(sys.argv[1])),Handler).serve_forever()
PY
MARKER_PID=$!
wait_listener "${MARKER_PORT}"
control_marker legacy-control
cp -a -- "${SB_PROJECT_DIR}" "${ARTIFACT_DIR}/legacy-project"
legacy_fingerprint=$(routing_state_fingerprint)
legacy_external=$(routing_state_fingerprint external)
legacy_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")

stage legacy-first-apply-failure
failure_before=$(service_pid)
routing_draft_create "${ARTIFACT_DIR}/failure-draft.json"
jq '.policy.server.rules=[{id:"private-fixture",kind:"ip_cidr",value:"127.0.0.0/8",action:"reject",enabled:true}]' "${ARTIFACT_DIR}/failure-draft.json" > "${ARTIFACT_DIR}/failure-edit.json"
if routing_policy_apply "${ARTIFACT_DIR}/failure-edit.json" > "${ARTIFACT_DIR}/failure-apply.log" 2>&1; then
  printf 'legacy migration unexpectedly committed after injected restart failure\n' >&2
  exit 1
fi
[[ -f "${ARTIFACT_DIR}/restart-injected-once" && "$(restart_count legacy-first-apply-failure)" == 2 ]]
failure_after=$(service_pid)
[[ "${failure_before}" != 0 && "${failure_after}" != 0 && "${failure_before}" != "${failure_after}" ]]
systemctl is-active --quiet sing-box
[[ "$(routing_state_fingerprint)" == "${legacy_fingerprint}" &&
   "$(routing_state_fingerprint external)" == "${legacy_external}" &&
   "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${legacy_config}" ]]
cmp "${ARTIFACT_DIR}/legacy-original.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/vless-reality.d" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" &&
   ! -e "${SB_PROJECT_DIR}/managed-config.generated.json" && ! -e "${SB_ROUTING_POLICY_FILE}" ]]
no_timestamped_backup
control_marker rollback-control
printf 'failure\tbefore=%s\tafter=%s\trestarts=2\n' "${failure_before}" "${failure_after}" >> "${ARTIFACT_DIR}/service-pids.tsv"
cp -a -- "${SB_PROJECT_DIR}" "${ARTIFACT_DIR}/rollback-project"

stage legacy-first-apply-success
success_before=$(service_pid)
routing_draft_create "${ARTIFACT_DIR}/success-draft.json"
jq '.policy.server.rules=[{id:"private-fixture",kind:"ip_cidr",value:"127.0.0.0/8",action:"reject",enabled:true}]' "${ARTIFACT_DIR}/success-draft.json" > "${ARTIFACT_DIR}/success-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/success-edit.json" > "${ARTIFACT_DIR}/success-apply.log" 2>&1
success_after=$(service_pid)
[[ "$(restart_count legacy-first-apply-success)" == 1 && "${success_before}" != 0 &&
   "${success_after}" != 0 && "${success_before}" != "${success_after}" ]]
systemctl is-active --quiet sing-box
wait_listener "${REALITY_PORT}"
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" ]]
grep -Fxq 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
[[ "$(routing_state_fingerprint external)" == "${legacy_external}" ]]
no_timestamped_backup
routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}"
jq -e '.phase=="committed"' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" >/dev/null
cmp "${ARTIFACT_DIR}/legacy-original.env" "${SB_ROUTING_PREVIOUS_DIR}/legacy-vless-reality.env.bak"
[[ "$(stat -c %a "${SB_ROUTING_PREVIOUS_DIR}/legacy-vless-reality.env.bak")" == 600 ]]
cmp "${ARTIFACT_DIR}/legacy-original.env" "${SB_ROUTING_PREVIOUS_DIR}/snapshot/project/protocols/vless-reality.env"
jq -e '.schema_version==2 and .server.rules[0].id=="private-fixture"' "${SB_ROUTING_POLICY_FILE}" >/dev/null
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/migrated.check" 2>&1
jq -S '[.inbounds[] | select(.type=="vless" and .tls.reality.enabled==true)]' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/migrated-reality-inbound.json"
cmp "${ARTIFACT_DIR}/legacy-reality-inbound.json" "${ARTIFACT_DIR}/migrated-reality-inbound.json"
control_marker migrated-control
printf 'success\tbefore=%s\tafter=%s\trestarts=1\n' "${success_before}" "${success_after}" >> "${ARTIFACT_DIR}/service-pids.tsv"

stage legacy-recover-no-pending
before_recover=$(routing_state_fingerprint)
recover_result=0
routing_policy_recover > "${ARTIFACT_DIR}/recover.log" 2>&1 || recover_result=$?
[[ "${recover_result}" == 1 ]]
printf 'exit=%s\npending=false\n' "${recover_result}" > "${ARTIFACT_DIR}/recover.result"
[[ "$(routing_state_fingerprint)" == "${before_recover}" && "$(service_pid)" == "${success_after}" &&
   "$(restart_count legacy-recover-no-pending)" == 0 ]]
stage complete
printf 'Real isolated legacy REALITY migration, restart rollback and recovery acceptance passed\n'
