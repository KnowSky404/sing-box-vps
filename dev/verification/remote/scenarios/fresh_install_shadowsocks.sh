verification_scenario_fresh_install_shadowsocks() {
  local expected_port=1083
  local expected_key=MDEyMzQ1Njc4OWFiY2RlZg==
  local config_file=/root/sing-box-vps/config.json
  local state_file=/root/sing-box-vps/protocols/shadowsocks.env
  local store_file=/root/sing-box-vps/protocols/instances/shadowsocks.json

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_shadowsocks\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"

  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

7
${expected_port}

n
${expected_key}
1
n
n
0
EOF

  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'INSTALLED=1' "${state_file}"
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  [[ "$(stat -c %a "${store_file}")" == 600 ]]
  jq -e --arg key "${expected_key}" '
    .schema_version==1 and .protocol=="shadowsocks" and .revision==1 and
    (.instances|length)==1 and .instances[0].id=="main" and
    .instances[0].tag=="ss-in" and
    .instances[0].listen=={address:"127.0.0.1",port:1083,network:["tcp","udp"]} and
    .instances[0].authentication=={
      method:"2022-blake3-aes-128-gcm",password:$key,users:[]}
  ' "${store_file}" >/dev/null
  grep -Fqx 'INSTALLED_PROTOCOLS=shadowsocks' \
    /root/sing-box-vps/protocols/index.env
  jq -e --arg key "${expected_key}" '
    (.inbounds|length)==1 and
    .inbounds[0].type=="shadowsocks" and
    .inbounds[0].tag=="ss-in" and
    .inbounds[0].listen=="127.0.0.1" and
    .inbounds[0].listen_port==1083 and
    .inbounds[0].network==["tcp","udp"] and
    .inbounds[0].method=="2022-blake3-aes-128-gcm" and
    .inbounds[0].password==$key and .inbounds[0].users==[]
  ' "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_run_protocol_probes
}
