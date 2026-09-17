#!/usr/bin/env bash

set -euo pipefail

# This regression test intentionally keeps the exported Mixed outbound as the
# only remote component in a reduced runtime config.  The complete export is
# still checked first, but its remote rule-set downloads are not a prerequisite
# for the local TCP/UDP proof below.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTS_DIR="${REPO_ROOT}/tests"

run_version() {
  local binary=$1
  local version_label=$2
  local server_binary=${3:-${binary}}
  local server_version_label=${4:-${version_label}}
  local mode
  get_public_ip() {
    printf '127.0.0.1\n'
  }

  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  printf '%s\n' \
    'INSTALLED_PROTOCOLS=mixed' \
    'PROTOCOL_STATE_VERSION=1' > "${SB_PROTOCOL_INDEX_FILE}"

  cat > "${TMP_DIR}/port-helper.py" <<'PY'
import json
import select
import socket
import sys
import threading

marker_tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
marker_tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
marker_tcp.bind(("127.0.0.1", 0))
marker_tcp.listen(16)
marker_udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
marker_udp.bind(("127.0.0.1", 0))

def reserve_tcp_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    return sock

reserved = [reserve_tcp_socket(), reserve_tcp_socket()]
print(json.dumps({
    "marker_tcp": marker_tcp.getsockname()[1],
    "marker_udp": marker_udp.getsockname()[1],
    "server": reserved[0].getsockname()[1],
    "client": reserved[1].getsockname()[1],
}), flush=True)
for sock in reserved:
    sock.close()

def serve_tcp(connection):
    try:
        connection.settimeout(2)
        connection.recv(65536)
        body = b"mixed-export-tcp-ok\n"
        connection.sendall(
            b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n" + body
        )
    finally:
        connection.close()

while True:
    readable, _, _ = select.select([marker_tcp, marker_udp], [], [], 1)
    for ready in readable:
        if ready is marker_tcp:
            connection, _ = marker_tcp.accept()
            threading.Thread(target=serve_tcp, args=(connection,), daemon=True).start()
        else:
            payload, address = marker_udp.recvfrom(65536)
            marker_udp.sendto(payload, address)
PY

  cat > "${TMP_DIR}/udp-probe.py" <<'PY'
import socket
import sys

proxy_port = int(sys.argv[1])
destination_port = int(sys.argv[2])
expected = b"mixed-export-udp-ok"

def recv_exact(sock, size):
    chunks = []
    while sum(len(chunk) for chunk in chunks) < size:
        chunk = sock.recv(size - sum(len(chunk) for chunk in chunks))
        if not chunk:
            raise SystemExit("SOCKS control connection closed early")
        chunks.append(chunk)
    return b"".join(chunks)

control = socket.create_connection(("127.0.0.1", proxy_port), timeout=3)
control.sendall(b"\x05\x01\x00")
reply = recv_exact(control, 2)
if reply != b"\x05\x00":
    raise SystemExit("local mixed SOCKS greeting failed")
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
packet = b"\x00\x00\x00\x01\x7f\x00\x00\x01" + destination_port.to_bytes(2, "big") + expected
udp.sendto(packet, ("127.0.0.1", relay_port))
response, _ = udp.recvfrom(65536)
if response[0:3] != b"\x00\x00\x00" or response[3] != 1:
    raise SystemExit("unexpected SOCKS UDP response header")
header_length = 10
if response[header_length:] != expected:
    raise SystemExit("UDP payload did not survive exported Mixed outbound")
print(response[header_length:].decode(), end="")
control.close()
udp.close()
PY

  python3 -u "${TMP_DIR}/port-helper.py" > "${TMP_DIR}/ports.json" 2> "${TMP_DIR}/port-helper.stderr" &
  marker_pid=$!

  for _ in {1..100}; do
    [[ -s "${TMP_DIR}/ports.json" ]] && break
    kill -0 "${marker_pid}"
    sleep 0.02
  done
  jq -e '.marker_tcp > 0 and .marker_udp > 0 and .server > 0 and .client > 0' \
    "${TMP_DIR}/ports.json" >/dev/null
  local marker_tcp marker_udp server_port client_port
  marker_tcp=$(jq -r .marker_tcp "${TMP_DIR}/ports.json")
  marker_udp=$(jq -r .marker_udp "${TMP_DIR}/ports.json")
  server_port=$(jq -r .server "${TMP_DIR}/ports.json")
  client_port=$(jq -r .client "${TMP_DIR}/ports.json")

  for mode in auth no-auth; do
    local auth_enabled username password
    if [[ "${mode}" == auth ]]; then
      auth_enabled=y
      username=mixed-runtime-user
      password=mixed-runtime-password
    else
      auth_enabled=n
      username=''
      password=''
    fi

    cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<EOF_STATE
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_runtime_${version_label}_${mode}
PORT=${server_port}
AUTH_ENABLED=${auth_enabled}
USERNAME=${username}
PASSWORD=${password}
EOF_STATE
    load_protocol_instance_state mixed main
    local server_inbound full_config outbound_json
    server_inbound=$(build_mixed_inbound_json | jq --argjson port "${server_port}" \
      '.listen = "127.0.0.1" | .listen_port = $port')
    full_config=$(build_singbox_client_config)
    printf '%s\n' "${full_config}" > "${TMP_DIR}/full-${mode}.json"
    validate_client_config_json "${full_config}"
    jq -e --arg mode "${mode}" '
      ([.outbounds[] | select(.type == "socks")] | length) == 1 and
      (([.outbounds[] | select(.type == "socks")][0] | has("network")) | not) and
      ([.outbounds[] | select(.type == "socks")][0].udp_over_tcp.enabled) == true and
      ([.outbounds[] | select(.type == "socks")][0].udp_over_tcp.version) == 2 and
      (if $mode == "auth" then
        ([.outbounds[] | select(.type == "socks")][0].username) == "mixed-runtime-user" and
        ([.outbounds[] | select(.type == "socks")][0].password) == "mixed-runtime-password"
      else
        ([.outbounds[] | select(.type == "socks")][0] | has("username") or has("password")) | not
      end)
    ' "${TMP_DIR}/full-${mode}.json" >/dev/null

    outbound_json=$(jq -c '.outbounds[] | select(.type == "socks")' "${TMP_DIR}/full-${mode}.json")
    jq -n --argjson inbound "${server_inbound}" \
      '{log:{level:"warn"},inbounds:[$inbound],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
      > "${TMP_DIR}/server-${mode}.json"
    jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].type == "mixed"' \
      "${TMP_DIR}/server-${mode}.json" >/dev/null
    "${TMP_DIR}/bin/sing-box-server" check -c "${TMP_DIR}/server-${mode}.json"
    "${TMP_DIR}/bin/sing-box-server" run -c "${TMP_DIR}/server-${mode}.json" \
      > "${TMP_DIR}/server-${mode}.log" 2>&1 &
    server_pid=$!

    jq -n --argjson outbound "${outbound_json}" --argjson port "${client_port}" \
      '{log:{level:"warn"},inbounds:[{type:"mixed",tag:"local",listen:"127.0.0.1",listen_port:$port}],outbounds:[$outbound,{type:"direct",tag:"direct"}],route:{final:$outbound.tag}}' \
      > "${TMP_DIR}/client-${mode}.json"
    "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/client-${mode}.json"
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/client-${mode}.json" \
      > "${TMP_DIR}/client-${mode}.log" 2>&1 &
    client_pid=$!

    local tcp_ok=n
    for _ in {1..100}; do
      if curl --silent --show-error --fail --max-time 2 --noproxy '' \
        --proxy "socks5h://127.0.0.1:${client_port}" \
        "http://127.0.0.1:${marker_tcp}/" > "${TMP_DIR}/tcp-${mode}.body" 2> "${TMP_DIR}/tcp-${mode}.stderr"; then
        tcp_ok=y
        break
      fi
      kill -0 "${server_pid}" && kill -0 "${client_pid}"
      sleep 0.05
    done
    [[ "${tcp_ok}" == y ]]
    grep -Fqx 'mixed-export-tcp-ok' "${TMP_DIR}/tcp-${mode}.body"
    python3 "${TMP_DIR}/udp-probe.py" "${client_port}" "${marker_udp}" \
      > "${TMP_DIR}/udp-${mode}.body"
    grep -Fqx 'mixed-export-udp-ok' "${TMP_DIR}/udp-${mode}.body"

    if [[ "${mode}" == auth ]]; then
      # The negative probe targets the authenticated Mixed server directly;
      # the exported outbound is intentionally retained byte-for-byte in the
      # reduced client config above.
      if curl --silent --show-error --fail --max-time 2 --noproxy '' \
        --proxy "socks5h://127.0.0.1:${server_port}" --proxy-user wrong:wrong \
        "http://127.0.0.1:${marker_tcp}/" > "${TMP_DIR}/wrong-auth.body" 2> "${TMP_DIR}/wrong-auth.stderr"; then
        printf 'mixed export server accepted incorrect SOCKS credentials\n' >&2
        return 1
      fi
    fi

    kill "${client_pid}" "${server_pid}"
    if wait "${client_pid}" 2>/dev/null; then :; else :; fi
    if wait "${server_pid}" 2>/dev/null; then :; else :; fi
    client_pid=''
    server_pid=''
  done

  printf 'mixed export runtime passed: client=%s server=%s (full-export-check=2, reduced-core-check=4, tcp=2, udp=2, server-wrong-auth=1)\n' \
    "${version_label}" "${server_version_label}"
}

if [[ "${1:-}" == --run-version ]]; then
  [[ "$("$2" version | sed -n 's/^sing-box version //p')" == "$3" ]]
  [[ "$("${4:-$2}" version | sed -n 's/^sing-box version //p')" == "${5:-$3}" ]]
  source "${TESTS_DIR}/menu_test_helper.sh"
  setup_menu_test_env 120
  cp -p "$2" "${TMP_DIR}/bin/sing-box"
  cp -p "${4:-$2}" "${TMP_DIR}/bin/sing-box-server"
  chmod +x "${TMP_DIR}/bin/sing-box-server"
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  marker_pid=''
  server_pid=''
  client_pid=''
  cleanup_runtime() {
    local pid wait_rc
    for pid in "${client_pid}" "${server_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        if kill "${pid}"; then :; else
          printf 'failed to stop owned Mixed runtime process %s\n' "${pid}" >&2
        fi
      fi
      if wait "${pid}" 2>/dev/null; then
        :
      else
        wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned Mixed runtime process %s exited with status %s\n' "${pid}" "${wait_rc}" >&2
      fi
    done
    rm -rf "${TMP_DIR}"
  }
  trap cleanup_runtime EXIT
  run_version "$2" "$3" "${4:-$2}" "${5:-$3}"
  exit 0
fi

if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
  printf 'SKIP mixed export runtime: SINGBOX_BINARY_113/SINGBOX_BINARY_114 are unavailable\n'
  exit 0
fi

for configured_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${configured_binary}" && ! -x "${configured_binary}" ]]; then
    printf 'configured Mixed runtime core is not executable\n' >&2
    exit 1
  fi
done

if [[ -n "${SINGBOX_BINARY_113:-}" && -x "${SINGBOX_BINARY_113}" ]]; then
  bash "${BASH_SOURCE[0]}" --run-version "${SINGBOX_BINARY_113}" 1.13.18
else
  printf 'SKIP mixed export runtime: SINGBOX_BINARY_113 is unavailable\n'
fi
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  core_114_label=$("${SINGBOX_BINARY_114}" version | sed -n 's/^sing-box version //p' | head -n 1)
  [[ "${core_114_label}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'configured 1.14.x core reported an invalid version\n' >&2
    exit 1
  }
  bash "${BASH_SOURCE[0]}" --run-version "${SINGBOX_BINARY_114}" "${core_114_label}"
else
  printf 'SKIP mixed export runtime: SINGBOX_BINARY_114 is unavailable\n'
fi
if [[ -n "${SINGBOX_BINARY_113:-}" && -x "${SINGBOX_BINARY_113}" &&
      -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  core_113_label=$("${SINGBOX_BINARY_113}" version | sed -n 's/^sing-box version //p' | head -n 1)
  [[ "${core_113_label}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'configured 1.13.x core reported an invalid version\n' >&2
    exit 1
  }
  bash "${BASH_SOURCE[0]}" --run-version "${SINGBOX_BINARY_113}" 1.13.18 \
    "${SINGBOX_BINARY_114}" "${core_114_label}"
  bash "${BASH_SOURCE[0]}" --run-version "${SINGBOX_BINARY_114}" "${core_114_label}" \
    "${SINGBOX_BINARY_113}" 1.13.18
fi
