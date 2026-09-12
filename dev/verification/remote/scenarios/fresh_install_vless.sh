verification_scenario_fresh_install_vless() {
  local config_uuid
  local env_uuid
  local instance_state_file=/root/sing-box-vps/protocols/vless-reality.d/main.env
  local current_port
  local expected_port=443
  local status_output_path
  local version_output_path

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_vless\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e /root/sing-box-vps/config.json
  test ! -e /etc/systemd/system/sing-box.service
  test ! -e /usr/local/bin/sbv
  SB_REALITY_SNI_VALIDATION_ASSUME_YES=1 bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'EOF'
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
  verification_mark_step fresh_install_vless_after_install
  test -f /root/sing-box-vps/config.json
  test -f /etc/systemd/system/sing-box.service
  test -x /usr/local/bin/sbv
  test -f /root/sing-box-vps/protocols/index.env
  test -f /root/sing-box-vps/protocols/vless-reality.env
  test -f "${instance_state_file}"
  verification_mark_step fresh_install_vless_files_present
  current_port=$(jq -r '.inbounds[0].listen_port // empty' /root/sing-box-vps/config.json)
  config_uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' /root/sing-box-vps/config.json)
  env_uuid=$(grep '^UUID=' "${instance_state_file}" | cut -d'=' -f2- || true)
  verification_mark_step fresh_install_vless_values_loaded
  [[ "${current_port}" == "${expected_port}" ]]
  grep -Fqx 'INSTALLED_PROTOCOLS=vless-reality' /root/sing-box-vps/protocols/index.env
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'DEFAULT_INSTANCE_ID=main' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'INSTANCE_IDS=main' /root/sing-box-vps/protocols/vless-reality.env
  grep -Fqx 'PORT=443' "${instance_state_file}"
  grep -Fqx 'SNI=www.cloudflare.com' "${instance_state_file}"
  verification_mark_step fresh_install_vless_static_asserts
  [[ -n "${config_uuid}" ]]
  [[ "${config_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  [[ -n "${env_uuid}" ]]
  [[ "${env_uuid}" == "${config_uuid}" ]]
  [[ "${env_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]
  ! grep -Fq 'stale.example.com' "${instance_state_file}"
  verification_mark_step fresh_install_vless_uuid_asserts
  verification_wait_for_service_active sing-box
  verification_mark_step fresh_install_vless_service_active
  version_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box.version.txt")
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box.version.txt" sing-box version
  grep -Fqx 'sing-box version 1.14.0' "${version_output_path}"
  verification_mark_step fresh_install_vless_version_checked
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" sing-box check -c /root/sing-box-vps/config.json
  verification_mark_step fresh_install_vless_config_checked
  verification_assert_port_listening "${expected_port}" "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_mark_step fresh_install_vless_port_listening
  verification_capture_status_menu "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt"
  status_output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/sbv-status.txt")
  grep -Fq '运行状态摘要' "${status_output_path}"
  grep -Fq 'sing-box: active' "${status_output_path}"
  grep -Fq 'Warp: 未开启' "${status_output_path}"
  grep -Fq '配置文件: /root/sing-box-vps/config.json' "${status_output_path}"
  ! grep -Fq '协议:' "${status_output_path}"
  ! grep -Fq '地址:' "${status_output_path}"
  ! grep -Fq '端口:' "${status_output_path}"
  verification_mark_step fresh_install_vless_status_menu
  verification_run_protocol_probes
  verification_mark_step fresh_install_vless_protocol_probes

  # The privileged verification container can exercise the core-owned part of
  # a Linux TUN lifecycle.  The component transaction itself remains the
  # owner of state/config/service rollback; host PREROUTING policy is not
  # installed or inferred here.
  local tun_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-record.json"
  local tun_create_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-create.json"
  local tun_delete_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-delete.json"
  local tun_diagnose_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-diagnose.json"
  local tun_after_delete_diagnose_json="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tun-resource-after-delete-diagnose.json"
  (umask 077; jq -n '{id:"tun-resource-verification",role:"inbound",type:"tun",
    tag:"tun-resource-verification",enabled:true,route_rules:[],config:{
    interface_name:"sbv-tun",address:["172.19.0.1/30"],auto_route:true,
    strict_route:true}}' > "${tun_record}")
  bash /usr/local/bin/sbv agent component create --json --yes --allow-public \
    --expected-revision 0 --file "${tun_record}" > "${tun_create_json}"
  verification_capture_file_if_present "${tun_create_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-create.json"
  jq -e '.ok==true and .operation=="create" and .revision==1 and
    .type=="tun" and .service_restarted==true' "${tun_create_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_component_created
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-check.txt" \
    sing-box check -c /root/sing-box-vps/config.json
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-interface.json" \
    ip -j link show dev sbv-tun
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules.json" \
    ip -j rule show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes.json" \
    ip -j route show table all
  jq -e 'any(.[]; .ifname == "sbv-tun")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-interface.json")" >/dev/null
  jq -e 'any(.[]; (.priority == 9000) and ((.table // "" | tostring) == "2022"))' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules.json")" >/dev/null
  jq -e 'any(.[]; ((.table // "main" | tostring) == "2022") and .dev == "sbv-tun")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes.json")" >/dev/null
  bash /usr/local/bin/sbv agent component diagnose --json > "${tun_diagnose_json}"
  verification_capture_file_if_present "${tun_diagnose_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-diagnose.json"
  jq -e '.ok==true and .data.transparent_resources.status=="available" and
    .data.transparent_resources.service_active==true and
    ([.data.transparent_resources.resources[] | select(.type=="tun" and
      .interface.status=="present" and .policy_routing.status=="present" and
      .rule.status=="present")] | length == 1)' "${tun_diagnose_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_resources_observed

  bash /usr/local/bin/sbv agent component delete --json --yes \
    --expected-revision 1 --id tun-resource-verification > "${tun_delete_json}"
  verification_capture_file_if_present "${tun_delete_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-delete.json"
  jq -e '.ok==true and .operation=="delete" and .revision==2 and
    .id=="tun-resource-verification" and .service_restarted==true' \
    "${tun_delete_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_component_deleted
  verification_wait_for_service_active sing-box
  verification_capture_best_effort_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-interface-after-delete.json" \
    ip -j link show dev sbv-tun
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules-after-delete.json" \
    ip -j rule show
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes-after-delete.json" \
    ip -j route show table all
  if ip -j link show dev sbv-tun >/dev/null 2>&1; then
    printf 'TUN interface remained after managed component deletion\n' >&2
    return 1
  fi
  ! jq -e 'any(.[]; (.priority == 9000) and ((.table // "" | tostring) == "2022"))' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-rules-after-delete.json")" >/dev/null
  ! jq -e 'any(.[]; ((.table // "main" | tostring) == "2022") and .dev == "sbv-tun")' \
    "$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/tun-routes-after-delete.json")" >/dev/null
  bash /usr/local/bin/sbv agent component diagnose --json > "${tun_after_delete_diagnose_json}"
  verification_capture_file_if_present "${tun_after_delete_diagnose_json}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tun-resource-after-delete-diagnose.json"
  jq -e '.ok==true and .data.transparent_resources.status=="available" and
    (.data.transparent_resources.resources | length == 0)' \
    "${tun_after_delete_diagnose_json}" >/dev/null
  verification_mark_step fresh_install_vless_tun_resources_cleaned
}
