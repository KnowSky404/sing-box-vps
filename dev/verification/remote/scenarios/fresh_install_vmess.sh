verification_scenario_fresh_install_vmess() {
  local expected_port=1085 cert_path key_path
  local config_file=/root/sing-box-vps/config.json
  local state_file=/root/sing-box-vps/protocols/vmess.env
  local store_file=/root/sing-box-vps/protocols/instances/vmess.json

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  cert_path="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vmess.crt"
  key_path="${VERIFY_REMOTE_LOCAL_TREE_DIR}/vmess.key"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -subj '/CN=vmess.verification.invalid' \
    -addext 'subjectAltName=DNS:vmess.verification.invalid' \
    -keyout "${key_path}" -out "${cert_path}" >/dev/null 2>&1
  chmod 600 "${cert_path}" "${key_path}"
  printf 'SCENARIO=fresh_install_vmess\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

9
${expected_port}
2
first

0
auto
second

0
aes-128-gcm
y
vmess.verification.invalid
${cert_path}
${key_path}
1
1
n
n
0
EOF
  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  grep -Fqx 'INSTALLED_PROTOCOLS=vmess' /root/sing-box-vps/protocols/index.env
  jq -e --argjson port "${expected_port}" '
    .protocol=="vmess" and .revision==1 and (.instances|length)==1 and
    .instances[0].id=="main" and .instances[0].tag=="vmess-in" and
    .instances[0].listen=={address:"127.0.0.1",port:$port} and
    (.instances[0].authentication.users|length)==2 and
    all(.instances[0].authentication.users[];
      (.name|type=="string" and length>0) and
      (.uuid|test("^[0-9a-f-]{36}$")) and
      (.alter_id==0) and
      (.security|IN("auto","aes-128-gcm"))) and
    .instances[0].tls.enabled==true and
    .instances[0].tls.server_name=="vmess.verification.invalid" and
    .instances[0].client_trust=="certificate" and
    .instances[0].transport=={type:"none"}
  ' "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    (.inbounds|length)==1 and .inbounds[0].type=="vmess" and
    .inbounds[0].listen=="127.0.0.1" and .inbounds[0].listen_port==$port and
    (.inbounds[0].users|length)==2 and
    all(.inbounds[0].users[]; has("name") and has("uuid") and has("alterId") and
      (.alterId|type=="number" and .==0)) and
    (.inbounds[0]|has("transport")|not) and .inbounds[0].tls.enabled==true
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_run_protocol_probes
}
