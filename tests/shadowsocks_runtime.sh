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
  cp -p "${core_binary}" "${TMP_DIR}/bin/sing-box"
  # Source at top level so the registry and adapters execute under the
  # selected shell, including the Bash 4.2 compatibility run.
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  export SINGBOX_CONFIG_FILE
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"

  server_pid=''
  client_pid=''
  marker_pid=''
  cleanup() {
    local rc=$? pid wait_rc
    if (( rc != 0 )); then
      [[ ! -f "${TMP_DIR}/server.log" ]] || tail -100 "${TMP_DIR}/server.log" >&2
      [[ ! -f "${TMP_DIR}/client.log" ]] || tail -100 "${TMP_DIR}/client.log" >&2
    fi
    for pid in "${client_pid}" "${server_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        if kill "${pid}"; then :; else
          printf 'failed to stop owned Shadowsocks runtime process %s\n' "${pid}" >&2
        fi
      fi
      if wait "${pid}" 2>/dev/null; then :; else
        wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned Shadowsocks runtime process %s exited with status %s\n' "${pid}" "${wait_rc}" >&2
      fi
    done
    rm -rf -- "${TMP_DIR}"
    return "${rc}"
  }
  trap cleanup EXIT

  cat >"${TMP_DIR}/marker.py" <<'PY_MARKER'
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
print(json.dumps({"tcp": tcp.getsockname()[1], "udp": udp.getsockname()[1]}), flush=True)

def handle(connection):
    try:
        connection.settimeout(3)
        connection.recv(65536)
        body = b"shadowsocks-runtime-tcp-ok\n"
        connection.sendall(
            b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n" + body
        )
    finally:
        connection.close()

while True:
    ready, _, _ = select.select([tcp, udp], [], [], 1)
    for sock in ready:
        if sock is tcp:
            connection, _ = tcp.accept()
            threading.Thread(target=handle, args=(connection,), daemon=True).start()
        else:
            payload, address = udp.recvfrom(65536)
            udp.sendto(payload, address)
PY_MARKER
  cat >"${TMP_DIR}/udp_probe.py" <<'PY_UDP'
import socket
import sys

proxy_port = int(sys.argv[1])
marker_port = int(sys.argv[2])
want = b"shadowsocks-runtime-udp-ok"

def read_exact(sock, amount):
    value = b""
    while len(value) < amount:
        part = sock.recv(amount - len(value))
        if not part:
            raise SystemExit("SOCKS control connection closed")
        value += part
    return value

control = socket.create_connection(("127.0.0.1", proxy_port), 4)
control.sendall(b"\x05\x02\x00\x02")
greeting = read_exact(control, 2)
if greeting[0] != 5:
    raise SystemExit("SOCKS greeting failed")
if greeting[1] == 2:
    raise SystemExit("unexpected client authentication requirement")
if greeting[1] != 0:
    raise SystemExit("SOCKS no-auth method unavailable")
control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
reply = read_exact(control, 4)
if reply[:2] != b"\x05\x00":
    raise SystemExit("UDP associate failed")
if reply[3] == 1:
    read_exact(control, 4)
elif reply[3] == 3:
    read_exact(control, read_exact(control, 1)[0])
elif reply[3] == 4:
    read_exact(control, 16)
else:
    raise SystemExit("UDP associate address type failed")
relay_port = int.from_bytes(read_exact(control, 2), "big")
datagram = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
datagram.settimeout(5)
datagram.sendto(
    b"\x00\x00\x00\x01\x7f\x00\x00\x01" + marker_port.to_bytes(2, "big") + want,
    ("127.0.0.1", relay_port),
)
response, _ = datagram.recvfrom(65536)
if response[:4] != b"\x00\x00\x00\x01" or response[10:] != want:
    raise SystemExit("UDP marker payload mismatch")
print(want.decode(), end="")
control.close()
datagram.close()
PY_UDP

  python3 -u "${TMP_DIR}/marker.py" >"${TMP_DIR}/marker.ports" 2>"${TMP_DIR}/marker.stderr" &
  marker_pid=$!
  for _ in {1..100}; do
    [[ -s "${TMP_DIR}/marker.ports" ]] && break
    if ! kill -0 "${marker_pid}" 2>/dev/null; then
      printf 'Shadowsocks marker exited before publishing ports\n' >&2
      exit 1
    fi
    sleep 0.02
  done
  jq -e '.tcp > 0 and .udp > 0' "${TMP_DIR}/marker.ports" >/dev/null
  marker_tcp=$(jq -r '.tcp' "${TMP_DIR}/marker.ports")
  marker_udp=$(jq -r '.udp' "${TMP_DIR}/marker.ports")

  ports=$(python3 - <<'PY_PORTS'
import json
import socket

ports = []
for _ in range(6):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    ports.append(sock.getsockname()[1])
    sock.close()
print(json.dumps(ports))
PY_PORTS
)
  classic_single_port=$(jq -r '.[0]' <<<"${ports}")
  aes_single_port=$(jq -r '.[1]' <<<"${ports}")
  classic_multi_port=$(jq -r '.[2]' <<<"${ports}")
  aes_multi_port=$(jq -r '.[3]' <<<"${ports}")
  network_shared_port=$(jq -r '.[4]' <<<"${ports}")
  client_port=$(jq -r '.[5]' <<<"${ports}")

  classic_single_password='classic-single-password'
  classic_alice_password='classic-alice-password'
  classic_bob_password='classic-bob-password'
  aes128_server_key='AAAAAAAAAAAAAAAAAAAAAA=='
  aes128_user_key='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
  aes256_server_key='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
  aes256_alice_key='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
  aes256_bob_key='AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI='

  printf '%s\n' 'INSTALLED_PROTOCOLS=shadowsocks' 'PROTOCOL_STATE_VERSION=1' >"${SB_PROTOCOL_INDEX_FILE}"
  cat >"${SB_PROTOCOL_STATE_DIR}/shadowsocks.env" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE

  jq -n \
    --arg classic_single_password "${classic_single_password}" \
    --arg classic_alice_password "${classic_alice_password}" \
    --arg classic_bob_password "${classic_bob_password}" \
    --arg aes128_server_key "${aes128_server_key}" \
    --arg aes128_user_key "${aes128_user_key}" \
    --arg aes256_server_key "${aes256_server_key}" \
    --arg aes256_alice_key "${aes256_alice_key}" \
    --arg aes256_bob_key "${aes256_bob_key}" \
    --argjson classic_single_port "${classic_single_port}" \
    --argjson aes_single_port "${aes_single_port}" \
    --argjson classic_multi_port "${classic_multi_port}" \
    --argjson aes_multi_port "${aes_multi_port}" \
    --argjson network_shared_port "${network_shared_port}" \
    '{
      schema_version:1,
      protocol:"shadowsocks",
      revision:1,
      default_instance_id:"classic-single",
      instances:[
        {id:"classic-single",name:"Classic single",tag:"ss-classic-single",
          listen:{address:"127.0.0.1",port:$classic_single_port,network:["tcp","udp"]},
          authentication:{method:"aes-256-gcm",password:$classic_single_password,users:[]},
          outbound_policy:"default",dependencies:[]},
        {id:"aes-single",name:"2022 AES single",tag:"ss-aes-single",
          listen:{address:"127.0.0.1",port:$aes_single_port,network:["tcp","udp"]},
          authentication:{method:"2022-blake3-aes-128-gcm",password:$aes128_server_key,users:[]},
          outbound_policy:"default",dependencies:[]},
        {id:"classic-multi",name:"Classic multi",tag:"ss-classic-multi",
          listen:{address:"127.0.0.1",port:$classic_multi_port,network:["tcp","udp"]},
          authentication:{method:"chacha20-ietf-poly1305",password:"",users:[
            {name:"alice",password:$classic_alice_password},
            {name:"bob",password:$classic_bob_password}]},
          outbound_policy:"default",dependencies:[]},
        {id:"aes-multi",name:"2022 AES multi",tag:"ss-aes-multi",
          listen:{address:"127.0.0.1",port:$aes_multi_port,network:["tcp","udp"]},
          authentication:{method:"2022-blake3-aes-128-gcm",password:$aes128_server_key,users:[
            {name:"alice",password:$aes128_user_key},
            {name:"bob",password:$aes256_bob_key}]},
          outbound_policy:"default",dependencies:[]},
        {id:"tcp-only",name:"TCP only",tag:"ss-tcp-only",
          listen:{address:"127.0.0.1",port:$network_shared_port,network:["tcp"]},
          authentication:{method:"aes-128-gcm",password:"tcp-only-password",users:[]},
          outbound_policy:"default",dependencies:[]},
        {id:"udp-only",name:"UDP only",tag:"ss-udp-only",
          listen:{address:"127.0.0.1",port:$network_shared_port,network:["udp"]},
          authentication:{method:"aes-128-gcm",password:"udp-only-password",users:[]},
          outbound_policy:"default",dependencies:[]}
      ]
    }' >"${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
  chmod 600 "${SB_PROTOCOL_STATE_DIR}/shadowsocks.env" "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
  store_file="${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"

  validate_structured_instance_store shadowsocks "${store_file}"
  plain_proxy_structured_state_active shadowsocks

  rendered_inbounds=$(render_structured_instance_inbounds shadowsocks "${store_file}" | jq -s .)
  jq -e '
    length == 6 and
    all(.[]; .type == "shadowsocks" and (.listen_port | type) == "number") and
    any(.[]; .tag == "ss-tcp-only" and .network == ["tcp"]) and
    any(.[]; .tag == "ss-udp-only" and .network == ["udp"])
  ' <<<"${rendered_inbounds}" >/dev/null
  jq -n --argjson inbounds "${rendered_inbounds}" \
    '{log:{level:"info"},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
    >"${TMP_DIR}/server.json"

  stop_server() {
    if [[ -n "${server_pid}" ]]; then
      if kill -0 "${server_pid}" 2>/dev/null; then
        if kill "${server_pid}"; then :; else
          printf 'failed to stop owned Shadowsocks server process %s\n' "${server_pid}" >&2
        fi
      fi
      if wait "${server_pid}" 2>/dev/null; then :; else
        local wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned Shadowsocks server process %s exited with status %s\n' "${server_pid}" "${wait_rc}" >&2
      fi
      server_pid=''
    fi
  }

  start_server() {
    if ! "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/server.json" >"${TMP_DIR}/server-check.log" 2>&1; then
      cat "${TMP_DIR}/server-check.log" >&2
      return 1
    fi
    : >"${TMP_DIR}/server.log"
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/server.json" >"${TMP_DIR}/server.log" 2>&1 &
    server_pid=$!
    for _ in {1..200}; do
      if ! kill -0 "${server_pid}" 2>/dev/null; then
        tail -100 "${TMP_DIR}/server.log" >&2
        return 1
      fi
      if grep -Fq 'sing-box started' "${TMP_DIR}/server.log"; then
        return 0
      fi
      sleep 0.02
    done
    tail -100 "${TMP_DIR}/server.log" >&2
    return 1
  }

  stop_client() {
    if [[ -n "${client_pid}" ]]; then
      if kill -0 "${client_pid}" 2>/dev/null; then
        if kill "${client_pid}"; then :; else
          printf 'failed to stop owned Shadowsocks client process %s\n' "${client_pid}" >&2
        fi
      fi
      if wait "${client_pid}" 2>/dev/null; then :; else
        local wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned Shadowsocks client process %s exited with status %s\n' "${client_pid}" "${wait_rc}" >&2
      fi
      client_pid=''
    fi
  }

  start_client() {
    local outbound=$1 tag
    tag=$(jq -er '.tag | select(type == "string" and length > 0)' <<<"${outbound}") || return 1
    jq -n --argjson outbound "${outbound}" --arg tag "${tag}" --argjson port "${client_port}" \
      '{log:{level:"info"},inbounds:[{type:"mixed",tag:"local",listen:"127.0.0.1",listen_port:$port}],outbounds:[$outbound,{type:"direct",tag:"direct"}],route:{final:$tag}}' \
      >"${TMP_DIR}/client.json" || return 1
    if ! "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/client.json" >"${TMP_DIR}/client-check.log" 2>&1; then
      cat "${TMP_DIR}/client-check.log" >&2
      return 1
    fi
    : >"${TMP_DIR}/client.log"
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/client.json" >"${TMP_DIR}/client.log" 2>&1 &
    client_pid=$!
    for _ in {1..200}; do
      if ! kill -0 "${client_pid}" 2>/dev/null; then
        tail -100 "${TMP_DIR}/client.log" >&2
        return 1
      fi
      if grep -Fq 'sing-box started' "${TMP_DIR}/client.log"; then
        return 0
      fi
      sleep 0.02
    done
    tail -100 "${TMP_DIR}/client.log" >&2
    return 1
  }

  probe_tcp() {
    local label=$1
    curl --silent --show-error --fail --max-time 5 --noproxy '' \
      --proxy "socks5h://127.0.0.1:${client_port}" \
      "http://127.0.0.1:${marker_tcp}/" >"${TMP_DIR}/${label}.tcp"
    grep -Fqx 'shadowsocks-runtime-tcp-ok' "${TMP_DIR}/${label}.tcp"
  }

  probe_udp() {
    local label=$1
    python3 "${TMP_DIR}/udp_probe.py" "${client_port}" "${marker_udp}" \
      >"${TMP_DIR}/${label}.udp"
    grep -Fqx 'shadowsocks-runtime-udp-ok' "${TMP_DIR}/${label}.udp"
  }

  store_before_hash=$(sha256sum "${store_file}")
  export_outbounds=$(build_shadowsocks_client_outbounds_from_store "${store_file}" 127.0.0.1)
  [[ "$(sha256sum "${store_file}")" == "${store_before_hash}" ]]
  jq -s -e '
    length == 8 and (map(.tag) | unique | length) == 8 and
    all(.[]; .type == "shadowsocks" and .server == "127.0.0.1" and
      (.server_port | type) == "number" and (.network == ["tcp","udp"] or .network == ["tcp"] or .network == ["udp"]))
  ' <<<"${export_outbounds}" >/dev/null
  export_file="${TMP_DIR}/export.jsonl"
  printf '%s\n' "${export_outbounds}" >"${export_file}"
  jq -e --arg pass "${classic_single_password}" \
    'select(.tag == "shadowsocks-classic-single-single") | .method == "aes-256-gcm" and .password == $pass' \
    "${export_file}" >/dev/null
  jq -e --arg pass "${aes128_server_key}" \
    'select(.tag == "shadowsocks-aes-single-single") | .method == "2022-blake3-aes-128-gcm" and .password == $pass' \
    "${export_file}" >/dev/null
  jq -e --arg pass "${classic_alice_password}" \
    'select(.tag == ("shadowsocks-classic-multi-user-" + ("alice" | @base64))) | .password == $pass' \
    "${export_file}" >/dev/null
  jq -e --arg pass "${classic_bob_password}" \
    'select(.tag == ("shadowsocks-classic-multi-user-" + ("bob" | @base64))) | .password == $pass' \
    "${export_file}" >/dev/null
  derived_aes128_alice_key=$(shadowsocks_client_psk 2022-blake3-aes-128-gcm "${aes128_user_key}")
  derived_aes128_bob_key=$(shadowsocks_client_psk 2022-blake3-aes-128-gcm "${aes256_bob_key}")
  jq -e --arg server "${aes128_server_key}" --arg user "${derived_aes128_alice_key}" \
    'select(.tag == ("shadowsocks-aes-multi-user-" + ("alice" | @base64))) | .password == ($server + ":" + $user)' \
    "${export_file}" >/dev/null
  jq -e --arg server "${aes128_server_key}" --arg user "${derived_aes128_bob_key}" \
    'select(.tag == ("shadowsocks-aes-multi-user-" + ("bob" | @base64))) | .password == ($server + ":" + $user)' \
    "${export_file}" >/dev/null
  if grep -Fq "${aes128_user_key}" "${export_file}" || grep -Fq "${aes256_bob_key}" "${export_file}"; then
    printf 'Shadowsocks export retained an overlong raw user PSK\n' >&2
    exit 1
  fi

  # A real core check for each accepted method guards the complete renderer
  # contract. The live business probes below deliberately use only the four
  # requested single/multi cipher families plus transport-specific instances.
  method_check_count=0
  for method in \
    aes-128-gcm aes-192-gcm aes-256-gcm chacha20-ietf-poly1305 xchacha20-ietf-poly1305 \
    2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305 none; do
    method_password='classic-method-password'
    method_users='[]'
    if [[ "${method}" == 2022-blake3-aes-128-gcm ]]; then
      method_password=${aes128_server_key}
    elif [[ "${method}" == 2022-blake3-aes-256-gcm || "${method}" == 2022-blake3-chacha20-poly1305 ]]; then
      method_password=${aes256_server_key}
    elif [[ "${method}" == none ]]; then
      method_password=''
    fi
    jq --arg method "${method}" --arg password "${method_password}" \
      '.instances = [{id:"method",name:"method",tag:"ss-method",listen:{address:"127.0.0.1",port:1,network:["tcp"]},authentication:{method:$method,password:$password,users:[]},outbound_policy:"default",dependencies:[]}] | .default_instance_id="method"' \
      "${store_file}" >"${TMP_DIR}/method-store.json"
    validate_structured_instance_store shadowsocks "${TMP_DIR}/method-store.json"
    method_inbound=$(render_structured_instance_inbounds shadowsocks "${TMP_DIR}/method-store.json" | jq -s .)
    jq -n --argjson inbounds "${method_inbound}" \
      '{log:{level:"warn"},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
      >"${TMP_DIR}/method-config.json"
    "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/method-config.json" >"${TMP_DIR}/method-check.log" 2>&1
    method_check_count=$((method_check_count + 1))
  done

  start_server
  tcp_business=0
  udp_business=0
  auth_users=0
  network_cases=0

  run_tcp_udp_case() {
    local label=$1 user_tag=$2 outbound
    outbound=$(jq -ce --arg tag "${user_tag}" 'select(.tag == $tag)' "${export_file}")
    start_client "${outbound}"
    probe_tcp "${label}"
    tcp_business=$((tcp_business + 1))
    stop_client
    start_client "${outbound}"
    probe_udp "${label}"
    udp_business=$((udp_business + 1))
    stop_client
  }

  run_tcp_udp_case classic-single 'shadowsocks-classic-single-single'
  auth_users=$((auth_users + 1))
  run_tcp_udp_case aes-single 'shadowsocks-aes-single-single'
  auth_users=$((auth_users + 1))
  run_tcp_udp_case classic-alice "$(jq -r '"shadowsocks-classic-multi-user-" + ("alice" | @base64)' <<< '{}')"
  auth_users=$((auth_users + 1))
  run_tcp_udp_case classic-bob "$(jq -r '"shadowsocks-classic-multi-user-" + ("bob" | @base64)' <<< '{}')"
  auth_users=$((auth_users + 1))
  run_tcp_udp_case aes-alice "$(jq -r '"shadowsocks-aes-multi-user-" + ("alice" | @base64)' <<< '{}')"
  auth_users=$((auth_users + 1))
  run_tcp_udp_case aes-bob "$(jq -r '"shadowsocks-aes-multi-user-" + ("bob" | @base64)' <<< '{}')"
  auth_users=$((auth_users + 1))

  tcp_only=$(jq -ce 'select(.tag == "shadowsocks-tcp-only-single")' "${export_file}")
  start_client "${tcp_only}"
  probe_tcp tcp-only
  tcp_business=$((tcp_business + 1))
  stop_client
  network_cases=$((network_cases + 1))

  udp_only=$(jq -ce 'select(.tag == "shadowsocks-udp-only-single")' "${export_file}")
  start_client "${udp_only}"
  probe_udp udp-only
  udp_business=$((udp_business + 1))
  stop_client
  network_cases=$((network_cases + 1))

  # Authentication negatives are meaningful only after a valid client has
  # passed sing-box check and completed startup.
  wrong_auth=$(jq -ce 'select(.tag == "shadowsocks-classic-single-single") | .password = "wrong-password"' "${export_file}")
  start_client "${wrong_auth}"
  if probe_tcp wrong-auth; then
    printf 'wrong Shadowsocks credentials unexpectedly reached the marker\n' >&2
    exit 1
  fi
  stop_client

  stop_server
  for runtime_secret in \
    "${classic_single_password}" "${classic_alice_password}" "${classic_bob_password}" \
    "${aes128_server_key}" "${aes256_server_key}" "${aes256_alice_key}" \
    "${aes256_bob_key}" wrong-password; do
    if grep -Fq "${runtime_secret}" "${TMP_DIR}/server.log" "${TMP_DIR}/client.log"; then
      printf 'Shadowsocks runtime logs leaked a credential\n' >&2
      exit 1
    fi
  done

  printf 'Shadowsocks runtime passed: core=%s (method-checks=%s, exported=%s, auth-users=%s, tcp-business=%s, udp-business=%s, network-cases=%s, wrong-auth=1)\n' \
    "${core_label}" "${method_check_count}" "$(jq -s length "${export_file}")" \
    "${auth_users}" "${tcp_business}" "${udp_business}" "${network_cases}"
else
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'SKIP Shadowsocks runtime: real cores unavailable\n'
    exit 0
  fi
  if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then
    [[ -x "${SINGBOX_BINARY_113}" ]] || { printf 'configured 1.13.18 core unavailable\n' >&2; exit 1; }
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
    [[ -x "${SINGBOX_BINARY_114}" ]] || { printf 'configured 1.14.0 core unavailable\n' >&2; exit 1; }
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0
  fi
fi
