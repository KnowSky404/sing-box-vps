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

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen_port": 1080,
      "users": [
        {
          "username": "legacy-user",
          "password": "legacy-pass"
        }
      ]
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF

install_protocols_interactive "additional" <<'EOF'
3
hy2.example.com
8443
hy2-pass
hy2-user
100
50
n
2
/etc/ssl/certs/hy2.pem
/etc/ssl/private/hy2.key

EOF

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" ]]; then
  printf 'expected mixed protocol state file to be recreated from legacy config\n' >&2
  exit 1
fi

if ! grep -Fq 'AUTH_ENABLED=y' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected mixed state to preserve auth enabled flag, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/mixed.env")" >&2
  exit 1
fi

if ! grep -Fq 'USERNAME=legacy-user' "${SB_PROTOCOL_STATE_DIR}/mixed.env"; then
  printf 'expected mixed state to preserve username, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/mixed.env")" >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=mixed,hy2' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to keep mixed and add hy2, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi
