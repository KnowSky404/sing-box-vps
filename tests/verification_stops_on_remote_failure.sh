#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/ssh" <<'EOF'
#!/usr/bin/env bash
printf 'simulated remote failure\n' >&2
exit 23
EOF
chmod +x "${TMP_DIR}/ssh"

if PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected dispatcher to fail on remote error\n' >&2
  exit 1
fi

grep -Fq 'simulated remote failure' "${TMP_DIR}/stderr.txt"
run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
[[ -f "${run_dir}/remote.stderr.log" ]]
