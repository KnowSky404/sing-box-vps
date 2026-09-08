verification_scenario_fresh_install_trojan() {
  local expected_port=1084 cert_path key_path
  local config_file=/root/sing-box-vps/config.json
  local state_file=/root/sing-box-vps/protocols/trojan.env
  local store_file=/root/sing-box-vps/protocols/instances/trojan.json
  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  cert_path="${VERIFY_REMOTE_LOCAL_TREE_DIR}/trojan.crt"
  key_path="${VERIFY_REMOTE_LOCAL_TREE_DIR}/trojan.key"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -subj '/CN=trojan.verification.invalid' \
    -addext 'subjectAltName=DNS:trojan.verification.invalid' \
    -keyout "${key_path}" -out "${cert_path}" >/dev/null 2>&1
  chmod 600 "${cert_path}" "${key_path}"
  printf 'SCENARIO=fresh_install_trojan\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

8
${expected_port}
2
first
trojan-first-password
second
trojan-second-password
y
${cert_path}
${key_path}
trojan.verification.invalid
1
1
n
n
0
EOF
  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  grep -Fqx 'INSTALLED_PROTOCOLS=trojan' /root/sing-box-vps/protocols/index.env
  jq -e '.protocol=="trojan" and .revision==1 and (.instances|length)==1 and
    .instances[0].id=="main" and .instances[0].tag=="trojan-in" and
    .instances[0].listen=={address:"127.0.0.1",port:1084} and
    .instances[0].authentication.users==[
      {name:"first",password:"trojan-first-password"},{name:"second",password:"trojan-second-password"}] and
    .instances[0].tls.enabled==true and .instances[0].client_trust=="certificate" and
    .instances[0].transport=={type:"none"}' "${store_file}" >/dev/null
  jq -e '(.inbounds|length)==1 and .inbounds[0].type=="trojan" and
    .inbounds[0].listen=="127.0.0.1" and .inbounds[0].listen_port==1084 and
    (.inbounds[0].users|length)==2 and (.inbounds[0]|has("transport")|not) and
    .inbounds[0].tls.enabled==true' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_run_protocol_probes
}
