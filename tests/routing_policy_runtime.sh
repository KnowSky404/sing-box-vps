#!/usr/bin/env bash

# Container-only acceptance: never run against a host or an existing installation.
set -euo pipefail

if [[ "${SBV_ROUTING_RUNTIME_ACCEPTANCE:-}" != 1 || ! -f /.dockerenv ||
      "$(cat /proc/1/comm)" != systemd || ! -f /run/sbv-routing-runtime.sentinel ||
      -z "${SBV_ROUTING_RUNTIME_SENTINEL:-}" ]] ||
   [[ "$(cat /run/sbv-routing-runtime.sentinel)" != "${SBV_ROUTING_RUNTIME_SENTINEL}" ]]; then
  printf 'routing runtime requires its explicitly prepared disposable systemd container\n' >&2
  exit 64
fi
if [[ -e /root/sing-box-vps || -e /etc/systemd/system/sing-box.service ||
      -e /etc/sing-box/config.json || -e /usr/local/etc/sing-box/config.json ||
      -e /root/sing-box-vps.rules-write.lock || -e /root/sing-box-vps.instance-write.lock ||
      ! -x /usr/local/bin/sing-box || ! -f /tmp/install.sh ]] ||
   command systemctl cat sing-box >/dev/null 2>&1; then
  printf 'routing runtime refuses an existing or unprepared installation\n' >&2
  exit 64
fi

readonly ARTIFACT_DIR=/tmp/sbv-routing-runtime-artifacts
readonly HTTP_PROXY_PORT=19082
readonly OPERATOR_HTTP_PROXY_PORT=19083
readonly HTTP_MARKER_PORT=18080
readonly UDP_MARKER_PORT=18081
readonly HY2_PORT=19443
readonly SOCKS_PORT=19080
readonly HTTP_MANUAL_FALLBACK_JSON='{"inbound":"http-in","action":"route","outbound":"direct"}'
mkdir -m 700 "${ARTIFACT_DIR}"
http_pid='' udp_pid='' client_pid=''
DISPLACED_CORE=''
RUNTIME_PHASE=prepare

stop_owned_process() {
  local pid=${1:-} process_result=0
  [[ -n "${pid}" ]] || return 0
  if kill -0 "${pid}" 2>/dev/null; then kill -TERM "${pid}" || return 1; fi
  wait "${pid}" || process_result=$?
  [[ "${process_result}" == 0 || "${process_result}" == 130 || "${process_result}" == 143 ]]
}

runtime_cleanup() {
  local result=$? pid
  trap - EXIT
  if [[ -n "${DISPLACED_CORE}" && -f "${DISPLACED_CORE}" ]]; then
    if [[ ! -e "${SINGBOX_BIN_PATH}" && ! -L "${SINGBOX_BIN_PATH}" ]]; then
      mv -- "${DISPLACED_CORE}" "${SINGBOX_BIN_PATH}" || result=1
    else
      printf 'displaced core retained for diagnosis: %s\n' "${DISPLACED_CORE}" >&2
      result=1
    fi
  fi
  for pid in "${client_pid}" "${udp_pid}" "${http_pid}"; do
    if ! stop_owned_process "${pid}"; then result=1; fi
  done
  if [[ -f /etc/systemd/system/sing-box.service ]]; then
    cp -a /etc/systemd/system/sing-box.service "${ARTIFACT_DIR}/service-unit.txt" || result=1
    command systemctl status sing-box --no-pager > "${ARTIFACT_DIR}/service-final.txt" 2>&1 || {
      [[ "$(command systemctl is-active sing-box)" == inactive ]] || result=1
    }
  fi
  if [[ -f "${ARTIFACT_DIR}/systemctl-calls.tsv" ]]; then
    command systemctl show sing-box --property=LoadState --property=ActiveState --property=MainPID \
      > "${ARTIFACT_DIR}/service-final-state.txt" 2>&1 || result=1
    command journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/service-journal.txt" 2>&1 || result=1
  fi
  if [[ -d /root/sing-box-vps ]]; then
    cp -a /root/sing-box-vps "${ARTIFACT_DIR}/project-final" || result=1
  fi
  printf 'status=%s\nlast_phase=%s\n' "${result}" "${RUNTIME_PHASE}" > "${ARTIFACT_DIR}/result.env"
  exit "${result}"
}
trap runtime_cleanup EXIT
trap 'printf "routing runtime failed at line %s during %s\n" "${LINENO}" "${RUNTIME_PHASE}" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

stage() {
  RUNTIME_PHASE=$1
  printf '[runtime] %s\n' "${RUNTIME_PHASE}"
  printf '%s\t%s\n' "$(date -u +%FT%TZ)" "${RUNTIME_PHASE}" >> "${ARTIFACT_DIR}/stages.tsv"
}

# The real fresh-install detector must see no installed core. The offline
# download boundary publishes this already verified core when installation asks.
/usr/local/bin/sing-box version > "${ARTIFACT_DIR}/core-version.txt"
grep -Fqx 'sing-box version 1.14.2' "${ARTIFACT_DIR}/core-version.txt"
sha256sum /tmp/install.sh /usr/local/bin/sing-box "${BASH_SOURCE[0]}" > "${ARTIFACT_DIR}/sources.sha256"
mv /usr/local/bin/sing-box /tmp/sbv-routing-offline-core
# shellcheck disable=SC1091
source /tmp/install.sh

cat > "${ARTIFACT_DIR}/proof-boundaries.txt" <<'EOF'
Real: main/fresh HTTP input, protocol state, candidate generation, sing-box 1.14.2
checks, systemd unit/activation, firewall, routing drafts/apply/restore, HTTP TCP,
HY2 TLS/QUIC, SOCKS5 UDP ASSOCIATE, local UDP echo, ad allowlists, managed/manual
listener scope, manual selector references/default, foreign fallback order across
typed create/replace, failed-state client-only apply, history purge and rollback.
Prepared boundaries: dependency installation, core download, latest-version and
remote script-status queries, global sbv copying, and public-IP lookup are replaced
with the offline image/core baseline. No WARP account, public network/provider or
production evidence is claimed. The container has no external network interface.
All credentials and the generated self-signed certificate are disposable fixtures.
EOF

install_dependencies() {
  local dependency
  for dependency in jq curl openssl ip ss iptables ip6tables flock python3 systemctl; do
    command -v "${dependency}" >/dev/null || return 1
  done
}
install_binary() {
  [[ "${SB_VERSION}" == 1.14.2 && -x /tmp/sbv-routing-offline-core ]] || return 1
  cp /tmp/sbv-routing-offline-core "${SINGBOX_BIN_PATH}" && chmod 755 "${SINGBOX_BIN_PATH}"
}
get_latest_version() { SB_VERSION=1.14.2; }
ensure_sbv_command_installed() { :; }
check_script_status() { SCRIPT_VER_STATUS='offline fixture'; }
check_sb_version() { SB_VER_STATUS='prepared 1.14.2'; }
get_public_ip() { printf '203.0.113.10'; }
get_public_ipv4() { printf '203.0.113.10'; }
get_public_ipv6() { return 1; }
get_public_ip_candidates() { printf 'IPv4|203.0.113.10\n'; }
register_warp() { printf 'unexpected WARP registration in isolated routing acceptance\n' >&2; return 98; }

# Observe every service command while delegating to real systemd. Only the
# explicitly enabled failure stage suppresses one restart; rollback is real.
systemctl() {
  printf '%s\t%s\n' "${RUNTIME_PHASE}" "$*" >> "${ARTIFACT_DIR}/systemctl-calls.tsv"
  if [[ "${RUNTIME_PHASE}" == restart-failure && "${1:-}" == restart &&
        "${2:-}" == sing-box && ! -f "${ARTIFACT_DIR}/restart-failed-once" ]]; then
    : > "${ARTIFACT_DIR}/restart-failed-once"
    return 97
  fi
  command systemctl "$@"
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
assert_single_restart() {
  local phase=$1 before=$2 after count
  after=$(service_pid)
  count=$(awk -F '\t' -v phase="${phase}" '$1==phase && $2=="restart sing-box" {n++} END {print n+0}' "${ARTIFACT_DIR}/systemctl-calls.tsv")
  [[ "${count}" == 1 && "${before}" != 0 && "${after}" != 0 && "${before}" != "${after}" ]]
  printf '%s\tbefore=%s\tafter=%s\trestarts=%s\n' "${phase}" "${before}" "${after}" "${count}" >> "${ARTIFACT_DIR}/service-pids.tsv"
}

python3 -u - "${HTTP_MARKER_PORT}" <<'PY' > "${ARTIFACT_DIR}/http-marker.log" 2>&1 &
import http.server, sys
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        print("request", self.headers.get("Host"), flush=True)
        body=b"sbv-routing-http-marker\n"
        self.send_response(200); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *_args): pass
http.server.ThreadingHTTPServer(("127.0.0.1",int(sys.argv[1])),Handler).serve_forever()
PY
http_pid=$!
python3 -u - "${UDP_MARKER_PORT}" <<'PY' > "${ARTIFACT_DIR}/udp-marker.log" 2>&1 &
import socket, sys
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
    sock.bind(("127.0.0.1",int(sys.argv[1])))
    while True:
        payload,address=sock.recvfrom(65535)
        print(payload.decode("ascii",errors="replace"),flush=True)
        sock.sendto(payload,address)
PY
udp_pid=$!
wait_listener "${HTTP_MARKER_PORT}"
printf '\n127.0.0.1 allowed.sbv.test ads.sbv.test allow.ads.sbv.test fallback-deny.sbv.test hy2.sbv.test\n' >> /etc/hosts

http_probe() {
  local target=$1 expected=$2 label=$3 proxy_port=${4:-${HTTP_PROXY_PORT}} result=0 response
  local -a authentication=()
  if [[ "${proxy_port}" == "${HTTP_PROXY_PORT}" ]]; then
    authentication=(--proxy-user 'routing-user:routing-fixture-password')
  fi
  response=$(curl --noproxy '' --proxy "http://127.0.0.1:${proxy_port}" \
    "${authentication[@]}" --connect-timeout 3 --max-time 8 \
    --silent --show-error --fail "http://${target}:${HTTP_MARKER_PORT}/marker" \
    2> "${ARTIFACT_DIR}/${label}.stderr") || result=$?
  printf '%s' "${response}" > "${ARTIFACT_DIR}/${label}.response"
  printf 'exit=%s\nexpected=%s\nproxy_port=%s\n' "${result}" "${expected}" "${proxy_port}" > "${ARTIFACT_DIR}/${label}.result"
  if [[ "${expected}" == allowed ]]; then [[ "${result}" == 0 && "${response}" == sbv-routing-http-marker ]];
  else [[ "${result}" != 0 && "${response}" != sbv-routing-http-marker ]]; fi
}

assert_operator_http_preserved() {
  jq -S '.inbounds[] | select(.tag=="operator-http")' "${SINGBOX_CONFIG_FILE}" \
    > "${ARTIFACT_DIR}/operator-http-current.json"
  cmp "${ARTIFACT_DIR}/operator-http-original.json" "${ARTIFACT_DIR}/operator-http-current.json"
  jq -S '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}" \
    > "${ARTIFACT_DIR}/operator-egress-current.json"
  cmp "${ARTIFACT_DIR}/operator-egress-original.json" "${ARTIFACT_DIR}/operator-egress-current.json"
  jq -e '.route.final=="selector-managed" and any(.outbounds[];
    .tag=="selector-managed" and .outbounds==["operator-egress"] and .default=="operator-egress")' \
    "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq -e 'all(.inbounds[]; .tag!="operator-http") and all(.outbounds[]; .tag!="operator-egress") and
    any(.outbounds[]; .tag=="selector-managed" and .outbounds==["operator-egress"])' \
    "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
}

assert_http_fallback_order() {
  local label=$1
  jq -e --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" '
    (.route.rules | to_entries) as $entries |
    [$entries[] | select(.value.action=="reject" and .value.domain==["fallback-deny.sbv.test"]) | .key] as $reject |
    [$entries[] | select(.value==$fallback) | .key] as $manual |
    ($reject|length)==1 and ($manual|length)==1 and $reject[0] < $manual[0]
  ' "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq -e --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" 'all(.route.rules[]; .!=$fallback)' \
    "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
  jq '.route.rules' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/${label}-route-order.json"
}

stage fresh-http-install
(main) > "${ARTIFACT_DIR}/fresh-install.log" 2>&1 <<EOF
1

6
${HTTP_PROXY_PORT}
y
routing-user
routing-fixture-password
n
0
EOF
SB_VERSION=1.14.2
systemctl is-active --quiet sing-box
wait_listener "${HTTP_PROXY_PORT}"
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/fresh.check" 2>&1
jq -e '.server.private_network_block and (.server.adblock|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
jq -e --argjson port "${HTTP_PROXY_PORT}" '.instances[0] |
  .outbound_policy=="default" and .listen.port==$port and
  .authentication=={enabled:true,username:"routing-user",password:"routing-fixture-password"}' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
http_probe 127.0.0.1 blocked default-private-blocked
http_probe allowed.sbv.test blocked default-private-domain-blocked
cp "${SINGBOX_CONFIG_FILE}" "${ARTIFACT_DIR}/fresh-config.json"

stage operator-http-install
before_pid=$(service_pid)
before_operator_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
jq --argjson port "${OPERATOR_HTTP_PROXY_PORT}" '.inbounds += [
  {type:"http",tag:"operator-http",listen:"127.0.0.1",listen_port:$port}] |
  .outbounds += [{type:"direct",tag:"operator-egress",bind_interface:"lo"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/operator-http-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/operator-http-config.json" \
  > "${ARTIFACT_DIR}/operator-http-publish.log" 2>&1
[[ "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_operator_baseline}" ]]
jq -S '.inbounds[] | select(.tag=="operator-http")' "${SINGBOX_CONFIG_FILE}" \
  > "${ARTIFACT_DIR}/operator-http-original.json"
jq -S '.outbounds[] | select(.tag=="operator-egress")' "${SINGBOX_CONFIG_FILE}" \
  > "${ARTIFACT_DIR}/operator-egress-original.json"
systemctl restart sing-box
systemctl is-active --quiet sing-box
assert_single_restart operator-http-install "${before_pid}"
wait_listener "${OPERATOR_HTTP_PROXY_PORT}"
http_probe ads.sbv.test allowed operator-http-before-policy "${OPERATOR_HTTP_PROXY_PORT}"

stage component-selector-create
before_pid=$(service_pid)
printf '%s\n' '{"id":"selector-managed","role":"outbound","type":"selector","tag":"selector-managed","enabled":true,"route_rules":[],"config":{"outbounds":["operator-egress"],"default":"operator-egress"}}' \
  > "${ARTIFACT_DIR}/component-record.json"
managed_component_state_apply create 0 "${ARTIFACT_DIR}/component-record.json" '' n \
  > "${ARTIFACT_DIR}/component-create.log" 2>&1
assert_single_restart component-selector-create "${before_pid}"
systemctl is-active --quiet sing-box

stage operator-default-selector
before_pid=$(service_pid)
before_selector_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
jq '.route.final="selector-managed"' "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/operator-default-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/operator-default-config.json" > "${ARTIFACT_DIR}/operator-default-publish.log" 2>&1
[[ "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_selector_baseline}" ]]
systemctl restart sing-box
systemctl is-active --quiet sing-box
assert_single_restart operator-default-selector "${before_pid}"
assert_operator_http_preserved
http_probe ads.sbv.test allowed selector-operator-marker "${OPERATOR_HTTP_PROXY_PORT}"

stage filter-apply
before_pid=$(service_pid)
routing_draft_create "${ARTIFACT_DIR}/filter-draft.json"
jq '.policy.server.private_network_block=false | .policy.server.adblock=true |
  .policy.adblock.url="" | .policy.adblock.domains=["ads.sbv.test"] |
  .policy.adblock.allow=["allow.ads.sbv.test"]' \
  "${ARTIFACT_DIR}/filter-draft.json" > "${ARTIFACT_DIR}/filter-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/filter-edit.json" > "${ARTIFACT_DIR}/filter-apply.log" 2>&1
assert_single_restart filter-apply "${before_pid}"
http_probe allowed.sbv.test allowed http-allowed
http_probe ads.sbv.test blocked http-ad-blocked
http_probe allow.ads.sbv.test allowed http-ad-allowlist
http_probe ads.sbv.test allowed operator-http-ad-allowed "${OPERATOR_HTTP_PROXY_PORT}"
assert_operator_http_preserved
cp "${SINGBOX_CONFIG_FILE}" "${ARTIFACT_DIR}/filter-config.json"

stage http-direct-override
before_pid=$(service_pid)
revision=$(jq -r '.revision' "${SB_PROTOCOL_STATE_DIR}/instances/http.json")
routing_draft_create "${ARTIFACT_DIR}/node-draft.json"
jq --argjson revision "${revision}" '.node_overrides=[{protocol:"http",id:"main",policy:"direct",revision:$revision}]' \
  "${ARTIFACT_DIR}/node-draft.json" > "${ARTIFACT_DIR}/node-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/node-edit.json" > "${ARTIFACT_DIR}/node-apply.log" 2>&1
assert_single_restart http-direct-override "${before_pid}"
jq -e '.instances[0].outbound_policy=="direct"' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
http_probe allowed.sbv.test allowed direct-http-allowed
http_probe ads.sbv.test blocked direct-http-ad-blocked
http_probe allow.ads.sbv.test allowed direct-http-ad-allowlist
http_probe ads.sbv.test allowed direct-operator-http-ad-allowed "${OPERATOR_HTTP_PROXY_PORT}"
assert_operator_http_preserved

stage http-default-custom-reject
before_pid=$(service_pid)
revision=$(jq -r '.revision' "${SB_PROTOCOL_STATE_DIR}/instances/http.json")
routing_draft_create "${ARTIFACT_DIR}/custom-draft.json"
jq --argjson revision "${revision}" '
  .node_overrides=[{protocol:"http",id:"main",policy:"default",revision:$revision}] |
  .policy.server.rules=[{id:"fallback-deny",kind:"domain",value:"fallback-deny.sbv.test",action:"reject",enabled:true}]
' "${ARTIFACT_DIR}/custom-draft.json" > "${ARTIFACT_DIR}/custom-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/custom-edit.json" > "${ARTIFACT_DIR}/custom-apply.log" 2>&1
assert_single_restart http-default-custom-reject "${before_pid}"
jq -e '.instances[0].outbound_policy=="default"' "${SB_PROTOCOL_STATE_DIR}/instances/http.json" >/dev/null
jq -e --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" 'all(.route.rules[]; .!=$fallback)' \
  "${SB_PROJECT_DIR}/managed-config.generated.json" >/dev/null
http_probe fallback-deny.sbv.test blocked custom-http-denied
http_probe fallback-deny.sbv.test allowed custom-operator-allowed "${OPERATOR_HTTP_PROXY_PORT}"

stage http-manual-fallback-install
before_pid=$(service_pid)
before_fallback_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
jq -e --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" 'all(.route.rules[]; .!=$fallback)' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" '.route.rules += [$fallback]' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/http-manual-fallback-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/http-manual-fallback-config.json" > "${ARTIFACT_DIR}/http-manual-fallback-publish.log" 2>&1
[[ "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_fallback_baseline}" ]]
systemctl restart sing-box
systemctl is-active --quiet sing-box
assert_single_restart http-manual-fallback-install "${before_pid}"
assert_http_fallback_order installed
http_probe fallback-deny.sbv.test blocked installed-fallback-http-denied
http_probe allowed.sbv.test allowed installed-fallback-http-allowed
assert_operator_http_preserved

stage hy2-append
before_pid=$(service_pid)
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=hy2.sbv.test \
  -addext subjectAltName=DNS:hy2.sbv.test -addext basicConstraints=critical,CA:TRUE \
  -keyout "${ARTIFACT_DIR}/hy2.key" -out "${ARTIFACT_DIR}/hy2.crt" > "${ARTIFACT_DIR}/openssl.log" 2>&1
jq -n --arg cert "${ARTIFACT_DIR}/hy2.crt" --arg key "${ARTIFACT_DIR}/hy2.key" --argjson port "${HY2_PORT}" '
  {id:"routing-hy2",name:"Routing HY2",tag:"hy2-routing-runtime",listen:{address:"127.0.0.1",port:$port},
   authentication:{users:[{name:"routing-hy2",password:"routing-hy2-fixture-password"}]},
   tls:{enabled:true,server_name:"hy2.sbv.test",certificate_path:$cert,key_path:$key},client_trust:"certificate",
   bandwidth:{up_mbps:null,down_mbps:null},obfs:{enabled:false,type:"",password:""},masquerade:"",
   outbound_policy:"default",dependencies:[]}' > "${ARTIFACT_DIR}/hy2-record.json"
apply_plain_proxy_instance_change hy2 create 0 "${ARTIFACT_DIR}/hy2-record.json" n > "${ARTIFACT_DIR}/hy2-create.json" 2> "${ARTIFACT_DIR}/hy2-create.log"
jq -e '.ok==true and .revision==1' "${ARTIFACT_DIR}/hy2-create.json" >/dev/null
jq -e '.instances[0].outbound_policy=="default"' "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
assert_single_restart hy2-append "${before_pid}"
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/hy2-server.check" 2>&1
systemctl is-active --quiet sing-box
assert_http_fallback_order hy2-created
http_probe fallback-deny.sbv.test blocked created-fallback-http-denied
http_probe ads.sbv.test blocked typed-http-ad-blocked
http_probe allow.ads.sbv.test allowed typed-http-ad-allowlist
http_probe ads.sbv.test allowed typed-operator-http-ad-allowed "${OPERATOR_HTTP_PROXY_PORT}"
assert_operator_http_preserved
cp "${SINGBOX_CONFIG_FILE}" "${ARTIFACT_DIR}/hy2-created-config.json"

stage hy2-replace-direct
before_pid=$(service_pid)
jq '.outbound_policy="direct"' "${ARTIFACT_DIR}/hy2-record.json" > "${ARTIFACT_DIR}/hy2-replacement-record.json"
apply_plain_proxy_instance_change hy2 replace 1 "${ARTIFACT_DIR}/hy2-replacement-record.json" n \
  > "${ARTIFACT_DIR}/hy2-replace.json" 2> "${ARTIFACT_DIR}/hy2-replace.log"
jq -e '.ok==true and .revision==2' "${ARTIFACT_DIR}/hy2-replace.json" >/dev/null
jq -e '.instances[0].outbound_policy=="direct"' "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
assert_single_restart hy2-replace-direct "${before_pid}"
systemctl is-active --quiet sing-box
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/hy2-replaced-server.check" 2>&1
assert_http_fallback_order hy2-replaced
http_probe fallback-deny.sbv.test blocked replaced-fallback-http-denied
http_probe ads.sbv.test blocked replaced-http-ad-blocked
http_probe allow.ads.sbv.test allowed replaced-http-ad-allowlist
http_probe ads.sbv.test allowed replaced-operator-http-ad-allowed "${OPERATOR_HTTP_PROXY_PORT}"
assert_operator_http_preserved
cp "${SINGBOX_CONFIG_FILE}" "${ARTIFACT_DIR}/typed-config.json"
build_client_hy2_outbounds 127.0.0.1 > "${ARTIFACT_DIR}/hy2-outbounds.jsonl" 2> "${ARTIFACT_DIR}/hy2-client-export.log"
jq -s --argjson port "${SOCKS_PORT}" '{log:{level:"debug"},dns:{servers:[{type:"local",tag:"local"}]},
  inbounds:[{type:"socks",tag:"fixture-socks",listen:"127.0.0.1",listen_port:$port}],
  outbounds:.,route:{final:.[0].tag,default_domain_resolver:"local"}}' \
  "${ARTIFACT_DIR}/hy2-outbounds.jsonl" > "${ARTIFACT_DIR}/hy2-client.json"
"${SINGBOX_BIN_PATH}" check -c "${ARTIFACT_DIR}/hy2-client.json" > "${ARTIFACT_DIR}/hy2-client.check" 2>&1
"${SINGBOX_BIN_PATH}" run -c "${ARTIFACT_DIR}/hy2-client.json" > "${ARTIFACT_DIR}/hy2-client.log" 2>&1 &
client_pid=$!
wait_listener "${SOCKS_PORT}"

stage hy2-udp-filter
python3 - "${SOCKS_PORT}" "${UDP_MARKER_PORT}" <<'PY' > "${ARTIFACT_DIR}/hy2-udp.result.json"
import json, socket, struct, sys
socks_port, target_port = map(int, sys.argv[1:])
def exact(conn, size):
    data=b""
    while len(data)<size:
        chunk=conn.recv(size-len(data))
        if not chunk: raise RuntimeError("closed SOCKS control")
        data+=chunk
    return data
def probe(host, payload, blocked):
    with socket.create_connection(("127.0.0.1",socks_port),timeout=8) as control:
        control.settimeout(8); control.sendall(b"\x05\x01\x00")
        assert exact(control,2)==b"\x05\x00"
        control.sendall(b"\x05\x03\x00\x01"+b"\0"*6)
        reply=exact(control,4); assert reply[:2]==b"\x05\x00",reply
        if reply[3]==1: address=socket.inet_ntoa(exact(control,4))
        elif reply[3]==4: address=socket.inet_ntop(socket.AF_INET6,exact(control,16))
        else: address=exact(control,exact(control,1)[0]).decode()
        port=struct.unpack("!H",exact(control,2))[0]
        if address in ("0.0.0.0","::"): address="127.0.0.1"
        target=(b"\x01"+socket.inet_aton(host)) if host=="127.0.0.1" else (b"\x03"+bytes([len(host)])+host.encode())
        packet=b"\0\0\0"+target+struct.pack("!H",target_port)+payload
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as udp:
            udp.settimeout(3 if blocked else 8); udp.sendto(packet,(address,port))
            try: data,_peer=udp.recvfrom(65535)
            except socket.timeout:
                if blocked: return "timeout"
                raise
        if blocked: raise AssertionError("advertising domain returned a UDP reply")
        assert data[:3]==b"\0\0\0",data
        offset={1:8,4:20}.get(data[3])
        if data[3]==3: offset=5+data[4]
        assert offset is not None and data[offset+2:]==payload,data
        return "echo"
allowed=probe("127.0.0.1",b"sbv-routing-udp-marker",False)
allowed_domain=probe("allowed.sbv.test",b"sbv-routing-domain-udp-marker",False)
allowed_ad_domain=probe("allow.ads.sbv.test",b"sbv-routing-ad-allowlist-udp-marker",False)
denied=probe("ads.sbv.test",b"sbv-ads-should-not-reach-echo",True)
print(json.dumps({"hy2_udp_allowed":allowed,"hy2_domain_udp_allowed":allowed_domain,
                  "hy2_ad_allowlist_udp_allowed":allowed_ad_domain,
                  "ad_domain_udp_rejected":denied}))
PY
! grep -Fq sbv-ads-should-not-reach-echo "${ARTIFACT_DIR}/udp-marker.log"
stop_owned_process "${client_pid}"; client_pid=''

stage restart-failure
before_failure_pid=$(service_pid)
before_fingerprint=$(routing_state_fingerprint)
before_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
routing_draft_create "${ARTIFACT_DIR}/failure-draft.json"
jq '.policy.server.warp_ai |= not' "${ARTIFACT_DIR}/failure-draft.json" > "${ARTIFACT_DIR}/failure-edit.json"
if routing_policy_apply "${ARTIFACT_DIR}/failure-edit.json" > "${ARTIFACT_DIR}/failure-apply.log" 2>&1; then
  printf 'injected restart failure unexpectedly committed\n' >&2
  exit 1
fi
[[ -f "${ARTIFACT_DIR}/restart-failed-once" && ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
[[ "$(routing_state_fingerprint)" == "${before_fingerprint}" && "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config}" ]]
systemctl is-active --quiet sing-box
after_failure_pid=$(service_pid)
[[ "${before_failure_pid}" != 0 && "${after_failure_pid}" != 0 && "${before_failure_pid}" != "${after_failure_pid}" ]]
[[ "$(awk -F '\t' '$1=="restart-failure" && $2=="restart sing-box" {n++} END {print n+0}' "${ARTIFACT_DIR}/systemctl-calls.tsv")" == 2 ]]
printf 'restart-failure\tbefore=%s\tafter=%s\n' "${before_failure_pid}" "${after_failure_pid}" >> "${ARTIFACT_DIR}/service-pids.tsv"
http_probe allowed.sbv.test allowed rollback-http-allowed
http_probe ads.sbv.test blocked rollback-http-ad-blocked
http_probe allow.ads.sbv.test allowed rollback-http-ad-allowlist
http_probe ads.sbv.test allowed rollback-operator-http-ad-allowed "${OPERATOR_HTTP_PROXY_PORT}"
assert_operator_http_preserved
assert_http_fallback_order rollback
http_probe fallback-deny.sbv.test blocked rollback-fallback-http-denied

stage http-manual-fallback-remove
before_pid=$(service_pid)
before_fallback_removal_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
jq -e --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" '[.route.rules[] | select(.==$fallback)] | length==1' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
jq --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" '.route.rules |= map(select(.!=$fallback))' \
  "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/http-fallback-removed-config.json"
publish_managed_config_candidate "${ARTIFACT_DIR}/http-fallback-removed-config.json" > "${ARTIFACT_DIR}/http-fallback-removal.log" 2>&1
[[ "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_fallback_removal_baseline}" ]]
systemctl restart sing-box
systemctl is-active --quiet sing-box
assert_single_restart http-manual-fallback-remove "${before_pid}"
jq -e --argjson fallback "${HTTP_MANUAL_FALLBACK_JSON}" 'all(.route.rules[]; .!=$fallback)' "${SINGBOX_CONFIG_FILE}" >/dev/null
http_probe fallback-deny.sbv.test blocked removed-fallback-http-denied
http_probe allowed.sbv.test allowed removed-fallback-http-allowed
assert_operator_http_preserved

stage stopped-apply
systemctl stop sing-box
singbox_service_confirmed_stopped
before_stopped_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
before_stopped_policy=$(sha256sum "${SB_ROUTING_POLICY_FILE}")
routing_draft_create "${ARTIFACT_DIR}/stopped-draft.json"
jq '.policy.server.private_network_block=true' "${ARTIFACT_DIR}/stopped-draft.json" > "${ARTIFACT_DIR}/stopped-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/stopped-edit.json" > "${ARTIFACT_DIR}/stopped-apply.log" 2>&1
singbox_service_confirmed_stopped
[[ "$(service_pid)" == 0 ]]
[[ "$(awk -F '\t' '$1=="stopped-apply" && $2 ~ /^(start|restart) sing-box$/ {n++} END {print n+0}' "${ARTIFACT_DIR}/systemctl-calls.tsv")" == 0 ]]

stage explicit-restore
routing_policy_restore_previous > "${ARTIFACT_DIR}/restore.log" 2>&1
singbox_service_confirmed_stopped
[[ "$(service_pid)" == 0 ]]
[[ "$(awk -F '\t' '$1=="explicit-restore" && $2 ~ /^(start|restart) sing-box$/ {n++} END {print n+0}' "${ARTIFACT_DIR}/systemctl-calls.tsv")" == 0 ]]
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_stopped_config}" && "$(sha256sum "${SB_ROUTING_POLICY_FILE}")" == "${before_stopped_policy}" ]]
[[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" ]]
"${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${ARTIFACT_DIR}/final.check" 2>&1
iptables-save > "${ARTIFACT_DIR}/iptables-final.txt"
ip6tables-save > "${ARTIFACT_DIR}/ip6tables-final.txt"

stage failed-service-prepare
before_failed_core=$(sha256sum "${SINGBOX_BIN_PATH}")
before_failed_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
before_failed_baseline=$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")
command systemctl show sing-box --property=StartLimitBurst --property=StartLimitIntervalUSec \
  > "${ARTIFACT_DIR}/failed-service-limits.txt"
DISPLACED_CORE=$(mktemp /usr/local/bin/.sbv-routing-core.XXXXXX)
mv -- "${SINGBOX_BIN_PATH}" "${DISPLACED_CORE}"
failed_baseline=n
# Exhaust the original unit's bounded start limit so Restart=on-failure cannot
# relaunch it after the exact core is restored. Unit/config/baseline stay intact.
for attempt in {1..12}; do
  start_result=0
  systemctl start sing-box >> "${ARTIFACT_DIR}/failed-service-start.log" 2>&1 || start_result=$?
  for poll in {1..20}; do
    activity=$(command systemctl show sing-box --property=ActiveState --value)
    unit_result=$(command systemctl show sing-box --property=Result --value)
    [[ "${unit_result}" == success ]] || break
    sleep 0.05
  done
  printf 'attempt=%s status=%s active=%s result=%s\n' "${attempt}" "${start_result}" "${activity}" "${unit_result}" \
    >> "${ARTIFACT_DIR}/failed-service-attempts.txt"
  if [[ "${activity}" == failed && "${start_result}" != 0 &&
        "$(command systemctl show sing-box --property=SubState --value)" == failed &&
        -z "$(command systemctl show sing-box --property=Job --value)" ]]; then
    failed_baseline=y
    break
  fi
  systemctl stop sing-box
done
mv -- "${DISPLACED_CORE}" "${SINGBOX_BIN_PATH}"
DISPLACED_CORE=''
[[ "${failed_baseline}" == y && "${start_result}" != 0 && "$(sha256sum "${SINGBOX_BIN_PATH}")" == "${before_failed_core}" ]]
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_failed_config}" &&
   "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_failed_baseline}" ]]
[[ "$(command systemctl show sing-box --property=ActiveState --value)" == failed ]]

stage failed-client-apply
routing_draft_create "${ARTIFACT_DIR}/purge-client-draft.json"
jq '.policy.client.lan_direct |= not' "${ARTIFACT_DIR}/purge-client-draft.json" > "${ARTIFACT_DIR}/purge-client-edit.json"
routing_policy_apply "${ARTIFACT_DIR}/purge-client-edit.json" > "${ARTIFACT_DIR}/purge-client-apply.log" 2>&1
[[ "$(command systemctl show sing-box --property=ActiveState --value)" == failed && "$(service_pid)" == 0 ]]
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_failed_config}" &&
   "$(sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json")" == "${before_failed_baseline}" ]]
[[ "$(awk -F '\t' '$1=="failed-client-apply" && $2 ~ /^(start|restart) sing-box$/ {n++} END {print n+0}' "${ARTIFACT_DIR}/systemctl-calls.tsv")" == 0 ]]
[[ -d "${SB_ROUTING_PREVIOUS_DIR}" && ! -L "${SB_ROUTING_PREVIOUS_DIR}" ]]
routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}"
jq -e '.phase=="committed" and .before_active==false and .service_changed==false' \
  "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" >/dev/null

stage history-purge
readonly UNMANAGED_SIBLING="${SB_PROJECT_DIR}.unmanaged-neighbor"
[[ ! -e "${SBV_BIN_PATH}" && ! -L "${SBV_BIN_PATH}" && ! -e "${UNMANAGED_SIBLING}" ]]
cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
printf 'disposable routing acceptance sbv stub\n'
EOF
chmod 755 "${SBV_BIN_PATH}"
mkdir -m 700 -- "${UNMANAGED_SIBLING}"
printf 'retain this unmanaged sibling\n' > "${UNMANAGED_SIBLING}/marker"
before_sibling=$(sha256sum "${UNMANAGED_SIBLING}/marker")
mkdir -m 700 -- "${ARTIFACT_DIR}/before-purge"
cp -a -- "${SB_PROJECT_DIR}" "${ARTIFACT_DIR}/before-purge/project"
cp -a -- "${SB_ROUTING_PREVIOUS_DIR}" "${ARTIFACT_DIR}/before-purge/rules-previous"
cp -a -- "${SINGBOX_BIN_PATH}" "${SBV_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" "${ARTIFACT_DIR}/before-purge/"
cp -a -- "${UNMANAGED_SIBLING}" "${ARTIFACT_DIR}/before-purge/unmanaged-neighbor"
command systemctl status sing-box --no-pager > "${ARTIFACT_DIR}/before-purge/service-status.txt" 2>&1 || {
  [[ "$(command systemctl show sing-box --property=ActiveState --value)" == failed ]]
}
sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json" \
  "${SB_ROUTING_PREVIOUS_DIR}/transaction.json" "${SINGBOX_BIN_PATH}" "${SBV_BIN_PATH}" \
  > "${ARTIFACT_DIR}/before-purge/sources.sha256"
perform_full_uninstall > "${ARTIFACT_DIR}/history-purge.log" 2>&1
for removed_path in "${SB_PROJECT_DIR}" "${SB_ROUTING_PREVIOUS_DIR}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" "${SBV_BIN_PATH}"; do
  [[ ! -e "${removed_path}" && ! -L "${removed_path}" ]]
  printf 'removed=%s\n' "${removed_path}" >> "${ARTIFACT_DIR}/history-purge.result"
done
[[ "$(command systemctl show sing-box --property=LoadState --value)" == not-found ]]
[[ "$(sha256sum "${UNMANAGED_SIBLING}/marker")" == "${before_sibling}" ]]
printf 'unit=not-found\nunmanaged_sibling=retained\n' >> "${ARTIFACT_DIR}/history-purge.result"
stage complete
printf 'Real isolated routing acceptance passed: HTTP, HY2 UDP, filters, override, rollback, restore and history purge\n'
