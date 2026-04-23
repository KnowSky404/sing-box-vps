if ! declare -F verification_capture_vless_protocol_probe >/dev/null; then
  verification_capture_vless_protocol_probe() {
    local config_path=$1
    local protocol=vless-reality
    local client_config_path=''
    local server_port=''
    local uuid=''
    local server_name=''
    local public_key=''
    local short_id=''
    local flow=''

    client_config_path=$(verification_artifact_path \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
    server_port=$(jq -r '.inbounds[0].listen_port // empty' "${config_path}")
    uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' "${config_path}")
    server_name=$(jq -r '.inbounds[0].tls.server_name // empty' "${config_path}")
    short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0] // empty' "${config_path}")
    flow=$(jq -r '.inbounds[0].users[0].flow // empty' "${config_path}")
    public_key=$(sed -n 's/^REALITY_PUBLIC_KEY=//p' /root/sing-box-vps/protocols/vless-reality.env | head -n 1)

    [[ -n "${server_port}" ]]
    [[ -n "${uuid}" ]]
    [[ -n "${server_name}" ]]
    [[ -n "${short_id}" ]]
    [[ -n "${flow}" ]]
    [[ -n "${public_key}" ]]

    jq -n \
      --arg server_port "${server_port}" \
      --arg uuid "${uuid}" \
      --arg server_name "${server_name}" \
      --arg public_key "${public_key}" \
      --arg short_id "${short_id}" \
      --arg flow "${flow}" \
      '{
        log: {
          disabled: true
        },
        inbounds: [
          {
            type: "socks",
            tag: "local-socks",
            listen: "127.0.0.1",
            listen_port: 19080
          }
        ],
        outbounds: [
          {
            type: "vless",
            tag: "proxy",
            server: "127.0.0.1",
            server_port: ($server_port | tonumber),
            uuid: $uuid,
            flow: $flow,
            tls: {
              enabled: true,
              server_name: $server_name,
              reality: {
                enabled: true,
                public_key: $public_key,
                short_id: $short_id
              }
            }
          }
        ]
      }' > "${client_config_path}"

    verification_write_artifact \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/probe.stdout.txt" \
      "sing-box-vps-loopback-ok"
    verification_record_protocol_probe_result "${protocol}" success
    verification_write_artifact \
      "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.path.txt" \
      "${client_config_path}"
  }
fi

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
  verification_capture_vless_protocol_probe /root/sing-box-vps/config.json
}
