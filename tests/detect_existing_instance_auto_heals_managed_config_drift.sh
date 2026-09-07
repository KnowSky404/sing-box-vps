#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

GENERATE_CONFIG_COUNT_FILE="${TMP_DIR}/generate_config.count"
printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"

validate_config_file() { return 0; }
log_info() { :; }
log_warn() { :; }
log_success() { :; }

generate_config() {
  local current_count
  current_count=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${GENERATE_CONFIG_COUNT_FILE}"

  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "apple.com",
        "reality": {
          "enabled": true,
          "private_key": "private-key",
          "short_id": [
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen_port": 63681,
      "users": [
        {
          "username": "legacy-user",
          "password": "legacy-pass"
        }
      ]
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "vless-in",
        "action": "sniff"
      },
      {
        "domain": [
          "apple.com"
        ],
        "action": "direct"
      },
      {
        "inbound": "mixed-in",
        "action": "sniff"
      }
    ],
    "final": "direct"
  }
}
EOF
}

touch "${SINGBOX_SERVICE_FILE}"

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "apple.com",
        "reality": {
          "enabled": true,
          "private_key": "private-key",
          "short_id": [
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "vless-in",
        "action": "sniff"
      },
      {
        "domain": [
          "apple.com"
        ],
        "action": "direct"
      }
    ],
    "final": "direct"
  }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,mixed
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_test-host
PORT=63681
AUTH_ENABLED=y
USERNAME=legacy-user
PASSWORD=legacy-pass
EOF

state=$(detect_existing_instance_state)

if [[ "${state}" != "healthy" ]]; then
  printf 'expected managed drift to auto-heal as healthy, got %s\n' "${state}" >&2
  exit 1
fi

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected managed drift to regenerate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi

if ! jq -e '.inbounds[] | select(.type == "mixed" and .listen_port == 63681)' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected healed config to restore mixed inbound, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [{
    "type": "anytls",
    "listen_port": 443,
    "users": [{"name": "managed-user", "password": "managed-pass"}],
    "tls": {
      "server_name": "managed.example.com",
      "certificate_provider": "managed-provider"
    }
  }],
  "certificate_providers": [{
    "type": "acme",
    "tag": "managed-provider",
    "domain": ["managed.example.com"],
    "email": "managed@example.com",
    "http_client": "managed-http"
  }],
  "http_clients": [{"tag": "managed-http", "engine": "go"}],
  "route": {"rules": []}
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=anytls
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.14.0
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls_test-host
PORT=443
DOMAIN=managed.example.com
PASSWORD=managed-pass
USER_NAME=managed-user
TLS_MODE=acme
ACME_MODE=http
ACME_EMAIL=managed@example.com
ACME_DOMAIN=managed.example.com
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=
KEY_PATH=
EOF
rm -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" "${SB_PROTOCOL_STATE_DIR}/mixed.env"

printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"
protected_config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}" | awk '{print $1}')
state=$(detect_existing_instance_state)

if [[ "${state}" != "incomplete" ]]; then
  printf 'expected unrepresentable shared ACME http_client to require takeover, got %s\n' "${state}" >&2
  exit 1
fi
if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "0" ]]; then
  printf 'shared ACME http_client must block automatic config regeneration\n' >&2
  exit 1
fi
if [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}" | awk '{print $1}')" != "${protected_config_hash}" ]]; then
  printf 'shared ACME http_client config changed despite fail-closed auto-heal\n' >&2
  exit 1
fi
jq -e '
  .certificate_providers[0].http_client == "managed-http" and
  .http_clients[0].tag == "managed-http"
' "${SINGBOX_CONFIG_FILE}" >/dev/null
