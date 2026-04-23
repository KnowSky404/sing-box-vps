verification_scenario_uninstall_and_reinstall() {
  local before_uuid
  local after_port
  local after_uuid
  local after_sni
  local env_uuid
  local status_output_path
  local expected_port=443
  local expected_sni="www.cloudflare.com"

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=uninstall_and_reinstall\n'
  before_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json 2>/dev/null || true)
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
  after_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  after_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  after_sni=$(jq -r '.inbounds[0].tls.server_name // empty' /root/sing-box-vps/config.json)
  env_uuid=$(grep '^UUID=' /root/sing-box-vps/protocols/vless-reality.env | cut -d'=' -f2- || true)
  [[ "${after_port}" == "${expected_port}" ]]
  [[ -n "${after_uuid}" ]]
  [[ "${after_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  [[ "${after_sni}" == "${expected_sni}" ]]
  test -f /root/sing-box-vps/protocols/vless-reality.env
  [[ -n "${env_uuid}" ]]
  [[ "${env_uuid}" == "${after_uuid}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx "PORT=${expected_port}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "SNI=${expected_sni}" /root/sing-box-vps/protocols/vless-reality.env
  ! grep -Fqx 'PORT=8443' /root/sing-box-vps/protocols/vless-reality.env
  ! grep -Fqx 'SNI=cdn.cloudflare.com' /root/sing-box-vps/protocols/vless-reality.env
  if [[ -n "${before_uuid}" ]]; then
    [[ "${after_uuid}" != "${before_uuid}" ]]
    ! grep -Fqx "UUID=${before_uuid}" /root/sing-box-vps/protocols/vless-reality.env
  fi
  systemctl is-active --quiet sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq "端口: ${expected_port}" "${status_output_path}"
  verification_run_protocol_probes
}
