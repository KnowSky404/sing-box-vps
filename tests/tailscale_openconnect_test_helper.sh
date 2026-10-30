#!/usr/bin/env bash

set -euo pipefail
[[ "${SBV_COMPONENT_RUNTIME:-}" == 1 && -f /.dockerenv && -f /tmp/sbv-component-disposable ]] || {
  printf 'requires explicitly marked disposable Docker fixture\n' >&2; exit 64;
}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARTIFACT_DIR=/tmp/ts-oc-runtime
HEADSCALE_CONFIG="${ARTIFACT_DIR}/headscale/config.yaml"
mkdir -p "${ARTIFACT_DIR}/headscale"
chmod 700 "${ARTIFACT_DIR}"
trap 'printf "Tailscale/OpenConnect fixture failed at line %s\n" "${LINENO}" >&2' ERR
[[ "$(/usr/local/bin/sing-box version | sed -n 's/^sing-box version //p')" == 1.14.2 ]]
if [[ "${1:-}" == counterpart ]]; then
  [[ "$(dpkg-query -W -f='${Version}' ocserv)" == 1.1.6-3 ]]
else
  [[ "$(headscale version | sed -n '1p')" == 'headscale version v0.29.6+dirty' ]]
fi
headscale_cli() { timeout 10 headscale -c "${HEADSCALE_CONFIG}" "$@"; }
if [[ "${1:-}" == prepare ]]; then
  [[ ! -e /root/sing-box-vps && ! -e /etc/systemd/system/sing-box.service ]]
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=headscale-fixture \
    -addext "subjectAltName=IP:127.0.0.1,IP:${TAILSCALE_CONTROL_ADDRESS:?}" \
    -keyout "${ARTIFACT_DIR}/headscale/headscale.key" -out "${ARTIFACT_DIR}/headscale/headscale.crt" \
    >/dev/null 2> "${ARTIFACT_DIR}/headscale-certificate.log"
  cp "${ARTIFACT_DIR}/headscale/headscale.crt" /usr/local/share/ca-certificates/sbv-headscale-fixture.crt
  update-ca-certificates > "${ARTIFACT_DIR}/headscale-trust.log" 2>&1
  cat > "${HEADSCALE_CONFIG}" <<YAML
server_url: https://${TAILSCALE_CONTROL_ADDRESS}:21800
listen_addr: 0.0.0.0:21800
tls_cert_path: ${ARTIFACT_DIR}/headscale/headscale.crt
tls_key_path: ${ARTIFACT_DIR}/headscale/headscale.key
metrics_listen_addr: 127.0.0.1:21890
grpc_listen_addr: 127.0.0.1:21891
disable_check_updates: true
noise: {private_key_path: ${ARTIFACT_DIR}/headscale/noise.key}
prefixes: {v4: 100.64.0.0/10, v6: 'fd7a:115c:a1e0::/48'}
database: {type: sqlite, sqlite: {path: ${ARTIFACT_DIR}/headscale/db.sqlite}}
dns: {magic_dns: false, override_local_dns: false}
unix_socket: ${ARTIFACT_DIR}/headscale/headscale.sock
unix_socket_permission: '0770'
policy: {mode: file}
derp:
  server:
    enabled: true
    region_id: 999
    region_code: fixture
    region_name: Isolated fixture
    verify_clients: true
    stun_listen_addr: 0.0.0.0:21878
    private_key_path: ${ARTIFACT_DIR}/headscale/derp.key
    automatically_add_embedded_derp_region: true
    ipv4: ${TAILSCALE_CONTROL_ADDRESS}
  urls: []
  paths: []
  auto_update_enabled: false
YAML
  headscale -c "${HEADSCALE_CONFIG}" serve > "${ARTIFACT_DIR}/headscale.log" 2>&1 &
  printf '%s\n' "$!" > "${ARTIFACT_DIR}/headscale.pid"
  for ((attempt=0;attempt<100;attempt++)); do [[ -S "${ARTIFACT_DIR}/headscale/headscale.sock" ]] && break; sleep 0.1; done
  headscale_cli users create fixture -o json > "${ARTIFACT_DIR}/headscale-user.json"
  user_id=$(jq -r .id "${ARTIFACT_DIR}/headscale-user.json")
  headscale_cli preauthkeys create --user "${user_id}" --reusable --expiration 1h -o json > "${ARTIFACT_DIR}/headscale-key.json"
  key=$(jq -r .key "${ARTIFACT_DIR}/headscale-key.json")
  jq -n --arg key "${key}" --arg url "https://${TAILSCALE_CONTROL_ADDRESS}:21800" '{log:{level:"info"},endpoints:[{type:"tailscale",tag:"ts-peer",state_directory:"/tmp/ts-peer-state",auth_key:$key,control_url:$url,hostname:"fixture-peer",listen_port:21842}],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${ARTIFACT_DIR}/peer.json"
  chmod 600 "${ARTIFACT_DIR}/peer.json" "${ARTIFACT_DIR}/headscale-key.json"
  exit 0
fi
if [[ "${1:-}" == counterpart ]]; then
  mkdir -p /dev/net
  [[ -e /dev/net/tun ]] || mknod /dev/net/tun c 10 200
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=vpn-fixture -addext "subjectAltName=IP:${OPENCONNECT_SERVER_ADDRESS:?}" \
    -keyout "${ARTIFACT_DIR}/ocserv.key" -out "${ARTIFACT_DIR}/ocserv.crt" >/dev/null 2> "${ARTIFACT_DIR}/certificate.log"
  printf 'fixture-password\nfixture-password\n' | ocpasswd -c "${ARTIFACT_DIR}/ocpasswd" fixture > "${ARTIFACT_DIR}/ocpasswd.log" 2>&1
  cat > "${ARTIFACT_DIR}/ocserv.conf" <<CONF
auth = "plain[passwd=${ARTIFACT_DIR}/ocpasswd]"
tcp-port = 21843
udp-port = 21843
listen-host = 0.0.0.0
run-as-user = root
run-as-group = root
socket-file = ${ARTIFACT_DIR}/ocserv-socket
server-cert = ${ARTIFACT_DIR}/ocserv.crt
server-key = ${ARTIFACT_DIR}/ocserv.key
isolate-workers = false
max-clients = 4
max-same-clients = 4
keepalive = 20
dpd = 30
mobile-dpd = 30
try-mtu-discovery = false
cisco-client-compat = false
device = ocfixture
ipv4-network = 10.91.0.0
ipv4-netmask = 255.255.255.0
route = 10.91.0.0/255.255.255.0
CONF
  ocserv -f -d 1 -c "${ARTIFACT_DIR}/ocserv.conf" > "${ARTIFACT_DIR}/ocserv.log" 2>&1 &
  printf '%s\n' "$!" > "${ARTIFACT_DIR}/ocserv.pid"
  python3 -B "${REPO_ROOT}/tests/tailscale_openconnect_marker.py" > "${ARTIFACT_DIR}/marker.log" 2>&1 &
  printf '%s\n' "$!" > "${ARTIFACT_DIR}/marker.pid"
  exit 0
fi
[[ "${1:-}" == test || "${1:-}" == lifecycle ]]
source "${REPO_ROOT}/install.sh"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
cat > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" <<'JSON'
{"schema_version":1,"protocol":"mixed","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"VPN fixture Mixed","tag":"mixed-in","listen":{"address":"127.0.0.1","port":2080},"authentication":{"enabled":false,"username":"","password":""},"outbound_policy":"default","dependencies":[]}]}
JSON
SB_VERSION=1.14.2
generate_config > "${ARTIFACT_DIR}/baseline.log" 2>&1
cat > "${SINGBOX_SERVICE_FILE}" <<UNIT
[Unit]
Description=Disposable managed VPN endpoint acceptance
[Service]
Environment=TS_NO_LOGS_NO_SUPPORT=true
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl start sing-box
revision() { jq -r '.revision' "${SB_COMPONENT_STATE_FILE}" 2>/dev/null || printf 0; }
record() {
  local id=$1 role=$2 type=$3 config=$4 rules=${5:-'[]'}
  jq -cn --arg id "${id}" --arg role "${role}" --arg type "${type}" --argjson config "${config}" --argjson rules "${rules}" '{id:$id,role:$role,type:$type,tag:$id,enabled:true,config:$config,route_rules:$rules}'
}
mutate() {
  local operation=$1 value=$2 before suffix
  before=$(revision); suffix="${ARTIFACT_DIR}/${before}-${operation}"
  if [[ "${operation}" == delete ]]; then
    bash "${REPO_ROOT}/install.sh" agent component delete --json --yes --expected-revision "${before}" --id "${value}" > "${suffix}.json" 2> "${suffix}.log"
  else
    printf '%s\n' "${value}" > "${ARTIFACT_DIR}/record.json"
    chmod 600 "${ARTIFACT_DIR}/record.json"
    bash "${REPO_ROOT}/install.sh" agent component "${operation}" --json --yes --allow-public --expected-revision "${before}" --file "${ARTIFACT_DIR}/record.json" > "${suffix}.json" 2> "${suffix}.log"
  fi
  jq -e --argjson revision "$((before+1))" '.ok==true and .revision==$revision and .config_check=="passed"' "${suffix}.json" >/dev/null
  "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${suffix}.check" 2>&1
  systemctl is-active --quiet sing-box
}
wait_tcp() {
  local proxy=$1 target=$2 marker=$3 peer_prefix=$4 output=$5 attempt
  for ((attempt=0;attempt<16;attempt++)); do
    if curl --silent --show-error --fail --max-time 5 --noproxy '*' "http://127.0.0.1:${proxy}/${marker}" > "${output}" 2> "${output}.err" && \
      jq -e --arg marker "/${marker}" --arg prefix "${peer_prefix}" '.marker==$marker and (.peer|startswith($prefix))' "${output}" >/dev/null; then return 0; fi
    sleep 0.2
  done
  return 1
}
check_udp() {
  python3 -B - "$1" "$2" "$3" "$4" <<'PY'
import json,socket,sys,time
port,marker,prefix,out=int(sys.argv[1]),sys.argv[2],sys.argv[3],sys.argv[4]
for attempt in range(12):
 s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.settimeout(3)
 try:
  s.sendto(marker.encode(),('127.0.0.1',port));r=json.loads(s.recv(4096))
  assert r['marker']==marker and r['peer'].startswith(prefix)
  open(out,'w').write(json.dumps(r));break
 except socket.timeout:
  if attempt==11:raise
 finally:s.close()
 time.sleep(.2)
PY
}
assert_interface_absent() {
  if ip link show dev "$1" >/dev/null 2>&1; then
    printf 'managed interface remains after deletion: %s\n' "$1" >&2
    return 1
  fi
  return 0
}
add_inputs() {
  local prefix=$1 endpoint=$2 target=$3 tcp_port=$4 udp_port=$5
  mutate create "$(record "${prefix}-tcp" inbound direct "{\"listen\":\"127.0.0.1\",\"listen_port\":${tcp_port},\"network\":\"tcp\",\"override_address\":\"${target}\",\"override_port\":21910}" "[{\"inbound\":[\"${prefix}-tcp\"],\"action\":\"route\",\"outbound\":\"${endpoint}\"}]")"
  mutate create "$(record "${prefix}-udp" inbound direct "{\"listen\":\"127.0.0.1\",\"listen_port\":${udp_port},\"network\":\"udp\",\"override_address\":\"${target}\",\"override_port\":21911}" "[{\"inbound\":[\"${prefix}-udp\"],\"action\":\"route\",\"outbound\":\"${endpoint}\"}]")"
}
if [[ "${1:-}" == lifecycle ]]; then
  oc_config=$(jq -cn --arg ca "${ARTIFACT_DIR}/ocserv.crt" --arg server "https://${OPENCONNECT_SERVER_ADDRESS:?}:21843" '{server:$server,flavor:"anyconnect",username:"fixture",password:"fixture-password",system:true,name:"sbv-oc-test",tls:{certificate_authority_path:$ca}}')
  mutate create "$(record oc-client endpoint openconnect "${oc_config}")"
  ip -j address show dev sbv-oc-test > "${ARTIFACT_DIR}/oc-system-interface.json"
  jq -e 'any(.[].addr_info[]; .family=="inet" and (.local|startswith("10.91.0.")))' "${ARTIFACT_DIR}/oc-system-interface.json" >/dev/null
  mutate delete oc-client
  assert_interface_absent sbv-oc-test
  assert_interface_absent sbv-ts-test
  jq -e '.components|length==0' "${SB_COMPONENT_STATE_FILE}" >/dev/null
  printf 'openconnect_system_interface_absent=1\nmanaged_components_empty=1\n' > "${ARTIFACT_DIR}/actual-interface-cleanup.env"
  printf 'openconnect_system_lifecycle=passed\n' > "${ARTIFACT_DIR}/results.env"
  sha256sum "${REPO_ROOT}/install.sh" "${SINGBOX_BIN_PATH}" /usr/local/bin/headscale > "${ARTIFACT_DIR}/hashes.txt"
  exit 0
fi
key=$(jq -r .key "${ARTIFACT_DIR}/headscale-key.json")
ts_config=$(jq -cn --arg key "${key}" --arg dir "${ARTIFACT_DIR}/client-state" '{state_directory:$dir,auth_key:$key,control_url:"https://127.0.0.1:21800",hostname:"fixture-managed-client",listen_port:21841}')
mutate create "$(record ts-client endpoint tailscale "${ts_config}")"
for ((attempt=0;attempt<100;attempt++)); do
  headscale_cli nodes list -o json > "${ARTIFACT_DIR}/nodes.json"
  if jq -e 'any(.[];.name=="fixture-managed-client" and .online==true) and any(.[];.name=="fixture-peer" and .online==true)' "${ARTIFACT_DIR}/nodes.json" >/dev/null; then break; fi
  sleep 0.2
done
peer_ip=$(jq -er '.[]|select(.name=="fixture-peer")|.ip_addresses[]|select(contains(":")|not)' "${ARTIFACT_DIR}/nodes.json")
node_id=$(jq -er '.[]|select(.name=="fixture-managed-client")|.id' "${ARTIFACT_DIR}/nodes.json")
add_inputs ts ts-client "${peer_ip}" 21920 21922
wait_tcp 21920 "${peer_ip}" ts-internal 127.0.0.1 "${ARTIFACT_DIR}/ts-internal-tcp.json"
check_udp 21922 ts-internal 127.0.0.1 "${ARTIFACT_DIR}/ts-internal-udp.json"
ts_system=$(jq '.system_interface=true | .system_interface_name="sbv-ts-test"' <<< "${ts_config}")
mutate replace "$(record ts-client endpoint tailscale "${ts_system}")"
ip -j address show dev sbv-ts-test > "${ARTIFACT_DIR}/ts-system-interface.json"
ip -j route show table all > "${ARTIFACT_DIR}/ts-system-routes.json"
if [[ "${VPN_RUNTIME_SYSTEM_DATA_PLANE:-1}" == 1 ]]; then
  wait_tcp 21920 "${peer_ip}" ts-system 127.0.0.1 "${ARTIFACT_DIR}/ts-system-tcp.json"
  check_udp 21922 ts-system 127.0.0.1 "${ARTIFACT_DIR}/ts-system-udp.json"
fi
headscale_cli nodes list -o json > "${ARTIFACT_DIR}/nodes-after-restart.json"
jq -e --argjson id "${node_id}" 'length==2 and any(.[];.name=="fixture-managed-client" and .id==$id)' "${ARTIFACT_DIR}/nodes-after-restart.json" >/dev/null
mutate delete ts-udp
mutate delete ts-tcp
mutate delete ts-client
assert_interface_absent sbv-ts-test
test -s "${ARTIFACT_DIR}/client-state/tailscaled.state"
printf 'FP-07=passed\n' > "${ARTIFACT_DIR}/results.env"
printf 'tailscale_selected_data_plane=internal\ntailscale_system_interface_lifecycle=passed\n' >> "${ARTIFACT_DIR}/results.env"
if [[ "${VPN_RUNTIME_SYSTEM_DATA_PLANE:-1}" == 1 ]]; then
  printf 'tailscale_system_data_plane=passed\n' >> "${ARTIFACT_DIR}/results.env"
else
  printf 'tailscale_system_data_plane=not_validated\n' >> "${ARTIFACT_DIR}/results.env"
fi
oc_config=$(jq -cn --arg ca "${ARTIFACT_DIR}/ocserv.crt" --arg server "https://${OPENCONNECT_SERVER_ADDRESS:?}:21843" '{server:$server,flavor:"anyconnect",username:"fixture",password:"fixture-password",tls:{certificate_authority_path:$ca}}')
mutate create "$(record oc-client endpoint openconnect "${oc_config}")"
add_inputs oc oc-client 10.91.0.1 21921 21923
wait_tcp 21921 10.91.0.1 oc-internal 10.91.0. "${ARTIFACT_DIR}/oc-internal-tcp.json"
check_udp 21923 oc-internal 10.91.0. "${ARTIFACT_DIR}/oc-internal-udp.json"
jq -e '.peer!="10.91.0.1"' "${ARTIFACT_DIR}/oc-internal-tcp.json" >/dev/null
oc_system=$(jq '.system=true | .name="sbv-oc-test"' <<< "${oc_config}")
mutate replace "$(record oc-client endpoint openconnect "${oc_system}")"
ip -j address show dev sbv-oc-test > "${ARTIFACT_DIR}/oc-system-interface.json"
ip -j route show table all > "${ARTIFACT_DIR}/oc-system-routes.json"
if [[ "${VPN_RUNTIME_SYSTEM_DATA_PLANE:-1}" == 1 ]]; then
  wait_tcp 21921 10.91.0.1 oc-system 10.91.0. "${ARTIFACT_DIR}/oc-system-tcp.json"
  check_udp 21923 oc-system 10.91.0. "${ARTIFACT_DIR}/oc-system-udp.json"
fi
mutate delete oc-udp
mutate delete oc-tcp
mutate delete oc-client
assert_interface_absent sbv-oc-test
jq -e '.components|length==0' "${SB_COMPONENT_STATE_FILE}" >/dev/null
journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/journal.log"
grep -Fq 'anyconnect tunnel established' "${ARTIFACT_DIR}/journal.log"
printf 'FP-08=passed\n' >> "${ARTIFACT_DIR}/results.env"
printf 'openconnect_selected_data_plane=internal\nopenconnect_system_interface_lifecycle=passed\n' >> "${ARTIFACT_DIR}/results.env"
if [[ "${VPN_RUNTIME_SYSTEM_DATA_PLANE:-1}" == 1 ]]; then
  printf 'openconnect_system_data_plane=passed\n' >> "${ARTIFACT_DIR}/results.env"
else
  printf 'openconnect_system_data_plane=not_validated\n' >> "${ARTIFACT_DIR}/results.env"
fi
sha256sum "${REPO_ROOT}/install.sh" "${SINGBOX_BIN_PATH}" /usr/local/bin/headscale > "${ARTIFACT_DIR}/hashes.txt"
printf 'Tailscale/OpenConnect controlled authentication and TCP/UDP acceptance passed\n'
