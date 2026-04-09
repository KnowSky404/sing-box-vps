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

GENERATE_CONFIG_COUNT_FILE="${TMP_DIR}/generate_config.count"
printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"

get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
generate_config() {
  local current_count
  current_count=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${GENERATE_CONFIG_COUNT_FILE}"
}
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }

install_protocols_interactive "fresh" <<'EOF'

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

n
n
EOF

if [[ ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'expected protocol index file to be created during hy2 install\n' >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=hy2' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to contain hy2, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]; then
  printf 'expected hy2 state file to be created during install\n' >&2
  exit 1
fi

if ! grep -Fq 'DOMAIN=hy2.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 state file to persist domain, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Fq 'TLS_MODE=manual' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 state file to persist manual TLS mode, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected install flow to generate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi
