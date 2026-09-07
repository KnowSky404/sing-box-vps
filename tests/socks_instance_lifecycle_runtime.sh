#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTS_DIR="${REPO_ROOT}/tests"

if [[ "${1:-}" == --run ]]; then
  if [[ $# -ne 3 || ! -x "$2" ]]; then
    printf 'usage: %s --run CORE_BINARY CORE_LABEL\n' "${BASH_SOURCE[0]}" >&2
    exit 2
  fi
  core_binary=$2
  core_label=$3
  source "${TESTS_DIR}/menu_test_helper.sh"
  setup_menu_test_env 120
  cp -p "${core_binary}" "${TMP_DIR}/real-sing-box"
  cat > "${TMP_DIR}/bin/sing-box" <<'EOF_CORE'
#!/usr/bin/env bash
if [[ "${1:-}" == check && -n "${SBV_SOCKS_CHECK_FAIL_FILE:-}" && -e "${SBV_SOCKS_CHECK_FAIL_FILE}" ]]; then
  printf 'injected SOCKS core-check failure\n' >&2
  exit 23
fi
exec "${SBV_SOCKS_REAL_CORE:?}" "$@"
EOF_CORE
  chmod +x "${TMP_DIR}/bin/sing-box"
  export SBV_SOCKS_REAL_CORE="${TMP_DIR}/real-sing-box"
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  export SINGBOX_CONFIG_FILE
  mkdir -p "${SB_PROTOCOL_STATE_DIR}" "${SB_PROJECT_DIR}"
  printf 'active\n' > "${TMP_DIR}/systemctl.state"
  printf '0\n' > "${TMP_DIR}/systemctl.restarts"
  : > "${TMP_DIR}/systemctl.log"
  : > "${TMP_DIR}/firewall.log"
  export SBV_SOCKS_STATE_FILE="${TMP_DIR}/systemctl.state"
  export SBV_SOCKS_RESTART_FILE="${TMP_DIR}/systemctl.restarts"
  export SBV_SOCKS_SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log"
  export SBV_SOCKS_CORE_PID_FILE="${TMP_DIR}/core.pid"
  export SBV_SOCKS_CORE_LOG="${TMP_DIR}/core.log"
  cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
state=${SBV_SOCKS_STATE_FILE:?}; restarts=${SBV_SOCKS_RESTART_FILE:?}; pidfile=${SBV_SOCKS_CORE_PID_FILE:?}
printf '%s\n' "$*" >> "${SBV_SOCKS_SYSTEMCTL_LOG:?}"
if [[ "$*" == 'show -p ActiveState --value sing-box' ]]; then cat "${state}"; exit 0; fi
case "${1:-}:${2:-}:${3:-}" in
  is-active:--quiet:sing-box) [[ "$(<"${state}")" == active ]] ;;
  is-active:sing-box:) cat "${state}"; [[ "$(<"${state}")" == active ]] ;;
  restart:sing-box:)
    n=$(<"${restarts}"); printf '%s\n' "$((n+1))" > "${restarts}"
    if [[ -s "${pidfile}" ]]; then
      old=$(<"${pidfile}")
      if kill -0 "${old}" 2>/dev/null; then
        kill "${old}"
        # The management mock is a separate process, so it cannot wait(2)
        # for the old core. Give the core time to close listeners before the
        # replacement starts; otherwise a fast restart can race bind(2).
        sleep 0.2
      fi
    fi
    for fd in {3..20}; do eval "exec ${fd}>&-"; done
    "${SBV_SOCKS_REAL_CORE}" run -c "${SINGBOX_CONFIG_FILE}" >"${SBV_SOCKS_CORE_LOG:?}" 2>&1 &
    printf '%s\n' "$!" > "${pidfile}"; printf 'active\n' > "${state}" ;;
  stop:sing-box:)
    if [[ -s "${pidfile}" ]]; then
      old=$(<"${pidfile}")
      if kill -0 "${old}" 2>/dev/null; then
        kill "${old}"
        sleep 0.2
      fi
    fi
    printf 'inactive\n' > "${state}" ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
  chmod +x "${TMP_DIR}/bin/systemctl"
  cat > "${TMP_DIR}/marker.py" <<'PY_MARKER'
import json,select,socket,threading
t=socket.socket(); t.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); t.bind(("127.0.0.1",0)); t.listen(16)
u=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); u.bind(("127.0.0.1",0))
used={t.getsockname()[1],u.getsockname()[1]}
def r():
 while 1:
  a=socket.socket(); a.bind(("127.0.0.1",0)); p=a.getsockname()[1]; b=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
  if p in used: a.close(); b.close(); continue
  try: b.bind(("127.0.0.1",p))
  except OSError: a.close(); b.close(); continue
  a.close(); b.close(); used.add(p); return p
print(json.dumps({"tcp":t.getsockname()[1],"udp":u.getsockname()[1],"mixed":r(),"main":r(),"edge":r(),"beta":r(),"replace":r(),"alpha":r(),"client":r()}),flush=True)
def h(c):
 try:
  c.recv(65536); b=b"socks-lifecycle-tcp-ok\n"; c.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: "+str(len(b)).encode()+b"\r\nConnection: close\r\n\r\n"+b)
 finally: c.close()
while 1:
 rdy,_,_=select.select([t,u],[],[],1)
 for s in rdy:
  if s is t: c,_=t.accept(); threading.Thread(target=h,args=(c,),daemon=True).start()
  else: b,a=u.recvfrom(65536); u.sendto(b,a)
PY_MARKER
  cat > "${TMP_DIR}/udp.py" <<'PY_UDP'
import socket,sys
p,d,u,w=int(sys.argv[1]),int(sys.argv[2]),sys.argv[3].encode(),sys.argv[4].encode(); want=b"socks-lifecycle-udp-ok"
def x(s,n):
 b=b""
 while len(b)<n:
  q=s.recv(n-len(b))
  if not q: raise SystemExit("SOCKS control closed")
  b+=q
 return b
c=socket.create_connection(("127.0.0.1",p),3); c.sendall(b"\x05\x02\x00\x02"); m=x(c,2)
if m[0]!=5: raise SystemExit("SOCKS greeting failed")
if m[1]==2:
 c.sendall(b"\x01"+bytes([len(u)])+u+bytes([len(w)])+w)
 if x(c,2)!=b"\x01\x00": raise SystemExit("SOCKS auth failed")
elif m[1]!=0: raise SystemExit("SOCKS method failed")
c.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00"); h=x(c,4)
if h[:2]!=b"\x05\x00": raise SystemExit("UDP associate failed")
if h[3]==1: x(c,4)
elif h[3]==3: x(c,x(c,1)[0])
elif h[3]==4: x(c,16)
else: raise SystemExit("UDP address type failed")
rp=int.from_bytes(x(c,2),"big"); q=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); q.settimeout(5)
q.sendto(b"\0\0\0\1\177\0\0\1"+d.to_bytes(2,"big")+want,("127.0.0.1",rp)); z,_=q.recvfrom(65536)
if z[:4]!=b"\0\0\0\1" or z[10:]!=want: raise SystemExit("UDP payload mismatch")
print(want.decode(),end=""); c.close(); q.close()
PY_UDP
  marker_pid=''; core_pid=''; client_pid=''
  cleanup() {
    local rc=$? pid attempt
    if (( rc != 0 )); then [[ ! -f "${TMP_DIR}/core.log" ]] || tail -80 "${TMP_DIR}/core.log" >&2; fi
    for pid in "${core_pid}" "${client_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then kill "${pid}"; for attempt in {1..20}; do kill -0 "${pid}" 2>/dev/null || break; sleep 0.05; done; if kill -0 "${pid}" 2>/dev/null; then kill -KILL "${pid}"; fi; fi
      if wait "${pid}" 2>/dev/null; then :; else :; fi
    done
    if [[ -s "${SBV_SOCKS_CORE_PID_FILE}" ]]; then pid=$(<"${SBV_SOCKS_CORE_PID_FILE}"); if [[ "${pid}" != "${core_pid}" && "${pid}" != "${marker_pid}" ]] && kill -0 "${pid}" 2>/dev/null; then kill "${pid}"; fi; fi
    rm -rf -- "${TMP_DIR}"; return "${rc}"
  }
  trap cleanup EXIT
  python3 -u "${TMP_DIR}/marker.py" >"${TMP_DIR}/ports.json" 2>"${TMP_DIR}/marker.stderr" & marker_pid=$!
  for _ in {1..100}; do [[ -s "${TMP_DIR}/ports.json" ]] && break; kill -0 "${marker_pid}"; sleep 0.02; done
  jq -e 'all(.[]; .>0)' "${TMP_DIR}/ports.json" >/dev/null
  marker_tcp=$(jq -r .tcp "${TMP_DIR}/ports.json"); marker_udp=$(jq -r .udp "${TMP_DIR}/ports.json"); mixed_port=$(jq -r .mixed "${TMP_DIR}/ports.json"); main_port=$(jq -r .main "${TMP_DIR}/ports.json"); edge_port=$(jq -r .edge "${TMP_DIR}/ports.json"); beta_port=$(jq -r .beta "${TMP_DIR}/ports.json"); replace_port=$(jq -r .replace "${TMP_DIR}/ports.json"); alpha_port=$(jq -r .alpha "${TMP_DIR}/ports.json"); client_port=$(jq -r .client "${TMP_DIR}/ports.json")
  printf '%s\n' 'INSTALLED_PROTOCOLS=mixed' 'PROTOCOL_STATE_VERSION=1' >"${SB_PROTOCOL_INDEX_FILE}"
  cat >"${SB_PROTOCOL_STATE_DIR}/mixed.env" <<EOF_MIXED
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy-mixed
PORT=${mixed_port}
AUTH_ENABLED=y
USERNAME=mixed-user
PASSWORD=mixed-password
EOF_MIXED
  jq -n --argjson m "${mixed_port}" '{log:{level:"warn"},inbounds:[{type:"mixed",tag:"mixed-in",listen:"127.0.0.1",listen_port:$m,users:[{username:"mixed-user",password:"mixed-password"}]}],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' >"${SINGBOX_CONFIG_FILE}"
  "${SBV_SOCKS_REAL_CORE}" check -c "${SINGBOX_CONFIG_FILE}"
  "${SBV_SOCKS_REAL_CORE}" run -c "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/core.log" 2>&1 & core_pid=$!
  printf '%s\n' "${core_pid}" >"${SBV_SOCKS_CORE_PID_FILE}"
  instance_firewall_prepare() { printf 'prepare\n' >>"${TMP_DIR}/firewall.log"; return 0; }
  instance_firewall_apply() { printf 'apply\n' >>"${TMP_DIR}/firewall.log"; return 0; }
  instance_firewall_rollback() { printf 'rollback\n' >>"${TMP_DIR}/firewall.log"; return 0; }
  expect_success() { local label=$1 rev=$2; shift 2; agent_cli instance "$@" >"${TMP_DIR}/${label}.json" 2>"${TMP_DIR}/${label}.stderr" || { cat "${TMP_DIR}/${label}.stderr" >&2; return 1; }; jq -e --argjson r "${rev}" '.ok==true and .revision==$r and .data.revision==$r' "${TMP_DIR}/${label}.json" >/dev/null; }
  expect_failure() { local label=$1; shift; if agent_cli instance "$@" >"${TMP_DIR}/${label}.json" 2>"${TMP_DIR}/${label}.stderr"; then return 1; fi; jq -e '.ok==false and (.error|type=="string") and (.data.ok==false)' "${TMP_DIR}/${label}.json" >/dev/null; }
  make_record() { jq -n --arg id "$1" --arg name "$2" --arg tag "$3" --arg user "$5" --arg pass "$6" --argjson port "$4" '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},authentication:{enabled:true,username:$user,password:$pass},outbound_policy:"default",dependencies:[]}' >"$7"; }
  probe_tcp() { local p=$1 u=$2 w=$3; for _ in {1..100}; do if curl --silent --show-error --fail --max-time 2 --noproxy '' --proxy "socks5h://127.0.0.1:${p}" --proxy-user "${u}:${w}" "http://127.0.0.1:${marker_tcp}/" >"${TMP_DIR}/tcp-${p}" 2>/dev/null; then grep -Fqx 'socks-lifecycle-tcp-ok' "${TMP_DIR}/tcp-${p}"; return; fi; sleep 0.05; done; return 1; }
  probe_udp() { python3 "${TMP_DIR}/udp.py" "$1" "${marker_udp}" "$2" "$3" >"${TMP_DIR}/udp-$1"; grep -Fqx 'socks-lifecycle-udp-ok' "${TMP_DIR}/udp-$1"; }
  refresh_core_pid() { core_pid=$(<"${SBV_SOCKS_CORE_PID_FILE}"); }
  make_record main 'Main SOCKS' socks-main "${main_port}" main-user main-password "${TMP_DIR}/main.json"
  make_record edge 'Edge SOCKS' socks-edge "${edge_port}" edge-user edge-password "${TMP_DIR}/edge.json"
  make_record edge 'Updated Edge' socks-edge "${replace_port}" edge-user-2 updated-edge-password "${TMP_DIR}/edge-updated.json"
  make_record alpha 'Alpha SOCKS' socks-alpha "${alpha_port}" alpha-user alpha-password "${TMP_DIR}/alpha.json"
  expect_success create_main 1 create socks --json --yes --expected-revision 0 --file "${TMP_DIR}/main.json"
  refresh_core_pid
  expect_success create_edge 2 create socks --json --yes --expected-revision 1 --file "${TMP_DIR}/edge.json"
  refresh_core_pid
  jq -e '.revision==2 and (.instances|length)==2 and any(.instances[];.id=="main" and .authentication.password=="main-password")' "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
  jq -e 'any(.inbounds[];.type=="mixed" and .tag=="mixed-in") and any(.inbounds[];.tag=="socks-main") and any(.inbounds[];.tag=="socks-edge") and all(.inbounds[] | select(.tag != "mixed-in"); .type=="socks")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  probe_tcp "${mixed_port}" mixed-user mixed-password; probe_udp "${mixed_port}" mixed-user mixed-password; probe_tcp "${main_port}" main-user main-password; probe_udp "${main_port}" main-user main-password; probe_tcp "${edge_port}" edge-user edge-password; probe_udp "${edge_port}" edge-user edge-password
  if curl --silent --show-error --fail --max-time 2 --noproxy '' --proxy "socks5h://127.0.0.1:${edge_port}" --proxy-user wrong:wrong "http://127.0.0.1:${marker_tcp}/" >/dev/null 2>&1; then exit 1; fi
  if curl --silent --show-error --fail --max-time 2 --noproxy '' --proxy "http://127.0.0.1:${edge_port}" "http://127.0.0.1:${marker_tcp}/" >/dev/null 2>&1; then exit 1; fi
  build_client_outbound_json_for_protocol socks 127.0.0.1 >"${TMP_DIR}/exported.jsonl"
  jq -s -e 'length==2 and all(.[];.type=="socks" and .version=="5" and .udp_over_tcp.enabled==true and .udp_over_tcp.version==2)' "${TMP_DIR}/exported.jsonl" >/dev/null
  exported_edge=$(jq -c 'select(.tag=="socks-edge")' "${TMP_DIR}/exported.jsonl")
  jq -n --argjson o "${exported_edge}" --argjson p "${client_port}" '{log:{level:"warn"},inbounds:[{type:"mixed",tag:"local",listen:"127.0.0.1",listen_port:$p}],outbounds:[$o,{type:"direct",tag:"direct"}],route:{final:$o.tag}}' >"${TMP_DIR}/client.json"
  "${SBV_SOCKS_REAL_CORE}" check -c "${TMP_DIR}/client.json"
  "${SBV_SOCKS_REAL_CORE}" run -c "${TMP_DIR}/client.json" >"${TMP_DIR}/client.log" 2>&1 & client_pid=$!
  for _ in {1..100}; do if curl --silent --show-error --fail --max-time 2 --noproxy '' --proxy "socks5h://127.0.0.1:${client_port}" "http://127.0.0.1:${marker_tcp}/" >"${TMP_DIR}/export-tcp" 2>/dev/null; then break; fi; sleep 0.05; done
  grep -Fqx 'socks-lifecycle-tcp-ok' "${TMP_DIR}/export-tcp"
  python3 "${TMP_DIR}/udp.py" "${client_port}" "${marker_udp}" '' '' >"${TMP_DIR}/export-udp"
  grep -Fqx 'socks-lifecycle-udp-ok' "${TMP_DIR}/export-udp"
  kill "${client_pid}"; if wait "${client_pid}" 2>/dev/null; then :; else :; fi; client_pid=''
  expect_success replace_edge 3 replace socks --json --yes --expected-revision 2 --file "${TMP_DIR}/edge-updated.json"
  refresh_core_pid
  probe_tcp "${replace_port}" edge-user-2 updated-edge-password; probe_udp "${replace_port}" edge-user-2 updated-edge-password; probe_tcp "${mixed_port}" mixed-user mixed-password; probe_udp "${mixed_port}" mixed-user mixed-password
  expect_success delete_main 4 delete socks --json --yes --expected-revision 3 --id main
  refresh_core_pid
  jq -e 'any(.inbounds[];.type=="mixed" and .tag=="mixed-in") and any(.inbounds[];.tag=="socks-edge") and all(.inbounds[];.tag!="socks-main") and all(.inbounds[] | select(.tag != "mixed-in"); .type=="socks")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  probe_tcp "${replace_port}" edge-user-2 updated-edge-password; probe_udp "${replace_port}" edge-user-2 updated-edge-password; probe_tcp "${mixed_port}" mixed-user mixed-password; probe_udp "${mixed_port}" mixed-user mixed-password
  before_store=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json"); before_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  touch "${TMP_DIR}/check-fail"; export SBV_SOCKS_CHECK_FAIL_FILE="${TMP_DIR}/check-fail"
  expect_failure failed_candidate create socks --json --yes --expected-revision 4 --file "${TMP_DIR}/alpha.json"
  unset SBV_SOCKS_CHECK_FAIL_FILE; rm -f -- "${TMP_DIR}/check-fail"
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${before_store}" && "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config}" ]]
  kill -0 "${core_pid}"; probe_tcp "${replace_port}" edge-user-2 updated-edge-password; probe_udp "${replace_port}" edge-user-2 updated-edge-password
  printf 'socks instance runtime passed: core=%s (migration=0, instances=2, exported=2, tcp=9, udp=9, wrong-auth=1, failed-candidate=1)\n' "${core_label}"
else
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then printf 'SKIP socks instance runtime: real cores unavailable\n'; exit 0; fi
  if [[ -n "${SINGBOX_BINARY_113:-}" && -x "${SINGBOX_BINARY_113}" ]]; then bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18; else printf 'SKIP socks instance runtime: SINGBOX_BINARY_113 unavailable\n'; fi
  if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0; else printf 'SKIP socks instance runtime: SINGBOX_BINARY_114 unavailable\n'; fi
fi
