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
