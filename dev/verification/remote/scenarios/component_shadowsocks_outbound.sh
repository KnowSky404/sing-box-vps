verification_scenario_component_shadowsocks_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_shadowsocks_outbound\n'
  verification_protocol_prepare shadowsocks
  verification_fixture_tcp_marker
  verification_case_shadowsocks_outbound 0
  verification_case_assert_clean 2
)
