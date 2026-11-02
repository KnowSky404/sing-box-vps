
managed_state_snapshot_is_valid() {
  local snapshot_dir=$1

  [[ "${snapshot_dir}" == /tmp/sing-box-vps-state.* ||
     "${snapshot_dir}" == "${SB_PROJECT_DIR}.instance-write.lock/snapshot" ||
     "${snapshot_dir}" == "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" ]] || return 1
  [[ ! -L "${snapshot_dir}" ]] || return 1
  [[ -d "${snapshot_dir}" && -f "${snapshot_dir}/snapshot.meta" ]] || return 1
  grep -Fqx 'SNAPSHOT_VERSION=1' "${snapshot_dir}/snapshot.meta" || return 1
  grep -Fqx "PROJECT_DIR=${SB_PROJECT_DIR}" "${snapshot_dir}/snapshot.meta" || return 1
}

persist_file_backup() {
  local source_file=$1
  local backup_file=$2
  local backup_dir backup_name backup_candidate

  [[ -f "${source_file}" ]] || return 1
  backup_dir=$(dirname "${backup_file}")
  backup_name=$(basename "${backup_file}")
  mkdir -p "${backup_dir}" || return 1
  backup_candidate=$(mktemp "${backup_dir}/.${backup_name}.candidate.XXXXXX") || return 1
  if ! cp -p "${source_file}" "${backup_candidate}" ||
     ! chmod 600 "${backup_candidate}" ||
     ! mv -f "${backup_candidate}" "${backup_file}"; then
    rm -f "${backup_candidate}"
    return 1
  fi
}

create_managed_state_snapshot() {
  local snapshot_dir

  if [[ $# -gt 0 ]]; then
    [[ ("$1" == "${SB_PROJECT_DIR}.instance-write.lock/snapshot" &&
        -d "${SB_PROJECT_DIR}.instance-write.lock" && ! -L "${SB_PROJECT_DIR}.instance-write.lock") ||
       ("$1" == "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" &&
        -d "${SB_COMPONENT_TRANSACTION_DIR}" && ! -L "${SB_COMPONENT_TRANSACTION_DIR}") ]] || return 1
    snapshot_dir=$1
    mkdir -m 700 "${snapshot_dir}" || return 1
  else
    if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
      printf '[ERROR] 存在未完成的实例事务；先执行 instance recover，未开始其他写操作。\n' >&2
      return 1
    fi
    snapshot_dir=$(mktemp -d /tmp/sing-box-vps-state.XXXXXX) || return 1
  fi
  chmod 700 "${snapshot_dir}" || {
    rm -rf "${snapshot_dir}"
    return 1
  }
  if ! mkdir -p "${snapshot_dir}/project"; then
    rm -rf "${snapshot_dir}"
    return 1
  fi
  if [[ -d "${SB_PROJECT_DIR}" ]]; then
    if ! cp -a "${SB_PROJECT_DIR}/." "${snapshot_dir}/project/"; then
      rm -rf "${snapshot_dir}"
      return 1
    fi
    : > "${snapshot_dir}/project.existed"
  fi
  if ! {
    printf 'SNAPSHOT_VERSION=1\n'
    printf 'PROJECT_DIR=%s\n' "${SB_PROJECT_DIR}"
  } > "${snapshot_dir}/snapshot.meta"; then
    rm -rf "${snapshot_dir}"
    return 1
  fi
  chmod 600 "${snapshot_dir}/snapshot.meta" || {
    rm -rf "${snapshot_dir}"
    return 1
  }

  printf '%s' "${snapshot_dir}"
}

discard_managed_state_snapshot() {
  local snapshot_dir=$1

  managed_state_snapshot_is_valid "${snapshot_dir}" || return 1
  rm -rf "${snapshot_dir}"
}

restore_managed_state_snapshot() {
  local snapshot_dir=$1
  local project_parent project_base restore_candidate restore_previous
  local current_existed="n"

  managed_state_snapshot_is_valid "${snapshot_dir}" || return 1
  [[ -n "${SB_PROJECT_DIR}" && "${SB_PROJECT_DIR}" != "/" ]] || return 1
  project_parent=$(dirname "${SB_PROJECT_DIR}")
  project_base=$(basename "${SB_PROJECT_DIR}")
  mkdir -p "${project_parent}" || return 1

  restore_candidate=$(mktemp -d "${project_parent}/.${project_base}.restore.XXXXXX") || return 1
  if [[ -f "${snapshot_dir}/project.existed" ]]; then
    if ! cp -a "${snapshot_dir}/project/." "${restore_candidate}/"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
  fi

  restore_previous=$(mktemp -d "${project_parent}/.${project_base}.previous.XXXXXX") || {
    rm -rf "${restore_candidate}"
    return 1
  }
  rmdir "${restore_previous}" || {
    rm -rf "${restore_candidate}" "${restore_previous}"
    return 1
  }

  if [[ -e "${SB_PROJECT_DIR}" || -L "${SB_PROJECT_DIR}" ]]; then
    if ! mv "${SB_PROJECT_DIR}" "${restore_previous}"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
    current_existed="y"
  fi

  if [[ -f "${snapshot_dir}/project.existed" ]]; then
    if ! mv "${restore_candidate}" "${SB_PROJECT_DIR}"; then
      if [[ "${current_existed}" == "y" ]] && ! mv "${restore_previous}" "${SB_PROJECT_DIR}"; then
        printf '[ERROR] state_restore: previous_directory_restore_failed; recovery=%s\n' "${restore_previous}" >&2
        return 1
      fi
      rm -rf "${restore_candidate}" || return 1
      return 1
    fi
  elif ! rmdir "${restore_candidate}"; then
    if [[ "${current_existed}" == "y" ]] && ! mv "${restore_previous}" "${SB_PROJECT_DIR}"; then
      printf '[ERROR] state_restore: previous_directory_restore_failed; recovery=%s\n' "${restore_previous}" >&2
    fi
    return 1
  fi

  if [[ "${current_existed}" == "y" ]] && ! rm -rf "${restore_previous}"; then
    return 1
  fi
}

rollback_managed_state_snapshot() {
  local snapshot_dir=$1

  if ! restore_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "配置状态回滚失败；事务快照保留在 ${snapshot_dir}。"
    return 1
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "配置状态已恢复，但临时事务快照未能删除: ${snapshot_dir}。"
    return 1
  fi
}

abort_managed_state_transaction() {
  local snapshot_dir=$1
  local failure_message=$2

  if rollback_managed_state_snapshot "${snapshot_dir}"; then
    log_error "${failure_message}，已恢复变更前的配置状态。"
    return 1
  fi
  log_error "${failure_message}，且自动回滚失败；事务快照保留在 ${snapshot_dir}。"
  return 1
}

# Advanced component mutations use a durable journal.  The management flock
# serializes live writers, while this directory survives an abrupt process or
# host interruption and gives the next operator a bounded recovery path.
MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=""
MANAGED_COMPONENT_RECOVERY_LAST_ERROR=""

managed_component_transaction_path_is_trusted() {
  local lock_dir=${1:-}

  [[ "${lock_dir}" == "${SB_COMPONENT_TRANSACTION_DIR}" &&
     -d "${lock_dir}" && ! -L "${lock_dir}" ]]
}

managed_component_transaction_begin() {
  local lock_dir=${1:-} operation=${2:-} expected_revision=${3:-}
  local before_active=${4:-false} owner_pid=${5:-} owner_start=${6:-}
  local transaction_next

  [[ "${lock_dir}" == "${SB_COMPONENT_TRANSACTION_DIR}" &&
     ! -e "${lock_dir}" && ! -L "${lock_dir}" ]] || return 1
  [[ "${operation}" =~ ^(create|replace|delete|rebuild|takeover)$ ]] || return 1
  [[ "${expected_revision}" =~ ^(0|[1-9][0-9]{0,15})$ ]] || return 1
  [[ "${before_active}" == true || "${before_active}" == false ]] || return 1
  [[ "${owner_pid}" =~ ^[1-9][0-9]*$ && "${owner_start}" =~ ^[0-9]+$ ]] || return 1

  umask 077
  mkdir -m 700 "${lock_dir}" || return 1
  transaction_next="${lock_dir}/transaction.next"
  if ! jq -n \
    --arg operation "${operation}" \
    --arg expected "${expected_revision}" \
    --argjson pid "${owner_pid}" \
    --arg start "${owner_start}" \
    --argjson before "${before_active}" \
    '{schema_version:1,operation:$operation,expected_revision:$expected,
      owner_pid:$pid,owner_start:$start,before_active:$before,phase:"prepare",
      new_revision:null,firewall_expected:false,redirect_policy_expected:false,
      tproxy_policy_expected:false}' > "${transaction_next}"; then
    rm -rf -- "${lock_dir}"
    return 1
  fi
  if ! chmod 600 "${transaction_next}"; then
    rm -rf -- "${lock_dir}"
    return 1
  fi
  if ! mv -f -- "${transaction_next}" "${lock_dir}/transaction.json"; then
    rm -rf -- "${lock_dir}"
    return 1
  fi
}

managed_component_transaction_checkpoint() {
  local lock_dir=${1:-} phase=${2:-} transaction_next

  managed_component_transaction_path_is_trusted "${lock_dir}" || return 1
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]] || return 1
  [[ "${phase}" =~ ^(prepare|snapshot|publish|resources|service|committed)$ ]] || return 1
  transaction_next="${lock_dir}/transaction.next"
  if ! jq --arg phase "${phase}" '.phase=$phase' \
    "${lock_dir}/transaction.json" > "${transaction_next}"; then
    rm -f -- "${transaction_next}"
    return 1
  fi
  chmod 600 "${transaction_next}" || return 1
  mv -f -- "${transaction_next}" "${lock_dir}/transaction.json"
}

managed_component_transaction_set_revision() {
  local lock_dir=${1:-} revision=${2:-} transaction_next

  managed_component_transaction_path_is_trusted "${lock_dir}" || return 1
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" &&
     "${revision}" =~ ^(0|[1-9][0-9]{0,15})$ ]] || return 1
  transaction_next="${lock_dir}/transaction.next"
  if ! jq --argjson revision "${revision}" '.new_revision=$revision' \
    "${lock_dir}/transaction.json" > "${transaction_next}"; then
    rm -f -- "${transaction_next}"
    return 1
  fi
  chmod 600 "${transaction_next}" || return 1
  mv -f -- "${transaction_next}" "${lock_dir}/transaction.json"
}

managed_component_transaction_set_firewall_expected() {
  local lock_dir=${1:-} expected=${2:-false} transaction_next

  managed_component_transaction_path_is_trusted "${lock_dir}" || return 1
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" &&
     ("${expected}" == true || "${expected}" == false) ]] || return 1
  transaction_next="${lock_dir}/transaction.next"
  if ! jq --argjson expected "${expected}" '.firewall_expected=$expected' \
    "${lock_dir}/transaction.json" > "${transaction_next}"; then
    rm -f -- "${transaction_next}"
    return 1
  fi
  chmod 600 "${transaction_next}" || return 1
  mv -f -- "${transaction_next}" "${lock_dir}/transaction.json"
}

managed_component_transaction_set_redirect_policy_expected() {
  local lock_dir=${1:-} expected=${2:-false} transaction_next

  managed_component_transaction_path_is_trusted "${lock_dir}" || return 1
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" &&
     ("${expected}" == true || "${expected}" == false) ]] || return 1
  transaction_next="${lock_dir}/transaction.next"
  if ! jq --argjson expected "${expected}" '.redirect_policy_expected=$expected' \
    "${lock_dir}/transaction.json" > "${transaction_next}"; then
    rm -f -- "${transaction_next}"
    return 1
  fi
  chmod 600 "${transaction_next}" || return 1
  mv -f -- "${transaction_next}" "${lock_dir}/transaction.json"
}

managed_component_transaction_set_tproxy_policy_expected() {
  local lock_dir=${1:-} expected=${2:-false} transaction_next

  managed_component_transaction_path_is_trusted "${lock_dir}" || return 1
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" &&
     ("${expected}" == true || "${expected}" == false) ]] || return 1
  transaction_next="${lock_dir}/transaction.next"
  if ! jq --argjson expected "${expected}" '.tproxy_policy_expected=$expected' \
    "${lock_dir}/transaction.json" > "${transaction_next}"; then
    rm -f -- "${transaction_next}"
    return 1
  fi
  chmod 600 "${transaction_next}" || return 1
  mv -f -- "${transaction_next}" "${lock_dir}/transaction.json"
}

managed_component_transaction_restore() {
  local lock_dir=${1:-} before_active firewall_expected firewall_journal redirect_expected redirect_journal
  local tproxy_expected tproxy_journal
  local status=0 service_state
  MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=""

  managed_component_transaction_path_is_trusted "${lock_dir}" || {
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=component_rollback_failed
    return 1
  }
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]] || {
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=component_rollback_failed
    return 1
  }
  before_active=$(jq -r '.before_active' "${lock_dir}/transaction.json") || {
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=component_rollback_failed
    return 1
  }
  firewall_expected=$(jq -r '.firewall_expected' "${lock_dir}/transaction.json") || {
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=component_rollback_failed
    return 1
  }
  redirect_expected=$(jq -r '.redirect_policy_expected // false' "${lock_dir}/transaction.json") || {
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=component_rollback_failed
    return 1
  }
  tproxy_expected=$(jq -r '.tproxy_policy_expected // false' "${lock_dir}/transaction.json") || {
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=component_rollback_failed
    return 1
  }
  firewall_journal="${lock_dir}/snapshot/component-firewall.json"
  if [[ -e "${firewall_journal}" || -L "${firewall_journal}" ]]; then
    if [[ ! -f "${firewall_journal}" || -L "${firewall_journal}" ]]; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=firewall_rollback_failed
      return 1
    fi
    if ! instance_firewall_rollback "${firewall_journal}"; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=firewall_rollback_failed
      status=1
    fi
  elif [[ "${firewall_expected}" == true ]]; then
    printf '[ERROR] 高级组件事务防火墙日志缺失；无法证明外部状态已恢复。\n' >&2
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=firewall_rollback_failed
    status=1
  fi

  redirect_journal="${lock_dir}/snapshot/component-redirect-policy.json"
  if [[ -e "${redirect_journal}" || -L "${redirect_journal}" ]]; then
    if [[ ! -f "${redirect_journal}" || -L "${redirect_journal}" ]] ||
       ! managed_component_redirect_policy_journal_validate "${redirect_journal}"; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=redirect_policy_rollback_failed
      status=1
    elif [[ "${redirect_expected}" == true ]]; then
      if ! managed_component_redirect_policy_remove_delta "${redirect_journal}"; then
        MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=redirect_policy_rollback_failed
        status=1
      fi
    elif [[ "$(jq -r '.status' "${redirect_journal}")" != prepared ]]; then
      printf '[ERROR] 高级组件事务 Redirect 策略日志未经授权进入变更阶段；外部状态未自动修改。\n' >&2
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=redirect_policy_rollback_failed
      status=1
    fi
  elif [[ "${redirect_expected}" == true ]]; then
    printf '[ERROR] 高级组件事务 Redirect 策略日志缺失；无法证明外部状态已恢复。\n' >&2
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=redirect_policy_rollback_failed
    status=1
  fi
  [[ "${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR}" != redirect_policy_rollback_failed ]] || return 1

  tproxy_journal="${lock_dir}/snapshot/component-tproxy-policy.json"
  if [[ -e "${tproxy_journal}" || -L "${tproxy_journal}" ]]; then
    if [[ ! -f "${tproxy_journal}" || -L "${tproxy_journal}" ]] ||
       ! managed_component_tproxy_policy_journal_validate "${tproxy_journal}"; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=tproxy_policy_rollback_failed
      status=1
    elif [[ "${tproxy_expected}" == true ]]; then
      if ! managed_component_tproxy_policy_remove_delta "${tproxy_journal}"; then
        MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=tproxy_policy_rollback_failed
        status=1
      fi
    elif [[ "$(jq -r '.status' "${tproxy_journal}")" != prepared ]]; then
      printf '[ERROR] 高级组件事务 TProxy 策略日志未经授权进入变更阶段；外部状态未自动修改。\n' >&2
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=tproxy_policy_rollback_failed
      status=1
    fi
  elif [[ "${tproxy_expected}" == true ]]; then
    printf '[ERROR] 高级组件事务 TProxy 策略日志缺失；无法证明外部状态已恢复。\n' >&2
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=tproxy_policy_rollback_failed
    status=1
  fi
  [[ "${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR}" != tproxy_policy_rollback_failed ]] || return 1

  if ! managed_state_snapshot_is_valid "${lock_dir}/snapshot" ||
     ! restore_managed_state_snapshot "${lock_dir}/snapshot"; then
    printf '[ERROR] 高级组件事务状态快照恢复失败；事务目录已保留供人工处理。\n' >&2
    MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR:-component_rollback_failed}
    return 1
  fi

  if [[ "${before_active}" == true ]]; then
    if [[ ! -f "${SINGBOX_SERVICE_FILE}" ]] ||
       ! run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box >/dev/null ||
       ! systemctl is-active --quiet sing-box; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR:-component_rollback_failed}
      status=1
    fi
  elif [[ -f "${SINGBOX_SERVICE_FILE}" ]]; then
    service_state=$(systemctl is-active sing-box 2>/dev/null || printf 'unknown')
    case "${service_state}" in
      active)
        if ! systemctl stop sing-box >/dev/null 2>&1 || ! singbox_service_confirmed_stopped; then
          MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR:-component_rollback_failed}
          status=1
        fi
        ;;
      inactive|failed) ;;
      *)
        MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR:-component_rollback_failed}
        status=1
        ;;
    esac
  fi
  if [[ "${redirect_expected}" == true && -f "${redirect_journal}" && ! -L "${redirect_journal}" ]]; then
    if ! managed_component_redirect_policy_restore_before "${redirect_journal}"; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=redirect_policy_rollback_failed
      status=1
    fi
  fi
  if [[ "${tproxy_expected}" == true && -f "${tproxy_journal}" && ! -L "${tproxy_journal}" ]]; then
    if ! managed_component_tproxy_policy_restore_before "${tproxy_journal}"; then
      MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR=tproxy_policy_rollback_failed
      status=1
    fi
  fi
  return "${status}"
}

managed_component_abort_transaction_with_resources() {
  local lock_dir=${1:-} failure_message=${2:-} restore_error
  if ! managed_component_transaction_restore "${lock_dir}"; then
    restore_error=${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR:-component_rollback_failed}
    case "${restore_error}" in
      firewall_rollback_failed)
        MANAGED_COMPONENT_LAST_ERROR=firewall_rollback_failed
        printf '[ERROR] %s，监听防火墙资源回滚不确定；事务目录保留在 %s。\n' \
          "${failure_message}" "${lock_dir}" >&2 ;;
      redirect_policy_rollback_failed)
        MANAGED_COMPONENT_LAST_ERROR=redirect_policy_rollback_failed
        printf '[ERROR] %s，Redirect 主机策略回滚不确定；事务目录保留在 %s。\n' \
          "${failure_message}" "${lock_dir}" >&2 ;;
      tproxy_policy_rollback_failed)
        MANAGED_COMPONENT_LAST_ERROR=tproxy_policy_rollback_failed
        printf '[ERROR] %s，TProxy 主机策略及路由回滚不确定；事务目录保留在 %s。\n' \
          "${failure_message}" "${lock_dir}" >&2 ;;
      *)
        MANAGED_COMPONENT_LAST_ERROR=component_rollback_failed
        printf '[ERROR] %s，事务回滚不确定；事务目录保留在 %s。\n' \
          "${failure_message}" "${lock_dir}" >&2 ;;
    esac
    return 1
  fi
  if ! rm -rf -- "${lock_dir}"; then
    MANAGED_COMPONENT_LAST_ERROR=component_cleanup_failed
    printf '[ERROR] %s，资源与配置已恢复，但事务目录清理失败：%s。\n' \
      "${failure_message}" "${lock_dir}" >&2
    return 1
  fi
  printf '[ERROR] %s，监听防火墙、Redirect/TProxy 策略、配置和服务活动状态均已恢复。\n' \
    "${failure_message}" >&2
}

managed_component_restore_service_activity() {
  local lock_dir=${1:-} before_active service_state

  managed_component_transaction_path_is_trusted "${lock_dir}" || return 1
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]] || return 1
  before_active=$(jq -r '.before_active' "${lock_dir}/transaction.json") || return 1
  if [[ "${before_active}" == true ]]; then
    [[ -f "${SINGBOX_SERVICE_FILE}" ]] || return 1
    run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box >/dev/null || return 1
    systemctl is-active --quiet sing-box
    return $?
  fi
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] || return 0
  service_state=$(systemctl is-active sing-box 2>/dev/null || printf 'unknown')
  case "${service_state}" in
    inactive|failed) return 0 ;;
    active)
      systemctl stop sing-box >/dev/null 2>&1 || return 1
      singbox_service_confirmed_stopped
      ;;
    *) return 1 ;;
  esac
}

managed_component_abort_component_transaction() {
  local lock_dir=${1:-} snapshot_dir=${2:-} failure_message=${3:-} restore_service=${4:-n}
  local redirect_expected=false redirect_journal redirect_status
  local tproxy_expected=false tproxy_journal tproxy_status

  redirect_journal="${lock_dir}/snapshot/component-redirect-policy.json"
  if [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]]; then
    redirect_expected=$(jq -r '.redirect_policy_expected // false' "${lock_dir}/transaction.json") || redirect_expected=false
  fi
  if [[ -e "${redirect_journal}" || -L "${redirect_journal}" ]]; then
    if [[ ! -f "${redirect_journal}" || -L "${redirect_journal}" ]] ||
       ! managed_component_redirect_policy_journal_validate "${redirect_journal}"; then
      printf '[ERROR] %s，Redirect 策略事务日志不可信；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
      return 1
    fi
    redirect_status=$(jq -r '.status' "${redirect_journal}") || return 1
    if [[ "${redirect_expected}" == true ]]; then
      if ! managed_component_redirect_policy_remove_delta "${redirect_journal}"; then
        printf '[ERROR] %s，Redirect 策略回滚不确定；事务目录保留在 %s。\n' \
          "${failure_message}" "${lock_dir}" >&2
        return 1
      fi
    elif [[ "${redirect_status}" != prepared ]]; then
      printf '[ERROR] %s，Redirect 策略日志未经授权进入变更阶段；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
      return 1
    fi
  elif [[ "${redirect_expected}" == true ]]; then
    printf '[ERROR] %s，Redirect 策略日志缺失；事务目录保留在 %s。\n' \
      "${failure_message}" "${lock_dir}" >&2
    return 1
  fi

  tproxy_journal="${lock_dir}/snapshot/component-tproxy-policy.json"
  if [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]]; then
    tproxy_expected=$(jq -r '.tproxy_policy_expected // false' "${lock_dir}/transaction.json") || tproxy_expected=false
  fi
  if [[ -e "${tproxy_journal}" || -L "${tproxy_journal}" ]]; then
    if [[ ! -f "${tproxy_journal}" || -L "${tproxy_journal}" ]] ||
       ! managed_component_tproxy_policy_journal_validate "${tproxy_journal}"; then
      printf '[ERROR] %s，TProxy 策略事务日志不可信；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
      return 1
    fi
    tproxy_status=$(jq -r '.status' "${tproxy_journal}") || return 1
    if [[ "${tproxy_expected}" == true ]]; then
      if ! managed_component_tproxy_policy_remove_delta "${tproxy_journal}"; then
        printf '[ERROR] %s，TProxy 策略及路由回滚不确定；事务目录保留在 %s。\n' \
          "${failure_message}" "${lock_dir}" >&2
        return 1
      fi
    elif [[ "${tproxy_status}" != prepared ]]; then
      printf '[ERROR] %s，TProxy 策略日志未经授权进入变更阶段；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
      return 1
    fi
  elif [[ "${tproxy_expected}" == true ]]; then
    printf '[ERROR] %s，TProxy 策略日志缺失；事务目录保留在 %s。\n' \
      "${failure_message}" "${lock_dir}" >&2
    return 1
  fi

  if [[ -n "${snapshot_dir}" ]] && managed_state_snapshot_is_valid "${snapshot_dir}" &&
     restore_managed_state_snapshot "${snapshot_dir}"; then
    if [[ "${restore_service}" == y ]] && ! managed_component_restore_service_activity "${lock_dir}"; then
      printf '[ERROR] %s，配置状态已恢复但服务活动状态恢复失败；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
    elif [[ "${redirect_expected}" == true ]] &&
         ! managed_component_redirect_policy_restore_before "${redirect_journal}"; then
      printf '[ERROR] %s，配置状态已恢复但 Redirect 策略回滚不确定；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
    elif [[ "${tproxy_expected}" == true ]] &&
         ! managed_component_tproxy_policy_restore_before "${tproxy_journal}"; then
      printf '[ERROR] %s，配置状态已恢复但 TProxy 策略及路由回滚不确定；事务目录保留在 %s。\n' \
        "${failure_message}" "${lock_dir}" >&2
    elif rm -rf -- "${lock_dir}"; then
      printf '[ERROR] %s，已恢复变更前的配置状态。\n' "${failure_message}" >&2
    else
      printf '[ERROR] %s，配置状态已恢复但事务目录未能删除：%s。\n' \
        "${failure_message}" "${lock_dir}" >&2
    fi
  else
    printf '[ERROR] %s，且自动回滚失败；事务目录保留在 %s。\n' \
      "${failure_message}" "${lock_dir}" >&2
  fi
  return 1
}

managed_component_recovery_result_json() {
  local operation=${1:-unknown} revision=${2:-0} phase=${3:-prepare} status=${4:-unchanged}

  jq -cn --arg operation "${operation}" --arg revision "${revision}" --arg phase "${phase}" \
    --arg status "${status}" \
    '{ok:true,action:"component-recover",operation:$operation,revision:($revision|tonumber),
      status:$status,transaction:{phase:$phase,manual_intervention_required:false}}'
}

managed_component_recover_transaction() {
  local expected_revision=${1:-} lock_dir="${SB_COMPONENT_TRANSACTION_DIR}"
  local recovery_entries transaction_expected owner_pid owner_start current_start=""
  local phase operation revision snapshot recovery_fd state current_revision
  local recovery_error
  MANAGED_COMPONENT_RECOVERY_LAST_ERROR=""
  MANAGED_COMPONENT_RECOVERY_LAST_RESULT=""

  [[ ${EUID} -eq 0 ]] || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=root_required
    agent_json_error root_required "恢复必须以 root 执行。"
    return 1
  }
  [[ "${expected_revision}" =~ ^(0|[1-9][0-9]{0,15})$ ]] || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=invalid_arguments
    agent_json_error invalid_arguments "组件恢复需要有效的 --expected-revision。"
    return 1
  }
  acquire_managed_write_lock || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_write_busy
    agent_json_error component_write_busy "另一个管理进程正在执行；未开始组件恢复。"
    return 1
  }
  if [[ ! -e "${lock_dir}" ]]; then
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_unavailable
    agent_json_error component_recovery_unavailable "未找到可验证的待恢复高级组件事务。"
    return 1
  fi
  managed_component_transaction_path_is_trusted "${lock_dir}" || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
    agent_json_error component_recovery_untrusted "高级组件事务目录不可信；未修改。"
    return 1
  }
  if [[ ! -e "${lock_dir}/transaction.json" ]]; then
    recovery_entries=$(find "${lock_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n') || {
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
      agent_json_error component_recovery_untrusted "高级组件事务目录无法安全读取；未修改。"
      return 1
    }
    if [[ -n "${recovery_entries}" && "${recovery_entries}" != transaction.next ]] ||
       [[ -e "${lock_dir}/transaction.next" &&
          ( ! -f "${lock_dir}/transaction.next" || -L "${lock_dir}/transaction.next" ) ]]; then
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
      agent_json_error component_recovery_untrusted "主日志缺失且发现已准备材料；无法证明未发生变更。"
      return 1
    fi
    if ! rm -rf -- "${lock_dir}"; then
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_cleanup_failed
      agent_json_error component_cleanup_failed "组件事务未发生发布，但事务目录清理失败。"
      return 1
    fi
    MANAGED_COMPONENT_RECOVERY_LAST_RESULT=$(managed_component_recovery_result_json unknown "${expected_revision}" prepare unchanged) || return 1
    printf '%s\n' "${MANAGED_COMPONENT_RECOVERY_LAST_RESULT}"
    return 0
  fi
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]] || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
    agent_json_error component_recovery_untrusted "高级组件事务主日志不是可信普通文件；未修改。"
    return 1
  }
  if ! jq -e '
    .schema_version == 1 and
    (.operation | IN("create","replace","delete","rebuild","takeover")) and
    (.owner_pid | type == "number" and . == floor and . > 0) and
    (.owner_start | type == "string" and test("^[0-9]+$")) and
    (.before_active | type == "boolean") and
    (.phase | IN("prepare","snapshot","publish","resources","service","committed")) and
    (.new_revision == null or (.new_revision | type == "number" and . == floor and . >= 0 and . <= 9007199254740991)) and
    (.firewall_expected | type == "boolean") and
    ((has("redirect_policy_expected") | not) or (.redirect_policy_expected | type == "boolean")) and
    ((has("tproxy_policy_expected") | not) or (.tproxy_policy_expected | type == "boolean"))
  ' "${lock_dir}/transaction.json" >/dev/null 2>&1; then
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
    agent_json_error component_recovery_untrusted "高级组件事务日志无法验证；请保留目录人工检查。"
    return 1
  fi
  transaction_expected=$(jq -r '.expected_revision' "${lock_dir}/transaction.json") || return 1
  if [[ "${transaction_expected}" != "${expected_revision}" ]]; then
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_revision_mismatch
    agent_json_error component_revision_mismatch "组件事务原 revision 与请求不匹配；未恢复。"
    return 1
  fi
  operation=$(jq -r '.operation' "${lock_dir}/transaction.json") || return 1
  owner_pid=$(jq -r '.owner_pid' "${lock_dir}/transaction.json") || return 1
  owner_start=$(jq -r '.owner_start' "${lock_dir}/transaction.json") || return 1
  if [[ -r "/proc/${owner_pid}/stat" ]]; then
    current_start=$(awk '{print $22}' "/proc/${owner_pid}/stat") || {
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
      agent_json_error component_recovery_untrusted "无法验证原组件写进程；未恢复。"
      return 1
    }
    if [[ "${current_start}" == "${owner_start}" ]]; then
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_transaction_active
      agent_json_error component_transaction_active "原组件写进程仍在运行；禁止并发恢复。"
      return 1
    fi
  fi
  command -v flock >/dev/null 2>&1 && [[ ! -L "${lock_dir}/recovery.flock" ]] || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_unavailable
    agent_json_error component_recovery_unavailable "组件恢复需要可用且可信的 flock。"
    return 1
  }
  exec {recovery_fd}>"${lock_dir}/recovery.flock" || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_unavailable
    agent_json_error component_recovery_unavailable "无法打开组件恢复锁；未修改。"
    return 1
  }
  flock -n "${recovery_fd}" || {
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_active
    agent_json_error component_recovery_active "另一个恢复进程已取得组件恢复锁。"
    return 1
  }
  phase=$(jq -r '.phase' "${lock_dir}/transaction.json") || return 1
  revision=$(jq -r '.new_revision // .expected_revision' "${lock_dir}/transaction.json") || return 1
  snapshot="${lock_dir}/snapshot"
  if [[ "${phase}" == committed ]]; then
    state=$(managed_component_state_json) || {
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
      agent_json_error component_recovery_untrusted "已提交组件事务的当前 state 无法安全读取；事务目录保留。"
      return 1
    }
    current_revision=$(jq -r '.revision | tostring' <<< "${state}") || return 1
    if [[ "${current_revision}" != "${revision}" ]]; then
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
      agent_json_error component_recovery_untrusted "已提交组件事务 revision 与当前 state 不一致；事务目录保留。"
      return 1
    fi
    if ! rm -rf -- "${lock_dir}"; then
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_cleanup_failed
      agent_json_error component_cleanup_failed "组件事务已提交，但事务目录清理失败。"
      return 1
    fi
    MANAGED_COMPONENT_RECOVERY_LAST_RESULT=$(managed_component_recovery_result_json "${operation}" "${revision}" "${phase}" committed) || return 1
    printf '%s\n' "${MANAGED_COMPONENT_RECOVERY_LAST_RESULT}"
    return 0
  fi
  if [[ "${phase}" == prepare && ! -e "${snapshot}" ]]; then
    if ! rm -rf -- "${lock_dir}"; then
      MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_cleanup_failed
      agent_json_error component_cleanup_failed "组件事务尚未发布，但事务目录清理失败。"
      return 1
    fi
    MANAGED_COMPONENT_RECOVERY_LAST_RESULT=$(managed_component_recovery_result_json "${operation}" "${expected_revision}" "${phase}" unchanged) || return 1
    printf '%s\n' "${MANAGED_COMPONENT_RECOVERY_LAST_RESULT}"
    return 0
  fi
  if ! managed_state_snapshot_is_valid "${snapshot}"; then
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_recovery_untrusted
    agent_json_error component_recovery_untrusted "组件事务快照缺失或不可信；未自动恢复。"
    return 1
  fi
  if ! managed_component_transaction_restore "${lock_dir}"; then
    recovery_error=${MANAGED_COMPONENT_TRANSACTION_RESTORE_ERROR:-component_rollback_failed}
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=${recovery_error}
    case "${recovery_error}" in
      firewall_rollback_failed)
        agent_json_error firewall_rollback_failed "组件事务状态已尝试恢复，但防火墙外部资源仍不确定；事务目录已保留。" ;;
      redirect_policy_rollback_failed)
        agent_json_error redirect_policy_rollback_failed "组件事务状态已尝试恢复，但 Redirect 主机策略仍不确定；事务目录已保留。" ;;
      tproxy_policy_rollback_failed)
        agent_json_error tproxy_policy_rollback_failed "组件事务状态已尝试恢复，但 TProxy 主机策略及路由仍不确定；事务目录已保留。" ;;
      *)
        agent_json_error component_rollback_failed "组件事务自动回滚失败；事务目录已保留供人工恢复。" ;;
    esac
    return 1
  fi
  if ! rm -rf -- "${lock_dir}"; then
    MANAGED_COMPONENT_RECOVERY_LAST_ERROR=component_cleanup_failed
    agent_json_error component_cleanup_failed "组件事务已回滚，但事务目录清理失败。"
    return 1
  fi
  MANAGED_COMPONENT_RECOVERY_LAST_RESULT=$(managed_component_recovery_result_json "${operation}" "${expected_revision}" "${phase}" rolled_back) || return 1
  printf '%s\n' "${MANAGED_COMPONENT_RECOVERY_LAST_RESULT}"
}

# Validate only managed candidates, not arbitrary existing configurations on
# read/upgrade. Explicit component identities are required; DNS, certificates,
# HTTP clients and rule sets have separate upstream tag namespaces. This is a
# reference preflight, never a substitute for the target core's `check`.
validate_managed_component_graph() {
  local config_file=${1:-} graph_status
  if [[ $# -ne 1 || ! -f "${config_file}" || ! -r "${config_file}" ]]; then
    printf '[ERROR] component_graph: invalid input\n' >&2
    return 1
  fi
  # Read the candidate once. Errors are fixed classifications: neither jq
  # diagnostics nor user-controlled tags, paths or credentials reach stderr.
  if ! graph_status=$(jq -sr '
    def bad: error("invalid field type");
    def object: if type == "object" then . else bad end;
    def array: if type == "array" then . else bad end;
    def text: if type == "string" then . else bad end;
    def name: text | if length > 0 then . else bad end;
    def list: if type == "array" then map(name) else [name] end;
    def field($key; $default): if has($key) then .[$key] else $default end;
    def records($items; $space; $role; $typed; $explicit):
      $items | array | to_entries[] | .key as $index | .value | object |
      (if $typed then .type | name else (.type // "") end) as $type |
      (if $explicit then .tag | name
       else (field("tag"; "") | text) as $tag |
         if $tag == "" then ($index | tostring) else $tag end end) as $tag |
      {id: ($space + ":" + $tag), space: $space, role: $role, tag: $tag,
       kind: $type, value: .};
    def ref($owner; $space; $value; $dependency):
      $value | text | select(length > 0) |
      {from: $owner, space: $space, tag: ., dependency: $dependency};
    def optional_ref($owner; $space; $key; $dependency):
      if has($key) then ref($owner; $space; .[$key]; $dependency) else empty end;
    def list_refs($owner; $space; $key):
      if has($key) then .[$key] | list[] | ref($owner; $space; .; false)
      else empty end;
    def resolver_tag:
      if type == "string" then text
      elif type == "object" then .server | name else bad end;
    def domain_host:
      type == "string" and length > 0 and
      (test("^[0-9.]+$") | not) and (contains(":") | not);
    def dial_refs($owner; $dependency; $default_resolver):
      object |
      optional_ref($owner; "outbound"; "detour"; true),
      optional_ref($owner; "netns"; "netns"; true),
      (if has("domain_resolver") then
         ref($owner; "dns"; (.domain_resolver | resolver_tag); $dependency)
       elif $dependency and (.detour // "") == "" then
         ref($owner; "dns"; $default_resolver; true)
       else empty end);
    def http_refs($owner; $default_resolver):
      if type == "string" then ref($owner; "http"; .; true)
      elif type == "object" then dial_refs($owner; true; $default_resolver)
      else bad end;
    def provider_refs($owner; $default_resolver):
      object | (.type | name) as $type |
      if $type == "acme" or $type == "cloudflare-origin-ca" then
        if has("http_client") then .http_client | http_refs($owner; $default_resolver)
        else empty end
      elif $type == "tailscale" then
        optional_ref($owner; "tailscale"; "endpoint"; true)
      else empty end;
    def tls_refs($owner; $default_resolver):
      object |
      (if has("certificate_provider") then
         .certificate_provider |
         if type == "string" then name | ref($owner; "cert"; .; true)
         else provider_refs($owner; $default_resolver) end
       else empty end),
      (if has("acme") then .acme | object |
         if has("http_client") then .http_client | http_refs($owner; $default_resolver)
         else empty end
       else empty end),
      (if has("reality") then .reality | object |
         if has("handshake") then .handshake |
           dial_refs($owner; (.server | domain_host); $default_resolver)
         else empty end
       else empty end);
    def rule_refs($owner; $dns):
      array[] | object | . as $rule |
      list_refs($owner; "inbound"; "inbound"),
      list_refs($owner; "ruleset"; "rule_set"),
      (if $dns then
         (list_refs($owner; "outbound"; "outbound") | select(.tag != "any")),
         optional_ref($owner; "dns"; "server"; false)
       else
         optional_ref($owner; "outbound"; "outbound"; false),
         (if .action == "resolve" then optional_ref($owner; "dns"; "server"; false)
          else empty end)
       end),
      (if $rule | has("rules") then $rule.rules | rule_refs($owner; $dns)
       else empty end);
    # Build adjacency once. Kahn elimination does not revisit all paths in a
    # shared selector DAG and cannot recurse forever on a cycle.
    def acyclic($edges):
      (reduce $edges[] as $edge ({degree: {}, next: {}};
        .degree[$edge.from] = (.degree[$edge.from] // 0) |
        .degree[$edge.to] = ((.degree[$edge.to] // 0) + 1) |
        .next[$edge.from] += [$edge.to])) as $graph |
      ($graph + {queue: [$graph.degree | to_entries[] | select(.value == 0) | .key],
                 cursor: 0}) |
      until(.cursor == (.queue | length);
        .queue[.cursor] as $node | .cursor += 1 |
        reduce (.next[$node] // [])[] as $target (.;
          .degree[$target] -= 1 |
          if .degree[$target] == 0 then .queue += [$target] else . end)) |
      .cursor == (.degree | length);
    try (
      if length == 1 and (.[0] | type == "object") then .[0]
      else error("invalid config shape") end |
      . as $root |
      (field("route"; {}) | object) as $route |
      (field("dns"; {}) | object) as $dns |
      ($route | if has("default_domain_resolver") then
         .default_domain_resolver | resolver_tag else "" end) as $default_resolver |
      [records(field("inbounds"; []); "component"; "inbound"; true; true),
       records(field("outbounds"; []); "component"; "outbound"; true; true),
       records(field("endpoints"; []); "component"; "endpoint"; true; true),
       records(field("certificate_providers"; []); "cert"; "cert"; true; false),
       records(field("http_clients"; []); "http"; "http"; false; true),
       records(field("services"; []); "service"; "service"; true; false),
       records(field("network_namespaces"; []); "netns"; "netns"; false; true),
       records(($dns | field("servers"; [])); "dns"; "dns"; false; false),
       ($route | field("rule_set"; []) | array[] | object | . as $set |
         (.tag | list | if length > 0 then .[] else bad end) |
         {id: ("ruleset:" + .), space: "ruleset", role: "ruleset", tag: .,
          kind: ($set.type // "inline"), value: $set})] as $nodes |
      if ($nodes | group_by(.id) | any(.[]; length > 1)) then
        error("duplicate tag") else . end |
      # Aliases resolve to the same component node, not different graph nodes.
      (reduce $nodes[] as $node ({};
        .[$node.space][$node.tag] = $node.id |
        if $node.role == "inbound" or $node.role == "endpoint" then
          .inbound[$node.tag] = $node.id else . end |
        if $node.role == "outbound" or $node.role == "endpoint" then
          .outbound[$node.tag] = $node.id else . end |
        if $node.role == "endpoint" and $node.kind == "tailscale" then
          .tailscale[$node.tag] = $node.id else . end)) as $spaces |
      [($nodes[] | . as $node | .value |
        if $node.role == "inbound" or
           ($node.role == "endpoint" and $node.kind == "openvpn-server") then
          optional_ref($node.id; "inbound"; "detour"; true),
          optional_ref($node.id; "netns"; "netns"; true)
        elif $node.role == "outbound" or $node.role == "endpoint" or
             $node.role == "http" or $node.role == "dns" then
          dial_refs($node.id; (($node.role == "http") or (.server | domain_host)); $default_resolver)
        else empty end),
       ($nodes[] | select(.role == "outbound" and
          (.kind == "selector" or .kind == "urltest")) | . as $node | .value |
          (.outbounds | array | if length > 0 then map(name) else bad end) as $members |
          (if has("default") then (.default | text) as $default |
            if $default != "" and ($members | index($default)) == null then bad
            else empty end else empty end),
          ($members[] | ref($node.id; "outbound"; .; true))),
       ($nodes[] | select(.role == "inbound" or .role == "service" or
          (.role == "endpoint" and .kind == "openvpn-server")) |
          . as $node | .value |
          if has("tls") then .tls | tls_refs($node.id; $default_resolver) else empty end),
       ($nodes[] | select(.role == "inbound" and .kind == "cloudflared") |
          . as $node | .value |
          (if has("control_dialer") then .control_dialer | dial_refs($node.id; true; $default_resolver) else empty end),
          (if has("tunnel_dialer") then .tunnel_dialer | dial_refs($node.id; true; $default_resolver) else empty end)),
       ($nodes[] | select(.role == "inbound" and .kind == "tun") |
          . as $node | .value |
          list_refs($node.id; "ruleset"; "route_address_set"),
          list_refs($node.id; "ruleset"; "route_exclude_address_set")),
       ($nodes[] | select(.role == "cert") | . as $node | .value |
          provider_refs($node.id; $default_resolver)),
       ($nodes[] | select((.role == "inbound" or .role == "outbound") and
          .kind == "hysteria2") | . as $node | .value |
          if has("realm") then .realm | object |
            (if has("http_client") then .http_client | http_refs($node.id; $default_resolver)
             else empty end),
            (if $node.role == "inbound" and has("stun_domain_resolver") then
               ref($node.id; "dns"; (.stun_domain_resolver | resolver_tag); true)
             else empty end)
          else empty end),
       ($nodes[] | select(.role == "dns") | . as $node | .value |
          # DNS transport managers register explicit resolver dependencies
          # even for IP servers; unlike ordinary outbound dialers these must
          # be checked for startup cycles independently of the target address.
          (if has("domain_resolver") then
             ref($node.id; "dns"; (.domain_resolver | resolver_tag); true)
           else empty end),
          optional_ref($node.id; "dns"; "address_resolver"; true),
          (if $node.kind == "tailscale" then
             optional_ref($node.id; "tailscale"; "endpoint"; true) else empty end)),
       ($nodes[] | select(.role == "ruleset") | . as $node | .value |
          optional_ref($node.id; "outbound"; "download_detour"; true),
          (if has("http_client") then .http_client | http_refs($node.id; $default_resolver)
           else empty end)),
       ($nodes[] | select(.role == "service") | . as $node | .value |
          optional_ref($node.id; (if $node.kind == "ocm" or $node.kind == "ccm"
            then "outbound" else "inbound" end); "detour"; true),
          optional_ref($node.id; "netns"; "netns"; true),
          (if $node.kind == "api" and has("dashboard") then .dashboard | object |
            if has("http_client") then .http_client | http_refs($node.id; $default_resolver)
            else empty end else empty end),
          (if $node.kind == "derp" then
            (list_refs($node.id; "tailscale"; "verify_client_endpoint") | .dependency = true),
            (field("verify_client_url"; []) |
              if type == "array" then .[] else . end |
              if type == "string" then empty else http_refs($node.id; $default_resolver) end),
            (field("mesh_with"; []) | array[] | dial_refs($node.id; (.server | domain_host); $default_resolver))
           else empty end)),
       ($route | optional_ref("root:route"; "outbound"; "final"; false),
          optional_ref("root:route"; "http"; "default_http_client"; false),
          ref("root:route"; "dns"; $default_resolver; false),
          (field("rules"; []) | rule_refs("root:route"; false)),
          ((.geoip // {}), (.geosite // {}) | object |
            optional_ref("root:route"; "outbound"; "download_detour"; false))),
       ($dns | optional_ref("root:dns"; "dns"; "final"; false),
          (field("rules"; []) | rule_refs("root:dns"; true))),
       ($root | field("experimental"; {}) | object | field("clash_api"; {}) | object |
          optional_ref("root:experimental"; "outbound"; "external_ui_download_detour"; false))
      ] as $refs |
      if any($refs[]; $spaces[.space][.tag] == null) then
        error("unknown reference") else . end |
      [$refs[] | select(.dependency) |
        {from: .from, to: $spaces[.space][.tag]}] | unique as $edges |
      if acyclic($edges) then "ok" else error("dependency cycle") end
    ) catch (
      if . == "invalid config shape" or . == "invalid field type" or
         . == "duplicate tag" or . == "unknown reference" or . == "dependency cycle"
      then . else "invalid field type" end
    )
  ' -- "${config_file}" 2>/dev/null); then
    graph_status="invalid config shape"
  fi
  if [[ "${graph_status}" != "ok" ]]; then
    printf '[ERROR] component_graph: %s; 配置未发布。\n' "${graph_status}" >&2
    return 1
  fi
}
