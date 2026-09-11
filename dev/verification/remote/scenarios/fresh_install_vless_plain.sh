verification_scenario_fresh_install_vless_plain() {
  local expected_port=1086 cert_path key_path quic_record quic_result
  local config_file=/root/sing-box-vps/config.json
  local state_file=/root/sing-box-vps/protocols/vless-plain.env
  local store_file=/root/sing-box-vps/protocols/instances/vless-plain.json

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_vless_plain\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

10
${expected_port}
1
probe
11111111-1111-4111-8111-111111111111

n
1
n
n
0
EOF
  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-plain' /root/sing-box-vps/protocols/index.env
  jq -e --argjson port "${expected_port}" '
    .protocol=="vless-plain" and .revision==1 and (.instances|length)==1 and
    .instances[0].id=="main" and .instances[0].tag=="vless-plain-in" and
    .instances[0].listen=={address:"127.0.0.1",port:$port} and
    .instances[0].authentication.users==[
      {name:"probe",uuid:"11111111-1111-4111-8111-111111111111",flow:""}] and
    .instances[0].tls=={enabled:false} and .instances[0].client_trust=="system" and
    .instances[0].transport=={type:"none"}
  ' "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    ([.inbounds[] | select(.type=="vless" and (.tls.reality? == null))][0]) as $inbound |
    (.inbounds|length)==1 and $inbound.tag=="vless-plain-in" and
    $inbound.listen=="127.0.0.1" and $inbound.listen_port==$port and
    $inbound.users==[{name:"probe",uuid:"11111111-1111-4111-8111-111111111111"}] and
    ($inbound|has("tls")|not) and ($inbound|has("transport")|not)
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check-initial.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.initial.ss-lntp.txt"

  # Reconfigure the same managed instance to QUIC with a temporary test
  # certificate.  This keeps the ordinary TCP install coverage while proving
  # that VLESS plain QUIC renders as a UDP listener and carries UDP payloads.
  cert_path="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-plain.crt"
  key_path="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-plain.key"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -subj '/CN=vless-plain.verification.invalid' \
    -addext 'subjectAltName=DNS:vless-plain.verification.invalid' \
    -keyout "${key_path}" -out "${cert_path}" >/dev/null 2>&1
  chmod 600 "${cert_path}" "${key_path}"
  quic_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-plain-quic.json"
  (umask 077; jq -n --arg cert "${cert_path}" --arg key "${key_path}" --argjson port "${expected_port}" '
    {id:"main",name:"VLESS plain QUIC verification",tag:"vless-plain-in",
     listen:{address:"127.0.0.1",port:$port},
     authentication:{users:[{name:"probe",uuid:"11111111-1111-4111-8111-111111111111",flow:""}]},
     tls:{enabled:true,server_name:"vless-plain.verification.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",transport:{type:"quic"},
     outbound_policy:"default",dependencies:[]}' > "${quic_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance replace vless-plain --json --yes \
    --expected-revision 1 --file "${quic_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-plain-quic-replace.json"
  quic_result="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vless-plain-quic-replace.json"
  jq -e '.ok==true and .protocol=="vless-plain" and .changed==true and .revision==2' \
    "${quic_result}" >/dev/null
  jq -e --arg cert "${cert_path}" --arg key "${key_path}" '
    .protocol=="vless-plain" and .revision==2 and (.instances|length)==1 and
    .instances[0].transport=={type:"quic"} and
    .instances[0].tls=={enabled:true,server_name:"vless-plain.verification.invalid",
      certificate_path:$cert,key_path:$key} and .instances[0].client_trust=="certificate"
  ' "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    (.inbounds|length)==1 and
    .inbounds[0].type=="vless" and .inbounds[0].tag=="vless-plain-in" and
    .inbounds[0].listen=="127.0.0.1" and .inbounds[0].listen_port==$port and
    .inbounds[0].users==[{name:"probe",uuid:"11111111-1111-4111-8111-111111111111"}] and
    .inbounds[0].transport=={type:"quic"} and
    .inbounds[0].tls.enabled==true and .inbounds[0].tls.alpn==["h3"]
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_udp_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lunp.txt"
  verification_run_protocol_probes
  verification_execute_protocol_udp_probe vless-plain "${config_file}"
}
