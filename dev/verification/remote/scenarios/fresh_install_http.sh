verification_scenario_fresh_install_http() {
  local expected_port=1082
  local config_file=/root/sing-box-vps/config.json
  local state_file=/root/sing-box-vps/protocols/http.env
  local store_file=/root/sing-box-vps/protocols/instances/http.json

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_http\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

6
${expected_port}
y
http-user
http-pass
n
n
n
0
EOF

  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  jq -e '.protocol=="http" and .revision==1 and (.instances|length)==1 and
    .instances[0].id=="main" and .instances[0].tag=="http-in" and
    .instances[0].listen=={address:"127.0.0.1",port:1082} and
    .instances[0].authentication=={enabled:true,username:"http-user",password:"http-pass"} and
    .instances[0].tls=={enabled:false}' "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    ([.inbounds[] | select(.type=="http")][0]) as $inbound |
    $inbound.listen=="127.0.0.1" and $inbound.listen_port==$port and
    $inbound.users==[{username:"http-user",password:"http-pass"}] and
    ($inbound|has("tls")|not)' "${config_file}" >/dev/null
  grep -Fqx 'INSTALLED_PROTOCOLS=http' /root/sing-box-vps/protocols/index.env
  jq -e '(.inbounds|length)==1 and .inbounds[0].type=="http"' \
    "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_run_protocol_probes
}
