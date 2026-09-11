#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
REPO_ROOT=$(cd "${TESTS_DIR}/.." && pwd)

mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/vmess"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/vmess.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=vmess.test' \
  -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.crt" >/dev/null 2>"${TMP_DIR}/openssl.log"
jq -n --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/server.key" '
  {schema_version:1,protocol:"vmess",revision:1,default_instance_id:"main",
   instances:[
     {id:"main",name:"VMess probe",tag:"vmess-in",
       listen:{address:"127.0.0.1",port:18085},
       authentication:{users:[{name:"first",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto"}]},
       tls:{enabled:true,server_name:"vmess.test",certificate_path:$cert,key_path:$key},
       client_trust:"certificate",transport:{type:"ws",path:"/proxy",headers:{Host:"vmess.test"}},
       outbound_policy:"default",dependencies:[]},
     {id:"quic",name:"VMess QUIC probe",tag:"vmess-quic",
       listen:{address:"127.0.0.1",port:18086},
       authentication:{users:[{name:"quic",uuid:"22222222-2222-4222-8222-222222222222",alter_id:0,security:"auto"}]},
       tls:{enabled:true,server_name:"vmess.test",certificate_path:$cert,key_path:$key},
       client_trust:"certificate",transport:{type:"quic"},
       outbound_policy:"default",dependencies:[]}
   ]}
' > "${TMP_DIR}/project/protocols/instances/vmess.json"
jq -n '{inbounds:[{type:"vmess",tag:"vmess-in",listen_port:18085}]}' > "${TMP_DIR}/config.json"
awk '/^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {exit} {print}' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TMP_DIR}/entrypoint.sh"

VERIFY_PROTOCOL_REGISTRY_JSON=$(source "${REPO_ROOT}/install.sh"; protocol_registry_json)
export VERIFY_PROTOCOL_REGISTRY_JSON
VERIFY_ARTIFACT_DIR="${TMP_DIR}/artifacts"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/fresh"
VERIFY_REMOTE_INSTALL_SCRIPT="${TESTABLE_INSTALL}"
export VERIFY_ARTIFACT_DIR VERIFY_CURRENT_SCENARIO_DIR VERIFY_REMOTE_INSTALL_SCRIPT

bash -s -- "${TMP_DIR}/entrypoint.sh" "${TMP_DIR}" <<'RUN'
set -euo pipefail
source "$1"
fixture_dir=$2
VERIFY_ARTIFACT_DIR="${fixture_dir}/artifacts"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/fresh"
export VERIFY_ARTIFACT_DIR VERIFY_CURRENT_SCENARIO_DIR
verification_generate_protocol_probe_client_config vmess "${fixture_dir}/config.json" >/dev/null
verification_generate_vmess_probe_client \
  <(jq -n '{inbounds:[{type:"vmess",tag:"vmess-quic",listen_port:18086}]}') \
  "${fixture_dir}/artifacts/scenarios/fresh/protocol-probes/vmess/quic-client.json"
RUN

client_file="${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/vmess/client.json"
jq -e '
  .outbounds[0] as $out |
  $out.type=="vmess" and $out.tag=="proxy" and $out.server=="127.0.0.1" and
  $out.server_port==18085 and $out.uuid=="11111111-1111-4111-8111-111111111111" and
  $out.security=="auto" and $out.alter_id==0 and $out.network==["tcp","udp"] and
  $out.transport=={type:"ws",path:"/proxy",headers:{Host:"vmess.test"}} and
  $out.tls.enabled==true and $out.tls.server_name=="vmess.test" and
  ($out.tls.certificate|contains("BEGIN CERTIFICATE")) and
  ($out.tls|has("key")|not) and (.outbounds|length)==1
' "${client_file}" >/dev/null
[[ $(stat -c '%a' "${client_file}") == 600 ]]
! grep -Fq 'PRIVATE KEY' "${client_file}"
quic_client_file="${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/vmess/quic-client.json"
jq -e '
  .outbounds[0] as $out |
  $out.type=="vmess" and $out.tag=="proxy" and $out.server=="127.0.0.1" and
  $out.server_port==18086 and $out.uuid=="22222222-2222-4222-8222-222222222222" and
  $out.security=="auto" and $out.network==["tcp","udp"] and
  $out.transport=={type:"quic"} and
  $out.tls.enabled==true and $out.tls.server_name=="vmess.test" and
  $out.tls.alpn==["h3"] and ($out.tls.certificate|contains("BEGIN CERTIFICATE")) and
  ($out.tls|has("key")|not) and (.outbounds|length)==1
' "${quic_client_file}" >/dev/null
[[ $(stat -c '%a' "${quic_client_file}") == 600 ]]
! grep -Fq 'PRIVATE KEY' "${quic_client_file}"
printf 'VMess verification probe generator uses managed state, QUIC h3 and probe-only trust\n'
