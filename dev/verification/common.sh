#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)
readonly REMOTE_ARTIFACT_BUNDLE_BEGIN='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__'
readonly REMOTE_ARTIFACT_BUNDLE_END='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__'

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

extract_remote_artifacts() {
  local stdout_file=$1
  local run_dir=$2
  local artifact_dir=${3:-"${run_dir}/remote-artifacts"}
  local encoded_bundle_file="${run_dir}/remote.artifacts.b64"

  awk -v begin="${REMOTE_ARTIFACT_BUNDLE_BEGIN}" -v end="${REMOTE_ARTIFACT_BUNDLE_END}" '
    $0 == begin {
      capture = 1
      next
    }
    $0 == end {
      capture = 0
      exit
    }
    capture {
      print
    }
  ' "${stdout_file}" > "${encoded_bundle_file}"

  if [[ ! -s "${encoded_bundle_file}" ]]; then
    rm -f "${encoded_bundle_file}"
    return 1
  fi

  rm -rf "${artifact_dir}"
  mkdir -p "${artifact_dir}"
  if base64 -d "${encoded_bundle_file}" | tar -xzf - -C "${artifact_dir}"; then
    rm -f "${encoded_bundle_file}"
    return 0
  fi

  rm -f "${encoded_bundle_file}"
  rm -rf "${artifact_dir}"
  return 2
}
