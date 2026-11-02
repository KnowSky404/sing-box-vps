
# New function: Update config only
update_config_only() {
  local selected_protocol selected_instance snapshot_dir
  local retained_protocols=() retained_csv empty_baseline=n

  # Recovery must remain reachable before reading potentially interrupted state.
  if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
    if selected_protocol=$(jq -er '.protocol // "mixed"' "${SB_PROJECT_DIR}.instance-write.lock/transaction.json") &&
       plain_proxy_management_pending_revision "${selected_protocol}" >/dev/null; then
      protocol_instance_management_menu "${selected_protocol}"
      return $?
    fi
    log_warn "无法验证未完成的实例事务；已保留现场，请使用 Agent 恢复入口或人工检查。"
    return 1
  fi

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_error "未找到配置文件或协议状态，请先执行安装流程。"
  fi

  mapfile -t retained_protocols < <(list_retained_instance_protocols)
  retained_csv=$(IFS=,; printf '%s' "${retained_protocols[*]-}")
  if [[ ${#retained_protocols[@]} -gt 0 ]] && instance_management_empty_config_baseline; then
    # The last delete keeps revisioned stores but has no active protocol to
    # load or migrate. The instance transaction validates the recreate later.
    empty_baseline=y
  else
    migrate_legacy_single_protocol_state_if_needed
    log_info "正在读取当前配置..."
    load_current_config_state
  fi

  echo -e "\n${BLUE}--- 进入配置修改模式 ---${NC}"
  SELECTED_PROTOCOL=""
  if ! prompt_installed_protocol_selection "${retained_csv}" "${empty_baseline}"; then
    return 0
  fi
  selected_protocol="${SELECTED_PROTOCOL}"
  [[ -n "${selected_protocol}" ]] || return 0

  # Consolidate the instance tools under the existing protocol entry. Keep
  # legacy ACME/provider state on its original edit path.
  if protocol_array_contains "${selected_protocol}" ${retained_protocols[@]+"${retained_protocols[@]}"} ||
     [[ "${selected_protocol}" == mixed || "${selected_protocol}" == socks ||
        "${selected_protocol}" == http || "${selected_protocol}" == shadowsocks ||
        "${selected_protocol}" == trojan || "${selected_protocol}" == vmess ]] ||
     plain_proxy_structured_state_active "${selected_protocol}"; then
    protocol_instance_management_menu "${selected_protocol}"
    return $?
  fi

  load_protocol_state "${selected_protocol}"
  if [[ "${selected_protocol}" == "vless-reality" ]]; then
    SELECTED_VLESS_INSTANCE_ID=""
    if ! prompt_vless_reality_instance_selection; then
      return 0
    fi
    selected_instance="${SELECTED_VLESS_INSTANCE_ID}"
    load_vless_reality_protocol_state
    load_vless_reality_instance_state "${selected_instance}" || log_error "加载 REALITY 实例失败: ${selected_instance}"
    echo -e "当前正在修改: $(protocol_display_name "${SB_PROTOCOL}") / ${SB_NODE_NAME} (${SB_VLESS_INSTANCE_ID})"
  else
    echo -e "当前正在修改: $(protocol_display_name "${SB_PROTOCOL}")"
  fi
  ensure_existing_generated_config_baseline || return 1
  snapshot_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
  if [[ "${selected_protocol}" == vless-reality ]]; then
    if ! prompt_protocol_update_fields "${selected_protocol}"; then
      abort_managed_state_transaction "${snapshot_dir}" "协议输入已取消或未完成"
      return 1
    fi
  else
    prompt_protocol_update_fields "${selected_protocol}"
  fi
  if ! save_protocol_state "${selected_protocol}" || ! generate_config; then
    abort_managed_state_transaction "${snapshot_dir}" "协议配置生成或校验失败"
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "协议配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
  if [[ "${selected_protocol}" == "vless-reality" ]]; then
    refresh_vless_reality_qos_rules
  fi
  setup_service
  open_committed_protocol_ports || return $?
  load_protocol_state "${selected_protocol}"
  run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box
  log_success "配置及服务文件已更新并重启服务。"
  log_info "连接信息未自动展示，如需查看请进入菜单 11。"
}

remove_protocol_menu() {
  local protocols=() selected_protocols=() remaining_protocols=()
  local selected_protocol display_str confirm
  local state_file backup_state_file transaction_dir
  local joined_protocols first_remaining protocol
  local reality_instances=() instance_state_file backup_instance_state_file
  local selected_instance first_remaining_instance removed_instance_port
  local reality_remove_mode="instance" choice removed_port
  local removed_ports=() idx raw_choice raw_choices chosen_protocol display_list

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" && ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    log_error "未找到配置文件或协议状态，请先执行安装流程。"
  fi

  migrate_legacy_single_protocol_state_if_needed
  load_current_config_state
  mapfile -t protocols < <(list_installed_protocols)

  if [[ ${#protocols[@]} -eq 0 ]]; then
    log_error "当前未检测到已安装协议。"
  fi

  echo -e "\n${BLUE}--- 移除已安装协议 ---${NC}"
  echo "可用协议:"
  for idx in "${!protocols[@]}"; do
    echo "$((idx + 1)). $(protocol_display_name "${protocols[$idx]}")"
  done
  echo "0. 返回"
  echo "留空则移除所有已安装协议。"
  read -rp "请选择一个或多个协议 [0-${#protocols[@]}]，逗号分隔: " choice

  if [[ -z "$(trim_whitespace "${choice}")" ]]; then
    selected_protocols=("${protocols[@]}")
  elif [[ "$(trim_whitespace "${choice}")" == "0" ]]; then
    return 0
  else
    IFS="," read -r -a raw_choices <<< "${choice}"
    for raw_choice in "${raw_choices[@]}"; do
      raw_choice=$(trim_whitespace "${raw_choice}")
      [[ -z "${raw_choice}" ]] && continue
      if [[ "${raw_choice}" =~ ^[1-9][0-9]*$ ]] && (( raw_choice >= 1 && raw_choice <= ${#protocols[@]} )); then
        chosen_protocol="${protocols[$((raw_choice - 1))]}"
        if ! protocol_array_contains "${chosen_protocol}" ${selected_protocols[@]+"${selected_protocols[@]}"}; then
          selected_protocols+=("${chosen_protocol}")
        fi
      else
        log_warn "跳过无效选项: ${raw_choice}"
      fi
    done
  fi

  if [[ ${#selected_protocols[@]} -eq 0 ]]; then
    log_info "未选择任何协议。"
    return 0
  fi

  if mixed_structured_state_active && protocol_array_contains mixed "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      mixed_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 Mixed 实例需通过实例事务逐个移除；请先进入 Mixed 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active socks && protocol_array_contains socks "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      socks_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 SOCKS 实例需通过实例事务逐个移除；请先进入 SOCKS 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active http && protocol_array_contains http "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      http_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 HTTP 实例需通过实例事务逐个移除；请先进入 HTTP 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active shadowsocks && protocol_array_contains shadowsocks "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      shadowsocks_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 Shadowsocks 实例需通过实例事务逐个移除；请先进入 Shadowsocks 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi

  if plain_proxy_structured_state_active trojan && protocol_array_contains trojan "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      trojan_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 Trojan 实例需通过实例事务逐个移除；请先进入 Trojan 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active vmess && protocol_array_contains vmess "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      vmess_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 VMess 实例需通过实例事务逐个移除；请先进入 VMess 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active vless-plain && protocol_array_contains vless-plain "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      vless_plain_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 VLESS 实例需通过实例事务逐个移除；请先进入 VLESS 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active anytls && protocol_array_contains anytls "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      anytls_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 AnyTLS 实例需通过实例事务逐个移除；请先进入 AnyTLS 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active hy2 && protocol_array_contains hy2 "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      hy2_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 Hysteria2 实例需通过实例事务逐个移除；请先进入 Hysteria2 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active snell && protocol_array_contains snell "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      snell_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 Snell 实例需通过实例事务逐个移除；请先进入 Snell 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active tuic && protocol_array_contains tuic "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      tuic_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 TUIC 实例需通过实例事务逐个移除；请先进入 TUIC 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi
  if plain_proxy_structured_state_active hysteria && protocol_array_contains hysteria "${selected_protocols[@]}"; then
    if [[ ${#selected_protocols[@]} -eq 1 ]]; then
      hysteria_instance_management_menu delete
      return $?
    fi
    log_warn "结构化 Hysteria 实例需通过实例事务逐个移除；请先进入 Hysteria 实例管理，再移除其他协议。本次未修改。"
    return 1
  fi

  # Selecting only VLESS + REALITY keeps the historical per-instance removal
  # flow when more than one managed instance exists, while still exposing an
  # explicit whole-protocol option. Multi-select and blank keep their newer
  # whole-protocol semantics.
  if [[ ${#selected_protocols[@]} -eq 1 && "${selected_protocols[0]}" == "vless-reality" ]]; then
    migrate_vless_reality_state_to_instances_if_needed
    mapfile -t reality_instances < <(list_vless_reality_instance_ids)
    if [[ ${#reality_instances[@]} -gt 1 ]]; then
      echo "检测到多个 REALITY 实例:"
      echo "1. 移除单个 REALITY 实例 (默认)"
      echo "2. 移除整个 VLESS + REALITY 协议"
      echo "0. 返回"
      read -rp "请选择移除范围 [1]: " reality_remove_mode
      reality_remove_mode=$(trim_whitespace "${reality_remove_mode}")
      case "${reality_remove_mode}" in
        ""|1) reality_remove_mode="instance" ;;
        2) reality_remove_mode="protocol" ;;
        0) return 0 ;;
        *)
          log_warn "无效选项，已取消移除。"
          return 0
          ;;
      esac
    fi
    if [[ ${#reality_instances[@]} -gt 1 && "${reality_remove_mode}" == "instance" ]]; then
      SELECTED_VLESS_INSTANCE_ID=""
      if ! prompt_vless_reality_instance_selection; then
        return 0
      fi
      selected_instance="${SELECTED_VLESS_INSTANCE_ID}"
      load_vless_reality_instance_state "${selected_instance}" || \
        log_error "未找到 REALITY 实例状态: ${selected_instance}"
      removed_instance_port="${SB_PORT}"
      read -rp "确认移除 REALITY 实例 ${SB_NODE_NAME} (${selected_instance})? [y/N]: " confirm
      if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        log_info "已取消移除 REALITY 实例。"
        return 0
      fi

      instance_state_file=$(vless_reality_instance_state_file "${selected_instance}") || \
        log_error "REALITY 实例 ID 非法: ${selected_instance}"
      state_file=$(protocol_state_file "vless-reality")
      [[ -f "${instance_state_file}" ]] || log_error "未找到 REALITY 实例状态文件: ${instance_state_file}"
      [[ -f "${state_file}" ]] || log_error "未找到协议状态文件: ${state_file}"

      ensure_existing_generated_config_baseline || return 1
      transaction_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
      backup_instance_state_file="${instance_state_file}.bak.$(date +%Y%m%d%H%M%S)"
      if ! mv "${instance_state_file}" "${backup_instance_state_file}"; then
        abort_managed_state_transaction "${transaction_dir}" "REALITY 实例状态备份失败"
      fi

      load_vless_reality_protocol_state
      remove_vless_reality_instance_id_from_list "${selected_instance}"
      first_remaining_instance="${VLESS_REALITY_INSTANCE_IDS%%,*}"
      if [[ "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" == "${selected_instance}" ]]; then
        VLESS_REALITY_DEFAULT_INSTANCE_ID="${first_remaining_instance}"
      fi
      if ! save_vless_reality_protocol_state; then
        abort_managed_state_transaction "${transaction_dir}" "REALITY 协议状态写入失败"
      fi

      if ! generate_config; then
        abort_managed_state_transaction "${transaction_dir}" "移除 REALITY 实例后配置生成或校验失败"
      fi

      if ! discard_managed_state_snapshot "${transaction_dir}"; then
        log_warn "REALITY 实例移除已提交，但临时事务快照未能删除: ${transaction_dir}。"
      fi
      setup_service
      load_protocol_state "vless-reality"
      open_committed_protocol_ports || return $?
      refresh_vless_reality_qos_rules
      run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box
      close_firewall_port "${removed_instance_port}" || return $?
      log_success "已移除 REALITY 实例: ${selected_instance}。原状态已备份到: ${backup_instance_state_file}"
      return 0
    fi
  fi

  display_list=()
  for selected_protocol in "${selected_protocols[@]}"; do
    display_list+=("$(protocol_display_name "${selected_protocol}")")
  done
  display_str=$(IFS=", "; printf "%s" "${display_list[*]}")
  read -rp "确认移除下列协议: ${display_str}? [y/N]: " confirm
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    log_info "已取消移除协议。"
    return 0
  fi

  ensure_existing_generated_config_baseline || return 1
  if [[ ${#selected_protocols[@]} -eq ${#protocols[@]} &&
        -f "${SB_PROJECT_DIR}/managed-config.generated.json" ]] &&
     [[ "$(jq -cS . "${SINGBOX_CONFIG_FILE}")" != "$(jq -cS . "${SB_PROJECT_DIR}/managed-config.generated.json")" ]]; then
    log_warn "配置包含手工扩展；legacy 整体移除会删除共享配置，已取消。请使用对应协议的实例事务移除，或先人工迁移扩展。"
    return 1
  fi
  transaction_dir=$(create_managed_state_snapshot) || log_error "无法创建配置状态事务快照。"
  if [[ ${#selected_protocols[@]} -eq ${#protocols[@]} ]]; then
    if ! persist_file_backup "${SINGBOX_CONFIG_FILE}" "${SINGBOX_CONFIG_FILE}.bak" ||
       ! persist_file_backup "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_INDEX_FILE}.bak"; then
      abort_managed_state_transaction "${transaction_dir}" "无法为当前配置和协议索引创建持久备份"
    fi
  fi

  for selected_protocol in "${selected_protocols[@]}"; do
    if [[ "${selected_protocol}" == "vless-reality" ]]; then
      migrate_vless_reality_state_to_instances_if_needed
      mapfile -t reality_instances < <(list_vless_reality_instance_ids)
      if [[ ${#reality_instances[@]} -gt 0 ]]; then
        for instance_id in "${reality_instances[@]}"; do
          if ! instance_state_file=$(vless_reality_instance_state_file "${instance_id}"); then
            abort_managed_state_transaction "${transaction_dir}" "REALITY 实例 ID 非法: ${instance_id}"
          fi
          if [[ ! -f "${instance_state_file}" ]]; then
            abort_managed_state_transaction "${transaction_dir}" "未找到 REALITY 实例状态: ${instance_id}"
          fi
          backup_instance_state_file="${instance_state_file}.bak.$(date +%Y%m%d%H%M%S)"
          if ! mv "${instance_state_file}" "${backup_instance_state_file}"; then
            abort_managed_state_transaction "${transaction_dir}" "REALITY 实例状态备份失败: ${instance_id}"
          fi
          # Capture removed instance port for firewall cleanup
          removed_ports+=("$(sed -n 's/^PORT=//p' "${backup_instance_state_file}" 2>/dev/null || true)")
        done
        state_file=$(protocol_state_file "vless-reality")
        if [[ -f "${state_file}" ]]; then
          backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
          if ! mv "${state_file}" "${backup_state_file}"; then
            abort_managed_state_transaction "${transaction_dir}" "VLESS + REALITY 协议状态备份失败"
          fi
          VLESS_REALITY_INSTANCE_IDS=""
          VLESS_REALITY_DEFAULT_INSTANCE_ID=""
        else
          abort_managed_state_transaction "${transaction_dir}" "未找到 VLESS + REALITY 协议状态"
        fi
      else
        abort_managed_state_transaction "${transaction_dir}" "未找到可移除的 REALITY 实例状态"
      fi
    else
      state_file=$(protocol_state_file "${selected_protocol}")
      if [[ -f "${state_file}" ]]; then
        backup_state_file="${state_file}.bak.$(date +%Y%m%d%H%M%S)"
        if ! mv "${state_file}" "${backup_state_file}"; then
          abort_managed_state_transaction "${transaction_dir}" "协议状态备份失败: ${selected_protocol}"
        fi
        # Capture removed protocol port for firewall cleanup
        removed_ports+=("$(sed -n 's/^PORT=//p' "${backup_state_file}" 2>/dev/null || true)")
      else
        abort_managed_state_transaction "${transaction_dir}" "未找到协议状态: ${selected_protocol}"
      fi
    fi
  done

  for protocol in "${protocols[@]}"; do
    if protocol_array_contains "${protocol}" "${selected_protocols[@]}"; then
      continue
    fi
    remaining_protocols+=("${protocol}")
  done

  if [[ ${#remaining_protocols[@]} -gt 0 ]]; then
    joined_protocols=$(IFS=,; printf "%s" "${remaining_protocols[*]}")
    if ! write_protocol_index "${joined_protocols}"; then
      abort_managed_state_transaction "${transaction_dir}" "协议索引写入失败"
    fi
  else
    # Stop before treating the new inventory as empty. A stop failure must not
    # turn a still-running listener into an apparently unreferenced resource.
    local stop_status
    if systemctl stop sing-box >/dev/null 2>&1; then :; else
      stop_status=$?
      rollback_managed_state_snapshot "${transaction_dir}" || \
        log_warn "服务停止失败且文件回滚失败；请检查事务快照。"
      printf '[ERROR] protocol_remove: stop_failed; firewall_unchanged\n' >&2
      return "${stop_status}"
    fi
    if ! singbox_service_confirmed_stopped; then
      rollback_managed_state_snapshot "${transaction_dir}" || \
        log_warn "服务状态无法确认且文件回滚失败；请检查事务快照。"
      printf '[ERROR] protocol_remove: service_state_unconfirmed; inspect_service_manually\n' >&2
      return 1
    fi
    rm -f "${SB_PROTOCOL_INDEX_FILE}"
    rm -f "${SINGBOX_CONFIG_FILE}"
    if command -v tc >/dev/null 2>&1; then
      clear_vless_reality_qos_rules
    fi
    if systemctl disable sing-box >/dev/null 2>&1; then :; else
      stop_status=$?
      printf '[ERROR] protocol_remove: disable_failed; service_stopped; firewall_unchanged; snapshot=%s\n' "${transaction_dir}" >&2
      return "${stop_status}"
    fi
    for removed_port in "${removed_ports[@]}"; do
      if [[ -n "${removed_port}" ]]; then
        close_firewall_port "${removed_port}" all_removed || return $?
      fi
    done
    if ! discard_managed_state_snapshot "${transaction_dir}"; then
      log_warn "协议移除已提交，但临时事务快照未能删除: ${transaction_dir}。"
    fi
    log_info "所有协议已移除，sing-box 服务已停止。"
    return 0
  fi

  if ! generate_config; then
    abort_managed_state_transaction "${transaction_dir}" "移除协议后配置生成或校验失败"
  fi

  if ! discard_managed_state_snapshot "${transaction_dir}"; then
    log_warn "协议移除已提交，但临时事务快照未能删除: ${transaction_dir}。"
  fi
  setup_service
  first_remaining="${remaining_protocols[0]}"
  load_protocol_state "${first_remaining}"
  open_committed_protocol_ports || return $?
  refresh_vless_reality_qos_rules
  run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box
  for removed_port in "${removed_ports[@]}"; do
    if [[ -n "${removed_port}" ]]; then
      close_firewall_port "${removed_port}" || return $?
    fi
  done
  log_success "已移除协议: ${display_str}。"
}
