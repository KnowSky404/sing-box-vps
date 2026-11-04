# Direct and transparent-policy assertions shared by aggregate and leaf scenes.
# Definitions only: sourcing never creates listeners, namespaces or host policy.
verification_policy_validate_revision() {
  [[ "${1:-}" =~ ^(0|[1-9][0-9]{0,14})$ ]] || {
    printf '[ERROR] policy case requires a bounded explicit revision.\n' >&2
    return 2
  }
}

verification_case_direct_inbound() {
  local base_revision=${1:?expected component revision required} mode=${2:-delete}
  verification_policy_validate_revision "${base_revision}" || return $?
  [[ "${mode}" == retain || "${mode}" == delete ]] || return 2
  local config_path
  local direct_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-record.json"
  local direct_response="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-response.txt"
  local direct_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-curl.stderr.txt"
  local direct_udp_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-record.json"
  local direct_udp_response="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-response.txt"
  local direct_udp_response_path
  local direct_udp_client_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-client.stderr.txt"
  # Fixtures may already be active in the aggregate; shared setup is idempotent.
  verification_fixture_tcp_marker
  verification_fixture_udp_echo
  (umask 077; jq -n --argjson marker_port "${direct_marker_port}" '
    {id:"direct-inbound-verification",role:"inbound",type:"direct",
     tag:"direct-inbound-verification",enabled:true,route_rules:[],
     config:{listen:"127.0.0.1",listen_port:1092,network:"tcp",
       override_address:"127.0.0.1",override_port:$marker_port}}
  ' > "${direct_record}")
  local direct_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "${base_revision}" --file "${direct_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-create.json"
  direct_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-create.json"
  if [[ "${direct_create_status}" != "0" ]]; then
    return "${direct_create_status}"
  fi
  jq -e --argjson revision "$((base_revision + 1))" '.ok==true and .operation=="create" and .revision==$revision and .type=="direct"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-create.json" >/dev/null
  verification_mark_step direct-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_mark_step direct-inbound-service-active
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_mark_step direct-inbound-config-checked
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson marker_port "${direct_marker_port}" '
    ([.inbounds[] | select(.type == "direct" and .tag == "direct-inbound-verification" and
      .listen == "127.0.0.1" and .listen_port == 1092 and .network == "tcp" and
      .override_address == "127.0.0.1" and .override_port == $marker_port)] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step direct-inbound-config-asserted
  verification_assert_port_listening 1092 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.direct-inbound.ss-lntp.txt"
  set +e
  curl --fail --silent --show-error --max-time 5 --noproxy '*' \
    "http://127.0.0.1:1092/" \
    > "$(verification_artifact_path "${direct_response}")" \
    2> "$(verification_artifact_path "${direct_curl_stderr}")"
  local direct_curl_status=$?
  set -e
  [[ "${direct_curl_status}" == "0" ]]
  grep -Fqx "${direct_marker}" "$(verification_artifact_path "${direct_response}")"
  verification_mark_step direct-inbound-curl-complete

  (umask 077; jq -n --argjson marker_port "${direct_udp_marker_port}" '
    {id:"direct-udp-inbound-verification",role:"inbound",type:"direct",
     tag:"direct-udp-inbound-verification",enabled:true,route_rules:[],
     config:{listen:"127.0.0.1",listen_port:1093,network:"udp",
       override_address:"127.0.0.1",override_port:$marker_port}}
  ' > "${direct_udp_record}")
  local direct_udp_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "$((base_revision + 1))" --file "${direct_udp_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-create.json"
  direct_udp_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-udp-create.json"
  if [[ "${direct_udp_create_status}" != "0" ]]; then
    return "${direct_udp_create_status}"
  fi
  jq -e --argjson revision "$((base_revision + 2))" '.ok==true and .operation=="create" and .revision==$revision and .type=="direct"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/direct-udp-create.json" >/dev/null
  verification_mark_step direct-udp-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_mark_step direct-udp-inbound-service-active
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_mark_step direct-udp-inbound-config-checked
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e --argjson marker_port "${direct_udp_marker_port}" '
    ([.inbounds[] | select(.type == "direct" and .tag == "direct-udp-inbound-verification" and
      .listen == "127.0.0.1" and .listen_port == 1093 and .network == "udp" and
      .override_address == "127.0.0.1" and .override_port == $marker_port)] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step direct-udp-inbound-config-asserted
  verification_assert_udp_port_listening 1093 \
    "${VERIFY_CURRENT_SCENARIO_DIR}/listeners.direct-udp-inbound.ss-lunp.txt"
  direct_udp_response_path=$(verification_artifact_path "${direct_udp_response}")
  set +e
  python3 - "${direct_udp_response_path}" "${direct_udp_marker}" \
    > /dev/null 2> "$(verification_artifact_path "${direct_udp_client_stderr}")" <<'PY'
import pathlib
import socket
import sys

response_path, marker = sys.argv[1:]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
    client.settimeout(5)
    client.sendto(marker.encode(), ("127.0.0.1", 1093))
    payload, _ = client.recvfrom(65535)
pathlib.Path(response_path).write_bytes(payload)
PY
  local direct_udp_client_status=$?
  set -e
  [[ "${direct_udp_client_status}" == "0" ]]
  grep -Fqx "${direct_udp_marker}" "${direct_udp_response_path}"
  verification_mark_step direct-udp-inbound-client-complete

  if [[ "${mode}" == delete ]]; then
    verification_policy_delete_direct direct-udp-inbound-verification "$((base_revision + 2))"
    verification_policy_delete_direct direct-inbound-verification "$((base_revision + 3))"
    verification_assert_port_not_listening 1092 "${VERIFY_CURRENT_SCENARIO_DIR}/direct-after-delete.ss-lntp.txt"
    if verification_udp_port_is_listening 1093; then
      printf '[ERROR] deleted Direct UDP listener remains active.\n' >&2
      return 1
    fi
    verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/direct-after-delete.ss-lunp.txt" ss -lunp
  fi
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/direct-final-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_wait_for_service_active sing-box
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound.result.env" \
    'COMPONENT=direct-inbound' 'RESULT=success' 'DATA_PLANE=direct_tcp_override_loopback' "LIFECYCLE=${mode}"
  verification_write_artifact "${VERIFY_CURRENT_SCENARIO_DIR}/direct-inbound-udp.result.env" \
    'COMPONENT=direct-inbound' 'RESULT=success' 'DATA_PLANE=direct_udp_override_loopback' "LIFECYCLE=${mode}"
}

verification_policy_delete_direct() {
  local component_id=$1 expected_revision=$2 output
  verification_policy_validate_revision "${expected_revision}" || return $?
  output=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/${component_id}-delete.json")
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "${expected_revision}" --id "${component_id}" > "${output}"
  jq -e --arg id "${component_id}" --argjson revision "$((expected_revision + 1))" \
    '.ok==true and .operation=="delete" and .id==$id and .revision==$revision' "${output}" >/dev/null
  jq -e --arg id "${component_id}" '
    all(.inbounds[]; .tag!=$id) and all(.route.rules[]?; ((.inbound // []) | index($id) | not))
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_mark_step "${component_id}-deleted"
}

verification_case_redirect_create() {
  local base_revision=${1:?expected component revision required}
  verification_policy_validate_revision "${base_revision}" || return $?
  verification_prepare_redirect_policy_fixture VERIFY_REDIRECT_MARKER_PID
  local redirect_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-record.json"
  (umask 077; jq -n --arg interface "${VERIFY_REDIRECT_HOST_VETH}" \
    --argjson destination_port "${VERIFY_REDIRECT_MARKER_PORT}" \
    '{id:"redirect-inbound-verification",role:"inbound",type:"redirect",
      tag:"redirect-inbound-verification",enabled:true,route_rules:[],
      config:{listen:"0.0.0.0",listen_port:1094},
      host_policy:{ingress_interface:$interface,destination_ports:[$destination_port],
        management_ports:[22,2222,1094]}}' > "${redirect_record}")
  local redirect_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes --allow-public \
    --expected-revision "${base_revision}" --file "${redirect_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json"
  redirect_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-create.json"
  [[ "${redirect_create_status}" == 0 ]]
  jq -e --argjson revision "$((base_revision + 1))" '.ok==true and .operation=="create" and .revision==$revision and .type=="redirect"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json" >/dev/null
  jq -e '.redirect_host_policy.status == "available" and
    (.redirect_host_policy.resources | length) == 1 and
    .redirect_host_policy.resources[0].status == "present" and
    .redirect_host_policy.resources[0].resource_scope == "installer_owned_ipv4_tcp_prerouting"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-create.json" >/dev/null
  verification_mark_step redirect-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-inbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_execute_redirect_probe /root/.sing-box-vps/runtime/config.json 1094 \
    "${VERIFY_REDIRECT_MARKER_PORT}" "${VERIFY_REDIRECT_MARKER}"
  verification_mark_step redirect-inbound-probe-complete

}

verification_case_tproxy_create_probe() {
  local base_revision=${1:?expected component revision required}
  verification_policy_validate_revision "${base_revision}" || return $?
  local tproxy_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-record.json"
  (umask 077; jq -n '{id:"tproxy-inbound-verification",role:"inbound",type:"tproxy",
    tag:"tproxy-inbound-verification",enabled:true,route_rules:[],
    config:{listen:"0.0.0.0",listen_port:1095,network:["tcp","udp"]}}' > "${tproxy_record}")
  local tproxy_create_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes --allow-public \
    --expected-revision "${base_revision}" --file "${tproxy_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-create.json"
  tproxy_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-create.json"
  [[ "${tproxy_create_status}" == 0 ]]
  jq -e --argjson revision "$((base_revision + 1))" '.ok==true and .operation=="create" and .revision==$revision and .type=="tproxy"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-create.json" >/dev/null
  verification_mark_step tproxy-inbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-inbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_execute_tproxy_probe /root/.sing-box-vps/runtime/config.json 1095 managed "$((base_revision + 1))"
  verification_mark_step tproxy-inbound-probe-complete

}

verification_case_transparent_diagnose() {
  local mode=${1:-both}
  [[ "${mode}" == both || "${mode}" == tproxy ]] || return 2
  local transparent_diagnose
  transparent_diagnose=$(bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component diagnose --json)
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/transparent-component-diagnose.json" \
    "${transparent_diagnose}"
  jq -e --arg mode "${mode}" '
    .ok == true and
    (if $mode == "both" then
      .data.redirect_host_policy.status == "available" and
      (.data.redirect_host_policy.resources | length) == 1 and
      .data.redirect_host_policy.resources[0].status == "present"
     else true end) and
    .data.tproxy_host_policy.status == "available" and
    (.data.tproxy_host_policy.resources | length) == 1 and
    .data.tproxy_host_policy.resources[0].status == "present" and
    .data.tproxy_host_policy.resources[0].resource_scope == "installer_owned_ipv4_tcp_udp_prerouting_policy_route" and
    all(.data.tproxy_host_policy.operator_managed[]; .id != "tproxy-inbound-verification") and
    (if $mode == "both" then
      any(.data.components[]; .id == "redirect-inbound-verification" and
        .instance_environment.requirements.requires_root == true and
        .instance_environment.requirements.requires_tun_device == false)
     else true end) and
    any(.data.components[]; .id == "tproxy-inbound-verification" and
      .instance_environment.requirements.requires_root == true and
      .instance_environment.requirements.requires_tun_device == false)
  ' <<< "${transparent_diagnose}" >/dev/null

}

verification_case_tproxy_delete() {
  local expected_revision=${1:?expected component revision required}
  verification_policy_validate_revision "${expected_revision}" || return $?
  ((expected_revision >= 1)) || return 2
  local tproxy_delete_status=0
  local tproxy_revision tproxy_chain tproxy_marker tproxy_route_table tproxy_rule_priority
  local tproxy_policy_artifact tproxy_mangle_after_delete_artifact
  tproxy_policy_artifact=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/managed-host-policy-revision-$((expected_revision - 1)).json")
  tproxy_revision=$(jq -r '.revision' \
    "${tproxy_policy_artifact}")
  tproxy_chain=$(jq -r '.tproxy_host_policy.resources[0].chain' \
    "${tproxy_policy_artifact}")
  tproxy_marker=$(jq -r '.tproxy_host_policy.resources[0].marker' \
    "${tproxy_policy_artifact}")
  tproxy_route_table=$(jq -r '.tproxy_host_policy.resources[0].route_table' \
    "${tproxy_policy_artifact}")
  tproxy_rule_priority=$(jq -r '.tproxy_host_policy.resources[0].rule_priority' \
    "${tproxy_policy_artifact}")
  [[ "${tproxy_revision}" == "${expected_revision}" ]]
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "${tproxy_revision}" --id tproxy-inbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-delete.json"
  tproxy_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-delete.json"
  [[ "${tproxy_delete_status}" == 0 ]]
  jq -e --argjson revision "$((expected_revision + 1))" '.ok==true and .operation=="delete" and .revision==$revision and .id=="tproxy-inbound-verification" and
    .tproxy_host_policy.status == "not_configured" and
    (.tproxy_host_policy.resources | length) == 0' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tproxy-delete.json" >/dev/null
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/mangle.after-delete.txt" \
    iptables -t mangle -S
  tproxy_mangle_after_delete_artifact=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/transparent/tproxy/mangle.after-delete.txt")
  if grep -F -- "${tproxy_chain}" "${tproxy_mangle_after_delete_artifact}" >/dev/null ||
     grep -F -- "${tproxy_marker}" "${tproxy_mangle_after_delete_artifact}" >/dev/null; then
    printf '[ERROR] Managed TProxy mangle resources remained after component deletion.\n' >&2
    return 1
  fi
  if ip -4 rule show | awk -v priority="${tproxy_rule_priority}:" '$1 == priority { found=1 } END { exit !found }'; then
    printf '[ERROR] Managed TProxy policy rule remained after component deletion.\n' >&2
    return 1
  fi
  if [[ -n "$(ip -4 route show table "${tproxy_route_table}")" ]]; then
    printf '[ERROR] Managed TProxy route table remained populated after component deletion.\n' >&2
    return 1
  fi
  verification_cleanup_tproxy_probe_fixture
  jq -e '
    all(.inbounds[]; .tag!="tproxy-inbound-verification")
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_assert_port_not_listening 1095 "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-after-delete.ss-lntp.txt"
  if verification_udp_port_is_listening 1095; then
    printf '[ERROR] deleted TProxy UDP listener remains active.\n' >&2
    return 1
  fi
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tproxy-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_wait_for_service_active sing-box
  verification_mark_step tproxy-component-and-policy-deleted
}

verification_case_redirect_delete() {
  local expected_revision=${1:?expected component revision required}
  verification_policy_validate_revision "${expected_revision}" || return $?
  local redirect_delete_status=0
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "${expected_revision}" --id redirect-inbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-delete.json"
  redirect_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-delete.json"
  [[ "${redirect_delete_status}" == 0 ]]
  jq -e --argjson revision "$((expected_revision + 1))" '.ok==true and .operation=="delete" and .revision==$revision and .id=="redirect-inbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/redirect-delete.json" >/dev/null
  verification_assert_redirect_policy_removed
  verification_cleanup_redirect_policy_fixture
  if ip link show dev sbv-rph0 >/dev/null 2>&1 ||
     ip netns list | awk '$1 == "sbv-rpc" { found=1 } END { exit !found }'; then
    printf '[ERROR] Redirect verification veth/netns cleanup was incomplete.\n' >&2
    return 1
  fi
  verification_mark_step redirect-component-and-policy-deleted
  jq -e '
    ([.inbounds[] | select(.type == "redirect" and .tag == "redirect-inbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null

  verification_assert_port_not_listening 1094 "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-after-delete.ss-lntp.txt"
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/redirect-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_wait_for_service_active sing-box
}

verification_case_transparent_policy() {
  local base_revision=${1:?expected component revision required}
  verification_policy_validate_revision "${base_revision}" || return $?
  verification_case_redirect_create "${base_revision}"
  verification_case_tproxy_create_probe "$((base_revision + 1))"
  verification_case_transparent_diagnose both
  verification_case_tproxy_delete "$((base_revision + 4))"
  verification_case_redirect_delete "$((base_revision + 5))"
  verification_mark_step transparent-components-deleted
  jq -e '
    all(.inbounds[]; .tag!="redirect-inbound-verification" and .tag!="tproxy-inbound-verification")
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
}
