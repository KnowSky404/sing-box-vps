verification_scenario_upgrade_rollback_1_13_to_1_14() {
  local legacy_install
  local dropin_dir=/etc/systemd/system/sing-box.service.d
  local dropin_path="${dropin_dir}/verification-version-gate.conf"
  local before_hash
  local before_service_hash
  local after_service_hash
  local upgrade_status=0
  local upgrade_path
  local transaction_result_path
  local transaction_manifest_path
  local transaction_manifest_sha256

  verification_prepare_remote_local_tree
  trap 'rm -f "${legacy_install:-}" "${dropin_path}"; systemctl daemon-reload >/dev/null 2>&1 || true; verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=upgrade_rollback_1_13_to_1_14\n'

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
  install -m 0755 "${VERIFY_REMOTE_INSTALL_SCRIPT}" /usr/local/bin/sbv

  grep -Fqx 'sing-box version 1.13.18' <(sing-box version)
  before_hash=$(sha256sum /root/sing-box-vps/config.json | awk '{print $1}')
  before_service_hash=$(sha256sum /etc/systemd/system/sing-box.service | awk '{print $1}')
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/config.before.sha256" "${before_hash}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/service.before.sha256" "${before_service_hash}"
  mkdir -p "${dropin_dir}"
  cat > "${dropin_path}" <<'EOF_DROPIN'
[Service]
ExecStartPre=
ExecStartPre=/bin/sh -c 'case "$(/usr/local/bin/sing-box version 2>/dev/null)" in *1.14.0*) exit 1 ;; *) exit 0 ;; esac'
EOF_DROPIN
  systemctl daemon-reload

  upgrade_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/upgrade.json")
  set +e
  sbv agent upgrade --json 1.14.0 --yes > "${upgrade_path}"
  upgrade_status=$?
  set -e
  [[ "${upgrade_status}" != "0" ]]
  jq -e '
    .schema_version == "1.0" and
    .ok == false and
    .rolled_back == true and
    .installed == "1.13.18" and
    .config_preserved == true and
    .service.after == "active" and
    .transaction.result_persisted == true and
    .transaction.status == "rolled_back" and
    .check.ok == true
  ' "${upgrade_path}" >/dev/null
  transaction_result_path=$(jq -r '.transaction.result_path' "${upgrade_path}")
  [[ "${transaction_result_path}" == /root/sing-box-vps-backups/upgrade-*/transaction-result.json ]]
  [[ "$(stat -c '%a' "${transaction_result_path}")" == "600" ]]
  jq -e '
    .schema_version == "1.0" and
    .status == "rolled_back" and
    .old_version == "1.13.18" and
    .new_version == "1.14.0" and
    .rollback.attempted == true and
    .rollback.result == "success"
  ' "${transaction_result_path}" >/dev/null
  transaction_manifest_path=$(jq -r '.manifest_path' "${transaction_result_path}")
  transaction_manifest_sha256=$(jq -r '.manifest_sha256' "${transaction_result_path}")
  case "${transaction_manifest_path}" in
    /root/sing-box-vps-backups/upgrade-*/SHA256SUMS) ;;
    *) return 1 ;;
  esac
  [[ "${transaction_manifest_sha256}" == "$(sha256sum "${transaction_manifest_path}" | awk '{print $1}')" ]]
  jq -e --arg path "${transaction_manifest_path}" --arg sha256 "${transaction_manifest_sha256}" \
    '.manifest.path == $path and .manifest.sha256 == $sha256' \
    "${transaction_result_path}" >/dev/null
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/transaction-result.json" \
    cat "${transaction_result_path}"
  grep -Fqx 'sing-box version 1.13.18' <(sing-box version)
  [[ "$(sha256sum /root/sing-box-vps/config.json | awk '{print $1}')" == "${before_hash}" ]]
  after_service_hash=$(sha256sum /etc/systemd/system/sing-box.service | awk '{print $1}')
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/config.after.sha256" "${before_hash}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/service.after.sha256" "${after_service_hash}"
  [[ "${after_service_hash}" == "${before_service_hash}" ]]
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/after.version.txt" \
    sing-box version
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt" \
    systemctl status sing-box --no-pager
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/after-rollback.check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_wait_for_service_active sing-box
  verification_run_protocol_probes
}
