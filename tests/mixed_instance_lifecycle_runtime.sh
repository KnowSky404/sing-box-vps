#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTS_DIR="${REPO_ROOT}/tests"

if [[ "${1:-}" == --run ]]; then
  core_binary=$2
  core_label=$3

  # Source the generated installer at file scope.  This matters on Bash 4.2:
  # sourcing it from inside a helper function makes readonly arrays local.
  source "${TESTS_DIR}/menu_test_helper.sh"
  setup_menu_test_env 120
  cp -p "${core_binary}" "${TMP_DIR}/real-sing-box"
  cat > "${TMP_DIR}/bin/sing-box" <<'EOF_CORE_WRAPPER'
#!/usr/bin/env bash
if [[ "${1:-}" == check && -n "${SBV_RUNTIME_CHECK_FAIL_FILE:-}" && -e "${SBV_RUNTIME_CHECK_FAIL_FILE}" ]]; then
  printf 'injected runtime core-check failure\n' >&2
  exit 23
fi
exec "${SBV_RUNTIME_REAL_CORE:?}" "$@"
EOF_CORE_WRAPPER
  chmod +x "${TMP_DIR}/bin/sing-box"
  export SBV_RUNTIME_REAL_CORE="${TMP_DIR}/real-sing-box"
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  export SINGBOX_CONFIG_FILE

  mkdir -p "${SB_PROTOCOL_STATE_DIR}" "${SB_PROJECT_DIR}"
  printf '%s\n' 'active' > "${TMP_DIR}/systemctl.state"
  printf '0\n' > "${TMP_DIR}/systemctl.restarts"
  : > "${TMP_DIR}/systemctl.log"
  : > "${TMP_DIR}/firewall.log"
  export SBV_RUNTIME_STATE_FILE="${TMP_DIR}/systemctl.state"
  export SBV_RUNTIME_RESTART_FILE="${TMP_DIR}/systemctl.restarts"
  export SBV_RUNTIME_SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log"
  export SBV_RUNTIME_CORE_PID_FILE="${TMP_DIR}/core.pid"
  export SBV_RUNTIME_CORE_LOG="${TMP_DIR}/core.log"

  cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
state_file=${SBV_RUNTIME_STATE_FILE:?missing state file}
restart_file=${SBV_RUNTIME_RESTART_FILE:?missing restart file}
log_file=${SBV_RUNTIME_SYSTEMCTL_LOG:?missing systemctl log}
pid_file=${SBV_RUNTIME_CORE_PID_FILE:?missing core pid file}
core_log=${SBV_RUNTIME_CORE_LOG:?missing core log}
printf '%s\n' "$*" >> "${log_file}"
if [[ "$*" == 'show -p ActiveState --value sing-box' ]]; then
  cat "${state_file}"
  exit 0
fi
case "${1:-}:${2:-}:${3:-}" in
  is-active:--quiet:sing-box)
    [[ "$(<"${state_file}")" == active ]]
    ;;
  is-active:sing-box:)
    cat "${state_file}"
    [[ "$(<"${state_file}")" == active ]]
    ;;
  restart:sing-box:)
    count=$(<"${restart_file}")
    printf '%s\n' "$((count + 1))" > "${restart_file}"
    if [[ -n "${SBV_RUNTIME_RESTART_FAIL_FILE:-}" && -e "${SBV_RUNTIME_RESTART_FAIL_FILE}" ]]; then
      rm -f -- "${SBV_RUNTIME_RESTART_FAIL_FILE}"
      printf 'injected restart failure\n' >&2
      exit 55
    fi
    if [[ -s "${pid_file}" ]]; then
      old_pid=$(<"${pid_file}")
      if kill -0 "${old_pid}" 2>/dev/null; then kill "${old_pid}"; fi
      if wait "${old_pid}" 2>/dev/null; then :; else :; fi
    fi
    # apply_mixed_instance_change holds its management flock while invoking
    # this test double.  Do not let the replacement core inherit that fd, or
    # the next public mutation would look falsely concurrent.
    for fd in {3..20}; do eval "exec ${fd}>&-"; done
    "${SBV_RUNTIME_REAL_CORE}" run -c "${SINGBOX_CONFIG_FILE}" >"${core_log}" 2>&1 &
    printf '%s\n' "$!" > "${pid_file}"
    printf 'active\n' > "${state_file}"
    ;;
  stop:sing-box:)
    if [[ -s "${pid_file}" ]]; then
      old_pid=$(<"${pid_file}")
      if kill -0 "${old_pid}" 2>/dev/null; then kill "${old_pid}"; fi
    fi
    printf 'inactive\n' > "${state_file}"
    ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
  chmod +x "${TMP_DIR}/bin/systemctl"

  cat > "${TMP_DIR}/ports.py" <<'PY_PORTS'
import json
import select
import socket
import threading

tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind(("127.0.0.1", 0))
tcp.listen(16)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(("127.0.0.1", 0))

def reserve():
    while True:
        tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        tcp_sock.bind(("127.0.0.1", 0))
        port = tcp_sock.getsockname()[1]
        udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            udp_sock.bind(("127.0.0.1", port))
        except OSError:
            tcp_sock.close()
            udp_sock.close()
            continue
        tcp_sock.close()
        udp_sock.close()
        return port

print(json.dumps({
    "marker_tcp": tcp.getsockname()[1], "marker_udp": udp.getsockname()[1],
    "main": reserve(), "edge": reserve(), "beta": reserve(), "edge_new": reserve(), "alpha": reserve()
}), flush=True)

def serve(connection):
    try:
        connection.settimeout(3)
        connection.recv(65536)
        body = b"mixed-instance-tcp-ok\n"
        connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
                           + b"\r\nConnection: close\r\n\r\n" + body)
    finally:
        connection.close()

while True:
    readable, _, _ = select.select([tcp, udp], [], [], 1)
    for ready in readable:
        if ready is tcp:
            connection, _ = tcp.accept()
            threading.Thread(target=serve, args=(connection,), daemon=True).start()
        else:
            payload, address = udp.recvfrom(65536)
            udp.sendto(payload, address)
PY_PORTS

  cat > "${TMP_DIR}/udp-probe.py" <<'PY_UDP'
import socket
import sys

proxy_port = int(sys.argv[1])
destination_port = int(sys.argv[2])
expected = sys.argv[3].encode()
username = sys.argv[4].encode()
password = sys.argv[5].encode()

def recv_exact(sock, size):
    result = b""
    while len(result) < size:
        chunk = sock.recv(size - len(result))
        if not chunk:
            raise SystemExit("SOCKS control connection closed early")
        result += chunk
    return result

control = socket.create_connection(("127.0.0.1", proxy_port), timeout=3)
control.sendall(b"\x05\x02\x00\x02")
method_reply = recv_exact(control, 2)
if method_reply[:1] != b"\x05":
    raise SystemExit("SOCKS greeting failed")
if method_reply[1] == 2:
    if len(username) > 255 or len(password) > 255:
        raise SystemExit("SOCKS credentials are too long")
    control.sendall(b"\x01" + bytes([len(username)]) + username + bytes([len(password)]) + password)
    if recv_exact(control, 2) != b"\x01\x00":
        raise SystemExit("SOCKS authentication failed")
elif method_reply[1] != 0:
    raise SystemExit("SOCKS server selected an unsupported method")
control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
reply = recv_exact(control, 4)
if reply[:2] != b"\x05\x00" or reply[3] not in (1, 3, 4):
    raise SystemExit("UDP associate failed")
if reply[3] == 1:
    recv_exact(control, 4)
elif reply[3] == 3:
    recv_exact(control, recv_exact(control, 1)[0])
else:
    recv_exact(control, 16)
relay_port = int.from_bytes(recv_exact(control, 2), "big")

udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.settimeout(5)
request = b"\x00\x00\x00\x01\x7f\x00\x00\x01" + destination_port.to_bytes(2, "big") + expected
udp.sendto(request, ("127.0.0.1", relay_port))
response, _ = udp.recvfrom(65536)
if response[:3] != b"\x00\x00\x00" or response[3] != 1 or response[10:] != expected:
    raise SystemExit("UDP payload did not survive Mixed instance")
print(response[10:].decode(), end="")
control.close()
udp.close()
PY_UDP

  marker_pid=''
  core_pid=''
  cleanup_runtime() {
    local pid cleanup_status=$? attempt
    if (( cleanup_status != 0 )); then
      printf 'Mixed runtime core log (%s):\n' "${core_label}" >&2
      if [[ -f "${TMP_DIR}/core.log" ]]; then
        tail -80 "${TMP_DIR}/core.log" >&2
      fi
      if [[ -f "${TMP_DIR}/systemctl.log" ]]; then
        printf 'systemctl calls:\n' >&2
        cat "${TMP_DIR}/systemctl.log" >&2
      fi
    fi
    for pid in "${core_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}"
        for attempt in {1..20}; do
          kill -0 "${pid}" 2>/dev/null || break
          sleep 0.05
        done
        if kill -0 "${pid}" 2>/dev/null; then kill -KILL "${pid}"; fi
      fi
      if wait "${pid}" 2>/dev/null; then :; else :; fi
    done
    if [[ -s "${SBV_RUNTIME_CORE_PID_FILE}" ]]; then
      pid=$(<"${SBV_RUNTIME_CORE_PID_FILE}")
      if [[ "${pid}" != "${core_pid}" && "${pid}" != "${marker_pid}" ]] &&
         kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}"
      fi
    fi
    rm -rf -- "${TMP_DIR}"
    return "${cleanup_status}"
  }
  trap cleanup_runtime EXIT

  python3 -u "${TMP_DIR}/ports.py" > "${TMP_DIR}/ports.json" 2> "${TMP_DIR}/ports.stderr" &
  marker_pid=$!
  for _ in {1..100}; do
    [[ -s "${TMP_DIR}/ports.json" ]] && break
    kill -0 "${marker_pid}"
    sleep 0.02
  done
  jq -e 'all(.[]; . > 0)' "${TMP_DIR}/ports.json" >/dev/null
  marker_tcp=$(jq -r .marker_tcp "${TMP_DIR}/ports.json")
  marker_udp=$(jq -r .marker_udp "${TMP_DIR}/ports.json")
  main_port=$(jq -r .main "${TMP_DIR}/ports.json")
  edge_port=$(jq -r .edge "${TMP_DIR}/ports.json")
  beta_port=$(jq -r .beta "${TMP_DIR}/ports.json")
  edge_new_port=$(jq -r .edge_new "${TMP_DIR}/ports.json")
  alpha_port=$(jq -r .alpha "${TMP_DIR}/ports.json")

  cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF_INDEX
  cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<EOF_LEGACY
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy-mixed
PORT=${main_port}
AUTH_ENABLED=y
USERNAME=legacy-user
PASSWORD=legacy-password
EOF_LEGACY
  jq -n --argjson port "${main_port}" '
    {log:{level:"warn"},inbounds:[{type:"mixed",tag:"mixed-in",listen_port:$port,
      users:[{username:"legacy-user",password:"legacy-password"}]}],
     outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}
  ' > "${SINGBOX_CONFIG_FILE}"
  printf '%s\n' 'STACK_STATE_VERSION=1' 'INBOUND_STACK_MODE=dual_stack' \
    'OUTBOUND_STACK_MODE=dual_stack' > "${SB_STACK_STATE_FILE}"
  "${SBV_RUNTIME_REAL_CORE}" check -c "${SINGBOX_CONFIG_FILE}"
  "${SBV_RUNTIME_REAL_CORE}" run -c "${SINGBOX_CONFIG_FILE}" >"${TMP_DIR}/core.log" 2>&1 &
  core_pid=$!
  printf '%s\n' "${core_pid}" > "${SBV_RUNTIME_CORE_PID_FILE}"

  instance_firewall_prepare() { printf 'prepare\n' >> "${TMP_DIR}/firewall.log"; return 0; }
  instance_firewall_apply() { printf 'apply\n' >> "${TMP_DIR}/firewall.log"; return 0; }
  instance_firewall_rollback() { printf 'rollback\n' >> "${TMP_DIR}/firewall.log"; return 0; }

  expect_success() {
    local label=$1 revision=$2
    shift 2
    if ! agent_cli instance "$@" >"${TMP_DIR}/${label}.json" 2>"${TMP_DIR}/${label}.stderr"; then
      printf '%s unexpectedly failed\n' "${label}" >&2
      cat "${TMP_DIR}/${label}.stderr" >&2
      return 1
    fi
    jq -e --argjson revision "${revision}" \
      '.ok == true and .revision == $revision and .data.revision == $revision' \
      "${TMP_DIR}/${label}.json" >/dev/null
  }

  expect_failure() {
    local label=$1
    shift
    if agent_cli instance "$@" >"${TMP_DIR}/${label}.json" 2>"${TMP_DIR}/${label}.stderr"; then
      printf '%s unexpectedly succeeded\n' "${label}" >&2
      return 1
    fi
    jq -e '.ok == false and (.error | type == "string") and (.data.ok == false)' \
      "${TMP_DIR}/${label}.json" >/dev/null
    if grep -Eq 'legacy-password|edge-password|beta-password|updated-edge-password' \
      "${TMP_DIR}/${label}.json"; then
      printf '%s leaked credentials\n' "${label}" >&2
      return 1
    fi
  }

  refresh_core_pid() {
    core_pid=$(<"${SBV_RUNTIME_CORE_PID_FILE}")
  }

  make_record() {
    local id=$1 name=$2 tag=$3 port=$4 user=$5 password=$6 file=$7
    jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg user "${user}" \
      --arg password "${password}" --argjson port "${port}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
        authentication:{enabled:true,username:$user,password:$password},
        outbound_policy:"default",dependencies:[]}' > "${file}"
  }

  make_record edge 'Edge Mixed' mixed-edge "${edge_port}" edge-user edge-password "${TMP_DIR}/edge.json"
  make_record beta 'Beta Mixed' mixed-beta "${beta_port}" beta-user beta-password "${TMP_DIR}/beta.json"
  make_record edge 'Updated Edge' mixed-edge "${edge_new_port}" edge-user-2 updated-edge-password "${TMP_DIR}/edge-updated.json"
  make_record alpha 'Alpha Mixed' mixed-alpha "${alpha_port}" alpha-user alpha-password "${TMP_DIR}/alpha.json"

  probe_tcp() {
    local port=$1 user=$2 password=$3
    local body="${TMP_DIR}/tcp-${port}.body"
    for _ in {1..100}; do
      if curl --silent --show-error --fail --max-time 2 --noproxy '' \
        --proxy "socks5h://127.0.0.1:${port}" --proxy-user "${user}:${password}" \
        "http://127.0.0.1:${marker_tcp}/" > "${body}" 2>"${body}.stderr"; then
        grep -Fqx 'mixed-instance-tcp-ok' "${body}"
        return 0
      fi
      sleep 0.05
    done
    return 1
  }
  probe_udp() {
    local port=$1 user=$2 password=$3
    python3 "${TMP_DIR}/udp-probe.py" "${port}" "${marker_udp}" "mixed-instance-udp-ok" "${user}" "${password}" \
      > "${TMP_DIR}/udp-${port}.body"
    grep -Fqx 'mixed-instance-udp-ok' "${TMP_DIR}/udp-${port}.body"
  }

  # Explicit migration is the only operation that activates the structured
  # store. It must retain the legacy listener and credentials.
  expect_success migrate 1 migrate mixed --json --yes --expected-revision 0
  refresh_core_pid
  jq -e '.revision == 1 and .default_instance_id == "main" and (.instances|length)==1 and
    .instances[0].authentication.password == "legacy-password" and
    .instances[0].listen.address == "127.0.0.1" and
    .instances[0].listen.port == ('"${main_port}"')' \
    "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
  jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].listen_port == ('"${main_port}"')' \
    "${SINGBOX_CONFIG_FILE}" >/dev/null
  probe_tcp "${main_port}" legacy-user legacy-password
  probe_udp "${main_port}" legacy-user legacy-password

  expect_success create_edge 2 create mixed --json --yes --expected-revision 1 --file "${TMP_DIR}/edge.json"
  refresh_core_pid
  expect_success create_beta 3 create mixed --json --yes --expected-revision 2 --file "${TMP_DIR}/beta.json"
  refresh_core_pid
  jq -e '([.instances[].id] | sort) == ["beta","edge","main"] and
    all(.instances[]; .authentication.enabled == true)' \
    "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null

  probe_tcp "${edge_port}" edge-user edge-password
  probe_udp "${edge_port}" edge-user edge-password
  probe_tcp "${beta_port}" beta-user beta-password
  probe_udp "${beta_port}" beta-user beta-password
  if curl --silent --show-error --fail --max-time 2 --noproxy '' \
    --proxy "socks5h://127.0.0.1:${edge_port}" --proxy-user wrong:wrong \
    "http://127.0.0.1:${marker_tcp}/" >"${TMP_DIR}/wrong.body" 2>"${TMP_DIR}/wrong.stderr"; then
    printf 'wrong Mixed credentials were accepted\n' >&2
    exit 1
  fi

  # Replace changes one listener and its credentials; beta must continue to
  # serve with its original material.
  expect_success replace_edge 4 replace mixed --json --yes --expected-revision 3 --file "${TMP_DIR}/edge-updated.json"
  refresh_core_pid
  jq -e 'any(.instances[]; .id=="edge" and .listen.port == ('"${edge_new_port}"') and
    .authentication.password == "updated-edge-password") and
    any(.instances[]; .id=="beta" and .listen.port == ('"${beta_port}"') and
    .authentication.password == "beta-password")' \
    "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
  probe_tcp "${edge_new_port}" edge-user-2 updated-edge-password
  probe_udp "${edge_new_port}" edge-user-2 updated-edge-password
  probe_tcp "${beta_port}" beta-user beta-password
  probe_udp "${beta_port}" beta-user beta-password

  expect_success delete_beta 5 delete mixed --json --yes --expected-revision 4 --id beta
  refresh_core_pid
  jq -e '([.instances[].id] | sort) == ["edge","main"] and
    all(.instances[]; .id != "beta")' "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json" >/dev/null
  probe_tcp "${edge_new_port}" edge-user-2 updated-edge-password
  probe_udp "${edge_new_port}" edge-user-2 updated-edge-password

  # A failed candidate check must leave the old service and managed state live.
  before_store=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")
  before_config=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  touch "${TMP_DIR}/core-check-fail"
  export SBV_RUNTIME_CHECK_FAIL_FILE="${TMP_DIR}/core-check-fail"
  expect_failure failed_candidate create mixed --json --yes --expected-revision 5 --file "${TMP_DIR}/alpha.json"
  unset SBV_RUNTIME_CHECK_FAIL_FILE
  rm -f -- "${TMP_DIR}/core-check-fail"
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/mixed.json")" == "${before_store}" ]]
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config}" ]]
  kill -0 "${core_pid}"
  probe_tcp "${edge_new_port}" edge-user-2 updated-edge-password
  probe_udp "${edge_new_port}" edge-user-2 updated-edge-password

  printf 'mixed instance runtime passed: core=%s (migration=1, instances=2, tcp=7, udp=7, wrong-auth=1, failed-candidate=1)\n' \
    "${core_label}"
else
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'SKIP mixed instance runtime: SINGBOX_BINARY_113/SINGBOX_BINARY_114 are unavailable\n'
    exit 0
  fi
  if [[ -n "${SINGBOX_BINARY_113:-}" && -x "${SINGBOX_BINARY_113}" ]]; then
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18
  else
    printf 'SKIP mixed instance runtime: SINGBOX_BINARY_113 is unavailable\n'
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0
  else
    printf 'SKIP mixed instance runtime: SINGBOX_BINARY_114 is unavailable\n'
  fi
fi
