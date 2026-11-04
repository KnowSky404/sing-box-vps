# Shared outbound assertions; loaded into the trusted verification payload.
# Explicit CAS bases preserve both aggregate and independent leaf contracts.

verification_case_ssh_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # SSH is an outbound-only adapter.  Prove its real direct-tcpip path with a
  # disposable OpenSSH server and loopback marker, while keeping the route
  # owned by the typed component transaction.  The target name is localhost so
  # the SSH server resolves it inside this same isolated container; no external
  # host or credential is involved.
  local ssh_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-marker.port"
  local ssh_marker_stdout
  local ssh_marker_stderr
  local ssh_marker
  local ssh_marker_port
  local ssh_port=2222
  local ssh_server_user=sbv-verifier
  local ssh_server_password=sbv-ssh-password
  local ssh_dir="${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh"
  local ssh_host_key="${ssh_dir}/ssh_host_ed25519_key"
  local ssh_host_key_public
  local sshd_config="${ssh_dir}/sshd_config"
  local sshd_log
  local ssh_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-outbound-record.json"
  local ssh_response="${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound-response.txt"
  local ssh_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound-curl.stderr.txt"
  local ssh_create_status=0
  local ssh_delete_status=0
  ssh_marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-marker.stdout.txt")
  ssh_marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-marker.stderr.txt")
  sshd_log=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/sshd.log")
  ssh_marker="sing-box-vps-ssh-outbound-loopback-ok-$(date +%s)-$$"
  python3 - "${ssh_marker_port_file}" "${ssh_marker}" \
    > "${ssh_marker_stdout}" 2> "${ssh_marker_stderr}" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file, marker = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer(("127.0.0.1", 0), MarkerHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  ssh_marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${ssh_marker_port_file}" ]] && break
    kill -0 "${ssh_marker_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${ssh_marker_port_file}" ]]
  ssh_marker_port=$(cat "${ssh_marker_port_file}")
  [[ "${ssh_marker_port}" =~ ^[0-9]+$ ]]
  if verification_port_is_listening "${ssh_port}"; then
    printf 'SSH fixture port is already occupied\n' >&2
    return 2
  fi

  mkdir -p "${ssh_dir}" /run/sshd
  ssh-keygen -q -t ed25519 -N '' -f "${ssh_host_key}" >/dev/null
  ssh_host_key_public=$(ssh-keygen -y -f "${ssh_host_key}")
  if id "${ssh_server_user}" >/dev/null 2>&1; then
    printf 'SSH fixture user already exists; refusing password replacement\n' >&2
    return 2
  fi
  useradd --no-create-home --shell /bin/sh "${ssh_server_user}"
  VERIFY_CASE_SSH_USER_CREATED=${ssh_server_user}
  VERIFY_CASE_SSH_USER_UID=$(id -u "${ssh_server_user}")
  printf '%s:%s\n' "${ssh_server_user}" "${ssh_server_password}" | chpasswd
  printf '%s\n' \
    'Port 2222' \
    'ListenAddress 127.0.0.1' \
    "HostKey ${ssh_host_key}" \
    'PermitRootLogin no' \
    'PasswordAuthentication yes' \
    'KbdInteractiveAuthentication no' \
    'ChallengeResponseAuthentication no' \
    'PubkeyAuthentication no' \
    "AllowUsers ${ssh_server_user}" \
    'UsePAM no' \
    'StrictModes no' \
    'LogLevel DEBUG1' > "${sshd_config}"
  /usr/sbin/sshd -D -e -f "${sshd_config}" > "${sshd_log}" 2>&1 &
  sshd_pid=$!
  for _ in {1..50}; do
    if verification_port_is_listening "${ssh_port}"; then break; fi
    kill -0 "${sshd_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_assert_port_listening "${ssh_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.sshd.ss-lntp.txt"

  (umask 077; jq -n --arg host_key "${ssh_host_key_public}" \
    --argjson ssh_port "${ssh_port}" '
    {id:"ssh-outbound-verification",role:"outbound",type:"ssh",
     tag:"ssh-outbound-verification",enabled:true,
     route_rules:[{domain:["localhost"],action:"route",outbound:"ssh-outbound-verification"}],
     config:{server:"127.0.0.1",server_port:$ssh_port,user:"sbv-verifier",
       password:"sbv-ssh-password",host_key:[$host_key],connect_timeout:"5s"}}
  ' > "${ssh_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${ssh_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-create.json"
  ssh_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-create.json"
  [[ "${ssh_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and .type=="ssh"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-create.json" >/dev/null
  verification_mark_step ssh-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg host_key "${ssh_host_key_public}" --argjson ssh_port "${ssh_port}" '
    ([.outbounds[] | select(.type == "ssh" and .tag == "ssh-outbound-verification" and
      .server == "127.0.0.1" and .server_port == $ssh_port and
      .user == "sbv-verifier" and .password == "sbv-ssh-password" and
      .host_key == [$host_key])] | length == 1) and
    ([.route.rules[] | select(.outbound == "ssh-outbound-verification" and
      .domain == ["localhost"])] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step ssh-outbound-config-asserted
  set +e
  curl --fail --silent --show-error --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://localhost:${ssh_marker_port}/" \
    > "$(verification_artifact_path "${ssh_response}")" \
    2> "$(verification_artifact_path "${ssh_curl_stderr}")"
  local ssh_curl_status=$?
  set -e
  [[ "${ssh_curl_status}" == 0 ]]
  grep -Fqx "${ssh_marker}" "$(verification_artifact_path "${ssh_response}")"
  grep -Fq "Accepted password for ${ssh_server_user}" "${sshd_log}"
  verification_mark_step ssh-outbound-curl-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id ssh-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-delete.json"
  ssh_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-delete.json"
  [[ "${ssh_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and .id=="ssh-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-delete.json" >/dev/null
  verification_mark_step ssh-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "ssh-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "ssh-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["ssh-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound.result.env" \
    'COMPONENT=ssh-outbound' 'RESULT=success' \
    'DATA_PLANE=ssh_direct_tcpip_loopback' 'HOST_KEY_VERIFICATION=pinned'
}

verification_case_socks_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # SOCKS is a managed outbound adapter rather than another inbound preset.
  # Prove its authenticated SOCKS5 CONNECT path with a disposable upstream
  # server and loopback marker, keeping the upstream credentials inside this
  # isolated container and the route owned by the component CAS transaction.
  local socks_outbound_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-marker.port"
  local socks_outbound_marker_stdout
  local socks_outbound_marker_stderr
  local socks_outbound_marker
  local socks_outbound_marker_port
  local socks_upstream_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-upstream.port"
  local socks_upstream_stdout
  local socks_upstream_stderr
  local socks_upstream_request_log
  local socks_upstream_port
  local socks_upstream_user=socks-upstream-user
  local socks_upstream_password=socks-upstream-pass
  local socks_outbound_target_domain=sbv-socks-outbound.invalid
  local socks_outbound_dir="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound"
  local socks_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-record.json"
  local socks_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-response.txt"
  local socks_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-curl.stderr.txt"
  local socks_outbound_create_status=0
  local socks_outbound_delete_status=0
  socks_outbound_marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-marker.stdout.txt")
  socks_outbound_marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-marker.stderr.txt")
  socks_upstream_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-upstream.stdout.txt")
  socks_upstream_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-upstream.stderr.txt")
  socks_upstream_request_log=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-upstream.request.txt")
  mkdir -p "${socks_outbound_dir}"
  socks_outbound_marker="sing-box-vps-socks-outbound-loopback-ok-$(date +%s)-$$"
  python3 - "${socks_outbound_marker_port_file}" "${socks_outbound_marker}" \
    > "${socks_outbound_marker_stdout}" 2> "${socks_outbound_marker_stderr}" <<'PY' &
import http.server
import pathlib
import socketserver
import sys

port_file, marker = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = (marker + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer(("127.0.0.1", 0), MarkerHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  socks_outbound_marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${socks_outbound_marker_port_file}" ]] && break
    kill -0 "${socks_outbound_marker_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${socks_outbound_marker_port_file}" ]]
  socks_outbound_marker_port=$(cat "${socks_outbound_marker_port_file}")
  [[ "${socks_outbound_marker_port}" =~ ^[0-9]+$ ]]

  python3 - "${socks_upstream_port_file}" "${socks_outbound_marker_port}" \
    "${socks_outbound_target_domain}" "${socks_upstream_user}" \
    "${socks_upstream_password}" "${socks_upstream_request_log}" <<'PY' \
    > "${socks_upstream_stdout}" 2> "${socks_upstream_stderr}" &
import pathlib
import select
import socket
import socketserver
import sys

port_file, marker_port, marker_domain, expected_user, expected_password, request_log = sys.argv[1:]
marker_port = int(marker_port)

def recv_exact(conn, size):
    data = bytearray()
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise ConnectionError("short SOCKS5 frame")
        data.extend(chunk)
    return bytes(data)

def relay(left, right):
    sockets = [left, right]
    while True:
        ready, _, _ = select.select(sockets, [], [], 5)
        if not ready:
            continue
        for source in ready:
            payload = source.recv(65536)
            if not payload:
                return
            destination = right if source is left else left
            destination.sendall(payload)

class SocksHandler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(5)
        try:
            if recv_exact(client, 1) != b"\x05":
                return
            method_count = recv_exact(client, 1)[0]
            methods = recv_exact(client, method_count)
            if 2 not in methods:
                client.sendall(b"\x05\xff")
                return
            client.sendall(b"\x05\x02")
            if recv_exact(client, 1) != b"\x01":
                return
            user_length = recv_exact(client, 1)[0]
            user = recv_exact(client, user_length).decode("utf-8")
            password_length = recv_exact(client, 1)[0]
            password = recv_exact(client, password_length).decode("utf-8")
            if user != expected_user or password != expected_password:
                client.sendall(b"\x01\x01")
                return
            client.sendall(b"\x01\x00")
            version, command, _, address_type = recv_exact(client, 4)
            if version != 5 or command != 1:
                client.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
                return
            if address_type == 1:
                host = socket.inet_ntoa(recv_exact(client, 4))
            elif address_type == 3:
                host = recv_exact(client, recv_exact(client, 1)[0]).decode("idna")
            elif address_type == 4:
                host = socket.inet_ntop(socket.AF_INET6, recv_exact(client, 16))
            else:
                client.sendall(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
                return
            port = int.from_bytes(recv_exact(client, 2), "big")
            if host not in ("127.0.0.1", "localhost", marker_domain) or port != marker_port:
                client.sendall(b"\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00")
                return
            with socket.create_connection(("127.0.0.1", marker_port), timeout=5) as upstream:
                bind_host, bind_port = upstream.getsockname()
                client.sendall(b"\x05\x00\x00\x01" + socket.inet_aton(bind_host) +
                               bind_port.to_bytes(2, "big"))
                pathlib.Path(request_log).write_text(
                    "AUTHENTICATED\nDESTINATION=%s:%s\n" % (host, port),
                    encoding="ascii")
                relay(client, upstream)
        except (ConnectionError, OSError, UnicodeError, ValueError):
            return

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer(("127.0.0.1", 0), SocksHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  socks_upstream_pid=$!
  for _ in {1..50}; do
    [[ -s "${socks_upstream_port_file}" ]] && break
    kill -0 "${socks_upstream_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${socks_upstream_port_file}" ]]
  socks_upstream_port=$(cat "${socks_upstream_port_file}")
  [[ "${socks_upstream_port}" =~ ^[0-9]+$ ]]

  (umask 077; jq -n --argjson upstream_port "${socks_upstream_port}" \
    --arg domain "${socks_outbound_target_domain}" '
    {id:"socks-outbound-verification",role:"outbound",type:"socks",
     tag:"socks-outbound-verification",enabled:true,
     route_rules:[{domain:[$domain],action:"route",outbound:"socks-outbound-verification"}],
     config:{server:"127.0.0.1",server_port:$upstream_port,version:"5",
       username:"socks-upstream-user",password:"socks-upstream-pass",network:["tcp"],
       connect_timeout:"5s"}}
  ' > "${socks_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${socks_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-create.json"
  socks_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-create.json"
  [[ "${socks_outbound_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and .type=="socks"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-create.json" >/dev/null
  verification_mark_step socks-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${socks_outbound_target_domain}" \
    --argjson upstream_port "${socks_upstream_port}" '
    ([.outbounds[] | select(.type == "socks" and .tag == "socks-outbound-verification" and
      .server == "127.0.0.1" and .server_port == $upstream_port and
      .version == "5" and .username == "socks-upstream-user" and
      .password == "socks-upstream-pass" and .network == ["tcp"])] | length == 1) and
    ([.route.rules[] | select(.outbound == "socks-outbound-verification" and
      .domain == [$domain])] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step socks-outbound-config-asserted
  set +e
  curl --fail --silent --show-error --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${socks_outbound_target_domain}:${socks_outbound_marker_port}/" \
    > "$(verification_artifact_path "${socks_outbound_response}")" \
    2> "$(verification_artifact_path "${socks_outbound_curl_stderr}")"
  local socks_outbound_curl_status=$?
  set -e
  [[ "${socks_outbound_curl_status}" == 0 ]]
  grep -Fqx "${socks_outbound_marker}" \
    "$(verification_artifact_path "${socks_outbound_response}")"
  grep -Fqx 'AUTHENTICATED' "${socks_upstream_request_log}"
  grep -Fqx "DESTINATION=${socks_outbound_target_domain}:${socks_outbound_marker_port}" \
    "${socks_upstream_request_log}"
  verification_mark_step socks-outbound-curl-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id socks-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-delete.json"
  socks_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-delete.json"
  [[ "${socks_outbound_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and .id=="socks-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-delete.json" >/dev/null
  verification_mark_step socks-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "socks-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "socks-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/socks-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["socks-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound.result.env" \
    'COMPONENT=socks-outbound' 'RESULT=success' \
    'DATA_PLANE=socks5_connect_loopback' 'AUTHENTICATION=upstream_username_password'
}

verification_case_selector_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # Selector groups must exercise their member resolution, not only parse as
  # arbitrary JSON.  Reuse the disposable direct loopback marker with a
  # single-member group so the route and chosen outbound are observable while
  # keeping the built-in direct owner outside the component registry.
  local selector_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-record.json"
  local selector_create_status=0
  local selector_delete_status=0
  (umask 077; jq -n '
    {id:"selector-outbound-verification",role:"outbound",type:"selector",
     tag:"selector-outbound-verification",enabled:true,
     route_rules:[{domain:["localhost"],action:"route",outbound:"selector-outbound-verification"}],
     config:{outbounds:["direct"],default:"direct",interrupt_exist_connections:true}}
  ' > "${selector_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${selector_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-create.json"
  selector_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-create.json"
  [[ "${selector_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and .type=="selector"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-create.json" >/dev/null
  verification_mark_step selector-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.type == "selector" and .tag == "selector-outbound-verification" and
      .outbounds == ["direct"] and .default == "direct" and
      .interrupt_exist_connections == true)] | length == 1) and
    ([.route.rules[] | select(.outbound == "selector-outbound-verification" and
      .domain == ["localhost"])] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step selector-outbound-config-asserted
  set +e
  curl --fail --silent --show-error --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://localhost:${direct_marker_port}/" \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-response.txt")" \
    2> "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-curl.stderr.txt")"
  local selector_curl_status=$?
  set -e
  [[ "${selector_curl_status}" == 0 ]]
  grep -Fqx "${direct_marker}" \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-response.txt")"
  verification_mark_step selector-outbound-curl-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id selector-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-delete.json"
  selector_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-delete.json"
  [[ "${selector_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and .id=="selector-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-delete.json" >/dev/null
  verification_mark_step selector-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "selector-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "selector-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/selector-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["selector-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound.result.env" \
    'COMPONENT=selector-outbound' 'RESULT=success' \
    'DATA_PLANE=selector_direct_loopback'
}

verification_case_urltest_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # URLTest groups share the same typed member graph but add an active health
  # URL. Give it a separate health path so the fixture can distinguish an
  # active health request from the business marker sent through the group.
  local urltest_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-record.json"
  local urltest_probe_url="http://localhost:${direct_marker_port}/urltest-health"
  local urltest_create_status=0
  local urltest_delete_status=0
  local urltest_curl_status=1
  (umask 077; jq -n --arg url "${urltest_probe_url}" '
    {id:"urltest-outbound-verification",role:"outbound",type:"urltest",
     tag:"urltest-outbound-verification",enabled:true,
     route_rules:[{domain:["localhost"],action:"route",outbound:"urltest-outbound-verification"}],
     config:{outbounds:["direct"],url:$url,interval:"1s",tolerance:0,
       idle_timeout:"5s",interrupt_exist_connections:true}}
  ' > "${urltest_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${urltest_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-create.json"
  urltest_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-create.json"
  [[ "${urltest_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and .type=="urltest"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-create.json" >/dev/null
  verification_mark_step urltest-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg url "${urltest_probe_url}" '
    ([.outbounds[] | select(.type == "urltest" and .tag == "urltest-outbound-verification" and
      .outbounds == ["direct"] and .url == $url and .interval == "1s" and
      .tolerance == 0 and .idle_timeout == "5s" and
      .interrupt_exist_connections == true)] | length == 1) and
    ([.route.rules[] | select(.outbound == "urltest-outbound-verification" and
      .domain == ["localhost"])] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step urltest-outbound-config-asserted
  local urltest_response="${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-response.txt"
  local urltest_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-curl.stderr.txt"
  for _ in {1..20}; do
    set +e
    curl --fail --silent --show-error --max-time 3 --noproxy '' \
      --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
      "http://localhost:${direct_marker_port}/urltest-business" \
      > "$(verification_artifact_path "${urltest_response}")" \
      2> "$(verification_artifact_path "${urltest_curl_stderr}")"
    urltest_curl_status=$?
    set -e
    if [[ "${urltest_curl_status}" == 0 ]] && \
      grep -Fqx "${direct_marker}" "$(verification_artifact_path "${urltest_response}")"; then
      break
    fi
    sleep 0.5
  done
  [[ "${urltest_curl_status}" == 0 ]]
  grep -Fqx "${direct_marker}" "$(verification_artifact_path "${urltest_response}")"
  verification_mark_step urltest-outbound-curl-complete
  # A business marker alone can succeed before an active probe. Require the
  # fixture's independent request log to observe the configured health path.
  for _ in {1..50}; do
    if [[ -f "${direct_marker_requests}" ]] && \
      grep -Eq '^(GET|HEAD) /urltest-health$' "${direct_marker_requests}"; then
      break
    fi
    sleep 0.1
  done
  grep -Eq '^(GET|HEAD) /urltest-health$' "${direct_marker_requests}"
  grep -Fxq 'GET /urltest-business' "${direct_marker_requests}"
  verification_capture_file_if_present "${direct_marker_requests}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-marker.requests.txt"
  verification_mark_step urltest-health-probe-observed

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id urltest-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-delete.json"
  urltest_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-delete.json"
  [[ "${urltest_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and .id=="urltest-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-delete.json" >/dev/null
  verification_mark_step urltest-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "urltest-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "urltest-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["urltest-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound.result.env" \
    'COMPONENT=urltest-outbound' 'RESULT=success' \
    'DATA_PLANE=urltest_direct_loopback' 'HEALTHCHECK=loopback_http' 'HEALTH_PROBE=observed'
}

verification_case_shadowsocks_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # A managed Shadowsocks outbound must exercise the encrypted upstream and
  # the component-owned route rules, not only parse a SS2022 object.  Reuse the
  # disposable SS2022 inbound above as the upstream and scope the first route
  # to the SOCKS5 ingress; the second route terminates the upstream request at
  # the existing direct loopback marker instead of recursively selecting the
  # same outbound for the synthetic domain.
  local shadowsocks_outbound_target_domain='sbv-shadowsocks-outbound.invalid'
  local shadowsocks_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-record.json"
  local shadowsocks_outbound_create_status=0
  local shadowsocks_outbound_delete_status=0
  (umask 077; jq -n --arg domain "${shadowsocks_outbound_target_domain}" \
    --argjson marker_port "${direct_marker_port}" '
    {id:"shadowsocks-outbound-verification",role:"outbound",type:"shadowsocks",
     tag:"shadowsocks-outbound-verification",enabled:true,
     route_rules:[
       {inbound:["socks-in"],domain:[$domain],action:"route",outbound:"shadowsocks-outbound-verification"},
       {inbound:["ss-in"],domain:[$domain],action:"route",outbound:"direct",
        override_address:"127.0.0.1",override_port:$marker_port}
     ],
     config:{server:"127.0.0.1",server_port:1083,
       method:"2022-blake3-aes-128-gcm",password:"MDEyMzQ1Njc4OWFiY2RlZg==",
       network:["tcp"]}}
  ' > "${shadowsocks_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${shadowsocks_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-create.json"
  shadowsocks_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-create.json"
  [[ "${shadowsocks_outbound_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="shadowsocks" and .id=="shadowsocks-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-create.json" >/dev/null
  verification_mark_step shadowsocks-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${shadowsocks_outbound_target_domain}" \
    --argjson marker_port "${direct_marker_port}" '
    ([.outbounds[] | select(.type == "shadowsocks" and
      .tag == "shadowsocks-outbound-verification" and
      .server == "127.0.0.1" and .server_port == 1083 and
      .method == "2022-blake3-aes-128-gcm" and
      .password == "MDEyMzQ1Njc4OWFiY2RlZg==" and .network == ["tcp"])] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .domain == [$domain] and .outbound == "shadowsocks-outbound-verification")] | length == 1) and
    ([.route.rules[] | select(.inbound == ["ss-in"] and .domain == [$domain] and
      .outbound == "direct" and .override_address == "127.0.0.1" and
      .override_port == $marker_port)] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step shadowsocks-outbound-config-asserted
  local shadowsocks_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-response.txt"
  local shadowsocks_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-curl.stderr.txt"
  set +e
  curl --fail --silent --show-error --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${shadowsocks_outbound_target_domain}/" \
    > "$(verification_artifact_path "${shadowsocks_outbound_response}")" \
    2> "$(verification_artifact_path "${shadowsocks_outbound_curl_stderr}")"
  local shadowsocks_outbound_curl_status=$?
  set -e
  [[ "${shadowsocks_outbound_curl_status}" == 0 ]]
  grep -Fqx "${direct_marker}" \
    "$(verification_artifact_path "${shadowsocks_outbound_response}")"
  verification_mark_step shadowsocks-outbound-curl-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id shadowsocks-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-delete.json"
  shadowsocks_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-delete.json"
  [[ "${shadowsocks_outbound_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and
    .id=="shadowsocks-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-delete.json" >/dev/null
  verification_mark_step shadowsocks-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "shadowsocks-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "shadowsocks-outbound-verification" or
      (.inbound == ["ss-in"] and .domain == ["sbv-shadowsocks-outbound.invalid"]))] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["shadowsocks-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound.result.env" \
    'COMPONENT=shadowsocks-outbound' 'RESULT=success' \
    'DATA_PLANE=shadowsocks2022_connect_loopback' 'AUTHENTICATION=ss2022_psk'
}

verification_case_direct_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # Direct outbound destination overrides belong to route options in sing-box
  # 1.14.  Exercise a custom direct component through the existing SOCKS5
  # ingress and the loopback marker, keeping the deprecated outbound override
  # fields out of the typed component config.
  local direct_outbound_target_domain='sbv-direct-outbound.invalid'
  local direct_outbound_udp_target_port=19093
  local direct_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-record.json"
  local direct_outbound_create_status=0
  local direct_outbound_delete_status=0
  (umask 077; jq -n --arg domain "${direct_outbound_target_domain}" \
    --argjson marker_port "${direct_marker_port}" \
    --argjson udp_marker_port "${direct_udp_marker_port}" \
    --argjson target_port "${direct_outbound_udp_target_port}" '
     {id:"direct-outbound-verification",role:"outbound",type:"direct",
     tag:"direct-outbound-verification",enabled:true,
     route_rules:[
       {inbound:["socks-in"],domain:[$domain],action:"route",
        outbound:"direct-outbound-verification",override_address:"127.0.0.1",
        override_port:$marker_port},
       {inbound:["socks-in"],network:["udp"],port:$target_port,action:"route",
        outbound:"direct-outbound-verification",override_address:"127.0.0.1",
        override_port:$udp_marker_port}
     ],config:{}}
  ' > "${direct_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${direct_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-create.json"
  direct_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-create.json"
  [[ "${direct_outbound_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="direct" and .id=="direct-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-create.json" >/dev/null
  verification_mark_step direct-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${direct_outbound_target_domain}" \
    --argjson marker_port "${direct_marker_port}" \
    --argjson udp_marker_port "${direct_udp_marker_port}" \
    --argjson target_port "${direct_outbound_udp_target_port}" '
    ([.outbounds[] | select(.type == "direct" and
      .tag == "direct-outbound-verification")] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .domain == [$domain] and .action == "route" and
      .outbound == "direct-outbound-verification" and
      .override_address == "127.0.0.1" and .override_port == $marker_port)] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .network == ["udp"] and .port == $target_port and .action == "route" and
      .outbound == "direct-outbound-verification" and
      .override_address == "127.0.0.1" and .override_port == $udp_marker_port)] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step direct-outbound-config-asserted
  local direct_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-response.txt"
  local direct_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-curl.stderr.txt"
  set +e
  curl --fail --silent --show-error --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${direct_outbound_target_domain}/" \
    > "$(verification_artifact_path "${direct_outbound_response}")" \
    2> "$(verification_artifact_path "${direct_outbound_curl_stderr}")"
  local direct_outbound_curl_status=$?
  set -e
  [[ "${direct_outbound_curl_status}" == 0 ]]
  grep -Fqx "${direct_marker}" \
    "$(verification_artifact_path "${direct_outbound_response}")"
  verification_mark_step direct-outbound-curl-complete

  # The same direct outbound must also forward an explicitly routed UDP
  # request.  The synthetic target port differs from the echo port so a
  # default direct fallback cannot produce the marker; only the component's
  # route-option override reaches the existing UDP echo fixture.
  local direct_outbound_udp_response="${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-udp-response.txt"
  local direct_outbound_udp_response_path
  local direct_outbound_udp_client_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-udp-client.stderr.txt"
  local direct_outbound_udp_marker="sing-box-vps-direct-outbound-udp-loopback-ok-$(date +%s)-$$"
  direct_outbound_udp_response_path=$(verification_artifact_path \
    "${direct_outbound_udp_response}")
  rm -f -- "${direct_outbound_udp_response_path}" \
    "$(verification_artifact_path "${direct_outbound_udp_client_stderr}")"
  set +e
  python3 - "${direct_outbound_udp_response_path}" \
    "${direct_outbound_udp_marker}" "${direct_outbound_udp_target_port}" \
    "${direct_udp_marker_port}" > /dev/null \
    2> "$(verification_artifact_path "${direct_outbound_udp_client_stderr}")" <<'PY'
import pathlib
import socket
import struct
import sys

response_path, marker_text, target_port_text, echo_port_text = sys.argv[1:]
marker = marker_text.encode("ascii")
target_port = int(target_port_text)
echo_port = int(echo_port_text)
if target_port == echo_port:
    raise RuntimeError("synthetic UDP target port must differ from echo port")

def recv_exact(conn, size):
    chunks = []
    received = 0
    while received < size:
        chunk = conn.recv(size - received)
        if not chunk:
            raise RuntimeError("SOCKS control connection closed")
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)

def read_address(conn, address_type):
    if address_type == 1:
        return socket.inet_ntoa(recv_exact(conn, 4))
    if address_type == 3:
        size = recv_exact(conn, 1)[0]
        return recv_exact(conn, size).decode("ascii")
    if address_type == 4:
        return socket.inet_ntop(socket.AF_INET6, recv_exact(conn, 16))
    raise RuntimeError("unsupported SOCKS address type")

username = b"socks-user"
password = b"socks-pass"
with socket.create_connection(("127.0.0.1", 1081), timeout=5) as control:
    control.settimeout(5)
    control.sendall(b"\x05\x01\x02")
    if recv_exact(control, 2) != b"\x05\x02":
        raise RuntimeError("SOCKS username/password method was not selected")
    control.sendall(b"\x01" + bytes([len(username)]) + username +
                   bytes([len(password)]) + password)
    if recv_exact(control, 2) != b"\x01\x00":
        raise RuntimeError("SOCKS authentication failed")
    control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    reply = recv_exact(control, 4)
    if reply[:2] != b"\x05\x00":
        raise RuntimeError("SOCKS UDP ASSOCIATE failed")
    relay_host = read_address(control, reply[3])
    relay_port = struct.unpack("!H", recv_exact(control, 2))[0]
    if relay_host in ("0.0.0.0", "::"):
        relay_host = "127.0.0.1"
    request = (b"\x00\x00\x00\x01" + socket.inet_aton("127.0.0.1") +
               struct.pack("!H", target_port) + marker)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(10)
        udp.sendto(request, (relay_host, relay_port))
        response, _source = udp.recvfrom(65535)
    if len(response) < 10 or response[:3] != b"\x00\x00\x00":
        raise RuntimeError("invalid SOCKS UDP response header")
    offset = 4
    if response[3] == 1:
        offset += 4
    elif response[3] == 3:
        offset += 1 + response[4]
    elif response[3] == 4:
        offset += 16
    else:
        raise RuntimeError("invalid SOCKS UDP response address type")
    offset += 2
    payload = response[offset:]
    if payload != marker:
        raise RuntimeError("UDP marker mismatch")
pathlib.Path(response_path).write_bytes(payload)
PY
  local direct_outbound_udp_client_status=$?
  set -e
  [[ "${direct_outbound_udp_client_status}" == 0 ]]
  grep -Fqx "${direct_outbound_udp_marker}" "${direct_outbound_udp_response_path}"
  verification_mark_step direct-outbound-udp-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id direct-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-delete.json"
  direct_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-delete.json"
  [[ "${direct_outbound_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and
    .id=="direct-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-outbound-delete.json" >/dev/null
  verification_mark_step direct-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "direct-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "direct-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/direct-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["direct-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound.result.env" \
    'COMPONENT=direct-outbound' 'RESULT=success' \
    'DATA_PLANE=direct_route_override_loopback'
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-outbound-udp.result.env" \
    'COMPONENT=direct-outbound' 'RESULT=success' \
    'DATA_PLANE=direct_udp_route_override_loopback'
}

verification_case_block_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # The block component has no options and must reject the routed request.  A
  # non-zero curl status is the data-plane assertion; a successful marker would
  # prove the route unexpectedly fell through to a different outbound.
  local block_outbound_target_domain='localhost'
  local block_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-record.json"
  local block_outbound_create_status=0
  local block_outbound_delete_status=0
  # A working control path makes rejection meaningful; a missing route or
  # unresolved synthetic domain must not produce a false-positive block result.
  curl --fail --silent --show-error --max-time 5 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${block_outbound_target_domain}:${direct_marker_port}/" \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/block-control-before.txt")"
  printf '%s\n' "${direct_marker}" | cmp -s - \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/block-control-before.txt")"
  (umask 077; jq -n --arg domain "${block_outbound_target_domain}" '
    {id:"block-outbound-verification",role:"outbound",type:"block",
     tag:"block-outbound-verification",enabled:true,
     route_rules:[{inbound:["socks-in"],domain:[$domain],action:"route",
       outbound:"block-outbound-verification"}],config:{}}
  ' > "${block_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${block_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-create.json"
  block_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound-create.json"
  [[ "${block_outbound_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="block" and .id=="block-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-create.json" >/dev/null
  verification_mark_step block-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${block_outbound_target_domain}" '
    ([.outbounds[] | select(.type == "block" and
      .tag == "block-outbound-verification")] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .domain == [$domain] and .action == "route" and
      .outbound == "block-outbound-verification")] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step block-outbound-config-asserted
  local block_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound-response.txt"
  local block_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound-curl.stderr.txt"
  set +e
  curl --fail --silent --show-error --max-time 5 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${block_outbound_target_domain}:${direct_marker_port}/" \
    > "$(verification_artifact_path "${block_outbound_response}")" \
    2> "$(verification_artifact_path "${block_outbound_curl_stderr}")"
  local block_outbound_curl_status=$?
  set -e
  [[ "${block_outbound_curl_status}" != 0 ]]
  if [[ -s "$(verification_artifact_path "${block_outbound_response}")" ]] &&
     grep -Fq "${direct_marker}" \
       "$(verification_artifact_path "${block_outbound_response}")"; then
    printf 'block outbound unexpectedly returned the direct marker\n' >&2
    return 1
  fi
  verification_mark_step block-outbound-curl-rejected

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id block-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-delete.json"
  block_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound-delete.json"
  [[ "${block_outbound_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and
    .id=="block-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/block-outbound-delete.json" >/dev/null
  verification_mark_step block-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "block-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "block-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/block-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["block-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  curl --fail --silent --show-error --max-time 5 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${block_outbound_target_domain}:${direct_marker_port}/" \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/block-control-after.txt")"
  printf '%s\n' "${direct_marker}" | cmp -s - \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/block-control-after.txt")"
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/block-outbound.result.env" \
    'COMPONENT=block-outbound' 'RESULT=success' \
    'DATA_PLANE=block_reject_loopback' 'REQUEST=expected_failure'
}

verification_case_vless_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # A managed VLESS outbound must complete a real VLESS handshake before its
  # route is considered covered.  The disposable upstream is another
  # sing-box process inside this verification container; its route sends the
  # synthetic destination to the existing HTTP marker, keeping the evidence
  # independent of external DNS, TLS or public services.
  local vless_outbound_server_config
  local vless_outbound_server_stdout
  local vless_outbound_server_stderr
  local vless_outbound_server_check
  local vless_outbound_server_port=1094
  local vless_outbound_server_uuid='33333333-3333-4333-8333-333333333333'
  local vless_outbound_target_domain='sbv-vless-outbound.invalid'
  local vless_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-record.json"
  local vless_outbound_create_status=0
  local vless_outbound_delete_status=0
  local vless_outbound_response
  local vless_outbound_curl_stderr

  vless_outbound_server_dir=$(mktemp -d /tmp/sing-box-vps-vless-upstream.XXXXXX)
  vless_outbound_server_config="${vless_outbound_server_dir}/config.json"
  vless_outbound_server_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-upstream.stdout.txt")
  vless_outbound_server_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-upstream.stderr.txt")
  vless_outbound_server_check="${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-upstream-check.txt"
  (umask 077; jq -n \
    --arg domain "${vless_outbound_target_domain}" \
    --arg uuid "${vless_outbound_server_uuid}" \
    --argjson server_port "${vless_outbound_server_port}" \
    --argjson marker_port "${direct_marker_port}" \
    --argjson udp_marker_port "${direct_udp_marker_port}" '
    {log:{disabled:true},
     inbounds:[{type:"vless",tag:"vless-outbound-upstream",listen:"127.0.0.1",
       listen_port:$server_port,users:[{uuid:$uuid}]}],
     outbounds:[{type:"direct",tag:"vless-upstream-direct"}],
     route:{rules:[
       {domain:[$domain],action:"route",outbound:"vless-upstream-direct",
        override_address:"127.0.0.1",override_port:$marker_port},
       {network:["udp"],port:$udp_marker_port,action:"route",
        outbound:"vless-upstream-direct"}
     ]}}
  ' > "${vless_outbound_server_config}")
  verification_capture_command "${vless_outbound_server_check}" \
    sing-box check -c "${vless_outbound_server_config}"
  sing-box run -c "${vless_outbound_server_config}" \
    > "${vless_outbound_server_stdout}" \
    2> "${vless_outbound_server_stderr}" &
  vless_outbound_server_pid=$!
  for _ in {1..50}; do
    if verification_port_is_listening "${vless_outbound_server_port}"; then
      break
    fi
    kill -0 "${vless_outbound_server_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_assert_port_listening "${vless_outbound_server_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-upstream.ss-lntp.txt"
  (umask 077; jq -n \
    --arg domain "${vless_outbound_target_domain}" \
    --arg uuid "${vless_outbound_server_uuid}" \
    --argjson server_port "${vless_outbound_server_port}" \
    --argjson udp_marker_port "${direct_udp_marker_port}" '
    {id:"vless-outbound-verification",role:"outbound",type:"vless",
     tag:"vless-outbound-verification",enabled:true,
     route_rules:[
       {inbound:["socks-in"],domain:[$domain],action:"route",
        outbound:"vless-outbound-verification"},
       {inbound:["socks-in"],network:["udp"],port:$udp_marker_port,
        action:"route",outbound:"vless-outbound-verification"}
     ],
     config:{server:"127.0.0.1",server_port:$server_port,uuid:$uuid,
       flow:"",network:["tcp","udp"]}}
  ' > "${vless_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${vless_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-create.json"
  vless_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-create.json"
  [[ "${vless_outbound_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="vless" and .id=="vless-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-create.json" >/dev/null
  verification_mark_step vless-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${vless_outbound_target_domain}" \
    --arg uuid "${vless_outbound_server_uuid}" \
    --argjson server_port "${vless_outbound_server_port}" \
    --argjson udp_marker_port "${direct_udp_marker_port}" '
    ([.outbounds[] | select(.type == "vless" and
      .tag == "vless-outbound-verification" and .server == "127.0.0.1" and
      .server_port == $server_port and .uuid == $uuid and .flow == "" and
      .network == ["tcp","udp"])] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .domain == [$domain] and .action == "route" and
      .outbound == "vless-outbound-verification")] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .network == ["udp"] and .port == $udp_marker_port and
      .action == "route" and .outbound == "vless-outbound-verification")] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step vless-outbound-config-asserted
  vless_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-response.txt"
  vless_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-curl.stderr.txt"
  set +e
  curl --fail --silent --show-error --max-time 10 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${vless_outbound_target_domain}/" \
    > "$(verification_artifact_path "${vless_outbound_response}")" \
    2> "$(verification_artifact_path "${vless_outbound_curl_stderr}")"
  local vless_outbound_curl_status=$?
  set -e
  [[ "${vless_outbound_curl_status}" == 0 ]]
  grep -Fqx "${direct_marker}" \
    "$(verification_artifact_path "${vless_outbound_response}")"
  verification_mark_step vless-outbound-curl-complete

  # VLESS carries UDP through its XUDP packet encoding while keeping the
  # proxy outbound usable for TCP.  Build a minimal client from the rendered
  # managed outbound so the omitted packet_encoding retains sing-box's xudp
  # default; the upstream VLESS server routes this synthetic UDP port to the
  # existing loopback echo fixture.
  local vless_outbound_udp_client_config
  local vless_outbound_udp_client_check
  local vless_outbound_udp_client_stdout
  local vless_outbound_udp_client_stderr
  local vless_outbound_udp_response
  local vless_outbound_udp_response_path
  local vless_outbound_udp_marker
  local vless_outbound_udp_rendered
  local vless_outbound_udp_client_status=1
  vless_outbound_udp_client_config="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-udp-client.json"
  vless_outbound_udp_client_check="${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-udp-client.check.txt"
  vless_outbound_udp_client_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-udp-client.stdout.txt")
  vless_outbound_udp_client_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-udp-client.stderr.txt")
  vless_outbound_udp_response="${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-udp-response.txt"
  vless_outbound_udp_response_path=$(verification_artifact_path \
    "${vless_outbound_udp_response}")
  vless_outbound_udp_marker="sing-box-vps-vless-outbound-udp-loopback-ok-$(date +%s)-$$"
  vless_outbound_udp_rendered=$(jq -ce \
    '.outbounds[] | select(.tag == "vless-outbound-verification")' \
    /root/.sing-box-vps/runtime/config.json)
  (umask 077; jq -n --argjson outbound "${vless_outbound_udp_rendered}" '
    {log:{disabled:true},
     inbounds:[{type:"socks",tag:"vless-outbound-udp-probe-in",listen:"127.0.0.1",
       listen_port:19081}],
     outbounds:[($outbound | .tag = "vless-outbound-udp-probe")],
     route:{final:"vless-outbound-udp-probe"}}
  ' > "${vless_outbound_udp_client_config}")
  verification_capture_command "${vless_outbound_udp_client_check}" \
    sing-box check -c "${vless_outbound_udp_client_config}"
  jq -e --argjson base_revision "${base_revision}" '
    (.outbounds | length == 1) and
    (.outbounds[0].type == "vless" and
      .outbounds[0].network == ["tcp","udp"] and
      (.outbounds[0] | has("packet_encoding") | not)) and
    (.route.final == "vless-outbound-udp-probe")
  ' "${vless_outbound_udp_client_config}" >/dev/null
  sing-box run -c "${vless_outbound_udp_client_config}" \
    > "${vless_outbound_udp_client_stdout}" \
    2> "${vless_outbound_udp_client_stderr}" &
  vless_outbound_udp_client_pid=$!
  for _ in {1..50}; do
    if verification_ss_output | awk '$1 == "LISTEN" && $4 ~ /:19081$/ { found = 1 } END { exit(found ? 0 : 1) }'; then
      break
    fi
    kill -0 "${vless_outbound_udp_client_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_ss_output | awk '$1 == "LISTEN" && $4 ~ /:19081$/ { found = 1 } END { exit(found ? 0 : 1) }'
  set +e
  python3 - "${vless_outbound_udp_response_path}" \
    "${direct_udp_marker_port}" "${vless_outbound_udp_marker}" \
    > /dev/null 2> "${vless_outbound_udp_client_stderr}" <<'PY'
import pathlib
import socket
import struct
import sys

response_path, target_port_text, marker_text = sys.argv[1:]
target_port = int(target_port_text)
marker = marker_text.encode("ascii")

def recv_exact(conn, size):
    chunks = []
    received = 0
    while received < size:
        chunk = conn.recv(size - received)
        if not chunk:
            raise RuntimeError("SOCKS control connection closed")
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)

def read_address(conn, atyp):
    if atyp == 1:
        return socket.inet_ntoa(recv_exact(conn, 4))
    if atyp == 3:
        size = recv_exact(conn, 1)[0]
        return recv_exact(conn, size).decode("ascii")
    if atyp == 4:
        return socket.inet_ntop(socket.AF_INET6, recv_exact(conn, 16))
    raise RuntimeError("unsupported SOCKS address type")

def read_reply(conn):
    header = recv_exact(conn, 4)
    if header[0] != 5 or header[1] != 0:
        raise RuntimeError("SOCKS UDP ASSOCIATE failed")
    address = read_address(conn, header[3])
    port = struct.unpack("!H", recv_exact(conn, 2))[0]
    return address, port

with socket.create_connection(("127.0.0.1", 19081), timeout=5) as control:
    control.settimeout(5)
    control.sendall(b"\x05\x01\x00")
    if recv_exact(control, 2) != b"\x05\x00":
        raise RuntimeError("SOCKS no-auth negotiation failed")
    control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    relay_address, relay_port = read_reply(control)
    if relay_address in ("0.0.0.0", "::"):
        relay_address = "127.0.0.1"
    request = (b"\x00\x00\x00\x01" + socket.inet_aton("127.0.0.1") +
               struct.pack("!H", target_port) + marker)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(5)
        udp.sendto(request, (relay_address, relay_port))
        response, _source = udp.recvfrom(65535)
    if len(response) < 10 or response[:3] != b"\x00\x00\x00":
        raise RuntimeError("invalid SOCKS UDP response header")
    offset = 4
    if response[3] == 1:
        offset += 4
    elif response[3] == 3:
        offset += 1 + response[4]
    elif response[3] == 4:
        offset += 16
    else:
        raise RuntimeError("invalid SOCKS UDP response address type")
    offset += 2
    payload = response[offset:]
    if payload != marker:
        raise RuntimeError("VLESS UDP marker mismatch")
    pathlib.Path(response_path).write_bytes(payload)
PY
  vless_outbound_udp_client_status=$?
  set -e
  [[ "${vless_outbound_udp_client_status}" == 0 ]]
  grep -Fqx "${vless_outbound_udp_marker}" "${vless_outbound_udp_response_path}"
  verification_mark_step vless-outbound-udp-probe-complete
  verification_case_stop_pid vless_outbound_udp_client_pid

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id vless-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-delete.json"
  vless_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-delete.json"
  [[ "${vless_outbound_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and
    .id=="vless-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-outbound-delete.json" >/dev/null
  verification_mark_step vless-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "vless-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "vless-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_case_stop_pid vless_outbound_server_pid
  rm -rf -- "${vless_outbound_server_dir}"
  vless_outbound_server_dir=''
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/vless-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["vless-outbound-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound.result.env" \
    'COMPONENT=vless-outbound' 'RESULT=success' \
    'DATA_PLANE=vless_tcp_loopback' 'UPSTREAM=vless_loopback_server'
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/vless-outbound-udp.result.env" \
    'COMPONENT=vless-outbound' 'RESULT=success' \
    'DATA_PLANE=vless_udp_xudp_loopback' 'UPSTREAM=vless_loopback_server' \
    'CLIENT_TRANSPORT=xudp'
}

verification_case_shadowtls_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # ShadowTLS outbound is a transport, so prove its real v3 handshake through
  # the typed HTTP detour that carries the application request.  The
  # disposable server uses the already-running certificate cover and sends
  # the authenticated stream into a Mixed inbound; only that inner listener's
  # route reaches the existing loopback marker.  This keeps the evidence
  # specific to ShadowTLS and does not mistake a standalone transport for a
  # complete proxy protocol.
  local shadowtls_outbound_server_config
  local shadowtls_outbound_server_stdout
  local shadowtls_outbound_server_stderr
  local shadowtls_outbound_server_check
  local shadowtls_outbound_target_domain='sbv-shadowtls-outbound.invalid'
  local shadowtls_outbound_server_port=1095
  local shadowtls_outbound_inner_port=1096
  local shadowtls_outbound_password='shadowtls-outbound-password'
  local shadowtls_outbound_server_ss_lntp
  local shadowtls_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-record.json"
  local shadowtls_outbound_http_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-record.json"
  local shadowtls_outbound_create_status=0
  local shadowtls_outbound_http_create_status=0
  local shadowtls_outbound_http_delete_status=0
  local shadowtls_outbound_delete_status=0
  local shadowtls_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-response.txt"
  local shadowtls_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-curl.stderr.txt"
  local shadowtls_outbound_journal="${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-journal.txt"
  local shadowtls_outbound_config
  local shadowtls_outbound_curl_status=1
  shadowtls_outbound_server_dir=$(mktemp -d /tmp/sing-box-vps-shadowtls-upstream.XXXXXX)
  shadowtls_outbound_server_config="${shadowtls_outbound_server_dir}/config.json"
  shadowtls_outbound_server_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-server.stdout.txt")
  shadowtls_outbound_server_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-server.stderr.txt")
  shadowtls_outbound_server_check="${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-server-check.txt"
  shadowtls_outbound_server_ss_lntp="${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-server.ss-lntp.txt"
  (umask 077; jq -n --arg domain "${shadowtls_outbound_target_domain}" \
    --argjson marker_port "${direct_marker_port}" \
    --argjson listen_port "${shadowtls_outbound_server_port}" \
    --argjson inner_port "${shadowtls_outbound_inner_port}" \
    --arg password "${shadowtls_outbound_password}" '
    {log:{level:"info"},
     inbounds:[
       {type:"shadowtls",tag:"shadowtls-outbound-server",listen:"127.0.0.1",
        listen_port:$listen_port,version:3,
        users:[{name:"shadowtls-outbound-user",password:$password}],
        handshake:{server:"127.0.0.1",server_port:1090},
        handshake_for_server_name:{},strict_mode:false,wildcard_sni:"off",
        detour:"shadowtls-outbound-inner"},
       {type:"mixed",tag:"shadowtls-outbound-inner",listen:"127.0.0.1",
        listen_port:$inner_port}],
     outbounds:[{type:"direct",tag:"shadowtls-outbound-direct"}],
     route:{rules:[{inbound:["shadowtls-outbound-inner"],domain:[$domain],
       action:"route",outbound:"shadowtls-outbound-direct",
       override_address:"127.0.0.1",override_port:$marker_port}]}}
  ' > "${shadowtls_outbound_server_config}")
  verification_capture_command "${shadowtls_outbound_server_check}" \
    sing-box check -c "${shadowtls_outbound_server_config}"
  sing-box run -c "${shadowtls_outbound_server_config}" \
    > "${shadowtls_outbound_server_stdout}" \
    2> "${shadowtls_outbound_server_stderr}" &
  shadowtls_outbound_server_pid=$!
  for _ in {1..50}; do
    if verification_port_is_listening "${shadowtls_outbound_server_port}"; then
      break
    fi
    kill -0 "${shadowtls_outbound_server_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_assert_port_listening "${shadowtls_outbound_server_port}" \
    "${shadowtls_outbound_server_ss_lntp}"

  (umask 077; jq -n --arg password "${shadowtls_outbound_password}" '
    {id:"shadowtls-outbound-verification",role:"outbound",type:"shadowtls",
     tag:"shadowtls-outbound-verification",enabled:true,route_rules:[],
     config:{server:"127.0.0.1",server_port:1095,version:3,password:$password,
       tls:{enabled:true,server_name:"sing-box-vps-verification.invalid",insecure:true}}}
  ' > "${shadowtls_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${shadowtls_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-create.json"
  shadowtls_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-create.json"
  [[ "${shadowtls_outbound_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="shadowtls" and .id=="shadowtls-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-create.json" >/dev/null
  verification_mark_step shadowtls-outbound-component-created

  (umask 077; jq -n --arg domain "${shadowtls_outbound_target_domain}" \
    --argjson inner_port "${shadowtls_outbound_inner_port}" '
    {id:"shadowtls-outbound-http",role:"outbound",type:"http",
     tag:"shadowtls-outbound-http",enabled:true,
     route_rules:[{inbound:["socks-in"],domain:[$domain],action:"route",
       outbound:"shadowtls-outbound-http"}],
     config:{server:"127.0.0.1",server_port:$inner_port,
       detour:"shadowtls-outbound-verification"}}
  ' > "${shadowtls_outbound_http_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 1))" --file "${shadowtls_outbound_http_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-create.json"
  shadowtls_outbound_http_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-http-create.json"
  [[ "${shadowtls_outbound_http_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 2) and
    .type=="http" and .id=="shadowtls-outbound-http"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-create.json" >/dev/null
  verification_mark_step shadowtls-outbound-http-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  shadowtls_outbound_config=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${shadowtls_outbound_config}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${shadowtls_outbound_target_domain}" \
    --argjson inner_port "${shadowtls_outbound_inner_port}" '
    ([.outbounds[] | select(.type == "shadowtls" and
      .tag == "shadowtls-outbound-verification" and .server == "127.0.0.1" and
      .server_port == 1095 and .version == 3 and
      .password == "shadowtls-outbound-password" and
      .tls.server_name == "sing-box-vps-verification.invalid" and
      .tls.insecure == true)] | length == 1) and
    ([.outbounds[] | select(.type == "http" and
      .tag == "shadowtls-outbound-http" and .server == "127.0.0.1" and
      .server_port == $inner_port and
      .detour == "shadowtls-outbound-verification")] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .domain == [$domain] and .action == "route" and
      .outbound == "shadowtls-outbound-http")] | length == 1)
  ' "${shadowtls_outbound_config}" >/dev/null
  verification_mark_step shadowtls-outbound-config-asserted
  set +e
  curl --fail --silent --show-error --max-time 15 --noproxy '' \
    --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
    "http://${shadowtls_outbound_target_domain}/" \
    > "$(verification_artifact_path "${shadowtls_outbound_response}")" \
    2> "$(verification_artifact_path "${shadowtls_outbound_curl_stderr}")"
  shadowtls_outbound_curl_status=$?
  set -e
  [[ "${shadowtls_outbound_curl_status}" == 0 ]]
  grep -Fqx "${direct_marker}" \
    "$(verification_artifact_path "${shadowtls_outbound_response}")"
  for _ in {1..20}; do
    if grep -Fq 'inbound/shadowtls[shadowtls-outbound-server]' \
      "${shadowtls_outbound_server_stderr}" && \
      grep -Fq 'inbound/mixed[shadowtls-outbound-inner]' \
      "${shadowtls_outbound_server_stderr}"; then
      break
    fi
    sleep 0.1
  done
  grep -Fq 'inbound/shadowtls[shadowtls-outbound-server]' \
    "${shadowtls_outbound_server_stderr}"
  grep -Fq 'inbound/mixed[shadowtls-outbound-inner]' \
    "${shadowtls_outbound_server_stderr}"
  verification_capture_command "${shadowtls_outbound_journal}" \
    journalctl -u sing-box --no-pager -n 300
  # The HTTP detour owns the application dial log; the ShadowTLS transport
  # itself is evidenced by the server-side handshake logs above.
  grep -Fq 'outbound/http[shadowtls-outbound-http]' \
    "$(verification_artifact_path "${shadowtls_outbound_journal}")"
  verification_mark_step shadowtls-outbound-curl-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 2))" --id shadowtls-outbound-http \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-delete.json"
  shadowtls_outbound_http_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-http-delete.json"
  [[ "${shadowtls_outbound_http_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 3) and
    .id=="shadowtls-outbound-http"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-http-delete.json" >/dev/null
  verification_mark_step shadowtls-outbound-http-component-deleted
  jq -e --argjson base_revision "${base_revision}" --arg domain "${shadowtls_outbound_target_domain}" '
    ([.outbounds[] | select(.tag == "shadowtls-outbound-http")] | length == 0) and
    ([.route.rules[] | select(.outbound == "shadowtls-outbound-http" or
      .domain == [$domain])] | length == 0) and
    ([.outbounds[] | select(.tag == "shadowtls-outbound-verification")] | length == 1)
  ' /root/.sing-box-vps/runtime/config.json >/dev/null

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 3))" --id shadowtls-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-delete.json"
  shadowtls_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound-delete.json"
  [[ "${shadowtls_outbound_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 4) and
    .id=="shadowtls-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-outbound-delete.json" >/dev/null
  verification_mark_step shadowtls-outbound-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "shadowtls-outbound-verification")] | length == 0) and
    ([.route.rules[] | select(.outbound == "shadowtls-outbound-verification")] | length == 0)
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_case_stop_pid shadowtls_outbound_server_pid
  rm -rf -- "${shadowtls_outbound_server_dir}"
  shadowtls_outbound_server_dir=''
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["shadowtls-outbound-http","shadowtls-outbound-verification"]' '
    .revision==($base_revision + 4) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-outbound.result.env" \
    'COMPONENT=shadowtls-outbound' 'RESULT=success' \
    'DATA_PLANE=shadowtls_tcp_composite' 'UPSTREAM=shadowtls_v3_loopback'
}

verification_case_shadowsocks_udp_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # The typed Shadowsocks outbound also has a native UDP mode.  Reuse the
  # existing SS2022 inbound as the encrypted upstream and the direct UDP echo
  # marker as its destination.  A real authenticated UDP ASSOCIATE through
  # the managed SOCKS ingress proves the component's UDP network selection and
  # route ownership instead of only checking a rendered network array.
  local shadowsocks_outbound_udp_record
  local shadowsocks_outbound_udp_config
  local shadowsocks_outbound_udp_response
  local shadowsocks_outbound_udp_response_path
  local shadowsocks_outbound_udp_client_stderr
  local shadowsocks_outbound_udp_journal
  local shadowsocks_outbound_udp_create_status=0
  local shadowsocks_outbound_udp_delete_status=0
  local shadowsocks_outbound_udp_client_status=1
  shadowsocks_outbound_udp_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-record.json"
  shadowsocks_outbound_udp_response="${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-response.txt"
  shadowsocks_outbound_udp_response_path=$(verification_artifact_path \
    "${shadowsocks_outbound_udp_response}")
  shadowsocks_outbound_udp_client_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-client.stderr.txt"
  shadowsocks_outbound_udp_journal="${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-journal.txt"
  (umask 077; jq -n --argjson marker_port "${direct_udp_marker_port}" '
    {id:"shadowsocks-outbound-udp-verification",role:"outbound",type:"shadowsocks",
     tag:"shadowsocks-outbound-udp-verification",enabled:true,
     route_rules:[{inbound:["socks-in"],network:["udp"],port:$marker_port,
       action:"route",outbound:"shadowsocks-outbound-udp-verification"}],
     config:{server:"127.0.0.1",server_port:1083,
       method:"2022-blake3-aes-128-gcm",password:"MDEyMzQ1Njc4OWFiY2RlZg==",
       network:["udp"]}}
  ' > "${shadowsocks_outbound_udp_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${shadowsocks_outbound_udp_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-create.json"
  shadowsocks_outbound_udp_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-create.json"
  [[ "${shadowsocks_outbound_udp_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="shadowsocks" and .id=="shadowsocks-outbound-udp-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-create.json" >/dev/null
  verification_mark_step shadowsocks-outbound-udp-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  shadowsocks_outbound_udp_config=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${shadowsocks_outbound_udp_config}"
  jq -e --argjson base_revision "${base_revision}" --argjson marker_port "${direct_udp_marker_port}" '
    ([.outbounds[] | select(.type == "shadowsocks" and
      .tag == "shadowsocks-outbound-udp-verification" and
      .server == "127.0.0.1" and .server_port == 1083 and
      .method == "2022-blake3-aes-128-gcm" and
      .password == "MDEyMzQ1Njc4OWFiY2RlZg==" and .network == ["udp"])] |
      length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .network == ["udp"] and .port == $marker_port and
      .outbound == "shadowsocks-outbound-udp-verification")] | length == 1)
  ' "${shadowsocks_outbound_udp_config}" >/dev/null
  verification_mark_step shadowsocks-outbound-udp-config-asserted
  rm -f -- "${shadowsocks_outbound_udp_response_path}" \
    "$(verification_artifact_path "${shadowsocks_outbound_udp_client_stderr}")"
  set +e
  python3 - "${shadowsocks_outbound_udp_response_path}" \
    "${direct_udp_marker}" "${direct_udp_marker_port}" \
    > /dev/null \
    2> "$(verification_artifact_path "${shadowsocks_outbound_udp_client_stderr}")" <<'PY'
import pathlib
import socket
import struct
import sys

response_path, marker_text, target_port_text = sys.argv[1:]
marker = marker_text.encode("ascii")
target_port = int(target_port_text)

def recv_exact(conn, size):
    chunks = []
    received = 0
    while received < size:
        chunk = conn.recv(size - received)
        if not chunk:
            raise RuntimeError("SOCKS control connection closed")
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)

def read_address(conn, address_type):
    if address_type == 1:
        return socket.inet_ntoa(recv_exact(conn, 4))
    if address_type == 3:
        size = recv_exact(conn, 1)[0]
        return recv_exact(conn, size).decode("ascii")
    if address_type == 4:
        return socket.inet_ntop(socket.AF_INET6, recv_exact(conn, 16))
    raise RuntimeError("unsupported SOCKS address type")

username = b"socks-user"
password = b"socks-pass"
with socket.create_connection(("127.0.0.1", 1081), timeout=5) as control:
    control.settimeout(5)
    control.sendall(b"\x05\x01\x02")
    if recv_exact(control, 2) != b"\x05\x02":
        raise RuntimeError("SOCKS username/password method was not selected")
    control.sendall(b"\x01" + bytes([len(username)]) + username +
                   bytes([len(password)]) + password)
    if recv_exact(control, 2) != b"\x01\x00":
        raise RuntimeError("SOCKS authentication failed")
    control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    reply = recv_exact(control, 4)
    if reply[:2] != b"\x05\x00":
        raise RuntimeError("SOCKS UDP ASSOCIATE failed")
    relay_host = read_address(control, reply[3])
    relay_port = struct.unpack("!H", recv_exact(control, 2))[0]
    if relay_host in ("0.0.0.0", "::"):
        relay_host = "127.0.0.1"
    request = (b"\x00\x00\x00\x01" + socket.inet_aton("127.0.0.1") +
               struct.pack("!H", target_port) + marker)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(10)
        udp.sendto(request, (relay_host, relay_port))
        response, _source = udp.recvfrom(65535)
    if len(response) < 10 or response[:3] != b"\x00\x00\x00":
        raise RuntimeError("invalid SOCKS UDP response header")
    offset = 4
    if response[3] == 1:
        offset += 4
    elif response[3] == 3:
        offset += 1 + response[4]
    elif response[3] == 4:
        offset += 16
    else:
        raise RuntimeError("invalid SOCKS UDP response address type")
    offset += 2
    payload = response[offset:]
    if payload != marker:
        raise RuntimeError("UDP marker mismatch")
pathlib.Path(response_path).write_bytes(payload)
PY
  shadowsocks_outbound_udp_client_status=$?
  set -e
  [[ "${shadowsocks_outbound_udp_client_status}" == 0 ]]
  grep -Fqx "${direct_udp_marker}" "${shadowsocks_outbound_udp_response_path}"
  for _ in {1..20}; do
    verification_capture_command "${shadowsocks_outbound_udp_journal}" \
      journalctl -u sing-box --no-pager -n 300
    if grep -Fq 'outbound/shadowsocks[shadowsocks-outbound-udp-verification]' \
      "$(verification_artifact_path "${shadowsocks_outbound_udp_journal}")" && \
      grep -Fq 'inbound/shadowsocks[ss-in]' \
      "$(verification_artifact_path "${shadowsocks_outbound_udp_journal}")"; then
      break
    fi
    sleep 0.1
  done
  grep -Fq 'outbound/shadowsocks[shadowsocks-outbound-udp-verification]' \
    "$(verification_artifact_path "${shadowsocks_outbound_udp_journal}")"
  grep -Fq 'inbound/shadowsocks[ss-in]' \
    "$(verification_artifact_path "${shadowsocks_outbound_udp_journal}")"
  verification_mark_step shadowsocks-outbound-udp-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id shadowsocks-outbound-udp-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-delete.json"
  shadowsocks_outbound_udp_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp-delete.json"
  [[ "${shadowsocks_outbound_udp_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and
    .id=="shadowsocks-outbound-udp-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-udp-delete.json" >/dev/null
  verification_mark_step shadowsocks-outbound-udp-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "shadowsocks-outbound-udp-verification")] |
      length) == 0 and
    ([.route.rules[] | select(.outbound ==
      "shadowsocks-outbound-udp-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks_udp-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["shadowsocks-outbound-udp-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-udp.result.env" \
    'COMPONENT=shadowsocks-outbound-udp' 'RESULT=success' \
    'DATA_PLANE=shadowsocks2022_udp_loopback' 'AUTHENTICATION=ss2022_psk'
}

verification_case_socks_udp_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  # SOCKS outbound UDP is a separate upstream contract from SS2022 UDP.  A
  # disposable SOCKS5 server below implements UDP ASSOCIATE and relays only
  # the exact marker to the direct UDP echo.  This keeps the proof inside the
  # verification container while observing both upstream authentication and
  # the managed outbound's native UDP path.
  local socks_outbound_udp_upstream_port_file
  local socks_outbound_udp_upstream_stdout
  local socks_outbound_udp_upstream_stderr
  local socks_outbound_udp_upstream_request_log
  local socks_outbound_udp_upstream_port
  local socks_outbound_udp_upstream_user=socks-udp-upstream-user
  local socks_outbound_udp_upstream_password=socks-udp-upstream-pass
  local socks_outbound_udp_record
  local socks_outbound_udp_config
  local socks_outbound_udp_response
  local socks_outbound_udp_response_path
  local socks_outbound_udp_client_stderr
  local socks_outbound_udp_journal
  local socks_outbound_udp_marker
  local socks_outbound_udp_create_status=0
  local socks_outbound_udp_delete_status=0
  local socks_outbound_udp_client_status=1
  local socks_outbound_udp_upstream_dir="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp"
  local socks_outbound_udp_target_domain=sbv-socks-outbound-udp.invalid
  socks_outbound_udp_upstream_port_file="${socks_outbound_udp_upstream_dir}/port"
  socks_outbound_udp_upstream_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-upstream.stdout.txt")
  socks_outbound_udp_upstream_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-upstream.stderr.txt")
  socks_outbound_udp_upstream_request_log=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-upstream.request.txt")
  socks_outbound_udp_record="${socks_outbound_udp_upstream_dir}/record.json"
  socks_outbound_udp_response="${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-response.txt"
  socks_outbound_udp_response_path=$(verification_artifact_path \
    "${socks_outbound_udp_response}")
  socks_outbound_udp_client_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-client.stderr.txt"
  socks_outbound_udp_journal="${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-journal.txt"
  socks_outbound_udp_marker="sing-box-vps-socks-outbound-udp-loopback-ok-$(date +%s)-$$"
  mkdir -p "${socks_outbound_udp_upstream_dir}"
  python3 - "${socks_outbound_udp_upstream_port_file}" \
    "${direct_udp_marker_port}" "${socks_outbound_udp_upstream_user}" \
    "${socks_outbound_udp_upstream_password}" \
    "${socks_outbound_udp_upstream_request_log}" "${socks_outbound_udp_marker}" \
    > "${socks_outbound_udp_upstream_stdout}" \
    2> "${socks_outbound_udp_upstream_stderr}" <<'PY' &
import pathlib
import select
import socket
import socketserver
import struct
import sys

port_file, target_port_text, expected_user, expected_password, request_log, marker = sys.argv[1:]
target_port = int(target_port_text)
marker_bytes = marker.encode("ascii")


def recv_exact(conn, size):
    data = bytearray()
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise ConnectionError("short SOCKS5 frame")
        data.extend(chunk)
    return bytes(data)


def read_tcp_address(conn, address_type):
    if address_type == 1:
        return socket.inet_ntoa(recv_exact(conn, 4))
    if address_type == 3:
        size = recv_exact(conn, 1)[0]
        return recv_exact(conn, size).decode("idna")
    if address_type == 4:
        return socket.inet_ntop(socket.AF_INET6, recv_exact(conn, 16))
    raise ValueError("unsupported SOCKS5 address type")


def read_udp_address(packet, offset, address_type):
    if address_type == 1:
        if len(packet) < offset + 4:
            raise ValueError("short IPv4 UDP address")
        return socket.inet_ntoa(packet[offset:offset + 4]), offset + 4
    if address_type == 3:
        if len(packet) < offset + 1:
            raise ValueError("short domain UDP address")
        size = packet[offset]
        offset += 1
        if len(packet) < offset + size:
            raise ValueError("short domain UDP address")
        return packet[offset:offset + size].decode("idna"), offset + size
    if address_type == 4:
        if len(packet) < offset + 16:
            raise ValueError("short IPv6 UDP address")
        return socket.inet_ntop(socket.AF_INET6, packet[offset:offset + 16]), offset + 16
    raise ValueError("unsupported UDP address type")


def append_log(*lines):
    with open(request_log, "a", encoding="ascii") as stream:
        for line in lines:
            stream.write(line + "\n")


class SocksUdpHandler(socketserver.BaseRequestHandler):
    def handle(self):
        control = self.request
        control.settimeout(5)
        relay = None
        try:
            if recv_exact(control, 1) != b"\x05":
                return
            method_count = recv_exact(control, 1)[0]
            methods = recv_exact(control, method_count)
            if 2 not in methods:
                control.sendall(b"\x05\xff")
                return
            control.sendall(b"\x05\x02")
            if recv_exact(control, 1) != b"\x01":
                return
            user_length = recv_exact(control, 1)[0]
            user = recv_exact(control, user_length).decode("utf-8")
            password_length = recv_exact(control, 1)[0]
            password = recv_exact(control, password_length).decode("utf-8")
            if user != expected_user or password != expected_password:
                control.sendall(b"\x01\x01")
                return
            control.sendall(b"\x01\x00")
            append_log("AUTHENTICATED")

            version, command, _, address_type = recv_exact(control, 4)
            if version != 5 or command != 3:
                control.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
                return
            requested_host = read_tcp_address(control, address_type)
            requested_port = int.from_bytes(recv_exact(control, 2), "big")

            relay = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            relay.bind(("127.0.0.1", 0))
            relay.settimeout(5)
            relay_port = relay.getsockname()[1]
            control.sendall(b"\x05\x00\x00\x01" + socket.inet_aton("127.0.0.1") +
                            struct.pack("!H", relay_port))
            append_log("UDP_ASSOCIATE", "ASSOCIATE_TARGET=%s:%s" %
                       (requested_host, requested_port))

            while True:
                # sing-box may release the short-lived control connection as
                # soon as its packet connection is established.  Keep the
                # disposable relay alive until the UDP marker arrives so the
                # probe observes the data plane rather than treating control
                # connection EOF as a failed upstream.
                ready, _, _ = select.select([relay], [], [], 5)
                if not ready:
                    continue
                packet, client_address = relay.recvfrom(65535)
                if len(packet) < 4 or packet[:2] != b"\x00\x00" or packet[2] != 0:
                    continue
                udp_address_type = packet[3]
                destination, offset = read_udp_address(packet, 4, udp_address_type)
                if len(packet) < offset + 2:
                    continue
                destination_port = int.from_bytes(packet[offset:offset + 2], "big")
                payload = packet[offset + 2:]
                if destination != "127.0.0.1" or destination_port != target_port:
                    raise ValueError("unexpected UDP destination")
                if payload != marker_bytes:
                    raise ValueError("unexpected UDP payload")
                append_log("DESTINATION=%s:%s" % (destination, destination_port),
                           "PAYLOAD=%s" % marker)
                relay.sendto(payload, ("127.0.0.1", target_port))
                response, _ = relay.recvfrom(65535)
                response_header = (b"\x00\x00\x00\x01" +
                                   socket.inet_aton("127.0.0.1") +
                                   struct.pack("!H", target_port))
                relay.sendto(response_header + response, client_address)
        except (ConnectionError, OSError, UnicodeError, ValueError):
            return
        finally:
            if relay is not None:
                relay.close()


class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


with ReusableServer(("127.0.0.1", 0), SocksUdpHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  socks_udp_upstream_pid=$!
  for _ in {1..50}; do
    [[ -s "${socks_outbound_udp_upstream_port_file}" ]] && break
    kill -0 "${socks_udp_upstream_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${socks_outbound_udp_upstream_port_file}" ]]
  socks_outbound_udp_upstream_port=$(cat "${socks_outbound_udp_upstream_port_file}")
  [[ "${socks_outbound_udp_upstream_port}" =~ ^[0-9]+$ ]]

  (umask 077; jq -n --argjson upstream_port "${socks_outbound_udp_upstream_port}" \
    --arg domain "${socks_outbound_udp_target_domain}" \
    --argjson marker_port "${direct_udp_marker_port}" '
    {id:"socks-outbound-udp-verification",role:"outbound",type:"socks",
     tag:"socks-outbound-udp-verification",enabled:true,
     route_rules:[{inbound:["socks-in"],network:["udp"],port:$marker_port,
       action:"route",outbound:"socks-outbound-udp-verification"}],
     config:{server:"127.0.0.1",server_port:$upstream_port,version:"5",
       username:"socks-udp-upstream-user",password:"socks-udp-upstream-pass",
       network:["udp"]}}
  ' > "${socks_outbound_udp_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${socks_outbound_udp_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp-create.json"
  socks_outbound_udp_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-create.json"
  [[ "${socks_outbound_udp_create_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="create" and .revision==($base_revision + 1) and
    .type=="socks" and .id=="socks-outbound-udp-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp-create.json" >/dev/null
  verification_mark_step socks-outbound-udp-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  socks_outbound_udp_config=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${socks_outbound_udp_config}"
  jq -e --argjson base_revision "${base_revision}" --arg domain "${socks_outbound_udp_target_domain}" \
    --argjson upstream_port "${socks_outbound_udp_upstream_port}" \
    --argjson marker_port "${direct_udp_marker_port}" '
    ([.outbounds[] | select(.type == "socks" and
      .tag == "socks-outbound-udp-verification" and
      .server == "127.0.0.1" and .server_port == $upstream_port and
      .version == "5" and .username == "socks-udp-upstream-user" and
      .password == "socks-udp-upstream-pass" and .network == ["udp"])] |
      length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .network == ["udp"] and .port == $marker_port and
      .outbound == "socks-outbound-udp-verification")] | length == 1)
  ' "${socks_outbound_udp_config}" >/dev/null
  verification_mark_step socks-outbound-udp-config-asserted
  rm -f -- "${socks_outbound_udp_response_path}" \
    "$(verification_artifact_path "${socks_outbound_udp_client_stderr}")"
  set +e
  python3 - "${socks_outbound_udp_response_path}" \
    "${socks_outbound_udp_marker}" "${direct_udp_marker_port}" \
    > /dev/null \
    2> "$(verification_artifact_path "${socks_outbound_udp_client_stderr}")" <<'PY'
import pathlib
import socket
import struct
import sys

response_path, marker_text, target_port_text = sys.argv[1:]
marker = marker_text.encode("ascii")
target_port = int(target_port_text)


def recv_exact(conn, size):
    chunks = []
    received = 0
    while received < size:
        chunk = conn.recv(size - received)
        if not chunk:
            raise RuntimeError("SOCKS control connection closed")
        chunks.append(chunk)
        received += len(chunk)
    return b"".join(chunks)


def read_address(conn, address_type):
    if address_type == 1:
        return socket.inet_ntoa(recv_exact(conn, 4))
    if address_type == 3:
        size = recv_exact(conn, 1)[0]
        return recv_exact(conn, size).decode("ascii")
    if address_type == 4:
        return socket.inet_ntop(socket.AF_INET6, recv_exact(conn, 16))
    raise RuntimeError("unsupported SOCKS address type")


username = b"socks-user"
password = b"socks-pass"
with socket.create_connection(("127.0.0.1", 1081), timeout=5) as control:
    control.settimeout(5)
    control.sendall(b"\x05\x01\x02")
    if recv_exact(control, 2) != b"\x05\x02":
        raise RuntimeError("SOCKS username/password method was not selected")
    control.sendall(b"\x01" + bytes([len(username)]) + username +
                   bytes([len(password)]) + password)
    if recv_exact(control, 2) != b"\x01\x00":
        raise RuntimeError("SOCKS authentication failed")
    control.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
    reply = recv_exact(control, 4)
    if reply[:2] != b"\x05\x00":
        raise RuntimeError("SOCKS UDP ASSOCIATE failed")
    relay_host = read_address(control, reply[3])
    relay_port = struct.unpack("!H", recv_exact(control, 2))[0]
    if relay_host in ("0.0.0.0", "::"):
        relay_host = "127.0.0.1"
    request = (b"\x00\x00\x00\x01" + socket.inet_aton("127.0.0.1") +
               struct.pack("!H", target_port) + marker)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(10)
        udp.sendto(request, (relay_host, relay_port))
        response, _source = udp.recvfrom(65535)
    if len(response) < 10 or response[:3] != b"\x00\x00\x00":
        raise RuntimeError("invalid SOCKS UDP response header")
    offset = 4
    if response[3] == 1:
        offset += 4
    elif response[3] == 3:
        offset += 1 + response[4]
    elif response[3] == 4:
        offset += 16
    else:
        raise RuntimeError("invalid SOCKS UDP response address type")
    offset += 2
    payload = response[offset:]
    if payload != marker:
        raise RuntimeError("UDP marker mismatch")
pathlib.Path(response_path).write_bytes(payload)
PY
  socks_outbound_udp_client_status=$?
  set -e
  [[ "${socks_outbound_udp_client_status}" == 0 ]]
  grep -Fqx "${socks_outbound_udp_marker}" "${socks_outbound_udp_response_path}"
  grep -Fqx 'AUTHENTICATED' "${socks_outbound_udp_upstream_request_log}"
  grep -Fqx 'UDP_ASSOCIATE' "${socks_outbound_udp_upstream_request_log}"
  grep -Fqx "DESTINATION=127.0.0.1:${direct_udp_marker_port}" \
    "${socks_outbound_udp_upstream_request_log}"
  grep -Fqx "PAYLOAD=${socks_outbound_udp_marker}" \
    "${socks_outbound_udp_upstream_request_log}"
  verification_mark_step socks-outbound-udp-complete
  for _ in {1..20}; do
    verification_capture_command "${socks_outbound_udp_journal}" \
      journalctl -u sing-box --no-pager -n 300
    if grep -Fq 'outbound/socks[socks-outbound-udp-verification]' \
      "$(verification_artifact_path "${socks_outbound_udp_journal}")"; then
      break
    fi
    sleep 0.1
  done
  grep -Fq 'outbound/socks[socks-outbound-udp-verification]' \
    "$(verification_artifact_path "${socks_outbound_udp_journal}")"

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id socks-outbound-udp-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp-delete.json"
  socks_outbound_udp_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp-delete.json"
  [[ "${socks_outbound_udp_delete_status}" == 0 ]]
  jq -e --argjson base_revision "${base_revision}" '.ok==true and .operation=="delete" and .revision==($base_revision + 2) and
    .id=="socks-outbound-udp-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-udp-delete.json" >/dev/null
  verification_mark_step socks-outbound-udp-component-deleted
  jq -e --argjson base_revision "${base_revision}" '
    ([.outbounds[] | select(.tag == "socks-outbound-udp-verification")] |
      length) == 0 and
    ([.route.rules[] | select(.outbound ==
      "socks-outbound-udp-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_case_stop_pid socks_udp_upstream_pid
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/socks_udp-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e --argjson base_revision "${base_revision}" --argjson removed_ids '["socks-outbound-udp-verification"]' '
    .revision==($base_revision + 2) and
    all(.components[]; .id as $id | ($removed_ids | index($id)) == null)
  ' /root/.sing-box-vps/runtime/components.json >/dev/null
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-udp.result.env" \
    'COMPONENT=socks-outbound-udp' 'RESULT=success' \
    'DATA_PLANE=socks5_native_udp_loopback' \
    'AUTHENTICATION=upstream_username_password'
}

verification_case_http_outbound() {
  local base_revision=${1:?expected component revision required}
  local lifecycle=${2:?delete or retain required}
  [[ "${base_revision}" =~ ^(0|[1-9][0-9]*)$ ]] || return 2
  case "${lifecycle}" in delete|retain) ;; *) return 2 ;; esac
  local config_file=/root/.sing-box-vps/runtime/config.json
  local state_file=/root/.sing-box-vps/runtime/components.json
  local component_id=atomic-http-outbound
  local target_domain=sbv-atomic-http-outbound.invalid
  local marker="sing-box-vps-atomic-http-$(date +%s)-$$"
  local ports_file record create_result delete_result response requests proxy_port _

  ports_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-upstream-ports.json"
  record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-record.json"
  create_result=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/create.json")
  delete_result=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/delete.json")
  response=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/response.txt")
  requests=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/proxy.request.txt")
  verification_atomic_http_fixture "${ports_file}" "${marker}" "${target_domain}" "${requests}" \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/upstream.stdout.txt")" \
    2> "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/upstream.stderr.txt")" &
  http_outbound_proxy_pid=$!
  for _ in {1..50}; do
    [[ -s "${ports_file}" ]] && break
    kill -0 "${http_outbound_proxy_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  proxy_port=$(jq -er '.proxy | select(type=="number" and .>0 and .<65536)' "${ports_file}")
  jq -n --arg id "${component_id}" --arg domain "${target_domain}" --argjson port "${proxy_port}" '
    {id:$id,role:"outbound",type:"http",tag:$id,enabled:true,
      route_rules:[{inbound:["socks-in"],domain:[$domain],action:"route",outbound:$id}],
      config:{server:"127.0.0.1",server_port:$port,username:"proxy-user",password:"proxy-pass",
        headers:{"X-SBV-Proxy":"http-outbound"},connect_timeout:"5s"}}' > "${record}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 0))" --file "${record}" > "${create_result}"
  jq -e --argjson base_revision "${base_revision}" --arg id "${component_id}" '.ok==true and .operation=="create" and
    .revision==($base_revision + 1) and .type=="http" and .id==$id' "${create_result}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/created-check.txt" sing-box check -c "${config_file}"
  verification_capture_file_if_present "${config_file}" "${VERIFY_CURRENT_SCENARIO_DIR}/created-config.json"
  jq -e --argjson base_revision "${base_revision}" --arg id "${component_id}" --arg domain "${target_domain}" --argjson port "${proxy_port}" '
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
  jq -e --argjson base_revision "${base_revision}" --arg id "${component_id}" '
    .revision==($base_revision + 1) and
    any(.components[]; .id==$id and .role=="outbound" and .type=="http")
  ' "${state_file}" >/dev/null
  verification_mark_step authenticated-http-marker-complete
  if [[ "${lifecycle}" == retain ]]; then
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound.result.env" \
      'COMPONENT=http-outbound' 'RESULT=success' 'DATA_PLANE=authenticated_http_proxy_loopback' \
      'LIFECYCLE=create_retain' "REVISIONS=${base_revision},$((base_revision + 1))"
    return 0
  fi

  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id "${component_id}" > "${delete_result}"
  jq -e --argjson base_revision "${base_revision}" --arg id "${component_id}" '.ok==true and .operation=="delete" and
    .revision==($base_revision + 2) and .id==$id' "${delete_result}" >/dev/null
  jq -e --argjson base_revision "${base_revision}" --arg id "${component_id}" '
    .revision==($base_revision + 2) and all(.components[]; .id!=$id)
  ' "${state_file}" >/dev/null
  jq -e --argjson base_revision "${base_revision}" --arg id "${component_id}" '
    all(.outbounds[]; .tag!=$id) and all(.route.rules[]?; .outbound!=$id)
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/deleted-check.txt" sing-box check -c "${config_file}"
  verification_mark_step http-component-and-route-deleted
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound.result.env" \
    'COMPONENT=http-outbound' 'RESULT=success' 'DATA_PLANE=authenticated_http_proxy_loopback' \
    'LIFECYCLE=create_delete' "REVISIONS=${base_revision},$((base_revision + 1)),$((base_revision + 2))"
}
