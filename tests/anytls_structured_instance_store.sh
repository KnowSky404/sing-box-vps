#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 127
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "AnyTLS structured store failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"
state_file="${SB_PROTOCOL_STATE_DIR}/anytls.env"
cert_file="${TMP_DIR}/anytls.crt"
key_file="${TMP_DIR}/anytls.key"
printf '%s\n' 'certificate fixture' > "${cert_file}"
printf '%s\n' 'private key fixture' > "${key_file}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"

jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {schema_version:1,protocol:"anytls",revision:7,default_instance_id:"anytls-public",instances:[
    {id:"anytls-local",name:"AnyTLS local",tag:"anytls-local",listen:{address:"127.0.0.1",port:34411},
     authentication:{users:[{name:"alice",password:"alice-password"},{name:"bob",password:"bob-password"}]},
     tls:{enabled:true,server_name:"anytls.local",certificate_path:$cert,key_path:$key},client_trust:"system",
     outbound_policy:"default",dependencies:[]},
    {id:"anytls-public",name:"AnyTLS public",tag:"anytls-public",listen:{address:"0.0.0.0",port:34412},
     authentication:{users:[{name:"public",password:"public-password"}]},
     tls:{enabled:true,server_name:"anytls.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
     outbound_policy:"direct",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"

[[ "$(structured_instance_store_protocol anytls)" == anytls ]]
validate_structured_instance_store anytls "${store_file}"
plain_proxy_structured_state_active anytls
[[ "$(list_protocol_instance_ids anytls)" == $'anytls-local\nanytls-public' ]]
[[ "$(protocol_default_instance_id anytls)" == anytls-public ]]

load_protocol_state anytls read-only
[[ "${SB_PROTOCOL}" == anytls && "${SB_INSTANCE_ID}" == anytls-public ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 && "${SB_PORT}" == 34412 ]]
[[ "${SB_ANYTLS_CLIENT_TRUST}" == certificate ]]
jq -e 'length == 1 and .[0].name == "public" and .[0].password == "public-password"' \
  <<< "${SB_ANYTLS_AUTH_JSON}" >/dev/null
jq -e '.enabled == true and .server_name == "anytls.example"' \
  <<< "${SB_ANYTLS_TLS_JSON}" >/dev/null

rendered=$(render_structured_instance_inbounds anytls "${store_file}" | jq -s .)
jq -e '
  length == 2 and
  any(.[]; .tag == "anytls-local" and .type == "anytls" and .listen == "127.0.0.1" and
    .users[0].name == "alice" and .tls.server_name == "anytls.local" and
    (.tls | has("certificate_path")) and (.tls | has("key_path"))) and
  any(.[]; .tag == "anytls-public" and .listen_port == 34412 and
    .users[0].password == "public-password" and .tls.enabled == true)
' <<< "${rendered}" >/dev/null
routes=$(render_structured_instance_route_rules anytls "${store_file}")
jq -e 'length == 3 and any(.[]; .inbound == "anytls-public" and .outbound == "direct")' \
  <<< "${routes}" >/dev/null
listed=$(anytls_instance_management_menu list)
grep -Fq $'anytls-local\tAnyTLS local' <<< "${listed}"
grep -Fq $'users=2\ttls=true\tclient_trust=system' <<< "${listed}"
grep -Fq $'anytls-public\tAnyTLS public' <<< "${listed}"

jq -c '.instances[0]' "${store_file}" > "${TMP_DIR}/instance.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/instance.json" anytls

reject_instance() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${TMP_DIR}/instance.json" > "${invalid_file}"
  if structured_instance_store_validate_instance_argument "${invalid_file}" anytls; then
    printf 'accepted invalid AnyTLS instance: %s\n' "${label}" >&2
    return 1
  fi
}

reject_store() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${store_file}" > "${invalid_file}"
  if validate_structured_instance_store anytls "${invalid_file}"; then
    printf 'accepted invalid AnyTLS store: %s\n' "${label}" >&2
    return 1
  fi
}

reject_instance disabled_tls '.tls = {enabled:false}'
reject_instance unknown_tls '.tls.provider = "acme"'
reject_instance unsupported_transport '.transport = {type:"ws",path:"/anytls"}'
reject_instance empty_users '.authentication.users = []'
reject_store duplicate_names '.instances[0].authentication.users[1].name = "alice"'
reject_store duplicate_passwords '.instances[0].authentication.users[1].password = "alice-password"'
reject_store unknown_record_field '.instances[0].unknown = true'
reject_store invalid_trust '.instances[1].client_trust = "insecure"'

# Legacy AnyTLS remains readable and is not accidentally forced through the
# schema-2 typed loader.
mv "${store_file}" "${store_file}.typed"
cat > "${state_file}" <<'EOF_LEGACY'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls-legacy
PORT=443
DOMAIN=legacy.anytls.example
PASSWORD=legacy-password
USER_NAME=legacy-user
TLS_MODE=acme
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=legacy.anytls.example
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=
KEY_PATH=
EOF_LEGACY
load_protocol_state anytls read-only
[[ "${SB_PROTOCOL}" == anytls && "${SB_ANYTLS_DOMAIN}" == legacy.anytls.example ]]
[[ "${SB_ANYTLS_PASSWORD}" == legacy-password && "${SB_ANYTLS_TLS_MODE}" == acme ]]

printf 'AnyTLS structured instance store checks passed\n'
