#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/verification_protocol_probe_test_helper.sh"

PROTOCOLS_DIR="${TMP_DIR}/protocols"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
HTTP_STATE_FILE="${PROTOCOLS_DIR}/http.env"
HTTP_STORE_FILE="${PROTOCOLS_DIR}/instances/http.json"
CONFIG_FILE="${TMP_DIR}/http.json"
ENTRYPOINT_FILE="${TMP_DIR}/entrypoint.sh"
ARTIFACT_DIR="${TMP_DIR}/artifacts"
mkdir -p "$(dirname "${HTTP_STORE_FILE}")"
setup_protocol_probe_command_stubs

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/http.env|'"${HTTP_STATE_FILE}"'|g' \
  | perl -0pe 's|/root/sing-box-vps/protocols/instances/http.json|'"${HTTP_STORE_FILE}"'|g' \
  > "${ENTRYPOINT_FILE}"

cat > "${HTTP_STATE_FILE}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE
cat > "${HTTP_STORE_FILE}" <<'EOF_STORE'
{
  "schema_version": 1,
  "protocol": "http",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "HTTP probe",
    "tag": "http-in",
    "listen": {"address": "127.0.0.1", "port": 18082},
    "authentication": {"enabled": true, "username": "http-user", "password": "http-pass"},
    "outbound_policy": "default",
    "tls": {"enabled": false},
    "dependencies": []
  }]
}
EOF_STORE
cat > "${CONFIG_FILE}" <<'EOF_CONFIG'
{
  "inbounds": [{
    "type": "http",
    "tag": "http-in",
    "listen": "127.0.0.1",
    "listen_port": 18082,
    "users": [{"username": "http-user", "password": "http-pass"}],
    "tls": {"enabled": false}
  }]
}
EOF_CONFIG

bash -s -- "${ENTRYPOINT_FILE}" "${ARTIFACT_DIR}" "${CONFIG_FILE}" <<'EOF_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO=runtime_smoke
VERIFY_CURRENT_SCENARIO_DIR=scenarios/runtime_smoke
verification_execute_single_protocol_probe http "$3"
EOF_RUN

PROBE_DIR="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/http"
jq -e '
  .outbounds[0].type == "http" and
  .outbounds[0].server == "127.0.0.1" and
  .outbounds[0].server_port == 18082 and
  .outbounds[0].username == "http-user" and
  .outbounds[0].password == "http-pass" and
  (.outbounds[0] | has("tls") | not)
' "${PROBE_DIR}/client.json" >/dev/null
grep -Fqx 'RESULT=success' "${PROBE_DIR}/result.env"
grep -Fq 'sing-box check -c ' "${PROBE_CALL_LOG}"
grep -Fq 'sing-box run -c ' "${PROBE_CALL_LOG}"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

# TLS state is read for SNI, but server certificate/key paths never enter the
# generated client configuration.
jq '.instances[0].tls={enabled:true,server_name:"http.example.com",certificate_path:"/private/cert.pem",key_path:"/private/key.pem"}' \
  "${HTTP_STORE_FILE}" > "${TMP_DIR}/tls-store.json"
cp "${TMP_DIR}/tls-store.json" "${HTTP_STORE_FILE}"
jq '.inbounds[0].tls={enabled:true,server_name:"http.example.com",certificate_path:"/private/cert.pem",key_path:"/private/key.pem"}' \
  "${CONFIG_FILE}" > "${TMP_DIR}/tls-config.json"
rm -rf "${ARTIFACT_DIR}"
bash -s -- "${ENTRYPOINT_FILE}" "${ARTIFACT_DIR}" "${TMP_DIR}/tls-config.json" <<'EOF_TLS_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO=runtime_smoke
VERIFY_CURRENT_SCENARIO_DIR=scenarios/runtime_smoke
verification_execute_single_protocol_probe http "$3"
EOF_TLS_RUN
TLS_PROBE_DIR="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/http"
jq -e '
  .outbounds[0].tls == {enabled:true,server_name:"http.example.com",insecure:true} and
  (.outbounds[0] | has("certificate_path") | not) and
  (.outbounds[0] | has("key_path") | not)
' "${TLS_PROBE_DIR}/client.json" >/dev/null
grep -Fqx 'RESULT=success' "${TLS_PROBE_DIR}/result.env"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"
