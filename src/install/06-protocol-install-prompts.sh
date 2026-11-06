
trojan_generate_password() {
  local value
  value=$(openssl rand -hex 24 2>/dev/null) || return 1
  [[ -n "${value}" ]] || return 1
  printf '%s' "${value}"
}

trojan_prompt_users() {
  local current=${1:-'[]'} count i name password old_name old_password users='[]'
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp "[Trojan] 用户数量 (1-128，默认 ${count}): " i || return 1
  [[ -z "${i}" ]] || count=${i}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i=0; i<count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_password=$(jq -j --argjson i "${i}" '.[$i].password // "", "\u0001"' <<< "${current}") || return 1
    old_password=${old_password%$'\1'}
    read -rp "[Trojan] 用户 $((i+1)) 名称 (默认 ${old_name:-user-$((i+1))}): " name || return 1
    name=${name:-${old_name:-user-$((i+1))}}
    if [[ -n "${old_password}" ]]; then
      read -rsp "[Trojan] 用户 ${name} 密码 (留空保持): " password || return 1
    else
      read -rsp "[Trojan] 用户 ${name} 密码 (留空自动生成): " password || return 1
    fi
    printf '\n' >&2
    [[ -n "${password}" ]] || password=${old_password}
    [[ -n "${password}" ]] || password=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg password "${password}" '$users + [{name:$name,password:$password}]') || return 1
  done
  SB_TROJAN_AUTH_JSON=${users}
}

anytls_prompt_users() {
  local current=${1:-'[]'} count i name password old_name old_password users='[]' answer
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp "[AnyTLS] 用户数量 (1-128，默认 ${count}): " answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i=0; i<count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_password=$(jq -j --argjson i "${i}" '.[$i].password // "", "\u0001"' <<< "${current}") || return 1
    old_password=${old_password%$'\1'}
    read -rp "[AnyTLS] 用户 $((i+1)) 名称 (默认 ${old_name:-user-$((i+1))}): " name || return 1
    name=${name:-${old_name:-user-$((i+1))}}
    if [[ -n "${old_password}" ]]; then
      read -rsp "[AnyTLS] 用户 ${name} 密码 (留空保持): " password || return 1
    else
      read -rsp "[AnyTLS] 用户 ${name} 密码 (留空自动生成): " password || return 1
    fi
    printf '\n' >&2
    [[ -n "${password}" ]] || password=${old_password}
    [[ -n "${password}" ]] || password=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg password "${password}" '$users + [{name:$name,password:$password}]') || return 1
  done
  SB_ANYTLS_AUTH_JSON=${users}
}

hy2_prompt_users() {
  local current=${1:-'[]'} count i name password old_name old_password users='[]' answer
  echo '[Hysteria2] 用户名称用于区分凭据；密码用于客户端连接认证，留空可自动生成。' >&2
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp "[Hysteria2] 用户数量 (1-128，默认 ${count}): " answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i=0; i<count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_password=$(jq -j --argjson i "${i}" '.[$i].password // "", "\u0001"' <<< "${current}") || return 1
    old_password=${old_password%$'\1'}
    read -rp "[Hysteria2] 用户 $((i+1)) 名称 (默认 ${old_name:-user-$((i+1))}): " name || return 1
    name=${name:-${old_name:-user-$((i+1))}}
    read -rsp "[Hysteria2] 用户 ${name} 密码 (留空保持/自动生成): " password || return 1
    printf '\n' >&2
    [[ -n "${password}" ]] || password=${old_password}
    [[ -n "${password}" ]] || password=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg password "${password}" '$users + [{name:$name,password:$password}]') || return 1
  done
  SB_HY2_AUTH_JSON=${users}
}

snell_prompt_users() {
  local current=${1:-'[]'} count i name userkey old_name old_userkey users='[]' answer
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[0-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=0
  read -rp "[Snell] 用户数量 (0-128，默认 ${count}): " answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^(0|[1-9][0-9]{0,2})$ && "${count}" -le 128 ]] || return 1
  for ((i=0; i<count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_userkey=$(jq -j --argjson i "${i}" '.[$i].userkey // "", "\u0001"' <<< "${current}") || return 1
    old_userkey=${old_userkey%$'\1'}
    read -rp "[Snell] 用户 $((i+1)) 名称 (默认 ${old_name:-user-$((i+1))}): " name || return 1
    name=$(trim_whitespace "${name:-${old_name:-user-$((i+1))}}")
    [[ -n "${name}" ]] || return 1
    if [[ -n "${old_userkey}" ]]; then
      read -rsp "[Snell] 用户 ${name} key (留空保持): " userkey || return 1
    else
      read -rsp "[Snell] 用户 ${name} key (留空自动生成): " userkey || return 1
    fi
    printf '\n' >&2
    [[ -n "${userkey}" ]] || userkey=${old_userkey}
    [[ -n "${userkey}" ]] || userkey=$(generate_random_token '' 16) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg userkey "${userkey}" '$users + [{name:$name,userkey:$userkey}]') || return 1
  done
  SB_SNELL_USER_JSON=${users}
}

tuic_generate_uuid() {
  local value
  value=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid) || return 1
  [[ "${value}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || return 1
  printf '%s' "${value,,}"
}

tuic_prompt_users() {
  local current=${1:-'[]'} count i name uuid password old_name old_uuid old_password users='[]' answer
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp '[TUIC] 用户数量 (1-128，默认当前值): ' answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i = 0; i < count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_uuid=$(jq -r --argjson i "${i}" '.[$i].uuid // empty' <<< "${current}") || return 1
    old_password=$(jq -j --argjson i "${i}" '.[$i].password // "", "\u0001"' <<< "${current}") || return 1
    old_password=${old_password%$'\1'}
    name=${old_name:-tuic-user-$((i + 1))}
    read -rp "[TUIC] 用户 $((i + 1)) 名称 (默认 ${name}): " answer || return 1
    [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
    [[ -n "${name}" ]] || return 1
    uuid=${old_uuid}
    while true; do
      read -rp "[TUIC] 用户 ${name} UUID (留空自动生成): " answer || return 1
      [[ -z "${answer}" ]] && answer=${uuid}
      [[ -n "${answer}" ]] || answer=$(tuic_generate_uuid) || return 1
      if [[ "${answer}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then uuid=${answer,,}; break; fi
      log_warn '[TUIC] UUID 格式无效，请输入标准 UUID。' >&2
      uuid=""
    done
    if [[ -n "${old_password}" ]]; then
      read -rsp "[TUIC] 用户 ${name} 密码 (留空保持): " answer || return 1
    else
      read -rsp "[TUIC] 用户 ${name} 密码 (留空自动生成): " answer || return 1
    fi
    printf '\n' >&2
    password=${answer:-${old_password}}
    [[ -n "${password}" ]] || password=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg uuid "${uuid}" --arg password "${password}" '$users + [{name:$name,uuid:$uuid,password:$password}]') || return 1
  done
  SB_TUIC_AUTH_JSON=${users}
}

tuic_prompt_options() {
  local current_cc=${1:-bbr} current_timeout=${2:-3} current_heartbeat=${3:-10}
  local current_zero=${4:-n} current_relay=${5:-native} current_uos=${6:-n}
  local choice value
  choice=$(prompt_choice "[TUIC] 拥塞控制 [1=cubic,2=new_reno,3=bbr] (默认保持): " 1 3 "$([[ "${current_cc}" == cubic ]] && printf 1 || [[ "${current_cc}" == new_reno ]] && printf 2 || printf 3)") || return 1
  case "${choice}" in 1) SB_TUIC_CONGESTION_CONTROL=cubic ;; 2) SB_TUIC_CONGESTION_CONTROL=new_reno ;; *) SB_TUIC_CONGESTION_CONTROL=bbr ;; esac
  value=$(prompt_optional_positive_integer "[TUIC] auth_timeout 秒 (当前 ${current_timeout}，留空保持): " "${current_timeout}" "auth_timeout") || return 1
  SB_TUIC_AUTH_TIMEOUT_SECONDS=${value}
  value=$(prompt_optional_positive_integer "[TUIC] heartbeat 秒 (当前 ${current_heartbeat}，留空保持): " "${current_heartbeat}" "heartbeat") || return 1
  SB_TUIC_HEARTBEAT_SECONDS=${value}
  SB_TUIC_ZERO_RTT_HANDSHAKE=$(prompt_yes_no "[TUIC] 是否启用 zero-rtt-handshake [y/n] (当前 ${current_zero}): " "${current_zero}") || return 1
  choice=$(prompt_choice "[TUIC] UDP relay mode [1=native,2=quic,3=关闭并使用 udp_over_stream] (默认保持): " 1 3 "$([[ "${current_relay}" == quic ]] && printf 2 || [[ "${current_uos}" == y ]] && printf 3 || printf 1)") || return 1
  case "${choice}" in
    1) SB_TUIC_UDP_RELAY_MODE=native; SB_TUIC_UDP_OVER_STREAM=n ;;
    2) SB_TUIC_UDP_RELAY_MODE=quic; SB_TUIC_UDP_OVER_STREAM=n ;;
    3) SB_TUIC_UDP_RELAY_MODE=""; SB_TUIC_UDP_OVER_STREAM=y ;;
  esac
}

hysteria_prompt_users() {
  local current=${1:-'[]'} count i name auth old_name old_auth answer users='[]'
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp '[Hysteria] 用户数量 (1-128，默认当前值): ' answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i = 0; i < count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_auth=$(jq -j --argjson i "${i}" '.[$i].auth_str // "", "\u0001"' <<< "${current}") || return 1
    old_auth=${old_auth%$'\1'}
    name=${old_name:-hysteria-user-$((i + 1))}
    read -rp "[Hysteria] 用户 $((i + 1)) 名称 (默认 ${name}): " answer || return 1
    [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
    [[ -n "${name}" ]] || return 1
    if [[ -n "${old_auth}" ]]; then
      read -rsp "[Hysteria] 用户 ${name} auth_str (留空保持): " answer || return 1
    else
      read -rsp "[Hysteria] 用户 ${name} auth_str (留空自动生成): " answer || return 1
    fi
    printf '\n' >&2
    auth=${answer:-${old_auth}}
    [[ -n "${auth}" ]] || auth=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg auth_str "${auth}" '$users + [{name:$name,auth_str:$auth_str}]') || return 1
  done
  SB_HYSTERIA_AUTH_JSON=${users}
}

hysteria_prompt_quic_options() {
  local current=${1:-'{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'}
  local initial mtu streams stream connection answer
  initial=$(jq -r '.initial_packet_size // 0' <<< "${current}") || return 1
  mtu=$(jq -r 'if .disable_path_mtu_discovery then "y" else "n" end' <<< "${current}") || return 1
  streams=$(jq -r '.max_concurrent_streams // 0' <<< "${current}") || return 1
  stream=$(jq -r '.stream_receive_window // ""' <<< "${current}") || return 1
  connection=$(jq -r '.connection_receive_window // ""' <<< "${current}") || return 1
  initial=$(prompt_optional_nonnegative_integer "[Hysteria] QUIC initial_packet_size（当前 ${initial}，0 为默认）: " "${initial}" "initial_packet_size") || return 1
  [[ -n "${initial}" ]] || initial=0
  [[ "${initial}" -le 65535 ]] || return 1
  mtu=$(prompt_yes_no "[Hysteria] 禁用 QUIC path MTU discovery [y/n]（当前 ${mtu}）: " "${mtu}") || return 1
  streams=$(prompt_optional_nonnegative_integer "[Hysteria] QUIC max_concurrent_streams（当前 ${streams}，0 为默认）: " "${streams}" "max_concurrent_streams") || return 1
  [[ -n "${streams}" ]] || streams=0
  [[ "${streams}" -le 65535 ]] || return 1
  read -rp "[Hysteria] stream_receive_window（当前 ${stream}，留空保持/清除）: " answer || return 1
  [[ -z "${answer}" ]] || stream=$(trim_whitespace "${answer}")
  read -rp "[Hysteria] connection_receive_window（当前 ${connection}，留空保持/清除）: " answer || return 1
  [[ -z "${answer}" ]] || connection=$(trim_whitespace "${answer}")
  SB_HYSTERIA_QUIC_JSON=$(jq -cn --argjson initial_packet_size "${initial}" --argjson max_concurrent_streams "${streams}" --argjson disable_path_mtu_discovery "$([[ "${mtu}" == y ]] && printf true || printf false)" --arg stream_receive_window "${stream}" --arg connection_receive_window "${connection}" '{connection_receive_window:$connection_receive_window,disable_path_mtu_discovery:$disable_path_mtu_discovery,initial_packet_size:$initial_packet_size,max_concurrent_streams:$max_concurrent_streams,stream_receive_window:$stream_receive_window}') || return 1
}

prompt_hysteria_update() {
  local in_p answer server_name certificate_path key_path trust_choice edit_users tls_json obfs_choice quic_json
  tls_json=${SB_HYSTERIA_TLS_JSON:-'{"enabled":false}'}
  quic_json=${SB_HYSTERIA_QUIC_JSON:-'{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'}
  in_p=$(prompt_port '[Hysteria] 新端口 (当前值，留空保持): ' "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${SB_PORT}" ]]; then SB_PORT=${in_p}; check_port_conflict "${SB_PORT}"; fi
  edit_users=$(prompt_yes_no '[Hysteria] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_users}" == y ]]; then hysteria_prompt_users "${SB_HYSTERIA_AUTH_JSON:-[]}" || return 1; fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls_json}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls_json}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls_json}") || return 1
  read -rp "[Hysteria] TLS server name（当前 ${server_name}，留空保持）: " answer || return 1
  [[ -z "${answer}" ]] || server_name=$(trim_whitespace "${answer}")
  [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path "[Hysteria] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[Hysteria] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  SB_HYSTERIA_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[Hysteria] 客户端证书信任 [1=certificate,2=system]（默认保持）: ' 1 2 "$([[ "${SB_HYSTERIA_CLIENT_TRUST:-system}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && SB_HYSTERIA_CLIENT_TRUST=system || SB_HYSTERIA_CLIENT_TRUST=certificate
  SB_HYSTERIA_UP_MBPS=$(prompt_optional_positive_integer "[Hysteria] 上行带宽 Mbps（当前 ${SB_HYSTERIA_UP_MBPS:-100}）: " "${SB_HYSTERIA_UP_MBPS:-100}" "上行带宽") || return 1
  SB_HYSTERIA_DOWN_MBPS=$(prompt_optional_positive_integer "[Hysteria] 下行带宽 Mbps（当前 ${SB_HYSTERIA_DOWN_MBPS:-100}）: " "${SB_HYSTERIA_DOWN_MBPS:-100}" "下行带宽") || return 1
  obfs_choice=$(prompt_yes_no '[Hysteria] 是否启用 obfs [y/n]（当前保持）: ' "${SB_HYSTERIA_OBFS_ENABLED:-n}") || return 1
  SB_HYSTERIA_OBFS_ENABLED=${obfs_choice}
  if [[ "${obfs_choice}" == y ]]; then
    read -rsp '[Hysteria] obfs password（留空保持/自动生成）: ' answer || return 1; printf '\n' >&2
    [[ -z "${answer}" ]] || SB_HYSTERIA_OBFS_PASSWORD=${answer}
  else SB_HYSTERIA_OBFS_PASSWORD=""; fi
  hysteria_prompt_quic_options "${quic_json}" || return 1
  ensure_hysteria_materials
}

prompt_hysteria_install() {
  local answer server_name certificate_path key_path trust_choice
  set_protocol_defaults hysteria
  SB_NODE_NAME=$(default_instance_node_name "hysteria") || return 1
  echo -e '\n'"${BLUE}"'--- 配置 Hysteria ---'"${NC}" >&2
  SB_PORT=$(prompt_port '[Hysteria] 端口（默认当前值）: ' "${SB_PORT}") || return 1
  check_port_conflict "${SB_PORT}"
  hysteria_prompt_users '[]' || return 1
  read -rp '[Hysteria] TLS server name: ' answer || return 1
  server_name=$(trim_whitespace "${answer}"); [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path '[Hysteria] TLS 证书绝对路径: ') || return 1
  key_path=$(prompt_required_path '[Hysteria] TLS 私钥绝对路径: ') || return 1
  SB_HYSTERIA_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[Hysteria] 客户端证书信任 [1=certificate,2=system]（默认 2）: ' 1 2 2) || return 1
  [[ "${trust_choice}" == 2 ]] && SB_HYSTERIA_CLIENT_TRUST=system || SB_HYSTERIA_CLIENT_TRUST=certificate
  SB_HYSTERIA_UP_MBPS=$(prompt_optional_positive_integer '[Hysteria] 上行带宽 Mbps（默认 100）: ' 100 '上行带宽') || return 1
  SB_HYSTERIA_DOWN_MBPS=$(prompt_optional_positive_integer '[Hysteria] 下行带宽 Mbps（默认 100）: ' 100 '下行带宽') || return 1
  SB_HYSTERIA_OBFS_ENABLED=$(prompt_yes_no '[Hysteria] 是否启用 obfs [y/n]（默认 n）: ' n) || return 1
  if [[ "${SB_HYSTERIA_OBFS_ENABLED}" == y ]]; then
    read -rsp '[Hysteria] obfs password（留空自动生成）: ' answer || return 1; printf '\n' >&2
    SB_HYSTERIA_OBFS_PASSWORD=${answer}
  fi
  hysteria_prompt_quic_options "${SB_HYSTERIA_QUIC_JSON}" || return 1
  ensure_hysteria_materials
}

naive_prompt_users() {
  local current=${1:-} count i name username password old_name old_username old_password answer users='[]'
  [[ -n "${current}" ]] || current='[]'
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp '[NaiveProxy] 用户数量 (1-128，默认当前值): ' answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i=0; i<count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_username=$(jq -r --argjson i "${i}" '.[$i].username // empty' <<< "${current}") || return 1
    old_password=$(jq -j --argjson i "${i}" '.[$i].password // "", "\u0001"' <<< "${current}") || return 1
    old_password=${old_password%$'\1'}
    name=${old_name:-naive-user-$((i + 1))}
    read -rp "[NaiveProxy] 用户 $((i + 1)) 名称（默认 ${name}）: " answer || return 1
    [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
    [[ -n "${name}" ]] || return 1
    username=${old_username:-${name}}
    while true; do
      read -rp "[NaiveProxy] 用户 ${name} username（默认 ${username}）: " answer || return 1
      [[ -z "${answer}" ]] || username=$(trim_whitespace "${answer}")
      [[ -n "${username}" && "${username}" != *:* ]] && break
      log_warn '[NaiveProxy] username 不能为空且不能包含冒号。' >&2
    done
    read -rsp "[NaiveProxy] 用户 ${name} password（留空保持/自动生成）: " answer || return 1
    printf '\n' >&2
    password=${answer:-${old_password}}
    [[ -n "${password}" ]] || password=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg username "${username}" --arg password "${password}" '$users + [{name:$name,username:$username,password:$password}]') || return 1
  done
  SB_NAIVE_AUTH_JSON=${users}
}

naive_prompt_network() {
  local current=${1:-} choice
  [[ -n "${current}" ]] || current='["tcp","udp"]'
  choice=$(prompt_choice '[NaiveProxy] 网络 [1=tcp+udp,2=tcp,3=udp]（默认保持）: ' 1 3 "$([[ "${current}" == '["tcp","udp"]' ]] && printf 1 || [[ "${current}" == '["tcp"]' ]] && printf 2 || printf 3)") || return 1
  case "${choice}" in
    1) SB_NAIVE_NETWORK_JSON='["tcp","udp"]' ;;
    2) SB_NAIVE_NETWORK_JSON='["tcp"]' ;;
    3) SB_NAIVE_NETWORK_JSON='["udp"]' ;;
  esac
}

naive_prompt_options() {
  local current_cc=${1:-bbr} current_quic=${2:-n} current_concurrency=${3:-0}
  local current_stream=${4:-} current_session=${5:-} current_headers=${6:-} choice answer
  [[ -n "${current_headers}" ]] || current_headers='{}'
  choice=$(prompt_choice '[NaiveProxy] QUIC 拥塞控制 [1=bbr,2=cubic,3=reno]（默认保持）: ' 1 3 "$([[ "${current_cc}" == cubic ]] && printf 2 || [[ "${current_cc}" == reno ]] && printf 3 || printf 1)") || return 1
  case "${choice}" in 2) SB_NAIVE_QUIC_CONGESTION_CONTROL=cubic ;; 3) SB_NAIVE_QUIC_CONGESTION_CONTROL=reno ;; *) SB_NAIVE_QUIC_CONGESTION_CONTROL=bbr ;; esac
  SB_NAIVE_QUIC=$(prompt_yes_no "[NaiveProxy] 客户端是否启用 QUIC [y/n]（当前 ${current_quic}）: " "${current_quic}") || return 1
  SB_NAIVE_INSECURE_CONCURRENCY=$(prompt_optional_positive_integer "[NaiveProxy] insecure_concurrency（当前 ${current_concurrency}）: " "${current_concurrency}" "insecure_concurrency") || return 1
  read -rp "[NaiveProxy] stream_receive_window（当前 ${current_stream}，留空清除）: " answer || return 1
  [[ -z "${answer}" ]] || current_stream=$(trim_whitespace "${answer}")
  SB_NAIVE_STREAM_RECEIVE_WINDOW=${current_stream}
  read -rp "[NaiveProxy] quic_session_receive_window（当前 ${current_session}，留空清除）: " answer || return 1
  [[ -z "${answer}" ]] || current_session=$(trim_whitespace "${answer}")
  SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW=${current_session}
  read -rp '[NaiveProxy] extra_headers JSON（留空保持）: ' answer || return 1
  [[ -z "${answer}" ]] || current_headers=${answer}
  SB_NAIVE_EXTRA_HEADERS_JSON=${current_headers}
}

prompt_naive_update() {
  local in_p answer server_name certificate_path key_path trust_choice edit_users tls_json current_headers
  tls_json=${SB_NAIVE_TLS_JSON:-'{"enabled":false}'}
  in_p=$(prompt_port '[NaiveProxy] 新端口（当前值，留空保持）: ' "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${SB_PORT}" ]]; then SB_PORT=${in_p}; check_port_conflict "${SB_PORT}"; fi
  edit_users=$(prompt_yes_no '[NaiveProxy] 是否重新编辑用户凭据 [y/n]（默认 n）: ' n) || return 1
  if [[ "${edit_users}" == y ]]; then naive_prompt_users "${SB_NAIVE_AUTH_JSON:-[]}" || return 1; fi
  server_name=$(jq -r '.server_name // empty' <<< "${tls_json}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${tls_json}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${tls_json}") || return 1
  read -rp "[NaiveProxy] TLS server name（当前 ${server_name}，留空保持）: " answer || return 1; [[ -z "${answer}" ]] || server_name=$(trim_whitespace "${answer}")
  [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path "[NaiveProxy] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[NaiveProxy] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  SB_NAIVE_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[NaiveProxy] 客户端证书信任 [1=certificate,2=system]（默认保持）: ' 1 2 "$([[ "${SB_NAIVE_CLIENT_TRUST:-system}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && SB_NAIVE_CLIENT_TRUST=system || SB_NAIVE_CLIENT_TRUST=certificate
  naive_prompt_network "${SB_NAIVE_NETWORK_JSON:-[\"tcp\",\"udp\"]}" || return 1
  current_headers=${SB_NAIVE_EXTRA_HEADERS_JSON:-}
  [[ -n "${current_headers}" ]] || current_headers='{}'
  naive_prompt_options "${SB_NAIVE_QUIC_CONGESTION_CONTROL:-bbr}" "${SB_NAIVE_QUIC:-n}" "${SB_NAIVE_INSECURE_CONCURRENCY:-0}" "${SB_NAIVE_STREAM_RECEIVE_WINDOW:-}" "${SB_NAIVE_QUIC_SESSION_RECEIVE_WINDOW:-}" "${current_headers}" || return 1
  ensure_naive_materials
}

prompt_naive_install() {
  local answer server_name certificate_path key_path trust_choice
  set_protocol_defaults naive
  SB_NODE_NAME=$(default_instance_node_name "naive") || return 1
  echo -e '\n'"${BLUE}"'--- 配置 NaiveProxy ---'"${NC}" >&2
  SB_PORT=$(prompt_port '[NaiveProxy] 端口（默认当前值）: ' "${SB_PORT}") || return 1
  check_port_conflict "${SB_PORT}"
  naive_prompt_users '[]' || return 1
  read -rp '[NaiveProxy] TLS server name: ' answer || return 1; server_name=$(trim_whitespace "${answer}"); [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path '[NaiveProxy] TLS 证书绝对路径: ') || return 1
  key_path=$(prompt_required_path '[NaiveProxy] TLS 私钥绝对路径: ') || return 1
  SB_NAIVE_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[NaiveProxy] 客户端证书信任 [1=certificate,2=system]（默认 2）: ' 1 2 2) || return 1
  [[ "${trust_choice}" == 2 ]] && SB_NAIVE_CLIENT_TRUST=system || SB_NAIVE_CLIENT_TRUST=certificate
  naive_prompt_network "${SB_NAIVE_NETWORK_JSON}" || return 1
  naive_prompt_options bbr n 0 '' '' '{}' || return 1
  ensure_naive_materials
}

shadowtls_prompt_users() {
  local current=${1:-[]} count i name password old_name old_password answer users='[]'
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp '[ShadowTLS] 用户数量 (1-128，默认当前值): ' answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i = 0; i < count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_password=$(jq -r --argjson i "${i}" '.[$i].password // empty' <<< "${current}") || return 1
    name=${old_name:-shadowtls-user-$((i + 1))}
    read -rp "[ShadowTLS] 用户 $((i + 1)) 名称（默认 ${name}）: " answer || return 1
    [[ -z "${answer}" ]] || name=$(trim_whitespace "${answer}")
    [[ -n "${name}" ]] || return 1
    read -rsp "[ShadowTLS] 用户 ${name} password（留空保持/自动生成）: " answer || return 1
    printf '\n' >&2
    password=${answer:-${old_password}}
    [[ -n "${password}" ]] || password=$(trojan_generate_password) || return 1
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg password "${password}" '$users + [{name:$name,password:$password}]') || return 1
  done
  SB_SHADOWTLS_AUTH_JSON=${users}
}

shadowtls_prompt_handshake() {
  local current=${1:-'{"server":"","server_port":443}'} server port answer
  server=$(jq -r '.server // empty' <<< "${current}") || return 1
  port=$(jq -r '.server_port // 443' <<< "${current}") || return 1
  read -rp "[ShadowTLS] 握手服务器（当前 ${server}）: " answer || return 1
  [[ -z "${answer}" ]] || server=$(trim_whitespace "${answer}")
  [[ -n "${server}" ]] || return 1
  port=$(prompt_port "[ShadowTLS] 握手端口（当前 ${port}）: " "${port}") || return 1
  SB_SHADOWTLS_HANDSHAKE_JSON=$(jq -cn --arg server "${server}" --argjson port "${port}" '{server:$server,server_port:$port}') || return 1
}

shadowtls_prompt_handshake_map() {
  local current=${1:-} answer
  [[ -n "${current}" ]] || current='{}'
  read -rp '[ShadowTLS] 按 SNI 覆盖握手映射 JSON（留空保持当前）: ' answer || return 1
  [[ -z "${answer}" ]] || current=${answer}
  jq -e 'type == "object" and all(to_entries[]; (.key|type=="string" and length>0) and (.value|type=="object" and (.server|type=="string" and length>0) and (.server_port|type=="number" and floor==. and .>=1 and .<=65535)))' <<< "${current}" >/dev/null 2>&1 || return 1
  SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON=$(jq -cS . <<< "${current}") || return 1
}

shadowtls_prompt_client_tls() {
  local current=${1:-'{"server_name":"","certificate_path":""}'} trust=${2:-system} server_name certificate_path answer
  server_name=$(jq -r '.server_name // empty' <<< "${current}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${current}") || return 1
  read -rp "[ShadowTLS] 客户端 TLS server_name（当前 ${server_name}）: " answer || return 1
  [[ -z "${answer}" ]] || server_name=$(trim_whitespace "${answer}")
  [[ -n "${server_name}" ]] || return 1
  if [[ "${trust}" == certificate ]]; then
    certificate_path=$(prompt_required_path "[ShadowTLS] 客户端信任证书绝对路径: " "${certificate_path}") || return 1
  else
    certificate_path=""
  fi
  SB_SHADOWTLS_CLIENT_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path}') || return 1
}

shadowtls_prompt_version_and_auth() {
  local current=${1:-3} choice answer
  choice=$(prompt_choice '[ShadowTLS] 版本 [1/2/3]（默认保持）: ' 1 3 "${current}") || return 1
  SB_SHADOWTLS_VERSION=${choice}
  case "${choice}" in
    1) SB_SHADOWTLS_PASSWORD=""; SB_SHADOWTLS_AUTH_JSON='[]' ;;
    2)
      read -rsp '[ShadowTLS] v2 password（留空自动生成）: ' answer || return 1; printf '\n' >&2
      SB_SHADOWTLS_PASSWORD=${answer:-${SB_SHADOWTLS_PASSWORD:-$(trojan_generate_password)}}
      SB_SHADOWTLS_AUTH_JSON='[]'
      [[ -n "${SB_SHADOWTLS_PASSWORD}" ]] || return 1
      ;;
    3) shadowtls_prompt_users "${SB_SHADOWTLS_AUTH_JSON:-[]}" || return 1; SB_SHADOWTLS_PASSWORD="" ;;
    *) return 1 ;;
  esac
}

prompt_shadowtls_update() {
  local in_p answer choice current_version current_handshake current_map current_client_tls trust_choice detour_port
  in_p=$(prompt_port '[ShadowTLS] 新端口（当前值，留空保持）: ' "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${SB_PORT}" ]]; then SB_PORT=${in_p}; check_port_conflict "${SB_PORT}"; fi
  current_version=${SB_SHADOWTLS_VERSION:-3}
  shadowtls_prompt_version_and_auth "${current_version}" || return 1
  current_handshake=${SB_SHADOWTLS_HANDSHAKE_JSON:-}
  [[ -n "${current_handshake}" ]] || current_handshake='{"server":"","server_port":443}'
  shadowtls_prompt_handshake "${current_handshake}" || return 1
  current_map=${SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON:-}
  [[ -n "${current_map}" ]] || current_map='{}'
  if [[ "${SB_SHADOWTLS_VERSION}" -eq 1 ]]; then SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON='{}'; else shadowtls_prompt_handshake_map "${current_map}" || return 1; fi
  if [[ "${SB_SHADOWTLS_VERSION}" -eq 3 ]]; then
    SB_SHADOWTLS_STRICT_MODE=$(prompt_yes_no "[ShadowTLS] strict_mode [y/n]（当前 ${SB_SHADOWTLS_STRICT_MODE:-n}）: " "${SB_SHADOWTLS_STRICT_MODE:-n}") || return 1
    choice=$(prompt_choice '[ShadowTLS] wildcard_sni [1=off,2=authed,3=all]（默认保持）: ' 1 3 "$([[ "${SB_SHADOWTLS_WILDCARD_SNI:-off}" == authed ]] && printf 2 || [[ "${SB_SHADOWTLS_WILDCARD_SNI:-off}" == all ]] && printf 3 || printf 1)") || return 1
    case "${choice}" in 2) SB_SHADOWTLS_WILDCARD_SNI=authed ;; 3) SB_SHADOWTLS_WILDCARD_SNI=all ;; *) SB_SHADOWTLS_WILDCARD_SNI=off ;; esac
  else SB_SHADOWTLS_STRICT_MODE=n; SB_SHADOWTLS_WILDCARD_SNI=off; fi
  detour_port=$(prompt_port '[ShadowTLS] 私有内层端口（当前值，留空保持）: ' "${SB_SHADOWTLS_DETOUR_PORT}") || return 1
  [[ -n "${detour_port}" ]] && SB_SHADOWTLS_DETOUR_PORT=${detour_port}
  trust_choice=$(prompt_choice '[ShadowTLS] 客户端证书信任 [1=certificate,2=system]（默认保持）: ' 1 2 "$([[ "${SB_SHADOWTLS_CLIENT_TRUST:-system}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 1 ]] && SB_SHADOWTLS_CLIENT_TRUST=certificate || SB_SHADOWTLS_CLIENT_TRUST=system
  current_client_tls=${SB_SHADOWTLS_CLIENT_TLS_JSON:-}
  [[ -n "${current_client_tls}" ]] || current_client_tls='{"server_name":"","certificate_path":""}'
  shadowtls_prompt_client_tls "${current_client_tls}" "${SB_SHADOWTLS_CLIENT_TRUST}" || return 1
}

prompt_shadowtls_install() {
  local choice answer trust_choice
  set_protocol_defaults shadowtls
  SB_NODE_NAME=$(default_instance_node_name "shadowtls") || return 1
  echo -e '\n'"${BLUE}"'--- 配置 ShadowTLS ---'"${NC}" >&2
  SB_PORT=$(prompt_port '[ShadowTLS] 外层监听端口（默认当前值）: ' "${SB_PORT}") || return 1
  check_port_conflict "${SB_PORT}"
  shadowtls_prompt_version_and_auth 3 || return 1
  shadowtls_prompt_handshake "${SB_SHADOWTLS_HANDSHAKE_JSON}" || return 1
  if [[ "${SB_SHADOWTLS_VERSION}" -eq 1 ]]; then SB_SHADOWTLS_HANDSHAKE_FOR_SERVER_NAME_JSON='{}'; else shadowtls_prompt_handshake_map '{}' || return 1; fi
  if [[ "${SB_SHADOWTLS_VERSION}" -eq 3 ]]; then
    SB_SHADOWTLS_STRICT_MODE=$(prompt_yes_no '[ShadowTLS] strict_mode [y/n]（默认 n）: ' n) || return 1
    choice=$(prompt_choice '[ShadowTLS] wildcard_sni [1=off,2=authed,3=all]（默认 1）: ' 1 3 1) || return 1
    case "${choice}" in 2) SB_SHADOWTLS_WILDCARD_SNI=authed ;; 3) SB_SHADOWTLS_WILDCARD_SNI=all ;; *) SB_SHADOWTLS_WILDCARD_SNI=off ;; esac
  fi
  while [[ "${SB_SHADOWTLS_DETOUR_PORT}" == "${SB_PORT}" ]]; do SB_SHADOWTLS_DETOUR_PORT=$(pick_random_high_port) || return 1; done
  SB_SHADOWTLS_DETOUR_PORT=$(prompt_port '[ShadowTLS] 私有内层端口（默认当前值）: ' "${SB_SHADOWTLS_DETOUR_PORT}") || return 1
  check_port_conflict "${SB_SHADOWTLS_DETOUR_PORT}"
  trust_choice=$(prompt_choice '[ShadowTLS] 客户端证书信任 [1=certificate,2=system]（默认 2）: ' 1 2 2) || return 1
  [[ "${trust_choice}" == 1 ]] && SB_SHADOWTLS_CLIENT_TRUST=certificate || SB_SHADOWTLS_CLIENT_TRUST=system
  shadowtls_prompt_client_tls '{"server_name":"","certificate_path":""}' "${SB_SHADOWTLS_CLIENT_TRUST}" || return 1
}

prompt_tuic_update() {
  local in_p answer server_name certificate_path key_path trust_choice edit_users trust
  local old_tls=${SB_TUIC_TLS_JSON:-'{"enabled":false}'}
  in_p=$(prompt_port '[TUIC] 新端口 (当前值，留空保持): ' "${SB_PORT}") || return 1
  if [[ "${in_p}" != "${SB_PORT}" ]]; then SB_PORT=${in_p}; check_port_conflict "${SB_PORT}"; fi
  edit_users=$(prompt_yes_no '[TUIC] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_users}" == y ]]; then tuic_prompt_users "${SB_TUIC_AUTH_JSON:-[]}" || return 1; fi
  server_name=$(jq -r '.server_name // empty' <<< "${old_tls}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${old_tls}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${old_tls}") || return 1
  read -rp "[TUIC] TLS server name (当前 ${server_name}，留空保持): " answer || return 1
  [[ -z "${answer}" ]] || server_name=$(trim_whitespace "${answer}")
  [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path "[TUIC] TLS 证书绝对路径 (当前 ${certificate_path}): " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[TUIC] TLS 私钥绝对路径 (当前 ${key_path}): " "${key_path}") || return 1
  SB_TUIC_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust=${SB_TUIC_CLIENT_TRUST:-system}
  trust_choice=$(prompt_choice '[TUIC] 客户端证书信任 [1=certificate,2=system] (默认保持): ' 1 2 "$([[ "${trust}" == system ]] && printf 2 || printf 1)") || return 1
  [[ "${trust_choice}" == 2 ]] && SB_TUIC_CLIENT_TRUST=system || SB_TUIC_CLIENT_TRUST=certificate
  tuic_prompt_options "${SB_TUIC_CONGESTION_CONTROL:-bbr}" "${SB_TUIC_AUTH_TIMEOUT_SECONDS:-3}" "${SB_TUIC_HEARTBEAT_SECONDS:-10}" "${SB_TUIC_ZERO_RTT_HANDSHAKE:-n}" "${SB_TUIC_UDP_RELAY_MODE:-native}" "${SB_TUIC_UDP_OVER_STREAM:-n}" || return 1
  ensure_tuic_materials
}

prompt_tuic_install() {
  local answer server_name certificate_path key_path trust_choice
  set_protocol_defaults tuic
  SB_NODE_NAME=$(default_instance_node_name "tuic") || return 1
  SB_PORT=$(prompt_port '[TUIC] 端口 (默认当前值): ' "${SB_PORT}") || return 1
  check_port_conflict "${SB_PORT}"
  tuic_prompt_users '[]' || return 1
  while [[ -z "${server_name:-}" ]]; do
    read -rp '[TUIC] TLS server name: ' answer || return 1
    server_name=$(trim_whitespace "${answer}")
  done
  certificate_path=$(prompt_required_path '[TUIC] TLS 证书绝对路径: ') || return 1
  key_path=$(prompt_required_path '[TUIC] TLS 私钥绝对路径: ') || return 1
  SB_TUIC_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[TUIC] 客户端证书信任 [1=certificate,2=system] (默认 2): ' 1 2 2) || return 1
  [[ "${trust_choice}" == 2 ]] && SB_TUIC_CLIENT_TRUST=system || SB_TUIC_CLIENT_TRUST=certificate
  tuic_prompt_options bbr 3 10 n native n || return 1
  ensure_tuic_materials
}

trojan_prompt_transport() {
  local choice path service transport='{"type":"none"}'
  echo 'Trojan 传输:' >&2
  echo '1. TCP' >&2; echo '2. HTTP' >&2; echo '3. WebSocket' >&2; echo '4. gRPC' >&2; echo '5. QUIC' >&2
  choice=$(prompt_choice '[Trojan] 请选择传输 [1-5] (默认 1): ' 1 5 1) || return 1
  case "${choice}" in
    1) transport='{"type":"none"}' ;;
    2) read -rp '[Trojan] HTTP path (可留空): ' path || return 1; transport=$(jq -cn --arg path "${path}" '{type:"http"} + (if $path != "" then {path:$path} else {} end)') || return 1 ;;
    3) read -rp '[Trojan] WebSocket path (默认 /): ' path || return 1; path=${path:-/}; transport=$(jq -cn --arg path "${path}" '{type:"ws",path:$path}') || return 1 ;;
    4) read -rp '[Trojan] gRPC service name (可留空): ' service || return 1; transport=$(jq -cn --arg service "${service}" '{type:"grpc"} + (if $service != "" then {service_name:$service} else {} end)') || return 1 ;;
    5) transport='{"type":"quic"}' ;;
  esac
  SB_TROJAN_TRANSPORT_JSON=${transport}
}

prompt_trojan_install() {
  local tls_choice trust_choice cert_path key_path
  set_protocol_defaults trojan
  SB_NODE_NAME=$(default_instance_node_name "trojan") || return 1
  echo -e '\n'"${BLUE}"'--- 配置 Trojan ---'"${NC}" >&2
  SB_PORT=$(prompt_port '[Trojan] 端口 (默认当前值): ' "${SB_PORT}") || return 1
  trojan_prompt_users '[]' || return 1
  tls_choice=$(prompt_yes_no '[Trojan] 是否启用 TLS [y/n] (默认 y): ' y) || return 1
  if [[ "${tls_choice}" == y ]]; then
    cert_path=$(prompt_required_path '[Trojan] 证书绝对路径: ') || return 1
    key_path=$(prompt_required_path '[Trojan] 私钥绝对路径: ') || return 1
    SB_TROJAN_TLS_JSON=$(jq -cn --arg certificate_path "${cert_path}" --arg key_path "${key_path}" '{enabled:true,server_name:"",certificate_path:$certificate_path,key_path:$key_path}') || return 1
    while [[ -z "$(jq -r '.server_name' <<< "${SB_TROJAN_TLS_JSON}")" ]]; do
      read -rp '[Trojan] TLS server name: ' cert_path || return 1
      SB_TROJAN_TLS_JSON=$(jq -cn --arg server_name "${cert_path}" --argjson tls "${SB_TROJAN_TLS_JSON}" '$tls + {server_name:$server_name}') || return 1
    done
    echo '客户端证书信任方式: 1. 固定证书  2. 系统信任' >&2
    trust_choice=$(prompt_choice '[Trojan] 请选择 [1-2] (默认 1): ' 1 2 1) || return 1
    if [[ "${trust_choice}" == 2 ]]; then
      SB_TROJAN_CLIENT_TRUST=system
      log_warn '系统信任模式要求客户端系统信任该公网证书；不嵌入固定证书。' >&2
    else SB_TROJAN_CLIENT_TRUST=certificate; fi
  else
    SB_TROJAN_TLS_JSON='{"enabled":false}'
    SB_TROJAN_CLIENT_TRUST=system
    log_warn '未启用 TLS，认证摘要和业务流量未受 TLS 保护，存在窃听/重放风险；请确认访问范围。' >&2
  fi
  trojan_prompt_transport || return 1
}

prompt_trojan_update() {
  local tls_choice trust_choice edit_users edit_transport old_users old_tls old_transport old_trust answer
  old_users=${SB_TROJAN_AUTH_JSON:-[]}; old_tls=${SB_TROJAN_TLS_JSON:-'{"enabled":false}'}
  old_transport=${SB_TROJAN_TRANSPORT_JSON:-'{"type":"none"}'}; old_trust=${SB_TROJAN_CLIENT_TRUST:-system}
  SB_PORT=$(prompt_port '[Trojan] 新端口 (当前值，留空保持): ' "${SB_PORT}") || return 1
  edit_users=$(prompt_yes_no '[Trojan] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_users}" == y ]]; then trojan_prompt_users "${old_users}" || return 1; else SB_TROJAN_AUTH_JSON=${old_users}; fi
  tls_choice=$(prompt_yes_no '[Trojan] 是否启用 TLS [y/n] (默认保持当前): ' "$(jq -r '.enabled // false' <<< "${old_tls}" | sed 's/true/y/;s/false/n/')") || return 1
  if [[ "${tls_choice}" == y ]]; then
    local server_name certificate_path key_path
    server_name=$(jq -r '.server_name // empty' <<< "${old_tls}"); certificate_path=$(jq -r '.certificate_path // empty' <<< "${old_tls}"); key_path=$(jq -r '.key_path // empty' <<< "${old_tls}")
    read -rp "TLS server name (当前 ${server_name}，留空保持): " answer || return 1; [[ -z "${answer}" ]] || server_name=${answer}
    [[ -n "${server_name}" ]] || return 1
    read -rp "TLS 证书路径 (当前 ${certificate_path}，留空保持): " answer || return 1; [[ -z "${answer}" ]] || certificate_path=${answer}
    read -rp "TLS 私钥路径 (当前 ${key_path}，留空保持): " answer || return 1; [[ -z "${answer}" ]] || key_path=${answer}
    SB_TROJAN_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
    trust_choice=$(prompt_choice '[Trojan] 客户端信任 [1=certificate,2=system] (默认保持): ' 1 2 "$([[ "${old_trust}" == system ]] && printf 2 || printf 1)") || return 1
    [[ "${trust_choice}" == 2 ]] && SB_TROJAN_CLIENT_TRUST=system || SB_TROJAN_CLIENT_TRUST=certificate
  else SB_TROJAN_TLS_JSON='{"enabled":false}'; SB_TROJAN_CLIENT_TRUST=system; fi
  SB_TROJAN_TRANSPORT_JSON=${old_transport}
  edit_transport=$(prompt_yes_no '[Trojan] 是否编辑传输 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_transport}" == y ]]; then trojan_prompt_transport || return 1; fi
}

vmess_generate_uuid() {
  local value
  value=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid) || return 1
  [[ "${value}" =~ ^[0-9a-fA-F-]{36}$ ]] || return 1
  printf '%s' "${value,,}"
}

vmess_prompt_users() {
  local current=${1:-'[]'} count i name uuid alter_id security old_name old_uuid old_alter old_security users='[]' answer
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp '[VMess] 用户数量 (1-128，默认当前值): ' answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i = 0; i < count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_uuid=$(jq -r --argjson i "${i}" '.[$i].uuid // empty' <<< "${current}") || return 1
    old_alter=$(jq -r --argjson i "${i}" '.[$i].alter_id // 0' <<< "${current}") || return 1
    old_security=$(jq -r --argjson i "${i}" '.[$i].security // "auto"' <<< "${current}") || return 1
    name=${old_name:-vmess-user-$((i + 1))}
    read -rp "[VMess] 用户 $((i + 1)) 名称 (默认 ${name}): " answer || return 1
    [[ -z "${answer}" ]] || name=${answer}
    uuid=${old_uuid}
    while true; do
      read -rp "[VMess] 用户 ${name} UUID (留空自动生成): " answer || return 1
      [[ -z "${answer}" ]] && answer=${uuid}
      [[ -n "${answer}" ]] || answer=$(vmess_generate_uuid) || return 1
      if [[ "${answer}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then uuid=${answer,,}; break; fi
      log_warn '[VMess] UUID 格式无效，请输入标准 UUID。' >&2
      uuid=""
    done
    read -rp "[VMess] 用户 ${name} alterId (默认 ${old_alter}，建议 0): " answer || return 1
    alter_id=${answer:-${old_alter:-0}}
    [[ "${alter_id}" =~ ^[0-9]+$ ]] && (( alter_id <= 65535 )) || return 1
    read -rp "[VMess] 用户 ${name} security [auto/none/zero/aes-128-cfb/aes-128-gcm/chacha20-poly1305] (默认 ${old_security}): " answer || return 1
    security=${answer:-${old_security:-auto}}
    case "${security}" in auto|none|zero|aes-128-cfb|aes-128-gcm|chacha20-poly1305) ;; *) return 1 ;; esac
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg uuid "${uuid}" --argjson alter_id "${alter_id}" --arg security "${security}" '$users + [{name:$name,uuid:$uuid,alter_id:$alter_id,security:$security}]') || return 1
  done
  SB_VMESS_AUTH_JSON=${users}
}

vmess_prompt_transport() {
  local choice path service transport='{"type":"none"}'
  echo 'VMess 传输:' >&2
  echo '1. TCP' >&2; echo '2. HTTP' >&2; echo '3. WebSocket' >&2; echo '4. gRPC' >&2; echo '5. QUIC' >&2
  choice=$(prompt_choice '[VMess] 请选择传输 [1-5] (默认 1): ' 1 5 1) || return 1
  case "${choice}" in
    1) transport='{"type":"none"}' ;;
    2) read -rp '[VMess] HTTP path (可留空): ' path || return 1; transport=$(jq -cn --arg path "${path}" '{type:"http"} + (if $path != "" then {path:$path} else {} end)') || return 1 ;;
    3) read -rp '[VMess] WebSocket path (默认 /): ' path || return 1; path=${path:-/}; transport=$(jq -cn --arg path "${path}" '{type:"ws",path:$path}') || return 1 ;;
    4) read -rp '[VMess] gRPC service name (可留空): ' service || return 1; transport=$(jq -cn --arg service "${service}" '{type:"grpc"} + (if $service != "" then {service_name:$service} else {} end)') || return 1 ;;
    5) transport='{"type":"quic"}' ;;
  esac
  SB_VMESS_TRANSPORT_JSON=${transport}
}

vmess_prompt_tls() {
  local current=${1:-'{"enabled":false}'} enabled server_name certificate_path key_path trust_choice answer
  enabled=$(jq -r 'if .enabled == true then "y" else "n" end' <<< "${current}") || return 1
  enabled=$(prompt_yes_no '[VMess] 是否启用 TLS [y/n] (默认保持当前): ' "${enabled}") || return 1
  if [[ "${enabled}" == n ]]; then
    SB_VMESS_TLS_JSON='{"enabled":false}'
    SB_VMESS_CLIENT_TRUST=system
    return 0
  fi
  server_name=$(jq -r '.server_name // empty' <<< "${current}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${current}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${current}") || return 1
  read -rp "[VMess] TLS server name (当前 ${server_name}): " answer || return 1; [[ -z "${answer}" ]] || server_name=${answer}
  [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path "[VMess] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[VMess] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  SB_VMESS_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[VMess] 客户端证书信任 [1=certificate,2=system] (默认 1): ' 1 2 1) || return 1
  [[ "${trust_choice}" == 2 ]] && SB_VMESS_CLIENT_TRUST=system || SB_VMESS_CLIENT_TRUST=certificate
}

vless_plain_generate_uuid() {
  local value
  value=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid) || return 1
  [[ "${value}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]] || return 1
  printf '%s' "${value,,}"
}

vless_plain_prompt_users() {
  local current=${1:-'[]'} count i name uuid flow old_name old_uuid old_flow users='[]' answer
  count=$(jq -r 'length' <<< "${current}" 2>/dev/null || printf 0)
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || count=1
  read -rp '[VLESS] 用户数量 (1-128，默认当前值): ' answer || return 1
  [[ -z "${answer}" ]] || count=${answer}
  [[ "${count}" =~ ^[1-9][0-9]{0,2}$ && "${count}" -le 128 ]] || return 1
  for ((i = 0; i < count; i++)); do
    old_name=$(jq -r --argjson i "${i}" '.[$i].name // empty' <<< "${current}") || return 1
    old_uuid=$(jq -r --argjson i "${i}" '.[$i].uuid // empty' <<< "${current}") || return 1
    old_flow=$(jq -r --argjson i "${i}" '.[$i].flow // ""' <<< "${current}") || return 1
    name=${old_name:-vless-user-$((i + 1))}
    read -rp "[VLESS] 用户 $((i + 1)) 名称 (默认 ${name}): " answer || return 1
    [[ -z "${answer}" ]] || name=${answer}
    uuid=${old_uuid}
    while true; do
      read -rp "[VLESS] 用户 ${name} UUID (留空自动生成): " answer || return 1
      [[ -z "${answer}" ]] && answer=${uuid}
      [[ -n "${answer}" ]] || answer=$(vless_plain_generate_uuid) || return 1
      if [[ "${answer}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then uuid=${answer,,}; break; fi
      log_warn '[VLESS] UUID 格式无效，请输入标准 UUID。' >&2
      uuid=""
    done
    flow=${old_flow}
    read -rp "[VLESS] 用户 ${name} flow [留空/xtls-rprx-vision] (默认 ${flow:-留空}): " answer || return 1
    [[ -z "${answer}" ]] || flow=$(trim_whitespace "${answer}")
    case "${flow}" in ""|xtls-rprx-vision) ;; *) return 1 ;; esac
    users=$(jq -cn --argjson users "${users}" --arg name "${name}" --arg uuid "${uuid}" --arg flow "${flow}" '$users + [{name:$name,uuid:$uuid,flow:$flow}]') || return 1
  done
  SB_VLESS_PLAIN_AUTH_JSON=${users}
}

vless_plain_prompt_transport() {
  local choice path service transport='{"type":"none"}'
  echo 'VLESS 传输:' >&2
  echo '1. TCP' >&2; echo '2. HTTP' >&2; echo '3. WebSocket' >&2; echo '4. gRPC' >&2; echo '5. QUIC' >&2
  choice=$(prompt_choice '[VLESS] 请选择传输 [1-5] (默认 1): ' 1 5 1) || return 1
  case "${choice}" in
    1) transport='{"type":"none"}' ;;
    2) read -rp '[VLESS] HTTP path (可留空): ' path || return 1; transport=$(jq -cn --arg path "${path}" '{type:"http"} + (if $path != "" then {path:$path} else {} end)') || return 1 ;;
    3) read -rp '[VLESS] WebSocket path (默认 /): ' path || return 1; path=${path:-/}; transport=$(jq -cn --arg path "${path}" '{type:"ws",path:$path}') || return 1 ;;
    4) read -rp '[VLESS] gRPC service name (可留空): ' service || return 1; transport=$(jq -cn --arg service "${service}" '{type:"grpc"} + (if $service != "" then {service_name:$service} else {} end)') || return 1 ;;
    5) transport='{"type":"quic"}' ;;
  esac
  SB_VLESS_PLAIN_TRANSPORT_JSON=${transport}
}

vless_plain_prompt_tls() {
  local current=${1:-'{"enabled":false}'} enabled server_name certificate_path key_path trust_choice answer
  enabled=$(jq -r 'if .enabled == true then "y" else "n" end' <<< "${current}") || return 1
  enabled=$(prompt_yes_no '[VLESS] 是否启用 TLS [y/n] (默认保持当前): ' "${enabled}") || return 1
  if [[ "${enabled}" == n ]]; then
    SB_VLESS_PLAIN_TLS_JSON='{"enabled":false}'
    SB_VLESS_PLAIN_CLIENT_TRUST=system
    return 0
  fi
  server_name=$(jq -r '.server_name // empty' <<< "${current}") || return 1
  certificate_path=$(jq -r '.certificate_path // empty' <<< "${current}") || return 1
  key_path=$(jq -r '.key_path // empty' <<< "${current}") || return 1
  read -rp "[VLESS] TLS server name (当前 ${server_name}): " answer || return 1; [[ -z "${answer}" ]] || server_name=${answer}
  [[ -n "${server_name}" ]] || return 1
  certificate_path=$(prompt_required_path "[VLESS] TLS 证书绝对路径（当前 ${certificate_path}）: " "${certificate_path}") || return 1
  key_path=$(prompt_required_path "[VLESS] TLS 私钥绝对路径（当前 ${key_path}）: " "${key_path}") || return 1
  SB_VLESS_PLAIN_TLS_JSON=$(jq -cn --arg server_name "${server_name}" --arg certificate_path "${certificate_path}" --arg key_path "${key_path}" '{enabled:true,server_name:$server_name,certificate_path:$certificate_path,key_path:$key_path}') || return 1
  trust_choice=$(prompt_choice '[VLESS] 客户端证书信任 [1=certificate,2=system] (默认 1): ' 1 2 1) || return 1
  [[ "${trust_choice}" == 2 ]] && SB_VLESS_PLAIN_CLIENT_TRUST=system || SB_VLESS_PLAIN_CLIENT_TRUST=certificate
}

prompt_vless_plain_install() {
  set_protocol_defaults vless-plain
  SB_NODE_NAME=$(default_instance_node_name "vless-plain") || return 1
  echo -e '\n'"${BLUE}"'--- 配置普通 VLESS ---'"${NC}" >&2
  SB_PORT=$(prompt_port '[VLESS] 端口 (默认当前值): ' "${SB_PORT}") || return 1
  vless_plain_prompt_users '[]' || return 1
  vless_plain_prompt_tls '{"enabled":false}' || return 1
  vless_plain_prompt_transport || return 1
}

prompt_vless_plain_update() {
  local old_users=${SB_VLESS_PLAIN_AUTH_JSON:-'[]'} old_tls=${SB_VLESS_PLAIN_TLS_JSON:-'{"enabled":false}'} edit_users edit_transport
  SB_PORT=$(prompt_port '[VLESS] 新端口 (当前值，留空保持): ' "${SB_PORT}") || return 1
  edit_users=$(prompt_yes_no '[VLESS] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_users}" == y ]]; then vless_plain_prompt_users "${old_users}" || return 1; else SB_VLESS_PLAIN_AUTH_JSON=${old_users}; fi
  vless_plain_prompt_tls "${old_tls}" || return 1
  SB_VLESS_PLAIN_TRANSPORT_JSON=${SB_VLESS_PLAIN_TRANSPORT_JSON:-'{"type":"none"}'}
  edit_transport=$(prompt_yes_no '[VLESS] 是否编辑传输 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_transport}" == y ]]; then vless_plain_prompt_transport || return 1; fi
}

prompt_vmess_install() {
  set_protocol_defaults vmess
  SB_NODE_NAME=$(default_instance_node_name "vmess") || return 1
  echo -e '\n'"${BLUE}"'--- 配置 VMess ---'"${NC}" >&2
  SB_PORT=$(prompt_port '[VMess] 端口 (默认当前值): ' "${SB_PORT}") || return 1
  vmess_prompt_users '[]' || return 1
  vmess_prompt_tls '{"enabled":false}' || return 1
  vmess_prompt_transport || return 1
}

prompt_vmess_update() {
  local old_users=${SB_VMESS_AUTH_JSON:-'[]'} old_tls=${SB_VMESS_TLS_JSON:-'{"enabled":false}'} edit_users edit_transport
  SB_PORT=$(prompt_port '[VMess] 新端口 (当前值，留空保持): ' "${SB_PORT}") || return 1
  edit_users=$(prompt_yes_no '[VMess] 是否重新编辑用户凭据 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_users}" == y ]]; then vmess_prompt_users "${old_users}" || return 1; else SB_VMESS_AUTH_JSON=${old_users}; fi
  vmess_prompt_tls "${old_tls}" || return 1
  SB_VMESS_TRANSPORT_JSON=${SB_VMESS_TRANSPORT_JSON:-'{"type":"none"}'}
  edit_transport=$(prompt_yes_no '[VMess] 是否编辑传输 [y/n] (默认 n): ' n) || return 1
  if [[ "${edit_transport}" == y ]]; then vmess_prompt_transport || return 1; fi
}

open_all_protocol_ports() {
  local plan owned_plan entries protocol port transport
  plan=$(managed_listener_plan "${SINGBOX_CONFIG_FILE}") || return $?
  owned_plan=$(filter_owned_firewall_plan_json "${plan}") || return $?
  if [[ "${owned_plan}" != "${plan}" ]]; then
    # Coexisting listeners require address-scoped rules; a coarse port allow
    # could otherwise expose an unowned listener on another local address.
    run_with_progress "同步托管监听的防火墙规则" open_scoped_protocol_ports
    return $?
  fi
  plan=$(instance_firewall_targets_json "${owned_plan}") || return $?
  entries=$(jq -r 'unique_by([.protocol,.port,.transport])[] | [.protocol,.port,.transport] | @tsv' <<< "${plan}") || return $?
  while IFS=$'\t' read -r protocol port transport; do
    [[ -n "${protocol}" ]] || continue
    open_firewall_port "${port}" "${protocol}" "${transport}" || return $?
  done <<< "${entries}"
}

open_committed_protocol_ports() {
  local status
  if open_all_protocol_ports; then return 0; else status=$?; fi
  printf '[ERROR] protocol_apply: config_committed; firewall_may_be_partial; service_restart_not_attempted; inspect_service_manually\n' >&2
  return "${status}"
}

protocol_array_contains() {
  local target=$1
  shift || true

  local item
  for item in "$@"; do
    [[ "${item}" == "${target}" ]] && return 0
  done

  return 1
}

protocol_option_to_id() {
  local record
  local fields=()
  for record in "${SB_PROTOCOL_REGISTRY[@]}"; do
    IFS='|' read -r -a fields <<< "${record}"
    if [[ "$1" == "${fields[9]}" ]]; then
      printf '%s' "${fields[0]}"
      return 0
    fi
  done
  return 1
}

protocol_install_menu_option_to_id() {
  # UI groups the two VLESS presets without changing registry/Agent IDs.
  case "$1" in
    1) printf '%s' vless ;;
    [2-9]) protocol_option_to_id "$1" ;;
    10|11|12|13|14) protocol_option_to_id "$(( $1 + 1 ))" ;;
    *) return 1 ;;
  esac
}

protocol_install_allows_additional_instance() {
  case "$1" in
    vless-reality|mixed|socks|vless-plain|anytls|hy2|snell|tuic|hysteria|naive|shadowtls) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_vless_install_selection() {
  local plain_available=${1:-y} choice

  SELECTED_VLESS_INSTALL_PROTOCOL=""
  echo -e "\n${BLUE}--- VLESS ---${NC}"
  echo '1. VLESS + REALITY'
  [[ "${plain_available}" != y ]] || echo '2. 普通 VLESS'
  echo '0. 返回上一级'
  while true; do
    read -rp '请选择 VLESS 类型 (默认 1): ' choice || return 1
    choice=$(trim_whitespace "${choice}")
    case "${choice:-1}" in
      0) return 1 ;;
      1) SELECTED_VLESS_INSTALL_PROTOCOL=vless-reality; return 0 ;;
      2)
        if [[ "${plain_available}" == y ]]; then
          SELECTED_VLESS_INSTALL_PROTOCOL=vless-plain
          return 0
        fi
        ;;
    esac
    log_warn '请选择菜单中列出的 VLESS 类型。'
  done
}

prompt_protocol_install_selection() {
  local install_mode=${1:-additional}
  local installed_protocols=() selected_protocols=() raw_choices=()
  local choice raw_choice protocol index installed_list vless_selection="" plain_available=y

  SELECTED_PROTOCOLS_CSV=""

  if [[ "${install_mode}" != fresh ]]; then
    # Only active inventory is installed. Empty retained stores keep their
    # revision for recreation, but must not become installed menu entries.
    if [[ $# -ge 2 ]]; then
      installed_list=$2
    else
      installed_list=$(list_installed_protocols) || return 1
    fi
    if [[ -n "${installed_list}" ]]; then
      mapfile -t installed_protocols <<< "${installed_list}"
    fi
  fi
  if protocol_array_contains vless-plain ${installed_protocols[@]+"${installed_protocols[@]}"}; then
    plain_available=n
  fi

  echo -e "\n${BLUE}--- 协议安装 ---${NC}"
  if [[ ${#installed_protocols[@]} -gt 0 ]]; then
    echo '当前已安装协议:'
    for protocol in "${installed_protocols[@]}"; do
      echo "- $(protocol_display_name "${protocol}")"
    done
  else
    echo '当前已安装协议: 无'
  fi

  echo '可安装协议:'
  for index in {1..14}; do
    protocol=$(protocol_install_menu_option_to_id "${index}") || return 1
    if [[ "${protocol}" == vless ]]; then
      echo "${index}. VLESS"
    elif ! protocol_array_contains "${protocol}" ${installed_protocols[@]+"${installed_protocols[@]}"}; then
      echo "${index}. $(protocol_display_name "${protocol}")"
    fi
  done

  echo '0. 返回上一级'
  echo '留空则安装全部可用协议。'
  read -rp '请选择一个或多个协议 [1-14]，逗号分隔: ' choice || return 1
  choice=$(trim_whitespace "${choice}")
  [[ "${choice}" != 0 ]] || return 1

  if [[ -z "${choice}" ]]; then
    # Preserve the registry order and the original all-protocol selection;
    # the VLESS family expands to both presets without a second prompt.
    while IFS= read -r protocol; do
      if protocol_array_contains "${protocol}" ${installed_protocols[@]+"${installed_protocols[@]}"}; then
        if [[ "${install_mode}" == additional ]] && protocol_install_allows_additional_instance "${protocol}"; then
          selected_protocols+=("${protocol}")
        fi
      else
        selected_protocols+=("${protocol}")
      fi
    done < <(list_registered_protocols)
  else
    IFS=',' read -r -a raw_choices <<< "${choice}"
    for raw_choice in "${raw_choices[@]}"; do
      raw_choice=$(trim_whitespace "${raw_choice}")
      [[ -n "${raw_choice}" ]] || continue
      protocol=$(protocol_install_menu_option_to_id "${raw_choice}") || {
        log_warn "跳过无效协议选项: ${raw_choice}"
        continue
      }
      if [[ "${protocol}" == vless ]]; then
        if [[ -z "${vless_selection}" ]]; then
          # Cancellation also discards earlier selections in a multi-select.
          prompt_vless_install_selection "${plain_available}" || return 1
          vless_selection=${SELECTED_VLESS_INSTALL_PROTOCOL}
        fi
        protocol=${vless_selection}
      fi
      if protocol_array_contains "${protocol}" ${installed_protocols[@]+"${installed_protocols[@]}"}; then
        if [[ "${install_mode}" != additional ]] || ! protocol_install_allows_additional_instance "${protocol}"; then
          log_warn "协议已安装，跳过: $(protocol_display_name "${protocol}")"
          continue
        fi
      fi
      if ! protocol_array_contains "${protocol}" ${selected_protocols[@]+"${selected_protocols[@]}"}; then
        selected_protocols+=("${protocol}")
      fi
    done
  fi

  if [[ ${#selected_protocols[@]} -eq 0 ]]; then
    log_error '未选择任何可安装协议。'
  fi

  SELECTED_PROTOCOLS_CSV=$(IFS=,; printf '%s' "${selected_protocols[*]}")
  return 0
}

prompt_vless_reality_install() {
  local in_node in_p

  set_protocol_defaults "vless+reality"
  SB_VLESS_INSTANCE_ID="main"
  SB_VLESS_INBOUND_TAG=""
  SB_NODE_NAME=$(default_instance_node_name vless-reality) || return 1
  echo -e "\n${BLUE}--- 配置 VLESS + REALITY ---${NC}"
  read -rp "[VLESS + REALITY] 节点名称 (默认 ${SB_NODE_NAME}): " in_node
  in_node=$(trim_whitespace "${in_node:-}")
  [[ -n "${in_node}" ]] && SB_NODE_NAME="${in_node}"

  SB_PORT=$(prompt_port "[VLESS + REALITY] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  prompt_reality_sni_install || return 1
  prompt_vless_reality_rate_limit_fields || return 1
  prompt_vless_reality_advanced_update_fields || return 1
  validate_current_reality_sni_alpn_or_warn
  SB_OUTBOUND_POLICY="default"
  return 0
}

vless_reality_naming_snapshot() {
  local ids instance_id name snapshot='{"instances":[]}'
  ids=$(list_vless_reality_instance_ids) || return 1
  while IFS= read -r instance_id; do
    [[ -n "${instance_id}" ]] || continue
    name=$(load_vless_reality_instance_state "${instance_id}" && printf '%s' "${SB_NODE_NAME}") || return 1
    snapshot=$(jq -c --arg id "${instance_id}" --arg name "${name}" \
      '.instances += [{id:$id,name:$name}]' <<< "${snapshot}") || return 1
  done <<< "${ids}"
  printf '%s' "${snapshot}"
}

prompt_vless_reality_instance_create() {
  local in_id in_node in_port default_id default_sni selected_id selected_node selected_port naming_snapshot

  migrate_vless_reality_state_to_instances_if_needed
  load_vless_reality_protocol_state
  default_id="reality-$(date +%H%M%S)"

  while true; do
    read -rp "[VLESS + REALITY] 新实例 ID (默认 ${default_id}): " in_id
    SB_VLESS_INSTANCE_ID=$(trim_whitespace "${in_id:-${default_id}}")
    if ! validate_vless_reality_instance_id "${SB_VLESS_INSTANCE_ID}"; then
      log_warn "实例 ID 只能包含小写字母、数字和短横线。"
      continue
    fi
    if vless_reality_instance_id_exists "${SB_VLESS_INSTANCE_ID}"; then
      log_warn "实例 ID 已存在: ${SB_VLESS_INSTANCE_ID}"
      continue
    fi
    break
  done
  selected_id="${SB_VLESS_INSTANCE_ID}"

  naming_snapshot=$(vless_reality_naming_snapshot) || return 1
  SB_NODE_NAME=$(default_instance_node_name vless-reality "${naming_snapshot}") || return 1
  read -rp "[VLESS + REALITY] 节点名称 (默认 ${SB_NODE_NAME}): " in_node
  SB_NODE_NAME=$(trim_whitespace "${in_node:-${SB_NODE_NAME}}")
  selected_node="${SB_NODE_NAME}"

  while true; do
    SB_PORT=$(prompt_port "[VLESS + REALITY] 端口: " "")
    port_in_configured_protocol_state "${SB_PORT}" && { log_warn "端口已被现有协议配置占用: ${SB_PORT}"; continue; }
    check_port_conflict "${SB_PORT}"
    break
  done
  selected_port="${SB_PORT}"

  default_sni=""
  if load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" 2>/dev/null; then
    default_sni="${SB_SNI}"
  fi
  SB_VLESS_INSTANCE_ID="${selected_id}"
  SB_VLESS_INBOUND_TAG=""
  SB_NODE_NAME="${selected_node}"
  SB_PORT="${selected_port}"
  prompt_reality_sni_for_new_instance "${default_sni}" || return 1

  SB_UUID=""
  SB_SHORT_ID_1=""
  SB_SHORT_ID_2=""
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
  SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="y"
  prompt_vless_reality_rate_limit_fields || return 1
  prompt_vless_reality_advanced_update_fields || return 1
  validate_current_reality_sni_alpn_or_warn
  # Loading the default instance above also loads its routing override. A new
  # instance always inherits global rules instead of copying that override.
  SB_OUTBOUND_POLICY="default"
  if vless_reality_bandwidth_profile_exists "${SB_VLESS_RATE_LIMIT_UP_MBPS}" "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" "${SB_VLESS_INSTANCE_ID}"; then
    log_warn "已存在相同类型且带宽配置完全相同的 VLESS + REALITY 节点，已取消创建。"
    return 0
  fi
  ensure_vless_reality_materials
  append_vless_reality_instance_id "${SB_VLESS_INSTANCE_ID}"
  save_vless_reality_protocol_state
  save_vless_reality_instance_state
}

prompt_mixed_install() {
  local in_p in_auth in_user in_pass

  set_protocol_defaults "mixed"
  SB_NODE_NAME=$(default_instance_node_name "mixed") || return 1
  echo -e "\n${BLUE}--- 配置 Mixed ---${NC}"
  SB_PORT=$(prompt_port "[Mixed] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  SB_MIXED_AUTH_ENABLED=$(prompt_yes_no "[Mixed] 是否启用用户名密码认证 [y/n] (默认 y，强烈建议开启): " "y")
  if [[ "${SB_MIXED_AUTH_ENABLED}" == "y" ]]; then
    read -rp "[Mixed] 用户名 (留空自动生成): " in_user
    SB_MIXED_USERNAME="${in_user}"
    read -rp "[Mixed] 密码 (留空自动生成): " in_pass
    SB_MIXED_PASSWORD="${in_pass}"
    ensure_mixed_auth_credentials
  else
    log_warn "你选择了关闭认证。开放的 HTTP/SOCKS 代理存在明显安全风险，请确认防火墙与访问源限制。"
  fi
}

prompt_hy2_install() {
  local in_domain in_p in_password in_user_name in_up in_down in_obfs in_obfs_password in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path in_masquerade

  set_protocol_defaults "hy2"
  SB_NODE_NAME=$(default_instance_node_name "hy2") || return 1
  echo -e "\n${BLUE}--- 配置 Hysteria2 ---${NC}"
  echo '[Hysteria2] 域名为必填项，用作 TLS server_name / SNI（客户端校验证书的名称），需与证书匹配。' >&2
  echo '[Hysteria2] 填写纯域名，如 hy2.example.com，不带 https:// 或路径；脚本会检查解析是否指向本机。' >&2

  while [[ -z "${SB_HY2_DOMAIN}" ]]; do
    if [[ -n "${SB_SHARED_TLS_DOMAIN:-}" ]]; then
      read -rp "[Hysteria2] 域名 (默认 ${SB_SHARED_TLS_DOMAIN}): " in_domain
      in_domain=${in_domain:-$SB_SHARED_TLS_DOMAIN}
    else
      read -rp "[Hysteria2] 域名（必填）: " in_domain
    fi
    SB_HY2_DOMAIN=$(trim_whitespace "${in_domain}")
    [[ -z "${SB_HY2_DOMAIN}" ]] && log_warn "域名不能为空。"
    if [[ -n "${SB_HY2_DOMAIN}" ]] && ! validate_tls_domain_points_to_server "Hysteria2" "${SB_HY2_DOMAIN}"; then
      SB_HY2_DOMAIN=""
    fi
  done
  SB_SHARED_TLS_DOMAIN="${SB_HY2_DOMAIN}"

  SB_PORT=$(prompt_port "[Hysteria2] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  read -rp "[Hysteria2] 认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_HY2_PASSWORD="${in_password}"
  read -rp "[Hysteria2] 用户名标识 (默认 ${SB_HY2_USER_NAME}): " in_user_name
  SB_HY2_USER_NAME=${in_user_name:-$SB_HY2_USER_NAME}

  echo '[Hysteria2] 带宽为可选项，单位 Mbps；上行为服务端发送，下行为服务端接收，留空不限制。' >&2
  SB_HY2_UP_MBPS=$(prompt_optional_positive_integer "[Hysteria2] 上行带宽 Mbps (留空表示不限制): " "" "上行带宽")
  SB_HY2_DOWN_MBPS=$(prompt_optional_positive_integer "[Hysteria2] 下行带宽 Mbps (留空表示不限制): " "" "下行带宽")

  echo '[Hysteria2] Salamander 混淆默认开启；客户端须使用相同的混淆密码。启用后普通 HTTP/3 客户端无法访问伪装网站。' >&2
  SB_HY2_OBFS_ENABLED=$(prompt_yes_no "[Hysteria2] 是否启用 obfs / Salamander 混淆 [y/n] (默认 y): " "y")
  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    SB_HY2_OBFS_TYPE="salamander"
    read -rp "[Hysteria2] obfs / Salamander 混淆密码 (留空自动生成): " in_obfs_password
    [[ -n "${in_obfs_password}" ]] && SB_HY2_OBFS_PASSWORD="${in_obfs_password}"
  fi

  echo "TLS 模式:"
  echo "1. ACME 自动签发（无需提前准备证书）"
  echo "2. 手动证书路径（需已有 PEM 证书与私钥）"
  in_tls_mode=$(prompt_choice "[Hysteria2] 请选择 [1-2] (默认 1): " 1 2 1)
  case "${in_tls_mode}" in
    2) SB_HY2_TLS_MODE="manual" ;;
    *) SB_HY2_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_HY2_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01（域名需解析到本机，公网 TCP 80 端口需可达）"
    echo "2. DNS-01 (Cloudflare，需有该域名的 DNS 编辑权限)"
    in_acme_mode=$(prompt_choice "[Hysteria2] 请选择 [1-2] (默认 1): " 1 2 1)
    case "${in_acme_mode}" in
      2) SB_HY2_ACME_MODE="dns" ;;
      *) SB_HY2_ACME_MODE="http" ;;
    esac

    SB_HY2_ACME_EMAIL=$(prompt_optional_email "[Hysteria2] ACME 邮箱 (可留空，用于证书通知): " "")
    SB_HY2_ACME_DOMAIN=$(prompt_optional_domain "[Hysteria2] ACME 证书域名 (留空使用 ${SB_HY2_DOMAIN}，证书需覆盖上面的 SNI): " "${SB_HY2_DOMAIN}")

    if [[ "${SB_HY2_ACME_MODE}" == "dns" ]]; then
      read -rp "[Hysteria2] Cloudflare API Token（DNS-01 必填，需有该域名的 DNS 编辑权限）: " in_cf_api_token
      SB_HY2_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_HY2_CERT_PATH}" ]]; do
      SB_HY2_CERT_PATH=$(prompt_required_path "[Hysteria2] 证书绝对路径（必填，如 /etc/ssl/certs/hy2.pem）: ")
    done

    while [[ -z "${SB_HY2_KEY_PATH}" ]]; do
      SB_HY2_KEY_PATH=$(prompt_required_path "[Hysteria2] 私钥绝对路径（必填，如 /etc/ssl/private/hy2.key）: ")
    done
  fi

  echo '[Hysteria2] 伪装地址是未通过认证的 HTTP/3 请求所看到的网站，须填写完整 URL（如 https://www.cloudflare.com），可留空使用默认地址。' >&2
  in_masquerade=$(prompt_hy2_masquerade_url "[Hysteria2] 伪装地址 (默认 ${SB_HY2_MASQUERADE}，留空使用默认): " "${SB_HY2_MASQUERADE}" create) || return 1
  SB_HY2_MASQUERADE=${in_masquerade}

  ensure_hy2_materials
}

prompt_anytls_install() {
  local in_domain in_p in_password in_user_name in_tls_mode in_acme_mode in_acme_email in_acme_domain in_cf_api_token in_cert_path in_key_path

  set_protocol_defaults "anytls"
  SB_NODE_NAME=$(default_instance_node_name "anytls") || return 1
  echo -e "\n${BLUE}--- 配置 AnyTLS ---${NC}"

  while [[ -z "${SB_ANYTLS_DOMAIN}" ]]; do
    if [[ -n "${SB_SHARED_TLS_DOMAIN:-}" ]]; then
      read -rp "[AnyTLS] 域名 (默认 ${SB_SHARED_TLS_DOMAIN}): " in_domain
      in_domain=${in_domain:-$SB_SHARED_TLS_DOMAIN}
    else
      read -rp "[AnyTLS] 域名: " in_domain
    fi
    SB_ANYTLS_DOMAIN=$(trim_whitespace "${in_domain}")
    [[ -z "${SB_ANYTLS_DOMAIN}" ]] && log_warn "域名不能为空。"
    if [[ -n "${SB_ANYTLS_DOMAIN}" ]] && ! validate_tls_domain_points_to_server "AnyTLS" "${SB_ANYTLS_DOMAIN}"; then
      SB_ANYTLS_DOMAIN=""
    fi
  done
  SB_SHARED_TLS_DOMAIN="${SB_ANYTLS_DOMAIN}"

  SB_PORT=$(prompt_port "[AnyTLS] 端口 (默认 ${SB_PORT}): " "${SB_PORT}")
  check_port_conflict "${SB_PORT}"

  read -rp "[AnyTLS] 用户名标识 (默认 ${SB_ANYTLS_USER_NAME}): " in_user_name
  SB_ANYTLS_USER_NAME=${in_user_name:-$SB_ANYTLS_USER_NAME}

  read -rp "[AnyTLS] 认证密码 (留空自动生成): " in_password
  [[ -n "${in_password}" ]] && SB_ANYTLS_PASSWORD="${in_password}"

  echo "TLS 模式:"
  echo "1. ACME 自动签发"
  echo "2. 手动证书路径"
  in_tls_mode=$(prompt_choice "[AnyTLS] 请选择 [1-2] (默认 1): " 1 2 1)
  case "${in_tls_mode}" in
    2) SB_ANYTLS_TLS_MODE="manual" ;;
    *) SB_ANYTLS_TLS_MODE="acme" ;;
  esac

  if [[ "${SB_ANYTLS_TLS_MODE}" == "acme" ]]; then
    echo "ACME 验证方式:"
    echo "1. HTTP-01"
    echo "2. DNS-01 (Cloudflare)"
    in_acme_mode=$(prompt_choice "[AnyTLS] 请选择 [1-2] (默认 1): " 1 2 1)
    case "${in_acme_mode}" in
      2) SB_ANYTLS_ACME_MODE="dns" ;;
      *) SB_ANYTLS_ACME_MODE="http" ;;
    esac

    SB_ANYTLS_ACME_EMAIL=$(prompt_optional_email "[AnyTLS] ACME 邮箱 (可留空，用于证书通知): " "")
    SB_ANYTLS_ACME_DOMAIN=$(prompt_optional_domain "[AnyTLS] ACME 域名 (默认 ${SB_ANYTLS_DOMAIN}): " "${SB_ANYTLS_DOMAIN}")

    if [[ "${SB_ANYTLS_ACME_MODE}" == "dns" ]]; then
      read -rp "[AnyTLS] Cloudflare API Token: " in_cf_api_token
      SB_ANYTLS_CF_API_TOKEN="${in_cf_api_token}"
    fi
  else
    while [[ -z "${SB_ANYTLS_CERT_PATH}" ]]; do
      SB_ANYTLS_CERT_PATH=$(prompt_required_path "[AnyTLS] 证书路径: ")
    done

    while [[ -z "${SB_ANYTLS_KEY_PATH}" ]]; do
      SB_ANYTLS_KEY_PATH=$(prompt_required_path "[AnyTLS] 私钥路径: ")
    done
  fi

  ensure_anytls_materials
}

prompt_protocol_install_fields() {
  local protocol
  protocol=$(normalize_protocol_id "$1")

  case "${protocol}" in
    vless-reality) prompt_vless_reality_install ;;
    vless-plain) prompt_vless_plain_install ;;
    mixed) prompt_mixed_install ;;
    socks) prompt_socks_install ;;
    http) prompt_http_install ;;
    shadowsocks) prompt_shadowsocks_install ;;
    trojan) prompt_trojan_install ;;
    vmess) prompt_vmess_install ;;
    hy2) prompt_hy2_install ;;
    anytls) prompt_anytls_install ;;
    snell) prompt_snell_install ;;
    tuic) prompt_tuic_install ;;
    hysteria) prompt_hysteria_install ;;
    naive) prompt_naive_install ;;
    shadowtls) prompt_shadowtls_install ;;
    *) log_error "不支持的协议安装类型: ${protocol}" ;;
  esac
}
