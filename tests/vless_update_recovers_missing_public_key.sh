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

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
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
          "handshake": { "server": "apple.com", "server_port": 443 },
          "private_key": "private-key-from-config",
          "short_id": [ "aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb" ]
        }
      }
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key-from-state
REALITY_PUBLIC_KEY=
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

cat > "${SB_KEY_FILE}" <<'EOF'
PRIVATE_KEY=private-key-from-key-file
EOF

generate_keypair_count_file="${TMP_DIR}/generate-keypair.count"
printf '0\n' > "${generate_keypair_count_file}"

run_singbox_generate_command() {
  local current_count
  current_count=$(cat "${generate_keypair_count_file}")
  printf '%s\n' "$((current_count + 1))" > "${generate_keypair_count_file}"
  printf 'PrivateKey: regenerated-private-key\nPublicKey: regenerated-public-key\n'
}

validate_config_file() { jq -e . "${SINGBOX_CONFIG_FILE}" >/dev/null; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
systemctl() { :; }
check_port_conflict() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() { :; }
ensure_warp_routing_assets() { :; }

update_config_only <<'EOF'
1


3
cloudflare.com
EOF

if ! grep -Fq 'SNI=cloudflare.com' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
  printf 'expected vless update to persist new SNI, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
  exit 1
fi

if ! grep -Fq 'REALITY_PUBLIC_KEY=regenerated-public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
  printf 'expected missing public key to be regenerated, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
  exit 1
fi

if [[ "$(cat "${generate_keypair_count_file}")" != "1" ]]; then
  printf 'expected exactly one keypair regeneration, got %s\n' "$(cat "${generate_keypair_count_file}")" >&2
  exit 1
fi
