#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
umask 077

mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/naive.env"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -subj '/CN=naive.test' \
  -addext 'subjectAltName=DNS:naive.test' \
  -keyout "${TMP_DIR}/naive.key" \
  -out "${TMP_DIR}/naive.crt" >/dev/null 2>&1
jq -n --arg cert "${TMP_DIR}/naive.crt" --arg key "${TMP_DIR}/naive.key" '
  {schema_version:1,protocol:"naive",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"Naive TCP probe",tag:"naive-in",
     listen:{address:"127.0.0.1",port:18446,network:["tcp"]},
     authentication:{users:[{name:"naive-user",username:"naive-user",password:"naive-password"}]},
     tls:{enabled:true,server_name:"naive.test",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",
     naive:{extra_headers:{},insecure_concurrency:0,quic:false,
       quic_congestion_control:"bbr",quic_session_receive_window:"",stream_receive_window:""},
     outbound_policy:"default",dependencies:[]}]}
' > "${TMP_DIR}/project/protocols/instances/naive.json"
jq -n --arg cert "${TMP_DIR}/naive.crt" --arg key "${TMP_DIR}/naive.key" '{inbounds:[
  {type:"naive",tag:"naive-in",listen:"127.0.0.1",listen_port:18446,
   network:"tcp",users:[{username:"naive-user",password:"naive-password"}],
   tls:{enabled:true,server_name:"naive.test",certificate_path:$cert,key_path:$key}}
]}' > "${TMP_DIR}/config.json"

VERIFY_PROTOCOL_REGISTRY_JSON=$(source "${REPO_ROOT}/install.sh"; protocol_registry_json)
export VERIFY_PROTOCOL_REGISTRY_JSON
source_testable_install
awk '/^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {exit} {print}' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TMP_DIR}/entrypoint.sh"

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
verification_generate_protocol_probe_client_config naive "${fixture_dir}/config.json" >/dev/null
RUN

client_file="${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/naive/client.json"
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "naive" and .outbounds[0].tag == "proxy" and
  .outbounds[0].server == "127.0.0.1" and .outbounds[0].server_port == 18446 and
  .outbounds[0].username == "naive-user" and
  .outbounds[0].password == "naive-password" and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.server_name == "naive.test" and
  (.outbounds[0].tls.certificate | contains("BEGIN CERTIFICATE")) and
  (.outbounds[0].tls | has("key") | not) and
  (.outbounds[0].quic // false) == false and
  .route.final == "proxy" and
  ([.inbounds[] | select(.tag == "local-socks" and .listen_port == 19080)] | length) == 1
' "${client_file}" >/dev/null
[[ "$(stat -c '%a' "${client_file}")" == 600 ]]
! grep -Fq 'PRIVATE KEY' "${client_file}"
! grep -Fq 'naive.json' "${client_file}"
printf 'NaiveProxy verification probe generator preserves TCP exporter and public-only TLS material\n'

# A UDP-only Naive listener must select the QUIC/HTTP3 client transport.  The
# sing-box Naive outbound can carry UDP only through UDP-over-TCP, which needs
# a TCP listener; do not silently add that adapter to this UDP-only fixture.
jq '.instances[0].listen.network=["udp"] | .instances[0].naive.quic=true' \
  "${TMP_DIR}/project/protocols/instances/naive.json" > \
  "${TMP_DIR}/project/protocols/instances/naive.next.json"
mv "${TMP_DIR}/project/protocols/instances/naive.next.json" \
  "${TMP_DIR}/project/protocols/instances/naive.json"
jq '.inbounds[0].network="udp"' "${TMP_DIR}/config.json" > "${TMP_DIR}/config.next.json"
mv "${TMP_DIR}/config.next.json" "${TMP_DIR}/config.json"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/udp"
export VERIFY_CURRENT_SCENARIO_DIR
bash -s -- "${TMP_DIR}/entrypoint.sh" "${TMP_DIR}" <<'RUN_UDP'
set -euo pipefail
source "$1"
fixture_dir=$2
VERIFY_ARTIFACT_DIR="${fixture_dir}/artifacts"
VERIFY_CURRENT_SCENARIO_DIR="scenarios/udp"
export VERIFY_ARTIFACT_DIR VERIFY_CURRENT_SCENARIO_DIR
verification_generate_protocol_probe_client_config naive "${fixture_dir}/config.json" >/dev/null
RUN_UDP

udp_client_file="${TMP_DIR}/artifacts/scenarios/udp/protocol-probes/naive/client.json"
jq -e '
  .log.level == "debug" and
  .outbounds[0].type == "naive" and
  .outbounds[0].quic == true and
  (.outbounds[0] | has("udp_over_tcp") | not) and
  .outbounds[0].server_port == 18446
' "${udp_client_file}" >/dev/null
printf 'NaiveProxy UDP probe generator selects QUIC/HTTP3 and avoids TCP-only UoT\n'
