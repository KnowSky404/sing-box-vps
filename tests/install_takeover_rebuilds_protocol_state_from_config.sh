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
    shared-hy2-advanced)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "hysteria2",
    "listen_port": 8443,
    "users": [{"name": "advanced-hy2-user", "password": "advanced-hy2-pass"}],
    "tls": {
      "server_name": "advanced-hy2.example.com",
      "certificate_provider": "advanced-hy2-provider"
    },
    "masquerade": "https://www.cloudflare.com"
  }],
  "certificate_providers": [{
    "type": "acme",
    "tag": "advanced-hy2-provider",
    "domain": ["advanced-hy2.example.com", "alt.advanced-hy2.example.com"],
    "data_directory": "/var/lib/sing-box/custom-acme",
    "default_server_name": "advanced-hy2.example.com",
    "email": "advanced-hy2@example.com",
    "provider": "letsencrypt",
    "disable_http_challenge": true,
    "alternative_tls_port": 10443,
    "key_type": "p256",
    "http_client": {"engine": "go"},
    "dns01_challenge": {
      "provider": "cloudflare",
      "api_token": "advanced-hy2-token",
      "zone_token": "advanced-zone-token",
      "ttl": "120s",
      "propagation_delay": "5s",
      "propagation_timeout": "2m",
      "resolvers": ["1.1.1.1"],
      "override_domain": "_acme-challenge.advanced-hy2.example.com"
    }
  }],
  "route": {"rules": []}
}
EOF
      ;;
    inline-legacy-anytls-advanced)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 443,
    "users": [{"name": "legacy-anytls-user", "password": "legacy-anytls-pass"}],
    "tls": {
      "server_name": "legacy-anytls.example.com",
      "acme": {
        "domain": ["legacy-anytls.example.com", "alt.legacy-anytls.example.com"],
        "data_directory": "/var/lib/sing-box/legacy-acme",
        "default_server_name": "legacy-anytls.example.com",
        "email": "legacy-anytls@example.com",
        "provider": "letsencrypt",
        "disable_tls_alpn_challenge": true,
        "alternative_http_port": 10080,
        "http_client": {"engine": "go"}
      }
    }
  }],
  "route": {"rules": []}
}
EOF
      ;;
    shared-http-client)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 443,
    "users": [{"name": "shared-http-user", "password": "shared-http-pass"}],
    "tls": {
      "server_name": "shared-http.example.com",
      "certificate_provider": "shared-http-provider"
    }
  }],
  "certificate_providers": [{
    "type": "acme",
    "tag": "shared-http-provider",
    "domain": ["shared-http.example.com"],
    "email": "shared-http@example.com",
    "http_client": "shared-acme-http"
  }],
  "http_clients": [{"tag": "shared-acme-http", "engine": "go"}],
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

assert_advanced_provider_extras() {
  local protocol=$1
  local expected_data_directory=$2
  local expected_default_server_name=$3
  local expected_additional_domain=$4
  local state_file extra_json provider_json
  state_file=$(protocol_state_file "${protocol}")
  extra_json=$(
    # shellcheck disable=SC1090
    source "${state_file}"
    printf '%s' "${ACME_EXTRA_JSON:-}"
  )

  if ! jq -e \
    --arg data_directory "${expected_data_directory}" \
    --arg default_server_name "${expected_default_server_name}" \
    --arg additional_domain "${expected_additional_domain}" \
    '.data_directory == $data_directory and
      .default_server_name == $default_server_name and
      .provider == "letsencrypt" and
      .http_client.engine == "go" and
      .domain == [$default_server_name, $additional_domain] and
      (.email? == null) and (.tag? == null) and (.type? == null)' \
    <<< "${extra_json}" >/dev/null; then
    printf 'expected advanced ACME extras in %s state, got:\n%s\n' "${protocol}" "${extra_json}" >&2
    exit 1
  fi

  load_protocol_state "${protocol}"
  case "${protocol}" in
    hy2) provider_json=$(build_hy2_acme_json) ;;
    anytls) provider_json=$(build_anytls_acme_json) ;;
    *) printf 'unsupported advanced provider assertion protocol: %s\n' "${protocol}" >&2; exit 1 ;;
  esac

  if ! jq -e \
    --arg data_directory "${expected_data_directory}" \
    --arg default_server_name "${expected_default_server_name}" \
    --arg additional_domain "${expected_additional_domain}" \
    '.data_directory == $data_directory and
      .default_server_name == $default_server_name and
      .provider == "letsencrypt" and
      .http_client.engine == "go" and
      .domain == [$default_server_name, $additional_domain] and
      (.type? == null) and (.tag? == null)' \
    <<< "${provider_json}" >/dev/null; then
    printf 'expected rebuilt %s provider to preserve advanced ACME extras, got:\n%s\n' "${protocol}" "${provider_json}" >&2
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

for provider_case in shared-anytls inline-anytls inline-hy2 shared-hy2-advanced inline-legacy-anytls-advanced; do
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
    shared-hy2-advanced)
      assert_provider_state hy2 advanced-hy2.example.com advanced-hy2@example.com advanced-hy2-token
      assert_advanced_provider_extras \
        hy2 /var/lib/sing-box/custom-acme advanced-hy2.example.com alt.advanced-hy2.example.com
      if ! jq -e \
        '.disable_http_challenge == true and .alternative_tls_port == 10443 and
          .key_type == "p256" and .dns01_challenge.zone_token == "advanced-zone-token" and
          .dns01_challenge.ttl == "120s" and .dns01_challenge.propagation_delay == "5s" and
          .dns01_challenge.propagation_timeout == "2m" and
          .dns01_challenge.resolvers == ["1.1.1.1"] and
          .dns01_challenge.override_domain == "_acme-challenge.advanced-hy2.example.com"' \
        <<< "$(build_hy2_acme_json)" >/dev/null; then
        printf 'expected advanced shared Hy2 ACME and DNS01 fields to survive rebuild\n' >&2
        exit 1
      fi
      ;;
    inline-legacy-anytls-advanced)
      if ! protocol_state_matches_config anytls; then
        printf 'expected legacy inline AnyTLS ACME state to match config snapshot\n' >&2
        exit 1
      fi
      assert_advanced_provider_extras \
        anytls /var/lib/sing-box/legacy-acme legacy-anytls.example.com alt.legacy-anytls.example.com
      if ! jq -e \
        '.disable_tls_alpn_challenge == true and .alternative_http_port == 10080 and
          .domain == ["legacy-anytls.example.com", "alt.legacy-anytls.example.com"] and
          .email == "legacy-anytls@example.com"' \
        <<< "$(build_anytls_acme_json)" >/dev/null; then
        printf 'expected legacy inline AnyTLS ACME fields to survive 1.14 provider rebuild\n' >&2
        exit 1
      fi
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
write_certificate_provider_config shared-http-client
if rebuild_protocol_state_from_config; then
  printf 'expected provider referencing a shared http_client to fail closed during state rebuild\n' >&2
  exit 1
fi
if [[ -e "$(protocol_state_file anytls)" || -e "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'shared http_client provider must not leave rewritten protocol state\n' >&2
  exit 1
fi

reset_protocol_state_artifacts
write_multi_protocol_config
write_installed_runtime_artifacts

run_takeover_from_incomplete_menu
assert_rebuilt_multi_protocol_state
