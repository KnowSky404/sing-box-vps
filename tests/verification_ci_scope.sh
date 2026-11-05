#!/usr/bin/env bash

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
FIXTURE="${TMP_DIR}/repo"
mkdir -p "${FIXTURE}/dev/verification" "${FIXTURE}/tests" "${FIXTURE}/scripts" "${FIXTURE}/.github"
mkdir -p "${FIXTURE}/dev/verification/remote/scenarios"
touch "${FIXTURE}/dev/verification/remote/scenarios/"{fresh_install_socks,runtime_smoke}.sh
cp "${REPO_ROOT}"/dev/verification/{ci,common,planner,selection}.sh "${FIXTURE}/dev/verification/"
printf 'dev/verification-runs/\n' > "${FIXTURE}/.gitignore"
printf '#!/usr/bin/env bash\n: baseline\n' > "${FIXTURE}/install.sh"
printf 'fixture readme\n' > "${FIXTURE}/README.md"
printf 'base initial\n' > "${FIXTURE}/.github/verification-scope.txt"
for test in $(rg -o 'tests/[a-zA-Z0-9_]+\.sh' "${REPO_ROOT}/dev/verification/ci.sh") tests/fixture_changed.sh tests/fixture_requested.sh tests/install_build_sync.sh tests/readme_mentions_current_versions.sh; do
  printf '#!/usr/bin/env bash\n: fixture\n' > "${FIXTURE}/${test}"
done
for script in build-install build-command-docs; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "${FIXTURE}/scripts/${script}.sh"
done
cat <<'RUNNER' > "${FIXTURE}/dev/verification/run.sh"
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "${VERIFICATION_ROOT}/planner.sh"
verification_parse_options "$@"
verification_build_plan
verification_print_plan > "${CI_SCOPE_EXECUTION_LOG}"
printf 'skip_remote=%s\n' "${VERIFY_SKIP_REMOTE:-0}" >> "${CI_SCOPE_EXECUTION_LOG}"
RUNNER
git -C "${FIXTURE}" init -q
git -C "${FIXTURE}" config user.name 'CI fixture'
git -C "${FIXTURE}" config user.email 'fixture@example.invalid'
git -C "${FIXTURE}" add .
git -C "${FIXTURE}" commit -qm baseline
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
export CI_SCOPE_EXECUTION_LOG="${TMP_DIR}/executed-plan"
run_ci() { bash "${FIXTURE}/dev/verification/ci.sh" "${BASE}" > "${TMP_DIR}/output" 2>&1; }
assert_rejected() {
  rm -f "${CI_SCOPE_EXECUTION_LOG}"
  if run_ci; then cat "${TMP_DIR}/output" >&2; exit 1; fi
  [[ ! -e "${CI_SCOPE_EXECUTION_LOG}" ]]
}

printf 'changed\n' >> "${FIXTURE}/README.md"
printf ': changed\n' >> "${FIXTURE}/tests/fixture_changed.sh"
run_ci || { cat "${TMP_DIR}/output" >&2; exit 1; }
grep -Fxq 'test=tests/fixture_changed.sh' "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq 'test=tests/wiki_documentation.sh' "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq skip_remote=1 "${CI_SCOPE_EXECUTION_LOG}"

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
run_ci || { cat "${TMP_DIR}/output" >&2; exit 1; }
grep -Fxq 'test=tests/fixture_requested.sh' "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq 'test=tests/fixture_changed.sh' "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq 'scenario=fresh_install_socks' "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq skip_remote=1 "${CI_SCOPE_EXECUTION_LOG}"

# The previous branch's tracked scope cannot approve a later runtime change.
git -C "${FIXTURE}" add .
git -C "${FIXTURE}" commit -qm delivered
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
printf ': next-task\n' >> "${FIXTURE}/install.sh"
assert_rejected
printf 'CI baseline-bound scope and additive host selection passed\n'
