verification_scenario_fresh_install_hysteria() {
  local expected_port=1086
  local cert_path=/tmp/sing-box-vps-verification-hysteria.crt
  local key_path=/tmp/sing-box-vps-verification-hysteria.key
  local config_file=/root/sing-box-vps/config.json
  local state_file=/root/sing-box-vps/protocols/hysteria.env
  local store_file=/root/sing-box-vps/protocols/instances/hysteria.json

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_hysteria\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  rm -f -- "${cert_path}" "${key_path}"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -subj '/CN=hysteria.verification.invalid' \
    -addext 'subjectAltName=DNS:hysteria.verification.invalid' \
    -keyout "${key_path}" -out "${cert_path}" >/dev/null 2>&1
  chmod 600 "${cert_path}" "${key_path}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

13
${expected_port}
1
hysteria-user
hysteria-verification-auth
hysteria.verification.invalid
${cert_path}
${key_path}
1
100
100
n
0
n
0


n
n
0
EOF
  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  grep -Fqx 'INSTALLED_PROTOCOLS=hysteria' /root/sing-box-vps/protocols/index.env
  jq -e --argjson port "${expected_port}" --arg cert "${cert_path}" --arg key "${key_path}" '
    .protocol=="hysteria" and .revision==1 and (.instances|length)==1 and
    .instances[0].id=="main" and .instances[0].tag=="hysteria-in" and
    .instances[0].listen=={address:"127.0.0.1",port:$port} and
    .instances[0].authentication.users==[
      {name:"hysteria-user",auth_str:"hysteria-verification-auth"}] and
    .instances[0].tls=={enabled:true,server_name:"hysteria.verification.invalid",
      certificate_path:$cert,key_path:$key} and
    .instances[0].client_trust=="certificate" and
    .instances[0].bandwidth=={up_mbps:100,down_mbps:100} and
    .instances[0].obfs=={enabled:false,password:""} and
    .instances[0].hysteria=={
      connection_receive_window:"",disable_path_mtu_discovery:false,
      initial_packet_size:0,max_concurrent_streams:0,stream_receive_window:""}
  ' "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    (.inbounds|length)==1 and .inbounds[0].type=="hysteria" and
    .inbounds[0].tag=="hysteria-in" and .inbounds[0].listen=="127.0.0.1" and
    .inbounds[0].listen_port==$port and .inbounds[0].users==[
      {name:"hysteria-user",auth_str:"hysteria-verification-auth"}] and
    .inbounds[0].tls.enabled==true and .inbounds[0].tls.alpn==["h3"] and
    .inbounds[0].up_mbps==100 and .inbounds[0].down_mbps==100 and
    (.inbounds[0]|has("obfs")|not)
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_udp_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lunp.txt"
  verification_run_protocol_probes
  verification_execute_protocol_udp_probe hysteria "${config_file}"
}
