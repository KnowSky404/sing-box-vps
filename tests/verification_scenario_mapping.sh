#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"

assert_scenarios() {
  local expected=$1
  shift
  local actual
  actual=$(printf '%s\n' "$(resolve_remote_scenarios "$@")" | paste -sd, -)
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected scenarios %s, got %s\n' "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_scenarios "fresh_install_vless,reconfigure_existing_install,runtime_smoke" install.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,runtime_smoke,uninstall_and_reinstall" install.sh tests/uninstall_purge_removes_runtime_artifacts.sh

date() {
  if [[ "${1:-}" == "+%s" ]]; then
    printf '1710000000\n'
    return 0
  fi

  command date "$@"
}

RESULT_ROOT="${TMP_DIR}/verification-runs"
first_run_dir=$(create_run_dir "${RESULT_ROOT}")
second_run_dir=$(create_run_dir "${RESULT_ROOT}")

[[ "${first_run_dir}" != "${second_run_dir}" ]] || {
  printf 'expected unique run dirs, got %s twice\n' "${first_run_dir}" >&2
  exit 1
}

case "${first_run_dir}" in
  "${RESULT_ROOT}"/20????????????) ;;
  *)
    printf 'unexpected first run dir: %s\n' "${first_run_dir}" >&2
    exit 1
    ;;
esac

case "${second_run_dir}" in
  "${RESULT_ROOT}"/20????????????) ;;
  *)
    printf 'unexpected second run dir: %s\n' "${second_run_dir}" >&2
    exit 1
    ;;
esac

[[ -d "${first_run_dir}" ]] || {
  printf 'expected first run dir to exist: %s\n' "${first_run_dir}" >&2
  exit 1
}

[[ -d "${second_run_dir}" ]] || {
  printf 'expected second run dir to exist: %s\n' "${second_run_dir}" >&2
  exit 1
}
