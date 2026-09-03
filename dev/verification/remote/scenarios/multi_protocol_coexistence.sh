verification_scenario_multi_protocol_coexistence() {
  local cert_dir
  local cert_path
  local key_path
  local config_path
  local index_path
  local protocol
  local port

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  cert_dir="${VERIFY_REMOTE_LOCAL_TREE_DIR}/shared-tls"
  cert_path="${cert_dir}/cert.pem"
  key_path="${cert_dir}/key.pem"
  mkdir -p "${cert_dir}"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "${key_path}" \
    -out "${cert_path}" \
    -subj '/CN=sing-box-vps-verification.invalid' \
    -days 1 >/dev/null 2>&1

  printf 'SCENARIO=multi_protocol_coexistence\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1



443
2
www.cloudflare.com
n
1
n
1080
y
mixed-user
mixed-pass
hy2.example.com
y
8443
hy2-pass
hy2-user


n
2
${cert_path}
${key_path}

anytls.example.com
y
9443
anytls-user
anytls-pass
2
${cert_path}
${key_path}
n
n
0
EOF

  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/config.json")
  index_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/protocols/index.env")
  cp /root/sing-box-vps/config.json "${config_path}"
  cp /root/sing-box-vps/protocols/index.env "${index_path}"
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls' "${index_path}"
  jq -e '
    ([.inbounds[] | .type] | sort) == ["anytls", "hysteria2", "mixed", "vless"] and
    ([.inbounds[] | select(.type == "vless") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "mixed") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "hysteria2") | .listen_port] | length == 1) and
    ([.inbounds[] | select(.type == "anytls") | .listen_port] | length == 1)
  ' /root/sing-box-vps/config.json >/dev/null
  grep -Fqx 'sing-box version 1.14.0' <(sing-box version)
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  for protocol in vless-reality mixed hy2 anytls; do
    if [[ "${protocol}" == "vless-reality" ]]; then
      port=$(jq -r '.inbounds[] | select(.type == "vless") | .listen_port' /root/sing-box-vps/config.json)
    else
      port=$(jq -r --arg protocol "${protocol}" '.inbounds[] | select(.type == $protocol) | .listen_port' /root/sing-box-vps/config.json)
    fi
    if [[ "${protocol}" == "hy2" ]]; then
      verification_assert_udp_port_listening "${port}" \
        "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.${protocol}.ss-lunp.txt"
    else
      verification_assert_port_listening "${port}" \
        "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.${protocol}.ss-lntp.txt"
    fi
  done
  verification_run_protocol_probes
}
