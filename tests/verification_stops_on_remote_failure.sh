#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

# Mock docker — image exists, container starts, exec fails
cat > "${TMP_DIR}/docker" <<DOCKER_EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "image" && "\${2:-}" == "inspect" ]]; then
  exit 0
fi
if [[ "\${1:-}" == "run" && "\${2:-}" == "-d" && "\${3:-}" == "--privileged" ]]; then
  printf 'test-container-fails\n'
  exit 0
fi
if [[ "\${1:-}" == "exec" && "\${2:-}" == "-i" ]]; then
  printf 'simulated remote failure\n' >&2
  exit 23
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
  printf 'expected docker exec failure to propagate\n' >&2
  exit 1
fi

grep -Fq 'simulated remote failure' "${TMP_DIR}/stderr.txt"
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
[[ -f "${run_dir}/remote.stderr.log" ]]
grep -Fq 'remote_target=docker:test-container-fails' "${run_dir}/summary.log"
printf 'Docker exec failure test PASSED\n'
