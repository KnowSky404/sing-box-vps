
# Keep per-node metadata across requests without retaining raw connection data.
push_subman_node_with_result() {
  local external_key=$1 payload_json=$2 status=0 outcome
  reset_subman_api_result
  if push_subman_node "${external_key}" "${payload_json}"; then
    outcome=${SUBMAN_LAST_OUTCOME:-committed}
    [[ "${outcome}" == "committed" || "${outcome}" == "reconciled" ]] || outcome=committed
  else
    status=$?
    outcome=${SUBMAN_LAST_OUTCOME:-failed}
  fi
  SUBMAN_LAST_OUTCOME=${outcome}
  record_subman_node_result "${external_key}" || return 1
  return "${status}"
}

delete_subman_node_with_result() {
  local external_key=$1 quiet=${2:-n} status=0 outcome
  reset_subman_api_result
  if delete_subman_node_by_external_key "${external_key}" "${quiet}"; then
    outcome=${SUBMAN_LAST_OUTCOME:-absent}
    case "${outcome}" in committed|reconciled|absent) ;; *) outcome=absent ;; esac
  else
    status=$?
    outcome=${SUBMAN_LAST_OUTCOME:-failed}
  fi
  SUBMAN_LAST_OUTCOME=${outcome}
  record_subman_node_result "${external_key}" "" "" "" delete || return 1
  return "${status}"
}

record_subman_node_result() {
  local external_key=${1:-} outcome=${SUBMAN_LAST_OUTCOME:-failed}
  SUBMAN_NODE_RESULTS_JSON=$(jq -c \
    --arg key "${external_key}" --arg protocol "${2:-}" \
    --arg instance_id "${3:-}" --arg address_label "${4:-}" --arg node_id "${SUBMAN_LAST_NODE_ID:-}" \
    --arg operation "${5:-upsert}" --arg outcome "${outcome}" --arg gist_id "${SUBMAN_LAST_GIST_ID:-}" \
    --arg revision "${SUBMAN_LAST_REVISION:-}" \
    --arg code "${SUBMAN_LAST_ERROR_CODE:-}" \
    --arg disposition "${SUBMAN_LAST_ERROR_DISPOSITION:-}" \
    --arg http_status "${SUBMAN_LAST_HTTP_STATUS:-}" \
    --arg retry_after "${SUBMAN_LAST_RETRY_AFTER:-}" '
      . + [{external_key:(if $key == "" then null else $key end), node_id:(if $node_id == "" then null else $node_id end),
        operation:$operation, outcome:$outcome, gist_id:(if $gist_id == "" then null else $gist_id end),
        revision:(if $revision == "" then null else ($revision|tonumber) end)}
        + (if $protocol == "" then {} else {protocol:$protocol,instance_id:$instance_id,address_label:$address_label} end)
        + (if $code == "" then {} else {error:{code:$code,disposition:$disposition,
          http_status:(if $http_status == "" then null else $http_status end),
          retry_after:(if $retry_after == "" then null else $retry_after end)}} end)]' <<< "${SUBMAN_NODE_RESULTS_JSON:-[]}") || return 1
}

record_subman_key_failure() {
  local protocol=$1 instance_id=${2:-} address_label=${3:-} quiet=${4:-n}
  reset_subman_api_result
  subman_set_client_error "invalid_external_key" "invalid-request"
  record_subman_node_result "" "${protocol}" "${instance_id}" "${address_label}" || return 1
  [[ "${quiet}" == y ]] || print_warn "SubMan 外部键生成失败或超过 119 UTF-8 字节: ${protocol}/${instance_id}；请缩短节点前缀并明确处理旧身份。"
  return 0
}

record_subman_address_failure() {
  local protocol=$1 instance_id=${2:-} quiet=${3:-n}
  reset_subman_api_result
  subman_set_client_error "public_ip_unavailable" "retryable-upstream"
  record_subman_node_result "" "${protocol}" "${instance_id}" "" || return 1
  [[ "${quiet}" == y ]] || print_warn "未获取到与监听地址匹配的公网 IP，无法生成 SubMan 节点链接: ${protocol}/${instance_id}。"
  return 0
}

select_subman_outbound_by_tag() {
  local tag=${1:-}
  [[ -n "${tag}" ]] || return 1
  # jq 1.6 can return failure when a later stream record does not match.
  # Select once from the complete stream and reject missing/ambiguous identity.
  jq -cse --arg tag "${tag}" '
    map(select(.tag == $tag))
    | if length == 1 then .[0] else error("SubMan outbound tag must match exactly one record") end'
}

subman_node_prefix() {
  local prefix
  prefix=$(trim_whitespace "${SUBMAN_NODE_PREFIX:-}")
  [[ -z "${prefix}" ]] && prefix=$(hostname)
  printf '%s' "${prefix}"
}

subman_type_for_protocol() {
  local type
  type=$(protocol_registry_field "$1" subman_type) || return 1
  [[ -n "${type}" ]] || return 1
  printf '%s' "${type}"
}

subman_unsupported_protocol_warning_json() {
  local protocol=${1:-}
  [[ -n "${protocol}" ]] || return 1
  jq -cn --arg protocol "${protocol}" '[{
    code: "subman_protocol_unsupported",
    protocol: $protocol,
    message: ($protocol + " 当前没有可保真 SubMan 载荷，已跳过。")
  }]'
}

subman_external_key_is_valid() {
  local external_key=${1:-} key_bytes
  [[ -n "${external_key}" ]] || return 1
  key_bytes=$(printf '%s' "${external_key}" | wc -c | tr -d '[:space:]') || return 1
  [[ "${key_bytes}" =~ ^[0-9]+$ && "${key_bytes}" -le 119 ]]
}

subman_external_key_for_protocol() {
  local protocol prefix instance_id address_label stack_suffix key
  protocol=$(normalize_protocol_id "$1")
  instance_id=${2:-}
  address_label=${3:-}
  prefix=$(subman_node_prefix)

  if [[ "${protocol}" == "vless-reality" && -n "${instance_id}" && "${instance_id}" != "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" ]]; then
    key=$(printf 'sing-box-vps:%s:%s:%s' "${prefix}" "${protocol}" "${instance_id}")
  else
    key=$(printf 'sing-box-vps:%s:%s' "${prefix}" "${protocol}")
  fi

  stack_suffix=$(network_stack_suffix_from_label "${address_label}")
  if [[ -n "${stack_suffix}" ]]; then
    key="${key}:${stack_suffix}"
  fi

  subman_external_key_is_valid "${key}" || return 1
  printf '%s' "${key}"
}

subman_external_key_for_shadowsocks_user() {
  local instance_id=${1:-} user_name=${2:-} address_label=${3:-}
  local prefix digest key stack_suffix

  structured_instance_store_validate_id "${instance_id}" || return 1
  prefix=$(subman_node_prefix)
  digest=$(printf '%s' "${user_name}" | sha256sum) || return 1
  digest=${digest%% *}
  key="sing-box-vps:${prefix}:shadowsocks:${instance_id}:user-${digest}"
  stack_suffix=$(network_stack_suffix_from_label "${address_label}")
  if [[ -n "${stack_suffix}" ]]; then
    key="${key}:${stack_suffix}"
  fi
  subman_external_key_is_valid "${key}" || return 1
  printf '%s' "${key}"
}


build_subman_shadowsocks_node_payload() {
  local outbound=${1:-} name=${2:-} node_type prefix raw_link

  [[ -n "${outbound}" && -n "${name}" ]] || return 1
  node_type=$(subman_type_for_protocol shadowsocks) || return 1
  raw_link=$(build_shadowsocks_uri "${outbound}" "${name}") || return 1
  prefix=$(subman_node_prefix)
  jq -n \
    --arg name "${name}" \
    --arg type "${node_type}" \
    --arg raw "${raw_link}" \
    --arg prefix "${prefix}" \
    '{name:$name,type:$type,raw:$raw,enabled:true,tags:["sing-box-vps",$prefix],source:"single"}'
}

trojan_share_skip() {
  TROJAN_SHARE_SKIP_CODE=${1:-trojan_uri_unrepresentable}
  TROJAN_SHARE_SKIP_MESSAGE=${2:-Trojan 当前配置无法无损转换为 SubMan raw URI。}
  return 2
}

trojan_share_query_value_safe() {
  local value=${1-}
  # SubMan's query parser trims Unicode whitespace. Reject values whose
  # leading/trailing bytes would therefore be changed by a raw URI roundtrip.
  jq -en --arg value "${value}" \
    '$value | (test("^[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]") or test("[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]$")) | not' \
    >/dev/null
}

trojan_share_uri_query() {
  local transport_json=${1:-} tls_json=${2:-} profile transport_type path host service_name
  local encoded value query=""

  [[ -n "${transport_json}" && -n "${tls_json}" ]] || return 1
  transport_type=$(jq -er '.type' <<< "${transport_json}") || return 1
  case "${transport_type}" in
    none)
      jq -e 'keys_unsorted == ["type"]' <<< "${transport_json}" >/dev/null || return 1
      ;;
    ws)
      jq -e '
        (keys_unsorted - ["type","path","headers","max_early_data","early_data_header_name"] | length) == 0 and
        ((.max_early_data // 0) == 0) and
        ((.early_data_header_name // "") == "") and
        ((.headers // {}) | keys_unsorted | map(ascii_downcase) | unique) ==
          ((.headers // {}) | keys_unsorted | map(ascii_downcase) | unique) and
        (((.headers // {}) | keys_unsorted | length) == 0 or
          ((.headers | keys_unsorted) == ["Host"] and (.headers.Host | type == "string")))
      ' <<< "${transport_json}" >/dev/null || return 1
      path=$(jq -r '.path // ""' <<< "${transport_json}") || return 1
      host=$(jq -r '.headers.Host // empty' <<< "${transport_json}") || return 1
      trojan_share_query_value_safe "${path}" || return 1
      [[ -z "${host}" ]] || trojan_share_query_value_safe "${host}" || return 1
      encoded=$(jq -rn --arg value "${path}" '$value|@uri') || return 1
      query="type=ws&path=${encoded}"
      if [[ -n "${host}" ]]; then
        encoded=$(jq -rn --arg value "${host}" '$value|@uri') || return 1
        query="${query}&host=${encoded}"
      fi
      ;;
    http)
      jq -e '
        (keys_unsorted - ["type","path","host"] | length) == 0 and
        (if has("host") then
          (.host | if type == "array" then length == 1 and (.[0] | type == "string")
                   elif type == "string" then true else false end)
         else true end)
      ' <<< "${transport_json}" >/dev/null || return 1
      path=$(jq -r '.path // ""' <<< "${transport_json}") || return 1
      host=$(jq -r 'if (.host | type) == "array" then .host[0] // empty else .host // empty end' <<< "${transport_json}") || return 1
      trojan_share_query_value_safe "${path}" || return 1
      [[ -z "${host}" ]] || trojan_share_query_value_safe "${host}" || return 1
      encoded=$(jq -rn --arg value "${path}" '$value|@uri') || return 1
      query="type=http&path=${encoded}"
      if [[ -n "${host}" ]]; then
        encoded=$(jq -rn --arg value "${host}" '$value|@uri') || return 1
        query="${query}&host=${encoded}"
      fi
      ;;
    grpc)
      jq -e 'keys_unsorted - ["type","service_name"] | length == 0' <<< "${transport_json}" >/dev/null || return 1
      service_name=$(jq -r '.service_name // empty' <<< "${transport_json}") || return 1
      [[ -z "${service_name}" ]] || trojan_share_query_value_safe "${service_name}" || return 1
      query='type=grpc'
      if [[ -n "${service_name}" ]]; then
        encoded=$(jq -rn --arg value "${service_name}" '$value|@uri') || return 1
        query="${query}&service_name=${encoded}"
      fi
      ;;
    quic)
      jq -e 'keys_unsorted == ["type"]' <<< "${transport_json}" >/dev/null || return 1
      query='type=quic'
      ;;
    *) return 1 ;;
  esac

  profile=$(build_v2ray_transport_profile_json trojan "${transport_json}" tls '' "$(resolve_config_target_singbox_version)") || return 1
  if jq -e '.tls_alpn | length > 0' <<< "${profile}" >/dev/null; then
    value=$(jq -r '.tls_alpn | join(",")' <<< "${profile}") || return 1
    encoded=$(jq -rn --arg value "${value}" '$value|@uri') || return 1
    query="${query}&alpn=${encoded}"
  fi
  value=$(jq -er '.server_name' <<< "${tls_json}") || return 1
  trojan_share_query_value_safe "${value}" || return 1
  encoded=$(jq -rn --arg value "${value}" '$value|@uri') || return 1
  printf 'sni=%s&%s' "${encoded}" "${query}"
}

build_trojan_subman_uri_from_store() (
  local store_file=${1:-} server=${2:-} instance_id=${3:-} user_name=${4-} node_name=${5:-Trojan}
  local snapshot instance tls_json transport_json client_trust password_encoded name_encoded query share_host port uri uri_bytes

  [[ $# -eq 5 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  structured_instance_store_validate_id "${instance_id}" || return 1
  validate_structured_instance_store trojan "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || return 1
  instance=$(jq -ce --arg id "${instance_id}" --arg user "${user_name}" \
    '.instances[] | select(.id == $id) | . as $instance |
     ($instance.authentication.users[] | select(.name == $user)) |
     {instance:$instance,user:.}' <<< "${snapshot}") || return 1
  tls_json=$(jq -ce '.instance.tls' <<< "${instance}") || return 1
  client_trust=$(jq -er '.instance.client_trust' <<< "${instance}") || return 1
  if ! jq -e '.enabled == true' <<< "${tls_json}" >/dev/null; then
    trojan_share_skip trojan_tls_disabled_uri_unrepresentable 'Trojan 明文入口无法转换为 SubMan 默认 TLS raw URI；该用户已跳过。'
    return 20
  fi
  if [[ "${client_trust}" != system ]]; then
    trojan_share_skip trojan_tls_certificate_uri_unrepresentable 'Trojan 自定义证书信任无法由 SubMan raw URI 无损表达；该用户已跳过。'
    return 21
  fi
  transport_json=$(jq -ce '.instance.transport' <<< "${instance}") || return 1
  if ! query=$(trojan_share_uri_query "${transport_json}" "${tls_json}"); then
    trojan_share_skip trojan_transport_uri_unrepresentable 'Trojan transport 包含 SubMan raw URI 无法无损表达的字段；该用户已跳过。'
    return 22
  fi
  password_encoded=$(jq -er '.user.password | @uri' <<< "${instance}") || return 1
  name_encoded=$(jq -rn --arg value "${node_name}" '$value|@uri') || return 1
  port=$(jq -er '.instance.listen.port' <<< "${instance}") || return 1
  share_host=$(format_share_host "${server}") || return 1
  uri="trojan://${password_encoded}@${share_host}:${port}?${query}#${name_encoded}"
  uri_bytes=$(printf '%s' "${uri}" | wc -c) || return 1
  [[ "${uri_bytes}" =~ ^[0-9]+$ && "${uri_bytes}" -le 16384 ]] || \
    { trojan_share_skip trojan_uri_too_large 'Trojan raw URI 超过 SubMan 16384 字节上限；该用户已跳过。'; return 23; }
  printf '%s' "${uri}"
)

trojan_share_warning_for_status() {
  local status=${1:-1}
  case "${status}" in
    20) build_trojan_share_warnings_json trojan_tls_disabled_uri_unrepresentable \
      'Trojan 明文入口无法转换为 SubMan 默认 TLS raw URI；该用户已跳过。' ;;
    21) build_trojan_share_warnings_json trojan_tls_certificate_uri_unrepresentable \
      'Trojan 自定义证书信任无法由 SubMan raw URI 无损表达；该用户已跳过。' ;;
    22) build_trojan_share_warnings_json trojan_transport_uri_unrepresentable \
      'Trojan transport 包含 SubMan raw URI 无法无损表达的字段；该用户已跳过。' ;;
    23) build_trojan_share_warnings_json trojan_uri_too_large \
      'Trojan raw URI 超过 SubMan 16384 字节上限；该用户已跳过。' ;;
    *) return 1 ;;
  esac
}

build_trojan_subman_links_and_warnings_json() (
  local node_name_digests
  local server=${1:-} instance_id=${2:-} store_file snapshot snapshot_file instance node_name user_name tag uri status
  local links='{}' warnings='[]' warning users_text address_label
  [[ $# -ge 1 && $# -le 2 ]] || return 1
  store_file=$(plain_proxy_structured_store_file trojan) || return 1
  snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || return 1
  snapshot_file=$(storage_mktemp) || return 1
  trap 'rm -f -- "${snapshot_file}"' EXIT
  printf '%s\n' "${snapshot}" > "${snapshot_file}" || return 1
  instance_id=${2:-$(jq -er '.default_instance_id' <<< "${snapshot}")}
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || return 1
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
  address_label=$(node_display_address_label "$(jq -r '.listen.address' <<< "${instance}")" "${server}") || return 1
  users_text=$(jq -r '.authentication.users[].name' <<< "${instance}") || return 1
  while IFS= read -r user_name; do
    [[ -n "${user_name}" ]] || continue
    tag=$(jq -r --arg user "${user_name}" '"trojan-" + .id + "-user-" + ($user | @base64)' <<< "${instance}") || return 1
    node_name=$(structured_node_display_name trojan "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    if uri=$(build_trojan_subman_uri_from_store "${snapshot_file}" "${server}" "${instance_id}" "${user_name}" "${node_name}"); then
      links=$(jq -cn --argjson links "${links}" --arg tag "${tag}" --arg uri "${uri}" '$links + {($tag):$uri}') || return 1
    else
      status=$?
      if [[ "${status}" =~ ^2[0-3]$ ]]; then
        warning=$(trojan_share_warning_for_status "${status}") || return 1
        warnings=$(jq -cn --argjson warnings "${warnings}" --argjson warning "${warning}" \
          --arg instance_id "${instance_id}" --arg tag "${tag}" \
          '$warnings + ($warning | map(. + {instance_id:$instance_id,outbound_tag:$tag}))') || return 1
      else
        return "${status}"
      fi
    fi
  done <<< "${users_text}"
  jq -cn --argjson links "${links}" --argjson warnings "${warnings}" '{links:$links,warnings:$warnings}'
)

build_trojan_share_warnings_json() {
  local code=${1:-trojan_uri_unrepresentable} message=${2:-Trojan 当前配置无法无损转换为 SubMan raw URI。}
  jq -cn --arg code "${code}" --arg message "${message}" '[{code:$code,message:$message}]'
}

subman_external_key_for_trojan_user() {
  local instance_id=${1:-} user_name=${2-} address_label=${3:-}
  local prefix digest key stack_suffix
  structured_instance_store_validate_id "${instance_id}" || return 1
  prefix=$(subman_node_prefix) || return 1
  digest=$(printf '%s' "${user_name}" | sha256sum) || return 1
  digest=${digest%% *}
  key="sing-box-vps:${prefix}:trojan:${instance_id}:user-${digest}"
  stack_suffix=$(network_stack_suffix_from_label "${address_label}") || return 1
  [[ -z "${stack_suffix}" ]] || key="${key}:${stack_suffix}"
  subman_external_key_is_valid "${key}" || return 1
  printf '%s' "${key}"
}


build_subman_trojan_node_payload() {
  local raw_link=${1:-} name=${2:-} node_type prefix
  [[ -n "${raw_link}" && -n "${name}" ]] || return 1
  node_type=$(subman_type_for_protocol trojan) || return 1
  prefix=$(subman_node_prefix) || return 1
  jq -n --arg name "${name}" --arg type "${node_type}" --arg raw "${raw_link}" \
    --arg prefix "${prefix}" \
    '{name:$name,type:$type,raw:$raw,enabled:true,tags:["sing-box-vps",$prefix],source:"single"}'
}

push_subman_trojan_instance() {
  local node_name_digests
  local instance_id=${1:-} server=${2:-} quiet=${3:-n} address_label=${4:-}
  local store_file snapshot snapshot_file producer_file instance user_name node_name raw_link external_key payload_json status producer_count
  local users_text
  local synced=0 skipped=0 failed=0 warnings='[]' warning

  SUBMAN_TROJAN_SYNCED=0
  SUBMAN_TROJAN_SKIPPED=0
  SUBMAN_TROJAN_FAILED=0
  SUBMAN_TROJAN_WARNINGS_JSON='[]'
  structured_instance_store_validate_id "${instance_id}" || { SUBMAN_TROJAN_FAILED=1; return 1; }
  store_file=$(plain_proxy_structured_store_file trojan) || { SUBMAN_TROJAN_FAILED=1; return 1; }
  snapshot=$(structured_instance_store_snapshot_json trojan "${store_file}") || { SUBMAN_TROJAN_FAILED=1; return 1; }
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || { SUBMAN_TROJAN_FAILED=1; return 1; }
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || { SUBMAN_TROJAN_FAILED=1; return 1; }
  if ! listener_address_is_wildcard "$(jq -r '.listen.address' <<< "${instance}")"; then
    server=$(jq -r '.listen.address' <<< "${instance}") || return 1
  fi
  # Validate the complete node connection material before any
  # SubMan mutation. Certificate-trust users are intentionally excluded here:
  # their URI is skipped because SubMan cannot carry the custom trust, while
  # their certificate file must not become a sync prerequisite.
  producer_file=$(storage_mktemp) || { SUBMAN_TROJAN_FAILED=1; return 1; }
  jq --arg id "${instance_id}" \
    '. as $root | ($root.instances | map(select(.id == $id and .client_trust == "system"))) as $instances |
     $root | .default_instance_id=$id | .instances=$instances' <<< "${snapshot}" > "${producer_file}" || {
    rm -f -- "${producer_file}"
    SUBMAN_TROJAN_FAILED=1
    return 1
  }
  producer_count=$(jq -r '.instances | length' "${producer_file}") || {
    rm -f -- "${producer_file}"
    SUBMAN_TROJAN_FAILED=1
    return 1
  }
  if [[ "${producer_count}" != 0 ]]; then
    if ! build_trojan_client_outbounds_from_store "${producer_file}" "${server}" >/dev/null; then
      rm -f -- "${producer_file}"
      SUBMAN_TROJAN_FAILED=1
      return 1
    fi
  fi
  rm -f -- "${producer_file}" || { SUBMAN_TROJAN_FAILED=1; return 1; }
  snapshot_file=$(storage_mktemp) || { SUBMAN_TROJAN_FAILED=1; return 1; }
  printf '%s\n' "${snapshot}" > "${snapshot_file}" || { rm -f -- "${snapshot_file}"; SUBMAN_TROJAN_FAILED=1; return 1; }
  users_text=$(jq -r '.authentication.users[].name' <<< "${instance}") || { rm -f -- "${snapshot_file}"; SUBMAN_TROJAN_FAILED=1; return 1; }
  while IFS= read -r user_name; do
    [[ -n "${user_name}" ]] || continue
    node_name=$(structured_node_display_name trojan "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || { failed=$((failed + 1)); continue; }
    if raw_link=$(build_trojan_subman_uri_from_store "${snapshot_file}" "${server}" "${instance_id}" "${user_name}" "${node_name}"); then
      :
    else
      status=$?
      if [[ "${status}" =~ ^2[0-3]$ ]]; then
        skipped=$((skipped + 1))
        warning=$(trojan_share_warning_for_status "${status}") || { failed=$((failed + 1)); continue; }
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson addition "${warning}" \
          --arg instance_id "${instance_id}" --arg user "${user_name}" \
          '$existing + ($addition | map(. + {instance_id:$instance_id,
            outbound_tag:("trojan-" + $instance_id + "-user-" + ($user | @base64))}))') || {
          failed=$((failed + 1))
          continue
        }
        [[ "${quiet}" == y ]] || print_warn "Trojan 实例 ${instance_id} 用户 ${user_name} 无法无损转换为 SubMan raw URI，已跳过。"
      else
        failed=$((failed + 1))
      fi
      continue
    fi
    external_key=$(subman_external_key_for_trojan_user "${instance_id}" "${user_name}" "${address_label}") || { record_subman_key_failure trojan "${instance_id}" "${address_label}" "${quiet}"; failed=$((failed + 1)); continue; }
    payload_json=$(build_subman_trojan_node_payload "${raw_link}" "${node_name}") || { failed=$((failed + 1)); continue; }
    if [[ "${quiet}" == y ]]; then
      if push_subman_node_with_result "${external_key}" "${payload_json}" >/dev/null; then synced=$((synced + 1)); else failed=$((failed + 1)); fi
    elif push_subman_node_with_result "${external_key}" "${payload_json}"; then
      synced=$((synced + 1))
    else
      failed=$((failed + 1))
    fi
  done <<< "${users_text}"
  rm -f -- "${snapshot_file}" || failed=$((failed + 1))
  SUBMAN_TROJAN_SYNCED=${synced}
  SUBMAN_TROJAN_SKIPPED=${skipped}
  SUBMAN_TROJAN_FAILED=${failed}
  SUBMAN_TROJAN_WARNINGS_JSON=${warnings}
  (( failed == 0 && (synced > 0 || skipped > 0) ))
}

push_subman_trojan_protocol() {
  local quiet=${1:-n} instance_ids instance_id address_entries address_entry address_label public_ip
  local total_synced=0 total_skipped=0 total_failed=0 warnings='[]' push_status=0
  SUBMAN_TROJAN_SYNCED=0
  SUBMAN_TROJAN_SKIPPED=0
  SUBMAN_TROJAN_FAILED=0
  SUBMAN_TROJAN_WARNINGS_JSON='[]'
  instance_ids=$(list_protocol_instance_ids trojan) || { SUBMAN_TROJAN_FAILED=1; return 1; }
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    load_protocol_instance_state trojan "${instance_id}" || { total_failed=$((total_failed + 1)); continue; }
    if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
      record_subman_address_failure trojan "${instance_id}" "${quiet}" || return 1
      total_failed=$((total_failed + 1))
      continue
    fi
    while IFS= read -r address_entry; do
      [[ -n "${address_entry}" ]] || continue
      address_label=${address_entry%%|*}
      public_ip=${address_entry#*|}
      if push_subman_trojan_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}"; then
        push_status=0
      else
        push_status=$?
      fi
      total_synced=$((total_synced + ${SUBMAN_TROJAN_SYNCED:-0}))
      total_skipped=$((total_skipped + ${SUBMAN_TROJAN_SKIPPED:-0}))
      total_failed=$((total_failed + ${SUBMAN_TROJAN_FAILED:-0}))
      if [[ "${push_status}" != 0 && "${SUBMAN_TROJAN_FAILED:-0}" == 0 ]]; then
        total_failed=$((total_failed + 1))
      fi
      if [[ -n "${SUBMAN_TROJAN_WARNINGS_JSON:-}" ]]; then
        if ! warnings=$(jq -cn --argjson existing "${warnings}" --argjson additions "${SUBMAN_TROJAN_WARNINGS_JSON}" '$existing + $additions'); then
          SUBMAN_TROJAN_SYNCED=${total_synced}
          SUBMAN_TROJAN_SKIPPED=${total_skipped}
          SUBMAN_TROJAN_FAILED=$((total_failed + 1))
          SUBMAN_TROJAN_WARNINGS_JSON='[]'
          return 1
        fi
      fi
    done <<< "${address_entries}"
  done <<< "${instance_ids}"
  SUBMAN_TROJAN_SYNCED=${total_synced}
  SUBMAN_TROJAN_SKIPPED=${total_skipped}
  SUBMAN_TROJAN_FAILED=${total_failed}
  SUBMAN_TROJAN_WARNINGS_JSON=${warnings}
  (( total_failed == 0 && (total_synced > 0 || total_skipped > 0) ))
}

vmess_share_skip() {
  VMESS_SHARE_SKIP_CODE=${1:-vmess_uri_unrepresentable}
  VMESS_SHARE_SKIP_MESSAGE=${2:-VMess 当前配置无法无损转换为 SubMan raw URI。}
  return 2
}

build_vmess_subman_uri_from_store() (
  local store_file=${1:-} server=${2:-} instance_id=${3:-} user_name=${4-} node_name=${5:-VMess}
  local snapshot instance client_trust tag outbound uri uri_bytes filtered_file
  [[ $# -eq 5 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  structured_instance_store_validate_id "${instance_id}" || return 1
  validate_structured_instance_store vmess "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || return 1
  instance=$(jq -ce --arg id "${instance_id}" --arg user "${user_name}" '.instances[] | select(.id == $id) | select(any(.authentication.users[]; .name == $user))' <<< "${snapshot}") || return 1
  client_trust=$(jq -er '.client_trust' <<< "${instance}") || return 1
  if [[ "${client_trust}" != system ]]; then
    vmess_share_skip vmess_tls_certificate_uri_unrepresentable 'VMess 自定义证书信任无法由 SubMan raw URI 无损表达；该用户已跳过。'
    return 31
  fi
  tag=$(jq -r --arg user "${user_name}" '"vmess-" + .id + "-user-" + ($user | @base64)' <<< "${instance}") || return 1
  filtered_file=$(storage_mktemp) || return 1
  trap 'rm -f -- "${filtered_file}"' EXIT
  jq -e --arg id "${instance_id}" '.instances |= map(select(.id == $id)) | .default_instance_id=$id' \
    <<< "${snapshot}" > "${filtered_file}" || return 1
  outbound=$(build_vmess_client_outbounds_from_store "${filtered_file}" "${server}" | select_subman_outbound_by_tag "${tag}") || return 1
  uri=$(build_vmess_uri_from_outbound "${outbound}" "${node_name}") || return 1
  uri_bytes=$(printf '%s' "${uri}" | wc -c) || return 1
  [[ "${uri_bytes}" =~ ^[0-9]+$ && "${uri_bytes}" -le 16384 ]] || {
    vmess_share_skip vmess_uri_too_large 'VMess raw URI 超过 SubMan 16384 字节上限；该用户已跳过。'; return 32;
  }
  printf '%s' "${uri}"
)

vmess_share_warning_for_status() {
  case "${1:-1}" in
    31) jq -cn '[{code:"vmess_tls_certificate_uri_unrepresentable",message:"VMess 自定义证书信任无法由 SubMan raw URI 无损表达；该用户已跳过。"}]' ;;
    32) jq -cn '[{code:"vmess_uri_too_large",message:"VMess raw URI 超过 SubMan 16384 字节上限；该用户已跳过。"}]' ;;
    *) return 1 ;;
  esac
}

subman_external_key_for_vmess_user() {
  local instance_id=${1:-} user_name=${2-} address_label=${3:-} prefix digest key stack_suffix
  structured_instance_store_validate_id "${instance_id}" || return 1
  prefix=$(subman_node_prefix) || return 1; digest=$(printf '%s' "${user_name}" | sha256sum); digest=${digest%% *}
  key="sing-box-vps:${prefix}:vmess:${instance_id}:user-${digest}"
  stack_suffix=$(network_stack_suffix_from_label "${address_label}") || return 1
  [[ -z "${stack_suffix}" ]] || key="${key}:${stack_suffix}"
  subman_external_key_is_valid "${key}" || return 1
  printf '%s' "${key}"
}


build_subman_vmess_node_payload() {
  local raw_link=${1:-} name=${2:-} node_type prefix
  [[ -n "${raw_link}" && -n "${name}" ]] || return 1
  node_type=$(subman_type_for_protocol vmess) || return 1; prefix=$(subman_node_prefix) || return 1
  jq -n --arg name "${name}" --arg type "${node_type}" --arg raw "${raw_link}" --arg prefix "${prefix}" '{name:$name,type:$type,raw:$raw,enabled:true,tags:["sing-box-vps",$prefix],source:"single"}'
}

push_subman_vmess_instance() {
  local node_name_digests
  local instance_id=${1:-} server=${2:-} quiet=${3:-n} address_label=${4:-}
  local store_file snapshot snapshot_file instance user_name node_name raw_link external_key payload_json status warning users_text
  local synced=0 skipped=0 failed=0 warnings='[]'
  SUBMAN_VMESS_SYNCED=0; SUBMAN_VMESS_SKIPPED=0; SUBMAN_VMESS_FAILED=0; SUBMAN_VMESS_WARNINGS_JSON='[]'
  structured_instance_store_validate_id "${instance_id}" || { SUBMAN_VMESS_FAILED=1; return 1; }
  store_file=$(plain_proxy_structured_store_file vmess) || { SUBMAN_VMESS_FAILED=1; return 1; }
  snapshot=$(structured_instance_store_snapshot_json vmess "${store_file}") || { SUBMAN_VMESS_FAILED=1; return 1; }
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || { SUBMAN_VMESS_FAILED=1; return 1; }
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || { SUBMAN_VMESS_FAILED=1; return 1; }
  if ! listener_address_is_wildcard "$(jq -r '.listen.address' <<< "${instance}")"; then
    server=$(jq -r '.listen.address' <<< "${instance}") || return 1
  fi
  snapshot_file=$(storage_mktemp) || { SUBMAN_VMESS_FAILED=1; return 1; }; printf '%s\n' "${snapshot}" > "${snapshot_file}" || { rm -f -- "${snapshot_file}"; SUBMAN_VMESS_FAILED=1; return 1; }
  users_text=$(jq -r '.authentication.users[].name' <<< "${instance}") || { rm -f -- "${snapshot_file}"; SUBMAN_VMESS_FAILED=1; return 1; }
  while IFS= read -r user_name; do
    [[ -n "${user_name}" ]] || continue
    node_name=$(structured_node_display_name vmess "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || { failed=$((failed + 1)); continue; }
    if raw_link=$(build_vmess_subman_uri_from_store "${snapshot_file}" "${server}" "${instance_id}" "${user_name}" "${node_name}"); then
      external_key=$(subman_external_key_for_vmess_user "${instance_id}" "${user_name}" "${address_label}") || { record_subman_key_failure vmess "${instance_id}" "${address_label}" "${quiet}"; failed=$((failed + 1)); continue; }
      payload_json=$(build_subman_vmess_node_payload "${raw_link}" "${node_name}") || { failed=$((failed + 1)); continue; }
      if [[ "${quiet}" == y ]]; then push_subman_node_with_result "${external_key}" "${payload_json}" >/dev/null && synced=$((synced + 1)) || failed=$((failed + 1)); else push_subman_node_with_result "${external_key}" "${payload_json}" && synced=$((synced + 1)) || failed=$((failed + 1)); fi
    else
      status=$?
      if [[ "${status}" == 31 || "${status}" == 32 ]]; then
        skipped=$((skipped + 1)); warning=$(vmess_share_warning_for_status "${status}") || { failed=$((failed + 1)); continue; }
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson addition "${warning}" --arg instance_id "${instance_id}" --arg user "${user_name}" '$existing + ($addition | map(. + {instance_id:$instance_id,outbound_tag:("vmess-" + $instance_id + "-user-" + ($user | @base64))}))') || { failed=$((failed + 1)); continue; }
        [[ "${quiet}" == y ]] || print_warn "VMess 实例 ${instance_id} 用户 ${user_name} 无法无损转换为 SubMan raw URI，已跳过。"
      else failed=$((failed + 1)); fi
    fi
  done <<< "${users_text}"
  rm -f -- "${snapshot_file}" || failed=$((failed + 1))
  SUBMAN_VMESS_SYNCED=${synced}; SUBMAN_VMESS_SKIPPED=${skipped}; SUBMAN_VMESS_FAILED=${failed}; SUBMAN_VMESS_WARNINGS_JSON=${warnings}
  (( failed == 0 && (synced > 0 || skipped > 0) ))
}

push_subman_vmess_protocol() {
  local quiet=${1:-n} instance_ids instance_id address_entries address_entry address_label public_ip
  local total_synced=0 total_skipped=0 total_failed=0 warnings='[]'
  SUBMAN_VMESS_SYNCED=0; SUBMAN_VMESS_SKIPPED=0; SUBMAN_VMESS_FAILED=0; SUBMAN_VMESS_WARNINGS_JSON='[]'
  instance_ids=$(list_protocol_instance_ids vmess) || { SUBMAN_VMESS_FAILED=1; return 1; }
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    load_protocol_instance_state vmess "${instance_id}" || { total_failed=$((total_failed + 1)); continue; }
    if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
      record_subman_address_failure vmess "${instance_id}" "${quiet}" || return 1
      total_failed=$((total_failed + 1))
      continue
    fi
    while IFS= read -r address_entry; do
      [[ -n "${address_entry}" ]] || continue; address_label=${address_entry%%|*}; public_ip=${address_entry#*|}
      push_subman_vmess_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}" || :
      total_synced=$((total_synced + ${SUBMAN_VMESS_SYNCED:-0})); total_skipped=$((total_skipped + ${SUBMAN_VMESS_SKIPPED:-0})); total_failed=$((total_failed + ${SUBMAN_VMESS_FAILED:-0}))
      if [[ -n "${SUBMAN_VMESS_WARNINGS_JSON:-}" ]]; then warnings=$(jq -cn --argjson a "${warnings}" --argjson b "${SUBMAN_VMESS_WARNINGS_JSON}" '$a+$b') || return 1; fi
    done <<< "${address_entries}"
  done <<< "${instance_ids}"
  SUBMAN_VMESS_SYNCED=${total_synced}; SUBMAN_VMESS_SKIPPED=${total_skipped}; SUBMAN_VMESS_FAILED=${total_failed}; SUBMAN_VMESS_WARNINGS_JSON=${warnings}
  (( total_failed == 0 && (total_synced > 0 || total_skipped > 0) ))
}

vless_plain_share_skip() {
  VLESS_PLAIN_SHARE_SKIP_CODE=${1:-vless_plain_uri_unrepresentable}
  VLESS_PLAIN_SHARE_SKIP_MESSAGE=${2:-VLESS 当前配置无法无损转换为 raw URI。}
  return 2
}

vless_plain_share_warning_for_status() {
  case "${1:-1}" in
    31) jq -cn '[{code:"vless_plain_tls_certificate_uri_unrepresentable",message:"VLESS 自定义证书信任无法由 raw URI 无损表达；该用户已跳过。"}]' ;;
    32) jq -cn '[{code:"vless_plain_transport_uri_unrepresentable",message:"VLESS transport 包含 raw URI 无法无损表达的字段；该用户已跳过。"}]' ;;
    33) jq -cn '[{code:"vless_plain_uri_too_large",message:"VLESS raw URI 超过 SubMan 16384 字节上限；该用户已跳过。"}]' ;;
    *) return 1 ;;
  esac
}

vless_plain_share_transport_supported() {
  local transport_json=${1:-} transport_type
  transport_type=$(jq -er '.type' <<< "${transport_json}") || return 1
  case "${transport_type}" in
    none|quic) jq -e 'keys_unsorted == ["type"]' <<< "${transport_json}" >/dev/null ;;
    http)
      jq -e '((keys_unsorted - ["type","host","path","headers"] | length) == 0) and
        ((.method // "GET") == "GET") and
        (((.headers // {}) | keys_unsorted | map(ascii_downcase) | unique) == [] or
          ((.headers | keys_unsorted | map(ascii_downcase) | unique) == ["host"] and
           ((.headers.Host // .headers.host) | type == "string"))) and
        ((.host // []) | if type == "array" then length <= 1 else true end)' <<< "${transport_json}" >/dev/null ;;
    ws)
      jq -e '((keys_unsorted - ["type","path","headers"] | length) == 0) and
        ((.headers // {}) | keys_unsorted | map(ascii_downcase) | unique) as $keys |
        ($keys == [] or $keys == ["host"])' <<< "${transport_json}" >/dev/null ;;
    grpc) jq -e '(keys_unsorted - ["type","service_name"] | length) == 0' <<< "${transport_json}" >/dev/null ;;
    *) return 1 ;;
  esac
}

build_vless_plain_subman_uri_from_store() (
  local store_file=${1:-} server=${2:-} instance_id=${3:-} user_name=${4-} node_name=${5:-VLESS}
  local snapshot instance client_trust tag filtered_file outbound uri uri_bytes transport_json
  [[ $# -eq 5 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  structured_instance_store_validate_id "${instance_id}" || return 1
  validate_structured_instance_store vless-plain "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || return 1
  instance=$(jq -ce --arg id "${instance_id}" --arg user "${user_name}" '.instances[] | select(.id == $id) | select(any(.authentication.users[]; .name == $user))' <<< "${snapshot}") || return 1
  client_trust=$(jq -er '.client_trust' <<< "${instance}") || return 1
  if [[ "${client_trust}" != system ]]; then
    vless_plain_share_skip vless_plain_tls_certificate_uri_unrepresentable 'VLESS 自定义证书信任无法由 raw URI 无损表达；该用户已跳过。'
    return 31
  fi
  transport_json=$(jq -ce '.transport' <<< "${instance}") || return 1
  if ! vless_plain_share_transport_supported "${transport_json}"; then
    vless_plain_share_skip vless_plain_transport_uri_unrepresentable 'VLESS transport 包含 raw URI 无法无损表达的字段；该用户已跳过。'
    return 32
  fi
  tag=$(jq -r --arg user "${user_name}" '"vless-plain-" + .id + "-user-" + ($user | @base64)' <<< "${instance}") || return 1
  filtered_file=$(storage_mktemp) || return 1
  trap 'rm -f -- "${filtered_file}"' EXIT
  jq -e --arg id "${instance_id}" '.instances |= map(select(.id == $id)) | .default_instance_id=$id' <<< "${snapshot}" > "${filtered_file}" || return 1
  outbound=$(build_vless_plain_client_outbounds_from_store "${filtered_file}" "${server}" | select_subman_outbound_by_tag "${tag}") || return 1
  uri=$(build_vless_plain_uri_from_outbound "${outbound}" "${node_name}") || return 1
  uri_bytes=$(printf '%s' "${uri}" | wc -c) || return 1
  [[ "${uri_bytes}" =~ ^[0-9]+$ && "${uri_bytes}" -le 16384 ]] || {
    vless_plain_share_skip vless_plain_uri_too_large 'VLESS raw URI 超过 SubMan 16384 字节上限；该用户已跳过。'; return 33;
  }
  printf '%s' "${uri}"
)

subman_external_key_for_vless_plain_user() {
  local instance_id=${1:-} user_name=${2-} address_label=${3:-} prefix digest key stack_suffix
  structured_instance_store_validate_id "${instance_id}" || return 1
  prefix=$(subman_node_prefix) || return 1; digest=$(printf '%s' "${user_name}" | sha256sum); digest=${digest%% *}
  key="sing-box-vps:${prefix}:vless-plain:${instance_id}:user-${digest}"
  stack_suffix=$(network_stack_suffix_from_label "${address_label}") || return 1
  [[ -z "${stack_suffix}" ]] || key="${key}:${stack_suffix}"
  subman_external_key_is_valid "${key}" || return 1
  printf '%s' "${key}"
}


build_subman_vless_plain_node_payload() {
  local raw_link=${1:-} name=${2:-} node_type prefix
  [[ -n "${raw_link}" && -n "${name}" ]] || return 1
  node_type=$(subman_type_for_protocol vless-plain) || return 1; prefix=$(subman_node_prefix) || return 1
  jq -n --arg name "${name}" --arg type "${node_type}" --arg raw "${raw_link}" --arg prefix "${prefix}" '{name:$name,type:$type,raw:$raw,enabled:true,tags:["sing-box-vps",$prefix],source:"single"}'
}

push_subman_vless_plain_instance() {
  local node_name_digests
  local instance_id=${1:-} server=${2:-} quiet=${3:-n} address_label=${4:-}
  local store_file snapshot snapshot_file instance user_name node_name raw_link external_key payload_json status warning users_text
  local synced=0 skipped=0 failed=0 warnings='[]'
  SUBMAN_VLESS_PLAIN_SYNCED=0; SUBMAN_VLESS_PLAIN_SKIPPED=0; SUBMAN_VLESS_PLAIN_FAILED=0; SUBMAN_VLESS_PLAIN_WARNINGS_JSON='[]'
  structured_instance_store_validate_id "${instance_id}" || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  store_file=$(plain_proxy_structured_store_file vless-plain) || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  snapshot=$(structured_instance_store_snapshot_json vless-plain "${store_file}") || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  if ! listener_address_is_wildcard "$(jq -r '.listen.address' <<< "${instance}")"; then
    server=$(jq -r '.listen.address' <<< "${instance}") || return 1
  fi
  snapshot_file=$(storage_mktemp) || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }; printf '%s\n' "${snapshot}" > "${snapshot_file}" || { rm -f -- "${snapshot_file}"; SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  users_text=$(jq -r '.authentication.users[].name' <<< "${instance}") || { rm -f -- "${snapshot_file}"; SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  while IFS= read -r user_name; do
    [[ -n "${user_name}" ]] || continue
    node_name=$(structured_node_display_name vless-plain "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || { failed=$((failed + 1)); continue; }
    if raw_link=$(build_vless_plain_subman_uri_from_store "${snapshot_file}" "${server}" "${instance_id}" "${user_name}" "${node_name}"); then
      external_key=$(subman_external_key_for_vless_plain_user "${instance_id}" "${user_name}" "${address_label}") || { record_subman_key_failure vless-plain "${instance_id}" "${address_label}" "${quiet}"; failed=$((failed + 1)); continue; }
      payload_json=$(build_subman_vless_plain_node_payload "${raw_link}" "${node_name}") || { failed=$((failed + 1)); continue; }
      if [[ "${quiet}" == y ]]; then push_subman_node_with_result "${external_key}" "${payload_json}" >/dev/null && synced=$((synced + 1)) || failed=$((failed + 1)); else push_subman_node_with_result "${external_key}" "${payload_json}" && synced=$((synced + 1)) || failed=$((failed + 1)); fi
    else
      status=$?
      if [[ "${status}" == 31 || "${status}" == 32 || "${status}" == 33 ]]; then
        skipped=$((skipped + 1)); warning=$(vless_plain_share_warning_for_status "${status}") || { failed=$((failed + 1)); continue; }
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson addition "${warning}" --arg instance_id "${instance_id}" --arg user "${user_name}" '$existing + ($addition | map(. + {instance_id:$instance_id,outbound_tag:("vless-plain-" + $instance_id + "-user-" + ($user | @base64))}))') || { failed=$((failed + 1)); continue; }
        [[ "${quiet}" == y ]] || print_warn "VLESS 实例 ${instance_id} 用户 ${user_name} 无法无损转换为 SubMan raw URI，已跳过。"
      else failed=$((failed + 1)); fi
    fi
  done <<< "${users_text}"
  rm -f -- "${snapshot_file}" || failed=$((failed + 1))
  SUBMAN_VLESS_PLAIN_SYNCED=${synced}; SUBMAN_VLESS_PLAIN_SKIPPED=${skipped}; SUBMAN_VLESS_PLAIN_FAILED=${failed}; SUBMAN_VLESS_PLAIN_WARNINGS_JSON=${warnings}
  (( failed == 0 && (synced > 0 || skipped > 0) ))
}

push_subman_vless_plain_protocol() {
  local quiet=${1:-n} instance_ids instance_id address_entries address_entry address_label public_ip
  local total_synced=0 total_skipped=0 total_failed=0 warnings='[]'
  SUBMAN_VLESS_PLAIN_SYNCED=0; SUBMAN_VLESS_PLAIN_SKIPPED=0; SUBMAN_VLESS_PLAIN_FAILED=0; SUBMAN_VLESS_PLAIN_WARNINGS_JSON='[]'
  instance_ids=$(list_protocol_instance_ids vless-plain) || { SUBMAN_VLESS_PLAIN_FAILED=1; return 1; }
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    load_protocol_instance_state vless-plain "${instance_id}" || { total_failed=$((total_failed + 1)); continue; }
    if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
      record_subman_address_failure vless-plain "${instance_id}" "${quiet}" || return 1
      total_failed=$((total_failed + 1))
      continue
    fi
    while IFS= read -r address_entry; do
      [[ -n "${address_entry}" ]] || continue; address_label=${address_entry%%|*}; public_ip=${address_entry#*|}
      push_subman_vless_plain_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}" || :
      total_synced=$((total_synced + ${SUBMAN_VLESS_PLAIN_SYNCED:-0})); total_skipped=$((total_skipped + ${SUBMAN_VLESS_PLAIN_SKIPPED:-0})); total_failed=$((total_failed + ${SUBMAN_VLESS_PLAIN_FAILED:-0}))
      if [[ -n "${SUBMAN_VLESS_PLAIN_WARNINGS_JSON:-}" ]]; then warnings=$(jq -cn --argjson a "${warnings}" --argjson b "${SUBMAN_VLESS_PLAIN_WARNINGS_JSON}" '$a+$b') || return 1; fi
    done <<< "${address_entries}"
  done <<< "${instance_ids}"
  SUBMAN_VLESS_PLAIN_SYNCED=${total_synced}; SUBMAN_VLESS_PLAIN_SKIPPED=${total_skipped}; SUBMAN_VLESS_PLAIN_FAILED=${total_failed}; SUBMAN_VLESS_PLAIN_WARNINGS_JSON=${warnings}
  (( total_failed == 0 && (total_synced > 0 || total_skipped > 0) ))
}

push_subman_shadowsocks_instance() {
  local node_name_digests
  local instance_id=${1:-} server=${2:-} quiet=${3:-n} address_label=${4:-}
  local store_file outbound user_name external_key node_name payload_json network_json method
  local snapshot outbounds_text user_names_text instance_address
  local outbounds=() user_names=() index

  SUBMAN_SHADOWSOCKS_SYNCED=0
  SUBMAN_SHADOWSOCKS_SKIPPED=0
  SUBMAN_SHADOWSOCKS_FAILED=0
  structured_instance_store_validate_id "${instance_id}" || {
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  }
  store_file=$(plain_proxy_structured_store_file shadowsocks) || {
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  }
  snapshot=$(structured_instance_store_snapshot_json shadowsocks "${store_file}") || {
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  }
  jq -e --arg id "${instance_id}" 'any(.instances[]; .id == $id)' <<< "${snapshot}" >/dev/null 2>&1 || {
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  }
  if ! node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}"); then
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  fi
  if ! instance_address=$(jq -er --arg id "${instance_id}" \
      '.instances[] | select(.id == $id) | .listen.address' <<< "${snapshot}"); then
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  fi
  if ! listener_address_is_wildcard "${instance_address}"; then
    server=${instance_address}
  fi
  if ! outbounds_text=$(
    temporary=$(storage_mktemp) || exit 1
    cleanup_snapshot_file() {
      local cleanup_status=$?
      rm -f -- "${temporary}"
      return "${cleanup_status}"
    }
    trap cleanup_snapshot_file EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    if ! jq -c --arg id "${instance_id}" \
        '.instances |= map(select(.id == $id)) | .default_instance_id = $id' \
        <<< "${snapshot}" > "${temporary}"; then
      exit 1
    fi
    build_shadowsocks_client_outbounds_from_store "${temporary}" "${server}"
  ); then
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  fi
  mapfile -t outbounds <<< "${outbounds_text}"
  if ! user_names_text=$(jq -r --arg id "${instance_id}" '
    .instances[] | select(.id == $id) |
    if (.authentication.users | length) == 0 then ""
    else .authentication.users[].name end
  ' <<< "${snapshot}"); then
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  fi
  mapfile -t user_names <<< "${user_names_text}"
  [[ ${#outbounds[@]} -gt 0 && ${#outbounds[@]} -eq ${#user_names[@]} ]] || {
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  }

  for index in "${!outbounds[@]}"; do
    outbound=${outbounds[${index}]}
    user_name=${user_names[${index}]}
    network_json=$(jq -c '.network // []' <<< "${outbound}") || {
      SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
      continue
    }
    method=$(jq -r '.method // empty' <<< "${outbound}") || {
      SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
      continue
    }
    if [[ "${method}" == none ]]; then
      if ! SUBMAN_SHADOWSOCKS_WARNINGS_JSON=$(jq -cn \
          --argjson existing "${SUBMAN_SHADOWSOCKS_WARNINGS_JSON:-[]}" \
          '$existing + [{code:"shadowsocks_subman_none_unsupported",message:"Shadowsocks none 无法转换为 SubMan SIP002；该实例已跳过。"}]'); then
        SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
        continue
      fi
      SUBMAN_SHADOWSOCKS_SKIPPED=$((SUBMAN_SHADOWSOCKS_SKIPPED + 1))
      [[ "${quiet}" == y ]] || print_warn "Shadowsocks 实例 ${instance_id} 使用 none；SubMan SIP002 parser 无法接受空密码，已跳过。"
      continue
    fi
    if [[ "${network_json}" != '["tcp","udp"]' ]]; then
      SUBMAN_SHADOWSOCKS_SKIPPED=$((SUBMAN_SHADOWSOCKS_SKIPPED + 1))
      [[ "${quiet}" == y ]] || print_warn "Shadowsocks 实例 ${instance_id} 用户项网络限制为 ${network_json}，SIP002 无法保真，已跳过。"
      continue
    fi
    if ! external_key=$(subman_external_key_for_shadowsocks_user "${instance_id}" "${user_name}" "${address_label}"); then
      record_subman_key_failure shadowsocks "${instance_id}" "${address_label}" "${quiet}"
      SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
      continue
    fi
    node_name=$(structured_node_display_name shadowsocks "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || {
      SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
      continue
    }
    payload_json=$(build_subman_shadowsocks_node_payload "${outbound}" "${node_name}") || {
      SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
      continue
    }
    if [[ "${quiet}" == y ]]; then
      if push_subman_node_with_result "${external_key}" "${payload_json}" >/dev/null; then
        SUBMAN_SHADOWSOCKS_SYNCED=$((SUBMAN_SHADOWSOCKS_SYNCED + 1))
      else
        SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
      fi
    elif push_subman_node_with_result "${external_key}" "${payload_json}"; then
      SUBMAN_SHADOWSOCKS_SYNCED=$((SUBMAN_SHADOWSOCKS_SYNCED + 1))
    else
      SUBMAN_SHADOWSOCKS_FAILED=$((SUBMAN_SHADOWSOCKS_FAILED + 1))
    fi
  done

  (( SUBMAN_SHADOWSOCKS_FAILED == 0 ))
}

push_subman_shadowsocks_protocol() {
  local quiet=${1:-n} instance_ids instance_id address_entries=() address_entry address_label public_ip address_text
  local warnings instance_synced instance_skipped instance_failed
  local total_synced=0 total_skipped=0 total_failed=0

  SUBMAN_SHADOWSOCKS_WARNINGS_JSON='[]'
  instance_ids=$(list_protocol_instance_ids shadowsocks) || {
    SUBMAN_SHADOWSOCKS_SYNCED=0
    SUBMAN_SHADOWSOCKS_SKIPPED=0
    SUBMAN_SHADOWSOCKS_FAILED=1
    return 1
  }
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    if ! load_protocol_instance_state shadowsocks "${instance_id}"; then
      total_failed=$((total_failed + 1))
      continue
    fi
    if warnings=$(shadowsocks_share_warnings_json); then
      SUBMAN_SHADOWSOCKS_WARNINGS_JSON=$(jq -cn \
        --argjson existing "${SUBMAN_SHADOWSOCKS_WARNINGS_JSON}" \
        --argjson additions "${warnings}" '$existing + $additions') || return 1
    fi
    if ! address_text=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_text}" ]]; then
      record_subman_address_failure shadowsocks "${instance_id}" "${quiet}" || return 1
      total_failed=$((total_failed + 1))
      continue
    fi
    address_entries=()
    while IFS= read -r address_entry; do
      if [[ -n "${address_entry}" ]]; then
        address_entries+=("${address_entry}")
      fi
    done <<< "${address_text}"
    if [[ ${#address_entries[@]} -eq 0 ]]; then
      total_failed=$((total_failed + 1))
      continue
    fi
    for address_entry in "${address_entries[@]}"; do
      [[ -n "${address_entry}" ]] || continue
      address_label=${address_entry%%|*}
      public_ip=${address_entry#*|}
      push_subman_shadowsocks_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}" || :
      instance_synced=${SUBMAN_SHADOWSOCKS_SYNCED}
      instance_skipped=${SUBMAN_SHADOWSOCKS_SKIPPED}
      instance_failed=${SUBMAN_SHADOWSOCKS_FAILED}
      total_synced=$((total_synced + instance_synced))
      total_skipped=$((total_skipped + instance_skipped))
      total_failed=$((total_failed + instance_failed))
    done
  done <<< "${instance_ids}"
  SUBMAN_SHADOWSOCKS_SYNCED=${total_synced}
  SUBMAN_SHADOWSOCKS_SKIPPED=${total_skipped}
  SUBMAN_SHADOWSOCKS_FAILED=${total_failed}
  (( total_failed == 0 ))
}

hy2_share_skip() {
  HY2_SHARE_SKIP_CODE=${1:-hy2_uri_unrepresentable}
  HY2_SHARE_SKIP_MESSAGE=${2:-Hysteria2 当前配置无法无损转换为 SubMan raw URI。}
  return 2
}

build_hy2_subman_uri_from_store() (
  local store_file=${1:-} server=${2:-} instance_id=${3:-} user_name=${4-} node_name=${5:-Hysteria2}
  local snapshot instance client_trust tag filtered_file outbound uri uri_bytes

  [[ $# -eq 5 && -n "${store_file}" && -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  [[ -n "${server}" && "${server}" != *[[:space:]@/?#%]* ]] || return 1
  structured_instance_store_validate_id "${instance_id}" || return 1
  validate_structured_instance_store hy2 "${store_file}" || return 1
  snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || return 1
  instance=$(jq -ce --arg id "${instance_id}" --arg user "${user_name}" \
    '.instances[] | select(.id == $id) | select(any(.authentication.users[]; .name == $user))' <<< "${snapshot}") || return 1
  client_trust=$(jq -er '.client_trust' <<< "${instance}") || return 1
  if [[ "${client_trust}" != system ]]; then
    hy2_share_skip hy2_tls_certificate_uri_unrepresentable 'Hysteria2 自定义证书信任无法由 SubMan raw URI 无损表达；该用户已跳过。'
    return 41
  fi
  tag=$(jq -r --arg user "${user_name}" '"hy2-" + .id + "-user-" + ($user | @base64)' <<< "${instance}") || return 1
  filtered_file=$(storage_mktemp) || return 1
  trap 'rm -f -- "${filtered_file}"' EXIT
  jq -e --arg id "${instance_id}" \
    '.instances |= map(select(.id == $id)) | .default_instance_id=$id' \
    <<< "${snapshot}" > "${filtered_file}" || return 1
  outbound=$(build_client_hy2_outbounds "${server}" "${filtered_file}" | select_subman_outbound_by_tag "${tag}") || return 1
  uri=$(build_hy2_uri_from_outbound "${outbound}" "${node_name}") || return 1
  uri_bytes=$(printf '%s' "${uri}" | wc -c) || return 1
  [[ "${uri_bytes}" =~ ^[0-9]+$ && "${uri_bytes}" -le 16384 ]] || {
    hy2_share_skip hy2_uri_too_large 'Hysteria2 raw URI 超过 SubMan 16384 字节上限；该用户已跳过。'
    return 42
  }
  printf '%s' "${uri}"
)

hy2_share_warning_for_status() {
  case "${1:-1}" in
    41) jq -cn '[{code:"hy2_tls_certificate_uri_unrepresentable",message:"Hysteria2 自定义证书信任无法由 SubMan raw URI 无损表达；该用户已跳过。"}]' ;;
    42) jq -cn '[{code:"hy2_uri_too_large",message:"Hysteria2 raw URI 超过 SubMan 16384 字节上限；该用户已跳过。"}]' ;;
    *) return 1 ;;
  esac
}

hy2_subman_partial_options_warning() {
  jq -cn '[{code:"hy2_uri_partial_options",message:"Hysteria2 带宽限制或 masquerade 无法由标准 URI 完整表达；请使用完整客户端 outbound JSON。"}]'
}

build_hy2_subman_links_and_warnings_json() (
  local node_name_digests
  local server=${1:-} instance_id=${2:-} store_file snapshot snapshot_file instance node_name user_name tag uri status warning certificate_path ed25519_warning
  local links='{}' warnings='[]' users_text address_label

  [[ $# -ge 1 && $# -le 2 ]] || return 1
  store_file=$(plain_proxy_structured_store_file hy2) || return 1
  snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || return 1
  snapshot_file=$(storage_mktemp) || return 1
  trap 'rm -f -- "${snapshot_file}"' EXIT
  printf '%s\n' "${snapshot}" > "${snapshot_file}" || return 1
  instance_id=${2:-$(jq -er '.default_instance_id' <<< "${snapshot}")}
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || return 1
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
  address_label=$(node_display_address_label "$(jq -r '.listen.address' <<< "${instance}")" "${server}") || return 1
  certificate_path=$(jq -r '.tls.certificate_path // ""' <<< "${instance}") || return 1
  ed25519_warning=$(hy2_ed25519_share_warning_json "${certificate_path}") || return 1
  users_text=$(jq -r '.authentication.users[].name' <<< "${instance}") || return 1
  while IFS= read -r user_name; do
    [[ -n "${user_name}" ]] || continue
    tag=$(jq -r --arg user "${user_name}" '"hy2-" + .id + "-user-" + ($user | @base64)' <<< "${instance}") || return 1
    node_name=$(structured_node_display_name hy2 "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    if uri=$(build_hy2_subman_uri_from_store "${snapshot_file}" "${server}" "${instance_id}" "${user_name}" "${node_name}"); then
      links=$(jq -cn --argjson links "${links}" --arg tag "${tag}" --arg uri "${uri}" '$links + {($tag):$uri}') || return 1
      if jq -e '.bandwidth.up_mbps != null or .bandwidth.down_mbps != null or .masquerade != ""' <<< "${instance}" >/dev/null; then
        warning=$(hy2_subman_partial_options_warning) || return 1
        warnings=$(jq -cn --argjson warnings "${warnings}" --argjson warning "${warning}" \
          --arg instance_id "${instance_id}" --arg tag "${tag}" \
          '$warnings + ($warning | map(. + {instance_id:$instance_id,outbound_tag:$tag}))') || return 1
      fi
      if jq -e 'length > 0' <<< "${ed25519_warning}" >/dev/null; then
        warnings=$(jq -cn --argjson warnings "${warnings}" --argjson warning "${ed25519_warning}" \
          --arg instance_id "${instance_id}" --arg tag "${tag}" \
          '$warnings + ($warning | map(. + {instance_id:$instance_id,outbound_tag:$tag}))') || return 1
      fi
    else
      status=$?
      if [[ "${status}" == 41 || "${status}" == 42 ]]; then
        warning=$(hy2_share_warning_for_status "${status}") || return 1
        warnings=$(jq -cn --argjson warnings "${warnings}" --argjson warning "${warning}" \
          --arg instance_id "${instance_id}" --arg tag "${tag}" \
          '$warnings + ($warning | map(. + {instance_id:$instance_id,outbound_tag:$tag}))') || return 1
      else
        return "${status}"
      fi
    fi
  done <<< "${users_text}"
  jq -cn --argjson links "${links}" --argjson warnings "${warnings}" '{links:$links,warnings:$warnings}'
)

subman_external_key_for_hy2_user() {
  local instance_id=${1:-} user_name=${2-} address_label=${3:-} prefix digest key stack_suffix
  structured_instance_store_validate_id "${instance_id}" || return 1
  prefix=$(subman_node_prefix) || return 1
  digest=$(printf '%s' "${user_name}" | sha256sum) || return 1
  digest=${digest%% *}
  key="sing-box-vps:${prefix}:hy2:${instance_id}:user-${digest}"
  stack_suffix=$(network_stack_suffix_from_label "${address_label}") || return 1
  [[ -z "${stack_suffix}" ]] || key="${key}:${stack_suffix}"
  subman_external_key_is_valid "${key}" || return 1
  printf '%s' "${key}"
}


build_subman_hy2_node_payload() {
  local raw_link=${1:-} name=${2:-} node_type prefix
  [[ -n "${raw_link}" && -n "${name}" ]] || return 1
  node_type=$(subman_type_for_protocol hy2) || return 1
  prefix=$(subman_node_prefix) || return 1
  jq -n --arg name "${name}" --arg type "${node_type}" --arg raw "${raw_link}" --arg prefix "${prefix}" \
    '{name:$name,type:$type,raw:$raw,enabled:true,tags:["sing-box-vps",$prefix],source:"single"}'
}

push_subman_hy2_instance() {
  local node_name_digests
  local instance_id=${1:-} server=${2:-} quiet=${3:-n} address_label=${4:-}
  local store_file snapshot snapshot_file instance user_name node_name raw_link external_key payload_json status warning certificate_path ed25519_warning
  local users_text synced=0 skipped=0 failed=0 warnings='[]'

  SUBMAN_HY2_SYNCED=0
  SUBMAN_HY2_SKIPPED=0
  SUBMAN_HY2_FAILED=0
  SUBMAN_HY2_WARNINGS_JSON='[]'
  structured_instance_store_validate_id "${instance_id}" || { SUBMAN_HY2_FAILED=1; return 1; }
  store_file=$(plain_proxy_structured_store_file hy2) || { SUBMAN_HY2_FAILED=1; return 1; }
  snapshot=$(structured_instance_store_snapshot_json hy2 "${store_file}") || { SUBMAN_HY2_FAILED=1; return 1; }
  instance=$(jq -ce --arg id "${instance_id}" '.instances[] | select(.id == $id)' <<< "${snapshot}") || { SUBMAN_HY2_FAILED=1; return 1; }
  node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || { SUBMAN_HY2_FAILED=1; return 1; }
  if ! listener_address_is_wildcard "$(jq -r '.listen.address' <<< "${instance}")"; then
    server=$(jq -r '.listen.address' <<< "${instance}") || return 1
  fi
  certificate_path=$(jq -r '.tls.certificate_path // ""' <<< "${instance}") || { SUBMAN_HY2_FAILED=1; return 1; }
  ed25519_warning=$(hy2_ed25519_share_warning_json "${certificate_path}") || { SUBMAN_HY2_FAILED=1; return 1; }
  snapshot_file=$(storage_mktemp) || { SUBMAN_HY2_FAILED=1; return 1; }
  printf '%s\n' "${snapshot}" > "${snapshot_file}" || { rm -f -- "${snapshot_file}"; SUBMAN_HY2_FAILED=1; return 1; }
  users_text=$(jq -r '.authentication.users[].name' <<< "${instance}") || { rm -f -- "${snapshot_file}"; SUBMAN_HY2_FAILED=1; return 1; }
  while IFS= read -r user_name; do
    [[ -n "${user_name}" ]] || continue
    node_name=$(structured_node_display_name hy2 "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || { failed=$((failed + 1)); continue; }
    if raw_link=$(build_hy2_subman_uri_from_store "${snapshot_file}" "${server}" "${instance_id}" "${user_name}" "${node_name}"); then
      external_key=$(subman_external_key_for_hy2_user "${instance_id}" "${user_name}" "${address_label}") || { record_subman_key_failure hy2 "${instance_id}" "${address_label}" "${quiet}"; failed=$((failed + 1)); continue; }
      payload_json=$(build_subman_hy2_node_payload "${raw_link}" "${node_name}") || { failed=$((failed + 1)); continue; }
      if [[ "${quiet}" == y ]]; then
        if push_subman_node_with_result "${external_key}" "${payload_json}" >/dev/null; then synced=$((synced + 1)); else failed=$((failed + 1)); fi
      elif push_subman_node_with_result "${external_key}" "${payload_json}"; then
        synced=$((synced + 1))
      else
        failed=$((failed + 1))
      fi
      if jq -e '.bandwidth.up_mbps != null or .bandwidth.down_mbps != null or .masquerade != ""' <<< "${instance}" >/dev/null; then
        warning=$(hy2_subman_partial_options_warning) || { failed=$((failed + 1)); continue; }
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson addition "${warning}" \
          --arg instance_id "${instance_id}" --arg user "${user_name}" \
          '$existing + ($addition | map(. + {instance_id:$instance_id,outbound_tag:("hy2-" + $instance_id + "-user-" + ($user | @base64))}))') || { failed=$((failed + 1)); continue; }
      fi
      if jq -e 'length > 0' <<< "${ed25519_warning}" >/dev/null; then
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson addition "${ed25519_warning}" \
          --arg instance_id "${instance_id}" --arg user "${user_name}" \
          '$existing + ($addition | map(. + {instance_id:$instance_id,outbound_tag:("hy2-" + $instance_id + "-user-" + ($user | @base64))}))') || { failed=$((failed + 1)); continue; }
      fi
    else
      status=$?
      if [[ "${status}" == 41 || "${status}" == 42 ]]; then
        skipped=$((skipped + 1))
        warning=$(hy2_share_warning_for_status "${status}") || { failed=$((failed + 1)); continue; }
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson addition "${warning}" \
          --arg instance_id "${instance_id}" --arg user "${user_name}" \
          '$existing + ($addition | map(. + {instance_id:$instance_id,outbound_tag:("hy2-" + $instance_id + "-user-" + ($user | @base64))}))') || { failed=$((failed + 1)); continue; }
        [[ "${quiet}" == y ]] || print_warn "Hysteria2 实例 ${instance_id} 用户 ${user_name} 无法无损转换为 SubMan raw URI，已跳过。"
      else
        failed=$((failed + 1))
      fi
    fi
  done <<< "${users_text}"
  rm -f -- "${snapshot_file}" || failed=$((failed + 1))
  SUBMAN_HY2_SYNCED=${synced}
  SUBMAN_HY2_SKIPPED=${skipped}
  SUBMAN_HY2_FAILED=${failed}
  SUBMAN_HY2_WARNINGS_JSON=${warnings}
  (( failed == 0 && (synced > 0 || skipped > 0) ))
}

push_subman_hy2_protocol() {
  local quiet=${1:-n} instance_ids instance_id address_entries address_entry address_label public_ip
  local total_synced=0 total_skipped=0 total_failed=0 warnings='[]'
  SUBMAN_HY2_SYNCED=0
  SUBMAN_HY2_SKIPPED=0
  SUBMAN_HY2_FAILED=0
  SUBMAN_HY2_WARNINGS_JSON='[]'
  instance_ids=$(list_protocol_instance_ids hy2) || { SUBMAN_HY2_FAILED=1; return 1; }
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    load_protocol_instance_state hy2 "${instance_id}" || { total_failed=$((total_failed + 1)); continue; }
    if ! address_entries=$(list_subman_addresses_for_current_protocol) || [[ -z "${address_entries}" ]]; then
      record_subman_address_failure hy2 "${instance_id}" "${quiet}" || return 1
      total_failed=$((total_failed + 1))
      continue
    fi
    while IFS= read -r address_entry; do
      [[ -n "${address_entry}" ]] || continue
      address_label=${address_entry%%|*}
      public_ip=${address_entry#*|}
      push_subman_hy2_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}" || :
      total_synced=$((total_synced + ${SUBMAN_HY2_SYNCED:-0}))
      total_skipped=$((total_skipped + ${SUBMAN_HY2_SKIPPED:-0}))
      total_failed=$((total_failed + ${SUBMAN_HY2_FAILED:-0}))
      if [[ -n "${SUBMAN_HY2_WARNINGS_JSON:-}" ]]; then
        warnings=$(jq -cn --argjson existing "${warnings}" --argjson additions "${SUBMAN_HY2_WARNINGS_JSON}" '$existing + $additions') || return 1
      fi
    done <<< "${address_entries}"
  done <<< "${instance_ids}"
  SUBMAN_HY2_SYNCED=${total_synced}
  SUBMAN_HY2_SKIPPED=${total_skipped}
  SUBMAN_HY2_FAILED=${total_failed}
  SUBMAN_HY2_WARNINGS_JSON=${warnings}
  (( total_failed == 0 && (total_synced > 0 || total_skipped > 0) ))
}

build_subman_raw_for_protocol() (
  local node_name_digests
  local protocol public_ip address_label instance_id store_file snapshot user_name node_name
  local instance listen_address snapshot_file
  protocol=$(normalize_protocol_id "$1") || return 1
  public_ip=$2
  address_label=${3:-}
  instance_id=${4:-}
  snapshot=${5:-}
  node_name_digests=${6:-}

  if [[ "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain ]] ||
     { [[ "${protocol}" == hy2 ]] && { [[ -n "${snapshot}" ]] ||
       { [[ "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; }; }; }; then
    if [[ -z "${snapshot}" ]]; then
      store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
      snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${store_file}") || return 1
    fi
    instance_id=${instance_id:-${SB_INSTANCE_ID:-}}
    [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
    instance=$(jq -ce --arg id "${instance_id}" '[.instances[] | select(.id == $id)] | select(length == 1) | .[0]' <<< "${snapshot}") || return 1
    listen_address=$(jq -er '.listen.address' <<< "${instance}") || return 1
    if ! listener_address_is_wildcard "${listen_address}"; then
      public_ip=${listen_address}
      address_label='监听地址'
    elif [[ -z "${address_label}" ]]; then
      address_label=$(node_display_address_label "${listen_address}" "${public_ip}") || return 1
    fi
    user_name=$(jq -er '.authentication.users[0].name' <<< "${instance}") || return 1
    if [[ -z "${node_name_digests}" ]]; then
      node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
    fi
    node_name=$(structured_node_display_name "${protocol}" "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    snapshot_file=$(storage_mktemp) || return 1
    trap 'rm -f -- "${snapshot_file}"' EXIT
    printf '%s\n' "${snapshot}" > "${snapshot_file}" || return 1
    case "${protocol}" in
      trojan) build_trojan_subman_uri_from_store "${snapshot_file}" "${public_ip}" "${instance_id}" "${user_name}" "${node_name}" ;;
      vmess) build_vmess_subman_uri_from_store "${snapshot_file}" "${public_ip}" "${instance_id}" "${user_name}" "${node_name}" ;;
      vless-plain) build_vless_plain_subman_uri_from_store "${snapshot_file}" "${public_ip}" "${instance_id}" "${user_name}" "${node_name}" ;;
      hy2) build_hy2_subman_uri_from_store "${snapshot_file}" "${public_ip}" "${instance_id}" "${user_name}" "${node_name}" ;;
    esac
    return $?
  fi

  case "${protocol}" in
    vless-reality)
      if [[ -n "${instance_id}" ]]; then
        build_vless_link_for_instance "${instance_id}" "${public_ip}" "${address_label}"
      else
        build_vless_link "${public_ip}" "${address_label}"
      fi
      ;;
    hy2) build_hy2_link "${public_ip}" "${address_label}" "${public_ip}" ;;
    *) return 1 ;;
  esac
)

build_subman_node_payload() {
  local node_name_digests
  local protocol public_ip address_label instance_id node_type raw_link node_name prefix
  local store_file snapshot instance user_name listen_address
  protocol=$(normalize_protocol_id "$1") || return 1
  public_ip=$2
  address_label=${3:-}
  instance_id=${4:-}
  node_type=$(subman_type_for_protocol "${protocol}") || return 1
  if [[ "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == vless-plain ]] ||
     { [[ "${protocol}" == hy2 && "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; }; then
    store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
    snapshot=$(structured_instance_store_snapshot_json "${protocol}" "${store_file}") || return 1
    instance_id=${instance_id:-${SB_INSTANCE_ID:-}}
    [[ -n "${instance_id}" ]] || instance_id=$(jq -er '.default_instance_id' <<< "${snapshot}") || return 1
    instance=$(jq -ce --arg id "${instance_id}" '[.instances[] | select(.id == $id)] | select(length == 1) | .[0]' <<< "${snapshot}") || return 1
    listen_address=$(jq -er '.listen.address' <<< "${instance}") || return 1
    if ! listener_address_is_wildcard "${listen_address}"; then
      public_ip=${listen_address}
      address_label='监听地址'
    elif [[ -z "${address_label}" ]]; then
      address_label=$(node_display_address_label "${listen_address}" "${public_ip}") || return 1
    fi
    user_name=$(jq -er '.authentication.users[0].name' <<< "${instance}") || return 1
    node_name_digests=$(structured_node_user_digests "${snapshot}" "${instance_id}") || return 1
    node_name=$(structured_node_display_name "${protocol}" "${snapshot}" "${instance_id}" "${user_name}" "${address_label}" "${node_name_digests}") || return 1
    raw_link=$(build_subman_raw_for_protocol "${protocol}" "${public_ip}" "${address_label}" "${instance_id}" "${snapshot}" "${node_name_digests}") || return 1
  else
    if [[ "${protocol}" == vless-reality && -n "${instance_id}" ]]; then
      load_vless_reality_protocol_state
      load_vless_reality_instance_state "${instance_id}" || return 1
    fi
    raw_link=$(build_subman_raw_for_protocol "${protocol}" "${public_ip}" "${address_label}" "${instance_id}") || return 1
    if [[ "${protocol}" == vless-reality && -n "${instance_id}" ]]; then
      load_vless_reality_protocol_state
      load_vless_reality_instance_state "${instance_id}" || return 1
    fi
    node_name=$(display_node_name_for_protocol "${protocol}" "${SB_NODE_NAME:-}" "${address_label}") || return 1
  fi
  prefix=$(subman_node_prefix) || return 1
  [[ -z "${node_name}" ]] && node_name="${prefix} ${protocol}"

  jq -n \
    --arg name "${node_name}" \
    --arg type "${node_type}" \
    --arg raw "${raw_link}" \
    --arg prefix "${prefix}" \
    '{
      "name": $name,
      "type": $type,
      "raw": $raw,
      "enabled": true,
      "tags": ["sing-box-vps", $prefix],
      "source": "single"
    }'
}

push_subman_protocol_instance() {
  local protocol=$1
  local public_ip=$2
  local instance_id=${3:-}
  local quiet=${4:-n}
  local address_label=${5:-}
  local external_key payload_json

  if [[ "${protocol}" == "shadowsocks" ]]; then
    push_subman_shadowsocks_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}"
    return $?
  fi
  if [[ "${protocol}" == "trojan" ]]; then
    push_subman_trojan_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}"
    return $?
  fi
  if [[ "${protocol}" == "vmess" ]]; then
    push_subman_vmess_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}"
    return $?
  fi
  if [[ "${protocol}" == "vless-plain" ]]; then
    push_subman_vless_plain_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}"
    return $?
  fi
  if [[ "${protocol}" == "hy2" ]] && [[ "${CONFIG_SCHEMA_VERSION:-1}" == 2 ]] && plain_proxy_structured_state_active hy2; then
    push_subman_hy2_instance "${instance_id}" "${public_ip}" "${quiet}" "${address_label}"
    return $?
  fi
  if ! external_key=$(subman_external_key_for_protocol "${protocol}" "${instance_id}" "${address_label}"); then
    record_subman_key_failure "${protocol}" "${instance_id}" "${address_label}" "${quiet}"
    return 1
  fi

  if ! payload_json=$(build_subman_node_payload "${protocol}" "${public_ip}" "${address_label}" "${instance_id}"); then
    [[ "${quiet}" == "y" ]] || print_warn "生成 SubMan 节点载荷失败: ${protocol}"
    return 1
  fi

  if [[ "${quiet}" == "y" ]]; then
    push_subman_node_with_result "${external_key}" "${payload_json}" >/dev/null
  else
    push_subman_node_with_result "${external_key}" "${payload_json}"
  fi
}

reset_subman_api_result() {
  SUBMAN_LAST_HTTP_STATUS=""
  SUBMAN_LAST_ERROR_CODE=""
  SUBMAN_LAST_ERROR_DISPOSITION=""
  SUBMAN_LAST_RETRY_AFTER=""
  SUBMAN_LAST_REVISION=""
  SUBMAN_LAST_NODE_ID=""
  SUBMAN_LAST_GIST_ID=""
  SUBMAN_LAST_OUTCOME="failed"
  SUBMAN_LAST_RESPONSE_BODY=""
  SUBMAN_LAST_RESPONSE_ETAG=""
  SUBMAN_LAST_RESPONSE_REVISION=""
  SUBMAN_LAST_RESPONSE_CACHE_CONTROL=""
}

subman_set_client_error() {
  SUBMAN_LAST_ERROR_CODE=$1
  SUBMAN_LAST_ERROR_DISPOSITION=$2
}

validate_subman_node_request() {
  local external_key=$1
  local payload_json=$2
  local external_key_bytes

  external_key_bytes=$(printf '%s' "${external_key}" | wc -c | tr -d '[:space:]')
  if [[ -z "${external_key}" || "${external_key_bytes}" -gt 119 ]]; then
    subman_set_client_error "invalid_external_key" "invalid-request"
    return 1
  fi

  if ! jq -e '
    def trim_label: gsub("^[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+$"; "");
    def tag_label: if type == "string" then . else .label end | trim_label;
    type == "object"
    and (.name | type == "string" and utf8bytelength > 0 and utf8bytelength <= 256)
    and (.type | type == "string" and IN("vless", "vmess", "trojan", "ss", "ssr", "hysteria2", "tuic", "anytls", "other"))
    and (.raw | type == "string" and utf8bytelength > 0 and utf8bytelength <= 16384)
    and (if has("enabled") then (.enabled | type == "boolean") else true end)
    and ((.source // "single") | IN("single", "subscription"))
    and ((.tags // []) | type == "array")
    and all((.tags // [])[];
      if type == "string" then
        trim_label | utf8bytelength > 0 and utf8bytelength <= 128 and (ascii_downcase | startswith("external:") | not)
      elif type == "object" then
        (.label | type == "string" and (trim_label | utf8bytelength > 0 and utf8bytelength <= 128 and (ascii_downcase | startswith("external:") | not)))
        and (if (.id | type) == "string" then (.id | trim_label | ascii_downcase | startswith("external:") | not) else true end)
      else
        false
      end
    )
    and ((.tags // []) | map(tag_label) | unique | length <= 63)
  ' >/dev/null 2>&1 <<< "${payload_json}"; then
    subman_set_client_error "invalid_node_payload" "invalid-request"
    return 1
  fi
}

subman_response_header() {
  local headers_file=$1
  local header_name=$2
  awk -v header="${header_name}" '
    /^HTTP\// { value="" }
    tolower($0) ~ ("^" header ":") {
      sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*$/, "")
      if (header == "cache-control" && value != "") value=value "," $0
      else value=$0
    }
    END { print value }
  ' "${headers_file}"
}

subman_curl_with_progress() {
  local error_file=$1
  shift
  run_with_progress "SubMan API 请求" subman_curl_private "${error_file}" "$@"
}

subman_curl_private() {
  local error_file=$1
  shift
  curl "$@" 2> "${error_file}"
}

subman_api_request_cleanup() {
  [[ -n "${request_dir}" ]] || return 0
  if ! rm -rf -- "${request_dir}"; then
    printf '[ERROR] SubMan 请求临时文件清理失败；请保留私有目录权限并人工处理。\n' >&2
    return 1
  fi
  request_dir=''
}

subman_api_request_restore_traps() {
  trap - INT TERM HUP
  [[ -z "${request_traps}" ]] || eval "${request_traps}"
}

subman_api_request_signal() {
  local signal=$1 code=$2
  request_interrupted=${code}
  subman_api_request_cleanup || request_cleanup_failed=y
  subman_api_request_restore_traps
  printf '[WARN] SubMan 请求已中断；变更请求的远端结果可能不确定，请先读回确认。\n' >&2
  kill -s "${signal}" "${BASHPID:-$$}"
}

subman_api_request() {
  local request_dir='' request_traps request_interrupted=0 request_cleanup_failed=n request_status=0
  request_traps=$(trap -p INT TERM HUP)
  trap 'subman_api_request_signal INT 130' INT
  trap 'subman_api_request_signal TERM 143' TERM
  trap 'subman_api_request_signal HUP 129' HUP
  if subman_api_request_body "$@"; then :; else request_status=$?; fi
  if ! subman_api_request_cleanup || [[ "${request_cleanup_failed}" == y ]]; then
    subman_set_client_error temporary_cleanup_failed operator-repair
    [[ "$1" == GET ]] || SUBMAN_LAST_OUTCOME=unknown-outcome
    request_status=1
  fi
  subman_api_request_restore_traps
  if [[ "${request_interrupted}" != 0 ]]; then
    if [[ "$1" == GET ]]; then
      subman_set_client_error signal_interrupted retryable-upstream
    else
      subman_set_client_error signal_interrupted unknown-outcome
      SUBMAN_LAST_OUTCOME=unknown-outcome
    fi
    return "${request_interrupted}"
  fi
  return "${request_status}"
}

subman_api_request_body() {
  local method=$1
  local path=$2
  local payload_json=${3:-}
  local if_match=${4:-}
  local api_url endpoint tmp_dir config_file payload_file headers_file body_file stderr_file
  local escaped_token escaped_if_match http_status curl_status

  reset_subman_api_result
  api_url=$(normalize_subman_api_url "${SUBMAN_API_URL:-}")
  if [[ -z "${api_url}" ]]; then
    subman_set_client_error "api_url_missing" "invalid-request"
    return 1
  fi
  if [[ -z "${SUBMAN_API_TOKEN:-}" ]]; then
    subman_set_client_error "api_token_missing" "auth-required"
    return 1
  fi

  SUBMAN_API_URL=${api_url}
  if ! validate_subman_connection_settings; then
    subman_set_client_error "invalid_connection_settings" "invalid-request"
    return 1
  fi
  endpoint="${api_url}${path}"
  tmp_dir="${SB_DATA_ROOT}/tmp"
  if ! request_dir=$(storage_mktemp -d "${tmp_dir%/}/subman-api.XXXXXX"); then
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi
  if ! chmod 700 "${request_dir}"; then
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi
  config_file="${request_dir}/curl.conf"
  payload_file="${request_dir}/payload.json"
  headers_file="${request_dir}/headers.txt"
  body_file="${request_dir}/body.json"
  stderr_file="${request_dir}/curl.stderr"
  if ! {
    : > "${headers_file}"
    : > "${body_file}"
    : > "${stderr_file}"
    chmod 600 "${headers_file}" "${body_file}" "${stderr_file}"
  }; then
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi

  escaped_token=${SUBMAN_API_TOKEN//\\/\\\\}
  escaped_token=${escaped_token//\"/\\\"}
  if ! {
    printf 'header = "Authorization: Bearer %s"\n' "${escaped_token}"
    if [[ -n "${payload_json}" ]]; then
      printf 'header = "Content-Type: application/json"\n'
    fi
    if [[ -n "${if_match}" ]]; then
      escaped_if_match=${if_match//\\/\\\\}
      escaped_if_match=${escaped_if_match//\"/\\\"}
      printf 'header = "If-Match: %s"\n' "${escaped_if_match}"
    fi
  } > "${config_file}" || ! chmod 600 "${config_file}"; then
    subman_set_client_error "temporary_file_failed" "operator-repair"
    return 1
  fi

  if [[ -n "${payload_json}" ]]; then
    if ! printf '%s' "${payload_json}" > "${payload_file}" || ! chmod 600 "${payload_file}"; then
      subman_set_client_error "temporary_file_failed" "operator-repair"
      return 1
    fi
  fi

  if [[ -n "${payload_json}" ]]; then
    if http_status=$(subman_curl_with_progress "${stderr_file}" -sS --connect-timeout 15 --max-time 60 --config "${config_file}" -X "${method}" "${endpoint}" \
      --data-binary "@${payload_file}" -D "${headers_file}" -o "${body_file}" \
      -w '%{http_code}'); then
      curl_status=0
    else
      curl_status=$?
    fi
  else
    if http_status=$(subman_curl_with_progress "${stderr_file}" -sS --connect-timeout 15 --max-time 60 --config "${config_file}" -X "${method}" "${endpoint}" \
      -D "${headers_file}" -o "${body_file}" -w '%{http_code}'); then
      curl_status=0
    else
      curl_status=$?
    fi
  fi

  [[ "${request_interrupted}" == 0 ]] || return "${request_interrupted}"
  SUBMAN_LAST_HTTP_STATUS=${http_status:-000}
  SUBMAN_LAST_RESPONSE_BODY=$(cat "${body_file}")
  SUBMAN_LAST_RESPONSE_ETAG=$(subman_response_header "${headers_file}" etag)
  SUBMAN_LAST_RESPONSE_REVISION=$(subman_response_header "${headers_file}" x-subman-revision)
  SUBMAN_LAST_RETRY_AFTER=$(subman_response_header "${headers_file}" retry-after)
  SUBMAN_LAST_RESPONSE_CACHE_CONTROL=$(subman_response_header "${headers_file}" cache-control)
  [[ "${SUBMAN_LAST_RETRY_AFTER}" =~ ^[0-9]+$ ]] || SUBMAN_LAST_RETRY_AFTER=""
  if [[ "${curl_status}" -ne 0 ]]; then
    if [[ "${method}" == "GET" ]]; then
      subman_set_client_error "transport_error" "retryable-upstream"
    else
      subman_set_client_error "transport_error" "unknown-outcome"
      SUBMAN_LAST_OUTCOME="unknown-outcome"
    fi
    return 1
  fi
}

capture_subman_api_error() {
  local error_code error_disposition
  error_code=$(jq -r 'if (.error.code | type) == "string" then .error.code else empty end' 2>/dev/null <<< "${SUBMAN_LAST_RESPONSE_BODY}" || true)
  error_disposition=$(jq -r 'if (.error.disposition | type) == "string" then .error.disposition else empty end' 2>/dev/null <<< "${SUBMAN_LAST_RESPONSE_BODY}" || true)
  SUBMAN_LAST_ERROR_CODE=${error_code:-unexpected_response}
  SUBMAN_LAST_ERROR_DISPOSITION=${error_disposition:-operator-repair}
}

report_subman_api_failure() {
  local action=$1
  local detail="HTTP ${SUBMAN_LAST_HTTP_STATUS:-000}"

  [[ -n "${SUBMAN_LAST_ERROR_CODE}" ]] && detail="${detail}, ${SUBMAN_LAST_ERROR_CODE}"
  [[ -n "${SUBMAN_LAST_ERROR_DISPOSITION}" ]] && detail="${detail}/${SUBMAN_LAST_ERROR_DISPOSITION}"
  if [[ -n "${SUBMAN_LAST_RETRY_AFTER}" ]]; then
    detail="${detail}, Retry-After ${SUBMAN_LAST_RETRY_AFTER}s"
  fi
  print_warn "SubMan ${action}失败: ${detail}"
  if [[ "${SUBMAN_LAST_ERROR_DISPOSITION}" == "unknown-outcome" || "${SUBMAN_LAST_OUTCOME:-}" == "unknown-outcome" ]]; then
    print_warn "请求结果不确定；请先在 SubMan 查询节点状态，不要直接盲目重试。"
  fi
}

validate_subman_workspace_response() {
  local response_kind=$1
  local expected_external_key=${2:-}
  local body_revision expected_etag external_label
  local jq_filter

  case "${response_kind}" in
    node)
      jq_filter='(.data.id | type == "string" and length > 0) and (.data.tags | type == "array")'
      ;;
    list)
      jq_filter='(.data | type == "array")'
      ;;
    delete)
      jq_filter='(.data.deleted == true)'
      ;;
    *)
      subman_set_client_error "unexpected_response" "operator-repair"
      return 1
      ;;
  esac

  if [[ -z "${SUBMAN_EXPECTED_GIST_ID:-}" ]]; then
    subman_set_client_error "workspace_gist_required" "operator-repair"
    return 1
  fi

  if ! jq -e "${jq_filter} and (.workspace.file == \"subman.json\") and (.workspace.gistId | type == \"string\" and length > 0) and (.workspace.revision | type == \"number\" and . >= 0 and floor == .)" \
    >/dev/null 2>&1 <<< "${SUBMAN_LAST_RESPONSE_BODY}"; then
    subman_set_client_error "unexpected_response" "operator-repair"
    return 1
  fi

  SUBMAN_LAST_GIST_ID=$(jq -r '.workspace.gistId' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
  if [[ "${SUBMAN_LAST_GIST_ID}" != "${SUBMAN_EXPECTED_GIST_ID}" ]]; then
    subman_set_client_error "workspace_gist_mismatch" "operator-repair"
    return 1
  fi

  body_revision=$(jq -r '.workspace.revision' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
  expected_etag="\"subman-revision-${body_revision}\""
  if [[ "${SUBMAN_LAST_RESPONSE_REVISION}" != "${body_revision}" || "${SUBMAN_LAST_RESPONSE_ETAG}" != "${expected_etag}" ]]; then
    subman_set_client_error "revision_contract_mismatch" "operator-repair"
    return 1
  fi

  if ! jq -en --arg cache_control "${SUBMAN_LAST_RESPONSE_CACHE_CONTROL}" \
    '$cache_control | test("(^|,)\\s*no-store\\s*(,|$)"; "i")' >/dev/null; then
    subman_set_client_error "cache_contract_mismatch" "operator-repair"
    return 1
  fi

  if [[ "${response_kind}" == "node" && -n "${expected_external_key}" ]]; then
    external_label="external:${expected_external_key}"
    if ! jq -e --arg external_label "${external_label}" '
      any(.data.tags[]?; (if type == "string" then . else .label end) == $external_label)
    ' >/dev/null 2>&1 <<< "${SUBMAN_LAST_RESPONSE_BODY}"; then
      subman_set_client_error "external_key_contract_mismatch" "operator-repair"
      return 1
    fi
  fi

  SUBMAN_LAST_REVISION=${body_revision}
  if [[ "${response_kind}" == "node" ]]; then
    SUBMAN_LAST_NODE_ID=$(jq -r '.data.id' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
  fi
}

preflight_subman_workspace() {
  if [[ -z "${SUBMAN_EXPECTED_GIST_ID:-}" ]]; then
    reset_subman_api_result
    subman_set_client_error "workspace_gist_required" "operator-repair"
    return 1
  fi
  subman_api_request "GET" "/api/nodes" || return 1
  if [[ "${SUBMAN_LAST_HTTP_STATUS}" != "200" ]]; then
    capture_subman_api_error
    return 1
  fi
  validate_subman_workspace_response "list"
}

reconcile_subman_node_after_uncertain_write() {
  local external_key=$1
  local payload_json=$2
  local preflight_snapshot=$3
  local previous_http_status=${SUBMAN_LAST_HTTP_STATUS}
  local previous_error_code=${SUBMAN_LAST_ERROR_CODE}
  local previous_error_disposition=${SUBMAN_LAST_ERROR_DISPOSITION}
  local previous_retry_after=${SUBMAN_LAST_RETRY_AFTER}
  local matching_node

  if preflight_subman_workspace; then
    if matching_node=$(printf '%s\n%s\n' "${SUBMAN_LAST_RESPONSE_BODY}" "${preflight_snapshot}" | \
      jq -sce --arg external_label "external:${external_key}" --argjson desired "${payload_json}" '
      def trim_value: gsub("^[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+|[\u0009-\u000D\u0020\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+$"; "");
      def tag_labels: map(if type == "string" then . else .label end | trim_value) | unique;
      # SubMan resolves duplicate display names against the prewrite inventory.
      # Its timestamp is the same UTC committedAt stored in node.updatedAt.
      def server_name($base; $taken; $updated_at):
        if ($taken | index($base)) == null then $base
        else
          ($updated_at
            | select(type == "string")
            | select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"))
            | .[0:16] | sub("T"; " ")) as $timestamp
          | ($base + " " + $timestamp) as $timestamped
          | if ($taken | index($timestamped)) == null then $timestamped
            else first(range(2; ($taken | length) + 3)
              | ($timestamped + " #" + tostring) as $candidate
              | select(($taken | index($candidate)) == null) | $candidate)
            end
        end;
      select(length == 2) | .[1] as $before | .[0]
      | [$before.data[]
        | select(any(.tags[]?; (if type == "string" then . else .label end) == $external_label))
      ] as $prior_targets
      | select(($prior_targets | length) <= 1)
      | ($prior_targets[0].id // null) as $prior_id
      | [$before.data[] | select(.id != $prior_id) | .name | trim_value] as $taken
      | ($desired.name | trim_value) as $base
      |
      [.data[]
        | select(any(.tags[]?; (if type == "string" then . else .label end) == $external_label))
      ]
      | select(length == 1) | .[0]
      | select($prior_id == null or .id == $prior_id)
      | server_name($base; $taken; .updatedAt) as $expected_name
      | select((.id | type == "string" and length > 0)
        and .name == $expected_name
        and .type == $desired.type
        and .raw == ($desired.raw | trim_value)
        and .enabled == (if $desired | has("enabled") then $desired.enabled else true end)
        and .source == (($desired.source // "single") | trim_value)
        and ((.tags | tag_labels) == ((($desired.tags // []) | tag_labels) + [$external_label] | unique)))
    ' 2>/dev/null); then
      SUBMAN_LAST_NODE_ID=$(jq -r '.id' <<< "${matching_node}")
      SUBMAN_LAST_OUTCOME="reconciled"
      return 0
    fi
  fi

  # The read cannot prove that the PUT committed the desired state. Retain its
  # original failure metadata, and never replay the mutation automatically.
  reset_subman_api_result
  SUBMAN_LAST_HTTP_STATUS=${previous_http_status}
  SUBMAN_LAST_ERROR_CODE=${previous_error_code}
  SUBMAN_LAST_ERROR_DISPOSITION=${previous_error_disposition}
  SUBMAN_LAST_RETRY_AFTER=${previous_retry_after}
  SUBMAN_LAST_OUTCOME="unknown-outcome"
  return 1
}

push_subman_node() {
  local external_key=$1
  local payload_json=$2
  local encoded_key if_match preflight_snapshot

  reset_subman_api_result
  if ! validate_subman_node_request "${external_key}" "${payload_json}"; then
    report_subman_api_failure "节点推送"
    return 1
  fi

  if ! preflight_subman_workspace; then
    report_subman_api_failure "Workspace 预检"
    return 1
  fi
  if_match=${SUBMAN_LAST_RESPONSE_ETAG}
  preflight_snapshot=${SUBMAN_LAST_RESPONSE_BODY}
  encoded_key=$(jq -rn --arg value "${external_key}" '$value | @uri')
  if ! subman_api_request "PUT" "/api/nodes/by-key/${encoded_key}" "${payload_json}" "${if_match}"; then
    if [[ "${SUBMAN_LAST_ERROR_DISPOSITION}" == "unknown-outcome" ]] && \
      reconcile_subman_node_after_uncertain_write "${external_key}" "${payload_json}" "${preflight_snapshot}"; then
      print_success "SubMan 节点回读确认: HTTP 200, Workspace revision ${SUBMAN_LAST_REVISION}"
      return 0
    fi
    report_subman_api_failure "节点推送"
    return 1
  fi
  if [[ "${SUBMAN_LAST_HTTP_STATUS}" != "200" ]]; then
    capture_subman_api_error
    if [[ "${SUBMAN_LAST_HTTP_STATUS}" == 5* || "${SUBMAN_LAST_ERROR_DISPOSITION}" == "unknown-outcome" ]]; then
      if reconcile_subman_node_after_uncertain_write "${external_key}" "${payload_json}" "${preflight_snapshot}"; then
        print_success "SubMan 节点回读确认: HTTP 200, Workspace revision ${SUBMAN_LAST_REVISION}"
        return 0
      fi
    fi
    report_subman_api_failure "节点推送"
    return 1
  fi
  if ! validate_subman_workspace_response "node" "${external_key}"; then
    SUBMAN_LAST_OUTCOME="unknown-outcome"
    report_subman_api_failure "节点推送"
    return 1
  fi

  SUBMAN_LAST_OUTCOME="committed"
  print_success "SubMan 节点推送成功: HTTP 200, Workspace revision ${SUBMAN_LAST_REVISION}"
}

delete_subman_node_by_external_key() {
  local external_key=$1
  local quiet=${2:-n}
  local external_label node_id node_count encoded_node_id attempt if_match

  external_label="external:${external_key}"
  for attempt in 1 2; do
    if ! preflight_subman_workspace; then
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点查询"
      return 1
    fi
    if [[ "${SUBMAN_LAST_HTTP_STATUS}" != "200" ]]; then
      capture_subman_api_error
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点查询"
      return 1
    fi
    if ! validate_subman_workspace_response "list"; then
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点查询"
      return 1
    fi

    node_count=$(jq -r --arg external_label "${external_label}" '[
      .data[]
      | select(any(.tags[]?; (if type == "string" then . else .label end) == $external_label))
      | .id
    ] | unique | length' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
    if [[ "${node_count}" -eq 0 ]]; then
      SUBMAN_LAST_OUTCOME="absent"
      [[ "${quiet}" == "y" ]] || print_info "SubMan 旧节点无需清理: ${external_key}"
      return 0
    fi
    if [[ "${node_count}" -ne 1 ]]; then
      subman_set_client_error "external_key_ambiguous" "operator-repair"
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
      return 1
    fi

    node_id=$(jq -r --arg external_label "${external_label}" '
      [.data[] | select(any(.tags[]?; (if type == "string" then . else .label end) == $external_label)) | .id]
      | unique[0]
    ' <<< "${SUBMAN_LAST_RESPONSE_BODY}")
    if_match=${SUBMAN_LAST_RESPONSE_ETAG}
    encoded_node_id=$(jq -rn --arg value "${node_id}" '$value | @uri')
    if ! subman_api_request "DELETE" "/api/nodes/${encoded_node_id}" "" "${if_match}"; then
      SUBMAN_LAST_NODE_ID=${node_id}
      [[ "${SUBMAN_LAST_ERROR_DISPOSITION}" != "unknown-outcome" ]] || SUBMAN_LAST_OUTCOME="unknown-outcome"
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
      return 1
    fi
    SUBMAN_LAST_NODE_ID=${node_id}
    if [[ "${SUBMAN_LAST_HTTP_STATUS}" == "200" ]]; then
      if validate_subman_workspace_response "delete"; then
        SUBMAN_LAST_NODE_ID=${node_id}
        SUBMAN_LAST_OUTCOME="committed"
        [[ "${quiet}" == "y" ]] || print_success "SubMan 旧节点已删除: ${external_key}, Workspace revision ${SUBMAN_LAST_REVISION}"
        return 0
      fi
      SUBMAN_LAST_OUTCOME="unknown-outcome"
      [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
      return 1
    fi

    capture_subman_api_error
    [[ "${SUBMAN_LAST_HTTP_STATUS}" != 5* ]] || SUBMAN_LAST_OUTCOME="unknown-outcome"
    if [[ "${SUBMAN_LAST_ERROR_CODE}" == "entity_not_found" || "${SUBMAN_LAST_ERROR_CODE}" == "entity_deleted" || "${SUBMAN_LAST_ERROR_CODE}" == "not_found" ]]; then
      SUBMAN_LAST_ERROR_CODE=""
      SUBMAN_LAST_ERROR_DISPOSITION=""
      SUBMAN_LAST_RETRY_AFTER=""
      SUBMAN_LAST_OUTCOME="absent"
      return 0
    fi
    if [[ "${attempt}" -eq 1 && "${SUBMAN_LAST_ERROR_DISPOSITION}" == "state-conflict" ]]; then
      continue
    fi
    [[ "${quiet}" == "y" ]] || report_subman_api_failure "旧节点清理"
    return 1
  done
}

push_subman_legacy_protocol_key_cleanup() {
  local protocol=$1
  local instance_id=${2:-}
  local quiet=${3:-n}
  local external_key

  if ! external_key=$(subman_external_key_for_protocol "${protocol}" "${instance_id}" ""); then
    [[ "${quiet}" == "y" ]] || print_warn "生成 SubMan 旧节点清理键失败: ${protocol}"
    return 1
  fi

  delete_subman_node_with_result "${external_key}" "${quiet}"
}

subman_instance_ready_for_legacy_cleanup() {
  local attempted=$1
  local synced=$2
  local stacked_synced=$3

  (( attempted > 0 && synced == attempted && stacked_synced == attempted ))
}
