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

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }
validate_config_file() { return 0; }

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
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
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        {
          "name": "hy2-user",
          "password": "hy2-pass"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "hy2.example.com",
        "certificate_path": "/etc/ssl/certs/hy2.pem",
        "key_path": "/etc/ssl/private/hy2.key"
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
      },
      {
        "inbound": "hy2-in",
        "action": "sniff"
      }
    ],
    "final": "direct"
  }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2
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

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=hy2-pass
USER_NAME=hy2-user
UP_MBPS=''
DOWN_MBPS=''
OBFS_ENABLED=n
OBFS_TYPE=''
OBFS_PASSWORD=''
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=''
ACME_DOMAIN=hy2.example.com
DNS_PROVIDER=cloudflare
CF_API_TOKEN=''
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=https://www.cloudflare.com
EOF

install_protocols_interactive additional <<'EOF'
2
63681
y
proxy_501265
e9dd334d6630fb62
EOF

if ! grep -Fq 'INSTALLED_PROTOCOLS=vless-reality,hy2,mixed' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected mixed to be appended to protocol index, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]; then
  printf 'expected mixed state file to be created\n' >&2
  exit 1
fi

if ! grep -Fq 'USERNAME=proxy_501265' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected mixed username to persist, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/mixed.env")" >&2
  exit 1
fi

if ! grep -Fq 'PASSWORD=e9dd334d6630fb62' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected mixed password to persist, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/mixed.env")" >&2
  exit 1
fi

if ! jq -e '.inbounds[] | select(.type == "mixed" and .listen_port == 63681)' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected generated config to include mixed inbound, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi
