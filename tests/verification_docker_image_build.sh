#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

# Mock docker — image doesn't exist initially, gets built, then runs
cat > "${TMP_DIR}/docker" <<DOCKER_EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "image" && "\${2:-}" == "inspect" ]]; then
  if [[ -f "${TMP_DIR}/image-built" ]]; then
    exit 0
  fi
  exit 1
fi
if [[ "\${1:-}" == "build" ]]; then
  : > "${TMP_DIR}/image-built"
  printf '%s\\n' "\$@" > "${TMP_DIR}/build-arguments.txt"
  exit 0
fi
if [[ "\${1:-}" == "run" && "\${2:-}" == "-d" && "\${3:-}" == "--privileged" ]]; then
  printf 'test-container-built\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${3:-}" == "systemctl" && "\${4:-}" == "is-system-running" ]]; then
  printf 'degraded\n'
  exit 1
fi
if [[ "\${1:-}" == "exec" && "\${2:-}" == "-i" ]]; then
  cat > /dev/null
  printf 'SERVICE_ACTIVE=active\n'
  printf '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__\n'
  tar -C "${TMP_DIR}" -czf - . | base64
  printf '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__\n'
  exit 0
fi
if [[ "\${1:-}" == "rm" && "\${2:-}" == "-f" ]]; then
  exit 0
fi
printf 'unexpected docker call: %s\n' "\$*" >&2
exit 1
DOCKER_EOF
chmod +x "${TMP_DIR}/docker"

PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_DOCKER_IMAGE=fixture-build-image \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file README.md --scenario fresh_install_http > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"

[[ -f "${TMP_DIR}/image-built" ]]
printf '%s\n' build -t fixture-build-image -f \
  "${REPO_ROOT}/dev/verification/docker/Dockerfile" "${REPO_ROOT}" \
  > "${TMP_DIR}/expected-build-arguments.txt"
diff -u "${TMP_DIR}/expected-build-arguments.txt" "${TMP_DIR}/build-arguments.txt"
grep -Fq 'remote_target=docker:test-container-built' "${TMP_DIR}/stdout.txt"
printf 'Docker image build + run test PASSED\n'
