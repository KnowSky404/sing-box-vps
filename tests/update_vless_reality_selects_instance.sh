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
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
systemctl() { :; }
check_port_conflict() { :; }
load_current_config_state() {
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}
refresh_vless_reality_qos_rules() {
  printf 'qos refreshed\n' > "${TMP_DIR}/qos.called"
}
select_reality_sni_candidate() {
  printf 'auto.example.com'
}

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    { "type": "vless", "tag": "vless-in", "listen_port": 443 },
    { "type": "vless", "tag": "vless-reality-second", "listen_port": 8443 }
  ],
  "route": { "rules": [] }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,second
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main-node
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env" <<'EOF'
INSTANCE_ID=second
ENABLED=1
NODE_NAME=second-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

update_config_only <<'EOF'
1
2
9443

1
EOF

if ! grep -Fq 'PORT=9443' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env"; then
  printf 'expected selected second REALITY instance to update, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env")" >&2
  exit 1
fi

if ! grep -Fq 'PORT=443' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"; then
  printf 'expected main REALITY instance to remain unchanged, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env")" >&2
  exit 1
fi

test -f "${TMP_DIR}/qos.called"
