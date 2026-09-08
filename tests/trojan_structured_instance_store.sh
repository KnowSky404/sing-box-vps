#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 122
# Source at file scope so Bash 4.2 retains readonly protocol registry arrays.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "Trojan structured store failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/trojan.json"
state_file="${SB_PROTOCOL_STATE_DIR}/trojan.env"
cert_file="${TMP_DIR}/trojan.crt"
key_file="${TMP_DIR}/trojan.key"
printf '%s\n' 'certificate fixture' > "${cert_file}"
printf '%s\n' 'key fixture' > "${key_file}"

cat > "${state_file}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE

jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {
    schema_version: 1,
    protocol: "trojan",
    revision: 7,
    default_instance_id: "trojan-ws",
    instances: [
      {
        id: "trojan-none",
        name: "Trojan native",
        tag: "trojan-none",
        listen: {address: "127.0.0.1", port: 33401},
        authentication: {users: [{name: "native-user", password: "native-password"}]},
        tls: {enabled: false},
        client_trust: "system",
        transport: {type: "none"},
        outbound_policy: "default",
        dependencies: []
      },
      {
        id: "trojan-ws",
        name: "Trojan WebSocket",
        tag: "trojan-ws",
        listen: {address: "0.0.0.0", port: 33402},
        authentication: {users: [
          {name: "ws-user", password: "ws-password"},
          {name: "ws-second", password: "ws-second-password"}
        ]},
        tls: {enabled: true, server_name: "trojan.example", certificate_path: $cert, key_path: $key},
        client_trust: "certificate",
        transport: {type: "ws", path: "/trojan", headers: {Host: "trojan.example"}},
        outbound_policy: "direct",
        dependencies: []
      },
      {
        id: "trojan-quic",
        name: "Trojan QUIC",
        tag: "trojan-quic",
        listen: {address: "127.0.0.1", port: 33402},
        authentication: {users: [{name: "quic-user", password: "quic-password"}]},
        tls: {enabled: true, server_name: "quic.example", certificate_path: $cert, key_path: $key},
        client_trust: "certificate",
        transport: {type: "quic"},
        outbound_policy: "warp",
        dependencies: []
      }
    ]
  }
' > "${store_file}"
chmod 600 "${store_file}" "${state_file}"

[[ "$(structured_instance_store_protocol trojan)" == trojan ]]
validate_structured_instance_store trojan "${store_file}"
plain_proxy_structured_state_active trojan
[[ "$(list_protocol_instance_ids trojan)" == $'trojan-none\ntrojan-ws\ntrojan-quic' ]]
[[ "$(protocol_default_instance_id trojan)" == trojan-ws ]]

load_plain_proxy_structured_instance trojan trojan-ws
[[ "${SB_PROTOCOL}" == trojan && "${SB_INSTANCE_ID}" == trojan-ws ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 && "${SB_PORT}" == 33402 ]]
jq -e 'length == 2 and .[0].name == "ws-user"' <<< "${SB_TROJAN_AUTH_JSON}" >/dev/null
jq -e '.type == "ws" and .path == "/trojan" and .headers.Host == "trojan.example"' \
  <<< "${SB_TROJAN_TRANSPORT_JSON}" >/dev/null
jq -e '.enabled == true and .server_name == "trojan.example"' <<< "${SB_TROJAN_TLS_JSON}" >/dev/null

rendered=$(render_structured_instance_inbounds trojan "${store_file}" | jq -s .)
jq -e --arg cert "${cert_file}" --arg key "${key_file}" '
  length == 3 and
  any(.[]; .type == "trojan" and .tag == "trojan-none" and
    (.tls // {enabled:false}).enabled == false and .transport == null and (.users|length) == 1) and
  any(.[]; .tag == "trojan-ws" and .tls.enabled == true and
    .tls.certificate_path == $cert and .tls.key_path == $key and
    .transport.type == "ws" and .transport.path == "/trojan" and (.users|length) == 2) and
  any(.[]; .tag == "trojan-quic" and .transport.type == "quic")
' <<< "${rendered}" >/dev/null

route_json=$(render_structured_instance_route_rules trojan "${store_file}")
jq -e 'length == 5 and any(.[]; .inbound == "trojan-ws" and .outbound == "direct") and
  any(.[]; .inbound == "trojan-quic" and .outbound == "warp-ep")' <<< "${route_json}" >/dev/null

jq -c '.instances[1]' "${store_file}" > "${TMP_DIR}/trojan-instance.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/trojan-instance.json" trojan

reject_instance() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${TMP_DIR}/trojan-instance.json" > "${invalid_file}"
  if structured_instance_store_validate_instance_argument "${invalid_file}" trojan; then
    printf 'accepted invalid Trojan instance: %s\n' "${label}" >&2
    return 1
  fi
}

reject_store() {
  local label=$1 expression=$2 invalid_file="${TMP_DIR}/${1}.json"
  jq "${expression}" "${store_file}" > "${invalid_file}"
  if validate_structured_instance_store trojan "${invalid_file}"; then
    printf 'accepted invalid Trojan store: %s\n' "${label}" >&2
    return 1
  fi
}

# Trojan user names are opaque identifiers, not HTTP Basic-auth usernames;
# colons are therefore valid as long as control/length constraints hold.
jq '.authentication.users[0].name = "good:name"' "${TMP_DIR}/trojan-instance.json" > "${TMP_DIR}/colon-name.json"
structured_instance_store_validate_instance_argument "${TMP_DIR}/colon-name.json" trojan
reject_instance bad_password_nul '.authentication.users[0].password = "bad\u0000password"'
reject_instance bad_password_too_large '.authentication.users[0].password = ("x" * 4097)'
reject_instance missing_tls '.tls = null'
reject_instance invalid_client_trust '.client_trust = "acme"'
reject_instance plaintext_certificate_trust '.tls = {enabled:false} | .client_trust = "certificate"'
reject_instance relative_certificate '.tls.certificate_path = "relative.crt"'
reject_instance unknown_transport_field '.transport.extra = "reject"'
reject_instance httpupgrade_transport '.transport = {type:"httpupgrade",path:"/upgrade"}'
reject_instance ws_early_data '.transport = {type:"ws",path:"/trojan",max_early_data:1,early_data_header_name:"X-Early-Data"}'

reject_store duplicate_usernames '.instances[1].authentication.users[1].name = "ws-user"'
reject_store same_transport_collision '.instances[2].transport = {type:"ws",path:"/trojan",headers:{Host:"trojan.example"}}'
reject_store unknown_record_field '.instances[0].unknown = true'
reject_store invalid_transport '.instances[0].transport = {type:"unsupported"}'
reject_store quic_without_tls '.instances[2].tls = {enabled:false} | .instances[2].client_trust = "system"'
reject_store plaintext_certificate_trust '.instances[0].client_trust = "certificate"'
reject_store tls_unknown_field '.instances[1].tls.provider = "acme"'

# The complete typed inventory can be collected back from a representative
# live config without losing TLS, users, transport, or canonical network.
jq '{inbounds: [.instances[] | {
  type:"trojan",tag:.tag,listen:.listen.address,listen_port:.listen.port,
  users:.authentication.users,tls:.tls,transport:(if .transport.type == "none" then null else .transport end)
}], outbounds:[{type:"direct",tag:"direct"}], route:{rules:[
  {inbound:"trojan-none",action:"sniff"},
  {inbound:"trojan-ws",action:"route",outbound:"direct"},
  {inbound:"trojan-quic",action:"route",outbound:"warp-ep"}
],final:"direct"}}' "${store_file}" > "${SINGBOX_CONFIG_FILE}"
candidate=$(plain_proxy_config_store_candidate trojan)
jq -e --arg cert "${cert_file}" --arg key "${key_file}" '
  .protocol == "trojan" and .revision == 7 and .default_instance_id == "trojan-ws" and
  any(.instances[]; .tag == "trojan-none" and .client_trust == "system") and
  any(.instances[]; .tag == "trojan-ws" and .tls.certificate_path == $cert and
    .client_trust == "certificate" and .transport.type == "ws" and (.authentication.users|length) == 2) and
  any(.instances[]; .tag == "trojan-quic" and .client_trust == "certificate" and .transport.type == "quic")
' <<< "${candidate}" >/dev/null

cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/trojan-config-before-unknown.json"
jq '.inbounds[1].unknown_option = true' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/trojan-config-unknown.json"
mv "${TMP_DIR}/trojan-config-unknown.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate trojan >/dev/null 2>&1; then
  printf 'accepted unsupported Trojan live field\n' >&2
  exit 1
fi
mv "${TMP_DIR}/trojan-config-before-unknown.json" "${SINGBOX_CONFIG_FILE}"

printf 'Trojan structured instance store checks passed\n'
