#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
umask 077
mkdir -p "${TMP_DIR}/project/protocols/instances" "${TMP_DIR}/artifacts"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/trojan.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=trojan.test' \
  -keyout "${TMP_DIR}/server.key" -out "${TMP_DIR}/server.crt" >/dev/null 2>"${TMP_DIR}/openssl.log"
jq -n --arg cert "${TMP_DIR}/server.crt" --arg key "${TMP_DIR}/server.key" '
  {schema_version:1,protocol:"trojan",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"Trojan probe",tag:"trojan-in",
     listen:{address:"127.0.0.1",port:18083},
     authentication:{users:[{name:"first",password:"密碼 $ quote\"\n"},{name:"second",password:"second-secret"}]},
     tls:{enabled:true,server_name:"trojan.test",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",transport:{type:"ws",path:"/proxy",max_early_data:0},
     outbound_policy:"default",dependencies:[]}]}
' > "${TMP_DIR}/project/protocols/instances/trojan.json"
jq -n '{inbounds:[{type:"trojan",tag:"trojan-in"}]}' > "${TMP_DIR}/config.json"
awk '/^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ {exit} {print}' \
  "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TMP_DIR}/entrypoint.sh"

# Fresh shell: sourcing the standalone installer twice would redefine its
# readonly constants and does not represent how the Docker entrypoint runs.
bash -s -- "${TMP_DIR}/entrypoint.sh" "${TESTABLE_INSTALL}" "${TMP_DIR}" <<'RUN'
set -euo pipefail
source "$1"
old_artifact_dir=${VERIFY_ARTIFACT_DIR}
VERIFY_REMOTE_INSTALL_SCRIPT=$2
fixture_dir=$3
verification_generate_trojan_probe_client "${fixture_dir}/config.json" "${fixture_dir}/artifacts/client.json"
rm -rf -- "${old_artifact_dir}"
RUN

jq -e --rawfile certificate "${TMP_DIR}/server.crt" '
  .outbounds[0] as $out |
  $out.type=="trojan" and $out.tag=="proxy" and $out.server=="127.0.0.1" and
  $out.server_port==18083 and $out.password=="密碼 $ quote\"\n" and
  $out.transport=={type:"ws",path:"/proxy",max_early_data:0} and
  $out.tls.enabled==true and $out.tls.server_name=="trojan.test" and
  $out.tls.alpn==["http/1.1"] and ($out.tls.insecure // false)==false and
  ($out.tls | has("key") or has("key_path") | not) and
  ([$out.tls.certificate] | flatten | join("\n") | contains("BEGIN CERTIFICATE"))
' "${TMP_DIR}/artifacts/client.json" >/dev/null
! rg -q 'PRIVATE KEY|server.key|second-secret' "${TMP_DIR}/artifacts/client.json"
[[ $(stat -c '%a' "${TMP_DIR}/artifacts/client.json") == 600 ]]
printf 'Trojan probe client uses managed exporter, strict trust and unchanged credential bytes\n'
