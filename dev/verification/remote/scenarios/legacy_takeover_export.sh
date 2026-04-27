verification_scenario_legacy_takeover_export() {
  local export_stdout_path
  local legacy_config_path=${VERIFY_LEGACY_CONFIG_FILE:-/root/sing-box-vps/config.json}
  local legacy_key_path=${VERIFY_LEGACY_KEY_FILE:-/root/sing-box-vps/reality.key}
  local legacy_service_path=${VERIFY_LEGACY_SERVICE_FILE:-/etc/systemd/system/sing-box.service}
  local export_path=/root/sing-box-vps/client/sing-box-client.json
  local expected_port=443
  local expected_sni="www.cloudflare.com"
  local expected_uuid="11111111-1111-1111-1111-111111111111"
  local expected_private_key="IEwVBb_qLcYr1L_CTI5exTWbT7qRgZnr43xP8nC0dkM"
  local expected_public_key="u9nRBiDRTmyxLQLkiVq-kYFPhRyeZkSo8p9c7s8Dfjo"

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=legacy_takeover_export\n'

  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  mkdir -p "$(dirname "${legacy_config_path}")"
  cat > "${legacy_config_path}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "legacy-vless-in",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111"
        }
      ],
      "tls": {
        "server_name": "www.cloudflare.com",
        "reality": {
          "private_key": "IEwVBb_qLcYr1L_CTI5exTWbT7qRgZnr43xP8nC0dkM",
          "short_id": [
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    }
  ],
  "route": {
    "rules": []
  }
}
EOF
  cat > "${legacy_key_path}" <<'EOF'
PRIVATE_KEY=IEwVBb_qLcYr1L_CTI5exTWbT7qRgZnr43xP8nC0dkM
PUBLIC_KEY=u9nRBiDRTmyxLQLkiVq-kYFPhRyeZkSo8p9c7s8Dfjo
EOF
  mkdir -p "$(dirname "${legacy_service_path}")"
  cat > "${legacy_service_path}" <<'EOF'
[Unit]
Description=sing-box
EOF

  test -f "${legacy_config_path}"
  test -f "${legacy_service_path}"
  test ! -f /root/sing-box-vps/protocols/index.env

  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'EOF'
1
1
0
EOF

  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx "PORT=${expected_port}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "UUID=${expected_uuid}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "SNI=${expected_sni}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "REALITY_PRIVATE_KEY=${expected_private_key}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "REALITY_PUBLIC_KEY=${expected_public_key}" /root/sing-box-vps/protocols/vless-reality.env
  systemctl is-active --quiet sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json

  export_stdout_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-export.txt")
  bash /usr/local/bin/sbv > "${export_stdout_path}" 2>&1 <<'EOF'
10
2
0
0
EOF

  grep -Fq 'sing-box 裸核客户端配置导出成功。' "${export_stdout_path}"
  grep -Fq "文件路径: ${export_path}" "${export_stdout_path}"
  test -f "${export_path}"
  verification_capture_file_if_present "${export_path}" "${VERIFY_CURRENT_SCENARIO_DIR}/client/sing-box-client.json"
  jq -e '.outbounds[] | select(.type == "vless" and .tag == "rn-us-lax+vless") | .tls.utls.enabled == true and .tls.utls.fingerprint == "chrome"' "${export_path}" >/dev/null
}
