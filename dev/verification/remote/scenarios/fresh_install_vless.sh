verification_scenario_fresh_install_vless() {
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
  systemctl is-active --quiet sing-box
  sing-box check -c /root/sing-box-vps/config.json
}
