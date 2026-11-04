# Shared private runtime fixtures. Sourced as definitions by the Docker payload.
verification_fixture_tcp_marker() {
  if [[ -n "${direct_marker_pid:-}" ]]; then
    kill -0 "${direct_marker_pid}" 2>/dev/null || return 1
    [[ "${direct_marker_port:-}" =~ ^[0-9]+$ ]] || return 1
    return 0
  fi
  direct_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-marker.port"
  direct_marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-marker.stdout.txt")
  direct_marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-marker.stderr.txt")
  direct_marker_requests="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-marker.requests"
  direct_marker="sing-box-vps-direct-inbound-loopback-ok-$(date +%s)-$$"
  python3 - "${direct_marker_port_file}" "${direct_marker}" "${direct_marker_requests}" \
    > "${direct_marker_stdout}" 2> "${direct_marker_stderr}" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file, marker, requests_file = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def reply(self, body):
        with open(requests_file, "a", encoding="utf-8") as log:
            log.write(self.command + " " + self.path + "\n")
        payload = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if body:
            self.wfile.write(payload)

    def do_GET(self):
        self.reply(True)

    def do_HEAD(self):
        self.reply(False)

    def log_message(self, *_args):
        return

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer(("127.0.0.1", 0), MarkerHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  direct_marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${direct_marker_port_file}" ]] && break
    kill -0 "${direct_marker_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${direct_marker_port_file}" ]]
  direct_marker_port=$(cat "${direct_marker_port_file}")
  [[ "${direct_marker_port}" =~ ^[0-9]+$ ]]
}

verification_fixture_udp_echo() {
  if [[ -n "${direct_udp_marker_pid:-}" ]]; then
    kill -0 "${direct_udp_marker_pid}" 2>/dev/null || return 1
    [[ "${direct_udp_marker_port:-}" =~ ^[0-9]+$ ]] || return 1
    return 0
  fi
  direct_udp_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-marker.port"
  direct_udp_marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-marker.stdout.txt")
  direct_udp_marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-marker.stderr.txt")
  direct_udp_marker="sing-box-vps-direct-inbound-udp-loopback-ok-$(date +%s)-$$"
  python3 - "${direct_udp_marker_port_file}" \
    > "${direct_udp_marker_stdout}" 2> "${direct_udp_marker_stderr}" <<'PY' &
import pathlib
import socket
import sys

port_file = sys.argv[1]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
    server.bind(("127.0.0.1", 0))
    pathlib.Path(port_file).write_text(str(server.getsockname()[1]), encoding="ascii")
    while True:
        payload, address = server.recvfrom(65535)
        server.sendto(payload, address)
PY
  direct_udp_marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${direct_udp_marker_port_file}" ]] && break
    kill -0 "${direct_udp_marker_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${direct_udp_marker_port_file}" ]]
  direct_udp_marker_port=$(cat "${direct_udp_marker_port_file}")
  [[ "${direct_udp_marker_port}" =~ ^[0-9]+$ ]]
}

verification_fixture_tls() {
  if [[ "${VERIFY_CASE_TLS_READY:-0}" == 1 ]]; then
    [[ -f "${cert_path}" && -f "${key_path}" ]] || return 1
    return 0
  fi
  cert_dir="/tmp/sing-box-vps-verification-tls"
  rm -rf -- "${cert_dir}"
  cert_path="${cert_dir}/cert.pem"
  key_path="${cert_dir}/key.pem"
  mkdir -p "${cert_dir}"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${key_path}" \
    -out "${cert_path}" \
    -subj '/CN=sing-box-vps-verification.invalid' \
    -addext 'subjectAltName=DNS:sing-box-vps-verification.invalid' \
    -days 1 >/dev/null 2>&1
  chmod 600 "${cert_path}" "${key_path}"
  VERIFY_CASE_TLS_READY=1
}

verification_fixture_tls_cover() {
  if [[ -n "${shadowtls_handshake_pid:-}" ]] && kill -0 "${shadowtls_handshake_pid}" 2>/dev/null; then return 0; fi
  shadowtls_cover_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.stdout.txt")
  shadowtls_cover_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.stderr.txt")
  openssl s_server -accept 127.0.0.1:1090 -cert "${cert_path}" -key "${key_path}" -www -quiet \
    >"${shadowtls_cover_stdout}" 2>"${shadowtls_cover_stderr}" &
  shadowtls_handshake_pid=$!
  for _ in {1..50}; do
    if verification_port_is_listening 1090; then break; fi
    kill -0 "${shadowtls_handshake_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_assert_port_listening 1090 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.ss-lntp.txt"
}

verification_case_context_start() {
  local baseline=${1:-socks}
  [[ "${baseline}" == socks || "${baseline}" == none ]] || return 2
  verification_prepare_remote_local_tree
  umask 077
  local name
  for name in shadowtls_handshake_pid http_outbound_marker_pid http_outbound_proxy_pid direct_marker_pid direct_udp_marker_pid ssh_marker_pid sshd_pid socks_outbound_marker_pid socks_upstream_pid socks_udp_upstream_pid vless_outbound_udp_client_pid vless_outbound_server_pid shadowtls_outbound_server_pid; do
    printf -v "${name}" '%s' ''
  done
  vless_outbound_server_dir=''
  shadowtls_outbound_server_dir=''
  config_path=''
  VERIFY_CASE_TLS_READY=0
  VERIFY_CASE_SSH_USER_CREATED=''
  VERIFY_CASE_SSH_USER_UID=''
  VERIFY_REDIRECT_FIXTURE_OWNED=0
  VERIFY_REDIRECT_NETNS_CREATED=0
  VERIFY_REDIRECT_VETH_CREATED=0
  VERIFY_REDIRECT_MARKER_PID=''
  VERIFY_REDIRECT_HOST_VETH=''
  VERIFY_REDIRECT_NETNS=''
  trap 'verification_case_context_cleanup "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "${baseline}" == socks ]]; then verification_assert_atomic_socks_baseline; fi
}

verification_case_stop_pid() {
  local name=$1 pid status=0
  case "${name}" in
    shadowtls_handshake_pid|http_outbound_marker_pid|http_outbound_proxy_pid|direct_marker_pid|direct_udp_marker_pid|ssh_marker_pid|sshd_pid|socks_outbound_marker_pid|socks_upstream_pid|socks_udp_upstream_pid|vless_outbound_udp_client_pid|vless_outbound_server_pid|shadowtls_outbound_server_pid) ;;
    *) printf 'unregistered fixture PID variable\n' >&2; return 2 ;;
  esac
  pid=${!name:-}
  [[ -n "${pid}" ]] || return 0
  if kill -0 "${pid}" 2>/dev/null; then kill "${pid}" || status=1; fi
  if wait "${pid}"; then :; else
    case $? in 0|130|137|143) ;; *) status=1 ;; esac
  fi
  printf -v "${name}" '%s' ''
  return "${status}"
}

verification_case_context_cleanup() {
  local status=$1 cleanup_status=0 name pid path
  trap - EXIT
  for name in shadowtls_handshake_pid http_outbound_marker_pid http_outbound_proxy_pid direct_marker_pid direct_udp_marker_pid ssh_marker_pid sshd_pid socks_outbound_marker_pid socks_upstream_pid socks_udp_upstream_pid vless_outbound_udp_client_pid vless_outbound_server_pid shadowtls_outbound_server_pid; do
    verification_case_stop_pid "${name}" || cleanup_status=1
  done
  if [[ -f "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/fixture.json")" ]]; then
    verification_case_cleanup_tproxy_component || cleanup_status=1
    verification_cleanup_tproxy_probe_fixture || cleanup_status=1
  fi
  if [[ "${VERIFY_REDIRECT_FIXTURE_OWNED:-0}" == 1 ]]; then
    verification_cleanup_redirect_policy_fixture || cleanup_status=1
  fi
  for path in "${vless_outbound_server_dir:-}" "${shadowtls_outbound_server_dir:-}"; do
    [[ -z "${path}" ]] || rm -rf -- "${path}" || cleanup_status=1
  done
  if [[ -n "${VERIFY_CASE_SSH_USER_CREATED:-}" ]]; then
    if [[ "${VERIFY_CASE_SSH_USER_CREATED}" == sbv-verifier && "${VERIFY_CASE_SSH_USER_UID:-}" =~ ^[1-9][0-9]*$ ]] &&
      [[ "$(id -u sbv-verifier)" == "${VERIFY_CASE_SSH_USER_UID}" ]]; then
      userdel sbv-verifier || cleanup_status=1
    else
      printf 'refused cleanup of changed SSH fixture identity\n' >&2
      cleanup_status=1
    fi
  fi
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/cleanup.env" "PROCESS_CLEANUP=$([[ ${cleanup_status} == 0 ]] && printf success || printf failure)" || cleanup_status=1
  verification_cleanup_remote_local_tree || cleanup_status=1
  [[ ${status} != 0 ]] || status=${cleanup_status}
  exit "${status}"
}

verification_case_assert_clean() {
  local expected_revision=${1:?expected revision required}
  jq -e --argjson revision "${expected_revision}" '.revision==$revision and (.components|length)==0' \
    /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/final-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_wait_for_service_active sing-box
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/leaf.result.env" \
    'RESULT=success' "FINAL_REVISION=${expected_revision}"
}

verification_case_cleanup_tproxy_component() {
  local store=/root/.sing-box-vps/runtime/components.json revision read_status
  [[ -e "${store}" || -L "${store}" ]] || return 0
  if [[ ! -f "${store}" || -L "${store}" ]] ||
    ! jq -e 'type=="object" and (.revision|type=="number" and .>=0 and .==floor) and
      (.components|type=="array") and all(.components[]; type=="object")' "${store}" >/dev/null; then
    printf 'TProxy fixture cleanup rejected its component registry\n' >&2
    return 1
  fi
  if jq -e 'any(.components[]; .id=="tproxy-inbound-verification" and .role=="inbound" and .type=="tproxy")' "${store}" >/dev/null; then
    revision=$(jq -er '.revision|select(type=="number" and .>=0 and .==floor)' "${store}") || return 1
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
      --expected-revision "${revision}" --id tproxy-inbound-verification \
      > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-cleanup-delete.json")" || return 1
  else
    read_status=$?
    [[ "${read_status}" == 1 ]] || return 1
  fi
}

# Loopback-only HTTP upstream shared with its handshake regression. The proxy
# accepts one synthetic target, authentication and header contract; it cannot
# become an open forward proxy if a managed route is rendered incorrectly.
verification_atomic_http_fixture() {
  exec python3 - "$@" <<'PY_HTTP_FIXTURE'
import http.server
import json
import pathlib
import select
import socket
import socketserver
import sys
import threading

ports_path, marker, domain, request_log = sys.argv[1:]

class Marker(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        payload = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(("127.0.0.1", 0), Marker) as origin:
    class Proxy(socketserver.BaseRequestHandler):
        def handle(self):
            client = self.request
            client.settimeout(5)
            raw = bytearray()
            while b"\r\n\r\n" not in raw and len(raw) < 65536:
                chunk = client.recv(1)
                if not chunk:
                    return
                raw.extend(chunk)
            if not raw.endswith(b"\r\n\r\n"):
                return
            lines = bytes(raw).decode("iso-8859-1").split("\r\n")
            headers = {}
            for line in lines[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.lower()] = value.strip()
            if headers.get("proxy-authorization") != "Basic cHJveHktdXNlcjpwcm94eS1wYXNz":
                client.sendall(b"HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n")
                return
            if (lines[0] != "CONNECT " + domain + ":80 HTTP/1.1" or
                    headers.get("x-sbv-proxy") != "http-outbound"):
                client.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
                return
            pathlib.Path(request_log).write_bytes(raw)
            with socket.create_connection(origin.server_address, timeout=5) as upstream:
                client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                peers = [client, upstream]
                while True:
                    readable, _, _ = select.select(peers, [], [], 5)
                    if not readable:
                        return
                    for source in readable:
                        data = source.recv(65536)
                        if not data:
                            return
                        (upstream if source is client else client).sendall(data)

    with Server(("127.0.0.1", 0), Proxy) as proxy:
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        ports_stage = pathlib.Path(ports_path + ".stage")
        ports_stage.write_text(json.dumps({"proxy": proxy.server_address[1]}))
        ports_stage.replace(ports_path)
        proxy.serve_forever()
PY_HTTP_FIXTURE
}
