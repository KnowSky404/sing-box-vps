#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/verification_protocol_probe_test_helper.sh"

PROTOCOLS_DIR="${TMP_DIR}/protocols"
STATE_FILE="${PROTOCOLS_DIR}/vless-plain.env"
STORE_FILE="${PROTOCOLS_DIR}/instances/vless-plain.json"
CONFIG_FILE="${TMP_DIR}/vless.json"
ENTRYPOINT_FILE="${TMP_DIR}/entrypoint.sh"
ARTIFACT_DIR="${TMP_DIR}/artifacts"
mkdir -p "$(dirname "${STORE_FILE}")"
setup_protocol_probe_command_stubs

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {
    exit
  }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
  | perl -0pe 's|/root/sing-box-vps/protocols/vless-plain.env|'"${STATE_FILE}"'|g' \
  | perl -0pe 's|/root/sing-box-vps/protocols/instances/vless-plain.json|'"${STORE_FILE}"'|g' \
  > "${ENTRYPOINT_FILE}"

cat > "${STATE_FILE}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=vless-probe.test' \
  -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.crt" \
  >/dev/null 2>"${TMP_DIR}/openssl.log"
cat > "${STORE_FILE}" <<EOF_STORE
{
  "schema_version": 1,
  "protocol": "vless-plain",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "VLESS probe",
    "tag": "vless-plain-in",
    "listen": {"address": "127.0.0.1", "port": 18089},
    "authentication": {"users": [{"name": "probe", "uuid": "11111111-1111-4111-8111-111111111111", "flow": "xtls-rprx-vision"}]},
    "tls": {"enabled": true, "server_name": "vless-probe.test", "certificate_path": "${TMP_DIR}/server.crt", "key_path": "${TMP_DIR}/server.key"},
    "client_trust": "certificate",
    "transport": {"type": "ws", "path": "/vless", "headers": {"Host": "vless-probe.test"}},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
EOF_STORE
cat > "${CONFIG_FILE}" <<'EOF_CONFIG'
{
  "inbounds": [
    {"type": "vless", "tag": "vless-reality-in", "listen_port": 18443,
     "tls": {"enabled": true, "reality": {"enabled": true}}, "users": []},
    {"type": "vless", "tag": "vless-plain-in", "listen": "127.0.0.1", "listen_port": 18089,
     "tls": {"enabled": true, "server_name": "vless-probe.test"}, "users": []}
  ]
}
EOF_CONFIG

bash -s -- "${ENTRYPOINT_FILE}" "${ARTIFACT_DIR}" "${CONFIG_FILE}" <<'EOF_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO=runtime_smoke
VERIFY_CURRENT_SCENARIO_DIR=scenarios/runtime_smoke
verification_execute_single_protocol_probe vless-plain "$3"
EOF_RUN

PROBE_DIR="${ARTIFACT_DIR}/scenarios/runtime_smoke/protocol-probes/vless-plain"
jq -e '
  .outbounds[0] as $out |
  $out.type == "vless" and $out.tag == "proxy" and
  $out.server == "127.0.0.1" and $out.server_port == 18089 and
  $out.uuid == "11111111-1111-4111-8111-111111111111" and
  $out.flow == "xtls-rprx-vision" and $out.network == ["tcp", "udp"] and
  $out.transport == {type:"ws",path:"/vless",headers:{Host:"vless-probe.test"}} and
  $out.tls == {enabled:true,server_name:"vless-probe.test",insecure:true} and
  (.outbounds | length) == 1
' "${PROBE_DIR}/client.json" >/dev/null
grep -Fqx 'RESULT=success' "${PROBE_DIR}/result.env"
grep -Fq 'sing-box check -c ' "${PROBE_CALL_LOG}"
grep -Fq 'sing-box run -c ' "${PROBE_CALL_LOG}"
assert_protocol_probe_processes_cleaned "${PROBE_CLIENT_PID_FILE}"
assert_protocol_probe_processes_cleaned "${PROBE_HTTP_PID_FILE}"
! grep -Fq 'PRIVATE KEY' "${PROBE_DIR}/client.json"
! grep -Fq 'server.key' "${PROBE_DIR}/client.json"

# The same managed record can select QUIC.  Generate its client profile after
# the ordinary WebSocket probe and assert that QUIC keeps the proxy network
# broad while adding the h3 ALPN required by the transport.
cat > "${STORE_FILE}" <<EOF_STORE_QUIC
{
  "schema_version": 1,
  "protocol": "vless-plain",
  "revision": 2,
  "default_instance_id": "main",
  "instances": [{
    "id": "main",
    "name": "VLESS QUIC probe",
    "tag": "vless-plain-in",
    "listen": {"address": "127.0.0.1", "port": 18089},
    "authentication": {"users": [{"name": "probe", "uuid": "11111111-1111-4111-8111-111111111111", "flow": ""}]},
    "tls": {"enabled": true, "server_name": "vless-probe.test", "certificate_path": "${TMP_DIR}/server.crt", "key_path": "${TMP_DIR}/server.key"},
    "client_trust": "certificate",
    "transport": {"type": "quic"},
    "outbound_policy": "default",
    "dependencies": []
  }]
}
EOF_STORE_QUIC
cat > "${CONFIG_FILE}" <<'EOF_CONFIG_QUIC'
{
  "inbounds": [
    {"type": "vless", "tag": "vless-reality-in", "listen_port": 18443,
     "tls": {"enabled": true, "reality": {"enabled": true}}, "users": []},
    {"type": "vless", "tag": "vless-plain-in", "listen": "127.0.0.1", "listen_port": 18089,
     "tls": {"enabled": true, "server_name": "vless-probe.test", "alpn": ["h3"]},
     "transport": {"type": "quic"}, "users": []}
  ]
}
EOF_CONFIG_QUIC
bash -s -- "${ENTRYPOINT_FILE}" "${ARTIFACT_DIR}" "${CONFIG_FILE}" \
  "${TMP_DIR}/vless-quic-client.json" <<'EOF_QUIC_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO=runtime_smoke
VERIFY_CURRENT_SCENARIO_DIR=scenarios/runtime_smoke
quic_client_config=$(verification_generate_protocol_probe_client_config vless-plain "$3")
cp "$quic_client_config" "$4"
EOF_QUIC_RUN
jq -e '
  .outbounds[0] as $out |
  $out.type == "vless" and $out.server == "127.0.0.1" and $out.server_port == 18089 and
  $out.uuid == "11111111-1111-4111-8111-111111111111" and
  $out.network == ["tcp", "udp"] and $out.transport == {type:"quic"} and
  $out.tls == {enabled:true,server_name:"vless-probe.test",insecure:true,alpn:["h3"]}
' "${TMP_DIR}/vless-quic-client.json" >/dev/null
! grep -Fq 'PRIVATE KEY' "${TMP_DIR}/vless-quic-client.json"
! grep -Fq 'server.key' "${TMP_DIR}/vless-quic-client.json"
printf 'VLESS plain probe generator uses the ordinary discriminator and probe-only TLS trust\n'
