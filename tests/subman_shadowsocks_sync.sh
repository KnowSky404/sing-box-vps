#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "Shadowsocks SubMan sync failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
state_file="${SB_PROTOCOL_STATE_DIR}/shadowsocks.env"
cat > "${state_file}" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
EOF_STATE

jq -n '
  {
    schema_version: 1,
    protocol: "shadowsocks",
    revision: 4,
    default_instance_id: "ss-multi",
    instances: [
      {
        id: "ss-multi",
        name: "SS multi",
        tag: "ss-multi",
        listen: {address: "127.0.0.1", port: 33801, network: ["tcp", "udp"]},
        authentication: {method: "aes-128-gcm", password: "", users: [
          {name: "alice", password: "alice-secret"},
          {name: "bob", password: "bob-secret"}
        ]},
        outbound_policy: "default",
        dependencies: []
      },
      {
        id: "ss-single",
        name: "SS single",
        tag: "ss-single",
        listen: {address: "127.0.0.1", port: 33802, network: ["tcp"]},
        authentication: {method: "aes-256-gcm", password: "server-secret", users: []},
        outbound_policy: "direct",
        dependencies: []
      },
      {
        id: "ss-none",
        name: "SS none",
        tag: "ss-none",
        listen: {address: "127.0.0.1", port: 33803, network: ["tcp", "udp"]},
        authentication: {method: "none", password: "", users: []},
        outbound_policy: "default",
        dependencies: []
      }
    ]
  }
' > "${store_file}"
chmod 600 "${state_file}" "${store_file}"
save_plain_proxy_structured_marker shadowsocks

load_protocol_instance_state ss ss-multi
specific_addresses=$(list_subman_addresses_for_current_protocol)
[[ "${specific_addresses}" == '监听地址|127.0.0.1' ]]

# Keep subsequent pushes deterministic and avoid consulting the host's public
# address inventory; production sync uses the existing discovery helper.
list_subman_addresses_for_current_protocol() {
  printf 'test-address|198.51.100.20\n'
}

SUBMAN_NODE_PREFIX="sync-test"
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_node() {
  MOCK_KEYS+=("${1}")
  MOCK_PAYLOADS+=("${2}")
  return 0
}
LEGACY_CLEANUP_CALLS=0
LEGACY_DELETE_CALLS=0
push_subman_legacy_protocol_key_cleanup() {
  LEGACY_CLEANUP_CALLS=$((LEGACY_CLEANUP_CALLS + 1))
  return 1
}
delete_subman_node_by_external_key() {
  LEGACY_DELETE_CALLS=$((LEGACY_DELETE_CALLS + 1))
  return 1
}

push_subman_shadowsocks_protocol y
[[ "${SUBMAN_SHADOWSOCKS_SYNCED}" == 2 ]]
[[ "${SUBMAN_SHADOWSOCKS_SKIPPED}" == 2 ]]
[[ "${SUBMAN_SHADOWSOCKS_FAILED}" == 0 ]]
jq -e 'any(.[]; .code == "shadowsocks_subman_none_unsupported")' \
  <<< "${SUBMAN_SHADOWSOCKS_WARNINGS_JSON}" >/dev/null
[[ "${LEGACY_CLEANUP_CALLS}" == 0 && "${LEGACY_DELETE_CALLS}" == 0 ]]
[[ ${#MOCK_KEYS[@]} -eq 2 ]]
[[ "$(printf '%s\n' "${MOCK_KEYS[@]}" | sort | uniq | wc -l | tr -d '[:space:]')" == 2 ]]
! printf '%s\n' "${MOCK_KEYS[@]}" | grep -Fq 'ss-none:'

# A direct instance push must use the concrete listen address from its private
# snapshot, even when its caller supplied a stale/public address.
MOCK_KEYS=(); MOCK_PAYLOADS=()
push_subman_shadowsocks_instance ss-multi 203.0.113.99 y
[[ ${#MOCK_PAYLOADS[@]} -eq 2 ]]
for payload in "${MOCK_PAYLOADS[@]}"; do
  [[ "$(jq -r '.raw' <<< "${payload}")" == *'@127.0.0.1:33801'* ]]
done

alice_digest=$(printf 'alice' | sha256sum); alice_digest=${alice_digest%% *}
bob_digest=$(printf 'bob' | sha256sum); bob_digest=${bob_digest%% *}
[[ "$(printf '%s\n' "${MOCK_KEYS[@]}" | grep -F "ss-multi:user-${alice_digest}" | wc -l | tr -d '[:space:]')" == 1 ]]
[[ "$(printf '%s\n' "${MOCK_KEYS[@]}" | grep -F "ss-multi:user-${bob_digest}" | wc -l | tr -d '[:space:]')" == 1 ]]
! printf '%s\n' "${MOCK_KEYS[@]}" | grep -Eq 'alice|bob'
for payload in "${MOCK_PAYLOADS[@]}"; do
  jq -e '.type == "ss" and .source == "single" and .enabled == true and (.raw | startswith("ss://"))' \
    <<< "${payload}" >/dev/null
done

# Simulate a live-store user reorder immediately after the private snapshot is
# captured. Outbound credentials and usernames must still come from that same
# snapshot, never from a second live-store read.
eval "$(declare -f structured_instance_store_snapshot_json | sed '1s/^structured_instance_store_snapshot_json /original_structured_instance_store_snapshot_json /')"
structured_instance_store_snapshot_json() {
  local captured
  captured=$(original_structured_instance_store_snapshot_json "$@") || return 1
  jq '.instances |= map(if .id == "ss-multi" then .authentication.users |= reverse else . end)' \
    "${store_file}" > "${store_file}.race"
  mv "${store_file}.race" "${store_file}"
  printf '%s\n' "${captured}"
}
MOCK_KEYS=(); MOCK_PAYLOADS=()
push_subman_shadowsocks_instance ss-multi 198.51.100.20 y
alice_fragment=$(printf 'aes-128-gcm:alice-secret' | base64 | tr '+/' '-_' | sed 's/=*$//')
bob_fragment=$(printf 'aes-128-gcm:bob-secret' | base64 | tr '+/' '-_' | sed 's/=*$//')
alice_payload=""
bob_payload=""
for index in "${!MOCK_KEYS[@]}"; do
  if [[ "${MOCK_KEYS[${index}]}" == *"user-${alice_digest}"* ]]; then
    alice_payload=${MOCK_PAYLOADS[${index}]}
  elif [[ "${MOCK_KEYS[${index}]}" == *"user-${bob_digest}"* ]]; then
    bob_payload=${MOCK_PAYLOADS[${index}]}
  fi
done
[[ "$(jq -r '.raw' <<< "${alice_payload}")" == *"${alice_fragment}"* ]]
[[ "$(jq -r '.raw' <<< "${bob_payload}")" == *"${bob_fragment}"* ]]
eval "$(declare -f original_structured_instance_store_snapshot_json | sed '1s/^original_structured_instance_store_snapshot_json /structured_instance_store_snapshot_json /')"

# Reordering users does not alter their resource keys.
before_multi_keys=$(printf '%s\n' "${MOCK_KEYS[@]}" | grep 'ss-multi:' | sort)
jq '.instances |= map(if .id == "ss-multi" then .authentication.users |= reverse else . end)' \
  "${store_file}" > "${TMP_DIR}/reordered.json"
mv "${TMP_DIR}/reordered.json" "${store_file}"
MOCK_KEYS=(); MOCK_PAYLOADS=()
push_subman_shadowsocks_instance ss-multi 127.0.0.1 y
after_multi_keys=$(printf '%s\n' "${MOCK_KEYS[@]}" | sort)
[[ "${before_multi_keys}" == "${after_multi_keys}" ]]

# A failed outbound producer must fail the instance as a whole; process
# substitution must not turn its non-zero status into a successful empty sync.
eval "$(declare -f build_shadowsocks_client_outbounds_from_store | sed '1s/^build_shadowsocks_client_outbounds_from_store /original_build_shadowsocks_client_outbounds_from_store /')"
build_shadowsocks_client_outbounds_from_store() {
  return 73
}
MOCK_KEYS=(); MOCK_PAYLOADS=()
! push_subman_shadowsocks_instance ss-multi 198.51.100.20 y
[[ "${SUBMAN_SHADOWSOCKS_SYNCED}" == 0 && "${SUBMAN_SHADOWSOCKS_FAILED}" == 1 ]]
eval "$(declare -f original_build_shadowsocks_client_outbounds_from_store | sed '1s/^original_build_shadowsocks_client_outbounds_from_store /build_shadowsocks_client_outbounds_from_store /')"

# A single-user API failure is isolated from its sibling and counted as failed.
push_subman_node() {
  MOCK_KEYS+=("${1}")
  MOCK_PAYLOADS+=("${2}")
  if [[ "${1}" == *"user-${bob_digest}"* ]]; then
    SUBMAN_LAST_ERROR_CODE="mock_failure"
    SUBMAN_LAST_ERROR_DISPOSITION="retryable-upstream"
    return 1
  fi
  return 0
}
MOCK_KEYS=(); MOCK_PAYLOADS=()
! push_subman_shadowsocks_instance ss-multi 127.0.0.1 y
[[ "${SUBMAN_SHADOWSOCKS_SYNCED}" == 1 && "${SUBMAN_SHADOWSOCKS_FAILED}" == 1 && "${SUBMAN_SHADOWSOCKS_SKIPPED}" == 0 ]]

printf 'Shadowsocks SubMan sync checks passed: synced=2 skipped=2 stable-user-keys=2\n'
