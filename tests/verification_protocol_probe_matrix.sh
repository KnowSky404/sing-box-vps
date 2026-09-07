#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/verification_protocol_probe_test_helper.sh"

if grep -Fq 'python3-minimal' "${REPO_ROOT}/dev/verification/docker/Dockerfile" || \
  ! grep -Eq '(^|[[:space:]])python3([[:space:]]|\\|$)' "${REPO_ROOT}/dev/verification/docker/Dockerfile"; then
  printf 'verification image must install full python3 for the http.server probe\n' >&2
  exit 1
fi

RED_ARTIFACT_DIR="${TMP_DIR}/artifacts-red"
DISCOVERY_FAILURE_ARTIFACT_DIR="${TMP_DIR}/artifacts-discovery-failure"
GREEN_ARTIFACT_DIR="${TMP_DIR}/artifacts-green"
TESTABLE_ENTRYPOINT="${TMP_DIR}/entrypoint-testable.sh"
LISTENER_HARNESS="${TMP_DIR}/listener-harness.sh"
PROTOCOLS_DIR="${TMP_DIR}/protocols"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
MIXED_STATE_FILE="${PROTOCOLS_DIR}/mixed.env"
FAILURE_CALLS_FILE="${TMP_DIR}/calls-failure.log"
GREEN_CALLS_FILE="${TMP_DIR}/calls-green.log"
mkdir -p "${RED_ARTIFACT_DIR}/meta" "${RED_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${DISCOVERY_FAILURE_ARTIFACT_DIR}/meta" "${DISCOVERY_FAILURE_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${GREEN_ARTIFACT_DIR}/meta" "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke"
mkdir -p "${PROTOCOLS_DIR}"
setup_protocol_probe_command_stubs

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/index.env|'"${INDEX_FILE}"'|g' \
  | perl -0pe 's|/root/sing-box-vps/protocols/mixed.env|'"${MIXED_STATE_FILE}"'|g' \
  > "${TESTABLE_ENTRYPOINT}"

cat > "${LISTENER_HARNESS}" <<EOF_LISTENER
#!/usr/bin/env bash
set -euo pipefail

verification_artifact_path() {
  local relative_path=\$1
  local target_path="\${VERIFY_ARTIFACT_DIR}/\${relative_path}"
  mkdir -p "\$(dirname "\${target_path}")"
  printf '%s\\n' "\${target_path}"
}

verification_write_artifact() {
  local relative_path=\$1
  shift || true
  printf '%s\\n' "\$@" > "\$(verification_artifact_path "\${relative_path}")"
}

source "${TESTABLE_ENTRYPOINT}"
VERIFY_ARTIFACT_DIR="${TMP_DIR}/listener-artifacts"
export PROBE_UDP_PORT=8443
verification_assert_udp_port_listening 8443 scenarios/runtime_smoke/listeners.hy2.ss-lunp.txt
verification_ss_output() {
  printf 'LISTEN 0 0 127.0.0.1:18443 0.0.0.0:*\n'
}
verification_ss_udp_output() {
  printf 'UNCONN 0 0 127.0.0.1:18443 0.0.0.0:*\n'
}
if verification_port_is_listening 8443 || verification_udp_port_is_listening 8443; then
  printf 'listener matching accepted a port suffix false positive\n' >&2
  exit 1
fi
EOF_LISTENER
chmod +x "${LISTENER_HARNESS}"
rm -rf "${TMP_DIR}/listener-artifacts"
bash "${LISTENER_HARNESS}"
grep -Fq 'UNCONN 0 0 127.0.0.1:8443' \
  "${TMP_DIR}/listener-artifacts/scenarios/runtime_smoke/listeners.hy2.ss-lunp.txt"

write_probe_harness() {
  local harness_path=$1
  local entrypoint_path=$2
  local artifact_dir=$3
  local calls_file=$4
  local setup_snippet=${5:-}
  local index_contents=${6:-$'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,mystery-protocol'}
  local index_contents_shell
  printf -v index_contents_shell '%q' "${index_contents}"

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

printf '%s\n' ${index_contents_shell} > "${INDEX_FILE}"

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
grep -Fqx 'mixed|/root/sing-box-vps/config.json' "${FAILURE_CALLS_FILE}"
grep -Fqx 'hy2|/root/sing-box-vps/config.json' "${FAILURE_CALLS_FILE}"
grep -Fqx 'anytls|/root/sing-box-vps/config.json' "${FAILURE_CALLS_FILE}"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=failure' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mixed/result.env"
grep -Fqx 'RESULT=failure' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'RESULT=failure' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/result.env"
grep -Fqx 'RESULT=unsupported' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"

ALIAS_ARTIFACT_DIR="${TMP_DIR}/artifacts-alias"
ALIAS_CALLS_FILE="${TMP_DIR}/calls-alias.log"
write_probe_harness \
  "${TMP_DIR}/probe-harness-alias.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${ALIAS_ARTIFACT_DIR}" \
  "${ALIAS_CALLS_FILE}" \
  $'verification_execute_single_protocol_probe() {\n  printf \'%s\\n\' "$1" >> "${PROBE_CALLS_FILE}"\n}' \
  $'INSTALLED_PROTOCOLS=vless,vless+reality,hysteria2,hy2,mixed,mixed'

bash "${TMP_DIR}/probe-harness-alias.sh"
printf '%s\n' vless-reality hy2 mixed > "${TMP_DIR}/calls-alias.expected"
cmp "${TMP_DIR}/calls-alias.expected" "${ALIAS_CALLS_FILE}"

INVALID_ARTIFACT_DIR="${TMP_DIR}/artifacts-invalid-id"
INVALID_CALLS_FILE="${TMP_DIR}/calls-invalid-id.log"
write_probe_harness \
  "${TMP_DIR}/probe-harness-invalid-id.sh" \
  "${TESTABLE_ENTRYPOINT}" \
  "${INVALID_ARTIFACT_DIR}" \
  "${INVALID_CALLS_FILE}" \
  $'verification_execute_single_protocol_probe() {\n  printf \'%s\\n\' "$1" >> "${PROBE_CALLS_FILE}"\n}' \
  $'INSTALLED_PROTOCOLS=mixed,../../escape'

if bash "${TMP_DIR}/probe-harness-invalid-id.sh" \
  > "${TMP_DIR}/stdout-invalid-id.txt" \
  2> "${TMP_DIR}/stderr-invalid-id.txt"; then
  printf 'expected invalid protocol ID to fail closed\n' >&2
  exit 1
fi
grep -Fq 'invalid protocol id in verification index' "${TMP_DIR}/stderr-invalid-id.txt"
[[ ! -s "${INVALID_CALLS_FILE}" ]]
[[ ! -e "${TMP_DIR}/escape" ]]

ACTUAL_ARTIFACT_DIR="${TMP_DIR}/artifacts-actual"
ACTUAL_CONFIG_FILE="${TMP_DIR}/actual-client.json"
cat > "${ACTUAL_CONFIG_FILE}" <<'EOF_CONFIG'
{}
EOF_CONFIG

cat > "${TMP_DIR}/run-actual-probe.sh" <<EOF_RUN
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"
VERIFY_ARTIFACT_DIR="${ACTUAL_ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_generate_protocol_probe_client_config() {
  local output_path
  output_path=\$(verification_artifact_path "\${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/vless-reality/client.json")
  printf '%s\\n' '{}' > "\${output_path}"
  printf '%s\\n' "\${output_path}"
}

verification_execute_single_protocol_probe vless-reality "${ACTUAL_CONFIG_FILE}"
EOF_RUN
chmod +x "${TMP_DIR}/run-actual-probe.sh"

rm -rf "${ACTUAL_ARTIFACT_DIR}"
bash "${TMP_DIR}/run-actual-probe.sh"
ACTUAL_PROBE_DIR="${ACTUAL_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality"
grep -Fqx 'client-check-ok' "${ACTUAL_PROBE_DIR}/client.check.txt"
[[ -f "${ACTUAL_PROBE_DIR}/client.stdout.txt" ]]
[[ -f "${ACTUAL_PROBE_DIR}/client.stderr.txt" ]]
grep -Fq 'sing-box check -c ' "${PROBE_CALL_LOG}"
grep -Fq 'sing-box run -c ' "${PROBE_CALL_LOG}"
grep -Fq 'curl --fail --silent --show-error --noproxy ' "${PROBE_CALL_LOG}"
grep -Fq 'python3 - ' "${PROBE_CALL_LOG}"
grep -Fq 'sing-box-vps-loopback-ok-vless-reality-' "${ACTUAL_PROBE_DIR}/http-response.txt"
cmp "${ACTUAL_PROBE_DIR}/http-response.txt" "${ACTUAL_PROBE_DIR}/probe.stdout.txt"
grep -Fqx 'RESULT=success' "${ACTUAL_PROBE_DIR}/result.env"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

MIXED_ARTIFACT_DIR="${TMP_DIR}/artifacts-mixed"
MIXED_CONFIG_FILE="${TMP_DIR}/mixed-server.json"
cat > "${MIXED_CONFIG_FILE}" <<'EOF_MIXED_CONFIG'
{
  "inbounds": [
    {
      "type": "mixed",
      "listen_port": 18080,
      "users": [
        {
          "username": "mixed-user",
          "password": "mixed-pass"
        }
      ]
    }
  ]
}
EOF_MIXED_CONFIG
cat > "${MIXED_STATE_FILE}" <<'EOF_MIXED_STATE'
AUTH_ENABLED=y
USERNAME=mixed-user
PASSWORD=mixed-pass
EOF_MIXED_STATE

cat > "${TMP_DIR}/run-mixed-probe.sh" <<EOF_MIXED_RUN
#!/usr/bin/env bash
set -euo pipefail

source "${TESTABLE_ENTRYPOINT}"
VERIFY_ARTIFACT_DIR="${MIXED_ARTIFACT_DIR}"
VERIFY_CURRENT_SCENARIO="runtime_smoke"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/\${VERIFY_CURRENT_SCENARIO}"

verification_execute_single_protocol_probe mixed "${MIXED_CONFIG_FILE}"
EOF_MIXED_RUN
chmod +x "${TMP_DIR}/run-mixed-probe.sh"

rm -rf "${MIXED_ARTIFACT_DIR}"
bash "${TMP_DIR}/run-mixed-probe.sh"
MIXED_PROBE_DIR="${MIXED_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mixed"
jq -e '
  .outbounds[0].type == "socks" and
  .outbounds[0].version == "5" and
  .outbounds[0].server == "127.0.0.1" and
  .outbounds[0].server_port == 18080 and
  .outbounds[0].username == "mixed-user" and
  .outbounds[0].password == "mixed-pass"
' "${MIXED_PROBE_DIR}/client.json" >/dev/null
grep -Fqx 'client-check-ok' "${MIXED_PROBE_DIR}/client.check.txt"
[[ -f "${MIXED_PROBE_DIR}/client.stdout.txt" ]]
[[ -f "${MIXED_PROBE_DIR}/client.stderr.txt" ]]
grep -Fq 'sing-box run -c ' "${PROBE_CALL_LOG}"
grep -Fq 'curl --fail --silent --show-error --noproxy ' "${PROBE_CALL_LOG}"
grep -Fq 'sing-box-vps-loopback-ok-mixed-' "${MIXED_PROBE_DIR}/http-response.txt"
cmp "${MIXED_PROBE_DIR}/http-response.txt" "${MIXED_PROBE_DIR}/probe.stdout.txt"
grep -Fqx 'RESULT=success' "${MIXED_PROBE_DIR}/result.env"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

SOCKS_ARTIFACT_DIR="${TMP_DIR}/artifacts-socks"
SOCKS_CONFIG_FILE="${TMP_DIR}/socks-server.json"
jq '.inbounds[0].type="socks" |
  .inbounds[0].users=[{username:"socks-user\n",password:"special:$`\\\"\n"}]' \
  "${MIXED_CONFIG_FILE}" > "${SOCKS_CONFIG_FILE}"
bash -s -- "${TESTABLE_ENTRYPOINT}" "${SOCKS_ARTIFACT_DIR}" "${SOCKS_CONFIG_FILE}" <<'EOF_SOCKS_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO=runtime_smoke
VERIFY_CURRENT_SCENARIO_DIR=scenarios/runtime_smoke
verification_execute_single_protocol_probe socks "$3"
EOF_SOCKS_RUN
SOCKS_PROBE_DIR="${SOCKS_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/socks"
jq -e --slurpfile server "${SOCKS_CONFIG_FILE}" '
  .outbounds[0].type=="socks" and .outbounds[0].version=="5" and
  .outbounds[0].udp_over_tcp=={enabled:true,version:2} and
  .outbounds[0].username==$server[0].inbounds[0].users[0].username and
  .outbounds[0].password==$server[0].inbounds[0].users[0].password
' "${SOCKS_PROBE_DIR}/client.json" >/dev/null
[[ "$(stat -c %a "${SOCKS_PROBE_DIR}/client.json")" == 600 ]]
grep -Fqx 'RESULT=success' "${SOCKS_PROBE_DIR}/result.env"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

: > "${PROBE_CLIENT_PID_FILE}"
: > "${PROBE_HTTP_PID_FILE}"
if PROBE_FAIL_CHECK=1 bash "${TMP_DIR}/run-actual-probe.sh"; then
  printf 'expected client check failure to fail the probe\n' >&2
  exit 1
fi
grep -Fqx 'RESULT=failure' "${ACTUAL_PROBE_DIR}/result.env"
grep -Fq 'client-check-failed' "${ACTUAL_PROBE_DIR}/client.check.txt"
[[ ! -s "${PROBE_CLIENT_PID_FILE}" ]]
[[ ! -s "${PROBE_HTTP_PID_FILE}" ]]

: > "${PROBE_CLIENT_PID_FILE}"
: > "${PROBE_HTTP_PID_FILE}"
if PROBE_FAIL_RUN=1 bash "${TMP_DIR}/run-actual-probe.sh"; then
  printf 'expected client run failure to fail the probe\n' >&2
  exit 1
fi
grep -Fqx 'RESULT=failure' "${ACTUAL_PROBE_DIR}/result.env"
[[ ! -s "${PROBE_CLIENT_PID_FILE}" ]]
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

: > "${PROBE_CLIENT_PID_FILE}"
: > "${PROBE_HTTP_PID_FILE}"
if PROBE_CURL_RESPONSE=wrong-marker bash "${TMP_DIR}/run-actual-probe.sh"; then
  printf 'expected mismatched HTTP marker to fail the probe\n' >&2
  exit 1
fi
grep -Fqx 'RESULT=failure' "${ACTUAL_PROBE_DIR}/result.env"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

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
grep -Fqx 'mixed|/root/sing-box-vps/config.json' "${GREEN_CALLS_FILE}"
grep -Fqx 'hy2|/root/sing-box-vps/config.json' "${GREEN_CALLS_FILE}"
grep -Fqx 'anytls|/root/sing-box-vps/config.json' "${GREEN_CALLS_FILE}"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-reality/result.env"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/hy2/result.env"
grep -Fqx 'RESULT=success' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/anytls/result.env"
grep -Fqx 'RESULT=unsupported' \
  "${GREEN_ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/mystery-protocol/result.env"
