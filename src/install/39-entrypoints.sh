
install_or_reconfigure_singbox() {
  install_protocols_interactive "fresh"
}

update_singbox_binary_preserving_config() {
  local installed_ver installed_target_ver reinstall_choice before_service_state
  local backup_dir='' binary_backup='' library_backup_dir='' status=0 rollback_status=0
  local previous_int previous_term previous_hup update_signal_status=0 service_attempted=n changed=false
  local stage=prepare failure_code=update_failed mode library_path library_state marker_state

  installed_ver=$(detect_installed_singbox_version) || return 1
  [[ "${installed_ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  get_os_info || return $?
  get_arch || return $?
  install_dependencies || return $?
  if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then SB_ENABLE_WARP=y; else SB_ENABLE_WARP=n; fi
  load_warp_route_settings || return $?
  log_info "检测到现有安装，默认仅更新 sing-box 二进制并保留当前配置。"
  printf '当前版本: %s\n' "${installed_ver}"
  if [[ -z "${SB_VERSION:-}" ]]; then prompt_singbox_version || return $?; fi
  get_latest_version || return $?
  if [[ "${SB_VERSION#v}" == "${installed_ver}" ]]; then
    read -rp "目标版本与当前版本一致 (${installed_ver})，是否仍重新安装二进制? [y/N]: " reinstall_choice || return 1
    [[ "${reinstall_choice}" =~ ^[Yy]$ ]] || return 0
  fi
  before_service_state=$(systemctl is-active sing-box 2>/dev/null || true)
  backup_dir=$(storage_mktemp -d "$(dirname "${SINGBOX_BIN_PATH}")/.sing-box-update.XXXXXXXX") || return 1
  binary_backup="${backup_dir}/sing-box"
  library_backup_dir="${backup_dir}/library"
  if ! cp -p -- "${SINGBOX_BIN_PATH}" "${binary_backup}" ||
     ! cp -p -- "${SINGBOX_CONFIG_FILE}" "${backup_dir}/config.json" ||
     ! singbox_library_snapshot "${library_backup_dir}"; then
    if ! rm -rf -- "${backup_dir}"; then log_warn "更新准备失败；临时备份保留在 ${backup_dir}。"; fi
    return 1
  fi
  previous_int=$(trap -p INT)
  previous_term=$(trap -p TERM)
  previous_hup=$(trap -p HUP)
  trap 'update_signal_status=130' INT
  trap 'update_signal_status=143' TERM
  trap 'update_signal_status=129' HUP

  singbox_update_apply() {
    stage=install
    failure_code=binary_install_failed
    install_binary || return $?
    [[ "${update_signal_status}" == 0 ]] || return "${update_signal_status}"
    stage=validate
    failure_code=target_version_not_installed
    installed_target_ver=$(detect_installed_singbox_version) || return 1
    if [[ "${installed_target_ver#v}" != "${SB_VERSION#v}" ]]; then
      log_warn "安装后的 sing-box 版本 (${installed_target_ver:-未知}) 与目标版本 ${SB_VERSION#v} 不一致，服务未重启。"
      return 1
    fi
    failure_code=config_changed
    cmp -s -- "${backup_dir}/config.json" "${SINGBOX_CONFIG_FILE}" || return 1
    failure_code=config_check_failed
    log_info "正在使用 sing-box ${SB_VERSION} 校验现有配置..."
    if ! validate_config_file; then
      log_warn "现有配置未通过 sing-box ${SB_VERSION} 校验。配置已保留，服务未重启。"
      return 1
    fi
    [[ "${update_signal_status}" == 0 ]] || return "${update_signal_status}"
    stage=service
    failure_code=service_not_active
    service_attempted=y
    if ! run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box ||
       [[ "$(systemctl is-active sing-box 2>/dev/null || true)" != active ]]; then
      log_warn "sing-box 服务重启失败或未保持 active。"
      return 1
    fi
    [[ "${update_signal_status}" == 0 ]] || return "${update_signal_status}"
    failure_code=config_changed
    cmp -s -- "${backup_dir}/config.json" "${SINGBOX_CONFIG_FILE}" || return 1
  }
  if singbox_update_apply; then status=0; else status=$?; fi
  if [[ "${update_signal_status}" != 0 ]]; then status=${update_signal_status}; failure_code=signal_interrupted; fi
  if ! singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${binary_backup}"; then changed=true; fi
  if [[ "${status}" != 0 ]]; then
    if ! restore_singbox_update_artifacts "${binary_backup}" "${library_backup_dir}"; then rollback_status=1; fi
    if ! cmp -s -- "${backup_dir}/config.json" "${SINGBOX_CONFIG_FILE}"; then
      mode=$(stat -c '%a' "${backup_dir}/config.json") || rollback_status=1
      if ! singbox_atomic_file_copy "${backup_dir}/config.json" "${SINGBOX_CONFIG_FILE}" "${mode:-0600}" ||
         ! singbox_file_matches_backup "${SINGBOX_CONFIG_FILE}" "${backup_dir}/config.json"; then rollback_status=1; fi
    fi
    if [[ "${service_attempted}" == y && "${rollback_status}" == 0 ]]; then
      if [[ "${before_service_state}" == active ]]; then
        if ! run_with_progress "恢复更新前 sing-box 服务" systemctl restart sing-box >/dev/null ||
           [[ "$(systemctl is-active sing-box 2>/dev/null || true)" != active ]]; then rollback_status=1; fi
      elif ! systemctl stop sing-box >/dev/null 2>&1 ||
           [[ "$(systemctl is-active sing-box 2>/dev/null || true)" == active ]]; then rollback_status=1; fi
    fi
  fi
  trap - INT TERM HUP
  [[ -z "${previous_int}" ]] || eval "${previous_int}"
  [[ -z "${previous_term}" ]] || eval "${previous_term}"
  [[ -z "${previous_hup}" ]] || eval "${previous_hup}"
  unset -f singbox_update_apply
  if [[ "${status}" != 0 ]]; then
    printf '[ERROR] operation=sing_box_update stage=%s code=%s command_exit_code=%s changed=%s rolled_back=%s rollback_ok=%s manual_intervention_required=%s\n' \
      "${stage}" "${failure_code}" "${status}" "${changed}" \
      "$([[ "${rollback_status}" == 0 ]] && printf true || printf false)" \
      "$([[ "${rollback_status}" == 0 ]] && printf true || printf false)" \
      "$([[ "${rollback_status}" == 0 ]] && printf false || printf true)" >&2
    if [[ "${rollback_status}" != 0 ]]; then
      log_warn "自动恢复旧 sing-box 二进制、运行库或服务状态失败；备份保留在 ${backup_dir}。"
      return "${status}"
    fi
    if ! rm -rf -- "${backup_dir}"; then log_warn "更新已回滚；临时备份未能清理: ${backup_dir}。"; fi
    return "${status}"
  fi
  if ! rm -rf -- "${backup_dir}"; then log_warn "更新已提交；临时备份未能清理: ${backup_dir}。"; return 1; fi
  log_success "sing-box 已更新到 ${SB_VERSION}，当前配置已保留。"
  display_status_summary || return $?
  log_info "连接信息未自动展示，如需查看请进入菜单 11。"
}

cli_update_singbox() {
  local version_arg=${1:-}
  local normalized_version
  local existing_instance_state

  if ! normalized_version=$(normalize_singbox_version_input "${version_arg}"); then
    log_warn "无效版本号: ${version_arg}。请输入 latest、${SB_SUPPORT_MAX_VERSION} 或完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。" >&2
    return 1
  fi

  existing_instance_state=$(detect_existing_instance_state)
  case "${existing_instance_state}" in
    healthy)
      ;;
    incomplete)
      log_warn "检测到残缺的 sing-box 实例；请先运行 sbv 交互菜单完成接管或修复后再更新。" >&2
      return 1
      ;;
    *)
      log_warn "未检测到已安装的 sing-box 实例；请先运行 sbv 完成安装。" >&2
      return 1
      ;;
  esac

  SB_VERSION="${normalized_version}"
  update_singbox_binary_preserving_config
}

prompt_incomplete_instance_action() {
  local existing_instance_state
  local install_choice

  echo
  render_left_aligned_page_header "sing-box 管理" "发现现有实例缺少关键组件"
  render_section_title "实例检测"
  echo "检测到残缺的现有实例。"
  render_section_title "操作选项"
  render_menu_item "1" "接管现有实例"
  render_menu_item "2" "按全新安装处理"
  echo "0. 返回"
  install_choice=$(prompt_choice "请选择 [0-2]: " 0 2 "")

  case "${install_choice}" in
    1) take_over_existing_instance ;;
    2) install_or_reconfigure_singbox ;;
    0) return 0 ;;
    *) log_warn "无效选项，请重新选择。" ;;
  esac
}

install_new_protocols_menu() {
  local existing_instance_state installed_list preselected_protocols=""

  # Display choices without reconstructing every installed protocol. This
  # preview is never an authorization to write: the complete health check
  # (including recovery/takeover dispatch) still runs after a selection.
  if [[ -x "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" &&
        -f "${SINGBOX_CONFIG_FILE}" ]] &&
     { [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] || instance_management_empty_config_baseline; } &&
     validate_protocol_index_for_rebuild; then
    installed_list=""
    if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
      installed_list=$(list_indexed_protocols_raw) || return 1
    fi
    prompt_protocol_install_selection additional "${installed_list}" || return 0
    preselected_protocols=${SELECTED_PROTOCOLS_CSV}
  fi

  if [[ -x "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" ]] &&
     instance_management_empty_config_baseline; then
    run_with_progress "校验未配置协议的 sing-box 安装" validate_config_file || return $?
    install_protocols_interactive additional "${preselected_protocols}"
    return $?
  fi

  existing_instance_state=$(run_with_progress "检查 sing-box 安装状态" detect_existing_instance_state) || return $?

  case "${existing_instance_state}" in
    healthy)
      install_protocols_interactive additional "${preselected_protocols}"
      ;;
    incomplete)
      prompt_incomplete_instance_action
      ;;
    *)
      install_or_reconfigure_singbox
      ;;
  esac
}

update_singbox_version_menu() {
  local existing_instance_state

  existing_instance_state=$(detect_existing_instance_state)

  case "${existing_instance_state}" in
    healthy)
      update_singbox_binary_preserving_config
      ;;
    incomplete)
      prompt_incomplete_instance_action
      ;;
    *)
      log_warn "未检测到已安装的 sing-box 实例，将进入安装流程。"
      install_or_reconfigure_singbox
      ;;
  esac
}

install_or_update_singbox() {
  local existing_instance_state
  local install_choice
  local installed_ver

  existing_instance_state=$(detect_existing_instance_state)

  if [[ "${existing_instance_state}" == "healthy" ]]; then
    installed_ver=$("${SINGBOX_BIN_PATH}" version | head -n1 | awk '{print $3}')
    load_current_config_state

    echo
    render_left_aligned_page_header "部署管理" "维护 sing-box 核心与已安装协议"
    render_section_title "安装摘要"
    render_summary_item "当前版本" "${installed_ver}"
    render_summary_item "当前协议" "$(protocol_display_name "${SB_PROTOCOL}")"
    render_summary_item "当前端口" "${SB_PORT}"
    render_section_title "操作选项"
    render_menu_item "1" "更新 sing-box 二进制并保留当前配置"
    render_menu_item "2" "安装新增协议"
    render_menu_item "3" "修改已安装协议配置"
    render_menu_item "4" "移除已安装协议"
    render_menu_item "5" "卸载 sing-box"
    echo "0. 返回"
    install_choice=$(prompt_choice "请选择 [0-5] (默认 1): " 0 5 1)

    case "${install_choice}" in
      2) install_new_protocols_menu ;;
      3) update_config_only ;;
      4) remove_protocol_menu ;;
      5) uninstall_singbox ;;
      0) return 0 ;;
      *) update_singbox_version_menu ;;
    esac
    return
  fi

  if [[ "${existing_instance_state}" == "incomplete" ]]; then
    prompt_incomplete_instance_action
    return
  fi

  install_or_reconfigure_singbox
}

main() {
  local update_status=0

  if [[ $# -gt 0 ]]; then
    case "$1" in
      menu)
        if [[ $# -ne 1 ]]; then
          agent_cli_error menu invalid_arguments '用法: sbv menu'; return 1
        fi
        shift
        ;;
      -h|--help|help)
        if [[ $# -ne 1 ]]; then
          agent_cli_error help invalid_arguments '用法: sbv --help'; return 1
        fi
        print_cli_help; return 0
        ;;
      agent) shift; agent_dispatch "$@"; return $? ;;
      update)
        case "${2:-}" in
          sbv|script) [[ $# -eq 2 ]] || { agent_cli_error update invalid_arguments '用法: sbv update sbv'; return 1; } ;;
          sing-box|singbox) [[ $# -ge 2 && $# -le 3 ]] || { agent_cli_error update invalid_arguments '用法: sbv update sing-box [latest|x.y.z]'; return 1; } ;;
          *) agent_cli_error update unknown_command '未知 update 子命令。'; return 1 ;;
        esac
        ;;
      update-sbv|update-script|uninstall)
        [[ $# -eq 1 ]] || { agent_cli_error "$1" invalid_arguments '该命令不接收额外参数。'; return 1; }
        ;;
      update-sing-box|update-singbox)
        [[ $# -le 2 ]] || { agent_cli_error update invalid_arguments '用法: sbv update-sing-box [latest|x.y.z]'; return 1; }
        ;;
      --internal-uninstall-purge)
        [[ $# -eq 1 || ( $# -eq 2 && "${2:-}" == --yes ) ]] || { agent_cli_error uninstall invalid_arguments '卸载参数无效。'; return 1; }
        ;;
      *) canonical_cli_dispatch "$@"; return $? ;;
    esac
  fi

  case "${1:-}" in
    -h|--help|help|agent) ;;
    *)
      check_root
      if [[ $# -eq 0 ]]; then
        storage_menu_gate || return $?
      else
        storage_require_current || return $?
      fi
      if [[ $# -eq 0 ]]; then
        acquire_managed_write_lock exclusive allow-rules-recovery || return $?
      else
        acquire_managed_write_lock || return $?
      fi
      if [[ $# -gt 0 && -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
        printf '[ERROR] 存在未完成的实例事务；先执行 sbv agent instance recover，未执行其他写操作。\n' >&2
        return 1
      fi
      ;;
  esac

  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help|help)
        print_cli_help
        exit 0
        ;;
      agent)
        shift
        agent_dispatch "$@"
        exit $?
        ;;
      update)
        shift
        case "${1:-}" in
          sbv|script)
            check_root
            if manual_update_script; then
              exit 0
            else
              update_status=$?
              exit "${update_status}"
            fi
            ;;
          sing-box|singbox)
            shift || true
            check_root
            cli_update_singbox "${1:-}"
            exit $?
            ;;
          *)
            log_warn "未知 update 子命令: ${1:-}" >&2
            print_cli_help >&2
            exit 1
            ;;
        esac
        ;;
      update-sbv|update-script)
        check_root
        if manual_update_script; then
          exit 0
        else
          update_status=$?
          exit "${update_status}"
        fi
        ;;
      update-sing-box|update-singbox)
        shift
        check_root
        cli_update_singbox "${1:-}"
        exit $?
        ;;
      uninstall)
        check_root
        uninstall_singbox
        exit 0
        ;;
      --internal-uninstall-purge)
        check_root
        if [[ "${2:-}" == "--yes" ]]; then
          perform_full_uninstall || exit 1
        else
          uninstall_singbox
        fi
        exit 0
        ;;
    esac
  fi

  show_banner
  check_root
  if [[ -e "${SB_ROUTING_TRANSACTION_DIR}" || -L "${SB_ROUTING_TRANSACTION_DIR}" ]]; then
    log_warn "存在待恢复的规则事务；请进入菜单 12 恢复。"
  elif [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
    log_warn "存在待恢复的实例事务；仅开放只读诊断与菜单 2 恢复入口。"
  elif ! ensure_sbv_command_installed; then
    log_warn "全局命令 sbv 未能完成同步；当前管理菜单继续运行，请稍后手动重试。"
  fi
  while true; do
    # Status checks
    check_script_status
    check_sb_version
    check_bbr_status

    render_section_title "部署管理"
    render_menu_item "1" "安装新协议"
    render_menu_item "2" "协议与实例配置"
    render_menu_item "3" "移除已安装协议"
    render_menu_item "4" "更新 sing-box 版本" "" "${SB_VER_STATUS}"
    render_menu_item "5" "卸载 sing-box"

    render_section_title "服务控制"
    render_menu_item "6" "启动 sing-box"
    render_menu_item "7" "停止 sing-box"
    render_menu_item "8" "重启 sing-box"
    render_menu_item "9" "运行状态摘要" "" "$(main_menu_service_status_summary)"
    render_menu_item "10" "查看实时日志"

    render_section_title "节点与订阅"
    render_menu_item "11" "节点分享与订阅"

    render_section_title "网络与系统"
    render_menu_item "12" "网络与分流"
    render_menu_item "13" "系统设置"

    render_section_title "脚本维护"
    render_menu_item "14" "更新管理脚本 (sbv)" "" "${SCRIPT_VER_STATUS}"
    render_menu_item "15" "卸载管理脚本 (sbv)"
    echo "0. 退出"
    render_main_menu_footer
    choice=$(prompt_choice "请选择 [0-15]: " 0 15 "")

    if [[ -e "${SB_ROUTING_TRANSACTION_DIR}" || -L "${SB_ROUTING_TRANSACTION_DIR}" ]]; then
      case "${choice}" in
        0|10|12) ;;
        *) log_warn "请先通过菜单 12 恢复规则事务；本次未执行其他操作。"; continue ;;
      esac
    fi
    if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
      case "${choice}" in
        0|2|9|10) ;;
        *) log_warn "请先通过菜单 2 恢复未完成的实例事务；本次未执行其他写操作。"; continue ;;
      esac
    fi

    case "$choice" in
      1) install_new_protocols_menu ;;
      2) update_config_only ;;
      3) remove_protocol_menu ;;
      4) update_singbox_version_menu ;;
      5) uninstall_singbox ;;
      6) run_with_progress "启动 sing-box" systemctl start sing-box && log_success "服务已启动。" ;;
      7) systemctl stop sing-box && log_success "服务已停止。" ;;
      8) run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box && log_success "服务已重启。" ;;
      9) view_status ;;
      10) journalctl -u sing-box -f || true ;;
      11) view_node_info ;;
      12) routing_management_menu || log_warn '规则操作未完成，已返回主菜单。' ;;
      13) system_management_menu ;;
      14)
        if manual_update_script; then
          if reload_sbv_menu_after_update; then
            :
          else
            update_status=$?
            log_warn "sbv 已更新，但管理菜单自动切换失败（退出码 ${update_status}）；当前菜单继续运行，请退出后重新运行 sbv。"
          fi
        else
          update_status=$?
          log_warn "sbv 自更新失败（退出码 ${update_status}），已返回管理菜单。"
        fi
        ;;
      15) uninstall_script ;;
      0) exit_script ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
}
