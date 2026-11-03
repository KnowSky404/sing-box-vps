
structured_instance_store_empty_json() {
  local protocol=${1:-mixed}
  structured_instance_store_protocol "${protocol}" >/dev/null || return 1
  jq -cn --arg protocol "${protocol}" '{schema_version:1,protocol:$protocol,revision:0,default_instance_id:"",instances:[]}'
}

structured_instance_store_validate_instance_argument() {
  local file=${1:-} protocol=${2:-mixed} file_size filter transport_json tls_mode flow flow_list
  protocol=$(structured_instance_store_protocol "${protocol}") || return 1
  [[ -n "${file}" && -f "${file}" && ! -L "${file}" ]] || return 1
  file_size=$(wc -c < "${file}") || return 1
  [[ "${file_size}" =~ ^[0-9]+$ && ${file_size} -le 1048576 ]] || return 1
  filter=$(structured_instance_record_jq_filter) || return 1
  jq -es "${filter}"'length == 1 and (.[0] | valid_instance($protocol))' \
    --arg protocol "${protocol}" "${file}" >/dev/null 2>&1 || return 1
  if [[ "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain ]]; then
    transport_json=$(jq -c '.transport' "${file}") || return 1
    validate_v2ray_transport_state_json "${transport_json}" || return 1
    tls_mode=$(jq -r 'if .tls.enabled == true then "tls" else "disabled" end' "${file}") || return 1
    if [[ "${protocol}" == "vless-plain" ]]; then
      flow_list=$(jq -r '.authentication.users[] | .flow // ""' "${file}") || return 1
    else
      flow_list=""
    fi
    while IFS= read -r flow; do
      build_v2ray_transport_profile_json "${protocol/vless-plain/vless}" "${transport_json}" "${tls_mode}" "${flow}" \
        "$(resolve_config_target_singbox_version)" >/dev/null || return 1
    done <<< "${flow_list}"
  fi
}

structured_instance_store_revision() {
  jq -r '.revision' "${1}" 2>/dev/null
}

structured_instance_store_revision_arg() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
  local value=${1#${1%%[!0]*}}
  [[ -n "${value}" ]] || value=0
  if (( ${#value} > 16 )); then
    return 1
  fi
  if (( ${#value} == 16 )) && [[ "${value}" > "9007199254740991" ]]; then
    return 1
  fi
  printf '%s' "${value}"
}

structured_instance_store_candidate() (
  umask 077
  local protocol current_file operation argument expected_revision temp_dir candidate_json status
  protocol=$(structured_instance_store_protocol "${1:-}") || {
    structured_instance_store_error candidate unsupported_protocol; return 1;
  }
  current_file=${2:-}
  operation=${3:-}
  argument=${4:-}
  expected_revision=$(structured_instance_store_revision_arg "${5:-}") || {
    structured_instance_store_error candidate invalid_revision; return 1;
  }
  temp_dir=$(storage_mktemp -d) || return $?
  trap 'if ! rm -rf -- "${temp_dir}"; then structured_instance_store_error candidate cleanup_failed; fi' EXIT
  trap 'return 130' INT
  trap 'return 143' TERM
  trap 'return 129' HUP
  if [[ -n "${current_file}" ]]; then
    [[ -f "${current_file}" && ! -L "${current_file}" ]] || return 1
    head -c 1048577 -- "${current_file}" > "${temp_dir}/current.json" || return $?
  else
    structured_instance_store_empty_json "${protocol}" > "${temp_dir}/current.json" || return $?
  fi
  validate_structured_instance_store "${protocol}" "${temp_dir}/current.json" || return $?
  [[ "$(structured_instance_store_revision "${temp_dir}/current.json")" == "${expected_revision}" ]] || {
    structured_instance_store_error candidate revision_conflict; return 1;
  }
  case "${operation}" in
    create|replace)
      [[ -f "${argument}" && ! -L "${argument}" ]] || return 1
      head -c 1048577 -- "${argument}" > "${temp_dir}/instance.json" || return $?
      structured_instance_store_validate_instance_argument "${temp_dir}/instance.json" "${protocol}" || {
        structured_instance_store_error candidate invalid_instance; return 1;
      }
      ;;
    delete|default)
      structured_instance_store_validate_id "${argument}" || {
        structured_instance_store_error candidate invalid_id; return 1;
      }
      printf 'null\n' > "${temp_dir}/instance.json" || return $?
      ;;
    *) structured_instance_store_error candidate invalid_operation; return 1 ;;
  esac
  if candidate_json=$(jq -cS --arg op "${operation}" --arg id "${argument}" \
      --slurpfile record "${temp_dir}/instance.json" '
    . as $old | $record[0] as $instance |
    if $op == "create" then
      if any(.instances[]; .id == $instance.id) then error("exists") else
        .instances += [$instance] |
        if .default_instance_id == "" then .default_instance_id=$instance.id else . end
      end
    elif $op == "replace" then
      if any(.instances[]; .id == $instance.id and .tag == $instance.tag) then
        .instances |= map(if .id == $instance.id then $instance else . end)
      else error("missing instance or changed tag") end
    elif $op == "delete" then
      if any(.instances[]; .id == $id) then
        .instances |= map(select(.id != $id)) |
        if .default_instance_id == $id then .default_instance_id=(.instances[0].id // "") else . end
      else error("missing") end
    else
      if any(.instances[]; .id == $id) then .default_instance_id=$id else error("missing") end
    end |
    if . == $old then .
    elif $old.revision >= 9007199254740991 then error("revision exhausted")
    else .revision=($old.revision+1) end
  ' "${temp_dir}/current.json" 2>/dev/null); then :; else
    status=$?
    structured_instance_store_error candidate invalid_operation_or_revision
    return "${status}"
  fi
  printf '%s\n' "${candidate_json}" > "${temp_dir}/candidate.json" || return $?
  validate_structured_instance_store "${protocol}" "${temp_dir}/candidate.json" || return $?
  rm -rf -- "${temp_dir}" || {
    status=$?; structured_instance_store_error candidate cleanup_failed; return "${status}";
  }
  trap - EXIT INT TERM HUP
  printf '%s\n' "${candidate_json}"
)

publish_structured_instance_store() (
  # File primitive only: lifecycle callers still need managed state snapshots.
  umask 077
  [[ ${EUID} -eq 0 ]] || { structured_instance_store_error publish root_required; return 1; }
  local protocol candidate_file expected_revision instance_dir target backup lock activation=${4:-}
  local staged="" old_copy="" old_backup_copy="" backup_stage=""
  local had_target=n had_backup=n commit_attempted=n backup_attempted=n
  local current_json current_revision candidate_revision old_semantics new_semantics
  local candidate_hash published_hash old_identities status=0 phase=precheck
  local temporary_files=()
  protocol=$(structured_instance_store_protocol "${1:-}") || {
    structured_instance_store_error publish unsupported_protocol; return 1;
  }
  candidate_file=${2:-}
  expected_revision=$(structured_instance_store_revision_arg "${3:-}") || {
    structured_instance_store_error publish invalid_revision; return 1;
  }
  [[ -f "${candidate_file}" && ! -L "${candidate_file}" ]] || {
    structured_instance_store_error publish invalid_candidate; return 1;
  }
  instance_dir="${SB_PROTOCOL_STATE_DIR}/instances"
  target="${instance_dir}/${protocol}.json"
  backup="${target}.bak"
  lock="${instance_dir}/.${protocol}.write.lock"
  [[ ! -L "${SB_PROTOCOL_STATE_DIR}" && ! -L "${instance_dir}" ]] || {
    structured_instance_store_error publish symlink_rejected; return 1;
  }
  mkdir -p "${instance_dir}" || return $?
  chmod 700 "${instance_dir}" || return $?
  # Never steal an existing marker. SIGKILL/power loss requires inspection;
  # a marker alone is not evidence that a process is still running.
  if mkdir "${lock}" 2>/dev/null; then :; else
    status=$?
    structured_instance_store_error publish lock_unavailable
    return "${status}"
  fi

  structured_write_finish() {
    local initial_status=$1 cleanup_status=0 restore_failed=n file
    if (( initial_status != 0 )); then
      if [[ "${commit_attempted}" == y ]]; then
        if [[ "${had_target}" == y ]]; then
          if mv -f -- "${old_copy}" "${target}"; then :; else restore_failed=y; fi
        else
          if rm -f -- "${target}"; then :; else restore_failed=y; fi
        fi
      fi
      if [[ "${backup_attempted}" == y ]]; then
        if [[ "${had_backup}" == y ]]; then
          if mv -f -- "${old_backup_copy}" "${backup}"; then :; else restore_failed=y; fi
        else
          if rm -f -- "${backup}"; then :; else restore_failed=y; fi
        fi
      fi
      if [[ "${restore_failed}" == y ]]; then
        structured_instance_store_error publish rollback_failed
        printf '[ERROR] recovery artifacts retained; inspect %s before retrying.\n' "${lock}" >&2
        return "${initial_status}"
      fi
      if [[ "${commit_attempted}" == y || "${backup_attempted}" == y ]]; then
        structured_instance_store_error "${phase}" failed_rolled_back
      else
        structured_instance_store_error "${phase}" failed_unchanged
      fi
    fi
    for file in ${temporary_files[@]+"${temporary_files[@]}"}; do
      if rm -f -- "${file}"; then :; else cleanup_status=1; fi
    done
    if (( cleanup_status == 0 )); then
      if rm -f -- "${lock}/recovery"; then :; else cleanup_status=1; fi
      if rmdir "${lock}"; then :; else cleanup_status=1; fi
    fi
    if (( cleanup_status != 0 )); then
      structured_instance_store_error publish cleanup_failed
      printf '[ERROR] target_commit_attempted=%s; inspect %s before retrying.\n' "${commit_attempted}" "${lock}" >&2
      (( initial_status != 0 )) || initial_status=1
    fi
    return "${initial_status}"
  }
  trap 'structured_write_finish "$?"' EXIT
  trap 'return 130' INT
  trap 'return 143' TERM
  trap 'return 129' HUP

  # CAS is checked under the lock. Capture external input once, bounded, then
  # validate and publish only that private capture.
  [[ ! -L "${target}" && ! -L "${backup}" ]] || {
    structured_instance_store_error publish symlink_rejected; return 1;
  }
  [[ ! -e "${target}" || -f "${target}" ]] || return 1
  [[ ! -e "${backup}" || -f "${backup}" ]] || return 1
  phase=stage
  staged=$(storage_mktemp "${instance_dir}/.${protocol}.candidate.XXXXXX") || return $?
  temporary_files+=("${staged}")
  head -c 1048577 -- "${candidate_file}" > "${staged}" || return $?
  [[ "$(stat -c %s "${staged}")" -le 1048576 ]] || return 1
  validate_structured_instance_store "${protocol}" "${staged}" || return $?
  if [[ -f "${target}" ]]; then
    had_target=y
    old_copy=$(storage_mktemp "${instance_dir}/.${protocol}.previous.XXXXXX") || return $?
    temporary_files+=("${old_copy}")
    cp -p -- "${target}" "${old_copy}" || return $?
    validate_structured_instance_store "${protocol}" "${old_copy}" || return $?
    current_json=$(jq -cS . "${old_copy}") || return $?
  else
    current_json=$(structured_instance_store_empty_json "${protocol}") || return $?
  fi
  current_revision=$(jq -r '.revision' <<< "${current_json}") || return $?
  [[ "${expected_revision}" == "${current_revision}" ]] || {
    structured_instance_store_error publish revision_conflict; return 1;
  }
  candidate_revision=$(jq -r '.revision' "${staged}") || return $?
  old_semantics=$(jq -cS '{default_instance_id,instances}' <<< "${current_json}") || return $?
  new_semantics=$(jq -cS '{default_instance_id,instances}' "${staged}") || return $?
  if [[ "${old_semantics}" == "${new_semantics}" ]]; then
    if [[ "${activation}" == rebuild ]]; then
      # A rebuild is an intentional repair transaction.  It keeps the typed
      # semantics byte-for-byte stable while advancing the CAS revision so
      # observers can distinguish the repaired config from the drifted one.
      :
    elif [[ "${activation}" == legacy-empty-activation && "${had_target}" == n &&
          "${current_revision}" == 0 && "${candidate_revision}" == 1 ]] &&
       protocol_state_exists mixed && [[ "$(protocol_instance_state_schema mixed)" == 1 ]]; then
      # Deleting a legacy singleton is a real external lifecycle change even
      # though its first structured representation is an empty tombstone.
      :
    else
      [[ "${candidate_revision}" == "${current_revision}" ]] || return 1
      structured_write_finish 0 || status=$?
      trap - EXIT INT TERM HUP
      return "${status}"
    fi
  fi
  jq -e --argjson old "${current_revision}" \
    '$old < 9007199254740991 and .revision == ($old + 1)' "${staged}" >/dev/null || return $?
  old_identities=$(jq -c '[.instances[] | {id,tag}]' <<< "${current_json}") || return $?
  jq -e --argjson old "${old_identities}" '
    .instances as $new | all($old[]; . as $previous |
      all($new[] | select(.id == $previous.id); .tag == $previous.tag))
  ' "${staged}" >/dev/null || {
    structured_instance_store_error publish tag_immutable; return 1;
  }
  candidate_hash=$(sha256sum "${staged}") || return $?
  candidate_hash=${candidate_hash%% *}
  phase=backup
  if [[ -f "${backup}" ]]; then
    had_backup=y
    old_backup_copy=$(storage_mktemp "${instance_dir}/.${protocol}.previous-backup.XXXXXX") || return $?
    temporary_files+=("${old_backup_copy}")
    cp -p -- "${backup}" "${old_backup_copy}" || return $?
  fi
  printf 'target=%s\nprevious=%s\nprevious_backup=%s\n' \
    "${target}" "${old_copy}" "${old_backup_copy}" > "${lock}/recovery" || return $?
  if [[ "${had_target}" == y ]]; then
    backup_stage=$(storage_mktemp "${instance_dir}/.${protocol}.backup.XXXXXX") || return $?
    temporary_files+=("${backup_stage}")
    cp -- "${old_copy}" "${backup_stage}" || return $?
    chmod 600 "${backup_stage}" || return $?
    backup_attempted=y
    mv -f -- "${backup_stage}" "${backup}" || return $?
  fi
  phase=commit
  commit_attempted=y
  mv -f -- "${staged}" "${target}" || return $?
  phase=postcheck
  validate_structured_instance_store "${protocol}" "${target}" || return $?
  [[ "$(stat -c %a "${target}")" == 600 ]] || return 1
  published_hash=$(sha256sum "${target}") || return $?
  [[ "${published_hash%% *}" == "${candidate_hash}" ]] || return 1
  printf 'state=committed\nsha256=%s\n' "${candidate_hash}" >> "${lock}/recovery" || return $?
  structured_write_finish 0 || status=$?
  trap - EXIT INT TERM HUP
  return "${status}"
)

structured_instance_store_snapshot_json() (
  umask 077
  local protocol=${1:-} file=${2:-} staged snapshot status
  [[ -f "${file}" && ! -L "${file}" ]] || return 1
  staged=$(storage_mktemp) || return $?
  trap 'if ! rm -f -- "${staged}"; then structured_instance_store_error read cleanup_failed; fi' EXIT
  trap 'return 130' INT
  trap 'return 143' TERM
  trap 'return 129' HUP
  head -c 1048577 -- "${file}" > "${staged}" || return $?
  validate_structured_instance_store "${protocol}" "${staged}" || return $?
  snapshot=$(jq -cS . "${staged}") || return $?
  rm -f -- "${staged}" || { status=$?; structured_instance_store_error read cleanup_failed; return "${status}"; }
  trap - EXIT INT TERM HUP
  printf '%s\n' "${snapshot}"
)

render_structured_instance_inbounds() {
  local protocol snapshot transport_json tls_mode transport_list transport_record flow flow_list
  local use_certificate_provider=n
  protocol=$(structured_instance_store_protocol "${1:-}") || { structured_instance_store_error render_inbounds unsupported_protocol; return 1; }
  snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${2:-}") || return $?
  if [[ "${protocol}" == shadowtls ]]; then
    jq -c '.instances[] | [
      ({type:"shadowtls",tag:.tag,listen:.listen.address,listen_port:.listen.port,detour:.detour.tag,version:.version,handshake:.handshake} +
       (if .version == 2 then {password:.authentication.password}
        elif .version == 3 then {users:.authentication.users}
        else {} end) +
       (if (.handshake_for_server_name | length) > 0 then {handshake_for_server_name:.handshake_for_server_name} else {} end) +
       (if .version == 3 then {strict_mode:.strict_mode,wildcard_sni:.wildcard_sni} else {} end)),
      {type:"mixed",tag:.detour.tag,listen:.detour.listen.address,listen_port:.detour.listen.port}
    ] | .[]' <<< "${snapshot}" 2>/dev/null || { structured_instance_store_error render_inbounds render_failed; return 1; }
    return 0
  fi
  if [[ "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain ]]; then
    transport_list=$(jq -c --arg protocol "${protocol}" '.instances[] | [.transport, .tls.enabled, (if $protocol == "vless-plain" then (.authentication.users | map(.flow // "")) else [""] end)]' <<< "${snapshot}") || return 1
    while IFS= read -r transport_record; do
      [[ -n "${transport_record}" ]] || continue
      transport_json=$(jq -c '.[0]' <<< "${transport_record}") || return 1
      tls_mode=$(jq -r 'if .[1] then "tls" else "disabled" end' <<< "${transport_record}") || return 1
      if [[ "${protocol}" == "vless-plain" ]]; then
        flow_list=$(jq -r '.[2][]' <<< "${transport_record}") || return 1
      else
        flow_list=""
      fi
      while IFS= read -r flow; do
        build_v2ray_transport_profile_json "${protocol/vless-plain/vless}" "${transport_json}" "${tls_mode}" "${flow}" "$(resolve_config_target_singbox_version)" >/dev/null || return 1
      done <<< "${flow_list}"
    done <<< "${transport_list}"
  fi
  if [[ "${protocol}" == hy2 ]] && singbox_config_supports_1_14; then use_certificate_provider=y; fi
  jq -c --arg protocol "${protocol}" --arg use_certificate_provider "${use_certificate_provider}" '
    .instances[] |
    ({type:(if $protocol == "vless-plain" then "vless" elif $protocol == "hy2" then "hysteria2" else $protocol end),tag:.tag,listen:.listen.address,listen_port:.listen.port} +
      (if $protocol == "shadowsocks" then
         {method:.authentication.method,password:.authentication.password,
          users:.authentication.users,network:.listen.network}
       elif $protocol == "vless-plain" then
         {users:(.authentication.users | map(if .flow == "" then del(.flow) else . end))}
      elif $protocol == "anytls" then
         {users:.authentication.users}
       elif $protocol == "hy2" then
         {users:.authentication.users}
       elif $protocol == "hysteria" then
       {users:(.authentication.users | map({name,auth_str}))}
       elif $protocol == "naive" then
         {users:(.authentication.users | map({username,password}))} +
         (if .listen.network == ["tcp","udp"] then {} else {network:.listen.network[0]} end)
       elif $protocol == "tuic" then
         {users:(.authentication.users | map({name,uuid,password}))}
       elif $protocol == "snell" then
         {version:.version,psk:.authentication.psk,users:.authentication.users} +
         (if .version == 5 then {obfs_mode:.obfs_mode} else {mode:.mode} end)
       else {users:(if .authentication.enabled then [{username:.authentication.username,password:.authentication.password}] else [] end)} end) +
      (if $protocol == "http" and .tls.enabled then
         {tls:.tls}
      elif ($protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain") and .tls.enabled then
         {tls:(.tls + {alpn:(if .transport.type == "http" or .transport.type == "grpc" then ["h2"] elif .transport.type == "ws" then ["http/1.1"] elif .transport.type == "quic" then ["h3"] else [] end)})}
       elif $protocol == "anytls" then
         {tls:.tls}
       elif $protocol == "hy2" then
         {tls:(.tls + {alpn:["h3"]} |
           if has("acme") and $use_certificate_provider == "y" then
             .certificate_provider=(.acme + {type:"acme"}) | del(.acme)
           else . end)}
       elif $protocol == "tuic" then
         {tls:(.tls + {alpn:["h3"]})}
      elif $protocol == "hysteria" then
         {tls:(.tls + {alpn:["h3"]})}
       elif $protocol == "naive" then
         {tls:.tls}
       else {}
       end) +
      (if $protocol == "trojan" then
         {users:(.authentication.users)} +
         (if .transport.type == "none" then {} else {transport:.transport} end)
      elif $protocol == "vmess" then
         {users:(.authentication.users | map({name,uuid,alterId:.alter_id}))} +
         (if .transport.type == "none" then {} else {transport:.transport} end)
       elif $protocol == "vless-plain" then
         {users:(.authentication.users | map({name,uuid} + (if .flow == "" then {} else {flow:.flow} end)))} +
         (if .transport.type == "none" then {} else {transport:.transport} end)
       else {}
       end) +
      (if $protocol == "hy2" then
         (if .bandwidth.up_mbps != null then {up_mbps:.bandwidth.up_mbps} else {} end) +
         (if .bandwidth.down_mbps != null then {down_mbps:.bandwidth.down_mbps} else {} end) +
         (if .obfs.enabled then {obfs:{type:.obfs.type,password:.obfs.password}} else {} end) +
         (if .masquerade != "" then {masquerade:.masquerade} else {} end)
       elif $protocol == "tuic" then
         (if .tuic.congestion_control != "" then {congestion_control:.tuic.congestion_control} else {} end) +
         (if .tuic.auth_timeout_seconds > 0 then {auth_timeout:((.tuic.auth_timeout_seconds|tostring) + "s")} else {} end) +
         (if .tuic.zero_rtt_handshake then {zero_rtt_handshake:true} else {} end) +
         (if .tuic.heartbeat_seconds > 0 then {heartbeat:((.tuic.heartbeat_seconds|tostring) + "s")} else {} end)
       elif $protocol == "hysteria" then
         {up_mbps:.bandwidth.up_mbps,down_mbps:.bandwidth.down_mbps} +
         (if .obfs.enabled then {obfs:.obfs.password} else {} end) +
         (if .hysteria.initial_packet_size > 0 then {initial_packet_size:.hysteria.initial_packet_size} else {} end) +
         (if .hysteria.disable_path_mtu_discovery then {disable_path_mtu_discovery:true} else {} end) +
         (if .hysteria.max_concurrent_streams > 0 then {max_concurrent_streams:.hysteria.max_concurrent_streams} else {} end) +
         (if .hysteria.stream_receive_window != "" then {stream_receive_window:.hysteria.stream_receive_window} else {} end) +
         (if .hysteria.connection_receive_window != "" then {connection_receive_window:.hysteria.connection_receive_window} else {} end)
       elif $protocol == "naive" then
         (if .naive.quic_congestion_control != "bbr" then {quic_congestion_control:.naive.quic_congestion_control} else {} end)
       else {} end))
  ' <<< "${snapshot}" 2>/dev/null || { structured_instance_store_error render_inbounds render_failed; return 1; }
}

render_structured_instance_route_rules() {
  local protocol snapshot
  protocol=$(structured_instance_store_protocol "${1:-}") || { structured_instance_store_error render_routes unsupported_protocol; return 1; }
  snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${2:-}") || return $?
  if [[ "${protocol}" == shadowtls ]]; then
    jq -c '[.instances[] | {inbound:.detour.tag,action:"sniff"}, (if .outbound_policy == "default" then empty elif .outbound_policy == "direct" then {inbound:.detour.tag,action:"route",outbound:"direct"} else {inbound:.detour.tag,action:"route",outbound:"warp-ep"} end)]' <<< "${snapshot}" 2>/dev/null || { structured_instance_store_error render_routes render_failed; return 1; }
    return 0
  fi
  jq -c '[.instances[] | {inbound:.tag,action:"sniff"}, (if .outbound_policy == "default" then empty elif .outbound_policy == "direct" then {inbound:.tag,action:"route",outbound:"direct"} else {inbound:.tag,action:"route",outbound:"warp-ep"} end)]' <<< "${snapshot}" 2>/dev/null || { structured_instance_store_error render_routes render_failed; return 1; }
}

# Mixed schema-2 activation is explicit: the marker and the typed store must
# both exist and validate.  Legacy mixed.env remains a separate read-only
# schema-1 contract and is never migrated by a read/render operation.
plain_proxy_structured_store_file() {
  local protocol
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  printf '%s/instances/%s.json' "${SB_PROTOCOL_STATE_DIR}" "${protocol}"
}

mixed_structured_store_file() {
  plain_proxy_structured_store_file mixed
}

plain_proxy_structured_marker_is_valid() {
  local marker_file=${1:-} line trimmed installed_count=0 schema_count=0

  [[ -n "${marker_file}" && -f "${marker_file}" && ! -L "${marker_file}" ]] || return 1
  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed=${line}
    # Whitespace-only lines and comments are inert.  Do not evaluate or
    # source any other text from this marker.
    trimmed="${trimmed#${trimmed%%[![:space:]]*}}"
    [[ -z "${trimmed}" ]] && continue
    [[ "${trimmed}" == \#* ]] && continue
    case "${trimmed}" in
      INSTALLED=1|INSTALLED=\"1\"|INSTALLED=\'1\')
        installed_count=$((installed_count + 1))
        ;;
      CONFIG_SCHEMA_VERSION=2|CONFIG_SCHEMA_VERSION=\"2\"|CONFIG_SCHEMA_VERSION=\'2\')
        schema_count=$((schema_count + 1))
        ;;
      *)
        return 1
        ;;
    esac
  done < "${marker_file}"
  [[ "${installed_count}" == "1" && "${schema_count}" == "1" ]]
}

mixed_structured_marker_is_valid() {
  plain_proxy_structured_marker_is_valid "${1:-}"
}

plain_proxy_structured_state_active() {
  local protocol state_file store_file
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  plain_proxy_structured_marker_is_valid "${state_file}" || return 1
  store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store "${protocol}" "${store_file}" || return 1
  jq -e '.instances | length > 0' "${store_file}" >/dev/null 2>&1
}

mixed_structured_state_active() {
  plain_proxy_structured_state_active mixed
}

save_plain_proxy_structured_marker() {
  local protocol state_file staged backup_file store_file
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  state_file=$(protocol_state_file "${protocol}") || return 1
  [[ ! -L "${state_file}" && (! -e "${state_file}" || -f "${state_file}") ]] || return 1
  store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
  [[ -f "${store_file}" ]] || return 1
  validate_structured_instance_store "${protocol}" "${store_file}" || return 1
  staged=$(storage_mktemp "${state_file}.candidate.XXXXXX") || return 1
  if ! {
    write_env_assignment "INSTALLED" "1"
    write_env_assignment "CONFIG_SCHEMA_VERSION" "2"
  } > "${staged}"; then
    rm -f -- "${staged}"
    return 1
  fi
  chmod 600 "${staged}" || {
    rm -f -- "${staged}"
    return 1
  }
  if [[ -f "${state_file}" ]]; then
    backup_file="${state_file}.bak"
    [[ ! -L "${backup_file}" && (! -e "${backup_file}" || -f "${backup_file}") ]] || {
      rm -f -- "${staged}"
      return 1
    }
    persist_file_backup "${state_file}" "${backup_file}" || {
      rm -f -- "${staged}"
      return 1
    }
  fi
  if ! mv -f -- "${staged}" "${state_file}"; then
    rm -f -- "${staged}"
    return 1
  fi
}

save_mixed_structured_marker() {
  save_plain_proxy_structured_marker mixed
}

load_shadowtls_structured_instance() {
  local state_file store_file instance_id default_id snapshot instance_json
  state_file=$(protocol_state_file shadowtls) || return 1
  store_file=$(plain_proxy_structured_store_file shadowtls) || return 1
  plain_proxy_structured_marker_is_valid "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowtls "${store_file}") || return 1
  default_id=$(jq -r '.default_instance_id' <<< "${snapshot}") || return 1
  instance_id=${1:-${default_id}}
  structured_instance_store_validate_id "${instance_id}" || return 1
  instance_json=$(jq -c --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || return 1
  [[ -n "${instance_json}" ]] || return 1
  reset_protocol_instance_runtime_fields
  INSTALLED=1
  CONFIG_SCHEMA_VERSION=2
  SB_PROTOCOL=shadowtls
  SB_INSTANCE_ID=${instance_id}
  SB_MIXED_INSTANCE_ID=${instance_id}
  SB_NODE_NAME=$(jq -r '.name' <<< "${instance_json}") || return 1
  SB_MIXED_INBOUND_TAG=$(jq -r '.tag' <<< "${instance_json}") || return 1
  SB_MIXED_LISTEN_ADDRESS=$(jq -r '.listen.address' <<< "${instance_json}") || return 1
  SB_PORT=$(jq -r '.listen.port' <<< "${instance_json}") || return 1
  SB_OUTBOUND_POLICY=$(jq -r '.outbound_policy' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_VERSION=$(jq -r '.version' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_PASSWORD=$(jq -r '.authentication.password' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_AUTH_JSON=$(jq -c '.authentication.users' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_HANDSHAKE_JSON=$(jq -c '.handshake' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON=$(jq -c '.handshake_for_server_name' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_STRICT_MODE=$(jq -r 'if .strict_mode then "y" else "n" end' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_WILDCARD_SNI=$(jq -r '.wildcard_sni' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_DETOUR_TAG=$(jq -r '.detour.tag' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_DETOUR_PORT=$(jq -r '.detour.listen.port' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_CLIENT_TRUST=$(jq -r '.client_trust' <<< "${instance_json}") || return 1
  SB_SHADOWTLS_CLIENT_TLS_JSON=$(jq -c '.client_tls + {enabled:true}' <<< "${instance_json}") || return 1
  SB_MIXED_AUTH_ENABLED=n
  SB_MIXED_USERNAME=""
  SB_MIXED_PASSWORD=""
  SB_MIXED_STORE_REVISION=$(jq -r '.revision | tostring' <<< "${snapshot}") || return 1
  NODE_NAME=${SB_NODE_NAME}
  PORT=${SB_PORT}
  AUTH_ENABLED=n
  USERNAME=""
  PASSWORD=""
  export INSTALLED CONFIG_SCHEMA_VERSION NODE_NAME PORT AUTH_ENABLED USERNAME PASSWORD
}

load_plain_proxy_structured_instance() {
  local protocol state_file store_file instance_id default_id stream_file field snapshot
  local fields=()
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  if [[ "${protocol}" == shadowtls ]]; then
    load_shadowtls_structured_instance "${2:-}"
    return $?
  fi
  state_file=$(protocol_state_file "${protocol}") || return 1
  store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
  plain_proxy_structured_marker_is_valid "${state_file}" || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1

  # Capture and validate one private snapshot. All subsequent reads use that
  # snapshot so a concurrent store replacement cannot mix revisions.
  snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${store_file}") || return 1
  jq -e '.instances | length > 0' <<< "${snapshot}" >/dev/null 2>&1 || return 1
  default_id=$(jq -r '.default_instance_id' <<< "${snapshot}") || return 1
  instance_id=${2:-${default_id}}
  structured_instance_store_validate_id "${instance_id}" || return 1
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null 2>&1 || return 1

  reset_protocol_instance_runtime_fields
  SB_MIXED_STORE_REVISION=$(jq -r '.revision | tostring' <<< "${snapshot}") || return 1
  [[ "${SB_MIXED_STORE_REVISION}" =~ ^[0-9]+$ ]] || return 1

  # NUL-delimited fields preserve embedded and trailing newlines in names and
  # credentials; the typed validator has already rejected NUL bytes.
  stream_file=$(storage_mktemp) || return 1
  if ! jq -j --arg id "${instance_id}" --arg protocol "${protocol}" '
      .instances[] | select(.id == $id) |
      [.id, .name, .tag, .listen.address, (.listen.port | tostring),
       (if $protocol == "trojan" or $protocol == "tuic" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "hysteria" or $protocol == "naive" then "y" elif .authentication.enabled then "y" else "n" end),
       (if $protocol == "trojan" then "" elif $protocol == "naive" then (.authentication.users[0].username // "") elif $protocol == "tuic" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "hysteria" then (.authentication.users[0].name // "") else (.authentication.username // "") end),
       (if $protocol == "trojan" then "" elif $protocol == "naive" then (.authentication.users[0].password // "") elif $protocol == "tuic" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "hysteria" then (.authentication.users[0].password // .authentication.users[0].auth_str // "") else .authentication.password end),
       .outbound_policy, (if $protocol == "http" or $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then (.tls | tojson) else "" end),
       (if $protocol == "shadowsocks" then (.authentication | tojson) else "" end),
       (if $protocol == "shadowsocks" or $protocol == "naive" then (.listen.network | tojson) else "" end),
       (if $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then (.authentication.users | tojson) else "" end),
       (if $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then (.transport | tojson) else "" end),
       (if $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then .client_trust else "" end),
       (if $protocol == "hy2" then (.bandwidth | tojson) else "" end),
       (if $protocol == "hy2" then (.obfs | tojson) else "" end),
       (if $protocol == "hy2" then .masquerade else "" end),
       (if $protocol == "snell" then (.version | tostring) else "" end),
       (if $protocol == "snell" then (.authentication.psk // "") else "" end),
       (if $protocol == "snell" then (.authentication.users | tojson) else "" end),
       (if $protocol == "snell" then (.obfs_mode // "") else "" end),
       (if $protocol == "snell" then (.obfs_host // "") else "" end),
       (if $protocol == "snell" then (.mode // "") else "" end),
       (if $protocol == "tuic" then (.tuic | tojson) else "" end),
       (if $protocol == "hysteria" then ({bandwidth:.bandwidth,obfs:.obfs,hysteria:.hysteria} | tojson)
        elif $protocol == "naive" then ({network:.listen.network,naive:.naive} | tojson)
        else "" end)] | .[] | ., "\u0000"
    ' <<< "${snapshot}" > "${stream_file}"; then
    rm -f -- "${stream_file}"
    return 1
  fi
  while IFS= read -r -d '' field; do
    fields+=("${field}")
  done < "${stream_file}"
  rm -f -- "${stream_file}"
  [[ ${#fields[@]} -eq 26 ]] || return 1

  INSTALLED=1
  CONFIG_SCHEMA_VERSION=2
  NODE_NAME=${fields[1]}
  PORT=${fields[4]}
  AUTH_ENABLED=${fields[5]}
  USERNAME=${fields[6]}
  PASSWORD=${fields[7]}
  SB_PROTOCOL="${protocol}"
  SB_INSTANCE_ID=${fields[0]}
  SB_MIXED_INSTANCE_ID=${fields[0]}
  SB_NODE_NAME=${fields[1]}
  SB_MIXED_INBOUND_TAG=${fields[2]}
  SB_MIXED_LISTEN_ADDRESS=${fields[3]}
  SB_PORT=${fields[4]}
  SB_MIXED_AUTH_ENABLED=${fields[5]}
  SB_MIXED_USERNAME=${fields[6]}
  SB_MIXED_PASSWORD=${fields[7]}
  SB_OUTBOUND_POLICY=${fields[8]}
  SB_SHADOWSOCKS_AUTH_JSON=${fields[10]}
  SB_SHADOWSOCKS_NETWORK_JSON=${fields[11]}
  SB_TROJAN_AUTH_JSON=${fields[12]}
  SB_TROJAN_TRANSPORT_JSON=${fields[13]}
  SB_TROJAN_CLIENT_TRUST=${fields[14]}
  SB_VMESS_AUTH_JSON=${fields[12]}
  SB_VMESS_TRANSPORT_JSON=${fields[13]}
  SB_VMESS_CLIENT_TRUST=${fields[14]}
  SB_VLESS_PLAIN_AUTH_JSON=${fields[12]}
  SB_VLESS_PLAIN_TRANSPORT_JSON=${fields[13]}
  SB_VLESS_PLAIN_CLIENT_TRUST=${fields[14]}
  if [[ "${protocol}" == "hy2" ]]; then
    SB_HY2_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_HY2_DOMAIN=$(jq -r '.server_name // empty' <<< "${fields[9]}") || return 1
    SB_HY2_TLS_MODE=manual
    SB_HY2_ACME_MODE=http
    SB_HY2_ACME_EMAIL=""
    SB_HY2_ACME_DOMAIN="${SB_HY2_DOMAIN}"
    SB_HY2_ACME_EXTRA_JSON='{}'
    SB_HY2_DNS_PROVIDER=cloudflare
    SB_HY2_CF_API_TOKEN=""
    if jq -e 'has("acme")' <<< "${SB_HY2_TLS_JSON}" >/dev/null; then
      SB_HY2_TLS_MODE=acme
      SB_HY2_ACME_EMAIL=$(jq -r '.acme.email // ""' <<< "${SB_HY2_TLS_JSON}") || return 1
      SB_HY2_ACME_DOMAIN=$(jq -r '.acme.domain[0]' <<< "${SB_HY2_TLS_JSON}") || return 1
      SB_HY2_ACME_EXTRA_JSON=$(normalize_acme_extra_json "$(jq -c '.acme' <<< "${SB_HY2_TLS_JSON}")") || return 1
      if jq -e '.acme | has("dns01_challenge")' <<< "${SB_HY2_TLS_JSON}" >/dev/null; then
        SB_HY2_ACME_MODE=dns
        SB_HY2_CF_API_TOKEN=$(jq -r '.acme.dns01_challenge.api_token' <<< "${SB_HY2_TLS_JSON}") || return 1
      fi
    fi
    SB_HY2_CERT_PATH=$(jq -r '.certificate_path // empty' <<< "${fields[9]}") || return 1
    SB_HY2_KEY_PATH=$(jq -r '.key_path // empty' <<< "${fields[9]}") || return 1
    SB_HY2_AUTH_JSON=${fields[12]}
    SB_HY2_CLIENT_TRUST=${fields[14]}
    SB_HY2_USER_NAME=$(jq -r '.[0].name // empty' <<< "${fields[12]}") || return 1
    SB_HY2_PASSWORD=$(jq -r '.[0].password // empty' <<< "${fields[12]}") || return 1
    SB_HY2_UP_MBPS=$(jq -r '.up_mbps // empty' <<< "${fields[15]}") || return 1
    SB_HY2_DOWN_MBPS=$(jq -r '.down_mbps // empty' <<< "${fields[15]}") || return 1
    if jq -e '.enabled == true' <<< "${fields[16]}" >/dev/null 2>&1; then
      SB_HY2_OBFS_ENABLED=y
      SB_HY2_OBFS_TYPE=$(jq -r '.type' <<< "${fields[16]}") || return 1
      SB_HY2_OBFS_PASSWORD=$(jq -r '.password' <<< "${fields[16]}") || return 1
    else
      SB_HY2_OBFS_ENABLED=n
      SB_HY2_OBFS_TYPE=""
      SB_HY2_OBFS_PASSWORD=""
    fi
    SB_HY2_MASQUERADE=${fields[17]}
  fi
  if [[ "${protocol}" == "snell" ]]; then
    SB_SNELL_VERSION=${fields[18]}
    SB_SNELL_PSK=${fields[19]}
    SB_SNELL_USER_JSON=${fields[20]}
    SB_SNELL_OBFS_MODE=${fields[21]}
    SB_SNELL_OBFS_HOST=${fields[22]}
    SB_SNELL_MODE=${fields[23]}
  fi
  if [[ "${protocol}" == "tuic" ]]; then
    SB_TUIC_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_TUIC_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_TUIC_CLIENT_TRUST=${fields[14]}
    SB_TUIC_CONGESTION_CONTROL=$(jq -r '.congestion_control // "bbr"' <<< "${fields[24]}") || return 1
    SB_TUIC_AUTH_TIMEOUT_SECONDS=$(jq -r '.auth_timeout_seconds // 3' <<< "${fields[24]}") || return 1
    SB_TUIC_HEARTBEAT_SECONDS=$(jq -r '.heartbeat_seconds // 10' <<< "${fields[24]}") || return 1
    SB_TUIC_ZERO_RTT_HANDSHAKE=$(jq -r 'if .zero_rtt_handshake then "y" else "n" end' <<< "${fields[24]}") || return 1
    SB_TUIC_UDP_RELAY_MODE=$(jq -r '.udp_relay_mode // "native"' <<< "${fields[24]}") || return 1
    SB_TUIC_UDP_OVER_STREAM=$(jq -r 'if .udp_over_stream then "y" else "n" end' <<< "${fields[24]}") || return 1
  fi
  if [[ "${protocol}" == "hysteria" ]]; then
    SB_HYSTERIA_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_HYSTERIA_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_HYSTERIA_CLIENT_TRUST=${fields[14]}
    SB_HYSTERIA_UP_MBPS=$(jq -r '.bandwidth.up_mbps' <<< "${fields[25]}") || return 1
    SB_HYSTERIA_DOWN_MBPS=$(jq -r '.bandwidth.down_mbps' <<< "${fields[25]}") || return 1
    if jq -e '.obfs.enabled == true' <<< "${fields[25]}" >/dev/null 2>&1; then SB_HYSTERIA_OBFS_ENABLED=y; else SB_HYSTERIA_OBFS_ENABLED=n; fi
    SB_HYSTERIA_OBFS_PASSWORD=$(jq -r '.obfs.password // ""' <<< "${fields[25]}") || return 1
    SB_HYSTERIA_QUIC_JSON=$(jq -c '.hysteria' <<< "${fields[25]}") || return 1
  fi
  if [[ "${protocol}" == "naive" ]]; then
    SB_NAIVE_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_NAIVE_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_NAIVE_CLIENT_TRUST=${fields[14]}
    SB_NAIVE_NETWORK_JSON=$(jq -c '.network' <<< "${fields[25]}") || return 1
    SB_NAIVE_QUIC_CONGESTION_CONTROL=$(jq -r '.naive.quic_congestion_control // "bbr"' <<< "${fields[25]}") || return 1
    SB_NAIVE_QUIC=$(jq -r 'if .naive.quic then "y" else "n" end' <<< "${fields[25]}") || return 1
    SB_NAIVE_INSECURE_CONCURRENCY=$(jq -r '.naive.insecure_concurrency // 0' <<< "${fields[25]}") || return 1
    SB_NAIVE_STREAM_RECEIVE_WINDOW=$(jq -r '.naive.stream_receive_window // ""' <<< "${fields[25]}") || return 1
    SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW=$(jq -r '.naive.quic_session_receive_window // ""' <<< "${fields[25]}") || return 1
    SB_NAIVE_EXTRA_HEADERS_JSON=$(jq -c '.naive.extra_headers // {}' <<< "${fields[25]}") || return 1
  fi
  if [[ "${protocol}" == "http" ]]; then
    SB_HTTP_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
  else
    SB_HTTP_TLS_JSON=""
  fi
  if [[ "${protocol}" == "anytls" ]]; then
    SB_ANYTLS_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_ANYTLS_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_ANYTLS_CLIENT_TRUST=${fields[14]}
    SB_ANYTLS_DOMAIN=$(jq -r '.server_name // empty' <<< "${SB_ANYTLS_TLS_JSON}") || return 1
    SB_ANYTLS_TLS_MODE=manual
    SB_ANYTLS_CERT_PATH=$(jq -r '.certificate_path // empty' <<< "${SB_ANYTLS_TLS_JSON}") || return 1
    SB_ANYTLS_KEY_PATH=$(jq -r '.key_path // empty' <<< "${SB_ANYTLS_TLS_JSON}") || return 1
    SB_ANYTLS_USER_NAME=${fields[6]}
    SB_ANYTLS_PASSWORD=${fields[7]}
  fi
  if [[ "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "vless-plain" ]]; then
    SB_TROJAN_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_TROJAN_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_TROJAN_TRANSPORT_JSON=$(jq -c . <<< "${fields[13]}" 2>/dev/null) || return 1
    SB_VMESS_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_VMESS_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_VMESS_TRANSPORT_JSON=$(jq -c . <<< "${fields[13]}" 2>/dev/null) || return 1
    SB_VLESS_PLAIN_TLS_JSON=$(jq -c . <<< "${fields[9]}" 2>/dev/null) || return 1
    SB_VLESS_PLAIN_AUTH_JSON=$(jq -c . <<< "${fields[12]}" 2>/dev/null) || return 1
    SB_VLESS_PLAIN_TRANSPORT_JSON=$(jq -c . <<< "${fields[13]}" 2>/dev/null) || return 1
    SB_VLESS_PLAIN_CLIENT_TRUST=${fields[14]}
  else
    SB_TROJAN_TLS_JSON='{"enabled":false}'
    SB_TROJAN_AUTH_JSON='[]'
    SB_TROJAN_TRANSPORT_JSON='{"type":"none"}'
    SB_TROJAN_CLIENT_TRUST="certificate"
    SB_VMESS_TLS_JSON='{"enabled":false}'
    SB_VMESS_AUTH_JSON='[]'
    SB_VMESS_TRANSPORT_JSON='{"type":"none"}'
    SB_VMESS_CLIENT_TRUST="certificate"
    SB_VLESS_PLAIN_TLS_JSON='{"enabled":false}'
    SB_VLESS_PLAIN_AUTH_JSON='[]'
    SB_VLESS_PLAIN_TRANSPORT_JSON='{"type":"none"}'
    SB_VLESS_PLAIN_CLIENT_TRUST="certificate"
  fi
}

load_mixed_structured_instance() {
  if [[ $# -gt 0 ]]; then
    load_plain_proxy_structured_instance mixed "$1"
  else
    load_plain_proxy_structured_instance mixed
  fi
}
