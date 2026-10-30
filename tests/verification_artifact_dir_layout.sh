#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"

RESULT_ROOT="${TMP_DIR}/verification-runs"
run_dir=$(create_run_dir "${RESULT_ROOT}")

case "${run_dir}" in
  "${RESULT_ROOT}"/20????????????) ;;
  *)
    printf 'unexpected run dir: %s\n' "${run_dir}" >&2
    exit 1
    ;;
esac

[[ -d "${run_dir}" ]] || {
  printf 'expected run dir to exist: %s\n' "${run_dir}" >&2
  exit 1
}

# Conditional callers disable Bash errexit inside the helper. Parent and leaf
# mkdir failures must still stop, preserve the status and produce no run path.
assert_creation_failure() (
  local mode=$1 expected_status=$2 output status=0
  local calls="${TMP_DIR}/${mode}.calls"
  local errors="${TMP_DIR}/${mode}.stderr"
  mkdir() {
    printf '%s\n' "$*" >> "${calls}"
    if [[ "${mode}" == parent ]]; then
      # A second call would succeed, exposing a missing guard without hanging.
      if [[ "$1" == -p ]]; then return 13; fi
      return 0
    fi
    if [[ "$1" == -p ]]; then
      command mkdir "$@"
    elif [[ $(wc -l < "${calls}") -eq 2 ]]; then
      return 17
    else
      command mkdir "$@"
    fi
  }
  if output=$(create_run_dir "${TMP_DIR}/${mode}-runs" 2> "${errors}"); then
    printf 'expected %s mkdir failure to stop artifact creation\n' "${mode}" >&2
    return 1
  else
    status=$?
  fi
  [[ "${status}" -eq "${expected_status}" ]]
  [[ -z "${output}" ]]
  case "${mode}" in
    parent) [[ $(wc -l < "${calls}") -eq 1 ]] ;;
    leaf)
      [[ $(wc -l < "${calls}") -eq 2 ]]
      grep -Fq '无法创建验证产物目录' "${errors}"
      ;;
  esac
)

assert_creation_failure parent 13
assert_creation_failure leaf 17
printf 'Artifact directory layout and failure checks PASSED\n'
