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
systemctl() { :; }
check_port_conflict() { :; }
register_warp() {
  cat > "${SB_WARP_KEY_FILE}" <<'EOF'
WARP_PRIV_KEY=warp-private-key
WARP_V4=172.16.0.2
WARP_V6=2606:4700:110:8cde:1234:5678:90ab:cdef
EOF
}
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}
run_singbox_generate_command() {
  if [[ "${1:-}" == "reality-keypair" ]]; then
    cat <<'EOF'
PrivateKey: private-key
PublicKey: public-key
EOF
    return 0
  fi

  return 1
}
get_public_ip() {
  printf '203.0.113.10\n'
}

install_protocols_interactive "fresh" <<'EOF'

1


n
y
1
EOF

if ! grep -Fq 'REALITY_PUBLIC_KEY=public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
  printf 'expected vless state file to persist generated REALITY public key, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
  exit 1
fi

load_current_config_state
link=$(build_vless_link "203.0.113.10")

if [[ "${link}" != *'pbk=public-key'* ]]; then
  printf 'expected built VLESS link to use persisted public key, got:\n%s\n' "${link}" >&2
  exit 1
fi

if [[ "${link}" == *'[密钥丢失，请更新配置]'* ]]; then
  printf 'expected built VLESS link to avoid missing-key placeholder, got:\n%s\n' "${link}" >&2
  exit 1
fi
