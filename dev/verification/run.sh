#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

list_changed_files() {
  local seen_list=''
  local file
  local files=()

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    if [[ ",${seen_list}," != *",${file},"* ]]; then
      files+=("${file}")
      seen_list="${seen_list},${file}"
    fi
  done < <(
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  )

  if [[ "${#files[@]}" -gt 0 ]]; then
    printf '%s\n' "${files[@]}"
  fi
}

run_local_tests() {
  local test_file

  if [[ "${VERIFY_SKIP_LOCAL_TESTS:-0}" == "1" ]]; then
    return 0
  fi

  for test_file in tests/verification_*.sh; do
    VERIFY_SKIP_LOCAL_TESTS=1 bash "${test_file}"
  done
}

resolve_changed_files() {
  if [[ "${1:-}" == "--changed-file" ]]; then
    shift
    if [[ "$#" -gt 0 ]]; then
      printf '%s\n' "$@"
    fi
    return 0
  fi

  list_changed_files
}

main() {
  local mode
  local run_dir
  local changed_files=()

  mapfile -t changed_files < <(resolve_changed_files "$@")
  mode=$(determine_verification_mode "${changed_files[@]}")
  run_dir=$(create_run_dir)
  if [[ "${#changed_files[@]}" -gt 0 ]]; then
    printf '%s\n' "${changed_files[@]}" > "${run_dir}/changed-files.txt"
  else
    : > "${run_dir}/changed-files.txt"
  fi

  printf 'mode=%s\nrun_dir=%s\n' "${mode}" "${run_dir}"
  run_local_tests

  if [[ "${mode}" == "remote" ]]; then
    require_remote_env
    resolve_remote_scenarios "${changed_files[@]}" > "${run_dir}/scenarios.txt"
    run_remote_entrypoint "${run_dir}"
  fi
}

main "$@"
