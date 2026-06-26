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
  exit 0
fi
if [[ "\${1:-}" == "run" && "\${2:-}" == "-d" && "\${3:-}" == "--privileged" ]]; then
  printf 'test-container-id-12345\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${2:-}" == "-i" ]]; then
  # Read stdin (the payload) and run it
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

if PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  :
else
  status=$?
  printf 'expected docker verification to succeed, got exit %d\n' "${status}" >&2
  cat "${TMP_DIR}/stderr.txt" >&2
  exit 1
fi

grep -Fq 'remote_target=docker:test-container-id-12345' "${TMP_DIR}/stdout.txt"
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'remote_artifacts=extracted' "${run_dir}/summary.log"
printf 'Docker verification test PASSED\n'
