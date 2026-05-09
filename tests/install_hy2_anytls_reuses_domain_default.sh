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
generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }

install_protocols_interactive "fresh" <<'EOF'

3,4
shared.example.com
8443
hy2-pass
hy2-user


n
2
/etc/ssl/certs/shared.pem
/etc/ssl/private/shared.key


9443
anytls-user
anytls-pass
2
/etc/ssl/certs/shared.pem
/etc/ssl/private/shared.key
n
n
EOF

if ! grep -Fq 'DOMAIN=shared.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 state to persist entered domain, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Fq 'DOMAIN=shared.example.com' "${SB_PROTOCOL_STATE_DIR}/anytls.env"; then
  printf 'expected anytls state to reuse hy2 domain when domain prompt is blank, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/anytls.env")" >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=hy2,anytls' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to contain hy2,anytls, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi
