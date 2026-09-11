verification_config_inbound_type_for_protocol() {
  verification_protocol_metadata "$1" | jq -er '.type'
}

verification_scenario_multi_protocol_coexistence() {
  local cert_dir
  local cert_path
  local config_type
  local key_path
  local config_path
  local index_path
  local protocol
  local port

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  cert_dir="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shared-tls"
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

  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/config.json")
  index_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/index.env")
  cp /root/sing-box-vps/config.json "${config_path}"
  cp /root/sing-box-vps/protocols/index.env "${index_path}"
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,socks,http,shadowsocks,trojan' "${index_path}"
  jq -e '
    ([.inbounds[] | .type] | sort) == ["anytls", "http", "hysteria2", "mixed", "shadowsocks", "socks", "trojan", "vless"] and
    ([.inbounds[] | select(.type == "vless") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "mixed") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "hysteria2") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "anytls") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "socks") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "http") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "shadowsocks") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "trojan" and .transport.type=="quic" and .tls.alpn==["h3"])] | length == 1)
  ' /root/sing-box-vps/config.json >/dev/null
  grep -Fqx 'sing-box version 1.14.0' <(sing-box version)
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  while IFS= read -r protocol; do
    config_type=$(verification_config_inbound_type_for_protocol "${protocol}")
    port=$(jq -r --arg config_type "${config_type}" \
      '.inbounds[] | select(.type == $config_type) | .listen_port' \
      /root/sing-box-vps/config.json)
    if verification_protocol_metadata "${protocol}" | jq -e \
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
}
