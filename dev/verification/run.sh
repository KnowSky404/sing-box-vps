#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

main() {
  local mode
  local run_dir
  local changed_files=()

  mapfile -t changed_files < <(git diff --name-only HEAD)
  mode=$(determine_verification_mode "${changed_files[@]}")
  run_dir=$(create_run_dir)

  printf 'mode=%s\nrun_dir=%s\n' "${mode}" "${run_dir}"
}

main "$@"
