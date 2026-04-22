#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

ARTIFACT_DIR="${TMP_DIR}/artifacts"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
PROTOCOLS_DIR="${TMP_DIR}/protocols"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
mkdir -p "${ARTIFACT_DIR}/meta" "${ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${PROTOCOLS_DIR}"

perl -0pe '
  s|/root/sing-box-vps/protocols/index.env|'"${INDEX_FILE}"'|g;
  s/if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then.*\z//s;
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TESTABLE_ENTRYPOINT}"

cat > "${TMP_DIR}/probe-harness.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

verification_artifact_path() {
  local relative_path=\$1
  local target_path="\${VERIFY_ARTIFACT_DIR}/\${relative_path}"
  mkdir -p "\$(dirname "\${target_path}")"
  printf '%s\n' "\${target_path}"
}

verification_write_artifact() {
  local relative_path=\$1
  shift || true
  printf '%s\n' "\$@" > "\$(verification_artifact_path "\${relative_path}")"
}

source "${TESTABLE_ENTRYPOINT}"

VERIFY_ARTIFACT_DIR="${ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

cat > "${INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2,mystery-protocol
INDEX_EOF

verification_run_protocol_probes
EOF
chmod +x "${TMP_DIR}/probe-harness.sh"

if bash "${TMP_DIR}/probe-harness.sh" > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected supported protocols to fail before real probe implementation\n' >&2
  exit 1
fi

grep -Fqx 'RESULT=failure' \
  "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=failure' \
  "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'RESULT=unsupported' \
  "${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"
