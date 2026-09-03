#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)
readonly REMOTE_ARTIFACT_BUNDLE_BEGIN='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__'
readonly REMOTE_ARTIFACT_BUNDLE_END='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__'
readonly DEFAULT_DOCKER_IMAGE="sing-box-vps-verify:2026090301"

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
      tests/verification_protocol_probe_hy2.sh \
      tests/verification_protocol_probe_anytls.sh \
      tests/reality_sni_validation.sh \
      tests/generate_config_cleans_temp_files_on_failure.sh \
      tests/system_safety_guards.sh \
      tests/agent_upgrade_commands.sh \
      tests/agent_cli_multi_instance_status.sh \
      tests/agent_cli_ops_commands.sh \
      tests/agent_cli_outputs_machine_readable_node_info.sh \
      tests/agent_json_regression.sh \
      tests/export_client_config_1_14_compatibility.sh \
      tests/agent_docs_cover_capabilities.sh \
      tests/version_metadata_is_consistent.sh \
      tests/vless_reality_instance_removal.sh \
      tests/install_takeover_rebuilds_protocol_state_from_config.sh \
      tests/detect_existing_instance_auto_heals_managed_config_drift.sh \
      tests/update_keeps_existing_config.sh \
      tests/update_rolls_back_binary_when_config_invalid.sh \
      tests/subman_config_helpers.sh \
      tests/subman_payload_generation.sh \
      tests/subman_api_push.sh \
      tests/subman_sync_orchestration.sh
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
    printf '%s\n' fresh_install_vless reconfigure_existing_install legacy_takeover_export fresh_install_anytls upgrade_1_13_to_1_14
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

require_docker_env() {
  local attempt
  local image=${VERIFY_DOCKER_IMAGE:-"${DEFAULT_DOCKER_IMAGE}"}
  local systemd_state=''

  if ! command -v docker &>/dev/null; then
    printf 'ERROR: docker 不可用，请先安装 Docker。\n' >&2
    return 1
  fi

  if ! docker image inspect "${image}" &>/dev/null; then
    printf 'INFO: 正在构建 Docker 验证镜像 %s...\n' "${image}"
    docker build -t "${image}" -f "${REPO_ROOT}/dev/verification/docker/Dockerfile" "${REPO_ROOT}"
  fi

  VERIFY_DOCKER_CONTAINER=$(docker run -d --privileged "${image}")
  export VERIFY_DOCKER_CONTAINER

  for ((attempt = 1; attempt <= 100; attempt++)); do
    systemd_state=$(docker exec "${VERIFY_DOCKER_CONTAINER}" systemctl is-system-running 2>/dev/null || true)
    case "${systemd_state}" in
      running|degraded)
        return 0
        ;;
    esac
    sleep 0.2
  done

  printf 'ERROR: Docker 验证容器中的 systemd 未能完成启动（state=%s）。\n' "${systemd_state:-unknown}" >&2
  require_docker_cleanup
  return 1
}

require_docker_cleanup() {
  if [[ -n "${VERIFY_DOCKER_CONTAINER:-}" ]]; then
    docker rm -f "${VERIFY_DOCKER_CONTAINER}" &>/dev/null || true
    unset VERIFY_DOCKER_CONTAINER
  fi
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
