#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 128
REPO_ROOT=$(cd "${TESTS_DIR}/.." && pwd)

mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/tuic"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/tuic.env"
printf 'INSTALLED_PROTOCOLS=tuic\n' > "${TMP_DIR}/project/protocols/index.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=tuic.test' \
  -addext 'subjectAltName=DNS:tuic.test' \
  -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.crt" >/dev/null 2>"${TMP_DIR}/openssl.log"
jq -n --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/server.key" '
  {schema_version:1,protocol:"tuic",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"TUIC probe",tag:"tuic-in",
     listen:{address:"127.0.0.1",port:18088},
     authentication:{users:[
       {name:"first",uuid:"11111111-1111-4111-8111-111111111111",
        password:"tuic password with spaces & $?"}]},
     tls:{enabled:true,server_name:"tuic.test",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",
     tuic:{auth_timeout_seconds:3,congestion_control:"bbr",heartbeat_seconds:10,
       udp_over_stream:false,udp_relay_mode:"quic",zero_rtt_handshake:true},
     outbound_policy:"default",dependencies:[]}]}
' > "${TMP_DIR}/project/protocols/instances/tuic.json"
jq -n '{inbounds:[{type:"tuic",tag:"tuic-in",listen_port:18088}]}' > "${TMP_DIR}/config.json"

awk '/^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {exit} {print}' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TMP_DIR}/entrypoint.sh"

# Use the exact installer exporter in a fresh shell, matching the Docker
# entrypoint.  The client receives only the public certificate material.
bash -s -- "${TMP_DIR}/entrypoint.sh" "${TESTABLE_INSTALL}" "${TMP_DIR}" <<'RUN'
set -euo pipefail
source "$1"
VERIFY_REMOTE_INSTALL_SCRIPT=$2
fixture_dir=$3
verification_generate_tuic_probe_client \
  "${fixture_dir}/config.json" \
  "${fixture_dir}/artifacts/client.json"
RUN

jq -e '
  .outbounds[0] as $out |
  $out.type=="tuic" and $out.tag=="proxy" and
  $out.server=="127.0.0.1" and $out.server_port==18088 and
  $out.uuid=="11111111-1111-4111-8111-111111111111" and
  $out.password=="tuic password with spaces & $?" and
  $out.network==["tcp","udp"] and $out.tls.alpn==["h3"] and
  $out.tls.enabled==true and $out.tls.server_name=="tuic.test" and
  ($out.tls.certificate|contains("BEGIN CERTIFICATE")) and
  ($out.tls|has("key")|not) and
  $out.congestion_control=="bbr" and
  $out.udp_relay_mode=="quic" and
  $out.zero_rtt_handshake==true and
  $out.heartbeat=="10s" and
  (.outbounds|length)==1
' "${TMP_DIR}/artifacts/client.json" >/dev/null
[[ $(stat -c '%a' "${TMP_DIR}/artifacts/client.json") == 600 ]]
! rg -q 'PRIVATE KEY|server.key|second-secret' "${TMP_DIR}/artifacts/client.json"

printf 'TUIC verification probe uses the managed multi-user exporter and preserves UDP relay options with public-only TLS material\n'
