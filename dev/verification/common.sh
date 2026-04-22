#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)

determine_verification_mode() {
  local file
  for file in "$@"; do
    case "${file}" in
      install.sh | uninstall.sh | utils/* | configs/*)
        printf 'remote\n'
        return 0
        ;;
    esac
  done

  printf 'local\n'
}

resolve_remote_scenarios() {
  local needs_reinstall=0
  local file

  printf '%s\n' fresh_install_vless reconfigure_existing_install runtime_smoke

  for file in "$@"; do
    case "${file}" in
      *uninstall* | *takeover* | *reinstall* | *incomplete* | *residual* | *legacy*)
        needs_reinstall=1
        ;;
    esac
  done

  if [[ "${needs_reinstall}" == "1" ]]; then
    printf '%s\n' uninstall_and_reinstall
  fi
}

create_run_dir() {
  local root=${1:-"${REPO_ROOT}/dev/verification-runs"}
  local base_epoch
  local offset=0
  local stamp

  mkdir -p "${root}"
  base_epoch=$(date '+%s')

  while true; do
    stamp=$(date -d "@$((base_epoch + offset))" '+%Y%m%d%H%M%S')
    if mkdir "${root}/${stamp}" 2>/dev/null; then
      printf '%s\n' "${root}/${stamp}"
      return 0
    fi
    offset=$((offset + 1))
  done
}

require_remote_env() {
  : "${VERIFY_REMOTE_HOST:?VERIFY_REMOTE_HOST is required}"
  : "${VERIFY_REMOTE_USER:?VERIFY_REMOTE_USER is required}"
}

run_remote_entrypoint() {
  local run_dir=$1
  local status=0

  if ssh "${VERIFY_REMOTE_USER}@${VERIFY_REMOTE_HOST}" 'bash -s' < "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" \
    > "${run_dir}/remote.stdout.log" \
    2> "${run_dir}/remote.stderr.log"; then
    return 0
  else
    status=$?
  fi

  cat "${run_dir}/remote.stderr.log" >&2
  return "${status}"
}
