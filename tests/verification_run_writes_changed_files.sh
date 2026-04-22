#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/git" <<EOF
#!${REAL_BASH}
if [[ "\$#" -eq 0 ]]; then
  exit 0
fi
if [[ "\${1:-}" == "diff" && "\${2:-}" == "--name-only" ]]; then
  if [[ -n "\${VERIFY_EMPTY_CHANGES:-}" ]]; then
    exit 0
  fi
  printf 'install.sh\nREADME.md\n'
  exit 0
fi
if [[ "\${1:-}" == "ls-files" && "\${2:-}" == "--others" && "\${3:-}" == "--exclude-standard" ]]; then
  if [[ -n "\${VERIFY_EMPTY_CHANGES:-}" ]]; then
    exit 0
  fi
  printf 'tests/new_untracked_case.sh\n'
  exit 0
fi
printf 'unexpected git call: %s\n' "\$*" >&2
exit 1
EOF
chmod +x "${TMP_DIR}/git"

cat > "${TMP_DIR}/bash" <<EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "${REPO_ROOT}/dev/verification/run.sh" ]]; then
  exec "${REAL_BASH}" "\$@"
fi
if [[ "\${1:-}" == tests/*.sh ]]; then
  printf '%s|%s\n' "\$1" "\${VERIFY_SKIP_LOCAL_TESTS:-unset}" >> "${TMP_DIR}/local-tests.log"
  exit 0
fi
exec "${REAL_BASH}" "\$@"
EOF
chmod +x "${TMP_DIR}/bash"

PATH="${TMP_DIR}:${PATH}" \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fqx 'install.sh' "${run_dir}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir}/changed-files.txt"
scenarios=$(paste -sd, "${run_dir}/scenarios.txt")
[[ "${scenarios}" == "fresh_install_vless,reconfigure_existing_install,runtime_smoke" ]] || {
  printf 'unexpected scenarios: %s\n' "${scenarios}" >&2
  exit 1
}
grep -Fqx 'tests/verification_trigger_rules.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_artifact_dir_layout.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_run_writes_changed_files.sh|1' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_scenario_mapping.sh|1' "${TMP_DIR}/local-tests.log"
[[ $(wc -l < "${TMP_DIR}/local-tests.log") -eq 4 ]] || {
  printf 'expected only verification workflow tests to run locally\n' >&2
  exit 1
}
default_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")

PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-skip.txt"

run_dir_skip=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-skip.txt")
grep -Fqx 'install.sh' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'README.md' "${run_dir_skip}/changed-files.txt"
grep -Fqx 'tests/new_untracked_case.sh' "${run_dir_skip}/changed-files.txt"
scenarios_skip=$(paste -sd, "${run_dir_skip}/scenarios.txt")
[[ "${scenarios_skip}" == "fresh_install_vless,reconfigure_existing_install,runtime_smoke" ]] || {
  printf 'unexpected scenarios for skip run: %s\n' "${scenarios_skip}" >&2
  exit 1
}
[[ "${default_local_test_count}" -gt 0 ]] || {
  printf 'expected default run to execute local tests\n' >&2
  exit 1
}
skip_local_test_count=$(wc -l < "${TMP_DIR}/local-tests.log")
[[ "${skip_local_test_count}" -eq "${default_local_test_count}" ]] || {
  printf 'expected skip run to avoid local tests: before=%s after=%s\n' "${default_local_test_count}" "${skip_local_test_count}" >&2
  exit 1
}

PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_EMPTY_CHANGES=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" > "${TMP_DIR}/stdout-empty.txt"

run_dir_empty=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout-empty.txt")
[[ ! -s "${run_dir_empty}/changed-files.txt" ]] || {
  printf 'expected empty change snapshot for empty change set\n' >&2
  exit 1
}
[[ ! -e "${run_dir_empty}/scenarios.txt" ]] || {
  printf 'did not expect scenarios.txt for local mode empty change set\n' >&2
  exit 1
}
