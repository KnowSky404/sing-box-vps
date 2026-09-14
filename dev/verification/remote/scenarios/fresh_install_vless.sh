verification_run_openvpn_endpoint_runtime_probe() {
  local endpoint_cert_dir=/tmp/sing-box-vps-verification-openvpn
  local expected_revision=${1:-0}
  local server_create_revision=$((expected_revision + 1))
  local client_create_revision=$((expected_revision + 2))
  local proxy_create_revision=$((expected_revision + 3))
  local proxy_delete_revision=$((expected_revision + 4))
  local client_delete_revision=$((expected_revision + 5))
  local server_delete_revision=$((expected_revision + 6))
  local endpoint_cert_path="${endpoint_cert_dir}/server.crt"
  local endpoint_key_path="${endpoint_cert_dir}/server.key"
  local marker_port_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-marker.port"
  local marker_address marker_ip_json marker_port marker
  local marker_stdout marker_stderr marker_response marker_access
  local server_record client_record proxy_record
  local server_create client_create proxy_create
  local server_delete client_delete proxy_delete
  local tcp_journal_path
  local tcp_journal_relative="${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/journalctl.txt"
  local curl_status=1

  if [[ "${VERIFY_REMOTE_SKIP_PRIVILEGED_RESOURCES:-0}" == "1" ]]; then
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/result.env" \
      'RESULT=blocked' 'REASON=privileged_resource_probe_disabled'
    verification_mark_step fresh_install_vless_openvpn_endpoint_blocked
    return 0
  fi
  if ! command -v ip >/dev/null 2>&1; then
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/result.env" \
      'RESULT=blocked' 'REASON=ip_unavailable'
    verification_mark_step fresh_install_vless_openvpn_endpoint_blocked
    return 0
  fi
  if ! marker_ip_json=$(ip -j -4 addr show scope global); then
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/result.env" \
      'RESULT=blocked' 'REASON=ip_json_unavailable'
    verification_mark_step fresh_install_vless_openvpn_endpoint_blocked
    return 0
  fi
  marker_address=$(jq -r '
    [.[] | .addr_info[]? | select(.family == "inet" and .scope == "global") | .local][0] // empty
  ' <<<"${marker_ip_json}")
  if [[ -z "${marker_address}" ]]; then
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/result.env" \
      'RESULT=blocked' 'REASON=no_global_ipv4_marker_address'
    verification_mark_step fresh_install_vless_openvpn_endpoint_blocked
    return 0
  fi
  if ! command -v openssl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/result.env" \
      'RESULT=blocked' 'REASON=openssl_or_python3_unavailable'
    verification_mark_step fresh_install_vless_openvpn_endpoint_blocked
    return 0
  fi

  rm -rf -- "${endpoint_cert_dir}"
  mkdir -p "${endpoint_cert_dir}"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${endpoint_key_path}" \
    -out "${endpoint_cert_path}" \
    -subj '/CN=sing-box-vps-openvpn-verification.invalid' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,digitalSignature,keyEncipherment' \
    -addext 'extendedKeyUsage=serverAuth' \
    -addext 'subjectAltName=DNS:sing-box-vps-openvpn-verification.invalid' \
    -days 1 >/dev/null 2>&1
  chmod 600 "${endpoint_cert_path}" "${endpoint_key_path}"

  marker="sing-box-vps-openvpn-endpoint-loopback-ok-$(date +%s)-$$"
  marker_stdout=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/marker.stdout.txt")
  marker_stderr=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/marker.stderr.txt")
  marker_response=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/marker.response.txt")
  marker_access=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/marker.access.txt")
  python3 - "${marker_port_file}" "${marker_address}" "${marker}" "${marker_access}" \
    >"${marker_stdout}" 2>"${marker_stderr}" <<'PY' &
import http.server
import pathlib
import sys

port_path, bind_address, marker, access_path = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        pathlib.Path(access_path).write_text(self.path + "\n", encoding="ascii")
        body = (marker + "\n").encode("ascii")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

server = http.server.ThreadingHTTPServer((bind_address, 0), MarkerHandler)
pathlib.Path(port_path).write_text(str(server.server_address[1]), encoding="ascii")
server.serve_forever()
PY
  OPENVPN_ENDPOINT_MARKER_PID=$!
  for _ in {1..100}; do
    [[ -s "${marker_port_file}" ]] && break
    kill -0 "${OPENVPN_ENDPOINT_MARKER_PID}" 2>/dev/null || {
      printf 'OpenVPN endpoint marker exited before binding\n' >&2
      return 1
    }
    sleep 0.1
  done
  [[ -s "${marker_port_file}" ]]
  marker_port=$(<"${marker_port_file}")
  [[ "${marker_port}" =~ ^[0-9]+$ ]]
  verification_mark_step fresh_install_vless_openvpn_endpoint_prepared

  server_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-server.json"
  client_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-client.json"
  proxy_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-proxy.json"
  server_create="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-server-create.json"
  client_create="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-client-create.json"
  proxy_create="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-proxy-create.json"
  server_delete="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-server-delete.json"
  client_delete="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-client-delete.json"
  proxy_delete="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-proxy-delete.json"
  (umask 077; jq -n --arg cert "${endpoint_cert_path}" --arg key "${endpoint_key_path}" '
    {id:"openvpn-endpoint-server-verification",role:"endpoint",type:"openvpn-server",
     tag:"openvpn-endpoint-server-verification",enabled:true,route_rules:[],config:{
       mode:"tls",system:false,listen:"127.0.0.1",listen_port:11994,network:"tcp",
       address:["10.77.0.1/24"],users:[{username:"probe",password:"probe-pass"}],
       tls:{certificate_path:$cert,key_path:$key,verify_client_certificate:"none"}}}' \
    > "${server_record}")
  (umask 077; jq -n --arg cert "${endpoint_cert_path}" '
    {id:"openvpn-endpoint-client-verification",role:"endpoint",type:"openvpn-client",
     tag:"openvpn-endpoint-client-verification",enabled:true,route_rules:[],config:{
       mode:"tls",system:false,server:"127.0.0.1",server_port:11994,network:"tcp",
       username:"probe",password:"probe-pass",
       tls:{certificate_path:$cert,server_name:"sing-box-vps-openvpn-verification.invalid",
         remote_certificate_tls:"server"}}}' \
    > "${client_record}")
  (umask 077; jq -n --arg marker_address "${marker_address}" --argjson marker_port "${marker_port}" '
    {id:"openvpn-endpoint-proxy-verification",role:"inbound",type:"direct",
     tag:"openvpn-endpoint-proxy-verification",enabled:true,
     route_rules:[{inbound:["openvpn-endpoint-proxy-verification"],action:"route",
       outbound:"openvpn-endpoint-client-verification"}],config:{
       listen:"127.0.0.1",listen_port:15091,override_address:$marker_address,
       override_port:$marker_port}}' \
    > "${proxy_record}")

  bash /usr/local/bin/sbv agent component create --json --yes --allow-public \
    --expected-revision "${expected_revision}" --file "${server_record}" > "${server_create}"
  verification_capture_file_if_present "${server_create}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/server-create.json"
  jq -e --argjson revision "${server_create_revision}" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="openvpn-server" and .service_restarted==true' "${server_create}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_server_created
  verification_wait_for_service_active sing-box

  bash /usr/local/bin/sbv agent component create --json --yes \
    --expected-revision "${server_create_revision}" --file "${client_record}" > "${client_create}"
  verification_capture_file_if_present "${client_create}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/client-create.json"
  jq -e --argjson revision "${client_create_revision}" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="openvpn-client" and .service_restarted==true' "${client_create}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_client_created
  verification_wait_for_service_active sing-box

  bash /usr/local/bin/sbv agent component create --json --yes \
    --expected-revision "${client_create_revision}" --file "${proxy_record}" > "${proxy_create}"
  verification_capture_file_if_present "${proxy_create}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/proxy-create.json"
  jq -e --argjson revision "${proxy_create_revision}" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="direct" and .service_restarted==true' "${proxy_create}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_proxy_created
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/config.check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/config.json" \
    jq -c '{endpoints:[.endpoints[] | select(.tag == "openvpn-endpoint-server-verification" or
      .tag == "openvpn-endpoint-client-verification")],inbounds:[.inbounds[] |
      select(.tag == "openvpn-endpoint-proxy-verification")],route:{rules:[.route.rules[] |
      select(.outbound == "openvpn-endpoint-client-verification")]}}' \
    /root/sing-box-vps/config.json
  jq -e '.endpoints | length == 2 and
    any(.[]; .type=="openvpn-server" and .system==false) and
    any(.[]; .type=="openvpn-client" and .system==false)' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/config.json")" >/dev/null
  verification_assert_port_listening 11994 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/server-listener.ss-lntp.txt"
  verification_assert_port_listening 15091 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/proxy-listener.ss-lntp.txt"

  for _ in {1..20}; do
    if curl --fail --silent --show-error --max-time 5 --noproxy '*' \
      http://127.0.0.1:15091/ > "${marker_response}" 2> \
      "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/curl.stderr.txt")"; then
      curl_status=0
      break
    fi
    sleep 0.5
  done
  [[ "${curl_status}" == 0 ]]
  grep -Fqx "${marker}" "${marker_response}"
  grep -Fqx '/' "${marker_access}"
  verification_capture_best_effort_command "${tcp_journal_relative}" \
    journalctl -u sing-box -n 160 --no-pager
  tcp_journal_path=$(verification_artifact_path "${tcp_journal_relative}")
  grep -Fq 'peer connected' "${tcp_journal_path}"
  grep -Fq 'tunnel established to 127.0.0.1:11994 over tcp' "${tcp_journal_path}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/result.env" \
    'RESULT=success' 'TRANSPORT=tcp' 'SYSTEM_INTERFACE=false' \
    'AUTH=username_password' 'PAYLOAD=marker_round_trip'
  verification_mark_step fresh_install_vless_openvpn_endpoint_payload_success

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision "${proxy_create_revision}" --id openvpn-endpoint-proxy-verification > "${proxy_delete}"
  verification_capture_file_if_present "${proxy_delete}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/proxy-delete.json"
  jq -e --argjson revision "${proxy_delete_revision}" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="openvpn-endpoint-proxy-verification" and .service_restarted==true' \
    "${proxy_delete}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_proxy_deleted
  verification_wait_for_service_active sing-box
  verification_assert_port_not_listening 15091 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/proxy-after-delete.ss-lntp.txt"

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision "${proxy_delete_revision}" --id openvpn-endpoint-client-verification > "${client_delete}"
  verification_capture_file_if_present "${client_delete}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/client-delete.json"
  jq -e --argjson revision "${client_delete_revision}" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="openvpn-endpoint-client-verification" and .service_restarted==true' \
    "${client_delete}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_client_deleted
  verification_wait_for_service_active sing-box

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision "${client_delete_revision}" --id openvpn-endpoint-server-verification > "${server_delete}"
  verification_capture_file_if_present "${server_delete}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/server-delete.json"
  jq -e --argjson revision "${server_delete_revision}" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="openvpn-endpoint-server-verification" and .service_restarted==true' \
    "${server_delete}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_server_deleted
  verification_wait_for_service_active sing-box
  verification_assert_port_not_listening 11994 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/server-after-delete.ss-lntp.txt"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/after-delete.check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint/after-delete.env" \
    'RESULT=success' 'RESOURCES=managed_components_removed'
  verification_mark_step fresh_install_vless_openvpn_endpoint_resources_cleaned

  # Run the same synthetic pair over OpenVPN's UDP transport after the TCP
  # records have been removed.  Keeping this as a separate revision window and
  # artifact directory proves that the component graph does not accidentally
  # reuse a TCP endpoint or leave its listener behind.
  local udp_expected_revision="${server_delete_revision}"
  local udp_server_create_revision=$((udp_expected_revision + 1))
  local udp_client_create_revision=$((udp_expected_revision + 2))
  local udp_proxy_create_revision=$((udp_expected_revision + 3))
  local udp_proxy_delete_revision=$((udp_expected_revision + 4))
  local udp_client_delete_revision=$((udp_expected_revision + 5))
  local udp_server_delete_revision=$((udp_expected_revision + 6))
  local udp_server_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-server.json"
  local udp_client_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-client.json"
  local udp_proxy_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-proxy.json"
  local udp_server_create="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-server-create.json"
  local udp_client_create="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-client-create.json"
  local udp_proxy_create="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-proxy-create.json"
  local udp_proxy_delete="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-proxy-delete.json"
  local udp_client_delete="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-client-delete.json"
  local udp_server_delete="${VERIFY_REMOTE_LOCAL_TREE_DIR}/openvpn-endpoint-udp-server-delete.json"
  local udp_marker_response
  local udp_journal_path
  local udp_journal_relative="${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/journalctl.txt"
  local udp_curl_status=1

  (umask 077; jq -n --arg cert "${endpoint_cert_path}" --arg key "${endpoint_key_path}" '
    {id:"openvpn-endpoint-udp-server-verification",role:"endpoint",type:"openvpn-server",
     tag:"openvpn-endpoint-udp-server-verification",enabled:true,route_rules:[],config:{
       mode:"tls",system:false,listen:"127.0.0.1",listen_port:11995,network:"udp",
       address:["10.78.0.1/24"],users:[{username:"probe",password:"probe-pass"}],
       tls:{certificate_path:$cert,key_path:$key,verify_client_certificate:"none"}}}' \
    > "${udp_server_record}")
  (umask 077; jq -n --arg cert "${endpoint_cert_path}" '
    {id:"openvpn-endpoint-udp-client-verification",role:"endpoint",type:"openvpn-client",
     tag:"openvpn-endpoint-udp-client-verification",enabled:true,route_rules:[],config:{
       mode:"tls",system:false,server:"127.0.0.1",server_port:11995,network:"udp",
       username:"probe",password:"probe-pass",
       tls:{certificate_path:$cert,server_name:"sing-box-vps-openvpn-verification.invalid",
         remote_certificate_tls:"server"}}}' \
    > "${udp_client_record}")
  (umask 077; jq -n --arg marker_address "${marker_address}" --argjson marker_port "${marker_port}" '
    {id:"openvpn-endpoint-udp-proxy-verification",role:"inbound",type:"direct",
     tag:"openvpn-endpoint-udp-proxy-verification",enabled:true,
     route_rules:[{inbound:["openvpn-endpoint-udp-proxy-verification"],action:"route",
       outbound:"openvpn-endpoint-udp-client-verification"}],config:{
       listen:"127.0.0.1",listen_port:15092,override_address:$marker_address,
       override_port:$marker_port}}' \
    > "${udp_proxy_record}")

  bash /usr/local/bin/sbv agent component create --json --yes --allow-public \
    --expected-revision "${udp_expected_revision}" --file "${udp_server_record}" > "${udp_server_create}"
  verification_capture_file_if_present "${udp_server_create}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/server-create.json"
  jq -e --argjson revision "${udp_server_create_revision}" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="openvpn-server" and .service_restarted==true' "${udp_server_create}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_server_created
  verification_wait_for_service_active sing-box

  bash /usr/local/bin/sbv agent component create --json --yes \
    --expected-revision "${udp_server_create_revision}" --file "${udp_client_record}" > "${udp_client_create}"
  verification_capture_file_if_present "${udp_client_create}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/client-create.json"
  jq -e --argjson revision "${udp_client_create_revision}" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="openvpn-client" and .service_restarted==true' "${udp_client_create}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_client_created
  verification_wait_for_service_active sing-box

  bash /usr/local/bin/sbv agent component create --json --yes \
    --expected-revision "${udp_client_create_revision}" --file "${udp_proxy_record}" > "${udp_proxy_create}"
  verification_capture_file_if_present "${udp_proxy_create}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/proxy-create.json"
  jq -e --argjson revision "${udp_proxy_create_revision}" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="direct" and .service_restarted==true' "${udp_proxy_create}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_proxy_created
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/config.check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/config.json" \
    jq -c '{endpoints:[.endpoints[] | select(.tag == "openvpn-endpoint-udp-server-verification" or
      .tag == "openvpn-endpoint-udp-client-verification")],inbounds:[.inbounds[] |
      select(.tag == "openvpn-endpoint-udp-proxy-verification")],route:{rules:[.route.rules[] |
      select(.outbound == "openvpn-endpoint-udp-client-verification")]}}' \
    /root/sing-box-vps/config.json
  jq -e '.endpoints | length == 2 and
    any(.[]; .type=="openvpn-server" and .system==false and .network=="udp") and
    any(.[]; .type=="openvpn-client" and .system==false and .network=="udp")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/config.json")" >/dev/null
  verification_assert_udp_port_listening 11995 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/server-listener.ss-lunp.txt"
  verification_assert_port_listening 15092 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/proxy-listener.ss-lntp.txt"

  udp_marker_response=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/marker.response.txt")
  for _ in {1..20}; do
    if curl --fail --silent --show-error --max-time 5 --noproxy '*' \
      http://127.0.0.1:15092/ > "${udp_marker_response}" 2> \
      "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/curl.stderr.txt")"; then
      udp_curl_status=0
      break
    fi
    sleep 0.5
  done
  [[ "${udp_curl_status}" == 0 ]]
  grep -Fqx "${marker}" "${udp_marker_response}"
  grep -Fqx '/' "${marker_access}"
  verification_capture_best_effort_command "${udp_journal_relative}" \
    journalctl -u sing-box -n 160 --no-pager
  udp_journal_path=$(verification_artifact_path "${udp_journal_relative}")
  grep -Fq 'peer connected' "${udp_journal_path}"
  grep -Fq 'tunnel established to 127.0.0.1:11995 over udp' "${udp_journal_path}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/result.env" \
    'RESULT=success' 'TRANSPORT=udp' 'SYSTEM_INTERFACE=false' \
    'AUTH=username_password' 'PAYLOAD=marker_round_trip'
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_payload_success

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision "${udp_proxy_create_revision}" --id openvpn-endpoint-udp-proxy-verification > "${udp_proxy_delete}"
  verification_capture_file_if_present "${udp_proxy_delete}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/proxy-delete.json"
  jq -e --argjson revision "${udp_proxy_delete_revision}" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="openvpn-endpoint-udp-proxy-verification" and .service_restarted==true' \
    "${udp_proxy_delete}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_proxy_deleted
  verification_wait_for_service_active sing-box
  verification_assert_port_not_listening 15092 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/proxy-after-delete.ss-lntp.txt"

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision "${udp_proxy_delete_revision}" --id openvpn-endpoint-udp-client-verification > "${udp_client_delete}"
  verification_capture_file_if_present "${udp_client_delete}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/client-delete.json"
  jq -e --argjson revision "${udp_client_delete_revision}" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="openvpn-endpoint-udp-client-verification" and .service_restarted==true' \
    "${udp_client_delete}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_client_deleted
  verification_wait_for_service_active sing-box

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision "${udp_client_delete_revision}" --id openvpn-endpoint-udp-server-verification > "${udp_server_delete}"
  verification_capture_file_if_present "${udp_server_delete}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/server-delete.json"
  jq -e --argjson revision "${udp_server_delete_revision}" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="openvpn-endpoint-udp-server-verification" and .service_restarted==true' \
    "${udp_server_delete}" >/dev/null
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_server_deleted
  verification_wait_for_service_active sing-box
  verification_capture_best_effort_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/server-after-delete.ss-lunp.txt" \
    verification_ss_udp_output
  ! verification_udp_port_is_listening 11995
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/after-delete.check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/openvpn-endpoint-udp/after-delete.env" \
    'RESULT=success' 'RESOURCES=managed_components_removed'
  verification_mark_step fresh_install_vless_openvpn_endpoint_udp_resources_cleaned
  if [[ -n "${OPENVPN_ENDPOINT_MARKER_PID:-}" ]]; then
    kill "${OPENVPN_ENDPOINT_MARKER_PID}" 2>/dev/null || true
    wait "${OPENVPN_ENDPOINT_MARKER_PID}" 2>/dev/null || true
    OPENVPN_ENDPOINT_MARKER_PID=''
  fi
  rm -rf -- "${endpoint_cert_dir}"
}

verification_scenario_fresh_install_vless() {
  local config_uuid
  local env_uuid
  local instance_state_file=/root/sing-box-vps/protocols/vless-reality.d/main.env
  local current_port
  local expected_port=443
  local status_output_path
  local version_output_path
  local OPENVPN_ENDPOINT_MARKER_PID=''

  verification_prepare_remote_local_tree
  trap 'set +e; if [[ -n "${OPENVPN_ENDPOINT_MARKER_PID:-}" ]]; then kill "${OPENVPN_ENDPOINT_MARKER_PID}" 2>/dev/null || true; wait "${OPENVPN_ENDPOINT_MARKER_PID}" 2>/dev/null || true; fi; rm -rf -- /tmp/sing-box-vps-verification-openvpn; verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_vless\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e /root/sing-box-vps/config.json
  test ! -e /etc/systemd/system/sing-box.service
  test ! -e /usr/local/bin/sbv
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'EOF'
1

1

443
2
www.cloudflare.com
n
1
n
n
n
0
EOF
  verification_mark_step fresh_install_vless_after_install
  test -f /root/sing-box-vps/config.json
  test -f /etc/systemd/system/sing-box.service
  test -x /usr/local/bin/sbv
  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/vless-reality.env
  test -f "${instance_state_file}"
  verification_mark_step fresh_install_vless_files_present
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  config_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  env_uuid=$(grep '^UUID=' "${instance_state_file}" | cut -d'=' -f2- || true)
  verification_mark_step fresh_install_vless_values_loaded
  [[ "${current_port}" == "${expected_port}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'DEFAULT_INSTANCE_ID=main' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'INSTANCE_IDS=main' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'PORT=443' "${instance_state_file}"
  grep -Fqx 'SNI=www.cloudflare.com' "${instance_state_file}"
  verification_mark_step fresh_install_vless_static_asserts
  [[ -n "${config_uuid}" ]]
  [[ "${config_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  [[ -n "${env_uuid}" ]]
  [[ "${env_uuid}" == "${config_uuid}" ]]
  [[ "${env_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  ! grep -Fq 'stale.example.com' "${instance_state_file}"
  verification_mark_step fresh_install_vless_uuid_asserts
  verification_wait_for_service_active sing-box
  verification_mark_step fresh_install_vless_service_active
  version_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box.version.txt")
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box.version.txt" sing-box version
  grep -Fqx 'sing-box version 1.14.0' "${version_output_path}"
  verification_mark_step fresh_install_vless_version_checked
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_mark_step fresh_install_vless_config_checked
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_mark_step fresh_install_vless_port_listening
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq '运行状态摘要' "${status_output_path}"
  grep -Fq 'sing-box: active' "${status_output_path}"
  grep -Fq 'Warp: 未开启' "${status_output_path}"
  grep -Fq '配置文件: /root/sing-box-vps/config.json' "${status_output_path}"
  ! grep -Fq '协议:' "${status_output_path}"
  ! grep -Fq '地址:' "${status_output_path}"
  ! grep -Fq '端口:' "${status_output_path}"
  verification_mark_step fresh_install_vless_status_menu
  verification_run_protocol_probes
  verification_mark_step fresh_install_vless_protocol_probes

  if [[ "${VERIFY_REMOTE_SKIP_PRIVILEGED_RESOURCES:-0}" == "1" ]] ||
    [[ ! -e /dev/net/tun ]] || ! command -v ip >/dev/null 2>&1; then
    verification_mark_step fresh_install_vless_tun_resources_unavailable
    verification_run_openvpn_endpoint_runtime_probe 0
    return 0
  fi

  # The privileged verification container can exercise the core-owned part of
  # a Linux TUN lifecycle.  The component transaction itself remains the
  # owner of state/config/service rollback; host PREROUTING policy is not
  # installed or inferred here.
  local tun_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-record.json"
  local tun_create_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-create.json"
  local tun_delete_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-delete.json"
  local tun_diagnose_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-diagnose.json"
  local tun_after_delete_diagnose_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-after-delete-diagnose.json"
  (umask 077; jq -n '{id:"tun-resource-verification",role:"inbound",type:"tun",
    tag:"tun-resource-verification",enabled:true,route_rules:[],config:{
    interface_name:"sbv-tun",address:["172.19.0.1/30"],auto_route:true,
    strict_route:true}}' > "${tun_record}")
  bash /usr/local/bin/sbv agent component create --json --yes --allow-public \
    --expected-revision 0 --file "${tun_record}" > "${tun_create_json}"
  verification_capture_file_if_present "${tun_create_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-create.json"
  jq -e '.ok==true and .operation=="create" and .revision==1 and
    .type=="tun" and .service_restarted==true' "${tun_create_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_component_created
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-interface.json" \
    ip -j link show dev sbv-tun
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules.json" \
    ip -j rule show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes.json" \
    ip -j route show table all
  jq -e 'any(.[]; .ifname == "sbv-tun")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-interface.json")" >/dev/null
  jq -e 'any(.[]; (.priority == 9000) and ((.table // "" | tostring) == "2022"))' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules.json")" >/dev/null
  jq -e 'any(.[]; ((.table // "main" | tostring) == "2022") and .dev == "sbv-tun")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes.json")" >/dev/null
  bash /usr/local/bin/sbv agent component diagnose --json > "${tun_diagnose_json}"
  verification_capture_file_if_present "${tun_diagnose_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-diagnose.json"
  jq -e '.ok==true and .data.transparent_resources.status=="available" and
    .data.transparent_resources.service_active==true and
    ([.data.transparent_resources.resources[] | select(.type=="tun" and
      .interface.status=="present" and .policy_routing.status=="present" and
      .rule.status=="present")] | length == 1)' "${tun_diagnose_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_resources_observed

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision 1 --id tun-resource-verification > "${tun_delete_json}"
  verification_capture_file_if_present "${tun_delete_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-delete.json"
  jq -e '.ok==true and .operation=="delete" and .revision==2 and
    .id=="tun-resource-verification" and .service_restarted==true' \
    "${tun_delete_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_component_deleted
  verification_wait_for_service_active sing-box
  verification_capture_best_effort_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-interface-after-delete.json" \
    ip -j link show dev sbv-tun
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules-after-delete.json" \
    ip -j rule show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes-after-delete.json" \
    ip -j route show table all
  if ip -j link show dev sbv-tun >/dev/null 2>&1; then
    printf 'TUN interface remained after managed component deletion\n' >&2
    return 1
  fi
  ! jq -e 'any(.[]; (.priority == 9000) and ((.table // "" | tostring) == "2022"))' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules-after-delete.json")" >/dev/null
  ! jq -e 'any(.[]; ((.table // "main" | tostring) == "2022") and .dev == "sbv-tun")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes-after-delete.json")" >/dev/null
  bash /usr/local/bin/sbv agent component diagnose --json > "${tun_after_delete_diagnose_json}"
  verification_capture_file_if_present "${tun_after_delete_diagnose_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-after-delete-diagnose.json"
  jq -e '.ok==true and .data.transparent_resources.status=="available" and
    (.data.transparent_resources.resources | length == 0)' \
    "${tun_after_delete_diagnose_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_resources_cleaned

  # Bridge is an outbound L3 component, but like TUN it creates a core-owned
  # Linux TUN plus iproute2 rules/routes.  Exercise the explicit table/rule
  # path and ensure the same transaction removes every core-owned resource.
  local bridge_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/bridge-resource-record.json"
  local bridge_create_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/bridge-resource-create.json"
  local bridge_delete_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/bridge-resource-delete.json"
  local bridge_diagnose_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/bridge-resource-diagnose.json"
  local bridge_after_delete_diagnose_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/bridge-resource-after-delete-diagnose.json"
  (umask 077; jq -n '{id:"bridge-resource-verification",role:"outbound",type:"bridge",
    tag:"bridge-resource-verification",enabled:true,route_rules:[],config:{
    interface:"lo",bridge_name:"sbv-bridge",iproute2_table_index:2200,
    iproute2_rule_index:120}}' > "${bridge_record}")
  bash /usr/local/bin/sbv agent component create --json --yes \
    --expected-revision 2 --file "${bridge_record}" > "${bridge_create_json}"
  verification_capture_file_if_present "${bridge_create_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-resource-create.json"
  jq -e '.ok==true and .operation=="create" and .revision==3 and
    .type=="bridge" and .service_restarted==true' "${bridge_create_json}" >/dev/null
  verification_mark_step fresh_install_vless_bridge_component_created
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-resource-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-rules.json" \
    ip -j rule show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-routes.json" \
    ip -j route show table all
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-links.json" \
    ip -j link show
  jq -e 'any(.[]; .ifname == "sbv-bridge0")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-links.json")" >/dev/null
  jq -e 'any(.[]; (.priority == 120) and .iif == "sbv-bridge0" and
    ((.table // "") | tostring) == "2200") and
    any(.[]; (.priority == 121) and .dst == "192.0.2.1" and
      ((.table // "main") | tostring) == "main")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-rules.json")" >/dev/null
  jq -e 'any(.[]; .dst == "192.0.2.1" and .dev == "sbv-bridge0" and
    ((.table // "main") | tostring) == "main") and
    any(.[]; ((.table // "main") | tostring) == "2200" and
      ((.dst // "default") == "default" or .type == "blackhole"))' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-routes.json")" >/dev/null
  bash /usr/local/bin/sbv agent component diagnose --json > "${bridge_diagnose_json}"
  verification_capture_file_if_present "${bridge_diagnose_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-resource-diagnose.json"
  jq -e '.ok==true and .data.transparent_resources.status=="available" and
    ([.data.transparent_resources.resources[] | select(.type=="bridge" and
      .interface_name=="sbv-bridge0" and .policy_routing.status=="present" and
      .rule.status=="present")] | length == 1)' "${bridge_diagnose_json}" >/dev/null
  verification_mark_step fresh_install_vless_bridge_resources_observed

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision 3 --id bridge-resource-verification > "${bridge_delete_json}"
  verification_capture_file_if_present "${bridge_delete_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-resource-delete.json"
  jq -e '.ok==true and .operation=="delete" and .revision==4 and
    .id=="bridge-resource-verification" and .service_restarted==true' \
    "${bridge_delete_json}" >/dev/null
  verification_mark_step fresh_install_vless_bridge_component_deleted
  verification_wait_for_service_active sing-box
  verification_capture_best_effort_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-links-after-delete.json" \
    ip -j link show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-rules-after-delete.json" \
    ip -j rule show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-routes-after-delete.json" \
    ip -j route show table all
  if ip -j link show dev sbv-bridge0 >/dev/null 2>&1; then
    printf 'bridge interface remained after managed component deletion\n' >&2
    return 1
  fi
  ! jq -e 'any(.[]; (.priority == 120) and .iif == "sbv-bridge0") or
    any(.[]; (.priority == 121) and .dst == "192.0.2.1")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-rules-after-delete.json")" >/dev/null
  ! jq -e 'any(.[]; .dev == "sbv-bridge0" and
    (((.dst // "") == "192.0.2.1") or ((.table // "main") | tostring) == "2200"))' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-routes-after-delete.json")" >/dev/null
  bash /usr/local/bin/sbv agent component diagnose --json > "${bridge_after_delete_diagnose_json}"
  verification_capture_file_if_present "${bridge_after_delete_diagnose_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/bridge-resource-after-delete-diagnose.json"
  jq -e '.ok==true and .data.transparent_resources.status=="available" and
    (.data.transparent_resources.resources | length == 0)' \
    "${bridge_after_delete_diagnose_json}" >/dev/null
  verification_mark_step fresh_install_vless_bridge_resources_cleaned

  verification_run_openvpn_endpoint_runtime_probe 4
}
