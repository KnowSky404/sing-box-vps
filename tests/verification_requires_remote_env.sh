#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

# Mock docker — image exists, container starts, exec pipes payload and returns bundle
cat > "${TMP_DIR}/docker" <<DOCKER_EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "image" && "\${2:-}" == "inspect" ]]; then
  [[ "\${VERIFY_DOCKER_FIXTURE_MODE:-}" != build_fail ]]
  exit \$?
fi
if [[ "\${1:-}" == build ]]; then
  exit 17
fi
if [[ "\${1:-}" == exec ]]; then
  : > "${TMP_DIR}/docker-exec-called"
fi
if [[ "\${1:-}" == "run" && "\${2:-}" == "-d" && "\${3:-}" == "--privileged" ]]; then
  : > "${TMP_DIR}/docker-run-called"
  if [[ "\${VERIFY_DOCKER_FIXTURE_MODE:-}" == run_fail ]]; then
    exit 19
  fi
  printf 'test-container-id-12345\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${3:-}" == "systemctl" && "\${4:-}" == "is-system-running" ]]; then
  printf 'running\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${2:-}" == "-i" ]]; then
  # Read stdin (the payload) and run it
  : > "${TMP_DIR}/docker-exec-active"
  cat > /dev/null
  sleep 0.2
  rm -f "${TMP_DIR}/docker-exec-active"
  printf 'SERVICE_ACTIVE=active\n'
  printf '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__\n'
  tar -C "${TMP_DIR}" -czf - . | base64
  printf '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__\n'
  exit 0
fi
if [[ "\${1:-}" == "rm" && "\${2:-}" == "-f" ]]; then
  if [[ -f "${TMP_DIR}/docker-exec-active" ]]; then
    : > "${TMP_DIR}/premature-docker-cleanup"
  fi
  exit 0
fi
printf 'unexpected docker call: %s\n' "\$*" >&2
exit 1
DOCKER_EOF
chmod +x "${TMP_DIR}/docker"

if PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file README.md --scenario fresh_install_http > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  :
else
  status=$?
  printf 'expected docker verification to succeed, got exit %d\n' "${status}" >&2
  cat "${TMP_DIR}/stderr.txt" >&2
  exit 1
fi

grep -Fq 'remote_target=docker:test-container-id-12345' "${TMP_DIR}/stdout.txt"
[[ ! -e "${TMP_DIR}/premature-docker-cleanup" ]]
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'remote_artifacts=extracted' "${run_dir}/summary.log"
# Failed prerequisites stop immediately and preserve their original exit status.
rm -f "${TMP_DIR}/docker-run-called" "${TMP_DIR}/docker-exec-called"
failure_status=0
PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_DOCKER_FIXTURE_MODE=build_fail \
  bash "${REPO_ROOT}/dev/verification/run.sh" \
  --changed-file README.md --scenario fresh_install_http \
  > "${TMP_DIR}/build-fail.stdout" 2> "${TMP_DIR}/build-fail.stderr" || failure_status=$?
[[ "${failure_status}" -eq 17 ]] || {
  printf 'expected Docker build status 17, got %s\n' "${failure_status}" >&2
  exit 1
}
[[ ! -e "${TMP_DIR}/docker-run-called" ]]
[[ ! -e "${TMP_DIR}/docker-exec-called" ]]

failure_status=0
PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_DOCKER_FIXTURE_MODE=run_fail \
  bash "${REPO_ROOT}/dev/verification/run.sh" \
  --changed-file README.md --scenario fresh_install_http \
  > "${TMP_DIR}/run-fail.stdout" 2> "${TMP_DIR}/run-fail.stderr" || failure_status=$?
[[ "${failure_status}" -eq 19 ]] || {
  printf 'expected Docker run status 19, got %s\n' "${failure_status}" >&2
  exit 1
}
[[ -e "${TMP_DIR}/docker-run-called" ]]
[[ ! -e "${TMP_DIR}/docker-exec-called" ]]
printf 'Docker verification and prerequisite failure checks PASSED\n'
