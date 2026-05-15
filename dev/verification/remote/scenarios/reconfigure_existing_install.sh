verification_scenario_reconfigure_existing_install() {
  local before_port
  local after_port
  local after_uuid
  local after_sni
  local before_config_path
  local after_config_path
  local diff_path
  local status_output_path
  local diff_status=0
  local expected_port=8443
  local expected_uuid="22222222-2222-4222-8222-222222222222"
  local expected_sni="cdn.cloudflare.com"

  printf 'SCENARIO=reconfigure_existing_install\n'
  before_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  before_config_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/config.before.json")
  after_config_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/config.after.json")
  diff_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/config.diff.txt")
  cp /root/sing-box-vps/config.json "${before_config_path}"
  bash /usr/local/bin/sbv <<'EOF'
4
1
8443
22222222-2222-4222-8222-222222222222
3
cdn.cloudflare.com
0
EOF
  after_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  after_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  after_sni=$(jq -r '.inbounds[0].tls.server_name // empty' /root/sing-box-vps/config.json)
  cp /root/sing-box-vps/config.json "${after_config_path}"
  diff -u "${before_config_path}" "${after_config_path}" > "${diff_path}" || diff_status=$?
  [[ "${diff_status}" == "1" ]]
  [[ -n "${before_port}" && "${before_port}" != "${after_port}" ]]
  [[ "${after_port}" == "${expected_port}" ]]
  [[ "${after_uuid}" == "${expected_uuid}" ]]
  [[ "${after_sni}" == "${expected_sni}" ]]
  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx "PORT=${expected_port}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "UUID=${expected_uuid}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "SNI=${expected_sni}" /root/sing-box-vps/protocols/vless-reality.env
  systemctl is-active --quiet sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_assert_port_not_listening "${before_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.old-port.ss-lntp.txt"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq "端口: ${expected_port}" "${status_output_path}"
  verification_run_protocol_probes
}
