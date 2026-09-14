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

  verification_prepare_remote_local_tree
  trap 'set +e; if [[ -n "${shadowtls_handshake_pid:-}" ]]; then kill "${shadowtls_handshake_pid}" 2>/dev/null || true; wait "${shadowtls_handshake_pid}" 2>/dev/null || true; fi; if [[ -n "${http_outbound_proxy_pid:-}" ]]; then kill "${http_outbound_proxy_pid}" 2>/dev/null || true; wait "${http_outbound_proxy_pid}" 2>/dev/null || true; fi; if [[ -n "${http_outbound_marker_pid:-}" ]]; then kill "${http_outbound_marker_pid}" 2>/dev/null || true; wait "${http_outbound_marker_pid}" 2>/dev/null || true; fi; if [[ -n "${direct_marker_pid:-}" ]]; then kill "${direct_marker_pid}" 2>/dev/null || true; wait "${direct_marker_pid}" 2>/dev/null || true; fi; if [[ -n "${direct_udp_marker_pid:-}" ]]; then kill "${direct_udp_marker_pid}" 2>/dev/null || true; wait "${direct_udp_marker_pid}" 2>/dev/null || true; fi; verification_cleanup_remote_local_tree; trap - RETURN' RETURN
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
  verification_execute_protocol_udp_probe hy2 /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe shadowsocks /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe trojan /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe tuic /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe vmess /root/sing-box-vps/config.json
  verification_execute_protocol_udp_probe snell /root/sing-box-vps/config.json
}
