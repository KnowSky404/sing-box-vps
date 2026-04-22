verification_scenario_uninstall_and_reinstall() {
  printf 'SCENARIO=uninstall_and_reinstall\n'
  bash /root/Clouds/sing-box-vps/uninstall.sh --yes || bash /root/Clouds/sing-box-vps/install.sh --internal-uninstall-purge --yes
  test ! -e /root/sing-box-vps/config.json
  bash /root/Clouds/sing-box-vps/install.sh <<'EOF'
1

1
443
www.cloudflare.com
n
n
0
EOF
  systemctl is-active --quiet sing-box
}
