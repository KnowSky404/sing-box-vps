#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

RED_ARTIFACT_DIR="${TMP_DIR}/artifacts-red"
GREEN_ARTIFACT_DIR="${TMP_DIR}/artifacts-green"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
RED_PHASE_ENTRYPOINT="${TMP_DIR}/entrypoint-red-phase.sh"
PROTOCOLS_DIR="${TMP_DIR}/protocols"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
mkdir -p "${RED_ARTIFACT_DIR}/meta" "${RED_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${GREEN_ARTIFACT_DIR}/meta" "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${PROTOCOLS_DIR}"

perl -0pe '
  s|/root/sing-box-vps/protocols/index.env|'"${INDEX_FILE}"'|g;
  s/if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then.*\z//s;
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TESTABLE_ENTRYPOINT}"

perl -0pe '
  s|/root/sing-box-vps/protocols/index.env|'"${INDEX_FILE}"'|g;
  s/read_installed_protocols\(\) \{\n.*?\n\}\n\n//s;
  s/verification_protocol_probe_support_status\(\) \{\n.*?\n\}\n\n//s;
  s/verification_record_protocol_probe_result\(\) \{\n.*?\n\}\n\n//s;
  s/verification_run_protocol_probes\(\) \{\n.*?\n\}\n\n//s;
  s/if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then.*\z//s;
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${RED_PHASE_ENTRYPOINT}"

write_probe_harness() {
  local harness_path=$1
  local entrypoint_path=$2
  local artifact_dir=$3

  cat > "${harness_path}" <<EOF
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

source "${entrypoint_path}"

VERIFY_ARTIFACT_DIR="${artifact_dir}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

cat > "${INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2,mystery-protocol
INDEX_EOF

verification_run_protocol_probes
EOF
  chmod +x "${harness_path}"
}

write_probe_harness \
  "${TMP_DIR}/probe-harness-red.sh" \
  "${RED_PHASE_ENTRYPOINT}" \
  "${RED_ARTIFACT_DIR}"

if bash "${TMP_DIR}/probe-harness-red.sh" > "${TMP_DIR}/stdout-red.txt" 2> "${TMP_DIR}/stderr-red.txt"; then
  printf 'expected probe harness red phase to fail when helpers are missing\n' >&2
  exit 1
fi

grep -Eq 'verification_run_protocol_probes: command not found|No such file' "${TMP_DIR}/stderr-red.txt"

write_probe_harness \
  "${TMP_DIR}/probe-harness-green.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${GREEN_ARTIFACT_DIR}"

if bash "${TMP_DIR}/probe-harness-green.sh" > "${TMP_DIR}/stdout-green.txt" 2> "${TMP_DIR}/stderr-green.txt"; then
  printf 'expected supported protocols to fail before real probe implementation\n' >&2
  exit 1
fi

grep -Fqx 'RESULT=failure' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=failure' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'RESULT=unsupported' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"
