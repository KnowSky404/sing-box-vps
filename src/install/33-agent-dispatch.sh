
agent_component_cli() {
  local operation=${1:-} expected="" input="" component_id="" json=n confirmed=n allow_public=n
  local export_json export_status
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) [[ "${json}" == n ]] || break; json=y; shift ;;
      --yes) [[ "${confirmed}" == n ]] || break; confirmed=y; shift ;;
      --allow-public) [[ "${allow_public}" == n ]] || break; allow_public=y; shift ;;
      --expected-revision) [[ $# -ge 2 && -z "${expected}" ]] || break; expected=$2; shift 2 ;;
      --file) [[ $# -ge 2 && -z "${input}" ]] || break; input=$2; shift 2 ;;
      --id) [[ $# -ge 2 && -z "${component_id}" ]] || break; component_id=$2; shift 2 ;;
      *) break ;;
    esac
  done

  if [[ "${operation}" == list ]]; then
    if [[ $# -ne 0 || "${json}" != y || "${confirmed}" != n || "${allow_public}" != n || -n "${expected}" || -n "${input}" || -n "${component_id}" ]]; then
      agent_json_error invalid_arguments "用法: sbv agent component list --json"; return 1
    fi
    managed_component_inventory_json
    return $?
  fi

  if [[ "${operation}" == diagnose ]]; then
    if [[ $# -ne 0 || "${json}" != y || "${confirmed}" != n || "${allow_public}" != n || -n "${expected}" || -n "${input}" || -n "${component_id}" ]]; then
      agent_json_error invalid_arguments "用法: sbv agent component diagnose --json"; return 1
    fi
    if managed_component_diagnose_json; then
      return 0
    fi
    agent_json_error component_state_untrusted "高级组件状态无法完整读取；未返回部分诊断。"
    return 1
  fi

  if [[ "${operation}" == recover ]]; then
    if [[ $# -ne 0 || "${json}" != y || "${confirmed}" != y || "${allow_public}" != n ||
          -n "${input}" || -n "${component_id}" ||
          ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ]]; then
      agent_json_error invalid_arguments "用法: sbv agent component recover --json --yes --expected-revision N"; return 1
    fi
    if ! structured_instance_store_revision_arg "${expected}" >/dev/null; then
      agent_json_error invalid_arguments "revision 超出安全整数范围；未修改。"; return 1
    fi
    managed_component_recover_transaction "${expected}"
    return $?
  fi

  if [[ "${operation}" == export ]]; then
    if [[ $# -ne 0 || "${json}" != y || "${confirmed}" != n || "${allow_public}" != n ||
          -z "${component_id}" || -n "${input}" ||
          ( -n "${expected}" && ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ) ]]; then
      agent_json_error invalid_arguments "用法: sbv agent component export --json --id ID [--expected-revision N]"; return 1
    fi
    if [[ -n "${expected}" ]] && ! structured_instance_store_revision_arg "${expected}" >/dev/null; then
      agent_json_error invalid_arguments "revision 超出安全整数范围；未修改。"; return 1
    fi
    if export_json=$(managed_component_export_json "${component_id}" "${expected}"); then
      printf '%s\n' "${export_json}"
      return 0
    else
      export_status=$?
    fi
    case "${export_status}" in
      2) agent_json_error revision_mismatch "组件 state revision 不匹配；未返回导出。" ;;
      3) agent_json_error component_not_found "组件不存在；未返回导出。" ;;
      *) agent_json_error component_export_failed "组件状态无法安全读取；未返回导出。" ;;
    esac
    return 1
  fi

  if [[ "${operation}" == takeover ]]; then
    if [[ $# -ne 0 || "${json}" != y || "${confirmed}" != y ||
          -n "${input}" || -n "${component_id}" ||
          ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ]]; then
      agent_json_error invalid_arguments "用法: sbv agent component takeover --json --yes --expected-revision N [--allow-public]"; return 1
    fi
    if ! structured_instance_store_revision_arg "${expected}" >/dev/null; then
      agent_json_error invalid_arguments "revision 超出安全整数范围；未修改。"; return 1
    fi
    if managed_component_state_apply takeover "${expected}" "" "" "${allow_public}"; then
      printf '%s\n' "${MANAGED_COMPONENT_LAST_RESULT}"
      return 0
    fi
    case "${MANAGED_COMPONENT_LAST_ERROR:-component_takeover_failed}" in
      revision_mismatch) agent_json_error revision_mismatch "组件 state revision 不匹配；未修改。" ;;
      instance_transaction_pending) agent_json_error instance_transaction_pending "存在未完成的实例事务；请先完成 instance recover。" ;;
      component_write_busy) agent_json_error component_write_busy "另一个管理进程正在执行；组件未修改。" ;;
      component_transaction_pending) agent_json_error component_transaction_pending "存在未完成的高级组件事务；请先执行 component recover。" ;;
      component_transaction_begin_failed|component_transaction_write_failed) agent_json_error component_transaction_failed "高级组件持久事务日志写入失败；未报告成功。" ;;
      component_cleanup_failed) agent_json_error component_cleanup_failed "组件已提交，但持久事务目录清理失败；请执行 component recover。" ;;
      component_feature_unsupported) agent_json_error component_feature_unsupported "当前 sing-box 核心版本未知或不支持远程规则集 http_client；未修改。" ;;
      network_namespace_unavailable) agent_json_error network_namespace_unavailable "默认 network namespace 不存在、无法访问或预检工具缺失；未修改配置或状态。" ;;
      namespace_runtime_unsafe_build) agent_json_error namespace_runtime_unsafe_build "当前核心构建的 namespace 路径存在已复现崩溃；请安装已验证的兼容构建，配置和状态未修改。" ;;
      namespace_runtime_build_not_assessed) agent_json_error namespace_runtime_build_not_assessed "无法确认当前核心构建的 namespace 兼容性；请提供可解析的构建信息，配置和状态未修改。" ;;
      host_policy_state_invalid|host_policy_preflight_failed) agent_json_error host_policy_preflight_failed "Redirect 主机策略状态或 iptables/接口预检失败；未修改。" ;;
      host_policy_requires_active_service) agent_json_error host_policy_requires_active_service "首次启用 Redirect 主机策略前必须已有 active sing-box 服务；未修改。" ;;
      host_policy_journal_failed) agent_json_error host_policy_journal_failed "Redirect 主机策略事务日志准备失败；未报告成功。" ;;
      host_policy_apply_failed|host_policy_postcheck_failed) agent_json_error host_policy_apply_failed "Redirect 主机策略应用或 postcheck 失败；已尝试事务回滚，必要时请执行 component recover。" ;;
      tproxy_host_policy_state_invalid|tproxy_host_policy_preflight_failed) agent_json_error tproxy_host_policy_preflight_failed "TProxy 主机策略状态、iptables mangle、iproute2 或接口预检失败；未修改。" ;;
      tproxy_host_policy_requires_active_service) agent_json_error tproxy_host_policy_requires_active_service "首次启用 TProxy 主机策略前必须已有 active sing-box 服务；未修改。" ;;
      tproxy_host_policy_journal_failed) agent_json_error tproxy_host_policy_journal_failed "TProxy 主机策略事务日志准备失败；未报告成功。" ;;
      tproxy_host_policy_apply_failed|tproxy_host_policy_postcheck_failed) agent_json_error tproxy_host_policy_apply_failed "TProxy 主机策略应用或 postcheck 失败；已尝试回滚 mangle、策略规则和路由，必要时请执行 component recover。" ;;
      public_confirmation_required) agent_json_error confirmation_required "现有接管对象包含公开监听或 OpenVPN server；请明确传入 --allow-public。" ;;
      component_live_missing) agent_json_error component_live_missing "当前配置没有可接管的已注册高级入站或 Endpoint。" ;;
      component_live_untrusted) agent_json_error component_live_untrusted "当前配置对象或组件状态无法安全读取；未修改。" ;;
      component_takeover_conflict) agent_json_error component_takeover_conflict "接管对象与现有组件 ID/tag 冲突；未修改。" ;;
      config_check_failed) agent_json_error config_check_failed "组件接管已回滚；候选配置或无损保留校验失败。" ;;
      service_restart_failed) agent_json_error service_restart_failed "组件接管已回滚；服务重启失败。" ;;
      transparent_resource_check_failed) agent_json_error transparent_resource_check_failed "组件接管已回滚；core-owned 透明资源未就绪。" ;;
      firewall_prepare_failed) agent_json_error firewall_prepare_failed "组件接管已回滚；防火墙资源预检失败。" ;;
      firewall_apply_failed) agent_json_error firewall_apply_failed "组件接管已回滚；防火墙资源应用失败。" ;;
      firewall_commit_failed) agent_json_error firewall_commit_failed "组件接管已回滚；防火墙资源提交失败。" ;;
      firewall_rollback_failed) agent_json_error firewall_rollback_failed "防火墙外部资源回滚不确定；已保留事务快照供恢复。" ;;
      redirect_policy_rollback_failed) agent_json_error redirect_policy_rollback_failed "Redirect 主机策略回滚不确定；已保留事务快照供恢复。" ;;
      tproxy_policy_rollback_failed) agent_json_error tproxy_policy_rollback_failed "TProxy mangle、策略规则或路由回滚不确定；已保留事务快照供恢复。" ;;
      *) agent_json_error component_takeover_failed "组件接管失败，状态已回滚或保留快照待恢复。" ;;
    esac
    return 1
  fi

  if [[ "${operation}" == rebuild ]]; then
    if [[ $# -ne 0 || "${json}" != y || "${confirmed}" != y || "${allow_public}" != n ||
          -n "${input}" || -n "${component_id}" || ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ]]; then
      agent_json_error invalid_arguments "用法: sbv agent component rebuild --json --yes --expected-revision N"; return 1
    fi
    if ! structured_instance_store_revision_arg "${expected}" >/dev/null; then
      agent_json_error invalid_arguments "revision 超出安全整数范围；未修改。"; return 1
    fi
    if managed_component_state_apply rebuild "${expected}" "" "" n; then
      printf '%s\n' "${MANAGED_COMPONENT_LAST_RESULT}"
      return 0
    fi
    case "${MANAGED_COMPONENT_LAST_ERROR:-component_apply_failed}" in
      revision_mismatch) agent_json_error revision_mismatch "组件 state revision 不匹配；未修改。" ;;
      instance_transaction_pending) agent_json_error instance_transaction_pending "存在未完成的实例事务；请先完成 instance recover。" ;;
      component_write_busy) agent_json_error component_write_busy "另一个管理进程正在执行；组件未修改。" ;;
      component_transaction_pending) agent_json_error component_transaction_pending "存在未完成的高级组件事务；请先执行 component recover。" ;;
      component_transaction_begin_failed|component_transaction_write_failed) agent_json_error component_transaction_failed "高级组件持久事务日志写入失败；未报告成功。" ;;
      component_cleanup_failed) agent_json_error component_cleanup_failed "组件已提交，但持久事务目录清理失败；请执行 component recover。" ;;
      component_feature_unsupported) agent_json_error component_feature_unsupported "当前 sing-box 核心版本未知或不支持远程规则集 http_client；未修改。" ;;
      network_namespace_unavailable) agent_json_error network_namespace_unavailable "默认 network namespace 不存在、无法访问或预检工具缺失；未修改配置或状态。" ;;
      namespace_runtime_unsafe_build) agent_json_error namespace_runtime_unsafe_build "当前核心构建的 namespace 路径存在已复现崩溃；请安装已验证的兼容构建，配置和状态未修改。" ;;
      namespace_runtime_build_not_assessed) agent_json_error namespace_runtime_build_not_assessed "无法确认当前核心构建的 namespace 兼容性；请提供可解析的构建信息，配置和状态未修改。" ;;
      host_policy_state_invalid|host_policy_preflight_failed) agent_json_error host_policy_preflight_failed "Redirect 主机策略状态或 iptables/接口预检失败；未修改。" ;;
      host_policy_requires_active_service) agent_json_error host_policy_requires_active_service "首次启用 Redirect 主机策略前必须已有 active sing-box 服务；未修改。" ;;
      host_policy_journal_failed) agent_json_error host_policy_journal_failed "Redirect 主机策略事务日志准备失败；未报告成功。" ;;
      host_policy_apply_failed|host_policy_postcheck_failed) agent_json_error host_policy_apply_failed "Redirect 主机策略应用或 postcheck 失败；已尝试事务回滚，必要时请执行 component recover。" ;;
      tproxy_host_policy_state_invalid|tproxy_host_policy_preflight_failed) agent_json_error tproxy_host_policy_preflight_failed "TProxy 主机策略状态、iptables mangle、iproute2 或接口预检失败；未修改。" ;;
      tproxy_host_policy_requires_active_service) agent_json_error tproxy_host_policy_requires_active_service "首次启用 TProxy 主机策略前必须已有 active sing-box 服务；未修改。" ;;
      tproxy_host_policy_journal_failed) agent_json_error tproxy_host_policy_journal_failed "TProxy 主机策略事务日志准备失败；未报告成功。" ;;
      tproxy_host_policy_apply_failed|tproxy_host_policy_postcheck_failed) agent_json_error tproxy_host_policy_apply_failed "TProxy 主机策略应用或 postcheck 失败；已尝试回滚 mangle、策略规则和路由，必要时请执行 component recover。" ;;
      config_check_failed) agent_json_error config_check_failed "组件重建已回滚；生成的配置未通过图校验、监听校验或 sing-box check。" ;;
      service_restart_failed) agent_json_error service_restart_failed "组件重建已回滚；服务重启失败。" ;;
      transparent_resource_check_failed) agent_json_error transparent_resource_check_failed "组件重建已回滚；core-owned 透明资源未就绪。" ;;
      firewall_prepare_failed) agent_json_error firewall_prepare_failed "组件重建已回滚；防火墙资源预检失败。" ;;
      firewall_apply_failed) agent_json_error firewall_apply_failed "组件重建已回滚；防火墙资源应用失败。" ;;
      firewall_commit_failed) agent_json_error firewall_commit_failed "组件重建已回滚；防火墙资源提交失败。" ;;
      firewall_rollback_failed) agent_json_error firewall_rollback_failed "防火墙外部资源回滚不确定；已保留事务快照供恢复。" ;;
      redirect_policy_rollback_failed) agent_json_error redirect_policy_rollback_failed "Redirect 主机策略回滚不确定；已保留事务快照供恢复。" ;;
      tproxy_policy_rollback_failed) agent_json_error tproxy_policy_rollback_failed "TProxy mangle、策略规则或路由回滚不确定；已保留事务快照供恢复。" ;;
      *) agent_json_error component_apply_failed "组件重建失败，状态已回滚或保留快照待恢复。" ;;
    esac
    return 1
  fi

  if [[ "${operation}" != create && "${operation}" != replace && "${operation}" != delete ||
        $# -ne 0 || "${json}" != y || "${confirmed}" != y ||
        ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ]]; then
    agent_json_error invalid_arguments "组件参数无效；需要 create/replace/delete、--json、--yes 和 --expected-revision N。"
    return 1
  fi
  if ! structured_instance_store_revision_arg "${expected}" >/dev/null; then
    agent_json_error invalid_arguments "revision 超出安全整数范围；未修改。"
    return 1
  fi
  case "${operation}" in
    create|replace)
      if [[ -z "${input}" || -n "${component_id}" ]]; then
        agent_json_error invalid_arguments "create/replace 需要 --file，且不接受 --id。"; return 1
      fi
      ;;
    delete)
      if [[ -n "${input}" || -z "${component_id}" || "${allow_public}" != n ]]; then
        agent_json_error invalid_arguments "delete 需要 --id，且不接受 --file/--allow-public。"; return 1
      fi
      ;;
  esac
  if managed_component_state_apply "${operation}" "${expected}" "${input}" "${component_id}" "${allow_public}"; then
    printf '%s\n' "${MANAGED_COMPONENT_LAST_RESULT}"
    return 0
  fi
  case "${MANAGED_COMPONENT_LAST_ERROR:-component_apply_failed}" in
    revision_mismatch) agent_json_error revision_mismatch "组件 state revision 不匹配；未修改。" ;;
    instance_transaction_pending) agent_json_error instance_transaction_pending "存在未完成的实例事务；请先完成 instance recover。" ;;
    public_confirmation_required) agent_json_error confirmation_required "公开监听或隧道组件需要 --allow-public；未修改。" ;;
    component_feature_unsupported) agent_json_error component_feature_unsupported "当前 sing-box 核心版本未知或不支持远程规则集 http_client；未修改。" ;;
    network_namespace_unavailable) agent_json_error network_namespace_unavailable "默认 network namespace 不存在、无法访问或预检工具缺失；未修改配置或状态。" ;;
    namespace_runtime_unsafe_build) agent_json_error namespace_runtime_unsafe_build "当前核心构建的 namespace 路径存在已复现崩溃；请安装已验证的兼容构建，配置和状态未修改。" ;;
    namespace_runtime_build_not_assessed) agent_json_error namespace_runtime_build_not_assessed "无法确认当前核心构建的 namespace 兼容性；请提供可解析的构建信息，配置和状态未修改。" ;;
    host_policy_state_invalid|host_policy_preflight_failed) agent_json_error host_policy_preflight_failed "Redirect 主机策略状态或 iptables/接口预检失败；未修改。" ;;
    host_policy_requires_active_service) agent_json_error host_policy_requires_active_service "首次启用 Redirect 主机策略前必须已有 active sing-box 服务；未修改。" ;;
    host_policy_journal_failed) agent_json_error host_policy_journal_failed "Redirect 主机策略事务日志准备失败；未报告成功。" ;;
    host_policy_apply_failed|host_policy_postcheck_failed) agent_json_error host_policy_apply_failed "Redirect 主机策略应用或 postcheck 失败；已尝试事务回滚，必要时请执行 component recover。" ;;
    tproxy_host_policy_state_invalid|tproxy_host_policy_preflight_failed) agent_json_error tproxy_host_policy_preflight_failed "TProxy 主机策略状态、iptables mangle、iproute2 或接口预检失败；未修改。" ;;
    tproxy_host_policy_requires_active_service) agent_json_error tproxy_host_policy_requires_active_service "首次启用 TProxy 主机策略前必须已有 active sing-box 服务；未修改。" ;;
    tproxy_host_policy_journal_failed) agent_json_error tproxy_host_policy_journal_failed "TProxy 主机策略事务日志准备失败；未报告成功。" ;;
    tproxy_host_policy_apply_failed|tproxy_host_policy_postcheck_failed) agent_json_error tproxy_host_policy_apply_failed "TProxy 主机策略应用或 postcheck 失败；已尝试回滚 mangle、策略规则和路由，必要时请执行 component recover。" ;;
    component_referenced_or_missing) agent_json_error component_referenced "组件仍被 route/group/detour 引用，或目标不存在；未修改。" ;;
    record_invalid|component_conflict) agent_json_error invalid_component "组件记录无效、类型不受支持或 tag/id 冲突；未修改。" ;;
    service_restart_failed) agent_json_error service_restart_failed "组件已回滚；服务重启失败。" ;;
    transparent_resource_check_failed) agent_json_error transparent_resource_check_failed "组件已回滚；core-owned 透明资源未就绪。" ;;
    config_check_failed) agent_json_error config_check_failed "组件已回滚；生成的配置未通过图校验或 sing-box check。" ;;
    root_required) agent_json_error root_required "组件写操作必须以 root 执行；未修改。" ;;
    component_write_busy) agent_json_error component_write_busy "另一个管理进程正在执行；组件未修改。" ;;
    component_transaction_pending) agent_json_error component_transaction_pending "存在未完成的高级组件事务；请先执行 component recover。" ;;
    component_transaction_begin_failed|component_transaction_write_failed) agent_json_error component_transaction_failed "高级组件持久事务日志写入失败；未报告成功。" ;;
    component_cleanup_failed) agent_json_error component_cleanup_failed "组件已提交，但持久事务目录清理失败；请执行 component recover。" ;;
    firewall_prepare_failed) agent_json_error firewall_prepare_failed "组件已回滚；防火墙资源预检失败，未执行外部变更。" ;;
    firewall_apply_failed) agent_json_error firewall_apply_failed "组件已回滚；防火墙资源应用失败。" ;;
    firewall_commit_failed) agent_json_error firewall_commit_failed "组件已回滚；防火墙资源提交失败。" ;;
    firewall_rollback_failed) agent_json_error firewall_rollback_failed "防火墙外部资源回滚不确定；已保留事务快照供恢复。" ;;
    redirect_policy_rollback_failed) agent_json_error redirect_policy_rollback_failed "Redirect 主机策略回滚不确定；已保留事务快照供恢复。" ;;
    tproxy_policy_rollback_failed) agent_json_error tproxy_policy_rollback_failed "TProxy mangle、策略规则或路由回滚不确定；已保留事务快照供恢复。" ;;
    *) agent_json_error component_apply_failed "组件事务失败，状态已回滚或保留快照待恢复。" ;;
  esac
  return 1
}

agent_instance_protocol_supported() {
  case "${1:-}" in
    vless-reality|mixed|socks|http|shadowsocks|trojan|vmess|vless-plain|anytls|hy2|snell|tuic|hysteria|naive|shadowtls)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

agent_instance_store_record_json() {
  local protocol=${1:-} instance_id=${2:-} schema store_file inbound_json address port tag

  protocol=$(normalize_protocol_id "${protocol}") || return 1
  schema=$(protocol_instance_state_schema "${protocol}") || return 1
  if [[ "${schema}" == 2 && "${protocol}" != vless-reality ]]; then
    store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
    jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' "${store_file}"
    return $?
  fi
  if [[ "${protocol}" == vless-reality ]]; then
    tag=${SB_VLESS_INBOUND_TAG:-}
    [[ -n "${tag}" ]] || tag=$(vless_reality_inbound_tag_for_instance "${instance_id}") || return 1
    inbound_json=$(jq -c --arg tag "${tag}" '.inbounds[]? | select(.tag == $tag)' "${SINGBOX_CONFIG_FILE}") || return 1
    address=$(jq -r '.listen // ""' <<< "${inbound_json}") || return 1
    port=$(jq -r '.listen_port // 0' <<< "${inbound_json}") || return 1
    jq -cn \
      --arg id "${SB_VLESS_INSTANCE_ID:-${instance_id}}" \
      --arg name "${SB_NODE_NAME:-}" \
      --arg tag "${tag}" \
      --arg address "${address}" \
      --arg port "${port}" \
      --arg uuid "${SB_UUID:-}" \
      --arg sni "${SB_SNI:-}" \
      --arg short_id_1 "${SB_SHORT_ID_1:-}" \
      --arg short_id_2 "${SB_SHORT_ID_2:-}" \
      --arg policy "${SB_OUTBOUND_POLICY:-default}" \
      '{id:$id,name:$name,protocol:"vless-reality",tag:$tag,listen:{address:$address,port:($port|tonumber)},authentication:{uuid:$uuid},tls:{server_name:$sni,short_id:[$short_id_1,$short_id_2]},outbound_policy:$policy}'
    return $?
  fi
  jq -cn --arg id "${instance_id}" --arg protocol "${protocol}" \
    '{id:$id,protocol:$protocol,legacy_state:true}'
}

agent_instance_safe_record_json() {
  local protocol=${1:-} instance_id=${2:-} record

  record=$(agent_instance_store_record_json "${protocol}" "${instance_id}") || return 1
  jq -c '
    del(
      .authentication.password,
      .authentication.psk,
      .authentication.username,
      .authentication.uuid,
      .authentication.users[]?.password,
      .authentication.users[]?.username,
      .authentication.users[]?.uuid,
      .authentication.users[]?.auth_str,
      .authentication.users[]?.userkey,
      .authentication.users[]?.private_key,
      .tls.key_path,
      .tls.short_id,
      .client_tls.key_path
    )
  ' <<< "${record}"
}

agent_instance_current_revision_json() {
  local protocol=${1:-} schema store_file

  protocol=$(normalize_protocol_id "${protocol}") || return 1
  schema=$(protocol_instance_state_schema "${protocol}") || return 1
  if [[ "${schema}" == 2 && "${protocol}" != vless-reality ]]; then
    store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
    jq -er '.revision' "${store_file}"
  else
    printf 'null\n'
  fi
}

agent_instance_read_cli() {
  local operation=${1:-} protocol=${2:-} expected="" instance_id="" json=n
  local indexed_protocols current_revision summary safe_record check_json check_status=0
  local state_matches=false api_protocol record_json connection_json service_state
  local indexed_protocol_array=()

  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) [[ "${json}" == n ]] || break; json=y; shift ;;
      --expected-revision) [[ $# -ge 2 && -z "${expected}" ]] || break; expected=$2; shift 2 ;;
      --id) [[ $# -ge 2 && -z "${instance_id}" ]] || break; instance_id=$2; shift 2 ;;
      *) break ;;
    esac
  done
  protocol=$(normalize_protocol_id "${protocol}") || {
    agent_json_error invalid_arguments "实例协议无效；未读取。"; return 1;
  }
  agent_instance_protocol_supported "${protocol}" || {
    agent_json_error invalid_arguments "实例协议不支持该只读入口；未读取。"; return 1;
  }
  [[ $# -eq 0 && "${json}" == y ]] || {
    agent_json_error invalid_arguments "用法: instance view|diagnose|export 协议 --json [--id ID] [--expected-revision N]"; return 1;
  }
  if [[ -n "${expected}" && ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ]]; then
    agent_json_error invalid_arguments "revision 格式无效；未读取。"; return 1
  fi
  if ! structured_instance_store_revision_arg "${expected:-0}" >/dev/null; then
    agent_json_error invalid_arguments "revision 超出安全整数范围；未读取。"; return 1;
  fi
  indexed_protocols=$(agent_trusted_indexed_protocols_raw) || {
    agent_json_error protocol_state_untrusted "协议索引或 live 配置无法完整读取；未读取实例。"; return 1;
  }
  mapfile -t indexed_protocol_array <<< "${indexed_protocols}"
  protocol_array_contains "${protocol}" "${indexed_protocol_array[@]}" || {
    agent_json_error protocol_not_installed "协议未安装或未被当前索引信任；未读取。"; return 1;
  }
  if [[ -z "${instance_id}" ]]; then
    instance_id=$(protocol_default_instance_id "${protocol}") || {
      agent_json_error instance_not_found "未找到该协议的默认实例；未读取。"; return 1;
    }
  fi
  load_protocol_instance_state "${protocol}" "${instance_id}" || {
    agent_json_error instance_not_found "实例不存在或状态无法安全读取；未读取。"; return 1;
  }
  current_revision=$(agent_instance_current_revision_json "${protocol}") || {
    agent_json_error protocol_state_untrusted "实例 revision 无法安全读取；未读取。"; return 1;
  }
  if [[ -n "${expected}" && "${current_revision}" != null && "${expected}" != "${current_revision}" ]]; then
    agent_json_error revision_mismatch "实例 state revision 不匹配；未读取。"; return 1;
  fi
  if [[ -n "${expected}" && "${current_revision}" == null && "${expected}" != 0 ]]; then
    agent_json_error revision_mismatch "该实例没有可比较的 typed revision；未读取。"; return 1;
  fi
  api_protocol=$(agent_protocol_id "${protocol}") || return 1
  summary=$(agent_node_summary_json_for_current_protocol "127.0.0.1") || {
    agent_json_error instance_view_failed "实例摘要无法安全读取；未返回部分凭据。"; return 1;
  }
  safe_record=$(agent_instance_safe_record_json "${protocol}" "${instance_id}") || {
    agent_json_error instance_view_failed "实例记录无法安全读取；未返回部分凭据。"; return 1;
  }
  case "${operation}" in
    view)
      jq -n --arg protocol "${api_protocol}" --arg id "${instance_id}" \
        --argjson revision "${current_revision}" --argjson summary "${summary}" \
        --argjson record "${safe_record}" \
        '{action:"instance-view",protocol:$protocol,instance_id:$id,revision:$revision,instance:$summary,record:$record,sensitive:false}'
      ;;
    export)
      connection_json=$(agent_link_json_for_current_protocol "127.0.0.1") || {
        agent_json_error instance_export_failed "实例连接材料无法安全生成；未返回部分导出。"; return 1;
      }
      record_json=$(agent_instance_store_record_json "${protocol}" "${instance_id}") || {
        agent_json_error instance_export_failed "实例敏感记录无法安全读取；未返回部分导出。"; return 1;
      }
      jq -n --arg protocol "${api_protocol}" --arg id "${instance_id}" \
        --argjson revision "${current_revision}" --argjson record "${record_json}" \
        --argjson connection "${connection_json}" \
        '{action:"instance-export",protocol:$protocol,instance_id:$id,revision:$revision,sensitive:true,record:$record,connection:$connection}'
      ;;
    diagnose)
      if check_json=$(agent_singbox_check_json); then check_status=0; else check_status=$?; fi
      if protocol_state_matches_config "${protocol}" >/dev/null 2>&1; then state_matches=true; fi
      if service_state=$(systemctl is-active sing-box 2>/dev/null); then
        :
      else
        service_state=${service_state:-unknown}
      fi
      jq -n --arg protocol "${api_protocol}" --arg id "${instance_id}" \
        --argjson revision "${current_revision}" --argjson summary "${summary}" \
        --argjson record "${safe_record}" --argjson check "${check_json}" \
        --arg service_state "${service_state}" --argjson state_matches "${state_matches}" \
        --argjson check_status "${check_status}" \
        '{action:"instance-diagnose",protocol:$protocol,instance_id:$id,revision:$revision,instance:$summary,record:$record,state:{matches_config:$state_matches},service:{active_state:$service_state},check:$check,check_exit_code:$check_status,sensitive:false}'
      [[ "${check_status}" == 0 && "${state_matches}" == true ]]
      ;;
    *)
      agent_json_error invalid_arguments "未知实例只读操作；未读取。"; return 1 ;;
  esac
}

agent_instance_cli() {
  local operation=${1:-} protocol=${2:-} expected="" input="" instance_id="" json=n confirmed=n allow_public=n
  if [[ "${operation}" == view || "${operation}" == diagnose || "${operation}" == export ]]; then
    agent_instance_read_cli "${operation}" "${protocol}" "${@:3}"
    return $?
  fi
  [[ $# -ge 2 ]] || { agent_json_error invalid_arguments "用法: instance 操作 mixed|socks|http|shadowsocks|trojan|vmess|vless-plain|anytls|hy2|snell|tuic|hysteria|naive|shadowtls --json [--yes --expected-revision N] [--file 文件 | --id ID]"; return 1; }
  shift 2
  protocol=$(normalize_protocol_id "${protocol}") || {
    agent_json_error invalid_arguments "实例协议无效；未修改。"; return 1;
  }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) [[ "${json}" == n ]] || break; json=y; shift ;;
      --yes) [[ "${confirmed}" == n ]] || break; confirmed=y; shift ;;
      --allow-public) [[ "${allow_public}" == n ]] || break; allow_public=y; shift ;;
      --expected-revision) [[ $# -ge 2 && -z "${expected}" ]] || break; expected=$2; shift 2 ;;
      --file) [[ $# -ge 2 && -z "${input}" ]] || break; input=$2; shift 2 ;;
      --id) [[ $# -ge 2 && -z "${instance_id}" ]] || break; instance_id=$2; shift 2 ;;
      *) break ;;
    esac
  done
  if [[ $# -ne 0 || "${json}" != y || ("${protocol}" != mixed && "${protocol}" != socks && "${protocol}" != http && "${protocol}" != shadowsocks && "${protocol}" != trojan && "${protocol}" != vmess && "${protocol}" != vless-plain && "${protocol}" != anytls && "${protocol}" != hy2 && "${protocol}" != snell && "${protocol}" != tuic && "${protocol}" != hysteria && "${protocol}" != naive && "${protocol}" != shadowtls) || ! "${expected}" =~ ^(0|[1-9][0-9]{0,15})$ ]]; then
    agent_json_error invalid_arguments "实例参数、协议或 revision 无效；未修改。"; return 1
  fi
  if ! structured_instance_store_revision_arg "${expected}" >/dev/null; then
    agent_json_error invalid_arguments "revision 超出安全整数范围；未修改。"; return 1
  fi
  if [[ "${operation}" == migrate && "${protocol}" != mixed ]]; then
    agent_json_error invalid_arguments "只有 Mixed 提供 legacy schema 1 迁移；SOCKS/HTTP/Shadowsocks/Trojan/VMess/VLESS/AnyTLS/Hysteria2/Snell/TUIC/Hysteria/NaiveProxy/ShadowTLS 使用 schema 2，已有 live 配置请使用接管入口。"
    return 1
  fi
  if [[ "${operation}" == rebuild || "${operation}" == takeover ]]; then
    [[ -n "${expected}" ]] || {
      agent_json_error invalid_arguments "rebuild/takeover 需要 --expected-revision N。"; return 1;
    }
  fi
  if [[ "${operation}" == rebuild && "${allow_public}" == y ]]; then
    agent_json_error invalid_arguments "rebuild 不改变监听暴露，不接收 --allow-public。"; return 1
  fi
  [[ "${confirmed}" == y ]] || { agent_json_error confirmation_required "实例写操作需要 --yes；非回环入口另需 --allow-public。"; return 1; }
  case "${operation}" in
    create|replace) [[ -n "${input}" && -z "${instance_id}" ]] || { agent_json_error invalid_arguments "create/replace 需要 --file 类型化实例记录。"; return 1; } ;;
    delete|default) [[ -z "${input}" && -n "${instance_id}" && "${allow_public}" == n ]] || { agent_json_error invalid_arguments "delete/default 需要 --id。"; return 1; }; input=${instance_id} ;;
    migrate|recover|rebuild) [[ -z "${input}${instance_id}" && "${allow_public}" == n ]] || { agent_json_error invalid_arguments "migrate/recover/rebuild 不接收实例参数。"; return 1; } ;;
    takeover) [[ -z "${input}${instance_id}" ]] || { agent_json_error invalid_arguments "takeover 不接收 --file 或 --id；可选 --allow-public。"; return 1; } ;;
    *) agent_json_error invalid_arguments "未知实例操作。"; return 1 ;;
  esac
  if [[ "${operation}" == recover ]]; then
    recover_plain_proxy_instance_transaction "${protocol}" "${expected}"
  else
    apply_plain_proxy_instance_change "${protocol}" "${operation}" "${expected}" "${input}" "${allow_public}"
  fi
}

agent_cli() {
  local command=${1:-help}
  shift || true
  local service_command

  case "${command}" in
    storage)
      storage_cli "$@"
      ;;
    help|-h|--help)
      if [[ $# -ne 0 ]]; then
        agent_cli_error "help" "invalid_arguments" "用法: sbv agent help"
        return $?
      fi
      agent_print_help
      ;;
    capabilities)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "capabilities" "invalid_arguments" "用法: sbv agent capabilities --json"
        return $?
      fi
      agent_cli_run "capabilities" agent_capabilities_json
      ;;
    commands)
      if [[ $# -ne 1 || "${1:-}" != --json ]]; then
        agent_cli_error commands invalid_arguments '用法: sbv commands --json'; return 1
      fi
      agent_cli_run commands agent_commands_json
      ;;
    schema)
      agent_cli_run schema agent_schema_cli "$@"
      ;;
    routing)
      agent_cli_run routing agent_routing_cli "$@"
      ;;
    instance)
      agent_cli_run "instance" agent_instance_cli "$@"
      ;;
    component)
      agent_cli_run "component" agent_component_cli "$@"
      ;;
    upgrade-check)
      if [[ $# -ne 2 || "${1:-}" != "--json" ]]; then
        agent_cli_error "upgrade-check" "invalid_arguments" "用法: sbv agent upgrade-check --json x.y.z"
        return $?
      fi
      agent_cli_run "upgrade-check" agent_upgrade_check_json "${2}"
      ;;
    upgrade)
      if [[ $# -lt 2 || $# -gt 3 || "${1:-}" != "--json" ]]; then
        agent_cli_error "upgrade" "invalid_arguments" "用法: sbv agent upgrade --json x.y.z --yes"
        return $?
      fi
      agent_cli_run "upgrade" agent_upgrade_cli "$@"
      ;;
    status)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "status" "invalid_arguments" "用法: sbv agent status --json"
        return $?
      fi
      agent_cli_run "status" agent_status_json
      ;;
    nodes)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "nodes" "invalid_arguments" "用法: sbv agent nodes --json"
        return $?
      fi
      agent_cli_run "nodes" agent_collect_nodes_json "summary"
      ;;
    links)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "links" "invalid_arguments" "用法: sbv agent links --json"
        return $?
      fi
      agent_cli_run "links" agent_collect_nodes_json "links"
      ;;
    warp)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "warp" "invalid_arguments" "用法: sbv agent warp --json"
        return $?
      fi
      agent_cli_run "warp" agent_warp_json
      ;;
    check)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "check" "invalid_arguments" "用法: sbv agent check --json"
        return $?
      fi
      agent_cli_run "check" agent_singbox_check_json
      ;;
    doctor)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "doctor" "invalid_arguments" "用法: sbv agent doctor --json"
        return $?
      fi
      agent_cli_run "doctor" agent_doctor_json
      ;;
    service)
      service_command=${1:-service}
      if [[ $# -lt 1 || $# -gt 4 ]]; then
        agent_cli_error "service ${service_command}" "invalid_arguments" "用法: sbv service start|stop|restart|status|logs --json [--yes | --lines N]"
        return $?
      fi
      agent_cli_run "service ${service_command}" agent_service_cli "$@"
      ;;
    subman-sync)
      if [[ $# -ne 1 || "${1:-}" != "--json" ]]; then
        agent_cli_error "subman-sync" "invalid_arguments" "用法: sbv agent subman-sync --json"
        return $?
      fi
      agent_cli_run "subman-sync" agent_subman_sync_json
      ;;
    *)
      agent_cli_error "${command}" "unknown_command" "未知 agent 子命令: ${command}"
      return $?
      ;;
  esac
}

agent_command_name_from_args() {
  local command=${1:-help}

  if [[ "${command}" == "service" && -n "${2:-}" ]]; then
    printf 'service %s' "${2}"
  else
    printf '%s' "${command}"
  fi
}

agent_current_user_is_root() {
  [[ ${EUID} -eq 0 ]]
}

agent_dispatch() {
  local command

  case "${1:-help}" in
    help|-h|--help)
      agent_cli "$@"
      return $?
      ;;
  esac

  command=$(agent_command_name_from_args "$@")
  case "${1:-}" in
    capabilities|commands|schema) agent_cli "$@"; return $? ;;
    storage) storage_cli "${@:2}"; return $? ;;
  esac
  storage_require_current || return $?
  if [[ -e "${SB_ROUTING_TRANSACTION_DIR}" || -L "${SB_ROUTING_TRANSACTION_DIR}" ]]; then
    if [[ "${1:-}" != routing || "${2:-}" != recover ]]; then
      agent_cli_error "${command}" routing_transaction_pending "存在未完成的规则事务；请先执行 sbv routing recover --json --yes。"
      return 1
    fi
  fi
  if ! agent_current_user_is_root; then
    agent_cli_error "${command}" "root_required" "Agent 命令必须以 root 用户执行。"
    return $?
  fi

  case "${1:-}" in
    routing)
      (
        if [[ "${2:-}" == recover ]]; then
          if ! acquire_managed_write_lock exclusive allow-rules-recovery; then
            agent_cli_error routing instance_write_busy '另一个管理进程正在执行。'; return 1
          fi
        elif [[ "${2:-}" == apply || "${2:-}" == restore ]]; then
          if ! acquire_managed_write_lock; then
            agent_cli_error routing instance_write_busy '另一个管理进程正在执行。'; return 1
          fi
        elif ! acquire_managed_write_lock shared; then
          agent_cli_error routing instance_write_busy '配置正在被管理进程使用。'; return 1
        fi
        if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" || -L "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
          agent_cli_error routing instance_transaction_pending '请先完成 instance recover。'; return 1
        fi
        if [[ -e "${SB_COMPONENT_TRANSACTION_DIR}" || -L "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
          agent_cli_error routing component_transaction_pending '请先完成 component recover。'; return 1
        fi
        agent_cli "$@"
      )
      ;;
    service)
      (
        case "${2:-}" in status|logs) local service_lock=shared ;; *) local service_lock=exclusive ;; esac
        if ! acquire_managed_write_lock "${service_lock}"; then
          agent_cli_error "${command}" instance_write_busy '另一个管理进程正在执行。'; return 1
        fi
        if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" || -L "${SB_PROJECT_DIR}.instance-write.lock" ||
              -e "${SB_COMPONENT_TRANSACTION_DIR}" || -L "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
          agent_cli_error "${command}" transaction_pending '请先恢复未完成的实例或组件事务。'; return 1
        fi
        agent_cli "$@"
      )
      ;;
    instance)
      case "${2:-}" in
        view|diagnose|export)
          (
            if ! acquire_managed_write_lock shared; then
              agent_cli_error "instance" instance_write_busy "配置正在被管理进程使用，未返回部分实例状态。"; return 1
            fi
            if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
              agent_cli_error "instance" instance_transaction_pending "存在未完成的实例事务；请先检查并恢复。"; return 1
            fi
            agent_cli "$@"
          )
          ;;
        *) agent_cli "$@" ;;
      esac
      ;;
    component)
      case "${2:-}" in
        diagnose) (
          if ! acquire_managed_write_lock shared; then
            agent_cli_error "component" instance_write_busy "配置正在被管理进程使用，未返回部分组件状态。"; return 1
          fi
          if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
            agent_cli_error "component" instance_transaction_pending "存在未完成的实例事务；请先检查并恢复。"; return 1
          fi
          agent_cli "$@"
        ) ;;
        list|export) (
          if ! acquire_managed_write_lock shared; then
            agent_cli_error "component" instance_write_busy "配置正在被管理进程使用，未返回部分组件状态。"; return 1
          fi
          if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
            agent_cli_error "component" instance_transaction_pending "存在未完成的实例事务；请先检查并恢复。"; return 1
          fi
          if [[ -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
            agent_cli_error "component" component_transaction_pending "存在未完成的高级组件事务；请先执行 component recover。"; return 1
          fi
          agent_cli "$@"
        ) ;;
        recover) (
          if ! acquire_managed_write_lock; then
            agent_cli_error "component" instance_write_busy "另一个管理进程正在执行；未开始组件恢复。"; return 1
          fi
          if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
            agent_cli_error "component" instance_transaction_pending "请先完成 instance recover；未开始组件恢复。"; return 1
          fi
          agent_cli "$@"
        ) ;;
        *) (
          if ! acquire_managed_write_lock; then
            agent_cli_error "component" instance_write_busy "另一个管理进程正在执行。"; return 1
          fi
          if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
            agent_cli_error "component" instance_transaction_pending "请先完成 instance recover；未开始其他写操作。"; return 1
          fi
          if [[ -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
            agent_cli_error "component" component_transaction_pending "请先完成 component recover；未开始其他写操作。"; return 1
          fi
          agent_cli "$@"
        ) ;;
      esac
      ;;
    status|nodes|links|check|doctor|warp|upgrade-check)
      (
        if ! acquire_managed_write_lock shared; then
          agent_cli_error "${command}" instance_write_busy "配置正在被管理进程使用，未返回部分状态。"; return 1
        fi
        if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
          agent_cli_error "${command}" instance_transaction_pending "存在未完成的实例事务；请先检查并恢复。"; return 1
        fi
        agent_cli "$@"
      )
      ;;
    upgrade|subman-sync)
      (
        if ! acquire_managed_write_lock; then
          agent_cli_error "${command}" instance_write_busy "另一个管理进程正在执行。"; return 1
        fi
        if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
          agent_cli_error "${command}" instance_transaction_pending "请先完成 instance recover；未开始其他写操作。"; return 1
        fi
        agent_cli "$@"
      )
      ;;
    *) agent_cli "$@" ;;
  esac
}
