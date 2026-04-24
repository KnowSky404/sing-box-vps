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

write_runtime_artifacts() {
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"

  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.5\n'
  exit 0
fi

if [[ "${1:-}" == "check" ]]; then
  exit 0
fi

exit 0
EOF
  chmod +x "${SINGBOX_BIN_PATH}"

  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF

  cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SBV_BIN_PATH}"
}

write_legacy_multi_protocol_config() {
  mkdir -p "${SB_PROJECT_DIR}"

  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111"
        }
      ],
      "tls": {
        "server_name": "apple.com",
        "reality": {
          "private_key": "private-key",
          "short_id": [
            "aaaaaaaaaaaaaaaa"
          ]
        }
      }
    },
    {
      "type": "hysteria2",
      "listen_port": 65123,
      "users": [
        {
          "name": "hy2-user",
          "password": "ff288bbff8ba6dbd579a3e6101ca6f11"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "bfc-us-lax.ziteng.li",
        "acme": {
          "domain": [
            "bfc-us-lax.ziteng.li"
          ],
          "email": ""
        }
      },
      "masquerade": "https://www.cloudflare.com"
    }
  ],
  "route": {
    "rules": []
  }
}
EOF
}

write_runtime_artifacts
write_legacy_multi_protocol_config

if ! TAKEOVER_OUTPUT=$(printf '1\n' | install_or_update_singbox 2>&1); then
  printf 'expected takeover flow to succeed for hy2 acme rebuild, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
  exit 1
fi

TAKEOVER_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")

if [[ "${TAKEOVER_OUTPUT}" != *"现有实例接管完成。"* ]]; then
  printf 'expected successful takeover message for hy2 acme rebuild, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
  exit 1
fi

if [[ "$(detect_existing_instance_state)" != "healthy" ]]; then
  printf 'expected hy2 acme takeover rebuild to leave instance healthy, got %s\n' "$(detect_existing_instance_state)" >&2
  exit 1
fi

if ! protocol_state_matches_config hy2; then
  printf 'expected rebuilt hy2 state to match config snapshot\nexpected:\n%s\nsaved:\n%s\n' \
    "$(render_expected_protocol_state_snapshot hy2)" \
    "$(render_saved_protocol_state_snapshot hy2)" >&2
  exit 1
fi
