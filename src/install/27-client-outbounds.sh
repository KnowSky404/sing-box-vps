
build_anytls_outbound_example() {
  local public_ip=$1
  local server_host
  server_host=${SB_ANYTLS_DOMAIN:-${public_ip}}

  jq -n \
    --arg server "${server_host}" \
    --arg port "${SB_PORT}" \
    --arg password "${SB_ANYTLS_PASSWORD}" \
    --arg sni "${SB_ANYTLS_DOMAIN:-${server_host}}" \
    '{
      "type": "anytls",
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $password,
      "client_metadata": "",
      "tls": {
        "enabled": true,
        "server_name": $sni
      }
    }'
}

client_outbound_tag_for_protocol() {
  local protocol address_label=${2:-} base suffix up='' down=''
  protocol=$(normalize_protocol_id "$1")
  if [[ -n "${SB_NODE_NAME:-}" ]]; then
    # Preserve historical technical tags, including long tags. Display-name
    # shortening must not change selectors or route references in client JSON.
    base=$(normalize_node_name "${SB_NODE_NAME}") || return 1
    case "${protocol}" in
      vless-reality) up=${SB_VLESS_RATE_LIMIT_UP_MBPS:-}; down=${SB_VLESS_RATE_LIMIT_DOWN_MBPS:-} ;;
      hy2) up=${SB_HY2_UP_MBPS:-}; down=${SB_HY2_DOWN_MBPS:-} ;;
    esac
    suffix=$(bandwidth_limit_name_suffix "${up}" "${down}") || return 1
    [[ -z "${suffix}" ]] || base="${base}-${suffix}"
    node_name_for_network_stack "${base}" "${address_label}"
    return $?
  fi

  printf '%s' "$(default_node_name_for_protocol "$(state_protocol_to_runtime "${protocol}")")"
}

build_client_vless_reality_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local outbound_tag=${2:-$(client_outbound_tag_for_protocol "vless-reality")}
  local alpn_json

  alpn_json=$(vless_reality_alpn_json_for_mode "${SB_VLESS_ALPN_MODE:-off}")

  jq -n \
    --arg tag "${outbound_tag}" \
    --arg server "${public_ip}" \
    --arg port "${SB_PORT}" \
    --arg uuid "${SB_UUID}" \
    --arg server_name "${SB_SNI}" \
    --arg public_key "${SB_PUBLIC_KEY}" \
    --arg short_id "${SB_SHORT_ID_1}" \
    --arg tcp_fast_open "${SB_VLESS_TCP_FAST_OPEN:-n}" \
    --argjson alpn "${alpn_json}" \
    '{
      "type": "vless",
      "tag": $tag,
      "server": $server,
      "server_port": ($port | tonumber),
      "uuid": $uuid,
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": $server_name,
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": $public_key,
          "short_id": $short_id
        }
      }
    }
    | if $tcp_fast_open == "y" then . + { "tcp_fast_open": true } else . end
    | if $alpn == null then . else .tls += { "alpn": $alpn } end'
}

vless_reality_client_tag_is_used() {
  local candidate=$1
  shift || true
  local used

  for used in "$@"; do
    [[ "${used}" == "${candidate}" ]] && return 0
  done

  return 1
}

unique_vless_reality_client_tag() {
  local base_tag=$1
  local instance_id=$2
  local port=$3
  shift 3 || true
  local candidate counter

  candidate=${base_tag}
  if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
    printf '%s' "${candidate}"
    return 0
  fi

  candidate="${base_tag}-${instance_id}"
  if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
    printf '%s' "${candidate}"
    return 0
  fi

  candidate="${base_tag}-${port}"
  if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
    printf '%s' "${candidate}"
    return 0
  fi

  counter=2
  while true; do
    candidate="${base_tag}-${instance_id}-${counter}"
    if ! vless_reality_client_tag_is_used "${candidate}" "$@"; then
      printf '%s' "${candidate}"
      return 0
    fi
    counter=$((counter + 1))
  done
}

build_client_vless_reality_outbounds() {
  local public_ip=${1:-$(get_public_ip)}
  local instance_id outbound_json base_tag outbound_tag instance_ids
  local default_instance_id=""
  local status=0 adapter_status count=0
  local used_tags=()
  local outbound_fragments=()

  if instance_ids=$(list_protocol_instance_ids "vless-reality"); then
    :
  else
    adapter_status=$?
    return "${adapter_status}"
  fi
  if default_instance_id=$(protocol_default_instance_id "vless-reality"); then
    :
  else
    adapter_status=$?
    return "${adapter_status}"
  fi

  while IFS= read -r instance_id; do
    [[ -z "${instance_id}" ]] && continue
    if load_protocol_instance_state "vless-reality" "${instance_id}"; then
      :
    else
      adapter_status=$?
      [[ "${status}" == "0" ]] && status="${adapter_status}"
      continue
    fi
    base_tag=$(client_outbound_tag_for_protocol "vless-reality")
    outbound_tag=$(unique_vless_reality_client_tag "${base_tag}" "${instance_id}" "${SB_PORT}" ${used_tags[@]+"${used_tags[@]}"})
    if outbound_json=$(build_client_vless_reality_outbound "${public_ip}" "${outbound_tag}"); then
      outbound_fragments+=("${outbound_json}")
      used_tags+=("${outbound_tag}")
      count=$((count + 1))
    else
      status=$?
      break
    fi
  done <<< "${instance_ids}"

  if [[ -n "${default_instance_id}" ]]; then
    if load_protocol_instance_state "vless-reality" "${default_instance_id}" >/dev/null 2>&1; then
      :
    else
      adapter_status=$?
      [[ "${status}" == "0" ]] && status="${adapter_status}"
    fi
  fi

  if (( status != 0 )); then
    return "${status}"
  fi
  if (( count == 0 )); then
    log_warn "未找到可用的 VLESS + REALITY 实例，无法生成节点连接材料: vless-reality" >&2
    return 1
  fi

  for outbound_json in "${outbound_fragments[@]}"; do
    printf '%s\n' "${outbound_json}" || return 1
  done
  return 0
}

build_client_hy2_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local server_host tls_server_name disable_chrome_parrot="n"
  server_host=${public_ip}
  tls_server_name=${SB_HY2_DOMAIN:-${public_ip}}
  if hy2_client_needs_chrome_parrot_disabled; then
    disable_chrome_parrot="y"
  fi

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "hy2")" \
    --arg server "${server_host}" \
    --arg port "${SB_PORT}" \
    --arg password "${SB_HY2_PASSWORD}" \
    --arg server_name "${tls_server_name}" \
    --arg up_mbps "${SB_HY2_UP_MBPS}" \
    --arg down_mbps "${SB_HY2_DOWN_MBPS}" \
    --arg obfs_enabled "${SB_HY2_OBFS_ENABLED}" \
    --arg obfs_type "${SB_HY2_OBFS_TYPE}" \
    --arg obfs_password "${SB_HY2_OBFS_PASSWORD}" \
    --arg disable_chrome_parrot "${disable_chrome_parrot}" \
    '{
      "type": "hysteria2",
      "tag": $tag,
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $password,
      "tls": {
        "enabled": true,
        "server_name": $server_name
      }
    } + (
      if $disable_chrome_parrot == "y" then
        { "disable_chrome_parrot": true }
      else
        {}
      end
    ) + (
      if ($up_mbps | length) > 0 then
        { "up_mbps": ($up_mbps | tonumber) }
      else
        {}
      end
    ) + (
      if ($down_mbps | length) > 0 then
        { "down_mbps": ($down_mbps | tonumber) }
      else
        {}
      end
    ) + (
      if $obfs_enabled == "y" then
        {
          "obfs": {
            "type": $obfs_type,
            "password": $obfs_password
          }
        }
      else
        {}
      end
    )'
}

build_client_hy2_outbounds() (
  local public_ip=${1:-} store_override=${2:-} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address expected_count output_count
  local raw_file raw_outbound tls_json trust server_name certificate_path certificate_pem disable_chrome_parrot

  if [[ -n "${store_override}" ]]; then
    store_file=${store_override}
  else
    store_file=$(plain_proxy_structured_store_file hy2) || return 1
  fi
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"
  output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file=$(mktemp "${tmpdir}/store.XXXXXX") || return 1
    jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    if listener_address_is_wildcard "${listen_address}"; then
      server_address=${public_ip}
    else
      case "${listen_address}" in
        127.*|::1)
          server_address=${listen_address}
          printf '[WARN] Hysteria2 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' "${instance_id}" "${listen_address}" >&2
          ;;
        *) server_address=${listen_address} ;;
      esac
    fi
    [[ -n "${server_address}" ]] || return 1
    raw_file=$(mktemp "${tmpdir}/raw.XXXXXX") || return 1
    jq -c --arg server "${server_address}" '
      .instances[] as $instance | $instance.authentication.users[] as $user |
      {type:"hysteria2",tag:("hy2-" + $instance.id + "-user-" + ($user.name | @base64)),server:$server,
       server_port:$instance.listen.port,password:$user.password,
       _tls:$instance.tls,_client_trust:$instance.client_trust,
       _bandwidth:$instance.bandwidth,_obfs:$instance.obfs}
    ' "${instance_file}" > "${raw_file}" || return 1
    while IFS= read -r raw_outbound; do
      [[ -n "${raw_outbound}" ]] || continue
      tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
      server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
      trust=$(jq -er '._client_trust' <<< "${raw_outbound}") || return 1
      certificate_path=$(jq -r '._tls.certificate_path // ""' <<< "${raw_outbound}") || return 1
      case "${trust}" in
        system)
          tls_json=$(jq -cn --arg server_name "${server_name}" '{enabled:true,server_name:$server_name}') || return 1
          if singbox_config_supports_1_14 && hy2_certificate_path_uses_ed25519 "${certificate_path}"; then
            disable_chrome_parrot=true
          else
            disable_chrome_parrot=false
          fi
          ;;
        certificate)
          certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
          tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
          if singbox_config_supports_1_14 && hy2_certificate_path_uses_ed25519 "${certificate_path}"; then
            disable_chrome_parrot=true
          else
            disable_chrome_parrot=false
          fi
          ;;
        *) return 1 ;;
      esac
      jq -c --argjson tls "${tls_json}" --argjson disable_chrome_parrot "${disable_chrome_parrot}" '
        del(._tls,._client_trust) | .tls=$tls |
        if $disable_chrome_parrot then .disable_chrome_parrot=true else . end |
        if ._bandwidth.up_mbps != null then .up_mbps=._bandwidth.up_mbps else . end |
        if ._bandwidth.down_mbps != null then .down_mbps=._bandwidth.down_mbps else . end |
        if ._obfs.enabled then .obfs={type:._obfs.type,password:._obfs.password} else . end |
        del(._bandwidth,._obfs)
      ' <<< "${raw_outbound}" >> "${output_file}" || return 1
    done < "${raw_file}"
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_anytls_outbound() {
  local public_ip=${1:-$(get_public_ip)}
  local server_host
  server_host=${SB_ANYTLS_DOMAIN:-${public_ip}}

  jq -n \
    --arg tag "$(client_outbound_tag_for_protocol "anytls")" \
    --arg server "${server_host}" \
    --arg port "${SB_PORT}" \
    --arg password "${SB_ANYTLS_PASSWORD}" \
    --arg server_name "${SB_ANYTLS_DOMAIN:-${server_host}}" \
    '{
      "type": "anytls",
      "tag": $tag,
      "server": $server,
      "server_port": ($port | tonumber),
      "password": $password,
      "tls": {
        "enabled": true,
        "server_name": $server_name
      }
    }'
}

build_client_anytls_outbounds() (
  local public_ip=${1:-} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address expected_count output_count

  store_file=$(plain_proxy_structured_store_file anytls) || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json anytls "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"
  output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file=$(mktemp "${tmpdir}/store.XXXXXX") || return 1
    jq --arg id "${instance_id}" '
      . as $root |
      ($root.instances | map(select(.id == $id))) as $instances |
      $root | .default_instance_id=$id | .instances=$instances
    ' <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -er --arg id "${instance_id}" \
      '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::)
        server_address=${public_ip}
        ;;
      127.*|::1)
        server_address=${listen_address}
        printf '[WARN] AnyTLS 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' \
          "${instance_id}" "${listen_address}" >&2
        ;;
      *)
        server_address=${listen_address}
        ;;
    esac
    [[ -n "${server_address}" ]] || return 1
    build_anytls_client_outbounds_from_store "${instance_file}" "${server_address}" >> "${output_file}" || return 1
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_anytls_client_outbounds_from_store() (
  local store_file=${1:-} server=${2:-} raw_file output_file expected_count output_count snapshot raw_outbound
  local tls_json trust server_name certificate_path certificate_pem

  [[ $# -eq 2 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  validate_structured_instance_store anytls "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json anytls "${store_file}") || return 1
  raw_file=$(mktemp) || return 1
  output_file=$(mktemp) || {
    rm -f -- "${raw_file}"
    return 1
  }
  trap 'rm -f -- "${raw_file}" "${output_file}"' EXIT
  jq -c --arg server "${server}" '
    .instances[] as $instance |
    $instance.authentication.users[] as $user |
    {
      type:"anytls",
      tag:("anytls-" + $instance.id + "-user-" + ($user.name | @base64)),
      server:$server,
      server_port:$instance.listen.port,
      password:$user.password,
      client_metadata:"",
      _tls:$instance.tls,
      _client_trust:$instance.client_trust
    }
  ' <<< "${snapshot}" > "${raw_file}" || return 1

  while IFS= read -r raw_outbound; do
    [[ -n "${raw_outbound}" ]] || continue
    tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
    jq -e '.enabled == true' <<< "${tls_json}" >/dev/null || return 1
    server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
    trust=$(jq -er '._client_trust' <<< "${raw_outbound}") || return 1
    case "${trust}" in
      system)
        tls_json=$(jq -cn --arg server_name "${server_name}" \
          '{enabled:true,server_name:$server_name}') || return 1
        ;;
      certificate)
        certificate_path=$(jq -er '._tls.certificate_path' <<< "${raw_outbound}") || return 1
        certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
        tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" \
          '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
        ;;
      *)
        return 1
        ;;
    esac
    jq -c --argjson tls "${tls_json}" \
      'del(._tls,._client_trust) | .tls=$tls' <<< "${raw_outbound}" >> "${output_file}" || return 1
  done < "${raw_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

validate_mixed_client_connection() {
  local port=${1:-} auth_enabled=${2:-} username=${3:-} password=${4:-}
  local LC_ALL=C
  # SOCKS5 credentials are length-prefixed in bytes, not Unicode characters.
  [[ "${port}" =~ ^[0-9]{1,5}$ ]] || return 1
  jq -en --arg port "${port}" '$port | tonumber | . >= 1 and . <= 65535' >/dev/null || return 1
  case "${auth_enabled}" in
    y)
      [[ -n "${username}" && -n "${password}" && ${#username} -le 255 && ${#password} -le 255 ]]
      ;;
    n) return 0 ;;
    *) return 1 ;;
  esac
}

mixed_loaded_state_is_exportable() {
  if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]]; then
    [[ "${SB_PROTOCOL}" == "mixed" && -n "${SB_MIXED_INSTANCE_ID}" ]] || return 1
    validate_mixed_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
      "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}"
    return $?
  fi
  # The read-only instance adapter clears source variables before loading.
  # Validate that same raw snapshot, not a second read of a file that could
  # change between validation and rendering. Loader defaults are not evidence
  # that a required port/authentication field was actually persisted.
  [[ "${SB_PROTOCOL}" == "mixed" && "${SB_INSTANCE_ID}" == "main" ]] || return 1
  [[ "${INSTALLED:-}" == "1" ]] || return 1
  validate_mixed_client_connection "${PORT:-}" "${AUTH_ENABLED:-}" "${USERNAME:-}" "${PASSWORD:-}"
}

build_client_plain_proxy_outbound() {
  local protocol=${1:-}
  local public_ip outbound_tag protocol_label outbound_type
  local http_tls_json certificate_path certificate_pem tls_json='{}'

  protocol=$(structured_instance_store_protocol "${protocol}") || return 1
  public_ip=${2:-$(get_public_ip)}
  outbound_tag=${3:-$(client_outbound_tag_for_protocol "${protocol}")}
  case "${protocol}" in
    mixed) protocol_label="Mixed"; outbound_type=socks ;;
    socks) protocol_label="SOCKS"; outbound_type=socks ;;
    http) protocol_label="HTTP"; outbound_type=http ;;
    *) return 1 ;;
  esac
  if [[ -z "${public_ip}" || -z "${outbound_tag}" ]]; then
    printf '[ERROR] %s_export_state_invalid: %s 端口或认证字段不完整或无效，未生成客户端连接材料。\n' \
      "${protocol}" "${protocol_label}" >&2
    return 1
  fi
  if [[ "${protocol}" == http ]]; then
    if ! validate_http_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
      "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}"; then
      printf '[ERROR] http_export_state_invalid: HTTP 端口或认证字段不完整或无效，未生成客户端连接材料。\n' >&2
      return 1
    fi
    if ! plain_proxy_http_auth_representable; then
      printf '[ERROR] http_export_state_invalid: HTTP Basic 用户名或密码无法安全表达，未生成客户端连接材料。\n' >&2
      return 1
    fi
  elif ! validate_mixed_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
    "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}"; then
    printf '[ERROR] %s_export_state_invalid: %s 端口或认证字段不完整或无效，未生成客户端连接材料。\n' \
      "${protocol}" "${protocol_label}" >&2
    return 1
  fi

  if [[ "${protocol}" == http ]]; then
    http_tls_json=${SB_HTTP_TLS_JSON:-}
    validate_http_tls_state_json "${http_tls_json}" || return 1
    if jq -e '.enabled == true' <<< "${http_tls_json}" >/dev/null; then
      certificate_path=$(jq -r '.certificate_path' <<< "${http_tls_json}") || return 1
      certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
      tls_json=$(jq -n --arg server_name "$(jq -r '.server_name' <<< "${http_tls_json}")" \
        --arg certificate "${certificate_pem}" \
        '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
    fi
  fi
  jq -n \
    --arg type "${outbound_type}" \
    --arg tag "${outbound_tag}" \
    --arg server "${public_ip}" \
    --arg port "${SB_PORT}" \
    --arg auth_enabled "${SB_MIXED_AUTH_ENABLED}" \
    --arg username "${SB_MIXED_USERNAME:-}" \
    --arg password "${SB_MIXED_PASSWORD:-}" \
    --argjson tls "${tls_json}" \
    '{type:$type, tag:$tag, server:$server, server_port:($port|tonumber)}
    + (if $type == "socks" then {version:"5", udp_over_tcp:{enabled:true, version:2}} else {} end)
    + (if $auth_enabled == "y" then {username:$username, password:$password} else {} end)
    + (if $type == "http" and ($tls | length) > 0 then {tls:$tls} else {} end)'
}

build_client_mixed_outbound() (
  build_client_plain_proxy_outbound mixed "$@"
)

build_client_plain_proxy_outbounds() (
  local protocol=${1:-}
  local public_ip
  local store_file instance_id listen_address server_address outbound_json tmpdir display_protocol outbound_type
  local instance_ids_raw
  local instance_ids=()

  protocol=$(structured_instance_store_protocol "${protocol}") || return 1
  public_ip=${2:-$(get_public_ip)}
  case "${protocol}" in
    mixed) display_protocol="Mixed"; outbound_type=socks ;;
    socks) display_protocol="SOCKS"; outbound_type=socks ;;
    http) display_protocol="HTTP"; outbound_type=http ;;
    *) return 1 ;;
  esac
  [[ -n "${public_ip}" ]] || return 1
  plain_proxy_structured_state_active "${protocol}" || return 1
  store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
  if ! instance_ids_raw=$(jq -r '.instances[].id' "${store_file}"); then
    return 1
  fi
  [[ -n "${instance_ids_raw}" ]] || return 1
  mapfile -t instance_ids <<< "${instance_ids_raw}"
  [[ ${#instance_ids[@]} -gt 0 ]] || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT

  for instance_id in "${instance_ids[@]}"; do
    [[ -n "${instance_id}" ]] || return 1
    load_plain_proxy_structured_instance "${protocol}" "${instance_id}" || return 1
    [[ "${SB_PROTOCOL}" == "${protocol}" ]] || return 1
    [[ "${SB_MIXED_STORE_REVISION}" =~ ^[0-9]+$ ]] || return 1
    listen_address=${SB_MIXED_LISTEN_ADDRESS}
    case "${listen_address}" in
      0.0.0.0|::)
        server_address=${public_ip}
        ;;
      127.*|::1)
        server_address=${listen_address}
        printf '[WARN] %s 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' \
          "${display_protocol}" "${instance_id}" "${listen_address}" >&2
        ;;
      *)
        server_address=${listen_address}
        ;;
    esac
    outbound_json=$(build_client_plain_proxy_outbound "${protocol}" "${server_address}" "${protocol}-${instance_id}" "${outbound_type}") || return 1
    printf '%s\n' "${outbound_json}" >> "${tmpdir}/outbounds.jsonl" || return 1
  done
  jq -c '.' "${tmpdir}/outbounds.jsonl"
)

build_client_mixed_outbounds() (
  build_client_plain_proxy_outbounds mixed "$@"
)

build_client_socks_outbounds() (
  build_client_plain_proxy_outbounds socks "$@"
)

build_client_http_outbounds() (
  local public_ip=${1:-$(get_public_ip)}
  build_client_plain_proxy_outbounds http "${public_ip}"
)

build_client_trojan_outbounds() (
  local public_ip=${1:-} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address expected_count output_count

  store_file=$(plain_proxy_structured_store_file trojan) || return 1
  snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"
  output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file=$(mktemp "${tmpdir}/store.XXXXXX") || return 1
    jq --arg id "${instance_id}" '
      . as $root |
      ($root.instances | map(select(.id == $id))) as $instances |
      $root | .default_instance_id=$id | .instances=$instances
    ' <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -er --arg id "${instance_id}" \
      '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::)
        server_address=${public_ip:-$(get_public_ip)}
        ;;
      *)
        server_address=${listen_address}
        ;;
    esac
    [[ -n "${server_address}" ]] || return 1
    build_trojan_client_outbounds_from_store "${instance_file}" "${server_address}" >> "${output_file}" || return 1
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_trojan_client_outbounds_from_store() (
  local store_file=${1:-} server=${2:-} raw_file output_file expected_count output_count snapshot
  local raw_outbound tls_json transport_json profile tls_mode
  local server_name certificate_path certificate_pem alpn_json

  [[ $# -eq 2 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  validate_structured_instance_store trojan "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || return 1
  raw_file=$(mktemp) || return 1
  output_file=$(mktemp) || {
    rm -f -- "${raw_file}"
    return 1
  }
  trap 'rm -f -- "${raw_file}" "${output_file}"' EXIT
  jq -c --arg server "${server}" '
    .instances[] as $instance |
    $instance.authentication.users[] as $user |
    {
      type:"trojan",
      tag:("trojan-" + $instance.id + "-user-" + ($user.name | @base64)),
      server:$server,
      server_port:$instance.listen.port,
      password:$user.password,
      _tls:$instance.tls,
      _client_trust:$instance.client_trust,
      _transport:$instance.transport
    }
  ' <<< "${snapshot}" > "${raw_file}" || return 1

  while IFS= read -r raw_outbound; do
    [[ -n "${raw_outbound}" ]] || continue
    tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
    transport_json=$(jq -ec '._transport' <<< "${raw_outbound}") || return 1
    tls_mode=disabled
    if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null; then
      tls_mode=tls
    elif ! jq -e '.enabled == false' <<< "${tls_json}" >/dev/null; then
      return 1
    fi
    profile=$(build_v2ray_transport_profile_json trojan "${transport_json}" "${tls_mode}" '' "$(resolve_config_target_singbox_version)") || return 1
    alpn_json=$(jq -c '.tls_alpn' <<< "${profile}") || return 1
    if [[ "${tls_mode}" == tls ]]; then
      server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
      case "$(jq -er '._client_trust' <<< "${raw_outbound}")" in
        system)
          tls_json=$(jq -cn --arg server_name "${server_name}" --argjson alpn "${alpn_json}" \
            '{enabled:true,server_name:$server_name} + (if ($alpn|length)>0 then {alpn:$alpn} else {} end)') || return 1
          ;;
        certificate)
          certificate_path=$(jq -er '._tls.certificate_path' <<< "${raw_outbound}") || return 1
          certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
          tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" \
            --argjson alpn "${alpn_json}" \
            '{enabled:true,server_name:$server_name,certificate:$certificate} + (if ($alpn|length)>0 then {alpn:$alpn} else {} end)') || return 1
          ;;
        *) return 1 ;;
      esac
    else
      tls_json='{"enabled":false}'
    fi
    jq -c --argjson tls "${tls_json}" --argjson transport "${transport_json}" '
      del(._tls, ._client_trust, ._transport) |
      # An explicit disabled TLS object still creates a TLS dialer in the
      # pinned Trojan cores. Omit it entirely for a plaintext connection.
      (if $tls.enabled then .tls = $tls else del(.tls) end) |
      (if $transport.type == "none" then del(.transport) else .transport = $transport end)
    ' <<< "${raw_outbound}" >> "${output_file}" || return 1
  done < "${raw_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_vmess_outbounds() (
  local public_ip=${1:-} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address expected_count output_count
  store_file=$(plain_proxy_structured_store_file vmess) || return 1
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"; output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file=$(mktemp "${tmpdir}/store.XXXXXX") || return 1
    jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in 0.0.0.0|::) server_address=${public_ip:-$(get_public_ip)} ;; *) server_address=${listen_address} ;; esac
    [[ -n "${server_address}" ]] || return 1
    build_vmess_client_outbounds_from_store "${instance_file}" "${server_address}" >> "${output_file}" || return 1
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_vmess_client_outbounds_from_store() (
  local store_file=${1:-} server=${2:-} raw_file output_file snapshot raw_outbound tls_json transport_json profile tls_mode
  local server_name certificate_path certificate_pem alpn_json network_json security alter_id
  [[ $# -eq 2 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  validate_structured_instance_store vmess "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  raw_file=$(mktemp) || return 1
  output_file=$(mktemp) || { rm -f -- "${raw_file}"; return 1; }
  trap 'rm -f -- "${raw_file}" "${output_file}"' EXIT
  # V2Ray QUIC selects the transport socket, but does not turn a proxy
  # outbound into a UDP-only service.  Keep both proxy networks enabled; the
  # transport profile is the source of the server's UDP listener projection.
  jq -c --arg server "${server}" '.instances[] as $instance | $instance.authentication.users[] as $user |
    {type:"vmess",tag:("vmess-" + $instance.id + "-user-" + ($user.name | @base64)),server:$server,server_port:$instance.listen.port,
     uuid:$user.uuid,security:$user.security,alter_id:$user.alter_id,network:["tcp","udp"],
     _tls:$instance.tls,_client_trust:$instance.client_trust,_transport:$instance.transport}' <<< "${snapshot}" > "${raw_file}" || return 1
  while IFS= read -r raw_outbound; do
    [[ -n "${raw_outbound}" ]] || continue
    tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
    transport_json=$(jq -ec '._transport' <<< "${raw_outbound}") || return 1
    tls_mode=disabled
    if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null; then tls_mode=tls
    elif ! jq -e '.enabled == false' <<< "${tls_json}" >/dev/null; then return 1; fi
    profile=$(build_v2ray_transport_profile_json vmess "${transport_json}" "${tls_mode}" '' "$(resolve_config_target_singbox_version)") || return 1
    alpn_json=$(jq -c '.tls_alpn' <<< "${profile}") || return 1
    if [[ "${tls_mode}" == tls ]]; then
      server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
      case "$(jq -er '._client_trust' <<< "${raw_outbound}")" in
        system)
          tls_json=$(jq -cn --arg server_name "${server_name}" --argjson alpn "${alpn_json}" '{enabled:true,server_name:$server_name} + (if ($alpn|length)>0 then {alpn:$alpn} else {} end)') || return 1 ;;
        certificate)
          certificate_path=$(jq -er '._tls.certificate_path' <<< "${raw_outbound}") || return 1
          certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
          tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" --argjson alpn "${alpn_json}" '{enabled:true,server_name:$server_name,certificate:$certificate} + (if ($alpn|length)>0 then {alpn:$alpn} else {} end)') || return 1 ;;
        *) return 1 ;;
      esac
    else tls_json='{"enabled":false}'; fi
    jq -c --argjson tls "${tls_json}" --argjson transport "${transport_json}" 'del(._tls,._client_trust,._transport) | (if $tls.enabled then .tls=$tls else del(.tls) end) | (if $transport.type == "none" then del(.transport) else .transport=$transport end)' <<< "${raw_outbound}" >> "${output_file}" || return 1
  done < "${raw_file}"
  output_count=$(jq -s 'length' "${output_file}") || return 1
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  [[ "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_vless_plain_outbounds() (
  local public_ip=${1:-} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address expected_count output_count
  store_file=$(plain_proxy_structured_store_file vless-plain) || return 1
  snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"; output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file=$(mktemp "${tmpdir}/store.XXXXXX") || return 1
    jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in 0.0.0.0|::) server_address=${public_ip:-$(get_public_ip)} ;; *) server_address=${listen_address} ;; esac
    [[ -n "${server_address}" ]] || return 1
    build_vless_plain_client_outbounds_from_store "${instance_file}" "${server_address}" >> "${output_file}" || return 1
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_vless_plain_client_outbounds_from_store() (
  local store_file=${1:-} server=${2:-} raw_file output_file snapshot raw_outbound tls_json transport_json
  local profile tls_mode server_name certificate_path certificate_pem alpn_json flow
  [[ $# -eq 2 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  validate_structured_instance_store vless-plain "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  raw_file=$(mktemp) || return 1
  output_file=$(mktemp) || { rm -f -- "${raw_file}"; return 1; }
  trap 'rm -f -- "${raw_file}" "${output_file}"' EXIT
  # Like VMess, VLESS QUIC uses UDP for the transport socket while the proxy
  # outbound may still carry TCP streams and UDP packets.
  jq -c --arg server "${server}" '.instances[] as $instance | $instance.authentication.users[] as $user |
    {type:"vless",tag:("vless-plain-" + $instance.id + "-user-" + ($user.name | @base64)),server:$server,server_port:$instance.listen.port,
     uuid:$user.uuid} + (if ($user.flow // "") == "" then {} else {flow:$user.flow} end) +
     {network:["tcp","udp"],
      _tls:$instance.tls,_client_trust:$instance.client_trust,_transport:$instance.transport}' <<< "${snapshot}" > "${raw_file}" || return 1
  while IFS= read -r raw_outbound; do
    [[ -n "${raw_outbound}" ]] || continue
    tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
    transport_json=$(jq -ec '._transport' <<< "${raw_outbound}") || return 1
    flow=$(jq -r '.flow // empty' <<< "${raw_outbound}") || return 1
    tls_mode=disabled
    if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null; then tls_mode=tls
    elif ! jq -e '.enabled == false' <<< "${tls_json}" >/dev/null; then return 1; fi
    profile=$(build_v2ray_transport_profile_json vless "${transport_json}" "${tls_mode}" "${flow}" "$(resolve_config_target_singbox_version)") || return 1
    alpn_json=$(jq -c '.tls_alpn' <<< "${profile}") || return 1
    if [[ "${tls_mode}" == tls ]]; then
      server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
      case "$(jq -er '._client_trust' <<< "${raw_outbound}")" in
        system)
          tls_json=$(jq -cn --arg server_name "${server_name}" --argjson alpn "${alpn_json}" '{enabled:true,server_name:$server_name} + (if ($alpn|length)>0 then {alpn:$alpn} else {} end)') || return 1
          ;;
        certificate)
          certificate_path=$(jq -er '._tls.certificate_path' <<< "${raw_outbound}") || return 1
          certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
          tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" --argjson alpn "${alpn_json}" '{enabled:true,server_name:$server_name,certificate:$certificate} + (if ($alpn|length)>0 then {alpn:$alpn} else {} end)') || return 1
          ;;
        *) return 1 ;;
      esac
    else
      tls_json='{"enabled":false}'
    fi
    jq -c --argjson tls "${tls_json}" --argjson transport "${transport_json}" 'del(._tls,._client_trust,._transport) | (if $tls.enabled then .tls=$tls else del(.tls) end) | (if $transport.type == "none" then del(.transport) else .transport=$transport end)' <<< "${raw_outbound}" >> "${output_file}" || return 1
  done < "${raw_file}"
  output_count=$(jq -s 'length' "${output_file}") || return 1
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  [[ "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_vless_plain_uri_from_outbound() {
  local outbound=${1:-} name=${2:-VLESS} server port uuid flow transport_type tls_enabled query path host service_name encoded share_host
  [[ -n "${outbound}" ]] || return 1
  server=$(jq -er '.server' <<< "${outbound}") || return 1
  port=$(jq -er '.server_port' <<< "${outbound}") || return 1
  uuid=$(jq -er '.uuid' <<< "${outbound}") || return 1
  transport_type=$(jq -r '.transport.type // "none"' <<< "${outbound}") || return 1
  case "${transport_type}" in none) query='type=tcp' ;; http|ws|grpc|quic) query="type=${transport_type}" ;; *) return 1 ;; esac
  tls_enabled=$(jq -r 'if .tls.enabled == true then true else false end' <<< "${outbound}") || return 1
  if [[ "${tls_enabled}" == true ]]; then
    query="${query}&security=tls"
    encoded=$(jq -rn --arg value "$(jq -er '.tls.server_name' <<< "${outbound}")" '$value|@uri') || return 1
    query="${query}&sni=${encoded}"
  else
    query="${query}&security=none"
  fi
  flow=$(jq -r '.flow // empty' <<< "${outbound}") || return 1
  if [[ -n "${flow}" ]]; then
    encoded=$(jq -rn --arg value "${flow}" '$value|@uri') || return 1
    query="${query}&flow=${encoded}"
  fi
  case "${transport_type}" in
    http|ws)
      path=$(jq -r '.transport.path // empty' <<< "${outbound}") || return 1
      if [[ -n "${path}" ]]; then encoded=$(jq -rn --arg value "${path}" '$value|@uri') || return 1; query="${query}&path=${encoded}"; fi
      host=$(jq -r '.transport.headers.Host // .transport.headers.host // (if (.transport.host|type) == "array" then .transport.host[0] // empty else .transport.host // empty end)' <<< "${outbound}") || return 1
      if [[ -n "${host}" ]]; then encoded=$(jq -rn --arg value "${host}" '$value|@uri') || return 1; query="${query}&host=${encoded}"; fi
      ;;
    grpc)
      service_name=$(jq -r '.transport.service_name // empty' <<< "${outbound}") || return 1
      if [[ -n "${service_name}" ]]; then encoded=$(jq -rn --arg value "${service_name}" '$value|@uri') || return 1; query="${query}&serviceName=${encoded}"; fi
      ;;
  esac
  encoded=$(jq -rn --arg value "${name}" '$value|@uri') || return 1
  share_host=$(format_share_host "${server}") || return 1
  printf 'vless://%s@%s:%s?encryption=none&%s#%s' "${uuid}" "${share_host}" "${port}" "${query}" "${encoded}"
}

build_vless_plain_links_json() {
  local node_name_digests
  local server=${1:-} instance_id=${2:-${SB_INSTANCE_ID:-}} outbounds outbound uri key result='{}'
  local store_file snapshot end_snapshot binding candidate_id user_name node_name address_label
  store_file=$(plain_proxy_structured_store_file vless-plain) || return 1
  snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  outbounds=$(build_client_vless_plain_outbounds "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
  while IFS= read -r outbound; do
    [[ -n "${outbound}" ]] || continue
    key=$(jq -er '.tag' <<< "${outbound}") || return 1
    if [[ -n "${instance_id}" && "${key}" != "vless-plain-${instance_id}-user-"* ]]; then continue; fi
    binding=$(jq -ce --arg key "${key}" '
      [.instances[] as $instance | $instance.authentication.users[] as $user |
       select(("vless-plain-" + $instance.id + "-user-" + ($user.name | @base64)) == $key) |
       {instance_id:$instance.id,user_name:$user.name,listen_address:$instance.listen.address}] |
      select(length == 1) | .[0]' <<< "${snapshot}") || return 1
    candidate_id=$(jq -r '.instance_id' <<< "${binding}") || return 1
    user_name=$(jq -r '.user_name' <<< "${binding}") || return 1
    address_label=$(node_display_address_label "$(jq -r '.listen_address' <<< "${binding}")" "$(jq -r '.server' <<< "${outbound}")") || return 1
    node_name=$(structured_node_display_name vless-plain "${snapshot}" "${candidate_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    uri=$(build_vless_plain_uri_from_outbound "${outbound}" "${node_name}") || return 1
    result=$(jq -cn --argjson result "${result}" --arg key "${key}" --arg uri "${uri}" '$result+{($key):$uri}') || return 1
  done <<< "${outbounds}"
  jq -e 'length > 0' <<< "${result}" >/dev/null || return 1
  printf '%s\n' "${result}"
}

build_vmess_uri_from_outbound() {
  local outbound=${1:-} name=${2:-VMess} payload encoded
  [[ -n "${outbound}" ]] || return 1
  payload=$(jq -cS --arg name "${name}" '
    .transport as $transport | (.tls // {}) as $tls |
    select((($transport.type // "none") != "http" and ($transport.type // "none") != "ws") or
      ((($transport.headers // {}) | keys | all(. == "Host")) and
       (($transport.method // "GET") == "GET"))) |
    select((($transport.type // "none") != "http") or
      ((($transport.host // []) | if type == "array" then length <= 1 else true end))) |
    {v:"2",ps:$name,add:.server,port:(.server_port|tostring),id:.uuid,aid:(.alter_id // 0),scy:.security,
     net:(if ($transport.type // "none") == "none" then "tcp" elif $transport.type == "http" then "http" elif $transport.type == "ws" then "ws" elif $transport.type == "grpc" then "grpc" elif $transport.type == "quic" then "quic" else error("unsupported transport") end),
     type:(if ($transport.type // "none") == "grpc" then "gun" else "none" end),
     host:(if $transport.type == "ws" then ($transport.headers.Host // $transport.host // "")
       elif (($transport.host // "")|type) == "array" then (($transport.host // [])|join(","))
       else ($transport.host // "") end),
     path:(if ($transport.type // "none") == "grpc" then ($transport.service_name // "") else ($transport.path // "") end),
     tls:(if ($tls.enabled // false) then "tls" else "" end),sni:($tls.server_name // "")}' <<< "${outbound}") || return 1
  encoded=$(printf '%s' "${payload}" | base64 -w0 2>/dev/null) || return 1
  [[ -n "${encoded}" ]] || return 1
  encoded=${encoded//$'\n'/}; encoded=${encoded//+/-}; encoded=${encoded//\//_}; encoded=${encoded%%=*}
  printf 'vmess://%s' "${encoded}"
}

build_vmess_links_json() {
  local node_name_digests
  local server=${1:-} instance_id=${2:-${SB_INSTANCE_ID:-}} outbounds outbound uri key result='{}'
  local store_file snapshot end_snapshot binding candidate_id user_name node_name address_label
  store_file=$(plain_proxy_structured_store_file vmess) || return 1
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  outbounds=$(build_client_vmess_outbounds "${server}") || return 1
  end_snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  [[ "${snapshot}" == "${end_snapshot}" ]] || return 1
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
  while IFS= read -r outbound; do
    [[ -n "${outbound}" ]] || continue
    key=$(jq -er '.tag' <<< "${outbound}") || return 1
    if [[ -n "${instance_id}" && "${key}" != "vmess-${instance_id}-user-"* ]]; then continue; fi
    binding=$(jq -ce --arg key "${key}" '
      [.instances[] as $instance | $instance.authentication.users[] as $user |
       select(("vmess-" + $instance.id + "-user-" + ($user.name | @base64)) == $key) |
       {instance_id:$instance.id,user_name:$user.name,listen_address:$instance.listen.address}] |
      select(length == 1) | .[0]' <<< "${snapshot}") || return 1
    candidate_id=$(jq -r '.instance_id' <<< "${binding}") || return 1
    user_name=$(jq -r '.user_name' <<< "${binding}") || return 1
    address_label=$(node_display_address_label "$(jq -r '.listen_address' <<< "${binding}")" "$(jq -r '.server' <<< "${outbound}")") || return 1
    node_name=$(structured_node_display_name vmess "${snapshot}" "${candidate_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    uri=$(build_vmess_uri_from_outbound "${outbound}" "${node_name}") || return 1
    result=$(jq -cn --argjson result "${result}" --arg key "${key}" --arg uri "${uri}" '$result+{($key):$uri}') || return 1
  done <<< "${outbounds}"
  jq -e 'length > 0' <<< "${result}" >/dev/null || return 1
  printf '%s\n' "${result}"
}

shadowsocks_client_psk() (
  local method=${1:-} psk=${2-} min_bytes decoded_file digest_file decoded_bytes

  case "${method}" in
    2022-blake3-aes-128-gcm) min_bytes=16 ;;
    2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) min_bytes=32 ;;
    none|aes-128-gcm|aes-192-gcm|aes-256-gcm|chacha20-ietf-poly1305|xchacha20-ietf-poly1305)
      printf '%s' "${psk}"
      return 0
      ;;
    *) return 1 ;;
  esac
  [[ -n "${psk}" ]] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  decoded_file=$(mktemp) || return 1
  digest_file=$(mktemp) || {
    rm -f -- "${decoded_file}"
    return 1
  }
  trap 'rm -f -- "${decoded_file}" "${digest_file}"' EXIT
  printf '%s' "${psk}" | openssl base64 -d -A > "${decoded_file}" || return 1
  decoded_bytes=$(wc -c < "${decoded_file}") || return 1
  if (( decoded_bytes == min_bytes )); then
    printf '%s' "${psk}"
    return 0
  fi
  (( decoded_bytes > min_bytes )) || return 1
  openssl dgst -sha256 -binary "${decoded_file}" > "${digest_file}" || return 1
  head -c "${min_bytes}" "${digest_file}" | openssl base64 -A || return 1
)

build_client_shadowsocks_outbounds() (
  local public_ip=${1:-$(get_public_ip)} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address
  store_file=$(plain_proxy_structured_store_file shadowsocks) || return 1
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowsocks "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"
  output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file=$(mktemp "${tmpdir}/store.XXXXXX") || return 1
    jq --arg id "${instance_id}" '
      . as $root |
      ($root.instances | map(select(.id == $id))) as $instances |
      $root | .default_instance_id=$id | .instances=$instances
    ' <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -r --arg id "${instance_id}" '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::) server_address=${public_ip} ;;
      *) server_address=${listen_address} ;;
    esac
    build_shadowsocks_client_outbounds_from_store "${instance_file}" "${server_address}" >> "${output_file}" || return 1
  done < "${instance_ids_file}"
  jq -c '.' "${output_file}"
)

build_shadowsocks_client_outbounds_from_store() (
  local store_file=${1:-} server=${2:-} raw_file output_file expected_count output_count
  local raw_outbound method server_psk user_psk password

  [[ $# -eq 2 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  validate_structured_instance_store shadowsocks "${store_file}" || return 1

  raw_file=$(mktemp) || return 1
  output_file=$(mktemp) || {
    rm -f -- "${raw_file}"
    return 1
  }
  trap 'rm -f -- "${raw_file}" "${output_file}"' EXIT
  jq -c --arg server "${server}" '
    .instances[] as $instance |
    $instance.authentication as $authentication |
    ($authentication.users |
      if length == 0 then
        [{name:"", password:$authentication.password, single:true}]
      else
        map(. + {single:false})
      end)[] as $user |
    ($authentication.method == "2022-blake3-aes-128-gcm" or
     $authentication.method == "2022-blake3-aes-256-gcm") as $aes2022 |
    {
      type:"shadowsocks",
      tag:("shadowsocks-" + $instance.id + "-" +
        (if $user.single then "single" else "user-" + ($user.name | @base64) end)),
      server:$server,
      server_port:$instance.listen.port,
      method:$authentication.method,
      password:(if $user.single then $authentication.password
        elif $aes2022 then ($authentication.password + ":" + $user.password)
        else $user.password end),
      network:$instance.listen.network,
      _server_psk:$authentication.password,
      _user_psk:(if $user.single then "" else $user.password end)
    }
  ' "${store_file}" > "${raw_file}" || return 1
  while IFS= read -r raw_outbound; do
    [[ -n "${raw_outbound}" ]] || continue
    method=$(jq -er '._method // .method' <<< "${raw_outbound}") || return 1
    if [[ "${method}" == 2022-* ]]; then
      server_psk=$(jq -er '._server_psk' <<< "${raw_outbound}") || return 1
      server_psk=$(shadowsocks_client_psk "${method}" "${server_psk}") || return 1
      user_psk=$(jq -er '._user_psk' <<< "${raw_outbound}") || return 1
      if [[ -n "${user_psk}" ]]; then
        user_psk=$(shadowsocks_client_psk "${method}" "${user_psk}") || return 1
        password="${server_psk}:${user_psk}"
      else
        password=${server_psk}
      fi
      jq -c --arg password "${password}" 'del(._server_psk, ._user_psk) | .password=$password' \
        <<< "${raw_outbound}" >> "${output_file}" || return 1
    else
      jq -c 'del(._server_psk, ._user_psk)' <<< "${raw_outbound}" >> "${output_file}" || return 1
    fi
  done < "${raw_file}"
  expected_count=$(jq -r '[.instances[] | if (.authentication.users | length) == 0 then 1 else (.authentication.users | length) end] | add // 0' "${store_file}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_snell_outbounds() (
  local public_ip=${1:-} store_override=${2:-} store_file snapshot output_file raw_file
  local instance_id listen_address server_address raw_outbound user_count expected_count output_count
  local tmpdir instance_ids_file instance_file
  if [[ -n "${store_override}" ]]; then store_file=${store_override}; else store_file=$(plain_proxy_structured_store_file snell) || return 1; fi
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json snell "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"; output_file="${tmpdir}/outbounds.jsonl"; : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    listen_address=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::) server_address=${public_ip} ;;
      127.*|::1)
        server_address=${listen_address}
        printf '[WARN] Snell 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' "${instance_id}" "${listen_address}" >&2
        ;;
      *) server_address=${listen_address} ;;
    esac
    instance_file="${tmpdir}/instance-${instance_id}.json"
    jq --arg id "${instance_id}" '. as $root | ($root.instances | map(select(.id == $id))) as $instances | $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${instance_file}" || return 1
    raw_file="${tmpdir}/raw-${instance_id}.jsonl"
    jq -c --arg server "${server_address}" '
      .instances[] as $instance |
      (($instance.authentication.users // []) | if length == 0 then [{name:"",userkey:"",single:true}] else map(. + {single:false}) end)[] as $user |
      {type:"snell",tag:("snell-" + $instance.id + "-" + (if $user.single then "single" else "user-" + ($user.name | @base64) end)),
       server:$server,server_port:$instance.listen.port,
       version:(if $instance.version == 5 then 4 else 6 end),psk:$instance.authentication.psk,
       userkey:(if $user.single then "" else $user.userkey end),network:["tcp","udp"],
       _inbound_version:$instance.version,_obfs_mode:$instance.obfs_mode,_obfs_host:$instance.obfs_host,_mode:$instance.mode}
    ' "${instance_file}" > "${raw_file}" || return 1
    while IFS= read -r raw_outbound; do
      [[ -n "${raw_outbound}" ]] || continue
      jq -c '
        if ._inbound_version == 5 then
          . + (if ._obfs_mode == "http" then {obfs_mode:"http",obfs_host:._obfs_host} else {obfs_mode:"none"} end)
        else . + {mode:._mode}
        end | del(._inbound_version,._obfs_mode,._obfs_host,._mode)
      ' <<< "${raw_outbound}" >> "${output_file}" || return 1
    done < "${raw_file}"
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | if length == 0 then 1 else length end] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_tuic_outbounds() (
  local public_ip=${1:-} store_override=${2:-} store_file snapshot tmpdir instance_ids_file instance_file output_file
  local instance_id listen_address server_address expected_count output_count raw_file raw_outbound
  local tls_json trust server_name certificate_path certificate_pem

  if [[ -n "${store_override}" ]]; then
    store_file=${store_override}
  else
    store_file=$(plain_proxy_structured_store_file tuic) || return 1
  fi
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store tuic "${store_file}" || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json tuic "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  instance_ids_file="${tmpdir}/instance-ids"
  output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1
  jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}" > "${instance_ids_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    instance_file="${tmpdir}/instance-${instance_id}.json"
    jq --arg id "${instance_id}" \
      '. as $root | ($root.instances | map(select(.id == $id))) as $instances |
       $root | .default_instance_id=$id | .instances=$instances' \
      <<< "${snapshot}" > "${instance_file}" || return 1
    listen_address=$(jq -er --arg id "${instance_id}" \
      '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::)
        server_address=${public_ip}
        ;;
      127.*|::1)
        server_address=${listen_address}
        printf '[WARN] TUIC 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' \
          "${instance_id}" "${listen_address}" >&2
        ;;
      *)
        server_address=${listen_address}
        ;;
    esac
    [[ -n "${server_address}" ]] || return 1
    raw_file="${tmpdir}/raw-${instance_id}.jsonl"
    jq -c --arg server "${server_address}" '
      .instances[] as $instance |
      $instance.authentication.users[] as $user |
      {type:"tuic",tag:("tuic-" + $instance.id + "-user-" + ($user.name | @base64)),
       server:$server,server_port:$instance.listen.port,uuid:$user.uuid,password:$user.password,
       network:["tcp","udp"],_tls:$instance.tls,_client_trust:$instance.client_trust,_tuic:$instance.tuic}
    ' "${instance_file}" > "${raw_file}" || return 1
    while IFS= read -r raw_outbound; do
      [[ -n "${raw_outbound}" ]] || continue
      tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
      jq -e '.enabled == true' <<< "${tls_json}" >/dev/null || return 1
      server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
      trust=$(jq -er '._client_trust' <<< "${raw_outbound}") || return 1
      case "${trust}" in
        system)
          tls_json=$(jq -cn --arg server_name "${server_name}" \
            '{enabled:true,server_name:$server_name}') || return 1
          ;;
        certificate)
          certificate_path=$(jq -er '._tls.certificate_path' <<< "${raw_outbound}") || return 1
          certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
          tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" \
            '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
          ;;
        *) return 1 ;;
      esac
      jq -c --argjson tls "${tls_json}" \
        --arg cc "$(jq -er '._tuic.congestion_control' <<< "${raw_outbound}")" \
        --arg relay "$(jq -r '._tuic.udp_relay_mode // ""' <<< "${raw_outbound}")" \
        --argjson udp_over_stream "$(jq -er '._tuic.udp_over_stream' <<< "${raw_outbound}")" \
        --argjson zero_rtt_handshake "$(jq -er '._tuic.zero_rtt_handshake' <<< "${raw_outbound}")" \
        --arg heartbeat_seconds "$(jq -er '._tuic.heartbeat_seconds | tostring' <<< "${raw_outbound}")" \
        'del(._tls,._client_trust,._tuic) | .tls=($tls + {alpn:["h3"]}) | .congestion_control=$cc
         | if $relay != "" then .udp_relay_mode=$relay
           elif $udp_over_stream then .udp_over_stream=true else . end
         | if $zero_rtt_handshake then .zero_rtt_handshake=true else . end
         | if (($heartbeat_seconds|tonumber) > 0) then .heartbeat=(($heartbeat_seconds|tonumber)|tostring + "s") else . end' \
        <<< "${raw_outbound}" >> "${output_file}" || return 1
    done < "${raw_file}"
  done < "${instance_ids_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_hysteria_outbounds() (
  local public_ip=${1:-} store_override=${2:-} store_file snapshot tmpdir output_file instance_id listen_address server_address
  local tls_json trust server_name certificate_path certificate_pem outbound_json expected_count output_count
  if [[ -n "${store_override}" ]]; then store_file=${store_override}; else store_file=$(plain_proxy_structured_store_file hysteria) || return 1; fi
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store hysteria "${store_file}" || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json hysteria "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  output_file="${tmpdir}/outbounds.jsonl"; : > "${output_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    listen_address=$(jq -er --arg id "${instance_id}" '.instances[]|select(.id==$id)|.listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::) server_address=${public_ip} ;;
      127.*|::1) server_address=${listen_address}; printf '[WARN] Hysteria 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' "${instance_id}" "${listen_address}" >&2 ;;
      *) server_address=${listen_address} ;;
    esac
    jq -c --arg id "${instance_id}" --arg server "${server_address}" '.instances[]|select(.id==$id) as $instance | $instance.authentication.users[] as $user | {type:"hysteria",tag:("hysteria-"+$instance.id+"-user-"+($user.name|@base64)),server:$server,server_port:$instance.listen.port,up_mbps:$instance.bandwidth.up_mbps,down_mbps:$instance.bandwidth.down_mbps,auth_str:$user.auth_str,_tls:$instance.tls,_trust:$instance.client_trust,_obfs:$instance.obfs,_quic:$instance.hysteria}' <<< "${snapshot}" >> "${output_file}" || return 1
  done < <(jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}")
  while IFS= read -r outbound_json; do
    [[ -n "${outbound_json}" ]] || continue
    tls_json=$(jq -ec '._tls' <<< "${outbound_json}") || return 1
    server_name=$(jq -er '._tls.server_name' <<< "${outbound_json}") || return 1
    trust=$(jq -er '._trust' <<< "${outbound_json}") || return 1
    case "${trust}" in
      system) tls_json=$(jq -cn --arg server_name "${server_name}" '{enabled:true,server_name:$server_name}') || return 1 ;;
      certificate)
        certificate_path=$(jq -er '._tls.certificate_path' <<< "${outbound_json}") || return 1
        certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
        tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
        ;;
      *) return 1 ;;
    esac
    jq -c --argjson tls "${tls_json}" '._obfs as $obfs | ._quic as $quic | del(._tls,._trust,._obfs,._quic) | .tls=$tls |
      if $obfs.enabled then .obfs=$obfs.password else . end |
      if $quic.initial_packet_size > 0 then .initial_packet_size=$quic.initial_packet_size else . end |
      if $quic.disable_path_mtu_discovery then .disable_path_mtu_discovery=true else . end |
      if $quic.max_concurrent_streams > 0 then .max_concurrent_streams=$quic.max_concurrent_streams else . end |
      if $quic.stream_receive_window != "" then .stream_receive_window=$quic.stream_receive_window else . end |
      if $quic.connection_receive_window != "" then .connection_receive_window=$quic.connection_receive_window else . end' <<< "${outbound_json}" >> "${tmpdir}/final.jsonl" || return 1
  done < "${output_file}"
  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(wc -l < "${tmpdir}/final.jsonl") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag)|unique|length)==length' "${tmpdir}/final.jsonl" >/dev/null || return 1
  cat "${tmpdir}/final.jsonl"
)

build_client_naive_outbounds() (
  local public_ip=${1:-} store_override=${2:-} store_file snapshot tmpdir output_file raw_file
  local instance_id listen_address server_address raw_outbound
  local tls_json trust server_name certificate_path certificate_pem
  local expected_count output_count

  if [[ -n "${store_override}" ]]; then
    store_file=${store_override}
  else
    store_file=$(plain_proxy_structured_store_file naive) || return 1
  fi
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store naive "${store_file}" || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json naive "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  output_file="${tmpdir}/outbounds.jsonl"
  : > "${output_file}" || return 1

  # The official Linux pure-Go Naive outbound is built with
  # with_naive_outbound and loads libcronet at runtime.  `sing-box check`
  # cannot prove that the shared library is present, so keep the requirement
  # explicit in the generated material and the Agent warning instead of
  # claiming a portable outbound for every custom build.
  printf '[WARN] NaiveProxy 客户端 outbound 需要带 with_naive_outbound 的 sing-box，并在运行时加载 libcronet.so；当前导出未声称库文件已部署。\n' >&2

  while IFS= read -r -d '' instance_id; do
    [[ -n "${instance_id}" ]] || return 1
    listen_address=$(jq -er --arg id "${instance_id}" \
      '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::)
        server_address=${public_ip}
        ;;
      127.*|::1)
        server_address=${listen_address}
        printf '[WARN] NaiveProxy 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' \
          "${instance_id}" "${listen_address}" >&2
        ;;
      *)
        server_address=${listen_address}
        ;;
    esac
    [[ -n "${server_address}" ]] || return 1
    raw_file="${tmpdir}/raw-${instance_id}.jsonl"
    if ! jq -c --arg id "${instance_id}" --arg server "${server_address}" '
      .instances[] | select(.id == $id) as $instance |
      $instance.authentication.users[] as $user |
      {type:"naive",tag:("naive-" + $instance.id + "-user-" + ($user.name | @base64)),
       server:$server,server_port:$instance.listen.port,username:$user.username,password:$user.password,
       _tls:$instance.tls,_client_trust:$instance.client_trust,_naive:$instance.naive,
       _listen_network:$instance.listen.network}
    ' <<< "${snapshot}" > "${raw_file}"; then
      return 1
    fi
    while IFS= read -r raw_outbound; do
      [[ -n "${raw_outbound}" ]] || continue
      tls_json=$(jq -ec '._tls' <<< "${raw_outbound}") || return 1
      jq -e '.enabled == true and (.server_name | type == "string" and length > 0)' \
        <<< "${tls_json}" >/dev/null || return 1
      server_name=$(jq -er '._tls.server_name' <<< "${raw_outbound}") || return 1
      trust=$(jq -er '._client_trust' <<< "${raw_outbound}") || return 1
      case "${trust}" in
        system)
          tls_json=$(jq -cn --arg server_name "${server_name}" \
            '{enabled:true,server_name:$server_name}') || return 1
          ;;
        certificate)
          certificate_path=$(jq -er '._tls.certificate_path' <<< "${raw_outbound}") || return 1
          certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
          tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" \
            '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
          ;;
        *)
          return 1
          ;;
      esac
      jq -c --argjson tls "${tls_json}" \
        --argjson quic "$(jq -er '._naive.quic' <<< "${raw_outbound}")" \
        --arg cc "$(jq -er '._naive.quic_congestion_control' <<< "${raw_outbound}")" \
        --argjson insecure_concurrency "$(jq -er '._naive.insecure_concurrency' <<< "${raw_outbound}")" \
        --arg stream_receive_window "$(jq -er '._naive.stream_receive_window' <<< "${raw_outbound}")" \
        --arg quic_session_receive_window "$(jq -er '._naive.quic_session_receive_window' <<< "${raw_outbound}")" \
        --argjson extra_headers "$(jq -ec '._naive.extra_headers' <<< "${raw_outbound}")" \
        --argjson udp_over_tcp_enabled "$(jq -c '._listen_network | index("tcp") != null' <<< "${raw_outbound}")" \
        'del(._tls,._client_trust,._naive,._listen_network) | .tls=$tls |
         if $udp_over_tcp_enabled then .udp_over_tcp={enabled:true,version:2} else . end |
         if $quic then .quic=true else . end |
         if $cc != "bbr" then .quic_congestion_control=$cc else . end |
         if $insecure_concurrency > 0 then .insecure_concurrency=$insecure_concurrency else . end |
         if $stream_receive_window != "" then .stream_receive_window=$stream_receive_window else . end |
         if $quic_session_receive_window != "" then .quic_session_receive_window=$quic_session_receive_window else . end |
         if ($extra_headers | length) > 0 then .extra_headers=$extra_headers else . end' \
        <<< "${raw_outbound}" >> "${output_file}" || return 1
    done < "${raw_file}"
  done < <(jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}")

  expected_count=$(jq -r '[.instances[].authentication.users | length] | add // 0' <<< "${snapshot}") || return 1
  output_count=$(jq -s 'length' "${output_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${output_count}" == "${expected_count}" && "${output_count}" -gt 0 ]] || return 1
  jq -es 'length > 0 and (map(.tag) | unique | length) == length' "${output_file}" >/dev/null || return 1
  cat "${output_file}"
)

build_client_shadowtls_bundle_json() (
  local public_ip=${1:-} store_override=${2:-} store_file snapshot tmpdir records_file bundle_file instance_id listen_address server_address
  local detour_address detour_port version users_json trust server_name certificate_path certificate_pem tls_json expected_count record_count
  if [[ -n "${store_override}" ]]; then store_file=${store_override}; else store_file=$(plain_proxy_structured_store_file shadowtls) || return 1; fi
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store shadowtls "${store_file}" || return 1
  public_ip=${public_ip:-$(get_public_ip)}
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  snapshot=$(structured_instance_store_snapshot_json shadowtls "${store_file}") || return 1
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "${tmpdir}"' EXIT
  records_file="${tmpdir}/records.jsonl"
  bundle_file="${tmpdir}/bundle.json"
  : > "${records_file}" || return 1
  while IFS= read -r -d '' instance_id; do
    listen_address=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}") || return 1
    case "${listen_address}" in
      0.0.0.0|::) server_address=${public_ip} ;;
      127.*|::1) server_address=${listen_address}; printf '[WARN] ShadowTLS 实例 %s 绑定回环地址 %s；导出仅供本机使用，未宣称公网可达。\n' "${instance_id}" "${listen_address}" >&2 ;;
      *) server_address=${listen_address} ;;
    esac
    version=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .version' <<< "${snapshot}") || return 1
    users_json=$(jq -c --arg id "${instance_id}" '.instances[] | select(.id == $id) | .authentication.users' <<< "${snapshot}") || return 1
    detour_address=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .detour.listen.address' <<< "${snapshot}") || return 1
    detour_port=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .detour.listen.port' <<< "${snapshot}") || return 1
    server_name=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .client_tls.server_name' <<< "${snapshot}") || return 1
    trust=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .client_trust' <<< "${snapshot}") || return 1
    tls_json=$(jq -cn --arg server_name "${server_name}" '{enabled:true,server_name:$server_name}') || return 1
    if [[ "${trust}" == certificate ]]; then
      certificate_path=$(jq -er --arg id "${instance_id}" '.instances[] | select(.id == $id) | .client_tls.certificate_path' <<< "${snapshot}") || return 1
      certificate_pem=$(read_public_certificate_pem "${certificate_path}") || return 1
      tls_json=$(jq -cn --arg server_name "${server_name}" --arg certificate "${certificate_pem}" '{enabled:true,server_name:$server_name,certificate:$certificate}') || return 1
    fi
    jq -c --arg id "${instance_id}" --arg server "${server_address}" --arg detour_address "${detour_address}" --argjson detour_port "${detour_port}" --argjson version "${version}" --argjson users "${users_json}" --argjson tls "${tls_json}" '
      .instances[] | select(.id == $id) as $instance |
      (if $version == 3 then $users else [{name:"default",password:$instance.authentication.password}] end)[] as $user |
      ("shadowtls-" + $instance.id + "-" + ($user.name | @base64)) as $primary_tag |
      ($primary_tag + "-transport") as $transport_tag |
      {
        transport: (
          {type:"shadowtls",tag:$transport_tag,server:$server,server_port:$instance.listen.port,version:$version,tls:$tls} +
          (if $version == 2 then {password:$instance.authentication.password} elif $version == 3 then {password:$user.password} else {} end)
        ),
        primary: {type:"http",tag:$primary_tag,server:$detour_address,server_port:$detour_port,detour:$transport_tag}
      }
    ' <<< "${snapshot}" >> "${records_file}" || return 1
  done < <(jq -j '.instances[] | .id, "\u0000"' <<< "${snapshot}")
  expected_count=$(jq -r '[.instances[] | if .version == 3 then (.authentication.users | length) else 1 end] | add // 0' <<< "${snapshot}") || return 1
  record_count=$(jq -s 'length' "${records_file}") || return 1
  [[ "${expected_count}" =~ ^[0-9]+$ && "${record_count}" == "${expected_count}" && "${record_count}" -gt 0 ]] || return 1
  jq -s '{outbounds:[.[] | .transport, .primary],primary_tags:map(.primary.tag)}' "${records_file}" > "${bundle_file}" || return 1
  jq -e --argjson expected "${expected_count}" '
      . as $bundle |
      ($bundle.outbounds | length == ($expected * 2)) and
      ($bundle.primary_tags | length == $expected) and
      ($bundle.outbounds | (map(.tag) | unique | length) == length) and
      ($bundle.primary_tags | (unique | length) == length) and
      (all($bundle.outbounds[]; if .type == "shadowtls" then (.tls.enabled == true and (.tag | endswith("-transport")))
                              elif .type == "http" then (.detour | type == "string" and endswith("-transport"))
                              else false end))
    ' "${bundle_file}" >/dev/null || return 1
  cat "${bundle_file}"
)

build_client_shadowtls_outbounds() (
  local bundle_json
  bundle_json=$(build_client_shadowtls_bundle_json "$@") || return 1
  jq -c '.outbounds[]' <<< "${bundle_json}"
)

build_client_outbound_json_for_protocol() {
  local protocol original_protocol_state original_instance_id outbound_json build_status restore_original_state public_ip
  local default_instance_id adapter_status
  protocol=$(normalize_protocol_id "$1") || return 1
  public_ip=${2:-$(get_public_ip)}
  original_protocol_state=$(runtime_protocol_to_state "${SB_PROTOCOL}" 2>/dev/null || true)
  original_instance_id=""
  if [[ -n "${original_protocol_state}" ]] && protocol_state_exists "${original_protocol_state}"; then
    if original_instance_id=$(protocol_default_instance_id "${original_protocol_state}"); then
      :
    else
      adapter_status=$?
      return "${adapter_status}"
    fi
  fi
  build_status=0
  restore_original_state="n"

  case "${protocol}" in
    vless-reality|vless-plain|mixed|socks|http|shadowsocks|trojan|vmess|hy2|anytls|snell|tuic|hysteria|naive|shadowtls) ;;
    *)
      return 1
      ;;
  esac

  if [[ -n "${original_protocol_state}" && "${original_protocol_state}" != "${protocol}" ]] && protocol_state_exists "${original_protocol_state}"; then
    restore_original_state="y"
  fi

  if default_instance_id=$(protocol_default_instance_id "${protocol}"); then
    if load_protocol_instance_state "${protocol}" "${default_instance_id}"; then
      :
    else
      build_status=$?
    fi
  else
    build_status=$?
  fi

  if (( build_status == 0 )); then
    case "${protocol}" in
      mixed)
        if ! mixed_loaded_state_is_exportable; then
          printf '[ERROR] mixed_export_state_invalid: Mixed 原始状态不完整或无效，禁止以默认值生成客户端配置。\n' >&2
          build_status=1
        elif [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]]; then
          if outbound_json=$(build_client_mixed_outbounds "${public_ip}"); then
            :
          else
            build_status=$?
          fi
        elif outbound_json=$(build_client_mixed_outbound "${public_ip}"); then
          :
        else
          build_status=$?
        fi
        ;;
      socks)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active socks; then
          if outbound_json=$(build_client_socks_outbounds "${public_ip}"); then
            :
          else
            build_status=$?
          fi
        else
          printf '[ERROR] socks_export_state_invalid: SOCKS 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
      http)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active http; then
          if outbound_json=$(build_client_http_outbounds "${public_ip}"); then
            :
          else
            build_status=$?
          fi
        else
          printf '[ERROR] http_export_state_invalid: HTTP 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
      shadowsocks)
        if outbound_json=$(build_client_shadowsocks_outbounds "${public_ip}"); then :; else build_status=$?; fi
        ;;
      trojan)
        if outbound_json=$(build_client_trojan_outbounds "${public_ip}"); then :; else build_status=$?; fi
        ;;
      vmess)
        if outbound_json=$(build_client_vmess_outbounds "${public_ip}"); then :; else build_status=$?; fi
        ;;
      vless-plain)
        if outbound_json=$(build_client_vless_plain_outbounds "${public_ip}"); then :; else build_status=$?; fi
        ;;
      vless-reality)
        if outbound_json=$(build_client_vless_reality_outbounds "${public_ip}"); then
          :
        else
          build_status=$?
        fi
        ;;
      hy2)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active hy2; then
          if outbound_json=$(build_client_hy2_outbounds "${public_ip}"); then
            :
          else
            build_status=$?
          fi
        elif outbound_json=$(build_client_hy2_outbound); then
          :
        else
          build_status=$?
        fi
        ;;
      anytls)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active anytls; then
          if outbound_json=$(build_client_anytls_outbounds "${public_ip}"); then
            :
          else
            build_status=$?
          fi
        elif outbound_json=$(build_client_anytls_outbound); then
          :
        else
          build_status=$?
        fi
        ;;
      snell)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active snell; then
          if outbound_json=$(build_client_snell_outbounds "${public_ip}"); then :; else build_status=$?; fi
        else
          printf '[ERROR] snell_export_state_invalid: Snell 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
      tuic)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active tuic; then
          if outbound_json=$(build_client_tuic_outbounds "${public_ip}"); then :; else build_status=$?; fi
        else
          printf '[ERROR] tuic_export_state_invalid: TUIC 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
      hysteria)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active hysteria; then
          if outbound_json=$(build_client_hysteria_outbounds "${public_ip}"); then :; else build_status=$?; fi
        else
          printf '[ERROR] hysteria_export_state_invalid: Hysteria 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
      naive)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active naive; then
          if outbound_json=$(build_client_naive_outbounds "${public_ip}"); then :; else build_status=$?; fi
        else
          printf '[ERROR] naive_export_state_invalid: NaiveProxy 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
      shadowtls)
        if [[ "${CONFIG_SCHEMA_VERSION:-1}" == "2" ]] && plain_proxy_structured_state_active shadowtls; then
          if outbound_json=$(build_client_shadowtls_outbounds "${public_ip}"); then :; else build_status=$?; fi
        else
          printf '[ERROR] shadowtls_export_state_invalid: ShadowTLS 结构化状态不完整或无效，未生成客户端连接材料。\n' >&2
          build_status=1
        fi
        ;;
    esac
  fi

  if [[ "${restore_original_state}" == "y" ]]; then
    if [[ -n "${original_instance_id}" ]] &&
       load_protocol_instance_state "${original_protocol_state}" "${original_instance_id}" >/dev/null 2>&1; then
      :
    else
      adapter_status=$?
      [[ "${build_status}" == "0" ]] && build_status="${adapter_status}"
    fi
  fi

  if (( build_status != 0 )); then
    return "${build_status}"
  fi

  printf '%s\n' "${outbound_json}"
}
