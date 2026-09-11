verification_scenario_runtime_smoke() {
  local current_port
  local current_protocols
  local current_protocol
  local listener_artifact
  local status_output_path
  local shadowtls_handshake_pid=''
  local shadowtls_handshake_server
  local shadowtls_handshake_port
  local shadowtls_certificate_path
  local shadowtls_key_path
  local shadowtls_cover_stdout
  local shadowtls_cover_stderr

  printf 'SCENARIO=runtime_smoke\n'
  trap 'set +e; if [[ -n "${shadowtls_handshake_pid:-}" ]]; then kill "${shadowtls_handshake_pid}" 2>/dev/null || true; wait "${shadowtls_handshake_pid}" 2>/dev/null || true; fi; trap - RETURN' RETURN
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

  # A ShadowTLS loopback handshake target is a test-only TLS cover dependency,
  # not a service managed by sing-box.  Recreate it for the final smoke pass
  # after the preceding scenario has cleaned up its child processes, so the
  # composite ShadowTLS probe remains a real data-plane check.
  if printf '%s\n' "${current_protocols}" | tr ',' '\n' | grep -Fxq shadowtls; then
    shadowtls_handshake_server=$(jq -er '
      [.inbounds[] | select(.type == "shadowtls")][0].handshake.server // empty
    ' /root/sing-box-vps/config.json)
    shadowtls_handshake_port=$(jq -er '
      [.inbounds[] | select(.type == "shadowtls")][0].handshake.server_port // empty
    ' /root/sing-box-vps/config.json)
    if [[ "${shadowtls_handshake_server}" == 127.* ||
          "${shadowtls_handshake_server}" == ::1 ||
          "${shadowtls_handshake_server}" == localhost ]]; then
      shadowtls_certificate_path=$(jq -er '
        [.instances[] | select(.tag == "shadowtls-in")][0].client_tls.certificate_path // empty
      ' /root/sing-box-vps/protocols/instances/shadowtls.json)
      shadowtls_key_path="${shadowtls_certificate_path%/*}/key.pem"
      [[ -f "${shadowtls_certificate_path}" && -f "${shadowtls_key_path}" ]]
      if ! verification_port_is_listening "${shadowtls_handshake_port}"; then
        shadowtls_cover_stdout=$(verification_artifact_path \
          "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.stdout.txt")
        shadowtls_cover_stderr=$(verification_artifact_path \
          "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.stderr.txt")
        openssl s_server -accept "${shadowtls_handshake_port}" \
          -cert "${shadowtls_certificate_path}" \
          -key "${shadowtls_key_path}" -www -quiet \
          >"${shadowtls_cover_stdout}" 2>"${shadowtls_cover_stderr}" &
        shadowtls_handshake_pid=$!
        for _ in {1..50}; do
          if verification_port_is_listening "${shadowtls_handshake_port}"; then
            break
          fi
          kill -0 "${shadowtls_handshake_pid}" 2>/dev/null || return 1
          sleep 0.1
        done
        verification_assert_port_listening "${shadowtls_handshake_port}" \
          "${VERIFY_CURRENT_SCENARIO_DIR}/shadowtls-cover.ss-lntp.txt"
      fi
    fi
  fi

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
