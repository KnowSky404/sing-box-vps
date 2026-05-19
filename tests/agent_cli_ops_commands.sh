#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'STUB'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.12\n'
    ;;
  check)
    if [[ -f "${SINGBOX_CHECK_FAIL_FILE:-}" ]]; then
      printf 'config invalid\n'
      printf 'bad route\n' >&2
      exit 23
    fi
    printf 'config ok\n'
    exit 0
    ;;
esac
STUB
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'STUB'
#!/usr/bin/env bash

state_file="${SYSTEMCTL_STATE_FILE:?missing state file}"
restart_count_file="${SYSTEMCTL_RESTART_COUNT_FILE:?missing restart count file}"

case "${1:-} ${2:-}" in
  "is-active sing-box")
    cat "${state_file}"
    ;;
  "restart sing-box")
    count=$(cat "${restart_count_file}")
    printf '%s\n' "$((count + 1))" > "${restart_count_file}"
    printf 'active\n' > "${state_file}"
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "${TMP_DIR}/bin/systemctl"

source_testable_install

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
touch "${SINGBOX_CONFIG_FILE}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF_INDEX

SYSTEMCTL_STATE_FILE="${TMP_DIR}/systemctl.state"
SYSTEMCTL_RESTART_COUNT_FILE="${TMP_DIR}/systemctl.restart.count"
printf 'inactive\n' > "${SYSTEMCTL_STATE_FILE}"
printf '0\n' > "${SYSTEMCTL_RESTART_COUNT_FILE}"
export SYSTEMCTL_STATE_FILE SYSTEMCTL_RESTART_COUNT_FILE SINGBOX_CONFIG_FILE

check_json=$(agent_cli check --json)
jq -e '
  .ok == true
  and .exit_code == 0
  and .config_file == env.SINGBOX_CONFIG_FILE
  and (.stdout | contains("config ok"))
' <<< "${check_json}" >/dev/null

SINGBOX_CHECK_FAIL_FILE="${TMP_DIR}/fail-check"
touch "${SINGBOX_CHECK_FAIL_FILE}"
export SINGBOX_CHECK_FAIL_FILE

if fail_json=$(agent_cli check --json); then
  printf 'expected check command to fail when sing-box check fails\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .exit_code == 23
  and (.stdout | contains("config invalid"))
  and (.stderr | contains("bad route"))
' <<< "${fail_json}" >/dev/null

doctor_json=$(agent_cli doctor --json)
jq -e '
  .status.service.active_state == "inactive"
  and .diagnostics.config_file_exists == true
  and .diagnostics.protocol_index_exists == true
  and .diagnostics.protocol_state_dir_exists == true
  and .diagnostics.check.ok == false
' <<< "${doctor_json}" >/dev/null

unset SINGBOX_CHECK_FAIL_FILE
rm -f "${TMP_DIR}/fail-check"

if restart_missing_yes_json=$(agent_cli service restart --json); then
  printf 'expected service restart without --yes to fail\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "confirmation_required"
' <<< "${restart_missing_yes_json}" >/dev/null

restart_json=$(agent_cli service restart --json --yes)
jq -e '
  .ok == true
  and .action == "service_restart"
  and .check.ok == true
  and .service.before == "inactive"
  and .service.after == "active"
' <<< "${restart_json}" >/dev/null

if [[ "$(cat "${SYSTEMCTL_RESTART_COUNT_FILE}")" != "1" ]]; then
  printf 'expected exactly one restart call, got %s\n' "$(cat "${SYSTEMCTL_RESTART_COUNT_FILE}")" >&2
  exit 1
fi

if subman_json=$(agent_cli subman-sync --json); then
  printf 'expected missing SubMan config to fail non-interactively\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "subman_config_missing"
' <<< "${subman_json}" >/dev/null
