#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

calls="${TMP_DIR}/calls"
: > "${calls}"
check_root() { :; }
acquire_managed_write_lock() { :; }
ensure_sbv_command_installed() { :; }
check_script_status() { SCRIPT_VER_STATUS=''; }
check_sb_version() { SB_VER_STATUS=''; }
check_bbr_status() { :; }
main_menu_service_status_summary() { printf 'active'; }
exit_script() { exit 0; }
clear() { :; }
load_current_config_state() { printf 'unexpected config read\n' >> "${calls}"; return 1; }
install_new_protocols_menu() { printf 'unexpected install\n' >> "${calls}"; }
recover_mixed_instance_transaction() { printf 'mixed %s\n' "$1" >> "${calls}"; }
recover_plain_proxy_instance_transaction() { printf '%s %s\n' "$1" "$2" >> "${calls}"; }

# Every former top-level instance entry remains reachable for recovery before
# any live configuration or protocol state is loaded.
lock_dir="${SB_PROJECT_DIR}.instance-write.lock"
mkdir -p "${lock_dir}"
for protocol in mixed socks http shadowsocks trojan vmess vless-plain anytls hy2 snell tuic hysteria naive shadowtls; do
  jq -n --arg protocol "${protocol}" '{schema_version:1,protocol:$protocol,expected_revision:"7"}' > "${lock_dir}/transaction.json"
  if update_config_only >/dev/null 2>"${TMP_DIR}/recovery.stderr" <<'EOF'
1
y
EOF
  then
    :
  else
    cat "${TMP_DIR}/recovery.stderr" >&2
    exit 1
  fi
  grep -Fxq "${protocol} 7" "${calls}"
done

# Old Mixed journals do not have a protocol field.
printf '%s\n' '{"schema_version":1,"expected_revision":"8"}' > "${lock_dir}/transaction.json"
update_config_only >/dev/null <<'EOF'
1
y
EOF
grep -Fxq 'mixed 8' "${calls}"

# Main menu 2 must pass the pending-transaction guard; menu 1 stays blocked.
printf '%s\n' '{"schema_version":1,"protocol":"hy2","expected_revision":"9"}' > "${lock_dir}/transaction.json"
(main) >"${TMP_DIR}/main.output" 2>&1 <<'EOF'
1
2
1
y
0
EOF
grep -Fxq 'hy2 9' "${calls}"
! grep -Fq 'unexpected' "${calls}"
! grep -Fq '实例与状态' "${TMP_DIR}/main.output"
grep -Fq '菜单 2' "${TMP_DIR}/main.output"

# An unknown/damaged journal stays in place and cannot select a shell handler.
printf '%s\n' '{"schema_version":1,"protocol":"unknown","expected_revision":"7"}' > "${lock_dir}/transaction.json"
if update_config_only >/dev/null 2>&1; then
  printf 'expected untrusted transaction to block recovery\n' >&2
  exit 1
fi
[[ -f "${lock_dir}/transaction.json" ]]

rm "${lock_dir}/transaction.json"
rmdir "${lock_dir}"
touch "${SINGBOX_CONFIG_FILE}"
migrate_legacy_single_protocol_state_if_needed() { :; }
load_current_config_state() { :; }
prompt_installed_protocol_selection() { SELECTED_PROTOCOL=${protocol}; }
plain_proxy_structured_state_active() { [[ "${1:-}" != vless-reality ]]; }
for protocol in mixed socks http shadowsocks trojan vmess vless-plain anytls hy2 snell tuic hysteria naive shadowtls; do
  output=$(update_config_only <<'EOF'
0
EOF
)
  grep -Fq -- "--- $(plain_proxy_management_label "${protocol}") 实例管理 ---" <<< "${output}"
done

printf 'main menu checks passed: management=14 recovery=14 legacy-Mixed=1 protected-install=1\n'
