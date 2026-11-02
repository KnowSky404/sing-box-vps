#!/usr/bin/env bash
# Disposable systemd-container acceptance only; never target a host installation.
set -euo pipefail
if [[ "${SBV_ROUTING_RUNTIME_ACCEPTANCE:-}" != 1 || ! -f /.dockerenv ||
      "$(cat /proc/1/comm)" != systemd || ! -f /run/sbv-routing-runtime.sentinel ||
      -z "${SBV_ROUTING_RUNTIME_SENTINEL:-}" ||
      "$(cat /run/sbv-routing-runtime.sentinel)" != "${SBV_ROUTING_RUNTIME_SENTINEL}" ]]; then
  printf 'routing runtime requires its explicitly prepared disposable systemd container\n' >&2
  exit 64
fi
if [[ -e /root/sing-box-vps || -e /etc/systemd/system/sing-box.service ||
      ! -x /usr/local/bin/sing-box || ! -f /tmp/install.sh ]] ||
   command systemctl cat sing-box >/dev/null 2>&1; then
  printf 'routing runtime refuses an existing or unprepared installation\n' >&2
  exit 64
fi
readonly ARTIFACT_DIR=/tmp/sbv-routing-runtime-artifacts
mkdir -m 700 "${ARTIFACT_DIR}"
http_pid='' udp_pid='' RUNTIME_PHASE=prepare
runtime_cleanup() {
  local result=$? pid
  trap - EXIT
  for pid in "${http_pid}" "${udp_pid}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" 2>/dev/null; then kill -TERM "${pid}" || result=1; fi
    wait "${pid}" || { [[ "$?" == 143 ]] || result=1; }
  done
  command journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/service-journal.txt" || result=1
  if [[ -d /root/sing-box-vps ]]; then
    cp -a /root/sing-box-vps "${ARTIFACT_DIR}/project-final" || result=1
  fi
  printf 'status=%s\nlast_phase=%s\n' "${result}" "${RUNTIME_PHASE}" > "${ARTIFACT_DIR}/result.env"
  exit "${result}"
}
trap runtime_cleanup EXIT
trap 'printf "routing runtime failed at line %s phase %s\n" "${LINENO}" "${RUNTIME_PHASE}" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM
stage() { RUNTIME_PHASE=$1; printf '[runtime] %s\n' "$1"; }
source /tmp/install.sh
/usr/local/bin/sing-box version > "${ARTIFACT_DIR}/core-version.txt"
grep -Fxq 'sing-box version 1.14.2' "${ARTIFACT_DIR}/core-version.txt"
sha256sum /tmp/install.sh /usr/local/bin/sing-box "${BASH_SOURCE[0]}" > "${ARTIFACT_DIR}/sources.sha256"
cat > "${ARTIFACT_DIR}/proof-boundaries.txt" <<'EOF'
Real: fresh installer orchestration, HTTP and SOCKS listeners, sing-box 1.14.2,
systemd, managed firewall, CN domain/IP TCP and UDP filtering, node inheritance,
network-file preservation, legacy cleanup and transactional service rollback.
Prepared: node prompt answers, already installed dependencies/core, public-IP
lookup and deterministic inline CN datasets (domain cn.fixture.invalid and
127.0.0.2/32). No actual geo database/source download, Cloudflare WARP account,
public egress, SubMan write or production acceptance. External network disabled.
EOF
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
# Keep production projection/rule order; replace only remote data with fixtures.
eval "$(declare -f routing_policy_render_server_json | sed '1s/routing_policy_render_server_json/routing_policy_runtime_render_real/')"
routing_policy_render_server_json() {
  routing_policy_runtime_render_real "$@" | jq '.rule_sets |= map(
    if .tag == "sbv-block-geosite-cn" then
      {type:"inline",tag:.tag,rules:[{domain:["cn.fixture.invalid"]}]}
    elif .tag == "sbv-block-geoip-cn" then
      {type:"inline",tag:.tag,rules:[{ip_cidr:["127.0.0.2/32"]}]}
    else . end)'
}
systemctl() {
  printf '%s\t%s\n' "${RUNTIME_PHASE}" "$*" >> "${ARTIFACT_DIR}/systemctl-calls.tsv"
  if [[ "${RUNTIME_PHASE}" == restart-failure && "${1:-}" == restart &&
        "${2:-}" == sing-box && ! -e "${ARTIFACT_DIR}/failed-once" ]]; then
    : > "${ARTIFACT_DIR}/failed-once"
    return 97
  fi
  command systemctl "$@"
}
wait_listener() {
  local port=$1 attempt
  for attempt in {1..80}; do
    if ss -H -lnt | awk -v p="${port}" '$4 ~ (":"p"$") {f=1} END {exit !f}'; then return 0; fi
    sleep 0.1
  done
  return 1
}
python3 -u - <<'PY' > "${ARTIFACT_DIR}/http-marker.log" 2>&1 &
import http.server
class Handler(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  body=b'sbv-server-marker\n'
  self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body)
 def log_message(self,*_): pass
http.server.ThreadingHTTPServer(('0.0.0.0',18080),Handler).serve_forever()
PY
http_pid=$!
python3 -u - <<'PY' > "${ARTIFACT_DIR}/udp-marker.log" 2>&1 &
import socket
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
 s.bind(('0.0.0.0',18081))
 while True:
  p,a=s.recvfrom(65535);s.sendto(p,a)
PY
udp_pid=$!
printf '\n127.0.0.1 cn.fixture.invalid allowed.fixture.invalid\n' >> /etc/hosts
wait_listener 18080
http_probe() {
  local target=$1 expect=$2 port=${3:-19082} result=0 response
  response=$(curl --noproxy '' --proxy "http://127.0.0.1:${port}" --connect-timeout 2 --max-time 3 \
    --silent --show-error --fail "http://${target}:18080/" 2> "${ARTIFACT_DIR}/${RUNTIME_PHASE}-${target}-${port}.stderr") || result=$?
  if [[ "${expect}" == allow ]]; then [[ "${result}" == 0 && "${response}" == sbv-server-marker ]]; else [[ "${result}" != 0 ]]; fi
}
network_fingerprint() {
  local path
  for path in "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_KEY_FILE}" "${SB_WARP_ROUTE_SETTINGS_FILE}" \
    "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}"; do
    if [[ -f "${path}" ]]; then sha256sum "${path}"; else printf 'absent:%s\n' "${path}"; fi
  done
}
stage fresh-install
install_protocols_interactive fresh > "${ARTIFACT_DIR}/fresh-install.log" 2>&1 </dev/null
wait_listener 19082
for path in "${SB_ROUTING_POLICY_FILE}" "${SB_WARP_KEY_FILE}" "${SB_WARP_ROUTE_SETTINGS_FILE}" \
  "${SB_WARP_DOMAINS_FILE}" "${SB_WARP_REMOTE_RULESETS_FILE}" "${SB_WARP_LOCAL_RULESET_DIR}"; do [[ ! -e "${path}" ]]; done
http_probe 127.0.0.1 allow
http_probe 127.0.0.2 allow
http_probe cn.fixture.invalid allow
stage block-cn-apply
routing_draft_create "${ARTIFACT_DIR}/draft.json"
jq '.policy.server.block_cn=true' "${ARTIFACT_DIR}/draft.json" > "${ARTIFACT_DIR}/cn.json"
routing_policy_apply "${ARTIFACT_DIR}/cn.json" > "${ARTIFACT_DIR}/cn-apply.log" 2>&1
wait_listener 19082
http_probe 127.0.0.1 allow
http_probe 127.0.0.2 reject
http_probe cn.fixture.invalid reject
http_probe allowed.fixture.invalid allow
[[ "$(awk -F '\t' '$1=="block-cn-apply" && $2=="restart sing-box" {n++} END{print n+0}' "${ARTIFACT_DIR}/systemctl-calls.tsv")" == 1 ]]
network_fingerprint > "${ARTIFACT_DIR}/network.before"
stage add-node
jq -n '{id:"added",name:"Added HTTP",tag:"http-added",listen:{address:"127.0.0.1",port:19083},
 authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[],tls:{enabled:false}}' > "${ARTIFACT_DIR}/http.json"
revision=$(jq -r .revision "$(plain_proxy_structured_store_file http)")
apply_plain_proxy_instance_change http create "${revision}" "${ARTIFACT_DIR}/http.json" n > "${ARTIFACT_DIR}/create.json"
wait_listener 19083
network_fingerprint > "${ARTIFACT_DIR}/network.after"
cmp "${ARTIFACT_DIR}/network.before" "${ARTIFACT_DIR}/network.after"
http_probe 127.0.0.1 allow 19083
http_probe 127.0.0.2 reject 19083
http_probe cn.fixture.invalid reject 19083
stage node-direct-cannot-bypass
routing_draft_create "${ARTIFACT_DIR}/draft.json"
revision=$(jq -r .revision "$(plain_proxy_structured_store_file http)")
jq --argjson revision "${revision}" '.node_overrides=[{protocol:"http",id:"added",policy:"direct",revision:$revision}]' \
  "${ARTIFACT_DIR}/draft.json" > "${ARTIFACT_DIR}/direct.json"
routing_policy_apply "${ARTIFACT_DIR}/direct.json" > "${ARTIFACT_DIR}/direct-apply.log" 2>&1
http_probe 127.0.0.1 allow 19083
http_probe 127.0.0.2 reject 19083
http_probe cn.fixture.invalid reject 19083
stage udp-node
jq -n '{id:"udp",name:"UDP SOCKS",tag:"socks-udp",listen:{address:"127.0.0.1",port:19080},
 authentication:{enabled:false,username:"",password:""},outbound_policy:"default",dependencies:[]}' > "${ARTIFACT_DIR}/socks.json"
network_fingerprint > "${ARTIFACT_DIR}/network.before-udp"
apply_plain_proxy_instance_change socks create 0 "${ARTIFACT_DIR}/socks.json" n > "${ARTIFACT_DIR}/socks-create.json"
network_fingerprint > "${ARTIFACT_DIR}/network.after-udp"
cmp "${ARTIFACT_DIR}/network.before-udp" "${ARTIFACT_DIR}/network.after-udp"
wait_listener 19080
python3 - <<'PY' > "${ARTIFACT_DIR}/udp-result.txt"
import socket,struct
for dst,allowed in [('127.0.0.1',True),('127.0.0.2',False)]:
 with socket.create_connection(('127.0.0.1',19080),timeout=3) as tcp:
  tcp.sendall(b'\x05\x01\x00'); assert tcp.recv(2)==b'\x05\x00'
  tcp.sendall(b'\x05\x03\x00\x01'+socket.inet_aton('127.0.0.1')+b'\x00\x00')
  reply=tcp.recv(64);assert reply[:2]==b'\x05\x00'
  if reply[3]==1: host=socket.inet_ntoa(reply[4:8]);port=struct.unpack('!H',reply[8:10])[0]
  elif reply[3]==4: host=socket.inet_ntop(socket.AF_INET6,reply[4:20]);port=struct.unpack('!H',reply[20:22])[0]
  else: raise AssertionError(reply)
  family=socket.AF_INET6 if ':' in host else socket.AF_INET
  with socket.socket(family,socket.SOCK_DGRAM) as udp:
   udp.settimeout(2); marker=b'sbv-cn-udp-marker'
   udp.sendto(b'\x00\x00\x00\x01'+socket.inet_aton(dst)+struct.pack('!H',18081)+marker,(host,port))
   try: body,_=udp.recvfrom(4096);received=body.endswith(marker)
   except socket.timeout: received=False
   assert received==allowed,(dst,received)
   print(dst,'allowed' if allowed else 'rejected')
PY
stage restart-failure
network_fingerprint > "${ARTIFACT_DIR}/before-failure"
routing_draft_create "${ARTIFACT_DIR}/draft.json"
jq '.policy.server.block_cn=false' "${ARTIFACT_DIR}/draft.json" > "${ARTIFACT_DIR}/off.json"
if routing_policy_apply "${ARTIFACT_DIR}/off.json" > "${ARTIFACT_DIR}/failure.log" 2>&1; then exit 1; fi
network_fingerprint > "${ARTIFACT_DIR}/after-failure"
cmp "${ARTIFACT_DIR}/before-failure" "${ARTIFACT_DIR}/after-failure"
command systemctl is-active --quiet sing-box
http_probe 127.0.0.2 reject
stage legacy-preservation
# Seed a previous release's valid state to test an existing installation, rather
# than adding a removed feature through the new UI.
legacy=$(routing_policy_read_json | jq -c '{schema_version:1,
 server:(.server|del(.block_cn)|. + {private_network_block:true,adblock:true}),
 client:{lan_direct:true,cn_direct:true,adblock:false},
 adblock:{url:"",domains:["ads.fixture.invalid"],allow:[]}}')
printf '%s\n' "${legacy}" > "${SB_ROUTING_POLICY_FILE}"
chmod 600 "${SB_ROUTING_POLICY_FILE}"
generate_config > "${ARTIFACT_DIR}/legacy-seed.log" 2>&1
command systemctl restart sing-box
cp "${SB_ROUTING_POLICY_FILE}" "${ARTIFACT_DIR}/legacy.before"
jq '.name="Renamed HTTP"' "${ARTIFACT_DIR}/http.json" > "${ARTIFACT_DIR}/renamed.json"
revision=$(jq -r .revision "$(plain_proxy_structured_store_file http)")
# Network menu owns direct override; an edit carries forward the stored policy.
jq '.outbound_policy="direct"' "${ARTIFACT_DIR}/renamed.json" > "${ARTIFACT_DIR}/replace.json"
apply_plain_proxy_instance_change http replace "${revision}" "${ARTIFACT_DIR}/replace.json" n > "${ARTIFACT_DIR}/replace-result.json"
cmp "${ARTIFACT_DIR}/legacy.before" "${SB_ROUTING_POLICY_FILE}"
jq -e 'any(.route.rules[]; .ip_is_private==true and .action=="reject") and any(.route.rule_set[]; .tag=="sbv-adblock-inline")' "${SINGBOX_CONFIG_FILE}" >/dev/null
http_probe 127.0.0.1 reject
stage explicit-cleanup
routing_draft_create "${ARTIFACT_DIR}/draft.json"
routing_policy_apply "${ARTIFACT_DIR}/draft.json" > "${ARTIFACT_DIR}/cleanup.log" 2>&1
jq -e '.schema_version==2 and (keys|sort)==["schema_version","server"]' "${SB_ROUTING_POLICY_FILE}" >/dev/null
jq -e 'all(.route.rules[]; .ip_is_private!=true) and all(.route.rule_set[]; .tag!="sbv-adblock-inline")' "${SINGBOX_CONFIG_FILE}" >/dev/null
http_probe 127.0.0.1 allow
stage restore-legacy
routing_policy_restore_previous > "${ARTIFACT_DIR}/restore.log" 2>&1
cmp "${ARTIFACT_DIR}/legacy.before" "${SB_ROUTING_POLICY_FILE}"
http_probe 127.0.0.1 reject
stage complete
printf 'server-only network runtime passed\n'
