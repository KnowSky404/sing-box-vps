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
for test in $(grep -oE 'tests/[a-zA-Z0-9_]+\.sh' "${REPO_ROOT}/dev/verification/ci.sh") tests/fixture_changed.sh tests/fixture_requested.sh tests/install_build_sync.sh tests/readme_mentions_current_versions.sh tests/default_dual_stack_runtime.sh tests/bootstrap_download.sh tests/http_structured_takeover.sh tests/http_export_runtime.sh tests/managed_component_graph.sh tests/routing_policy_config.sh; do
  cat <<'TEST' > "${FIXTURE}/${test}"
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${BASH_SOURCE[0]##*/}" >> "${CI_SCOPE_EXECUTION_LOG}"
if [[ -n "${CI_DRIFT_IN_TEST:-}" && "${BASH_SOURCE[0]##*/}" == install_build_sync.sh ]]; then
  git switch -q --detach "${CI_DRIFT_IN_TEST}"
fi
if [[ "${CI_DIRTY_DRIFT:-}" == 1 && "${BASH_SOURCE[0]##*/}" == install_build_sync.sh ]]; then
  printf '# changed during host verification\n' >> .github/verification-scope.txt
fi
if [[ "${CI_CRLF_DRIFT:-}" == 1 && "${BASH_SOURCE[0]##*/}" == install_build_sync.sh ]]; then
  printf 'local readme\r\n' > README.md
fi
if [[ "${CI_REMOVE_RESULTS:-}" == 1 && "${BASH_SOURCE[0]##*/}" == wiki_documentation.sh ]]; then
  for results in dev/verification-runs/*/local-tests/results.tsv; do
    [[ ! -f "${results}" ]] || rm -- "${results}"
  done
fi
if [[ "${BASH_SOURCE[0]##*/}" == install_build_sync.sh ]]; then
  printf 'fixture build output\n'
  if [[ "${CI_REWRITE_AT_SCAN:-0}" == 1 ]]; then
    printf 'SKIP fixture: missing dependency\n'
  fi
fi
if [[ -n "${CI_DAMAGE_EARLIER_LOG:-}" && "${BASH_SOURCE[0]##*/}" == wiki_documentation.sh ]]; then
  for log in dev/verification-runs/*/local-tests/install_build_sync.sh.log; do
    case "${CI_DAMAGE_EARLIER_LOG}" in
      remove) rm -- "${log}" ;;
      truncate) : > "${log}" ;;
      replace) printf 'different output\n' > "${log}" ;;
    esac
  done
fi
if [[ -n "${CI_REMOVE_SUMMARY:-}" && "${BASH_SOURCE[0]##*/}" == wiki_documentation.sh ]]; then
  for summary in dev/verification-runs/*/summary.log; do
    [[ ! -f "${summary}" ]] || rm -- "${summary}"
  done
  if [[ "${CI_REMOVE_SUMMARY}" == fail ]]; then exit 42; fi
fi
if [[ "${CI_DAMAGE_PLAN:-}" == 1 && "${BASH_SOURCE[0]##*/}" == wiki_documentation.sh ]]; then
  for plan in dev/verification-runs/*/plan.txt; do
    [[ ! -f "${plan}" ]] || : > "${plan}"
  done
fi
if [[ -n "${CI_DRIFT_CORE:-}" && "${BASH_SOURCE[0]##*/}" == install_build_sync.sh ]]; then
  printf '# changed bytes, same version\n' >> "${CI_DRIFT_CORE}"
fi
if [[ -n "${CI_SKIP_HOST_TEST:-}" && "${BASH_SOURCE[0]##*/}" == "${CI_SKIP_TEST_FILE:-wiki_documentation.sh}" ]]; then
  printf '%s\n' "${CI_SKIP_HOST_TEST}"
  if [[ -n "${CI_CORE_PROOF:-}" ]]; then printf '%s\n' "${CI_CORE_PROOF}"; fi
fi
if [[ "${BASH_SOURCE[0]##*/}" == managed_listener_resources.sh ]]; then
  [[ "${SBV_TEST_ISOLATED_LISTENER_WILDCARD:-1}" == 0 ]]
  printf 'SKIP isolated IPv6 wildcard startup contrast: Docker only\n'
fi
if [[ "${BASH_SOURCE[0]##*/}" == managed_openvpn_endpoint_runtime.sh ]]; then
  [[ "${SBV_CI_HOST_ONLY:-0}" == 1 ]]
  printf 'SKIP OpenVPN system endpoint runtime: TUN unavailable\n'
fi
if [[ -n "${CI_EXPECT_ROUTING_CORE:-}" && ( "${BASH_SOURCE[0]##*/}" == routing_policy_config.sh ||
    "${BASH_SOURCE[0]##*/}" == routing_policy_instance_baseline.sh ) ]]; then
  [[ "${ROUTING_POLICY_TEST_REAL_CORE:-}" == "${CI_EXPECT_ROUTING_CORE}" ]]
fi
if [[ -n "${CI_OLDER_TAKEOVER:-}" && "${BASH_SOURCE[0]##*/}" == http_structured_takeover.sh ]]; then
  printf 'SKIP HTTP real-core check: binary unavailable\n'
  printf 'HTTP structured takeover checks passed; real core checks=%s\n' "${CI_OLDER_TAKEOVER}"
fi
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
unset SINGBOX_BINARY_113 SINGBOX_BINARY_114 ROUTING_POLICY_TEST_REAL_CORE
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

# A second clean revision can require a different plan.
git -C "${FIXTURE}" switch -qc drift
printf '#!/usr/bin/env bash\n: fixture\n' > "${FIXTURE}/bootstrap.sh"
git -C "${FIXTURE}" add bootstrap.sh
git -C "${FIXTURE}" commit -qm drift
DRIFT_HEAD=$(git -C "${FIXTURE}" rev-parse HEAD)
git -C "${FIXTURE}" switch -q --detach "${BASE}"
mkdir "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/git" <<'TEST'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == merge-base && "$3" == HEAD ]]; then
  "${CI_REAL_GIT}" switch -q --detach "${CI_DRIFT_HEAD}"
fi
exec "${CI_REAL_GIT}" "$@"
TEST
chmod +x "${TMP_DIR}/bin/git"
CI_REAL_GIT=$(command -v git) CI_DRIFT_HEAD="${DRIFT_HEAD}" PATH="${TMP_DIR}/bin:${PATH}" assert_rejected
grep -Fq 'CI inputs changed during planning' "${TMP_DIR}/output"
[[ $(git -C "${FIXTURE}" rev-parse HEAD) == "${DRIFT_HEAD}" ]]
git -C "${FIXTURE}" switch -q --detach "${BASE}"

if CI_DRIFT_IN_TEST="${DRIFT_HEAD}" run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq "head=${BASE}" "${run_dir}/summary.log"
grep -Fxq evidence=inputs_changed "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi
git -C "${FIXTURE}" switch -q --detach "${BASE}"

# Git can normalize away changes to the actual bytes a host test reads.
git -C "${FIXTURE}" config core.autocrlf true
printf 'local readme\n' > "${FIXTURE}/README.md"
before=$(git -C "${FIXTURE}" diff -- README.md)
if CI_CRLF_DRIFT=1 run_ci; then exit 1; fi
[[ "$(git -C "${FIXTURE}" diff -- README.md)" == "${before}" ]]
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq evidence=inputs_changed "${run_dir}/summary.log"
git -C "${FIXTURE}" config --unset core.autocrlf
git -C "${FIXTURE}" restore README.md

# Successful test processes must leave a complete result for every planned test.
if CI_REMOVE_RESULTS=1 run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq evidence=results_incomplete "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi

for damage in remove truncate replace; do
  if CI_DAMAGE_EARLIER_LOG="${damage}" run_ci; then exit 1; fi
  run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
  grep -Fxq evidence=results_incomplete "${run_dir}/summary.log"
  grep -Fxq host_gate=failed "${run_dir}/summary.log"
  grep -Eq '^tests/install_build_sync\.sh[[:space:]]+passed[[:space:]]' "${run_dir}/local-tests/results.tsv"
done

if CI_DAMAGE_PLAN=1 run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq evidence=results_incomplete "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"

if CI_REMOVE_SUMMARY=1 run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq evidence=results_incomplete "${run_dir}/summary.log"
grep -Fxq "head=${BASE}" "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi

status=0
CI_REMOVE_SUMMARY=fail run_ci || status=$?
[[ "${status}" == 42 ]]
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq "head=${BASE}" "${run_dir}/summary.log"
grep -Fxq "base=${BASE}" "${run_dir}/summary.log"
grep -Fxq local_status=failed "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"

printf '#!/usr/bin/env bash\nprintf "sing-box version 1.14.4\\n"\n' > "${TMP_DIR}/core"
printf '#!/usr/bin/env bash\nprintf "sing-box version 1.13.18\\n"\n' > "${TMP_DIR}/core113"
chmod +x "${TMP_DIR}/core" "${TMP_DIR}/core113"
mkdir "${TMP_DIR}/shadow-bin"
cp -p "${TMP_DIR}/core113" "${TMP_DIR}/shadow-bin/candidate-core"
cp -p "${TMP_DIR}/core" "${FIXTURE}/candidate-core"
printf '\n/candidate-core\n' >> "${FIXTURE}/.git/info/exclude"
SINGBOX_BINARY_114=candidate-core PATH="${TMP_DIR}/shadow-bin:${PATH}" expect_success
grep -Fxq 'validation_core=sing-box version 1.14.4' "${TMP_DIR}/last-summary"
printf 'not executable\n' > "${TMP_DIR}/bad-core"
for core in "${TMP_DIR}/bad-core" "${TMP_DIR}/core"; do
  SINGBOX_BINARY_113="${core}" assert_rejected
  grep -Fq 'Configured sing-box 1.13 validation core is unusable' "${TMP_DIR}/output"
done

# Existing candidates may omit their core checks without printing a marker.
printf 'for binary_var in SINGBOX_BINARY_113 SINGBOX_BINARY_114; do :; done\n' >> "${FIXTURE}/tests/managed_component_graph.sh"
assert_rejected
grep -Fq 'Selected check requires SINGBOX_BINARY_114: tests/managed_component_graph.sh' "${TMP_DIR}/output"
SINGBOX_BINARY_114="${TMP_DIR}/core" expect_success
git -C "${FIXTURE}" restore tests/managed_component_graph.sh
printf ': select older compatibility fixture\n' >> "${FIXTURE}/tests/singbox_1_14_compatibility.sh"
SINGBOX_BINARY_114="${TMP_DIR}/core" assert_rejected
grep -Fq 'Selected check requires SINGBOX_BINARY_113 and SINGBOX_BINARY_114:' "${TMP_DIR}/output"
SINGBOX_BINARY_113="${TMP_DIR}/core113" SINGBOX_BINARY_114="${TMP_DIR}/core" expect_success
git -C "${FIXTURE}" restore tests/singbox_1_14_compatibility.sh

printf '# changed routing probe\n' > "${FIXTURE}/tests/routing_policy_private_runtime.py"
assert_rejected
grep -Fq 'Selected routing check requires SINGBOX_BINARY_114: tests/routing_policy_config.sh' "${TMP_DIR}/output"
SINGBOX_BINARY_114="${TMP_DIR}/core" CI_EXPECT_ROUTING_CORE="${TMP_DIR}/core" expect_success
grep -Fxq routing_policy_config.sh "${CI_SCOPE_EXECUTION_LOG}"
cp "${TMP_DIR}/core" "${TMP_DIR}/other-core"
SINGBOX_BINARY_114="${TMP_DIR}/core" ROUTING_POLICY_TEST_REAL_CORE="${TMP_DIR}/other-core" assert_rejected
grep -Fq 'Routing probe core conflicts with SINGBOX_BINARY_114' "${TMP_DIR}/output"
rm -- "${FIXTURE}/tests/routing_policy_private_runtime.py"
printf ': select standalone routing baseline\n' >> "${FIXTURE}/tests/routing_policy_instance_baseline.sh"
assert_rejected
grep -Fq 'Selected routing check requires SINGBOX_BINARY_114: tests/routing_policy_instance_baseline.sh' "${TMP_DIR}/output"
SINGBOX_BINARY_114="${TMP_DIR}/core" CI_EXPECT_ROUTING_CORE="${TMP_DIR}/core" expect_success
grep -Fxq routing_policy_instance_baseline.sh "${CI_SCOPE_EXECUTION_LOG}"
git -C "${FIXTURE}" restore tests/routing_policy_instance_baseline.sh

if SINGBOX_BINARY_114="${TMP_DIR}/core" CI_DRIFT_CORE="${TMP_DIR}/core" run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq evidence=inputs_changed "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"
if SINGBOX_BINARY_113="${TMP_DIR}/core113" CI_DRIFT_CORE="${TMP_DIR}/core113" run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Eq '^validation_core_113_sha256=[0-9a-f]{64}$' "${run_dir}/summary.log"
grep -Fxq evidence=inputs_changed "${run_dir}/summary.log"

for skip in 'SKIP fixture: missing dependency' 'sing-box check not run: set SINGBOX_BINARY_114' \
  'real startup comparisons not run: configured cores missing' \
  'Trojan structured takeover checks passed; real core checks=0' \
  'structured instance store checks passed; real core checks=0; HTTP/SOCKS TCP probes=0' \
  'SKIP cross-version server compatibility: both validation cores are required'; do
  if CI_SKIP_HOST_TEST="${skip}" run_ci; then exit 1; fi
  run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
  grep -Fxq local_status=required_not_run "${run_dir}/summary.log"
  grep -Fxq host_gate=failed "${run_dir}/summary.log"
  grep -Eq '^tests/wiki_documentation\.sh[[:space:]]+skipped[[:space:]]+[0-9]+$' "${run_dir}/local-tests/results.tsv"
done

legacy_skip='SKIP HTTP export runtime: SINGBOX_BINARY_113 unavailable'
if SINGBOX_BINARY_114="${TMP_DIR}/core" CI_SKIP_HOST_TEST="${legacy_skip}" run_ci; then exit 1; fi
printf ': select HTTP runtime test\n' >> "${FIXTURE}/tests/http_export_runtime.sh"
runtime_proof='HTTP export runtime passed: core=1.14.4 (fixture)'
SINGBOX_BINARY_114="${TMP_DIR}/core" CI_SKIP_TEST_FILE=http_export_runtime.sh \
  CI_SKIP_HOST_TEST="${legacy_skip}" CI_CORE_PROOF="${runtime_proof}" expect_success
grep -Fxq validation_core_113_sha256=not_supplied "${TMP_DIR}/last-summary"
grep -Fxq host_gate=passed "${TMP_DIR}/last-summary"
if SINGBOX_BINARY_114="${TMP_DIR}/core" CI_SKIP_TEST_FILE=http_export_runtime.sh CI_SKIP_HOST_TEST="${legacy_skip}" run_ci; then exit 1; fi
if SINGBOX_BINARY_113="${TMP_DIR}/core113" SINGBOX_BINARY_114="${TMP_DIR}/core" CI_SKIP_TEST_FILE=http_export_runtime.sh \
  CI_SKIP_HOST_TEST="${legacy_skip}" CI_CORE_PROOF="${runtime_proof}" run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq local_status=required_not_run "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"
git -C "${FIXTURE}" restore tests/http_export_runtime.sh

printf ': select takeover test\n' >> "${FIXTURE}/tests/http_structured_takeover.sh"
SINGBOX_BINARY_114="${TMP_DIR}/core" CI_SKIP_TEST_FILE=http_structured_takeover.sh \
  CI_SKIP_HOST_TEST='SKIP HTTP real-core check: SINGBOX_BINARY_113 unavailable' \
  CI_CORE_PROOF='HTTP structured takeover checks passed; real core checks=1' expect_success
if SINGBOX_BINARY_114="${TMP_DIR}/core" CI_SKIP_TEST_FILE=http_structured_takeover.sh \
  CI_SKIP_HOST_TEST='SKIP HTTP real-core check: SINGBOX_BINARY_114 unavailable' run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq local_status=required_not_run "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"

SINGBOX_BINARY_114="${TMP_DIR}/core" CI_OLDER_TAKEOVER=1 expect_success
if SINGBOX_BINARY_114="${TMP_DIR}/core" CI_OLDER_TAKEOVER=0 run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq local_status=required_not_run "${run_dir}/summary.log"
git -C "${FIXTURE}" restore tests/http_structured_takeover.sh

# A scanner failure is distinct from a report with no skipped checks.
mkdir "${TMP_DIR}/bad-scanner"
cat > "${TMP_DIR}/bad-scanner/awk" <<'TEST'
#!/usr/bin/env bash
if [[ "${*: -1}" == */sbv-host-log.* ]]; then
  if [[ "${CI_REWRITE_AT_SCAN:-0}" != 1 ]]; then
    exit 2
  fi
  for log in dev/verification-runs/*/local-tests/install_build_sync.sh.log; do
    printf 'rewritten live log\n' > "${log}"
  done
fi
exec "${CI_REAL_AWK}" "$@"
TEST
chmod +x "${TMP_DIR}/bad-scanner/awk"
if CI_REAL_AWK=$(command -v awk) PATH="${TMP_DIR}/bad-scanner:${PATH}" run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq host_gate=failed "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi

if CI_REWRITE_AT_SCAN=1 CI_REAL_AWK=$(command -v awk) PATH="${TMP_DIR}/bad-scanner:${PATH}" run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq local_status=required_not_run "${run_dir}/summary.log"
grep -Fxq 'rewritten live log' "${run_dir}/local-tests/install_build_sync.sh.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi

printf ': select listener test\n' >> "${FIXTURE}/tests/managed_listener_resources.sh"
expect_success
grep -Fxq remote_status=required_not_run "${TMP_DIR}/last-summary"
grep -Fxq host_gate=passed "${TMP_DIR}/last-summary"
git -C "${FIXTURE}" restore tests/managed_listener_resources.sh

printf ': select OpenVPN test\n' >> "${FIXTURE}/tests/managed_openvpn_endpoint_runtime.sh"
expect_success
grep -Fxq remote_status=required_not_run "${TMP_DIR}/last-summary"
grep -Fxq host_gate=passed "${TMP_DIR}/last-summary"
git -C "${FIXTURE}" restore tests/managed_openvpn_endpoint_runtime.sh

# Local status configuration must not hide a selected untracked input.
git -C "${FIXTURE}" config status.showUntrackedFiles no
mkdir "${FIXTURE}/docs"
printf 'untracked document\n' > "${FIXTURE}/docs/task.md"
expect_success
grep -Fxq 'file=docs/task.md' "${TMP_DIR}/last-plan"
grep -Fxq 'worktree=dirty' "${TMP_DIR}/last-summary"
rm -- "${FIXTURE}/docs/task.md"
git -C "${FIXTURE}" config --unset status.showUntrackedFiles

ln -s "${TMP_DIR}/core" "${FIXTURE}/docs/link"
assert_rejected
grep -Fq 'CI cannot bind symlinked worktree input: docs/link' "${TMP_DIR}/output"
rm -- "${FIXTURE}/docs/link"

mkdir -p "${FIXTURE}/tests/first" "${FIXTURE}/tests/second"
printf '#!/usr/bin/env bash\nprintf "first log\\n"\n' > "${FIXTURE}/tests/first/same.sh"
printf '#!/usr/bin/env bash\nprintf "second log\\n"\n' > "${FIXTURE}/tests/second/same.sh"
expect_success
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq 'first log' "${run_dir}/local-tests/first/same.sh.log"
grep -Fxq 'second log' "${run_dir}/local-tests/second/same.sh.log"
rm -- "${FIXTURE}/tests/first/same.sh" "${FIXTURE}/tests/second/same.sh"

printf 'changed\n' >> "${FIXTURE}/README.md"
printf ': changed\n' >> "${FIXTURE}/tests/fixture_changed.sh"
expect_success
grep -Fxq 'test=tests/fixture_changed.sh' "${TMP_DIR}/last-plan"
grep -Fxq fixture_changed.sh "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq wiki_documentation.sh "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq local_status=passed "${TMP_DIR}/last-summary"
grep -Fxq host_gate=passed "${TMP_DIR}/last-summary"
grep -Fxq remote_status=not_required "${TMP_DIR}/last-summary"
grep -Fxq "head=${BASE}" "${TMP_DIR}/last-summary"
grep -Fxq "base=${BASE}" "${TMP_DIR}/last-summary"
grep -Fxq 'worktree=dirty' "${TMP_DIR}/last-summary"

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
printf 'base %s\n--test tests/fixture_requested.sh\n--test tests/install_build_sync.sh\n--scenario fresh_install_socks\n' "${BASE}" > "${FIXTURE}/.github/verification-scope.txt"
expect_success
grep -Fxq 'test=tests/fixture_requested.sh' "${TMP_DIR}/last-plan"
grep -Fxq 'scenario=fresh_install_socks' "${TMP_DIR}/last-plan"
grep -Fxq fixture_requested.sh "${CI_SCOPE_EXECUTION_LOG}"
grep -Fxq remote_status=required_not_run "${TMP_DIR}/last-summary"
[[ $(grep -Fxc install_build_sync.sh "${CI_SCOPE_EXECUTION_LOG}") == 1 ]]
[[ $(head -n 1 "${CI_SCOPE_EXECUTION_LOG}") == install_build_sync.sh ]]

# Changing an already-dirty file cannot pass just because porcelain is unchanged.
scope_status=$(git -C "${FIXTURE}" status --porcelain)
if CI_DIRTY_DRIFT=1 run_ci; then exit 1; fi
[[ "$(git -C "${FIXTURE}" status --porcelain)" == "${scope_status}" ]]
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq evidence=inputs_changed "${run_dir}/summary.log"
grep -Fxq host_gate=failed "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi

# Host failure is terminal, even though the CI artifact directory exists.
printf 'exit 42\n' >> "${FIXTURE}/tests/fixture_requested.sh"
status=0
run_ci || status=$?
[[ "${status}" == 42 ]]
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq host_gate=failed "${run_dir}/summary.log"
grep -Fxq local_status=failed "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi
git -C "${FIXTURE}" restore tests/fixture_requested.sh

# An otherwise successful test cannot leave an unwritable results path and pass.
cat >> "${FIXTURE}/tests/fixture_requested.sh" <<'TEST'
for results in dev/verification-runs/*/local-tests/results.tsv; do
  [[ -f "${results}" ]] || continue
  rm -- "${results}"
  mkdir -- "${results}"
done
TEST
if run_ci; then exit 1; fi
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq host_gate=failed "${run_dir}/summary.log"
if grep -Fxq host_gate=passed "${run_dir}/summary.log"; then exit 1; fi
git -C "${FIXTURE}" restore tests/fixture_requested.sh

# A dedicated container fixture stays unexecuted while actual host checks run.
printf ': container-change\n' >> "${FIXTURE}/tests/default_dual_stack_runtime.sh"
expect_success
grep -Fxq plan_status=needs_scope "${TMP_DIR}/last-plan"
grep -Fxq local_status=passed "${TMP_DIR}/last-summary"
if grep -Fxq default_dual_stack_runtime.sh "${CI_SCOPE_EXECUTION_LOG}"; then exit 1; fi

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
GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main assert_rejected
INTEGRATED_HEAD=$(git -C "${FIXTURE}" rev-parse HEAD)
git -C "${FIXTURE}" update-ref refs/remotes/origin/main "${INTEGRATED_HEAD}"
DRIVER_FIXTURE="${TMP_DIR}/protected-driver"
git clone --quiet --no-hardlinks "${FIXTURE}" "${DRIVER_FIXTURE}"
git -C "${DRIVER_FIXTURE}" checkout --quiet --detach "${INTEGRATED_HEAD}"
if bash "${DRIVER_FIXTURE}/dev/verification/ci.sh" "${BASE}" "${FIXTURE}" "${BASE}" > "${TMP_DIR}/output" 2>&1; then exit 1; fi
grep -Fq 'Protected main revision does not match the verifier checkout' "${TMP_DIR}/output"
bash "${DRIVER_FIXTURE}/dev/verification/ci.sh" "${BASE}" "${FIXTURE}" "${INTEGRATED_HEAD}" > "${TMP_DIR}/output" 2>&1
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq "base=${BASE}" "${run_dir}/summary.log"
grep -Fxq "scope_base=${ORIGINAL_BASE}" "${run_dir}/summary.log"
grep -Fxq "trusted_driver_sha=${INTEGRATED_HEAD}" "${run_dir}/summary.log"
grep -Fxq host_gate=passed "${run_dir}/summary.log"
grep -Fxq fixture_requested.sh "${CI_SCOPE_EXECUTION_LOG}"

# A later scope declaration cannot stand in for a second integrated PR.
git -C "${FIXTURE}" switch --quiet -c multiple-scopes
printf 'base %s\n--test tests/fixture_changed.sh\n' "${BASE}" > "${FIXTURE}/.github/verification-scope.txt"
git -C "${FIXTURE}" add .github/verification-scope.txt
git -C "${FIXTURE}" commit -qm 'second scope'
MULTIPLE_HEAD=$(git -C "${FIXTURE}" rev-parse HEAD)
git -C "${FIXTURE}" update-ref refs/remotes/origin/main "${MULTIPLE_HEAD}"
git -C "${DRIVER_FIXTURE}" fetch --quiet "${FIXTURE}" "${MULTIPLE_HEAD}"
git -C "${DRIVER_FIXTURE}" switch --quiet --detach "${MULTIPLE_HEAD}"
if bash "${DRIVER_FIXTURE}/dev/verification/ci.sh" "${BASE}" "${FIXTURE}" "${MULTIPLE_HEAD}" > "${TMP_DIR}/output" 2>&1; then exit 1; fi
grep -Fq 'Integrated CI requires one committed scope declaration' "${TMP_DIR}/output"
git -C "${FIXTURE}" switch --quiet newer-main

printf 'base %s\n--test tests/fixture_requested.sh\n' "${BASE}" > "${FIXTURE}/.github/verification-scope.txt"
expect_success
grep -Fxq host_gate=passed "${TMP_DIR}/last-summary"
git -C "${FIXTURE}" restore .github/verification-scope.txt

# Another accepted PR may have already published this exact scope content.
git -C "${FIXTURE}" checkout -qb identical-scope-main "${ORIGINAL_BASE}"
git -C "${FIXTURE}" show "${TASK_COMMIT}:.github/verification-scope.txt" > "${FIXTURE}/.github/verification-scope.txt"
printf 'upstream\n' > "${FIXTURE}/upstream-note.md"
git -C "${FIXTURE}" add .github/verification-scope.txt upstream-note.md
git -C "${FIXTURE}" commit -qm identical-scope-upstream
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
git -C "${FIXTURE}" cherry-pick "${TASK_COMMIT}" >/dev/null
assert_rejected
GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main assert_rejected
printf 'base %s\n--test tests/fixture_requested.sh\n' "${TASK_COMMIT}" > "${FIXTURE}/.github/verification-scope.txt"
GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main assert_rejected

# A protected driver can verify a candidate that has no compatible CI entry.
git -C "${FIXTURE}" restore .github/verification-scope.txt
git -C "${FIXTURE}" switch -qc older-ci "${ORIGINAL_BASE}"
printf '#!/usr/bin/env bash\nexit 99\n' > "${FIXTURE}/dev/verification/ci.sh"
git -C "${FIXTURE}" add dev/verification/ci.sh
git -C "${FIXTURE}" commit -qm older-ci
BASE=$(git -C "${FIXTURE}" rev-parse HEAD)
bash "${REPO_ROOT}/dev/verification/ci.sh" "${BASE}" "${FIXTURE}" > "${TMP_DIR}/output" 2>&1
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/output")
grep -Fxq "head=${BASE}" "${run_dir}/summary.log"
grep -Fxq host_gate=passed "${run_dir}/summary.log"
printf '# new candidate inventory\n' >> "${FIXTURE}/dev/verification/selection.sh"
rm -f "${CI_SCOPE_EXECUTION_LOG}"
if bash "${REPO_ROOT}/dev/verification/ci.sh" "${BASE}" "${FIXTURE}" > "${TMP_DIR}/output" 2>&1; then exit 1; fi
grep -Fq 'Candidate planning rules differ from the trusted driver' "${TMP_DIR}/output"
[[ ! -e "${CI_SCOPE_EXECUTION_LOG}" ]]
printf 'CI strict scope, final host result, and dedicated-runtime boundary passed\n'
