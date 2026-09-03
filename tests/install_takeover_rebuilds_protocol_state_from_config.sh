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

ensure_sbv_command_installed() {
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

write_certificate_provider_config() {
  case "$1" in
    shared-anytls)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "anytls",
      "listen_port": 443,
      "users": [{"name": "shared-anytls-user", "password": "shared-anytls-pass"}],
      "tls": {
        "server_name": "shared-anytls.example.com",
        "certificate_provider": "shared-anytls-provider"
      }
    }
  ],
  "certificate_providers": [{
    "type": "acme",
    "tag": "shared-anytls-provider",
    "domain": ["shared-anytls.example.com"],
    "email": "shared-anytls@example.com",
    "dns01_challenge": {
      "provider": "cloudflare",
      "api_token": "shared-anytls-token"
    }
  }],
  "route": {"rules": []}
}
EOF
      ;;
    inline-anytls)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 443,
    "users": [{"name": "inline-anytls-user", "password": "inline-anytls-pass"}],
    "tls": {
      "server_name": "inline-anytls.example.com",
      "certificate_provider": {
        "type": "acme",
        "domain": ["inline-anytls.example.com"],
        "email": "inline-anytls@example.com",
        "dns01_challenge": {
          "provider": "cloudflare",
          "api_token": "inline-anytls-token"
        }
      }
    }
  }],
  "route": {"rules": []}
}
EOF
      ;;
    inline-hy2)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "hysteria2",
    "listen_port": 8443,
    "users": [{"name": "inline-hy2-user", "password": "inline-hy2-pass"}],
    "tls": {
      "server_name": "inline-hy2.example.com",
      "certificate_provider": {
        "type": "acme",
        "domain": ["inline-hy2.example.com"],
        "email": "inline-hy2@example.com",
        "dns01_challenge": {
          "provider": "cloudflare",
          "api_token": "inline-hy2-token"
        }
      }
    },
    "masquerade": "https://www.cloudflare.com"
  }],
  "route": {"rules": []}
}
EOF
      ;;
    invalid-inline-provider)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 443,
    "users": [{"name": "invalid-user", "password": "invalid-pass"}],
    "tls": {
      "server_name": "invalid.example.com",
      "certificate_provider": {"type": "self_signed"}
    }
  }],
  "route": {"rules": []}
}
EOF
      ;;
    invalid-shared-provider)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 443,
    "users": [{"name": "unmapped-user", "password": "unmapped-pass"}],
    "tls": {
      "server_name": "unmapped.example.com",
      "certificate_provider": "missing-provider"
    }
  }],
  "route": {"rules": []}
}
EOF
      ;;
    *)
      printf 'unknown certificate provider fixture: %s\n' "$1" >&2
      exit 1
      ;;
  esac
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

assert_provider_state() {
  local protocol=$1
  local domain=$2
  local email=$3
  local token=$4
  local state_file
  state_file=$(protocol_state_file "${protocol}")

  if ! protocol_state_matches_config "${protocol}"; then
    printf 'expected rebuilt %s provider state to match config snapshot\nexpected:\n%s\nsaved:\n%s\n' \
      "${protocol}" "$(render_expected_protocol_state_snapshot "${protocol}")" \
      "$(render_saved_protocol_state_snapshot "${protocol}")" >&2
    exit 1
  fi

  for expected_field in \
    "TLS_MODE=acme" \
    "ACME_MODE=dns" \
    "ACME_DOMAIN=${domain}" \
    "ACME_EMAIL=${email}" \
    "DNS_PROVIDER=cloudflare" \
    "CF_API_TOKEN=${token}"; do
    if ! grep -Fq "${expected_field}" "${state_file}"; then
      printf 'expected %s in %s, got:\n%s\n' "${expected_field}" "${state_file}" "$(cat "${state_file}")" >&2
      exit 1
    fi
  done
}

assert_loaded_anytls_provider_state() {
  local domain=$1
  local email=$2
  local token=$3

  rm -f "${SB_PROTOCOL_INDEX_FILE}"
  load_current_config_state
  if [[ "${SB_PROTOCOL}" != "anytls" || "${SB_ANYTLS_TLS_MODE}" != "acme" || \
    "${SB_ANYTLS_ACME_DOMAIN}" != "${domain}" || "${SB_ANYTLS_ACME_EMAIL}" != "${email}" || \
    "${SB_ANYTLS_ACME_MODE}" != "dns" || "${SB_ANYTLS_DNS_PROVIDER}" != "cloudflare" || \
    "${SB_ANYTLS_CF_API_TOKEN}" != "${token}" ]]; then
    printf 'load_current_config_state lost AnyTLS certificate provider fields\n' >&2
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

for provider_case in shared-anytls inline-anytls inline-hy2; do
  reset_protocol_state_artifacts
  write_certificate_provider_config "${provider_case}"

  if ! rebuild_protocol_state_from_config; then
    printf 'expected %s certificate provider state rebuild to succeed\n' "${provider_case}" >&2
    exit 1
  fi

  case "${provider_case}" in
    shared-anytls)
      assert_provider_state anytls shared-anytls.example.com shared-anytls@example.com shared-anytls-token
      assert_loaded_anytls_provider_state shared-anytls.example.com shared-anytls@example.com shared-anytls-token
      ;;
    inline-anytls)
      assert_provider_state anytls inline-anytls.example.com inline-anytls@example.com inline-anytls-token
      assert_loaded_anytls_provider_state inline-anytls.example.com inline-anytls@example.com inline-anytls-token
      ;;
    inline-hy2)
      assert_provider_state hy2 inline-hy2.example.com inline-hy2@example.com inline-hy2-token
      ;;
  esac
done

reset_protocol_state_artifacts
write_certificate_provider_config invalid-inline-provider
if rebuild_protocol_state_from_config; then
  printf 'expected non-ACME inline provider to fail closed during state rebuild\n' >&2
  exit 1
fi
if [[ -e "$(protocol_state_file anytls)" || -e "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'non-ACME inline provider must not leave rewritten protocol state\n' >&2
  exit 1
fi

reset_protocol_state_artifacts
write_certificate_provider_config invalid-shared-provider
if rebuild_protocol_state_from_config; then
  printf 'expected unmapped shared provider to fail closed during state rebuild\n' >&2
  exit 1
fi
if [[ -e "$(protocol_state_file anytls)" || -e "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'unmapped shared provider must not leave rewritten protocol state\n' >&2
  exit 1
fi

reset_protocol_state_artifacts
write_multi_protocol_config
write_installed_runtime_artifacts

run_takeover_from_incomplete_menu
assert_rebuilt_multi_protocol_state
