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
state_file=${SBV_SNELL_SYSTEMCTL_STATE_FILE:?missing state file}
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
trap 'printf "Snell lifecycle failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
export SBV_SNELL_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
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

snell_prompt_users '[]' <<< $'2\nalice\nalice-key\nbob\nbob-key'
jq -e '.|length==2 and .[0].name=="alice" and .[0].userkey=="alice-key" and .[1].name=="bob" and .[1].userkey=="bob-key"' <<< "${SB_SNELL_USER_JSON}" >/dev/null
snell_prompt_users '[{"name":"alice","userkey":"alice-key"}]' <<< $'1\n\n'
jq -e '.|length==1 and .[0].name=="alice" and .[0].userkey=="alice-key"' <<< "${SB_SNELL_USER_JSON}" >/dev/null

make_v6_record() {
  local id=$1 name=$2 tag=$3 port=$4 psk=$5 file=$6
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg psk "${psk}" \
    --argjson port "${port}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
      version:6,authentication:{psk:$psk,users:[{name:"alice",userkey:"alice-key"}]},
      obfs_mode:"",obfs_host:"",mode:"default",outbound_policy:"default",dependencies:[]}' > "${file}"
}

make_v5_record() {
  local id=$1 name=$2 tag=$3 port=$4 psk=$5 file=$6
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg psk "${psk}" \
    --argjson port "${port}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
      version:5,authentication:{psk:$psk,users:[]},
      obfs_mode:"http",obfs_host:"snell.example",mode:"",outbound_policy:"default",dependencies:[]}' > "${file}"
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
    '.ok==true and .protocol=="snell" and .revision==$revision and
     .data.ok==true and .data.protocol=="snell" and .data.revision==$revision' \
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

make_v6_record main 'Native Snell v6' snell-main 2089 'snell-v6-psk-123456' "${TMP_DIR}/v6.json"
make_v5_record legacy-v5 'Snell v5' snell-v5 2090 'snell-v5-psk' "${TMP_DIR}/v5.json"

expect_failure missing_confirmation create snell --json --expected-revision 0 --file "${TMP_DIR}/v6.json"
expect_success create_v6 1 create snell --json --yes --expected-revision 0 --file "${TMP_DIR}/v6.json"
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/snell.env"
jq -e '.revision==1 and .default_instance_id=="main" and
  .instances[0].version==6 and .instances[0].mode=="default" and
  .instances[0].authentication.users[0].userkey=="alice-key"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" >/dev/null
jq -e '.inbounds[0].type=="snell" and .inbounds[0].listen_port==2089 and
  .inbounds[0].version==6 and .inbounds[0].mode=="default" and
  .inbounds[0].users[0].name=="alice" and .inbounds[0].users[0].userkey=="alice-key"' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null

expect_success create_v5 2 create snell --json --yes --expected-revision 1 --file "${TMP_DIR}/v5.json"
jq -e '.revision==2 and
  ([.instances[].version] | sort)==[5,6] and
  any(.instances[]; .id=="legacy-v5" and .obfs_mode=="http" and .obfs_host=="snell.example" and .mode=="")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" >/dev/null
jq -e '([.inbounds[].type] | sort)==["snell","snell"] and
  any(.inbounds[]; .tag=="snell-v5" and .version==5 and .obfs_mode=="http" and
    (has("obfs_host") | not))' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
outbounds_with_v5=$(build_client_snell_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==2 and
  any(.[]; .version==4 and .obfs_mode=="http" and .obfs_host=="snell.example" and .userkey=="") and
  any(.[]; .version==6 and .userkey=="alice-key")' <<< "${outbounds_with_v5}" >/dev/null
if [[ -n "${SINGBOX_BINARY_114:-}" && -x "${SINGBOX_BINARY_114}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq -n --argjson snell_outbounds "${outbounds_with_v5}" \
    '{log:{disabled:true},outbounds:($snell_outbounds + [{type:"direct",tag:"direct"}]),route:{final:"direct"}}' \
    > "${TMP_DIR}/snell-client-v5-v6.json"
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/snell-client-v5-v6.json" >/dev/null
fi

expect_failure stale_revision replace snell --json --yes --expected-revision 1 --file "${TMP_DIR}/v6.json"
make_v6_record main 'Replaced Snell v6' snell-main 2091 'snell-v6-replaced-123456' "${TMP_DIR}/v6-replaced.json"
expect_success replace_v6 3 replace snell --json --yes --expected-revision 2 --file "${TMP_DIR}/v6-replaced.json"
jq -e '.revision==3 and
  any(.instances[]; .id=="main" and .listen.port==2091 and .name=="Replaced Snell v6" and
    .authentication.psk=="snell-v6-replaced-123456")' \
  "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" >/dev/null

make_v6_record bad 'Invalid Snell' snell-bad 2092 short "${TMP_DIR}/bad.json"
expect_failure invalid_psk create snell --json --yes --expected-revision 3 --file "${TMP_DIR}/bad.json"
jq -e '.revision==3 and (.instances | length)==2' "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" >/dev/null

expect_success delete_v5 4 delete snell --json --yes --expected-revision 3 --id legacy-v5
jq -e '.revision==4 and (.instances | length)==1 and .instances[0].id=="main"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" >/dev/null

rendered=$(render_structured_instance_inbounds snell "${SB_PROTOCOL_STATE_DIR}/instances/snell.json" | jq -s .)
jq -e 'length==1 and .[0].type=="snell" and .[0].version==6 and .[0].mode=="default" and
  .[0].psk=="snell-v6-replaced-123456" and .[0].users[0].userkey=="alice-key"' \
  <<< "${rendered}" >/dev/null
outbounds=$(build_client_snell_outbounds 203.0.113.10 | jq -s .)
jq -e 'length==1 and .[0].type=="snell" and .[0].version==6 and .[0].network==["tcp","udp"] and
  .[0].server=="127.0.0.1" and .[0].server_port==2091 and .[0].userkey=="alice-key"' \
  <<< "${outbounds}" >/dev/null

load_protocol_state snell read-only
node_summary=$(agent_snell_node_json 203.0.113.10)
jq -e '.protocol=="snell" and .version==6 and .user_count==1 and
  .client_exportable==true and .shareable==false and
  (tostring | contains("snell-v6-replaced-123456") | not) and
  (tostring | contains("alice-key") | not)' <<< "${node_summary}" >/dev/null
link_material=$(agent_snell_link_json 203.0.113.10)
jq -e '.links=={} and (.outbounds|length)==1 and
  .outbounds[0].type=="snell" and
  any(.warnings[]; .code=="snell_standard_uri_unavailable")' <<< "${link_material}" >/dev/null

printf 'Snell instance lifecycle transactions passed\n'
