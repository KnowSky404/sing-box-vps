#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 122
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "Shadowsocks structured store failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
state_file="${SB_PROTOCOL_STATE_DIR}/shadowsocks.env"
ss_key_128='AAAAAAAAAAAAAAAAAAAAAA=='
ss_key_128_user='AQEBAQEBAQEBAQEBAQEBAQ=='
ss_key_256='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
ss_key_256_user='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='

[[ ${#ss_key_128} -eq 24 && ${#ss_key_128_user} -eq 24 ]]
[[ ${#ss_key_256} -eq 44 && ${#ss_key_256_user} -eq 44 ]]

cat > "${state_file}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE
jq -n \
  --arg key128 "${ss_key_128}" \
  --arg key128_user "${ss_key_128_user}" \
  --arg key256 "${ss_key_256}" \
  --arg key256_user "${ss_key_256_user}" \
  '{
    schema_version: 1,
    protocol: "shadowsocks",
    revision: 0,
    default_instance_id: "ss-single",
    instances: [
      {
        id: "ss-single",
        name: "SS single",
        tag: "ss-single",
        listen: {address: "127.0.0.1", port: 33201, network: ["tcp"]},
        authentication: {method: "aes-256-gcm", password: "classic-password", users: []},
        outbound_policy: "default",
        dependencies: []
      },
      {
        id: "ss-multi",
        name: "SS classic multi",
        tag: "ss-multi",
        listen: {address: "127.0.0.1", port: 33201, network: ["udp"]},
        authentication: {method: "chacha20-ietf-poly1305", password: "", users: [
          {name: "alice", password: "alice-password"},
          {name: "bob", password: "bob-password"}
        ]},
        outbound_policy: "direct",
        dependencies: []
      },
      {
        id: "ss-2022",
        name: "SS 2022 multi",
        tag: "ss-2022",
        listen: {address: "127.0.0.1", port: 33202, network: ["tcp", "udp"]},
        authentication: {method: "2022-blake3-aes-128-gcm", password: $key128, users: [
          {name: "2022-user", password: $key128_user}
        ]},
        outbound_policy: "warp",
        dependencies: []
      }
    ]
  }' > "${store_file}"
chmod 600 "${store_file}" "${state_file}"

[[ "$(structured_instance_store_protocol ss)" == shadowsocks ]]
[[ "$(structured_instance_store_protocol shadowsocks)" == shadowsocks ]]
validate_structured_instance_store ss "${store_file}"
plain_proxy_structured_state_active shadowsocks
[[ "$(list_protocol_instance_ids ss)" == $'ss-single\nss-multi\nss-2022' ]]
[[ "$(protocol_default_instance_id ss)" == ss-single ]]

load_protocol_instance_state ss ss-2022
[[ "${SB_PROTOCOL}" == shadowsocks && "${SB_INSTANCE_ID}" == ss-2022 ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 127.0.0.1 && "${SB_PORT}" == 33202 ]]
jq -e --arg key "${ss_key_128}" \
  '.method == "2022-blake3-aes-128-gcm" and .password == $key and (.users | length) == 1' \
  <<< "${SB_SHADOWSOCKS_AUTH_JSON}" >/dev/null
[[ "${SB_SHADOWSOCKS_NETWORK_JSON}" == '["tcp","udp"]' ]]

rendered=$(render_structured_instance_inbounds shadowsocks "${store_file}" | jq -s .)
jq -e --arg key "${ss_key_128}" '
  length == 3 and
  any(.[]; .type == "shadowsocks" and .tag == "ss-single" and
    .method == "aes-256-gcm" and .password == "classic-password" and .network == ["tcp"] and (.users | length) == 0) and
  any(.[]; .tag == "ss-multi" and .method == "chacha20-ietf-poly1305" and
    .password == "" and .network == ["udp"] and (.users | length) == 2) and
  any(.[]; .tag == "ss-2022" and .method == "2022-blake3-aes-128-gcm" and
    .password == $key and .network == ["tcp", "udp"] and .users[0].name == "2022-user")
' <<< "${rendered}" >/dev/null

# Exercise every supported cipher family: five classic single-user methods,
# both 2022 AES methods, and the 2022 ChaCha single-user form.
for classic_method in aes-128-gcm aes-192-gcm aes-256-gcm chacha20-ietf-poly1305 xchacha20-ietf-poly1305; do
  jq --arg method "${classic_method}" \
    '.instances[0].authentication = {method:$method,password:"classic-password",users:[]}' \
    "${store_file}" > "${TMP_DIR}/valid-${classic_method}.json"
  validate_structured_instance_store ss "${TMP_DIR}/valid-${classic_method}.json"
done
jq '.instances[0].authentication = {method:"none",password:"",users:[]}' \
  "${store_file}" > "${TMP_DIR}/valid-none.json"
validate_structured_instance_store ss "${TMP_DIR}/valid-none.json"
jq --arg key "${ss_key_256}" --arg user_key "${ss_key_256_user}" \
  '.instances[2].authentication = {method:"2022-blake3-aes-256-gcm",password:$key,users:[{name:"2022-user",password:$user_key}]}' \
  "${store_file}" > "${TMP_DIR}/valid-2022-aes-256.json"
validate_structured_instance_store ss "${TMP_DIR}/valid-2022-aes-256.json"
jq --arg key "${ss_key_256}" \
  '.instances[2].authentication = {method:"2022-blake3-chacha20-poly1305",password:$key,users:[]}' \
  "${store_file}" > "${TMP_DIR}/valid-2022-chacha-single.json"
validate_structured_instance_store ss "${TMP_DIR}/valid-2022-chacha-single.json"

# A TCP and UDP listener may share a port, while two listeners using the same
# transport/address/port must be rejected by the shared listener validator.
jq '{inbounds: .}' <<< "${rendered}" > "${SINGBOX_CONFIG_FILE}"
candidate=$(plain_proxy_config_store_candidate ss)
jq -e '.protocol == "shadowsocks" and (.instances | length) == 3 and
  any(.instances[]; .tag == "ss-2022" and .listen.network == ["tcp", "udp"])' \
  <<< "${candidate}" >/dev/null

reject_store() {
  local label expression invalid_file output_file
  label=$1
  expression=$2
  invalid_file="${TMP_DIR}/${label}.json"
  output_file="${TMP_DIR}/${label}.out"
  jq "${expression}" "${store_file}" > "${invalid_file}"
  if validate_structured_instance_store ss "${invalid_file}" > "${output_file}" 2> "${output_file}.err"; then
    printf 'accepted invalid Shadowsocks store: %s\n' "${label}" >&2
    return 1
  fi
  [[ ! -s "${output_file}" ]]
}

reject_store invalid_method '.instances[0].authentication.method = "unsupported-cipher"'
reject_store invalid_2022_server_key '.instances[2].authentication.password = "not-a-2022-key"'
reject_store invalid_2022_user_key '.instances[2].authentication.users[0].password = "not-a-2022-key"'
reject_store unknown_auth_field '.instances[0].authentication.extra = "must-not-pass"'
reject_store unknown_record_field '.instances[0].arbitrary_json = {passthrough: true}'
reject_store invalid_network '.instances[0].listen.network = ["sctp"]'
reject_store unsorted_network '.instances[0].listen.network = ["udp", "tcp"]'
reject_store none_with_password '.instances[0].authentication = {method:"none",password:"unexpected",users:[]}'
reject_store 2022_chacha_users '.instances[2].authentication = {method:"2022-blake3-chacha20-poly1305",password:"'"${ss_key_256}"'",users:[{name:"user",password:"'"${ss_key_256_user}"'"}]}'
reject_store same_transport_conflict '.instances[1].listen.network = ["tcp"]'

# Do not accept an arbitrary live endpoint or silently flatten unsupported
# Shadowsocks fields during takeover extraction.
cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/ss-config-before-negative.json"
jq '.inbounds[0].unsupported_option = true' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/ss-config-unknown.json"
mv "${TMP_DIR}/ss-config-unknown.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate ss > "${TMP_DIR}/unknown.out" 2> "${TMP_DIR}/unknown.err"; then
  printf 'accepted unsupported Shadowsocks live field\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/unknown.out" ]]
cp -p "${TMP_DIR}/ss-config-before-negative.json" "${SINGBOX_CONFIG_FILE}"

jq '.inbounds[0].method = "unsupported-cipher"' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/ss-config-method.json"
mv "${TMP_DIR}/ss-config-method.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate ss > "${TMP_DIR}/method.out" 2> "${TMP_DIR}/method.err"; then
  printf 'accepted unsupported Shadowsocks live method\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/method.out" ]]

printf 'Shadowsocks structured instance store checks passed\n'
