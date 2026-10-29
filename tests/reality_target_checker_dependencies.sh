#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${REPO_ROOT}/tests/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
log_info() { :; }
log_success() { printf 'success\n' >> "${TMP_DIR}/success"; }
run_with_progress() {
  shift
  printf '%s\n' "$*" >> "${TMP_DIR}/commands"
  case "$*" in
    'apt-get update -y') return "${UPDATE_STATUS}" ;;
    'apt-get install '*|'yum install '*) return "${INSTALL_STATUS}" ;;
    *) fail 'unexpected package command' ;;
  esac
}

# Guarded callers suppress Bash errexit in nested functions; package failures
# must still propagate without a misleading success message or further actions.
OS_NAME=debian
UPDATE_STATUS=28
INSTALL_STATUS=0
status=0
install_dependencies || status=$?
[[ "${status}" == 28 ]] || fail 'apt update error was lost'
[[ ! -e "${TMP_DIR}/success" ]] || fail 'reported success after failed update'
[[ "$(wc -l < "${TMP_DIR}/commands")" == 1 ]] || fail 'continued after failed update'

: > "${TMP_DIR}/commands"
UPDATE_STATUS=0
INSTALL_STATUS=25
status=0
install_dependencies || status=$?
[[ "${status}" == 25 ]] || fail 'apt install error was lost'
[[ ! -e "${TMP_DIR}/success" ]] || fail 'reported success after failed apt install'

: > "${TMP_DIR}/commands"
OS_NAME=rocky
INSTALL_STATUS=29
status=0
install_dependencies || status=$?
[[ "${status}" == 29 ]] || fail 'yum install error was lost'
[[ ! -e "${TMP_DIR}/success" ]] || fail 'reported success after failed yum install'
printf 'REALITY dependency preparation failure tests passed.\n'
