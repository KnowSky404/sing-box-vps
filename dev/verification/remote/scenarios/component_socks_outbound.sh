verification_scenario_component_socks_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_socks_outbound\n'
  verification_case_socks_outbound 0
  verification_case_assert_clean 2
)
