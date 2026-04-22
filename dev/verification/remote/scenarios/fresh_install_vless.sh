verification_scenario_fresh_install_vless() {
  printf 'SCENARIO=fresh_install_vless\n'
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
  systemctl is-active --quiet sing-box
  sing-box check -c /root/sing-box-vps/config.json
}
