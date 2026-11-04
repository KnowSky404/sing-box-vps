# Typed protocol fixtures shared by focused probes and pure coexistence.
# Definitions only: sourcing this file never installs protocols or starts peers.
verification_protocol_record() {
  local protocol=${1:?protocol required} port tag
  case "${protocol}" in
    mixed) port=1080; tag=mixed-in ;;
    socks) port=1081; tag=socks-in ;;
    http) port=1082; tag=http-in ;;
    shadowsocks) port=1083; tag=ss-in ;;
    trojan) port=1084; tag=trojan-in ;;
    vmess) port=1085; tag=vmess-in ;;
    snell) port=1086; tag=snell-in ;;
    tuic) port=1087; tag=tuic-in ;;
    shadowtls) port=1088; tag=shadowtls-in ;;
    naive) port=1091; tag=naive-in ;;
    hy2) port=8443; tag=hy2-in ;;
    anytls) port=9443; tag=anytls-in ;;
    *) printf 'unsupported typed protocol fixture\n' >&2; return 2 ;;
  esac
  jq -n --arg protocol "${protocol}" --argjson port "${port}" --arg tag "${tag}" \
    --arg cert "${cert_path:-}" --arg key "${key_path:-}" '
    {id:"main",name:($protocol+" verification"),tag:$tag,
     listen:{address:"127.0.0.1",port:$port},outbound_policy:"default",dependencies:[]} as $base |
    {enabled:true,server_name:"sing-box-vps-verification.invalid",certificate_path:$cert,key_path:$key} as $tls |
    if $protocol=="mixed" or $protocol=="socks" then
      $base+{authentication:{enabled:true,username:($protocol+"-user"),password:($protocol+"-pass")}}
    elif $protocol=="http" then
      $base+{authentication:{enabled:true,username:"http-user",password:"http-pass"},tls:{enabled:false}}
    elif $protocol=="shadowsocks" then
      $base|.listen.network=["tcp","udp"] |
      .+{authentication:{method:"2022-blake3-aes-128-gcm",password:"MDEyMzQ1Njc4OWFiY2RlZg==",users:[]}}
    elif $protocol=="trojan" then
      $base+{authentication:{users:[{name:"main",password:"trojan-verification-password"}]},
        tls:$tls,client_trust:"certificate",transport:{type:"quic"}}
    elif $protocol=="vmess" then
      $base+{authentication:{users:[{name:"vmess-user",uuid:"22222222-2222-4222-8222-222222222222",alter_id:0,security:"auto"}]},
        tls:$tls,client_trust:"certificate",transport:{type:"quic"}}
    elif $protocol=="snell" then
      $base+{authentication:{psk:"snell-v6-psk-123456",users:[{name:"snell-user",userkey:"snell-user-key"}]},
        version:6,obfs_mode:"",obfs_host:"",mode:"default"}
    elif $protocol=="tuic" then
      $base+{authentication:{users:[{name:"tuic-user",uuid:"11111111-1111-4111-8111-111111111111",password:"tuic-verification-password"}]},
        tls:$tls,client_trust:"certificate",tuic:{auth_timeout_seconds:3,congestion_control:"bbr",heartbeat_seconds:10,
        udp_over_stream:false,udp_relay_mode:"native",zero_rtt_handshake:false}}
    elif $protocol=="shadowtls" then
      $base+{version:3,authentication:{password:"",users:[{name:"shadow-user",password:"shadowtls-verification-password"}]},
        handshake:{server:"127.0.0.1",server_port:1090},handshake_for_server_name:{},
        strict_mode:false,wildcard_sni:"off",detour:{tag:"shadowtls-inner-main",listen:{address:"127.0.0.1",port:1089}},
        dependencies:["shadowtls-inner-main"],client_trust:"certificate",
        client_tls:{server_name:"sing-box-vps-verification.invalid",certificate_path:$cert}}
    elif $protocol=="naive" then
      $base|.listen.network=["tcp"] |
      .+{authentication:{users:[{name:"naive-user",username:"naive-user",password:"naive-verification-password"}]},
        tls:$tls,client_trust:"certificate",naive:{extra_headers:{},insecure_concurrency:0,quic:false,
        quic_congestion_control:"bbr",quic_session_receive_window:"",stream_receive_window:""}}
    elif $protocol=="hy2" then
      $base+{authentication:{users:[{name:"hy2-user",password:"hy2-pass"}]},tls:$tls,client_trust:"certificate",
        bandwidth:{up_mbps:null,down_mbps:null},obfs:{enabled:false,type:"",password:""},masquerade:""}
    elif $protocol=="anytls" then
      $base+{authentication:{users:[{name:"anytls-user",password:"anytls-pass"}]},tls:$tls,client_trust:"certificate"}
    else error("unsupported fixture") end'
}

verification_protocol_prepare() {
  local protocol=${1:?protocol required} record response config=/root/.sing-box-vps/runtime/config.json
  case "${protocol}" in
    socks)
      jq -e 'any(.inbounds[]; .type=="socks" and .tag=="socks-in" and .listen_port==1081)' "${config}" >/dev/null
      return 0
      ;;
    vless-reality)
      # REALITY writes are explicitly interactive-only. This is its existing
      # menu path under test, not an advertised structured write operation.
      # The original public Cloudflare handshake-cover boundary is retained.
      SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" \
        > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/reality-menu.txt")" 2>&1 <<'REALITY_MENU'
1
1
1

443
2
www.cloudflare.com
n
1
n
0
REALITY_MENU
      jq -e 'any(.inbounds[]; .type=="vless" and .tls.reality.enabled==true and .listen_port==443)' "${config}" >/dev/null
      verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/reality-boundary.env" \
        'AUTOMATION=interactive_only_menu_fixture' 'COVER=www.cloudflare.com_external_tls'
      ;;
    *)
      case "${protocol}" in
        hy2|anytls|trojan|vmess|tuic|shadowtls|naive) verification_fixture_tls ;;
      esac
      if [[ "${protocol}" == shadowtls ]]; then verification_fixture_tls_cover; fi
      record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/protocol-${protocol}.json"
      verification_protocol_record "${protocol}" > "${record}"
      chmod 600 "${record}"
      response=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/${protocol}-create.json")
      bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create "${protocol}" --json --yes \
        --expected-revision 0 --file "${record}" > "${response}"
      jq -e --arg protocol "${protocol}" '.ok and .protocol==$protocol and .changed and .revision==1 and
        .transaction.status=="success" and .transaction.phase=="committed" and
        .transaction.operation_exit_code==0' "${response}" >/dev/null
      jq -e --arg protocol "${protocol}" '.protocol==$protocol and .revision==1 and
        (.instances|length)==1 and .instances[0].id=="main"' \
        "/root/.sing-box-vps/runtime/protocols/instances/${protocol}.json" >/dev/null
      ;;
  esac
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/${protocol}-created-check.txt" sing-box check -c "${config}"
  verification_mark_step "${protocol}-created-and-checked"
}

verification_protocol_probe() {
  local protocol=${1:?protocol required} config=/root/.sing-box-vps/runtime/config.json
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/${protocol}-check.txt" sing-box check -c "${config}"
  verification_execute_single_protocol_probe "${protocol}" "${config}"
  verification_protocol_udp_probe "${protocol}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/${protocol}-probe.result.env" \
    "PROTOCOL=${protocol}" 'RESULT=success' 'CORE_CHECK=passed'
}

verification_protocol_udp_probe() {
  local protocol=${1:?protocol required} config=/root/.sing-box-vps/runtime/config.json journal
  case "${protocol}" in
    http|shadowtls)
      verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/${protocol}-udp.result.env" \
        "PROTOCOL=${protocol}" 'RESULT=not_supported' 'CAPABILITY=tcp_proxy_only'
      ;;
    vless-reality|mixed|hy2|anytls|socks|shadowsocks|trojan|tuic|vmess|snell|naive)
      verification_execute_protocol_udp_probe "${protocol}" "${config}"
      ;;
    *) printf 'unsupported protocol probe fixture\n' >&2; return 2 ;;
  esac
  if [[ "${protocol}" == anytls || "${protocol}" == naive ]]; then
    journal=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/${protocol}-udp-journal.txt")
    for _ in {1..20}; do
      journalctl -u sing-box -n 100 --no-pager > "${journal}" 2>&1
      if grep -Fq "inbound/${protocol}[${protocol}-in]: inbound UoT connection" "${journal}"; then break; fi
      sleep 0.1
    done
    grep -Fq "inbound/${protocol}[${protocol}-in]: inbound UoT connection" "${journal}"
  fi
}

verification_protocol_naive_transition() {
  local config_path
  # Naive outbound carries UDP through its explicit UDP-over-TCP adapter when
  # the managed listener has a TCP leg.  Preserve the initial TCP probe tree
  # before replacing the same instance with a UDP-only listener below.
  local naive_udp_journal_artifact=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/naive-udp-journal.txt")
  for _ in {1..20}; do
    journalctl -u sing-box -n 100 --no-pager > "${naive_udp_journal_artifact}" 2>&1
    if grep -Fq 'inbound/naive[naive-in]: inbound UoT connection' \
      "${naive_udp_journal_artifact}"; then
      break
    fi
    sleep 0.1
  done
  grep -Fq 'inbound/naive[naive-in]: inbound UoT connection' \
    "${naive_udp_journal_artifact}"
  verification_capture_tree_if_present \
    "$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive")" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive-tcp-uot"
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive-tcp-uot/result.env" \
    'PROTOCOL=naive' 'RESULT=success' \
    'DATA_PLANE=naive_udp_over_tcp_loopback' 'SERVER_NETWORK=tcp' \
    'CLIENT_TRANSPORT=http2_uot'

  # A UDP-only Naive listener is HTTP/3/QUIC, not a native TCP listener.  Use
  # the same typed instance and revision CAS to prove that the renderer,
  # QUIC exporter and authenticated marker all move together.  UDP payload
  # remains intentionally separate: sing-box's Naive outbound exposes UDP
  # through UoT, which requires the TCP leg exercised above.
  local naive_udp_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-udp-record.json"
  local naive_udp_replace_status=0
  (umask 077; jq -n --arg cert "${cert_path}" --arg key "${key_path}" '
    {id:"main",name:"Naive HTTP3 verification",tag:"naive-in",
     listen:{address:"127.0.0.1",port:1091,network:["udp"]},
     authentication:{users:[{name:"naive-user",username:"naive-user",password:"naive-verification-password"}]},
     tls:{enabled:true,server_name:"sing-box-vps-verification.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",
     naive:{extra_headers:{},insecure_concurrency:0,quic:true,
       quic_congestion_control:"bbr",quic_session_receive_window:"",stream_receive_window:""},
     outbound_policy:"default",dependencies:[]}
  ' > "${naive_udp_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance replace naive --json --yes \
    --expected-revision 1 --file "${naive_udp_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-udp-replace.json"
  naive_udp_replace_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-udp-replace.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/naive-udp-replace.json"
  [[ "${naive_udp_replace_status}" == 0 ]]
  jq -e '.ok==true and .action=="instance" and .protocol=="naive" and
    .changed==true and .revision==2 and .transaction.status=="success" and
    .transaction.phase=="committed" and .transaction.operation_exit_code==0' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/naive-udp-replace.json" >/dev/null
  verification_mark_step naive-udp-instance-replaced
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/naive-http3-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/naive-http3-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e '
    ([.inbounds[] | select(.type == "naive" and .tag == "naive-in" and
      .listen == "127.0.0.1" and .listen_port == 1091 and .network == "udp" and
      .users[0].username == "naive-user" and
      .tls.server_name == "sing-box-vps-verification.invalid")] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step naive-http3-config-asserted
  verification_execute_single_protocol_probe naive /root/.sing-box-vps/runtime/config.json
  jq -e '
    .outbounds | length == 1 and .[0].type == "naive" and
    .[0].quic == true and (.[0] | has("udp_over_tcp") | not)
  ' "$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive/client.json")" >/dev/null
  grep -Fq 'protocol: quic/1+spdy/3' \
    "$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive/client.stderr.txt")"
  local naive_http3_journal_artifact=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/naive-http3-journal.txt")
  journalctl -u sing-box -n 100 --no-pager > "${naive_http3_journal_artifact}" 2>&1
  grep -Fq 'inbound/naive[naive-in]: [naive-user] inbound connection' \
    "${naive_http3_journal_artifact}"
  verification_capture_tree_if_present \
    "$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive")" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive-udp-http3"
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/naive-udp-http3/result.env" \
    'PROTOCOL=naive' 'RESULT=success' \
    'DATA_PLANE=naive_http3_tcp_loopback' 'SERVER_NETWORK=udp' \
    'CLIENT_TRANSPORT=quic_http3'
  verification_mark_step naive-http3-probe-complete

}

verification_protocol_snell_transition() {
  local config_path
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
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/snell-v5-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
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
  ' /root/.sing-box-vps/runtime/protocols/instances/snell.json >/dev/null
  verification_mark_step snell-v5-config-asserted
  verification_execute_single_protocol_probe snell /root/.sing-box-vps/runtime/config.json
  verification_execute_protocol_udp_probe snell /root/.sing-box-vps/runtime/config.json
  jq -e '
    .outbounds | length == 1 and .[0].type == "snell" and .[0].version == 4 and
    .[0].network == ["tcp", "udp"] and .[0].obfs_mode == "http" and
    .[0].obfs_host == "snell-v5.example.com" and
    (.[0] | has("mode") | not)
  ' "$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/snell/client.json")" >/dev/null

}

verification_protocol_assert_coexistence() {
  local mode=${1:-pure} config_path index_path expected_core_version protocol port configured_network
  [[ "${mode}" == pure || "${mode}" == aggregate ]] || return 2
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/config.json")
  index_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/index.env")
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/libcronet.sha256.txt" \
    sha256sum /root/.sing-box-vps/lib/libcronet.so
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  cp /root/.sing-box-vps/runtime/protocols/index.env "${index_path}"
  jq -en --arg actual "$(sed -n 's/^INSTALLED_PROTOCOLS=//p' "${index_path}")" '
    ($actual|split(",")|sort) == (["vless-reality","mixed","hy2","anytls","socks","http","shadowsocks","trojan","tuic","vmess","snell","shadowtls","naive"]|sort)
  ' >/dev/null
  jq -e --arg mode "${mode}" '
    ([.inbounds[] | .type] | sort) == ((["anytls", "http", "hysteria2", "mixed", "mixed", "naive", "shadowsocks", "shadowtls", "snell", "socks", "trojan", "tuic", "vless", "vmess"] + (if $mode=="aggregate" then ["direct","direct"] else [] end))|sort) and
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
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  expected_core_version=$(verification_supported_core_version)
  grep -Fqx "sing-box version ${expected_core_version}" <(sing-box version)
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  while IFS= read -r protocol; do
    port=$(verification_config_inbound_port_for_protocol \
      "${protocol}" /root/.sing-box-vps/runtime/config.json)
    configured_network=$(verification_config_inbound_network_for_protocol \
      "${protocol}" /root/.sing-box-vps/runtime/config.json)
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

}

verification_protocol_leaf() (
  set -euo pipefail
  local protocol=${1:?protocol required} transition=${2:-none}
  verification_case_context_start
  printf 'SCENARIO=%s\n' "${VERIFY_CURRENT_SCENARIO}"
  verification_protocol_prepare "${protocol}"
  verification_protocol_probe "${protocol}"
  case "${transition}" in
    naive) verification_protocol_naive_transition ;;
    snell) verification_protocol_snell_transition ;;
    none) ;;
    *) return 2 ;;
  esac
)
