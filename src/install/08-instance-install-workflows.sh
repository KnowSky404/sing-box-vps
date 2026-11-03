
# Compatibility surface for the existing Mixed menu/tests.  The old public
# signatures stay intact while all new validation and record construction live
# in the shared plain-proxy helpers above.
mixed_management_capture_snapshot() { plain_proxy_management_capture_snapshot mixed "$@"; }
mixed_management_prompt_target() { plain_proxy_management_prompt_target mixed "$@"; }
mixed_management_build_record() { plain_proxy_management_build_record mixed "$@"; }

plain_proxy_management_pending_revision() {
  local protocol=${1:-} transaction_file="${SB_PROJECT_DIR}.instance-write.lock/transaction.json"
  structured_instance_store_protocol "${protocol}" >/dev/null || return 1
  [[ -f "${transaction_file}" && ! -L "${transaction_file}" ]] || return 1
  jq -e --arg protocol "${protocol}" '
    .schema_version == 1 and (if has("protocol") then .protocol else "mixed" end) == $protocol and
    (.expected_revision | type == "string" and test("^(0|[1-9][0-9]{0,15})$"))
  ' "${transaction_file}" >/dev/null 2>&1 || return 1
  jq -er '.expected_revision' "${transaction_file}" 2>/dev/null
}

mixed_instance_create_interactive() (
  local temp_dir revision result status allow_public=n
  umask 077
  temp_dir=$(storage_mktemp -d) || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  mixed_management_capture_snapshot "${temp_dir}/before.json" || {
    log_error "Mixed 状态无法安全读取，已取消创建。"
    return 1
  }
  revision=$(jq -r '.revision' "${temp_dir}/before.json") || return 1
  mixed_management_build_record "${temp_dir}/before.json" create "" "${temp_dir}/record.json" || return $?
  allow_public=${MIXED_MANAGEMENT_ALLOW_PUBLIC:-n}
  result=$(apply_mixed_instance_change create "${revision}" "${temp_dir}/record.json" "${allow_public}") || {
    status=$?
    [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2
    return "${status}"
  }
  [[ -n "${result}" ]] && printf '%s\n' "${result}"
)

mixed_management_pending_revision() {
  plain_proxy_management_pending_revision mixed
}

mixed_management_confirm() {
  prompt_yes_no "$1 [y/N]: " n
}

mixed_instance_management_menu() (
  local requested_operation=${1:-} temp_dir choice snapshot revision target record_file result status one_shot=n last_instance=n
  local confirmation
  umask 077
  case "${requested_operation}" in
    "") ;;
    delete) one_shot=y ;;
    *) log_warn "不支持的 Mixed 管理操作: ${requested_operation}" >&2; return 1 ;;
  esac
  temp_dir=$(storage_mktemp -d) || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  while true; do
    # Recovery is intentionally offered before reading live config/store: an
    # interrupted transaction may leave those files at an untrusted phase.
    if [[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
      if revision=$(mixed_management_pending_revision); then
        echo "检测到未完成的 Mixed 实例事务（revision ${revision}）。" >&2
        choice=$(prompt_choice "仅可恢复该事务；恢复 [1]，返回 [0]: " 0 1 0) || return 1
        [[ "${choice}" == 1 ]] || return 0
        [[ "$(mixed_management_confirm "确认执行事务恢复")" == y ]] || return 0
        result=$(recover_mixed_instance_transaction "${revision}") || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; return "${status}"
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        return 0
      fi
      log_error "发现无法验证的 Mixed 实例事务日志；保留现场，未执行任何变更。"
      return 1
    fi
    if [[ "${one_shot}" == y ]]; then
      choice=3
    else
      echo -e "\n${BLUE}--- Mixed 实例管理 ---${NC}"
      echo "1. 创建实例"
      echo "2. 修改实例"
      echo "3. 删除实例"
      echo "4. 设置默认实例"
      echo "5. 迁移 legacy schema 1"
      echo "6. 恢复未完成事务"
      echo "7. 列出实例（含 ID）"
      echo "0. 返回"
      choice=$(prompt_choice "请选择 [0-7]: " 0 7 "") || return 1
    fi
    if [[ "${choice}" == 0 ]]; then return 0; fi
    if [[ "${choice}" == 6 ]]; then
      if revision=$(mixed_management_pending_revision); then
        [[ "$(mixed_management_confirm "确认执行事务恢复")" == y ]] || continue
        result=$(recover_mixed_instance_transaction "${revision}") || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; continue
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
      else
        log_warn "当前没有可验证的待恢复事务。"
      fi
      continue
    fi
    if ! mixed_management_capture_snapshot "${temp_dir}/before.json"; then
      log_error "Mixed 状态缺失或格式不可信；未执行任何变更。"
      return 1
    fi
    snapshot="${temp_dir}/before.json"
    revision=$(jq -r '.revision' "${snapshot}") || return 1
    case "${choice}" in
      1)
        record_file="${temp_dir}/record.json"
        mixed_management_build_record "${snapshot}" create "" "${record_file}" || continue
        result=$(apply_mixed_instance_change create "${revision}" "${record_file}" "${MIXED_MANAGEMENT_ALLOW_PUBLIC:-n}") || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; continue;
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        ;;
      2)
        target=$(mixed_management_prompt_target "${snapshot}" "请选择要修改的 Mixed 实例") || continue
        record_file="${temp_dir}/record.json"
        mixed_management_build_record "${snapshot}" replace "${target}" "${record_file}" || continue
        result=$(apply_mixed_instance_change replace "${revision}" "${record_file}" "${MIXED_MANAGEMENT_ALLOW_PUBLIC:-n}") || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; continue;
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        ;;
      3|4)
        last_instance=n
        [[ "${choice}" == 3 ]] && [[ "$(jq -r '.instances | length' "${snapshot}")" == 1 ]] && last_instance=y
        target=$(mixed_management_prompt_target "${snapshot}" "请选择实例") || {
          [[ "${one_shot}" == y ]] && return 0
          continue
        }
        if [[ "${choice}" == 3 ]]; then
          confirmation="确认删除实例 ${target}"
        else
          confirmation="确认将 ${target} 设为默认实例"
        fi
        if [[ "$(mixed_management_confirm "${confirmation}")" != y ]]; then
          [[ "${one_shot}" == y ]] && return 0
          continue
        fi
        result=$(apply_mixed_instance_change "$([[ "${choice}" == 3 ]] && printf delete || printf default)" "${revision}" "${target}" n) || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; continue;
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        [[ "${one_shot}" == y || "${last_instance}" == y ]] && return 0
        ;;
      5)
        [[ "$(mixed_management_confirm "确认迁移 Mixed legacy schema 1")" == y ]] || continue
        result=$(apply_mixed_instance_change migrate "${revision}" "" n) || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; continue;
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        ;;
      6)
        result=$(recover_mixed_instance_transaction "${revision}") || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; continue;
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        ;;
      7)
        jq -r '.instances[] | "\(.id)\t\(.name)\t\(.listen.address):\(.listen.port)\tauth=\(.authentication.enabled)\tpolicy=\(.outbound_policy)"' "${snapshot}"
        ;;
      0) return 0 ;;
    esac
  done
)

socks_instance_management_menu() {
  plain_proxy_instance_management_menu socks "$@"
}

http_instance_management_menu() {
  plain_proxy_instance_management_menu http "$@"
}

shadowsocks_instance_management_menu() {
  plain_proxy_instance_management_menu shadowsocks "$@"
}

trojan_instance_management_menu() {
  plain_proxy_instance_management_menu trojan "$@"
}

vmess_instance_management_menu() {
  plain_proxy_instance_management_menu vmess "$@"
}

vless_plain_instance_management_menu() {
  plain_proxy_instance_management_menu vless-plain "$@"
}

anytls_instance_management_menu() {
  if protocol_state_exists anytls && ! plain_proxy_structured_state_active anytls; then
    log_warn '当前 AnyTLS 仍是 legacy schema 1；请使用配置更新入口保留原有 ACME/provider 配置，不能直接进入 schema 2 实例管理。' >&2
    return 1
  fi
  plain_proxy_instance_management_menu anytls "$@"
}

hy2_instance_management_menu() {
  plain_proxy_instance_management_menu hy2 "$@"
}

snell_instance_management_menu() {
  plain_proxy_instance_management_menu snell "$@"
}

tuic_instance_management_menu() {
  plain_proxy_instance_management_menu tuic "$@"
}

hysteria_instance_management_menu() {
  plain_proxy_instance_management_menu hysteria "$@"
}

naive_instance_management_menu() {
  plain_proxy_instance_management_menu naive "$@"
}

shadowtls_instance_management_menu() {
  plain_proxy_instance_management_menu shadowtls "$@"
}

protocol_instance_management_menu() {
  local protocol
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  "${protocol//-/_}_instance_management_menu"
}

plain_proxy_instance_management_menu() (
  local protocol=${1:-} requested_operation=${2:-} temp_dir choice snapshot revision target result status one_shot=n
  local record_file label confirmation
  umask 077
  label=$(plain_proxy_management_label "${protocol}") || return 1
  case "${requested_operation}" in
    "") ;;
    create) choice=1; one_shot=y ;;
    replace) choice=2; one_shot=y ;;
    delete) choice=3; one_shot=y ;;
    default) choice=4; one_shot=y ;;
    migrate) log_warn "${label} 没有 legacy schema 1 可迁移。" >&2; return 1 ;;
    recover) choice=6; one_shot=y ;;
    list) choice=7; one_shot=y ;;
    *) log_warn "不支持的 ${label} 管理操作: ${requested_operation}" >&2; return 1 ;;
  esac
  temp_dir=$(storage_mktemp -d) || return 1
  trap 'rm -rf -- "${temp_dir}"' EXIT
  while true; do
    if [[ -d "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
      if revision=$(plain_proxy_management_pending_revision "${protocol}"); then
        echo "检测到未完成的 ${label} 实例事务（revision ${revision}）。" >&2
        choice=$(prompt_choice "仅可恢复该事务；恢复 [1]，返回 [0]: " 0 1 0) || return 1
        [[ "${choice}" == 1 ]] || return 0
        [[ "$(mixed_management_confirm "确认执行事务恢复")" == y ]] || return 0
        result=$(run_with_progress "${label} 事务恢复" recover_plain_proxy_instance_transaction "${protocol}" "${revision}") || {
          status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; return "${status}"
        }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        return 0
      fi
      log_error "发现无法验证的 ${label} 实例事务日志；保留现场，未执行任何变更。"
      return 1
    fi
    if [[ -z "${requested_operation}" ]]; then
      echo -e "\n${BLUE}--- ${label} 实例管理 ---${NC}"
      echo "1. 创建实例"; echo "2. 修改实例"; echo "3. 删除实例"; echo "4. 设置默认实例"
      echo "5. 迁移 legacy schema 1（不适用）"; echo "6. 恢复未完成事务"; echo "7. 列出实例（含 ID）"; echo "0. 返回"
      if [[ "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain ]]; then
        echo "字段：用户凭据、TLS、传输、client_trust（均为类型化输入）"
      elif [[ "${protocol}" == anytls ]]; then
        echo "字段：用户凭据、TLS、client_trust（均为类型化输入）"
      elif [[ "${protocol}" == hy2 ]]; then
        echo "字段：用户凭据、ACME 自动签发或手动 TLS、client_trust、带宽、Salamander obfs、masquerade"
      elif [[ "${protocol}" == snell ]]; then
        echo "字段：Snell 版本、PSK、用户 key、v5 obfs 或 v6 shaping（均为类型化输入）"
      elif [[ "${protocol}" == tuic ]]; then
        echo "字段：用户 UUID/密码、手动 TLS、client_trust、QUIC 拥塞与 UDP relay 选项（均为类型化输入）"
      elif [[ "${protocol}" == hysteria ]]; then
        echo "字段：用户 auth_str、手动 TLS、client_trust、必填带宽、obfs 与 QUIC 选项（均为类型化输入）"
      elif [[ "${protocol}" == naive ]]; then
        echo "字段：NaiveProxy 用户、TCP/UDP 网络、手动 TLS、client_trust 与客户端 QUIC 参数（均为类型化输入）"
      elif [[ "${protocol}" == shadowtls ]]; then
        echo "字段：ShadowTLS 版本/认证、握手映射、strict/wildcard、detour 与客户端信任（均为类型化输入）"
      fi
      choice=$(prompt_choice "请选择 [0-7]: " 0 7 "") || return 1
    fi
    [[ "${choice}" == 0 ]] && return 0
    if [[ "${choice}" == 6 ]]; then
      revision=$(plain_proxy_management_pending_revision "${protocol}" 2>/dev/null || true)
      if [[ -n "${revision}" ]]; then
        [[ "$(mixed_management_confirm "确认执行事务恢复")" == y ]] || { [[ "${one_shot}" == y ]] && return 0 || continue; }
        result=$(run_with_progress "${label} 事务恢复" recover_plain_proxy_instance_transaction "${protocol}" "${revision}") || { status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; [[ "${one_shot}" == y ]] && return "${status}" || continue; }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
      else log_warn "当前没有可验证的待恢复事务。"; fi
      [[ "${one_shot}" == y ]] && return 0
      continue
    fi
    if ! plain_proxy_management_capture_snapshot "${protocol}" "${temp_dir}/before.json"; then
      log_error "${label} 状态缺失或格式不可信；未执行任何变更。"; return 1
    fi
    snapshot="${temp_dir}/before.json"; revision=$(jq -r '.revision' "${snapshot}") || return 1
    case "${choice}" in
      1|2)
        record_file="${temp_dir}/record.json"
        target=""
        if [[ "${choice}" == 2 ]]; then
          target=$(plain_proxy_management_prompt_target "${protocol}" "${snapshot}" "请选择要修改的 ${label} 实例") || { [[ "${one_shot}" == y ]] && return 0 || continue; }
        fi
        plain_proxy_management_build_record "${protocol}" "${snapshot}" "$([[ "${choice}" == 1 ]] && printf create || printf replace)" "${target}" "${record_file}" || {
          status=$?
          [[ "${one_shot}" == y ]] && return "${status}"
          continue
        }
        result=$(run_with_progress "${label} 实例事务（校验、备份、发布及服务检查）" apply_plain_proxy_instance_change "${protocol}" "$([[ "${choice}" == 1 ]] && printf create || printf replace)" "${revision}" "${record_file}" "${PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC:-n}") || { status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; [[ "${one_shot}" == y ]] && return "${status}" || continue; }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        [[ "${one_shot}" == y ]] && return 0
        ;;
      3|4)
        target=$(plain_proxy_management_prompt_target "${protocol}" "${snapshot}" "请选择实例") || { [[ "${one_shot}" == y ]] && return 0 || continue; }
        if [[ "${choice}" == 3 ]]; then
          confirmation="确认删除实例 ${target}"
        else
          confirmation="确认将 ${target} 设为默认实例"
        fi
        [[ "$(mixed_management_confirm "${confirmation}")" == y ]] || { [[ "${one_shot}" == y ]] && return 0 || continue; }
        result=$(run_with_progress "${label} 实例事务（校验、备份、发布及服务检查）" apply_plain_proxy_instance_change "${protocol}" "$([[ "${choice}" == 3 ]] && printf delete || printf default)" "${revision}" "${target}" n) || { status=$?; [[ -n "${result:-}" ]] && printf '%s\n' "${result}" >&2; [[ "${one_shot}" == y ]] && return "${status}" || continue; }
        [[ -n "${result}" ]] && printf '%s\n' "${result}"
        [[ "${one_shot}" == y ]] && return 0
        ;;
      5) log_warn "${label} 没有 legacy schema 1 可迁移。" ;;
      7)
        jq -r --arg protocol "${protocol}" '.instances[] | "\(.id)\t\(.name)\t\(.listen.address):\(.listen.port)" + (if $protocol == "shadowsocks" then "\tnetwork=\(.listen.network|join(","))\tmethod=\(.authentication.method)\tusers=\(.authentication.users|length)" elif $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then "\tusers=\(.authentication.users|length)\ttransport=\(.transport.type)\ttls=\(.tls.enabled)\tclient_trust=\(.client_trust)" elif $protocol == "anytls" then "\tusers=\(.authentication.users|length)\ttls=\(.tls.enabled)\tclient_trust=\(.client_trust)" elif $protocol == "hy2" then "\tusers=\(.authentication.users|length)\ttls=\(.tls.enabled)\tclient_trust=\(.client_trust)\tbandwidth=\(.bandwidth.up_mbps // "-")/\(.bandwidth.down_mbps // "-")\tobfs=\(.obfs.enabled)" elif $protocol == "snell" then "\tversion=\(.version)\tusers=\(.authentication.users|length)\tobfs=\(.obfs_mode // .mode)" elif $protocol == "tuic" then "\tusers=\(.authentication.users|length)\ttls=\(.tls.enabled)\tclient_trust=\(.client_trust)\tcc=\(.tuic.congestion_control)\trelay=\(.tuic.udp_relay_mode // (if .tuic.udp_over_stream then "udp_over_stream" else "-" end))" elif $protocol == "hysteria" then "\tusers=\(.authentication.users|length)\ttls=\(.tls.enabled)\tclient_trust=\(.client_trust)\tbandwidth=\(.bandwidth.up_mbps)/\(.bandwidth.down_mbps)\tobfs=\(.obfs.enabled)" elif $protocol == "naive" then "\tnetwork=\(.listen.network|join(","))\tusers=\(.authentication.users|length)\ttls=\(.tls.enabled)\tclient_trust=\(.client_trust)\tcc=\(.naive.quic_congestion_control)" elif $protocol == "shadowtls" then "\tversion=\(.version)\tusers=\(if .version == 3 then (.authentication.users|length) else (if .version == 2 then 1 else 0 end) end)\tclient_trust=\(.client_trust)\tdetour=\(.detour.listen.address):\(.detour.listen.port)" else "\tauth=\(.authentication.enabled)\tpolicy=\(.outbound_policy)" + (if $protocol == "http" then "\ttls=\(.tls.enabled)" else "" end) end)' "${snapshot}" || return $?
        [[ "${one_shot}" == y ]] && return 0
        ;;
      *) log_warn "无效选项，请重新选择。" ;;
    esac
  done
)

install_protocols_interactive() {
  local install_mode=$1
  local preselected_protocols=${2:-}
  local installed_protocols=() selected_protocols=()
  local protocol first_selected_protocol snapshot_dir installed_protocol_list

  load_stack_mode_state

  if [[ "${install_mode}" == "fresh" ]]; then
    get_os_info
    get_arch
    prompt_singbox_version
    prompt_protocol_install_selection "fresh" || return 0
    IFS=',' read -r -a selected_protocols <<< "${SELECTED_PROTOCOLS_CSV}"
    if protocol_array_contains mixed "${selected_protocols[@]}" && mixed_inactive_store_snapshot >/dev/null 2>&1; then
      log_warn "Mixed 已保留 revision；请通过协议实例管理创建 Mixed 实例，或本次仅选择其他协议。"
      return 1
    fi
    if protocol_array_contains socks "${selected_protocols[@]}" && plain_proxy_inactive_store_snapshot socks >/dev/null 2>&1; then
      log_warn "SOCKS 已保留 revision；请通过追加安装单独创建 SOCKS 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot http >/dev/null 2>&1 &&
       protocol_array_contains http "${selected_protocols[@]}"; then
      log_warn "HTTP 已保留 revision；请通过协议实例管理创建 HTTP 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot shadowsocks >/dev/null 2>&1 &&
       protocol_array_contains shadowsocks "${selected_protocols[@]}"; then
      log_warn "Shadowsocks 已保留 revision；请通过协议实例管理创建 Shadowsocks 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot trojan >/dev/null 2>&1 &&
       protocol_array_contains trojan "${selected_protocols[@]}"; then
      log_warn "Trojan 已保留 revision；请通过实例管理入口创建 Trojan 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot vmess >/dev/null 2>&1 &&
       protocol_array_contains vmess "${selected_protocols[@]}"; then
      log_warn "VMess 已保留 revision；请通过实例管理入口创建 VMess 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot vless-plain >/dev/null 2>&1 &&
       protocol_array_contains vless-plain "${selected_protocols[@]}"; then
      log_warn "VLESS 已保留 revision；请通过实例管理入口创建 VLESS 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot anytls >/dev/null 2>&1 &&
       protocol_array_contains anytls "${selected_protocols[@]}"; then
      log_warn "AnyTLS 已保留 revision；请通过实例管理入口创建 AnyTLS 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot hy2 >/dev/null 2>&1 &&
       protocol_array_contains hy2 "${selected_protocols[@]}"; then
      log_warn "Hysteria2 已保留 revision；请通过实例管理入口创建 Hysteria2 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot snell >/dev/null 2>&1 &&
       protocol_array_contains snell "${selected_protocols[@]}"; then
      log_warn "Snell 已保留 revision；请通过实例管理入口创建 Snell 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot tuic >/dev/null 2>&1 &&
       protocol_array_contains tuic "${selected_protocols[@]}"; then
      log_warn "TUIC 已保留 revision；请通过实例管理入口创建 TUIC 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot hysteria >/dev/null 2>&1 &&
       protocol_array_contains hysteria "${selected_protocols[@]}"; then
      log_warn "Hysteria 已保留 revision；请通过实例管理入口创建 Hysteria 实例，或本次仅选择其他协议。"
      return 1
    fi
    if plain_proxy_inactive_store_snapshot shadowtls >/dev/null 2>&1 &&
       protocol_array_contains shadowtls "${selected_protocols[@]}"; then
      log_warn "ShadowTLS 已保留 revision；请通过协议实例管理创建 ShadowTLS 实例，或本次仅选择其他协议。"
      return 1
    fi
    # REALITY checks run during its input prompts and need dig/jq/TLS tools.
    # Prepare them before those prompts; other protocols keep their order.
    if protocol_array_contains vless-reality "${selected_protocols[@]}"; then
      install_dependencies || return $?
    fi
    snapshot_dir=$(create_managed_state_snapshot) || {
      log_error "无法创建配置状态事务快照。"
      return 1
    }

    for protocol in "${selected_protocols[@]}"; do
      if ! prompt_protocol_install_fields "${protocol}" || ! save_protocol_state "${protocol}"; then
        abort_managed_state_transaction "${snapshot_dir}" "协议 ${protocol} 配置或状态保存失败"
        return 1
      fi
    done

    if ! routing_policy_prepare_install_defaults || ! write_protocol_index "${SELECTED_PROTOCOLS_CSV}"; then
      abort_managed_state_transaction "${snapshot_dir}" "已有网络设置载入或协议索引保存失败"
      return 1
    fi
    if ! protocol_array_contains vless-reality "${selected_protocols[@]}"; then
      install_dependencies || return $?
    fi
    local lookup_status=0
    get_latest_version || lookup_status=$?
    if [[ ${lookup_status} -ne 0 ]]; then
      rollback_managed_state_snapshot "${snapshot_dir}" || log_warn '版本查询中断且状态恢复失败，请检查事务快照。'
      return "${lookup_status}"
    fi
    if ! install_binary; then
      abort_managed_state_transaction "${snapshot_dir}" "sing-box 核心准备或安装失败"
      return 1
    fi
  else
    # Removing the last managed instance leaves a valid empty configuration
    # and revisioned stores. Do not rebuild an installed inventory from it.
    if instance_management_empty_config_baseline; then
      installed_protocol_list=""
    else
      migrate_legacy_single_protocol_state_if_needed recover-incomplete-index || return 1
      installed_protocol_list=$(list_installed_protocols) || return 1
    fi
    load_current_config_state "${installed_protocol_list}" || return 1
    if [[ -n "${installed_protocol_list}" ]]; then
      mapfile -t installed_protocols <<< "${installed_protocol_list}"
    fi
    if mixed_inactive_store_snapshot >/dev/null 2>&1 &&
       ! protocol_array_contains mixed ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(mixed)
    fi
    if plain_proxy_inactive_store_snapshot http >/dev/null 2>&1 &&
       ! protocol_array_contains http ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(http)
    fi
    if plain_proxy_inactive_store_snapshot shadowsocks >/dev/null 2>&1 &&
       ! protocol_array_contains shadowsocks ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(shadowsocks)
    fi
    if plain_proxy_inactive_store_snapshot trojan >/dev/null 2>&1 &&
       ! protocol_array_contains trojan ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(trojan)
    fi
    if plain_proxy_inactive_store_snapshot vmess >/dev/null 2>&1 &&
       ! protocol_array_contains vmess ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(vmess)
    fi
    if plain_proxy_inactive_store_snapshot vless-plain >/dev/null 2>&1 &&
       ! protocol_array_contains vless-plain ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(vless-plain)
    fi
    if plain_proxy_inactive_store_snapshot anytls >/dev/null 2>&1 &&
       ! protocol_array_contains anytls ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(anytls)
    fi
    if plain_proxy_inactive_store_snapshot hy2 >/dev/null 2>&1 &&
       ! protocol_array_contains hy2 ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(hy2)
    fi
    if plain_proxy_inactive_store_snapshot snell >/dev/null 2>&1 &&
       ! protocol_array_contains snell ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(snell)
    fi
    if plain_proxy_inactive_store_snapshot tuic >/dev/null 2>&1 &&
       ! protocol_array_contains tuic ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(tuic)
    fi
    if plain_proxy_inactive_store_snapshot hysteria >/dev/null 2>&1 &&
       ! protocol_array_contains hysteria ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(hysteria)
    fi
    if plain_proxy_inactive_store_snapshot naive >/dev/null 2>&1 &&
       ! protocol_array_contains naive ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(naive)
    fi
    if plain_proxy_inactive_store_snapshot shadowtls >/dev/null 2>&1 &&
       ! protocol_array_contains shadowtls ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      installed_protocols+=(shadowtls)
    fi
    if [[ -n "${preselected_protocols}" ]]; then
      SELECTED_PROTOCOLS_CSV=${preselected_protocols}
    else
      prompt_protocol_install_selection "additional" "${installed_protocol_list}" || return 0
    fi
    IFS=',' read -r -a selected_protocols <<< "${SELECTED_PROTOCOLS_CSV}"

    # An already-installed Mixed protocol must enter the instance lifecycle
    # before the old transaction takes a snapshot.  Mixed combined with a
    # different protocol is rejected here because the legacy save path cannot
    # safely publish a JSON inventory in the same transaction.
    if protocol_array_contains "mixed" ${installed_protocols[@]+"${installed_protocols[@]}"} &&
       protocol_array_contains "mixed" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        mixed_instance_create_interactive || return $?
        return 0
      fi
      log_warn "Mixed 实例不能与其他新增协议合并操作；请先单独管理 Mixed 实例。"
      return 0
    fi
    if protocol_array_contains "socks" ${installed_protocols[@]+"${installed_protocols[@]}"} &&
       protocol_array_contains "socks" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        socks_instance_management_menu create || return $?
        return 0
      fi
      log_warn "SOCKS 实例不能与其他新增协议合并操作；请先单独管理 SOCKS 实例。"
      return 0
    fi
    # HTTP is always a standalone typed-instance operation in the additional
    # flow, including its first install.  This prevents the legacy save path
    # from flattening the HTTP TLS/plain record into an env singleton.
    if protocol_array_contains "http" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        http_instance_management_menu create || return $?
        return 0
      fi
      log_warn "HTTP 实例不能与其他新增协议合并操作；请先单独管理 HTTP 实例。"
      return 0
    fi
    if protocol_array_contains "shadowsocks" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        shadowsocks_instance_management_menu create || return $?
        return 0
      fi
      log_warn "Shadowsocks 实例不能与其他新增协议合并操作；请先单独管理 Shadowsocks 实例。"
      return 0
    fi
    if protocol_array_contains "trojan" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        trojan_instance_management_menu create || return $?
        return 0
      fi
      log_warn "Trojan 实例不能与其他新增协议合并操作；请先单独管理 Trojan 实例。"
      return 0
    fi
    if protocol_array_contains "vmess" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        vmess_instance_management_menu create || return $?
        return 0
      fi
      log_warn "VMess 实例不能与其他新增协议合并操作；请先单独管理 VMess 实例。"
      return 0
    fi
    if protocol_array_contains "vless-plain" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        vless_plain_instance_management_menu create || return $?
        return 0
      fi
      log_warn "VLESS 实例不能与其他新增协议合并操作；请先单独管理 VLESS 实例。"
      return 0
    fi
    if protocol_array_contains "anytls" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        anytls_instance_management_menu create || return $?
        return 0
      fi
      log_warn "AnyTLS 实例不能与其他新增协议合并操作；请先单独管理 AnyTLS 实例。"
      return 0
    fi
    if protocol_array_contains "hy2" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        hy2_instance_management_menu create || return $?
        return 0
      fi
      log_warn "Hysteria2 实例不能与其他新增协议合并操作；请先单独管理 Hysteria2 实例。"
      return 0
    fi
    if protocol_array_contains "snell" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        snell_instance_management_menu create || return $?
        return 0
      fi
      log_warn "Snell 实例不能与其他新增协议合并操作；请先单独管理 Snell 实例。"
      return 0
    fi
    if protocol_array_contains "tuic" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        tuic_instance_management_menu create || return $?
        return 0
      fi
      log_warn "TUIC 实例不能与其他新增协议合并操作；请先单独管理 TUIC 实例。"
      return 0
    fi
    if protocol_array_contains "hysteria" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        hysteria_instance_management_menu create || return $?
        return 0
      fi
      log_warn "Hysteria 实例不能与其他新增协议合并操作；请先单独管理 Hysteria 实例。"
      return 0
    fi
    if protocol_array_contains "naive" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        naive_instance_management_menu create || return $?
        return 0
      fi
      log_warn "NaiveProxy 实例不能与其他新增协议合并操作；请先单独管理 NaiveProxy 实例。"
      return 0
    fi
    if protocol_array_contains "shadowtls" "${selected_protocols[@]}"; then
      if [[ ${#selected_protocols[@]} -eq 1 ]]; then
        shadowtls_instance_management_menu create || return $?
        return 0
      fi
      log_warn "ShadowTLS 实例不能与其他新增协议合并操作；请先单独管理 ShadowTLS 实例。"
      return 0
    fi
    snapshot_dir=$(create_managed_state_snapshot) || {
      log_error "无法创建配置状态事务快照。"
      return 1
    }

    if ! ensure_existing_generated_config_baseline; then
      abort_managed_state_transaction "${snapshot_dir}" "新增协议前的生成基线无法建立"
      return 1
    fi

    for protocol in "${selected_protocols[@]}"; do
      if [[ "${protocol}" == "vless-reality" ]] && protocol_array_contains "${protocol}" ${installed_protocols[@]+"${installed_protocols[@]}"}; then
        if ! prompt_vless_reality_instance_create; then
          abort_managed_state_transaction "${snapshot_dir}" "REALITY 实例配置失败"
          return 1
        fi
      else
        if ! prompt_protocol_install_fields "${protocol}" || ! save_protocol_state "${protocol}"; then
          abort_managed_state_transaction "${snapshot_dir}" "协议 ${protocol} 配置或状态保存失败"
          return 1
        fi
      fi
      if ! protocol_array_contains "${protocol}" ${installed_protocols[@]+"${installed_protocols[@]}"}; then
        installed_protocols+=("${protocol}")
      fi
    done

    if ! write_protocol_index "$(IFS=,; printf '%s' "${installed_protocols[*]}")"; then
      abort_managed_state_transaction "${snapshot_dir}" "协议索引保存失败"
      return 1
    fi
  fi

  if ! generate_config; then
    abort_managed_state_transaction "${snapshot_dir}" "配置生成或校验失败"
    return 1
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "安装配置已提交，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
  if protocol_array_contains "vless-reality" "${selected_protocols[@]}"; then
    refresh_vless_reality_qos_rules
  fi
  setup_service
  first_selected_protocol="${selected_protocols[0]}"
  if [[ -n "${first_selected_protocol:-}" ]]; then
    load_protocol_state "${first_selected_protocol}"
  fi
  open_committed_protocol_ports || return $?
  run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box
  log_info "连接信息未自动展示，如需查看请进入菜单 11。"
}
