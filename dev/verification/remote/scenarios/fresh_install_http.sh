verification_scenario_fresh_install_http() {
  local expected_port=1082
  local config_file=/root/.sing-box-vps/runtime/config.json
  local state_file=/root/.sing-box-vps/runtime/protocols/http.env
  local store_file=/root/.sing-box-vps/runtime/protocols/instances/http.json
  local empty_artifact_dir

  verification_prepare_remote_local_tree
  trap 'verification_cleanup_remote_local_tree; trap - RETURN' RETURN
  printf 'SCENARIO=fresh_install_http\n'
  bash "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" --yes || \
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" --internal-uninstall-purge --yes
  test ! -e "${config_file}"
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<EOF
1

6
${expected_port}
y
http-user
http-pass
n
0
EOF

  test -x /usr/local/bin/sbv
  test -f /etc/systemd/system/sing-box.service
  grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${state_file}"
  jq -e '.protocol=="http" and .revision==1 and (.instances|length)==1 and
    .instances[0].id=="main" and .instances[0].tag=="http-in" and
    .instances[0].listen=={address:"::",port:1082} and
    .instances[0].authentication=={enabled:true,username:"http-user",password:"http-pass"} and
    .instances[0].tls=={enabled:false}' "${store_file}" >/dev/null
  jq -e --argjson port "${expected_port}" '
    ([.inbounds[] | select(.type=="http")][0]) as $inbound |
    $inbound.listen=="::" and $inbound.listen_port==$port and
    $inbound.users==[{username:"http-user",password:"http-pass"}] and
    ($inbound|has("tls")|not)' "${config_file}" >/dev/null
  grep -Fqx 'INSTALLED_PROTOCOLS=http' /root/.sing-box-vps/runtime/protocols/index.env
  jq -e '(.inbounds|length)==1 and .inbounds[0].type=="http"' \
    "${config_file}" >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.ss-lntp.txt"
  verification_run_protocol_probes

  # An empty retained store is a supported install baseline. Exercise the
  # actual main-menu route, preserving the CAS revision across recreation.
  empty_artifact_dir=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/empty-delete.json")
  empty_artifact_dir=${empty_artifact_dir%/*}
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent instance delete http --json --yes \
    --expected-revision 1 --id main > "${empty_artifact_dir}/empty-delete.json"
  jq -e '.ok==true and .revision==2' "${empty_artifact_dir}/empty-delete.json" >/dev/null
  jq -e '.revision==2 and (.instances|length)==0' "${store_file}" >/dev/null
  sing-box check -c "${config_file}"
  cp "${config_file}" "${VERIFY_REMOTE_LOCAL_TREE_DIR}/empty-config.json"
  cp "${store_file}" "${VERIFY_REMOTE_LOCAL_TREE_DIR}/empty-store.json"
  # Older installs may have removed the empty index entirely.
  rm -f /root/.sing-box-vps/runtime/protocols/index.env
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" > "${empty_artifact_dir}/empty-cancel.txt" 2>&1 <<'EOF'
1
0
0
EOF
  grep -Fq '当前已安装协议: 无' "${empty_artifact_dir}/empty-cancel.txt"
  ! grep -Fq '检测到残缺的现有实例' "${empty_artifact_dir}/empty-cancel.txt"
  cmp "${config_file}" "${VERIFY_REMOTE_LOCAL_TREE_DIR}/empty-config.json"
  cmp "${store_file}" "${VERIFY_REMOTE_LOCAL_TREE_DIR}/empty-store.json"
  test ! -e /root/.sing-box-vps/runtime/protocols/index.env

  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" > "${empty_artifact_dir}/empty-recreate.txt" 2>&1 <<EOF
1
6
Recreated HTTP
main
http-in
127.0.0.1
${expected_port}
y
http-user
http-pass
n
0
EOF
  ! grep -Fq '检测到残缺的现有实例' "${empty_artifact_dir}/empty-recreate.txt"
  jq -e '.revision==3 and (.instances|length)==1 and .instances[0].id=="main"' "${store_file}" >/dev/null
  grep -Fqx 'INSTALLED_PROTOCOLS=http' /root/.sing-box-vps/runtime/protocols/index.env
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/recreated-sing-box-check.txt" \
    sing-box check -c "${config_file}"
  verification_assert_port_listening "${expected_port}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/recreated-listeners.ss-lntp.txt"
  verification_run_protocol_probes
}
