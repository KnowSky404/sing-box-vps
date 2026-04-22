verification_scenario_fresh_install_vless() {
  local expected_uuid="11111111-1111-4111-8111-111111111111"

  printf 'SCENARIO=fresh_install_vless\n'
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
  test -f /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'PORT=443' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx "UUID=${expected_uuid}" /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'SNI=www.cloudflare.com' /root/sing-box-vps/protocols/vless-reality.env
  ! grep -Fq 'stale.example.com' /root/sing-box-vps/protocols/vless-reality.env
  systemctl is-active --quiet sing-box
  sing-box check -c /root/sing-box-vps/config.json
}
