#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

restart_service_after_takeover() {
  :
}

write_installed_runtime_artifacts() {
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"

  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.5\n'
  exit 0
fi

exit 0
EOF
  chmod +x "${SINGBOX_BIN_PATH}"

  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF
}

write_multi_protocol_config() {
  mkdir -p "${SB_PROJECT_DIR}"

  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "listen_port": 1080,
      "users": [
        {
          "username": "legacy-user",
          "password": "legacy-pass"
        }
      ]
    },
    {
      "type": "anytls",
      "listen_port": 443,
      "users": [
        {
          "name": "demo",
          "password": "secret"
        }
      ],
      "tls": {
        "server_name": "edge.example.com",
        "certificate_path": "/tmp/cert.pem",
        "key_path": "/tmp/key.pem"
      }
    }
  ],
  "route": {
    "rules": []
  }
}
EOF
}

reset_protocol_state_artifacts() {
  rm -f "${SB_PROTOCOL_INDEX_FILE}"
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
}

run_takeover_from_incomplete_menu() {
  if ! TAKEOVER_OUTPUT=$(printf '1\n' | install_or_update_singbox 2>&1); then
    printf 'expected option 1 takeover flow to succeed, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  TAKEOVER_PLAIN_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")
  if [[ "${TAKEOVER_PLAIN_OUTPUT}" != *"检测到残缺的现有实例"* ]]; then
    printf 'expected incomplete-instance menu before takeover, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi
}

assert_rebuilt_multi_protocol_state() {
  if [[ ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    printf 'expected takeover flow to rebuild protocol index file: %s\n' "${SB_PROTOCOL_INDEX_FILE}" >&2
    exit 1
  fi

  if [[ ! -f "$(protocol_state_file mixed)" ]]; then
    printf 'expected takeover flow to rebuild mixed protocol state file\n' >&2
    exit 1
  fi

  if [[ ! -f "$(protocol_state_file anytls)" ]]; then
    printf 'expected takeover flow to rebuild anytls protocol state file\n' >&2
    exit 1
  fi

  if ! grep -Fq 'INSTALLED_PROTOCOLS=mixed,anytls' "${SB_PROTOCOL_INDEX_FILE}"; then
    printf 'expected takeover flow to rebuild protocol index from config.json, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
    exit 1
  fi

  if ! grep -Fq 'USERNAME=legacy-user' "$(protocol_state_file mixed)"; then
    printf 'expected takeover flow to rebuild mixed state from config.json, got:\n%s\n' "$(cat "$(protocol_state_file mixed)")" >&2
    exit 1
  fi

  if ! grep -Fq 'DOMAIN=edge.example.com' "$(protocol_state_file anytls)"; then
    printf 'expected takeover flow to rebuild anytls state from config.json, got:\n%s\n' "$(cat "$(protocol_state_file anytls)")" >&2
    exit 1
  fi
}

write_multi_protocol_config
write_installed_runtime_artifacts

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed,anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "$(protocol_state_file mixed)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_test-host
PORT=1080
AUTH_ENABLED=y
USERNAME=legacy-user
PASSWORD=legacy-pass
EOF

run_takeover_from_incomplete_menu
assert_rebuilt_multi_protocol_state

reset_protocol_state_artifacts
write_multi_protocol_config
write_installed_runtime_artifacts

run_takeover_from_incomplete_menu
assert_rebuilt_multi_protocol_state
