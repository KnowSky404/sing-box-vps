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

verification_scenario_component_http_outbound() (
  set -euo pipefail
  umask 077
  local fixture_pid='' status=0 cleanup_status=0
  local config_file=/root/.sing-box-vps/runtime/config.json
  local state_file=/root/.sing-box-vps/runtime/components.json
  local component_id=atomic-http-outbound
  local target_domain=sbv-atomic-http-outbound.invalid
  local marker="sing-box-vps-atomic-http-$(date +%s)-$$"
  local ports_file record create_result delete_result response requests proxy_port

  verification_prepare_remote_local_tree
  verification_cleanup_atomic_http() {
    status=$?
    trap - EXIT
    if [[ -n "${fixture_pid}" ]]; then
      if kill -0 "${fixture_pid}" 2>/dev/null; then
        kill "${fixture_pid}" || cleanup_status=1
      fi
      if wait "${fixture_pid}"; then :; else
        case $? in 143) ;; *) cleanup_status=1 ;; esac
      fi
    fi
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/cleanup.env" \
      "PROCESS_CLEANUP=$([[ "${cleanup_status}" == 0 ]] && printf success || printf failure)" || cleanup_status=1
    verification_cleanup_remote_local_tree || cleanup_status=1
    if [[ "${status}" == 0 ]]; then status=${cleanup_status}; fi
    exit "${status}"
  }
  trap verification_cleanup_atomic_http EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf 'SCENARIO=component_http_outbound\n'

  # The planner provides fresh_install_socks. Refuse inherited multi-protocol
  # state or another component revision rather than broadening this case.
  jq -e '(.inbounds|length)==1 and .inbounds[0].type=="socks" and
    .inbounds[0].tag=="socks-in" and .inbounds[0].listen_port==1081 and
    .inbounds[0].users==[{username:"socks-user",password:"socks-pass"}]' \
    "${config_file}" >/dev/null
  if [[ -f "${state_file}" ]]; then
    jq -e '.revision==0 and (.components|length)==0' "${state_file}" >/dev/null
  fi

  ports_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-upstream-ports.json"
  record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-record.json"
  create_result=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/create.json")
  delete_result=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/delete.json")
  response=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/response.txt")
  requests=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/proxy.request.txt")
  verification_atomic_http_fixture "${ports_file}" "${marker}" "${target_domain}" "${requests}" \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/upstream.stdout.txt")" \
    2> "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/upstream.stderr.txt")" &
  fixture_pid=$!
  for _ in {1..50}; do
    [[ -s "${ports_file}" ]] && break
    kill -0 "${fixture_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  proxy_port=$(jq -er '.proxy | select(type=="number" and .>0 and .<65536)' "${ports_file}")
  jq -n --arg id "${component_id}" --arg domain "${target_domain}" --argjson port "${proxy_port}" '
    {id:$id,role:"outbound",type:"http",tag:$id,enabled:true,
      route_rules:[{inbound:["socks-in"],domain:[$domain],action:"route",outbound:$id}],
      config:{server:"127.0.0.1",server_port:$port,username:"proxy-user",password:"proxy-pass",
        headers:{"X-SBV-Proxy":"http-outbound"},connect_timeout:"5s"}}' > "${record}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision 0 --file "${record}" > "${create_result}"
  jq -e --arg id "${component_id}" '.ok==true and .operation=="create" and
    .revision==1 and .type=="http" and .id==$id' "${create_result}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/created-check.txt" sing-box check -c "${config_file}"
  verification_capture_file_if_present "${config_file}" "${VERIFY_CURRENT_SCENARIO_DIR}/created-config.json"
  jq -e --arg id "${component_id}" --arg domain "${target_domain}" --argjson port "${proxy_port}" '
    any(.outbounds[]; .tag==$id and .type=="http" and .server=="127.0.0.1" and
      .server_port==$port and .username=="proxy-user" and .password=="proxy-pass" and
      .headers["X-SBV-Proxy"]=="http-outbound") and
    any(.route.rules[]; .inbound==["socks-in"] and .domain==[$domain] and .outbound==$id)
  ' "${config_file}" >/dev/null
  curl --fail --silent --show-error --connect-timeout 5 --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${target_domain}/" > "${response}" \
    2> "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/curl.stderr.txt")"
  printf '%s\n' "${marker}" | cmp -s - "${response}"
  grep -Fq 'Proxy-Authorization: Basic cHJveHktdXNlcjpwcm94eS1wYXNz' "${requests}"
  grep -iFq 'X-SBV-Proxy: http-outbound' "${requests}"
  verification_mark_step authenticated-http-marker-complete

  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 1 --id "${component_id}" > "${delete_result}"
  jq -e --arg id "${component_id}" '.ok==true and .operation=="delete" and
    .revision==2 and .id==$id' "${delete_result}" >/dev/null
  jq -e '.revision==2 and (.components|length)==0' "${state_file}" >/dev/null
  jq -e --arg id "${component_id}" '
    all(.outbounds[]; .tag!=$id) and all(.route.rules[]?; .outbound!=$id)
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/deleted-check.txt" sing-box check -c "${config_file}"
  verification_mark_step http-component-and-route-deleted
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound.result.env" \
    'COMPONENT=http-outbound' 'RESULT=success' 'DATA_PLANE=authenticated_http_proxy_loopback' \
    'LIFECYCLE=create_delete' 'REVISIONS=0,1,2'
)
