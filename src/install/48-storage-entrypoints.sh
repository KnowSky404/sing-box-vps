# Layout checks do not initialize storage or silently migrate a read operation.
storage_require_current() {
  if storage_needs_recovery; then
    agent_cli_error storage storage_recovery_required '目录迁移尚未完成；先执行 sbv storage recover --json --yes。'
    return 1
  fi
  if storage_needs_migration; then
    agent_cli_error storage storage_migration_required '检测到旧存储布局；先执行 sbv storage status --json 和 sbv storage migrate --json --yes。'
    return 1
  fi
}

storage_menu_gate() {
  local action='' answer=''
  if storage_needs_recovery; then
    action=recover
    printf '[WARN] 目录迁移未完成；需要恢复原布局和服务状态。\n' >&2
  elif storage_needs_migration; then
    action=migrate
    printf '[INFO] 检测到旧目录，将迁移至 %s；活动服务可能重启，旧数据会保留为迁移备份。\n' "${SB_DATA_ROOT}" >&2
  else
    return 0
  fi
  printf '[INFO] 可先运行 sbv storage status --json 查看布局和阻塞信息。\n' >&2
  if ! read -r -p '现在执行目录迁移/恢复？[y/N]: ' answer || [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    printf '[INFO] 未执行其他操作。\n' >&2
    return 1
  fi
  storage_cli "${action}" --json --yes || return $?
  # Recovery deliberately returns to the old layout. Let the operator inspect
  # its result before attempting migration again.
  if [[ "${action}" == recover ]]; then return 1; fi
  storage_require_current || return $?
}
