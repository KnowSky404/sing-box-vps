#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/bash" <<EOF_BASH
#!${REAL_BASH}
if [[ "\${1:-}" == "${REPO_ROOT}/dev/verification/run.sh" ]]; then
  exec "${REAL_BASH}" "\$@"
fi
if [[ "\${1:-}" == tests/*.sh ]]; then
  printf '%s|%s|%s\\n' \
    "\$1" \
    "\${VERIFY_SKIP_LOCAL_TESTS:-unset}" \
    "\${VERIFY_SKIP_REMOTE:-unset}" >> "${TMP_DIR}/local-tests.log"
  exit 0
fi
exec "${REAL_BASH}" "\$@"
EOF_BASH
cat > "${TMP_DIR}/docker" <<EOF_DOCKER
#!${REAL_BASH}
printf 'unexpected Docker invocation\\n' >&2
exit 99
EOF_DOCKER
chmod +x "${TMP_DIR}/bash" "${TMP_DIR}/docker"

output=$(
  env -u VERIFY_SKIP_LOCAL_TESTS PATH="${TMP_DIR}:${PATH}" VERIFY_SKIP_REMOTE=1 \
    bash "${REPO_ROOT}/dev/verification/run.sh" \
    --changed-file tests/install_hy2_protocol_creates_state.sh
)

grep -Fq 'mode=local' <<<"${output}"
grep -Fqx 'tests/install_hy2_protocol_creates_state.sh|1|unset' "${TMP_DIR}/local-tests.log"
[[ $(wc -l < "${TMP_DIR}/local-tests.log") -eq 1 ]] || {
  printf 'expected only the changed standalone test to execute once\n' >&2
  exit 1
}
printf 'Changed standalone test executes locally without unrelated tests\n'
