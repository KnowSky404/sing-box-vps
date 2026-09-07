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
  # shellcheck disable=SC1090
  source "${TESTABLE_INSTALL}"
  export SINGBOX_CONFIG_FILE
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"

  marker_pid=''
  server_pid=''
  cleanup() {
    local rc=$? pid wait_rc
    if (( rc != 0 )) && [[ -f "${TMP_DIR}/server.log" ]]; then
      tail -80 "${TMP_DIR}/server.log" >&2
    fi
    for pid in "${server_pid}" "${marker_pid}"; do
      [[ -n "${pid}" ]] || continue
      if kill -0 "${pid}" 2>/dev/null; then
        if kill "${pid}"; then :; else
          printf 'failed to stop owned plain-proxy process %s\n' "${pid}" >&2
        fi
      fi
      if wait "${pid}" 2>/dev/null; then :; else
        wait_rc=$?
        [[ "${wait_rc}" == 143 || "${wait_rc}" == 130 ]] ||
          printf 'owned plain-proxy process %s exited with status %s\n' "${pid}" "${wait_rc}" >&2
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
        body = b"plain-proxy-share-runtime-ok\n"
        connection.sendall(
            b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n" + body
        )
    finally:
        connection.close()
PY_MARKER

  python3 -u "${TMP_DIR}/marker.py" > "${TMP_DIR}/marker.port" 2> "${TMP_DIR}/marker.stderr" &
  marker_pid=$!
  for _ in {1..100}; do
    [[ -s "${TMP_DIR}/marker.port" ]] && break
    kill -0 "${marker_pid}"
    sleep 0.02
  done
  marker_port=$(<"${TMP_DIR}/marker.port")
  [[ "${marker_port}" =~ ^[0-9]+$ && "${marker_port}" -gt 0 ]]

  printf '%s\n' 'INSTALLED_PROTOCOLS=mixed' 'PROTOCOL_STATE_VERSION=1' > "${SB_PROTOCOL_INDEX_FILE}"
  server_port=$(python3 - <<'PY_PORT'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY_PORT
)

  stop_server() {
    if [[ -n "${server_pid}" ]]; then
      if kill -0 "${server_pid}" 2>/dev/null; then kill "${server_pid}"; fi
      if wait "${server_pid}" 2>/dev/null; then :; else :; fi
      server_pid=''
    fi
  }
  start_server() {
    local inbound
    inbound=$(build_mixed_inbound_json | jq --argjson port "${server_port}" \
      '.listen = "127.0.0.1" | .listen_port = $port')
    jq -n --argjson inbound "${inbound}" \
      '{log:{level:"warn"},inbounds:[$inbound],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
      > "${TMP_DIR}/server.json"
    jq -e '.inbounds[0].type == "mixed" and .inbounds[0].listen == "127.0.0.1"' \
      "${TMP_DIR}/server.json" >/dev/null
    "${SINGBOX_BIN_PATH}" check -c "${TMP_DIR}/server.json"
    "${SINGBOX_BIN_PATH}" run -c "${TMP_DIR}/server.json" > "${TMP_DIR}/server.log" 2>&1 &
    server_pid=$!
    for _ in {1..100}; do
      if kill -0 "${server_pid}" 2>/dev/null && python3 - "${server_port}" <<'PY_READY'
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
      then
        return 0
      fi
      kill -0 "${server_pid}"
      sleep 0.05
    done
    return 1
  }
  probe_uri() {
    local kind=$1 uri=$2
    curl --silent --show-error --fail --max-time 5 --noproxy '' \
      --proxy "${uri}" "http://127.0.0.1:${marker_port}/" > "${TMP_DIR}/${kind}.body"
    grep -Fqx 'plain-proxy-share-runtime-ok' "${TMP_DIR}/${kind}.body"
  }
  expected_encoded() {
    python3 - "$1" <<'PY_ENCODE'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""), end="")
PY_ENCODE
  }

  special_user='mix@/#?% 用户'
  special_password='p:ss@/#?% 密'
  cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<EOF_AUTH
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=share-runtime-${core_label}
PORT=${server_port}
AUTH_ENABLED=y
USERNAME='${special_user}'
PASSWORD='p:ss@/#?% 密'
EOF_AUTH
  load_protocol_state mixed read-only
  start_server
  http_uri=$(build_mixed_http_link 127.0.0.1)
  socks_uri=$(build_mixed_socks5_link 127.0.0.1)
  encoded_user=$(expected_encoded "${special_user}")
  encoded_password=$(expected_encoded "${special_password}")
  [[ "${http_uri}" == "http://${encoded_user}:${encoded_password}@127.0.0.1:${server_port}" ]]
  [[ "${socks_uri}" == "socks5://${encoded_user}:${encoded_password}@127.0.0.1:${server_port}" ]]
  probe_uri http-auth "${http_uri}"
  probe_uri socks-auth "${socks_uri}"
  stop_server

  # A trailing LF cannot be represented safely in the shell-readable .env
  # fixture. Inject it into the loaded fields and let curl determine whether
  # an encoded control character is accepted end to end.
  lf_password=$'p:ss@/#?% 密\n'
  load_protocol_state mixed read-only
  SB_MIXED_PASSWORD="${lf_password}"
  PASSWORD="${lf_password}"
  start_server
  lf_socks_uri=$(build_mixed_socks5_link 127.0.0.1)
  lf_encoded_password=$(expected_encoded "${lf_password}")
  [[ "${lf_socks_uri}" == "socks5://${encoded_user}:${lf_encoded_password}@127.0.0.1:${server_port}" ]]
  trailing_lf=0
  if probe_uri socks-trailing-lf "${lf_socks_uri}"; then
    trailing_lf=1
  else
    printf '[WARN] curl/core rejected optional trailing-LF SOCKS credential; special-character coverage remains valid.\n' >&2
  fi
  stop_server

  cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<EOF_NOAUTH
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=share-runtime-${core_label}-no-auth
PORT=${server_port}
AUTH_ENABLED=n
USERNAME=''
PASSWORD=''
EOF_NOAUTH
  load_protocol_state mixed read-only
  start_server
  http_uri=$(build_mixed_http_link 127.0.0.1)
  socks_uri=$(build_mixed_socks5_link 127.0.0.1)
  [[ "${http_uri}" == "http://127.0.0.1:${server_port}" ]]
  [[ "${socks_uri}" == "socks5://127.0.0.1:${server_port}" ]]
  probe_uri http-no-auth "${http_uri}"
  probe_uri socks-no-auth "${socks_uri}"
  stop_server

  colon_user='colon:user'
  colon_password='colon-password@/#?%'
  cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<EOF_COLON
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=share-runtime-${core_label}-colon
PORT=${server_port}
AUTH_ENABLED=y
USERNAME='${colon_user}'
PASSWORD='${colon_password}'
EOF_COLON
  load_protocol_state mixed read-only
  colon_socks_uri=$(build_mixed_socks5_link 127.0.0.1)
  colon_user_encoded=$(expected_encoded "${colon_user}")
  colon_password_encoded=$(expected_encoded "${colon_password}")
  [[ "${colon_socks_uri}" == "socks5://${colon_user_encoded}:${colon_password_encoded}@127.0.0.1:${server_port}" ]]
  if colon_http_uri=$(build_mixed_http_link 127.0.0.1); then
    printf 'Mixed HTTP builder accepted colon-containing username: %s\n' "${colon_http_uri}" >&2
    exit 1
  fi
  [[ -z "${colon_http_uri:-}" ]]
  start_server
  probe_uri socks-colon-user "${colon_socks_uri}"
  stop_server

  printf 'plain-proxy share runtime passed: core=%s (special-auth-http=1, special-auth-socks=1, trailing-lf=%s, no-auth-http=1, no-auth-socks=1, socks-colon-user=1, http-colon-user-rejected=1)\n' \
    "${core_label}" "${trailing_lf}"
else
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'SKIP plain-proxy share runtime: real cores unavailable\n'
    exit 0
  fi
  if [[ -n "${SINGBOX_BINARY_113:-}" && -x "${SINGBOX_BINARY_113}" ]]; then
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18
  else
    printf 'SKIP plain-proxy share runtime: SINGBOX_BINARY_113 unavailable\n'
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0
  else
    printf 'SKIP plain-proxy share runtime: SINGBOX_BINARY_114 unavailable\n'
  fi
fi
