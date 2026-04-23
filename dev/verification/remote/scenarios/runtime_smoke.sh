verification_scenario_runtime_smoke() {
  local current_port
  local status_output_path

  printf 'SCENARIO=runtime_smoke\n'
  test -f /root/sing-box-vps/config.json
  test -f /root/sing-box-vps/protocols/index.env
  test -x /usr/local/bin/sbv
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  [[ -n "${current_port}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  systemctl is-active --quiet sing-box
  printf 'SERVICE_ACTIVE=%s\n' "$(systemctl is-active sing-box)"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt" systemctl status sing-box --no-pager
  cat "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt")"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/journalctl.txt" journalctl -u sing-box -n 100 --no-pager
  cat "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/journalctl.txt")"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_assert_port_listening "${current_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  cat "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt")"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq "端口: ${current_port}" "${status_output_path}"
  verification_run_protocol_probes
}
