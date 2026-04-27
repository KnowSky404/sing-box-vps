#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
REAL_BASH=$(command -v bash)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/ssh" <<EOF
#!${REAL_BASH}
remote_host=\${1:-}
shift
printf '%s\n' "\${remote_host}" > "${TMP_DIR}/ssh-target.txt"
cat > "${TMP_DIR}/remote-script.sh"
printf 'REMOTE_HOST=%s\n' "\${remote_host}"
printf '%s\n' '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__'
tar -C "${TMP_DIR}" -czf - . | base64
printf '%s\n' '__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__'
EOF
chmod +x "${TMP_DIR}/ssh"

cat > "${TMP_DIR}/target.env" <<'EOF'
VERIFY_REMOTE_HOST_ALIAS=sing-box-test-0
EOF

PATH="${TMP_DIR}:${PATH}" VERIFY_REMOTE_TARGET_FILE="${TMP_DIR}/target.env" VERIFY_SKIP_LOCAL_TESTS=1 \
  bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > "${TMP_DIR}/stdout.txt"

run_dir=$(sed -n 's/^run_dir=//p' "${TMP_DIR}/stdout.txt")
grep -Fqx 'sing-box-test-0' "${TMP_DIR}/ssh-target.txt"
grep -Fq 'remote_target=sing-box-test-0' "${run_dir}/summary.log"
grep -Fq 'REMOTE_HOST=sing-box-test-0' "${run_dir}/remote.stdout.log"
