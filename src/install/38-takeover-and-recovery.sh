
managed_config_acme_is_state_representable() {
  local config_file=$1
  local inbound_count inbound_index inbound_type

  # Invalid JSON is handled by the existing candidate generation transaction;
  # this guard only prevents a valid config from losing ACME fields that the
  # protocol state model cannot reproduce.
  jq -e '.' "${config_file}" &>/dev/null || return 0
  inbound_count=$(jq -r '(.inbounds // []) | length' "${config_file}") || return 1
  [[ "${inbound_count}" =~ ^[0-9]+$ ]] || return 1

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_type=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].type // ""' "${config_file}") || return 1
    case "${inbound_type}" in
      hysteria2|anytls) ;;
      *) continue ;;
    esac

    if jq -e --argjson idx "${inbound_index}" '
      .inbounds[$idx].tls.acme? != null and
      .inbounds[$idx].tls.certificate_provider? != null
    ' "${config_file}" &>/dev/null; then
      return 1
    fi

    if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${config_file}" &>/dev/null; then
      inline_acme_extra_json_from_config "${config_file}" "${inbound_index}" >/dev/null || return 1
    elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${config_file}" &>/dev/null; then
      (load_certificate_provider_from_config "${config_file}" "${inbound_index}") || return 1
    fi
  done

  return 0
}

attempt_managed_instance_auto_heal() {
  local indexed_protocols=()
  local protocol
  local snapshot_dir

  [[ -x "${SINGBOX_BIN_PATH}" && -f "${SINGBOX_SERVICE_FILE}" && -f "${SINGBOX_CONFIG_FILE}" && -f "${SB_PROTOCOL_INDEX_FILE}" ]] || return 1
  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" || return 1

  # Detection must not reconcile away an indexed protocol whose state file is
  # missing. That is an incomplete instance requiring takeover, not safe drift
  # that can be regenerated from the remaining state files.
  mapfile -t indexed_protocols < <(list_indexed_protocols_raw)
  [[ ${#indexed_protocols[@]} -gt 0 ]] || return 1

  for protocol in "${indexed_protocols[@]}"; do
    protocol_state_exists "${protocol}" || return 1
  done

  protocol_state_layer_matches_config && return 0

  if ! managed_config_acme_is_state_representable "${SINGBOX_CONFIG_FILE}"; then
    log_warn "当前配置包含协议状态无法无损表达的 ACME 字段，已跳过自动重建并转入接管流程。"
    return 1
  fi

  log_warn "检测到托管实例配置与协议状态不一致，正在尝试按协议状态自动重建运行配置。"

  if config_has_advanced_route "${SINGBOX_CONFIG_FILE}"; then
    SB_ADVANCED_ROUTE="y"
  else
    SB_ADVANCED_ROUTE="n"
  fi

  if config_has_warp_enabled "${SINGBOX_CONFIG_FILE}"; then
    SB_ENABLE_WARP="y"
  else
    SB_ENABLE_WARP="n"
  fi

  load_warp_route_settings
  load_stack_mode_state

  snapshot_dir=$(create_managed_state_snapshot) || return 1

  if ! generate_config; then
    rollback_managed_state_snapshot "${snapshot_dir}" || true
    return 1
  fi

  discard_managed_state_snapshot "${snapshot_dir}" || true
  return 0
}

detect_existing_instance_state() {
  local has_bin="n"
  local has_service="n"
  local has_config="n"
  local has_index="n"
  local has_state="n"
  local has_sbv="n"
  local state_file

  [[ -x "${SINGBOX_BIN_PATH}" ]] && has_bin="y"
  [[ -f "${SINGBOX_SERVICE_FILE}" ]] && has_service="y"
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] && has_config="y"
  [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]] && has_index="y"
  [[ -x "${SBV_BIN_PATH}" ]] && has_sbv="y"

  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    for state_file in "${SB_PROTOCOL_STATE_DIR}"/*.env; do
      [[ -e "${state_file}" ]] || continue
      [[ "${state_file}" == "${SB_PROTOCOL_INDEX_FILE}" ]] && continue
      has_state="y"
      break
    done
  fi

  if [[ "${has_bin}" == "n" && "${has_service}" == "n" && "${has_config}" == "n" && "${has_index}" == "n" && "${has_state}" == "n" ]]; then
    printf '%s' "fresh"
    return 0
  fi

  if [[ "${has_bin}" == "y" && "${has_service}" == "y" && "${has_config}" == "y" ]]; then
    if protocol_state_layer_matches_config; then
      printf '%s' "healthy"
    elif attempt_managed_instance_auto_heal && protocol_state_layer_matches_config; then
      printf '%s' "healthy"
    else
      printf '%s' "incomplete"
    fi
    return 0
  fi

  printf '%s' "incomplete"
}

restore_protocol_state_layer_from_backup() {
  local backup_dir=$1
  local state_dir_existed=$2
  local restore_candidate restore_previous

  restore_candidate=$(mktemp -d "${SB_PROJECT_DIR}/.protocol-state-restore.XXXXXX") || return 1
  if [[ "${state_dir_existed}" == "y" ]]; then
    if ! cp -a "${backup_dir}/." "${restore_candidate}/"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
  fi

  restore_previous="${SB_PROTOCOL_STATE_DIR}.restore-old.$$"
  if [[ -e "${SB_PROTOCOL_STATE_DIR}" ]]; then
    if ! mv "${SB_PROTOCOL_STATE_DIR}" "${restore_previous}"; then
      rm -rf "${restore_candidate}"
      return 1
    fi
  fi
  if [[ "${state_dir_existed}" == "y" ]]; then
    if ! mv "${restore_candidate}" "${SB_PROTOCOL_STATE_DIR}"; then
      [[ -e "${restore_previous}" ]] && mv "${restore_previous}" "${SB_PROTOCOL_STATE_DIR}" || true
      rm -rf "${restore_candidate}"
      return 1
    fi
  else
    rmdir "${restore_candidate}" || return 1
  fi
  if [[ -e "${restore_previous}" ]]; then
    rm -rf "${restore_previous}" || return 1
  fi
}

abort_protocol_state_rebuild() {
  local backup_dir=$1
  local state_dir_existed=$2
  local backup_state_dir="${backup_dir}/state"

  # Rebuild work roots also contain transient candidates.  The state snapshot
  # must be in the dedicated child; do not infer the layout from an arbitrary
  # directory that could itself be part of a legitimate state tree.
  [[ -d "${backup_state_dir}" && ! -L "${backup_state_dir}" ]] || return 1

  if ! restore_protocol_state_layer_from_backup "${backup_state_dir}" "${state_dir_existed}"; then
    return 1
  fi
  rm -rf "${backup_dir}"
  return 0
}

rebuild_protocol_state_from_config() {
  # A pending public instance transaction owns the state/config snapshot. Do
  # not let takeover or auto-heal clear its state while recovery may still be
  # required after an interruption.
  [[ ! -e "${SB_PROJECT_DIR}.instance-write.lock" && ! -L "${SB_PROJECT_DIR}.instance-write.lock" ]] || {
    printf '[ERROR] instance_transaction_pending: existing Mixed instance transaction requires recovery first.\n' >&2
    return 1
  }
  validate_protocol_index_for_rebuild || return 1
  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" || return 1
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 0

  local SB_UNMANAGED_CLIENT_TAGS_JSON='[]' unmanaged_inbound unmanaged_tags=()
  local rebuilt_protocols=()
  local inbound_count inbound_index inbound_type inbound_json protocol
  local vless_instance_index=0 instance_id key_file_private state_index=""
  local backup_dir state_dir_existed="n"
  local mixed_inbound_count=0 mixed_rebuild_mode="legacy"
  local mixed_candidate_file="" mixed_candidate_revision=0 mixed_state_file mixed_state_schema
  local mixed_legacy_node_name mixed_legacy_tag mixed_legacy_listen mixed_legacy_policy mixed_stack_listen
  local socks_inbound_count=0 socks_candidate_file="" socks_candidate_revision=0 socks_state_file socks_state_schema
  local http_inbound_count=0 http_candidate_file="" http_candidate_revision=0 http_state_file http_state_schema
  local shadowsocks_inbound_count=0 shadowsocks_candidate_file="" shadowsocks_candidate_revision=0 shadowsocks_state_file shadowsocks_state_schema
  local trojan_inbound_count=0 trojan_candidate_file="" trojan_candidate_revision=0 trojan_state_file trojan_state_schema
  local vmess_inbound_count=0 vmess_candidate_file="" vmess_candidate_revision=0 vmess_state_file vmess_state_schema
  local vless_plain_inbound_count=0 vless_plain_candidate_file="" vless_plain_candidate_revision=0 vless_plain_state_file vless_plain_state_schema
  local hy2_inbound_count=0 hy2_candidate_file="" hy2_candidate_revision=0 hy2_state_file hy2_state_schema hy2_rebuild_mode="legacy"
  local anytls_inbound_count=0 anytls_candidate_file="" anytls_candidate_revision=0 anytls_state_file anytls_state_schema anytls_rebuild_mode="legacy"
  local snell_inbound_count=0 snell_candidate_file="" snell_candidate_revision=0 snell_state_file snell_state_schema
  local tuic_inbound_count=0 tuic_candidate_file="" tuic_candidate_revision=0 tuic_state_file tuic_state_schema
  local hysteria_inbound_count=0 hysteria_candidate_file="" hysteria_candidate_revision=0 hysteria_state_file hysteria_state_schema
  local naive_inbound_count=0 naive_candidate_file="" naive_candidate_revision=0 naive_state_file naive_state_schema
  local shadowtls_inbound_count=0 shadowtls_candidate_file="" shadowtls_candidate_revision=0 shadowtls_state_file shadowtls_state_schema
  local backup_state_dir

  backup_dir=$(mktemp -d) || return 1
  backup_state_dir="${backup_dir}/state"
  if ! mkdir -p "${backup_state_dir}"; then
    rm -rf "${backup_dir}"
    return 1
  fi
  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    state_dir_existed="y"
    if ! cp -a "${SB_PROTOCOL_STATE_DIR}/." "${backup_state_dir}/"; then
      rm -rf "${backup_dir}"
      return 1
    fi
  fi

  while IFS= read -r unmanaged_inbound; do
    if manual_client_inbound_is_unmanaged "${unmanaged_inbound}"; then
      unmanaged_tags+=("$(jq -r '.tag' <<< "${unmanaged_inbound}")")
    fi
  done < <(jq -c '.inbounds[]?' "${SINGBOX_CONFIG_FILE}")
  if (( ${#unmanaged_tags[@]} > 0 )); then
    SB_UNMANAGED_CLIENT_TAGS_JSON=$(printf '%s\n' "${unmanaged_tags[@]}" | jq -Rsc 'split("\n")[:-1]') || return 1
  fi

  if ! collect_vless_reality_config_instances; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  if ! inbound_count=$(jq -r '(.inbounds // []) | length' "${SINGBOX_CONFIG_FILE}"); then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  if [[ ! "${inbound_count}" =~ ^[0-9]+$ ]]; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi

  # Capture every Mixed inbound while the old root state and typed metadata
  # still exist.  The subsequent clear operation removes root .env files, so
  # doing this in the loop would lose IDs, names, credentials, and policies.
  mixed_inbound_count=$(config_protocol_inbound_count mixed "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  [[ "${mixed_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  if (( mixed_inbound_count > 0 )); then
    mixed_state_file=$(protocol_state_file "mixed") || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    mixed_state_schema="1"
    if [[ -f "${mixed_state_file}" ]]; then
      if grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=" "${mixed_state_file}"; then
        validate_protocol_state_schema mixed "${mixed_state_file}" || {
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        }
      fi
      mixed_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${mixed_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      mixed_state_schema=${mixed_state_schema//\"/}
      mixed_state_schema=${mixed_state_schema//\'/}
    fi
    mixed_legacy_node_name=""
    if [[ -f "${mixed_state_file}" && "${mixed_state_schema}" == "1" ]]; then
      mixed_legacy_node_name=$(
        unset NODE_NAME
        # shellcheck disable=SC1090
        source "${mixed_state_file}"
        # Keep trailing newlines in a legacy name across command substitution.
        printf '%s\1' "${NODE_NAME:-}"
      ) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      mixed_legacy_node_name=${mixed_legacy_node_name%$'\1'}
    fi

    # A schema-1 singleton may retain its old state format only when the
    # fixed legacy renderer can reproduce the live inbound exactly.  Any
    # custom tag/listen/policy or unsupported field takes the typed path.
    mixed_rebuild_mode="legacy"
    if [[ "${mixed_state_schema}" == "2" || "${mixed_inbound_count}" != "1" ]] ||
       mixed_structured_state_active >/dev/null 2>&1; then
      mixed_rebuild_mode="structured"
    else
      mixed_legacy_tag=$(jq -r '[.inbounds[]? | select(.type == "mixed")][0].tag // "mixed-in"' "${SINGBOX_CONFIG_FILE}" || true)
      mixed_legacy_listen=$(jq -r '[.inbounds[]? | select(.type == "mixed")][0].listen // empty' "${SINGBOX_CONFIG_FILE}" || true)
      if [[ -z "${mixed_legacy_listen}" ]]; then
        # sing-box's omitted Mixed listen address is the verified loopback
        # default; do not substitute the stack's public bind address.
        mixed_legacy_listen='127.0.0.1'
      fi
      mixed_legacy_policy=$(vless_reality_outbound_policy_from_config "${mixed_legacy_tag}" 2>/dev/null || true)
      mixed_stack_listen=$(stack_inbound_listen_address 2>/dev/null || true)
      if [[ "${mixed_legacy_tag}" != "mixed-in" ||
            "${mixed_legacy_listen}" != "${mixed_stack_listen}" ||
            "${mixed_legacy_policy}" != "default" ]]; then
        mixed_rebuild_mode="structured"
      fi
    fi

    if [[ "${mixed_rebuild_mode}" == "structured" ]]; then
      mixed_candidate_file="${backup_dir}/mixed.candidate.json"
      if ! mixed_config_store_candidate > "${mixed_candidate_file}"; then
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      fi
      if [[ -f "$(mixed_structured_store_file 2>/dev/null || true)" ]]; then
        mixed_candidate_revision=$(jq -r '.revision' "$(mixed_structured_store_file)") || {
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        }
      else
        mixed_candidate_revision=0
      fi
    else
      # Validate singleton fields even when the legacy state remains in use;
      # otherwise a malformed user/listen value could be silently flattened.
      if ! mixed_config_store_candidate >/dev/null; then
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      fi
    fi
  fi

  # SOCKS is structured-only. Capture its complete typed candidate while the
  # old metadata is still available; the clear below removes root env files.
  socks_inbound_count=$(config_protocol_inbound_count socks "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  [[ "${socks_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  if (( socks_inbound_count > 0 )); then
    socks_state_file=$(protocol_state_file socks) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    socks_state_schema=""
    if [[ -f "${socks_state_file}" ]]; then
      validate_protocol_state_schema socks "${socks_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      socks_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${socks_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      socks_state_schema=${socks_state_schema//\"/}
      socks_state_schema=${socks_state_schema//\'/}
    fi
    [[ -z "${socks_state_schema}" || "${socks_state_schema}" == "2" ]] || {
      printf '[ERROR] socks_store_candidate: SOCKS legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    socks_candidate_file="${backup_dir}/socks.candidate.json"
    if ! plain_proxy_config_store_candidate socks > "${socks_candidate_file}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if [[ -f "$(plain_proxy_structured_store_file socks 2>/dev/null || true)" ]]; then
      socks_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file socks)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
    else
      socks_candidate_revision=0
    fi
  fi

  # HTTP is structured-only. Capture its complete typed candidate while the
  # old metadata is still available; the clear below removes root .env files.
  http_inbound_count=$(config_protocol_inbound_count http "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  [[ "${http_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  if (( http_inbound_count > 0 )); then
    http_state_file=$(protocol_state_file http) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    http_state_schema=""
    if [[ -f "${http_state_file}" ]]; then
      validate_protocol_state_schema http "${http_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      http_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${http_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      http_state_schema=${http_state_schema//\"/}
      http_state_schema=${http_state_schema//\'/}
    fi
    [[ -z "${http_state_schema}" || "${http_state_schema}" == "2" ]] || {
      printf '[ERROR] http_store_candidate: HTTP legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    http_candidate_file="${backup_dir}/http.candidate.json"
    if ! plain_proxy_config_store_candidate http > "${http_candidate_file}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if [[ -f "$(plain_proxy_structured_store_file http 2>/dev/null || true)" ]]; then
      http_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file http)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
    else
      http_candidate_revision=0
    fi
  fi

  # Shadowsocks is structured-only. Capture its complete typed candidate while
  # the old metadata is still available; the clear below removes root .env files.
  shadowsocks_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "shadowsocks")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  [[ "${shadowsocks_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  }
  if (( shadowsocks_inbound_count > 0 )); then
    shadowsocks_state_file=$(protocol_state_file shadowsocks) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    shadowsocks_state_schema=""
    if [[ -f "${shadowsocks_state_file}" ]]; then
      validate_protocol_state_schema shadowsocks "${shadowsocks_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      shadowsocks_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${shadowsocks_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
      shadowsocks_state_schema=${shadowsocks_state_schema//\"/}
      shadowsocks_state_schema=${shadowsocks_state_schema//\'/}
    fi
    [[ -z "${shadowsocks_state_schema}" || "${shadowsocks_state_schema}" == "2" ]] || {
      printf '[ERROR] shadowsocks_store_candidate: Shadowsocks legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    }
    shadowsocks_candidate_file="${backup_dir}/shadowsocks.candidate.json"
    if ! plain_proxy_config_store_candidate shadowsocks > "${shadowsocks_candidate_file}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if [[ -f "$(plain_proxy_structured_store_file shadowsocks 2>/dev/null || true)" ]]; then
      shadowsocks_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file shadowsocks)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
      }
    else
      shadowsocks_candidate_revision=0
    fi
  fi

  # Trojan is structured-only.  Capture its complete typed candidate before
  # clearing the protocol cache; legacy Trojan env files are never accepted.
  trojan_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "trojan")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${trojan_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( trojan_inbound_count > 0 )); then
    trojan_state_file=$(protocol_state_file trojan) || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    trojan_state_schema=""
    if [[ -f "${trojan_state_file}" ]]; then
      validate_protocol_state_schema trojan "${trojan_state_file}" || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
      trojan_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${trojan_state_file}" | head -n1) || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
      trojan_state_schema=${trojan_state_schema//\"/}; trojan_state_schema=${trojan_state_schema//\'/}
    fi
    [[ -z "${trojan_state_schema}" || "${trojan_state_schema}" == 2 ]] || {
      printf '[ERROR] trojan_store_candidate: Trojan legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    }
    trojan_candidate_file="${backup_dir}/trojan.candidate.json"
    plain_proxy_config_store_candidate trojan > "${trojan_candidate_file}" || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    if [[ -f "$(plain_proxy_structured_store_file trojan 2>/dev/null || true)" ]]; then
      trojan_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file trojan)") || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    else trojan_candidate_revision=0; fi
  fi

  # VMess is structured-only. Capture its complete typed candidate before
  # clearing the protocol cache; legacy VMess env files are never accepted.
  vmess_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "vmess")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${vmess_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( vmess_inbound_count > 0 )); then
    vmess_state_file=$(protocol_state_file vmess) || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    vmess_state_schema=""
    if [[ -f "${vmess_state_file}" ]]; then
      validate_protocol_state_schema vmess "${vmess_state_file}" || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
      vmess_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${vmess_state_file}" | head -n1) || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
      vmess_state_schema=${vmess_state_schema//\"/}; vmess_state_schema=${vmess_state_schema//\'/}
    fi
    [[ -z "${vmess_state_schema}" || "${vmess_state_schema}" == 2 ]] || {
      printf '[ERROR] vmess_store_candidate: VMess legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    }
    vmess_candidate_file="${backup_dir}/vmess.candidate.json"
    vmess_config_store_candidate > "${vmess_candidate_file}" || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    if [[ -f "$(plain_proxy_structured_store_file vmess 2>/dev/null || true)" ]]; then
      vmess_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file vmess)") || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    else vmess_candidate_revision=0; fi
  fi

  # Ordinary VLESS is structured-only. Capture its complete typed candidate
  # before clearing the protocol cache; VLESS + REALITY is discriminated by
  # the presence of tls.reality and is handled by the collector above.
  vless_plain_inbound_count=$(config_protocol_inbound_count vless-plain "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${vless_plain_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( vless_plain_inbound_count > 0 )); then
    vless_plain_state_file=$(protocol_state_file vless-plain) || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    vless_plain_state_schema=""
    if [[ -f "${vless_plain_state_file}" ]]; then
      validate_protocol_state_schema vless-plain "${vless_plain_state_file}" || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
      vless_plain_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${vless_plain_state_file}" | head -n1) || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
      vless_plain_state_schema=${vless_plain_state_schema//\"/}; vless_plain_state_schema=${vless_plain_state_schema//\'/}
    fi
    [[ -z "${vless_plain_state_schema}" || "${vless_plain_state_schema}" == 2 ]] || {
      printf '[ERROR] vless_plain_store_candidate: VLESS legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    vless_plain_candidate_file="${backup_dir}/vless-plain.candidate.json"
    plain_proxy_config_store_candidate vless-plain > "${vless_plain_candidate_file}" || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    if [[ -f "$(plain_proxy_structured_store_file vless-plain 2>/dev/null || true)" ]]; then
      vless_plain_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file vless-plain)") || { abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1; }
    else vless_plain_candidate_revision=0; fi
  fi

  # Hysteria2 preserves its legacy schema-1 ACME/provider state.  Manual TLS
  # and multi-inbound layouts use the typed inventory so tags, users, rate
  # limits, obfs, masquerade, and CAS revisions survive takeover.
  hy2_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "hysteria2")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${hy2_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( hy2_inbound_count > 0 )); then
    hy2_state_file=$(protocol_state_file hy2) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    hy2_state_schema="1"
    if [[ -f "${hy2_state_file}" ]]; then
      validate_protocol_state_schema hy2 "${hy2_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      hy2_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${hy2_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      hy2_state_schema=${hy2_state_schema//\"/}; hy2_state_schema=${hy2_state_schema//\'/}
    fi
    [[ "${hy2_state_schema}" == 1 || "${hy2_state_schema}" == 2 ]] || {
      printf '[ERROR] hy2_store_candidate: Hysteria2 状态 schema 无法识别；已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ "${hy2_state_schema}" == 2 || "${hy2_inbound_count}" != "1" ]] ||
       plain_proxy_structured_state_active hy2 >/dev/null 2>&1; then
      hy2_rebuild_mode="structured"
      hy2_candidate_file="${backup_dir}/hy2.candidate.json"
      plain_proxy_config_store_candidate hy2 > "${hy2_candidate_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      if [[ -f "$(plain_proxy_structured_store_file hy2 2>/dev/null || true)" ]]; then
        hy2_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file hy2)") || {
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
        }
      else
        hy2_candidate_revision=0
      fi
    fi
  fi

  # AnyTLS keeps its legacy schema-1 state for ACME/provider configurations,
  # while schema 2 uses the shared typed multi-instance store.  Capture the
  # typed candidate before clearing the protocol cache so IDs, users, TLS and
  # revisions survive takeover without flattening them into one legacy user.
  anytls_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "anytls")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${anytls_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( anytls_inbound_count > 0 )); then
    anytls_state_file=$(protocol_state_file anytls) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    anytls_state_schema="1"
    if [[ -f "${anytls_state_file}" ]]; then
      validate_protocol_state_schema anytls "${anytls_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      anytls_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${anytls_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      anytls_state_schema=${anytls_state_schema//\"/}; anytls_state_schema=${anytls_state_schema//\'/}
    fi
    [[ "${anytls_state_schema}" == 1 || "${anytls_state_schema}" == 2 ]] || {
      printf '[ERROR] anytls_store_candidate: AnyTLS 状态 schema 无法识别；已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ "${anytls_state_schema}" == 2 || "${anytls_inbound_count}" != "1" ]] ||
       plain_proxy_structured_state_active anytls >/dev/null 2>&1; then
      anytls_rebuild_mode="structured"
      anytls_candidate_file="${backup_dir}/anytls.candidate.json"
      plain_proxy_config_store_candidate anytls > "${anytls_candidate_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      if [[ -f "$(plain_proxy_structured_store_file anytls 2>/dev/null || true)" ]]; then
        anytls_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file anytls)") || {
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
        }
      else
        anytls_candidate_revision=0
      fi
    fi
  fi

  # Snell is structured-only. Its version/PSK/user-key tuple and v5/v6
  # transport mode must survive takeover exactly; legacy .env state is not a
  # lossless representation and is rejected before the state cache is cleared.
  snell_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "snell")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${snell_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( snell_inbound_count > 0 )); then
    snell_state_file=$(protocol_state_file snell) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    snell_state_schema=""
    if [[ -f "${snell_state_file}" ]]; then
      validate_protocol_state_schema snell "${snell_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      snell_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${snell_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      snell_state_schema=${snell_state_schema//\"/}
      snell_state_schema=${snell_state_schema//\'/}
    fi
    [[ -z "${snell_state_schema}" || "${snell_state_schema}" == 2 ]] || {
      printf '[ERROR] snell_store_candidate: Snell legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    snell_candidate_file="${backup_dir}/snell.candidate.json"
    plain_proxy_config_store_candidate snell > "${snell_candidate_file}" || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ -f "$(plain_proxy_structured_store_file snell 2>/dev/null || true)" ]]; then
      snell_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file snell)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
    else
      snell_candidate_revision=0
    fi
  fi

  # TUIC is structured-only.  Its UUID/password users, mandatory manual TLS,
  # and QUIC transport options have no lossless schema-1 representation, so
  # reject legacy state before clearing the protocol cache and capture a typed
  # candidate while the existing identities and CAS revision are available.
  tuic_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "tuic")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${tuic_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( tuic_inbound_count > 0 )); then
    tuic_state_file=$(protocol_state_file tuic) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    tuic_state_schema=""
    if [[ -f "${tuic_state_file}" ]]; then
      validate_protocol_state_schema tuic "${tuic_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      tuic_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${tuic_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      tuic_state_schema=${tuic_state_schema//\"/}; tuic_state_schema=${tuic_state_schema//\'/}
    fi
    [[ -z "${tuic_state_schema}" || "${tuic_state_schema}" == 2 ]] || {
      printf '[ERROR] tuic_store_candidate: TUIC legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    }
    tuic_candidate_file="${backup_dir}/tuic.candidate.json"
    plain_proxy_config_store_candidate tuic > "${tuic_candidate_file}" || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ -f "$(plain_proxy_structured_store_file tuic 2>/dev/null || true)" ]]; then
      tuic_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file tuic)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
    else
      tuic_candidate_revision=0
    fi
  fi

  # Hysteria is structured-only.  Its auth_str users, mandatory manual TLS,
  # bandwidth, obfs, and QUIC options have no lossless schema-1 form, so
  # reject legacy state before clearing the protocol cache and capture the
  # typed candidate while the existing identities and CAS revision are available.
  hysteria_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "hysteria")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${hysteria_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( hysteria_inbound_count > 0 )); then
    hysteria_state_file=$(protocol_state_file hysteria) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    hysteria_state_schema=""
    if [[ -f "${hysteria_state_file}" ]]; then
      validate_protocol_state_schema hysteria "${hysteria_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      hysteria_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${hysteria_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      hysteria_state_schema=${hysteria_state_schema//\"/}; hysteria_state_schema=${hysteria_state_schema//\'/}
    fi
    [[ -z "${hysteria_state_schema}" || "${hysteria_state_schema}" == 2 ]] || {
      printf '[ERROR] hysteria_store_candidate: Hysteria legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    }
    hysteria_candidate_file="${backup_dir}/hysteria.candidate.json"
    plain_proxy_config_store_candidate hysteria > "${hysteria_candidate_file}" || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ -f "$(plain_proxy_structured_store_file hysteria 2>/dev/null || true)" ]]; then
      hysteria_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file hysteria)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
    else
      hysteria_candidate_revision=0
    fi
  fi

  # NaiveProxy is structured-only. Its multi-user credentials, mandatory
  # manual TLS, TCP/UDP selection, and optional QUIC/client tuning cannot be
  # recovered losslessly from a legacy .env state, so reject legacy state
  # before clearing the cache and capture a typed candidate while identities
  # and CAS metadata are still available.
  naive_inbound_count=$(jq -r '[.inbounds[]? | select(.type == "naive")] | length' "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${naive_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( naive_inbound_count > 0 )); then
    naive_state_file=$(protocol_state_file naive) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    naive_state_schema=""
    if [[ -f "${naive_state_file}" ]]; then
      validate_protocol_state_schema naive "${naive_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      naive_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${naive_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      naive_state_schema=${naive_state_schema//\"/}; naive_state_schema=${naive_state_schema//\'/}
    fi
    [[ -z "${naive_state_schema}" || "${naive_state_schema}" == 2 ]] || {
      printf '[ERROR] naive_store_candidate: NaiveProxy legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    }
    naive_candidate_file="${backup_dir}/naive.candidate.json"
    plain_proxy_config_store_candidate naive > "${naive_candidate_file}" || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ -f "$(plain_proxy_structured_store_file naive 2>/dev/null || true)" ]]; then
      naive_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file naive)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
    else
      naive_candidate_revision=0
    fi
  fi

  # ShadowTLS is a composite structured-only protocol: each managed instance
  # owns one outer ShadowTLS listener and one hidden loopback Mixed detour.
  # Capture its typed candidate before clearing the protocol cache so the
  # composite identity, dependency and CAS revision survive takeover.
  shadowtls_inbound_count=$(config_protocol_inbound_count shadowtls "${SINGBOX_CONFIG_FILE}") || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  [[ "${shadowtls_inbound_count}" =~ ^[0-9]+$ ]] || {
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
  }
  if (( shadowtls_inbound_count > 0 )); then
    shadowtls_state_file=$(protocol_state_file shadowtls) || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    shadowtls_state_schema=""
    if [[ -f "${shadowtls_state_file}" ]]; then
      validate_protocol_state_schema shadowtls "${shadowtls_state_file}" || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      shadowtls_state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${shadowtls_state_file}" | head -n1) || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
      shadowtls_state_schema=${shadowtls_state_schema//\"/}; shadowtls_state_schema=${shadowtls_state_schema//\'/}
    fi
    [[ -z "${shadowtls_state_schema}" || "${shadowtls_state_schema}" == 2 ]] || {
      printf '[ERROR] shadowtls_store_candidate: ShadowTLS legacy state is unsupported; 已保留原状态。\n' >&2
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    shadowtls_candidate_file="${backup_dir}/shadowtls.candidate.json"
    plain_proxy_config_store_candidate shadowtls > "${shadowtls_candidate_file}" || {
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
    }
    if [[ -f "$(plain_proxy_structured_store_file shadowtls 2>/dev/null || true)" ]]; then
      shadowtls_candidate_revision=$(jq -r '.revision' "$(plain_proxy_structured_store_file shadowtls)") || {
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1;
      }
    else
      shadowtls_candidate_revision=0
    fi
  fi

  clear_protocol_state_cache
  ensure_protocol_state_dir
  if ! rm -rf "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi

  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_json=$(jq -c --argjson idx "${inbound_index}" '.inbounds[$idx]' "${SINGBOX_CONFIG_FILE}")
    if jq -e --argjson tags "${SB_UNMANAGED_CLIENT_TAGS_JSON}" '.tag as $tag | $tags | index($tag) != null' <<< "${inbound_json}" >/dev/null; then continue; fi
    protocol=$(config_inbound_protocol "${inbound_json}" 2>/dev/null || true)
    [[ -n "${protocol}" ]] || continue

    case "${protocol}" in
      vless-reality)
        SB_PROTOCOL="vless+reality"
        SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
        SB_UUID=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].uuid // ""' "${SINGBOX_CONFIG_FILE}")
        SB_SNI=$(jq -r --argjson idx "${inbound_index}" --arg fallback "" '.inbounds[$idx].tls.server_name // $fallback' "${SINGBOX_CONFIG_FILE}")
        SB_PRIVATE_KEY=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.private_key // ""' "${SINGBOX_CONFIG_FILE}")
        SB_SHORT_ID_1=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[0] // ""' "${SINGBOX_CONFIG_FILE}")
        SB_SHORT_ID_2=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.reality.short_id[1] // ""' "${SINGBOX_CONFIG_FILE}")
        instance_id="${VLESS_CONFIG_INSTANCE_CANDIDATES[${vless_instance_index}]}"
        SB_VLESS_INBOUND_TAG="${VLESS_CONFIG_INSTANCE_TAGS[${vless_instance_index}]}"
        state_index=""
        if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]]; then
          state_index=$(vless_reality_existing_state_index_for_tag "${SB_VLESS_INBOUND_TAG}" 2>/dev/null || true)
          if [[ -n "${state_index}" ]]; then
            instance_id="${VLESS_REBUILD_STATE_IDS[${state_index}]}"
          fi
        fi
        SB_VLESS_INSTANCE_ID="${instance_id}"
        if [[ -n "${state_index}" ]]; then
          SB_NODE_NAME="${VLESS_REBUILD_STATE_NODE_NAMES[${state_index}]}"
          [[ -n "${SB_NODE_NAME}" ]] || SB_NODE_NAME="$(default_node_name_for_protocol "vless+reality")"
          SB_VLESS_RATE_LIMIT_UP_MBPS="${VLESS_REBUILD_STATE_RATE_UP[${state_index}]}"
          SB_VLESS_RATE_LIMIT_DOWN_MBPS="${VLESS_REBUILD_STATE_RATE_DOWN[${state_index}]}"
        elif [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "1" &&
                "${instance_id}" == "main" &&
                -n "${VLESS_REBUILD_STATE_NODE_NAMES[0]:-}" ]]; then
          SB_NODE_NAME="${VLESS_REBUILD_STATE_NODE_NAMES[0]}"
          SB_VLESS_RATE_LIMIT_UP_MBPS=""
          SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
        else
          SB_VLESS_RATE_LIMIT_UP_MBPS=""
          SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
        fi
        SB_VLESS_ALPN_MODE=$(jq -r --argjson idx "${inbound_index}" '
          (.inbounds[$idx].tls.alpn // []) |
          if . == ["h2", "http/1.1"] then "h2_http1"
          elif . == ["http/1.1"] then "http1"
          else "off"
          end
        ' "${SINGBOX_CONFIG_FILE}")
        SB_VLESS_TCP_FAST_OPEN=$(jq -r --argjson idx "${inbound_index}" 'if .inbounds[$idx].tcp_fast_open == true then "y" else "n" end' "${SINGBOX_CONFIG_FILE}")
        if ! SB_OUTBOUND_POLICY=$(vless_reality_outbound_policy_from_config "${SB_VLESS_INBOUND_TAG}"); then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        if (( vless_instance_index == 0 )); then
          SB_PRIVATE_KEY="${VLESS_CONFIG_REALITY_PRIVATE_KEY}"
          SB_PUBLIC_KEY=""
          if [[ -n "${VLESS_REBUILD_STATE_PRIVATE_KEY:-}" &&
                "${VLESS_REBUILD_STATE_PRIVATE_KEY}" == "${SB_PRIVATE_KEY}" ]]; then
            SB_PUBLIC_KEY="${VLESS_REBUILD_STATE_PUBLIC_KEY:-}"
          fi
          if [[ -z "${SB_PUBLIC_KEY}" && -f "${SB_KEY_FILE}" ]]; then
            key_file_private=$(grep '^PRIVATE_KEY=' "${SB_KEY_FILE}" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r\n ' || true)
            if [[ -n "${SB_PRIVATE_KEY}" && "${key_file_private}" == "${SB_PRIVATE_KEY}" ]]; then
              SB_PUBLIC_KEY=$(grep '^PUBLIC_KEY=' "${SB_KEY_FILE}" 2>/dev/null | head -n1 | cut -d'=' -f2- | tr -d '\r\n ' || true)
            else
              SB_PUBLIC_KEY=""
            fi
          fi
          VLESS_REALITY_DEFAULT_INSTANCE_ID="${VLESS_CONFIG_DEFAULT_INSTANCE_ID}"
          if [[ "${VLESS_REBUILD_STATE_SCHEMA:-none}" == "2" ]] &&
             vless_reality_config_id_exists "${VLESS_REBUILD_STATE_DEFAULT_ID}"; then
            VLESS_REALITY_DEFAULT_INSTANCE_ID="${VLESS_REBUILD_STATE_DEFAULT_ID}"
          fi
          VLESS_REALITY_INSTANCE_IDS="$(IFS=,; printf '%s' "${VLESS_CONFIG_INSTANCE_IDS[*]}")"
          if ! save_vless_reality_protocol_state; then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
        fi
        if ! save_vless_reality_instance_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        vless_instance_index=$((vless_instance_index + 1))
        ;;
      mixed)
        if [[ "${mixed_rebuild_mode}" == "structured" ]]; then
          # All Mixed records were captured before the root state cache was
          # cleared and are published once after this loop.  Do not overwrite
          # the typed store with one-record legacy writes.
          if ! protocol_array_contains "mixed" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
            rebuilt_protocols+=("mixed")
          fi
          continue
        fi
        SB_PROTOCOL="mixed"
        SB_NODE_NAME="${mixed_legacy_node_name:-$(default_node_name_for_protocol "mixed")}"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port' "${SINGBOX_CONFIG_FILE}")
        if jq -e --argjson idx "${inbound_index}" '(.inbounds[$idx].users // []) | length > 0' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_MIXED_AUTH_ENABLED="y"
          SB_MIXED_USERNAME=$(jq -j --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].username // "", "\u0001"' "${SINGBOX_CONFIG_FILE}")
          SB_MIXED_USERNAME=${SB_MIXED_USERNAME%$'\1'}
          SB_MIXED_PASSWORD=$(jq -j --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // "", "\u0001"' "${SINGBOX_CONFIG_FILE}")
          SB_MIXED_PASSWORD=${SB_MIXED_PASSWORD%$'\1'}
        else
          SB_MIXED_AUTH_ENABLED="n"
          SB_MIXED_USERNAME=""
          SB_MIXED_PASSWORD=""
        fi
        if ! save_mixed_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        ;;
      socks)
        if ! protocol_array_contains "socks" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("socks")
        fi
        continue
        ;;
      http)
        if ! protocol_array_contains "http" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("http")
        fi
        continue
        ;;
      shadowsocks)
        if ! protocol_array_contains "shadowsocks" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("shadowsocks")
        fi
        continue
        ;;
      trojan)
        if ! protocol_array_contains "trojan" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("trojan")
        fi
        continue
        ;;
      vmess)
        if ! protocol_array_contains "vmess" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("vmess")
        fi
        continue
        ;;
      vless-plain)
        if ! protocol_array_contains "vless-plain" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("vless-plain")
        fi
        continue
        ;;
      hy2)
        if [[ "${hy2_rebuild_mode}" == "structured" ]]; then
          if ! protocol_array_contains "hy2" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
            rebuilt_protocols+=("hy2")
          fi
          continue
        fi
        SB_PROTOCOL="hy2"
        SB_NODE_NAME="$(default_node_name_for_protocol "hy2")"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_USER_NAME=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_UP_MBPS=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].up_mbps // ""' "${SINGBOX_CONFIG_FILE}")
        SB_HY2_DOWN_MBPS=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].down_mbps // ""' "${SINGBOX_CONFIG_FILE}")
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.type == "salamander"' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_HY2_OBFS_ENABLED="y"
          SB_HY2_OBFS_TYPE="salamander"
          SB_HY2_OBFS_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].obfs.password // ""' "${SINGBOX_CONFIG_FILE}")
        else
          SB_HY2_OBFS_ENABLED="n"
          SB_HY2_OBFS_TYPE=""
          SB_HY2_OBFS_PASSWORD=""
        fi

        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_HY2_TLS_MODE="acme"
          SB_HY2_ACME_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
          SB_HY2_ACME_EMAIL=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
          if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
            SB_HY2_ACME_MODE="dns"
            SB_HY2_DNS_PROVIDER=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
            SB_HY2_CF_API_TOKEN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
          else
            SB_HY2_ACME_MODE="http"
            SB_HY2_DNS_PROVIDER="cloudflare"
            SB_HY2_CF_API_TOKEN=""
          fi
          if ! SB_HY2_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"); then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_HY2_CERT_PATH=""
          SB_HY2_KEY_PATH=""
        elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"; then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_HY2_TLS_MODE="acme"
          SB_HY2_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
          SB_HY2_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
          SB_HY2_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
          SB_HY2_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
          SB_HY2_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
          SB_HY2_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
          SB_HY2_CERT_PATH=""
          SB_HY2_KEY_PATH=""
        else
          SB_HY2_TLS_MODE="manual"
          SB_HY2_ACME_MODE="http"
          SB_HY2_ACME_EMAIL=""
          SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
          SB_HY2_ACME_EXTRA_JSON='{}'
          SB_HY2_DNS_PROVIDER="cloudflare"
          SB_HY2_CF_API_TOKEN=""
          SB_HY2_CERT_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
          SB_HY2_KEY_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
        fi
        SB_HY2_MASQUERADE=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].masquerade // ""' "${SINGBOX_CONFIG_FILE}")
        if ! save_hy2_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        ;;
      anytls)
        if [[ "${anytls_rebuild_mode}" == "structured" ]]; then
          if ! protocol_array_contains "anytls" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
            rebuilt_protocols+=("anytls")
          fi
          continue
        fi
        SB_PROTOCOL="anytls"
        SB_NODE_NAME="$(default_node_name_for_protocol "anytls")"
        SB_PORT=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].listen_port // "443"' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_PASSWORD=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].password // ""' "${SINGBOX_CONFIG_FILE}")
        SB_ANYTLS_USER_NAME=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].users[0].name // ""' "${SINGBOX_CONFIG_FILE}")
        if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          SB_ANYTLS_TLS_MODE="acme"
          if jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
            SB_ANYTLS_ACME_MODE="dns"
            SB_ANYTLS_DNS_PROVIDER=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.provider // "cloudflare"' "${SINGBOX_CONFIG_FILE}")
            SB_ANYTLS_CF_API_TOKEN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.dns01_challenge.api_token // ""' "${SINGBOX_CONFIG_FILE}")
          else
            SB_ANYTLS_ACME_MODE="http"
            SB_ANYTLS_DNS_PROVIDER="cloudflare"
            SB_ANYTLS_CF_API_TOKEN=""
          fi
          if ! SB_ANYTLS_ACME_EXTRA_JSON=$(inline_acme_extra_json_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"); then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_ANYTLS_ACME_EMAIL=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.email // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_ACME_DOMAIN=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.acme.domain[0] // .inbounds[$idx].tls.server_name // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_CERT_PATH=""
          SB_ANYTLS_KEY_PATH=""
        elif jq -e --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_provider? != null' "${SINGBOX_CONFIG_FILE}" &>/dev/null; then
          if ! load_certificate_provider_from_config "${SINGBOX_CONFIG_FILE}" "${inbound_index}"; then
            abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
            return 1
          fi
          SB_ANYTLS_TLS_MODE="acme"
          SB_ANYTLS_ACME_MODE="${CERT_PROVIDER_ACME_MODE}"
          SB_ANYTLS_DNS_PROVIDER="${CERT_PROVIDER_DNS_PROVIDER}"
          SB_ANYTLS_CF_API_TOKEN="${CERT_PROVIDER_CF_API_TOKEN}"
          SB_ANYTLS_ACME_EMAIL="${CERT_PROVIDER_EMAIL}"
          SB_ANYTLS_ACME_DOMAIN="${CERT_PROVIDER_DOMAIN}"
          SB_ANYTLS_ACME_EXTRA_JSON="${CERT_PROVIDER_EXTRA_JSON}"
          SB_ANYTLS_CERT_PATH=""
          SB_ANYTLS_KEY_PATH=""
        else
          SB_ANYTLS_TLS_MODE="manual"
          SB_ANYTLS_ACME_MODE="http"
          SB_ANYTLS_ACME_EMAIL=""
          SB_ANYTLS_ACME_DOMAIN="${SB_ANYTLS_DOMAIN}"
          SB_ANYTLS_ACME_EXTRA_JSON='{}'
          SB_ANYTLS_DNS_PROVIDER="cloudflare"
          SB_ANYTLS_CF_API_TOKEN=""
          SB_ANYTLS_CERT_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.certificate_path // ""' "${SINGBOX_CONFIG_FILE}")
          SB_ANYTLS_KEY_PATH=$(jq -r --argjson idx "${inbound_index}" '.inbounds[$idx].tls.key_path // ""' "${SINGBOX_CONFIG_FILE}")
        fi
        if ! save_anytls_state; then
          abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
          return 1
        fi
        ;;
      snell)
        if ! protocol_array_contains "snell" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("snell")
        fi
        continue
        ;;
      tuic)
        if ! protocol_array_contains "tuic" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("tuic")
        fi
        continue
        ;;
      hysteria)
        if ! protocol_array_contains "hysteria" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("hysteria")
        fi
        continue
        ;;
      naive)
        if ! protocol_array_contains "naive" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("naive")
        fi
        continue
        ;;
      shadowtls)
        if ! protocol_array_contains "shadowtls" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
          rebuilt_protocols+=("shadowtls")
        fi
        continue
        ;;
      *)
        abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
        return 1
        ;;
    esac

    if ! protocol_array_contains "${protocol}" ${rebuilt_protocols[@]+"${rebuilt_protocols[@]}"}; then
      rebuilt_protocols+=("${protocol}")
    fi
  done

  if [[ "${mixed_rebuild_mode}" == "structured" ]]; then
    # The candidate was built from the pre-clear snapshot.  Keep the existing
    # store as the CAS base, publish it once, then write the schema marker;
    # either failure enters the existing whole-state abort path.
    if ! publish_structured_instance_store mixed "${mixed_candidate_file}" "${mixed_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if ! save_mixed_structured_marker; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
  fi

  if (( socks_inbound_count > 0 )); then
    if ! publish_structured_instance_store socks "${socks_candidate_file}" "${socks_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if ! save_plain_proxy_structured_marker socks; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
  fi

  if (( http_inbound_count > 0 )); then
    if ! publish_structured_instance_store http "${http_candidate_file}" "${http_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if ! save_plain_proxy_structured_marker http; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
  fi

  if (( shadowsocks_inbound_count > 0 )); then
    if ! publish_structured_instance_store shadowsocks "${shadowsocks_candidate_file}" "${shadowsocks_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
    if ! save_plain_proxy_structured_marker shadowsocks; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
      return 1
    fi
  fi

  if (( trojan_inbound_count > 0 )); then
    if ! publish_structured_instance_store trojan "${trojan_candidate_file}" "${trojan_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker trojan; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( vmess_inbound_count > 0 )); then
    if ! publish_structured_instance_store vmess "${vmess_candidate_file}" "${vmess_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker vmess; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( vless_plain_inbound_count > 0 )); then
    if ! publish_structured_instance_store vless-plain "${vless_plain_candidate_file}" "${vless_plain_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker vless-plain; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( anytls_inbound_count > 0 )) && [[ "${anytls_rebuild_mode}" == "structured" ]]; then
    if ! publish_structured_instance_store anytls "${anytls_candidate_file}" "${anytls_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker anytls; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( hy2_inbound_count > 0 )) && [[ "${hy2_rebuild_mode}" == "structured" ]]; then
    if ! publish_structured_instance_store hy2 "${hy2_candidate_file}" "${hy2_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker hy2; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( snell_inbound_count > 0 )); then
    if ! publish_structured_instance_store snell "${snell_candidate_file}" "${snell_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker snell; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( tuic_inbound_count > 0 )); then
    if ! publish_structured_instance_store tuic "${tuic_candidate_file}" "${tuic_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker tuic; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( hysteria_inbound_count > 0 )); then
    if ! publish_structured_instance_store hysteria "${hysteria_candidate_file}" "${hysteria_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker hysteria; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( naive_inbound_count > 0 )); then
    if ! publish_structured_instance_store naive "${naive_candidate_file}" "${naive_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker naive; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if (( shadowtls_inbound_count > 0 )); then
    if ! publish_structured_instance_store shadowtls "${shadowtls_candidate_file}" "${shadowtls_candidate_revision}"; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
    if ! save_plain_proxy_structured_marker shadowtls; then
      abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"; return 1
    fi
  fi

  if [[ ${#rebuilt_protocols[@]} -eq 0 ]]; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi

  if ! write_protocol_index "$(IFS=,; printf '%s' "${rebuilt_protocols[*]}")"; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  if ! protocol_state_layer_matches_config; then
    abort_protocol_state_rebuild "${backup_dir}" "${state_dir_existed}"
    return 1
  fi
  rm -rf "${backup_dir}"
  return 0
}

take_over_existing_instance() {
  [[ -f "${SINGBOX_CONFIG_FILE}" ]] || log_error "未找到配置文件，无法接管现有实例。请先按全新安装处理。"
  validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" || return 1
  ensure_takeover_validation_binary
  check_config_valid
  rebuild_protocol_state_from_config || log_error "当前配置未识别到可接管的受支持协议。"
  restore_runtime_artifacts_for_takeover
  if [[ "$(detect_existing_instance_state)" != "healthy" ]]; then
    log_takeover_state_diagnostics
    log_error "接管后实例状态仍不完整，请根据以上诊断信息检查现场。"
  fi
  restart_service_after_takeover
  log_success "现有实例接管完成。"
}

resolve_takeover_binary_repair_version() {
  local recorded_version
  recorded_version=$(extract_recorded_singbox_version_from_index)

  if [[ -n "${recorded_version}" ]]; then
    SB_VERSION="${recorded_version}"
    log_info "接管修复将按本地记录的 sing-box 版本恢复二进制: ${SB_VERSION}"
    return 0
  fi

  SB_VERSION="${SB_SUPPORT_MAX_VERSION}"
  log_warn "未找到本地记录的 sing-box 版本；将回退到当前适配版本 ${SB_VERSION} 进行二进制修复。"
}

ensure_takeover_validation_binary() {
  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    resolve_takeover_binary_repair_version
    get_os_info
    get_arch
    install_dependencies || return $?
    install_binary || return $?
  fi
}

restore_runtime_artifacts_for_takeover() {
  if service_file_needs_repair; then
    setup_service
  fi

  if [[ ! -x "${SBV_BIN_PATH}" ]]; then
    if ! ensure_sbv_command_installed; then
      log_warn "接管流程未能同步全局命令 sbv；请稍后手动重试。"
    fi
  fi
}

restart_service_after_takeover() {
  run_with_progress "重启 sing-box（ACME 签发或 DNS 验证可能需要较长时间）" systemctl restart sing-box
}
