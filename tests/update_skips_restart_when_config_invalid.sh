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

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.5\n'
    exit 0
    ;;
  check)
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

GENERATE_CONFIG_COUNT_FILE="${TMP_DIR}/generate_config.count"
SYSTEMCTL_RESTART_COUNT_FILE="${TMP_DIR}/systemctl_restart.count"
printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"
printf '0\n' > "${SYSTEMCTL_RESTART_COUNT_FILE}"

show_banner() { :; }
check_root() { :; }
check_script_status() { SCRIPT_VER_STATUS=""; }
check_sb_version() { SB_VER_STATUS=""; }
check_bbr_status() { BBR_STATUS=""; }
get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
save_warp_route_settings() { :; }
install_binary() { :; }
generate_config() {
  local current_count
  current_count=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${GENERATE_CONFIG_COUNT_FILE}"
}
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_info() { :; }
check_port_conflict() { :; }
systemctl() {
  if [[ "${1:-}" == "restart" && "${2:-}" == "sing-box" ]]; then
    local current_count
    current_count=$(cat "${SYSTEMCTL_RESTART_COUNT_FILE}")
    printf '%s\n' "$((current_count + 1))" > "${SYSTEMCTL_RESTART_COUNT_FILE}"
  fi
}
load_current_config_state() {
  SB_PROTOCOL="vless+reality"
  SB_PORT="443"
  SB_UUID="11111111-1111-1111-1111-111111111111"
  SB_SNI="apple.com"
  SB_PRIVATE_KEY="private-key"
  SB_PUBLIC_KEY="public-key"
  SB_SHORT_ID_1="aaaaaaaaaaaaaaaa"
  SB_SHORT_ID_2="bbbbbbbbbbbbbbbb"
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": 443
    }
  ]
}
EOF

(
  main <<'EOF'
1

0
EOF
)

generate_config_calls=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
restart_calls=$(cat "${SYSTEMCTL_RESTART_COUNT_FILE}")

if (( generate_config_calls != 0 )); then
  printf 'expected invalid-config upgrade path to preserve config, but generate_config ran %s time(s)\n' "${generate_config_calls}" >&2
  exit 1
fi

if (( restart_calls != 0 )); then
  printf 'expected invalid-config upgrade path to skip service restart, but systemctl restart ran %s time(s)\n' "${restart_calls}" >&2
  exit 1
fi
