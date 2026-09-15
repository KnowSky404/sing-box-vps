verification_config_inbound_type_for_protocol() {
  verification_protocol_metadata "$1" | jq -er '.type'
}

verification_config_inbound_port_for_protocol() {
  local protocol=$1
  local config_file=$2
  local config_type

  config_type=$(verification_config_inbound_type_for_protocol "${protocol}")
  if [[ "${protocol}" == "mixed" ]]; then
    jq -er --arg config_type "${config_type}" '
      [.inbounds[] | select(.type == $config_type and
        ((.tag // "") | startswith("shadowtls-inner-") | not))][0].listen_port
    ' "${config_file}"
    return 0
  fi

  jq -er --arg config_type "${config_type}" '
    [.inbounds[] | select(.type == $config_type)][0].listen_port
  ' "${config_file}"
}

verification_config_inbound_network_for_protocol() {
  local protocol=$1
  local config_file=$2
  local config_type

  config_type=$(verification_config_inbound_type_for_protocol "${protocol}")
  if [[ "${protocol}" == "mixed" ]]; then
    jq -er --arg config_type "${config_type}" '
      [.inbounds[] | select(.type == $config_type and
        ((.tag // "") | startswith("shadowtls-inner-") | not))][0]
      | (.network // "")
      | if type == "array" then join(",") else . end
    ' "${config_file}"
    return 0
  fi

  jq -er --arg config_type "${config_type}" '
    [.inbounds[] | select(.type == $config_type)][0]
    | (.network // "")
    | if type == "array" then join(",") else . end
  ' "${config_file}"
}

verification_scenario_multi_protocol_coexistence() {
  local cert_dir
  local cert_path
  local key_path
  local config_path
  local index_path
  local protocol
  local port
  local configured_network
  local shadowtls_handshake_pid=''
  local http_outbound_marker_pid=''
  local http_outbound_proxy_pid=''
  local direct_marker_pid=''
  local direct_udp_marker_pid=''
  local ssh_marker_pid=''
  local sshd_pid=''
  local socks_outbound_marker_pid=''
  local socks_upstream_pid=''
  local anytls_udp_journal_artifact=''

  verification_prepare_remote_local_tree
  trap 'set +e; if [[ -n "${shadowtls_handshake_pid:-}" ]]; then kill "${shadowtls_handshake_pid}" 2>/dev/null || true; wait "${shadowtls_handshake_pid}" 2>/dev/null || true; fi; if [[ -n "${http_outbound_proxy_pid:-}" ]]; then kill "${http_outbound_proxy_pid}" 2>/dev/null || true; wait "${http_outbound_proxy_pid}" 2>/dev/null || true; fi; if [[ -n "${http_outbound_marker_pid:-}" ]]; then kill "${http_outbound_marker_pid}" 2>/dev/null || true; wait "${http_outbound_marker_pid}" 2>/dev/null || true; fi; if [[ -n "${direct_marker_pid:-}" ]]; then kill "${direct_marker_pid}" 2>/dev/null || true; wait "${direct_marker_pid}" 2>/dev/null || true; fi; if [[ -n "${direct_udp_marker_pid:-}" ]]; then kill "${direct_udp_marker_pid}" 2>/dev/null || true; wait "${direct_udp_marker_pid}" 2>/dev/null || true; fi; if [[ -n "${sshd_pid:-}" ]]; then kill "${sshd_pid}" 2>/dev/null || true; wait "${sshd_pid}" 2>/dev/null || true; fi; if [[ -n "${ssh_marker_pid:-}" ]]; then kill "${ssh_marker_pid}" 2>/dev/null || true; wait "${ssh_marker_pid}" 2>/dev/null || true; fi; if [[ -n "${socks_upstream_pid:-}" ]]; then kill "${socks_upstream_pid}" 2>/dev/null || true; wait "${socks_upstream_pid}" 2>/dev/null || true; fi; if [[ -n "${socks_outbound_marker_pid:-}" ]]; then kill "${socks_outbound_marker_pid}" 2>/dev/null || true; wait "${socks_outbound_marker_pid}" 2>/dev/null || true; fi; verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  # Keep the certificate paths valid for the following runtime_smoke scenario.
  # The Docker container is disposable, so this test-only directory cannot
  # outlive the verification run or affect a host installation.
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

  printf 'SCENARIO=multi_protocol_coexistence\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

1,2,3,4

443
2
www.cloudflare.com
n
1
n
1080
y
mixed-user
mixed-pass
hy2.example.com
y
8443
hy2-pass
hy2-user


n
2
${cert_path}
${key_path}

anytls.example.com
y
9443
anytls-user
anytls-pass
2
${cert_path}
${key_path}
n
n
0
EOF

  # Add SOCKS through the same public, confirmed instance transaction used
  # by operators; the four existing protocols must remain untouched.
  local socks_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-record.json"
  (umask 077; jq -n '{id:"main",name:"SOCKS verification",tag:"socks-in",
    listen:{address:"127.0.0.1",port:1081},
    authentication:{enabled:true,username:"socks-user",password:"socks-pass"},
    outbound_policy:"default",dependencies:[]}' > "${socks_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create socks --json --yes \
    --expected-revision 0 --file "${socks_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-create.json"
  jq -e '.ok==true and .protocol=="socks" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-create.json" >/dev/null

  # Add HTTP with an explicit schema-2 record.  TLS is intentionally disabled
  # here so this scenario probes HTTP CONNECT without inventing certificate
  # material; the HTTP probe still reads the live TLS record and rejects any
  # private key from client output.
  local http_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-record.json"
  (umask 077; jq -n '{id:"main",name:"HTTP verification",tag:"http-in",
    listen:{address:"127.0.0.1",port:1082},
    authentication:{enabled:true,username:"http-user",password:"http-pass"},
    outbound_policy:"default",tls:{enabled:false},dependencies:[]}' > "${http_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create http --json --yes \
    --expected-revision 0 --file "${http_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-create.json"
  jq -e '.ok==true and .protocol=="http" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-create.json" >/dev/null

  local shadowsocks_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-record.json"
  (umask 077; jq -n '{id:"main",name:"Shadowsocks verification",tag:"ss-in",
    listen:{address:"127.0.0.1",port:1083,network:["tcp","udp"]},
    authentication:{method:"2022-blake3-aes-128-gcm",password:"MDEyMzQ1Njc4OWFiY2RlZg==",users:[]},
    outbound_policy:"default",dependencies:[]}' > "${shadowsocks_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create shadowsocks --json --yes \
    --expected-revision 0 --file "${shadowsocks_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-create.json"
  jq -e '.ok==true and .protocol=="shadowsocks" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-create.json" >/dev/null

  local trojan_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/trojan-record.json"
  (umask 077; jq -n --arg cert "${cert_path}" --arg key "${key_path}" '
    {id:"main",name:"Trojan QUIC verification",tag:"trojan-in",
     listen:{address:"127.0.0.1",port:1084},
     authentication:{users:[{name:"main",password:"trojan-verification-password"}]},
     tls:{enabled:true,server_name:"sing-box-vps-verification.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",transport:{type:"quic"},
     outbound_policy:"default",dependencies:[]}' > "${trojan_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create trojan --json --yes \
    --expected-revision 0 --file "${trojan_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/trojan-create.json"
  jq -e '.ok==true and .protocol=="trojan" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/trojan-create.json" >/dev/null

  # Add TUIC through the typed instance transaction and exercise its QUIC/UDP
  # data plane below.  The probe uses the same structured exporter as client
  # export, so the test covers UUID/password, TLS trust and relay options.
  local tuic_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tuic-record.json"
  (umask 077; jq -n --arg cert "${cert_path}" --arg key "${key_path}" '
    {id:"main",name:"TUIC verification",tag:"tuic-in",
     listen:{address:"127.0.0.1",port:1087},
     authentication:{users:[{name:"tuic-user",uuid:"11111111-1111-4111-8111-111111111111",
       password:"tuic-verification-password"}]},
     tls:{enabled:true,server_name:"sing-box-vps-verification.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",
     tuic:{auth_timeout_seconds:3,congestion_control:"bbr",heartbeat_seconds:10,
       udp_over_stream:false,udp_relay_mode:"native",zero_rtt_handshake:false},
     outbound_policy:"default",dependencies:[]}' > "${tuic_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create tuic --json --yes \
    --expected-revision 0 --file "${tuic_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tuic-create.json"
  jq -e '.ok==true and .protocol=="tuic" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tuic-create.json" >/dev/null

  # VMess QUIC shares the V2Ray transport profile with production client
  # export.  Keep it as a separate typed instance so the coexistence run
  # proves the VMess UDP listener and h3 client negotiation without changing
  # the ordinary fresh-install preset.
  local vmess_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vmess-record.json"
  (umask 077; jq -n --arg cert "${cert_path}" --arg key "${key_path}" '
    {id:"main",name:"VMess QUIC verification",tag:"vmess-in",
     listen:{address:"127.0.0.1",port:1085},
     authentication:{users:[{name:"vmess-user",uuid:"22222222-2222-4222-8222-222222222222",
       alter_id:0,security:"auto"}]},
     tls:{enabled:true,server_name:"sing-box-vps-verification.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",transport:{type:"quic"},
     outbound_policy:"default",dependencies:[]}' > "${vmess_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create vmess --json --yes \
    --expected-revision 0 --file "${vmess_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vmess-create.json"
  jq -e '.ok==true and .protocol=="vmess" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vmess-create.json" >/dev/null

  # Snell v6 is a TCP listener whose packet API can carry UDP semantics over
  # the same authenticated stream.  The shared SOCKS UDP probe below exercises
  # that packet path without mislabeling it as a native UDP listener.
  local snell_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-record.json"
  (umask 077; jq -n '
    {id:"main",name:"Snell v6 verification",tag:"snell-in",
     listen:{address:"127.0.0.1",port:1086},
     authentication:{psk:"snell-v6-psk-123456",users:[{name:"snell-user",userkey:"snell-user-key"}]},
     version:6,obfs_mode:"",obfs_host:"",mode:"default",
     outbound_policy:"default",dependencies:[]}' > "${snell_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create snell --json --yes \
    --expected-revision 0 --file "${snell_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-create.json"
  jq -e '.ok==true and .protocol=="snell" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-create.json" >/dev/null

  # ShadowTLS v3 requires a real TLS cover connection and proxies the client
  # stream into its private Mixed detour.  Keep the cover server inside the
  # verification container so the following probe exercises that composite
  # data path rather than merely checking two independent listeners.
  local shadowtls_cover_stdout
  local shadowtls_cover_stderr
  shadowtls_cover_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.stdout.txt")
  shadowtls_cover_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.stderr.txt")
  openssl s_server -accept 1090 -cert "${cert_path}" -key "${key_path}" -www -quiet \
    >"${shadowtls_cover_stdout}" 2>"${shadowtls_cover_stderr}" &
  shadowtls_handshake_pid=$!
  for _ in {1..50}; do
    if verification_port_is_listening 1090; then break; fi
    kill -0 "${shadowtls_handshake_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  verification_assert_port_listening 1090 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.ss-lntp.txt"

  local shadowtls_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-record.json"
  (umask 077; jq -n --arg cert "${cert_path}" '
    {id:"main",name:"ShadowTLS v3 verification",tag:"shadowtls-in",
     listen:{address:"127.0.0.1",port:1088},version:3,
     authentication:{password:"",users:[{name:"shadow-user",password:"shadowtls-verification-password"}]},
     handshake:{server:"127.0.0.1",server_port:1090},handshake_for_server_name:{},
     strict_mode:false,wildcard_sni:"off",
     detour:{tag:"shadowtls-inner-main",listen:{address:"127.0.0.1",port:1089}},
     dependencies:["shadowtls-inner-main"],client_trust:"certificate",
     client_tls:{server_name:"sing-box-vps-verification.invalid",certificate_path:$cert},
     outbound_policy:"default"}
  ' > "${shadowtls_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create shadowtls --json --yes \
    --expected-revision 0 --file "${shadowtls_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-create.json"
  jq -e '.ok==true and .protocol=="shadowtls" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowtls-create.json" >/dev/null

  # NaiveProxy's TCP path is independently probeable with the official
  # with_naive_outbound/libcronet build.  Keep QUIC disabled in this slice so
  # the marker proves the authenticated HTTP/2 data plane without claiming a
  # separate UDP/HTTP3 result.
  local naive_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-record.json"
  (umask 077; jq -n --arg cert "${cert_path}" --arg key "${key_path}" '
    {id:"main",name:"Naive TCP verification",tag:"naive-in",
     listen:{address:"127.0.0.1",port:1091,network:["tcp"]},
     authentication:{users:[{name:"naive-user",username:"naive-user",password:"naive-verification-password"}]},
     tls:{enabled:true,server_name:"sing-box-vps-verification.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",
     naive:{extra_headers:{},insecure_concurrency:0,quic:false,
       quic_congestion_control:"bbr",quic_session_receive_window:"",stream_receive_window:""},
     outbound_policy:"default",dependencies:[]}
  ' > "${naive_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create naive --json --yes \
    --expected-revision 0 --file "${naive_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-create.json"
  jq -e '.ok==true and .protocol=="naive" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-create.json" >/dev/null

  # A managed HTTP outbound must prove more than schema validation: route an
  # authenticated SOCKS client through a local HTTP proxy and verify that the
  # proxy receives the request and returns the exact marker.  The fixture is
  # disposable and maps only the synthetic target name to its local marker,
  # so it cannot accidentally assert public reachability.
  local http_outbound_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-outbound-marker.port"
  local http_outbound_proxy_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-outbound-proxy.port"
  local http_outbound_marker_stdout
  local http_outbound_marker_stderr
  local http_outbound_proxy_stdout
  local http_outbound_proxy_stderr
  local http_outbound_proxy_requests
  local http_outbound_marker
  local http_outbound_proxy_auth
  local http_outbound_marker_port
  local http_outbound_proxy_port
  local http_outbound_target_domain='sbv-http-outbound.invalid'
  http_outbound_marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-marker.stdout.txt")
  http_outbound_marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-marker.stderr.txt")
  http_outbound_proxy_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-proxy.stdout.txt")
  http_outbound_proxy_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-proxy.stderr.txt")
  http_outbound_proxy_requests=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-proxy.request.txt")
  http_outbound_marker="sing-box-vps-http-outbound-loopback-ok-$(date +%s)-$$"
  http_outbound_proxy_auth=$(printf 'proxy-user:proxy-pass' | base64 | tr -d '\n')
  python3 - "${http_outbound_marker_port_file}" "${http_outbound_marker}" \
    > "${http_outbound_marker_stdout}" 2> "${http_outbound_marker_stderr}" <<'PY' &
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

with socketserver.ThreadingTCPServer(("127.0.0.1", 0), MarkerHandler) as server:
    server.daemon_threads = True
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  http_outbound_marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${http_outbound_marker_port_file}" ]] && break
    kill -0 "${http_outbound_marker_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${http_outbound_marker_port_file}" ]]
  http_outbound_marker_port=$(cat "${http_outbound_marker_port_file}")
  [[ "${http_outbound_marker_port}" =~ ^[0-9]+$ ]]

  python3 - "${http_outbound_proxy_port_file}" "${http_outbound_marker_port}" \
    "${http_outbound_target_domain}" "${http_outbound_proxy_auth}" \
    "${http_outbound_proxy_requests}" <<'PY' \
    > "${http_outbound_proxy_stdout}" 2> "${http_outbound_proxy_stderr}" &
import pathlib
import select
import socket
import socketserver
import sys
from urllib.parse import urlsplit

port_file, marker_port, marker_domain, expected_auth, request_log = sys.argv[1:]
marker_port = int(marker_port)
expected_proxy_auth = "Basic " + expected_auth

def recv_headers(conn):
    data = bytearray()
    while b"\r\n\r\n" not in data and len(data) <= 1024 * 1024:
        chunk = conn.recv(65536)
        if not chunk:
            break
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

class ProxyHandler(socketserver.BaseRequestHandler):
    def handle(self):
        client = self.request
        client.settimeout(5)
        raw = recv_headers(client)
        if b"\r\n\r\n" not in raw:
            return
        pathlib.Path(request_log).write_bytes(raw)
        header_block = raw.split(b"\r\n\r\n", 1)[0].decode("iso-8859-1")
        lines = header_block.split("\r\n")
        request_line = lines[0].split(" ", 2)
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                key, value = line.split(":", 1)
                headers[key.lower()] = value.strip()
        if headers.get("proxy-authorization") != expected_proxy_auth:
            client.sendall(b"HTTP/1.1 407 Proxy Authentication Required\r\n\r\n")
            return
        if len(request_line) != 3:
            return
        method, target, version = request_line
        host = ""
        port = 80
        path = target
        if method.upper() == "CONNECT":
            host, _, port_text = target.rpartition(":")
            port = int(port_text or "443")
        elif target.startswith("http://") or target.startswith("https://"):
            parsed = urlsplit(target)
            host = parsed.hostname or ""
            port = parsed.port or (443 if parsed.scheme == "https" else 80)
            path = parsed.path or "/"
            if parsed.query:
                path += "?" + parsed.query
        else:
            host_header = headers.get("host", "")
            host, _, port_text = host_header.rpartition(":")
            if not host:
                host = host_header
            port = int(port_text or "80")
        if host == marker_domain:
            host = "127.0.0.1"
            port = marker_port
        if host != "127.0.0.1":
            return
        with socket.create_connection((host, port), timeout=5) as upstream:
            if method.upper() == "CONNECT":
                client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
                relay(client, upstream)
                return
            rewritten = (method + " " + path + " " + version + "\r\n" +
                         "\r\n".join(lines[1:]) + "\r\n\r\n").encode("iso-8859-1")
            upstream.sendall(rewritten)
            relay(client, upstream)

class ReusableServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ReusableServer(("127.0.0.1", 0), ProxyHandler) as server:
    pathlib.Path(port_file).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
  http_outbound_proxy_pid=$!
  for _ in {1..50}; do
    [[ -s "${http_outbound_proxy_port_file}" ]] && break
    kill -0 "${http_outbound_proxy_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${http_outbound_proxy_port_file}" ]]
  http_outbound_proxy_port=$(cat "${http_outbound_proxy_port_file}")
  [[ "${http_outbound_proxy_port}" =~ ^[0-9]+$ ]]

  local http_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-outbound-record.json"
  (umask 077; jq -n --argjson proxy_port "${http_outbound_proxy_port}" --arg domain "${http_outbound_target_domain}" '
    {id:"http-outbound-verification",role:"outbound",type:"http",tag:"http-outbound-verification",enabled:true,
     route_rules:[{domain:[$domain],action:"route",outbound:"http-outbound-verification"}],
     config:{server:"127.0.0.1",server_port:$proxy_port,username:"proxy-user",password:"proxy-pass",
       headers:{"X-SBV-Proxy":"http-outbound"},connect_timeout:"5s"}}' > "${http_outbound_record}")
  local http_outbound_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision 0 --file "${http_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-outbound-create.json"
  http_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-create.json"
  if [[ "${http_outbound_create_status}" != "0" ]]; then
    return "${http_outbound_create_status}"
  fi
  jq -e '.ok==true and .operation=="create" and .revision==1 and .type=="http"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/http-outbound-create.json" >/dev/null
  verification_mark_step http-outbound-component-created

  verification_wait_for_service_active sing-box
  verification_mark_step http-outbound-service-active
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_mark_step http-outbound-config-checked
  config_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --arg domain "${http_outbound_target_domain}" --argjson proxy_port "${http_outbound_proxy_port}" '
    ([.outbounds[] | select(.type == "http" and .tag == "http-outbound-verification" and
      .server == "127.0.0.1" and .server_port == $proxy_port and
      .username == "proxy-user" and .password == "proxy-pass" and
      .headers["X-SBV-Proxy"] == "http-outbound")] | length == 1) and
    ([.route.rules[] | select(.outbound == "http-outbound-verification" and .domain == [$domain])] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step http-outbound-config-asserted

  local http_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-response.txt"
  local http_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound-curl.stderr.txt"
  set +e
  curl --fail --silent --show-error --noproxy '' \
    --proxy "socks5h://socks-user:socks-pass@127.0.0.1:1081" \
    "http://${http_outbound_target_domain}/" \
    > "$(verification_artifact_path "${http_outbound_response}")" \
    2> "$(verification_artifact_path "${http_outbound_curl_stderr}")"
  local http_outbound_curl_status=$?
  set -e
  [[ "${http_outbound_curl_status}" == "0" ]]
  verification_mark_step http-outbound-curl-complete
  grep -Fqx "${http_outbound_marker}" "$(verification_artifact_path "${http_outbound_response}")"
  grep -Fq 'Proxy-Authorization: Basic cHJveHktdXNlcjpwcm94eS1wYXNz' \
    "${http_outbound_proxy_requests}"
  # sing-box canonicalizes outbound header names (for example, X-Sbv-Proxy),
  # so the value assertion is intentionally case-insensitive for the field
  # name while remaining exact for the test marker.
  grep -iFq 'X-SBV-Proxy: http-outbound' "${http_outbound_proxy_requests}"
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/http-outbound.result.env" \
    'COMPONENT=http-outbound' 'RESULT=success' 'DATA_PLANE=authenticated_http_proxy_loopback'

  # A direct inbound must prove its actual tunnel/override behavior rather
  # than merely occupying a listener.  The disposable marker binds to a
  # random loopback port; the managed direct listener receives the HTTP
  # request and forwards it to the configured override address/port.
  local direct_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-marker.port"
  local direct_marker_stdout
  local direct_marker_stderr
  local direct_marker
  local direct_marker_port
  local direct_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-record.json"
  local direct_response="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-response.txt"
  local direct_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-curl.stderr.txt"
  direct_marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-marker.stdout.txt")
  direct_marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-marker.stderr.txt")
  direct_marker="sing-box-vps-direct-inbound-loopback-ok-$(date +%s)-$$"
  python3 - "${direct_marker_port_file}" "${direct_marker}" \
    > "${direct_marker_stdout}" 2> "${direct_marker_stderr}" <<'PY' &
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
  direct_marker_pid=$!
  for _ in {1..50}; do
    [[ -s "${direct_marker_port_file}" ]] && break
    kill -0 "${direct_marker_pid}" 2>/dev/null || return 1
    sleep 0.1
  done
  [[ -s "${direct_marker_port_file}" ]]
  direct_marker_port=$(cat "${direct_marker_port_file}")
  [[ "${direct_marker_port}" =~ ^[0-9]+$ ]]
  (umask 077; jq -n --argjson marker_port "${direct_marker_port}" '
    {id:"direct-inbound-verification",role:"inbound",type:"direct",
     tag:"direct-inbound-verification",enabled:true,route_rules:[],
     config:{listen:"127.0.0.1",listen_port:1092,network:"tcp",
       override_address:"127.0.0.1",override_port:$marker_port}}
  ' > "${direct_record}")
  local direct_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision 1 --file "${direct_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-create.json"
  direct_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-create.json"
  if [[ "${direct_create_status}" != "0" ]]; then
    return "${direct_create_status}"
  fi
  jq -e '.ok==true and .operation=="create" and .revision==2 and .type=="direct"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-create.json" >/dev/null
  verification_mark_step direct-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_mark_step direct-inbound-service-active
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_mark_step direct-inbound-config-checked
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --argjson marker_port "${direct_marker_port}" '
    ([.inbounds[] | select(.type == "direct" and .tag == "direct-inbound-verification" and
      .listen == "127.0.0.1" and .listen_port == 1092 and .network == "tcp" and
      .override_address == "127.0.0.1" and .override_port == $marker_port)] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step direct-inbound-config-asserted
  verification_assert_port_listening 1092 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.direct-inbound.ss-lntp.txt"
  set +e
  curl --fail --silent --show-error --max-time 5 --noproxy '*' \
    "http://127.0.0.1:1092/" \
    > "$(verification_artifact_path "${direct_response}")" \
    2> "$(verification_artifact_path "${direct_curl_stderr}")"
  local direct_curl_status=$?
  set -e
  [[ "${direct_curl_status}" == "0" ]]
  grep -Fqx "${direct_marker}" "$(verification_artifact_path "${direct_response}")"
  verification_mark_step direct-inbound-curl-complete
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound.result.env" \
    'COMPONENT=direct-inbound' 'RESULT=success' 'DATA_PLANE=direct_tcp_override_loopback'

  # The same direct adapter also supports UDP when the listener explicitly
  # selects that network.  Use a second disposable echo fixture and a
  # separate managed component so the TCP and UDP projections are observed
  # independently in the listener/resource plan.
  local direct_udp_marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-marker.port"
  local direct_udp_marker_stdout
  local direct_udp_marker_stderr
  local direct_udp_marker
  local direct_udp_marker_port
  local direct_udp_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-record.json"
  local direct_udp_response="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-response.txt"
  local direct_udp_response_path
  local direct_udp_client_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-client.stderr.txt"
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
  (umask 077; jq -n --argjson marker_port "${direct_udp_marker_port}" '
    {id:"direct-udp-inbound-verification",role:"inbound",type:"direct",
     tag:"direct-udp-inbound-verification",enabled:true,route_rules:[],
     config:{listen:"127.0.0.1",listen_port:1093,network:"udp",
       override_address:"127.0.0.1",override_port:$marker_port}}
  ' > "${direct_udp_record}")
  local direct_udp_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision 2 --file "${direct_udp_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-create.json"
  direct_udp_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-udp-create.json"
  if [[ "${direct_udp_create_status}" != "0" ]]; then
    return "${direct_udp_create_status}"
  fi
  jq -e '.ok==true and .operation=="create" and .revision==3 and .type=="direct"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-create.json" >/dev/null
  verification_mark_step direct-udp-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_mark_step direct-udp-inbound-service-active
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_mark_step direct-udp-inbound-config-checked
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --argjson marker_port "${direct_udp_marker_port}" '
    ([.inbounds[] | select(.type == "direct" and .tag == "direct-udp-inbound-verification" and
      .listen == "127.0.0.1" and .listen_port == 1093 and .network == "udp" and
      .override_address == "127.0.0.1" and .override_port == $marker_port)] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step direct-udp-inbound-config-asserted
  verification_assert_udp_port_listening 1093 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.direct-udp-inbound.ss-lunp.txt"
  direct_udp_response_path=$(verification_artifact_path "${direct_udp_response}")
  set +e
  python3 - "${direct_udp_response_path}" "${direct_udp_marker}" \
    > /dev/null 2> "$(verification_artifact_path "${direct_udp_client_stderr}")" <<'PY'
import pathlib
import socket
import sys

response_path, marker = sys.argv[1:]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
    client.settimeout(5)
    client.sendto(marker.encode(), ("127.0.0.1", 1093))
    payload, _ = client.recvfrom(65535)
pathlib.Path(response_path).write_bytes(payload)
PY
  local direct_udp_client_status=$?
  set -e
  [[ "${direct_udp_client_status}" == "0" ]]
  grep -Fqx "${direct_udp_marker}" "${direct_udp_response_path}"
  verification_mark_step direct-udp-inbound-client-complete
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp.result.env" \
    'COMPONENT=direct-inbound' 'RESULT=success' 'DATA_PLANE=direct_udp_override_loopback'

  # Redirect and TProxy are transparent inbounds: unlike direct, they must be
  # exercised through temporary host policy. The policy is deliberately
  # created only inside this privileged verification container and is removed
  # before the component records are deleted; it is not installer-owned.
  local redirect_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-record.json"
  (umask 077; jq -n '{id:"redirect-inbound-verification",role:"inbound",type:"redirect",
    tag:"redirect-inbound-verification",enabled:true,route_rules:[],
    config:{listen:"127.0.0.1",listen_port:1094}}' > "${redirect_record}")
  local redirect_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision 3 --file "${redirect_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json"
  redirect_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-create.json"
  [[ "${redirect_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==4 and .type=="redirect"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json" >/dev/null
  verification_mark_step redirect-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-inbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_execute_redirect_probe /root/sing-box-vps/config.json 1094
  verification_mark_step redirect-inbound-probe-complete

  local tproxy_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-record.json"
  (umask 077; jq -n '{id:"tproxy-inbound-verification",role:"inbound",type:"tproxy",
    tag:"tproxy-inbound-verification",enabled:true,route_rules:[],
    config:{listen:"0.0.0.0",listen_port:1095,network:["tcp","udp"]}}' > "${tproxy_record}")
  local tproxy_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes --allow-public \
    --expected-revision 4 --file "${tproxy_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-create.json"
  tproxy_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-create.json"
  [[ "${tproxy_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==5 and .type=="tproxy"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-create.json" >/dev/null
  verification_mark_step tproxy-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-inbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_execute_tproxy_probe /root/sing-box-vps/config.json 1095
  verification_mark_step tproxy-inbound-probe-complete

  local transparent_diagnose
  transparent_diagnose=$(bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component diagnose --json)
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/transparent-component-diagnose.json" \
    "${transparent_diagnose}"
  jq -e '
    .ok == true and
    any(.data.components[]; .id == "redirect-inbound-verification" and
      .instance_environment.requirements.requires_root == true and
      .instance_environment.requirements.requires_tun_device == false) and
    any(.data.components[]; .id == "tproxy-inbound-verification" and
      .instance_environment.requirements.requires_root == true and
      .instance_environment.requirements.requires_tun_device == false)
  ' <<< "${transparent_diagnose}" >/dev/null

  local tproxy_delete_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 5 --id tproxy-inbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-delete.json"
  tproxy_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-delete.json"
  [[ "${tproxy_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==6 and .id=="tproxy-inbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-delete.json" >/dev/null
  local redirect_delete_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 6 --id redirect-inbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-delete.json"
  redirect_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-delete.json"
  [[ "${redirect_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==7 and .id=="redirect-inbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-delete.json" >/dev/null
  verification_mark_step transparent-components-deleted
  jq -e '
    ([.inbounds[] | select(.type == "redirect" and .tag == "redirect-inbound-verification")] | length) == 0 and
    ([.inbounds[] | select(.type == "tproxy" and .tag == "tproxy-inbound-verification")] | length) == 0
  ' /root/sing-box-vps/config.json >/dev/null

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
  ! verification_port_is_listening "${ssh_port}"

  mkdir -p "${ssh_dir}" /run/sshd
  ssh-keygen -q -t ed25519 -N '' -f "${ssh_host_key}" >/dev/null
  ssh_host_key_public=$(ssh-keygen -y -f "${ssh_host_key}")
  if ! id "${ssh_server_user}" >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/sh "${ssh_server_user}"
  fi
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
    --expected-revision 7 --file "${ssh_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-create.json"
  ssh_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-create.json"
  [[ "${ssh_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==8 and .type=="ssh"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-create.json" >/dev/null
  verification_mark_step ssh-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --arg host_key "${ssh_host_key_public}" --argjson ssh_port "${ssh_port}" '
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
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-outbound.result.env" \
    'COMPONENT=ssh-outbound' 'RESULT=success' \
    'DATA_PLANE=ssh_direct_tcpip_loopback' 'HOST_KEY_VERIFICATION=pinned'

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 8 --id ssh-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-delete.json"
  ssh_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/ssh-delete.json"
  [[ "${ssh_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==9 and .id=="ssh-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/ssh-delete.json" >/dev/null
  verification_mark_step ssh-outbound-component-deleted
  jq -e '
    ([.outbounds[] | select(.tag == "ssh-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "ssh-outbound-verification")] | length) == 0
  ' /root/sing-box-vps/config.json >/dev/null

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
    --expected-revision 9 --file "${socks_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-create.json"
  socks_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-create.json"
  [[ "${socks_outbound_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==10 and .type=="socks"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-create.json" >/dev/null
  verification_mark_step socks-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --arg domain "${socks_outbound_target_domain}" \
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
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound.result.env" \
    'COMPONENT=socks-outbound' 'RESULT=success' \
    'DATA_PLANE=socks5_connect_loopback' 'AUTHENTICATION=upstream_username_password'

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 10 --id socks-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-delete.json"
  socks_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/socks-outbound-delete.json"
  [[ "${socks_outbound_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==11 and .id=="socks-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-outbound-delete.json" >/dev/null
  verification_mark_step socks-outbound-component-deleted
  jq -e '
    ([.outbounds[] | select(.tag == "socks-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "socks-outbound-verification")] | length) == 0
  ' /root/sing-box-vps/config.json >/dev/null

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
    --expected-revision 11 --file "${selector_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-create.json"
  selector_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-create.json"
  [[ "${selector_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==12 and .type=="selector"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-create.json" >/dev/null
  verification_mark_step selector-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e '
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
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound.result.env" \
    'COMPONENT=selector-outbound' 'RESULT=success' \
    'DATA_PLANE=selector_direct_loopback'

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 12 --id selector-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-delete.json"
  selector_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/selector-outbound-delete.json"
  [[ "${selector_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==13 and .id=="selector-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/selector-outbound-delete.json" >/dev/null
  verification_mark_step selector-outbound-component-deleted
  jq -e '
    ([.outbounds[] | select(.tag == "selector-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "selector-outbound-verification")] | length) == 0
  ' /root/sing-box-vps/config.json >/dev/null

  # URLTest groups share the same typed member graph but add an active health
  # URL.  Give it the single direct member and the existing marker URL so the
  # group must complete a real probe before the routed request succeeds.
  local urltest_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-record.json"
  local urltest_probe_url="http://localhost:${direct_marker_port}/"
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
    --expected-revision 13 --file "${urltest_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-create.json"
  urltest_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-create.json"
  [[ "${urltest_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==14 and .type=="urltest"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-create.json" >/dev/null
  verification_mark_step urltest-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --arg url "${urltest_probe_url}" '
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
      "http://localhost:${direct_marker_port}/" \
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
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound.result.env" \
    'COMPONENT=urltest-outbound' 'RESULT=success' \
    'DATA_PLANE=urltest_direct_loopback' 'HEALTHCHECK=loopback_http'

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 14 --id urltest-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-delete.json"
  urltest_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/urltest-outbound-delete.json"
  [[ "${urltest_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==15 and .id=="urltest-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/urltest-outbound-delete.json" >/dev/null
  verification_mark_step urltest-outbound-component-deleted
  jq -e '
    ([.outbounds[] | select(.tag == "urltest-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "urltest-outbound-verification")] | length) == 0
  ' /root/sing-box-vps/config.json >/dev/null

  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/config.json")
  index_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/index.env")
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/libcronet.sha256.txt" \
    sha256sum /usr/local/lib/libcronet.so
  cp /root/sing-box-vps/config.json "${config_path}"
  cp /root/sing-box-vps/protocols/index.env "${index_path}"
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,socks,http,shadowsocks,trojan,tuic,vmess,snell,shadowtls,naive' "${index_path}"
  jq -e '
    ([.inbounds[] | .type] | sort) == ["anytls", "direct", "direct", "http", "hysteria2", "mixed", "mixed", "naive", "shadowsocks", "shadowtls", "snell", "socks", "trojan", "tuic", "vless", "vmess"] and
    ([.inbounds[] | select(.type == "direct")] | length == 2) and
    ([.inbounds[] | select(.type == "vless") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "mixed") | .listen_port] | length == 2) and
    ([.inbounds[] | select(.type == "hysteria2") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "anytls") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "socks") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "http") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "shadowsocks") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "trojan" and .transport.type=="quic" and .tls.alpn==["h3"])] | length == 1) and
    ([.inbounds[] | select(.type == "tuic" and .tls.alpn==["h3"] and
      .congestion_control=="bbr" and .auth_timeout=="3s" and .heartbeat=="10s" and
      (. | has("udp_relay_mode") | not) and (. | has("udp_over_stream") | not))] | length == 1) and
    ([.inbounds[] | select(.type == "vmess" and .transport.type=="quic" and .tls.alpn==["h3"] and
      .users[0].uuid=="22222222-2222-4222-8222-222222222222")] | length == 1) and
    ([.inbounds[] | select(.type == "snell" and .version == 6 and
      .psk == "snell-v6-psk-123456" and .users[0].userkey == "snell-user-key" and
      .mode == "default")] | length == 1) and
    ([.inbounds[] | select(.type == "shadowtls" and .tag == "shadowtls-in" and
      .listen_port == 1088 and .version == 3 and .users[0].password == "shadowtls-verification-password" and
      .handshake.server == "127.0.0.1" and .handshake.server_port == 1090 and
      .detour == "shadowtls-inner-main")] | length == 1) and
    ([.inbounds[] | select(.type == "mixed" and .tag == "shadowtls-inner-main" and
      .listen == "127.0.0.1" and .listen_port == 1089)] | length == 1) and
    ([.inbounds[] | select(.type == "naive" and .tag == "naive-in" and
      .listen == "127.0.0.1" and .listen_port == 1091 and .network == "tcp" and
      .users[0].username == "naive-user" and .tls.server_name == "sing-box-vps-verification.invalid")] | length == 1)
  ' /root/sing-box-vps/config.json >/dev/null
  grep -Fqx 'sing-box version 1.14.0' <(sing-box version)
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  while IFS= read -r protocol; do
    port=$(verification_config_inbound_port_for_protocol \
      "${protocol}" /root/sing-box-vps/config.json)
    configured_network=$(verification_config_inbound_network_for_protocol \
      "${protocol}" /root/sing-box-vps/config.json)
    if [[ "${configured_network}" == "tcp" ]]; then
      verification_assert_port_listening "${port}" \
        "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.${protocol}.ss-lntp.txt"
    elif [[ "${configured_network}" == "udp" ]]; then
      verification_assert_udp_port_listening "${port}" \
        "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.${protocol}.ss-lunp.txt"
    elif verification_protocol_metadata "${protocol}" | jq -e \
      '.listen_networks | type == "array" and index("udp") != null' >/dev/null; then
      verification_assert_udp_port_listening "${port}" \
        "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.${protocol}.ss-lunp.txt"
    else
      verification_assert_port_listening "${port}" \
        "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.${protocol}.ss-lntp.txt"
    fi
  done < <(read_installed_protocols)
  verification_run_protocol_probes
  # AnyTLS keeps a TCP listener; this shared SOCKS5 UDP probe exercises its
  # authenticated UDP-over-AnyTLS (UoT) adapter without calling it native UDP.
  verification_execute_protocol_udp_probe anytls /root/sing-box-vps/config.json
  anytls_udp_journal_artifact=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/anytls-udp-journal.txt")
  for _ in {1..20}; do
    journalctl -u sing-box -n 100 --no-pager > "${anytls_udp_journal_artifact}" 2>&1
    if grep -Fq 'inbound/anytls[anytls-in]: inbound UoT connection' \
      "${anytls_udp_journal_artifact}"; then
      break
    fi
    sleep 0.1
  done
  grep -Fq 'inbound/anytls[anytls-in]: inbound UoT connection' \
    "${anytls_udp_journal_artifact}"
  verification_execute_protocol_udp_probe hy2 /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe shadowsocks /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe trojan /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe tuic /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe vmess /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe snell /root/sing-box-vps/config.json

  # The server v5 wire protocol is exported as a sing-box v4 outbound.  Keep
  # the v6 evidence above intact, then replace the same typed instance through
  # revision CAS so the existing single-Snell probe generator can exercise the
  # v5 HTTP-obfs TCP and packet-API UDP paths without accepting an ambiguous
  # multi-instance inventory.
  verification_capture_tree_if_present \
    "$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/snell")" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/snell-v6"
  local snell_v5_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-v5-record.json"
  local snell_v5_replace_status=0
  (umask 077; jq -n '
    {id:"main",name:"Snell v5 verification",tag:"snell-in",
     listen:{address:"127.0.0.1",port:1086},
     authentication:{psk:"snell-v5-psk-123456",users:[{name:"snell-v5-user",userkey:"snell-v5-user-key"}]},
     version:5,obfs_mode:"http",obfs_host:"snell-v5.example.com",mode:"",
     outbound_policy:"default",dependencies:[]}' > "${snell_v5_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance replace snell --json --yes \
    --expected-revision 1 --file "${snell_v5_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-v5-replace.json"
  snell_v5_replace_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-v5-replace.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/snell-v5-replace.json"
  [[ "${snell_v5_replace_status}" == "0" ]]
  jq -e '.ok==true and .action=="instance" and .protocol=="snell" and
    .changed==true and .revision==2 and .transaction.status=="success" and
    .transaction.phase=="committed" and .transaction.operation_exit_code==0' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/snell-v5-replace.json" >/dev/null
  verification_mark_step snell-v5-instance-replaced
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/snell-v5-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/snell-v5-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e '
    ([.inbounds[] | select(.type == "snell" and .tag == "snell-in" and
      .listen == "127.0.0.1" and .listen_port == 1086 and .version == 5 and
      .psk == "snell-v5-psk-123456" and .obfs_mode == "http" and
      (has("obfs_host") | not) and
      .users[0].userkey == "snell-v5-user-key" and (has("mode") | not))] |
      length == 1)
  ' "${config_path}" >/dev/null
  jq -e '
    .revision == 2 and
    ([.instances[] | select(.id == "main" and .version == 5 and
      .obfs_mode == "http" and .obfs_host == "snell-v5.example.com" and
      .mode == "" and .authentication.psk == "snell-v5-psk-123456" and
      .authentication.users[0].userkey == "snell-v5-user-key")] | length == 1)
  ' /root/sing-box-vps/protocols/instances/snell.json >/dev/null
  verification_mark_step snell-v5-config-asserted
  verification_execute_single_protocol_probe snell /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe snell /root/sing-box-vps/config.json
  jq -e '
    .outbounds | length == 1 and .[0].type == "snell" and .[0].version == 4 and
    .[0].network == ["tcp", "udp"] and .[0].obfs_mode == "http" and
    .[0].obfs_host == "snell-v5.example.com" and
    (.[0] | has("mode") | not)
  ' "$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/snell/client.json")" >/dev/null

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
    --expected-revision 15 --file "${shadowsocks_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-create.json"
  shadowsocks_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-create.json"
  [[ "${shadowsocks_outbound_create_status}" == 0 ]]
  jq -e '.ok==true and .operation=="create" and .revision==16 and
    .type=="shadowsocks" and .id=="shadowsocks-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-create.json" >/dev/null
  verification_mark_step shadowsocks-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-config.json")
  cp /root/sing-box-vps/config.json "${config_path}"
  jq -e --arg domain "${shadowsocks_outbound_target_domain}" \
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
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound.result.env" \
    'COMPONENT=shadowsocks-outbound' 'RESULT=success' \
    'DATA_PLANE=shadowsocks2022_connect_loopback' 'AUTHENTICATION=ss2022_psk'

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision 16 --id shadowsocks-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-delete.json"
  shadowsocks_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/shadowsocks-outbound-delete.json"
  [[ "${shadowsocks_outbound_delete_status}" == 0 ]]
  jq -e '.ok==true and .operation=="delete" and .revision==17 and
    .id=="shadowsocks-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/shadowsocks-outbound-delete.json" >/dev/null
  verification_mark_step shadowsocks-outbound-component-deleted
  jq -e '
    ([.outbounds[] | select(.tag == "shadowsocks-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "shadowsocks-outbound-verification" or
      (.inbound == ["ss-in"] and .domain == ["sbv-shadowsocks-outbound.invalid"]))] | length) == 0
  ' /root/sing-box-vps/config.json >/dev/null
}
