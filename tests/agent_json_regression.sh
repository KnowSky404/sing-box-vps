#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.14.0\n'
    ;;
  check)
    if [[ -f "${SINGBOX_CHECK_FAIL_FILE:-}" ]]; then
      printf 'config invalid\n'
      printf 'bad route\n' >&2
      exit 23
    fi
    printf 'config ok\n'
    ;;
esac
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash

case "${1:-} ${2:-}" in
  "is-active sing-box")
    printf 'active\n'
    ;;
  "restart sing-box")
    if [[ -f "${SYSTEMCTL_RESTART_FAIL_FILE:-}" ]]; then
      exit 19
    fi
    ;;
esac
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

source_testable_install
touch "${SINGBOX_CONFIG_FILE}"

generation_settings_config="${TMP_DIR}/generation-settings.json"
jq -n '{endpoints:[{type:"wireguard",tag:"warp-ep"}],outbounds:[],route:{final:"warp-ep",rules:[{ip_is_private:true,action:"reject"}]}}' \
  > "${generation_settings_config}"
cp "${generation_settings_config}" "${SINGBOX_CONFIG_FILE}"
SB_ADVANCED_ROUTE=n
SB_ENABLE_WARP=n
SB_WARP_ROUTE_MODE=selective
load_config_generation_settings "${generation_settings_config}"
[[ "${SB_ADVANCED_ROUTE}" == y && "${SB_ENABLE_WARP}" == y &&
   "${SB_WARP_ROUTE_MODE}" == all ]]
jq -n '{endpoints:[],outbounds:[],route:{final:"direct",rules:[]}}' \
  > "${generation_settings_config}"
cp "${generation_settings_config}" "${SINGBOX_CONFIG_FILE}"
load_config_generation_settings "${generation_settings_config}"
[[ "${SB_ADVANCED_ROUTE}" == n && "${SB_ENABLE_WARP}" == n ]]

assert_envelope() {
  local command=$1
  local expected_ok=$2
  local json=$3

  jq -e \
    --arg command "${command}" \
    --argjson expected_ok "${expected_ok}" \
    '.schema == "1"
     and .schema_version == "1.0"
     and .command == $command
     and (.timestamp | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
     and .ok == $expected_ok
     and (.data | type == "object")' <<< "${json}" >/dev/null
}

capabilities_json=$(agent_cli capabilities --json)
assert_envelope capabilities true "${capabilities_json}"
jq -e '.data.action == "capabilities" and .data.schema == "1"' <<< "${capabilities_json}" >/dev/null

original_root_check=$(declare -f agent_current_user_is_root)
agent_current_user_is_root() {
  return 1
}
if root_json=$(agent_dispatch status --json); then
  printf 'expected non-root agent dispatch to return non-zero\n' >&2
  exit 1
fi
assert_envelope status false "${root_json}"
jq -e '.error == "root_required" and .data.error == "root_required"' <<< "${root_json}" >/dev/null
eval "${original_root_check}"

if command -v setpriv >/dev/null 2>&1 &&
   awk '$1 == 0 && $3 > 1 { found = 1 } END { exit(found ? 0 : 1) }' /proc/self/uid_map &&
   awk '$1 == 0 && $3 > 1 { found = 1 } END { exit(found ? 0 : 1) }' /proc/self/gid_map; then
  chmod 0755 "${TMP_DIR}" "${TMP_DIR}/bin"
  chmod 0644 "${TESTABLE_INSTALL}"
  if root_json=$(setpriv --reuid=1 --regid=1 --clear-groups \
    bash -c 'source "$1"; main agent status --json' _ "${TESTABLE_INSTALL}"); then
    printf 'expected real non-root agent process to return non-zero\n' >&2
    exit 1
  fi
  assert_envelope status false "${root_json}"
  jq -e '.error == "root_required" and .data.error == "root_required"' <<< "${root_json}" >/dev/null
fi

SINGBOX_CHECK_FAIL_FILE="${TMP_DIR}/check-fails"
touch "${SINGBOX_CHECK_FAIL_FILE}"
export SINGBOX_CHECK_FAIL_FILE
if check_json=$(agent_cli check --json); then
  printf 'expected check failure to return non-zero\n' >&2
  exit 1
fi
assert_envelope check false "${check_json}"
jq -e '.data.ok == false and .data.exit_code == 23 and (.data.stderr | contains("bad route"))' <<< "${check_json}" >/dev/null
rm -f "${SINGBOX_CHECK_FAIL_FILE}"
unset SINGBOX_CHECK_FAIL_FILE

if missing_json=$(agent_cli status); then
  printf 'expected missing --json to return non-zero\n' >&2
  exit 1
fi
assert_envelope status false "${missing_json}"
jq -e '.error == "invalid_arguments"' <<< "${missing_json}" >/dev/null

if extra_json=$(agent_cli warp --json extra); then
  printf 'expected extra argument to return non-zero\n' >&2
  exit 1
fi
assert_envelope warp false "${extra_json}"
jq -e '.error == "invalid_arguments"' <<< "${extra_json}" >/dev/null

if service_extra_json=$(agent_cli service restart --json --yes extra); then
  printf 'expected extra service argument to return non-zero\n' >&2
  exit 1
fi
assert_envelope 'service restart' false "${service_extra_json}"
jq -e '.error == "invalid_arguments"' <<< "${service_extra_json}" >/dev/null

if upgrade_extra_json=$(agent_cli upgrade --json 1.14.0 --yes extra); then
  printf 'expected extra upgrade argument to return non-zero\n' >&2
  exit 1
fi
assert_envelope upgrade false "${upgrade_extra_json}"
jq -e '.error == "invalid_arguments"' <<< "${upgrade_extra_json}" >/dev/null

if unknown_json=$(agent_cli unknown-command --json); then
  printf 'expected unknown command to return non-zero\n' >&2
  exit 1
fi
assert_envelope unknown-command false "${unknown_json}"
jq -e '.error == "unknown_command"' <<< "${unknown_json}" >/dev/null

if help_json=$(agent_cli help --json); then
  printf 'expected help with an argument to return non-zero\n' >&2
  exit 1
fi
assert_envelope help false "${help_json}"
jq -e '.error == "invalid_arguments"' <<< "${help_json}" >/dev/null

SYSTEMCTL_RESTART_FAIL_FILE="${TMP_DIR}/restart-fails"
touch "${SYSTEMCTL_RESTART_FAIL_FILE}"
export SYSTEMCTL_RESTART_FAIL_FILE
if restart_json=$(agent_cli service restart --json --yes); then
  printf 'expected service restart failure to return non-zero\n' >&2
  exit 1
fi
assert_envelope 'service restart' false "${restart_json}"
jq -e '
  .error == "service_restart_failed"
  and .data.error == "service_restart_failed"
  and .data.service.restart_exit_code == 19
  and .data.ok == false
' <<< "${restart_json}" >/dev/null

rm -f "${SYSTEMCTL_RESTART_FAIL_FILE}"
unset SYSTEMCTL_RESTART_FAIL_FILE

# An export that cannot generate a candidate returns an actionable error envelope.
rm -f "${SB_PROTOCOL_INDEX_FILE}"
if export_json=$(agent_cli export-client --json); then
  printf 'expected export-client without protocols to return non-zero\n' >&2
  exit 1
fi
assert_envelope export-client false "${export_json}"
jq -e '.error == "client_config_generation_failed" and .data.error == "client_config_generation_failed"' <<< "${export_json}" >/dev/null

# A helper that exits before producing JSON must still be represented by an envelope.
empty_payload() { return 7; }
if empty_json=$(agent_cli_run empty empty_payload); then
  printf 'expected empty helper failure to return non-zero\n' >&2
  exit 1
fi
assert_envelope empty false "${empty_json}"
jq -e '.error == "internal_error" and .data == {}' <<< "${empty_json}" >/dev/null

if inconsistent_success=$(agent_emit_json_envelope consistency 0 '{"ok":false,"schema":{}}'); then
  printf 'expected payload ok=false to force a non-zero result\n' >&2
  exit 1
fi
assert_envelope consistency false "${inconsistent_success}"
jq -e '.schema == "1" and .data.schema == {} and .data.ok == false' <<< "${inconsistent_success}" >/dev/null

if inconsistent_failure=$(agent_emit_json_envelope consistency 19 '{"ok":true}'); then
  printf 'expected a non-zero command status to force a non-zero result\n' >&2
  exit 1
fi
assert_envelope consistency false "${inconsistent_failure}"
jq -e '.schema == "1" and .data.ok == true' <<< "${inconsistent_failure}" >/dev/null

# Keep large envelopes off argv: Linux rejects a single argument above
# MAX_ARG_STRLEN even though the total ARG_MAX is much larger.
large_payload=$(printf '%s' '{"ok":true,"padding":"';
  head -c 140000 /dev/zero | tr '\0' 'x';
  printf '%s\n' '"}')
large_envelope=$(agent_emit_json_envelope large 0 "${large_payload}")
assert_envelope large true "${large_envelope}"
jq -e '.data.padding | type == "string" and length == 140000' <<< "${large_envelope}" >/dev/null

agent_json_log_probe() {
  log_info "agent JSON log probe"
  print_warn "agent JSON warning probe"
  printf '%s\n' '{"ok":true,"action":"log-probe"}'
}
agent_log_stderr="${TMP_DIR}/agent-log.stderr"
log_probe_json=$(agent_cli_run log-probe agent_json_log_probe 2>"${agent_log_stderr}")
assert_envelope log-probe true "${log_probe_json}"
jq -e '.data.action == "log-probe"' <<< "${log_probe_json}" >/dev/null
if grep -Fq 'agent JSON log probe' <<< "${log_probe_json}"; then
  printf 'agent progress log leaked to structured stdout\n' >&2
  exit 1
fi
grep -Fq 'agent JSON log probe' "${agent_log_stderr}"
grep -Fq 'agent JSON warning probe' "${agent_log_stderr}"

printf '%s\n' 'agent JSON regression checks passed'
