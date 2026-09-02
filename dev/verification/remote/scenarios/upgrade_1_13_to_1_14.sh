verification_scenario_upgrade_1_13_to_1_14() {
  local legacy_install
  local before_hash after_hash before_service_hash after_service_hash
  local backup_path
  local preflight_path upgrade_path

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=upgrade_1_13_to_1_14\n'

  legacy_install=$(mktemp /tmp/sing-box-vps-install-1.13.18.XXXXXX)
  sed 's/readonly SB_SUPPORT_MAX_VERSION="[^"]*"/readonly SB_SUPPORT_MAX_VERSION="1.13.18"/' \
    "${VERIFY_REMOTE_INSTALL_SCRIPT}" > "${legacy_install}"
  chmod +x "${legacy_install}"
  "${legacy_install}" --internal-uninstall-purge --yes >/dev/null 2>&1 || true
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${legacy_install}" <<'EOF'
1

1

443
2
www.cloudflare.com
n
1
n
n
n
0
EOF
  rm -f "${legacy_install}"

  verification_mark_step upgrade_legacy_1_13_installed
  grep -Fqx 'sing-box version 1.13.18' <(sing-box version)
  test -f /root/sing-box-vps/config.json
  verification_capture_best_effort_command "${VERIFY_CURRENT_SCENARIO_DIR}/legacy-sbv-version.txt" \
    grep -m1 '^readonly SCRIPT_VERSION=' /usr/local/bin/sbv
  install -m 0755 "${VERIFY_REMOTE_INSTALL_SCRIPT}" /usr/local/bin/sbv
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/current-sbv-version.txt" \
    grep -m1 '^readonly SCRIPT_VERSION=' /usr/local/bin/sbv
  sbv agent capabilities --json \
    > "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/capabilities.json")"
  jq -e '.ok == true and (.script_version | tonumber) >= 2026090202' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/capabilities.json")" >/dev/null
  verification_mark_step upgrade_current_agent_surface_installed

  before_hash=$(sha256sum /root/sing-box-vps/config.json | awk '{print $1}')
  before_service_hash=$(sha256sum /etc/systemd/system/sing-box.service | awk '{print $1}')
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/config.before.sha256" "${before_hash}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/service.before.sha256" "${before_service_hash}"
  verification_capture_best_effort_command "${VERIFY_CURRENT_SCENARIO_DIR}/before.version.txt" sing-box version
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/before.check.txt" sing-box check -c /root/sing-box-vps/config.json

  preflight_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/upgrade-check.json")
  sbv agent upgrade-check --json 1.14.0 > "${preflight_path}"
  jq -e '
    .ready == true
    and .blockers == []
    and .current == "1.13.18"
    and .target == "1.14.0"
    and .apply == false
    and .target_binary_validation.performed == false
    and .current_check.ok == true
  ' "${preflight_path}" >/dev/null
  verification_mark_step upgrade_preflight_ready

  upgrade_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/upgrade.json")
  sbv agent upgrade --json 1.14.0 --yes > "${upgrade_path}"
  jq -e '
    .ok == true
    and .changed == true
    and .restarted == true
    and .rolled_back == false
    and .config_preserved == true
    and .installed == "1.14.0"
    and (.backup | type == "string" and length > 0)
    and .check.ok == true
    and .service.after == "active"
  ' "${upgrade_path}" >/dev/null
  verification_mark_step upgrade_applied

  after_hash=$(sha256sum /root/sing-box-vps/config.json | awk '{print $1}')
  after_service_hash=$(sha256sum /etc/systemd/system/sing-box.service | awk '{print $1}')
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/config.after.sha256" "${after_hash}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/service.after.sha256" "${after_service_hash}"
  [[ "${after_hash}" == "${before_hash}" ]]
  [[ "${after_service_hash}" == "${before_service_hash}" ]]
  grep -Fqx 'sing-box version 1.14.0' <(sing-box version)
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/after.check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt" systemctl status sing-box --no-pager
  backup_path=$(jq -r '.backup' "${upgrade_path}")
  case "${backup_path}" in
    /root/sing-box-vps-backups/upgrade-*) ;;
    *) return 1 ;;
  esac
  test -d "${backup_path}"
  test -f "${backup_path}/runtime/config.json"
  test -f "${backup_path}/sing-box"
  test -f "${backup_path}/sing-box.service"
  grep -Fq '  runtime/protocols/index.env' "${backup_path}/SHA256SUMS"
  grep -Fq '  runtime/protocols/vless-reality.env' "${backup_path}/SHA256SUMS"
  grep -Fq '  metadata.json' "${backup_path}/SHA256SUMS"
  (cd "${backup_path}" && sha256sum -c SHA256SUMS >/dev/null)
  [[ "$(sha256sum "${backup_path}/runtime/config.json" | awk '{print $1}')" == "${before_hash}" ]]
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/after.status.json" sbv agent status --json
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/journalctl.txt" journalctl -u sing-box -n 100 --no-pager
  verification_run_protocol_probes
  verification_mark_step upgrade_verified
}
