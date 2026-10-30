#!/usr/bin/env bash

set -euo pipefail

# This fixture owns systemd, DBus and namespaces inside a NEW disposable
# container. Two explicit guards prevent accidental execution on a VPS.
[[ "${SBV_COMPONENT_RUNTIME:-}" == 1 && -f /.dockerenv && -f /tmp/sbv-component-disposable ]] || {
  printf 'requires SBV_COMPONENT_RUNTIME=1 and disposable Docker marker\n' >&2; exit 64;
}
[[ ! -e /root/sing-box-vps && ! -e /etc/systemd/system/sing-box.service ]] || {
  printf 'refusing to overwrite an existing installation\n' >&2; exit 64;
}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/install.sh"
ARTIFACT_DIR=${COMPONENT_RUNTIME_ARTIFACT_DIR:-/tmp/component-runtime-acceptance}
mkdir -p "${ARTIFACT_DIR}" "${SB_PROTOCOL_STATE_DIR}/instances"
chmod 700 "${ARTIFACT_DIR}"
CORE_VERSION=$("${SINGBOX_BIN_PATH}" version | sed -n 's/^sing-box version //p')
[[ "${CORE_VERSION}" == 1.14.2 ]]
command -v dbus-daemon >/dev/null
command -v nsenter >/dev/null
TEST_PIDS=()
COMPONENT_RUNTIME_CASES=${COMPONENT_RUNTIME_CASES:-shared,resolved,default,unshare}
[[ "${COMPONENT_RUNTIME_CASES}" =~ ^(shared|resolved|default|unshare|bad-build)(,(shared|resolved|default|unshare|bad-build))*$ ]] || { printf 'invalid runtime case selection\n' >&2; exit 64; }
case_selected() { [[ ",${COMPONENT_RUNTIME_CASES}," == *",$1,"* ]]; }
cleanup() {
  local pid
  for pid in "${TEST_PIDS[@]}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" 2>/dev/null; then kill "${pid}"; fi
    if wait "${pid}"; then :; else [[ $? == 143 || $? == 137 ]] || true; fi
  done
  if ip netns list | grep -Eq '^sbv-spec-default( |$)'; then ip netns delete sbv-spec-default; fi
}
trap cleanup EXIT
trap 'printf "component runtime failure at line %s\n" "${LINENO}" >&2' ERR
sha256sum "${REPO_ROOT}/install.sh" "${SINGBOX_BIN_PATH}" > "${ARTIFACT_DIR}/hashes.txt"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
cat > "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" <<'JSON'
{"schema_version":1,"protocol":"mixed","revision":1,"default_instance_id":"main","instances":[{"id":"main","name":"Fixture Mixed","tag":"mixed-in","listen":{"address":"127.0.0.1","port":2080},"authentication":{"enabled":false,"username":"","password":""},"outbound_policy":"default","dependencies":[]}]}
JSON
SB_VERSION=1.14.2
generate_config > "${ARTIFACT_DIR}/baseline.log" 2>&1
cat > "${SINGBOX_SERVICE_FILE}" <<UNIT
[Unit]
Description=Disposable component acceptance core
[Service]
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
mkdir -p /etc/dbus-1/system.d
cat > /etc/dbus-1/system.d/sbv-component-resolved.conf <<'DBUS'
<busconfig>
  <policy user="root">
    <allow own="org.freedesktop.resolve1"/>
    <allow send_destination="org.freedesktop.resolve1"/>
  </policy>
</busconfig>
DBUS
systemctl restart dbus
systemctl start sing-box

revision() { jq -r '.revision' "${SB_COMPONENT_STATE_FILE}" 2>/dev/null || printf 0; }
mutate() {
  local operation=$1 value=$2 expected before suffix
  before=$(revision)
  suffix="${ARTIFACT_DIR}/${before}-${operation}"
  if [[ "${operation}" == delete ]]; then
    bash "${REPO_ROOT}/install.sh" agent component delete --json --yes --expected-revision "${before}" --id "${value}" > "${suffix}.json" 2> "${suffix}.log"
  else
    printf '%s\n' "${value}" > "${ARTIFACT_DIR}/record.json"
    chmod 600 "${ARTIFACT_DIR}/record.json"
    bash "${REPO_ROOT}/install.sh" agent component "${operation}" --json --yes --expected-revision "${before}" --file "${ARTIFACT_DIR}/record.json" > "${suffix}.json" 2> "${suffix}.log"
  fi
  expected=$((before + 1))
  jq -e --argjson revision "${expected}" '.ok==true and .revision==$revision and .config_check=="passed"' "${suffix}.json" >/dev/null
  "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}" > "${suffix}.check" 2>&1
  systemctl is-active --quiet sing-box
}
record() {
  local id=$1 role=$2 type=$3 config=$4 rules=${5:-'[]'}
  jq -cn --arg id "${id}" --arg role "${role}" --arg type "${type}" --argjson config "${config}" --argjson rules "${rules}" '{id:$id,role:$role,type:$type,tag:$id,enabled:true,config:$config,route_rules:$rules}'
}
wait_body() {
  local expected=$1 url=$2 output=$3 attempt
  for ((attempt=0;attempt<80;attempt++)); do
    if curl --silent --show-error --fail --max-time 2 "${url}" > "${output}" 2> "${output}.err" && [[ "$(cat "${output}")" == "${expected}" ]]; then return 0; fi
    sleep 0.2
  done
  return 1
}
python3 "${REPO_ROOT}/tests/component_runtime_http.py" 21300 "${ARTIFACT_DIR}" > "${ARTIFACT_DIR}/http.log" 2>&1 &
TEST_PIDS+=("$!")
wait_body 127.0.0.1 http://127.0.0.1:21300/ "${ARTIFACT_DIR}/http-control.txt"

if case_selected bad-build; then
  before_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  for kind in default unshare raw; do
    if [[ "${kind}" == raw ]]; then
      value=$(record raw-namespace outbound direct '{"netns":"/proc/self/ns/net"}')
    elif [[ "${kind}" == default ]]; then
      value=$(record bad-namespace network_namespace default '{"path":"/proc/self/ns/net"}')
    else
      value=$(record bad-namespace network_namespace unshare '{}')
    fi
    printf '%s\n' "${value}" > "${ARTIFACT_DIR}/bad-build-record.json"
    if bash "${REPO_ROOT}/install.sh" agent component create --json --yes --expected-revision 0 --file "${ARTIFACT_DIR}/bad-build-record.json" > "${ARTIFACT_DIR}/bad-build-${kind}.json" 2> "${ARTIFACT_DIR}/bad-build-${kind}.log"; then exit 1; fi
    jq -e '.ok==false and .error=="namespace_runtime_unsafe_build"' "${ARTIFACT_DIR}/bad-build-${kind}.json" >/dev/null
    [[ "$(revision)" == 0 && "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_hash}" ]]
    [[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]
    systemctl is-active --quiet sing-box
  done
  printf 'namespace_bad_build=blocked_before_publication\n' >> "${ARTIFACT_DIR}/results.env"
fi

if case_selected shared; then
# FP-02: an actual remote-rule-set consumer must use this named HTTP client,
# its distinguishing header and its configured first-hop source address.
mutate create "$(record fetch-route outbound direct '{"inet4_bind_address":"127.0.0.2"}')"
mutate create "$(record shared-client http_client shared '{"version":1,"detour":"fetch-route","headers":{"X-Component-Marker":"shared-client-v1"}}')"
mutate create "$(record fetched-rules rule_set remote '{"format":"source","url":"http://127.0.0.1:21300/rules.json","http_client":"shared-client"}')"
for ((attempt=0;attempt<80;attempt++)); do [[ -s "${ARTIFACT_DIR}/shared-request.json" ]] && break; sleep 0.2; done
jq -e '.peer=="127.0.0.2" and .version=="HTTP/1.1" and .header=="shared-client-v1"' "${ARTIFACT_DIR}/shared-request.json" >/dev/null
before=$(revision)
if bash "${REPO_ROOT}/install.sh" agent component delete --json --yes --expected-revision "${before}" --id shared-client > "${ARTIFACT_DIR}/referenced-client.json" 2> "${ARTIFACT_DIR}/referenced-client.log"; then exit 1; fi
[[ "$(revision)" == "${before}" ]]
jq -e '.ok==false and .error=="component_referenced"' "${ARTIFACT_DIR}/referenced-client.json" >/dev/null
mutate delete fetched-rules
mutate delete shared-client
mutate delete fetch-route
printf 'FP-02=passed\n' >> "${ARTIFACT_DIR}/results.env"
fi

if case_selected resolved; then
# FP-03: actual fake-resolved DBus registration and TCP+UDP DNS responses.
mutate create "$(record fixture-resolved service resolved '{"listen":"127.0.0.53","listen_port":21353}')"
busctl --system list > "${ARTIFACT_DIR}/dbus-names.txt"
grep -Fq org.freedesktop.resolve1 "${ARTIFACT_DIR}/dbus-names.txt"
# The service routes DNS through the existing local resolver. A fixture-only
# hosts entry gives an exact answer without depending on public DNS.
printf '203.0.113.7 resolved.component.invalid\n' >> /etc/hosts
python3 - "${ARTIFACT_DIR}/dns.json" <<'PY'
import json,socket,struct,sys
q=struct.pack('!HHHHHH',0x4242,0x100,1,0,0,0)+b''.join(bytes([len(p)])+p.encode() for p in 'resolved.component.invalid'.split('.'))+b'\0'+struct.pack('!HH',1,1)
results={}
for transport in ['udp','tcp']:
 s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM if transport=='udp' else socket.SOCK_STREAM);s.settimeout(5)
 s.connect(('127.0.0.53',21353))
 if transport=='udp':s.send(q);r=s.recv(4096)
 else:
  s.sendall(struct.pack('!H',len(q))+q);n=struct.unpack('!H',s.recv(2))[0];r=b''
  while len(r)<n:r+=s.recv(n-len(r))
 s.close()
 assert r[:2]==q[:2] and r[3]&15==0 and struct.unpack('!H',r[6:8])[0]>0 and socket.inet_aton('203.0.113.7') in r
 results[transport]='203.0.113.7'
open(sys.argv[1],'w').write(json.dumps(results))
PY
mutate delete fixture-resolved
! busctl --system list | grep -Fq org.freedesktop.resolve1
printf 'FP-03=passed\n' >> "${ARTIFACT_DIR}/results.env"
fi

# FP-04/05: reach a marker that is only bound inside the namespace. The
# namespace record and outbounds/inbounds all use production serializers and
# actual Agent CAS/service transactions.
namespace_case() {
  local mode=$1 ns_id="namespace-$1" ns_target ns_pid='' port=21312
  if [[ "${mode}" == default ]]; then
    local before config_hash
    before=$(revision)
    config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
    record absent-namespace network_namespace default '{"path":"/run/netns/sbv-spec-missing"}' > "${ARTIFACT_DIR}/absent-namespace.json"
    if bash "${REPO_ROOT}/install.sh" agent component create --json --yes --expected-revision "${before}" --file "${ARTIFACT_DIR}/absent-namespace.json" > "${ARTIFACT_DIR}/absent-result.json" 2> "${ARTIFACT_DIR}/absent-result.log"; then return 1; fi
    [[ "$(revision)" == "${before}" && "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_hash}" ]]
    jq -e '.ok==false and .error=="network_namespace_unavailable"' "${ARTIFACT_DIR}/absent-result.json" >/dev/null
    systemctl is-active --quiet sing-box
    ip netns add sbv-spec-default
    ip netns exec sbv-spec-default ip link set lo up
    mutate create "$(record "${ns_id}" network_namespace default '{"path":"/run/netns/sbv-spec-default"}')"
    ns_target=/run/netns/sbv-spec-default
  else
    mutate create "$(record "${ns_id}" network_namespace unshare '{}')"

  fi
  if [[ "${NAMESPACE_LIFECYCLE_ONLY:-0}" == 1 ]]; then
    local holder=''
    if [[ "${mode}" == unshare ]]; then
      journalctl -u sing-box --no-pager > "${ARTIFACT_DIR}/unshare-service.log"
      holder=$(sed -n 's/.*holder pid: \([0-9]*\).*/\1/p' "${ARTIFACT_DIR}/unshare-service.log" | tail -n 1)
      [[ -n "${holder}" && -e "/proc/${holder}/ns/net" ]]
    fi
    mutate delete "${ns_id}"
    if [[ "${mode}" == default ]]; then
      test -e /run/netns/sbv-spec-default
      ip netns delete sbv-spec-default
    else
      for ((attempt=0;attempt<50;attempt++)); do [[ ! -e "/proc/${holder}/ns/net" ]] && break; sleep 0.1; done
      [[ ! -e "/proc/${holder}/ns/net" ]]
    fi
    printf '%s_lifecycle=passed\n' "${mode}" >> "${ARTIFACT_DIR}/results.env"
    return 0
  fi
  mutate create "$(record namespace-out outbound direct "{\"netns\":\"${ns_id}\"}")"
  mutate create "$(record namespace-in inbound direct "{\"listen\":\"127.0.0.1\",\"listen_port\":21313,\"override_address\":\"127.0.0.1\",\"override_port\":${port}}" '[{"inbound":["namespace-in"],"action":"route","outbound":"namespace-out"}]')"
  if [[ "${mode}" == unshare ]]; then
    # The unshare namespace is held by a child process, distinct from this
    # container's namespace. Observe it rather than inventing a PID/path.
    local proc own_net
    own_net=$(readlink /proc/self/ns/net)
    for proc in /proc/[0-9]*/ns/net; do
      if [[ "$(readlink "${proc}" 2>/dev/null || true)" != "${own_net}" && -e "${proc}" ]]; then
        ns_pid=${proc#/proc/}; ns_pid=${ns_pid%%/*}; break
      fi
    done
    [[ -n "${ns_pid}" ]]
    ns_target="/proc/${ns_pid}/ns/net"
    nsenter --net="${ns_target}" ip link set lo up
  fi
  mkdir -p "${ARTIFACT_DIR}/${mode}-marker"
  printf '%s' "marker-${mode}" > "${ARTIFACT_DIR}/${mode}-marker/index.html"
  nsenter --net="${ns_target}" python3 -m http.server "${port}" --bind 127.0.0.1 --directory "${ARTIFACT_DIR}/${mode}-marker" > "${ARTIFACT_DIR}/${mode}-marker.log" 2>&1 &
  local marker_pid=$!
  TEST_PIDS+=("${marker_pid}")
  local ready=false
  for ((attempt=0;attempt<50;attempt++)); do
    if nsenter --net="${ns_target}" curl --silent --fail --max-time 1 "http://127.0.0.1:${port}/" > "${ARTIFACT_DIR}/${mode}-namespace-control.txt" && [[ "$(cat "${ARTIFACT_DIR}/${mode}-namespace-control.txt")" == "marker-${mode}" ]]; then ready=true; break; fi
    sleep 0.1
  done
  [[ "${ready}" == true ]]
  if curl --silent --fail --max-time 1 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then return 1; fi
  wait_body "marker-${mode}" http://127.0.0.1:21313/ "${ARTIFACT_DIR}/${mode}-response.txt"
  mutate delete namespace-in
  mutate delete namespace-out
  kill "${marker_pid}"
  if wait "${marker_pid}"; then :; else [[ $? == 143 ]]; fi
  mutate delete "${ns_id}"
  if [[ "${mode}" == default ]]; then
    test -e /run/netns/sbv-spec-default
    ip netns delete sbv-spec-default
    printf 'FP-04=passed\n' >> "${ARTIFACT_DIR}/results.env"
  else
    [[ ! -e "/proc/${ns_pid}/ns/net" ]]
    printf 'FP-05=passed\n' >> "${ARTIFACT_DIR}/results.env"
  fi
}
if case_selected default; then namespace_case default; fi
if case_selected unshare; then namespace_case unshare; fi
printf 'component runtime acceptance completed\n'
