#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/ssh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"runtime_smoke"* ]]; then
  scenario_line='SCENARIO=runtime_smoke'
else
  scenario_line='SCENARIO=missing'
fi
cat <<'OUT'
REMOTE_HOST=test-vps
OUT
printf '%s\n' "${scenario_line}"
exit 0
EOF
chmod +x "${TMP_DIR}/ssh"

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_HOST=test.example VERIFY_REMOTE_USER=root VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fq 'runtime_smoke' "${run_dir}/scenarios.txt"
grep -Fq 'REMOTE_HOST=test-vps' "${run_dir}/remote.stdout.log"
grep -Fq 'SCENARIO=runtime_smoke' "${run_dir}/remote.stdout.log"
