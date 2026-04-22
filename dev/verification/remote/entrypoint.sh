#!/usr/bin/env bash

set -euo pipefail

LOCK_DIR=/tmp/sing-box-vps-verification.lock

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  printf 'verification host is busy\n' >&2
  exit 32
fi

cleanup() {
  rmdir "${LOCK_DIR}"
}
trap cleanup EXIT

run_verification_scenario() {
  local function_name=$1

  if ! declare -F "${function_name}" >/dev/null; then
    printf 'missing scenario function: %s\n' "${function_name}" >&2
    exit 2
  fi

  "${function_name}"
}

for scenario in "$@"; do
  case "${scenario}" in
    fresh_install_vless)
      run_verification_scenario verification_scenario_fresh_install_vless
      ;;
    reconfigure_existing_install)
      run_verification_scenario verification_scenario_reconfigure_existing_install
      ;;
    uninstall_and_reinstall)
      run_verification_scenario verification_scenario_uninstall_and_reinstall
      ;;
    runtime_smoke)
      run_verification_scenario verification_scenario_runtime_smoke
      ;;
    *)
      printf 'unknown scenario: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done
