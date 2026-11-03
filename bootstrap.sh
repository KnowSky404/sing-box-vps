#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
readonly RAW_BASE_URL="https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main"

bootstrap_prepare_storage() {
  local root_home data_root current owner mode
  [[ "${EUID}" == 0 ]] || {
    printf '[ERROR] 本脚本必须以 root 身份运行。\n' >&2
    return 1
  }
  root_home=$(getent passwd 0 | cut -d: -f6) || return 1
  [[ -n "${root_home}" && "${root_home}" == /* && "${root_home}" != / &&
     "${root_home}" != *'/../'* && "${root_home}" != *$'\n'* &&
     "${root_home}" != *$'\r'* ]] || return 1
  data_root="${root_home}/.sing-box-vps"
  for current in "${root_home}" "${data_root}" "${data_root}/tmp"; do
    if [[ -L "${current}" || ( -e "${current}" && ! -d "${current}" ) ]]; then return 1; fi
    if [[ -d "${current}" ]]; then
      owner=$(stat -c '%u' -- "${current}") || return 1
      mode=$(stat -c '%a' -- "${current}") || return 1
      [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
      (( (8#${mode} & 0022) == 0 )) || return 1
    fi
  done
  # Validate the home ancestors before mkdir can traverse them.
  current=${root_home}
  while [[ "${current}" != / ]]; do
    [[ ! -L "${current}" && -d "${current}" ]] || return 1
    owner=$(stat -c '%u' -- "${current}") || return 1
    mode=$(stat -c '%a' -- "${current}") || return 1
    [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#${mode} & 0022) == 0 || (8#${mode} & 01000) != 0 )) || return 1
    current=$(dirname -- "${current}") || return 1
  done
  (umask 077; mkdir -p -- "${data_root}/tmp") || return 1
  chmod 0700 -- "${data_root}" "${data_root}/tmp" || return 1
  printf '%s\n' "${data_root}/tmp"
}

bootstrap_main() (
  local operation=${1:-install}
  local script_name temp_dir='' temp_file='' storage_tmp='' curl_status script_status
  local script_started=0
  cleanup_bootstrap_temp() {
    if [[ -n "${temp_file}" ]]; then
      rm -f -- "${temp_file}"
    fi
    if [[ -n "${temp_dir}" ]]; then
      rmdir -- "${temp_dir}"
    fi
  }
  handle_interrupt() {
    local signal_status=$1
    if (( script_started )); then
      printf '[WARN] 安装器已启动，目标状态需要人工检查。\n' >&2
    else
      printf '[WARN] 安装器尚未启动，系统未发生变更。\n' >&2
    fi
    exit "${signal_status}"
  }
  if (( $# > 0 )); then
    shift
  fi

  case "${operation}" in
    install) script_name=install.sh ;;
    uninstall) script_name=uninstall.sh ;;
    *)
      printf '[ERROR] 用法：bash bootstrap.sh [install|uninstall] [脚本参数...]\n' >&2
      return 2
      ;;
  esac

  umask 077
  trap 'cleanup_bootstrap_temp' EXIT
  trap 'handle_interrupt 130' INT
  trap 'handle_interrupt 143' TERM
  storage_tmp=$(bootstrap_prepare_storage) || {
    printf '[ERROR] 私有存储目录不可信或无法初始化；脚本尚未执行。\n' >&2
    return 1
  }
  temp_dir=$(mktemp -d "${storage_tmp}/sing-box-vps-bootstrap.XXXXXX") || {
    printf '[ERROR] 无法创建临时目录；脚本尚未执行。\n' >&2
    return 1
  }
  temp_file="${temp_dir}/${script_name}"
  if ! : > "${temp_file}"; then
    printf '[ERROR] 无法创建临时文件；脚本尚未执行。\n' >&2
    return 1
  fi

  if curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 --retry-delay 1 \
    -o "${temp_file}" "${RAW_BASE_URL}/${script_name}"; then
    curl_status=0
  else
    curl_status=$?
  fi
  if (( curl_status != 0 )); then
    printf '[ERROR] %s 下载失败，curl 退出码: %s；脚本尚未执行，系统未发生变更。\n' \
      "${script_name}" "${curl_status}" >&2
    return "${curl_status}"
  fi

  if [[ ! -s "${temp_file}" ]] || ! bash -n "${temp_file}"; then
    printf '[ERROR] %s 校验失败：Bash 语法无效或内容为空；脚本尚未执行，系统未发生变更。\n' \
      "${script_name}" >&2
    return 2
  fi
  if ! grep -Fqx "readonly PROJECT_AUTHOR=\"${PROJECT_AUTHOR}\"" "${temp_file}" || \
    ! grep -Fqx "readonly PROJECT_URL=\"${PROJECT_URL}\"" "${temp_file}"; then
    printf '[ERROR] %s 校验失败：项目身份不匹配；脚本尚未执行，系统未发生变更。\n' \
      "${script_name}" >&2
    return 2
  fi

  script_status=0
  script_started=1
  TMPDIR="${storage_tmp}" bash "${temp_file}" "$@" || script_status=$?
  return "${script_status}"
)

bootstrap_main "$@"
