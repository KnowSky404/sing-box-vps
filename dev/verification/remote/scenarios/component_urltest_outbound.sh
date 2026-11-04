verification_scenario_component_urltest_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_urltest_outbound\n'
  verification_fixture_tcp_marker
  verification_case_urltest_outbound 0
  verification_case_assert_clean 2
)
