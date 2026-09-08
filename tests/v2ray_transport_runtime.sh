#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTS_DIR="${REPO_ROOT}/tests"

if [[ "${1:-}" == --run || "${1:-}" == --diagnose-httpupgrade ]]; then
  if [[ $# -ne 3 || ! -x "$2" ]]; then
    printf 'usage: %s --run|--diagnose-httpupgrade CORE_BINARY CORE_LABEL\n' "${BASH_SOURCE[0]}" >&2
    exit 2
  fi

  core_binary=$2
  core_label=$3
  actual_core_version=$("${core_binary}" version | awk 'NR == 1 {print $3}')
  [[ "${actual_core_version}" == "${core_label#v}" ]] || {
    printf 'V2Ray transport runtime core version does not match its label\n' >&2
    exit 1
  }
  printf 'V2Ray transport runtime shell: Bash %s; core=%s\n' "${BASH_VERSION}" "${actual_core_version}"
  diagnostic_only=0
  [[ "$1" != --diagnose-httpupgrade ]] || diagnostic_only=1
  source "${TESTS_DIR}/menu_test_helper.sh"
  setup_menu_test_env 120
  cp -p "${core_binary}" "${TMP_DIR}/bin/sing-box"
  # Source at top level so the transport helper is exercised by the selected
  # shell, including the Bash 4.2 compatibility run.
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  export SINGBOX_CONFIG_FILE
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"

  server_pid=''
  client_pid=''
  marker_pid=''
  cleanup() {
    local rc=$? pid wait_rc failure_dir diagnostic
    if (( rc != 0 )); then
      [[ ! -f "${TMP_DIR}/server.log" ]] || tail -120 "${TMP_DIR}/server.log" >&2
      [[ ! -f "${TMP_DIR}/client.log" ]] || tail -120 "${TMP_DIR}/client.log" >&2
    fi
    for pid in "${client_pid}" "${server_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        if kill "${pid}"; then :; else
          printf 'failed to stop owned V2Ray transport process %s\n' "${pid}" >&2
        fi
      fi
      if wait "${pid}" 2>/dev/null; then :; else
        wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned V2Ray transport process %s exited with status %s\n' "${pid}" "${wait_rc}" >&2
      fi
    done
    if (( rc != 0 )); then
      failure_dir=$(mktemp -d "${TMPDIR:-/tmp}/sbv-v2ray-transport-failure.XXXXXX")
      chmod 700 "${failure_dir}"
      for diagnostic in server.log client.log server-check.log client-check.log marker.stderr \
        openssl.stderr rejected-profile.stderr server.json client.json cases; do
        [[ -f "${TMP_DIR}/${diagnostic}" ]] || continue
        cp -p -- "${TMP_DIR}/${diagnostic}" "${failure_dir}/${diagnostic}"
        chmod 600 "${failure_dir}/${diagnostic}"
      done
      printf 'V2Ray transport runtime diagnostics preserved at %s (private mode)\n' "${failure_dir}" >&2
    fi
    rm -rf -- "${TMP_DIR}"
    return "${rc}"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  cat >"${TMP_DIR}/marker.py" <<'PY_MARKER'
import select
import socket
import threading

tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind(("127.0.0.1", 0))
tcp.listen(32)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
udp.bind(("127.0.0.1", 0))
print("%d %d" % (tcp.getsockname()[1], udp.getsockname()[1]), flush=True)

def handle(connection):
    try:
        connection.settimeout(5)
        connection.recv(65536)
        body = b"v2ray-transport-runtime-tcp-ok\n"
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

  cat >"${TMP_DIR}/udp_probe.py" <<'PY_UDP_PROBE'
import socket
import sys

proxy_port = int(sys.argv[1])
marker_port = int(sys.argv[2])
want = b"v2ray-transport-runtime-udp-ok"

def read_exact(sock, amount):
    value = b""
    while len(value) < amount:
        part = sock.recv(amount - len(value))
        if not part:
            raise SystemExit("SOCKS control connection closed")
        value += part
    return value

control = socket.create_connection(("127.0.0.1", proxy_port), 5)
control.sendall(b"\x05\x01\x00")
greeting = read_exact(control, 2)
if greeting != b"\x05\x00":
    raise SystemExit("SOCKS no-auth greeting failed")
control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
reply = read_exact(control, 4)
if reply[:2] != b"\x05\x00":
    raise SystemExit("SOCKS UDP associate failed")
if reply[3] == 1:
    read_exact(control, 4)
elif reply[3] == 3:
    read_exact(control, read_exact(control, 1)[0])
elif reply[3] == 4:
    read_exact(control, 16)
else:
    raise SystemExit("SOCKS UDP associate address type failed")
relay_port = int.from_bytes(read_exact(control, 2), "big")
datagram = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
datagram.settimeout(8)
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
PY_UDP_PROBE

  python3 -u "${TMP_DIR}/marker.py" >"${TMP_DIR}/marker.ports" 2>"${TMP_DIR}/marker.stderr" &
  marker_pid=$!
  for _ in {1..200}; do
    [[ -s "${TMP_DIR}/marker.ports" ]] && break
    if ! kill -0 "${marker_pid}" 2>/dev/null; then
      printf 'V2Ray transport marker exited before publishing ports\n' >&2
      exit 1
    fi
    sleep 0.02
  done
  read -r marker_tcp marker_udp <"${TMP_DIR}/marker.ports"
  [[ "${marker_tcp}" =~ ^[0-9]+$ && "${marker_tcp}" -gt 0 ]]
  [[ "${marker_udp}" =~ ^[0-9]+$ && "${marker_udp}" -gt 0 ]]

  make_ports=$(python3 - <<'PY_PORTS'
import socket

ports = []
sockets = []
for attempt in range(200):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        udp_sock.bind(("127.0.0.1", port))
    except OSError:
        sock.close()
        udp_sock.close()
        continue
    ports.append(port)
    sockets.extend([sock, udp_sock])
    if len(ports) == 40:
        break
if len(ports) != 40:
    raise SystemExit("unable to reserve TCP/UDP fixture ports")
print(" ".join(str(port) for port in ports))
# Keep all reservations until the complete set is allocated. This prevents
# the kernel from reusing an earlier ephemeral port in the same fixture.
for sock in sockets:
    sock.close()
PY_PORTS
)
  read -r -a ports <<<"${make_ports}"
  client_port=${ports[39]}

  # Keep the trust root private to this run. The outbound uses the CA path and
  # the default strict verifier; insecure TLS is intentionally never used.
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=V2Ray transport test CA' \
    -keyout "${TMP_DIR}/ca.key" -out "${TMP_DIR}/ca.crt" \
    >/dev/null 2>"${TMP_DIR}/openssl.stderr"
  openssl req -newkey rsa:2048 -nodes -subj '/CN=proxy.local' \
    -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.csr" \
    >/dev/null 2>>"${TMP_DIR}/openssl.stderr"
  printf '%s\n' 'subjectAltName=DNS:proxy.local' >"${TMP_DIR}/server.ext"
  openssl x509 -req -in "${TMP_DIR}/server.csr" \
    -CA "${TMP_DIR}/ca.crt" -CAkey "${TMP_DIR}/ca.key" -CAcreateserial \
    -days 1 -out "${TMP_DIR}/server.crt" -extfile "${TMP_DIR}/server.ext" \
    >/dev/null 2>>"${TMP_DIR}/openssl.stderr"
  chmod 600 "${TMP_DIR}/ca.key" "${TMP_DIR}/server.key" "${TMP_DIR}/ca.crt" "${TMP_DIR}/server.crt"

  uuid='11111111-1111-4111-8111-111111111111'
  trojan_password='v2ray-trojan-runtime-password'
  transport_http='{"type":"http","host":["proxy.local"],"path":"/v2ray"}'
  transport_ws='{"type":"ws","path":"/ws","headers":{"Host":"proxy.local","X-Test-Transport":"v2ray"},"max_early_data":0}'
  transport_ws_early='{"type":"ws","path":"/ws path/测试","headers":{"Host":"proxy.local","X-Test-Transport":"v2ray"},"max_early_data":1024,"early_data_header_name":"Sec-WebSocket-Protocol"}'
  transport_grpc='{"type":"grpc","service_name":"v2ray_runtime"}'
  transport_httpupgrade='{"type":"httpupgrade","host":"proxy.local","path":"/upgrade"}'
  transport_quic='{"type":"quic"}'
  transport_none='{"type":"none"}'

  assert_profile() {
    local family=$1 transport_name=$2 transport=$3 tls_mode=$4 flow=$5 expected_network=$6 expected_alpn=$7 expected_tags=$8 profile
    profile=$(inspect_v2ray_transport_profile_json "${family}" "${transport}" "${tls_mode}" "${flow}" "${core_label}")
    jq -e --arg type "${transport_name}" --arg network "${expected_network}" \
      --argjson expected_transport "${transport}" \
      --argjson expected_alpn "${expected_alpn}" --argjson expected_tags "${expected_tags}" \
      '(.listen_networks == [$network]) and (.tls_alpn == $expected_alpn) and
       (.required_build_tags == $expected_tags) and
       (.runtime_guard.status == (if $type == "httpupgrade" then "blocked" else "requires_validation" end)) and
       (if $type == "none" then .transport == null else
          .transport.type == $type and .transport == $expected_transport
        end)' \
      <<<"${profile}" >/dev/null
    if [[ "${transport_name}" == ws ]]; then
      jq -e --arg path '/ws' --argjson headers '{"Host":"proxy.local","X-Test-Transport":"v2ray"}' \
        '.transport.path == $path and .transport.headers == $headers and
         .transport.max_early_data == 0 and (.transport | has("early_data_header_name") | not)' \
        <<<"${profile}" >/dev/null
    fi
  }

  # Exercise the complete typed profile matrix before any runtime process is
  # started. These checks also ensure no transport object is silently changed.
  for family in vmess trojan vless; do
    assert_profile "${family}" none "${transport_none}" tls '' tcp '[]' '[]'
    assert_profile "${family}" http "${transport_http}" tls '' tcp '["h2"]' '[]'
    assert_profile "${family}" ws "${transport_ws}" tls '' tcp '["http/1.1"]' '[]'
    assert_profile "${family}" grpc "${transport_grpc}" tls '' tcp '["h2"]' '[]'
    assert_profile "${family}" httpupgrade "${transport_httpupgrade}" tls '' tcp '["http/1.1"]' '[]'
    assert_profile "${family}" quic "${transport_quic}" tls '' udp '["h3"]' '["with_quic"]'
    assert_profile "${family}" none "${transport_none}" disabled '' tcp '[]' '[]'
    assert_profile "${family}" http "${transport_http}" disabled '' tcp '[]' '[]'
    assert_profile "${family}" ws "${transport_ws}" disabled '' tcp '[]' '[]'
    assert_profile "${family}" grpc "${transport_grpc}" disabled '' tcp '[]' '[]'
    assert_profile "${family}" httpupgrade "${transport_httpupgrade}" disabled '' tcp '[]' '[]'
  done
  assert_profile vless none "${transport_none}" reality xtls-rprx-vision tcp '[]' '[]'

  expect_profile_reject() {
    local description=$1 family=$2 transport=$3 tls_mode=$4 flow=$5
    if build_v2ray_transport_profile_json "${family}" "${transport}" "${tls_mode}" "${flow}" "${core_label}" \
      >"${TMP_DIR}/rejected-profile.json" 2>"${TMP_DIR}/rejected-profile.stderr"; then
      printf 'expected V2Ray transport profile rejection: %s\n' "${description}" >&2
      exit 1
    fi
  }
  expect_profile_reject 'REALITY on non-VLESS' trojan "${transport_none}" reality ''
  expect_profile_reject 'REALITY on transport' vless "${transport_ws}" reality ''
  expect_profile_reject 'Vision on VMess' vmess "${transport_none}" tls xtls-rprx-vision
  expect_profile_reject 'Vision on plaintext VLESS' vless "${transport_none}" disabled xtls-rprx-vision
  expect_profile_reject 'QUIC without TLS' vless "${transport_quic}" disabled ''
  expect_profile_reject 'bad transport field' vless '{"type":"ws","path":"/x","unknown":true}' tls ''
  expect_profile_reject 'WS unsafe raw path without early-data header' vless \
    '{"type":"ws","path":"/space path/测试"}' tls ''
  expect_profile_reject 'HTTP HEAD method' vless '{"type":"http","method":"HEAD"}' tls ''
  expect_profile_reject 'HTTP CONNECT method' vless '{"type":"http","method":"CONNECT"}' tls ''
  # Do not silently replace early data with ordinary WS. Preserve the exact
  # failing profile as an explicitly blocked contract, separate from the six
  # no-early-data WS business cases below.
  for family in vmess trojan vless; do
    for security in tls disabled; do
      expect_profile_reject 'WS early data runtime guard' "${family}" "${transport_ws_early}" "${security}" ''
      profile=$(inspect_v2ray_transport_profile_json "${family}" "${transport_ws_early}" "${security}" '' "${core_label}")
      jq -e --argjson original "${transport_ws_early}" '
        .transport == $original and .runtime_guard.status == "blocked" and
        .runtime_guard.code == "ws_early_data_runtime_unreliable"' <<< "${profile}" >/dev/null
      printf 'BLOCKED transport business case: %s/ws-early-data/%s (ws_early_data_runtime_unreliable)\n' "${family}" "${security}"
    done
  done

  # Build server and client fixtures solely from the profile fields. The
  # profile is the source of both transport placement and ALPN negotiation.
  server_inbounds='[]'
  cases=''
  case_count=0
  blocked_cases=0
  add_case() {
    local family=$1 transport_name=$2 transport=$3 tls_mode=$4 expected_network=$5 profile port tag inbound
    profile=$(inspect_v2ray_transport_profile_json "${family}" "${transport}" "${tls_mode}" '' "${core_label}")
    if [[ "${transport_name}" == httpupgrade ]]; then
      if build_v2ray_transport_profile_json "${family}" "${transport}" "${tls_mode}" '' "${core_label}" \
          > "${TMP_DIR}/blocked-profile" 2> "${TMP_DIR}/blocked-profile.stderr"; then
        printf 'HTTPUpgrade unexpectedly escaped its runtime guard\n' >&2
        return 1
      fi
      [[ ! -s "${TMP_DIR}/blocked-profile" ]]
      if (( diagnostic_only == 0 )); then
        printf 'BLOCKED transport business case: %s/httpupgrade/%s (httpupgrade_runtime_unreliable)\n' "${family}" "${tls_mode}"
        blocked_cases=$((blocked_cases + 1))
        return 0
      fi
    elif (( diagnostic_only != 0 )); then
      return 0
    else
      profile=$(build_v2ray_transport_profile_json "${family}" "${transport}" "${tls_mode}" '' "${core_label}")
    fi
    port=${ports[case_count]}
    tag="v2ray-${family}-${transport_name}-${tls_mode}"
    printf '%s\n' "${profile}" > "${TMP_DIR}/${tag}.profile"
    inbound=$(jq -cn \
      --arg family "${family}" --arg tag "${tag}" --argjson port "${port}" \
      --argjson profile "${profile}" --argjson expected_network "[\"${expected_network}\"]" \
      --arg tls_mode "${tls_mode}" \
      --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/server.key" \
      --arg uuid "${uuid}" --arg trojan_password "${trojan_password}" \
      '(
        if $family == "vmess" then
          {type:"vmess",tag:$tag,listen:"127.0.0.1",listen_port:$port,
           users:[{name:$tag,uuid:$uuid}]}
        elif $family == "trojan" then
          {type:"trojan",tag:$tag,listen:"127.0.0.1",listen_port:$port,
           users:[{name:$tag,password:$trojan_password}]}
        else
          {type:"vless",tag:$tag,listen:"127.0.0.1",listen_port:$port,
           users:[{name:$tag,uuid:$uuid}]}
        end
      )
      | if $profile.transport == null then . else .transport = $profile.transport end
      | if $tls_mode == "tls" then
          .tls={enabled:true,server_name:"proxy.local",certificate_path:$cert,key_path:$key}
          | if ($profile.tls_alpn|length)>0 then .tls.alpn=$profile.tls_alpn else . end
        else . end')
    server_inbounds=$(jq -cn --argjson all "${server_inbounds}" --argjson inbound "${inbound}" '$all + [$inbound]')
    printf '%s\n' "${family}|${transport_name}|${tls_mode}|${expected_network}|${tag}|${port}" >>"${TMP_DIR}/cases"
    case_count=$((case_count + 1))
  }

  for family in vmess trojan vless; do
    add_case "${family}" none "${transport_none}" tls tcp
    add_case "${family}" http "${transport_http}" tls tcp
    add_case "${family}" ws "${transport_ws}" tls tcp
    add_case "${family}" grpc "${transport_grpc}" tls tcp
    add_case "${family}" httpupgrade "${transport_httpupgrade}" tls tcp
    add_case "${family}" quic "${transport_quic}" tls udp
    # Plaintext coverage is intentionally limited to transports accepted by
    # the typed contract; QUIC is required to stay TLS-only.
    add_case "${family}" none "${transport_none}" disabled tcp
    add_case "${family}" http "${transport_http}" disabled tcp
    add_case "${family}" ws "${transport_ws}" disabled tcp
    add_case "${family}" grpc "${transport_grpc}" disabled tcp
    add_case "${family}" httpupgrade "${transport_httpupgrade}" disabled tcp
  done
  if (( diagnostic_only == 0 )); then
    [[ "${case_count}" == 27 && "${blocked_cases}" == 6 ]]
  else
    [[ "${case_count}" == 6 ]]
    printf 'DIAGNOSTIC ONLY: bypassing HTTPUpgrade runtime guard to reproduce upstream connection failures; not managed support\n'
  fi
  jq -n --argjson inbounds "${server_inbounds}" \
      '{log:{level:"info"},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
    >"${TMP_DIR}/server.json"
  chmod 600 "${TMP_DIR}/server.json"

  start_server() {
    "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/server.json" >"${TMP_DIR}/server-check.log" 2>&1 || {
      cat "${TMP_DIR}/server-check.log" >&2
      return 1
    }
    : >"${TMP_DIR}/server.log"
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/server.json" >"${TMP_DIR}/server.log" 2>&1 &
    server_pid=$!
    for _ in {1..300}; do
      if ! kill -0 "${server_pid}" 2>/dev/null; then
        tail -120 "${TMP_DIR}/server.log" >&2
        return 1
      fi
      if grep -Fq 'sing-box started' "${TMP_DIR}/server.log"; then
        return 0
      fi
      sleep 0.02
    done
    tail -120 "${TMP_DIR}/server.log" >&2
    return 1
  }

  stop_server() {
    if [[ -n "${server_pid}" ]]; then
      if kill -0 "${server_pid}" 2>/dev/null; then
        if kill "${server_pid}"; then :; else
          printf 'failed to stop owned V2Ray server process %s\n' "${server_pid}" >&2
        fi
      fi
      if wait "${server_pid}" 2>/dev/null; then :; else
        local wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned V2Ray server exited with status %s\n' "${wait_rc}" >&2
      fi
      server_pid=''
    fi
  }

  stop_client() {
    if [[ -n "${client_pid}" ]]; then
      if kill -0 "${client_pid}" 2>/dev/null; then
        if kill "${client_pid}"; then :; else
          printf 'failed to stop owned V2Ray client process %s\n' "${client_pid}" >&2
        fi
      fi
      if wait "${client_pid}" 2>/dev/null; then :; else
        local wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned V2Ray client exited with status %s\n' "${wait_rc}" >&2
      fi
      client_pid=''
    fi
  }

  start_client() {
    local outbound=$1 tag
    tag=$(jq -er '.tag' <<<"${outbound}")
    jq -n --argjson outbound "${outbound}" --arg tag "${tag}" --argjson port "${client_port}" \
      '{log:{level:"info"},inbounds:[{type:"mixed",tag:"local",listen:"127.0.0.1",listen_port:$port}],
        outbounds:[$outbound,{type:"direct",tag:"direct"}],route:{final:$tag}}' \
      >"${TMP_DIR}/client.json"
    "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/client.json" >"${TMP_DIR}/client-check.log" 2>&1 || {
      cat "${TMP_DIR}/client-check.log" >&2
      return 1
    }
    : >"${TMP_DIR}/client.log"
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/client.json" >"${TMP_DIR}/client.log" 2>&1 &
    client_pid=$!
    for _ in {1..300}; do
      if ! kill -0 "${client_pid}" 2>/dev/null; then
        tail -120 "${TMP_DIR}/client.log" >&2
        return 1
      fi
      if grep -Fq 'sing-box started' "${TMP_DIR}/client.log"; then
        return 0
      fi
      sleep 0.02
    done
    tail -120 "${TMP_DIR}/client.log" >&2
    return 1
  }

  probe_tcp() {
    local label=$1
    curl --silent --show-error --fail --max-time 12 --noproxy '' \
      --proxy "socks5h://127.0.0.1:${client_port}" \
      "http://127.0.0.1:${marker_tcp}/" >"${TMP_DIR}/${label}.tcp"
    grep -Fqx 'v2ray-transport-runtime-tcp-ok' "${TMP_DIR}/${label}.tcp"
  }

  probe_udp() {
    local label=$1
    python3 "${TMP_DIR}/udp_probe.py" "${client_port}" "${marker_udp}" \
      >"${TMP_DIR}/${label}.udp"
    grep -Fqx 'v2ray-transport-runtime-udp-ok' "${TMP_DIR}/${label}.udp"
  }

  start_server
  tls_tcp_cases=0
  tls_udp_cases=0
  plaintext_tcp_cases=0
  tcp_business=0
  udp_business=0
  case_total=0
  first_tls_outbound=''
  while IFS='|' read -r family transport_name tls_mode expected_network tag port; do
    [[ -n "${tag}" ]] || continue
    profile=$(<"${TMP_DIR}/${tag}.profile")
    outbound=$(jq -n \
      --arg family "${family}" --arg tag "${tag}" --arg server "127.0.0.1" \
      --argjson port "${port}" --argjson profile "${profile}" \
      --arg tls_mode "${tls_mode}" --arg ca "${TMP_DIR}/ca.crt" --arg uuid "${uuid}" \
      --arg trojan_password "${trojan_password}" \
      '(
        if $family == "vmess" then
          {type:"vmess",tag:$tag,server:$server,server_port:$port,
           uuid:$uuid,security:"auto"}
        elif $family == "trojan" then
          {type:"trojan",tag:$tag,server:$server,server_port:$port,password:$trojan_password}
        else
          {type:"vless",tag:$tag,server:$server,server_port:$port,uuid:$uuid}
        end
      )
      | if $profile.transport == null then . else .transport=$profile.transport end
      | if $tls_mode == "tls" then
          .tls={enabled:true,server_name:"proxy.local",certificate_path:$ca}
          | if ($profile.tls_alpn|length)>0 then .tls.alpn=$profile.tls_alpn else . end
        else . end')
    # Both roles must consume the same frozen profile, not similar-looking
    # independent fixtures. A mismatch would invalidate any transport finding.
    jq -e --arg tag "${tag}" --argjson outbound "${outbound}" '
      .inbounds[] | select(.tag == $tag) |
      (.transport == $outbound.transport) and (.tls.alpn == $outbound.tls.alpn)
    ' "${TMP_DIR}/server.json" >/dev/null
    if [[ -z "${first_tls_outbound}" && "${family}" == vmess &&
      "${transport_name}" == none && "${tls_mode}" == tls ]]; then
      first_tls_outbound=${outbound}
    fi
    start_client "${outbound}"
    label="${family}-${transport_name}-${tls_mode}"
    probe_tcp "${label}"
    tcp_business=$((tcp_business + 1))
    if [[ "${tls_mode}" == tls ]]; then
      tls_tcp_cases=$((tls_tcp_cases + 1))
    else
      plaintext_tcp_cases=$((plaintext_tcp_cases + 1))
    fi
    probe_udp "${label}"
    udp_business=$((udp_business + 1))
    if [[ "${tls_mode}" == tls ]]; then tls_udp_cases=$((tls_udp_cases + 1)); fi
    stop_client
    case_total=$((case_total + 1))
  done <"${TMP_DIR}/cases"

  if (( diagnostic_only != 0 )); then
    stop_server
    printf 'HTTPUpgrade diagnostic completed without reproducing the intermittent failure in this run; runtime guard remains blocked\n'
    exit 0
  fi

  # A syntactically valid client fixture must still fail on bad credentials.
  # Likewise, strict trust is proven by a wrong SNI certificate mismatch.
  wrong_auth=$(jq -ce '.uuid="22222222-2222-4222-8222-222222222222"' <<<"${first_tls_outbound}")
  start_client "${wrong_auth}"
  if probe_tcp wrong-auth; then
    printf 'V2Ray transport wrong credentials unexpectedly reached the marker\n' >&2
    exit 1
  fi
  stop_client
  wrong_sni=$(jq -ce '.tls.server_name="wrong.proxy.local"' <<<"${first_tls_outbound}")
  start_client "${wrong_sni}"
  if probe_tcp wrong-sni; then
    printf 'V2Ray transport wrong SNI unexpectedly passed strict trust\n' >&2
    exit 1
  fi
  stop_client
  stop_server

  for runtime_secret in "${trojan_password}" "${uuid}"; do
    if grep -Fq "${runtime_secret}" "${TMP_DIR}/server.log" "${TMP_DIR}/client.log"; then
      printf 'V2Ray transport runtime logs leaked a credential\n' >&2
      exit 1
    fi
  done

  printf 'V2Ray transport available-case runtime passed: core=%s (profiles=40, cases=%s, tls-tcp=%s, tls-udp=%s, plaintext-tcp=%s, tcp-business=%s, udp-business=%s, wrong-auth=1, wrong-sni=1, blocked-httpupgrade=6, blocked-ws-early-data=6)\n' \
    "${core_label}" "${case_total}" "${tls_tcp_cases}" "${tls_udp_cases}" \
    "${plaintext_tcp_cases}" "${tcp_business}" "${udp_business}"
else
  if [[ $# -ne 0 ]]; then
    printf 'usage: %s [--run|--diagnose-httpupgrade CORE_BINARY CORE_LABEL]\n' "${BASH_SOURCE[0]}" >&2
    exit 2
  fi
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'SKIP V2Ray transport runtime: real cores unavailable\n'
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
