verification_scenario_component_direct_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_direct_outbound\n'
  verification_fixture_tcp_marker
  verification_fixture_udp_echo
  verification_case_direct_outbound 0
  verification_case_assert_clean 2
)
