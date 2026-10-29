#!/usr/bin/env bash

# Explicit opt-in: run with the repository and a real core mounted read-only
# inside the verification Docker image. No Docker or host changes on default run.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# == 0 ]]; then
  printf 'REALITY target runtime skipped: use --run CORE_BINARY inside a disposable Docker container\n'
  exit 0
fi
if [[ $# != 2 || ${1:-} != --run || ! -x ${2:-} ]]; then
  printf 'usage: %s --run CORE_BINARY\n' "${BASH_SOURCE[0]}" >&2
  exit 2
fi
if [[ ! -f /.dockerenv || ${EUID} != 0 ]]; then
  printf 'REALITY target runtime requires a disposable root Docker container (local TLS fixture uses port 443)\n' >&2
  exit 2
fi
CORE_BINARY=$(readlink -f "${2}")
for dependency in openssl python3 curl jq timeout sha256sum perl; do
  command -v "${dependency}" >/dev/null || {
    printf 'REALITY target runtime dependency unavailable: %s\n' "${dependency}" >&2
    exit 2
  }
done

source "${REPO_ROOT}/tests/menu_test_helper.sh"
setup_menu_test_env 120
cp -p "${CORE_BINARY}" "${TMP_DIR}/bin/sing-box"
source "${TESTABLE_INSTALL}"

COVER_PID=''
SERVER_PID=''
CLIENT_PID=''
MARKER_PID=''
HOSTS_BACKUP="${TMP_DIR}/hosts.original"
cp /etc/hosts "${HOSTS_BACKUP}"
runtime_cleanup() {
  local status=$? pid
  trap - EXIT
  for pid in "${CLIENT_PID}" "${SERVER_PID}" "${COVER_PID}" "${MARKER_PID}"; do
    if [[ -n "${pid}" ]]; then
      if kill -0 "${pid}" 2>/dev/null; then
        kill "${pid}" || status=1
      fi
      if wait "${pid}"; then :; else
        case $? in 0|130|137|143) ;; *) status=1 ;; esac
      fi
    fi
  done
  if (( status != 0 )); then
    local log
    for log in checker.stderr cover.stderr server.stderr client.stderr marker.stderr; do
      if [[ -s "${TMP_DIR}/${log}" ]]; then
        printf '\n%s\n' "${log}:" >&2
        cat "${TMP_DIR}/${log}" >&2
      fi
    done
  fi
  cat "${HOSTS_BACKUP}" > /etc/hosts || status=1
  rm -rf "${TMP_DIR}" || status=1
  exit "${status}"
}
trap runtime_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_port() {
  local port=$1 pid=$2 attempt
  for ((attempt=0; attempt<50; attempt++)); do
    kill -0 "${pid}" 2>/dev/null || return 1
    if python3 - "${port}" <<'PY'
import socket
import sys
try:
    with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.1):
        pass
except OSError:
    raise SystemExit(1)
PY
    then return 0; fi
    sleep 0.1
  done
  printf 'runtime fixture port unavailable: %s\n' "${port}" >&2
  return 1
}

# Only DNS answers are fixtures: OpenSSL, curl, TCP and the checker remain real.
cat > "${TMP_DIR}/bin/dig" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
name=${args[${#args[@]} - 2]%.}
type=${args[${#args[@]} - 1]}
printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1\n'
if [[ "${name}" == reality-runtime.example.test && "${type}" == A ]]; then
  printf '%s. 60 IN A 127.0.0.1\n' "${name}"
fi
SH
chmod +x "${TMP_DIR}/bin/dig"


# Exercise the actual fixed-source download and digest validation before use.
mkdir -m 700 "${TMP_DIR}/checker"
prepare_reality_target_checker "${TMP_DIR}/checker/reality-target-checker.sh"
printf 'checker_download=verified\n'

FIXTURE_DOMAIN='reality-runtime.example.test'
printf '127.0.0.1 %s\n' "${FIXTURE_DOMAIN}" >> /etc/hosts
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout "${TMP_DIR}/cover.key" -out "${TMP_DIR}/cover.crt" \
  -subj "/CN=${FIXTURE_DOMAIN}" -addext "subjectAltName=DNS:${FIXTURE_DOMAIN}" \
  -days 30 > /dev/null 2>"${TMP_DIR}/openssl.stderr"
chmod 600 "${TMP_DIR}/cover.key" "${TMP_DIR}/cover.crt"
cat /etc/ssl/certs/ca-certificates.crt "${TMP_DIR}/cover.crt" > "${TMP_DIR}/trusted-ca.pem"
export SSL_CERT_FILE="${TMP_DIR}/trusted-ca.pem"
export CURL_CA_BUNDLE="${TMP_DIR}/trusted-ca.pem"


python3 - "${TMP_DIR}/cover.crt" "${TMP_DIR}/cover.key" \
  >"${TMP_DIR}/cover.stdout" 2>"${TMP_DIR}/cover.stderr" <<'PY' &
import socket
import ssl
import sys
import threading

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.load_cert_chain(sys.argv[1], sys.argv[2])
context.set_alpn_protocols(["h2", "http/1.1"])
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", 443))
listener.listen(16)

def serve(conn):
    try:
        conn.settimeout(3)
        with context.wrap_socket(conn, server_side=True) as tls:
            request = tls.recv(65536)
            if request.startswith(b"HEAD "):
                tls.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            elif request.startswith(b"PRI * HTTP/2.0"):
                # Minimal h2 HEAD response: SETTINGS, followed by indexed :status=200.
                tls.sendall(b"\x00\x00\x00\x04\x00\x00\x00\x00\x00")
                tls.sendall(b"\x00\x00\x01\x01\x05\x00\x00\x00\x01\x88")
    except (OSError, ssl.SSLError):
        pass

while True:
    conn, _ = listener.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
PY
COVER_PID=$!
wait_for_port 443 "${COVER_PID}"

CHECKER_STATUS=0
run_reality_target_check "${TMP_DIR}/checker/reality-target-checker.sh" \
  "${FIXTURE_DOMAIN}" "${TMP_DIR}/report.json" 2>"${TMP_DIR}/checker.stderr" || CHECKER_STATUS=$?
validate_reality_target_report "${TMP_DIR}/report.json" "${FIXTURE_DOMAIN}" "${CHECKER_STATUS}"
[[ "${CHECKER_STATUS}" == 3 ]]
jq -e '.selection.complete == true and .summary.basic_tls == "PASS" and
  .summary.compatibility == "PASS" and
  (.endpoints | length == 1 and .[0].ip == "127.0.0.1")' \
  "${TMP_DIR}/report.json" >/dev/null
printf 'checker_real_tls13_h2_x25519=passed\n'

# The automatic chooser must use the report and explicit WARN consent.
SELECTED_SNI=$(select_reality_sni_candidate "${FIXTURE_DOMAIN}" <<'EOF'
y
EOF
)
[[ "${SELECTED_SNI}" == "${FIXTURE_DOMAIN}" ]]
SB_SNI="${SELECTED_SNI}"
SB_PORT=18443
SB_VLESS_INSTANCE_ID=main
SB_NODE_NAME=reality-runtime
SB_UUID=11111111-1111-4111-8111-111111111111
SB_SHORT_ID_1=aaaaaaaaaaaaaaaa
SB_SHORT_ID_2=bbbbbbbbbbbbbbbb
SB_VLESS_ALPN_MODE=off
SB_VLESS_TCP_FAST_OPEN=n
SB_ENABLE_WARP=n
SB_OUTBOUND_POLICY=default
ensure_vless_reality_materials
save_vless_reality_state
printf '%s\n' INSTALLED_PROTOCOLS=vless-reality PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
grep -Fqx "SNI=${FIXTURE_DOMAIN}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
INBOUNDS=$(build_vless_inbound_json | jq -s .)
OUTBOUNDS=$(build_client_vless_reality_outbounds 127.0.0.1 | jq -s .)
CLIENT_TAG=$(jq -r '.[0].tag' <<< "${OUTBOUNDS}")
jq -n --argjson inbounds "${INBOUNDS}" \
  '{log:{level:"warn"},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
  > "${TMP_DIR}/server.json"
jq -n --argjson outbounds "${OUTBOUNDS}" --arg final "${CLIENT_TAG}" \
  '{log:{level:"warn"},inbounds:[{type:"socks",tag:"local",listen:"127.0.0.1",listen_port:19080}],
    outbounds:$outbounds,route:{final:$final}}' > "${TMP_DIR}/client.json"
jq -e --arg sni "${FIXTURE_DOMAIN}" \
  '.inbounds[0].tls.server_name == $sni and .inbounds[0].tls.reality.handshake.server == $sni' \
  "${TMP_DIR}/server.json" >/dev/null
jq -e --arg sni "${FIXTURE_DOMAIN}" '.outbounds[0].tls.server_name == $sni' \
  "${TMP_DIR}/client.json" >/dev/null
"${CORE_BINARY}" check -c "${TMP_DIR}/server.json"
"${CORE_BINARY}" check -c "${TMP_DIR}/client.json"
printf 'persisted_sni_and_generated_configs=passed\n'

python3 - >"${TMP_DIR}/marker.stdout" 2>"${TMP_DIR}/marker.stderr" <<'PY' &
import http.server
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"reality-target-runtime-marker\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_args):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
PY
MARKER_PID=$!
wait_for_port 18080 "${MARKER_PID}"
"${CORE_BINARY}" run -c "${TMP_DIR}/server.json" \
  >"${TMP_DIR}/server.stdout" 2>"${TMP_DIR}/server.stderr" &
SERVER_PID=$!
wait_for_port "${SB_PORT}" "${SERVER_PID}"
"${CORE_BINARY}" run -c "${TMP_DIR}/client.json" \
  >"${TMP_DIR}/client.stdout" 2>"${TMP_DIR}/client.stderr" &
CLIENT_PID=$!
wait_for_port 19080 "${CLIENT_PID}"
curl --fail --silent --show-error --max-time 10 --noproxy '' \
  --proxy socks5h://127.0.0.1:19080 http://127.0.0.1:18080/ > "${TMP_DIR}/response.txt"
grep -Fqx reality-target-runtime-marker "${TMP_DIR}/response.txt"
printf 'reality_handshake_and_http_payload=passed\n'
