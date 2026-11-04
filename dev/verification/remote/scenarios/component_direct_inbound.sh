verification_scenario_component_direct_inbound() (
  set -euo pipefail
  verification_case_context_start
  verification_assert_atomic_socks_baseline
  printf 'SCENARIO=component_direct_inbound\n'
  verification_case_direct_inbound 0 delete
  verification_case_assert_clean 4
)
