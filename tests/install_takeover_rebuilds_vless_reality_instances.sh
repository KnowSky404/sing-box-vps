#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

write_config() {
  case "$1" in
    valid)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443,
      "users": [{"name": "main", "uuid": "11111111-1111-4111-8111-111111111111"}],
      "tls": {
        "enabled": true,
        "server_name": "main.example.com",
        "reality": {
          "enabled": true,
          "private_key": "shared-private-key",
          "short_id": ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"]
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-second",
      "listen_port": 8443,
      "users": [{"name": "second", "uuid": "22222222-2222-4222-8222-222222222222"}],
      "tls": {
        "enabled": true,
        "server_name": "second.example.com",
        "alpn": ["http/1.1"],
        "reality": {
          "enabled": true,
          "private_key": "shared-private-key",
          "short_id": ["cccccccccccccccc"]
        }
      },
      "tcp_fast_open": true
    }
  ],
  "route": {"rules": []}
}
EOF
      ;;
    duplicate-id)
      sed 's/vless-reality-second/vless-reality-main/' "${SINGBOX_CONFIG_FILE}.valid" > "${SINGBOX_CONFIG_FILE}"
      ;;
    different-private-key)
      awk 'BEGIN { key_count = 0 } /"private_key": "shared-private-key"/ { key_count++; if (key_count == 2) sub("shared-private-key", "other-private-key") } { print }' \
        "${SINGBOX_CONFIG_FILE}.valid" > "${SINGBOX_CONFIG_FILE}"
      ;;
    malformed-tag-valid-user)
      sed 's/vless-reality-second/vless-reality-BAD_TAG/' "${SINGBOX_CONFIG_FILE}.valid" > "${SINGBOX_CONFIG_FILE}"
      ;;
    provider-failure)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen_port": 1080,
      "users": [{"username": "mixed-user", "password": "mixed-pass"}]
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen_port": 8443,
      "users": [{"name": "hy2-user", "password": "hy2-pass"}],
      "tls": {
        "server_name": "hy2.example.com",
        "certificate_provider": "missing-provider"
      }
    }
  ],
  "route": {"rules": []}
}
EOF
      ;;
    *)
      printf 'unknown fixture: %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

state_tree_hash() {
  if [[ ! -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    printf 'missing\n'
    return 0
  fi
  (
    cd "${SB_PROTOCOL_STATE_DIR}"
    find . -type f -print0 | sort -z | xargs -0 sha256sum
  ) | sha256sum
}

write_original_state_tree() {
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
  cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,mixed
PROTOCOL_STATE_VERSION=1
EOF
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=old-private-key
REALITY_PUBLIC_KEY=old-public-key
EOF
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
INBOUND_TAG=vless-in
ENABLED=1
NODE_NAME=old-main
PORT=443
UUID=old-uuid
SNI=old.example.com
SHORT_ID_1=old-short-1
SHORT_ID_2=old-short-2
EOF
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stale.env" <<'EOF'
INSTANCE_ID=stale
ENABLED=1
NODE_NAME=stale
EOF
  cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=old-mixed
PORT=1080
AUTH_ENABLED=y
USERNAME=old-user
PASSWORD=old-pass
EOF
}

write_config valid
cp "${SINGBOX_CONFIG_FILE}" "${SINGBOX_CONFIG_FILE}.valid"
cat > "${SB_KEY_FILE}" <<'EOF'
PRIVATE_KEY=stale-private-key
PUBLIC_KEY=stale-public-key
EOF
write_original_state_tree

if ! rebuild_protocol_state_from_config; then
  printf 'expected two VLESS REALITY inbounds to rebuild successfully\n' >&2
  exit 1
fi

grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' "${SB_PROTOCOL_INDEX_FILE}"
grep -Fqx 'DEFAULT_INSTANCE_ID=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fqx 'INSTANCE_IDS=main,second' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fqx 'REALITY_PRIVATE_KEY=shared-private-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fqx "REALITY_PUBLIC_KEY=''" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fqx 'INBOUND_TAG=vless-in' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
grep -Fqx 'PORT=443' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
grep -Fqx 'UUID=11111111-1111-4111-8111-111111111111' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
grep -Fqx 'INBOUND_TAG=vless-reality-second' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
grep -Fqx 'PORT=8443' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
grep -Fqx 'UUID=22222222-2222-4222-8222-222222222222' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
grep -Fqx 'ALPN_MODE=http1' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
grep -Fqx 'TCP_FAST_OPEN=y' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stale.env" ]]
protocol_state_layer_matches_config

write_original_state_tree
write_config malformed-tag-valid-user
if ! rebuild_protocol_state_from_config; then
  printf 'expected malformed VLESS tag to fall back to a valid user name\n' >&2
  exit 1
fi
grep -Fqx 'INSTANCE_IDS=main,second' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fqx 'INSTANCE_ID=second' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
grep -Fqx 'INBOUND_TAG=vless-reality-BAD_TAG' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
protocol_state_layer_matches_config

attempt_managed_instance_auto_heal() {
  return 1
}
sed -i 's/^SNI=second.example.com/SNI=drifted.example.com/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"
[[ "$(detect_existing_instance_state)" == "incomplete" ]]

for failure_case in duplicate-id different-private-key provider-failure; do
  write_original_state_tree
  before_hash=$(state_tree_hash)
  case "${failure_case}" in
    duplicate-id|different-private-key)
      write_config "${failure_case}"
      ;;
    provider-failure)
      write_config provider-failure
      ;;
  esac

  if rebuild_protocol_state_from_config; then
    printf 'expected %s rebuild to fail\n' "${failure_case}" >&2
    exit 1
  fi
  after_hash=$(state_tree_hash)
  if [[ "${before_hash}" != "${after_hash}" ]]; then
    printf 'expected %s failure to restore the complete state tree\nbefore: %s\nafter: %s\n' \
      "${failure_case}" "${before_hash}" "${after_hash}" >&2
    exit 1
  fi
  grep -Fqx 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  [[ -e "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stale.env" ]]
done

# Managed-only metadata is absent from sing-box JSON. Explicit takeover must
# join it by the existing inbound tag rather than inventing IDs or clearing QoS.
(
  write_config valid
  write_original_state_tree
  rm -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stale.env" "${SB_KEY_FILE}"
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=stable-edge
INSTANCE_IDS=stable-main,stable-edge
REALITY_PRIVATE_KEY=shared-private-key
REALITY_PUBLIC_KEY=retained-public-key
EOF
  for fixture_id in stable-main stable-edge; do
    SB_VLESS_INSTANCE_ID=${fixture_id}
    SB_NODE_NAME="custom ${fixture_id} name"
    SB_VLESS_RATE_LIMIT_UP_MBPS=17
    SB_VLESS_RATE_LIMIT_DOWN_MBPS=43
    SB_PORT=9999
    SB_UUID=old-uuid
    SB_SNI=old.example.com
    SB_SHORT_ID_1=old-short
    SB_SHORT_ID_2=""
    if [[ "${fixture_id}" == stable-main ]]; then
      SB_VLESS_INBOUND_TAG=vless-in
    else
      SB_VLESS_INBOUND_TAG=vless-reality-second
    fi
    save_vless_reality_instance_state
  done

  config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  rebuild_protocol_state_from_config
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_hash}" ]]
  grep -Fqx 'DEFAULT_INSTANCE_ID=stable-edge' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  grep -Fqx 'INSTANCE_IDS=stable-main,stable-edge' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  grep -Fqx 'REALITY_PUBLIC_KEY=retained-public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  for fixture_id in stable-main stable-edge; do
    load_vless_reality_instance_state "${fixture_id}"
    [[ "${SB_NODE_NAME}" == "custom ${fixture_id} name" ]]
    [[ "${SB_VLESS_RATE_LIMIT_UP_MBPS}" == 17 && "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" == 43 ]]
  done
  grep -Fqx 'PORT=443' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stable-main.env"
  grep -Fqx 'PORT=8443' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stable-edge.env"
  protocol_state_layer_matches_config
  first_hash=$(state_tree_hash)
  rebuild_protocol_state_from_config
  [[ "$(state_tree_hash)" == "${first_hash}" ]]

  # Validate both rendered directions using real, ephemeral REALITY material.
  for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
    [[ -n "${core_binary}" && -x "${core_binary}" ]] || continue
    (
      key_pair=$("${core_binary}" generate reality-keypair)
      test_private=$(sed -n 's/^PrivateKey: *//p' <<< "${key_pair}")
      test_public=$(sed -n 's/^PublicKey: *//p' <<< "${key_pair}")
      [[ -n "${test_private}" && -n "${test_public}" ]]
      SB_PRIVATE_KEY=${test_private}
      SB_PUBLIC_KEY=${test_public}
      VLESS_REALITY_DEFAULT_INSTANCE_ID=stable-edge
      VLESS_REALITY_INSTANCE_IDS=stable-main,stable-edge
      save_vless_reality_protocol_state
      ensure_vless_reality_materials() { return 0; }
      build_vless_inbound_json | jq -s '{inbounds: ., outbounds: [{type:"direct",tag:"direct"}]}' > "${TMP_DIR}/preserved-server.json"
      "${core_binary}" check -c "${TMP_DIR}/preserved-server.json"
      build_client_vless_reality_outbounds 127.0.0.1 | jq -s '{outbounds: .}' > "${TMP_DIR}/preserved-client.json"
      "${core_binary}" check -c "${TMP_DIR}/preserved-client.json"
    )
  done
  # The runtime validation above only replaces ephemeral root key material.
  # Subsequent rejection and rollback cases compare the current complete tree.

  cp "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/tagged-config.json"
  jq 'del(.inbounds[].tag, .inbounds[].users[].name)' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/anonymous-config.json"
  mv "${TMP_DIR}/anonymous-config.json" "${SINGBOX_CONFIG_FILE}"
  before_hash=$(state_tree_hash)
  if rebuild_protocol_state_from_config; then
    printf 'multiple anonymous inbounds must not replace managed identities\n' >&2
    exit 1
  fi
  [[ "$(state_tree_hash)" == "${before_hash}" ]]
  if agent_validate_vless_state_inventory; then
    printf 'Agent must also reject ambiguous anonymous inbounds\n' >&2
    exit 1
  fi
  jq '.inbounds[0].users[0].name = "stable-main" | .inbounds[1].users[0].name = "stable-edge"' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/identified-config.json"
  mv "${TMP_DIR}/identified-config.json" "${SINGBOX_CONFIG_FILE}"
  agent_validate_vless_state_inventory
  [[ "$(state_tree_hash)" == "${before_hash}" ]]
  mv "${TMP_DIR}/tagged-config.json" "${SINGBOX_CONFIG_FILE}"

  # Two managed identities cannot silently claim the same live inbound.
  sed -i 's/INBOUND_TAG=vless-reality-second/INBOUND_TAG=vless-in/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stable-edge.env"
  before_hash=$(state_tree_hash)
  if rebuild_protocol_state_from_config; then
    printf 'ambiguous managed tags must reject takeover\n' >&2
    exit 1
  fi
  [[ "$(state_tree_hash)" == "${before_hash}" ]]
  sed -i 's/INBOUND_TAG=vless-in/INBOUND_TAG=vless-reality-second/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stable-edge.env"

  sed -i 's/RATE_LIMIT_UP_MBPS=17/RATE_LIMIT_UP_MBPS=-1/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stable-edge.env"
  before_hash=$(state_tree_hash)
  if rebuild_protocol_state_from_config; then
    printf 'invalid saved QoS must reject takeover\n' >&2
    exit 1
  fi
  [[ "$(state_tree_hash)" == "${before_hash}" ]]
  sed -i 's/RATE_LIMIT_UP_MBPS=-1/RATE_LIMIT_UP_MBPS=17/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/stable-edge.env"

  before_hash=$(state_tree_hash)
  save_vless_reality_instance_state() { return 47; }
  if rebuild_protocol_state_from_config; then
    printf 'instance save failure must reject takeover\n' >&2
    exit 1
  fi
  [[ "$(state_tree_hash)" == "${before_hash}" ]]
)

(
  write_config valid
  write_original_state_tree
  # Only root schema1 state remains: preserve its name and matching key pair.
  rm -rf "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
  rm -f "${SB_KEY_FILE}"
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=legacy-custom-name
PORT=443
UUID=11111111-1111-4111-8111-111111111111
REALITY_PRIVATE_KEY=shared-private-key
REALITY_PUBLIC_KEY=legacy-public-key
EOF
  rebuild_protocol_state_from_config
  load_vless_reality_instance_state main
  [[ "${SB_NODE_NAME}" == legacy-custom-name ]]
  load_vless_reality_instance_state second
  [[ "${SB_NODE_NAME}" != legacy-custom-name ]]
  grep -Fqx 'REALITY_PUBLIC_KEY=legacy-public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  protocol_state_layer_matches_config
)

# Old single-instance configurations may omit both tag and user name.
(
  write_config valid
  jq '.inbounds = [.inbounds[0]] | del(.inbounds[0].tag, .inbounds[0].users[0].name)' \
    "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/untagged.json"
  mv "${TMP_DIR}/untagged.json" "${SINGBOX_CONFIG_FILE}"
  write_original_state_tree
  rm -rf "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
  rm -f "${SB_KEY_FILE}"
  printf '%s\n' 'INSTALLED=1' 'CONFIG_SCHEMA_VERSION=1' 'NODE_NAME=legacy-untagged-name' \
    'PORT=443' 'UUID=11111111-1111-4111-8111-111111111111' \
    'REALITY_PRIVATE_KEY=shared-private-key' 'REALITY_PUBLIC_KEY=legacy-public-key' \
    > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  rebuild_protocol_state_from_config
  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID}"
  [[ "${SB_NODE_NAME}" == legacy-untagged-name ]]
  protocol_state_layer_matches_config
  first_hash=$(state_tree_hash)
  rebuild_protocol_state_from_config
  [[ "$(state_tree_hash)" == "${first_hash}" ]]
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_hash}" ]]
  agent_validate_indexed_protocol_states vless-reality
  get_public_ip() { printf '192.0.2.1'; }
  agent_status_json > "${TMP_DIR}/untagged-status.json"
  agent_collect_nodes_json summary > "${TMP_DIR}/untagged-nodes.json"
  agent_collect_nodes_json links > "${TMP_DIR}/untagged-links.json"
  jq -e '.nodes | length == 1' "${TMP_DIR}/untagged-nodes.json" >/dev/null
  jq -e '.nodes | length == 1' "${TMP_DIR}/untagged-links.json" >/dev/null
  [[ "$(state_tree_hash)" == "${first_hash}" ]]
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_hash}" ]]
)
