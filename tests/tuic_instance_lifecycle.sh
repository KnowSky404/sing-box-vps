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
state_file=${SBV_TUIC_SYSTEMCTL_STATE_FILE:?missing state file}
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
trap 'printf "TUIC lifecycle failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
export SBV_TUIC_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
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
  -keyout "${TMP_DIR}/tuic.key" -out "${TMP_DIR}/tuic.crt" \
  -subj '/CN=tuic.lifecycle.invalid' -days 1 >/dev/null 2>&1

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 uuid=$5 password=$6 relay=$7 udp_over_stream=$8 file=$9
  jq -n \
    --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
    --arg uuid "${uuid}" --arg password "${password}" --arg relay "${relay}" \
    --argjson port "${port}" --argjson udp_over_stream "${udp_over_stream}" \
    --arg cert "${TMP_DIR}/tuic.crt" --arg key "${TMP_DIR}/tuic.key" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
      authentication:{users:[{name:"alice",uuid:$uuid,password:$password}]},
      tls:{enabled:true,server_name:"tuic.lifecycle.invalid",certificate_path:$cert,key_path:$key},
      client_trust:"certificate",
      tuic:{auth_timeout_seconds:3,congestion_control:"bbr",heartbeat_seconds:10,
        udp_over_stream:$udp_over_stream,udp_relay_mode:$relay,zero_rtt_handshake:false},
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
    '.ok==true and .protocol=="tuic" and .revision==$revision and
     .data.ok==true and .data.protocol=="tuic" and .data.revision==$revision' \
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

make_record main 'Native TUIC' tuic-main 2089 \
  11111111-1111-4111-8111-111111111111 first-password native false "${TMP_DIR}/native.json"
make_record stream 'TUIC UDP over stream' tuic-stream 2090 \
  22222222-2222-4222-8222-222222222222 stream-password "" true "${TMP_DIR}/stream.json"
make_record main 'Replaced TUIC' tuic-main 2091 \
  33333333-3333-4333-8333-333333333333 replaced-password quic false "${TMP_DIR}/replaced.json"
make_record invalid 'Invalid TUIC' tuic-invalid 2092 \
  44444444-4444-4444-8444-444444444444 invalid-password native true "${TMP_DIR}/invalid.json"

expect_failure missing_confirmation create tuic --json --expected-revision 0 --file "${TMP_DIR}/native.json"
expect_success create_main 1 create tuic --json --yes --expected-revision 0 --file "${TMP_DIR}/native.json"
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/tuic.env"
jq -e '.revision==1 and .default_instance_id=="main" and
  .instances[0].tuic.udp_relay_mode=="native" and
  .instances[0].tuic.udp_over_stream==false and
  .instances[0].authentication.users[0].uuid=="11111111-1111-4111-8111-111111111111"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json" >/dev/null
jq -e '.inbounds[0].type=="tuic" and .inbounds[0].listen_port==2089 and
  .inbounds[0].users[0].name=="alice" and .inbounds[0].tls.alpn==["h3"] and
  .inbounds[0].congestion_control=="bbr" and .inbounds[0].auth_timeout=="3s" and
  .inbounds[0].heartbeat=="10s" and
  (.inbounds[0] | has("udp_relay_mode") | not) and
  (.inbounds[0] | has("udp_over_stream") | not)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
candidate=$(tuic_config_store_candidate "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json")
jq -e '.revision==1 and .default_instance_id=="main" and
  .instances[0].id=="main" and .instances[0].tuic.udp_relay_mode=="native" and
  .instances[0].tuic.udp_over_stream==false and
  .instances[0].authentication.users[0].uuid=="11111111-1111-4111-8111-111111111111"' \
  <<< "${candidate}" >/dev/null

server_outbound_config() {
  local outbounds=$1 file=$2
  jq -n --argjson outbounds "${outbounds}" \
    '{log:{disabled:true},outbounds:($outbounds+[{type:"direct",tag:"direct"}]),route:{final:"direct"}}' > "${file}"
}

if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${SINGBOX_CONFIG_FILE}" >/dev/null
fi
outbounds=$(build_client_tuic_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==1 and .[0].type=="tuic" and .[0].network==["tcp","udp"] and .[0].tls.alpn==["h3"] and
  .[0].server=="127.0.0.1" and .[0].server_port==2089 and
  .[0].udp_relay_mode=="native" and .[0].tls.certificate and
  (.[] | has("password"))' <<< "${outbounds}" >/dev/null
server_outbound_config "${outbounds}" "${TMP_DIR}/tuic-client-native.json"
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/tuic-client-native.json" >/dev/null
fi

expect_success create_stream 2 create tuic --json --yes --expected-revision 1 --file "${TMP_DIR}/stream.json"
jq -e '.revision==2 and ([.instances[].id] | sort)==["main","stream"] and
  any(.instances[]; .id=="stream" and .tuic.udp_over_stream==true and .tuic.udp_relay_mode=="")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json" >/dev/null
jq -e '([.inbounds[].type] | sort)==["tuic","tuic"] and
  all(.inbounds[]; (. | has("udp_relay_mode") | not) and (. | has("udp_over_stream") | not))' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
outbounds=$(build_client_tuic_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==2 and any(.[]; .server_port==2090 and .udp_over_stream==true and .tls.alpn==["h3"] and (. | has("udp_relay_mode") | not)) and
  any(.[]; .server_port==2089 and .udp_relay_mode=="native" and .tls.alpn==["h3"])' <<< "${outbounds}" >/dev/null
server_outbound_config "${outbounds}" "${TMP_DIR}/tuic-client-stream.json"
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${SINGBOX_CONFIG_FILE}" >/dev/null
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/tuic-client-stream.json" >/dev/null
fi

expect_failure stale_revision replace tuic --json --yes --expected-revision 1 --file "${TMP_DIR}/replaced.json"
expect_success replace_main 3 replace tuic --json --yes --expected-revision 2 --file "${TMP_DIR}/replaced.json"
jq -e '.revision==3 and any(.instances[]; .id=="main" and .listen.port==2091 and
  .tuic.udp_relay_mode=="quic" and .tuic.udp_over_stream==false)' \
  "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json" >/dev/null

expect_failure invalid_relay create tuic --json --yes --expected-revision 3 --file "${TMP_DIR}/invalid.json"
jq -e '.revision==3 and (.instances|length)==2' "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json" >/dev/null

expect_success delete_stream 4 delete tuic --json --yes --expected-revision 3 --id stream
jq -e '.revision==4 and (.instances|length)==1 and .instances[0].id=="main"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/tuic.json" >/dev/null

load_protocol_state tuic read-only
[[ "${SB_PROTOCOL}" == tuic && "${SB_INSTANCE_ID}" == main && "${SB_PORT}" == 2091 ]]
node_summary=$(agent_tuic_node_json 203.0.113.10)
jq -e '.protocol=="tuic" and .instance_id=="main" and .user_count==1 and
  .client_exportable==true and .shareable==false and .tls_mode=="manual" and
  (. | tostring | contains("replaced-password") | not) and
  (. | tostring | contains("33333333-3333-4333-8333-333333333333") | not)' \
  <<< "${node_summary}" >/dev/null
link_material=$(agent_tuic_link_json 203.0.113.10)
jq -e '.links=={} and (.outbounds|length)==1 and .outbounds[0].type=="tuic" and
  any(.warnings[]; .code=="tuic_standard_uri_unavailable")' <<< "${link_material}" >/dev/null

printf 'TUIC instance lifecycle transactions passed\n'
