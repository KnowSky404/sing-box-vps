verification_scenario_lifecycle_safety() {
  local config=/root/.sing-box-vps/runtime/config.json
  local pending=/root/.sing-box-vps/runtime.component-write.lock
  local before_pid before_hash menu_output
  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=lifecycle_safety\n'
  # The fresh installer opens an unmarked legacy rule. Replace this exact
  # fixture-created rule with real ledger-owned rules for both families.
  iptables -D INPUT -p tcp --dport 1081 -j ACCEPT
  bash -s -- "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'FIREWALL_BASELINE'
set -euo pipefail
source "$1"
acquire_managed_write_lock
open_scoped_protocol_ports
FIREWALL_BASELINE
  jq -e '.rules | length==2 and any(.[]; .backend=="iptables") and any(.[]; .backend=="ip6tables")' \
    /root/.sing-box-vps/runtime/managed-firewall.json >/dev/null
  before_pid=$(systemctl show sing-box --property=MainPID --value)
  before_hash=$(sha256sum "${config}")
  cp "${config}" "${config}.lifecycle-fixture"

  lifecycle_menu() {
    bash -s -- "${VERIFY_REMOTE_INSTALL_SCRIPT}" "$1" <<'MENU'
set -euo pipefail
source "$1"
check_script_status() { SCRIPT_VER_STATUS=''; }
check_sb_version() { SB_VER_STATUS=''; }
check_bbr_status() { :; }
ensure_sbv_command_installed() { :; }
main <<< "$2"$'\n0'
MENU
  }

  printf '{invalid\n' > "${config}"
  menu_output=$(lifecycle_menu 8 2>&1)
  grep -q config_check_failed <<< "${menu_output}"
  if sbv service restart --json --yes > /tmp/lifecycle-invalid.json; then return 1; fi
  jq -e '.error=="config_check_failed"' /tmp/lifecycle-invalid.json >/dev/null
  [[ "$(systemctl show sing-box --property=MainPID --value)" == "${before_pid}" ]]
  cp "${config}.lifecycle-fixture" "${config}"
  [[ "$(sha256sum "${config}")" == "${before_hash}" ]]
  sing-box check -c "${config}"

  mkdir -m 700 "${pending}"
  menu_output=$(lifecycle_menu 8 2>&1)
  grep -q transaction_pending <<< "${menu_output}"
  if sbv service start --json --yes > /tmp/lifecycle-pending.json; then return 1; fi
  jq -e '.error=="transaction_pending"' /tmp/lifecycle-pending.json >/dev/null
  [[ "$(systemctl show sing-box --property=MainPID --value)" == "${before_pid}" ]]
  rmdir "${pending}"

  sbv service stop --json --yes | jq -e '.ok and .service.after=="inactive"' >/dev/null
  lifecycle_menu 6 > /tmp/lifecycle-start.txt
  verification_wait_for_service_active sing-box
  lifecycle_menu 7 > /tmp/lifecycle-stop.txt
  [[ "$(systemctl show sing-box --property=ActiveState --value)" == inactive ]]
  sbv service start --json --yes | jq -e '.ok and .service.after=="active"' >/dev/null

  # A failed stop still observes the real active unit; only the failing command
  # is injected. Files, rules and the running PID must remain untouched.
  before_pid=$(systemctl show sing-box --property=MainPID --value)
  if bash -s -- "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'STOP_FAILURE'
set -euo pipefail
source "$1"
systemctl() {
  if [[ "$*" == 'stop sing-box' ]]; then return 17; fi
  command systemctl "$@"
}
perform_singbox_runtime_uninstall
STOP_FAILURE
  then return 1; fi
  [[ "$(sha256sum "${config}")" == "${before_hash}" ]]
  [[ "$(systemctl show sing-box --property=MainPID --value)" == "${before_pid}" ]]
  jq -e '.rules | length>0' /root/.sing-box-vps/runtime/managed-firewall.json >/dev/null

  iptables -I INPUT -p tcp --dport 39997 -j ACCEPT
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes
  [[ ! -e "${config}" && ! -e /usr/local/bin/sbv && ! -e /usr/local/bin/sing-box ]]
  [[ "$(systemctl show sing-box --property=ActiveState --value)" == inactive ]]
  iptables -C INPUT -p tcp --dport 39997 -j ACCEPT
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/iptables-after-uninstall.txt" iptables-save || return 1
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/ip6tables-after-uninstall.txt" ip6tables-save || return 1
  if grep -q sbv-instance- "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/iptables-after-uninstall.txt")"; then return 1; fi
  if grep -q sbv-instance- "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/ip6tables-after-uninstall.txt")"; then return 1; fi
  iptables -D INPUT -p tcp --dport 39997 -j ACCEPT
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/uninstall-inactive.txt" \
    systemctl show sing-box --property=ActiveState --value
  printf 'real-systemd=passed\nmenu-cli-guards=passed\nowned-firewall-removal=passed\nunrelated-rule-preserved=passed\n' \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/lifecycle-results.txt")"
  unset -f lifecycle_menu
  # Restore a fresh, checked installation for the final smoke/proxy probe.
  verification_scenario_fresh_install_socks
}
