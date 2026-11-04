verification_config_inbound_type_for_protocol() {
  verification_protocol_metadata "$1" | jq -er '.type'
}

verification_config_inbound_port_for_protocol() {
  local protocol=$1
  local config_file=$2
  local config_type

  config_type=$(verification_config_inbound_type_for_protocol "${protocol}")
  if [[ "${protocol}" == "mixed" ]]; then
    jq -er --arg config_type "${config_type}" '
      [.inbounds[] | select(.type == $config_type and
        ((.tag // "") | startswith("shadowtls-inner-") | not))][0].listen_port
    ' "${config_file}"
    return 0
  fi

  jq -er --arg config_type "${config_type}" '
    [.inbounds[] | select(.type == $config_type)][0].listen_port
  ' "${config_file}"
}

verification_config_inbound_network_for_protocol() {
  local protocol=$1
  local config_file=$2
  local config_type

  config_type=$(verification_config_inbound_type_for_protocol "${protocol}")
  if [[ "${protocol}" == "mixed" ]]; then
    jq -er --arg config_type "${config_type}" '
      [.inbounds[] | select(.type == $config_type and
        ((.tag // "") | startswith("shadowtls-inner-") | not))][0]
      | (.network // "")
      | if type == "array" then join(",") else . end
    ' "${config_file}"
    return 0
  fi

  jq -er --arg config_type "${config_type}" '
    [.inbounds[] | select(.type == $config_type)][0]
    | (.network // "")
    | if type == "array" then join(",") else . end
  ' "${config_file}"
}

verification_scenario_multi_protocol_coexistence() (
  set -euo pipefail
  local cert_dir
  local cert_path
  local key_path
  local config_path
  local expected_core_version
  local index_path
  local protocol
  local port
  local configured_network
  local anytls_udp_journal_artifact=''
  local naive_udp_journal_artifact=''
  local naive_http3_journal_artifact=''

  verification_case_context_start none
  # Keep the certificate paths valid for the following runtime_smoke scenario.
  # The Docker container is disposable, so this test-only directory cannot
  # outlive the verification run or affect a host installation.
  verification_fixture_tls

  printf 'SCENARIO=multi_protocol_coexistence\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

1,2,3,4
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
0
EOF

  # Add SOCKS through the same public, confirmed instance transaction used
  # by operators; the four existing protocols must remain untouched.
  local socks_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-record.json"
  (umask 077; jq -n '{id:"main",name:"SOCKS verification",tag:"socks-in",
    listen:{address:"127.0.0.1",port:1081},
    authentication:{enabled:true,username:"socks-user",password:"socks-pass"},
    outbound_policy:"default",dependencies:[]}' > "${socks_record}")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance create socks --json --yes \
    --expected-revision 0 --file "${socks_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-create.json"
  jq -e '.ok==true and .protocol=="socks" and .changed==true and .revision==1' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/socks-create.json" >/dev/null

  for protocol in http shadowsocks trojan tuic vmess snell shadowtls naive; do
    verification_protocol_prepare "${protocol}"
  done

  verification_case_http_outbound 0 retain

  verification_case_direct_inbound 1 retain

  verification_case_transparent_policy 3

  verification_case_ssh_outbound 9

  verification_case_socks_outbound 11

  verification_case_selector_outbound 13

  verification_case_urltest_outbound 15

  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,socks,http,shadowsocks,trojan,tuic,vmess,snell,shadowtls,naive' /root/.sing-box-vps/runtime/protocols/index.env
  verification_protocol_assert_coexistence aggregate

  for protocol in vless-reality mixed socks; do verification_protocol_udp_probe "${protocol}"; done
  verification_protocol_udp_probe naive
  verification_protocol_naive_transition
  for protocol in anytls hy2 shadowsocks trojan tuic vmess snell; do verification_protocol_udp_probe "${protocol}"; done
  verification_protocol_snell_transition

  verification_case_shadowsocks_outbound 17

  verification_case_direct_outbound 19

  verification_case_block_outbound 21

  verification_case_vless_outbound 23

  verification_case_tor_outbound 25

  verification_case_shadowtls_outbound 27

  verification_case_shadowsocks_udp_outbound 31

  verification_case_socks_udp_outbound 33

  verification_scenario_managed_rule_sets 35
)
