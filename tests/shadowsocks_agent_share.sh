#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 122
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
state_file="${SB_PROTOCOL_STATE_DIR}/shadowsocks.env"
key_128='AAAAAAAAAAAAAAAAAAAAAA=='
user_key_128='AQEBAQEBAQEBAQEBAQEBAQ=='

cat > "${state_file}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE
jq -n \
  --arg key "${key_128}" \
  --arg user_key "${user_key_128}" \
  ' {
    schema_version: 1,
    protocol: "shadowsocks",
    revision: 7,
    default_instance_id: "ss-classic",
    instances: [
      {
        id: "ss-single",
        name: "SS none",
        tag: "ss-single",
        listen: {address: "127.0.0.1", port: 33201, network: ["tcp"]},
        authentication: {method: "none", password: "", users: []},
        outbound_policy: "default",
        dependencies: []
      },
      {
        id: "ss-classic",
        name: "SS classic multi",
        tag: "ss-classic",
        listen: {address: "::1", port: 33203, network: ["udp"]},
        authentication: {method: "chacha20-ietf-poly1305", password: "", users: [
          {name: "alice", password: "päss word@/?:%"},
          {name: "bob", password: "二号%"}
        ]},
        outbound_policy: "direct",
        dependencies: []
      },
      {
        id: "ss-2022",
        name: "SS 2022 multi",
        tag: "ss-2022",
        listen: {address: "::1", port: 33202, network: ["tcp", "udp"]},
        authentication: {method: "2022-blake3-aes-128-gcm", password: $key, users: [
          {name: "2022-user", password: $user_key}
        ]},
        outbound_policy: "warp",
        dependencies: []
      }
    ]
  }' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"

load_protocol_instance_state shadowsocks ss-classic
summary=$(agent_node_summary_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "shadowsocks" and .instance_id == "ss-classic" and
  .method == "chacha20-ietf-poly1305" and .user_count == 2 and
  .auth_enabled == true and .listen.network == ["udp"] and
  .instance_revision == 7 and .shareable == true and
  .client_exportable == true and
  (tostring | contains("päss word@/?:%") | not) and
  (tostring | contains("alice") | not) and
  (tostring | contains("password") | not) and
  (tostring | contains("users") | not)
' <<< "${summary}" >/dev/null

classic_alice_payload=$(printf '%s' 'chacha20-ietf-poly1305:päss word@/?:%' | base64 -w0 | tr '+/' '-_' | sed 's/=*$//')
classic_bob_payload=$(printf '%s' 'chacha20-ietf-poly1305:二号%' | base64 -w0 | tr '+/' '-_' | sed 's/=*$//')
classic_links=$(agent_link_json_for_current_protocol '2001:db8::10')
jq -e --arg alice "ss://${classic_alice_payload}@[::1]:33203#" \
  --arg bob "ss://${classic_bob_payload}@[::1]:33203#" '
  .protocol == "shadowsocks" and (.links | length) == 2 and (.outbounds | length) == 2 and
  any(.links[]; startswith($alice)) and any(.links[]; startswith($bob)) and
  any(.warnings[]?; .code == "shadowsocks_uri_network_omitted")
' <<< "${classic_links}" >/dev/null

load_protocol_instance_state shadowsocks ss-2022
ss2022_userinfo=$(jq -rn --arg method '2022-blake3-aes-128-gcm' \
  --arg password "${key_128}:${user_key_128}" \
  '($method | @uri) + ":" + ($password | @uri)')
ss2022_links=$(agent_link_json_for_current_protocol '2001:db8::10')
jq -e --arg expected "ss://${ss2022_userinfo}@[::1]:33202#" '
  .protocol == "shadowsocks" and (.links | length) == 1 and (.outbounds | length) == 1 and
  any(.links[]; startswith($expected) and contains("%3A") and contains("%3D")) and
  (any(.warnings[]?; .code == "shadowsocks_uri_network_omitted") | not)
' <<< "${ss2022_links}" >/dev/null

load_protocol_instance_state shadowsocks ss-single
none_summary=$(agent_node_summary_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "shadowsocks" and .auth_enabled == false and .user_count == 1 and
  .listen.network == ["tcp"] and .shareable == true and .client_exportable == true
' <<< "${none_summary}" >/dev/null
none_links=$(agent_link_json_for_current_protocol '2001:db8::10')
jq -e '
  .protocol == "shadowsocks" and (.links | length) == 1 and (.outbounds | length) == 1 and
  any(.links[]; contains("@127.0.0.1:33201") and (contains("2001:db8") | not)) and
  any(.warnings[]?; .code == "shadowsocks_uri_network_omitted") and
  any(.warnings[]?; .code == "shadowsocks_plaintext_transport")
' <<< "${none_links}" >/dev/null

baseline_store=$(<"${store_file}")
build_shadowsocks_links_json() {
  jq '.revision += 1 | .instances[0].name = "raced store"' "${store_file}" > "${store_file}.race"
  mv "${store_file}.race" "${store_file}"
  printf '%s\n' '{"mock":"ss://race"}'
}
if raced_links=$(agent_shadowsocks_link_json '2001:db8::10'); then
  printf 'Shadowsocks Agent links accepted a concurrent store revision\n' >&2
  exit 1
fi
[[ -z "${raced_links}" ]]
unset -f build_shadowsocks_links_json
printf '%s\n' "${baseline_store}" > "${store_file}"
chmod 600 "${store_file}"
load_protocol_instance_state shadowsocks ss-single

full_export_warnings=$(collect_client_export_warnings_json '{"outbounds":[{"type":"shadowsocks","method":"none"}]}' )
jq -e '
  any(.[]; .code == "shadowsocks_plaintext_transport") and
  (any(.[]; .code == "shadowsocks_uri_network_omitted") | not)
' <<< "${full_export_warnings}" >/dev/null

SB_SHADOWSOCKS_NETWORK_JSON='["tcp","udp"]'
SB_SHADOWSOCKS_AUTH_JSON=$(jq -cn --arg method '2022-blake3-aes-128-gcm' --arg password "${key_128}" \
  '{method:$method,password:$password,users:[]}')
ss2022_warnings=$(shadowsocks_share_warnings_json)
jq -e 'any(.[]; .code == "shadowsocks_2022_psk_derived") | not' <<< "${ss2022_warnings}" >/dev/null
long_psk='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=='
SB_SHADOWSOCKS_AUTH_JSON=$(jq -cn --arg method '2022-blake3-aes-128-gcm' --arg password "${long_psk}" \
  '{method:$method,password:$password,users:[]}')
ss2022_warnings=$(shadowsocks_share_warnings_json)
jq -e 'any(.[]; .code == "shadowsocks_2022_psk_derived")' <<< "${ss2022_warnings}" >/dev/null
load_protocol_instance_state shadowsocks ss-single

invalid_migrate=$(agent_instance_cli migrate shadowsocks --json --yes --expected-revision 7 2>"${TMP_DIR}/invalid-migrate.stderr" || true)
jq -e '.ok == false and .error == "invalid_arguments"' <<< "${invalid_migrate}" >/dev/null
invalid_migrate_alias=$(agent_instance_cli migrate ss --json --yes --expected-revision 7 2>"${TMP_DIR}/invalid-migrate-alias.stderr" || true)
jq -e '.ok == false and .error == "invalid_arguments"' <<< "${invalid_migrate_alias}" >/dev/null

capabilities=$(agent_capabilities_json)
jq -e '
  (.features.plain_proxy_instances.protocols | index("shadowsocks")) != null and
  .features.plain_proxy_instances.operations_by_protocol.shadowsocks ==
    ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"] and
  (.commands.instance.protocols | index("shadowsocks")) != null
' <<< "${capabilities}" >/dev/null

printf 'Shadowsocks Agent/share checks passed\n'
