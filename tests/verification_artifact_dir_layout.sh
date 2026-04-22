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
