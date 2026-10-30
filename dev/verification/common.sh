#!/usr/bin/env bash

set -euo pipefail

readonly VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly REPO_ROOT=$(cd "${VERIFICATION_ROOT}/../.." && pwd)
readonly REMOTE_ARTIFACT_BUNDLE_BEGIN='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_BEGIN__'
readonly REMOTE_ARTIFACT_BUNDLE_END='__SING_BOX_VPS_REMOTE_ARTIFACT_BUNDLE_END__'
readonly DEFAULT_DOCKER_IMAGE="sing-box-vps-verify:2026091501-ssh"

create_run_dir() {
  local root=${1:-"${REPO_ROOT}/dev/verification-runs"}
  local base_epoch
  local offset=0
  local stamp status

  mkdir -p -- "${root}" || return $?
  base_epoch=$(date '+%s') || return $?

  while true; do
    stamp=$(date -d "@$((base_epoch + offset))" '+%Y%m%d%H%M%S') || return $?
    if mkdir -- "${root}/${stamp}" 2>/dev/null; then
      printf '%s\n' "${root}/${stamp}"
      return 0
    else
      status=$?
    fi
    if [[ ! -d "${root}/${stamp}" ]]; then
      printf 'ERROR: 无法创建验证产物目录 %s。\n' "${root}/${stamp}" >&2
      return "${status}"
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
    docker build -t "${image}" -f "${REPO_ROOT}/dev/verification/docker/Dockerfile" "${REPO_ROOT}" || return $?
  fi

  VERIFY_DOCKER_CONTAINER=$(docker run -d --privileged "${image}") || return $?
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
