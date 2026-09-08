#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 122
# Keep this source at top level for Bash 4.2 registry-array compatibility.
source "${TESTABLE_INSTALL}"
trap 'printf "Trojan Agent/share failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/trojan.json"
state_file="${SB_PROTOCOL_STATE_DIR}/trojan.env"
cert_file="${TMP_DIR}/trojan-public.crt"
key_file="${TMP_DIR}/trojan-private.key"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=trojan.example' -keyout "${key_file}" -out "${cert_file}" \
  >/dev/null 2>&1
chmod 600 "${cert_file}" "${key_file}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"

jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {schema_version:1,protocol:"trojan",revision:12,default_instance_id:"trojan-ws",instances:[
    {id:"trojan-plain",name:"Trojan plain",tag:"trojan-plain",listen:{address:"127.0.0.1",port:33401},
      authentication:{users:[{name:"plain-user",password:"plain-secret"}]},tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"trojan-ws",name:"Trojan WebSocket",tag:"trojan-ws",listen:{address:"0.0.0.0",port:33402},
      authentication:{users:[{name:"ws-user",password:"ws-secret"},{name:"二号",password:"unicode-secret"}]},
      tls:{enabled:true,server_name:"trojan.example",certificate_path:$cert,key_path:$key},client_trust:"system",
      transport:{type:"ws",path:"/trojan",headers:{Host:"trojan.example"}},outbound_policy:"direct",dependencies:[]},
    {id:"trojan-grpc",name:"Trojan gRPC",tag:"trojan-grpc",listen:{address:"127.0.0.1",port:33403},
      authentication:{users:[{name:"grpc-user",password:"grpc-secret"}]},
      tls:{enabled:true,server_name:"grpc.example",certificate_path:$cert,key_path:$key},client_trust:"system",
      transport:{type:"grpc",service_name:"trojan-service"},outbound_policy:"warp",dependencies:[]},
    {id:"trojan-pinned",name:"Trojan pinned",tag:"trojan-pinned",listen:{address:"127.0.0.1",port:33404},
      authentication:{users:[{name:"pinned-user",password:"pinned-secret"}]},
      tls:{enabled:true,server_name:"pinned.example",certificate_path:$cert,key_path:$key},client_trust:"certificate",
      transport:{type:"ws",path:"/pinned",headers:{Host:"pinned.example","X-Extra":"skip-me"}},outbound_policy:"default",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${store_file}" "${state_file}"
printf '%s\n' INSTALLED_PROTOCOLS=trojan PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
chmod 600 "${SB_PROTOCOL_INDEX_FILE}"

# The fake core validates read-only checks and never prints client secrets.
cat > "${SINGBOX_BIN_PATH}" <<'EOF_CORE'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check|*) exit 0 ;;
esac
EOF_CORE
chmod 700 "${SINGBOX_BIN_PATH}"
systemctl() {
  case "${1:-}" in
    is-active) [[ "${2:-}" == --quiet ]] || printf 'active\n' ;;
    show) printf 'MainPID=1\nActiveState=active\n' ;;
    *) return 0 ;;
  esac
}
get_public_ip() { printf '203.0.113.44'; }

# Complete live inventory for status validation; private fields are included
# only in this private fixture, never in Agent node/status assertions.
jq -n --arg cert "${cert_file}" --arg key "${key_file}" '
  {inbounds:[
    {type:"trojan",tag:"trojan-plain",listen:"127.0.0.1",listen_port:33401,users:[{name:"plain-user",password:"plain-secret"}]},
    {type:"trojan",tag:"trojan-ws",listen:"0.0.0.0",listen_port:33402,users:[{name:"ws-user",password:"ws-secret"},{name:"二号",password:"unicode-secret"}],tls:{enabled:true,server_name:"trojan.example",certificate_path:$cert,key_path:$key},transport:{type:"ws",path:"/trojan",headers:{Host:"trojan.example"}}},
    {type:"trojan",tag:"trojan-grpc",listen:"127.0.0.1",listen_port:33403,users:[{name:"grpc-user",password:"grpc-secret"}],tls:{enabled:true,server_name:"grpc.example",certificate_path:$cert,key_path:$key},transport:{type:"grpc",service_name:"trojan-service"}},
    {type:"trojan",tag:"trojan-pinned",listen:"127.0.0.1",listen_port:33404,users:[{name:"pinned-user",password:"pinned-secret"}],tls:{enabled:true,server_name:"pinned.example",certificate_path:$cert,key_path:$key},transport:{type:"ws",path:"/pinned",headers:{Host:"pinned.example","X-Extra":"skip-me"}}}
  ],outbounds:[{type:"direct",tag:"direct"},{type:"direct",tag:"warp-ep"}],route:{rules:[{inbound:"trojan-grpc",outbound:"warp-ep"}],final:"direct"}}
' > "${SINGBOX_CONFIG_FILE}"
chmod 600 "${SINGBOX_CONFIG_FILE}"

# Live routing must agree with each typed instance policy.
jq '.route.rules |= map(.action = "route") | .route.rules += [{inbound:"trojan-ws",action:"route",outbound:"direct"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/routed-config.json"
mv "${TMP_DIR}/routed-config.json" "${SINGBOX_CONFIG_FILE}"

validate_structured_instance_store trojan "${store_file}"
load_plain_proxy_structured_instance trojan trojan-ws
[[ "${SB_PROTOCOL}" == trojan && "${SB_INSTANCE_ID}" == trojan-ws ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 0.0.0.0 && "${SB_PORT}" == 33402 ]]
jq -e 'length == 2 and .[1].name == "二号"' <<< "${SB_TROJAN_AUTH_JSON}" >/dev/null

plain_proxy_structured_state_matches_config trojan
if ! nodes_output=$(agent_cli nodes --json 2>"${TMP_DIR}/nodes.stderr"); then
  cat "${TMP_DIR}/nodes.stderr" >&2
  printf '%s\n' "${nodes_output}" >&2
  exit 1
fi
jq -e '
  .ok == true and .command == "nodes" and .data.action == "nodes" and (.data.nodes|length)==4 and
  all(.data.nodes[]; .protocol == "trojan" and (.instance_id|type)=="string") and
  any(.data.nodes[]; .instance_id == "trojan-ws" and .user_count == 2) and
  (tostring|contains("ws-secret")|not) and (tostring|contains("certificate_path")|not) and
  (tostring|contains("key_path")|not) and (tostring|contains("X-Extra")|not)
' <<< "${nodes_output}" >/dev/null
if [[ -s "${TMP_DIR}/nodes.stderr" ]]; then ! grep -Fq 'ws-secret' "${TMP_DIR}/nodes.stderr"; fi

status_output=$(agent_cli status --json 2>"${TMP_DIR}/status.stderr")
jq -e '.ok == true and .command == "status" and (tostring|contains("ws-secret")|not) and (tostring|contains("key_path")|not)' \
  <<< "${status_output}" >/dev/null
if [[ -s "${TMP_DIR}/status.stderr" ]]; then ! grep -Fq 'ws-secret' "${TMP_DIR}/status.stderr"; fi

cp -p "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/trusted-live.json"
jq '.inbounds[0].tag = "untracked-trojan"' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/untrusted-live.json"
mv "${TMP_DIR}/untrusted-live.json" "${SINGBOX_CONFIG_FILE}"
untrusted_nodes=$(agent_cli nodes --json 2>"${TMP_DIR}/untrusted.stderr" || true)
jq -e '.ok == false and .error == "protocol_state_untrusted" and (tostring|contains("plain-secret")|not)' <<< "${untrusted_nodes}" >/dev/null
mv "${TMP_DIR}/trusted-live.json" "${SINGBOX_CONFIG_FILE}"

capabilities=$(agent_cli capabilities --json)
jq -e '
  (.features.plain_proxy_instances.protocols|index("trojan")) != null and
  .features.plain_proxy_instances.operations_by_protocol.trojan == ["create","replace","delete","default","recover"] and
  (.commands.instance.protocols|index("trojan")) != null and
  any(.protocol_registry[]; .agent_id == "trojan" and .client_export == true and .multi_instance == true)
' <<< "${capabilities}" >/dev/null

load_plain_proxy_structured_instance trojan trojan-ws
ws_links=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e '
  .protocol == "trojan" and (.links|length)==2 and all(.links[]; startswith("trojan://") and contains("@203.0.113.44:33402")) and
  all(.links[]; contains("type=ws") and contains("path=%2Ftrojan")) and
  (tostring|contains("ws-secret"))
' <<< "${ws_links}" >/dev/null

load_plain_proxy_structured_instance trojan trojan-plain
plain_links=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e '.protocol == "trojan" and (.links|length)==0 and (.outbounds|length)==1 and any(.outbounds[]; .password == "plain-secret") and any(.warnings[]; .code == "trojan_tls_disabled_uri_unrepresentable")' \
  <<< "${plain_links}" >/dev/null
load_plain_proxy_structured_instance trojan trojan-pinned
pinned_links=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e '.protocol == "trojan" and (.links|length)==0 and (.outbounds|length)==1 and any(.outbounds[]; .password == "pinned-secret" and .transport.headers["X-Extra"] == "skip-me") and any(.warnings[]; .code == "trojan_tls_certificate_uri_unrepresentable")' \
  <<< "${pinned_links}" >/dev/null

load_plain_proxy_structured_instance trojan trojan-plain
plain_summary=$(agent_node_summary_json_for_current_protocol '203.0.113.44')
jq -e '.shareable == false and .client_exportable == true' <<< "${plain_summary}" >/dev/null
load_plain_proxy_structured_instance trojan trojan-pinned
pinned_summary=$(agent_node_summary_json_for_current_protocol '203.0.113.44')
jq -e '.shareable == false and .client_exportable == true' <<< "${pinned_summary}" >/dev/null
# Reordering users does not change stable link identities.
load_plain_proxy_structured_instance trojan trojan-ws
# Bash 4.2 can corrupt nested here-string input when command substitution
# itself calls read <<<. Keep API execution outside the assertion redirection.
before_links=$(agent_link_json_for_current_protocol '203.0.113.44')
before_tags=$(jq -c '[.outbounds[].tag] | sort' <<< "${before_links}")
jq -e 'all(.outbounds[]; (.tag|startswith("trojan-trojan-ws-user-")))' \
  <<< "${before_links}" >/dev/null
jq '.instances |= map(if .id == "trojan-ws" then .authentication.users |= reverse else . end)' "${store_file}" > "${TMP_DIR}/reordered.json"
mv "${TMP_DIR}/reordered.json" "${store_file}"
jq '.inbounds |= map(if .tag == "trojan-ws" then .users |= reverse else . end)' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/reordered-live.json"
mv "${TMP_DIR}/reordered-live.json" "${SINGBOX_CONFIG_FILE}"
after_links=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e --argjson before "${before_tags}" '([.outbounds[].tag] | sort) == $before and (.links|length)==2 and all(.outbounds[]; (.tag|startswith("trojan-trojan-ws-user-")))' <<< "${after_links}" >/dev/null

export_output=$(agent_cli export-client --json 2>"${TMP_DIR}/export.stderr")
jq -e --arg key "${key_file}" '
  .ok == true and .command == "export-client" and ([.data.config.outbounds[]|select(.type=="trojan")]|length)==5 and
  ([.data.config.outbounds[]|select(.type=="trojan")|.password]|length)==5 and
  ([.data.config.outbounds[]|select(.type=="trojan")|select(.tls.certificate? != null)]|length)==1 and
  (any(.data.config.outbounds[]; .type == "trojan" and .server_port == 33401 and (has("tls")|not))) and
  (tostring|contains($key)|not) and (tostring|contains("trojan-private")|not)
' <<< "${export_output}" >/dev/null
if [[ -s "${TMP_DIR}/export.stderr" ]]; then ! grep -Fq 'ws-secret' "${TMP_DIR}/export.stderr"; fi

# Export-client is transactional: a builder failure returns the stable
# generation error and preserves the previously published file byte-for-byte.
export_file=$(jq -r '.data.path' <<< "${export_output}")
export_hash=$(sha256sum "${export_file}" | awk '{print $1}')
original_client_builder=$(declare -f build_client_trojan_outbounds)
build_client_trojan_outbounds() { return 73; }
printf 'existing backup\n' > "${export_file}.bak"
backup_hash=$(sha256sum "${export_file}.bak" | awk '{print $1}')
failed_export=$(agent_cli export-client --json 2>"${TMP_DIR}/failed-export.stderr" || true)
jq -e '.ok == false and .error == "client_config_generation_failed" and (.message|contains("原导出文件和备份未改变"))' <<< "${failed_export}" >/dev/null
[[ "$(sha256sum "${export_file}" | awk '{print $1}')" == "${export_hash}" ]]
[[ "$(sha256sum "${export_file}.bak" | awk '{print $1}')" == "${backup_hash}" ]]
if [[ -s "${TMP_DIR}/failed-export.stderr" ]]; then ! grep -Fq 'ws-secret' "${TMP_DIR}/failed-export.stderr"; fi
eval "${original_client_builder}"

# A live-store replacement between the private snapshot and link rendering is
# rejected instead of publishing a mixed-revision result.
baseline_store=$(<"${store_file}")
original_snapshot=$(declare -f structured_instance_store_snapshot_json)
eval "${original_snapshot/structured_instance_store_snapshot_json/original_structured_instance_store_snapshot_json}"
structured_instance_store_snapshot_json() {
  local captured
  captured=$(original_structured_instance_store_snapshot_json "$@") || return 1
  jq '.revision += 1' "${store_file}" > "${TMP_DIR}/drifted.json"
  mv "${TMP_DIR}/drifted.json" "${store_file}"
  printf '%s\n' "${captured}"
}
load_plain_proxy_structured_instance trojan trojan-ws
drift_output=$(agent_trojan_link_json '203.0.113.44' || true)
[[ -z "${drift_output}" ]]
eval "$(declare -f original_structured_instance_store_snapshot_json | sed '1s/^original_structured_instance_store_snapshot_json /structured_instance_store_snapshot_json /')"
printf '%s' "${baseline_store}" > "${store_file}"

# A valid oversized per-user URI is skipped without invalidating the typed
# store, while the same instance's ordinary user remains shareable.
jq --arg cert "${cert_file}" --arg key "${key_file}" \
  '.instances += [{id:"trojan-oversized",name:"Oversized users",tag:"trojan-oversized",listen:{address:"127.0.0.1",port:33405},authentication:{users:[{name:"short-user",password:"short-secret"},{name:"long-user",password:("é" * 2048)}]},tls:{enabled:true,server_name:"oversized.example",certificate_path:$cert,key_path:$key},client_trust:"system",transport:{type:"ws",path:("/" + ("a" * 4095)),headers:{Host:"oversized.example"}},outbound_policy:"default",dependencies:[]}]' \
  "${store_file}" > "${TMP_DIR}/oversized-store.json"
mv "${TMP_DIR}/oversized-store.json" "${store_file}"
load_plain_proxy_structured_instance trojan trojan-plain
plain_links_after_oversize=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e '.links|length == 0' <<< "${plain_links_after_oversize}" >/dev/null
load_plain_proxy_structured_instance trojan trojan-oversized
oversized_links=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e '.protocol == "trojan" and .shareable == true and (.links|length)==1 and any(.links[]; startswith("trojan://") and contains("short-secret")) and
  any(.outbounds[]; .tag == "trojan-trojan-oversized-user-c2hvcnQtdXNlcg==" and .password == "short-secret") and
  any(.warnings[]; .code == "trojan_uri_too_large" and .instance_id == "trojan-oversized" and .outbound_tag == "trojan-trojan-oversized-user-bG9uZy11c2Vy")' <<< "${oversized_links}" >/dev/null

jq '.instances |= map(if .id == "trojan-oversized" then .authentication.users |= map(select(.name == "long-user")) else . end)' \
  "${store_file}" > "${TMP_DIR}/all-oversized.json"
mv "${TMP_DIR}/all-oversized.json" "${store_file}"
load_plain_proxy_structured_instance trojan trojan-oversized
all_oversized=$(agent_link_json_for_current_protocol '203.0.113.44')
jq -e '.shareable == false and (.links|length)==0 and (.outbounds|length)==1 and .warnings[0].code == "trojan_uri_too_large"' <<< "${all_oversized}" >/dev/null

printf 'Trojan Agent/share checks passed: nodes=4 links=2 export-outbounds=5 uri-too-large=1\n'
