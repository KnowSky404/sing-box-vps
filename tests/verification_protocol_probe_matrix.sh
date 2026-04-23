#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

RED_ARTIFACT_DIR="${TMP_DIR}/artifacts-red"
DISCOVERY_FAILURE_ARTIFACT_DIR="${TMP_DIR}/artifacts-discovery-failure"
GREEN_ARTIFACT_DIR="${TMP_DIR}/artifacts-green"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
PROTOCOLS_DIR="${TMP_DIR}/protocols"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
FAILURE_CALLS_FILE="${TMP_DIR}/calls-failure.log"
GREEN_CALLS_FILE="${TMP_DIR}/calls-green.log"
mkdir -p "${RED_ARTIFACT_DIR}/meta" "${RED_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${DISCOVERY_FAILURE_ARTIFACT_DIR}/meta" "${DISCOVERY_FAILURE_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${GREEN_ARTIFACT_DIR}/meta" "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${PROTOCOLS_DIR}"

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/index.env|'"${INDEX_FILE}"'|g' \
  > "${TESTABLE_ENTRYPOINT}"

write_probe_harness() {
  local harness_path=$1
  local entrypoint_path=$2
  local artifact_dir=$3
  local calls_file=$4
  local setup_snippet=${5:-}

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
PROBE_CALLS_FILE="${calls_file}"

${setup_snippet}

cat > "${INDEX_FILE}" <<'INDEX_EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2,mystery-protocol
INDEX_EOF

verification_run_protocol_probes
EOF
  chmod +x "${harness_path}"
}

write_probe_harness \
  "${TMP_DIR}/probe-harness-red.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${RED_ARTIFACT_DIR}" \
  "${TMP_DIR}/unused-red.log" \
  'unset -f verification_run_protocol_probes'

if bash "${TMP_DIR}/probe-harness-red.sh" > "${TMP_DIR}/stdout-red.txt" 2> "${TMP_DIR}/stderr-red.txt"; then
  printf 'expected probe harness red phase to fail when helpers are missing\n' >&2
  exit 1
fi

grep -Fq 'verification_run_protocol_probes: command not found' "${TMP_DIR}/stderr-red.txt"

write_probe_harness \
  "${TMP_DIR}/probe-harness-discovery-failure.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${DISCOVERY_FAILURE_ARTIFACT_DIR}" \
  "${TMP_DIR}/unused-discovery.log" \
  $'read_installed_protocols() {\n  return 23\n}'

discovery_failure_status=0
if bash "${TMP_DIR}/probe-harness-discovery-failure.sh" \
  > "${TMP_DIR}/stdout-discovery-failure.txt" \
  2> "${TMP_DIR}/stderr-discovery-failure.txt"; then
  printf 'expected protocol discovery failure to return non-zero\n' >&2
  exit 1
else
  discovery_failure_status=$?
fi

[[ "${discovery_failure_status}" == "23" ]]

write_probe_harness \
  "${TMP_DIR}/probe-harness-supported-failure.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${GREEN_ARTIFACT_DIR}" \
  "${FAILURE_CALLS_FILE}" \
  $'verification_execute_single_protocol_probe() {\n  local protocol=$1\n  local config_file=$2\n\n  printf \'%s|%s\\n\' "${protocol}" "${config_file}" >> "${PROBE_CALLS_FILE}"\n\n  if [[ "${protocol}" == "vless-reality" ]]; then\n    verification_record_protocol_probe_result "${protocol}" success\n    return 0\n  fi\n\n  return 17\n}'

if bash "${TMP_DIR}/probe-harness-supported-failure.sh" \
  > "${TMP_DIR}/stdout-supported-failure.txt" \
  2> "${TMP_DIR}/stderr-supported-failure.txt"; then
  printf 'expected supported protocol failure phase to return non-zero\n' >&2
  exit 1
fi

grep -Fqx 'vless-reality|/root/sing-box-vps/config.json' "${FAILURE_CALLS_FILE}"
grep -Fqx 'hy2|/root/sing-box-vps/config.json' "${FAILURE_CALLS_FILE}"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=failure' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'RESULT=unsupported' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"

rm -rf "${GREEN_ARTIFACT_DIR}"
mkdir -p "${GREEN_ARTIFACT_DIR}/meta" "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke"

write_probe_harness \
  "${TMP_DIR}/probe-harness-green.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${GREEN_ARTIFACT_DIR}" \
  "${GREEN_CALLS_FILE}" \
  $'verification_execute_single_protocol_probe() {\n  local protocol=$1\n  local config_file=$2\n\n  printf \'%s|%s\\n\' "${protocol}" "${config_file}" >> "${PROBE_CALLS_FILE}"\n  verification_record_protocol_probe_result "${protocol}" success\n  return 0\n}'

bash "${TMP_DIR}/probe-harness-green.sh" \
  > "${TMP_DIR}/stdout-green.txt" \
  2> "${TMP_DIR}/stderr-green.txt"

grep -Fqx 'vless-reality|/root/sing-box-vps/config.json' "${GREEN_CALLS_FILE}"
grep -Fqx 'hy2|/root/sing-box-vps/config.json' "${GREEN_CALLS_FILE}"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'RESULT=unsupported' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"
