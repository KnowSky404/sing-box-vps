#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
REPO_ROOT=$(cd "${TESTS_DIR}/.." && pwd)

mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/hysteria"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/hysteria.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=hysteria.test' \
  -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.crt" >/dev/null 2>"${TMP_DIR}/openssl.log"
jq -n --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/server.key" '
  {schema_version:1,protocol:"hysteria",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"Hysteria probe",tag:"hysteria-in",
     listen:{address:"127.0.0.1",port:18087},
     authentication:{users:[
       {name:"first",auth_str:"auth str with spaces & $?"},
       {name:"second",auth_str:"second-secret"}]},
     tls:{enabled:true,server_name:"hysteria.test",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",
     bandwidth:{up_mbps:123,down_mbps:456},
     obfs:{enabled:true,password:"obfs secret"},
     hysteria:{connection_receive_window:"20 MB",disable_path_mtu_discovery:true,
       initial_packet_size:1200,max_concurrent_streams:32,stream_receive_window:"10 MB"},
     outbound_policy:"default",dependencies:[]}]}
' > "${TMP_DIR}/project/protocols/instances/hysteria.json"
jq -n '{inbounds:[{type:"hysteria",tag:"hysteria-in",listen_port:18087}]}' > "${TMP_DIR}/config.json"
awk '/^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {exit} {print}' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TMP_DIR}/entrypoint.sh"

# Use the exact installer exporter in a fresh shell, matching the Docker
# entrypoint.  The fixture has two users; the probe intentionally exports one
# user so no additional credential is needlessly copied into the client.
bash -s -- "${TMP_DIR}/entrypoint.sh" "${TESTABLE_INSTALL}" "${TMP_DIR}" <<'RUN'
set -euo pipefail
source "$1"
VERIFY_REMOTE_INSTALL_SCRIPT=$2
fixture_dir=$3
verification_generate_hysteria_probe_client \
  "${fixture_dir}/config.json" \
  "${fixture_dir}/artifacts/client.json"
RUN

jq -e '
  .outbounds[0] as $out |
  $out.type=="hysteria" and $out.tag=="proxy" and
  $out.server=="127.0.0.1" and $out.server_port==18087 and
  $out.up_mbps==123 and $out.down_mbps==456 and
  $out.auth_str=="auth str with spaces & $?" and
  $out.tls.enabled==true and $out.tls.server_name=="hysteria.test" and
  $out.tls.alpn==["h3"] and
  ($out.tls.certificate|contains("BEGIN CERTIFICATE")) and
  ($out.tls|has("key")|not) and
  $out.obfs=="obfs secret" and
  $out.initial_packet_size==1200 and
  $out.max_concurrent_streams==32 and
  $out.disable_path_mtu_discovery==true and
  $out.stream_receive_window=="10 MB" and
  $out.connection_receive_window=="20 MB" and
  (.outbounds|length)==1
' "${TMP_DIR}/artifacts/client.json" >/dev/null
[[ $(stat -c '%a' "${TMP_DIR}/artifacts/client.json") == 600 ]]
! rg -q 'PRIVATE KEY|server.key|second-secret' "${TMP_DIR}/artifacts/client.json"

printf 'Hysteria v1 verification probe uses managed auth_str/bandwidth exporter and preserves public-only TLS material\n'
