
agent_print_help() {
  command_catalog_print_help
}

agent_require_json_flag() {
  if [[ "${1:-}" != "--json" ]]; then
    agent_json_error "json_required" "agent 子命令当前仅支持 --json 输出。"
    return 1
  fi
}

agent_json_error() {
  local error=$1
  local message=$2

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg error "${error}" \
    --arg message "${message}" \
    '{schema: $schema, ok: false, error: $error, message: $message}'
}

agent_emit_json_envelope() {
  local command=$1
  local status=$2
  local payload=${3:-}
  local timestamp
  local command_ok=false
  local payload_ok
  local effective_ok=false

  [[ "${status}" == "0" ]] && command_ok=true
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  if [[ -z "${payload}" ]] || ! jq -s -e 'length == 1 and (.[0] | type == "object")' \
    >/dev/null 2>&1 <<< "${payload}"; then
    jq -n \
      --arg schema_version "1.0" \
      --arg command "${command}" \
      --arg timestamp "${timestamp}" \
      '{
        schema: "1",
        schema_version: $schema_version,
        command: $command,
        timestamp: $timestamp,
        ok: false,
        data: {},
        error: "internal_error",
        message: "agent 命令未生成有效 JSON 对象。"
      }'
    [[ "${status}" == "0" ]] && return 1
    return "${status}"
  fi

  payload_ok=$(jq -r 'if (.ok | type) == "boolean" then .ok else empty end' <<< "${payload}")
  if [[ "${command_ok}" == "true" && "${payload_ok:-true}" == "true" ]]; then
    effective_ok=true
  fi

  # Keep the complete payload on stdin instead of passing it as one argv
  # element. Linux caps a single argument at MAX_ARG_STRLEN (128 KiB), while
  # capability/diagnostic envelopes can legitimately exceed that size.
  if ! jq -n \
    --arg schema_version "1.0" \
    --arg command "${command}" \
    --arg timestamp "${timestamp}" \
    --argjson effective_ok "${effective_ok}" \
    --slurpfile payload /dev/stdin \
    '($payload[0]) as $payload_object |
      $payload_object + {
        schema: "1",
        schema_version: $schema_version,
        command: $command,
        timestamp: $timestamp,
        ok: $effective_ok,
        data: $payload_object
      }' <<< "${payload}"; then
    return 1
  fi
  [[ "${effective_ok}" == "true" ]] && return 0
  return 1
}

agent_cli_run() {
  local command=$1
  shift
  local payload status
  # Structured agent stdout must contain exactly one JSON object.  Keep the
  # human-readable progress log available on stderr while the command runs so
  # generators cannot corrupt the envelope captured below.
  local SB_AGENT_JSON_MODE=y

  if payload=$("$@"); then
    status=0
  else
    status=$?
  fi
  agent_emit_json_envelope "${command}" "${status}" "${payload}"
  return $?
}

agent_cli_error() {
  local command=$1
  local error=$2
  local message=$3
  local payload

  payload=$(agent_json_error "${error}" "${message}")
  agent_emit_json_envelope "${command}" 1 "${payload}"
  return 1
}

agent_file_sha256() {
  local file=$1

  if [[ ! -f "${file}" ]]; then
    printf ''
    return 0
  fi

  sha256sum "${file}" | awk '{print $1}'
}

detect_existing_instance_state_read_only() {
  local has_bin="n"
  local has_service="n"
  local has_config="n"
  local has_index="n"
  local has_state="n"
  local state_file

  [[ -x "${SINGBOX_BIN_PATH}" ]] && has_bin="y"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && has_service="y"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && has_config="y"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && has_index="y"

  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
      [[ -e "${state_file}" ]] || continue
      [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] && continue
      has_state="y"
      break
    done
  fi

  if [[ "${has_bin}" == "n" && "${has_service}" == "n" && "${has_config}" == "n" && "${has_index}" == "n" && "${has_state}" == "n" ]]; then
    printf 'fresh'
    return 0
  fi

  if [[ "${has_bin}" == "y" && "${has_service}" == "y" && "${has_config}" == "y" && "${has_index}" == "y" && "${has_state}" == "y" ]] && \
    protocol_state_layer_matches_config true; then
    printf 'healthy'
    return 0
  fi

  printf 'incomplete'
}

agent_capabilities_json() {
  local registry components managed_registry catalog
  catalog=$(command_catalog_json) || return 1
  registry=$(protocol_registry_json) || return 1
  components=$(component_registry_json) || return 1
  managed_registry=$(jq -cn --argjson protocols "${registry}" --argjson components "${components}" '
    (($protocols | map(. + {registry_kind:"protocol"} | del(.legacy_capabilities,.handlers))) +
     ($components | map(. + {registry_kind:"component"}))) |
    sort_by(.role,.state_id,.type)
  ') || return 1
  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg script_version "${SCRIPT_VERSION}" \
    --arg default_listener "${SB_DEFAULT_LISTEN_ADDRESS}" \
    --arg supported_version "${SB_SUPPORT_MAX_VERSION}" \
    --arg backup_root "${SB_UPGRADE_BACKUP_ROOT}" \
    --arg component_state_file "${SB_COMPONENT_STATE_FILE}" \
    --arg component_transaction_dir "${SB_COMPONENT_TRANSACTION_DIR}" \
    --argjson registry "${registry}" \
    --argjson components "${components}" \
    --argjson managed_registry "${managed_registry}" \
    --slurpfile operation_catalog /dev/stdin \
    '{
      schema: $schema,
      ok: true,
      action: "capabilities",
      script_version: $script_version,
      operation_catalog: $operation_catalog[0],
      supported_sing_box_version: $supported_version,
      multi_protocol_coexistence: true,
      protocols: ($registry | map({key: .agent_id, value: .legacy_capabilities}) | from_entries),
      protocol_registry: ($registry | map(. + {capabilities: .legacy_capabilities} | del(.legacy_capabilities, .handlers))),
      managed_registry: {schema_version:1,entries:$managed_registry},
      features: {
        warp: {
          route_modes: ["all", "selective"],
          account_registration: true,
          custom_domains: true,
          local_rule_sets: true,
          remote_rule_sets: true
        },
        network_stack: {
          inbound: ["ipv4_only", "ipv6_only", "dual_stack"],
          outbound: ["ipv4_only", "ipv6_only", "prefer_ipv4", "prefer_ipv6"]
        },
        system: {bbr: true, firewall_port_management: true},
        connection_material: {links: true, ansi_qr: true},
        lifecycle: {
          service_start_stop_restart_status_logs: true,
          managed_instance_takeover_repair: true,
          core_upgrade_and_uninstall: true,
          script_self_update_and_uninstall: true
        },
        mixed_instances: {
          state_schema: 2,
          store_schema: 1,
          operations: ["create", "replace", "delete", "default", "rebuild", "takeover", "migrate", "recover"],
          read_only_operations: ["view", "diagnose", "export"],
          expected_revision_required: true,
          plaintext_public_confirmation: "--allow-public",
          default_new_listener: $default_listener,
          cross_protocol_bulk_delete: false,
          legacy_read_migration: false,
          firewall_ownership_ledger: true,
          firewall_managed_backends: ["ufw", "iptables", "ip6tables"],
          firewall_backend_policy: "single_frontend",
          firewalld: "external_rules_preflight_only",
          persistent_recovery_journal: true
        },
        plain_proxy_instances: {
          protocols: ["mixed", "socks", "http", "shadowsocks", "trojan", "vmess", "vless-plain", "anytls", "hy2", "snell", "tuic", "hysteria", "naive", "shadowtls"],
          legacy_migration_protocols: ["mixed"],
          state_schema: 2,
          store_schema: 1,
          operations: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
          read_only_operations: ["view", "diagnose", "export"],
          operations_by_protocol: {
            mixed: ["create", "replace", "delete", "default", "rebuild", "takeover", "migrate", "recover"],
            socks: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            http: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            shadowsocks: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            trojan: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            vmess: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            "vless-plain": ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            anytls: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            hy2: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            snell: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            tuic: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            hysteria: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            naive: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"],
            shadowtls: ["create", "replace", "delete", "default", "rebuild", "takeover", "recover"]
          },
          expected_revision_required: true,
          plaintext_public_confirmation: "--allow-public",
          default_new_listener: $default_listener,
          cross_protocol_bulk_delete: false
        },
        diagnostics: {config_check: true, doctor: true, media_check: true},
        subman: {supported_protocols: ($registry | map(select(.subman_type != "") | .agent_id)), idempotent_sync: true},
        components: {
          state_file: $component_state_file,
          schema_version: 1,
          operations: ["list", "diagnose", "export", "recover", "takeover", "rebuild", "create", "replace", "delete"],
          recovery_operations: ["recover"],
          read_only_operations: ["list", "diagnose", "export"],
          sensitive_operations: ["export"],
          diagnosis_fields: ["state", "config", "service", "firewall", "transactions", "transparent_resources", "redirect_host_policy"],
          expected_revision_required: true,
          plaintext_public_confirmation: "--allow-public",
          registry: $components,
          route_rules: true,
          reference_protection: true,
          service_restart_if_active: true,
          config_check: true,
          persistent_recovery_journal: true,
          transaction_directory: $component_transaction_dir
        }
      },
      commands: {
        capabilities: {mutation: false, sensitive: false},
        status: {mutation: false, sensitive: false},
        nodes: {mutation: false, sensitive: false},
        links: {mutation: false, sensitive: true},
        warp: {mutation: false, sensitive: false},
        check: {mutation: false, sensitive: false},
        doctor: {mutation: false, sensitive: false},
        "upgrade-check": {mutation: false, sensitive: false},
        upgrade: {mutation: true, sensitive: false, confirmation: "--yes", service_impact: "restart"},
        instance: {mutation: true, sensitive: false, confirmation: "--yes", service_impact: "restart_if_active", protocols: ["mixed", "socks", "http", "shadowsocks", "trojan", "vmess", "vless-plain", "anytls", "hy2", "snell", "tuic", "hysteria", "naive", "shadowtls"], read_only_operations: ["view", "diagnose", "export"], read_only_protocols: ["vless-reality", "mixed", "socks", "http", "shadowsocks", "trojan", "vmess", "vless-plain", "anytls", "hy2", "snell", "tuic", "hysteria", "naive", "shadowtls"]},
        component: {mutation: true, sensitive: true, confirmation: "--yes", service_impact: "restart_if_active", roles: ["inbound", "endpoint", "outbound", "certificate_provider", "http_client", "service", "network_namespace", "rule_set"]},
        "service restart": {mutation: true, sensitive: false, confirmation: "--yes"},
        "subman-sync": {mutation: true, sensitive: true, external_write: true}
      },
      interactive_features: {
        protocol_install_update_remove: true,
        managed_instance_takeover_repair: true,
        reality_multi_instance_and_qos: true,
        mixed_multi_instance_management: true,
        socks_multi_instance_management: true,
        http_multi_instance_management: true,
        shadowsocks_multi_instance_management: true,
        trojan_multi_instance_management: true,
        vmess_multi_instance_management: true,
        vless_plain_multi_instance_management: true,
        anytls_multi_instance_management: true,
        hy2_multi_instance_management: true,
        snell_multi_instance_management: true,
        tuic_multi_instance_management: true,
        hysteria_multi_instance_management: true,
        naive_multi_instance_management: true,
        shadowtls_multi_instance_management: true,
        warp_mutation: true,
        inbound_outbound_stack_management: true,
        bbr: true,
        media_check: true,
        service_start_stop_and_logs: true,
        script_self_update_and_uninstall: true,
        sing_box_uninstall: true
      },
      upgrade: {
        backup_root: $backup_root,
        manifest_scope: "all_regular_runtime_files_and_control_files",
        rewrites_server_config: false,
        target_binary_check_before_restart: true,
        automatic_binary_rollback_on_failure: true,
        restores_previous_service_activity: true
      }
    }' <<< "${catalog}"
}

agent_config_compatibility_json() {
  local target_version=$1
  local inline_acme_count=0
  local download_detour_count=0
  local certificate_provider_count=0
  local http_client_count=0
  local classification="neutral"
  local warnings_json='[]'
  local hy2_warnings_json='[]'
  local legacy_direct_count=0

  if [[ ! -f "${SINGBOX_CONFIG_FILE}" ]] || ! jq -e '.' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
    jq -n \
      --arg classification "unreadable" \
      '{
        schema: {classification: $classification, legacy: false, modern_1_14: false},
        legacy: {tls_acme_count: 0, download_detour_count: 0, direct_action_count: 0},
        modern: {certificate_provider_count: 0, http_client_count: 0},
        warnings: [{code: "config_json_unreadable", message: "配置文件不存在或不是有效 JSON。"}]
      }'
    return 0
  fi

  inline_acme_count=$(jq -r '[(.inbounds // [])[] | select(.tls.acme? != null)] | length' "${SINGBOX_CONFIG_FILE}")
  legacy_direct_count=$(singbox_legacy_direct_action_count) || return 1
  download_detour_count=$(jq -r '[(.route.rule_set // [])[] | select(.download_detour? != null)] | length' "${SINGBOX_CONFIG_FILE}")
  certificate_provider_count=$(jq -r '(.certificate_providers // []) | length' "${SINGBOX_CONFIG_FILE}")
  http_client_count=$(jq -r '
    (((.http_clients // []) | if type == "array" then length else 0 end) +
      ([(.route.rule_set // [])[] | select(.http_client? != null)] | length))
  ' "${SINGBOX_CONFIG_FILE}")

  if (( inline_acme_count > 0 || download_detour_count > 0 )); then
    classification="legacy_1_13"
  fi
  if (( certificate_provider_count > 0 || http_client_count > 0 )); then
    if [[ "${classification}" == "legacy_1_13" ]]; then
      classification="mixed"
    else
      classification="modern_1_14"
    fi
  fi

  if singbox_version_at_least "${target_version}" "${SB_CONFIG_SCHEMA_1_14_MIN_VERSION}"; then
    if (( inline_acme_count > 0 )); then
      warnings_json=$(jq -n --argjson warnings "${warnings_json}" '
        $warnings + [{
          code: "inline_acme_deprecated",
          message: "tls.acme 在 sing-box 1.14 中仍兼容但已弃用，计划在 1.16 移除。",
          removal_version: "1.16.0"
        }]')
    fi
    if (( download_detour_count > 0 )); then
      warnings_json=$(jq -n --argjson warnings "${warnings_json}" '
        $warnings + [{
          code: "download_detour_deprecated",
          message: "远程规则集 download_detour 在 sing-box 1.14 中仍兼容但已弃用，计划在 1.16 移除。",
          removal_version: "1.16.0"
        }]')
    fi
    hy2_warnings_json=$(collect_hy2_compatibility_warnings_json "share" 2>/dev/null || printf '[]')
    warnings_json=$(jq -n \
      --argjson warnings "${warnings_json}" \
      --argjson hy2_warnings "${hy2_warnings_json}" \
      '$warnings + $hy2_warnings')
  fi

  jq -n \
    --arg classification "${classification}" \
    --argjson legacy_direct_count "${legacy_direct_count}" \
    --argjson inline_acme_count "${inline_acme_count}" \
    --argjson download_detour_count "${download_detour_count}" \
    --argjson certificate_provider_count "${certificate_provider_count}" \
    --argjson http_client_count "${http_client_count}" \
    --argjson warnings "${warnings_json}" \
    '{
      schema: {
        classification: $classification,
        legacy: ($classification == "legacy_1_13" or $classification == "mixed"),
        modern_1_14: ($classification == "modern_1_14" or $classification == "mixed")
      },
      legacy: {
        direct_action_count: $legacy_direct_count,
        tls_acme_count: $inline_acme_count,
        download_detour_count: $download_detour_count
      },
      modern: {
        certificate_provider_count: $certificate_provider_count,
        http_client_count: $http_client_count
      },
      warnings: $warnings
    }'
}

agent_upgrade_check_json() {
  local target_input=$1
  local target_version
  local current_version
  local active_state
  local managed_instance_state
  local check_json
  local check_status=0
  local compatibility_json
  local config_sha256
  local blockers_json
  local direction="unknown"
  local target_supported=false
  local ready=false
  local legacy_direct_blocked=false

  if ! target_version=$(normalize_singbox_version_input "${target_input}") || [[ "${target_version}" == "latest" ]]; then
    agent_json_error "invalid_version" "upgrade-check 需要完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。"
    return 1
  fi

  current_version=$(detect_installed_singbox_version)
  current_version=${current_version#v}
  active_state=$(systemctl is-active sing-box 2>/dev/null || true)
  managed_instance_state=$(detect_existing_instance_state_read_only)
  config_sha256=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
  compatibility_json=$(agent_config_compatibility_json "${target_version}") || return 1
  if [[ "$(jq -r '.legacy.direct_action_count // 0' <<< "${compatibility_json}")" -gt 0 ]] &&
     singbox_version_at_least "${target_version}" 1.14.4; then
    legacy_direct_blocked=true
  fi

  if check_json=$(agent_singbox_check_json); then
    check_status=0
  else
    check_status=$?
  fi

  if singbox_version_at_least "${SB_SUPPORT_MAX_VERSION}" "${target_version}"; then
    target_supported=true
  fi

  if [[ "${current_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    if [[ "${current_version}" == "${target_version}" ]]; then
      direction="same"
    elif singbox_version_at_least "${target_version}" "${current_version}"; then
      direction="upgrade"
    else
      direction="downgrade"
    fi
  fi

  blockers_json=$(jq -n \
    --argjson legacy_direct_blocked "${legacy_direct_blocked}" \
    --arg current "${current_version}" \
    --arg direction "${direction}" \
    --arg managed_instance_state "${managed_instance_state}" \
    --arg active_state "${active_state:-unknown}" \
    --argjson target_supported "${target_supported}" \
    --argjson current_check_ok "$([[ "${check_status}" == "0" ]] && printf 'true' || printf 'false')" \
    '[
      if $legacy_direct_blocked then "legacy_direct_action" else empty end,
      if $target_supported != true then "target_unsupported" else empty end,
      if ($current | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not) then "current_version_unknown" else empty end,
      if $direction == "downgrade" then "downgrade_not_allowed" else empty end,
      if $managed_instance_state != "healthy" then "managed_instance_not_healthy" else empty end,
      if $active_state != "active" then "service_not_active" else empty end,
      if $current_check_ok != true then "current_config_check_failed" else empty end
    ]')

  if [[ "$(jq 'length' <<< "${blockers_json}")" == "0" ]]; then
    ready=true
  fi

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg current "${current_version}" \
    --arg target "${target_version}" \
    --arg direction "${direction}" \
    --arg active_state "${active_state:-unknown}" \
    --arg managed_instance_state "${managed_instance_state}" \
    --arg config_path "${SINGBOX_CONFIG_FILE}" \
    --arg config_sha256 "${config_sha256}" \
    --argjson target_supported "${target_supported}" \
    --argjson ready "${ready}" \
    --argjson current_check "${check_json}" \
    --argjson compatibility "${compatibility_json}" \
    --argjson blockers "${blockers_json}" \
    '{
      schema: $schema,
      ok: $ready,
      ready: $ready,
      action: "sing_box_upgrade_check",
      apply: false,
      current: $current,
      target: $target,
      direction: $direction,
      target_supported: $target_supported,
      blockers: $blockers,
      managed_instance_state: $managed_instance_state,
      service: {active_state: $active_state},
      config: {
        path: $config_path,
        sha256: $config_sha256,
        schema: $compatibility.schema,
        will_be_rewritten: false
      },
      legacy: $compatibility.legacy,
      modern: $compatibility.modern,
      current_check: $current_check,
      target_binary_validation: {
        performed: false,
        stage: "upgrade_before_restart"
      },
      migration_required: false,
      warnings: $compatibility.warnings
    }'

  [[ "${ready}" == "true" ]]
}

create_agent_upgrade_backup() {
  local current_version=$1
  local target_version=$2
  local transaction_id
  local backup_dir
  local manifest_file
  local relative_path
  local runtime_file_list
  local external_runtime_dir
  local external_library_path

  transaction_id=$(printf 'tx-%s-%s-%s' "$(date -u '+%Y%m%dT%H%M%SZ')" "$$" "${RANDOM}")

  if ! mkdir -p "${SB_UPGRADE_BACKUP_ROOT}" || ! chmod 700 "${SB_UPGRADE_BACKUP_ROOT}"; then
    return 1
  fi
  backup_dir=$(storage_mktemp -d "${SB_UPGRADE_BACKUP_ROOT}/upgrade-${current_version}-to-${target_version}.XXXXXXXX") || return 1
  if ! chmod 700 "${backup_dir}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  if [[ -d "${SB_PROJECT_DIR}" ]]; then
    if ! cp -a "${SB_PROJECT_DIR}" "${backup_dir}/runtime"; then
      rm -rf -- "${backup_dir}"
      return 1
    fi
  fi
  if [[ -f "${SINGBOX_BIN_PATH}" ]] && ! cp -p "${SINGBOX_BIN_PATH}" "${backup_dir}/sing-box"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -f "${SBV_BIN_PATH}" ]] && ! cp -p "${SBV_BIN_PATH}" "${backup_dir}/sbv"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -f "${SINGBOX_SERVICE_FILE}" ]] && ! cp -p "${SINGBOX_SERVICE_FILE}" "${backup_dir}/sing-box.service"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  external_runtime_dir="${backup_dir}/external-runtime"
  external_library_path=$(singbox_library_path) || {
    rm -rf -- "${backup_dir}"
    return 1
  }
  if ! singbox_library_snapshot "${external_runtime_dir}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  if ! jq -n \
    --arg created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg script_version "${SCRIPT_VERSION}" \
    --arg transaction_id "${transaction_id}" \
    --arg current_version "${current_version}" \
    --arg target_version "${target_version}" \
    --arg source_config "${SINGBOX_CONFIG_FILE}" \
    --arg manifest_path "${backup_dir}/SHA256SUMS" \
    --arg external_runtime_path "${external_runtime_dir}" \
    --arg external_library_path "${external_library_path}" \
    --arg external_marker_path "${SB_NAIVE_LIBRARY_MARKER}" \
    '{
      created_at: $created_at,
      script_version: $script_version,
      transaction_id: $transaction_id,
      old_version: $current_version,
      new_version: $target_version,
      current_version: $current_version,
      target_version: $target_version,
      source_config: $source_config,
      manifest_path: $manifest_path,
      external_runtime: {
        path: $external_runtime_path,
        library_path: $external_library_path,
        marker_path: $external_marker_path
      },
      manifest_scope: "all_regular_runtime_files_and_control_files",
      contains_sensitive_runtime_material: true
    }' > "${backup_dir}/metadata.json"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  manifest_file="${backup_dir}/SHA256SUMS"
  runtime_file_list="${backup_dir}/.runtime-files"
  if ! : > "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -d "${backup_dir}/runtime" ]] && \
    ! (cd "${backup_dir}" && find runtime -type f -print0) > "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if [[ -d "${backup_dir}/external-runtime" ]] && \
    ! (cd "${backup_dir}" && find external-runtime -type f -print0) >> "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if ! (
    cd "${backup_dir}" || exit 1
    while IFS= read -r -d '' relative_path; do
      sha256sum "${relative_path}" || exit 1
    done < .runtime-files
    for relative_path in sing-box sbv sing-box.service metadata.json; do
      if [[ -f "${relative_path}" ]]; then
        sha256sum "${relative_path}" || exit 1
      fi
    done
  ) > "${manifest_file}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if ! rm -f "${runtime_file_list}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi
  if ! chmod 600 "${manifest_file}" "${backup_dir}/metadata.json" || ! chmod -R go-rwx "${backup_dir}"; then
    rm -rf -- "${backup_dir}"
    return 1
  fi

  printf '%s' "${backup_dir}"
}

write_agent_upgrade_transaction_result() {
  local backup_dir=$1
  local status=$2
  local rollback_attempted=$3
  local rollback_result=$4
  local completed_at=${5:-}
  local failure_reason=${6:-}
  local operation_exit_code=${7:-}
  local metadata_file="${backup_dir}/metadata.json"
  local result_file="${backup_dir}/transaction-result.json"
  local temp_file
  local transaction_id
  local old_version
  local new_version
  local started_at
  local manifest_path
  local manifest_sha256
  local status_history_json
  local status_event_at

  [[ -f "${metadata_file}" && -f "${backup_dir}/SHA256SUMS" ]] || return 1
  transaction_id=$(jq -r '.transaction_id // empty' "${metadata_file}")
  old_version=$(jq -r '.old_version // .current_version // empty' "${metadata_file}")
  new_version=$(jq -r '.new_version // .target_version // empty' "${metadata_file}")
  started_at=$(jq -r '.created_at // empty' "${metadata_file}")
  manifest_path=$(jq -r '.manifest_path // empty' "${metadata_file}")
  manifest_sha256=$(agent_file_sha256 "${backup_dir}/SHA256SUMS")
  [[ -n "${transaction_id}" && -n "${old_version}" && -n "${new_version}" && -n "${started_at}" && -n "${manifest_sha256}" ]] || return 1

  status_event_at="${completed_at:-${started_at}}"
  status_history_json='[]'
  if [[ -f "${result_file}" ]]; then
    status_history_json=$(jq -c '.status_history // []' "${result_file}" 2>/dev/null || printf '[]')
  fi
  status_history_json=$(jq -c \
    --arg status "${status}" \
    --arg at "${status_event_at}" \
    --argjson history "${status_history_json}" \
    '$history + [{status: $status, at: $at}]' <<< '{}') || return 1

  temp_file=$(storage_mktemp "${backup_dir}/.transaction-result.XXXXXXXX") || return 1
  if ! jq -n \
    --arg schema_version "1.0" \
    --arg transaction_id "${transaction_id}" \
    --arg old_version "${old_version}" \
    --arg new_version "${new_version}" \
    --arg started_at "${started_at}" \
    --arg completed_at "${completed_at}" \
    --arg status "${status}" \
    --arg backup_path "${backup_dir}" \
    --arg manifest_path "${manifest_path}" \
    --arg manifest_sha256 "${manifest_sha256}" \
    --arg rollback_result "${rollback_result}" \
    --arg failure_reason "${failure_reason}" \
    --arg operation_exit_code "${operation_exit_code}" \
    --argjson status_history "${status_history_json}" \
    --argjson rollback_attempted "${rollback_attempted}" \
    '{
      schema_version: $schema_version,
      transaction_id: $transaction_id,
      old_version: $old_version,
      new_version: $new_version,
      started_at: $started_at,
      completed_at: (if $completed_at == "" then null else $completed_at end),
      status: $status,
      backup_path: $backup_path,
      manifest_path: $manifest_path,
      manifest_sha256: $manifest_sha256,
      manifest: {path: $manifest_path, sha256: $manifest_sha256},
      status_history: $status_history,
      rollback: {attempted: $rollback_attempted, result: $rollback_result},
      failure_reason: (if $failure_reason == "" then null else $failure_reason end),
      operation_exit_code: (if $operation_exit_code == "" then null else ($operation_exit_code | tonumber) end)
    }' > "${temp_file}"; then
    rm -f "${temp_file}"
    return 1
  fi
  if ! chmod 600 "${temp_file}" || ! mv -f "${temp_file}" "${result_file}"; then
    rm -f "${temp_file}"
    return 1
  fi
}

restore_agent_upgrade_backup() {
  local backup_dir=$1
  local restore_config=${2:-n}
  local service_was_active=${3:-n}
  local status=0
  local artifacts_restored="y"

  case "${backup_dir}" in
    "${SB_UPGRADE_BACKUP_ROOT}"/upgrade-*) ;;
    *) return 1 ;;
  esac

  [[ -f "${backup_dir}/sing-box" && -f "${backup_dir}/SHA256SUMS" ]] || return 1
  (cd "${backup_dir}" && sha256sum -c SHA256SUMS >/dev/null 2>&1) || return 1
  if replace_singbox_binary_atomically "${backup_dir}/sing-box"; then
    :
  else
    status=1
    artifacts_restored="n"
  fi
  if [[ -d "${backup_dir}/external-runtime" ]]; then
    if ! singbox_library_restore_snapshot "${backup_dir}/external-runtime"; then
      status=1
      artifacts_restored="n"
    fi
  fi

  if [[ -f "${backup_dir}/sing-box.service" ]]; then
    if ! cp -p "${backup_dir}/sing-box.service" "${SINGBOX_SERVICE_FILE}"; then
      status=1
      artifacts_restored="n"
    fi
  fi
  if [[ "${restore_config}" == "y" && -f "${backup_dir}/runtime/config.json" ]]; then
    if ! cp -p "${backup_dir}/runtime/config.json" "${SINGBOX_CONFIG_FILE}"; then
      status=1
      artifacts_restored="n"
    fi
  fi

  if ! systemctl daemon-reload >/dev/null 2>&1; then
    status=1
    artifacts_restored="n"
  fi
  if [[ "${artifacts_restored}" != "y" ]]; then
    systemctl stop sing-box >/dev/null 2>&1 || status=1
    return 1
  fi
  if [[ "${service_was_active}" == "y" ]]; then
    run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box >/dev/null || status=1
  else
    systemctl stop sing-box >/dev/null 2>&1 || status=1
  fi

  return "${status}"
}

agent_upgrade_cli() {
  local json_flag=${1:-}
  local target_input=${2:-}
  local yes_flag=${3:-}
  local target_version
  local preflight_json
  local current_version
  local before_hash
  local before_service_state
  local backup_dir
  local operation_log
  local operation_excerpt
  local operation_status=0
  local after_version
  local after_hash
  local after_service_state
  local after_check_json
  local after_check_status=0
  local config_preserved=false
  local changed=false
  local rollback_ok=false
  local final_changed=false
  local manual_intervention_required=false
  local restore_config="n"
  local failure_reason="upgrade_failed"
  local output_error
  local transaction_id
  local transaction_result_file
  local transaction_manifest_path
  local transaction_manifest_sha256
  local transaction_status
  local transaction_rollback_result
  local transaction_result_persisted=false

  if [[ "${json_flag}" != "--json" ]]; then
    agent_json_error "json_required" "upgrade 当前仅支持 --json 输出。"
    return 1
  fi
  if [[ "${yes_flag}" != "--yes" ]]; then
    agent_json_error "confirmation_required" "upgrade 会备份、替换二进制并重启服务，需要 --yes 确认。"
    return 1
  fi
  if ! target_version=$(normalize_singbox_version_input "${target_input}") || [[ "${target_version}" == "latest" ]]; then
    agent_json_error "invalid_version" "upgrade 需要完整版本号，例如 ${SB_SUPPORT_MAX_VERSION}。"
    return 1
  fi
  if ! singbox_version_at_least "${SB_SUPPORT_MAX_VERSION}" "${target_version}"; then
    agent_json_error "unsupported_version" "目标版本 ${target_version} 高于当前脚本适配上限 ${SB_SUPPORT_MAX_VERSION}。"
    return 1
  fi

  if ! preflight_json=$(agent_upgrade_check_json "${target_version}"); then
    if jq -e '.managed_instance_state == "healthy" and .current_check.ok != true' >/dev/null 2>&1 <<< "${preflight_json}"; then
      jq -n \
        --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
        --argjson preflight "${preflight_json}" \
        '{schema: $schema, ok: false, error: "config_check_failed", reason: "config_check_failed", preflight: $preflight}'
    else
      jq -n \
        --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
        --argjson preflight "${preflight_json}" \
        '{schema: $schema, ok: false, error: "preflight_failed", reason: "preflight_failed", preflight: $preflight}'
    fi
    return 1
  fi

  current_version=$(jq -r '.current' <<< "${preflight_json}")
  before_hash=$(jq -r '.config.sha256' <<< "${preflight_json}")
  before_service_state=$(jq -r '.service.active_state' <<< "${preflight_json}")

  if [[ "${current_version}" == "${target_version}" ]]; then
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg current "${current_version}" \
      --arg target "${target_version}" \
      --arg config_hash "${before_hash}" \
      --argjson check "$(jq -c '.current_check' <<< "${preflight_json}")" \
      --argjson warnings "$(jq -c '.warnings' <<< "${preflight_json}")" \
      '{
        schema: $schema,
        ok: true,
        action: "sing_box_upgrade",
        changed: false,
        restarted: false,
        rolled_back: false,
        current: $current,
        target: $target,
        installed: $current,
        backup: null,
        config_preserved: true,
        config: {sha256_before: $config_hash, sha256_after: $config_hash},
        check: $check,
        warnings: $warnings,
        transaction: {
          id: null,
          result_path: null,
          status: "not_attempted",
          result_persisted: false,
          reason: "already_installed",
          manifest: {path: null, sha256: null},
          rollback: {attempted: false, result: "not_attempted"}
        }
      }'
    return 0
  fi

  if ! backup_dir=$(create_agent_upgrade_backup "${current_version}" "${target_version}"); then
    agent_json_error "backup_failed" "无法创建升级备份，已取消升级。"
    return 1
  fi

  transaction_id=$(jq -r '.transaction_id' "${backup_dir}/metadata.json")
  transaction_result_file="${backup_dir}/transaction-result.json"
  transaction_manifest_path=$(jq -r '.manifest_path' "${backup_dir}/metadata.json")
  transaction_manifest_sha256=$(agent_file_sha256 "${backup_dir}/SHA256SUMS")
  if ! write_agent_upgrade_transaction_result \
    "${backup_dir}" \
    "backup_ready" \
    false \
    "not_attempted"; then
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg backup "${backup_dir}" \
      --arg transaction_id "${transaction_id}" \
      --arg transaction_result_file "${transaction_result_file}" \
      --arg transaction_manifest_path "${transaction_manifest_path}" \
      --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
      '{
        schema: $schema,
        ok: false,
        error: "transaction_record_failed",
        backup: $backup,
        transaction: {
          id: $transaction_id,
          result_path: $transaction_result_file,
          status: "backup_ready",
          result_persisted: false,
          manifest_path: $transaction_manifest_path,
          manifest_sha256: $transaction_manifest_sha256,
          manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
          rollback: {attempted: false, result: "not_attempted"}
        }
      }'
    return 1
  fi

  if ! operation_log=$(storage_mktemp); then
    transaction_status="failed"
    transaction_rollback_result="not_attempted"
    if write_agent_upgrade_transaction_result \
      "${backup_dir}" \
      "${transaction_status}" \
      false \
      "${transaction_rollback_result}" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "temporary_log_failed"; then
      transaction_result_persisted=true
      output_error="temporary_log_failed"
    else
      output_error="transaction_record_failed"
    fi
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg error "${output_error}" \
      --arg backup "${backup_dir}" \
      --arg transaction_id "${transaction_id}" \
      --arg transaction_result_file "${transaction_result_file}" \
      --arg transaction_manifest_path "${transaction_manifest_path}" \
      --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
      --arg transaction_status "${transaction_status}" \
      --argjson transaction_result_persisted "${transaction_result_persisted}" \
      '{
        schema: $schema,
        ok: false,
        error: $error,
        failure_reason: "temporary_log_failed",
        backup: $backup,
        transaction: {
          id: $transaction_id,
          result_path: $transaction_result_file,
          status: $transaction_status,
          result_persisted: $transaction_result_persisted,
          manifest_path: $transaction_manifest_path,
          manifest_sha256: $transaction_manifest_sha256,
          manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
          rollback: {attempted: false, result: "not_attempted"}
        }
      }'
    return 1
  fi
  set +e
  (
    set -e
    SB_VERSION="${target_version}"
    update_singbox_binary_preserving_config
  ) > "${operation_log}" 2>&1
  operation_status=$?
  set -e

  after_version=$(detect_installed_singbox_version)
  after_version=${after_version#v}
  after_hash=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
  after_service_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if after_check_json=$(agent_singbox_check_json); then
    after_check_status=0
  else
    after_check_status=$?
  fi

  [[ -n "${before_hash}" && "${before_hash}" == "${after_hash}" ]] && config_preserved=true
  [[ "${after_version}" == "${target_version}" ]] && changed=true
  operation_excerpt=$(sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g' "${operation_log}" | tail -n 80)

  if [[ "${operation_status}" == "0" && "${changed}" == "true" && "${config_preserved}" == "true" && "${after_check_status}" == "0" && "${after_service_state}" == "active" ]]; then
    transaction_status="success"
    transaction_rollback_result="not_attempted"
    if write_agent_upgrade_transaction_result \
      "${backup_dir}" \
      "${transaction_status}" \
      false \
      "${transaction_rollback_result}" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      "" \
      "${operation_status}"; then
      transaction_result_persisted=true
    fi
    rm -f "${operation_log}"
    jq -n \
      --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
      --arg current "${current_version}" \
      --arg target "${target_version}" \
      --arg installed "${after_version}" \
      --arg backup "${backup_dir}" \
      --arg transaction_id "${transaction_id}" \
      --arg transaction_result_file "${transaction_result_file}" \
      --arg transaction_manifest_path "${transaction_manifest_path}" \
      --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
      --argjson transaction_result_persisted "${transaction_result_persisted}" \
      --arg before_hash "${before_hash}" \
      --arg after_hash "${after_hash}" \
      --arg before_service "${before_service_state}" \
      --arg after_service "${after_service_state}" \
      --arg operation_log "${operation_excerpt}" \
      --argjson check "${after_check_json}" \
      --argjson warnings "$(jq -c '.warnings' <<< "${preflight_json}")" \
      '{
        schema: $schema,
        ok: true,
        action: "sing_box_upgrade",
        changed: true,
        restarted: true,
        rolled_back: false,
        current: $current,
        target: $target,
        installed: $installed,
        backup: $backup,
        transaction: {
          id: $transaction_id,
          result_path: $transaction_result_file,
          status: "success",
          result_persisted: $transaction_result_persisted,
          manifest_path: $transaction_manifest_path,
          manifest_sha256: $transaction_manifest_sha256,
          manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
          rollback: {attempted: false, result: "not_attempted"}
        },
        config_preserved: true,
        config: {sha256_before: $before_hash, sha256_after: $after_hash},
        service: {before: $before_service, after: $after_service},
        check: $check,
        warnings: $warnings,
        operation_log: $operation_log
      } + (if $transaction_result_persisted then {} else {ok: false, error: "transaction_record_failed"} end)'
    if [[ "${transaction_result_persisted}" != "true" ]]; then
      return 1
    fi
    return 0
  fi

  if [[ "${config_preserved}" != "true" ]]; then
    restore_config="y"
    failure_reason="config_changed"
  elif grep -Fq "现有配置未通过 sing-box" "${operation_log}"; then
    failure_reason="config_check_failed"
  elif grep -Fq "sing-box 服务重启失败或未保持 active" "${operation_log}"; then
    failure_reason="service_not_active"
  elif grep -Fq "安装后的 sing-box 版本" "${operation_log}"; then
    failure_reason="target_version_not_installed"
  elif [[ "${after_check_status}" != "0" ]]; then
    failure_reason="config_check_failed"
  elif [[ "${after_service_state}" != "active" ]]; then
    failure_reason="service_not_active"
  elif [[ "${after_version}" != "${target_version}" ]]; then
    failure_reason="target_version_not_installed"
  fi

  if restore_agent_upgrade_backup \
    "${backup_dir}" \
    "${restore_config}" \
    "$([[ "${before_service_state}" == "active" ]] && printf 'y' || printf 'n')"; then
    rollback_ok=true
  fi

  after_version=$(detect_installed_singbox_version)
  after_version=${after_version#v}
  after_hash=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
  after_service_state=$(systemctl is-active sing-box 2>/dev/null || true)
  if after_check_json=$(agent_singbox_check_json); then
    after_check_status=0
  else
    after_check_status=$?
  fi
  [[ -n "${before_hash}" && "${before_hash}" == "${after_hash}" ]] && config_preserved=true || config_preserved=false
  if [[ "${after_version}" != "${current_version}" || "${config_preserved}" != "true" || "${after_check_status}" != "0" ]] || \
    [[ "${after_service_state}" != "${before_service_state}" ]]; then
    rollback_ok=false
    final_changed=true
  fi
  output_error="${failure_reason}"
  if [[ "${rollback_ok}" != "true" ]]; then
    output_error="rollback_failed"
    manual_intervention_required=true
  fi
  if [[ "${rollback_ok}" == "true" ]]; then
    transaction_status="rolled_back"
    transaction_rollback_result="success"
  else
    transaction_status="rollback_failed"
    transaction_rollback_result="failed"
  fi
  if write_agent_upgrade_transaction_result \
    "${backup_dir}" \
    "${transaction_status}" \
    true \
    "${transaction_rollback_result}" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${failure_reason}" \
    "${operation_status}"; then
    transaction_result_persisted=true
  else
    output_error="transaction_record_failed"
  fi
  rm -f "${operation_log}"

  jq -n \
    --arg schema "${AGENT_OUTPUT_SCHEMA_VERSION}" \
    --arg error "${output_error}" \
    --arg failure_reason "${failure_reason}" \
    --arg current "${current_version}" \
    --arg target "${target_version}" \
    --arg installed "${after_version}" \
    --arg backup "${backup_dir}" \
    --arg transaction_id "${transaction_id}" \
    --arg transaction_result_file "${transaction_result_file}" \
    --arg transaction_manifest_path "${transaction_manifest_path}" \
    --arg transaction_manifest_sha256 "${transaction_manifest_sha256}" \
    --arg transaction_status "${transaction_status}" \
    --arg transaction_rollback_result "${transaction_rollback_result}" \
    --argjson transaction_result_persisted "${transaction_result_persisted}" \
    --arg before_hash "${before_hash}" \
    --arg after_hash "${after_hash}" \
    --arg before_service "${before_service_state}" \
    --arg after_service "${after_service_state}" \
    --arg operation_log "${operation_excerpt}" \
    --argjson operation_exit_code "${operation_status}" \
    --argjson changed "${final_changed}" \
    --argjson config_preserved "${config_preserved}" \
    --argjson rollback_ok "${rollback_ok}" \
    --argjson manual_intervention_required "${manual_intervention_required}" \
    --argjson check "${after_check_json}" \
    --argjson warnings "$(jq -c '.warnings' <<< "${preflight_json}")" \
    '{
      schema: $schema,
      ok: false,
      error: $error,
      reason: $error,
      failure_reason: $failure_reason,
      action: "sing_box_upgrade",
      changed: $changed,
      restarted: false,
      rollback_attempted: true,
      rolled_back: $rollback_ok,
      rollback_ok: $rollback_ok,
      manual_intervention_required: $manual_intervention_required,
      current: $current,
      target: $target,
      installed: $installed,
      backup: $backup,
      transaction: {
        id: $transaction_id,
        result_path: $transaction_result_file,
        status: $transaction_status,
        result_persisted: $transaction_result_persisted,
        manifest_path: $transaction_manifest_path,
        manifest_sha256: $transaction_manifest_sha256,
        manifest: {path: $transaction_manifest_path, sha256: $transaction_manifest_sha256},
        rollback: {attempted: true, result: $transaction_rollback_result}
      },
      config_preserved: $config_preserved,
      config: {sha256_before: $before_hash, sha256_after: $after_hash},
      service: {before: $before_service, after: $after_service},
      check: $check,
      warnings: $warnings,
      operation_exit_code: $operation_exit_code,
      operation_log: $operation_log
    }'
  return 1
}
