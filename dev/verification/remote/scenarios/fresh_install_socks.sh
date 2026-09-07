verification_scenario_fresh_install_socks() {
  local expected_port=1081 config_file=/root/sing-box-vps/config.json
  local store_file=/root/sing-box-vps/protocols/instances/socks.json
  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_socks\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

5
${expected_port}
y
socks-user
socks-pass
n
n
0
EOF
  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'INSTALLED_PROTOCOLS=socks' /root/sing-box-vps/protocols/index.env
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' /root/sing-box-vps/protocols/socks.env
  [[ "$(stat -c %a "${store_file}")" == 600 ]]
  jq -e '.protocol=="socks" and .revision==1 and (.instances|length)==1 and
    .instances[0].listen.address=="127.0.0.1" and
    .instances[0].authentication=={enabled:true,username:"socks-user",password:"socks-pass"}' \
    "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    (.inbounds|length)==1 and .inbounds[0].type=="socks" and
    .inbounds[0].listen=="127.0.0.1" and .inbounds[0].listen_port==$port and
    .inbounds[0].users==[{username:"socks-user",password:"socks-pass"}] and
    (.inbounds[0]|has("tls")|not)' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_run_protocol_probes
}
