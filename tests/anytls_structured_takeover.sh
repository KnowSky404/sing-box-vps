#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 130
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "AnyTLS structured takeover failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED_PROTOCOLS=anytls\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/anytls.env"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=anytls-takeover.example' \
  -addext 'subjectAltName=DNS:anytls-takeover.example' \
  -keyout "${TMP_DIR}/anytls.key" -out "${TMP_DIR}/anytls.crt" >/dev/null 2>&1
chmod 600 "${TMP_DIR}/anytls.key" "${TMP_DIR}/anytls.crt"

jq -n --arg cert "${TMP_DIR}/anytls.crt" --arg key "${TMP_DIR}/anytls.key" '
  {schema_version:1,protocol:"anytls",revision:9,default_instance_id:"anytls-public",instances:[
    {id:"anytls-local",name:"Local AnyTLS",tag:"anytls-local",listen:{address:"127.0.0.1",port:34521},
     authentication:{users:[{name:"alice",password:"alice-password"},{name:"bob",password:"bob-password"}]},
     tls:{enabled:true,server_name:"anytls-takeover.example",certificate_path:$cert,key_path:$key},client_trust:"system",
     outbound_policy:"default",dependencies:[]},
    {id:"anytls-public",name:"Public AnyTLS",tag:"anytls-public",listen:{address:"0.0.0.0",port:34522},
     authentication:{users:[{name:"public",password:"public-password"}]},
     tls:{enabled:true,server_name:"anytls-takeover.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
     outbound_policy:"direct",dependencies:[]}
  ]}
' > "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"
chmod 600 "${SB_PROTOCOL_STATE_DIR}/anytls.env" "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"

rendered=$(render_structured_instance_inbounds anytls "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" | jq -s .)
routes=$(render_structured_instance_route_rules anytls "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")
jq -n --argjson inbounds "${rendered}" --argjson routes "${routes}" \
  '{log:{level:"warn"},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$routes,final:"direct"}}' \
  > "${SINGBOX_CONFIG_FILE}"

before_config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
before_store_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")
candidate=$(anytls_config_store_candidate)
jq -e '
  .protocol == "anytls" and .revision == 9 and .default_instance_id == "anytls-public" and
  (.instances | length) == 2 and
  any(.instances[]; .tag == "anytls-local" and .id == "anytls-local" and
    .name == "Local AnyTLS" and (.authentication.users | length) == 2 and
    .client_trust == "system" and .outbound_policy == "default") and
  any(.instances[]; .tag == "anytls-public" and .id == "anytls-public" and
    .name == "Public AnyTLS" and .client_trust == "certificate" and
    .outbound_policy == "direct")
' <<< "${candidate}" >/dev/null
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")" == "${before_store_hash}" ]]

rebuild_protocol_state_from_config
plain_proxy_structured_state_active anytls
plain_proxy_validate_state_inventory anytls
plain_proxy_structured_state_matches_config anytls
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]
jq -e '
  .protocol == "anytls" and .revision == 9 and .default_instance_id == "anytls-public" and
  any(.instances[]; .tag == "anytls-local" and .name == "Local AnyTLS" and
    .authentication.users[1].password == "bob-password" and .client_trust == "system") and
  any(.instances[]; .tag == "anytls-public" and .name == "Public AnyTLS" and
    .authentication.users[0].password == "public-password" and .client_trust == "certificate")
' "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" >/dev/null

# A self-rendered inbound is a lossless takeover candidate and retains the
# client-only trust metadata stored outside sing-box's server configuration.
self_candidate=$(anytls_config_store_candidate "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")
jq -e 'any(.instances[]; .tag == "anytls-public" and .client_trust == "certificate")' \
  <<< "${self_candidate}" >/dev/null

jq '.inbounds[0].users[0].extra = true' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-field.json"
if anytls_config_store_candidate "${TMP_DIR}/bad-field.json" "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" \
  >/dev/null 2>"${TMP_DIR}/bad-field.stderr"; then
  printf 'accepted unsupported AnyTLS user field during takeover\n' >&2
  exit 1
fi
jq '.inbounds[1].tls = {enabled:false}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-tls.json"
if anytls_config_store_candidate "${TMP_DIR}/bad-tls.json" "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" \
  >/dev/null 2>"${TMP_DIR}/bad-tls.stderr"; then
  printf 'accepted disabled AnyTLS TLS during takeover\n' >&2
  exit 1
fi
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")" == "${before_store_hash}" ]]

# Multiple live AnyTLS inbounds must take the structured path even when the
# old state layer is absent; flattening them into one legacy singleton would
# silently discard an inbound and its credentials.
mv "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" "${TMP_DIR}/anytls.typed.json"
rm -f -- "${SB_PROTOCOL_STATE_DIR}/anytls.env" "${SB_PROTOCOL_STATE_DIR}/anytls.env.bak"
rebuild_protocol_state_from_config
plain_proxy_structured_state_active anytls
[[ "$(jq -r '.revision' "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")" == 1 ]]
[[ "$(jq -r '.instances | length' "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json")" == 2 ]]
jq -e 'all(.instances[]; .id == .tag and .name == .tag)' \
  "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" >/dev/null

core_checks=0
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${core_binary}" && -x "${core_binary}" ]]; then
    "${core_binary}" check -c "${SINGBOX_CONFIG_FILE}"
    core_checks=$((core_checks + 1))
  fi
done

printf 'AnyTLS structured takeover checks passed; real core checks=%s\n' "${core_checks}"
