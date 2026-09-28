#!/usr/bin/env bash

set -euo pipefail

readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
readonly RAW_BASE_URL="https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main"

bootstrap_main() (
  local operation=${1:-install}
  local script_name temp_file curl_status script_status
  local script_started=0
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
  temp_file=$(mktemp "${TMPDIR:-/tmp}/sing-box-vps-bootstrap.XXXXXX") || {
    printf '[ERROR] 无法创建临时文件；脚本尚未执行。\n' >&2
    return 1
  }
  trap 'rm -f -- "${temp_file}"' EXIT
  trap 'handle_interrupt 130' INT
  trap 'handle_interrupt 143' TERM

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
  bash "${temp_file}" "$@" || script_status=$?
  return "${script_status}"
)

bootstrap_main "$@"
