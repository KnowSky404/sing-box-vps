#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/bash" <<EOF
#!${REAL_BASH}
if [[ "\${1:-}" == "${REPO_ROOT}/dev/verification/run.sh" ]]; then
  exec "${REAL_BASH}" "\$@"
fi
if [[ "\${1:-}" == tests/verification_*.sh ]]; then
  printf '%s|%s|%s\n' \
    "\$1" \
    "\${VERIFY_SKIP_LOCAL_TESTS:-unset}" \
    "\${VERIFY_SKIP_REMOTE:-unset}" >> "${TMP_DIR}/local-tests.log"
  exit 0
fi
exec "${REAL_BASH}" "\$@"
EOF
chmod +x "${TMP_DIR}/bash"

output=$(
  PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_REMOTE=1 \
    bash "${REPO_ROOT}/dev/verification/run.sh" \
    --changed-file tests/install_hy2_protocol_creates_state.sh
)

grep -Fq 'mode=local' <<<"${output}"
grep -Fqx 'tests/verification_trigger_rules.sh|1|unset' "${TMP_DIR}/local-tests.log"
grep -Fqx 'tests/verification_runtime_smoke_artifacts.sh|1|unset' "${TMP_DIR}/local-tests.log"
