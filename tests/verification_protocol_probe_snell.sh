#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
umask 077
mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/snell.env"
jq -n '
  {schema_version:1,protocol:"snell",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"Snell probe",tag:"snell-in",
     listen:{address:"127.0.0.1",port:18086},
     authentication:{psk:"snell-v6-psk-123456",users:[{name:"snell-user",userkey:"snell-user-key"}]},
     version:6,obfs_mode:"",obfs_host:"",mode:"default",
     outbound_policy:"default",dependencies:[]}]}
' > "${TMP_DIR}/project/protocols/instances/snell.json"
jq -n '{inbounds:[{type:"snell",tag:"snell-in",listen:"127.0.0.1",listen_port:18086,version:6,psk:"snell-v6-psk-123456",users:[{name:"snell-user",userkey:"snell-user-key"}],mode:"default"}]}' \
  > "${TMP_DIR}/config.json"
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
verification_generate_protocol_probe_client_config snell "${fixture_dir}/config.json" >/dev/null
RUN

client_file="${TMP_DIR}/artifacts/scenarios/fresh/protocol-probes/snell/client.json"
jq -e '
  .outbounds[0] as $out |
  $out.type == "snell" and $out.tag == "proxy" and
  $out.server == "127.0.0.1" and $out.server_port == 18086 and
  $out.version == 6 and $out.psk == "snell-v6-psk-123456" and
  $out.userkey == "snell-user-key" and $out.network == "tcp" and
  $out.mode == "default" and (.outbounds | length) == 1 and
  .route.final == "proxy" and
  ([.inbounds[] | select(.tag == "local-socks" and .listen_port == 19080)] | length) == 1
' "${client_file}" >/dev/null
[[ $(stat -c '%a' "${client_file}") == 600 ]]
! grep -Fq 'snell.json' "${client_file}"
printf 'Snell verification probe generator uses managed v6 state and TCP exporter\n'
