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
  # Source at file scope so the registry and HTTP adapters retain Bash 4.2
  # semantics; this is intentionally not hidden behind a helper function.
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  export SINGBOX_CONFIG_FILE
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"

  marker_pid=''
  server_pid=''
  client_pid=''
  cleanup() {
    local rc=$? pid wait_rc
    if (( rc != 0 )); then
      [[ ! -f "${TMP_DIR}/server.log" ]] || tail -80 "${TMP_DIR}/server.log" >&2
      [[ ! -f "${TMP_DIR}/client.log" ]] || tail -80 "${TMP_DIR}/client.log" >&2
    fi
    for pid in "${client_pid}" "${server_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        if kill "${pid}"; then :; else
          printf 'failed to stop owned HTTP runtime process %s\n' "${pid}" >&2
        fi
      fi
      if wait "${pid}" 2>/dev/null; then :; else
        wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned HTTP runtime process %s exited with status %s\n' "${pid}" "${wait_rc}" >&2
      fi
    done
    rm -rf -- "${TMP_DIR}"
    return "${rc}"
  }
  trap cleanup EXIT

  cat > "${TMP_DIR}/marker.py" <<'PY_MARKER'
import socket

listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", 0))
listener.listen(16)
print(listener.getsockname()[1], flush=True)
while True:
    connection, _ = listener.accept()
    try:
        connection.settimeout(3)
        connection.recv(65536)
        body = b"http-export-runtime-ok\n"
        connection.sendall(
            b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n" + body
        )
    finally:
        connection.close()
PY_MARKER
  python3 -u "${TMP_DIR}/marker.py" >"${TMP_DIR}/marker.port" 2>"${TMP_DIR}/marker.stderr" &
  marker_pid=$!
  for _ in {1..100}; do
    [[ -s "${TMP_DIR}/marker.port" ]] && break
    kill -0 "${marker_pid}"
    sleep 0.02
  done
  marker_port=$(<"${TMP_DIR}/marker.port")
  [[ "${marker_port}" =~ ^[0-9]+$ && "${marker_port}" -gt 0 ]]

  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=proxy.local' \
    -addext 'subjectAltName=DNS:proxy.local' \
    -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.crt" \
    >/dev/null 2>"${TMP_DIR}/openssl.stderr"
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=wrong.local' \
    -addext 'subjectAltName=DNS:wrong.local' \
    -keyout "${TMP_DIR}/wrong.key" -out "${TMP_DIR}/wrong.crt" \
    >/dev/null 2>>"${TMP_DIR}/openssl.stderr"

  http_port=$(python3 - <<'PY_PORT'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY_PORT
)
  client_port=$(python3 - <<'PY_PORT'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY_PORT
)

  write_http_marker() {
    printf '%s\n' 'INSTALLED_PROTOCOLS=http' 'PROTOCOL_STATE_VERSION=1' >"${SB_PROTOCOL_INDEX_FILE}"
    cat >"${SB_PROTOCOL_STATE_DIR}/http.env" <<'EOF_HTTP_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_HTTP_STATE
  }

  write_http_store() {
    local auth=$1 tls_json=$2 username=${3:-http-user} password=${4:-http-password}
    jq -n \
      --argjson port "${http_port}" --argjson auth "${auth}" \
      --arg username "${username}" --arg password "${password}" \
      --argjson tls "${tls_json}" \
      '{schema_version:1,protocol:"http",revision:1,default_instance_id:"main",instances:[{
        id:"main",name:"HTTP runtime",tag:"http-in",
        listen:{address:"127.0.0.1",port:$port},
        authentication:{enabled:$auth,username:(if $auth then $username else "" end),password:(if $auth then $password else "" end)},
        outbound_policy:"default",tls:$tls,dependencies:[]
      }]}' >"${SB_PROTOCOL_STATE_DIR}/instances/http.json"
    chmod 600 "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
  }

  stop_server() {
    if [[ -n "${server_pid}" ]]; then
      if kill -0 "${server_pid}" 2>/dev/null; then
        if kill "${server_pid}"; then :; else
          printf 'failed to stop owned HTTP server process %s\n' "${server_pid}" >&2
        fi
      fi
      if wait "${server_pid}" 2>/dev/null; then :; else
        local wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned HTTP server process %s exited with status %s\n' "${server_pid}" "${wait_rc}" >&2
      fi
      server_pid=''
    fi
  }

  start_server() {
    local inbound
    if ! inbound=$(build_http_inbound_json | jq --argjson port "${http_port}" \
      '.listen = "127.0.0.1" | .listen_port = $port'); then
      return 1
    fi
    if ! jq -n --argjson inbound "${inbound}" \
      '{log:{level:"warn"},inbounds:[$inbound],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
      >"${TMP_DIR}/server.json"; then
      return 1
    fi
    if ! "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/server.json"; then
      return 1
    fi
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/server.json" >"${TMP_DIR}/server.log" 2>&1 &
    server_pid=$!
    for _ in {1..100}; do
      if kill -0 "${server_pid}" 2>/dev/null && python3 - "${http_port}" <<'PY_READY'
import socket
import sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY_READY
      then return 0; fi
      if ! kill -0 "${server_pid}" 2>/dev/null; then
        stop_server
        return 1
      fi
      sleep 0.05
    done
    stop_server
    return 1
  }

  stop_client() {
    if [[ -n "${client_pid}" ]]; then
      if kill -0 "${client_pid}" 2>/dev/null; then
        if kill "${client_pid}"; then :; else
          printf 'failed to stop owned HTTP client process %s\n' "${client_pid}" >&2
        fi
      fi
      if wait "${client_pid}" 2>/dev/null; then :; else
        local wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned HTTP client process %s exited with status %s\n' "${client_pid}" "${wait_rc}" >&2
      fi
      client_pid=''
    fi
  }

  start_client() {
    local outbound=$1
    if ! jq -n --argjson outbound "${outbound}" --argjson port "${client_port}" \
      '{log:{level:"warn"},inbounds:[{type:"mixed",tag:"local",listen:"127.0.0.1",listen_port:$port}],outbounds:[$outbound,{type:"direct",tag:"direct"}],route:{final:$outbound.tag}}' \
      >"${TMP_DIR}/client.json"; then
      return 1
    fi
    if ! "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/client.json"; then
      return 1
    fi
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/client.json" >"${TMP_DIR}/client.log" 2>&1 &
    client_pid=$!
    for _ in {1..100}; do
      if kill -0 "${client_pid}" 2>/dev/null && python3 - "${client_port}" <<'PY_READY'
import socket
import sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(0.2)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY_READY
      then return 0; fi
      if ! kill -0 "${client_pid}" 2>/dev/null; then
        stop_client
        return 1
      fi
      sleep 0.05
    done
    stop_client
    return 1
  }

  probe_http() {
    local label=$1
    curl --silent --show-error --fail --max-time 5 --noproxy '' \
      --proxy "http://127.0.0.1:${client_port}" \
      "http://127.0.0.1:${marker_port}/" >"${TMP_DIR}/${label}.body"
    grep -Fqx 'http-export-runtime-ok' "${TMP_DIR}/${label}.body"
  }

  http_tls_json='{"enabled":false}'
  write_http_marker
  write_http_store true "${http_tls_json}"
  start_server
  load_plain_proxy_structured_instance http main
  direct_plain_outbound=$(build_client_plain_proxy_outbound http 127.0.0.1 http-direct)
  jq -e '.type == "http" and .tag == "http-direct" and (has("tls") | not)' \
    <<<"${direct_plain_outbound}" >/dev/null
  plaintext_outbound=$(build_client_http_outbounds 127.0.0.1 | jq -s '.[0]')
  jq -e '.type == "http" and .server_port > 0 and .username == "http-user" and .password == "http-password" and (has("tls") | not)' \
    <<<"${plaintext_outbound}" >/dev/null
  start_client "${plaintext_outbound}"
  probe_http authenticated-plaintext
  stop_client
  stop_server

  write_http_store false "${http_tls_json}"
  start_server
  unauth_outbound=$(build_client_outbound_json_for_protocol http 127.0.0.1)
  jq -e '.type == "http" and (has("username") | not) and (has("password") | not)' \
    <<<"${unauth_outbound}" >/dev/null
  start_client "${unauth_outbound}"
  probe_http unauthenticated-plaintext
  stop_client
  stop_server

  write_http_store true "${http_tls_json}"
  start_server
  wrong_auth_outbound=$(jq '.username = "wrong-user" | .password = "wrong-password"' <<<"${plaintext_outbound}")
  start_client "${wrong_auth_outbound}"
  if probe_http wrong-auth; then
    printf 'wrong HTTP credentials unexpectedly reached the marker\n' >&2
    exit 1
  fi
  stop_client
  stop_server

  missing_tls=$(jq -n --arg path "${TMP_DIR}/missing.crt" --arg key "${TMP_DIR}/server.key" \
    '{enabled:true,server_name:"proxy.local",certificate_path:$path,key_path:$key}')
  write_http_store true "${missing_tls}"
  if start_server; then
    printf 'HTTP core accepted a missing server certificate\n' >&2
    exit 1
  fi
  if build_client_outbound_json_for_protocol http 127.0.0.1 >"${TMP_DIR}/missing-client.out" 2>"${TMP_DIR}/missing-client.stderr"; then
    printf 'HTTP export accepted a missing trust certificate\n' >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/missing-client.out" ]]

  mismatched_tls=$(jq -n --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/wrong.key" \
    '{enabled:true,server_name:"proxy.local",certificate_path:$cert,key_path:$key}')
  write_http_store true "${mismatched_tls}"
  if start_server; then
    printf 'HTTP core accepted a mismatched certificate key\n' >&2
    exit 1
  fi

  valid_tls=$(jq -n --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/server.key" \
    '{enabled:true,server_name:"proxy.local",certificate_path:$cert,key_path:$key}')
  write_http_store true "${valid_tls}"
  start_server
  tls_outbound=$(build_client_http_outbounds 127.0.0.1 | jq -s '.[0]')
  jq -e --arg cert "$(<"${TMP_DIR}/server.crt")" \
    --arg key_path "${TMP_DIR}/server.key" \
    '.type == "http" and .tls.enabled == true and .tls.server_name == "proxy.local" and .tls.certificate == $cert and (tostring | contains("PRIVATE KEY") | not) and (tostring | contains($key_path) | not) and (has("key") | not)' \
    <<<"${tls_outbound}" >/dev/null
  start_client "${tls_outbound}"
  probe_http authenticated-tls
  stop_client

  wrong_trust_outbound=$(jq --arg cert "$(<"${TMP_DIR}/wrong.crt")" '.tls.certificate = $cert' <<<"${tls_outbound}")
  start_client "${wrong_trust_outbound}"
  if probe_http wrong-trust; then
    printf 'HTTP TLS client accepted an untrusted certificate\n' >&2
    exit 1
  fi
  stop_client

  wrong_name_outbound=$(jq '.tls.server_name = "wrong.local"' <<<"${tls_outbound}")
  start_client "${wrong_name_outbound}"
  if probe_http wrong-server-name; then
    printf 'HTTP TLS client accepted a mismatched server name\n' >&2
    exit 1
  fi
  stop_client
  stop_server

  printf 'HTTP export runtime passed: core=%s (plaintext-auth=1, plaintext-no-auth=1, wrong-auth=1, missing-cert=1, mismatched-key=1, tls-pinned=1, wrong-trust=1, wrong-server-name=1)\n' \
    "${core_label}"
else
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'SKIP HTTP export runtime: real cores unavailable\n'
    exit 0
  fi
  if [[ -n "${SINGBOX_BINARY_113:-}" && -x "${SINGBOX_BINARY_113}" ]]; then
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18
  else
    printf 'SKIP HTTP export runtime: SINGBOX_BINARY_113 unavailable\n'
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0
  else
    printf 'SKIP HTTP export runtime: SINGBOX_BINARY_114 unavailable\n'
  fi
fi
