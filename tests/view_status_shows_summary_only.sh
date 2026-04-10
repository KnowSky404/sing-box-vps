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

SUMMARY_COUNT_FILE="${TMP_DIR}/summary.count"
PROMPT_COUNT_FILE="${TMP_DIR}/prompt.count"
INFO_COUNT_FILE="${TMP_DIR}/info.count"
printf '0\n' > "${SUMMARY_COUNT_FILE}"
printf '0\n' > "${PROMPT_COUNT_FILE}"
printf '0\n' > "${INFO_COUNT_FILE}"

display_status_summary() {
  local current_count
  current_count=$(cat "${SUMMARY_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${SUMMARY_COUNT_FILE}"
}

prompt_installed_protocol_selection() {
  local current_count
  current_count=$(cat "${PROMPT_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${PROMPT_COUNT_FILE}"
}

show_connection_info_menu() {
  local current_count
  current_count=$(cat "${INFO_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${INFO_COUNT_FILE}"
}

load_current_config_state() {
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}

view_status

if [[ "$(cat "${SUMMARY_COUNT_FILE}")" != "1" ]]; then
  printf 'expected status summary to render once, got %s\n' "$(cat "${SUMMARY_COUNT_FILE}")" >&2
  exit 1
fi

if [[ "$(cat "${PROMPT_COUNT_FILE}")" != "0" ]]; then
  printf 'expected status view to skip protocol selection, got %s prompts\n' "$(cat "${PROMPT_COUNT_FILE}")" >&2
  exit 1
fi

if [[ "$(cat "${INFO_COUNT_FILE}")" != "0" ]]; then
  printf 'expected status view to skip node info menu, got %s calls\n' "$(cat "${INFO_COUNT_FILE}")" >&2
  exit 1
fi
