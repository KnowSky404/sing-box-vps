verification_scenario_component_http_outbound() (
  set -euo pipefail
  verification_case_context_start
  verification_assert_atomic_socks_baseline
  printf 'SCENARIO=component_http_outbound\n'
  verification_case_http_outbound 0 delete
  verification_case_assert_clean 2
)
