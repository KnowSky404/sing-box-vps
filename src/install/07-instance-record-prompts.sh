
prompt_global_instance_options() {
  local default_exit private_access

  routing_policy_prepare_install_defaults || return 1
  default_exit="原生直连（WARP 关闭）"
  if [[ "${SB_ENABLE_WARP}" == y ]]; then
    if [[ "${SB_WARP_ROUTE_MODE}" == all ]]; then
      default_exit="WARP 全量出口"
    else
      default_exit="原生直连，命中分流规则时使用 WARP"
    fi
  fi
  private_access="允许"
  [[ "${SB_ADVANCED_ROUTE}" != y ]] || private_access="拒绝"
  log_info "使用全局规则：${default_exit}；服务端私网访问：${private_access}。"
  log_info "新节点跟随全局规则；请通过菜单 13「规则与分流管理」调整策略。"
  return 0
}

# Interactive Mixed management deliberately captures one validated store
# snapshot before prompting.  The revision from that snapshot is passed to
# the lifecycle CAS operation after the user finishes, so a long prompt can
# never accidentally overwrite a concurrent change.
# Standalone SOCKS uses the same typed record shape and CAS UI as Mixed.  Keep
# these helpers protocol-parameterized so the two menus cannot drift in their
# validation, credential handling, or public-listener acknowledgement.
plain_proxy_management_label() {
  case "${1:-}" in
    mixed) printf 'Mixed' ;;
    socks) printf 'SOCKS' ;;
    http) printf 'HTTP' ;;
    shadowsocks) printf 'Shadowsocks' ;;
    trojan) printf 'Trojan' ;;
    vmess) printf 'VMess' ;;
    vless-plain) printf 'VLESS' ;;
    anytls) printf 'AnyTLS' ;;
    hy2) printf 'Hysteria2' ;;
    snell) printf 'Snell' ;;
    tuic) printf 'TUIC' ;;
    hysteria) printf 'Hysteria' ;;
    naive) printf 'NaiveProxy' ;;
    shadowtls) printf 'ShadowTLS' ;;
    *) return 1 ;;
  esac
}

plain_proxy_management_capture_snapshot() {
  local protocol=${1:-} destination=${2:-} store_file
  structured_instance_store_protocol "${protocol}" >/dev/null || return 1
  [[ -n "${destination}" && ! -L "${destination}" ]] || return 1
  if plain_proxy_structured_state_active "${protocol}" >/dev/null 2>&1; then
    store_file=$(plain_proxy_structured_store_file "${protocol}") || return 1
    structured_instance_store_snapshot_json "${protocol}" "${store_file}" > "${destination}" || return 1
  elif [[ "${protocol}" == mixed ]] && protocol_state_exists mixed; then
    mixed_config_store_candidate | jq -c '.revision=0' > "${destination}" || return 1
  elif [[ "${protocol}" == anytls ]] && protocol_state_exists anytls; then
    plain_proxy_config_store_candidate anytls | jq -c '.revision=0' > "${destination}" || return 1
  elif [[ "${protocol}" == hy2 ]] && protocol_state_exists hy2; then
    # Import the complete legacy TLS settings before the lifecycle CAS write.
    plain_proxy_config_store_candidate hy2 | jq -c '.revision=0' > "${destination}" || return 1
  elif [[ "${protocol}" == shadowtls ]] && [[ -f "${SINGBOX_CONFIG_FILE}" ]] &&
       [[ "$(config_protocol_inbound_count shadowtls "${SINGBOX_CONFIG_FILE}" 2>/dev/null || printf 0)" -gt 0 ]]; then
    # ShadowTLS has no legacy .env shape.  A live composite config can be
    # taken over only through the typed candidate extractor, which preserves
    # the outer/inner relationship and starts its local CAS at revision 0.
    plain_proxy_config_store_candidate shadowtls "${SINGBOX_CONFIG_FILE}" | jq -c '.revision=0' > "${destination}" || return 1
  elif [[ -e "$(plain_proxy_structured_store_file "${protocol}")" ]]; then
    plain_proxy_inactive_store_snapshot "${protocol}" > "${destination}" || return 1
  else
    [[ -f "${SINGBOX_CONFIG_FILE}" ]] || return 1
    validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" || return 1
    [[ "$(config_protocol_inbound_count "${protocol}" "${SINGBOX_CONFIG_FILE}" 2>/dev/null || printf 0)" == "0" ]] || return 1
    structured_instance_store_empty_json "${protocol}" > "${destination}" || return 1
  fi
  validate_structured_instance_store "${protocol}" "${destination}"
}

plain_proxy_management_prompt_target() {
  local protocol=${1:-} snapshot=${2:-} prompt=${3:-请选择实例}
  local choice id index count label
  label=$(plain_proxy_management_label "${protocol}") || return 1
  [[ -f "${snapshot}" && ! -L "${snapshot}" ]] || return 1
  jq -e '.instances | length > 0' "${snapshot}" >/dev/null 2>&1 || return 1
  echo "当前 ${label} 实例:" >&2
  jq -r '.instances[] | "- \(.id): \(.name) (\(.listen.address):\(.listen.port))"' "${snapshot}" >&2 || return 1
  read -rp "${prompt}（可输入实例 ID 或序号，留空使用默认）: " choice || return 1
  choice=$(trim_whitespace "${choice}")
  if [[ -z "${choice}" ]]; then
    id=$(jq -r '.default_instance_id' "${snapshot}") || return 1
  elif jq -e --arg id "${choice}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1; then
    id=${choice}
  elif [[ "${choice}" =~ ^[1-9][0-9]{0,2}$ ]]; then
    count=$(jq -r '.instances | length' "${snapshot}") || return 1
    index=$((choice - 1))
    (( index < count )) || return 1
    id=$(jq -r --argjson index "${index}" '.instances[$index].id // empty' "${snapshot}") || return 1
  else
    log_warn "未找到 ${label} 实例 ID: ${choice}" >&2
    return 1
  fi
  structured_instance_store_validate_id "${id}" || return 1
  printf '%s' "${id}"
}

plain_proxy_management_next_id() {
  local protocol=${1:-} snapshot=${2:-} prefix candidate=1
  prefix=$(plain_proxy_management_label "${protocol}") || return 1
  prefix=${prefix,,}
  while jq -e --arg id "${prefix}-${candidate}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1; do
    candidate=$((candidate + 1))
  done
  printf '%s-%s' "${prefix}" "${candidate}"
}

plain_proxy_management_next_tag() {
  local protocol=${1:-} snapshot=${2:-} label candidate suffix=2
  label=$(plain_proxy_management_label "${protocol}") || return 1
  label=${label,,}
  candidate="${label}-in"
  while jq -e --arg tag "${candidate}" 'any(.instances[]; .tag == $tag)' "${snapshot}" >/dev/null 2>&1 ||
        jq -e --arg tag "${candidate}" 'any(.inbounds[]?; .tag == $tag)' "${SINGBOX_CONFIG_FILE}" >/dev/null 2>&1; do
    candidate="${label}-in-${suffix}"
    suffix=$((suffix + 1))
  done
  printf '%s' "${candidate}"
}

shadowsocks_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer auth_json network_json method current_auth current_network
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=n
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .id, "\u0001"' "${snapshot}") || return 1; id=${id%$'\1'}
    name=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .name, "\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .tag, "\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .listen.address, "\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | .listen.port' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | .outbound_policy' "${snapshot}") || return 1
    current_auth=$(jq -c --arg id "${target}" '.instances[] | select(.id == $id) | .authentication' "${snapshot}") || return 1
    current_network=$(jq -c --arg id "${target}" '.instances[] | select(.id == $id) | .listen.network' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id shadowsocks "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file shadowsocks "${snapshot}") || return 1
    tag=$(plain_proxy_management_next_tag shadowsocks "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=1080; policy=default
    current_auth='{"method":"2022-blake3-aes-128-gcm","password":"","users":[]}'
    current_network='["tcp","udp"]'
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1
  [[ -z "${answer}" ]] || name=${answer}
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}")
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  method=$(jq -r '.method' <<< "${current_auth}") || return 1
  method=$(shadowsocks_prompt_method "${method}") || return 1
  shadowsocks_prompt_auth "${method}" "${current_auth}" || return 1
  auth_json=${SB_SHADOWSOCKS_AUTH_JSON}
  network_json=$(shadowsocks_prompt_network "${current_network}") || return 1
  SB_SHADOWSOCKS_NETWORK_JSON=${network_json}
  if [[ "${method}" == none ]]; then
    log_warn 'Shadowsocks none 不提供加密，仅适合受限内网；请确认防火墙与访问源限制。' >&2
  fi
  answer=$(plain_proxy_management_prompt_public_consent shadowsocks "${address}" '' "${auth_json}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then
    log_info '未确认公网暴露，已取消 Shadowsocks 实例变更。'; return 2
  fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}
  MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson network "${network_json}" --argjson auth "${auth_json}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port,network:$network},authentication:$auth,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" shadowsocks
}

trojan_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls transport trust
  local tls_choice trust_choice edit_users edit_transport server_name certificate_path key_path
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    transport=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.transport' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id trojan "${snapshot}") || return 1; name=$(default_instance_node_name_from_file trojan "${snapshot}") || return 1
    tag=$(plain_proxy_management_next_tag trojan "${snapshot}") || return 1; address=${SB_DEFAULT_LISTEN_ADDRESS}; port=443
    users='[]'; tls='{"enabled":false}'; transport='{"type":"none"}'; trust=certificate; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=${answer}
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}")
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then
    edit_users=y
  else
    edit_users=$(prompt_yes_no '[Trojan] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  fi
  if [[ "${edit_users}" == y ]]; then
    trojan_prompt_users "${users}" || return 1
    users=${SB_TROJAN_AUTH_JSON}
  fi
  if [[ "${operation}" == create ]]; then
    tls_choice=$(prompt_yes_no '[Trojan] 是否启用 TLS [y/n] (默认 y): ' y) || return 1
  else
    tls_choice=$(jq -r 'if .enabled == true then "y" else "n" end' <<< "${tls}") || return 1
    tls_choice=$(prompt_yes_no '[Trojan] 是否启用 TLS [y/n] (默认保持当前): ' "${tls_choice}") || return 1
  fi
  if [[ "${tls_choice}" == y ]]; then
    server_name=$(jq -r '.server_name // empty' <<< "${tls}"); certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls}"); key_path=$(jq -r '.key_path // empty' <<< "${tls}")
    read -rp "TLS server name（当前: ${server_name}，留空保持）: " answer || return 1
    [[ -z "${answer}" ]] || server_name=${answer}
    [[ -n "${server_name}" ]] || return 1
    certificate_path=$(prompt_required_path "TLS 证书绝对路径（当前: ${certificate_path}）: " "${certificate_path}") || return 1
    key_path=$(prompt_required_path "TLS 私钥绝对路径（当前: ${key_path}）: " "${key_path}") || return 1
    tls=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
    trust_choice=$(prompt_choice '客户端信任 [1=certificate,2=system] (默认保持): ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
    [[ "${trust_choice}" == 2 ]] && trust=system || trust=certificate
    if [[ "${trust}" == system ]]; then
      log_warn '系统信任要求客户端信任该证书签发链；不嵌入固定证书，也不关闭证书校验。' >&2
    fi
  else tls='{"enabled":false}'; trust=system; fi
  if [[ "${operation}" == create ]]; then
    trojan_prompt_transport || return 1
    transport=${SB_TROJAN_TRANSPORT_JSON}
  else
    edit_transport=$(prompt_yes_no '[Trojan] 是否编辑传输 [y/n] (默认 n): ' n) || return 1
    if [[ "${edit_transport}" == y ]]; then
      trojan_prompt_transport || return 1
      transport=${SB_TROJAN_TRANSPORT_JSON}
    fi
  fi
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --argjson transport "${transport}" --arg trust "${trust}" --arg policy "${policy}" '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,transport:$transport,client_trust:$trust,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" trojan
}

vmess_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls transport trust
  local edit_users edit_transport
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    transport=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.transport' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id vmess "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file vmess "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag vmess "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=1080; users='[]'; tls='{"enabled":false}'; transport='{"type":"none"}'; trust=system; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}")
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then edit_users=y; else edit_users=$(prompt_yes_no '[VMess] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1; fi
  if [[ "${edit_users}" == y ]]; then vmess_prompt_users "${users}" || return 1; users=${SB_VMESS_AUTH_JSON}; fi
  vmess_prompt_tls "${tls}" || return 1; tls=${SB_VMESS_TLS_JSON}
  trust=${SB_VMESS_CLIENT_TRUST:-system}
  if [[ "${operation}" == create ]]; then
    vmess_prompt_transport || return 1; transport=${SB_VMESS_TRANSPORT_JSON}
  else
    edit_transport=$(prompt_yes_no '[VMess] 是否编辑传输 [y/n] (默认 n): ' n) || return 1
    if [[ "${edit_transport}" == y ]]; then vmess_prompt_transport || return 1; transport=${SB_VMESS_TRANSPORT_JSON}; fi
  fi
  answer=$(plain_proxy_management_prompt_public_consent vmess "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then
    log_info '未确认公网暴露，已取消 VMess 实例变更。'; return 2
  fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --argjson transport "${transport}" \
    --arg trust "${trust}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,transport:$transport,client_trust:$trust,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" vmess
}

vless_plain_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls transport trust
  local edit_users edit_transport
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    transport=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.transport' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id vless-plain "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file vless-plain "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag vless-plain "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=1080; users='[]'; tls='{"enabled":false}'; transport='{"type":"none"}'; trust=system; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}")
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then edit_users=y; else edit_users=$(prompt_yes_no '[VLESS] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1; fi
  if [[ "${edit_users}" == y ]]; then vless_plain_prompt_users "${users}" || return 1; users=${SB_VLESS_PLAIN_AUTH_JSON}; fi
  vless_plain_prompt_tls "${tls}" || return 1; tls=${SB_VLESS_PLAIN_TLS_JSON}; trust=${SB_VLESS_PLAIN_CLIENT_TRUST:-system}
  if [[ "${operation}" == create ]]; then
    vless_plain_prompt_transport || return 1; transport=${SB_VLESS_PLAIN_TRANSPORT_JSON}
  else
    edit_transport=$(prompt_yes_no '[VLESS] 是否编辑传输 [y/n] (默认 n): ' n) || return 1
    if [[ "${edit_transport}" == y ]]; then vless_plain_prompt_transport || return 1; transport=${SB_VLESS_PLAIN_TRANSPORT_JSON}; fi
  fi
  answer=$(plain_proxy_management_prompt_public_consent vless-plain "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then
    log_info '未确认公网暴露，已取消 VLESS 实例变更。'; return 2
  fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --argjson transport "${transport}" \
    --arg trust "${trust}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,transport:$transport,client_trust:$trust,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" vless-plain
}

anytls_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls trust trust_choice edit_users
  local server_name certificate_path key_path
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id anytls "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file anytls "${snapshot}") || return 1
    tag=$(plain_proxy_management_next_tag anytls "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=443; users='[]'; tls='{"enabled":true,"server_name":"","certificate_path":"","key_path":""}'; trust=system; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1
  [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1
    [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1
    [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1
  [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}")
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then
    edit_users=y
  else
    edit_users=$(prompt_yes_no '[AnyTLS] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  fi
  if [[ "${edit_users}" == y ]]; then
    anytls_prompt_users "${users}" || return 1
    users=${SB_ANYTLS_AUTH_JSON}
  fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls}") || return 1
  while [[ -z "${server_name}" ]]; do
    read -rp "[AnyTLS] TLS server name: " answer || return 1
    server_name=$(trim_whitespace "${answer}")
    [[ -n "${server_name}" ]] || log_warn '[AnyTLS] TLS server name 不能为空。' >&2
  done
  certificate_path=$(prompt_required_path "[AnyTLS] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[AnyTLS] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  tls=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" \
    '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[AnyTLS] 客户端证书信任 [1=certificate,2=system] (默认保持): ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && trust=system || trust=certificate
  [[ "${trust}" == system ]] && log_warn '系统信任模式要求客户端系统信任该证书签发链；不关闭证书校验。' >&2
  answer=$(plain_proxy_management_prompt_public_consent anytls "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then
    log_info '未确认公网暴露，已取消 AnyTLS 实例变更。'; return 2
  fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --arg trust "${trust}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$trust,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" anytls
}

plain_proxy_management_prompt_public_consent() {
  local protocol=${1:-} address=${2:-} tls_json=${3:-} auth_json=${4:-} label tls_enabled=n plaintext=y
  label=$(plain_proxy_management_label "${protocol}") || return 1
  if [[ ("${protocol}" == http || "${protocol}" == trojan || "${protocol}" == vmess || "${protocol}" == "vless-plain" || "${protocol}" == anytls || "${protocol}" == hy2 || "${protocol}" == tuic || "${protocol}" == hysteria || "${protocol}" == naive) && -n "${tls_json}" ]] &&
     jq -e '.enabled == true' <<< "${tls_json}" >/dev/null 2>&1; then
    tls_enabled=y
  fi
  if [[ "${protocol}" == shadowsocks ]]; then
    plaintext=n
    if [[ -n "${auth_json}" ]] &&
       [[ "$(jq -r '.method // empty' <<< "${auth_json}" 2>/dev/null || true)" == none ]]; then
      plaintext=y
    fi
  fi
  case "${address}" in
    127.*|::1) printf 'n'; return 0 ;;
  esac
  if [[ "${tls_enabled}" == y ]]; then
    prompt_yes_no "该 ${label} 入口将在非回环地址 ${address} 提供 TLS；确认继续并承担公网暴露风险 [y/N]: " n
  elif [[ "${plaintext}" == y ]]; then
    prompt_yes_no "该 ${label} 入口将以明文暴露在非回环地址 ${address}；确认继续并承担公网暴露风险 [y/N]: " n
  else
    prompt_yes_no "该 ${label} 入口将在非回环地址 ${address} 提供服务；确认继续并承担公网暴露风险 [y/N]: " n
  fi
}

plain_proxy_management_prompt_tls() {
  local protocol=${1:-} current=${2:-'{"enabled":false}'} enabled server_name certificate_path key_path
  [[ "${protocol}" == http ]] || return 1
  jq -e 'type == "object" and (.enabled | type == "boolean")' <<< "${current}" >/dev/null 2>&1 || return 1
  enabled=$(jq -r '.enabled' <<< "${current}") || return 1
  if [[ "${enabled}" == true ]]; then
    enabled=y
  else
    enabled=n
  fi
  enabled=$(prompt_yes_no "是否启用 HTTP TLS [y/n]（当前: ${enabled}，默认 ${enabled}）: " "${enabled}") || return 1
  if [[ "${enabled}" == n ]]; then
    SB_HTTP_TLS_JSON='{"enabled":false}'
    return 0
  fi
  server_name=$(jq -r '.server_name // empty' <<< "${current}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${current}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${current}") || return 1
  server_name=$(prompt_optional_domain "HTTP TLS server name（当前: ${server_name}）: " "${server_name}") || return 1
  # Paths are references only. The menu never creates, deletes, or rewrites
  # certificate material; config generation performs the final file check.
  certificate_path=$(prompt_required_path "HTTP TLS 证书绝对路径（当前: ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "HTTP TLS 私钥绝对路径（当前: ${key_path}）: " "${key_path}") || return 1
  SB_HTTP_TLS_JSON=$(jq -n -cS --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" \
    '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
}

hy2_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls trust trust_choice edit_users
  local server_name certificate_path key_path up_mbps down_mbps obfs enabled obfs_type obfs_password masquerade
  local tls_choice tls_default=1 acme acme_choice acme_default=1 email api_token
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
    up_mbps=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.bandwidth.up_mbps // empty' "${snapshot}") || return 1
    down_mbps=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.bandwidth.down_mbps // empty' "${snapshot}") || return 1
    obfs=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.obfs' "${snapshot}") || return 1
    masquerade=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.masquerade,"\u0001"' "${snapshot}") || return 1; masquerade=${masquerade%$'\1'}
  else
    id=$(plain_proxy_management_next_id hy2 "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file hy2 "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag hy2 "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=443; users='[]'; tls='{"enabled":true,"server_name":"","certificate_path":"","key_path":""}'
    trust=system; up_mbps=""; down_mbps=""; obfs='{"enabled":false,"type":"","password":""}'; masquerade=""; policy=default
  fi
  echo '[Hysteria2] 实例名称用于显示；ID 用于区分实例，tag 用于配置中的入口标识，均可留空使用当前值或默认值。' >&2
  echo '[Hysteria2] 新建默认监听 ::，同时接受外部 IPv4 / IPv6 连接；可填写 0.0.0.0 仅使用 IPv4，或 127.0.0.1 仅允许本机连接。修改时留空保留原地址。' >&2
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}"); structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}"); structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then edit_users=y; else edit_users=$(prompt_yes_no '[Hysteria2] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1; fi
  if [[ "${edit_users}" == y ]]; then hy2_prompt_users "${users}" || return 1; users=${SB_HY2_AUTH_JSON}; fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls}") || return 1
  if [[ "${operation}" == replace ]] && ! jq -e 'has("acme")' <<< "${tls}" >/dev/null; then tls_default=2; fi
  echo '[Hysteria2] TLS 模式：1=ACME 自动签发与续期（无需提前准备证书）；2=已有的手动证书。' >&2
  tls_choice=$(prompt_choice "[Hysteria2] TLS 模式 [1-2]（留空保持；新建默认 1）: " 1 2 "${tls_default}") || return 1
  echo '[Hysteria2] server_name / SNI 是客户端校验证书的名称，必填且需与证书匹配，如 hy2.example.com；不带 https:// 或路径。' >&2
  [[ -z "${server_name}" ]] || printf '[Hysteria2] 保留当前 server_name / SNI：%s\n' "${server_name}" >&2
  while [[ -z "${server_name}" ]]; do
    server_name=$(prompt_optional_domain '[Hysteria2] server_name / SNI（必填）: ' "${SB_SHARED_TLS_DOMAIN:-}") || return 1
    [[ -n "${server_name}" ]] || log_warn 'server_name / SNI 不能为空。' >&2
  done
  if [[ "${tls_choice}" == 1 ]]; then
    acme=$(jq -c '.acme // {}' <<< "${tls}") || return 1
    if jq -e 'has("dns01_challenge")' <<< "${acme}" >/dev/null; then acme_default=2; fi
    echo '[Hysteria2] ACME 验证：1=HTTP-01（域名需解析到本机，公网 TCP 80 需可达且可用于验证）；2=Cloudflare DNS-01（需该域名的 DNS 编辑权限，无需开放 TCP 80）。' >&2
    acme_choice=$(prompt_choice '[Hysteria2] ACME 验证方式 [1-2]（留空保持；新建默认 1）: ' 1 2 "${acme_default}") || return 1
    if [[ "${acme_choice}" == 1 ]]; then
      validate_tls_domain_points_to_server Hysteria2 "${server_name}" || return 1
    fi
    email=$(jq -r '.email // ""' <<< "${acme}") || return 1
    email=$(prompt_optional_email '[Hysteria2] ACME 邮箱（可留空，已有值留空保持，用于证书通知）: ' "${email}") || return 1
    acme=$(jq -c --arg domain "${server_name}" --arg email "${email}" --arg directory "${SB_ACME_DATA_DIR}" '
      if has("domain") then . else .domain=[$domain] end |
      if has("data_directory") then . else .data_directory=$directory end |
      if $email == "" then del(.email) else .email=$email end
    ' <<< "${acme}") || return 1
    if [[ "${acme_choice}" == 2 ]]; then
      api_token=$(jq -r '.dns01_challenge.api_token // ""' <<< "${acme}") || return 1
      while true; do
        read -rsp '[Hysteria2] Cloudflare API Token（DNS 编辑权限，已有值可留空保持）: ' answer || return 1
        printf '\n' >&2
        [[ -z "${answer}" ]] || api_token=${answer}
        [[ -n "${api_token}" && "${api_token}" != *[[:space:][:cntrl:]]* ]] && break
        log_warn 'Cloudflare API Token 不能为空或含空白字符。' >&2
      done
      acme=$(jq -c --arg token "${api_token}" '.dns01_challenge=((.dns01_challenge // {}) + {provider:"cloudflare",api_token:$token})' <<< "${acme}") || return 1
    else
      if [[ "${operation}" == create || "${tls_default}" == 2 || "${acme_default}" == 2 ]]; then
        acme=$(jq -c 'del(.dns01_challenge) | .disable_http_challenge=false | .disable_tls_alpn_challenge=true' <<< "${acme}") || return 1
      fi
    fi
    tls=$(jq -cn --arg server_name "${server_name}" --argjson acme "${acme}" '{enabled:true,server_name:$server_name,acme:$acme}') || return 1
    trust=system
  else
    echo '[Hysteria2] 手动模式：证书和私钥文件必须已存在于本机。' >&2
    certificate_path=$(prompt_required_path "[Hysteria2] TLS 证书绝对路径（必填，如 /etc/ssl/certs/hy2.pem；当前 ${certificate_path}，已有值可留空保持）: " "${certificate_path}") || return 1
    key_path=$(prompt_required_path "[Hysteria2] TLS 私钥绝对路径（必填，如 /etc/ssl/private/hy2.key；当前 ${key_path}，已有值可留空保持）: " "${key_path}") || return 1
    tls=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
    echo '[Hysteria2] 证书信任：1=信任此证书（适合自签名证书，客户端导出会携带公开证书）；2=系统证书库（适合受信任 CA 签发的证书）。' >&2
    trust_choice=$(prompt_choice "[Hysteria2] 客户端证书信任 [1-2]（当前 ${trust}，留空保持；新建默认 2）: " 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
    [[ "${trust_choice}" == 2 ]] && trust=system || trust=certificate
  fi
  echo '[Hysteria2] 带宽为可选项，单位 Mbps；上行为服务端发送，下行为服务端接收，留空不限制（修改时会清空原限制）。' >&2
  up_mbps=$(prompt_update_optional_positive_integer "[Hysteria2] 上行带宽 Mbps（当前: ${up_mbps:-未限制}，留空清空）: " "上行带宽") || return 1
  down_mbps=$(prompt_update_optional_positive_integer "[Hysteria2] 下行带宽 Mbps（当前: ${down_mbps:-未限制}，留空清空）: " "下行带宽") || return 1
  enabled=$(jq -r '.enabled' <<< "${obfs}") || return 1
  echo '[Hysteria2] Salamander 混淆为可选项，新建默认关闭；启用后客户端须使用相同的混淆密码，密码留空可自动生成。' >&2
  enabled=$(prompt_yes_no "[Hysteria2] 是否启用 Salamander obfs [y/n]（当前: ${enabled}，默认保持）: " "$([[ "${enabled}" == true ]] && printf y || printf n)") || return 1
  if [[ "${enabled}" == y ]]; then
    obfs_type=salamander; obfs_password=$(jq -r '.password // empty' <<< "${obfs}") || return 1
    read -rsp '[Hysteria2] obfs 密码（留空保持/自动生成）: ' answer || return 1; printf '\n' >&2
    [[ -z "${answer}" ]] || obfs_password=${answer}; [[ -n "${obfs_password}" ]] || obfs_password=$(trojan_generate_password) || return 1
    obfs=$(jq -cn --arg password "${obfs_password}" '{enabled:true,type:"salamander",password:$password}') || return 1
  else obfs='{"enabled":false,"type":"","password":""}'; fi
  echo '[Hysteria2] masquerade 为可选的伪装网站 URL，须包含 http:// 或 https://，如 https://www.cloudflare.com，用于未通过认证的 HTTP/3 请求；新建留空则不启用，修改留空保持。' >&2
  masquerade=$(prompt_hy2_masquerade_url "[Hysteria2] 伪装网站 URL（当前: ${masquerade:-未启用}，留空保持）: " "${masquerade}") || return 1
  answer=$(plain_proxy_management_prompt_public_consent hy2 "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then log_info '未确认公网暴露，已取消 Hysteria2 实例变更。'; return 2; fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --arg trust "${trust}" --arg up "${up_mbps}" --arg down "${down_mbps}" --argjson obfs "${obfs}" --arg masquerade "${masquerade}" --arg policy "${policy}" '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$trust,bandwidth:{up_mbps:(if $up=="" then null else ($up|tonumber) end),down_mbps:(if $down=="" then null else ($down|tonumber) end)},obfs:$obfs,masquerade:$masquerade,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" hy2
}

snell_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer version psk users obfs_mode obfs_host mode
  local version_choice obfs_choice mode_choice edit_users
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    version=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.version' "${snapshot}") || return 1
    psk=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.psk,"\u0001"' "${snapshot}") || return 1; psk=${psk%$'\1'}
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    obfs_mode=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.obfs_mode' "${snapshot}") || return 1
    obfs_host=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.obfs_host' "${snapshot}") || return 1
    mode=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.mode' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id snell "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file snell "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag snell "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=1080; version=6; psk=$(generate_snell_psk) || return 1
    users='[]'; obfs_mode=""; obfs_host=""; mode=default; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}"); structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}"); structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  version_choice=$(prompt_choice "Snell 版本（当前: ${version}，1=v5, 2=v6）: " 1 2 "$([[ "${version}" == 5 ]] && printf 1 || printf 2)") || return 1
  if [[ "${version_choice}" == 1 ]]; then version=5; else version=6; fi
  read -rsp "PSK（当前: 已设置，留空保持）: " answer || return 1; printf '\n' >&2; [[ -z "${answer}" ]] || psk=${answer}
  [[ -n "${psk}" ]] || psk=$(generate_snell_psk) || return 1
  if [[ "${version}" == 5 ]]; then
    obfs_choice=$(prompt_choice "Snell v5 obfs（1=none, 2=http，默认保持）: " 1 2 "$([[ "${obfs_mode}" == http ]] && printf 2 || printf 1)") || return 1
    if [[ "${obfs_choice}" == 2 ]]; then
      obfs_mode=http
      read -rp "Snell v5 obfs host（当前: ${obfs_host}）: " answer || return 1; [[ -z "${answer}" ]] || obfs_host=$(trim_whitespace "${answer}")
      [[ -n "${obfs_host}" ]] || return 1
    else obfs_mode=none; obfs_host=""; fi
    mode=""
  else
    obfs_mode=""; obfs_host=""
    mode_choice=$(prompt_choice "Snell v6 shaping（1=default, 2=unshaped, 3=unsafe-raw）: " 1 3 "$([[ "${mode}" == unshaped ]] && printf 2 || [[ "${mode}" == unsafe-raw ]] && printf 3 || printf 1)") || return 1
    case "${mode_choice}" in 2) mode=unshaped ;; 3) mode=unsafe-raw ;; *) mode=default ;; esac
  fi
  if [[ "${operation}" == create ]]; then
    edit_users=y
  else
    edit_users=$(prompt_yes_no '[Snell] 是否重新编辑用户 key [y/n] (默认 n): ' n) || return 1
  fi
  if [[ "${edit_users}" == y ]]; then
    snell_prompt_users "${users}" || return 1
    users=${SB_SNELL_USER_JSON}
  fi
  answer=$(plain_proxy_management_prompt_public_consent snell "${address}" '' ) || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then log_info '未确认公网暴露，已取消 Snell 实例变更。'; return 2; fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson version "${version}" --arg psk "${psk}" --argjson users "${users}" \
    --arg obfs_mode "${obfs_mode}" --arg obfs_host "${obfs_host}" --arg mode "${mode}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{psk:$psk,users:$users},version:$version,obfs_mode:$obfs_mode,obfs_host:$obfs_host,mode:$mode,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" snell
}

tuic_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls trust trust_choice edit_users
  local server_name certificate_path key_path cc auth_timeout heartbeat zero_rtt relay udp_over_stream
  local cc_choice relay_choice
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    cc=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.tuic.congestion_control' "${snapshot}") || return 1
    auth_timeout=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.tuic.auth_timeout_seconds' "${snapshot}") || return 1
    heartbeat=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.tuic.heartbeat_seconds' "${snapshot}") || return 1
    zero_rtt=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|if .tuic.zero_rtt_handshake then "y" else "n" end' "${snapshot}") || return 1
    relay=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.tuic.udp_relay_mode' "${snapshot}") || return 1
    udp_over_stream=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|if .tuic.udp_over_stream then "y" else "n" end' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id tuic "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file tuic "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag tuic "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=443
    users=$(jq -cn --arg uuid "$(tuic_generate_uuid)" --arg password "$(trojan_generate_password)" '[{name:"tuic-user-1",uuid:$uuid,password:$password}]') || return 1
    tls='{"enabled":true,"server_name":"","certificate_path":"","key_path":""}'
    trust=system; cc=bbr; auth_timeout=3; heartbeat=10; zero_rtt=n; relay=native; udp_over_stream=n; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}"); structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}"); structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then edit_users=y; else edit_users=$(prompt_yes_no '[TUIC] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1; fi
  if [[ "${edit_users}" == y ]]; then tuic_prompt_users "${users}" || return 1; users=${SB_TUIC_AUTH_JSON}; fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls}") || return 1
  while [[ -z "${server_name}" ]]; do read -rp '[TUIC] TLS server name: ' answer || return 1; server_name=$(trim_whitespace "${answer}"); done
  certificate_path=$(prompt_required_path "[TUIC] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[TUIC] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  tls=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[TUIC] 客户端证书信任 [1=certificate,2=system] (默认保持): ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && trust=system || trust=certificate
  cc_choice=$(prompt_choice '[TUIC] 拥塞控制 [1=cubic,2=new_reno,3=bbr] (默认保持): ' 1 3 "$([[ "${cc}" == cubic ]] && printf 1 || [[ "${cc}" == new_reno ]] && printf 2 || printf 3)") || return 1
  case "${cc_choice}" in 1) cc=cubic ;; 2) cc=new_reno ;; *) cc=bbr ;; esac
  auth_timeout=$(prompt_optional_positive_integer "[TUIC] auth_timeout 秒（当前 ${auth_timeout}）: " "${auth_timeout}" "auth_timeout") || return 1
  heartbeat=$(prompt_optional_positive_integer "[TUIC] heartbeat 秒（当前 ${heartbeat}）: " "${heartbeat}" "heartbeat") || return 1
  zero_rtt=$(prompt_yes_no "[TUIC] 是否启用 zero-rtt-handshake [y/n]（当前 ${zero_rtt}）: " "${zero_rtt}") || return 1
  relay_choice=$(prompt_choice '[TUIC] UDP relay [1=native,2=quic,3=udp_over_stream] (默认保持): ' 1 3 "$([[ "${udp_over_stream}" == y ]] && printf 3 || [[ "${relay}" == quic ]] && printf 2 || printf 1)") || return 1
  case "${relay_choice}" in 1) relay=native; udp_over_stream=n ;; 2) relay=quic; udp_over_stream=n ;; 3) relay=""; udp_over_stream=y ;; esac
  answer=$(plain_proxy_management_prompt_public_consent tuic "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then log_info '未确认公网暴露，已取消 TUIC 实例变更。'; return 2; fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --arg trust "${trust}" \
    --arg cc "${cc}" --arg auth_timeout "${auth_timeout}" --arg heartbeat "${heartbeat}" \
    --arg zero_rtt "${zero_rtt}" --arg relay "${relay}" --arg udp_over_stream "${udp_over_stream}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$trust,tuic:{auth_timeout_seconds:($auth_timeout|tonumber),congestion_control:$cc,heartbeat_seconds:($heartbeat|tonumber),udp_over_stream:($udp_over_stream=="y"),udp_relay_mode:$relay,zero_rtt_handshake:($zero_rtt=="y")},outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" tuic
}

hysteria_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls trust trust_choice edit_users
  local server_name certificate_path key_path up_mbps down_mbps obfs_enabled obfs_password quic_json
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    up_mbps=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.bandwidth.up_mbps' "${snapshot}") || return 1
    down_mbps=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.bandwidth.down_mbps' "${snapshot}") || return 1
    obfs_enabled=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|if .obfs.enabled then "y" else "n" end' "${snapshot}") || return 1
    obfs_password=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.obfs.password,"\u0001"' "${snapshot}") || return 1; obfs_password=${obfs_password%$'\1'}
    quic_json=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.hysteria' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id hysteria "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file hysteria "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag hysteria "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=443
    users=$(jq -cn --arg auth_str "$(trojan_generate_password)" '[{name:"hysteria-user-1",auth_str:$auth_str}]') || return 1
    tls='{"enabled":true,"server_name":"","certificate_path":"","key_path":""}'
    trust=system; up_mbps=100; down_mbps=100; obfs_enabled=n; obfs_password=""
    quic_json='{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'
    policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}"); structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}"); structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then edit_users=y; else edit_users=$(prompt_yes_no '[Hysteria] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1; fi
  if [[ "${edit_users}" == y ]]; then hysteria_prompt_users "${users}" || return 1; users=${SB_HYSTERIA_AUTH_JSON}; fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls}") || return 1
  read -rp "[Hysteria] TLS server name（当前: ${server_name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || server_name=$(trim_whitespace "${answer}"); [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path "[Hysteria] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[Hysteria] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  tls=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[Hysteria] 客户端证书信任 [1=certificate,2=system]（默认保持）: ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && trust=system || trust=certificate
  up_mbps=$(prompt_optional_positive_integer "[Hysteria] 上行带宽 Mbps（当前 ${up_mbps}）: " "${up_mbps}" '上行带宽') || return 1
  down_mbps=$(prompt_optional_positive_integer "[Hysteria] 下行带宽 Mbps（当前 ${down_mbps}）: " "${down_mbps}" '下行带宽') || return 1
  obfs_enabled=$(prompt_yes_no "[Hysteria] 是否启用 obfs [y/n]（当前 ${obfs_enabled}）: " "${obfs_enabled}") || return 1
  if [[ "${obfs_enabled}" == y ]]; then
    read -rsp '[Hysteria] obfs password（留空保持/自动生成）: ' answer || return 1; printf '\n' >&2; [[ -z "${answer}" ]] || obfs_password=${answer}
  else obfs_password=""; fi
  hysteria_prompt_quic_options "${quic_json}" || return 1; quic_json=${SB_HYSTERIA_QUIC_JSON}
  answer=$(plain_proxy_management_prompt_public_consent hysteria "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then log_info '未确认 Hysteria 公网暴露，已取消实例变更。'; return 2; fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --arg trust "${trust}" \
    --argjson up_mbps "${up_mbps}" --argjson down_mbps "${down_mbps}" --argjson obfs_enabled "$([[ "${obfs_enabled}" == y ]] && printf true || printf false)" --arg obfs_password "${obfs_password}" --argjson quic "${quic_json}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$trust,bandwidth:{up_mbps:$up_mbps,down_mbps:$down_mbps},obfs:{enabled:$obfs_enabled,password:$obfs_password},hysteria:$quic,outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" hysteria
}

naive_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer users tls trust trust_choice edit_users
  local server_name certificate_path key_path network cc quic insecure_concurrency stream_window session_window headers
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.name,"\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.tag,"\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[]|select(.id==$id)|.listen.address,"\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.listen.port' "${snapshot}") || return 1
    users=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.authentication.users' "${snapshot}") || return 1
    tls=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.tls' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.client_trust' "${snapshot}") || return 1
    network=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.listen.network' "${snapshot}") || return 1
    cc=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.naive.quic_congestion_control' "${snapshot}") || return 1
    quic=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|if .naive.quic then "y" else "n" end' "${snapshot}") || return 1
    insecure_concurrency=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.naive.insecure_concurrency' "${snapshot}") || return 1
    stream_window=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.naive.stream_receive_window' "${snapshot}") || return 1
    session_window=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.naive.quic_session_receive_window' "${snapshot}") || return 1
    headers=$(jq -c --arg id "${id}" '.instances[]|select(.id==$id)|.naive.extra_headers' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[]|select(.id==$id)|.outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id naive "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file naive "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag naive "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=1080
    users=$(jq -cn --arg password "$(trojan_generate_password)" '[{name:"naive-user-1",username:"naive-user-1",password:$password}]') || return 1
    tls='{"enabled":true,"server_name":"","certificate_path":"","key_path":""}'
    trust=system; network='["tcp","udp"]'; cc=bbr; quic=n; insecure_concurrency=0; stream_window=""; session_window=""; headers='{}'; policy=default
  fi
  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1; [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}"); structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1; [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1; [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}"); structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  if [[ "${operation}" == create ]]; then edit_users=y; else edit_users=$(prompt_yes_no '[NaiveProxy] 是否重新编辑用户凭据 [y/n]（默认 n）: ' n) || return 1; fi
  if [[ "${edit_users}" == y ]]; then naive_prompt_users "${users}" || return 1; users=${SB_NAIVE_AUTH_JSON}; fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls}") || return 1
  while [[ -z "${server_name}" ]]; do read -rp '[NaiveProxy] TLS server name: ' answer || return 1; server_name=$(trim_whitespace "${answer}"); done
  certificate_path=$(prompt_required_path "[NaiveProxy] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[NaiveProxy] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  tls=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[NaiveProxy] 客户端证书信任 [1=certificate,2=system]（默认保持）: ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && trust=system || trust=certificate
  naive_prompt_network "${network}" || return 1; network=${SB_NAIVE_NETWORK_JSON}
  naive_prompt_options "${cc}" "${quic}" "${insecure_concurrency}" "${stream_window}" "${session_window}" "${headers}" || return 1
  cc=${SB_NAIVE_QUIC_CONGESTION_CONTROL}; quic=${SB_NAIVE_QUIC}; insecure_concurrency=${SB_NAIVE_INSECURE_CONCURRENCY}; stream_window=${SB_NAIVE_STREAM_RECEIVE_WINDOW}; session_window=${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW}; headers=${SB_NAIVE_EXTRA_HEADERS_JSON}
  answer=$(plain_proxy_management_prompt_public_consent naive "${address}" "${tls}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then log_info '未确认 NaiveProxy 公网暴露，已取消实例变更。'; return 2; fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" --argjson port "${port}" --argjson users "${users}" --argjson tls "${tls}" --arg trust "${trust}" --argjson network "${network}" --arg cc "${cc}" --arg quic "${quic}" --argjson insecure_concurrency "${insecure_concurrency}" --arg stream_window "${stream_window}" --arg session_window "${session_window}" --argjson headers "${headers}" --arg policy "${policy}" '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port,network:$network},authentication:{users:$users},tls:$tls,client_trust:$trust,naive:{extra_headers:$headers,insecure_concurrency:$insecure_concurrency,quic:($quic=="y"),quic_congestion_control:$cc,quic_session_receive_window:$session_window,stream_receive_window:$stream_window},outbound_policy:$policy,dependencies:[]}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" naive
}

shadowtls_management_build_record() {
  local snapshot=${1:-} operation=${2:-create} target=${3:-} destination=${4:-}
  local id name tag address port policy answer version password users handshake handshake_default handshake_map
  local strict wildcard detour_port trust client_tls detour_tag tls_json
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=${target}
    name=$(jq -j --arg id "${id}" '.instances[] | select(.id == $id) | .name, "\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${id}" '.instances[] | select(.id == $id) | .tag, "\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${id}" '.instances[] | select(.id == $id) | .listen.address, "\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | .listen.port' "${snapshot}") || return 1
    version=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | .version' "${snapshot}") || return 1
    password=$(jq -j --arg id "${id}" '.instances[] | select(.id == $id) | .authentication.password, "\u0001"' "${snapshot}") || return 1; password=${password%$'\1'}
    users=$(jq -c --arg id "${id}" '.instances[] | select(.id == $id) | .authentication.users' "${snapshot}") || return 1
    handshake=$(jq -c --arg id "${id}" '.instances[] | select(.id == $id) | .handshake' "${snapshot}") || return 1
    handshake_map=$(jq -c --arg id "${id}" '.instances[] | select(.id == $id) | .handshake_for_server_name' "${snapshot}") || return 1
    strict=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | if .strict_mode then "y" else "n" end' "${snapshot}") || return 1
    wildcard=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | .wildcard_sni' "${snapshot}") || return 1
    detour_port=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | .detour.listen.port' "${snapshot}") || return 1
    trust=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | .client_trust' "${snapshot}") || return 1
    client_tls=$(jq -c --arg id "${id}" '.instances[] | select(.id == $id) | .client_tls' "${snapshot}") || return 1
    policy=$(jq -r --arg id "${id}" '.instances[] | select(.id == $id) | .outbound_policy' "${snapshot}") || return 1
  else
    id=$(plain_proxy_management_next_id shadowtls "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file shadowtls "${snapshot}") || return 1
    tag=$(plain_proxy_management_next_tag shadowtls "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=8443; version=3; password=""
    users=$(jq -cn --arg password "$(trojan_generate_password)" '[{name:"shadowtls-user-1",password:$password}]') || return 1
    handshake='{"server":"www.apple.com","server_port":443}'
    handshake_map='{}'; strict=n; wildcard=off; detour_port=$(pick_random_high_port) || return 1
    while [[ "${detour_port}" == "${port}" ]]; do detour_port=$(pick_random_high_port) || return 1; done
    trust=system; client_tls='{"server_name":"www.apple.com","certificate_path":""}'; policy=default
  fi

  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1
  [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1
    [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1
    [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  detour_tag="shadowtls-inner-${id}"
  read -rp "监听地址（默认 ${address}）: " answer || return 1
  [[ -z "${answer}" ]] || address=$(trim_whitespace "${answer}")
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "外层监听端口（当前: ${port}）: " "${port}") || return 1

  SB_SHADOWTLS_VERSION=${version}
  SB_SHADOWTLS_PASSWORD=${password}
  SB_SHADOWTLS_AUTH_JSON=${users}
  shadowtls_prompt_version_and_auth "${version}" || return 1
  version=${SB_SHADOWTLS_VERSION}; password=${SB_SHADOWTLS_PASSWORD}; users=${SB_SHADOWTLS_AUTH_JSON}
  handshake_default=${handshake}
  shadowtls_prompt_handshake "${handshake_default}" || return 1
  handshake=${SB_SHADOWTLS_HANDSHAKE_JSON}
  if [[ "${version}" -eq 1 ]]; then
    handshake_map='{}'
  else
    shadowtls_prompt_handshake_map "${handshake_map}" || return 1
    handshake_map=${SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON}
  fi
  if [[ "${version}" -eq 3 ]]; then
    strict=$(prompt_yes_no "strict_mode [y/n]（当前 ${strict}）: " "${strict}") || return 1
    answer=$(prompt_choice 'wildcard_sni [1=off,2=authed,3=all]（默认保持）: ' 1 3 "$([[ "${wildcard}" == authed ]] && printf 2 || [[ "${wildcard}" == all ]] && printf 3 || printf 1)") || return 1
    case "${answer}" in 2) wildcard=authed ;; 3) wildcard=all ;; *) wildcard=off ;; esac
  else
    strict=n; wildcard=off
  fi
  detour_port=$(prompt_port "私有内层端口（当前: ${detour_port}）: " "${detour_port}") || return 1
  [[ "${detour_port}" != "${port}" ]] || {
    printf '[ERROR] ShadowTLS 外层与内层端口必须不同。\n' >&2
    return 1
  }
  answer=$(prompt_choice '客户端证书信任 [1=certificate,2=system]（默认保持）: ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${answer}" == 1 ]] && trust=certificate || trust=system
  shadowtls_prompt_client_tls "${client_tls}" "${trust}" || return 1
  client_tls=${SB_SHADOWTLS_CLIENT_TLS_JSON}
  tls_json=$(jq -cS 'del(.enabled)' <<< "${client_tls}") || return 1

  answer=$(plain_proxy_management_prompt_public_consent shadowtls "${address}" "") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then
    log_info '未确认 ShadowTLS 公网暴露，已取消实例变更。'
    return 2
  fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}; MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" \
    --argjson port "${port}" --argjson version "${version}" --arg password "${password}" --argjson users "${users}" \
    --argjson handshake "${handshake}" --argjson handshake_map "${handshake_map}" \
    --argjson strict "$([[ "${strict}" == y ]] && printf true || printf false)" --arg wildcard "${wildcard}" \
    --arg detour_tag "${detour_tag}" --argjson detour_port "${detour_port}" --arg trust "${trust}" \
    --argjson client_tls "${tls_json}" --arg policy "${policy}" \
    '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},version:$version,authentication:{password:$password,users:$users},handshake:$handshake,handshake_for_server_name:$handshake_map,strict_mode:$strict,wildcard_sni:$wildcard,detour:{tag:$detour_tag,listen:{address:"127.0.0.1",port:$detour_port}},dependencies:[$detour_tag],client_trust:$trust,client_tls:$client_tls,outbound_policy:$policy}' > "${destination}" || return 1
  structured_instance_store_validate_instance_argument "${destination}" shadowtls
}

plain_proxy_management_build_record() {
  local protocol=${1:-} snapshot=${2:-} operation=${3:-create} target=${4:-} destination=${5:-}
  local id name tag address port auth username password policy answer label tls_json
  local name_changed=n address_changed=n port_changed=n username_changed=n password_changed=n
  local auth_changed=n policy_changed=n
  structured_instance_store_protocol "${protocol}" >/dev/null || return 1
  if [[ "${protocol}" == shadowsocks ]]; then
    shadowsocks_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == trojan ]]; then
    trojan_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == vmess ]]; then
    vmess_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == vless-plain ]]; then
    vless_plain_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == anytls ]]; then
    anytls_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == hy2 ]]; then
    hy2_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == snell ]]; then
    snell_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == tuic ]]; then
    tuic_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == hysteria ]]; then
    hysteria_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == naive ]]; then
    naive_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  if [[ "${protocol}" == shadowtls ]]; then
    shadowtls_management_build_record "${snapshot}" "${operation}" "${target}" "${destination}"
    return $?
  fi
  label=$(plain_proxy_management_label "${protocol}") || return 1
  [[ -f "${snapshot}" && ! -L "${snapshot}" && -n "${destination}" ]] || return 1
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=n

  if [[ "${operation}" == replace ]]; then
    jq -e --arg id "${target}" 'any(.instances[]; .id == $id)' "${snapshot}" >/dev/null 2>&1 || return 1
    id=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .id, "\u0001"' "${snapshot}") || return 1; id=${id%$'\1'}
    name=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .name, "\u0001"' "${snapshot}") || return 1; name=${name%$'\1'}
    tag=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .tag, "\u0001"' "${snapshot}") || return 1; tag=${tag%$'\1'}
    address=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .listen.address, "\u0001"' "${snapshot}") || return 1; address=${address%$'\1'}
    port=$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | .listen.port' "${snapshot}") || return 1
    auth=$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | if .authentication.enabled then "y" else "n" end' "${snapshot}") || return 1
    username=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .authentication.username, "\u0001"' "${snapshot}") || return 1; username=${username%$'\1'}
    password=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .authentication.password, "\u0001"' "${snapshot}") || return 1; password=${password%$'\1'}
    policy=$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | .outbound_policy' "${snapshot}") || return 1
    tls_json='{"enabled":false}'
    if [[ "${protocol}" == http ]]; then
      tls_json=$(jq -j --arg id "${target}" '.instances[] | select(.id == $id) | .tls, "\u0001"' "${snapshot}") || return 1
      tls_json=${tls_json%$'\1'}
    fi
  else
    id=$(plain_proxy_management_next_id "${protocol}" "${snapshot}") || return 1
    name=$(default_instance_node_name_from_file "${protocol}" "${snapshot}") || return 1; tag=$(plain_proxy_management_next_tag "${protocol}" "${snapshot}") || return 1
    address=${SB_DEFAULT_LISTEN_ADDRESS}; port=1080; auth=y; username=""; password=""; policy=default; tls_json='{"enabled":false}'
  fi

  read -rp "实例名称（当前: ${name}，留空保持）: " answer || return 1
  if [[ -n "${answer}" ]]; then name=$(trim_whitespace "${answer}"); name_changed=y; fi
  if [[ "${operation}" == create ]]; then
    read -rp "实例 ID（默认 ${id}）: " answer || return 1
    [[ -z "${answer}" ]] || id=$(trim_whitespace "${answer}")
    structured_instance_store_validate_id "${id}" || return 1
    read -rp "入口 tag（默认 ${tag}）: " answer || return 1
    [[ -z "${answer}" ]] || tag=$(trim_whitespace "${answer}")
  fi
  read -rp "监听地址（默认 ${address}）: " answer || return 1
  if [[ -n "${answer}" ]]; then address=$(trim_whitespace "${answer}"); address_changed=y; fi
  structured_instance_store_validate_address "${address}" || return 1
  port=$(prompt_port "监听端口（当前: ${port}）: " "${port}") || return 1
  [[ "${operation}" == create || "${port}" != "$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | .listen.port' "${snapshot}")" ]] && port_changed=y
  auth=$(prompt_yes_no "是否启用用户名密码认证 [y/n]（当前: ${auth}，默认 y）: " "${auth}") || return 1
  [[ "${operation}" == create || "${auth}" != "$(jq -r --arg id "${target}" '.instances[] | select(.id == $id) | if .authentication.enabled then "y" else "n" end' "${snapshot}")" ]] && auth_changed=y
  if [[ "${auth}" == y ]]; then
    read -rp "用户名（留空保持/自动生成）: " answer || return 1
    if [[ -n "${answer}" ]]; then username=${answer}; username_changed=y; fi
    read -rsp "密码（留空保持/自动生成）: " answer || return 1; printf '\n' >&2
    if [[ -n "${answer}" ]]; then password=${answer}; password_changed=y; fi
    SB_MIXED_AUTH_ENABLED=y; SB_MIXED_USERNAME=${username}; SB_MIXED_PASSWORD=${password}
    ensure_mixed_auth_credentials || return 1
    username=${SB_MIXED_USERNAME}; password=${SB_MIXED_PASSWORD}
  else username=""; password=""; fi
  if [[ "${protocol}" == http ]]; then
    SB_HTTP_TLS_JSON=${tls_json}
    plain_proxy_management_prompt_tls http "${tls_json}" || return 1
    tls_json=${SB_HTTP_TLS_JSON}
  fi
  answer=$(plain_proxy_management_prompt_public_consent "${protocol}" "${address}" "${tls_json}") || return 1
  if [[ "${address}" != 127.* && "${address}" != ::1 && "${answer}" != y ]]; then
    log_info "未确认公网明文暴露，已取消 ${label} 实例变更。"; return 2
  fi
  PLAIN_PROXY_MANAGEMENT_ALLOW_PUBLIC=${answer}
  MIXED_MANAGEMENT_ALLOW_PUBLIC=${answer}
  if [[ "${operation}" == replace ]]; then
    jq -cS --arg id "${id}" --arg name "${name}" --arg address "${address}" --arg protocol "${protocol}" --argjson tls "${tls_json}" --argjson port "${port}" \
      --argjson enabled "$([[ "${auth}" == y ]] && printf true || printf false)" --arg username "${username}" --arg password "${password}" --arg policy "${policy}" \
      --argjson name_changed "$([[ "${name_changed}" == y ]] && printf true || printf false)" --argjson address_changed "$([[ "${address_changed}" == y ]] && printf true || printf false)" \
      --argjson port_changed "$([[ "${port_changed}" == y ]] && printf true || printf false)" --argjson auth_changed "$([[ "${auth_changed}" == y ]] && printf true || printf false)" \
      --argjson username_changed "$([[ "${username_changed}" == y ]] && printf true || printf false)" --argjson password_changed "$([[ "${password_changed}" == y ]] && printf true || printf false)" \
      --argjson policy_changed "$([[ "${policy_changed}" == y ]] && printf true || printf false)" \
      'first(.instances[] | select(.id == $id) | .name = if $name_changed then $name else .name end | .listen.address = if $address_changed then $address else .listen.address end | .listen.port = if $port_changed then $port else .listen.port end | .authentication = if $auth_changed and ($enabled | not) then {enabled:false,username:"",password:""} elif $auth_changed or $username_changed or $password_changed then {enabled:true,username:(if $username_changed then $username else .authentication.username end),password:(if $password_changed then $password else .authentication.password end)} else .authentication end | .outbound_policy = if $policy_changed then $policy else .outbound_policy end | if $protocol == "http" then .tls = $tls else . end)' "${snapshot}" > "${destination}" || return 1
  else
    jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --arg address "${address}" --arg protocol "${protocol}" --argjson tls "${tls_json}" --argjson port "${port}" \
      --argjson enabled "$([[ "${auth}" == y ]] && printf true || printf false)" --arg username "${username}" --arg password "${password}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{enabled:$enabled,username:$username,password:$password},outbound_policy:$policy,dependencies:[]} + (if $protocol == "http" then {tls:$tls} else {} end)' > "${destination}" || return 1
  fi
  structured_instance_store_validate_instance_argument "${destination}" "${protocol}"
}
