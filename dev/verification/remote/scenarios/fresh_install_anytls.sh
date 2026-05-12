verification_scenario_fresh_install_anytls() {
  local current_port
  local current_password
  local current_domain
  local current_user_name
  local status_output_path
  local expected_port=9443
  local expected_domain="anytls.example.com"
  local expected_password="anytls-pass"
  local expected_user_name="anytls-user"
  local cert_dir
  local cert_path
  local key_path

  verification_prepare_remote_local_tree
  cert_dir="${VERIFY_REMOTE_LOCAL_TREE_DIR}/anytls-tls"
  cert_path="${cert_dir}/cert.pem"
  key_path="${cert_dir}/key.pem"
  rm -rf "${cert_dir}"
  mkdir -p "${cert_dir}"

  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${key_path}" \
    -out "${cert_path}" \
    -subj "/CN=${expected_domain}" \
    -days 1 >/dev/null 2>&1

  printf 'SCENARIO=fresh_install_anytls\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e /root/sing-box-vps/config.json
  test ! -e /etc/systemd/system/sing-box.service
  test ! -e /usr/local/bin/sbv
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

4
${expected_domain}
y
${expected_port}
${expected_user_name}
${expected_password}
2
${cert_path}
${key_path}
n
n
0
EOF
  test -f /root/sing-box-vps/config.json
  test -f /etc/systemd/system/sing-box.service
  test -x /usr/local/bin/sbv
  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/anytls.env
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  current_password=$(jq -r '.inbounds[0].users[0].password // empty' /root/sing-box-vps/config.json)
  current_domain=$(jq -r '.inbounds[0].tls.server_name // empty' /root/sing-box-vps/config.json)
  current_user_name=$(jq -r '.inbounds[0].users[0].name // empty' /root/sing-box-vps/config.json)
  [[ "${current_port}" == "${expected_port}" ]]
  [[ "${current_password}" == "${expected_password}" ]]
  [[ "${current_domain}" == "${expected_domain}" ]]
  [[ "${current_user_name}" == "${expected_user_name}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=anytls' /root/sing-box-vps/protocols/index.env
  grep -Fqx "PORT=${expected_port}" /root/sing-box-vps/protocols/anytls.env
  grep -Fqx "DOMAIN=${expected_domain}" /root/sing-box-vps/protocols/anytls.env
  grep -Fqx "PASSWORD=${expected_password}" /root/sing-box-vps/protocols/anytls.env
  grep -Fqx "USER_NAME=${expected_user_name}" /root/sing-box-vps/protocols/anytls.env
  grep -Fqx 'TLS_MODE=manual' /root/sing-box-vps/protocols/anytls.env
  systemctl is-active --quiet sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq "端口: ${expected_port}" "${status_output_path}"
  grep -Fq '配置文件: /root/sing-box-vps/config.json' "${status_output_path}"
  verification_run_protocol_probes
}
