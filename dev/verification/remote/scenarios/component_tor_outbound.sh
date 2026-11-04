verification_scenario_component_tor_outbound() (
  set -euo pipefail
  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree' EXIT
  printf 'SCENARIO=component_tor_outbound\n'
  verification_assert_atomic_socks_baseline
  # Planner always creates a fresh SOCKS-only baseline before this case.
  verification_case_tor_outbound 0
)
