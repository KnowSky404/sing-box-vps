verification_scenario_protocol_coexistence() (
  set -euo pipefail
  local protocol
  verification_case_context_start
  printf 'SCENARIO=protocol_coexistence\n'
  # The planner supplies one fresh SOCKS/core installation. All remaining
  # instances are added by the same helpers as independent protocol leaves.
  for protocol in vless-reality mixed hy2 anytls http shadowsocks trojan tuic vmess snell shadowtls naive; do
    verification_protocol_prepare "${protocol}"
  done
  # The shared TCP listener default must survive all protocol additions.
  jq -e 'all(.inbounds[] | select(.type | IN("vless","mixed","socks","http","shadowsocks","anytls","snell","shadowtls","naive")) |
    select((.transport.type // "none") != "quic"); .tcp_fast_open==true) and
    any(.inbounds[]; .type=="hysteria2" and .obfs.type=="salamander")' \
    /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_fixture_tcp_marker
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" hy2 masquerade-check --json \
    --url "http://127.0.0.1:${direct_marker_port}" \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/hy2-masquerade-check.json")"
  jq -e '.ok and .data.http_available and (.data.reality_candidates|length)>0 and
    .data.tls_server_name_reused==false' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/hy2-masquerade-check.json")" >/dev/null
  verification_protocol_assert_coexistence
  for protocol in vless-reality mixed hy2 anytls socks http shadowsocks trojan tuic vmess snell shadowtls naive; do
    # The inventory helper already probes TCP for all installed protocols.
    verification_protocol_udp_probe "${protocol}"
  done
  jq -e '([.inbounds[].type]|sort)==["anytls","http","hysteria2","mixed","mixed","naive","shadowsocks","shadowtls","snell","socks","trojan","tuic","vless","vmess"] and
    ((.endpoints // [])|length)==0 and
    all(.outbounds[]; (.type=="direct" or .type=="block") and
      (.tag=="direct" or .tag=="block"))' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-coexistence.result.env" \
    'RESULT=success' 'PROTOCOL_COUNT=13' 'COMPONENT_ADAPTERS=none' 'TOR=not_selected'
)
