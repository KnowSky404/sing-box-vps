verification_scenario_fresh_install_vless() {
  local config_uuid
  local env_uuid
  local current_port
  local expected_port=443
  local status_output_path

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_vless\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e /root/sing-box-vps/config.json
  test ! -e /etc/systemd/system/sing-box.service
  test ! -e /usr/local/bin/sbv
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'EOF'
1

1
443
www.cloudflare.com
n
n
0
EOF
  test -f /root/sing-box-vps/config.json
  test -f /etc/systemd/system/sing-box.service
  test -x /usr/local/bin/sbv
  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/vless-reality.env
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  config_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  env_uuid=$(grep '^UUID=' /root/sing-box-vps/protocols/vless-reality.env | cut -d'=' -f2- || true)
  [[ "${current_port}" == "${expected_port}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx 'PORT=443' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'SNI=www.cloudflare.com' /root/sing-box-vps/protocols/vless-reality.env
  [[ -n "${config_uuid}" ]]
  [[ "${config_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  [[ -n "${env_uuid}" ]]
  [[ "${env_uuid}" == "${config_uuid}" ]]
  [[ "${env_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  ! grep -Fq 'stale.example.com' /root/sing-box-vps/protocols/vless-reality.env
  systemctl is-active --quiet sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq "端口: ${expected_port}" "${status_output_path}"
  grep -Fq '配置文件: /root/sing-box-vps/config.json' "${status_output_path}"
  verification_run_protocol_probes
}
