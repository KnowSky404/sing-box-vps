verification_scenario_component_block_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_block_outbound\n'
  verification_fixture_tcp_marker
  verification_case_block_outbound 0
  verification_case_assert_clean 2
)
