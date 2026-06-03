verification_scenario_fresh_install_vless() {
  local config_uuid
  local env_uuid
  local instance_state_file=/root/sing-box-vps/protocols/vless-reality.d/main.env
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
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'EOF'
1

1

443
2
www.cloudflare.com
n
1
n
n
n
0
EOF
  verification_mark_step fresh_install_vless_after_install
  test -f /root/sing-box-vps/config.json
  test -f /etc/systemd/system/sing-box.service
  test -x /usr/local/bin/sbv
  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/vless-reality.env
  test -f "${instance_state_file}"
  verification_mark_step fresh_install_vless_files_present
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  config_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  env_uuid=$(grep '^UUID=' "${instance_state_file}" | cut -d'=' -f2- || true)
  verification_mark_step fresh_install_vless_values_loaded
  [[ "${current_port}" == "${expected_port}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'DEFAULT_INSTANCE_ID=main' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'INSTANCE_IDS=main' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'PORT=443' "${instance_state_file}"
  grep -Fqx 'SNI=www.cloudflare.com' "${instance_state_file}"
  verification_mark_step fresh_install_vless_static_asserts
  [[ -n "${config_uuid}" ]]
  [[ "${config_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  [[ -n "${env_uuid}" ]]
  [[ "${env_uuid}" == "${config_uuid}" ]]
  [[ "${env_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  ! grep -Fq 'stale.example.com' "${instance_state_file}"
  verification_mark_step fresh_install_vless_uuid_asserts
  verification_wait_for_service_active sing-box
  verification_mark_step fresh_install_vless_service_active
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_mark_step fresh_install_vless_config_checked
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_mark_step fresh_install_vless_port_listening
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq '运行状态摘要' "${status_output_path}"
  grep -Fq 'sing-box: active' "${status_output_path}"
  grep -Fq 'Warp: 未开启' "${status_output_path}"
  grep -Fq '配置文件: /root/sing-box-vps/config.json' "${status_output_path}"
  ! grep -Fq '协议:' "${status_output_path}"
  ! grep -Fq '地址:' "${status_output_path}"
  ! grep -Fq '端口:' "${status_output_path}"
  verification_mark_step fresh_install_vless_status_menu
  verification_run_protocol_probes
  verification_mark_step fresh_install_vless_protocol_probes
}
