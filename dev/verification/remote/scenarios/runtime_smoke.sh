verification_scenario_runtime_smoke() {
  local current_port
  local current_protocols
  local current_protocol
  local listener_artifact
  local status_output_path

  printf 'SCENARIO=runtime_smoke\n'
  test -f /root/sing-box-vps/config.json
  test -f /root/sing-box-vps/protocols/index.env
  test -x /usr/local/bin/sbv
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  current_protocols=$(sed -n 's/^INSTALLED_PROTOCOLS=//p' /root/sing-box-vps/protocols/index.env | head -n 1)
  [[ -n "${current_port}" ]]
  [[ -n "${current_protocols}" ]]
  current_protocol=$(printf '%s\n' "${current_protocols}" | cut -d ',' -f 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  current_protocol=$(verification_protocol_canonical_id "${current_protocol}")
  verification_wait_for_service_active sing-box
  printf 'SERVICE_ACTIVE=%s\n' "$(systemctl is-active sing-box)"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt" systemctl status sing-box --no-pager
  cat "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/systemctl.status.txt")"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/journalctl.txt" journalctl -u sing-box -n 100 --no-pager
  cat "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/journalctl.txt")"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  if verification_protocol_metadata "${current_protocol}" | jq -e \
    '.listen_networks | type == "array" and index("udp") != null' >/dev/null; then
    listener_artifact="${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lunp.txt"
    verification_assert_udp_port_listening "${current_port}" "${listener_artifact}"
  else
    listener_artifact="${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
    verification_assert_port_listening "${current_port}" "${listener_artifact}"
  fi
  cat "$(verification_artifact_path "${listener_artifact}")"
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq '运行状态摘要' "${status_output_path}"
  grep -Fq 'sing-box: active' "${status_output_path}"
  grep -Fq 'Warp:' "${status_output_path}"
  grep -Fq '配置文件: /root/sing-box-vps/config.json' "${status_output_path}"
  ! grep -Fq '协议:' "${status_output_path}"
  ! grep -Fq '地址:' "${status_output_path}"
  ! grep -Fq '端口:' "${status_output_path}"
  verification_run_protocol_probes
}
