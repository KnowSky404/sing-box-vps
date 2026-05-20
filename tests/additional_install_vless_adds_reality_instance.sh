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

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
  exit 0
fi
if [[ "${1:-}" == "generate" && "${2:-}" == "reality-keypair" ]]; then
  printf 'PrivateKey: private-key\n'
  printf 'PublicKey: public-key\n'
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
refresh_vless_reality_qos_rules() { printf 'qos refreshed\n' > "${TMP_DIR}/qos.called"; }
prompt_reality_sni_install() { SB_SNI="${SB_SNI:-apple.com}"; }

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
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

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{ "inbounds": [], "route": { "rules": [] } }
EOF

install_protocols_interactive additional <<'EOF'
1
limited-10m
limited-node
not-a-port
443
8443

y

10
EOF

limited_state="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/limited-10m.env"
if [[ ! -f "${limited_state}" ]]; then
  printf 'expected limited instance state to be created\n' >&2
  exit 1
fi

grep -Fq 'INSTANCE_IDS=main,limited-10m' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'NODE_NAME=limited-node' "${limited_state}"
grep -Fq 'PORT=8443' "${limited_state}"
grep -Eq '^RATE_LIMIT_UP_MBPS=$' "${limited_state}"
grep -Fq 'RATE_LIMIT_DOWN_MBPS=10' "${limited_state}"

if grep -Fq 'PORT=443' "${limited_state}"; then
  printf 'expected duplicate configured port 443 to be rejected, got:\n%s\n' "$(cat "${limited_state}")" >&2
  exit 1
fi

jq -e 'any(.inbounds[]; .tag == "vless-reality-limited-10m" and .listen_port == 8443)' "${SINGBOX_CONFIG_FILE}" >/dev/null
test -f "${TMP_DIR}/qos.called"
