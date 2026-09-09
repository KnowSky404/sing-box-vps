#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 128

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_CORE'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check) exit 0 ;;
  *) exit 64 ;;
esac
EOF_CORE
chmod +x "${TMP_DIR}/bin/sing-box"
cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
state_file=${SBV_HYSTERIA_SYSTEMCTL_STATE_FILE:?missing state file}
case "${1:-}:${2:-}:${3:-}" in
  show:-p:ActiveState) cat "${state_file}" ;;
  show:sing-box:) cat "${state_file}" ;;
  is-active:--quiet:sing-box) [[ "$(<"${state_file}")" == active ]] ;;
  restart:sing-box:) printf 'active\n' > "${state_file}" ;;
  stop:sing-box:) printf 'inactive\n' > "${state_file}" ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "Hysteria lifecycle failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
export SBV_HYSTERIA_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
printf 'INSTALLED_PROTOCOLS=\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
jq -n '{log:{disabled:true},inbounds:[],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"
printf '[Unit]\nDescription=fixture sing-box\n' > "${SINGBOX_SERVICE_FILE}"

instance_firewall_prepare() {
  local old_config=$1 new_config=$2 journal=$3
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "${journal}"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${TMP_DIR}/hysteria.key" -out "${TMP_DIR}/hysteria.crt" \
  -subj '/CN=hysteria.lifecycle.invalid' -days 1 >/dev/null 2>&1

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 auth_str=$5 obfs_enabled=$6 obfs_password=$7 file=$8
  jq -n \
    --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --arg auth_str "${auth_str}" --arg obfs_password "${obfs_password}" \
    --argjson port "${port}" --argjson obfs_enabled "${obfs_enabled}" \
    --arg cert "${TMP_DIR}/hysteria.crt" --arg key "${TMP_DIR}/hysteria.key" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
      authentication:{users:[{name:"alice",auth_str:$auth_str}]},
      tls:{enabled:true,server_name:"hysteria.lifecycle.invalid",certificate_path:$cert,key_path:$key},
      client_trust:"certificate",bandwidth:{up_mbps:100,down_mbps:200},
      obfs:{enabled:$obfs_enabled,password:$obfs_password},
      hysteria:{connection_receive_window:"",disable_path_mtu_discovery:false,
        initial_packet_size:0,max_concurrent_streams:0,stream_receive_window:""},
      outbound_policy:"default",dependencies:[]}' > "${file}"
}

expect_success() {
  local label=$1 revision=$2
  shift 2
  local output
  output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr") || {
    cat "${TMP_DIR}/${label}.stderr" >&2
    printf '%s unexpectedly failed: %s\n' "${label}" "${output}" >&2
    return 1
  }
  jq -e --argjson revision "${revision}" \
    '.ok==true and .protocol=="hysteria" and .revision==$revision and
     .data.ok==true and .data.protocol=="hysteria" and .data.revision==$revision' \
    <<< "${output}" >/dev/null
}

expect_failure() {
  local label=$1
  shift
  local output status
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded: %s\n' "${label}" "${output}" >&2
    return 1
  else
    status=$?
  fi
  (( status != 0 )) || return 1
  jq -e '.ok==false and (.error|type=="string") and .data.ok==false and (.data.error|type=="string")' \
    <<< "${output}" >/dev/null
}

make_record main 'Native Hysteria' hysteria-main 2093 first-auth false '' "${TMP_DIR}/native.json"
make_record obfs 'Obfs Hysteria' hysteria-obfs 2094 second-auth true obfs-secret "${TMP_DIR}/obfs.json"
jq '.hysteria={connection_receive_window:"1 GB",disable_path_mtu_discovery:true,initial_packet_size:1200,max_concurrent_streams:64,stream_receive_window:"16MB"}' \
  "${TMP_DIR}/obfs.json" > "${TMP_DIR}/obfs.next" && mv "${TMP_DIR}/obfs.next" "${TMP_DIR}/obfs.json"
make_record main 'Replaced Hysteria' hysteria-main 2095 replaced-auth false '' "${TMP_DIR}/replaced.json"
make_record invalid 'Invalid Hysteria' hysteria-invalid 2096 invalid-auth false '' "${TMP_DIR}/invalid.json"
jq '.bandwidth.up_mbps=0' "${TMP_DIR}/invalid.json" > "${TMP_DIR}/invalid.next" && mv "${TMP_DIR}/invalid.next" "${TMP_DIR}/invalid.json"
jq '.id="invalid-quic" | .tag="hysteria-invalid-quic" | .listen.port=2097 | .hysteria.stream_receive_window="16777216"' \
  "${TMP_DIR}/obfs.json" > "${TMP_DIR}/invalid-quic.json"

expect_failure missing_confirmation create hysteria --json --expected-revision 0 --file "${TMP_DIR}/native.json"
expect_success create_main 1 create hysteria --json --yes --expected-revision 0 --file "${TMP_DIR}/native.json"
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/hysteria.env"
jq -e '.revision==1 and .default_instance_id=="main" and
  .instances[0].authentication.users[0].auth_str=="first-auth" and
  .instances[0].bandwidth.up_mbps==100 and .instances[0].obfs.enabled==false' \
  "${SB_PROTOCOL_STATE_DIR}/instances/hysteria.json" >/dev/null
jq -e '.inbounds[0].type=="hysteria" and .inbounds[0].listen_port==2093 and
  .inbounds[0].users[0].auth_str=="first-auth" and .inbounds[0].tls.alpn==["h3"] and
  .inbounds[0].up_mbps==100 and .inbounds[0].down_mbps==200 and
  (.inbounds[0] | has("obfs") | not)' "${SINGBOX_CONFIG_FILE}" >/dev/null

candidate=$(hysteria_config_store_candidate "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_STATE_DIR}/instances/hysteria.json")
jq -e '.revision==1 and .instances[0].id=="main" and
  .instances[0].authentication.users[0].auth_str=="first-auth" and
  .instances[0].bandwidth.up_mbps==100' <<< "${candidate}" >/dev/null

server_outbound_config() {
  local outbounds=$1 file=$2
  jq -n --argjson outbounds "${outbounds}" \
    '{log:{disabled:true},outbounds:($outbounds+[{type:"direct",tag:"direct"}]),route:{final:"direct"}}' > "${file}"
}

outbounds=$(build_client_hysteria_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==1 and .[0].type=="hysteria" and .[0].server=="127.0.0.1" and
  .[0].server_port==2093 and .[0].auth_str=="first-auth" and
  .[0].tls.certificate and (.[] | has("up_mbps") and has("down_mbps"))' \
  <<< "${outbounds}" >/dev/null
server_outbound_config "${outbounds}" "${TMP_DIR}/hysteria-client-native.json"
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/hysteria-client-native.json" >/dev/null
fi

expect_success create_obfs 2 create hysteria --json --yes --expected-revision 1 --file "${TMP_DIR}/obfs.json"
jq -e '.revision==2 and any(.instances[]; .id=="obfs" and .obfs.enabled==true and .obfs.password=="obfs-secret")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/hysteria.json" >/dev/null
jq -e '([.inbounds[].type] | sort)==["hysteria","hysteria"] and
  any(.inbounds[]; .listen_port==2094 and .obfs=="obfs-secret" and
    .stream_receive_window=="16MB" and .connection_receive_window=="1 GB" and
    .disable_path_mtu_discovery==true and .initial_packet_size==1200 and
    .max_concurrent_streams==64)' "${SINGBOX_CONFIG_FILE}" >/dev/null
outbounds=$(build_client_hysteria_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==2 and any(.[]; .server_port==2094 and .obfs=="obfs-secret") and
  any(.[]; .server_port==2093 and (. | has("obfs") | not))' <<< "${outbounds}" >/dev/null
server_outbound_config "${outbounds}" "${TMP_DIR}/hysteria-client-obfs.json"
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${SINGBOX_CONFIG_FILE}" >/dev/null
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/hysteria-client-obfs.json" >/dev/null
fi

expect_failure stale_revision replace hysteria --json --yes --expected-revision 1 --file "${TMP_DIR}/replaced.json"
expect_success replace_main 3 replace hysteria --json --yes --expected-revision 2 --file "${TMP_DIR}/replaced.json"
jq -e '.revision==3 and any(.instances[]; .id=="main" and .listen.port==2095 and
  .authentication.users[0].auth_str=="replaced-auth")' "${SB_PROTOCOL_STATE_DIR}/instances/hysteria.json" >/dev/null
expect_failure invalid_bandwidth create hysteria --json --yes --expected-revision 3 --file "${TMP_DIR}/invalid.json"
expect_failure invalid_quic_window create hysteria --json --yes --expected-revision 3 --file "${TMP_DIR}/invalid-quic.json"
jq -e '.revision==3 and (.instances|length)==2' "${SB_PROTOCOL_STATE_DIR}/instances/hysteria.json" >/dev/null

expect_success delete_obfs 4 delete hysteria --json --yes --expected-revision 3 --id obfs
load_protocol_state hysteria read-only
[[ "${SB_PROTOCOL}" == hysteria && "${SB_INSTANCE_ID}" == main && "${SB_PORT}" == 2095 ]]
node_summary=$(agent_hysteria_node_json 203.0.113.10)
jq -e '.protocol=="hysteria" and .instance_id=="main" and .user_count==1 and
  .client_exportable==true and .shareable==false and .tls_mode=="manual" and
  (. | tostring | contains("replaced-auth") | not)' <<< "${node_summary}" >/dev/null
link_material=$(agent_hysteria_link_json 203.0.113.10)
jq -e '.links=={} and (.outbounds|length)==1 and .outbounds[0].type=="hysteria" and
  any(.warnings[]; .code=="hysteria_standard_uri_unavailable")' <<< "${link_material}" >/dev/null

printf 'Hysteria instance lifecycle transactions passed\n'
