#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

export SERVICE_TEST_STATE="${TMP_DIR}/service.state"
export SERVICE_TEST_CALLS="${TMP_DIR}/service.calls"
export SERVICE_TEST_CHECKS="${TMP_DIR}/checks"
export SERVICE_TEST_JOURNAL="${TMP_DIR}/journal.args"
printf 'inactive\n' > "${SERVICE_TEST_STATE}"
: > "${SERVICE_TEST_CALLS}"
: > "${SERVICE_TEST_CHECKS}"
printf '{}\n' > "${SINGBOX_CONFIG_FILE}"
cat <<'STUB' > "${TMP_DIR}/bin/sing-box"
#!/usr/bin/env bash
if [[ "${1:-}" == check ]]; then
  printf 'check\n' >> "${SERVICE_TEST_CHECKS}"
  [[ "${SERVICE_TEST_CHECK_FAIL:-n}" != y ]] || { printf 'invalid dummy config\n' >&2; exit 23; }
  printf 'config ok\n'
fi
STUB
cat <<'STUB' > "${TMP_DIR}/bin/systemctl"
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  'is-active sing-box')
    state=$(cat "${SERVICE_TEST_STATE}")
    printf '%s\n' "${state}"
    [[ "${state}" == active ]] || exit 3
    ;;
  'start sing-box'|'stop sing-box'|'restart sing-box')
    printf '%s\n' "$1" >> "${SERVICE_TEST_CALLS}"
    printf 'systemctl stdout must stay outside JSON\n'
    [[ "${SERVICE_TEST_FAIL:-n}" != y ]] || exit 9
    [[ "${SERVICE_TEST_NOOP:-n}" != y ]] || exit 0
    if [[ "$1" == stop ]]; then printf 'inactive\n'; else printf 'active\n'; fi > "${SERVICE_TEST_STATE}"
    ;;
  *) printf 'unexpected systemctl command\n' >&2; exit 99 ;;
esac
STUB
cat <<'STUB' > "${TMP_DIR}/bin/journalctl"
#!/usr/bin/env bash
printf '%s\n' "$@" > "${SERVICE_TEST_JOURNAL}"
if [[ "${SERVICE_TEST_LOG_FAIL:-n}" == y ]]; then
  printf 'partial dummy-secret\n'
  printf 'journal error dummy-secret\n' >&2
  exit 2
fi
if [[ "${SERVICE_TEST_LOG_LARGE:-n}" == y ]]; then
  awk 'BEGIN {for (i=0;i<140000;i++) printf "x"; printf "\n"}'
else
  printf 'dummy credential-bearing journal entry\n'
fi
STUB
chmod +x "${TMP_DIR}/bin/sing-box" "${TMP_DIR}/bin/systemctl" "${TMP_DIR}/bin/journalctl"

service_json() {
  agent_cli_run "service ${1:-}" agent_service_cli "$@"
}
expect_failure() {
  local expected_error=$1
  shift
  if response=$(service_json "$@" 2> "${TMP_DIR}/stderr"); then
    printf 'expected service operation to fail: %s\n' "$*" >&2
    exit 1
  fi
  jq -se --arg error "${expected_error}" 'length==1 and .[0].ok==false and .[0].error==$error' <<< "${response}" >/dev/null
}

response=$(service_json status --json)
jq -se 'length==1 and .[0].ok and .[0].service.active_state=="inactive" and (. [0].service.active|not)' <<< "${response}" >/dev/null
expect_failure confirmation_required start --json
expect_failure invalid_arguments status --json --yes
expect_failure invalid_arguments restart --json --yes extra
expect_failure invalid_arguments stop --json --yes --json
expect_failure json_required start --yes
expect_failure unknown_service_command unknown --json
[[ ! -s "${SERVICE_TEST_CALLS}" ]]

export SERVICE_TEST_CHECK_FAIL=y
expect_failure config_check_failed start --json --yes
jq -e '.skipped and .check.exit_code==23 and .service.before=="inactive" and .service.after=="inactive"' <<< "${response}" >/dev/null
[[ ! -s "${SERVICE_TEST_CALLS}" ]]
unset SERVICE_TEST_CHECK_FAIL
response=$(service_json start --yes --json 2> "${TMP_DIR}/stderr")
jq -se 'length==1 and .[0].ok and .[0].action=="service_start" and .[0].check.ok and .[0].service.after=="active"' <<< "${response}" >/dev/null
response=$(service_json restart --json --yes 2> "${TMP_DIR}/stderr")
jq -e '.ok and .action=="service_restart" and .check.ok and .service.before=="active" and .service.after=="active"' <<< "${response}" >/dev/null

checks_before=$(wc -l < "${SERVICE_TEST_CHECKS}")
export SERVICE_TEST_CHECK_FAIL=y
response=$(service_json stop --json --yes 2> "${TMP_DIR}/stderr")
jq -e '.ok and .action=="service_stop" and .service.after=="inactive" and .check==null' <<< "${response}" >/dev/null
[[ "$(wc -l < "${SERVICE_TEST_CHECKS}")" == "${checks_before}" ]]
unset SERVICE_TEST_CHECK_FAIL

printf 'active\n' > "${SERVICE_TEST_STATE}"
export SERVICE_TEST_NOOP=y
expect_failure service_stop_failed stop --json --yes
jq -e '.service.stop_exit_code==0 and .service.after=="active"' <<< "${response}" >/dev/null
unset SERVICE_TEST_NOOP
export SERVICE_TEST_FAIL=y
expect_failure service_restart_failed restart --json --yes
jq -e '.service.restart_exit_code==9 and (.skipped|not) and .check.ok' <<< "${response}" >/dev/null
unset SERVICE_TEST_FAIL

calls_before=$(wc -l < "${SERVICE_TEST_CALLS}")
printf 'unknown\n' > "${SERVICE_TEST_STATE}"
expect_failure service_state_unavailable status --json
expect_failure service_state_unavailable start --json --yes
[[ "$(wc -l < "${SERVICE_TEST_CALLS}")" == "${calls_before}" ]]

response=$(service_json logs --json)
jq -se 'length==1 and .[0].ok and .[0].sensitive and .[0].lines==100 and (.[0].logs|contains("dummy credential"))' <<< "${response}" >/dev/null
[[ "$(sed -n '6p' "${SERVICE_TEST_JOURNAL}")" == 100 ]]
! rg -q -- '--follow|^-f$' "${SERVICE_TEST_JOURNAL}"
response=$(service_json logs --lines 1000 --json)
jq -e '.ok and .lines==1000' <<< "${response}" >/dev/null
for value in 0 1001 -1 01 invalid '1;touch /tmp/never-service-test'; do
  expect_failure invalid_arguments logs --json --lines "${value}"
done
expect_failure invalid_arguments logs --json --lines 5 --lines 10
expect_failure invalid_arguments logs --json --yes
export SERVICE_TEST_LOG_FAIL=y
expect_failure service_logs_unavailable logs --json
jq -e '.sensitive and .logs=="" and .journal_exit_code==2' <<< "${response}" >/dev/null
! rg -q 'dummy-secret' "${TMP_DIR}/stderr"
unset SERVICE_TEST_LOG_FAIL
export SERVICE_TEST_LOG_LARGE=y
response=$(service_json logs --json)
jq -e '.ok and (.logs|length)==140000' <<< "${response}" >/dev/null
# Canonical service calls retain shared/read and exclusive/write guards, and
# dangling pending journals cannot bypass recovery requirements.
agent_current_user_is_root() { return 0; }
acquire_managed_write_lock() { printf '%s' "${1:-exclusive}" > "${TMP_DIR}/lock-mode"; }
printf 'inactive\n' > "${SERVICE_TEST_STATE}"
response=$(main service status --json)
[[ "$(cat "${TMP_DIR}/lock-mode")" == shared ]]
response=$(main service start --json --yes)
[[ "$(cat "${TMP_DIR}/lock-mode")" == exclusive ]]
for pending in "${SB_PROJECT_DIR}.instance-write.lock" "${SB_COMPONENT_TRANSACTION_DIR}"; do
  ln -s "${TMP_DIR}/missing-journal" "${pending}"
  if response=$(main service start --json --yes); then exit 1; fi
  jq -e '.error=="transaction_pending"' <<< "${response}" >/dev/null
  rm -- "${pending}"
done
printf '%s\n' 'agent service operations passed'

