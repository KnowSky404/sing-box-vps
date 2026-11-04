verification_scenario_component_shadowtls_outbound() (
  set -euo pipefail
  verification_case_context_start
  printf 'SCENARIO=component_shadowtls_outbound\n'
  verification_fixture_tcp_marker
  verification_fixture_tls
  verification_fixture_tls_cover
  verification_case_shadowtls_outbound 0
  verification_case_assert_clean 4
)
