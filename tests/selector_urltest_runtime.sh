#!/usr/bin/env bash

set -euo pipefail
[[ "${SBV_COMPONENT_RUNTIME:-}" == 1 && -f /.dockerenv && -f /tmp/sbv-component-disposable ]] || {
  printf 'requires explicit disposable Docker fixture\n' >&2; exit 64;
}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/install.sh"
ARTIFACT_DIR=${GROUP_RUNTIME_ARTIFACT_DIR:-/tmp/selector-urltest-runtime}
[[ ! -e "${ARTIFACT_DIR}" ]] || { printf 'artifact directory already exists; use a fresh path\n' >&2; exit 64; }
mkdir -p "${ARTIFACT_DIR}"
chmod 700 "${ARTIFACT_DIR}"
CORE_PID='' MARKER_PID='' UDP_PID=''
cleanup() {
  local pid
  for pid in "${CORE_PID}" "${MARKER_PID}" "${UDP_PID}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" 2>/dev/null; then kill "${pid}"; fi
    if wait "${pid}"; then :; fi
  done
}
trap cleanup EXIT
trap 'printf "selector/urltest runtime failure line %s\n" "${LINENO}" >&2' ERR
[[ "$("${SINGBOX_BIN_PATH}" version | sed -n 's/^sing-box version //p')" == 1.14.2 ]]
python3 "${REPO_ROOT}/tests/component_runtime_http.py" 21400 "${ARTIFACT_DIR}" > "${ARTIFACT_DIR}/http.log" 2>&1 &
MARKER_PID=$!
state=$(managed_component_state_default_json)
add_record() {
  local id=$1 type=$2 config=$3 rules=${4:-'[]'} record_json
  record_json=$(jq -cn --arg id "${id}" --arg type "${type}" --argjson config "${config}" --argjson rules "${rules}" '{id:$id,role:"outbound",type:$type,tag:$id,enabled:true,config:$config,route_rules:$rules}')
  state=$(managed_component_state_candidate "${state}" create "${record_json}")
}
add_record member-a direct '{"inet4_bind_address":"127.0.0.2"}'
add_record member-b direct '{"inet4_bind_address":"127.0.0.3"}'
add_record selected selector '{"outbounds":["member-a","member-b"],"default":"member-a"}' '[{"inbound":["selection-in"],"action":"route","outbound":"selected"}]'
add_record automatic urltest '{"outbounds":["member-a","member-b"],"url":"http://127.0.0.1:21400/health","interval":"1s","tolerance":0,"idle_timeout":"1m"}' '[{"inbound":["automatic-in"],"action":"route","outbound":"automatic"}]'
add_record denied block '{}' '[{"inbound":["udp-block"],"action":"route","outbound":"denied"}]'
managed_component_render_json "${state}" | jq '{log:{level:"debug"},outbounds,
  inbounds:[{type:"mixed",tag:"selection-in",listen:"127.0.0.1",listen_port:21480},
    {type:"mixed",tag:"automatic-in",listen:"127.0.0.1",listen_port:21482},
    {type:"direct",tag:"udp-block",listen:"127.0.0.1",listen_port:21483,network:"udp",override_address:"127.0.0.1",override_port:21485},
    {type:"direct",tag:"udp-direct",listen:"127.0.0.1",listen_port:21484,network:"udp",override_address:"127.0.0.1",override_port:21485}],
  route:{rules:(.route_rules+[{inbound:["udp-direct"],action:"route",outbound:"member-a"}]),final:"member-a"},
  experimental:{clash_api:{external_controller:"127.0.0.1:21481"}}}' > "${ARTIFACT_DIR}/config.json"
validate_managed_component_graph "${ARTIFACT_DIR}/config.json"
"${SINGBOX_BIN_PATH}" check -c "${ARTIFACT_DIR}/config.json" > "${ARTIFACT_DIR}/check.log" 2>&1
"${SINGBOX_BIN_PATH}" run -c "${ARTIFACT_DIR}/config.json" > "${ARTIFACT_DIR}/core.log" 2>&1 &
CORE_PID=$!
wait_proxy() {
  local proxy=$1 expected=$2 out=$3 attempt
  for ((attempt=0;attempt<100;attempt++)); do
    if curl --silent --show-error --fail --max-time 1 --noproxy '' --proxy "socks5://127.0.0.1:${proxy}" http://127.0.0.1:21400/ > "${out}" 2> "${out}.err" && [[ "$(cat "${out}")" == "${expected}" ]]; then return 0; fi
    kill -0 "${CORE_PID}" || return 1
    sleep 0.2
  done
  return 1
}
wait_proxy 21480 127.0.0.2 "${ARTIFACT_DIR}/selector-default.txt"
curl --silent --show-error --fail --max-time 3 -X PUT -H 'Content-Type: application/json' --data '{"name":"member-b"}' http://127.0.0.1:21481/proxies/selected > "${ARTIFACT_DIR}/selection-api.txt"
wait_proxy 21480 127.0.0.3 "${ARTIFACT_DIR}/selector-changed.txt"
printf 'FP-09=passed\n' >> "${ARTIFACT_DIR}/results.env"
wait_proxy 21482 127.0.0.2 "${ARTIFACT_DIR}/urltest-initial.txt"
touch "${ARTIFACT_DIR}/fail-a"
wait_proxy 21482 127.0.0.3 "${ARTIFACT_DIR}/urltest-failover.txt"
rm "${ARTIFACT_DIR}/fail-a"
wait_proxy 21482 127.0.0.2 "${ARTIFACT_DIR}/urltest-recovery.txt"
printf 'FP-10=passed\n' >> "${ARTIFACT_DIR}/results.env"
python3 - "${ARTIFACT_DIR}" <<'PY' &
import pathlib,socket,sys
p=pathlib.Path(sys.argv[1]);s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(('127.0.0.1',21485));(p/'udp-ready').touch()
while True:
 d,a=s.recvfrom(4096)
 with (p/'udp-access.log').open('a') as f:f.write(d.decode()+'\n')
 s.sendto(d,a)
PY
UDP_PID=$!
for ((attempt=0;attempt<50;attempt++)); do [[ -e "${ARTIFACT_DIR}/udp-ready" ]] && break; sleep 0.1; done
python3 - "${ARTIFACT_DIR}" <<'PY'
import pathlib,socket,sys
p=pathlib.Path(sys.argv[1]);s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.settimeout(2)
s.sendto(b'positive-control',('127.0.0.1',21484));assert s.recv(4096)==b'positive-control'
s.sendto(b'must-be-blocked',('127.0.0.1',21483))
try:s.recv(4096);raise AssertionError('blocked UDP unexpectedly returned')
except socket.timeout:pass
assert 'must-be-blocked' not in (p/'udp-access.log').read_text()
PY
printf 'FP-11=passed\n' >> "${ARTIFACT_DIR}/results.env"
printf '%s\n' "${state}" > "${ARTIFACT_DIR}/before-state.json"
for id in selected automatic denied member-b member-a; do state=$(managed_component_state_candidate "${state}" delete '' "${id}"); done
jq -e '.components|length==0' <<< "${state}" >/dev/null
printf '%s\n' "${state}" > "${ARTIFACT_DIR}/after-state.json"
printf 'selector/urltest/block UDP runtime acceptance passed\n'
