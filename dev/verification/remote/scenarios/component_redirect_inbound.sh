verification_scenario_component_redirect_inbound() (
  set -euo pipefail
  verification_case_context_start
  verification_assert_atomic_socks_baseline
  printf 'SCENARIO=component_redirect_inbound\n'
  verification_case_redirect_create 0
  verification_case_redirect_delete 1
  verification_case_assert_clean 2
)
