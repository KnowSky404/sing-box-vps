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
