#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf 'sing-box version 1.14.1\n' ;;
  check) exit 0 ;;
  *) exit 64 ;;
esac
EOF_SINGBOX
chmod 0755 "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
set -euo pipefail
state_file=${SBV_INSTANCE_SYSTEMCTL_STATE:?missing state file}
case "${1:-}:${2:-}:${3:-}" in
  show:-p:*) cat "${state_file}" ;;
  is-active:--quiet:sing-box) [[ "$(<"${state_file}")" == active ]] ;;
  restart:sing-box:) printf 'active\n' > "${state_file}" ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod 0755 "${TMP_DIR}/bin/systemctl"

source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'active\n' > "${TMP_DIR}/systemctl.state"
export SBV_INSTANCE_SYSTEMCTL_STATE="${TMP_DIR}/systemctl.state"
printf 'INSTALLED_PROTOCOLS=socks\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"

jq -n '{log:{level:"warn"},inbounds:[
  {type:"socks",tag:"takeover-socks",listen:"0.0.0.0",listen_port:35101,
   users:[{username:"takeover-user",password:"takeover-password"}]}
],outbounds:[{type:"direct",tag:"direct"}],route:{rules:[
  {inbound:"takeover-socks",action:"route",outbound:"direct"}
],final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"
printf '%s\n' '[Unit]' 'Description=fixture sing-box' > "${SINGBOX_SERVICE_FILE}"

firewall_log="${TMP_DIR}/firewall.log"
instance_firewall_prepare() {
  printf 'prepare\n' >> "${firewall_log}"
  printf '%s\n' '{"schema_version":1,"status":"prepared","backend_statuses":[],"diagnostics":[]}' > "${3}"
}
instance_firewall_apply() { printf 'apply\n' >> "${firewall_log}"; }
instance_firewall_rollback() { printf 'rollback\n' >> "${firewall_log}"; }

expect_success() {
  local label=$1 revision=$2
  shift 2
  local output
  output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr") || {
    cat "${TMP_DIR}/${label}.stderr" >&2
    printf '%s failed: %s\n' "${label}" "${output}" >&2
    return 1
  }
  jq -e --argjson revision "${revision}" \
    '.ok == true and .data.ok == true and .revision == $revision and .data.revision == $revision' \
    <<< "${output}" >/dev/null
}

expect_failure() {
  local label=$1
  shift
  local output
  if output=$(agent_cli instance "$@" 2>"${TMP_DIR}/${label}.stderr"); then
    printf '%s unexpectedly succeeded: %s\n' "${label}" "${output}" >&2
    return 1
  fi
  jq -e '.ok == false and .data.ok == false and (.error | type == "string")' <<< "${output}" >/dev/null
  ! grep -Eq 'takeover-password|takeover-user' <<< "${output}"
}

before_config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
expect_failure public_takeover_without_consent takeover socks --json --yes --expected-revision 0
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/socks.env" && ! -e "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" ]]

expect_success takeover 1 takeover socks --json --yes --allow-public --expected-revision 0
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/socks.env"
jq -e '.revision == 1 and .default_instance_id == "main" and
  .instances[0].authentication.password == "takeover-password" and
  .instances[0].listen.address == "0.0.0.0"' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${before_config_hash}" ]]

before_rebuild_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
jq '.inbounds[0].listen_port = 35102' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/drift.json"
mv "${TMP_DIR}/drift.json" "${SINGBOX_CONFIG_FILE}"
expect_success rebuild 2 rebuild socks --json --yes --expected-revision 1
jq -e '.inbounds[0].listen_port == 35101' "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e '.revision == 2 and .instances[0].listen.port == 35101' \
  "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" >/dev/null
[[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" != "${before_rebuild_hash}" ]]

view_output=$(agent_cli instance view socks --json --id main --expected-revision 2)
jq -e '.ok == true and .data.action == "instance-view" and
  .data.instance_id == "main" and .data.revision == 2 and
  .data.sensitive == false and
  .data.record.authentication.password == null and
  .data.record.authentication.users[0].username == null' \
  <<< "${view_output}" >/dev/null
diagnose_output=$(agent_cli instance diagnose socks --json --id main --expected-revision 2)
jq -e '.ok == true and .data.action == "instance-diagnose" and
  .data.state.matches_config == true and .data.check.ok == true and
  .data.sensitive == false' <<< "${diagnose_output}" >/dev/null
export_output=$(agent_cli instance export socks --json --id main --expected-revision 2)
jq -e '.ok == true and .data.action == "instance-export" and
  .data.sensitive == true and
  .data.record.authentication.password == "takeover-password"' \
  <<< "${export_output}" >/dev/null
if grep -Fq 'takeover-password' <<< "${view_output}${diagnose_output}"; then
  printf 'read-only instance view/diagnose leaked credentials\n' >&2
  exit 1
fi
if grep -Fq 'takeover-user' <<< "${view_output}${diagnose_output}"; then
  printf 'read-only instance view/diagnose leaked usernames\n' >&2
  exit 1
fi

before_active_store=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")
expect_failure takeover_existing_store takeover socks --json --yes --allow-public --expected-revision 2
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/socks.json")" == "${before_active_store}" ]]
expect_failure stale_rebuild rebuild socks --json --yes --expected-revision 1

printf 'instance rebuild/takeover checks passed\n'
