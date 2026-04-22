verification_scenario_uninstall_and_reinstall() {
  local after_port
  local after_uuid
  local after_sni
  local expected_port=443
  local expected_uuid="11111111-1111-4111-8111-111111111111"
  local expected_sni="www.cloudflare.com"

  printf 'SCENARIO=uninstall_and_reinstall\n'
  bash /root/Clouds/sing-box-vps/uninstall.sh --yes || bash /root/Clouds/sing-box-vps/install.sh --internal-uninstall-purge --yes
  test ! -e /root/sing-box-vps/config.json
  test ! -e /etc/systemd/system/sing-box.service
  test ! -e /usr/local/bin/sbv
  bash /root/Clouds/sing-box-vps/install.sh <<'EOF'
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
  after_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  after_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  after_sni=$(jq -r '.inbounds[0].tls.server_name // empty' /root/sing-box-vps/config.json)
  [[ "${after_port}" == "${expected_port}" ]]
  [[ "${after_uuid}" == "${expected_uuid}" ]]
  [[ "${after_sni}" == "${expected_sni}" ]]
  test -f /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "PORT=${expected_port}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "UUID=${expected_uuid}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "SNI=${expected_sni}" /root/sing-box-vps/protocols/vless-reality.env
  ! grep -Fqx 'PORT=8443' /root/sing-box-vps/protocols/vless-reality.env
  ! grep -Fqx 'UUID=22222222-2222-4222-8222-222222222222' /root/sing-box-vps/protocols/vless-reality.env
  ! grep -Fqx 'SNI=cdn.cloudflare.com' /root/sing-box-vps/protocols/vless-reality.env
  systemctl is-active --quiet sing-box
}
