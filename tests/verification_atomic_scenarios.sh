#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
plan() { bash "${REPO_ROOT}/dev/verification/run.sh" --plan --changed-file README.md "$@"; }
assert_scenarios() {
  local expected=$1 actual
  shift
  actual=$(plan "$@" | sed -n 's/^scenario=//p' | paste -sd, -)
  [[ "${actual}" == "${expected}" ]] || { printf 'expected %s got %s\n' "${expected}" "${actual}" >&2; exit 1; }
}
for leaf in component_http_outbound component_rule_sets component_tor_outbound; do
  assert_scenarios "fresh_install_socks,${leaf},runtime_smoke" --scenario "${leaf}" --scenario "${leaf}"
done
assert_scenarios 'fresh_install_socks,component_rule_sets,fresh_install_socks,component_http_outbound,runtime_smoke' \
  --scenario component_rule_sets --scenario component_http_outbound
full=$(plan --full)
! grep -E '^scenario=component_(http_outbound|rule_sets|tor_outbound)$' <<<"${full}"
[[ $(grep -Fxc 'scenario=multi_protocol_coexistence' <<<"${full}") == 1 ]]
for file in coexistence_cases multi_protocol_coexistence; do
  out=$(bash "${REPO_ROOT}/dev/verification/run.sh" --plan --changed-file "dev/verification/remote/scenarios/${file}.sh")
  grep -Fqx 'plan_status=needs_scope' <<<"${out}"
  ! grep -q '^scenario=' <<<"${out}"
  out=$(bash "${REPO_ROOT}/dev/verification/run.sh" --plan --changed-file "dev/verification/remote/scenarios/${file}.sh" --group version)
  grep -Fqx 'plan_status=ready' <<<"${out}"
  ! grep -q '^scenario=' <<<"${out}"
done
# Leaf-body changes need their own contracts, not transport/artifact mocks.
for leaf in component_http_outbound component_rule_sets; do
  out=$(bash "${REPO_ROOT}/dev/verification/run.sh" --plan --changed-file "dev/verification/remote/scenarios/${leaf}.sh")
  grep -Fqx "scenario=${leaf}" <<<"${out}"
  ! grep -Fqx 'group=verification' <<<"${out}"
  ! grep -Fqx 'test=tests/verification_runtime_smoke_artifacts.sh' <<<"${out}"
  if [[ "${leaf}" == component_http_outbound ]]; then
    grep -Fqx 'test=tests/verification_atomic_http_outbound.sh' <<<"${out}"
  fi
done
out=$(plan --full --changed-file dev/verification/remote/scenarios/component_http_outbound.sh \
  --changed-file dev/verification/remote/scenarios/component_rule_sets.sh)
! grep -E '^scenario=component_(http_outbound|rule_sets|tor_outbound)$' <<<"${out}"
# Missing prerequisites must fail during planning rather than run a partial case.
mkdir -p "${TMP_DIR}/repo/dev/verification/remote"
cp -R "${REPO_ROOT}/dev/verification/remote/scenarios" "${TMP_DIR}/repo/dev/verification/remote/"
(
  source "${REPO_ROOT}/dev/verification/selection.sh"
  REPO_ROOT="${TMP_DIR}/repo"
  rm "${REPO_ROOT}/dev/verification/remote/scenarios/coexistence_cases.sh"
  if verification_expand_scenarios component_rule_sets > /dev/null 2>&1; then exit 1; fi
)
# Exercise the actual dispatcher and runner, with only service/probe work replaced.
# This preserves fail-fast/subshell/finalization behavior without Docker or root writes.
python3 - "${REPO_ROOT}" "${TMP_DIR}" <<'PY'
from pathlib import Path
import sys
root, temp=map(Path, sys.argv[1:])
s=(root/'dev/verification/remote/entrypoint.sh').read_text()
start=s.index('if ! mkdir "${LOCK_DIR}"')
prefix=s[:start].replace('readonly LOCK_DIR=/tmp/sing-box-vps-verification.lock', 'readonly LOCK_DIR="'+str(temp/'lock')+'"')
prefix=prefix.replace('VERIFY_ARTIFACT_DIR=$(mktemp -d /tmp/sing-box-vps-verification-artifacts.XXXXXX)', 'VERIFY_ARTIFACT_DIR="'+str(temp/'artifacts')+'"')
(temp/'artifacts').mkdir()
stubs='''
verification_capture_common_artifacts() { :; }
verification_initialize_run_artifacts() { :; }
verification_cleanup() { rmdir "${LOCK_DIR}"; }
verification_scenario_component_rule_sets() { printf 'selected\\n'; return "${ATOMIC_FIXTURE_STATUS:-0}"; }
verification_scenario_multi_protocol_coexistence() { exit 98; }
verification_scenario_component_tor_outbound() { exit 99; }
'''
(temp/'dispatch.sh').write_text(prefix+stubs+s[start:])
PY
bash "${TMP_DIR}/dispatch.sh" component_rule_sets > "${TMP_DIR}/dispatch.log"
grep -Fqx 'selected' "${TMP_DIR}/dispatch.log"
grep -Fqx 'EXIT_STATUS=0' "${TMP_DIR}/artifacts/scenarios/component_rule_sets/result.env"
status=0
ATOMIC_FIXTURE_STATUS=17 bash "${TMP_DIR}/dispatch.sh" component_rule_sets component_tor_outbound > /dev/null || status=$?
[[ "${status}" == 17 ]]
grep -Fqx 'EXIT_STATUS=17' "${TMP_DIR}/artifacts/scenarios/component_rule_sets/result.env"
[[ ! -e "${TMP_DIR}/artifacts/scenarios/component_tor_outbound" ]]
printf 'Atomic scenario selection, isolation, full deduplication and failure artifacts passed\n'
