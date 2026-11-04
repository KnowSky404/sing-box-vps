#!/usr/bin/env bash

# Host-safe: exercise revision composition and wrapper failure behavior only.
# Real namespace/data-plane checks belong to the registered Docker scenes.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
SCENARIO_DIR="${REPO_ROOT}/dev/verification/remote/scenarios"
source "${SCENARIO_DIR}/policy_cases.sh"
for file in policy_cases component_direct_inbound component_redirect_inbound component_tproxy_inbound component_transparent_policy; do
  bash -n "${SCENARIO_DIR}/${file}.sh"
done

for revision in 0 3 1000; do verification_policy_validate_revision "${revision}"; done
for revision in '' 01 -1 1.5 invalid 9999999999999999; do
  if verification_policy_validate_revision "${revision}" > /dev/null 2>&1; then
    printf 'unsafe revision accepted: %s\n' "${revision}" >&2
    exit 1
  fi
done

assert_equal() {
  local expected=$1 actual=$2
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected:\n%s\nactual:\n%s\n' "${expected}" "${actual}" >&2
    return 1
  fi
}

# Both independent and aggregate callers use the same transparent-policy
# composition, with known revisions rather than opportunistic state reads.
for base in 0 3; do
  result=$(
    verification_case_redirect_create() { printf 'redirect_create:%s\n' "$1"; }
    verification_case_tproxy_create_probe() { printf 'tproxy_probe:%s\n' "$1"; }
    verification_case_transparent_diagnose() { printf 'diagnose:%s\n' "$1"; }
    verification_case_tproxy_delete() { printf 'tproxy_delete:%s\n' "$1"; }
    verification_case_redirect_delete() { printf 'redirect_delete:%s\n' "$1"; }
    verification_mark_step() { :; }
    jq() { :; }
    verification_case_transparent_policy "${base}"
  )
  expected=$(printf 'redirect_create:%s\ntproxy_probe:%s\ndiagnose:both\ntproxy_delete:%s\nredirect_delete:%s\n' \
    "${base}" "$((base + 1))" "$((base + 4))" "$((base + 5))")
  assert_equal "${expected}" "${result}"
done

# Wrapper routing and precise final store revisions remain independently testable.
for scene in component_direct_inbound component_redirect_inbound component_tproxy_inbound component_transparent_policy; do
  result=$(
    verification_case_context_start() { printf 'context\n'; }
    verification_assert_atomic_socks_baseline() { printf 'baseline\n'; }
    verification_case_assert_clean() { printf 'clean:%s\n' "$1"; }
    verification_case_direct_inbound() { printf 'direct:%s:%s\n' "$1" "$2"; }
    verification_case_redirect_create() { printf 'redirect_create:%s\n' "$1"; }
    verification_case_redirect_delete() { printf 'redirect_delete:%s\n' "$1"; }
    verification_case_tproxy_create_probe() { printf 'tproxy_probe:%s\n' "$1"; }
    verification_case_transparent_diagnose() { printf 'diagnose:%s\n' "$1"; }
    verification_case_tproxy_delete() { printf 'tproxy_delete:%s\n' "$1"; }
    verification_case_transparent_policy() { printf 'transparent:%s\n' "$1"; }
    source "${SCENARIO_DIR}/${scene}.sh"
    "verification_scenario_${scene}"
  )
  case "${scene}" in
    component_direct_inbound) tail_expected=$'direct:0:delete\nclean:4' ;;
    component_redirect_inbound) tail_expected=$'redirect_create:0\nredirect_delete:1\nclean:2' ;;
    component_tproxy_inbound) tail_expected=$'tproxy_probe:0\ndiagnose:tproxy\ntproxy_delete:3\nclean:4' ;;
    component_transparent_policy) tail_expected=$'transparent:0\nclean:6' ;;
  esac
  assert_equal "$(printf 'context\nbaseline\nSCENARIO=%s\n%s' "${scene}" "${tail_expected}")" "${result}"

  # Use a separate shell so an outer conditional cannot disable errexit inside
  # the scenario function. Its context's EXIT trap must preserve the failure.
  cat > "${TMP_DIR}/failure.sh" <<'FAILURE'
#!/usr/bin/env bash
set -euo pipefail
verification_case_context_start() { trap 'status=$?; printf "cleanup:%s\n" "${status}" >> "${FAILURE_LOG}"; exit "${status}"' EXIT; }
verification_assert_atomic_socks_baseline() { :; }
verification_case_assert_clean() { printf 'unexpected_clean\n' >> "${FAILURE_LOG}"; }
verification_case_direct_inbound() { return 17; }
verification_case_redirect_create() { return 17; }
verification_case_tproxy_create_probe() { return 17; }
verification_case_transparent_policy() { return 17; }
source "${SCENARIO_DIR}/${SCENE}.sh"
"verification_scenario_${SCENE}"
FAILURE
  status=0
  env SCENARIO_DIR="${SCENARIO_DIR}" SCENE="${scene}" FAILURE_LOG="${TMP_DIR}/${scene}.failure" \
    bash "${TMP_DIR}/failure.sh" > /dev/null || status=$?
  [[ "${status}" == 17 ]]
  assert_equal 'cleanup:17' "$(cat "${TMP_DIR}/${scene}.failure")"
done

# Keep actual data-plane and ownership checks in the shared runtime code.
for required in \
  'verification_fixture_tcp_marker' 'verification_fixture_udp_echo' \
  'DATA_PLANE=direct_tcp_override_loopback' 'DATA_PLANE=direct_udp_override_loopback' \
  'verification_execute_redirect_probe' 'verification_execute_tproxy_probe' \
  'installer_owned_ipv4_tcp_udp_prerouting_policy_route' \
  'Managed TProxy policy rule remained after component deletion' \
  'Managed TProxy route table remained populated after component deletion' \
  'verification_assert_redirect_policy_removed' 'verification_cleanup_tproxy_probe_fixture'; do
  grep -Fq "${required}" "${SCENARIO_DIR}/policy_cases.sh"
done
if grep -Fq 'managed-host-policy-revision-6.json' "${SCENARIO_DIR}/policy_cases.sh"; then
  printf 'TProxy artifact revision must be relative to the explicit CAS base\n' >&2
  exit 1
fi
printf 'Policy leaf revision composition, cleanup failure and runtime-boundary contracts passed\n'
