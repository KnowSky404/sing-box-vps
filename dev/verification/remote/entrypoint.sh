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

verification_scenario_fresh_install_vless() {
  :
}

verification_scenario_reconfigure_existing_install() {
  :
}

for scenario in "$@"; do
  case "${scenario}" in
    fresh_install_vless)
      verification_scenario_fresh_install_vless
      ;;
    reconfigure_existing_install)
      verification_scenario_reconfigure_existing_install
      ;;
    runtime_smoke)
      verification_scenario_runtime_smoke
      ;;
    *)
      printf 'unknown scenario: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done
