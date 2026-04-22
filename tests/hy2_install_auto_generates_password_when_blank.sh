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

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]; then
  printf 'expected hy2 state file to be created during install\n' >&2
  exit 1
fi

generated_password=$(grep '^PASSWORD=' "${SB_PROTOCOL_STATE_DIR}/hy2.env" | cut -d= -f2-)

if [[ -z "${generated_password}" ]]; then
  printf 'expected hy2 password to be auto-generated, got empty value\n' >&2
  exit 1
fi

if [[ "${generated_password}" == "hy2-password" ]]; then
  printf 'expected hy2 password to not use placeholder default, got %s\n' "${generated_password}" >&2
  exit 1
fi

if [[ ${#generated_password} -lt 24 ]]; then
  printf 'expected generated hy2 password length >= 24, got %s (%s chars)\n' "${generated_password}" "${#generated_password}" >&2
  exit 1
fi

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected install flow to generate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi
