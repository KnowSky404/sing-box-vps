verification_scenario_reconfigure_existing_install() {
  local before_port
  local after_port

  printf 'SCENARIO=reconfigure_existing_install\n'
  before_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  bash /usr/local/bin/sbv <<'EOF'
3
1
8443
0
EOF
  after_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  [[ -n "${before_port}" && "${before_port}" != "${after_port}" ]]
  systemctl is-active --quiet sing-box
}
