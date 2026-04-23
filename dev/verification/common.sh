#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)
readonly REMOTE_ARTIFACT_BUNDLE_BEGIN='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__'
readonly REMOTE_ARTIFACT_BUNDLE_END='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__'
readonly DEFAULT_REMOTE_TARGET_FILE="${REPO_ROOT}/dev/verification-target.env"

determine_verification_mode() {
  local file
  for file in "$@"; do
    case "${file}" in
      install.sh | uninstall.sh | utils/* | configs/* | dev/verification/*)
        printf 'remote\n'
        return 0
        ;;
    esac
  done

  printf 'local\n'
}

append_unique_lines() {
  local line
  local existing=${APPEND_UNIQUE_LINES_SEEN:-}

  for line in "$@"; do
    [[ -n "${line}" ]] || continue
    if [[ ",${existing}," == *",${line},"* ]]; then
      continue
    fi
    printf '%s\n' "${line}"
    existing="${existing},${line}"
  done

  APPEND_UNIQUE_LINES_SEEN="${existing}"
}

resolve_local_tests() {
  local changed_files=("$@")
  local file
  local needs_runner_tests=0
  local needs_remote_harness_tests=0
  local needs_protocol_probe_tests=0

  APPEND_UNIQUE_LINES_SEEN=''

  for file in "${changed_files[@]}"; do
    case "${file}" in
      install.sh | uninstall.sh | utils/* | configs/*)
        needs_protocol_probe_tests=1
        ;;
      dev/verification/run.sh | dev/verification/common.sh)
        needs_runner_tests=1
        ;;
      dev/verification/remote/*)
        needs_protocol_probe_tests=1
        needs_runner_tests=1
        needs_remote_harness_tests=1
        ;;
    esac
  done

  if [[ "${needs_protocol_probe_tests}" == "1" ]]; then
    append_unique_lines \
      tests/verification_protocol_probe_matrix.sh \
      tests/verification_protocol_probe_vless.sh \
      tests/verification_protocol_probe_hy2.sh
  fi

  if [[ "${needs_runner_tests}" == "1" ]]; then
    append_unique_lines \
      tests/verification_artifact_dir_layout.sh \
      tests/verification_trigger_rules.sh \
      tests/verification_scenario_mapping.sh \
      tests/verification_requires_remote_env.sh \
      tests/verification_remote_target_file_alias.sh \
      tests/verification_stops_on_remote_failure.sh \
      tests/verification_run_writes_changed_files.sh \
      tests/verification_tests_only_stays_local.sh
  fi

  if [[ "${needs_remote_harness_tests}" == "1" ]]; then
    append_unique_lines \
      tests/verification_runtime_smoke_artifacts.sh \
      tests/verification_remote_scenario_dispatch.sh
  fi
}

resolve_remote_scenarios() {
  local needs_reinstall=0
  local needs_install_flow=0
  local file

  for file in "$@"; do
    case "${file}" in
      install.sh | configs/*)
        needs_install_flow=1
        ;;
      *uninstall* | *takeover* | *reinstall* | *incomplete* | *residual* | *legacy*)
        needs_reinstall=1
        ;;
    esac
  done

  if [[ "${needs_install_flow}" == "1" ]]; then
    printf '%s\n' fresh_install_vless reconfigure_existing_install
  fi

  printf '%s\n' runtime_smoke

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
  local target_file=${VERIFY_REMOTE_TARGET_FILE:-"${DEFAULT_REMOTE_TARGET_FILE}"}

  if [[ -f "${target_file}" ]]; then
    # shellcheck disable=SC1090
    source "${target_file}"
    export VERIFY_REMOTE_TARGET_FILE="${target_file}"
  fi

  if [[ -n "${VERIFY_REMOTE_HOST_ALIAS:-}" ]]; then
    VERIFY_REMOTE_SSH_TARGET="${VERIFY_REMOTE_HOST_ALIAS}"
    VERIFY_REMOTE_TARGET_LABEL="${VERIFY_REMOTE_HOST_ALIAS}"
    export VERIFY_REMOTE_SSH_TARGET VERIFY_REMOTE_TARGET_LABEL
    return 0
  fi

  : "${VERIFY_REMOTE_HOST:?VERIFY_REMOTE_HOST_ALIAS or VERIFY_REMOTE_HOST is required}"
  : "${VERIFY_REMOTE_USER:?VERIFY_REMOTE_USER is required when VERIFY_REMOTE_HOST_ALIAS is not set}"
  VERIFY_REMOTE_SSH_TARGET="${VERIFY_REMOTE_USER}@${VERIFY_REMOTE_HOST}"
  VERIFY_REMOTE_TARGET_LABEL="${VERIFY_REMOTE_SSH_TARGET}"
  export VERIFY_REMOTE_SSH_TARGET VERIFY_REMOTE_TARGET_LABEL
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
