#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "plain proxy structured store failed at line %s\n" "${LINENO}" >&2' ERR

store_file="${SB_PROTOCOL_STATE_DIR}/instances/socks.json"
state_file="${SB_PROTOCOL_STATE_DIR}/socks.env"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"

jq -n '
  {
    schema_version: 1,
    protocol: "socks",
    revision: 0,
    default_instance_id: "Socks_A",
    instances: [
      {
        id: "Socks_A",
        name: "SOCKS primary",
        tag: "socks-primary",
        listen: {address: "0.0.0.0", port: 33101},
        authentication: {enabled: true, username: "user\n", password: "pass\n"},
        outbound_policy: "direct",
        dependencies: []
      },
      {
        id: "socks-B",
        name: "SOCKS local",
        tag: "socks-local",
        listen: {address: "127.0.0.1", port: 33102},
        authentication: {enabled: false, username: "", password: ""},
        outbound_policy: "default",
        dependencies: []
      }
    ]
  }
' > "${store_file}"
chmod 600 "${store_file}"

[[ "$(structured_instance_store_protocol socks)" == socks ]]
validate_structured_instance_store socks "${store_file}"
! plain_proxy_structured_state_active socks

save_plain_proxy_structured_marker socks
plain_proxy_structured_state_active socks
[[ "$(plain_proxy_structured_store_file socks)" == "${store_file}" ]]

load_plain_proxy_structured_instance socks
[[ "${SB_PROTOCOL}" == socks && "${SB_INSTANCE_ID}" == Socks_A ]]
[[ "${SB_MIXED_USERNAME}" == $'user\n' && "${SB_MIXED_PASSWORD}" == $'pass\n' ]]
[[ "${SB_MIXED_INBOUND_TAG}" == socks-primary && "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 ]]
[[ "${SB_OUTBOUND_POLICY}" == direct ]]

inbounds_json=$(render_structured_instance_inbounds socks "${store_file}" | jq -s .)
jq -e '
  length == 2 and
  .[0].type == "socks" and .[0].tag == "socks-primary" and
  .[0].users[0].username == "user\n" and
  .[1].type == "socks" and .[1].listen == "127.0.0.1" and
  (.[1].users | length) == 0
' <<< "${inbounds_json}" >/dev/null
route_json=$(render_structured_instance_route_rules socks "${store_file}")
jq -e 'length == 3 and any(.[]; .inbound == "socks-primary" and .outbound == "direct")' \
  <<< "${route_json}" >/dev/null

# Build a representable live SOCKS config and verify the generic collector,
# inventory matcher, and candidate all retain protocol-specific typed data.
jq '{inbounds: [.instances[] | {type: "socks", tag: .tag, listen: .listen.address,
  listen_port: .listen.port,
  users: (if .authentication.enabled then
    [{username: .authentication.username, password: .authentication.password}]
  else [] end)}],
  route: {rules: ([.instances[] | select(.outbound_policy != "default") |
    {inbound: .tag, action: "route", outbound: (if .outbound_policy == "warp" then "warp-ep" else .outbound_policy end)}])}}' \
  "${store_file}" > "${SINGBOX_CONFIG_FILE}"
plain_proxy_validate_state_inventory socks
plain_proxy_structured_state_matches_config socks
candidate_json=$(plain_proxy_config_store_candidate socks)
jq -e '.protocol == "socks" and (.instances | length) == 2 and any(.instances[]; .tag == "socks-primary")' \
  <<< "${candidate_json}" >/dev/null
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/socks-config-before-unknown.json"
jq '.inbounds[0].set_system_proxy = false' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/socks-config-unknown.json"
mv "${TMP_DIR}/socks-config-unknown.json" "${SINGBOX_CONFIG_FILE}"
! plain_proxy_config_store_candidate socks >/dev/null 2>&1
mv "${TMP_DIR}/socks-config-before-unknown.json" "${SINGBOX_CONFIG_FILE}"

# HTTP is a separate schema-2 typed store.  TLS is stored as a typed reference
# (never as arbitrary passthrough JSON) and is reproduced in the live inbound.
http_store_file="${SB_PROTOCOL_STATE_DIR}/instances/http.json"
http_state_file="${SB_PROTOCOL_STATE_DIR}/http.env"
jq -n '
  {
    schema_version: 1,
    protocol: "http",
    revision: 0,
    default_instance_id: "http-main",
    instances: [{
      id: "http-main",
      name: "HTTP primary",
      tag: "http-primary",
      listen: {address: "127.0.0.1", port: 33104},
      authentication: {enabled: true, username: "http-user", password: "http-password"},
      outbound_policy: "direct",
      dependencies: [],
      tls: {enabled: true, server_name: "proxy.example.com", certificate_path: "/tmp/http.crt", key_path: "/tmp/http.key"}
    }]
  }
' > "${http_store_file}"
printf '%s\n' 'INSTALLED=1' 'CONFIG_SCHEMA_VERSION=2' > "${http_state_file}"
chmod 600 "${http_store_file}" "${http_state_file}"

[[ "$(structured_instance_store_protocol http)" == http ]]
validate_structured_instance_store http "${http_store_file}"
plain_proxy_structured_state_active http
load_plain_proxy_structured_instance http
[[ "${SB_PROTOCOL}" == http && "${SB_INSTANCE_ID}" == http-main ]]
jq -e '
  .enabled == true and .server_name == "proxy.example.com" and
  .certificate_path == "/tmp/http.crt" and .key_path == "/tmp/http.key"
' <<< "${SB_HTTP_TLS_JSON}" >/dev/null

http_inbounds_json=$(render_structured_instance_inbounds http "${http_store_file}" | jq -s .)
jq -e '
  length == 1 and .[0].type == "http" and .[0].tag == "http-primary" and
  .[0].listen == "127.0.0.1" and .[0].listen_port == 33104 and
  .[0].users[0].username == "http-user" and
  .[0].tls.enabled == true and .[0].tls.server_name == "proxy.example.com"
' <<< "${http_inbounds_json}" >/dev/null

jq '{inbounds: [.instances[] | {type: "http", tag: .tag, listen: .listen.address,
  listen_port: .listen.port, users: [{username: .authentication.username, password: .authentication.password}],
  tls: .tls}], route: {rules: ([.instances[] | select(.outbound_policy != "default") |
    {inbound: .tag, action: "route", outbound: (if .outbound_policy == "warp" then "warp-ep" else .outbound_policy end)}])}}' \
  "${http_store_file}" > "${SINGBOX_CONFIG_FILE}"
plain_proxy_validate_state_inventory http
plain_proxy_structured_state_matches_config http
http_candidate_json=$(plain_proxy_config_store_candidate http)
jq -e '
  .protocol == "http" and (.instances | length) == 1 and
  .instances[0].tls.enabled == true and
  .instances[0].tls.certificate_path == "/tmp/http.crt"
' <<< "${http_candidate_json}" >/dev/null

cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/http-config-before-unsupported.json"
jq '.inbounds[0].unsupported_http_option = true' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/http-config-unsupported.json"
mv "${TMP_DIR}/http-config-unsupported.json" "${SINGBOX_CONFIG_FILE}"
! plain_proxy_config_store_candidate http >/dev/null 2>&1
cp -p "${TMP_DIR}/http-config-before-unsupported.json" "${SINGBOX_CONFIG_FILE}"

jq '.inbounds[0].tls.ca = "/tmp/unsupported-ca.pem"' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/http-config-unsupported-tls.json"
mv "${TMP_DIR}/http-config-unsupported-tls.json" "${SINGBOX_CONFIG_FILE}"
! plain_proxy_config_store_candidate http >/dev/null 2>&1
cp -p "${TMP_DIR}/http-config-before-unsupported.json" "${SINGBOX_CONFIG_FILE}"

jq '.inbounds += [{type: "unknown-http-endpoint", tag: "unknown-http-endpoint", listen_port: 33105}]' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/http-config-unknown-type.json"
mv "${TMP_DIR}/http-config-unknown-type.json" "${SINGBOX_CONFIG_FILE}"
! plain_proxy_config_store_candidate http >/dev/null 2>&1
cp -p "${TMP_DIR}/http-config-before-unsupported.json" "${SINGBOX_CONFIG_FILE}"

# The generic file primitive must preserve the protocol field and support CAS
# records without accepting a Mixed document under the SOCKS path.
empty_json=$(structured_instance_store_empty_json socks)
printf '%s\n' '{"id":"new-id","name":"new","tag":"new-tag","listen":{"address":"127.0.0.1","port":33103},"authentication":{"enabled":false,"username":"","password":""},"outbound_policy":"default","dependencies":[]}' \
  > "${TMP_DIR}/instance.json"
printf '%s\n' "${empty_json}" > "${TMP_DIR}/empty.json"
cas_json=$(structured_instance_store_candidate socks "${TMP_DIR}/empty.json" create "${TMP_DIR}/instance.json" 0)
jq -e '.protocol == "socks" and .revision == 1 and .instances[0].id == "new-id"' <<< "${cas_json}" >/dev/null

# SOCKS has no schema-1 migration path, and an active marker with a missing
# typed store must fail closed rather than synthesizing a legacy candidate.
mv "${store_file}" "${store_file}.saved"
! plain_proxy_structured_state_active socks
! plain_proxy_config_store_candidate socks >/dev/null 2>&1
mv "${store_file}.saved" "${store_file}"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nPORT=33101\n' > "${state_file}"
! plain_proxy_config_store_candidate socks >/dev/null 2>&1

printf 'plain proxy structured store checks passed\n'
