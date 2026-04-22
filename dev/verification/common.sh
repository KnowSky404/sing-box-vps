#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)

determine_verification_mode() {
  local file
  for file in "$@"; do
    case "${file}" in
      install.sh | utils/*)
        printf 'remote\n'
        return 0
        ;;
    esac
  done

  printf 'local\n'
}

create_run_dir() {
  local root=${1:-"${REPO_ROOT}/dev/verification-runs"}
  local stamp
  stamp=$(date '+%Y%m%d%H%M%S')
  mkdir -p "${root}/${stamp}"
  printf '%s\n' "${root}/${stamp}"
}
