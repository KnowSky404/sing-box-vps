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

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

POST_CONFIG_COUNT_FILE="${TMP_DIR}/post_config.count"
SUMMARY_COUNT_FILE="${TMP_DIR}/summary.count"
printf '0\n' > "${POST_CONFIG_COUNT_FILE}"
printf '0\n' > "${SUMMARY_COUNT_FILE}"

show_banner() { :; }
check_root() { :; }
check_script_status() { SCRIPT_VER_STATUS=""; }
check_sb_version() { SB_VER_STATUS=""; }
check_bbr_status() { BBR_STATUS=""; }
get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
save_warp_route_settings() { :; }
install_binary() { :; }
generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
check_port_conflict() { :; }
systemctl() { :; }
display_status_summary() {
  local current_count
  current_count=$(cat "${SUMMARY_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${SUMMARY_COUNT_FILE}"
}
show_post_config_connection_info() {
  local current_count
  current_count=$(cat "${POST_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${POST_CONFIG_COUNT_FILE}"
}
display_info() { :; }

(
  main <<'EOF'
1

1




0
EOF
)

post_config_calls=$(cat "${POST_CONFIG_COUNT_FILE}")
summary_calls=$(cat "${SUMMARY_COUNT_FILE}")

if (( summary_calls != 1 )); then
  printf 'expected first install to show status summary once, got %s\n' "${summary_calls}" >&2
  exit 1
fi

if (( post_config_calls != 0 )); then
  printf 'expected first install to leave connection info hidden until menu 10, got %s automatic calls\n' "${post_config_calls}" >&2
  exit 1
fi
