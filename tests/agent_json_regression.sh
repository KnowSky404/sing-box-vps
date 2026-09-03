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

# A helper that exits before producing JSON must still be represented by an envelope.
rm -f "${SB_PROTOCOL_INDEX_FILE}"
if export_json=$(agent_cli export-client --json); then
  printf 'expected export-client without protocols to return non-zero\n' >&2
  exit 1
fi
assert_envelope export-client false "${export_json}"
jq -e '.error == "internal_error" and .data == {}' <<< "${export_json}" >/dev/null

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

printf '%s\n' 'agent JSON regression checks passed'
