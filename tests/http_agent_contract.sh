#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/http.json"
cat > "${store_file}" <<'EOF_STORE'
{
  "schema_version": 1,
  "protocol": "http",
  "revision": 4,
  "default_instance_id": "web",
  "instances": [{
    "id": "web",
    "name": "HTTP web",
    "tag": "http-web",
    "listen": {"address": "127.0.0.1", "port": 31808},
    "authentication": {"enabled": true, "username": "web-user", "password": "web-secret"},
    "outbound_policy": "direct",
    "tls": {"enabled": false},
    "dependencies": []
  }]
}
EOF_STORE
chmod 600 "${store_file}"
save_plain_proxy_structured_marker http

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=http
PROTOCOL_STATE_VERSION=1
EOF_INDEX
jq -n --arg port 31808 '{log:{level:"warn"},inbounds:[{type:"http",tag:"http-web",listen:"127.0.0.1",listen_port:($port|tonumber),users:[{username:"web-user",password:"web-secret"}],tls:{enabled:false}}],outbounds:[{type:"direct",tag:"direct"}],route:{rules:[{inbound:"http-web",action:"route",outbound:"direct"}],final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"

agent_validate_indexed_protocol_states $'http\n'
[[ "$(list_protocol_instance_ids http)" == web ]]
[[ "$(protocol_default_instance_id http)" == web ]]
load_protocol_instance_state http web

summary=$(agent_node_summary_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "http" and .shareable == true and .client_exportable == true and
  .auth_enabled == true and .tls_enabled == false and .instance_id == "web" and
  .tag == "http-web" and .listen.address == "127.0.0.1" and .listen.port == 31808 and
  (has("username") | not) and (has("password") | not) and
  (tostring | contains("web-secret") | not) and (tostring | contains("certificate_path") | not)
' <<< "${summary}" >/dev/null

links=$(agent_link_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "http" and (.links | keys) == ["http"] and
  .links.http == "http://web-user:web-secret@127.0.0.1:31808" and
  .instance_id == "web" and .instance_revision == 4 and
  (tostring | contains("certificate_path") | not) and
  (tostring | contains("key_path") | not)
' <<< "${links}" >/dev/null

# HTTP Basic cannot encode a colon in the username.  HTTP has no alternate
# SOCKS transport, so Agent links must fail closed without returning JSON.
SB_MIXED_USERNAME='web:user'
SB_MIXED_PASSWORD='web-secret'
SB_HTTP_TLS_JSON='{"enabled":false}'
if links=$(agent_link_json_for_current_protocol 203.0.113.10); then
  printf 'invalid HTTP Basic credentials unexpectedly produced Agent links: %s\n' "${links}" >&2
  exit 1
fi
load_protocol_instance_state http web

capabilities=$(agent_capabilities_json)
jq -e '
  .features.plain_proxy_instances.protocols | index("http") != null
' <<< "${capabilities}" >/dev/null
jq -e '
  .features.plain_proxy_instances.operations_by_protocol.http ==
    ["create", "replace", "delete", "default", "recover"] and
  (.commands.instance.protocols | index("http") != null)
' <<< "${capabilities}" >/dev/null

invalid_migrate=$(agent_instance_cli migrate http --json --yes --expected-revision 4 2>"${TMP_DIR}/invalid-migrate.stderr" || true)
jq -e '.ok == false and .error == "invalid_arguments"' <<< "${invalid_migrate}" >/dev/null

# TLS-enabled HTTP remains represented as metadata only in read-only Agent
# output; no certificate or key path is exposed and no plaintext URI is made.
jq '.instances[0].tls = {enabled:true,server_name:"proxy.example",certificate_path:"/etc/ssl/proxy.crt",key_path:"/etc/ssl/proxy.key"}' "${store_file}" > "${store_file}.next"
mv "${store_file}.next" "${store_file}"
jq '.inbounds[0].tls = {enabled:true,server_name:"proxy.example",certificate_path:"/etc/ssl/proxy.crt",key_path:"/etc/ssl/proxy.key"}' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
load_protocol_instance_state http web
summary=$(agent_node_summary_json_for_current_protocol 203.0.113.10)
jq -e '.protocol == "http" and .shareable == false and .client_exportable == true and .tls_enabled == true and (tostring | contains("proxy.crt") | not)' <<< "${summary}" >/dev/null
links=$(agent_link_json_for_current_protocol 203.0.113.10)
jq -e '.protocol == "http" and (.links | length) == 0 and
  any(.warnings[]?; .code == "http_tls_uri_unrepresentable") and
  (tostring | contains("proxy.crt") | not)' <<< "${links}" >/dev/null

printf 'HTTP Agent contract checks passed\n'
