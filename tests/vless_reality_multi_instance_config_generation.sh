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

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

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

register_warp() { :; }
ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,limited-10m
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

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env" <<'EOF'
INSTANCE_ID=limited-10m
ENABLED=1
NODE_NAME=limited-node
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=10
ALPN_MODE=h2_http1
TCP_FAST_OPEN=y
EOF

generate_config

jq -e '
  (.inbounds | length) == 2 and
  any(.inbounds[]; .type == "vless" and .tag == "vless-in" and .listen_port == 443 and .users[0].uuid == "11111111-1111-1111-1111-111111111111") and
  any(.inbounds[]; .type == "vless" and .tag == "vless-reality-limited-10m" and .listen_port == 8443 and .users[0].name == "limited-10m" and .tls.server_name == "www.cloudflare.com") and
  any(.inbounds[]; .tag == "vless-reality-limited-10m" and .tcp_fast_open == true and .tls.alpn == ["h2", "http/1.1"]) and
  any(.inbounds[]; .tag == "vless-in" and (.tcp_fast_open | not) and (.tls | has("alpn") | not)) and
  ([.route.rules[] | select(.action == "sniff") | .inbound] | sort) == ["vless-in", "vless-reality-limited-10m"] and
  ([.route.rules[] | select(.action == "direct") | .domain[0]] | sort) == ["apple.com", "www.cloudflare.com"]
' "${SINGBOX_CONFIG_FILE}" >/dev/null
