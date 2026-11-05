#!/usr/bin/env bash

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
FIXTURE="${TMP_DIR}/repo"
mkdir -p "${FIXTURE}/dev/verification/remote/scenarios" "${FIXTURE}/tests" "${FIXTURE}/scripts" "${FIXTURE}/.github"
touch "${FIXTURE}/dev/verification/remote/scenarios/"{fresh_install_socks,runtime_smoke}.sh
cp "${REPO_ROOT}"/dev/verification/{ci,common,planner,selection,run}.sh "${FIXTURE}/dev/verification/"
printf 'dev/verification-runs/\n' > "${FIXTURE}/.gitignore"
printf '#!/usr/bin/env bash\n: baseline\n' > "${FIXTURE}/install.sh"
printf 'fixture readme\n' > "${FIXTURE}/README.md"
printf 'base initial\n' > "${FIXTURE}/.github/verification-scope.txt"
for test in $(rg -o 'tests/[a-zA-Z0-9_]+\.sh' "${REPO_ROOT}/dev/verification/ci.sh") tests/fixture_changed.sh tests/fixture_requested.sh tests/install_build_sync.sh tests/readme_mentions_current_versions.sh tests/default_dual_stack_runtime.sh; do
  cat <<'TEST' > "${FIXTURE}/${test}"
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${BASH_SOURCE[0]##*/}" >> "${CI_SCOPE_EXECUTION_LOG}"
TEST
done
for script in build-install build-command-docs; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "${FIXTURE}/scripts/${script}.sh"
done
git -C "${FIXTURE}" init -q
git -C "${FIXTURE}" config user.name 'CI fixture'
git -C "${FIXTURE}" config user.email 'fixture@example.invalid'
git -C "${FIXTURE}" add .
git -C "${FIXTURE}" commit -qm baseline
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
ORIGINAL_BASE=${BASE}
export CI_SCOPE_EXECUTION_LOG="${TMP_DIR}/executed-tests"
export VERIFY_SKIP_LOCAL_TESTS=1
unset GITHUB_EVENT_NAME GITHUB_REF
run_ci() {
  local run_dir
  rm -f "${CI_SCOPE_EXECUTION_LOG}"
  bash "${FIXTURE}/dev/verification/ci.sh" "${BASE}" > "${TMP_DIR}/output" 2>&1 || return $?
  run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
  cp "${run_dir}/plan.txt" "${TMP_DIR}/last-plan"
  cp "${run_dir}/summary.log" "${TMP_DIR}/last-summary"
}
assert_rejected() {
  if run_ci; then cat "${TMP_DIR}/output" >&2; exit 1; fi
  [[ ! -e "${CI_SCOPE_EXECUTION_LOG}" ]]
}
expect_success() { run_ci || { cat "${TMP_DIR}/output" >&2; exit 1; }; }

printf 'changed\n' >> "${FIXTURE}/README.md"
printf ': changed\n' >> "${FIXTURE}/tests/fixture_changed.sh"
expect_success
grep -Fxq 'test=tests/fixture_changed.sh' "${TMP_DIR}/last-plan"
grep -Fxq fixture_changed.sh "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq wiki_documentation.sh "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq local_status=passed "${TMP_DIR}/last-summary"

printf ': runtime-change\n' >> "${FIXTURE}/install.sh"
assert_rejected
printf 'base invalid\n--test tests/fixture_requested.sh\n' > "${FIXTURE}/.github/verification-scope.txt"
assert_rejected
printf 'base %s\n' "${BASE}" > "${FIXTURE}/.github/verification-scope.txt"
assert_rejected
for selector in '--full ignored' '--base other' '--test ../outside.sh' '--test tests/fixture_helper.sh' '--test tests/fixture_requested.sh;touch marker'; do
  printf 'base %s\n%s\n' "${BASE}" "${selector}" > "${FIXTURE}/.github/verification-scope.txt"
  assert_rejected
done
printf 'base %s\n--test tests/fixture_requested.sh\n--scenario fresh_install_socks\n' "${BASE}" > "${FIXTURE}/.github/verification-scope.txt"
expect_success
grep -Fxq 'test=tests/fixture_requested.sh' "${TMP_DIR}/last-plan"
grep -Fxq 'scenario=fresh_install_socks' "${TMP_DIR}/last-plan"
grep -Fxq fixture_requested.sh "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq remote_status=required_not_run "${TMP_DIR}/last-summary"

# A dedicated container fixture stays unexecuted while actual host checks run.
printf ': container-change\n' >> "${FIXTURE}/tests/default_dual_stack_runtime.sh"
expect_success
grep -Fxq plan_status=needs_scope "${TMP_DIR}/last-plan"
grep -Fxq local_status=passed "${TMP_DIR}/last-summary"
! grep -Fxq default_dual_stack_runtime.sh "${CI_SCOPE_EXECUTION_LOG}"

git -C "${FIXTURE}" add .
git -C "${FIXTURE}" commit -qm delivered
TASK_COMMIT=$(git -C "${FIXTURE}" rev-parse HEAD)
BASE=${TASK_COMMIT}
printf ': next-task\n' >> "${FIXTURE}/install.sh"
assert_rejected
git -C "${FIXTURE}" restore install.sh

# Model GitHub rebasing an accepted branch onto an unrelated newer main.
git -C "${FIXTURE}" checkout -qb newer-main "${ORIGINAL_BASE}"
printf 'upstream\n' > "${FIXTURE}/upstream-note.md"
git -C "${FIXTURE}" add upstream-note.md
git -C "${FIXTURE}" commit -qm upstream
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
git -C "${FIXTURE}" cherry-pick "${TASK_COMMIT}" >/dev/null
assert_rejected
GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main expect_success
grep -Fxq local_status=passed "${TMP_DIR}/last-summary"
grep -Fxq fixture_requested.sh "${CI_SCOPE_EXECUTION_LOG}"

# Another accepted PR may have already published this exact scope content.
git -C "${FIXTURE}" checkout -qb identical-scope-main "${ORIGINAL_BASE}"
git -C "${FIXTURE}" show "${TASK_COMMIT}:.github/verification-scope.txt" > "${FIXTURE}/.github/verification-scope.txt"
printf 'upstream\n' > "${FIXTURE}/upstream-note.md"
git -C "${FIXTURE}" add .github/verification-scope.txt upstream-note.md
git -C "${FIXTURE}" commit -qm identical-scope-upstream
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
git -C "${FIXTURE}" cherry-pick "${TASK_COMMIT}" >/dev/null
assert_rejected
GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main expect_success
printf 'base %s\n--test tests/fixture_requested.sh\n' "${TASK_COMMIT}" > "${FIXTURE}/.github/verification-scope.txt"
GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main assert_rejected
printf 'CI strict PR scope, rebase push and dedicated-runtime host boundary passed\n'
