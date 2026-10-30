#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
FIXTURE="${TMP_DIR}/repository"
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${FIXTURE}/dev" "${TMP_DIR}/bin"
cp -R "${REPO_ROOT}/dev/verification" "${FIXTURE}/dev/"
cp -R "${REPO_ROOT}/tests" "${FIXTURE}/"
cp "${REPO_ROOT}/install.sh" "${REPO_ROOT}/README.md" \
  "${REPO_ROOT}/bootstrap.sh" "${REPO_ROOT}/SECURITY.md" "${FIXTURE}/"
mkdir -p "${FIXTURE}/docs/wiki"
cp "${REPO_ROOT}/docs/wiki/Getting-Started.md" "${FIXTURE}/docs/wiki/"
cat >> "${FIXTURE}/install.sh" <<'FIXTURE_VERSION_LITERAL'
verification_fixture_version_literal() {
  cat <<'VERSION_TEXT'
# Version: 2000010101
readonly SCRIPT_VERSION="2000010101"
VERSION_TEXT
}
FIXTURE_VERSION_LITERAL

for name in committed staged unstaged; do
  printf '#!/usr/bin/env bash\n: fixture-%s\n' "${name}" > "${FIXTURE}/tests/fixture_${name}.sh"
done

printf '#!/usr/bin/env bash\n: helper baseline\n' > "${FIXTURE}/tests/fixture_helper.sh"
cat > "${FIXTURE}/tests/fixture_source_test.sh" <<'FIXTURE_CALLER'
#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/fixture_helper.sh"
FIXTURE_CALLER

git -C "${FIXTURE}" init -q
git -C "${FIXTURE}" config user.email planner-test@example.invalid
git -C "${FIXTURE}" config user.name 'Planner regression fixture'
git -C "${FIXTURE}" add .
git -C "${FIXTURE}" -c commit.gpgsign=false commit -qm 'test: establish planner baseline'
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
# Give the requested comparison branch its own commit, then return to a task
# branch at the original baseline. Its unrelated test must never enter our plan.
git -C "${FIXTURE}" checkout -qb planner-upstream
printf '#!/usr/bin/env bash\n: upstream only\n' > "${FIXTURE}/tests/fixture_upstream_only.sh"
git -C "${FIXTURE}" add tests/fixture_upstream_only.sh
git -C "${FIXTURE}" -c commit.gpgsign=false commit -qm 'test: add upstream-only fixture'
git -C "${FIXTURE}" checkout -qb planner-task "${BASE}"

export VERIFY_PLANNER_FIXTURE="${FIXTURE}"
export VERIFY_PLANNER_REAL_BASH="${REAL_BASH}"
export VERIFY_PLANNER_TEST_LOG="${TMP_DIR}/test-calls.log"
export VERIFY_PLANNER_DOCKER_LOG="${TMP_DIR}/docker-calls.log"
export VERIFY_PLANNER_EXECUTION_LOG="${TMP_DIR}/executed.log"

printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/bin/bash"
cat >> "${TMP_DIR}/bin/bash" <<'MOCK_BASH'
if [[ "${1:-}" == tests/*.sh || "${1:-}" == "${VERIFY_PLANNER_FIXTURE}/tests/"*.sh ]]; then
  printf '%s\n' "$1" >> "${VERIFY_PLANNER_TEST_LOG}"
  if [[ "${VERIFY_PLANNER_ALLOW_TESTS:-0}" != 1 ]]; then
    printf 'test execution is forbidden while planning\n' >&2
    exit 91
  fi
fi
exec "${VERIFY_PLANNER_REAL_BASH}" "$@"
MOCK_BASH
printf '#!%s\n' "${REAL_BASH}" > "${TMP_DIR}/bin/docker"
cat >> "${TMP_DIR}/bin/docker" <<'MOCK_DOCKER'
printf '%s\n' "$*" >> "${VERIFY_PLANNER_DOCKER_LOG}"
printf 'Docker execution is forbidden in this planner fixture\n' >&2
exit 92
MOCK_DOCKER
chmod +x "${TMP_DIR}/bin/bash" "${TMP_DIR}/bin/docker"

fixture_run() {
  (
    cd "${FIXTURE}"
    env -u VERIFY_SKIP_LOCAL_TESTS -u VERIFY_SKIP_REMOTE \
      PATH="${TMP_DIR}/bin:${PATH}" "${REAL_BASH}" \
      "${FIXTURE}/dev/verification/run.sh" "$@"
  )
}

assert_line() {
  local expected=$1
  local output=$2
  if ! grep -Fqx "${expected}" <<<"${output}"; then
    printf 'missing plan line %s in:\n%s\n' "${expected}" "${output}" >&2
    exit 1
  fi
}

assert_no_planning_side_effects() {
  [[ ! -e "${FIXTURE}/dev/verification-runs" ]]
  [[ ! -e "${VERIFY_PLANNER_TEST_LOG}" ]]
  [[ ! -e "${VERIFY_PLANNER_DOCKER_LOG}" ]]
  [[ ! -e "${VERIFY_PLANNER_EXECUTION_LOG}" ]]
}

assert_error_2() {
  local status=0
  fixture_run "$@" > "${TMP_DIR}/error.stdout" 2> "${TMP_DIR}/error.stderr" || status=$?
  if [[ "${status}" -ne 2 ]]; then
    printf 'expected exit 2, got %s for %s\n' "${status}" "$*" >&2
    cat "${TMP_DIR}/error.stdout" "${TMP_DIR}/error.stderr" >&2
    exit 1
  fi
}

# A clean repository has no work, and plan generation creates no run artifacts.
plan=$(fixture_run --plan)
assert_line 'mode=local' "${plan}"
assert_line 'plan_status=ready' "${plan}"
assert_line "base=${BASE}" "${plan}"
assert_no_planning_side_effects

# Version metadata must not pull in installation or protocol regressions.
sed -i '4s/^# Version: .*/# Version: 2099010101/;11s/^readonly SCRIPT_VERSION=.*/readonly SCRIPT_VERSION="2099010101"/' "${FIXTURE}/install.sh"
plan=$(fixture_run --plan --base "${BASE}")
assert_line 'mode=local' "${plan}"
assert_line 'plan_status=ready' "${plan}"
assert_line 'syntax=install.sh' "${plan}"
assert_line 'test=tests/version_metadata_is_consistent.sh' "${plan}"
! grep -q '^scenario=' <<<"${plan}"
assert_no_planning_side_effects

# Identical-looking version lines inside a heredoc are behavior, not metadata.
# Changing only those lines must not be hidden by global version normalization.
sed -i 's/2000010101/2000010102/g' "${FIXTURE}/install.sh"
plan=$(fixture_run --plan --base "${BASE}")
assert_line 'plan_status=needs_scope' "${plan}"
assert_error_2 --base "${BASE}"
assert_no_planning_side_effects
plan=$(fixture_run --plan --base "${BASE}" --group menu)
assert_line 'plan_status=ready' "${plan}"
assert_line 'mode=local' "${plan}"
! grep -q '^scenario=' <<<"${plan}"

# Restore only this disposable fixture file before testing independent mappings.
git -C "${FIXTURE}" show "${BASE}:install.sh" > "${FIXTURE}/install.sh"
plan=$(fixture_run --plan --changed-file bootstrap.sh)
assert_line 'test=tests/bootstrap_download.sh' "${plan}"
assert_line 'mode=local' "${plan}"
assert_no_planning_side_effects
plan=$(fixture_run --plan --changed-file docs/wiki/Getting-Started.md)
assert_line 'test=tests/bootstrap_download.sh' "${plan}"
assert_line 'mode=local' "${plan}"
assert_no_planning_side_effects

# Base-relative selection must include committed, staged, unstaged and new tests.
printf '# committed modification\n' >> "${FIXTURE}/tests/fixture_committed.sh"
git -C "${FIXTURE}" add tests/fixture_committed.sh
git -C "${FIXTURE}" -c commit.gpgsign=false commit -qm 'test: change committed fixture'
printf '# staged modification\n' >> "${FIXTURE}/tests/fixture_staged.sh"
git -C "${FIXTURE}" add tests/fixture_staged.sh
printf '# unstaged modification\n' >> "${FIXTURE}/tests/fixture_unstaged.sh"
cat > "${FIXTURE}/tests/fixture_untracked.sh" <<'FIXTURE_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'selected\n' >> "${VERIFY_PLANNER_EXECUTION_LOG:?}"
FIXTURE_TEST
plan=$(fixture_run --plan --base "${BASE}")
assert_line "base=${BASE}" "${plan}"
for name in committed staged unstaged untracked; do
  assert_line "test=tests/fixture_${name}.sh" "${plan}"
  [[ $(grep -Fxc "test=tests/fixture_${name}.sh" <<<"${plan}") -eq 1 ]]
done
assert_line 'mode=local' "${plan}"
assert_no_planning_side_effects

plan=$(fixture_run --plan --base planner-upstream)
assert_line "base=${BASE}" "${plan}"
assert_line 'test=tests/fixture_committed.sh' "${plan}"
! grep -Fqx 'test=tests/fixture_upstream_only.sh' <<<"${plan}"
assert_no_planning_side_effects

# Changed helpers select their actual callers instead of running a helper as a test.
printf '# helper modification\n' >> "${FIXTURE}/tests/fixture_helper.sh"
plan=$(fixture_run --plan --changed-file tests/fixture_helper.sh)
assert_line 'test=tests/fixture_source_test.sh' "${plan}"
! grep -Fqx 'test=tests/fixture_helper.sh' <<<"${plan}"
assert_no_planning_side_effects

# Container-only fixtures must not reach the host through any selector.
for fixture in tests/hy2_instance_acme_runtime.sh tests/component_runtime_acceptance.sh \
  tests/selector_urltest_runtime.sh tests/acme_component_runtime.sh \
  tests/cloudflared_runtime.sh tests/tailscale_openconnect_runtime.sh tests/namespace_core_runtime.sh; do
  plan=$(fixture_run --plan --changed-file "${fixture}" --group docs)
  assert_line 'plan_status=needs_scope' "${plan}"
  ! grep -Fqx "test=${fixture}" <<<"${plan}"
  plan=$(fixture_run --plan --changed-file "${fixture}" --scenario multi_protocol_coexistence)
  assert_line 'plan_status=needs_scope' "${plan}"
  plan=$(fixture_run --plan --changed-file "${fixture}" --full)
  assert_line 'plan_status=needs_scope' "${plan}"
  ! grep -Fqx "test=${fixture}" <<<"${plan}"
done
assert_no_planning_side_effects

plan=$(fixture_run --plan --changed-file README.md --group binary-install --group warp)
assert_line 'test=tests/binary_install_transactions.sh' "${plan}"
assert_line 'test=tests/binary_update_transactions.sh' "${plan}"
assert_line 'test=tests/binary_namespace_guard.sh' "${plan}"
assert_line 'test=tests/latest_version_lookup.sh' "${plan}"
assert_line 'test=tests/warp_registration_transactions.sh' "${plan}"
! grep -q '^scenario=' <<<"${plan}"
assert_no_planning_side_effects

# Invalid selectors must fail before producing artifacts or executing any work.
assert_error_2 --plan --base refs/heads/no-such-planner-reference
assert_error_2 --plan --unknown-option
assert_error_2 --plan --group no-such-planner-group
assert_error_2 --plan --scenario no-such-planner-scenario
assert_error_2 --plan --base "${BASE}" --changed-file README.md
assert_no_planning_side_effects

# A stale explicit manifest must fail rather than silently omit its required test.
mv "${FIXTURE}/tests/version_metadata_is_consistent.sh" "${TMP_DIR}/version-test.saved"
assert_error_2 --plan --changed-file README.md --group version
mv "${TMP_DIR}/version-test.saved" "${FIXTURE}/tests/version_metadata_is_consistent.sh"
assert_no_planning_side_effects

# Dependencies are ordered before their consumer and unrelated protocols stay out.
plan=$(fixture_run --plan --scenario reconfigure_existing_install)
scenarios=$(sed -n 's/^scenario=//p' <<<"${plan}" | paste -sd, -)
[[ "${scenarios}" == fresh_install_vless,reconfigure_existing_install,runtime_smoke ]]
plan=$(fixture_run --plan --scenario runtime_smoke)
scenarios=$(sed -n 's/^scenario=//p' <<<"${plan}" | paste -sd, -)
[[ "${scenarios}" == fresh_install_http,runtime_smoke ]]
plan=$(fixture_run --plan --scenario fresh_install_http --scenario fresh_install_http)
scenarios=$(sed -n 's/^scenario=//p' <<<"${plan}" | paste -sd, -)
[[ "${scenarios}" == fresh_install_http,runtime_smoke ]]
assert_no_planning_side_effects

# Full mode remains explicit and excludes a known container-only host-mutating fixture.
plan=$(fixture_run --plan --full)
! grep -Fqx 'test=tests/hy2_instance_acme_runtime.sh' <<<"${plan}"
assert_no_planning_side_effects

# A newly added standalone test must actually run exactly once, with no Docker.
VERIFY_PLANNER_ALLOW_TESTS=1 fixture_run --changed-file tests/fixture_untracked.sh > "${TMP_DIR}/execution.stdout"
grep -Fqx 'selected' "${VERIFY_PLANNER_EXECUTION_LOG}"
[[ $(wc -l < "${VERIFY_PLANNER_EXECUTION_LOG}") -eq 1 ]]
[[ $(wc -l < "${VERIFY_PLANNER_TEST_LOG}") -eq 1 ]]
[[ ! -e "${VERIFY_PLANNER_DOCKER_LOG}" ]]
printf 'Verification planner regression checks passed\n'
