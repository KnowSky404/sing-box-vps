verification_scenario_component_transparent_policy() (
  set -euo pipefail
  verification_case_context_start
  verification_assert_atomic_socks_baseline
  printf 'SCENARIO=component_transparent_policy\n'
  verification_case_transparent_policy 0
  verification_case_assert_clean 6
)
