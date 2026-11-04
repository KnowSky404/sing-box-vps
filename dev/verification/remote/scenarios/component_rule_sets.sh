verification_scenario_component_rule_sets() (
  set -euo pipefail
  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree' EXIT
  printf 'SCENARIO=component_rule_sets\n'
  verification_assert_atomic_socks_baseline
  # Planner always creates a fresh SOCKS-only baseline before this case.
  verification_scenario_managed_rule_sets 0
)
