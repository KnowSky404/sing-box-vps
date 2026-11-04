# Shared assertions for the aggregate and focused cases. Definitions only.
verification_scenario_managed_rule_sets() (
  set -euo pipefail
  local expected_revision=${1:-}
  local server_pid=''
  local server_port source_file remote_file
  local inline_record inline_replace_record inline_replace_response local_record remote_record
  local command_status revision component_id
  [[ "${expected_revision}" =~ ^[0-9]+$ ]] || return 1
  trap 'status=$?; trap - EXIT; if [[ -n "${server_pid:-}" ]] && kill -0 "${server_pid}" 2>/dev/null; then kill "${server_pid}" || status=1; wait "${server_pid}" || [[ $? == 143 ]] || status=1; fi; exit "${status}"' EXIT

  source_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-route-rules.json"
  remote_file="${VERIFY_REMOTE_LOCAL_TREE_DIR}/remote-route-rules.json"
  printf '%s\n' '{"version":1,"rules":[{"domain_suffix":["managed-rules.example.test"]}]}' > "${source_file}"
  cp "${source_file}" "${remote_file}"
  server_port=$(python3 - <<'PY'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.bind(("127.0.0.1", 0))
    print(listener.getsockname()[1])
PY
  )
  [[ "${server_port}" =~ ^[0-9]+$ ]]
  python3 -m http.server "${server_port}" --bind 127.0.0.1 \
    --directory "${VERIFY_REMOTE_LOCAL_TREE_DIR}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-rule-set-http.log" 2>&1 &
  server_pid=$!
  local server_ready=n
  for _ in {1..50}; do
    if curl --fail --silent \
      "http://127.0.0.1:${server_port}/" -o /dev/null; then
      server_ready=y
      break
    fi
    sleep 0.1
  done
  [[ "${server_ready}" == y ]] || {
    printf '[ERROR] local HTTP rule-set fixture did not become ready.\n' >&2
    return 1
  }

  inline_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-inline-rule-set.json"
  inline_replace_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-inline-rule-set-replacement-record.json"
  inline_replace_response="${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-inline-rule-set-replace-response.json"
  local_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-local-rule-set.json"
  remote_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-remote-rule-set.json"
  (umask 077; jq -n '{id:"managed-inline-rule-set-verification",role:"rule_set",type:"inline",
    tag:"verification-inline-rules",enabled:true,route_rules:[],
    config:{rules:[{domain_suffix:["inline-rules.example.test"]}]}}' > "${inline_record}")
  (umask 077; jq -n '{id:"managed-inline-rule-set-verification",role:"rule_set",type:"inline",
    tag:"verification-inline-rules",enabled:true,route_rules:[],
    config:{rules:[{domain_suffix:["replacement-rules.example.test"]}]}}' > "${inline_replace_record}")
  (umask 077; jq -n --arg path "${source_file}" '{id:"managed-local-rule-set-verification",
    role:"rule_set",type:"local",tag:"verification-local-rules",enabled:true,route_rules:[],
    config:{format:"source",path:$path}}' > "${local_record}")
  (umask 077; jq -n --arg url "http://127.0.0.1:${server_port}/remote-route-rules.json" \
    '{id:"managed-remote-rule-set-verification",role:"rule_set",type:"remote",
      tag:"verification-remote-rules",enabled:true,route_rules:[],
      config:{format:"source",url:$url}}' > "${remote_record}")

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "${expected_revision}" --file "${inline_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-inline-rule-set-create.json"
  command_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-inline-rule-set-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-inline-rule-set-create.json"
  [[ "${command_status}" == 0 ]]
  revision=$((expected_revision + 1))
  jq -e --argjson revision "${revision}" \
    '.ok==true and .operation=="create" and .revision==$revision and .role=="rule_set" and .type=="inline"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-inline-rule-set-create.json" >/dev/null
  verification_mark_step managed-inline-rule-set-created

  [[ "${inline_replace_record}" != "${inline_replace_response}" ]]
  jq -e '.id == "managed-inline-rule-set-verification" and
    .config.rules[0].domain_suffix == ["replacement-rules.example.test"]' \
    "${inline_replace_record}" >/dev/null
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component replace --json --yes \
    --expected-revision "${revision}" --file "${inline_replace_record}" \
    > "${inline_replace_response}"
  command_status=$?
  set -e
  verification_capture_file_if_present \
    "${inline_replace_response}" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-inline-rule-set-replace.json"
  [[ "${command_status}" == 0 ]]
  revision=$((revision + 1))
  jq -e --argjson revision "${revision}" \
    '.ok==true and .operation=="replace" and .revision==$revision and .type=="inline"' \
    "${inline_replace_response}" >/dev/null
  verification_mark_step managed-inline-rule-set-replaced

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "${revision}" --file "${local_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-local-rule-set-create.json"
  command_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-local-rule-set-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-local-rule-set-create.json"
  [[ "${command_status}" == 0 ]]
  revision=$((revision + 1))
  jq -e --argjson revision "${revision}" \
    '.ok==true and .operation=="create" and .revision==$revision and .type=="local"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-local-rule-set-create.json" >/dev/null
  verification_mark_step managed-local-rule-set-created

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "${revision}" --file "${remote_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-remote-rule-set-create.json"
  command_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-remote-rule-set-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-remote-rule-set-create.json"
  [[ "${command_status}" == 0 ]]
  revision=$((revision + 1))
  jq -e --argjson revision "${revision}" \
    '.ok==true and .operation=="create" and .revision==$revision and .type=="remote"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-remote-rule-set-create.json" >/dev/null
  verification_mark_step managed-remote-rule-set-created

  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-rule-sets-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  local managed_rule_sets_config
  managed_rule_sets_config=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-rule-sets-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${managed_rule_sets_config}"
  jq -e --arg source_path "${source_file}" \
    --arg remote_url "http://127.0.0.1:${server_port}/remote-route-rules.json" '
    (.route.rule_set | length == 3) and
    any(.route.rule_set[]; .tag == "verification-inline-rules" and .type == "inline" and
      .rules[0].domain_suffix == ["replacement-rules.example.test"]) and
    any(.route.rule_set[]; .tag == "verification-local-rules" and .type == "local" and
      .format == "source" and .path == $source_path) and
    any(.route.rule_set[]; .tag == "verification-remote-rules" and .type == "remote" and
      .format == "source" and .url == $remote_url)
  ' "${managed_rule_sets_config}" >/dev/null
  verification_mark_step managed-rule-sets-config-checked

  for _ in {1..50}; do
    if grep -Fq 'GET /remote-route-rules.json HTTP/1.1" 200 ' \
      "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-rule-set-http.log"; then
      break
    fi
    sleep 0.1
  done
  if ! grep -Fq 'GET /remote-route-rules.json HTTP/1.1" 200 ' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-rule-set-http.log"; then
    verification_capture_file_if_present \
      "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-rule-set-http.log" \
      "${VERIFY_CURRENT_SCENARIO_DIR}/managed-rule-set-http.log"
    printf '[ERROR] sing-box did not fetch the managed remote rule-set fixture successfully.\n' >&2
    return 1
  fi
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/managed-rule-set-http.log" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-rule-set-http.log"

  for component_id in managed-remote-rule-set-verification \
    managed-local-rule-set-verification managed-inline-rule-set-verification; do
    set +e
    bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
      --expected-revision "${revision}" --id "${component_id}" \
      > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/${component_id}-delete.json"
    command_status=$?
    set -e
    verification_capture_file_if_present \
      "${VERIFY_REMOTE_LOCAL_TREE_DIR}/${component_id}-delete.json" \
      "${VERIFY_CURRENT_SCENARIO_DIR}/${component_id}-delete.json"
    [[ "${command_status}" == 0 ]]
    revision=$((revision + 1))
    jq -e --argjson revision "${revision}" --arg id "${component_id}" \
      '.ok==true and .operation=="delete" and .revision==$revision and .id==$id' \
      "${VERIFY_REMOTE_LOCAL_TREE_DIR}/${component_id}-delete.json" >/dev/null
    verification_mark_step "${component_id}-deleted"
  done
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-rule-sets-final-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  jq -e '
    ([.route.rule_set[]? | select(.tag | startswith("verification-"))] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  [[ -f "${source_file}" && "${revision}" == "$((expected_revision + 7))" ]]
  verification_mark_step managed-route-rule-sets-removed
  verification_wait_for_service_active sing-box
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/managed-rule-sets.result.env" \
    'COMPONENT=route_rule_set' 'RESULT=success' 'REMOTE_FETCH=local_http_200' \
    'LIFECYCLE=create_replace_delete' 'CORE_CHECK=passed'
)

verification_case_tor_outbound() {
  local base_revision=${1:?expected component revision required} config_path
  [[ "${base_revision}" =~ ^[0-9]+$ ]] || return 2
  # Tor outbound must exercise the external executable and a real Tor circuit,
  # not only pass the target-core schema check.  The verification image ships
  # Debian's tor executable; check.torproject.org provides a stable response
  # marker confirming that the request exited through Tor.  This intentionally
  # remains an external-network proof and does not claim production ownership.
  local tor_outbound_record="${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-record.json"
  local tor_outbound_create_status=0
  local tor_outbound_delete_status=0
  local tor_outbound_curl_status=1
  local tor_outbound_target_url='https://check.torproject.org/'
  (umask 077; jq -n '
    {id:"tor-outbound-verification",role:"outbound",type:"tor",
     tag:"tor-outbound-verification",enabled:true,
     route_rules:[{inbound:["socks-in"],domain:["check.torproject.org"],
       action:"route",outbound:"tor-outbound-verification"}],
     config:{executable_path:"/usr/bin/tor",torrc:{ClientOnly:"1"}}}
  ' > "${tor_outbound_record}")
  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component create --json --yes \
    --expected-revision "${base_revision}" --file "${tor_outbound_record}" \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-create.json"
  tor_outbound_create_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-create.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-create.json"
  [[ "${tor_outbound_create_status}" == 0 ]]
  jq -e --argjson revision "$((base_revision + 1))" '.ok==true and .operation=="create" and .revision==$revision and
    .type=="tor" and .id=="tor-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-create.json" >/dev/null
  verification_mark_step tor-outbound-component-created
  verification_wait_for_service_active sing-box
  verification_capture_command \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  config_path=$(verification_artifact_path \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-config.json")
  cp /root/.sing-box-vps/runtime/config.json "${config_path}"
  jq -e '
    ([.outbounds[] | select(.type == "tor" and
      .tag == "tor-outbound-verification" and
      .executable_path == "/usr/bin/tor" and
      .torrc.ClientOnly == "1")] | length == 1) and
    ([.route.rules[] | select(.inbound == ["socks-in"] and
      .domain == ["check.torproject.org"] and .action == "route" and
      .outbound == "tor-outbound-verification")] | length == 1)
  ' "${config_path}" >/dev/null
  verification_mark_step tor-outbound-config-asserted
  local tor_outbound_response="${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-response.html"
  local tor_outbound_curl_stderr="${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-curl.stderr.txt"
  local tor_outbound_journal="${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-journal.txt"
  local tor_socks_listener_ready=0
  for _ in {1..120}; do
    if verification_port_is_listening 1081; then
      tor_socks_listener_ready=1
      break
    fi
    sleep 1
  done
  verification_capture_listener_snapshot \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tor-socks-listener.ss-lntp.txt"
  [[ "${tor_socks_listener_ready}" == 1 ]]
  verification_mark_step tor-socks-listener-ready
  for _ in {1..24}; do
    set +e
    curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
      --noproxy '' --proxy 'socks5h://socks-user:socks-pass@127.0.0.1:1081' \
      "${tor_outbound_target_url}" \
      > "$(verification_artifact_path "${tor_outbound_response}")" \
      2> "$(verification_artifact_path "${tor_outbound_curl_stderr}")"
    tor_outbound_curl_status=$?
    set -e
    if [[ "${tor_outbound_curl_status}" == 0 ]] && \
      grep -Fq 'This browser is configured to use Tor' \
      "$(verification_artifact_path "${tor_outbound_response}")"; then
      break
    fi
    sleep 1
  done
  [[ "${tor_outbound_curl_status}" == 0 ]]
  grep -Fq 'This browser is configured to use Tor' \
    "$(verification_artifact_path "${tor_outbound_response}")"
  verification_capture_command "${tor_outbound_journal}" \
    journalctl -u sing-box --no-pager -n 300
  verification_mark_step tor-outbound-curl-complete

  set +e
  bash "${VERIFY_REMOTE_INSTALL_SCRIPT}" agent component delete --json --yes \
    --expected-revision "$((base_revision + 1))" --id tor-outbound-verification \
    > "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-delete.json"
  tor_outbound_delete_status=$?
  set -e
  verification_capture_file_if_present \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-delete.json" \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound-delete.json"
  [[ "${tor_outbound_delete_status}" == 0 ]]
  jq -e --argjson revision "$((base_revision + 2))" '.ok==true and .operation=="delete" and .revision==$revision and
    .id=="tor-outbound-verification"' \
    "${VERIFY_REMOTE_LOCAL_TREE_DIR}/tor-outbound-delete.json" >/dev/null
  verification_mark_step tor-outbound-component-deleted
  jq -e '
    ([.outbounds[] | select(.tag == "tor-outbound-verification")] | length) == 0 and
    ([.route.rules[] | select(.outbound == "tor-outbound-verification")] | length) == 0
  ' /root/.sing-box-vps/runtime/config.json >/dev/null
  verification_wait_for_service_active sing-box
  verification_capture_command "${VERIFY_CURRENT_SCENARIO_DIR}/tor-deleted-check.txt" \
    sing-box check -c /root/.sing-box-vps/runtime/config.json
  verification_write_artifact \
    "${VERIFY_CURRENT_SCENARIO_DIR}/tor-outbound.result.env" \
    'COMPONENT=tor-outbound' 'RESULT=success' \
    'DATA_PLANE=tor_external_tcp' 'TARGET=check.torproject.org'

}

verification_assert_atomic_socks_baseline() {
  jq -e '(.inbounds|length)==1 and .inbounds[0].type=="socks" and
    .inbounds[0].tag=="socks-in" and .inbounds[0].listen_port==1081 and
    .inbounds[0].users==[{username:"socks-user",password:"socks-pass"}]' \
    /root/.sing-box-vps/runtime/config.json >/dev/null
  if [[ -f /root/.sing-box-vps/runtime/components.json ]]; then
    jq -e '.revision==0 and (.components|length)==0' \
      /root/.sing-box-vps/runtime/components.json >/dev/null
  fi
}
