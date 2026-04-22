#!/usr/bin/env bash

set -euo pipefail

LOCK_DIR=/tmp/sing-box-vps-verification.lock
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  printf 'verification host is busy\n' >&2
  exit 32
fi

cleanup() {
  rmdir "${LOCK_DIR}"
}
trap cleanup EXIT

for scenario in "$@"; do
  case "${scenario}" in
    runtime_smoke)
      bash "${SCRIPT_DIR}/scenarios/runtime_smoke.sh"
      ;;
    *)
      printf 'unknown scenario: %s\n' "${scenario}" >&2
      exit 2
      ;;
  esac
done
