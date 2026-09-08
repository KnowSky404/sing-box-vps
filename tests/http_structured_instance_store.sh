#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "HTTP structured instance store failed at line %s\n" "${LINENO}" >&2' ERR

store_file="${SB_PROTOCOL_STATE_DIR}/instances/http.json"
state_file="${SB_PROTOCOL_STATE_DIR}/http.env"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"

long_user=$(printf 'u%.0s' {1..300})
jq -n --arg long_user "${long_user}" '
  {
    schema_version: 1,
    protocol: "http",
    revision: 7,
    default_instance_id: "Http_TLS",
    instances: [
      {
        id: "Http_TLS",
        name: "HTTP TLS",
        tag: "http-tls",
        listen: {address: "0.0.0.0", port: 33401},
        authentication: {enabled: true, username: $long_user, password: "secret"},
        outbound_policy: "warp",
        tls: {enabled: true, server_name: "proxy.example.test", certificate_path: "/etc/ssl/proxy.crt", key_path: "/etc/ssl/proxy.key"},
        dependencies: []
      },
      {
        id: "http-plain",
        name: "HTTP plain",
        tag: "http-plain",
        listen: {address: "127.0.0.1", port: 33402},
        authentication: {enabled: false, username: "", password: ""},
        outbound_policy: "direct",
        tls: {enabled: false},
        dependencies: []
      }
    ]
  }
' > "${store_file}"
chmod 600 "${store_file}"

[[ "$(structured_instance_store_protocol http)" == http ]]
validate_structured_instance_store http "${store_file}"
save_plain_proxy_structured_marker http
plain_proxy_structured_state_active http

load_plain_proxy_structured_instance http
[[ "${SB_PROTOCOL}" == http && "${SB_INSTANCE_ID}" == Http_TLS ]]
[[ "${SB_MIXED_USERNAME}" == "${long_user}" && "${SB_MIXED_PASSWORD}" == secret ]]
[[ "${SB_MIXED_INBOUND_TAG}" == http-tls && "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 ]]
[[ "${SB_MIXED_STORE_REVISION}" == 7 ]]
jq -e '.enabled == true and .server_name == "proxy.example.test" and .certificate_path == "/etc/ssl/proxy.crt" and .key_path == "/etc/ssl/proxy.key"' \
  <<< "${SB_HTTP_TLS_JSON}" >/dev/null
load_plain_proxy_structured_instance http http-plain
[[ "${SB_MIXED_AUTH_ENABLED}" == n && "${SB_HTTP_TLS_JSON}" == '{"enabled":false}' ]]

inbounds_json=$(render_structured_instance_inbounds http "${store_file}" | jq -s .)
jq -e '
  length == 2 and
  .[0].type == "http" and .[0].tag == "http-tls" and .[0].tls.enabled == true and
  .[0].tls.server_name == "proxy.example.test" and (.[0].users[0].username | length == 300) and
  .[1].type == "http" and .[1].tag == "http-plain" and (.[1] | has("tls") | not) and
  (.[1].users | length) == 0
' <<< "${inbounds_json}" >/dev/null

# The HTTP instance argument has the protocol-specific TLS field.  The
# compatibility default remains Mixed and consequently rejects that field.
jq -c '.instances[0]' "${store_file}" > "${TMP_DIR}/http-instance.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/http-instance.json" http
! structured_instance_store_validate_instance_argument "${TMP_DIR}/http-instance.json"
jq -c '.instances[1]' "${store_file}" > "${TMP_DIR}/http-plain-instance.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/http-plain-instance.json" http

jq '.authentication.username = "bad:name"' "${TMP_DIR}/http-instance.json" > "${TMP_DIR}/http-instance-bad.json"
! structured_instance_store_validate_instance_argument "${TMP_DIR}/http-instance-bad.json" http
jq '.authentication.username = "bad\u0001name"' "${TMP_DIR}/http-instance.json" > "${TMP_DIR}/http-instance-bad.json"
! structured_instance_store_validate_instance_argument "${TMP_DIR}/http-instance-bad.json" http
jq '.authentication.password = "bad\u0001password"' "${TMP_DIR}/http-instance.json" > "${TMP_DIR}/http-instance-bad.json"
! structured_instance_store_validate_instance_argument "${TMP_DIR}/http-instance-bad.json" http
jq '.authentication.username = ("x" * 4097)' "${TMP_DIR}/http-instance.json" > "${TMP_DIR}/http-instance-bad.json"
! structured_instance_store_validate_instance_argument "${TMP_DIR}/http-instance-bad.json" http

cp -p "${store_file}" "${TMP_DIR}/valid.json"
jq '.instances[0].authentication.username = "bad:name"' "${TMP_DIR}/valid.json" > "${store_file}.bad"
! validate_structured_instance_store http "${store_file}.bad"
jq '.instances[0].authentication.username = "bad\u0001name"' "${TMP_DIR}/valid.json" > "${store_file}.bad"
! validate_structured_instance_store http "${store_file}.bad"
jq '.instances[0].tls.server_name = "bad\u0001name"' "${TMP_DIR}/valid.json" > "${store_file}.bad"
! validate_structured_instance_store http "${store_file}.bad"
jq '.instances[0].tls.certificate_path = "relative.crt"' "${TMP_DIR}/valid.json" > "${store_file}.bad"
! validate_structured_instance_store http "${store_file}.bad"
jq '.instances[0].authentication.username = ("x" * 4097)' "${TMP_DIR}/valid.json" > "${store_file}.bad"
! validate_structured_instance_store http "${store_file}.bad"

# A stale HTTP TLS value is cleared by the shared runtime reset hook before a
# different structured protocol is loaded.
SB_HTTP_TLS_JSON='{"enabled":true}'
reset_protocol_instance_runtime_fields
[[ -z "${SB_HTTP_TLS_JSON}" ]]

printf 'HTTP structured instance store checks passed\n'
