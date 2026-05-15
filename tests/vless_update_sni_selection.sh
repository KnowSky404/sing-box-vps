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

generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
systemctl() { :; }
check_port_conflict() { :; }
load_current_config_state() {
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}
select_reality_sni_candidate() {
  printf 'speed.example.com'
}

write_base_state() {
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443
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
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF
}

assert_state_sni() {
  local expected=$1
  if ! grep -Fqx "SNI=${expected}" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
    printf 'expected SNI=%s, got:\n%s\n' "${expected}" "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
    exit 1
  fi
}

write_base_state
update_config_only <<'EOF'
1



EOF
assert_state_sni "apple.com"

write_base_state
update_config_only <<'EOF'
1


2
EOF
assert_state_sni "speed.example.com"

write_base_state
update_config_only <<'EOF'
1


3
custom.example.com
EOF
assert_state_sni "custom.example.com"
