
check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "本脚本必须以 root 用户执行。"
  fi
}

sanitize_sbv_detail() {
  local detail=${1:-}
  local sanitized

  if ! sanitized=$(printf '%s' "${detail}" | tr '\r\n' ' ' | sed -E \
    's#(https?://)[^/@[:space:]]+@#\1[REDACTED]@#g; s#((Proxy-Authorization|Authorization):[[:space:]]*).*$#\1[REDACTED]#I; s#([?&](token|password|secret|key)=)[^&[:space:]]+#\1[REDACTED]#gI'); then
    sanitized='unavailable'
  fi

  sanitized=${sanitized:0:400}
  if [[ -z "${sanitized}" ]]; then
    sanitized='no detail available'
  fi
  printf '%s' "${sanitized}"
}

read_sbv_detail_file() {
  local detail=''

  if [[ -f "${1:-}" ]]; then
    if ! detail=$(head -c "${SBV_CURL_STDERR_MAX_BYTES}" -- "${1}" 2>/dev/null | \
      tr '\r\n' ' '); then
      detail='unable to read diagnostic output'
    fi
  else
    detail='no diagnostic output captured'
  fi

  sanitize_sbv_detail "${detail}"
}

append_sbv_update_log() {
  local level=$1
  local message=$2

  if ! storage_private_directory "$(dirname -- "${SBV_LOG_FILE}")"; then
    return 1
  fi
  [[ ! -L "${SBV_LOG_FILE}" &&
     ( ! -e "${SBV_LOG_FILE}" || -f "${SBV_LOG_FILE}" ) ]] || return 1
  (umask 077; : >> "${SBV_LOG_FILE}") || return 1
  chmod 0600 -- "${SBV_LOG_FILE}" || return 1
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "${message}" \
    >> "${SBV_LOG_FILE}"
}

reset_sbv_update_context() {
  SBV_UPDATE_OPERATION=''
  SBV_UPDATE_STAGE='precheck'
  SBV_UPDATE_ERROR_CODE=''
  SBV_UPDATE_ERROR_MESSAGE=''
  SBV_UPDATE_ERROR_DETAIL=''
  SBV_UPDATE_COMMAND_EXIT_CODE='0'
  SBV_UPDATE_HINT=''
  SBV_UPDATE_CHANGED='false'
  SBV_UPDATE_ROLLBACK_ATTEMPTED='false'
  SBV_UPDATE_ROLLED_BACK='false'
  SBV_UPDATE_ROLLBACK_OK='false'
  SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED='false'
  SBV_UPDATE_CURRENT_VERSION=''
  SBV_UPDATE_CANDIDATE_VERSION=''
  SBV_UPDATE_TARGET_PATH="${SBV_BIN_PATH}"
  SBV_UPDATE_LOG_FILE="${SBV_LOG_FILE}"
  SBV_UPDATE_TARGET_EXISTS='false'
  SBV_UPDATE_TARGET_WAS_EXECUTABLE='false'
  SBV_UPDATE_TARGET_MODE=''
  SBV_UPDATE_TARGET_UID=''
  SBV_UPDATE_TARGET_GID=''
  SBV_UPDATE_TARGET_HASH=''
  SBV_UPDATE_TARGET_VERSION=''
  SBV_UPDATE_EXPECTED_MODE=''
  SBV_UPDATE_EXPECTED_UID=''
  SBV_UPDATE_EXPECTED_GID=''
  SBV_UPDATE_CANDIDATE_PATH=''
  SBV_UPDATE_CANDIDATE_HASH=''
  SBV_UPDATE_CURL_STDERR_PATH=''
  SBV_UPDATE_BACKUP_PATH=''
  SBV_UPDATE_ROLLBACK_PATH=''
  SBV_UPDATE_LOCK_PATH=''
  SBV_UPDATE_LOCK_HELD='false'
  SBV_UPDATE_COMMITTED='false'
  SBV_UPDATE_NOOP='false'
  SBV_UPDATE_PRESERVE_ARTIFACTS='false'
  SBV_UPDATE_SIGNAL_NAME=''
  SBV_UPDATE_SIGNAL_CODE='0'
  SBV_UPDATE_TRAP_ACTIVE='false'
  SBV_UPDATE_TRAP_RUNNING='false'
  SBV_UPDATE_PREVIOUS_INT_TRAP=''
  SBV_UPDATE_PREVIOUS_TERM_TRAP=''
  SBV_UPDATE_PREVIOUS_HUP_TRAP=''
  SBV_UPDATE_PREVIOUS_ERR_TRAP=''
  SBV_VALIDATED_SCRIPT_VERSION=''
  SBV_SCRIPT_VALIDATION_CODE=''
  SBV_SCRIPT_VALIDATION_DETAIL=''
}

set_sbv_update_error() {
  local operation=${1:-${SBV_UPDATE_OPERATION:-sbv_update}}
  local stage=${2:-${SBV_UPDATE_STAGE:-unknown}}
  local code=${3:-update_failed}
  local message=${4:-操作失败}
  local detail=${5:-}
  local command_exit_code=${6:-0}
  local hint=${7:-}

  SBV_UPDATE_OPERATION=${operation}
  SBV_UPDATE_STAGE=${stage}
  SBV_UPDATE_ERROR_CODE=${code}
  SBV_UPDATE_ERROR_MESSAGE=${message}
  SBV_UPDATE_ERROR_DETAIL=$(sanitize_sbv_detail "${detail}")
  SBV_UPDATE_COMMAND_EXIT_CODE=${command_exit_code}
  SBV_UPDATE_HINT=${hint}
}

report_sbv_update_error() {
  local result='unchanged'
  local operation=${SBV_UPDATE_OPERATION:-sbv_update}
  local display_operation=${operation}
  local detail=${SBV_UPDATE_ERROR_DETAIL:-no detail available}

  case "${operation}" in
    sbv_update|ensure_sbv_local|ensure_sbv_remote) display_operation='sbv 自更新' ;;
    media_check_backend) display_operation='流媒体验证脚本下载' ;;
  esac

  if [[ "${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}" == 'true' ]]; then
    result='rollback_failed'
  elif [[ "${SBV_UPDATE_ROLLED_BACK}" == 'true' && "${SBV_UPDATE_ROLLBACK_OK}" == 'true' ]]; then
    result='rolled_back'
  fi

  printf '[ERROR] %s 失败\n' "${display_operation}" >&2
  printf '操作: %s\n' "${operation}" >&2
  printf '操作阶段: %s\n' "${SBV_UPDATE_STAGE:-unknown}" >&2
  printf '错误代码: %s\n' "${SBV_UPDATE_ERROR_CODE:-update_failed}" >&2
  printf '错误消息: %s\n' "${SBV_UPDATE_ERROR_MESSAGE:-操作失败}" >&2
  printf '底层退出码: %s\n' "${SBV_UPDATE_COMMAND_EXIT_CODE:-0}" >&2
  printf '错误详情: %s\n' "${detail}" >&2
  printf '上下文:\n' >&2
  printf '  operation: %s\n' "${operation}" >&2
  printf '  stage: %s\n' "${SBV_UPDATE_STAGE:-unknown}" >&2
  printf '  code: %s\n' "${SBV_UPDATE_ERROR_CODE:-update_failed}" >&2
  printf '  message: %s\n' "${SBV_UPDATE_ERROR_MESSAGE:-操作失败}" >&2
  printf '  detail: %s\n' "${detail}" >&2
  printf '  command_exit_code: %s\n' "${SBV_UPDATE_COMMAND_EXIT_CODE:-0}" >&2
  printf '  hint: %s\n' "${SBV_UPDATE_HINT:-}" >&2
  printf '状态:\n' >&2
  printf '  changed: %s\n' "${SBV_UPDATE_CHANGED}" >&2
  printf '  rollback_attempted: %s\n' "${SBV_UPDATE_ROLLBACK_ATTEMPTED}" >&2
  printf '  rolled_back: %s\n' "${SBV_UPDATE_ROLLED_BACK}" >&2
  printf '  rollback_ok: %s\n' "${SBV_UPDATE_ROLLBACK_OK}" >&2
  printf '  manual_intervention_required: %s\n' \
    "${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}" >&2
  printf '  处理结果: %s\n' "${result}" >&2
  printf '版本:\n' >&2
  printf '  current_version: %s\n' "${SBV_UPDATE_CURRENT_VERSION:-unknown}" >&2
  printf '  candidate_version: %s\n' "${SBV_UPDATE_CANDIDATE_VERSION:-unknown}" >&2
  printf '路径:\n' >&2
  printf '  target_path: %s\n' "${SBV_UPDATE_TARGET_PATH}" >&2
  printf '  target_sha256: %s\n' "${SBV_UPDATE_TARGET_HASH:-unknown}" >&2
  printf '  target_mode: %s\n' "${SBV_UPDATE_TARGET_MODE:-unknown}" >&2
  if [[ -n "${SBV_UPDATE_TARGET_UID}" && -n "${SBV_UPDATE_TARGET_GID}" ]]; then
    printf '  target_owner: %s:%s\n' "${SBV_UPDATE_TARGET_UID}" "${SBV_UPDATE_TARGET_GID}" >&2
  else
    printf '  target_owner: unknown\n' >&2
  fi
  if [[ -n "${SBV_UPDATE_BACKUP_PATH}" ]]; then
    printf '  backup_path: %s\n' "${SBV_UPDATE_BACKUP_PATH}" >&2
  fi
  if [[ -n "${SBV_UPDATE_CANDIDATE_PATH}" ]]; then
    printf '  candidate_path: %s\n' "${SBV_UPDATE_CANDIDATE_PATH}" >&2
  fi
  printf '  candidate_sha256: %s\n' "${SBV_UPDATE_CANDIDATE_HASH:-unknown}" >&2
  if [[ -n "${SBV_UPDATE_HINT}" ]]; then
    printf '建议: %s\n' "${SBV_UPDATE_HINT}" >&2
  fi
  printf '日志: %s\n' "${SBV_UPDATE_LOG_FILE}" >&2
  printf '  log_file: %s\n' "${SBV_UPDATE_LOG_FILE}" >&2

  append_sbv_update_log 'ERROR' \
    "${operation} ${SBV_UPDATE_ERROR_CODE:-update_failed}: ${SBV_UPDATE_ERROR_MESSAGE}; result=${result}; changed=${SBV_UPDATE_CHANGED}; rollback_attempted=${SBV_UPDATE_ROLLBACK_ATTEMPTED}; rolled_back=${SBV_UPDATE_ROLLED_BACK}; rollback_ok=${SBV_UPDATE_ROLLBACK_OK}; manual_intervention_required=${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}; detail=${detail}" \
    || true
}

extract_sbv_script_version() {
  local script_file=$1
  local match_count
  local script_version

  [[ -f "${script_file}" ]] || return 1
  match_count=$(grep -Ec '^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="[0-9]{10}"[[:space:]]*$' \
    "${script_file}" 2>/dev/null || true)
  [[ "${match_count}" == '1' ]] || return 1
  script_version=$(sed -nE \
    's/^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="([0-9]{10})"[[:space:]]*$/\1/p' \
    "${script_file}")
  [[ "${script_version}" =~ ^[0-9]{10}$ ]] || return 1
  printf '%s' "${script_version}"
}

set_sbv_script_validation_failure() {
  SBV_SCRIPT_VALIDATION_CODE=$1
  SBV_SCRIPT_VALIDATION_DETAIL=$2
  return 1
}

validate_sbv_script_file() {
  local script_file=$1
  local file_size
  local first_line=''
  local syntax_detail=''
  local script_version=''

  SBV_SCRIPT_VALIDATION_CODE=''
  SBV_SCRIPT_VALIDATION_DETAIL=''
  SBV_VALIDATED_SCRIPT_VERSION=''

  if [[ ! -f "${script_file}" ]]; then
    set_sbv_script_validation_failure 'candidate_missing' '候选文件不存在或不是普通文件'
    return 1
  fi
  if [[ -L "${script_file}" ]]; then
    set_sbv_script_validation_failure 'candidate_symlink' '候选文件是符号链接，已拒绝'
    return 1
  fi
  if ! file_size=$(wc -c < "${script_file}"); then
    set_sbv_script_validation_failure 'candidate_unreadable' '无法读取候选文件大小'
    return 1
  fi
  if (( file_size < SBV_SCRIPT_MIN_SIZE )); then
    set_sbv_script_validation_failure 'candidate_too_small' \
      "候选文件大小 ${file_size} 字节，小于最小要求 ${SBV_SCRIPT_MIN_SIZE} 字节"
    return 1
  fi
  IFS= read -r first_line < "${script_file}" || true
  if [[ "${first_line}" != '#!/usr/bin/env bash' ]]; then
    set_sbv_script_validation_failure 'candidate_shebang_invalid' \
      '候选文件缺少预期的 #!/usr/bin/env bash shebang'
    return 1
  fi
  if LC_ALL=C grep -Eiq '^[[:space:]]*(<!doctype[[:space:]]+html|<html|<body)' \
    "${script_file}"; then
    set_sbv_script_validation_failure 'candidate_html' '候选内容看起来是 HTML 或网关错误页'
    return 1
  fi
  if ! syntax_detail=$(bash -n -- "${script_file}" 2>&1); then
    set_sbv_script_validation_failure 'candidate_syntax_invalid' \
      "Bash 语法校验失败: ${syntax_detail}"
    return 1
  fi
  if ! script_version=$(extract_sbv_script_version "${script_file}"); then
    set_sbv_script_validation_failure 'candidate_version_invalid' \
      '必须存在且只能存在一个 YYYYMMDDXX 格式的 SCRIPT_VERSION'
    return 1
  fi
  if ! grep -Fqx 'readonly PROJECT_AUTHOR="KnowSky404"' "${script_file}"; then
    set_sbv_script_validation_failure 'candidate_identity_mismatch' \
      'PROJECT_AUTHOR 与 sing-box-vps 身份不匹配'
    return 1
  fi
  if ! grep -Fqx 'readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"' \
    "${script_file}"; then
    set_sbv_script_validation_failure 'candidate_identity_mismatch' \
      'PROJECT_URL 与 sing-box-vps 身份不匹配'
    return 1
  fi

  SBV_VALIDATED_SCRIPT_VERSION=${script_version}
  return 0
}

calculate_sbv_sha256() {
  command -v sha256sum >/dev/null 2>&1 || return 127
  sha256sum -- "$1" | awk '{print $1}'
}

get_sbv_file_metadata() {
  local metadata

  if ! metadata=$(stat -c '%a:%u:%g' -- "$1"); then
    return 1
  fi
  IFS=: read -r SBV_UPDATE_TARGET_MODE SBV_UPDATE_TARGET_UID SBV_UPDATE_TARGET_GID <<< \
    "${metadata}"
  [[ -n "${SBV_UPDATE_TARGET_MODE}" && -n "${SBV_UPDATE_TARGET_UID}" && \
    -n "${SBV_UPDATE_TARGET_GID}" ]]
}

sbv_update_signal_handler() {
  local signal_name=$1

  if [[ "${SBV_UPDATE_TRAP_RUNNING}" == 'true' ]]; then
    return 0
  fi
  SBV_UPDATE_TRAP_RUNNING='true'
  SBV_UPDATE_SIGNAL_NAME=${signal_name}
  case "${signal_name}" in
    INT) SBV_UPDATE_SIGNAL_CODE='130' ;;
    TERM) SBV_UPDATE_SIGNAL_CODE='143' ;;
    HUP) SBV_UPDATE_SIGNAL_CODE='129' ;;
    *) SBV_UPDATE_SIGNAL_CODE='1' ;;
  esac
  SBV_UPDATE_TRAP_RUNNING='false'
}

sbv_update_unexpected_error_handler() {
  local command_exit_code=${1:-1}

  if [[ "${SBV_UPDATE_TRAP_RUNNING}" == 'true' || \
    "${SBV_UPDATE_TRAP_ACTIVE}" != 'true' ]]; then
    return 0
  fi
  SBV_UPDATE_TRAP_RUNNING='true'
  if [[ -z "${SBV_UPDATE_ERROR_CODE}" ]]; then
    set_sbv_update_error \
      "${SBV_UPDATE_OPERATION:-sbv_update}" \
      "${SBV_UPDATE_STAGE:-unknown}" \
      'unexpected_error' \
      '更新过程中发生未预期异常' \
      '某个底层命令失败，详细命令内容未记录以避免泄露敏感信息' \
      "${command_exit_code}" \
      '检查日志中的阶段信息，并确认目标脚本及保留的恢复文件状态'
  fi
  SBV_UPDATE_TRAP_RUNNING='false'
}

install_sbv_update_traps() {
  SBV_UPDATE_PREVIOUS_INT_TRAP=$(trap -p INT || true)
  SBV_UPDATE_PREVIOUS_TERM_TRAP=$(trap -p TERM || true)
  SBV_UPDATE_PREVIOUS_HUP_TRAP=$(trap -p HUP || true)
  SBV_UPDATE_PREVIOUS_ERR_TRAP=$(trap -p ERR || true)
  trap 'sbv_update_signal_handler INT' INT
  trap 'sbv_update_signal_handler TERM' TERM
  trap 'sbv_update_signal_handler HUP' HUP
  trap 'sbv_update_unexpected_error_handler "$?"' ERR
  SBV_UPDATE_TRAP_ACTIVE='true'
}

restore_sbv_update_traps() {
  [[ "${SBV_UPDATE_TRAP_ACTIVE}" == 'true' ]] || return 0

  trap - INT TERM HUP ERR
  if [[ -n "${SBV_UPDATE_PREVIOUS_INT_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_INT_TRAP}" || true
  fi
  if [[ -n "${SBV_UPDATE_PREVIOUS_TERM_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_TERM_TRAP}" || true
  fi
  if [[ -n "${SBV_UPDATE_PREVIOUS_HUP_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_HUP_TRAP}" || true
  fi
  if [[ -n "${SBV_UPDATE_PREVIOUS_ERR_TRAP}" ]]; then
    eval "${SBV_UPDATE_PREVIOUS_ERR_TRAP}" || true
  fi
  SBV_UPDATE_TRAP_ACTIVE='false'
}

prepare_sbv_update() {
  local target_dir
  local target_version=''
  local lock_status=0

  SBV_UPDATE_STAGE='precheck'
  storage_initialize || {
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'storage_unavailable' \
      '私有存储目录无法安全初始化' '目录权限或所有者不可信' 1 '检查统一根目录；目标未发生变更'
    return 1
  }
  storage_selinux_prepare || {
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'selinux_setup_failed' \
      'SELinux 文件上下文无法安全准备' '已保留管理员规则，未发布候选脚本' 1 '检查 SELinux 工具、规则和目录标签'
    return 1
  }
  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  SBV_UPDATE_LOCK_PATH="${target_dir}/.sbv-update.lock"

  if [[ ! -d "${target_dir}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_directory_missing' \
      'sbv 目标目录不存在' "目标目录: ${target_dir}" 1 \
      '确认私有 bin 目录存在且当前用户具有 root 权限'
    return 1
  fi
  if [[ -L "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_symlink_unsupported' \
      'sbv 目标是符号链接，已安全拒绝更新' "目标路径: ${SBV_BIN_PATH}" 1 \
      '请先将符号链接解析为受管普通文件后再更新'
    return 1
  fi
  if [[ -e "${SBV_BIN_PATH}" && ! -f "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_not_regular' \
      'sbv 目标不是普通文件，已安全拒绝更新' "目标路径: ${SBV_BIN_PATH}" 1 \
      '移除目录或特殊文件后再重试；目标未发生变更'
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'curl_unavailable' \
      '找不到 curl，无法下载候选脚本' 'curl command not found' 127 \
      '安装 curl 后重试'
    return 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'sha256sum_unavailable' \
      '找不到 sha256sum，无法核对候选完整性' 'sha256sum command not found' 127 \
      '安装提供 sha256sum 的系统工具后重试'
    return 1
  fi
  if mkdir "${SBV_UPDATE_LOCK_PATH}" 2>/dev/null; then
    :
  else
    lock_status=$?
    if [[ -e "${SBV_UPDATE_LOCK_PATH}" || -L "${SBV_UPDATE_LOCK_PATH}" ]]; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'update_in_progress' \
        '已有另一个 sbv 更新事务正在运行' "锁路径: ${SBV_UPDATE_LOCK_PATH}" 1 \
        '等待现有更新结束后再重试；未取得锁时目标未发生变更'
      lock_status=1
    else
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'lock_create_failed' \
        '无法创建 sbv 更新锁' "锁路径: ${SBV_UPDATE_LOCK_PATH}" "${lock_status}" \
        '检查目标目录的写权限、磁盘空间和文件系统状态；目标未发生变更'
    fi
    return "${lock_status}"
  fi
  SBV_UPDATE_LOCK_HELD='true'

  if [[ -f "${SBV_BIN_PATH}" ]]; then
    SBV_UPDATE_TARGET_EXISTS='true'
    if [[ -x "${SBV_BIN_PATH}" ]]; then
      SBV_UPDATE_TARGET_WAS_EXECUTABLE='true'
    fi
    if ! get_sbv_file_metadata "${SBV_BIN_PATH}"; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_metadata_failed' \
        '无法读取现有 sbv 的权限或所有者' "目标路径: ${SBV_BIN_PATH}" 1 \
        '检查目标文件及私有 bin 目录的权限'
      return 1
    fi
    if ! SBV_UPDATE_TARGET_HASH=$(calculate_sbv_sha256 "${SBV_BIN_PATH}"); then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'precheck' 'target_hash_failed' \
        '无法计算现有 sbv 的 SHA-256' "目标路径: ${SBV_BIN_PATH}" 1 \
        '检查目标文件是否可读'
      return 1
    fi
    if target_version=$(extract_sbv_script_version "${SBV_BIN_PATH}"); then
      SBV_UPDATE_TARGET_VERSION=${target_version}
      SBV_UPDATE_CURRENT_VERSION=${target_version}
    else
      SBV_UPDATE_CURRENT_VERSION=${SCRIPT_VERSION}
    fi
  else
    SBV_UPDATE_CURRENT_VERSION=${SCRIPT_VERSION}
  fi
  return 0
}

create_sbv_candidate() {
  local target_dir

  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if ! SBV_UPDATE_CANDIDATE_PATH=$(storage_mktemp "${target_dir}/.sbv-candidate.XXXXXXXXXX"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'candidate_create_failed' \
      '无法创建同目录候选文件' "候选目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    return 1
  fi
  if ! SBV_UPDATE_CURL_STDERR_PATH=$(storage_mktemp "${target_dir}/.sbv-curl-stderr.XXXXXXXXXX"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'diagnostic_file_create_failed' \
      '无法创建下载诊断文件' "诊断目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    return 1
  fi
  return 0
}

classify_sbv_download_error() {
  case "${1:-}" in
    6) printf 'download_dns_failure' ;;
    7) printf 'download_connection_failed' ;;
    18) printf 'download_partial_transfer' ;;
    28) printf 'download_timeout' ;;
    130|143|129) printf 'signal_interrupted' ;;
    *) printf 'download_failed' ;;
  esac
}

stage_sbv_candidate_from_url() {
  local url=$1
  local curl_status=0
  local detail=''

  if ! create_sbv_candidate; then
    return 1
  fi
  if curl -fsSL \
    --connect-timeout "${SBV_CURL_CONNECT_TIMEOUT}" \
    --max-time "${SBV_CURL_MAX_TIME}" \
    --retry "${SBV_CURL_RETRY_COUNT}" \
    --retry-delay "${SBV_CURL_RETRY_DELAY}" \
    -o "${SBV_UPDATE_CANDIDATE_PATH}" "${url}" \
    2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    curl_status=0
  else
    curl_status=$?
  fi
  SBV_UPDATE_COMMAND_EXIT_CODE=${curl_status}
  if [[ "${SBV_UPDATE_SIGNAL_CODE}" != '0' ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'download' 'signal_interrupted' \
      "下载过程中收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${SBV_UPDATE_SIGNAL_CODE}" \
      '重新运行更新；提交前目标脚本保持不变'
    return "${SBV_UPDATE_SIGNAL_CODE}"
  fi
  if [[ "${curl_status}" != '0' ]]; then
    detail=$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'download' "$(classify_sbv_download_error "${curl_status}")" \
      '下载最新 sbv 脚本失败' "${detail}" "${curl_status}" \
      '检查 DNS、IPv4/IPv6 出口、路由或 HTTPS_PROXY；原脚本未发生变更'
    return "${curl_status}"
  fi
  return 0
}

stage_sbv_candidate_from_file() {
  local source_file=$1

  if ! create_sbv_candidate; then
    return 1
  fi
  if [[ ! -f "${source_file}" || -L "${source_file}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'source_not_regular' \
      '当前脚本来源不是可读取的普通文件' "来源路径: ${source_file}" 1 \
      '请从真实文件路径运行 install.sh'
    return 1
  fi
  if ! cp -p -- "${source_file}" "${SBV_UPDATE_CANDIDATE_PATH}" 2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'stage' 'candidate_copy_failed' \
      '无法将当前脚本复制到候选文件' \
      "$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")" 1 \
      '检查目标目录的磁盘空间和权限'
    return 1
  fi
  return 0
}

sbv_target_is_healthy() {
  [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]] || return 1
  [[ -f "${SBV_BIN_PATH}" && -x "${SBV_BIN_PATH}" ]] || return 1
  validate_sbv_script_file "${SBV_BIN_PATH}"
}

validate_sbv_candidate() {
  local candidate_version
  local validation_code
  local validation_detail

  SBV_UPDATE_STAGE='validate'
  if ! validate_sbv_script_file "${SBV_UPDATE_CANDIDATE_PATH}"; then
    validation_code=${SBV_SCRIPT_VALIDATION_CODE:-candidate_invalid}
    validation_detail=${SBV_SCRIPT_VALIDATION_DETAIL:-候选文件校验失败}
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'validate' "${validation_code}" \
      '候选 sbv 脚本校验失败' "${validation_detail}" 1 \
      '拒绝提交候选文件；原脚本未发生变更'
    return 1
  fi
  candidate_version=${SBV_VALIDATED_SCRIPT_VERSION}
  SBV_UPDATE_CANDIDATE_VERSION=${candidate_version}
  if ! SBV_UPDATE_CANDIDATE_HASH=$(calculate_sbv_sha256 "${SBV_UPDATE_CANDIDATE_PATH}"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'validate' 'candidate_hash_failed' \
      '无法计算候选 sbv 的 SHA-256' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '拒绝提交候选文件；原脚本未发生变更'
    return 1
  fi

  if [[ "${SBV_UPDATE_CURRENT_VERSION}" =~ ^[0-9]{10}$ ]] && \
    (( 10#${candidate_version} < 10#${SBV_UPDATE_CURRENT_VERSION} )); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'validate' 'candidate_version_downgrade' \
      '候选 sbv 版本低于当前版本，已拒绝降级' \
      "当前版本: ${SBV_UPDATE_CURRENT_VERSION}; 候选版本: ${candidate_version}" 1 \
      '确认远端分支和当前版本来源后再重试'
    return 1
  fi

  if [[ "${candidate_version}" == "${SBV_UPDATE_CURRENT_VERSION}" ]] && \
    sbv_target_is_healthy; then
    SBV_UPDATE_NOOP='true'
  fi
  return 0
}

create_sbv_backup() {
  local target_dir

  SBV_UPDATE_STAGE='backup'
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" != 'true' ]]; then
    return 0
  fi
  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if ! SBV_UPDATE_BACKUP_PATH=$(storage_mktemp "${target_dir}/.sbv-backup.XXXXXXXXXX"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_create_failed' \
      '无法创建受保护的 sbv 备份' "备份目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限；原脚本未发生变更'
    return 1
  fi
  if ! cp -p -- "${SBV_BIN_PATH}" "${SBV_UPDATE_BACKUP_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_copy_failed' \
      '无法创建现有 sbv 的备份' "目标路径: ${SBV_BIN_PATH}" 1 \
      '检查目标文件是否可读；原脚本未发生变更'
    return 1
  fi
  if ! chmod 0600 "${SBV_UPDATE_BACKUP_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_protect_failed' \
      '无法设置 sbv 备份的 root-only 权限' \
      "备份路径: ${SBV_UPDATE_BACKUP_PATH}" 1 \
      '检查文件系统权限；原脚本未发生变更'
    return 1
  fi
  if ! chown 0:0 "${SBV_UPDATE_BACKUP_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'backup' 'backup_protect_failed' \
      '无法将 sbv 备份设置为 root 所有' \
      "备份路径: ${SBV_UPDATE_BACKUP_PATH}" 1 \
      '检查文件系统权限；原脚本未发生变更'
    return 1
  fi
  return 0
}

prepare_sbv_candidate_for_commit() {
  local candidate_mode='755'

  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' && \
    "${SBV_UPDATE_TARGET_WAS_EXECUTABLE}" == 'true' ]]; then
    candidate_mode=${SBV_UPDATE_TARGET_MODE}
  fi
  SBV_UPDATE_EXPECTED_MODE=${candidate_mode}
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]]; then
    SBV_UPDATE_EXPECTED_UID=${SBV_UPDATE_TARGET_UID}
    SBV_UPDATE_EXPECTED_GID=${SBV_UPDATE_TARGET_GID}
  fi
  if ! chmod "${candidate_mode}" "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'candidate_chmod_failed' \
      '无法设置候选 sbv 的执行权限' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '检查目标目录的权限；原脚本未发生变更'
    return 1
  fi
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]] && \
    ! chown "${SBV_UPDATE_TARGET_UID}:${SBV_UPDATE_TARGET_GID}" \
      "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'candidate_chown_failed' \
      '无法保留 sbv 原有所有者' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '检查 chown 权限；原脚本未发生变更'
    return 1
  fi
  storage_selinux_label "${SBV_UPDATE_CANDIDATE_PATH}" "${SBV_BIN_PATH}" || {
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'selinux_label_failed' \
      '候选脚本的 SELinux 标签校验失败' '原脚本未发生变更' 1 '检查项目文件上下文规则'
    return 1
  }
  return 0
}

commit_sbv_candidate() {
  SBV_UPDATE_STAGE='commit'
  if ! prepare_sbv_candidate_for_commit; then
    return 1
  fi
  if ! mv -f -- "${SBV_UPDATE_CANDIDATE_PATH}" "${SBV_BIN_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'commit' 'atomic_replace_failed' \
      '无法原子替换 sbv 目标文件' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '检查目标目录权限和文件系统状态；原脚本未发生变更'
    return 1
  fi
  SBV_UPDATE_COMMITTED='true'
  SBV_UPDATE_CHANGED='true'
  return 0
}

postcheck_sbv_update() {
  local actual_hash
  local actual_mode
  local actual_uid
  local actual_gid

  SBV_UPDATE_STAGE='postcheck'
  if [[ ! -f "${SBV_BIN_PATH}" || -L "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'target_missing_after_commit' \
      '提交后未找到有效的 sbv 目标文件' "目标路径: ${SBV_BIN_PATH}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if ! validate_sbv_script_file "${SBV_BIN_PATH}"; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_validation_failed' \
      '提交后的 sbv 脚本校验失败' \
      "${SBV_SCRIPT_VALIDATION_DETAIL:-目标校验失败}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ "${SBV_VALIDATED_SCRIPT_VERSION}" != "${SBV_UPDATE_CANDIDATE_VERSION}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_version_mismatch' \
      '提交后的 sbv 版本与候选版本不一致' \
      "目标版本: ${SBV_VALIDATED_SCRIPT_VERSION}; 候选版本: ${SBV_UPDATE_CANDIDATE_VERSION}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if ! actual_hash=$(calculate_sbv_sha256 "${SBV_BIN_PATH}"); then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_hash_failed' \
      '无法计算提交后 sbv 的 SHA-256' "目标路径: ${SBV_BIN_PATH}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ "${actual_hash}" != "${SBV_UPDATE_CANDIDATE_HASH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_hash_mismatch' \
      '提交后的 sbv SHA-256 与候选不一致' \
      "候选哈希: ${SBV_UPDATE_CANDIDATE_HASH}; 目标哈希: ${actual_hash}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ ! -x "${SBV_BIN_PATH}" ]]; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_not_executable' \
      '提交后的 sbv 不可执行' "目标路径: ${SBV_BIN_PATH}" 1 \
      '事务将尝试恢复更新前的脚本'
    return 1
  fi
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" == 'true' ]]; then
    if ! actual_mode=$(stat -c '%a' -- "${SBV_BIN_PATH}") || \
      ! actual_uid=$(stat -c '%u' -- "${SBV_BIN_PATH}") || \
      ! actual_gid=$(stat -c '%g' -- "${SBV_BIN_PATH}"); then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_metadata_failed' \
        '无法读取提交后 sbv 的权限或所有者' "目标路径: ${SBV_BIN_PATH}" 1 \
        '事务将尝试恢复更新前的脚本'
      return 1
    fi
    if [[ "${actual_mode}" != "${SBV_UPDATE_EXPECTED_MODE}" || \
      "${actual_uid}" != "${SBV_UPDATE_EXPECTED_UID}" || \
      "${actual_gid}" != "${SBV_UPDATE_EXPECTED_GID}" ]]; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'postcheck_metadata_mismatch' \
        '提交后的 sbv 权限或所有者与预期不一致' \
        "实际: ${actual_mode}:${actual_uid}:${actual_gid}; 预期: ${SBV_UPDATE_EXPECTED_MODE}:${SBV_UPDATE_EXPECTED_UID}:${SBV_UPDATE_EXPECTED_GID}" 1 \
        '事务将尝试恢复更新前的脚本'
      return 1
    fi
  fi
  return 0
}

restore_sbv_backup() {
  local target_dir
  local restore_path

  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if [[ "${SBV_UPDATE_TARGET_EXISTS}" != 'true' ]]; then
    if ! rm -f -- "${SBV_BIN_PATH}"; then
      return 1
    fi
    return 0
  fi
  [[ -f "${SBV_UPDATE_BACKUP_PATH}" ]] || return 1
  if ! restore_path=$(storage_mktemp "${target_dir}/.sbv-rollback.XXXXXXXXXX"); then
    return 1
  fi
  SBV_UPDATE_ROLLBACK_PATH=${restore_path}
  if ! cp -p -- "${SBV_UPDATE_BACKUP_PATH}" "${restore_path}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  if ! chmod "${SBV_UPDATE_TARGET_MODE}" "${restore_path}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  if ! chown "${SBV_UPDATE_TARGET_UID}:${SBV_UPDATE_TARGET_GID}" "${restore_path}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  storage_selinux_label "${restore_path}" "${SBV_BIN_PATH}" || return 1
  if ! mv -f -- "${restore_path}" "${SBV_BIN_PATH}"; then
    rm -f -- "${restore_path}" || true
    return 1
  fi
  SBV_UPDATE_ROLLBACK_PATH=''
  return 0
}

verify_sbv_rollback() {
  local restored_hash

  if [[ "${SBV_UPDATE_TARGET_EXISTS}" != 'true' ]]; then
    [[ ! -e "${SBV_BIN_PATH}" && ! -L "${SBV_BIN_PATH}" ]] || return 1
    return 0
  fi
  [[ -f "${SBV_BIN_PATH}" && ! -L "${SBV_BIN_PATH}" ]] || return 1
  validate_sbv_script_file "${SBV_BIN_PATH}" || return 1
  if [[ "${SBV_UPDATE_TARGET_WAS_EXECUTABLE}" == 'true' && \
    ! -x "${SBV_BIN_PATH}" ]]; then
    return 1
  fi
  [[ "${SBV_VALIDATED_SCRIPT_VERSION}" == "${SBV_UPDATE_TARGET_VERSION}" ]] || return 1
  restored_hash=$(calculate_sbv_sha256 "${SBV_BIN_PATH}") || return 1
  [[ "${restored_hash}" == "${SBV_UPDATE_TARGET_HASH}" ]] || return 1
  [[ "$(stat -c '%a' -- "${SBV_BIN_PATH}")" == "${SBV_UPDATE_TARGET_MODE}" ]] || return 1
  [[ "$(stat -c '%u' -- "${SBV_BIN_PATH}")" == "${SBV_UPDATE_TARGET_UID}" ]] || return 1
  [[ "$(stat -c '%g' -- "${SBV_BIN_PATH}")" == "${SBV_UPDATE_TARGET_GID}" ]] || return 1
  return 0
}

preserve_sbv_recovery_artifacts() {
  local target_dir
  local retained_candidate=''

  SBV_UPDATE_PRESERVE_ARTIFACTS='true'
  target_dir=$(dirname -- "${SBV_BIN_PATH}")
  if [[ -f "${SBV_BIN_PATH}" ]]; then
    if retained_candidate=$(storage_mktemp "${target_dir}/.sbv-candidate-retained.XXXXXXXXXX"); then
      if cp -p -- "${SBV_BIN_PATH}" "${retained_candidate}" && \
        chmod 0600 "${retained_candidate}" && chown 0:0 "${retained_candidate}"; then
        SBV_UPDATE_CANDIDATE_PATH=${retained_candidate}
      else
        rm -f -- "${retained_candidate}" || true
      fi
    fi
  fi
}

cleanup_sbv_update() {
  if [[ "${SBV_UPDATE_PRESERVE_ARTIFACTS}" != 'true' ]]; then
    rm -f -- \
      "${SBV_UPDATE_CANDIDATE_PATH}" \
      "${SBV_UPDATE_CURL_STDERR_PATH}" \
      "${SBV_UPDATE_ROLLBACK_PATH}" \
      "${SBV_UPDATE_BACKUP_PATH}" 2>/dev/null || true
  fi
  if [[ "${SBV_UPDATE_LOCK_HELD}" == 'true' ]]; then
    rmdir "${SBV_UPDATE_LOCK_PATH}" 2>/dev/null || true
    SBV_UPDATE_LOCK_HELD='false'
  fi
}

finish_sbv_update_failure() {
  local result_status=${1:-1}
  local original_status=${result_status}
  local original_error_code=''

  if [[ -z "${SBV_UPDATE_ERROR_CODE}" ]]; then
    if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" "${SBV_UPDATE_STAGE:-unknown}" \
        'signal_interrupted' "更新过程中收到 ${SBV_UPDATE_SIGNAL_NAME}" \
        "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${SBV_UPDATE_SIGNAL_CODE}" \
        '重新运行更新；提交前目标脚本保持不变'
    else
      set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" "${SBV_UPDATE_STAGE:-unknown}" \
        'update_failed' 'sbv 更新事务失败' '未提供额外诊断信息' "${result_status}" \
        '原脚本未发生变更，检查日志后重试'
    fi
  fi

  if [[ "${SBV_UPDATE_COMMITTED}" == 'true' ]]; then
    SBV_UPDATE_ROLLBACK_ATTEMPTED='true'
    if restore_sbv_backup && verify_sbv_rollback; then
      SBV_UPDATE_ROLLED_BACK='true'
      SBV_UPDATE_ROLLBACK_OK='true'
    else
      original_error_code=${SBV_UPDATE_ERROR_CODE:-update_failed}
      SBV_UPDATE_ERROR_CODE='rollback_failed'
      SBV_UPDATE_ERROR_MESSAGE='提交后失败且自动恢复未通过最终校验'
      SBV_UPDATE_ERROR_DETAIL=$(sanitize_sbv_detail \
        "${SBV_UPDATE_ERROR_DETAIL}; 原始错误码: ${original_error_code}")
      SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED='true'
      result_status=1
      preserve_sbv_recovery_artifacts
      SBV_UPDATE_HINT='请使用保留的 backup_path 和 candidate_path 人工恢复，并重新校验 bash -n、版本、SHA-256 与执行权限'
    fi
  fi

  cleanup_sbv_update
  restore_sbv_update_traps
  report_sbv_update_error
  if [[ "${SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED}" != 'true' ]]; then
    result_status=${original_status}
  fi
  return "${result_status}"
}

finish_sbv_update_success() {
  if ! storage_publish_system_links sbv; then
    set_sbv_update_error "${SBV_UPDATE_OPERATION:-sbv_update}" 'postcheck' 'system_entry_conflict' \
      '全局 sbv 入口无法安全发布' '入口可能属于其他安装，已拒绝覆盖' 1 '检查受管链接及迁移状态'
    finish_sbv_update_failure 1
    return $?
  fi
  cleanup_sbv_update
  restore_sbv_update_traps
  if [[ "${SBV_UPDATE_NOOP}" == 'true' ]]; then
    printf '[INFO] sbv 已是当前版本 %s，事务 no-op，目标文件未替换（changed: false）。\n' \
      "${SBV_UPDATE_CURRENT_VERSION}"
  else
    printf '[SUCCESS] sbv 已完成原子更新到版本 %s（changed: true）。候选 SHA-256 已在本地提交后核对。\n' \
      "${SBV_UPDATE_CANDIDATE_VERSION}"
  fi
  return 0
}

sbv_update_transaction() {
  local operation=$1
  local source_kind=$2
  local source=$3
  local result_status=1

  reset_sbv_update_context
  SBV_UPDATE_OPERATION=${operation}
  SBV_UPDATE_TARGET_PATH=${SBV_BIN_PATH}
  SBV_UPDATE_LOG_FILE=${SBV_LOG_FILE}
  install_sbv_update_traps

  if prepare_sbv_update; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi

  SBV_UPDATE_STAGE='stage'
  case "${source_kind}" in
    url)
      if stage_sbv_candidate_from_url "${source}"; then
        :
      else
        result_status=$?
        finish_sbv_update_failure "${result_status}" || return $?
        return 0
      fi
      ;;
    file)
      if stage_sbv_candidate_from_file "${source}"; then
        :
      else
        result_status=$?
        finish_sbv_update_failure "${result_status}" || return $?
        return 0
      fi
      ;;
    *)
      set_sbv_update_error "${operation}" 'stage' 'source_kind_invalid' \
        '未知的 sbv 候选来源类型' "来源类型: ${source_kind}" 1 \
        '使用 file 或 url 来源'
      finish_sbv_update_failure 1 || return $?
      return 0
      ;;
  esac
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi

  if validate_sbv_candidate; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ "${SBV_UPDATE_NOOP}" == 'true' ]]; then
    finish_sbv_update_success
    return 0
  fi
  if create_sbv_backup; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if commit_sbv_candidate; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  SBV_UPDATE_STAGE='postcheck'
  if postcheck_sbv_update; then
    :
  else
    result_status=$?
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    finish_sbv_update_failure "${result_status}" || return $?
    return 0
  fi
  finish_sbv_update_success
}

finish_sbv_artifact_failure() {
  local result_status=${1:-1}

  cleanup_sbv_update
  restore_sbv_update_traps
  report_sbv_update_error
  return "${result_status}"
}

finish_sbv_artifact_success() {
  cleanup_sbv_update
  restore_sbv_update_traps
  return 0
}

download_shell_artifact_atomically() {
  local operation=$1
  local url=$2
  local target=$3
  local target_dir
  local target_name
  local lock_path
  local lock_status=0
  local curl_status=0
  local detail=''
  local file_size
  local first_line=''
  local syntax_detail=''
  local target_existed='false'
  local old_mode='0755'
  local old_uid=''
  local old_gid=''
  local old_hash=''
  local actual_mode=''
  local actual_uid=''
  local actual_gid=''
  local restore_hash=''
  local retained_candidate=''
  local result_status=1
  local expected_mode='755'
  local postcheck_failed='false'
  local postcheck_code='postcheck_failed'

  reset_sbv_update_context
  SBV_UPDATE_OPERATION=${operation}
  SBV_UPDATE_TARGET_PATH=${target}
  SBV_UPDATE_LOG_FILE=${SBV_LOG_FILE}
  target_dir=$(dirname -- "${target}")
  target_name=${target##*/}
  lock_path="${target_dir}/.${target_name}.update.lock"
  SBV_UPDATE_LOCK_PATH=${lock_path}

  if [[ ! -d "${target_dir}" ]]; then
    set_sbv_update_error "${operation}" 'precheck' 'target_directory_missing' \
      '可执行 artifact 目标目录不存在' "目标目录: ${target_dir}" 1 \
      '检查目标目录的权限'
    report_sbv_update_error
    return 1
  fi
  if [[ -L "${target}" || ( -e "${target}" && ! -f "${target}" ) ]]; then
    set_sbv_update_error "${operation}" 'precheck' 'target_not_regular' \
      '可执行 artifact 目标不是普通文件' "目标路径: ${target}" 1 \
      '检查目标路径后重试；目标未发生变更'
    report_sbv_update_error
    return 1
  fi

  install_sbv_update_traps
  if mkdir "${lock_path}" 2>/dev/null; then
    :
  else
    lock_status=$?
    if [[ -e "${lock_path}" || -L "${lock_path}" ]]; then
      set_sbv_update_error "${operation}" 'precheck' 'update_in_progress' \
        '已有另一个可执行 artifact 更新事务正在运行' "锁路径: ${lock_path}" 1 \
        '等待现有更新结束后再重试；未取得锁时目标未发生变更'
      lock_status=1
    else
      set_sbv_update_error "${operation}" 'precheck' 'lock_create_failed' \
        '无法创建可执行 artifact 更新锁' "锁路径: ${lock_path}" "${lock_status}" \
        '检查目标目录的写权限、磁盘空间和文件系统状态；目标未发生变更'
    fi
    finish_sbv_artifact_failure "${lock_status}" || return $?
    return 0
  fi
  SBV_UPDATE_LOCK_HELD='true'
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'precheck' 'signal_interrupted' \
      "更新过程中收到 ${SBV_UPDATE_SIGNAL_NAME}" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi
  if [[ -L "${target}" || ( -e "${target}" && ! -f "${target}" ) ]]; then
    set_sbv_update_error "${operation}" 'precheck' 'target_not_regular' \
      '加锁后发现 artifact 目标不是普通文件' "目标路径: ${target}" 1 \
      '检查目标路径后重试；目标未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi

  SBV_UPDATE_STAGE='stage'
  if ! SBV_UPDATE_CANDIDATE_PATH=$(storage_mktemp "${target_dir}/.${target_name}.candidate.XXXXXXXXXX"); then
    set_sbv_update_error "${operation}" 'stage' 'candidate_create_failed' \
      '无法创建可执行 artifact 候选文件' "候选目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if ! SBV_UPDATE_CURL_STDERR_PATH=$(storage_mktemp "${target_dir}/.${target_name}.stderr.XXXXXXXXXX"); then
    set_sbv_update_error "${operation}" 'stage' 'diagnostic_file_create_failed' \
      '无法创建下载诊断文件' "诊断目录: ${target_dir}" 1 \
      '检查目标目录的磁盘空间和权限'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if curl -fsSL \
    --connect-timeout "${SBV_CURL_CONNECT_TIMEOUT}" \
    --max-time "${SBV_CURL_MAX_TIME}" \
    --retry "${SBV_CURL_RETRY_COUNT}" \
    --retry-delay "${SBV_CURL_RETRY_DELAY}" \
    -o "${SBV_UPDATE_CANDIDATE_PATH}" "${url}" \
    2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    curl_status=0
  else
    curl_status=$?
  fi
  SBV_UPDATE_COMMAND_EXIT_CODE=${curl_status}
  if [[ "${SBV_UPDATE_SIGNAL_CODE}" != '0' ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'download' 'signal_interrupted' \
      "下载过程中收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi
  if [[ "${curl_status}" != '0' ]]; then
    detail=$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")
    set_sbv_update_error "${operation}" 'download' "$(classify_sbv_download_error "${curl_status}")" \
      '下载可执行 artifact 失败' "${detail}" "${curl_status}" \
      '检查 DNS、IPv4/IPv6 出口、路由或 HTTPS_PROXY；原文件未发生变更'
    finish_sbv_artifact_failure "${curl_status}" || return $?
    return 0
  fi

  SBV_UPDATE_STAGE='validate'
  if ! file_size=$(wc -c < "${SBV_UPDATE_CANDIDATE_PATH}"); then
    set_sbv_update_error "${operation}" 'validate' 'artifact_size_check_failed' \
      '无法读取下载的 artifact 大小' "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if (( file_size < SBV_ARTIFACT_MIN_SIZE )); then
    set_sbv_update_error "${operation}" 'validate' 'artifact_too_small' \
      '下载的可执行 artifact 为空或过小' "文件大小: ${file_size} 字节" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  IFS= read -r first_line < "${SBV_UPDATE_CANDIDATE_PATH}" || true
  if [[ ! "${first_line}" =~ ^#!.*(bash|sh)([[:space:]]|$) ]]; then
    set_sbv_update_error "${operation}" 'validate' 'artifact_shebang_invalid' \
      '远程 artifact 缺少可识别的 Shell shebang' "首行: ${first_line}" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if LC_ALL=C grep -Eiq '^[[:space:]]*(<!doctype[[:space:]]+html|<html|<body)' \
    "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${operation}" 'validate' 'artifact_html' \
      '远程 artifact 看起来是 HTML 或网关错误页' 'HTML marker detected' 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if ! syntax_detail=$(bash -n -- "${SBV_UPDATE_CANDIDATE_PATH}" 2>&1); then
    set_sbv_update_error "${operation}" 'validate' 'artifact_syntax_invalid' \
      '远程 artifact 未通过 Bash 语法校验' "${syntax_detail}" 1 \
      '拒绝提交远程内容；原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'validate' 'signal_interrupted' \
      "校验过程中收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi

  if [[ -f "${target}" ]]; then
    target_existed='true'
    SBV_UPDATE_TARGET_EXISTS='true'
    if ! get_sbv_file_metadata "${target}"; then
      set_sbv_update_error "${operation}" 'backup' 'target_metadata_failed' \
        '无法读取现有 artifact 的权限或所有者' "目标路径: ${target}" 1 \
        '检查目标文件权限；原文件未发生变更'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    old_mode=${SBV_UPDATE_TARGET_MODE}
    old_uid=${SBV_UPDATE_TARGET_UID}
    old_gid=${SBV_UPDATE_TARGET_GID}
    if ! old_hash=$(calculate_sbv_sha256 "${target}"); then
      set_sbv_update_error "${operation}" 'backup' 'target_hash_failed' \
        '无法计算现有 artifact 的 SHA-256' "目标路径: ${target}" 1 \
        '检查目标文件是否可读；原文件未发生变更'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    SBV_UPDATE_TARGET_HASH=${old_hash}
    if ! SBV_UPDATE_TARGET_VERSION=$(extract_sbv_script_version "${target}"); then
      SBV_UPDATE_TARGET_VERSION='unknown'
    fi
    SBV_UPDATE_CURRENT_VERSION=${SBV_UPDATE_TARGET_VERSION}
    if ! SBV_UPDATE_BACKUP_PATH=$(storage_mktemp "${target_dir}/.${target_name}.backup.XXXXXXXXXX"); then
      set_sbv_update_error "${operation}" 'backup' 'backup_create_failed' \
        '无法创建现有 artifact 的受保护备份' "目标目录: ${target_dir}" 1 \
        '原文件未发生变更；检查目标目录的权限'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    if ! cp -p -- "${target}" "${SBV_UPDATE_BACKUP_PATH}"; then
      set_sbv_update_error "${operation}" 'backup' 'backup_copy_failed' \
        '无法复制现有 artifact 到受保护备份' "目标路径: ${target}" 1 \
        '原文件未发生变更；检查目标目录的权限'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
    if ! chmod 0600 "${SBV_UPDATE_BACKUP_PATH}" || \
      ! chown 0:0 "${SBV_UPDATE_BACKUP_PATH}"; then
      set_sbv_update_error "${operation}" 'backup' 'backup_protect_failed' \
        '无法将 artifact 备份设置为 root-only' \
        "备份路径: ${SBV_UPDATE_BACKUP_PATH}" 1 \
        '检查文件系统权限；原文件未发生变更'
      finish_sbv_artifact_failure 1 || return $?
      return 0
    fi
  else
    SBV_UPDATE_CURRENT_VERSION='unknown'
  fi

  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'backup' 'signal_interrupted' \
      "备份阶段收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi

  if [[ "${target_existed}" == 'true' && -x "${target}" ]]; then
    expected_mode=${old_mode}
  fi
  SBV_UPDATE_EXPECTED_MODE=${expected_mode}
  if ! chmod "${expected_mode}" "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${operation}" 'commit' 'candidate_chmod_failed' \
      '无法设置 artifact 执行权限' "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if [[ "${target_existed}" == 'true' ]] && \
    ! chown "${old_uid}:${old_gid}" "${SBV_UPDATE_CANDIDATE_PATH}"; then
    set_sbv_update_error "${operation}" 'commit' 'candidate_chown_failed' \
      '无法保留 artifact 原有所有者' \
      "候选路径: ${SBV_UPDATE_CANDIDATE_PATH}" 1 \
      '原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    set_sbv_update_error "${operation}" 'commit' 'signal_interrupted' \
      "提交前收到 ${SBV_UPDATE_SIGNAL_NAME}，更新已中断" \
      "信号: ${SBV_UPDATE_SIGNAL_NAME}" "${result_status}" \
      '重新运行更新；提交前目标 artifact 保持不变'
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi
  if [[ "${target_existed}" == 'true' ]]; then
    SBV_UPDATE_EXPECTED_UID=${old_uid}
    SBV_UPDATE_EXPECTED_GID=${old_gid}
  else
    SBV_UPDATE_EXPECTED_MODE='755'
  fi
  SBV_UPDATE_STAGE='commit'
  if ! mv -f -- "${SBV_UPDATE_CANDIDATE_PATH}" "${target}"; then
    set_sbv_update_error "${operation}" 'commit' 'atomic_replace_failed' \
      '无法原子替换可执行 artifact' "目标路径: ${target}" 1 \
      '原文件未发生变更'
    finish_sbv_artifact_failure 1 || return $?
    return 0
  fi
  SBV_UPDATE_COMMITTED='true'
  SBV_UPDATE_CHANGED='true'

  SBV_UPDATE_STAGE='postcheck'
  if [[ -n "${SBV_UPDATE_SIGNAL_NAME}" ]]; then
    postcheck_failed='true'
    postcheck_code='signal_interrupted'
    result_status=${SBV_UPDATE_SIGNAL_CODE}
    detail="信号: ${SBV_UPDATE_SIGNAL_NAME}"
    SBV_UPDATE_COMMAND_EXIT_CODE=${result_status}
  elif [[ ! -f "${target}" || -L "${target}" ]]; then
    postcheck_failed='true'
    postcheck_code='postcheck_target_invalid'
    detail="目标路径: ${target}"
    SBV_UPDATE_COMMAND_EXIT_CODE='1'
  elif ! bash -n -- "${target}" 2>"${SBV_UPDATE_CURL_STDERR_PATH}"; then
    postcheck_failed='true'
    postcheck_code='postcheck_syntax_invalid'
    detail=$(read_sbv_detail_file "${SBV_UPDATE_CURL_STDERR_PATH}")
    SBV_UPDATE_COMMAND_EXIT_CODE='1'
  elif [[ ! -x "${target}" ]]; then
    postcheck_failed='true'
    postcheck_code='postcheck_not_executable'
    detail="目标路径: ${target}"
    SBV_UPDATE_COMMAND_EXIT_CODE='1'
  elif [[ "${target_existed}" == 'true' ]]; then
    if ! actual_mode=$(stat -c '%a' -- "${target}") || \
      ! actual_uid=$(stat -c '%u' -- "${target}") || \
      ! actual_gid=$(stat -c '%g' -- "${target}"); then
      postcheck_failed='true'
      postcheck_code='postcheck_metadata_failed'
      detail="目标路径: ${target}"
      SBV_UPDATE_COMMAND_EXIT_CODE='1'
    elif [[ "${actual_mode}" != "${SBV_UPDATE_EXPECTED_MODE}" || \
      "${actual_uid}" != "${old_uid}" || \
      "${actual_gid}" != "${old_gid}" ]]; then
      postcheck_failed='true'
      postcheck_code='postcheck_metadata_mismatch'
      detail="实际: ${actual_mode}:${actual_uid}:${actual_gid}; 预期: ${SBV_UPDATE_EXPECTED_MODE}:${old_uid}:${old_gid}"
      SBV_UPDATE_COMMAND_EXIT_CODE='1'
    fi
  fi
  if [[ "${postcheck_failed}" != 'true' ]]; then
    finish_sbv_artifact_success
    return 0
  fi

  SBV_UPDATE_ROLLBACK_ATTEMPTED='true'
  if [[ "${target_existed}" == 'true' ]]; then
    if SBV_UPDATE_ROLLBACK_PATH=$(storage_mktemp "${target_dir}/.${target_name}.rollback.XXXXXXXXXX") && \
      cp -p -- "${SBV_UPDATE_BACKUP_PATH}" "${SBV_UPDATE_ROLLBACK_PATH}" && \
      chmod "${old_mode}" "${SBV_UPDATE_ROLLBACK_PATH}" && \
      chown "${old_uid}:${old_gid}" "${SBV_UPDATE_ROLLBACK_PATH}" && \
      mv -f -- "${SBV_UPDATE_ROLLBACK_PATH}" "${target}" && \
      [[ -f "${target}" && ! -L "${target}" ]] && \
      bash -n -- "${target}" && \
      [[ "$(stat -c '%a' -- "${target}")" == "${old_mode}" ]] && \
      [[ "$(stat -c '%u' -- "${target}")" == "${old_uid}" ]] && \
      [[ "$(stat -c '%g' -- "${target}")" == "${old_gid}" ]] && \
      restore_hash=$(calculate_sbv_sha256 "${target}") && [[ "${restore_hash}" == "${old_hash}" ]]; then
      SBV_UPDATE_ROLLBACK_PATH=''
      SBV_UPDATE_ROLLED_BACK='true'
      SBV_UPDATE_ROLLBACK_OK='true'
      set_sbv_update_error "${operation}" 'postcheck' "${postcheck_code}" \
        '提交后的 artifact 校验失败，已恢复原文件' "${detail}" \
        "${SBV_UPDATE_COMMAND_EXIT_CODE:-1}" \
        '原文件已恢复，未保留无效远程内容'
      result_status=${SBV_UPDATE_COMMAND_EXIT_CODE:-1}
      finish_sbv_artifact_failure "${result_status}" || return $?
      return 0
    fi
  elif rm -f -- "${target}" && [[ ! -e "${target}" && ! -L "${target}" ]]; then
    SBV_UPDATE_ROLLED_BACK='true'
    SBV_UPDATE_ROLLBACK_OK='true'
    set_sbv_update_error "${operation}" 'postcheck' "${postcheck_code}" \
      '提交后的 artifact 校验失败，已删除原本不存在的无效目标' "${detail}" \
      "${SBV_UPDATE_COMMAND_EXIT_CODE:-1}" \
      '原目标原本不存在；请重新运行下载'
    result_status=${SBV_UPDATE_COMMAND_EXIT_CODE:-1}
    finish_sbv_artifact_failure "${result_status}" || return $?
    return 0
  fi

  if [[ -f "${target}" && ! -L "${target}" ]]; then
    if retained_candidate=$(storage_mktemp "${target_dir}/.${target_name}.candidate-retained.XXXXXXXXXX") && \
      cp -p -- "${target}" "${retained_candidate}" && \
      chmod 0600 "${retained_candidate}" && chown 0:0 "${retained_candidate}"; then
      SBV_UPDATE_CANDIDATE_PATH=${retained_candidate}
    else
      rm -f -- "${retained_candidate}" 2>/dev/null || true
    fi
  fi
  SBV_UPDATE_PRESERVE_ARTIFACTS='true'
  set_sbv_update_error "${operation}" 'postcheck' 'rollback_failed' \
    '提交后的 artifact 校验失败且自动恢复失败' "${detail}" \
    "${SBV_UPDATE_COMMAND_EXIT_CODE:-1}" \
    '保留的备份和候选文件可能需要人工恢复'
  SBV_UPDATE_MANUAL_INTERVENTION_REQUIRED='true'
  finish_sbv_artifact_failure 1 || return $?
  return 0
}

# Check for script update status. This is a read-only best-effort operation;
# unlike a mutating update it reports unavailable instead of propagating a
# network failure into the menu loop.
check_script_status() {
  local remote_content=''
  local remote_version=''

  if ! remote_content=$(curl -fsSL \
    --connect-timeout 5 \
    --max-time 15 \
    --retry 1 \
    --retry-delay 1 \
    "${SBV_UPDATE_URL}" 2>/dev/null); then
    SCRIPT_VER_STATUS="${RED}(无法检测更新: 网络不可用)${NC}"
    return 0
  fi

  if ! remote_version=$(printf '%s\n' "${remote_content}" | sed -nE \
    's/^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="([0-9]{10})"[[:space:]]*$/\1/p' \
    | awk 'NF { count += 1; value = $0 } END { if (count == 1) print value }'); then
    SCRIPT_VER_STATUS="${RED}(无法检测更新: 响应解析失败)${NC}"
    return 0
  fi
  if [[ -z "${remote_version}" ]]; then
    SCRIPT_VER_STATUS="${RED}(无法检测更新: 响应无有效版本)${NC}"
    return 0
  fi

  if (( 10#${remote_version} > 10#${SCRIPT_VERSION} )); then
    SCRIPT_VER_STATUS="${YELLOW}(有新版本: ${remote_version})${NC}"
  else
    SCRIPT_VER_STATUS="${GREEN}(已是最新)${NC}"
  fi
  return 0
}

manual_update_script() {
  local result_status=0

  log_info "正在从 GitHub 获取最新脚本..."
  if sbv_update_transaction 'sbv_update' url "${SBV_UPDATE_URL}"; then
    if [[ "${SBV_UPDATE_NOOP}" == 'true' ]]; then
      log_info "当前 sbv 已是最新版本。"
    else
      log_success "脚本已原子更新到 ${SBV_UPDATE_CANDIDATE_VERSION}。"
    fi
    return 0
  else
    result_status=$?
  fi
  return "${result_status}"
}

reload_sbv_menu_after_update() {
  local result_status=0
  local execfail_was_set='false'
  local errexit_was_set='false'

  # A disk no-op can still leave an older runtime in memory.
  if [[ "${SBV_UPDATE_NOOP}" == 'true' && \
    "${SBV_UPDATE_CANDIDATE_VERSION}" == "${SCRIPT_VERSION}" ]]; then
    return 0
  fi

  log_info "正在切换到更新后的 sbv 管理菜单..."
  # Keep the existing flock and its descriptor across exec. Opening a second
  # descriptor in the new runtime would conflict with our own inherited lock.
  export SB_MANAGEMENT_LOCK_FD SB_MANAGEMENT_LOCK_MODE
  if shopt -q execfail; then
    execfail_was_set='true'
  fi
  if [[ $- == *e* ]]; then
    errexit_was_set='true'
  fi
  # Bash errexit can terminate even a conditional exec despite execfail.
  shopt -s execfail
  set +e
  exec "${BASH}" "${SBV_BIN_PATH}" || result_status=$?
  if [[ "${errexit_was_set}" == 'true' ]]; then
    set -e
  fi
  if [[ "${execfail_was_set}" != 'true' ]]; then
    shopt -u execfail
  fi
  return "${result_status}"
}

ensure_sbv_command_installed() {
  local source_file=$0
  local result_status=0
  storage_initialize || return 1
  storage_selinux_prepare || return 1

  if [[ "${source_file}" == "${SBV_LINK_PATH}" && -L "${source_file}" &&
        "$(readlink -- "${source_file}")" == "${SBV_BIN_PATH}" ]]; then
    source_file=${SBV_BIN_PATH}
  fi

  if [[ "${source_file}" == "${SBV_BIN_PATH}" || "${source_file}" == 'sbv' ]]; then
    storage_publish_system_links sbv
    return $?
  fi

  if [[ -f "${source_file}" && ! -L "${source_file}" ]]; then
    log_info "正在同步全局命令: sbv..."
    if sbv_update_transaction 'ensure_sbv_local' file "${source_file}"; then
      storage_publish_system_links sbv || return 1
      log_success "全局命令 sbv 已同步为当前脚本版本。"
      return 0
    else
      result_status=$?
    fi
    log_warn "当前脚本同步失败（退出码 ${result_status}），将尝试远程候选。"
  fi

  log_info "正在安装全局命令: sbv..."
  if sbv_update_transaction 'ensure_sbv_remote' url "${SBV_UPDATE_URL}"; then
    storage_publish_system_links sbv || return 1
    log_success "全局命令 sbv 安装成功。"
    return 0
  else
    result_status=$?
  fi

  if [[ -f "${source_file}" && ! -L "${source_file}" ]]; then
    log_warn "全局命令安装失败（退出码 ${result_status}），请稍后重试或人工安装。"
  else
    log_warn "全局命令安装失败（退出码 ${result_status}），后续可重新运行一键安装命令。"
  fi
  return "${result_status}"
}

exit_script() {
  echo ""
  log_info "已退出脚本。后续可运行 sbv 再次进入管理菜单。"
  exit 0
}

# Check for sing-box version
check_sb_version() {
  local current_sb_ver

  if [[ -f "${SINGBOX_BIN_PATH}" ]]; then
    current_sb_ver=$("${SINGBOX_BIN_PATH}" version 2>/dev/null | head -n1 | awk '{print $3}' || true)
    if [[ -z "${current_sb_ver}" ]]; then
      SB_VER_STATUS="${YELLOW}(版本检测失败)${NC}"
    elif [[ "${current_sb_ver}" != "${SB_SUPPORT_MAX_VERSION}" ]]; then
      SB_VER_STATUS="${YELLOW}(当前版本: ${current_sb_ver}, 建议更新到: ${SB_SUPPORT_MAX_VERSION})${NC}"
    else
      SB_VER_STATUS="${GREEN}(已是适配的最佳版本: ${current_sb_ver})${NC}"
    fi
  else
    SB_VER_STATUS="${RED}(未安装)${NC}"
  fi
}
