verification_scenario_component_tproxy_inbound() (
  set -euo pipefail
  verification_case_context_start
  verification_assert_atomic_socks_baseline
  printf 'SCENARIO=component_tproxy_inbound\n'
  verification_case_tproxy_create_probe 0
  verification_case_transparent_diagnose tproxy
  verification_case_tproxy_delete 3
  verification_case_assert_clean 4
)
