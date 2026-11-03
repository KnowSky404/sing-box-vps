# Historical releases used this literal path, including on custom-home hosts.
readonly SB_LEGACY_PROJECT_DIR="/root/sing-box-vps"
readonly SB_LEGACY_BACKUP_DIR="${SB_LEGACY_PROJECT_DIR}-backups"
readonly SB_STORAGE_MIGRATION_DIR="${SB_DATA_ROOT}/migrations/pending"

storage_needs_recovery() {
  [[ -e "${SB_STORAGE_MIGRATION_DIR}" || -L "${SB_STORAGE_MIGRATION_DIR}" ]]
}

storage_needs_migration() {
  local item found_sidecar=false
  [[ -e "${SB_LEGACY_PROJECT_DIR}" || -L "${SB_LEGACY_PROJECT_DIR}" ||
     -e "${SB_LEGACY_BACKUP_DIR}" || -L "${SB_LEGACY_BACKUP_DIR}" ]] && return 0
  storage_legacy_pending && return 0
  while IFS= read -r -d '' item; do found_sidecar=true; done < <(storage_legacy_sidecar_paths)
  [[ "${found_sidecar}" == false ]] || return 0
  storage_legacy_sbv_has_identity
}

storage_legacy_sbv_has_identity() {
  [[ -f "${SBV_LINK_PATH}" && ! -L "${SBV_LINK_PATH}" ]] || return 1
  grep -Fqx "readonly PROJECT_AUTHOR=\"${PROJECT_AUTHOR}\"" "${SBV_LINK_PATH}" &&
    grep -Fqx "readonly PROJECT_URL=\"${PROJECT_URL}\"" "${SBV_LINK_PATH}"
}

# Only names actually created by historical source belong to this migration.
# Neighbouring administrator files sharing the prefix remain outside its scope.
storage_legacy_sidecar_paths() {
  local path suffix
  for path in "${SB_LEGACY_PROJECT_DIR}".*; do
    [[ -e "${path}" || -L "${path}" ]] || continue
    suffix=${path#"${SB_LEGACY_PROJECT_DIR}."}
    case "${suffix}" in
      management.flock|instance-transactions|rules-previous) printf '%s\0' "${path}" ;;
      *)
        if [[ "${suffix}" =~ ^firewall-reconcile\.[A-Za-z0-9]{6}$ ||
              "${suffix}" =~ ^warp-register\.[A-Za-z0-9]{8}$ ]]; then printf '%s\0' "${path}"; fi
        ;;
    esac
  done
}

storage_migration_error() {
  printf '[ERROR] storage: %s\n' "$1" >&2
  return 1
}

# Used for both source data and recovery material. Never follow source links or
# accept writable non-root parents, devices, sockets or executable shell state
# supplied through a less trusted account.
storage_migration_trusted_path() {
  local path=$1 node owner mode
  [[ "${path}" == /* && "${path}" != *$'\n'* && "${path}" != *'/../'* &&
     "${path}" != *'/./'* ]] || return 1
  node=${path}
  while [[ "${node}" != / ]]; do
    [[ ! -L "${node}" ]] || return 1
    if [[ -e "${node}" ]]; then
      owner=$(stat -c %u -- "${node}") || return 1
      mode=$(stat -c %a -- "${node}") || return 1
      [[ "${owner}" == 0 && "${mode}" =~ ^[0-7]+$ ]] || return 1
      if (( (8#${mode} & 0022) != 0 )); then
        [[ "${node}" != "${path}" && -d "${node}" ]] && (( (8#${mode} & 01000) != 0 )) || return 1
      fi
    fi
    node=$(dirname -- "${node}") || return 1
  done
}

storage_migration_trusted_tree() {
  local root=$1 invalid
  storage_migration_trusted_path "${root}" || return 1
  [[ -d "${root}" ]] || return 1
  invalid=$(find "${root}" \( -type l -o ! -uid 0 -o -perm /022 -o \( ! -type d -a ! -type f \) \) -print -quit) || return 1
  [[ -z "${invalid}" ]]
}

storage_migration_phase() {
  local phase=$1 directory=${SB_STORAGE_MIGRATION_DIR}
  jq --arg phase "${phase}" '.phase=$phase | if $phase=="rollback" then del(.last_error) else . end' "${directory}/journal.json" > "${directory}/journal.next" || return 1
  chmod 600 "${directory}/journal.next" || return 1
  mv -f -- "${directory}/journal.next" "${directory}/journal.json" || return 1
  printf '[INFO] storage migration: %s\n' "${phase}" >&2
}

storage_migration_mark() {
  local name=$1
  jq --arg name "${name}" '.touched[$name]=true' "${SB_STORAGE_MIGRATION_DIR}/journal.json" > "${SB_STORAGE_MIGRATION_DIR}/journal.next" || return 1
  chmod 600 "${SB_STORAGE_MIGRATION_DIR}/journal.next" || return 1
  mv -f -- "${SB_STORAGE_MIGRATION_DIR}/journal.next" "${SB_STORAGE_MIGRATION_DIR}/journal.json"
}

storage_status_json() {
  local legacy=false recovery=false phase=none backup='' pending=false conflict=false unsafe=false item
  storage_needs_migration && legacy=true
  if storage_needs_recovery; then
    recovery=true
    phase=untrusted
    if storage_migration_trusted_path "${SB_STORAGE_MIGRATION_DIR}/journal.json" &&
       [[ -f "${SB_STORAGE_MIGRATION_DIR}/journal.json" ]]; then
      phase=$(jq -r '.phase // "invalid"' "${SB_STORAGE_MIGRATION_DIR}/journal.json" 2>/dev/null) || phase=invalid
      backup=$(jq -r '.backup // ""' "${SB_STORAGE_MIGRATION_DIR}/journal.json" 2>/dev/null) || backup=''
    fi
  fi
  if [[ "${legacy}" == false && "${recovery}" == false && -f "${SB_DATA_ROOT}/migrations/completed.json" ]] &&
     storage_migration_trusted_path "${SB_DATA_ROOT}/migrations/completed.json"; then
    phase=$(jq -r '.phase // "invalid"' "${SB_DATA_ROOT}/migrations/completed.json" 2>/dev/null) || phase=invalid
    backup=$(jq -r '.backup // ""' "${SB_DATA_ROOT}/migrations/completed.json" 2>/dev/null) || backup=''
  fi
  storage_legacy_pending && pending=true
  if [[ -d "${SB_PROJECT_DIR}" ]] && [[ -n "$(find "${SB_PROJECT_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    [[ "${legacy}" != true ]] || conflict=true
  fi
  if [[ "${legacy}" == true ]]; then
    for item in "${SBV_BIN_PATH}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" "${SB_DATA_ROOT}/lib/libcronet.so" "${SBV_LOG_FILE}"; do
      [[ ! -e "${item}" && ! -L "${item}" ]] || conflict=true
    done
    for item in "${SB_LEGACY_PROJECT_DIR}" "${SB_LEGACY_BACKUP_DIR}"; do
      [[ ! -e "${item}" && ! -L "${item}" ]] || storage_migration_trusted_tree "${item}" || unsafe=true
    done
  fi
  jq -n --arg root "${SB_DATA_ROOT}" --arg legacy_root "${SB_LEGACY_PROJECT_DIR}" \
    --arg phase "${phase}" --arg backup "${backup}" --argjson legacy "${legacy}" \
    --argjson recovery "${recovery}" --argjson pending "${pending}" --argjson conflict "${conflict}" --argjson unsafe "${unsafe}" \
    '{layout_version:1,root:$root,legacy_root:$legacy_root,migration_required:$legacy,recovery_required:$recovery,phase:$phase,backup:$backup,legacy_pending:$pending,target_conflict:$conflict,blockers:[if $recovery then "storage_recovery_required" else empty end,if $pending then "legacy_transaction_requires_old_runtime_recovery" else empty end,if $conflict then "target_conflict" else empty end,if $unsafe then "untrusted_legacy_tree" else empty end]}'
}

storage_legacy_pending() {
  local suffix
  for suffix in .instance-write.lock .component-write.lock .rules-write.lock .warp-registration.pending.json; do
    [[ ! -e "${SB_LEGACY_PROJECT_DIR}${suffix}" && ! -L "${SB_LEGACY_PROJECT_DIR}${suffix}" ]] || return 0
  done
  return 1
}

# Decode the literal forms produced by write_env_assignment without evaluating
# shell substitutions. ANSI-C quoting is decoded as bytes, never shell code.
storage_decode_env_literal() {
  local text=$1 result='' state=plain char next index
  local body digits limit number
  if [[ "${text}" == \$\'* ]]; then
    [[ "${text}" == *\' && ${#text} -ge 3 ]] || return 1
    body=${text:2:${#text}-3}
    for ((index=0; index<${#body}; index++)); do
      char=${body:index:1}
      if [[ "${char}" == "'" ]]; then return 1; fi
      if [[ "${char}" != '\' ]]; then result+="${char}"; continue; fi
      index=$((index+1)); (( index < ${#body} )) || return 1
      next=${body:index:1}
      case "${next}" in
        "'"|'"'|'?'|'\') result+="${next}" ;;
        a|b|e|E|f|n|r|t|v)
          printf -v char '%b' "\\${next}" || return 1
          result+="${char}" ;;
        [0-7]|x|u|U)
          digits=''
          case "${next}" in
            [0-7]) digits=${next}; limit=3 ;;
            x) limit=2 ;;
            u) limit=4 ;;
            U) limit=8 ;;
          esac
          while (( index+1 < ${#body} && ${#digits} < limit )); do
            char=${body:index+1:1}
            if [[ "${next}" == [0-7] ]]; then [[ "${char}" == [0-7] ]] || break
            else [[ "${char}" == [0-9a-fA-F] ]] || break
            fi
            digits+="${char}"; index=$((index+1))
          done
          [[ -n "${digits}" && ! "${digits}" =~ ^0+$ ]] || return 1
          if [[ "${next}" == [0-7] ]]; then number="\\0${digits}"; else number="\\${next}${digits}"; fi
          printf -v char '%b' "${number}" || return 1
          [[ -n "${char}" ]] || return 1
          result+="${char}" ;;
        *) return 1 ;;
      esac
    done
    printf '%s' "${result}"
    return 0
  fi
  for ((index=0; index<${#text}; index++)); do
    char=${text:index:1}
    case "${state}:${char}" in
      plain:\'|double:\')
        if [[ "${state}" == plain ]]; then state=single; else result+="${char}"; fi ;;
      single:\') state=plain ;;
      plain:\"|double:\")
        if [[ "${state}" == plain ]]; then state=double; else state=plain; fi ;;
      single:*) result+="${char}" ;;
      plain:\\|double:\\)
        index=$((index+1)); (( index < ${#text} )) || return 1
        next=${text:index:1}
        if [[ "${state}" == double && "${next}" != ['\\$"`'] ]]; then result+='\'; fi
        result+="${next}" ;;
      plain:\$|double:\$|plain:\`|double:\`) return 1 ;;
      plain:*)
        [[ "${char}" != [[:space:]] && "${char}" != [';'\&\|\<\>\(\)] ]] || return 1
        result+="${char}" ;;
      double:*) result+="${char}" ;;
    esac
  done
  [[ "${state}" == plain ]] || return 1
  printf '%s' "${result}"
}

storage_rewrite_path_json() {
  jq --arg old "${SB_LEGACY_PROJECT_DIR}" --arg new "${SB_PROJECT_DIR}" --arg log "${SBV_LOG_FILE}" --arg media "${SB_MEDIA_CHECK_DIR}" '
    def relocated:
      if type=="string" and startswith("/") and test("(^|/)\\.\\.?(/|$)") then error("legacy_ambiguous_material_path")
      elif type=="string" and .==($old+"/sbv.log") then $log
      elif type=="string" and (.==($old+"/media-check") or startswith($old+"/media-check/")) then $media+.[(($old+"/media-check")|length):]
      elif type=="string" and (.==$old or startswith($old+"/")) then $new+.[($old|length):]
      elif type=="array" then map(relocated) else . end;
    def old_related: .==$old or startswith($old+"/");
    def normalized_path:
      split("/") | reduce .[] as $part ([];
        if $part=="" or $part=="." then .
        elif $part==".." then .[0:([length-1,0]|max)] else .+[$part] end) | "/"+join("/");
    def file_masquerade:
      if type=="object" and .type=="file" then
        if (.directory|type)=="string" and (.directory|startswith("/")) then .directory |= relocated
        else error("legacy_implicit_or_relative_file_masquerade_directory") end
      elif type!="string" or (test("^file:";"i")|not) then . else
        . as $original | capture("^(?<scheme>[Ff][Ii][Ll][Ee]:)(?<rest>.*)$";"s") as $parts |
        ($parts.rest | capture("^(?<base>[^?#]*)(?<suffix>[?#].*)?$";"s")) as $tail |
        (if ($tail.base|startswith("//")) then
          ($tail.base[2:] | capture("^(?<authority>[^/]*)(?<path>/.*)?$";"s")) as $url |
          {prefix:($parts.scheme+"//"+$url.authority),authority:$url.authority,path:($url.path // "")}
         else {prefix:$parts.scheme,authority:null,path:$tail.base} end) as $url |
        ($url.path | gsub("%(?<hex>[0-9A-Fa-f]{2})";("\"\\u00"+.hex+"\""|fromjson))) as $decoded |
        ([$url.path,$decoded,($url.path|normalized_path),($decoded|normalized_path)] | any(.[];old_related)) as $related |
        if ($url.path|startswith("/")|not) then error("legacy_implicit_or_relative_file_masquerade_directory")
        elif ($related|not) then $original
        elif ($url.authority!=null and $url.authority!="" and ($url.authority|ascii_downcase)!="localhost") or
             ($url.path|contains("%") or contains("//") or test("(^|/)\\.\\.?(/|$)")) then
          error("unsupported_legacy_file_masquerade_uri")
        else $url.prefix+($url.path|relocated)+($tail.suffix // "") end
      end;
    def dashboard_path:
      if type=="string" then relocated
      elif type=="object" and has("path") then .path |= relocated else . end;
    ([.network_namespaces[]?.tag, (.components[]? | select(.role=="network_namespace") | .tag)] | map(select(type=="string"))) as $namespace_tags |
    walk(if type=="object" then
      . as $object | with_entries(.key as $key | if
        (["data_directory","state_directory","certificate_path","key_path","config_path","private_key_path","client_certificate_path","client_key_path","mca_certificate_path","mca_key_path","static_key_path","certificate_authority_path","crl_path","secret_path","taildrop_directory","executable_path","wrapper_path","initial_path","protect_path","certificate_directory_path","dhcp_lease_files","mesh_psk_file","cache_path","credential_path","usages_path","pid_file"] | index($key)) != null
        then .value |= relocated
        elif .key=="masquerade" then .value |= file_masquerade
        elif .key=="netns" and (.value|type)=="string" then
          .value as $namespace | if ($namespace_tags|index($namespace))==null then .value |= relocated else . end
        elif .key=="path" and ($object.type=="local" or $object.type=="hosts") then .value |= relocated else . end) |
        if (.role=="rule_set" and .type=="local") or (.role=="network_namespace" and .type=="default")
          then .config.path |= relocated else . end |
        if .type=="api" then
          if (.config|type)=="object" and (.config|has("dashboard")) then .config.dashboard |= dashboard_path
          elif has("dashboard") then .dashboard |= dashboard_path else . end
        else . end
      else . end) |
    if (.network_namespaces? | type)=="array" then .network_namespaces |= map(if (.type // "")=="" or .type=="default" then .path |= relocated else . end) else . end |
    if (.experimental.cache_file.path? | type)=="string" then .experimental.cache_file.path |= relocated else . end |
    if (.log.output? | type)=="string" and .log.output!="stdout" and .log.output!="stderr" then .log.output |= relocated else . end |
    if (.experimental.clash_api.external_ui? | type)=="string" then .experimental.clash_api.external_ui |= relocated else . end'
}

storage_migration_rewrite() {
  local tree=$1 file candidate line key raw value protocol
  while IFS= read -r -d '' file; do
    case "${file#"${tree}/"}" in
      config.json|managed-config.generated.json|components.json|routing-policy.json|protocols/instances/*.json)
        if [[ "${file#"${tree}/"}" == protocols/instances/* ]]; then
          protocol=${file##*/}; protocol=${protocol%.json}
          case "${protocol}" in mixed|socks|http|shadowsocks|trojan|vmess|vless-plain|hy2|anytls|snell|tuic|hysteria|naive|shadowtls) ;; *) continue ;; esac
        fi
        candidate=$(mktemp "${file}.storage-next.XXXXXXXX") || return 1
        storage_rewrite_path_json < "${file}" > "${candidate}" || return 1
        jq -e 'type=="object"' "${candidate}" >/dev/null || return 1
        chmod --reference="${file}" "${candidate}" || return 1
        mv -f -- "${candidate}" "${file}" || return 1 ;;
      protocols/hy2.env|protocols/anytls.env)
        candidate=$(mktemp "${file}.storage-next.XXXXXXXX") || return 1
        : > "${candidate}" || return 1
        while IFS= read -r line || [[ -n "${line}" ]]; do
          key=${line%%=*}
          case "${key}" in
            CERT_PATH|KEY_PATH|ACME_EXTRA_JSON|MASQUERADE)
              if [[ "${key}" == MASQUERADE && "${file#"${tree}/"}" != protocols/hy2.env ]]; then
                printf '%s\n' "${line}" >> "${candidate}" || return 1
                continue
              fi
              raw=${line#*=}
              value=$(storage_decode_env_literal "${raw}") || return 1
              if [[ "${key}" == MASQUERADE ]]; then
                value=$(printf '%s' "${value}" | jq -Rs '{masquerade:.}' | storage_rewrite_path_json | jq -r .masquerade) || return 1
              elif [[ "${key}" == ACME_EXTRA_JSON && -n "${value}" ]]; then
                value=$(printf '%s' "${value}" | storage_rewrite_path_json) || return 1
              elif [[ "${value}" == "${SB_LEGACY_PROJECT_DIR}" || "${value}" == "${SB_LEGACY_PROJECT_DIR}/"* ]]; then
                value="${SB_PROJECT_DIR}${value#"${SB_LEGACY_PROJECT_DIR}"}"
              fi
              if [[ "${key}" != ACME_EXTRA_JSON ]]; then
                [[ "${value}" != *[[:cntrl:]]* ]] || return 1
              fi
              printf '%s=%q\n' "${key}" "${value}" >> "${candidate}" || return 1 ;;
            *) printf '%s\n' "${line}" >> "${candidate}" || return 1 ;;
          esac
        done < "${file}"
        chmod --reference="${file}" "${candidate}" || return 1
        mv -f -- "${candidate}" "${file}" || return 1 ;;
    esac
  done < <(find "${tree}" -type f -print0)
}

storage_migration_validate_state() {
  local tree=$1 file protocol value
  for file in "${tree}/protocols/instances/"*.json; do
    [[ -f "${file}" ]] || continue
    protocol=${file##*/}; protocol=${protocol%.json}
    case "${protocol}" in
      mixed|socks|http|shadowsocks|trojan|vmess|vless-plain|hy2|anytls|snell|tuic|hysteria|naive|shadowtls)
        validate_structured_instance_store "${protocol}" "${file}" || return 1 ;;
    esac
  done
  if [[ -f "${tree}/components.json" ]]; then
    value=$(cat "${tree}/components.json") || return 1
    managed_component_state_validate_json "${value}" || return 1
  fi
  if [[ -f "${tree}/routing-policy.json" ]]; then
    value=$(cat "${tree}/routing-policy.json") || return 1
    routing_policy_validate_json "${value}" || return 1
  fi
}

storage_migration_explicit_paths() {
  local file=$1
  # Changing systemd's working directory must not create a second Tailscale
  # identity or Tor data directory, or reinterpret relative material paths.
  jq -e '
    # Disabled project components and disabled TLS do not open their implicit
    # stores. This temporary view must not change the retained source state.
    walk(if type=="object" then
      (if (.components|type)=="array" then .components |= map(select(.enabled!=false)) else . end) |
      if (.tls|type)=="object" and .tls.enabled!=true then del(.tls) else . end
      else . end) |
    [.. | objects |
      select((.type=="tailscale" and ((((.config // .).state_directory // "")|length)==0 or (((.config // .).taildrop_directory // "")|length)==0)) or
             ((.type=="tor" or .type=="acme" or .type=="cloudflare-origin-ca") and (((.config // .).data_directory // "")|length)==0) or
             (.enabled==true and (.acme|type)=="object" and ((.acme.domain // [])|length)>0 and ((.acme.data_directory // "")|length)==0) or
             (.type=="api" and ((.config // .).dashboard as $dashboard |
               $dashboard==true or ($dashboard|type)=="string" and ($dashboard|length)==0 or
               ($dashboard|type)=="object" and $dashboard.enabled==true and (($dashboard.path // "")|length)==0)))] | length==0
  ' "${file}" >/dev/null || return 1
  jq -e '
    [.. | objects | to_entries[] |
      .key as $key | select((["data_directory","state_directory","certificate_path","key_path","config_path","private_key_path","client_certificate_path","client_key_path","mca_certificate_path","mca_key_path","static_key_path","certificate_authority_path","crl_path","secret_path","taildrop_directory","executable_path","wrapper_path","initial_path","protect_path","certificate_directory_path","dhcp_lease_files","mesh_psk_file","cache_path","credential_path","usages_path","pid_file"]|index($key))!=null) |
      .value | if type=="array" then .[] else . end |
      select(type=="string" and length>0 and (startswith("/")|not))] | length==0
  ' "${file}" >/dev/null || return 1
  jq -e '[..|objects|select(.type=="local" or .type=="hosts")|.path?|if type=="array" then .[] else . end|select(type=="string" and length>0 and (startswith("/")|not))]|length==0' "${file}" >/dev/null || return 1
  jq -e '[..|objects|select(.role=="rule_set" and .type=="local")|.config.path|select(type=="string" and length>0 and (startswith("/")|not))]|length==0' "${file}" >/dev/null || return 1
  # Default netns names resolve under /run/netns in the core, independent of
  # cwd. Preserve those names; only absolute managed paths are relocated.
  jq -e '[..|objects|select(.type=="api")|(.config // .).dashboard|
    if type=="string" then . elif type=="object" and .enabled==true then .path else empty end|
    select(type=="string" and length>0 and (startswith("/")|not))]|length==0' "${file}" >/dev/null || return 1
  jq -e '(.log.output? // "") as $output | $output=="" or $output=="stdout" or $output=="stderr" or ($output|startswith("/"))' "${file}" >/dev/null || return 1
  jq -e '(.experimental.clash_api.external_ui? // "") as $ui | $ui=="" or ($ui|startswith("/"))' "${file}" >/dev/null || return 1
  jq -e 'if .experimental.cache_file.enabled?==true then (.experimental.cache_file.path|type)=="string" and (.experimental.cache_file.path|startswith("/")) else true end' "${file}" >/dev/null || return 1
  storage_rewrite_path_json < "${file}" >/dev/null
}

storage_migration_legacy_service_is_supported() {
  local dropins count line trimmed
  # These custom settings can override the private directory/environment or
  # filesystem view. Preserve them and require an operator to reconcile them.
  if grep -Eq '^[[:space:]]*(WorkingDirectory|RootDirectory|RootImage|Environment|EnvironmentFile|PassEnvironment|UnsetEnvironment)[[:space:]]*=' "${SINGBOX_SERVICE_LINK_PATH}"; then
    storage_migration_error unsupported_custom_service_directory; return 1
  fi
  count=$(grep -Ec '^[[:space:]]*ExecStart[[:space:]]*=' "${SINGBOX_SERVICE_LINK_PATH}") || return 1
  [[ "${count}" == 1 ]] || { storage_migration_error unsupported_custom_service_directory; return 1; }
  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed=${line#"${line%%[![:space:]]*}"}
    case "${trimmed}" in ''|\#*|\;*) continue ;; esac
    [[ "${line}" != "ExecStart=${SINGBOX_LINK_PATH} run -c ${SB_LEGACY_PROJECT_DIR}/config.json" ]] || continue
    if [[ "${line}" == *"${SB_LEGACY_PROJECT_DIR}"* || "${line}" == *"${SB_LEGACY_BACKUP_DIR}"* ]]; then
      storage_migration_error unsupported_legacy_service_reference; return 1
    fi
  done < "${SINGBOX_SERVICE_LINK_PATH}"
  dropins=$(systemctl show --property=DropInPaths --value sing-box) || {
    storage_migration_error service_dropins_unavailable; return 1;
  }
  [[ -z "${dropins}" ]] || { storage_migration_error unsupported_custom_service_directory; return 1; }
}

storage_migration_acquire_locks() {
  local old_lock="${SB_LEGACY_PROJECT_DIR}.management.flock" new_lock="${SB_PROJECT_DIR}.management.flock"
  local inherited='' lock_path descriptor backup=''
  if [[ -f "${SB_STORAGE_MIGRATION_DIR}/journal.json" ]]; then
    backup=$(jq -r '.backup // ""' "${SB_STORAGE_MIGRATION_DIR}/journal.json") || return 1
    if [[ -f "${backup}/legacy-siblings/management.flock" && ! -e "${old_lock}" ]]; then
      old_lock="${backup}/legacy-siblings/management.flock"
    fi
  fi
  if [[ "${SB_MANAGEMENT_LOCK_FD:-}" =~ ^[0-9]+$ ]]; then
    inherited=$(readlink "/proc/${BASHPID:-$$}/fd/${SB_MANAGEMENT_LOCK_FD}") || return 1
    [[ "${inherited}" == "${old_lock}" || "${inherited}" == "${new_lock}" ]] || return 1
  fi
  for lock_path in "${old_lock}" "${new_lock}"; do
    storage_migration_trusted_path "${lock_path}" || return 1
    if [[ "${inherited}" == "${lock_path}" ]]; then
      descriptor=${SB_MANAGEMENT_LOCK_FD}
    else
      [[ ! -e "${lock_path}" || -f "${lock_path}" ]] || return 1
      (umask 077; touch -- "${lock_path}") || return 1
      exec {descriptor}>"${lock_path}" || return 1
    fi
    flock -n -x "${descriptor}" || { storage_migration_error management_busy; return 1; }
    if [[ "${lock_path}" == "${old_lock}" ]]; then
      SB_STORAGE_OLD_LOCK_FD=${descriptor}
    else
      SB_STORAGE_NEW_LOCK_FD=${descriptor}
    fi
  done
}

storage_migration_journal_valid() {
  local directory=${SB_STORAGE_MIGRATION_DIR} backup
  storage_migration_trusted_tree "${directory}" || return 1
  jq -e --arg root "${SB_DATA_ROOT}" --arg legacy "${SB_LEGACY_PROJECT_DIR}" '
    .version==1 and .root==$root and .legacy==$legacy and
    (.before_active|type=="boolean") and (.touched|type=="object") and
    (.backup|type=="string") and (.id|test("^migration-[0-9A-Za-z-]+$")) and
    .backup==($root+"/backups/migrations/"+.id)
  ' "${directory}/journal.json" >/dev/null || return 1
  backup=$(jq -r .backup "${directory}/journal.json") || return 1
  storage_migration_trusted_tree "${backup}" || return 1
}

storage_migration_restore() {
  local directory=${SB_STORAGE_MIGRATION_DIR} backup active name destination item owned_target status=0
  storage_migration_journal_valid || { storage_migration_error untrusted_recovery_journal; return 1; }
  backup=$(jq -r .backup "${directory}/journal.json") || return 1
  active=$(jq -r .before_active "${directory}/journal.json") || return 1
  # Recovery may be retried after an administrator repairs another failure.
  # Refuse to overwrite entries replaced in the meantime by unrelated content.
  if jq -e '.touched.links==true' "${directory}/journal.json" >/dev/null; then
    for name in sbv sing-box service; do
      case "${name}" in
        sbv) destination=${SBV_LINK_PATH}; owned_target=${SBV_BIN_PATH} ;;
        sing-box) destination=${SINGBOX_LINK_PATH}; owned_target=${SINGBOX_BIN_PATH} ;;
        service) destination=${SINGBOX_SERVICE_LINK_PATH}; owned_target=${SINGBOX_SERVICE_FILE} ;;
      esac
      storage_migration_recovery_target_owned "${backup}/original-${name}" "${destination}" "${owned_target}" || {
        storage_migration_recovery_conflict; return 1;
      }
    done
  fi
  if jq -e '.touched.legacy_library==true' "${directory}/journal.json" >/dev/null; then
    destination="$(dirname "$(dirname "${SINGBOX_LINK_PATH}")")/lib/libcronet.so"
    storage_migration_recovery_target_owned "${backup}/original-library" "${destination}" "${SB_DATA_ROOT}/lib/libcronet.so" || {
      storage_migration_recovery_conflict; return 1;
    }
  fi
  storage_migration_phase rollback || return 1
  # Stop any newly started service before restoring files; inability to stop
  # leaves all recovery material intact instead of deleting live artifacts.
  if jq -e '.touched.service_stop==true or .touched.links==true' "${directory}/journal.json" >/dev/null; then
    systemctl stop sing-box >> "${directory}/service.log" 2>&1 || { storage_migration_phase rollback_failed; return 1; }
  fi
  for name in legacy-runtime legacy-backups legacy-rules-previous legacy-instance-transactions; do
    case "${name}" in
      legacy-runtime) destination=${SB_LEGACY_PROJECT_DIR} ;;
      legacy-backups) destination=${SB_LEGACY_BACKUP_DIR} ;;
      legacy-rules-previous) destination="${SB_LEGACY_PROJECT_DIR}.rules-previous" ;;
      legacy-instance-transactions) destination="${SB_LEGACY_PROJECT_DIR}.instance-transactions" ;;
    esac
    if [[ -e "${backup}/${name}" ]]; then
      [[ ! -e "${destination}" && ! -L "${destination}" ]] || { status=1; continue; }
      mv -- "${backup}/${name}" "${destination}" || status=1
    fi
  done
  if [[ -d "${backup}/legacy-siblings" ]]; then
    for item in "${backup}/legacy-siblings/"*; do
      [[ -e "${item}" ]] || continue
      destination="${SB_LEGACY_PROJECT_DIR}.${item##*/}"
      [[ ! -e "${destination}" && ! -L "${destination}" ]] || { status=1; continue; }
      mv -- "${item}" "${destination}" || status=1
    done
  fi
  if jq -e '.touched.legacy_library==true' "${directory}/journal.json" >/dev/null; then
    destination="$(dirname "$(dirname "${SINGBOX_LINK_PATH}")")/lib/libcronet.so"
    if storage_migration_recovery_target_owned "${backup}/original-library" "${destination}" "${SB_DATA_ROOT}/lib/libcronet.so"; then
      storage_migration_restore_file "${backup}/original-library" "${destination}" || status=1
    else storage_migration_recovery_conflict; return 1
    fi
  fi
  if jq -e '.touched.links==true' "${directory}/journal.json" >/dev/null; then
    for name in sbv sing-box service; do
      case "${name}" in sbv) destination=${SBV_LINK_PATH} ;; sing-box) destination=${SINGBOX_LINK_PATH} ;; service) destination=${SINGBOX_SERVICE_LINK_PATH} ;; esac
      case "${name}" in sbv) owned_target=${SBV_BIN_PATH} ;; sing-box) owned_target=${SINGBOX_BIN_PATH} ;; service) owned_target=${SINGBOX_SERVICE_FILE} ;; esac
      storage_migration_recovery_target_owned "${backup}/original-${name}" "${destination}" "${owned_target}" || {
        storage_migration_recovery_conflict; return 1;
      }
      if [[ -f "${backup}/original-${name}" ]]; then
        storage_migration_restore_file "${backup}/original-${name}" "${destination}" || status=1
      elif [[ -L "${destination}" ]]; then
        case "${name}" in sbv) [[ "$(readlink "${destination}")" == "${SBV_BIN_PATH}" ]] ;; sing-box) [[ "$(readlink "${destination}")" == "${SINGBOX_BIN_PATH}" ]] ;; service) [[ "$(readlink "${destination}")" == "${SINGBOX_SERVICE_FILE}" ]] ;; esac && rm -- "${destination}" || status=1
      elif [[ -e "${destination}" ]]; then status=1
      fi
    done
    systemctl daemon-reload >> "${directory}/service.log" 2>&1 || status=1
  fi
  for name in runtime sbv sing-box service library log media; do
    jq -e --arg name "${name}" '.touched[$name]==true' "${directory}/journal.json" >/dev/null || continue
    case "${name}" in
      runtime) destination=${SB_PROJECT_DIR} ;;
      sbv) destination=${SBV_BIN_PATH} ;;
      sing-box) destination=${SINGBOX_BIN_PATH} ;;
      service) destination=${SINGBOX_SERVICE_FILE} ;;
      library) destination="${SB_DATA_ROOT}/lib/libcronet.so" ;;
      log) destination=${SBV_LOG_FILE} ;;
      media) destination=${SB_MEDIA_CHECK_DIR} ;;
    esac
    if (( status == 0 )); then rm -rf -- "${destination}" || status=1; fi
  done
  if jq -e '.touched.library==true' "${directory}/journal.json" >/dev/null && (( status == 0 )); then
    storage_remove_system_link "${SB_DATA_ROOT}/bin/libcronet.so" "${SB_DATA_ROOT}/lib/libcronet.so" || status=1
  fi
  if [[ "${active}" == true ]]; then
    systemctl start sing-box >> "${directory}/service.log" 2>&1 || status=1
    systemctl is-active --quiet sing-box >> "${directory}/service.log" 2>&1 || status=1
  fi
  if (( status != 0 )); then storage_migration_phase rollback_failed; return 1; fi
  storage_migration_phase rolled_back || return 1
  rm -rf -- "${directory}/stage" || return 1
  mv -- "${directory}" "${backup}/journal" || return 1
  printf '[WARN] storage migration: rolled_back; recovery_material=%s\n' "${backup}" >&2
}

storage_migration_recovery_target_owned() {
  local original=$1 target=$2 owned_target=$3
  storage_migration_trusted_path "$(dirname "${target}")" || return 1
  if [[ -L "${target}" ]]; then
    [[ "$(stat -c %u -- "${target}")" == 0 && "$(readlink -- "${target}")" == "${owned_target}" ]]
  elif [[ ! -e "${target}" ]]; then
    return 0
  else
    [[ -f "${target}" && -f "${original}" && ! -L "${original}" ]] || return 1
    storage_migration_trusted_path "${target}" || return 1
    cmp -s -- "${original}" "${target}"
  fi
}

storage_migration_recovery_conflict() {
  local directory=${SB_STORAGE_MIGRATION_DIR}
  jq '.last_error="ownership_conflict"' "${directory}/journal.json" > "${directory}/journal.next" || return 1
  chmod 600 "${directory}/journal.next" || return 1
  mv -f -- "${directory}/journal.next" "${directory}/journal.json" || return 1
  storage_migration_phase rollback_failed || return 1
  storage_migration_error ownership_conflict
}

storage_migration_restore_file() {
  local source=$1 target=$2 staged
  storage_migration_trusted_path "$(dirname "${target}")" || return 1
  [[ "$(stat -c %d "$(dirname "${target}")")" == "$(stat -c %d "${SB_DATA_ROOT}/tmp")" ]] || return 1
  staged=$(mktemp "${SB_DATA_ROOT}/tmp/.storage-restore.XXXXXXXX") || return 1
  if ! cp -p -- "${source}" "${staged}" || ! mv -f -- "${staged}" "${target}"; then
    rm -f -- "${staged}"
    return 1
  fi
}

storage_recover() (
  umask 077
  [[ ${EUID} -eq 0 ]] || { storage_migration_error root_required; return 1; }
  storage_needs_recovery || { storage_migration_error no_pending_migration; return 1; }
  storage_migration_journal_valid || { storage_migration_error untrusted_recovery_journal; return 1; }
  storage_migration_acquire_locks || return 1
  storage_migration_restore
)

storage_migrate() (
  umask 077
  local directory=${SB_STORAGE_MIGRATION_DIR} backup stage source_script core library expected actual
  local before_active=false status suffix item destination name journal_created=false finished=false
  local had_unit=false had_core=false bytes available journal_prepare source_parent
  local -a space_sources=()
  [[ ${EUID} -eq 0 ]] || { storage_migration_error root_required; return 1; }
  storage_needs_recovery && { storage_migration_error storage_recovery_required; return 1; }
  storage_needs_migration || return 0
  command -v jq >/dev/null && command -v flock >/dev/null || return 1
  if [[ -e "${SB_LEGACY_PROJECT_DIR}" || -L "${SB_LEGACY_PROJECT_DIR}" ]]; then
    storage_migration_trusted_tree "${SB_LEGACY_PROJECT_DIR}" || { storage_migration_error untrusted_legacy_tree; return 1; }
  fi
  if [[ -e "${SB_LEGACY_BACKUP_DIR}" || -L "${SB_LEGACY_BACKUP_DIR}" ]]; then
    storage_migration_trusted_tree "${SB_LEGACY_BACKUP_DIR}" || { storage_migration_error untrusted_legacy_backups; return 1; }
  fi
  storage_legacy_pending && { storage_migration_error legacy_transaction_requires_old_runtime_recovery; return 1; }
  if [[ -e "${SB_LEGACY_PROJECT_DIR}.rules-previous" ]]; then
    storage_migration_trusted_tree "${SB_LEGACY_PROJECT_DIR}.rules-previous" &&
      jq -e '.phase=="committed"' "${SB_LEGACY_PROJECT_DIR}.rules-previous/transaction.json" >/dev/null || {
        storage_migration_error legacy_rules_snapshot_requires_inspection; return 1;
      }
  fi
  if [[ -e "${SB_LEGACY_PROJECT_DIR}.instance-transactions" ]]; then
    storage_migration_trusted_tree "${SB_LEGACY_PROJECT_DIR}.instance-transactions" || return 1
  fi
  for item in "${SB_PROJECT_DIR}" "${SB_MEDIA_CHECK_DIR}"; do
    [[ ! -e "${item}" || ( -d "${item}" && ! -L "${item}" && -z "$(find "${item}" -mindepth 1 -maxdepth 1 -print -quit)" ) ]] || { storage_migration_error target_data_conflict; return 1; }
  done
  for item in "${SBV_BIN_PATH}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" "${SB_DATA_ROOT}/lib/libcronet.so" "${SB_DATA_ROOT}/bin/libcronet.so" "${SBV_LOG_FILE}"; do
    [[ ! -e "${item}" && ! -L "${item}" ]] || { storage_migration_error target_artifact_conflict; return 1; }
  done
  [[ ! -L "${SB_DATA_ROOT}/migrations/completed.json" ]] || { storage_migration_error untrusted_completion_record; return 1; }
  for item in "${SBV_LINK_PATH}" "${SINGBOX_LINK_PATH}" "${SINGBOX_SERVICE_LINK_PATH}"; do
    storage_migration_trusted_path "${item}" || { storage_migration_error untrusted_system_entry; return 1; }
    [[ ! -e "${item}" || -f "${item}" ]] || return 1
  done
  if [[ -f "${SBV_LINK_PATH}" ]]; then
    bash -n "${SBV_LINK_PATH}" && grep -Fqx "readonly PROJECT_AUTHOR=\"${PROJECT_AUTHOR}\"" "${SBV_LINK_PATH}" &&
      grep -Fqx "readonly PROJECT_URL=\"${PROJECT_URL}\"" "${SBV_LINK_PATH}" || { storage_migration_error unmanaged_sbv_entry; return 1; }
  fi
  core=${SINGBOX_LINK_PATH}
  if [[ -f "${core}" ]]; then
    [[ -x "${core}" ]] && timeout 10 "${core}" version 2>/dev/null | grep -q '^sing-box version ' || { storage_migration_error invalid_legacy_core; return 1; }
    had_core=true
  fi
  if [[ -f "${SINGBOX_SERVICE_LINK_PATH}" ]]; then
    grep -Fqx "ExecStart=${core} run -c ${SB_LEGACY_PROJECT_DIR}/config.json" "${SINGBOX_SERVICE_LINK_PATH}" || { storage_migration_error unmanaged_service_entry; return 1; }
    [[ "${had_core}" == true && -f "${SB_LEGACY_PROJECT_DIR}/config.json" ]] || return 1
    storage_migration_legacy_service_is_supported || return 1
    had_unit=true
  fi
  if systemctl is-active --quiet sing-box >/dev/null 2>&1; then
    [[ "${had_unit}" == true ]] || { storage_migration_error active_unmanaged_service; return 1; }
    before_active=true
  else
    status=$?; [[ "${status}" == 3 || "${status}" == 4 ]] || { storage_migration_error service_status_unavailable; return 1; }
  fi
  source_script=${SB_STORAGE_SCRIPT_SOURCE:-${BASH_SOURCE[0]}}
  [[ -f "${source_script}" && ! -L "${source_script}" ]] || { storage_migration_error invalid_current_runtime; return 1; }
  source_parent=$(CDPATH= cd -- "$(dirname -- "${source_script}")" && pwd -P) || {
    storage_migration_error invalid_current_runtime; return 1;
  }
  source_script="${source_parent}/$(basename -- "${source_script}")"
  storage_migration_trusted_path "${source_script}" && [[ -f "${source_script}" && ! -L "${source_script}" ]] && bash -n "${source_script}" &&
    grep -Fqx "readonly PROJECT_AUTHOR=\"${PROJECT_AUTHOR}\"" "${source_script}" &&
    grep -Fqx "readonly PROJECT_URL=\"${PROJECT_URL}\"" "${source_script}" || { storage_migration_error invalid_current_runtime; return 1; }
  for item in "${SB_LEGACY_PROJECT_DIR}/config.json" "${SB_LEGACY_PROJECT_DIR}/managed-config.generated.json" "${SB_LEGACY_PROJECT_DIR}/components.json"; do
    [[ ! -f "${item}" ]] || storage_migration_explicit_paths "${item}" || { storage_migration_error legacy_implicit_or_relative_paths_require_operator; return 1; }
  done
  storage_initialize || return 1
  # The rollback of old regular system artifacts must also be atomic while
  # keeping its staging files inside the unified private root.
  for item in "${SBV_LINK_PATH}" "${SINGBOX_LINK_PATH}" "${SINGBOX_SERVICE_LINK_PATH}"; do
    [[ "$(stat -c %d "$(dirname "${item}")")" == "$(stat -c %d "${SB_DATA_ROOT}")" ]] || {
      storage_migration_error cross_filesystem_system_rollback_unsupported; return 1;
    }
  done
  library="$(dirname "$(dirname "${core}")")/lib/libcronet.so"
  if [[ -f "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256" ]]; then
    storage_migration_trusted_path "${library}" && [[ -f "${library}" ]] || return 1
    [[ "$(stat -c %d "$(dirname "${library}")")" == "$(stat -c %d "${SB_DATA_ROOT}")" ]] || {
      storage_migration_error cross_filesystem_library_rollback_unsupported; return 1;
    }
  fi
  storage_migration_acquire_locks || return 1
  # Repeat conflict/legacy barriers while holding both old and new locks.
  storage_needs_recovery && return 1
  storage_legacy_pending && return 1
  [[ ! -d "${SB_LEGACY_PROJECT_DIR}" ]] || storage_migration_trusted_tree "${SB_LEGACY_PROJECT_DIR}" || return 1
  while IFS= read -r -d '' item; do
    if [[ -d "${item}" && ! -L "${item}" ]]; then storage_migration_trusted_tree "${item}" || return 1
    else storage_migration_trusted_path "${item}" && [[ -f "${item}" && ! -L "${item}" ]] || return 1
    fi
  done < <(storage_legacy_sidecar_paths)
  for item in "${SB_LEGACY_PROJECT_DIR}" "${SB_LEGACY_BACKUP_DIR}"; do
    [[ -e "${item}" ]] || continue
    [[ "$(stat -c %d "${item}")" == "$(stat -c %d "${SB_DATA_ROOT}")" ]] || {
      storage_migration_error cross_filesystem_legacy_move_unsupported; return 1;
    }
  done
  while IFS= read -r -d '' item; do
    [[ "$(stat -c %d "${item}")" == "$(stat -c %d "${SB_DATA_ROOT}")" ]] || {
      storage_migration_error cross_filesystem_legacy_move_unsupported; return 1;
    }
  done < <(storage_legacy_sidecar_paths)
  for item in "${SB_PROJECT_DIR}" "${SB_MEDIA_CHECK_DIR}"; do
    [[ ! -e "${item}" || ( -d "${item}" && ! -L "${item}" && -z "$(find "${item}" -mindepth 1 -maxdepth 1 -print -quit)" ) ]] || return 1
  done
  for item in "${SBV_BIN_PATH}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" "${SB_DATA_ROOT}/lib/libcronet.so" "${SB_DATA_ROOT}/bin/libcronet.so" "${SBV_LOG_FILE}"; do
    [[ ! -e "${item}" && ! -L "${item}" ]] || return 1
  done
  for item in "${SBV_LINK_PATH}" "${SINGBOX_LINK_PATH}" "${SINGBOX_SERVICE_LINK_PATH}"; do
    storage_migration_trusted_path "${item}" && [[ ! -e "${item}" || -f "${item}" ]] || return 1
  done
  if [[ "${had_unit}" == true ]]; then
    grep -Fqx "ExecStart=${core} run -c ${SB_LEGACY_PROJECT_DIR}/config.json" "${SINGBOX_SERVICE_LINK_PATH}" || return 1
    storage_migration_legacy_service_is_supported || return 1
  fi
  if systemctl is-active --quiet sing-box >/dev/null 2>&1; then
    [[ "${had_unit}" == true ]] || return 1
    before_active=true
  else status=$?; [[ "${status}" == 3 || "${status}" == 4 ]] || return 1; before_active=false
  fi
  [[ "$(stat -c %d "${SB_DATA_ROOT}")" == "$(stat -c %d "$(dirname "${SB_LEGACY_PROJECT_DIR}")")" ]] || {
    storage_migration_error cross_filesystem_legacy_move_unsupported; return 1;
  }
  space_sources=("${source_script}")
  [[ "${had_core}" != true ]] || space_sources+=("${core}")
  [[ ! -f "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256" ]] || space_sources+=("${library}")
  [[ ! -d "${SB_LEGACY_PROJECT_DIR}" ]] || space_sources+=("${SB_LEGACY_PROJECT_DIR}")
  bytes=$(du -sk -- "${space_sources[@]}" | awk '{total+=$1} END {printf "%.0f", total*2+1024}') || return 1
  available=$(df -Pk "${SB_DATA_ROOT}" | awk 'NR==2 {print $4}') || return 1
  [[ "${bytes}" =~ ^[0-9]+$ && "${available}" =~ ^[0-9]+$ ]] && (( available > bytes )) || {
    storage_migration_error insufficient_staging_space; return 1;
  }
  mkdir -p -m 700 "${SB_DATA_ROOT}/backups/migrations" || return 1
  backup=$(mktemp -d "${SB_DATA_ROOT}/backups/migrations/migration-XXXXXXXX") || return 1
  journal_prepare=$(mktemp -d "${SB_DATA_ROOT}/migrations/.prepare-XXXXXXXX") || return 1
  mkdir -m 700 "${journal_prepare}/stage" || { rm -rf -- "${journal_prepare}"; return 1; }
  jq -n --arg root "${SB_DATA_ROOT}" --arg legacy "${SB_LEGACY_PROJECT_DIR}" --arg backup "${backup}" \
    --arg id "${backup##*/}" --argjson active "${before_active}" \
    '{version:1,root:$root,legacy:$legacy,backup:$backup,id:$id,before_active:$active,phase:"prepare",touched:{}}' > "${journal_prepare}/journal.json" || { rm -rf -- "${journal_prepare}"; return 1; }
  chmod 600 "${journal_prepare}/journal.json" || { rm -rf -- "${journal_prepare}"; return 1; }
  mv -- "${journal_prepare}" "${directory}" || { rm -rf -- "${journal_prepare}"; return 1; }
  stage="${directory}/stage"
  journal_created=true
  storage_migration_exit() {
    local result=$?
    trap - EXIT INT TERM
    if [[ "${journal_created}" == true && "${finished}" != true ]]; then
      if ! storage_migration_restore; then printf '[ERROR] storage migration: rollback_failed; run sbv storage recover --json --yes\n' >&2; fi
    fi
    exit "${result}"
  }
  trap storage_migration_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  for name in sbv sing-box service; do
    case "${name}" in sbv) item=${SBV_LINK_PATH} ;; sing-box) item=${SINGBOX_LINK_PATH} ;; service) item=${SINGBOX_SERVICE_LINK_PATH} ;; esac
    [[ ! -f "${item}" ]] || cp -p -- "${item}" "${backup}/original-${name}" || return 1
  done
  if [[ "${before_active}" == true ]]; then
    storage_migration_mark service_stop || return 1
    systemctl stop sing-box > "${directory}/service.log" 2>&1 || return 1
    if systemctl is-active --quiet sing-box >> "${directory}/service.log" 2>&1; then return 1; fi
  fi
  storage_migration_phase validate || return 1
  mkdir -m 700 "${stage}/runtime" || return 1
  [[ ! -d "${SB_LEGACY_PROJECT_DIR}" ]] || cp -a -- "${SB_LEGACY_PROJECT_DIR}/." "${stage}/runtime/" || return 1
  chmod 700 "${stage}/runtime" || return 1
  storage_migration_rewrite "${stage}/runtime" || { storage_migration_error unsupported_legacy_state; return 1; }
  for item in "${stage}/runtime/config.json" "${stage}/runtime/managed-config.generated.json" "${stage}/runtime/components.json"; do
    [[ ! -f "${item}" ]] || storage_migration_explicit_paths "${item}" || { storage_migration_error legacy_implicit_or_relative_paths_require_operator; return 1; }
  done
  cp -p -- "${source_script}" "${stage}/sbv" && chmod 700 "${stage}/sbv" || return 1
  [[ "${had_core}" != true ]] || cp -p -- "${core}" "${stage}/sing-box" || return 1
  library="$(dirname "$(dirname "${core}")")/lib/libcronet.so"
  if [[ -f "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256" ]]; then
    storage_migration_trusted_path "${library}" && [[ -f "${library}" && ! -L "${library}" ]] || return 1
    expected=$(tr -d '[:space:]' < "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256") || return 1
    actual=$(sha256sum "${library}" | awk '{print $1}') || return 1
    [[ "${expected}" =~ ^[0-9a-f]{64}$ && "${expected}" == "${actual}" ]] || { storage_migration_error legacy_library_not_owned; return 1; }
    cp -p -- "${library}" "${stage}/libcronet.so" || return 1
  fi
  if [[ "${had_unit}" == true ]]; then
    while IFS= read -r item || [[ -n "${item}" ]]; do
      case "${item}" in
        ExecStart=*) printf 'ExecStart="%s" run -c "%s"\n' "${SINGBOX_BIN_PATH}" "${SINGBOX_CONFIG_FILE}" ;;
        '[Service]')
          printf '[Service]\nWorkingDirectory=%s\nEnvironment="HOME=%s" "TMPDIR=%s/tmp" "LD_LIBRARY_PATH=%s/lib"\n' "${SB_PROJECT_DIR}" "${SB_PROJECT_DIR}" "${SB_DATA_ROOT}" "${SB_DATA_ROOT}"
          printf 'Environment="XDG_CACHE_HOME=%s/.cache" "XDG_CONFIG_HOME=%s/.config" "XDG_STATE_HOME=%s/.local/state" "XDG_DATA_HOME=%s/.local/share"\n' "${SB_PROJECT_DIR}" "${SB_PROJECT_DIR}" "${SB_PROJECT_DIR}" "${SB_PROJECT_DIR}" ;;
        *) printf '%s\n' "${item}" ;;
      esac
    done < "${SINGBOX_SERVICE_LINK_PATH}" > "${stage}/service" || return 1
    chmod 600 "${stage}/service" || return 1
  fi
  # Path checks require referenced files at their final candidate location.
  # Publication is reversible and remains hidden behind the persistent journal.
  storage_migration_phase commit || return 1
  for name in runtime sbv sing-box service library log media; do
    case "${name}" in
      runtime) item="${stage}/runtime"; destination=${SB_PROJECT_DIR} ;;
      sbv) item="${stage}/sbv"; destination=${SBV_BIN_PATH} ;;
      sing-box) item="${stage}/sing-box"; destination=${SINGBOX_BIN_PATH} ;;
      service) item="${stage}/service"; destination=${SINGBOX_SERVICE_FILE} ;;
      library) item="${stage}/libcronet.so"; destination="${SB_DATA_ROOT}/lib/libcronet.so" ;;
      log) item="${SB_PROJECT_DIR}/sbv.log"; destination=${SBV_LOG_FILE} ;;
      media) item="${SB_PROJECT_DIR}/media-check"; destination=${SB_MEDIA_CHECK_DIR} ;;
    esac
    [[ -e "${item}" ]] || continue
    storage_migration_mark "${name}" || return 1
    if [[ -d "${destination}" ]]; then rmdir -- "${destination}" || return 1; fi
    mv -- "${item}" "${destination}" || return 1
  done
  storage_publish_library_link || return 1
  storage_migration_validate_state "${SB_PROJECT_DIR}" > "${directory}/state-check.log" 2>&1 || {
    storage_migration_error candidate_state_validation_failed; return 1;
  }
  for item in "${SINGBOX_CONFIG_FILE}" "${SB_PROJECT_DIR}/managed-config.generated.json"; do
    [[ -f "${item}" ]] || continue
    [[ -x "${SINGBOX_BIN_PATH}" ]] || return 1
    LD_LIBRARY_PATH="${SB_DATA_ROOT}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" "${SINGBOX_BIN_PATH}" check -c "${item}" >> "${directory}/check.log" 2>&1 || { storage_migration_error candidate_core_check_failed; return 1; }
  done
  storage_migration_mark links || return 1
  for name in sbv sing-box service; do
    case "${name}" in sbv) item=${SBV_LINK_PATH} ;; sing-box) item=${SINGBOX_LINK_PATH} ;; service) item=${SINGBOX_SERVICE_LINK_PATH} ;; esac
    if [[ -f "${backup}/original-${name}" ]]; then
      [[ -f "${item}" && ! -L "${item}" ]] && cmp -s -- "${backup}/original-${name}" "${item}" || return 1
      rm -- "${item}" || return 1
    fi
  done
  storage_publish_system_links sbv >&2 || return 1
  [[ "${had_core}" != true ]] || storage_publish_system_links sing-box >&2 || return 1
  [[ "${had_unit}" != true ]] || storage_publish_system_links service >&2 || return 1
  for item in "${SBV_BIN_PATH}" "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}"; do
    [[ ! -f "${item}" ]] || sha256sum -- "${item}" >> "${directory}/artifacts.sha256" || return 1
  done
  systemctl daemon-reload >> "${directory}/service.log" 2>&1 || return 1
  storage_migration_phase postcheck || return 1
  if [[ "${before_active}" == true ]]; then
    systemctl start sing-box >> "${directory}/service.log" 2>&1 &&
      systemctl is-active --quiet sing-box >> "${directory}/service.log" 2>&1 || { storage_migration_error migrated_service_failed; return 1; }
  fi
  [[ "$(readlink "${SBV_LINK_PATH}")" == "${SBV_BIN_PATH}" ]] || return 1
  [[ "${had_core}" != true || "$(readlink "${SINGBOX_LINK_PATH}")" == "${SINGBOX_BIN_PATH}" ]] || return 1
  [[ "${had_unit}" != true || "$(readlink "${SINGBOX_SERVICE_LINK_PATH}")" == "${SINGBOX_SERVICE_FILE}" ]] || return 1
  sha256sum -c "${directory}/artifacts.sha256" >> "${directory}/check.log" 2>&1 || return 1
  storage_migration_phase cleanup || return 1
  for name in legacy-runtime legacy-backups legacy-rules-previous legacy-instance-transactions; do
    case "${name}" in legacy-runtime) item=${SB_LEGACY_PROJECT_DIR} ;; legacy-backups) item=${SB_LEGACY_BACKUP_DIR} ;; legacy-rules-previous) item="${SB_LEGACY_PROJECT_DIR}.rules-previous" ;; legacy-instance-transactions) item="${SB_LEGACY_PROJECT_DIR}.instance-transactions" ;; esac
    [[ ! -e "${item}" ]] || mv -- "${item}" "${backup}/${name}" || return 1
  done
  mkdir -m 700 "${backup}/legacy-siblings" || return 1
  while IFS= read -r -d '' item; do
    suffix=${item#"${SB_LEGACY_PROJECT_DIR}."}
    mv -- "${item}" "${backup}/legacy-siblings/${suffix}" || return 1
  done < <(storage_legacy_sidecar_paths)
  if [[ -f "${stage}/libcronet.so" ]]; then return 1; fi
  # Remove only the old library proven by its original marker and digest.
  if [[ -f "${SB_DATA_ROOT}/lib/libcronet.so" && -f "${library}" ]]; then
    actual=$(sha256sum "${library}" | awk '{print $1}') || return 1
    [[ "${actual}" == "${expected}" ]] || return 1
    cp -p -- "${library}" "${backup}/original-library" || return 1
    storage_migration_mark legacy_library || return 1
    rm -- "${library}" || return 1
  fi
  storage_migration_phase completed || return 1
  [[ ! -L "${SB_DATA_ROOT}/migrations/completed.json" ]] || return 1
  storage_migration_restore_file "${directory}/journal.json" "${SB_DATA_ROOT}/migrations/completed.json" || return 1
  rm -rf -- "${stage}" || return 1
  mv -- "${directory}" "${backup}/journal" || return 1
  finished=true
  printf '[SUCCESS] storage migration: completed; backup=%s\n' "${backup}" >&2
)

# The menu's old updater can exec the new runtime with its legacy flock still
# open. Close that exact inherited file description only after a completed
# migration; the subsequent normal dispatcher then acquires the new lock.
storage_finish_legacy_handoff() {
  local descriptor=${SB_MANAGEMENT_LOCK_FD:-} target backup=''
  [[ "${descriptor}" =~ ^[0-9]+$ ]] || return 0
  target=$(readlink "/proc/${BASHPID:-$$}/fd/${descriptor}") || return 1
  if [[ -f "${SB_DATA_ROOT}/migrations/completed.json" ]]; then
    storage_migration_trusted_path "${SB_DATA_ROOT}/migrations/completed.json" || return 1
    backup=$(jq -r '.backup // ""' "${SB_DATA_ROOT}/migrations/completed.json") || return 1
  fi
  if [[ "${target}" == "${SB_LEGACY_PROJECT_DIR}.management.flock" ||
        ( -n "${backup}" && "${target}" == "${backup}/legacy-siblings/management.flock" ) ]]; then
    exec {descriptor}>&- || return 1
    unset SB_MANAGEMENT_LOCK_FD SB_MANAGEMENT_LOCK_MODE
  elif [[ "${target}" != "${SB_PROJECT_DIR}.management.flock" ]]; then
    return 1
  fi
}

storage_cli() {
  local operation=${1:-} json=false yes=false status=0 code='' data payload
  [[ $# -gt 0 ]] && shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) [[ "${json}" == false ]] || code=invalid_arguments; json=true ;;
      --yes) [[ "${yes}" == false ]] || code=invalid_arguments; yes=true ;;
      *) code=invalid_arguments ;;
    esac
    shift
  done
  [[ "${json}" == true ]] || code=json_required
  case "${operation}" in status) [[ "${yes}" == false ]] || code=invalid_arguments ;; migrate|recover) [[ "${yes}" == true ]] || code=confirmation_required ;; *) code=unknown_storage_operation ;; esac
  if [[ -n "${code}" ]]; then
    agent_cli_error "storage.${operation}" "${code}" '存储命令参数无效；请先读取 sbv schema storage.status --json 或对应操作说明。'
    return 1
  fi
  if ! agent_current_user_is_root; then
    agent_cli_error "storage.${operation}" root_required '存储操作必须以 root 用户执行。'
    return 1
  fi
  if [[ -z "${code}" ]]; then
    case "${operation}" in
      status) ;;
      migrate) storage_migrate && storage_finish_legacy_handoff || { status=$?; code=migration_failed; } ;;
      recover)
        storage_recover || {
          status=$?; code=recovery_failed
          if storage_migration_journal_valid &&
             jq -e '.last_error=="ownership_conflict"' "${SB_STORAGE_MIGRATION_DIR}/journal.json" >/dev/null; then code=ownership_conflict; fi
        }
        ;;
    esac
  fi
  data=$(storage_status_json) || { printf '{"ok":false,"error":{"code":"storage_status_unavailable"}}\n'; return 1; }
  payload=$(jq -n --arg code "${code}" --argjson status "${status}" --argjson data "${data}" \
    '$data + {ok:($status==0),error:(if $status==0 then null else $code end)}') || return 1
  agent_emit_json_envelope "storage.${operation}" "${status}" "${payload}"
}
