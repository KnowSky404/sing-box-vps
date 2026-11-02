
# --- Config Generator ---
publish_managed_config_candidate() (
  local source_file=${1:-} candidate="" backup_candidate=""
  umask 077
  [[ -f "${source_file}" && ! -L "${source_file}" && -x "${SINGBOX_BIN_PATH}" ]] || return 1
  candidate=$(mktemp "${SINGBOX_CONFIG_DIR}/.config.json.candidate.XXXXXX") || return $?
  trap 'rm -f -- "${candidate}" "${backup_candidate}"' EXIT
  head -c 4194305 -- "${source_file}" > "${candidate}" || return $?
  [[ "$(wc -c < "${candidate}")" -le 4194304 ]] || return 1
  jq -es 'length == 1 and (.[0] | type == "object")' "${candidate}" >/dev/null 2>&1 || return 1
  validate_managed_component_graph "${candidate}" || return $?
  validate_managed_listener_resources "${candidate}" || return $?
  "${SINGBOX_BIN_PATH}" check -c "${candidate}" >&2 || return $?
  chmod 600 "${candidate}" || return $?
  if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
    backup_candidate=$(mktemp "${SINGBOX_CONFIG_DIR}/.config.json.backup.XXXXXX") || return $?
    cp -p "${SINGBOX_CONFIG_FILE}" "${backup_candidate}" || return $?
    chmod 600 "${backup_candidate}" || return $?
    mv -f "${backup_candidate}" "${SINGBOX_CONFIG_FILE}.bak" || return $?
  fi
  mv -f "${candidate}" "${SINGBOX_CONFIG_FILE}" || return $?
)

generate_config_candidate() {
  local inventory_state_file=${1:-}
  local allow_empty_protocols=${2:-false}
  local inbound_file="" provider_file="" protocol_rule_file="" instance_outbound_rule_file=""
  local config_candidate="" backup_candidate="" generated_candidate="" baseline_file="${SB_PROJECT_DIR}/managed-config.generated.json" protocol
  local exit_cleanup_command effective_protocols
  local inbounds_json certificate_providers_json protocol_rules_json instance_outbound_rules_json
  local managed_components_json managed_route_options_json existing_default_http_client=""
  local legacy_advanced_route=${SB_ADVANCED_ROUTE}
  local routing_policy_active=n routing_policy_json='{}' routing_policy_rendered='{}' routing_policy_tags='[]' routing_policy_file

  # Force ensure jq is installed
  if ! command -v jq &>/dev/null; then
    log_warn "未检测到 jq，正在尝试自动安装以确保配置生成安全..."
    get_os_info && install_dependencies
  fi

  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    log_warn "无法生成配置：缺少可执行的 sing-box 二进制 ${SINGBOX_BIN_PATH}。"
    return 1
  fi

  routing_policy_file=$(routing_policy_file_path) || return 1
  if [[ -e "${routing_policy_file}" || -L "${routing_policy_file}" ]]; then
    routing_policy_json=$(routing_policy_read_json) || {
      printf '[ERROR] 路由策略状态无效；配置未生成。\n' >&2
      return 1
    }
    routing_policy_active=y
  fi

  # A matching live rule is not ownership evidence. For existing installs
  # without explicit policy state, only a trusted generated record may carry
  # the old global private-address restriction into a new ownership baseline.
  # Consult the retained baseline even if recovery must recreate a missing live
  # config. Otherwise preserve unproven live rules as operator content in merge.
  if [[ "${routing_policy_active}" != y &&
        ( -f "${SINGBOX_CONFIG_FILE}" || -e "${baseline_file}" || -L "${baseline_file}" ) ]]; then
    legacy_advanced_route=n
    if [[ -e "${baseline_file}" || -L "${baseline_file}" ]]; then
      [[ -f "${baseline_file}" && ! -L "${baseline_file}" &&
         "$(stat -c %a "${baseline_file}")" == 600 ]] || return 1
      jq -e 'type == "object" and (.inbounds | type == "array")' \
        "${baseline_file}" >/dev/null || return 1
      if jq -e 'any(.route.rules[]?; . == {ip_is_private:true,action:"reject"})' \
        "${baseline_file}" >/dev/null; then
        legacy_advanced_route=y
      fi
    fi
  fi

  # Inspect the complete live inventory before discovery or resource creation.
  # A supported first inbound is not evidence that the rest can be rebuilt.
  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" "${inventory_state_file}" || return 1

  # Capture discovery before resource preparation; process substitution hides
  # its failure status and could otherwise publish an empty/partial config.
  case "${allow_empty_protocols}" in
    true)
      # Only the installer may seed the old generated baseline after the
      # final managed protocol was removed. Unmanaged live content remains
      # outside that baseline and is preserved by the normal merge.
      instance_management_empty_config_baseline || return 1
      effective_protocols=""
      ;;
    false)
      effective_protocols=$(list_effective_protocols "${inventory_state_file}") || return 1
      [[ -n "${effective_protocols}" ]] || return 1
      ;;
    *) return 1 ;;
  esac
  managed_components_json=$(managed_component_render_json) || {
    log_warn "高级组件状态无效，禁止生成可能丢失组件的配置。"
    return 1
  }
  managed_route_options_json=$(managed_component_tun_route_options_json "${managed_components_json}") || return 1
  if [[ -e "${SINGBOX_CONFIG_FILE}" ]]; then
    existing_default_http_client=$(jq -r '.route.default_http_client // empty' \
      "${SINGBOX_CONFIG_FILE}") || return 1
  fi

  log_info "正在生成配置 (目标 sing-box $(resolve_config_target_singbox_version)，Endpoint 架构 & 安全注入)..."
  mkdir -p "${SINGBOX_CONFIG_DIR}" || return 1
  load_warp_route_settings || return 1

  # Endpoints Logic
  local warp_endpoint='null' enable_warp_endpoint
  enable_warp_endpoint="${SB_ENABLE_WARP}"
  if [[ "${enable_warp_endpoint}" != "y" ]] && instance_outbound_requires_warp "${inventory_state_file}"; then
    enable_warp_endpoint="y"
  fi
  if [[ "${enable_warp_endpoint}" != "y" && "${routing_policy_active}" == y ]] &&
     routing_policy_requires_warp "${routing_policy_json}"; then
    enable_warp_endpoint="y"
  fi

  if [[ "${enable_warp_endpoint}" == "y" ]]; then
    warp_endpoint=$(warp_endpoint_json_for_generation) || {
      printf '[ERROR] WARP 凭据缺失或无效；请通过网络设置恢复 WARP，节点操作未注册或更改账户。\n' >&2
      return 1
    }
  fi

  refresh_warp_route_assets || return 1
  ensure_stack_mode_state_loaded || return 1

  inbound_file=$(mktemp) || return 1
  if ! provider_file=$(mktemp); then
    rm -f "${inbound_file}"
    return 1
  fi
  if ! protocol_rule_file=$(mktemp); then
    rm -f "${inbound_file}" "${provider_file}"
    return 1
  fi
  if ! instance_outbound_rule_file=$(mktemp); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}"
    return 1
  fi
  if ! config_candidate=$(mktemp "${SINGBOX_CONFIG_DIR}/.config.json.candidate.XXXXXX"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}"
    return 1
  fi
  printf -v exit_cleanup_command 'rm -f -- %q %q %q %q %q' \
    "${inbound_file}" "${provider_file}" "${protocol_rule_file}" \
    "${instance_outbound_rule_file}" "${config_candidate}"
  trap "${exit_cleanup_command}" EXIT

  while IFS= read -r protocol; do
    [[ -z "${protocol}" ]] && continue
    if ! load_protocol_state "${protocol}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! append_protocol_fragment "${protocol}" inbound "${inbound_file}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! append_protocol_fragment "${protocol}" certificate "${provider_file}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if ! append_protocol_fragment "${protocol}" route "${protocol_rule_file}"; then
      rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
      return 1
    fi
    if [[ "${protocol}" == "vless-reality" ]]; then
      if ! build_vless_reality_instance_outbound_rules_json >> "${instance_outbound_rule_file}"; then
        rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
        return 1
      fi
    fi
  done <<< "${effective_protocols}"

  if ! inbounds_json=$(jq -s . "${inbound_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! certificate_providers_json=$(jq -s . "${provider_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! protocol_rules_json=$(jq -s 'add // []' "${protocol_rule_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi
  if ! instance_outbound_rules_json=$(jq -s 'add // []' "${instance_outbound_rule_file}"); then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  if ! jq -n \
    --arg adv_route "${legacy_advanced_route}" \
    --arg enable_warp "${SB_ENABLE_WARP}" \
    --arg enable_warp_endpoint "${enable_warp_endpoint}" \
    --arg warp_mode "${SB_WARP_ROUTE_MODE}" \
    --argjson warp_endpoint "${warp_endpoint}" \
    --arg outbound_stack_mode "${SB_OUTBOUND_STACK_MODE}" \
    --arg default_http_client "${existing_default_http_client}" \
    --argjson inbounds "${inbounds_json}" \
    --argjson managed_components "${managed_components_json}" \
    --argjson certificate_providers "${certificate_providers_json}" \
    --argjson protocol_rules "${protocol_rules_json}" \
    --argjson instance_outbound_rules "${instance_outbound_rules_json}" \
    --argjson managed_route_options "${managed_route_options_json}" \
    --argjson ai_domains "${WARP_AI_ROUTE_DOMAINS_JSON}" \
    --argjson ai_domain_suffixes "${WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON}" \
    --argjson stream_domains "${WARP_STREAM_ROUTE_DOMAINS_JSON}" \
    --argjson stream_domain_suffixes "${WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON}" \
    --argjson custom_domains "${SB_WARP_CUSTOM_DOMAINS_JSON}" \
    --argjson custom_domain_suffixes "${SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON}" \
    --argjson local_rule_sets "${SB_WARP_LOCAL_RULE_SETS_JSON}" \
    --argjson remote_rule_sets "${SB_WARP_REMOTE_RULE_SETS_JSON}" \
    --argjson warp_rule_set_tags "${SB_WARP_RULE_SET_TAGS_JSON}" \
    '{
      "log": { "level": "info", "timestamp": true },
      "dns": {
        "servers": [
          {
            "type": "local",
            "tag": "local-dns"
          }
        ],
        "strategy": $outbound_stack_mode
      },
      "endpoints": ((if $enable_warp_endpoint == "y" then [$warp_endpoint] else [] end) +
        ($managed_components.endpoints // [])),
      "inbounds": ($inbounds + ($managed_components.inbounds // [])),
      "outbounds": ([
        {
          "type": "direct",
          "tag": "direct",
          "domain_resolver": {
            "server": "local-dns",
            "strategy": $outbound_stack_mode
          }
        },
        { "type": "block", "tag": "block" }
      ] + ($managed_components.outbounds // [])),
      "route": ({
        "rule_set": (
          ($managed_components.rule_sets // []) +
          (if $enable_warp == "y" and $warp_mode == "selective" then
             $local_rule_sets + $remote_rule_sets
           else
             []
           end)
        ),
        "rules": (
          ($managed_components.route_rules // []) +
          $instance_outbound_rules +
          $protocol_rules +
          (if $adv_route == "y" then [ { "ip_is_private": true, "action": "reject" } ] else [] end) +
          (
            if $enable_warp == "y" and $warp_mode == "selective" then
              [
                {
                  "domain": $ai_domains,
                  "domain_suffix": $ai_domain_suffixes,
                  "action": "route",
                  "outbound": "warp-ep"
                },
                {
                  "domain": $stream_domains,
                  "domain_suffix": $stream_domain_suffixes,
                  "action": "route",
                  "outbound": "warp-ep"
                }
              ] +
              (
                if ($custom_domains | length) > 0 or ($custom_domain_suffixes | length) > 0 then
                  [
                    {
                      "domain": $custom_domains,
                      "domain_suffix": $custom_domain_suffixes,
                      "action": "route",
                      "outbound": "warp-ep"
                    }
                  ]
                else
                  []
                end
              ) +
              (
                if ($warp_rule_set_tags | length) > 0 then
                  [
                    {
                      "rule_set": $warp_rule_set_tags,
                      "action": "route",
                      "outbound": "warp-ep"
                    }
                  ]
                else
                  []
                end
              )
            else
              []
            end
          )
        ),
        "final": (if $enable_warp == "y" and $warp_mode == "all" then "warp-ep" else "direct" end)
      } + $managed_route_options +
      (if $default_http_client == "" then {} else
        {"default_http_client": $default_http_client}
       end))
    } + (
      if (($managed_components.network_namespaces // []) | length) > 0 then
        { "network_namespaces": ($managed_components.network_namespaces // []) }
      else
        {}
      end
    ) + (
      if (($certificate_providers | length) + (($managed_components.certificate_providers // []) | length)) > 0 then
        { "certificate_providers": ($certificate_providers + ($managed_components.certificate_providers // [])) }
      else
        {}
      end
    ) + (
      if (($managed_components.http_clients // []) | length) > 0 then
        { "http_clients": ($managed_components.http_clients // []) }
      else
        {}
      end
    ) + (
      if (($managed_components.services // []) | length) > 0 then
        { "services": ($managed_components.services // []) }
      else
        {}
      end
    )' > "${config_candidate}"; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  generated_candidate=$(mktemp "${SINGBOX_CONFIG_DIR}/.generated-config.XXXXXX") || return 1
  trap "${exit_cleanup_command}; rm -f -- \"${generated_candidate}\"" EXIT
  if [[ "${routing_policy_active}" == y ]]; then
    # Only protocol-generated traffic tags participate. Component/manual
    # listeners and the outer ShadowTLS handshake keep their existing scope.
    routing_policy_tags=$(jq -c '[.[] | select(.type != "shadowtls") | .tag] | unique' <<< "${inbounds_json}") || return 1
    routing_policy_rendered=$(routing_policy_render_server_json "${routing_policy_json}" "${routing_policy_tags}") || return 1
    jq --argjson policy "${routing_policy_json}" --argjson rendered "${routing_policy_rendered}" \
      --argjson tags "${routing_policy_tags}" --argjson components "${managed_components_json}" \
      --argjson protocols "${protocol_rules_json}" --argjson instance_rules "${instance_outbound_rules_json}" \
      --arg enable_warp "${SB_ENABLE_WARP}" --arg warp_mode "${SB_WARP_ROUTE_MODE}" \
      --argjson ai_domains "${WARP_AI_ROUTE_DOMAINS_JSON}" --argjson ai_suffixes "${WARP_AI_ROUTE_DOMAIN_SUFFIXES_JSON}" \
      --argjson media_domains "${WARP_STREAM_ROUTE_DOMAINS_JSON}" --argjson media_suffixes "${WARP_STREAM_ROUTE_DOMAIN_SUFFIXES_JSON}" \
      --argjson custom_domains "${SB_WARP_CUSTOM_DOMAINS_JSON}" --argjson custom_suffixes "${SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON}" \
      --argjson warp_sets "${SB_WARP_RULE_SET_TAGS_JSON}" '
      def fixed: .action == "route" and (.inbound | type) == "string" and
        (keys | sort) == ["action","inbound","outbound"];
      .route.rule_set += $rendered.rule_sets |
      .route.rules = (($components.route_rules // []) +
        [$tags[] | {inbound:.,action:"sniff"}] + $rendered.protection_rules +
        (($instance_rules + [$protocols[] | select(fixed)]) | sort_by(.inbound)) +
        [$protocols[] | select(.action != "sniff" and (fixed | not))] +
        $rendered.custom_rules +
        (if $enable_warp == "y" and $warp_mode == "selective" and ($tags | length) > 0 then
           (if ($custom_domains | length) > 0 or ($custom_suffixes | length) > 0 then
              [{inbound:$tags,domain:$custom_domains,domain_suffix:$custom_suffixes,action:"route",outbound:"warp-ep"}]
            else [] end) +
           (if ($warp_sets | length) > 0 then
              [{inbound:$tags,rule_set:$warp_sets,action:"route",outbound:"warp-ep"}]
            else [] end) +
           (if $policy.server.warp_ai then
              [{inbound:$tags,domain:$ai_domains,domain_suffix:$ai_suffixes,action:"route",outbound:"warp-ep"}]
            else [] end) +
           (if $policy.server.warp_streaming then
              [{inbound:$tags,domain:$media_domains,domain_suffix:$media_suffixes,action:"route",outbound:"warp-ep"}]
            else [] end)
         else [] end))
      ' "${config_candidate}" > "${generated_candidate}" || return 1
    cp -- "${generated_candidate}" "${config_candidate}" || return 1
  else
    cp -- "${config_candidate}" "${generated_candidate}" || return 1
  fi
  chmod 600 "${generated_candidate}" || return 1
  if [[ -e "${SINGBOX_CONFIG_FILE}" ]]; then
    if ! merge_generated_config_with_live "${generated_candidate}" "${SINGBOX_CONFIG_FILE}" "${baseline_file}" > "${config_candidate}"; then
      printf '[ERROR] 配置归属冲突或生成基线无效；配置未发布，请先检查手工修改与托管字段。\n' >&2
      return 1
    fi
  fi
  if [[ "${routing_policy_active}" == y ]] &&
     [[ -e "${SINGBOX_CONFIG_FILE}" ]]; then
    # The fragment file is no longer needed after assembly; reuse its private
    # staging path without ever writing the merged file while reading it.
    routing_policy_place_new_generated_rules "${generated_candidate}" "${config_candidate}" \
      "${baseline_file}" "${SINGBOX_CONFIG_FILE}" "${routing_policy_tags}" > "${inbound_file}" || return 1
    cp -- "${inbound_file}" "${config_candidate}" || return 1
  fi
  if [[ "${routing_policy_active}" == y ]]; then
    routing_policy_validate_merged_order "${generated_candidate}" "${config_candidate}" "${routing_policy_tags}" || return 1
  fi

  if ! publish_managed_config_candidate "${config_candidate}"; then
    rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
    return 1
  fi

  if [[ -f "${baseline_file}" ]]; then
    persist_file_backup "${baseline_file}" "${baseline_file}.bak" || return 1
  fi
  mv -f -- "${generated_candidate}" "${baseline_file}" || return 1
  rm -f "${inbound_file}" "${provider_file}" "${protocol_rule_file}" "${instance_outbound_rule_file}" "${config_candidate}"
  trap - EXIT
}

ensure_existing_generated_config_baseline() {
  # Legacy removals need the old owned tags before changing any state. A
  # regular generation safely preserves extensions and records that baseline.
  [[ -f "${SINGBOX_CONFIG_FILE}" && ! -e "${SB_PROJECT_DIR}/managed-config.generated.json" ]] || return 0
  if instance_management_empty_config_baseline; then
    run_with_progress "建立空协议配置的生成基线（校验及备份）" generate_config "" true
  else
    run_with_progress "建立现有配置的生成基线（校验及备份）" generate_config
  fi
}

generate_config() {
  local inventory_state_file=${1:-} allow_empty_protocols=${2:-false} snapshot_dir

  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" "${inventory_state_file}" || return 1
  snapshot_dir=$(create_managed_state_snapshot) || return 1
  if ! (generate_config_candidate "${inventory_state_file}" "${allow_empty_protocols}"); then
    rollback_managed_state_snapshot "${snapshot_dir}" || true
    return 1
  fi
  if ! discard_managed_state_snapshot "${snapshot_dir}"; then
    log_warn "配置已发布，但临时事务快照未能删除: ${snapshot_dir}。"
  fi
}

# --- Uninstaller ---
managed_uninstall_report_error() {
  local message=${1:-}
  printf '%b[ERROR]%b %s\n' "${RED}" "${NC}" "${message}" >&2
}

managed_uninstall_routing_previous_is_safe() {
  [[ "${SB_ROUTING_PREVIOUS_DIR}" == "${SB_PROJECT_DIR}.rules-previous" ]] || return 1
  if [[ -e "${SB_ROUTING_PREVIOUS_DIR}" || -L "${SB_ROUTING_PREVIOUS_DIR}" ]]; then
    if ! routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}" ||
       [[ "$(jq -r '.phase' "${SB_ROUTING_PREVIOUS_DIR}/transaction.json")" != committed ]]; then
      managed_uninstall_report_error '上次规则恢复快照不可信，未开始卸载；请保留现场并先检查该目录。'
      return 1
    fi
  fi
}

managed_uninstall_remove_project_state() {
  managed_uninstall_routing_previous_is_safe || return 1
  if ! rm -rf -- "${SB_PROJECT_DIR}" || [[ -e "${SB_PROJECT_DIR}" || -L "${SB_PROJECT_DIR}" ]]; then
    managed_uninstall_report_error '项目配置删除无法确认，规则恢复快照已保留。'
    return 1
  fi
  if [[ -e "${SB_ROUTING_PREVIOUS_DIR}" || -L "${SB_ROUTING_PREVIOUS_DIR}" ]]; then
    managed_uninstall_routing_previous_is_safe || return 1
    if ! rm -rf -- "${SB_ROUTING_PREVIOUS_DIR}" ||
       [[ -e "${SB_ROUTING_PREVIOUS_DIR}" || -L "${SB_ROUTING_PREVIOUS_DIR}" ]]; then
      managed_uninstall_report_error '项目配置已删除，但上次规则恢复快照清理失败；请保留现场。'
      return 1
    fi
  fi
}

managed_uninstall_acquire_guard() {
  acquire_managed_write_lock || {
    managed_uninstall_report_error "另一个管理事务正在执行，未开始卸载。"
    return 1
  }
  if [[ -e "${SB_COMPONENT_TRANSACTION_DIR}" || -L "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
    managed_uninstall_report_error "存在未完成的高级组件事务，未开始卸载；请先执行 component recover。"
    return 1
  fi
  if [[ -e "${SB_PROJECT_DIR}.instance-write.lock" || -L "${SB_PROJECT_DIR}.instance-write.lock" ]]; then
    managed_uninstall_report_error "存在未完成的实例事务，未开始卸载；请先恢复或检查该事务。"
    return 1
  fi
  managed_uninstall_routing_previous_is_safe || return 1
  return 0
}

perform_singbox_runtime_uninstall() {
  local lib_path expected_hash actual_hash component_state redirect_policy_plan tproxy_policy_plan

  managed_uninstall_acquire_guard || return 1
  component_state=$(managed_component_state_json) || {
    managed_uninstall_report_error "高级组件 state 无法安全读取，未开始卸载；请先检查 ${SB_COMPONENT_STATE_FILE}。"
    return 1
  }
  redirect_policy_plan=$(managed_component_redirect_host_policy_plan_json "${component_state}") || {
    managed_uninstall_report_error "Redirect 主机策略计划无法安全读取，未开始卸载。"
    return 1
  }
  if ! managed_component_redirect_policy_uninstall "${redirect_policy_plan}"; then
    managed_uninstall_report_error "Redirect 主机策略清理无法确认；服务、二进制和配置目录未改动，已清理的精确受管规则可能是部分状态，请先运行组件诊断。"
    return 1
  fi
  tproxy_policy_plan=$(managed_component_tproxy_host_policy_plan_json "${component_state}") || {
    managed_uninstall_report_error "TProxy 主机策略计划无法安全读取，未开始卸载。"
    return 1
  }
  if ! managed_component_tproxy_policy_uninstall "${tproxy_policy_plan}"; then
    managed_uninstall_report_error "TProxy 主机策略清理无法确认；服务、二进制和配置目录未改动，已清理的精确受管规则可能是部分状态，请先运行组件诊断。"
    return 1
  fi
  log_info "正在彻底卸载 sing-box 环境..."
  if command -v tc >/dev/null 2>&1; then
    clear_vless_reality_qos_rules
  fi
  systemctl stop sing-box &>/dev/null || true
  systemctl disable sing-box &>/dev/null || true
  rm -f "${SINGBOX_SERVICE_FILE}"
  systemctl daemon-reload
  rm -f "${SINGBOX_BIN_PATH}"
  lib_path=$(singbox_library_path || printf '')
  if [[ -n "${lib_path}" && -f "${SB_NAIVE_LIBRARY_MARKER}" ]]; then
    expected_hash=$(tr -d '[:space:]' < "${SB_NAIVE_LIBRARY_MARKER}")
    actual_hash=''
    if [[ -f "${lib_path}" && ! -L "${lib_path}" ]]; then
      actual_hash=$(sha256sum "${lib_path}" | awk '{print $1}')
    fi
    if [[ -n "${expected_hash}" && "${expected_hash}" == "${actual_hash}" ]]; then
      rm -f "${lib_path}"
      if [[ "$(dirname "${lib_path}")" == "/usr/local/lib" ]] &&
         command -v ldconfig >/dev/null 2>&1; then
        ldconfig || log_warn "libcronet.so 已删除，但 ldconfig 缓存刷新失败。"
      fi
    else
      log_warn "检测到 libcronet.so 已被外部修改，保留 ${lib_path} 以避免误删。"
    fi
  fi
  managed_uninstall_remove_project_state || return 1
  print_success "sing-box 服务、二进制和配置目录已彻底删除。"
}

perform_full_uninstall() {
  managed_uninstall_acquire_guard || return 1
  perform_singbox_runtime_uninstall || return 1
  rm -f "${SBV_BIN_PATH}"
  print_success "全局命令 sbv 已删除。"
}

uninstall_singbox() {
  echo ""
  print_warn "该操作会彻底删除 sing-box 服务、配置目录和密钥，但会保留全局命令 sbv。"
  read -rp "确认继续吗？[y/N]: " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "已取消卸载。"
    return 0
  fi

  perform_singbox_runtime_uninstall || return 1
  exit 0
}

# Uninstall script itself
uninstall_script() {
  local deleted_cfg="n"
  managed_uninstall_acquire_guard || return 1
  read -rp "是否同时删除项目配置文件目录 (/root/sing-box-vps)? [y/N]: " del_cfg
  if [[ "${del_cfg}" =~ ^[Yy]$ ]]; then
    local component_state redirect_policy_plan tproxy_policy_plan
    component_state=$(managed_component_state_json) || {
      managed_uninstall_report_error "高级组件 state 无法安全读取，未删除项目目录。"
      return 1
    }
    redirect_policy_plan=$(managed_component_redirect_host_policy_plan_json "${component_state}") || {
      managed_uninstall_report_error "Redirect 主机策略计划无法安全读取，未删除项目目录。"
      return 1
    }
    if ! managed_component_redirect_policy_uninstall "${redirect_policy_plan}"; then
      managed_uninstall_report_error "Redirect 主机策略清理无法确认，未删除项目目录。"
      return 1
    fi
    tproxy_policy_plan=$(managed_component_tproxy_host_policy_plan_json "${component_state}") || {
      managed_uninstall_report_error "TProxy 主机策略计划无法安全读取，未删除项目目录。"
      return 1
    }
    if ! managed_component_tproxy_policy_uninstall "${tproxy_policy_plan}"; then
      managed_uninstall_report_error "TProxy 主机策略清理无法确认，未删除项目目录。"
      return 1
    fi
    managed_uninstall_remove_project_state || return 1
    deleted_cfg="y"
    print_info "配置文件目录已删除。"
  fi
  
  if [[ "${deleted_cfg}" == "y" ]]; then
    print_info "正在删除全局命令 sbv..."
  else
    log_info "正在删除全局命令 sbv..."
  fi
  rm -f "${SBV_BIN_PATH}"
  if [[ "${deleted_cfg}" == "y" ]]; then
    print_success "管理脚本已卸载。"
  else
    log_success "管理脚本已卸载。"
  fi
  exit 0
}
