verification_scenario_reconfigure_existing_install() {
  local before_port
  local after_port
  local after_uuid
  local after_sni
  local expected_port=8443
  local expected_uuid="22222222-2222-4222-8222-222222222222"
  local expected_sni="cdn.cloudflare.com"

  printf 'SCENARIO=reconfigure_existing_install\n'
  before_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  bash /usr/local/bin/sbv <<'EOF'
3
1
8443
22222222-2222-4222-8222-222222222222
cdn.cloudflare.com
0
EOF
  after_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  after_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  after_sni=$(jq -r '.inbounds[0].tls.server_name // empty' /root/sing-box-vps/config.json)
  [[ -n "${before_port}" && "${before_port}" != "${after_port}" ]]
  [[ "${after_port}" == "${expected_port}" ]]
  [[ "${after_uuid}" == "${expected_uuid}" ]]
  [[ "${after_sni}" == "${expected_sni}" ]]
  test -f /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "PORT=${expected_port}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "UUID=${expected_uuid}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "SNI=${expected_sni}" /root/sing-box-vps/protocols/vless-reality.env
  systemctl is-active --quiet sing-box
}
