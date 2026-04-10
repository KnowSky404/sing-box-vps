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

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.6\n'
    ;;
  check)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

setup_service() { :; }
open_firewall_port() { :; }
systemctl() { :; }

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "apple.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "apple.com",
            "server_port": 443
          },
          "private_key": "private-key",
          "short_id": [
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

cat > "${SB_KEY_FILE}" <<'EOF'
PRIVATE_KEY=private-key
PUBLIC_KEY=public-key
EOF

configure_outbound_stack_mode <<'EOF'
1
EOF

if ! jq -e '.dns.strategy == "ipv4_only"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected legacy config stack update to regenerate valid config, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi

if ! jq -e '.inbounds[0].users[0].uuid == "11111111-1111-1111-1111-111111111111"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected legacy config stack update to preserve UUID, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi

if ! jq -e '.inbounds[0].tls.reality.private_key == "private-key"' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected legacy config stack update to preserve reality private key, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi

if ! jq -e '.inbounds[0].tls.reality.short_id == ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"]' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'expected legacy config stack update to preserve reality short IDs, got:\n%s\n' "$(cat "${SINGBOX_CONFIG_FILE}")" >&2
  exit 1
fi
