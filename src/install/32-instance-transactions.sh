
mixed_inactive_store_snapshot() {
  plain_proxy_inactive_store_snapshot mixed "$@"
}

plain_proxy_inactive_store_snapshot() {
  local protocol=$1
  local snapshot
  [[ ! -e "$(protocol_state_file "${protocol}")" ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json "${protocol}" "$(plain_proxy_structured_store_file "${protocol}")") || return $?
  jq -e '.instances==[] and .default_instance_id=="" and .revision>0' <<< "${snapshot}" >/dev/null || return 1
  printf '%s\n' "${snapshot}"
}

plain_proxy_instance_config_candidate() {
  local protocol=$1 old_config=$2 old_store=$3 new_store=$4 inbounds rules
  inbounds=$(render_structured_instance_inbounds "${protocol}" "${new_store}" | jq -s '.') || return $?
  rules=$(render_structured_instance_route_rules "${protocol}" "${new_store}") || return $?
  jq --arg protocol "${protocol}" --slurpfile old "${old_store}" --argjson added "${inbounds}" --argjson rules "${rules}" '
    def protocol_id:
      if $protocol == "shadowtls" and .type == "mixed" and ((.tag // "") | startswith("shadowtls-inner-")) then
        "shadowtls"
      elif .type == "vless" then
        (if .tls.reality? != null then "vless-reality" else "vless-plain" end)
      elif .type == "hysteria2" then "hy2"
      else .type end;
    ($old[0].instances | map(.tag) + (if $protocol == "shadowtls" then map(.detour.tag) else [] end)) as $old_tags |
    (any(.inbounds[]?; .type == "hysteria2" and .tls.certificate_provider? == "hy2-cert-provider")) as $had_legacy_hy2_provider |
    def owned_rule:
      (.inbound | type) == "string" and (.inbound as $tag | $old_tags | index($tag) != null) and
      ((.action == "sniff" and (keys | sort) == ["action","inbound"]) or
       (.action == "route" and (.outbound == "direct" or .outbound == "warp-ep") and
        (keys | sort) == ["action","inbound","outbound"]));
    (.inbounds // []) as $previous |
    ([$previous | to_entries[] | select(.value.tag as $tag | $old_tags | index($tag) != null) | .key][0] // ($previous|length)) as $at |
    .inbounds = ($previous[:$at] + $added + [$previous[$at:][] | select(.tag as $tag | $old_tags | index($tag) == null)]) |
    (.route.rules // []) as $prior_rules |
    ([$prior_rules[] | select(owned_rule) | [.inbound,.action]] | unique) as $positioned |
    # Keep existing managed rules in place: moving a direct/Warp rule ahead
    # of a custom reject or routing condition would change existing traffic.
    (reduce $prior_rules[] as $rule ({seen:[],rules:[]};
      if ($rule | owned_rule) then
        if (.seen | index([[$rule.inbound,$rule.action]])) != null then .
        else .seen += [[$rule.inbound,$rule.action]] |
          .rules += [$rules[] | select(.inbound == $rule.inbound and .action == $rule.action)] end
      else .rules += [$rule] end)) as $retained |
    # A missing sniff rule is observational and must run before retained
    # custom rules. A missing route rule is a fallback; append it after the
    # retained rules so a conditional/reject rule keeps its precedence.
    .route.rules = (
      [$rules[] | select(.action == "sniff") |
        select([.inbound,.action] as $key | $positioned | index([$key]) == null)]
      + $retained.rules
      + [$rules[] | select(.action == "route") |
        select([.inbound,.action] as $key | $positioned | index([$key]) == null)]
    ) |
    # Remove only the generator-owned legacy provider after all references
    # have gone. Shared component providers and other protocols stay intact.
    if $protocol == "hy2" and $had_legacy_hy2_provider and
       ([.. | objects | .certificate_provider? | select(. == "hy2-cert-provider")] | length) == 0 then
      .certificate_providers |= map(select(.tag != "hy2-cert-provider" or .type != "acme"))
    else . end
  ' "${old_config}"
}

# Deleting the final HY2 instance does not regenerate a surviving managed
# listener. Permit its address to drift only when its owned tag/type still
# identify exactly one live inbound and every other modeled field matches.
# The comparison changes a private candidate, never the live configuration.
hy2_final_instance_delete_matches_config() {
  local store_file=$1 instance_id=$2 config_file=$3 comparison_file=$4
  if ! jq --slurpfile store "${store_file}" --arg id "${instance_id}" '
    $store[0] as $store |
    if ($store.instances | length) != 1 or $store.instances[0].id != $id then
      error("not final instance")
    else $store.instances[0] as $record |
      [.inbounds[]? | select(.tag == $record.tag)] as $targets |
      if ($targets | length) != 1 or $targets[0].type != "hysteria2" or
         ($targets[0].listen | type) != "string" then
        error("untrusted target")
      else .inbounds |= map(if .tag == $record.tag then
        .listen = $record.listen.address else . end)
      end
    end
  ' "${config_file}" > "${comparison_file}" 2>/dev/null; then
    return 1
  fi
  plain_proxy_structured_state_matches_config hy2 "${comparison_file}"
}

# Public mutation entrypoints share a kernel lock. The persistent instance
# journal is a separate crash-recovery barrier, not a substitute for this lock.
acquire_managed_write_lock() {
  local lock_file="${SB_PROJECT_DIR}.management.flock" descriptor_target lock_mode=${1:-exclusive}
  local lock_option=-x
  case "${lock_mode}" in exclusive) ;; shared) lock_option=-s ;; *) return 1 ;; esac
  command -v flock >/dev/null 2>&1 || {
    printf '[ERROR] 写操作需要系统 flock 工具。\n' >&2; return 1;
  }
  [[ ! -L "${lock_file}" ]] || return 1
  if [[ "${SB_MANAGEMENT_LOCK_FD:-}" =~ ^[0-9]+$ ]]; then
    descriptor_target=$(readlink "/proc/${BASHPID:-$$}/fd/${SB_MANAGEMENT_LOCK_FD}") || return 1
    [[ "${descriptor_target}" == "${lock_file}" ]] || return 1
    if [[ "${lock_mode}" == shared && "${SB_MANAGEMENT_LOCK_MODE:-}" == exclusive ]]; then
      return 0
    fi
  else
    (umask 077; touch -- "${lock_file}") || return $?
    exec {SB_MANAGEMENT_LOCK_FD}>"${lock_file}" || return $?
  fi
  flock -n "${lock_option}" "${SB_MANAGEMENT_LOCK_FD}" || {
    printf '[ERROR] 另一个管理进程正在执行；本次未修改。\n' >&2; return 1;
  }
  SB_MANAGEMENT_LOCK_MODE=${lock_mode}
}

instance_transaction_checkpoint() {
  local lock_dir=$1 phase=$2
  jq --arg phase "${phase}" '.phase=$phase' "${lock_dir}/transaction.json" > "${lock_dir}/transaction.next" || return $?
  mv -f "${lock_dir}/transaction.next" "${lock_dir}/transaction.json" || return $?
  case "${phase}" in
    snapshot) printf '[INFO] 实例事务：备份当前配置及状态。\n' >&2 ;;
    publish) printf '[INFO] 实例事务：发布已校验的配置。\n' >&2 ;;
    resources) printf '[INFO] 实例事务：同步受管监听及防火墙规则。\n' >&2 ;;
    service) printf '[INFO] 实例事务：检查服务；ACME 签发可能需要较长时间。\n' >&2 ;;
    committed) printf '[SUCCESS] 实例事务：提交完成。\n' >&2 ;;
  esac
}

instance_transaction_restore() {
  local lock_dir=$1 before_active status=0
  before_active=$(jq -r '.before_active' "${lock_dir}/transaction.json") || return $?
  # Restore only owned external effects; never infer firewall recovery from a
  # directory restore. Keep the persistent journal if either half fails.
  if [[ -f "${lock_dir}/firewall.json" ]]; then
    instance_firewall_rollback "${lock_dir}/firewall.json" || status=1
  else
    printf '[ERROR] 防火墙事务日志缺失；无法证明外部状态已恢复。\n' >&2
    status=1
  fi
  if [[ -f "${lock_dir}/snapshot/snapshot.meta" ]]; then
    if ! restore_managed_state_snapshot "${lock_dir}/snapshot"; then
      printf '[ERROR] 状态快照恢复失败；未启动可能不一致的配置，请保留事务目录人工恢复。\n' >&2
      return 1
    fi
    if [[ "${before_active}" == true ]]; then
      if run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box >/dev/null && systemctl is-active --quiet sing-box; then :; else status=1; fi
    else
      if systemctl stop sing-box >/dev/null 2>&1 && singbox_service_confirmed_stopped; then :; else status=1; fi
    fi
  else
    printf '[ERROR] 事务恢复快照缺失；未报告回滚成功。\n' >&2
    return 1
  fi
  return "${status}"
}

instance_transaction_firewall_summary() {
  local journal_file=$1 summary
  if [[ -f "${journal_file}" && ! -L "${journal_file}" ]] && summary=$(jq -ce '
    def backend: IN("ufw","firewalld","iptables","ip6tables");
    def code: IN("backend_unavailable","backend_external_managed","backend_conflict",
      "backend_inspection_failed","backend_mutation_failed","backend_mutation_unconfirmed","owned_backend_unavailable",
      "owned_rule_inspection_failed","owned_rule_missing","rule_inspection_failed","firewalld_owned_unsupported",
      "firewalld_requires_manual_setup","invalid_old_plan","invalid_new_plan",
      "invalid_old_targets","invalid_new_targets","invalid_ledger","invalid_candidates",
      "ledger_persist_failed","ledger_restore_failed","compensation_failed","external_state_uncertain");
    select(type == "object") | . as $journal |
    {status:(if (.status | IN("prepared","applying","applied","committed","prepare_failed",
       "apply_failed","rolling_back","rolled_back","rollback_failed","rollback_uncertain"))
       then .status else "unavailable" end),
     backends:[.backend_statuses[]? | select(.backend | backend) |
       {backend, state:(if (.state | IN("available","unavailable","external-managed")) then .state else "unavailable" end)}],
     diagnostics:[.diagnostics[]? |
       {code:(if (.code | code) then .code else "firewall_diagnostic_unrecognized" end),
        severity:(if .severity == "error" then "error" else "warning" end),
        backend:(if (.backend | backend) then .backend else "unavailable" end)}]}
    + (if $journal.error_code == null then {} else
       {error_code:(if ($journal.error_code | code) then $journal.error_code else "firewall_diagnostic_unrecognized" end)} end)
  ' "${journal_file}" 2>/dev/null); then
    printf '%s\n' "${summary}"
  else
    printf '%s\n' '{"status":"unavailable","backends":[],"diagnostics":[]}'
  fi
}

instance_transaction_report() {
  local state=$1 phase=$2 code=$3 changed=$4 manual=$5 revision=${6:-0}
  local report_protocol=${SB_INSTANCE_TRANSACTION_PROTOCOL:-mixed}
  local firewall_summary='{"status":"not_attempted","backends":[],"diagnostics":[]}'
  [[ $# -le 6 ]] || firewall_summary=$7
  jq -n --arg protocol "${report_protocol}" --arg state "${state}" --arg phase "${phase}" --arg code "${code}" \
    --argjson changed "${changed}" --argjson manual "${manual}" --argjson revision "${revision}" \
    --argjson firewall "${firewall_summary}" '
    {ok:($code==""),action:"instance",protocol:$protocol,changed:$changed,revision:$revision,
     transaction:{status:$state,phase:$phase,manual_intervention_required:$manual,firewall:$firewall}}
    + (if $code=="" then {} else {error:$code,message:"实例操作未成功；检查 transaction 状态，必要时执行 instance recover。"} end)'
}

instance_transaction_persist_result() (
  local payload=$1 directory="${SB_PROJECT_DIR}.instance-transactions" result
  umask 077
  [[ ! -L "${directory}" ]] || return 1
  mkdir -p "${directory}" && chmod 700 "${directory}" || return $?
  result=$(mktemp "${directory}/result-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX.json") || return $?
  if ! instance_transaction_update_result "${result}" "${payload}"; then
    rm -f -- "${result}" || return 1
    return 1
  fi
  printf '%s' "${result}"
)

instance_transaction_update_result() (
  local result=$1 payload=$2 stage
  [[ "${result}" == "${SB_PROJECT_DIR}.instance-transactions/"result-*.json &&
     -f "${result}" && ! -L "${result}" ]] || return 1
  umask 077
  stage=$(mktemp "${result}.candidate.XXXXXX") || return $?
  trap 'rm -f -- "${stage}"' EXIT
  jq --arg path "${result}" \
    '.transaction.result_path=$path | .transaction.result_persisted=true' \
    <<< "${payload}" > "${stage}" || return $?
  mv -f -- "${stage}" "${result}"
)

recover_mixed_instance_transaction() {
  recover_plain_proxy_instance_transaction mixed "$@"
}

recover_plain_proxy_instance_transaction() (
  local SB_INSTANCE_TRANSACTION_PROTOCOL=$1
  local expected_revision=$2 lock_dir="${SB_PROJECT_DIR}.instance-write.lock"
  local phase owner_pid owner_start current_start="" result revision recovery_fd recovery_entries result_path firewall_summary
  structured_instance_store_protocol "${SB_INSTANCE_TRANSACTION_PROTOCOL}" >/dev/null || return 1
  [[ ${EUID} -eq 0 ]] || { agent_json_error root_required "恢复必须以 root 执行。"; return 1; }
  acquire_managed_write_lock || {
    agent_json_error instance_write_busy "另一个管理进程正在执行；未开始恢复。"; return 1;
  }
  if [[ -e "${SB_COMPONENT_TRANSACTION_DIR}" || -L "${SB_COMPONENT_TRANSACTION_DIR}" ]]; then
    agent_json_error component_transaction_pending "存在未完成的高级组件事务；请先完成 component recover。未开始实例恢复。"
    return 1
  fi
  [[ -d "${lock_dir}" && ! -L "${lock_dir}" ]] || {
    agent_json_error instance_recovery_unavailable "未找到可验证的待恢复实例事务；未自动删除任何文件。"; return 1;
  }
  if [[ ! -e "${lock_dir}/transaction.json" ]]; then
    # The shared kernel lock proves that no writer is still preparing this
    # directory. Before atomic journal publication, only transaction.next can
    # exist and no state/resource mutation is permitted. Anything else is an
    # ambiguous damaged transaction and must remain for manual inspection.
    recovery_entries=$(find "${lock_dir}" -mindepth 1 -maxdepth 1 -printf '%f\n') || return $?
    if [[ -n "${recovery_entries}" && "${recovery_entries}" != transaction.next ]] ||
       [[ -e "${lock_dir}/transaction.next" && (! -f "${lock_dir}/transaction.next" || -L "${lock_dir}/transaction.next") ]]; then
      agent_json_error instance_recovery_untrusted "主日志缺失且发现已准备材料；无法证明未发生变更，已保留目录。"; return 1
    fi
    result=$(instance_transaction_report unchanged prepare '' false false "${expected_revision}") || return $?
    result_path=$(instance_transaction_persist_result "${result}") || return $?
    rm -rf -- "${lock_dir}" || return $?
    jq --arg path "${result_path}" '.transaction.result_path=$path | .transaction.result_persisted=true' <<< "${result}"
    return 0
  fi
  [[ -f "${lock_dir}/transaction.json" && ! -L "${lock_dir}/transaction.json" ]] || {
    agent_json_error instance_recovery_untrusted "事务主日志不是可信普通文件；未修改。"; return 1;
  }
  jq -e --arg revision "${expected_revision}" --arg protocol "${SB_INSTANCE_TRANSACTION_PROTOCOL}" '
    .schema_version==1 and (if has("protocol") then .protocol else "mixed" end)==$protocol and (.owner_pid|type=="number" and floor==. and .>0) and
    (.owner_start|type=="string" and test("^[0-9]+$")) and
    (.before_active|type=="boolean") and .expected_revision==$revision and
    (.phase=="prepare" or .phase=="snapshot" or .phase=="publish" or .phase=="resources" or .phase=="service" or .phase=="committed")
  ' "${lock_dir}/transaction.json" >/dev/null 2>&1 || {
    agent_json_error instance_recovery_untrusted "事务日志无法验证或 revision 不匹配；请保留文件并人工检查。"; return 1;
  }
  owner_pid=$(jq -r .owner_pid "${lock_dir}/transaction.json") || return $?
  owner_start=$(jq -r .owner_start "${lock_dir}/transaction.json") || return $?
  if [[ -r "/proc/${owner_pid}/stat" ]]; then
    current_start=$(awk '{print $22}' "/proc/${owner_pid}/stat") || return $?
    if [[ "${current_start}" == "${owner_start}" ]]; then
      agent_json_error instance_transaction_active "原实例写进程仍在运行；禁止并发恢复。"; return 1
    fi
  fi
  # A kernel lock is released on uncatchable interruption; the durable write
  # journal itself stays in place until recovery has actually succeeded.
  command -v flock >/dev/null 2>&1 && [[ ! -L "${lock_dir}/recovery.flock" ]] || {
    agent_json_error instance_recovery_unavailable "恢复需要 flock 且锁文件必须可信。"; return 1;
  }
  exec {recovery_fd}>"${lock_dir}/recovery.flock" || return $?
  flock -n "${recovery_fd}" || {
    agent_json_error instance_recovery_active "另一个恢复进程已取得恢复锁。"; return 1;
  }
  phase=$(jq -r .phase "${lock_dir}/transaction.json") || return $?
  revision=$(jq -r '.new_revision // .expected_revision | tonumber' "${lock_dir}/transaction.json") || return $?
  firewall_summary=$(instance_transaction_firewall_summary "${lock_dir}/firewall.json")
  case "${phase}" in
    publish|resources|service)
      if ! instance_transaction_restore "${lock_dir}"; then
        firewall_summary=$(instance_transaction_firewall_summary "${lock_dir}/firewall.json")
        result=$(instance_transaction_report rollback_failed "${phase}" instance_rollback_failed false true "${expected_revision}" "${firewall_summary}") || return $?
        if result_path=$(instance_transaction_persist_result "${result}"); then
          jq --arg path "${result_path}" '.transaction.result_path=$path | .transaction.result_persisted=true' <<< "${result}"
        else
          jq '.transaction.result_path="" | .transaction.result_persisted=false |
            .transaction.audit_error="instance_audit_failed"' <<< "${result}"
        fi
        return 1
      fi
      firewall_summary=$(instance_transaction_firewall_summary "${lock_dir}/firewall.json")
      result=$(instance_transaction_report rolled_back "${phase}" '' false false "${expected_revision}" "${firewall_summary}") || return $?
      ;;
    committed) result=$(instance_transaction_report committed "${phase}" '' true false "${revision}" "${firewall_summary}") || return $? ;;
    *) result=$(instance_transaction_report unchanged "${phase}" '' false false "${expected_revision}" "${firewall_summary}") || return $? ;;
  esac
  result_path=$(instance_transaction_persist_result "${result}") || return $?
  rm -rf -- "${lock_dir}" || return $?
  jq --arg path "${result_path}" '.transaction.result_path=$path | .transaction.result_persisted=true' <<< "${result}"
)

apply_mixed_instance_change() {
  apply_plain_proxy_instance_change mixed "$@"
}

apply_plain_proxy_instance_change() (
  local instance_protocol=$1 operation=$2 expected_revision=$3 input=$4 allow_public=${5:-n}
  local SB_INSTANCE_TRANSACTION_PROTOCOL=${instance_protocol}
  local lock_dir="${SB_PROJECT_DIR}.instance-write.lock" touched=n completed=n noop=n
  local phase=prepare revision=0 before_active=false current_revision=0 schema count indexed protocol
  local owner_pid=${BASHPID:-$$} owner_start snapshot_file result_status
  local protocols=() inbound_json
  umask 077
  structured_instance_store_protocol "${instance_protocol}" >/dev/null || return 1
  [[ "${operation}" != migrate || "${instance_protocol}" == mixed ]] || return 1
  [[ ${EUID} -eq 0 ]] || { agent_json_error root_required "实例写操作必须以 root 执行。"; return 1; }
  acquire_managed_write_lock || {
    agent_json_error instance_write_busy "另一个管理进程正在执行；未修改。"; return 1;
  }
  [[ ${EUID} -eq 0 && -x "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_CONFIG_FILE}" &&
     ! -L "${SB_PROJECT_DIR}" && ! -L "${SB_PROTOCOL_STATE_DIR}" ]] || {
    agent_json_error instance_precheck_failed "需要现有受管配置、可执行核心和 root 权限。"; return 1;
  }
  validate_protocol_index_for_rebuild >&2 && validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" >&2 || {
    agent_json_error protocol_state_untrusted "现有配置或协议索引无法完整读取；未修改。"; return 1;
  }
  if ! mkdir -m 700 "${lock_dir}" 2>/dev/null; then
    agent_json_error instance_transaction_pending "已有实例写事务或未完成恢复；请先检查并使用 instance recover。"
    return 1
  fi
  instance_transaction_finish() {
    local operation_status=$1 state=success code="" manual=false cleanup_status=0 result result_path="" firewall_summary
    trap - EXIT INT TERM HUP
    if [[ "${operation_status}" != 0 ]]; then
      code=instance_apply_failed
      if [[ "${touched}" == y ]]; then
        if instance_transaction_restore "${lock_dir}"; then state=rolled_back; revision=${current_revision}; else
          state=rollback_failed; code=instance_rollback_failed; manual=true
        fi
      else
        state=unchanged
      fi
    elif [[ "${noop}" == y ]]; then
      state=not_attempted
    fi
    if [[ "${noop}" == y ]]; then
      firewall_summary='{"status":"not_attempted","backends":[],"diagnostics":[]}'
    else
      firewall_summary=$(instance_transaction_firewall_summary "${lock_dir}/firewall.json")
    fi
    result=$(instance_transaction_report "${state}" "${phase}" "${code}" \
      "$([[ "${completed}" == y ]] && printf true || printf false)" "${manual}" "${revision}" "${firewall_summary}" |
      jq --argjson status "${operation_status}" '.transaction.operation_exit_code=$status')
    if [[ "${touched}" == y ]]; then
      if result_path=$(instance_transaction_persist_result "${result}"); then :; else
        cleanup_status=1; manual=true; code=instance_audit_failed
      fi
    fi
    if [[ "${manual}" == false ]]; then
      if ! rm -rf -- "${lock_dir}"; then
        cleanup_status=1
        state=cleanup_failed; code=instance_cleanup_failed; manual=true
      fi
    fi
    [[ "${operation_status}" == 0 && "${cleanup_status}" != 0 ]] && operation_status=1
    result=$(instance_transaction_report "${state}" "${phase}" "${code}" \
      "$([[ "${completed}" == y ]] && printf true || printf false)" "${manual}" "${revision}" "${firewall_summary}" |
      jq --arg path "${result_path}" --argjson exit_code "${operation_status}" \
      '.transaction.result_path=$path | .transaction.result_persisted=($path!="") | .transaction.operation_exit_code=$exit_code')
    if [[ -n "${result_path}" ]] && ! instance_transaction_update_result "${result_path}" "${result}"; then
      operation_status=1
      result=$(jq '.ok=false | .error="instance_audit_failed" |
        .transaction.result_persisted=false | .transaction.manual_intervention_required=true |
        .transaction.operation_exit_code=1' <<< "${result}")
    fi
    printf '%s\n' "${result}"
    exit "${operation_status}"
  }
  trap 'instance_transaction_finish "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  owner_start=$(awk '{print $22}' "/proc/${owner_pid}/stat") || return $?
  case "$(systemctl show -p ActiveState --value sing-box)" in
    active) before_active=true ;;
    inactive|failed) before_active=false ;;
    *) return 1 ;;
  esac
  jq -n --arg protocol "${instance_protocol}" --arg operation "${operation}" --arg expected "${expected_revision}" --argjson pid "${owner_pid}" --arg start "${owner_start}" \
    --argjson before "${before_active}" \
    '{schema_version:1,protocol:$protocol,operation:$operation,expected_revision:$expected,owner_pid:$pid,owner_start:$start,before_active:$before,phase:"prepare"}' \
    > "${lock_dir}/transaction.next" || return $?
  mv -f -- "${lock_dir}/transaction.next" "${lock_dir}/transaction.json" || return $?
  if [[ "${operation}" == takeover ]] && plain_proxy_structured_state_active "${instance_protocol}"; then
    # Takeover is only for a live protocol that has not already been adopted
    # into the typed store.  Reusing an active store would silently replace
    # stable IDs/metadata and defeat the explicit CAS boundary.
    return 1
  fi
  if plain_proxy_structured_state_active "${instance_protocol}"; then
    structured_instance_store_snapshot_json "${instance_protocol}" "$(plain_proxy_structured_store_file "${instance_protocol}")" > "${lock_dir}/before.json" || return $?
    current_revision=$(jq -r .revision "${lock_dir}/before.json") || return $?
    # Rebuild intentionally repairs drift in the managed protocol projection;
    # final HY2 deletion may remove an owned listener whose address drifted.
    # All other mutations require the live config to match before preparation.
    if [[ "${operation}" != rebuild ]]; then
      if ! plain_proxy_structured_state_matches_config "${instance_protocol}" >/dev/null 2>&1; then
        if [[ "${instance_protocol}" != hy2 || "${operation}" != delete ]] ||
           ! hy2_final_instance_delete_matches_config "${lock_dir}/before.json" "${input}" \
             "${SINGBOX_CONFIG_FILE}" "${lock_dir}/delete-comparison.json"; then
          printf '[ERROR] 实例状态与运行配置不一致；未修改，请先检查受管配置漂移。\n' >&2
          return 1
        fi
      fi
    fi
  elif [[ "${operation}" == takeover ]]; then
    # A takeover starts from a virtual revision-zero store and imports the
    # complete, losslessly representable live inventory.  Existing typed
    # artifacts are never overwritten by this path: an orphan or malformed
    # store requires explicit recovery instead of an identity reset.
    local takeover_store_file takeover_state_file takeover_count
    takeover_store_file=$(plain_proxy_structured_store_file "${instance_protocol}") || return $?
    takeover_state_file=$(protocol_state_file "${instance_protocol}") || return $?
    [[ ! -e "${takeover_store_file}" && ! -L "${takeover_store_file}" ]] || return 1
    if plain_proxy_structured_marker_is_valid "${takeover_state_file}"; then
      return 1
    fi
    if ! takeover_count=$(config_protocol_inbound_count "${instance_protocol}" "${SINGBOX_CONFIG_FILE}"); then
      return 1
    fi
    [[ "${takeover_count}" =~ ^[0-9]+$ && "${takeover_count}" -gt 0 ]] || return 1
    structured_instance_store_empty_json "${instance_protocol}" > "${lock_dir}/before.json" || return $?
    current_revision=0
  elif protocol_state_exists "${instance_protocol}"; then
    if [[ "${instance_protocol}" == mixed ]]; then
      [[ ! -e "$(mixed_structured_store_file)" ]] || return 1
      mixed_config_store_candidate | jq '.revision=0' > "${lock_dir}/before.json" || return $?
    elif [[ "${instance_protocol}" == anytls ]]; then
      [[ ! -e "$(plain_proxy_structured_store_file anytls)" ]] || return 1
      plain_proxy_config_store_candidate anytls | jq '.revision=0' > "${lock_dir}/before.json" || return $?
    elif [[ "${instance_protocol}" == hy2 ]]; then
      [[ ! -e "$(plain_proxy_structured_store_file hy2)" ]] || return 1
      plain_proxy_config_store_candidate hy2 | jq '.revision=0' > "${lock_dir}/before.json" || return $?
    elif [[ "${instance_protocol}" == shadowtls ]]; then
      [[ ! -e "$(plain_proxy_structured_store_file shadowtls)" ]] || return 1
      plain_proxy_config_store_candidate shadowtls "${SINGBOX_CONFIG_FILE}" | jq '.revision=0' > "${lock_dir}/before.json" || return $?
    else
      return 1
    fi
  else
    [[ "${operation}" != migrate ]] || return 1
    if [[ "${instance_protocol}" == shadowtls ]] &&
       [[ "$(config_protocol_inbound_count shadowtls "${SINGBOX_CONFIG_FILE}" 2>/dev/null || printf 0)" -gt 0 ]]; then
      [[ ! -e "$(plain_proxy_structured_store_file shadowtls)" ]] || return 1
      plain_proxy_config_store_candidate shadowtls "${SINGBOX_CONFIG_FILE}" | jq '.revision=0' > "${lock_dir}/before.json" || return $?
      current_revision=0
    elif [[ "$(config_protocol_inbound_count "${instance_protocol}" "${SINGBOX_CONFIG_FILE}" 2>/dev/null || printf 0)" == "0" ]]; then
      if [[ -e "$(plain_proxy_structured_store_file "${instance_protocol}")" ]]; then
        plain_proxy_inactive_store_snapshot "${instance_protocol}" > "${lock_dir}/before.json" || return $?
        current_revision=$(jq -r .revision "${lock_dir}/before.json") || return $?
      else
        structured_instance_store_empty_json "${instance_protocol}" > "${lock_dir}/before.json" || return $?
      fi
    else
      return 1
    fi
  fi
  [[ "${expected_revision}" == "${current_revision}" ]] || return 1
  if [[ "${operation}" == migrate ]]; then
    if plain_proxy_structured_state_active "${instance_protocol}"; then
      revision=${current_revision}; noop=y; return 0
    fi
    jq '.revision=1' "${lock_dir}/before.json" > "${lock_dir}/after.json" || return $?
  elif [[ "${operation}" == rebuild ]]; then
    [[ "${current_revision}" -lt 9007199254740991 ]] || return 1
    jq --argjson revision "$((current_revision + 1))" '.revision=$revision' \
      "${lock_dir}/before.json" > "${lock_dir}/after.json" || return $?
  elif [[ "${operation}" == takeover ]]; then
    plain_proxy_config_store_candidate "${instance_protocol}" "${SINGBOX_CONFIG_FILE}" > "${lock_dir}/after.json" || return $?
    if [[ "${allow_public}" != y ]]; then
      jq -e 'all(.instances[]; .listen.address == "::1" or (.listen.address | test("^127\\.")))' \
        "${lock_dir}/after.json" >/dev/null 2>&1 || return 1
    fi
  else
    if [[ "${operation}" == create || "${operation}" == replace ]]; then
      [[ -f "${input}" && ! -L "${input}" ]] || return 1
      head -c 1048577 -- "${input}" > "${lock_dir}/record.json" || return $?
      [[ "$(wc -c < "${lock_dir}/record.json")" -le 1048576 ]] || return 1
      # New non-loopback exposure requires a distinct acknowledgement. Legacy
      # migration alone retains its existing listener without changing it.
      if [[ "${allow_public}" != y ]]; then
        jq -es 'length==1 and (.[0].listen.address | .=="::1" or test("^127\\."))' "${lock_dir}/record.json" >/dev/null 2>&1 || return 1
      fi
      input="${lock_dir}/record.json"
    fi
    structured_instance_store_candidate "${instance_protocol}" "${lock_dir}/before.json" "${operation}" "${input}" \
      "${current_revision}" > "${lock_dir}/after.json" || return $?
  fi
  validate_structured_instance_store "${instance_protocol}" "${lock_dir}/after.json" || return $?
  revision=$(jq -r .revision "${lock_dir}/after.json") || return $?
  if [[ "${revision}" == "${current_revision}" ]]; then noop=y; return 0; fi
  jq --argjson revision "${revision}" '.new_revision=$revision' "${lock_dir}/transaction.json" > "${lock_dir}/transaction.next" || return $?
  mv -f "${lock_dir}/transaction.next" "${lock_dir}/transaction.json" || return $?
  if [[ "${operation}" == takeover ]]; then
    # Import never rewrites the live configuration.  The collector above has
    # already rejected lossy fields; keeping the byte-identical candidate
    # makes takeover an auditable state adoption rather than a regeneration.
    cp -p -- "${SINGBOX_CONFIG_FILE}" "${lock_dir}/config.json" || return $?
    [[ "$(stat -c %s "${lock_dir}/config.json")" -le 4194304 ]] || return 1
  else
    plain_proxy_instance_config_candidate "${instance_protocol}" "${SINGBOX_CONFIG_FILE}" "${lock_dir}/before.json" "${lock_dir}/after.json" \
      > "${lock_dir}/config.json" || return $?
  fi
  validate_managed_component_graph "${lock_dir}/config.json" || return $?
  validate_managed_listener_resources "${lock_dir}/config.json" || return $?
  "${SINGBOX_BIN_PATH}" check -c "${lock_dir}/config.json" >&2 || return $?
  local firewall_tags
  firewall_tags=$(jq -cs '[.[].instances[] | .tag, (.detour.tag? // empty)] | unique' "${lock_dir}/before.json" "${lock_dir}/after.json") || return $?
  instance_firewall_prepare "${SINGBOX_CONFIG_FILE}" "${lock_dir}/config.json" "${lock_dir}/firewall.json" "${firewall_tags}" || return $?
  phase=snapshot
  instance_transaction_checkpoint "${lock_dir}" "${phase}" || return $?
  snapshot_file=$(create_managed_state_snapshot "${lock_dir}/snapshot") || return $?
  phase=publish
  instance_transaction_checkpoint "${lock_dir}" "${phase}" || return $?
  touched=y
  count=$(jq -r '.instances|length' "${lock_dir}/after.json") || return $?
  if [[ "${count}" == 0 ]]; then
    # Preserve the empty, revisioned store as a tombstone. Recreating Mixed
    # must not reset CAS to zero and revive an older request (ABA).
    publish_structured_instance_store "${instance_protocol}" "${lock_dir}/after.json" "${current_revision}" legacy-empty-activation || return $?
    persist_file_backup "$(protocol_state_file "${instance_protocol}")" "$(protocol_state_file "${instance_protocol}").bak" || return $?
    rm -f -- "$(protocol_state_file "${instance_protocol}")" || return $?
  else
    publish_structured_instance_store "${instance_protocol}" "${lock_dir}/after.json" "${current_revision}" \
      "$([[ "${operation}" == rebuild ]] && printf rebuild || printf '')" || return $?
    save_plain_proxy_structured_marker "${instance_protocol}" || return $?
  fi
  # Match the live config's protocol ordering, retaining every non-Mixed role.
  # `vless` is shared by REALITY and plain VLESS, so classify each inbound
  # through the config-aware adapter instead of normalizing the raw core type.
  protocols=()
  while IFS= read -r inbound_json; do
    [[ -n "${inbound_json}" ]] || continue
    if jq -e '.type | IN("direct","tun","redirect","tproxy","cloudflared")' \
      <<< "${inbound_json}" >/dev/null 2>&1; then
      # Advanced component inbounds have their own state and do not belong in
      # the share-link protocol index.
      continue
    fi
    if manual_client_inbound_is_unmanaged "${inbound_json}"; then continue; fi
    protocol=$(config_inbound_protocol "${inbound_json}") || return 1
    if ! protocol_array_contains "${protocol}" ${protocols[@]+"${protocols[@]}"}; then
      protocols+=("${protocol}")
    fi
  done < <(jq -c '.inbounds[]?' "${lock_dir}/config.json")
  indexed=$(IFS=,; printf '%s' "${protocols[*]-}")
  write_protocol_index "${indexed}" || return $?
  publish_managed_config_candidate "${lock_dir}/config.json" || return $?
  cmp -s -- "${lock_dir}/config.json" "${SINGBOX_CONFIG_FILE}" || return 1
  if [[ "${count}" != 0 ]]; then
    plain_proxy_structured_state_matches_config "${instance_protocol}" || return 1
  fi
  phase=resources
  instance_transaction_checkpoint "${lock_dir}" "${phase}" || return $?
  instance_firewall_apply "${lock_dir}/firewall.json" || return $?
  phase=service
  instance_transaction_checkpoint "${lock_dir}" "${phase}" || return $?
  if [[ "${before_active}" == true ]]; then
    run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box >/dev/null || return $?
    systemctl is-active --quiet sing-box || return $?
  fi
  phase=committed
  instance_transaction_checkpoint "${lock_dir}" "${phase}" || return $?
  completed=y
  return 0
)
