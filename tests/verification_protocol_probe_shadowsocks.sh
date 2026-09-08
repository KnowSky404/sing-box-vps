#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/verification_protocol_probe_test_helper.sh"

PROTOCOLS_DIR="${TMP_DIR}/protocols"
INDEX_FILE="${PROTOCOLS_DIR}/index.env"
STATE_FILE="${PROTOCOLS_DIR}/shadowsocks.env"
STORE_FILE="${PROTOCOLS_DIR}/instances/shadowsocks.json"
CONFIG_FILE="${TMP_DIR}/shadowsocks.json"
ENTRYPOINT_FILE="${TMP_DIR}/entrypoint.sh"
ARTIFACT_DIR="${TMP_DIR}/artifacts"
KEY="MDEyMzQ1Njc4OWFiY2RlZg=="
mkdir -p "$(dirname "${STORE_FILE}")"
setup_protocol_probe_command_stubs

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/shadowsocks.env|'"${STATE_FILE}"'|g' \
  | perl -0pe 's|/root/sing-box-vps/protocols/instances/shadowsocks.json|'"${STORE_FILE}"'|g' \
  > "${ENTRYPOINT_FILE}"

cat > "${STATE_FILE}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE
cat > "${STORE_FILE}" <<EOF_STORE
{
  "schema_version": 1,
  "protocol": "shadowsocks",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "Shadowsocks probe",
    "tag": "ss-in",
    "listen": {"address": "127.0.0.1", "port": 18083, "network": ["tcp", "udp"]},
    "authentication": {"method": "2022-blake3-aes-128-gcm", "password": "${KEY}", "users": []},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
EOF_STORE
cat > "${CONFIG_FILE}" <<'EOF_CONFIG'
{
  "inbounds": [{
    "type": "shadowsocks",
    "tag": "ss-in",
    "listen": "127.0.0.1",
    "listen_port": 18083,
    "network": ["tcp", "udp"],
    "method": "2022-blake3-aes-128-gcm",
    "password": "MDEyMzQ1Njc4OWFiY2RlZg==",
    "users": []
  }]
}
EOF_CONFIG

bash -s -- "${ENTRYPOINT_FILE}" "${ARTIFACT_DIR}" "${CONFIG_FILE}" <<'EOF_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO=runtime_smoke
VERIFY_CURRENT_SCENARIO_DIR=scenarios/runtime_smoke
verification_execute_single_protocol_probe shadowsocks "$3"
EOF_RUN

PROBE_DIR="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/shadowsocks"
jq -e '
  .outbounds[0].type == "shadowsocks" and
  .outbounds[0].server == "127.0.0.1" and
  .outbounds[0].server_port == 18083 and
  .outbounds[0].method == "2022-blake3-aes-128-gcm" and
  .outbounds[0].password == "MDEyMzQ1Njc4OWFiY2RlZg==" and
  .outbounds[0].network == ["tcp","udp"] and
  (.outbounds[0].type != "socks")
' "${PROBE_DIR}/client.json" >/dev/null
grep -Fqx 'RESULT=success' "${PROBE_DIR}/result.env"
grep -Fq 'sing-box check -c ' "${PROBE_CALL_LOG}"
grep -Fq 'sing-box run -c ' "${PROBE_CALL_LOG}"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"

printf 'Shadowsocks protocol probe checks passed: type=shadowsocks, network=tcp+udp, method=2022-aes128\n'
