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
state_file=${SBV_NAIVE_SYSTEMCTL_STATE_FILE:?missing state file}
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
trap 'printf "Naive lifecycle failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
export SBV_NAIVE_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
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
  -keyout "${TMP_DIR}/naive.key" -out "${TMP_DIR}/naive.crt" \
  -subj '/CN=naive.lifecycle.invalid' -days 1 >/dev/null 2>&1

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 username=$5 password=$6 network=$7 quic=$8 file=$9
  jq -n \
    --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --arg username "${username}" --arg password "${password}" \
    --arg network "${network}" --argjson port "${port}" --argjson quic "${quic}" \
    --arg cert "${TMP_DIR}/naive.crt" --arg key "${TMP_DIR}/naive.key" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port,network:[$network]},
      authentication:{users:[{name:$username,username:$username,password:$password}]},
      tls:{enabled:true,server_name:"naive.lifecycle.invalid",certificate_path:$cert,key_path:$key},
      client_trust:"certificate",
      naive:{extra_headers:{"User-Agent":"naive-lifecycle"},insecure_concurrency:4,quic:$quic,
        quic_congestion_control:"cubic",quic_session_receive_window:"16 MB",stream_receive_window:"8MB"},
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
    '.ok==true and .protocol=="naive" and .revision==$revision and
     .data.ok==true and .data.protocol=="naive" and .data.revision==$revision' \
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

make_record main 'Native Naive' naive-main 2098 alice first-password tcp true "${TMP_DIR}/native.json"
make_record udp 'Naive UDP' naive-udp 2099 bob second-password udp true "${TMP_DIR}/udp.json"
make_record main 'Replaced Naive' naive-main 2100 carol replaced-password tcp false "${TMP_DIR}/replaced.json"

expect_failure missing_confirmation create naive --json --expected-revision 0 --file "${TMP_DIR}/native.json"
expect_success create_main 1 create naive --json --yes --expected-revision 0 --file "${TMP_DIR}/native.json"
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/naive.env"
jq -e '.revision==1 and .default_instance_id=="main" and
  .instances[0].authentication.users[0].username=="alice" and
  .instances[0].naive.quic==true and .instances[0].naive.quic_congestion_control=="cubic"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/naive.json" >/dev/null
jq -e '.inbounds[0].type=="naive" and .inbounds[0].listen_port==2098 and
  .inbounds[0].users[0].username=="alice" and .inbounds[0].users[0].password=="first-password" and
  .inbounds[0].network=="tcp" and .inbounds[0].tls.enabled==true and
  .inbounds[0].quic_congestion_control=="cubic"' "${SINGBOX_CONFIG_FILE}" >/dev/null

candidate=$(naive_config_store_candidate "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_STATE_DIR}/instances/naive.json")
jq -e '.revision==1 and .instances[0].authentication.users[0].username=="alice" and
  .instances[0].naive.quic==true and .instances[0].listen.network==["tcp"]' <<< "${candidate}" >/dev/null

server_outbound_config() {
  local outbounds=$1 file=$2
  jq -n --argjson outbounds "${outbounds}" \
    '{log:{disabled:true},outbounds:($outbounds+[{type:"direct",tag:"direct"}]),route:{final:"direct"}}' > "${file}"
}

outbounds=$(build_client_naive_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==1 and .[0].type=="naive" and .[0].server=="127.0.0.1" and
  .[0].server_port==2098 and .[0].username=="alice" and .[0].password=="first-password" and
  .[0].quic==true and .[0].quic_congestion_control=="cubic" and
  .[0].udp_over_tcp=={enabled:true,version:2} and
  .[0].tls.certificate and .[0].extra_headers["User-Agent"]=="naive-lifecycle"' \
  <<< "${outbounds}" >/dev/null
server_outbound_config "${outbounds}" "${TMP_DIR}/naive-client-native.json"
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/naive-client-native.json" >/dev/null
fi

expect_success create_udp 2 create naive --json --yes --expected-revision 1 --file "${TMP_DIR}/udp.json"
jq -e '.revision==2 and ([.instances[].id] | sort)==["main","udp"] and
  any(.instances[]; .id=="udp" and .listen.network==["udp"])' \
  "${SB_PROTOCOL_STATE_DIR}/instances/naive.json" >/dev/null
jq -e '([.inbounds[].type] | sort)==["naive","naive"] and
  any(.inbounds[]; .listen_port==2099 and .network=="udp")' "${SINGBOX_CONFIG_FILE}" >/dev/null
outbounds=$(build_client_naive_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==2 and
  any(.[]; .server_port==2098 and .udp_over_tcp=={enabled:true,version:2}) and
  any(.[]; .server_port==2099 and .quic==true and .username=="bob" and
    (has("udp_over_tcp") | not))' <<< "${outbounds}" >/dev/null

expect_failure stale_revision replace naive --json --yes --expected-revision 1 --file "${TMP_DIR}/replaced.json"
expect_success replace_main 3 replace naive --json --yes --expected-revision 2 --file "${TMP_DIR}/replaced.json"
jq -e '.revision==3 and any(.instances[]; .id=="main" and .listen.port==2100 and
  .authentication.users[0].username=="carol")' "${SB_PROTOCOL_STATE_DIR}/instances/naive.json" >/dev/null
jq '.naive.stream_receive_window="16777216"' "${TMP_DIR}/udp.json" > "${TMP_DIR}/invalid.next" && mv "${TMP_DIR}/invalid.next" "${TMP_DIR}/udp.json"
expect_failure invalid_window create naive --json --yes --expected-revision 3 --file "${TMP_DIR}/udp.json"
jq -e '.revision==3 and (.instances|length)==2' "${SB_PROTOCOL_STATE_DIR}/instances/naive.json" >/dev/null

expect_success delete_udp 4 delete naive --json --yes --expected-revision 3 --id udp
load_protocol_state naive read-only
[[ "${SB_PROTOCOL}" == naive && "${SB_INSTANCE_ID}" == main && "${SB_PORT}" == 2100 ]]
node_summary=$(agent_naive_node_json 203.0.113.10)
jq -e '.protocol=="naive" and .instance_id=="main" and .user_count==1 and
  .client_exportable==true and .shareable==false and .outbound_runtime=="with_naive_outbound+libcronet" and
  (. | tostring | contains("replaced-password") | not)' <<< "${node_summary}" >/dev/null
link_material=$(agent_naive_link_json 203.0.113.10)
jq -e '.links=={} and (.outbounds|length)==1 and .outbounds[0].type=="naive" and
  any(.warnings[]; .code=="naive_standard_uri_unavailable") and
  any(.warnings[]; .code=="naive_libcronet_required")' <<< "${link_material}" >/dev/null

printf 'NaiveProxy instance lifecycle transactions passed\n'
