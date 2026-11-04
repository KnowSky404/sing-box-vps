verification_scenario_component_ssh_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_ssh_outbound\n'
  verification_case_ssh_outbound 0
  verification_case_assert_clean 2
)
