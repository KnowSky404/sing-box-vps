#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
umask 077

mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/shadowtls.env"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -subj '/CN=shadowtls.test' \
  -keyout "${TMP_DIR}/shadowtls.key" \
  -out "${TMP_DIR}/shadowtls.crt" >/dev/null 2>&1
jq -n --arg cert "${TMP_DIR}/shadowtls.crt" '
  {schema_version:1,protocol:"shadowtls",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"ShadowTLS probe",tag:"shadowtls-in",
     listen:{address:"127.0.0.1",port:18444},version:3,
     authentication:{password:"",users:[{name:"shadow-user",password:"shadow-password"}]},
     handshake:{server:"127.0.0.1",server_port:18443},handshake_for_server_name:{},
     strict_mode:false,wildcard_sni:"off",
     detour:{tag:"shadowtls-inner-main",listen:{address:"127.0.0.1",port:18445}},
     dependencies:["shadowtls-inner-main"],client_trust:"certificate",
     client_tls:{server_name:"shadowtls.test",certificate_path:$cert},
     outbound_policy:"default"}]}
' > "${TMP_DIR}/project/protocols/instances/shadowtls.json"
jq -n '{inbounds:[
  {type:"shadowtls",tag:"shadowtls-in",listen:"127.0.0.1",listen_port:18444,
   detour:"shadowtls-inner-main",version:3,users:[{name:"shadow-user",password:"shadow-password"}],
   handshake:{server:"127.0.0.1",server_port:18443}},
  {type:"mixed",tag:"shadowtls-inner-main",listen:"127.0.0.1",listen_port:18445}
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
verification_generate_protocol_probe_client_config shadowtls "${fixture_dir}/config.json" >/dev/null
RUN

client_file="${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/shadowtls/client.json"
jq -e '
  ([.outbounds[] | select(.type == "shadowtls")] | length) == 1 and
  ([.outbounds[] | select(.type == "http")] | length) == 1 and
  (.outbounds | map(select(.type == "shadowtls"))[0]) as $transport |
  (.outbounds | map(select(.type == "http"))[0]) as $proxy |
  $transport.tag == "shadowtls-transport" and
  $transport.server == "127.0.0.1" and $transport.server_port == 18444 and
  $transport.password == "shadow-password" and $transport.tls.enabled == true and
  ($transport.tls.certificate | contains("BEGIN CERTIFICATE")) and
  $proxy.tag == "proxy" and $proxy.server == "127.0.0.1" and
  $proxy.server_port == 18445 and $proxy.detour == "shadowtls-transport" and
  .route.final == "proxy" and
  ([.inbounds[] | select(.tag == "local-socks" and .listen_port == 19080)] | length) == 1
' "${client_file}" >/dev/null
[[ "$(stat -c '%a' "${client_file}")" == 600 ]]
! grep -Fq 'PRIVATE KEY' "${client_file}"
! grep -Fq 'shadowtls.json' "${client_file}"
printf 'ShadowTLS verification probe generator proves the composite transport chain\n'
