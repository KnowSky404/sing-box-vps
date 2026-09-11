#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120

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
state_file=${SBV_VLESS_SYSTEMCTL_STATE_FILE:?missing state file}
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
trap 'printf "VLESS lifecycle failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
export SBV_VLESS_SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
printf 'INSTALLED_PROTOCOLS=\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
jq -n '{log:{disabled:true},inbounds:[],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"
printf '[Unit]\nDescription=fixture sing-box\n' > "${SINGBOX_SERVICE_FILE}"

# The lifecycle test isolates state/config transactions from host firewall
# backends; the shared transaction suite covers the real ledger separately.
instance_firewall_prepare() {
  local old_config=$1 new_config=$2 journal=$3
  jq -n '{schema_version:1,status:"prepared",before_ledger_exists:false,
    before_ledger:{schema_version:1,rules:[]},after_ledger:{schema_version:1,rules:[]},
    operations:[],backend_statuses:[],diagnostics:[]}' > "${journal}"
}
instance_firewall_apply() { :; }
instance_firewall_rollback() { :; }

make_record() {
  local id=$1 name=$2 tag=$3 port=$4 transport=$5 file=$6
  jq -n --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --argjson port "${port}" \
    --argjson transport "${transport}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:"127.0.0.1",port:$port},
      authentication:{users:[{name:"first",uuid:"11111111-1111-4111-8111-111111111111",flow:""}]},
      tls:{enabled:false},client_trust:"system",transport:$transport,
      outbound_policy:"default",dependencies:[]}' > "${file}"
}

make_record main 'Native VLESS' vless-main 2095 '{"type":"none"}' "${TMP_DIR}/native.json"
make_record main 'WebSocket VLESS' vless-main 2096 '{"type":"ws","path":"/vless"}' "${TMP_DIR}/ws.json"

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
    '.ok==true and .protocol=="vless-plain" and .revision==$revision and
     .data.ok==true and .data.protocol=="vless-plain" and .data.revision==$revision' \
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

expect_failure missing_confirmation create vless-plain --json --expected-revision 0 --file "${TMP_DIR}/native.json"
expect_success create 1 create vless-plain --json --yes --expected-revision 0 --file "${TMP_DIR}/native.json"
jq -e '.revision==1 and .instances[0].transport=={type:"none"}' \
  "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" >/dev/null
jq -e '.inbounds[0].type=="vless" and .inbounds[0].listen_port==2095 and
  .inbounds[0].users[0].flow? == null and (.inbounds[0]|has("transport")|not)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
grep -Fqx 'INSTALLED_PROTOCOLS=vless-plain' "${SB_PROTOCOL_INDEX_FILE}"

expect_failure stale_revision replace vless-plain --json --yes --expected-revision 0 --file "${TMP_DIR}/ws.json"
expect_success replace 2 replace vless-plain --json --yes --expected-revision 1 --file "${TMP_DIR}/ws.json"
jq -e '.revision==2 and .instances[0].transport=={type:"ws",path:"/vless"}' \
  "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" >/dev/null
jq -e '.inbounds|length==1 and .[0].type=="vless" and .[0].transport.type=="ws" and .[0].transport.path=="/vless"' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
grep -Fqx 'INSTALLED_PROTOCOLS=vless-plain' "${SB_PROTOCOL_INDEX_FILE}"

expect_success delete 3 delete vless-plain --json --yes --expected-revision 2 --id main
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/vless-plain.env" ]]
jq -e '.revision==3 and .instances==[] and .default_instance_id==""' \
  "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" >/dev/null

# Empty tombstones retain CAS monotonicity and a later create must not revive
# the previous revision or tag implicitly.
expect_success recreate 4 create vless-plain --json --yes --expected-revision 3 --file "${TMP_DIR}/native.json"
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/vless-plain.env"
jq -e '.revision==4 and .default_instance_id=="main" and .instances[0].tag=="vless-main"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" >/dev/null
printf 'VLESS plain instance lifecycle transactions passed\n'
