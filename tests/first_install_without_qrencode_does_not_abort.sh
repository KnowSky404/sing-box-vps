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

get_os_info() { OS_NAME="debian"; }
get_arch() { ARCH="amd64"; }
prompt_singbox_version() { SB_VERSION="${SB_SUPPORT_MAX_VERSION}"; }
prompt_protocol_install_selection() { SELECTED_PROTOCOLS_CSV="vless-reality"; }
prompt_protocol_install_fields() {
  SB_PROTOCOL="vless+reality"
  SB_PORT="443"
  SB_UUID="11111111-1111-1111-1111-111111111111"
  SB_SNI="apple.com"
  SB_PUBLIC_KEY="public-key"
  SB_SHORT_ID_1="aaaaaaaaaaaaaaaa"
  SB_NODE_NAME="vless_reality_test-host"
}
save_protocol_state() { :; }
prompt_global_instance_options() { :; }
write_protocol_index() { :; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
save_warp_route_settings() { :; }
generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
load_protocol_state() { :; }
open_all_protocol_ports() { :; }
systemctl() { :; }
display_status_summary() { :; }

output=$(install_protocols_interactive "fresh" 2>&1)

if [[ "${output}" != *"REALITY 协议链接"* ]]; then
  printf 'expected first install flow to continue and show link output, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"未安装 qrencode"* ]]; then
  printf 'expected first install flow to warn about missing qrencode, got:\n%s\n' "${output}" >&2
  exit 1
fi
