
get_public_ip() {
  local address
  if address=$(get_public_ipv4) && [[ -n "${address}" ]]; then
    printf '%s' "${address}"
  elif address=$(get_public_ipv6) && [[ -n "${address}" ]]; then
    printf '%s' "${address}"
  else
    return 1
  fi
}

get_public_ipv4() {
  get_public_address_for_family 4
}

get_public_ipv6() {
  get_public_address_for_family 6
}

get_public_address_for_family() {
  local family=${1:-} endpoint address
  [[ "${family}" == 4 || "${family}" == 6 ]] || return 1
  for endpoint in https://api.ip.sb/ip https://ifconfig.me; do
    if ! address=$(curl "-${family}" -fsS --connect-timeout 5 --max-time 10 "${endpoint}" 2>/dev/null); then
      continue
    fi
    address=$(trim_whitespace "${address}") || return 1
    structured_instance_store_validate_address "${address}" || continue
    if listener_address_is_wildcard "${address}"; then continue; fi
    if [[ "${family}" == 4 && "${address}" != *:* || "${family}" == 6 && "${address}" == *:* ]]; then
      printf '%s' "${address}"
      return 0
    fi
  done
  return 1
}

normalize_ip_list() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | sed '/^$/d' | sort -u
}

get_public_ip_candidates() {
  local ipv4_address ipv6_address

  ipv4_address=$(get_public_ipv4 || true)
  ipv6_address=$(get_public_ipv6 || true)

  {
    printf '%s\n' "${ipv4_address}"
    printf '%s\n' "${ipv6_address}"
  } | normalize_ip_list
}

resolve_domain_ip_candidates() {
  local domain=$1
  local resolved_any="n"

  if command -v getent >/dev/null 2>&1; then
    getent ahosts "${domain}" 2>/dev/null | awk '{print $1}' | normalize_ip_list || true
    resolved_any="y"
  fi

  if command -v dig >/dev/null 2>&1; then
    {
      dig +short A "${domain}" 2>/dev/null || true
      dig +short AAAA "${domain}" 2>/dev/null || true
    } | normalize_ip_list
    resolved_any="y"
  fi

  if [[ "${resolved_any}" == "n" ]] && command -v nslookup >/dev/null 2>&1; then
    nslookup "${domain}" 2>/dev/null | awk '/^Address: / {print $2}' | normalize_ip_list || true
  fi
}

ip_lists_have_match() {
  local public_ips=$1
  local domain_ips=$2
  local public_ip domain_ip

  while IFS= read -r public_ip; do
    [[ -z "${public_ip}" ]] && continue
    while IFS= read -r domain_ip; do
      [[ -z "${domain_ip}" ]] && continue
      [[ "${public_ip}" == "${domain_ip}" ]] && return 0
    done <<< "${domain_ips}"
  done <<< "${public_ips}"

  return 1
}

confirm_domain_ip_mismatch() {
  local protocol_name=$1
  local domain=$2
  local public_ips=$3
  local domain_ips=$4
  local answer

  log_warn "${protocol_name} 域名解析结果与本机公网出口 IP 不匹配。"
  echo "域名: ${domain}"
  echo "本机公网出口 IP:"
  if [[ -n "${public_ips}" ]]; then
    printf '  - %s\n' ${public_ips}
  else
    echo "  - 未获取到"
  fi
  echo "域名解析 IP:"
  if [[ -n "${domain_ips}" ]]; then
    printf '  - %s\n' ${domain_ips}
  else
    echo "  - 未解析到"
  fi
  log_warn "如果继续，ACME HTTP-01 签发或客户端连接可能失败。CDN、反代、DNS-01 或手动证书场景可确认继续。"
  read -rp "仍要继续使用该域名吗？[y/N]: " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}

validate_tls_domain_points_to_server() {
  local protocol_name=$1
  local domain=$2
  local public_ips domain_ips

  public_ips=$(get_public_ip_candidates | normalize_ip_list || true)
  domain_ips=$(resolve_domain_ip_candidates "${domain}" | normalize_ip_list || true)

  if [[ -n "${public_ips}" && -n "${domain_ips}" ]] && ip_lists_have_match "${public_ips}" "${domain_ips}"; then
    return 0
  fi

  confirm_domain_ip_mismatch "${protocol_name}" "${domain}" "${public_ips}" "${domain_ips}"
}

format_share_host() {
  local host=$1

  if [[ "${host}" == *:* && "${host}" != \[*\] ]]; then
    printf '[%s]' "${host}"
  else
    printf '%s' "${host}"
  fi
}

build_vless_link() {
  local public_ip=$1
  local address_label=${2:-}
  local share_host node_name advanced_query alpn_value
  share_host=$(format_share_host "${public_ip}")
  node_name=$(vless_reality_display_node_name "${SB_NODE_NAME}" "${address_label}") || return 1
  advanced_query=""
  alpn_value=$(vless_reality_alpn_link_value_for_mode "${SB_VLESS_ALPN_MODE:-off}")
  [[ -n "${alpn_value}" ]] && advanced_query="${advanced_query}&alpn=${alpn_value}"
  [[ "${SB_VLESS_TCP_FAST_OPEN:-n}" == "y" ]] && advanced_query="${advanced_query}&tfo=1"

  printf 'vless://%s@%s:%s?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s%s&flow=xtls-rprx-vision#%s' \
    "${SB_UUID}" "${share_host}" "${SB_PORT}" "${SB_SNI}" "${SB_PUBLIC_KEY:-[密钥丢失，请更新配置]}" "${SB_SHORT_ID_1}" "${advanced_query}" "${node_name}"
}

vless_reality_rate_limit_summary() {
  local up_mbps=${1:-}
  local down_mbps=${2:-}
  local up_text down_text

  if [[ -n "${up_mbps}" ]]; then
    up_text="上行 ${up_mbps} Mbps"
  else
    up_text="上行不限"
  fi

  if [[ -n "${down_mbps}" ]]; then
    down_text="下行 ${down_mbps} Mbps"
  else
    down_text="下行不限"
  fi

  printf '%s / %s' "${up_text}" "${down_text}"
}

build_vless_link_for_instance() {
  local instance_id=$1
  local public_ip=$2
  local address_label=${3:-}
  local link_output status=0

  load_vless_reality_protocol_state
  load_vless_reality_instance_state "${instance_id}" || return 1
  link_output=$(build_vless_link "${public_ip}" "${address_label}") || status=$?
  load_vless_reality_instance_state "${VLESS_REALITY_DEFAULT_INSTANCE_ID:-main}" >/dev/null 2>&1 || true

  if (( status != 0 )); then
    return "${status}"
  fi
  printf '%s' "${link_output}"
}

encode_uri_userinfo_component() {
  local LC_ALL=C value=${1:-} result="" character encoded index
  for ((index=0; index<${#value}; index++)); do
    character=${value:index:1}
    case "${character}" in
      [a-zA-Z0-9.~_-]) result+="${character}" ;;
      *) printf -v encoded '%%%02X' "'${character}" || return 1; result+="${encoded}" ;;
    esac
  done
  printf '%s' "${result}"
}

plain_proxy_http_auth_representable() {
  local LC_ALL=C
  [[ "${SB_MIXED_AUTH_ENABLED:-}" == n ]] && return 0
  [[ "${SB_MIXED_AUTH_ENABLED:-}" == y ]] || return 1
  # RFC 7617: the first colon separates user/password; neither admits CTL.
  [[ "${SB_MIXED_USERNAME:-}" != *:* &&
     ! "${SB_MIXED_USERNAME:-}${SB_MIXED_PASSWORD:-}" =~ [[:cntrl:]] ]]
}

validate_http_client_connection() {
  local port=${1:-} auth_enabled=${2:-} username=${3:-} password=${4:-}
  local username_bytes password_bytes
  [[ "${port}" =~ ^[0-9]{1,5}$ ]] || return 1
  jq -en --arg port "${port}" '$port | tonumber | . >= 1 and . <= 65535' >/dev/null || return 1
  case "${auth_enabled}" in
    y)
      [[ -n "${username}" && -n "${password}" ]] || return 1
      username_bytes=$(printf '%s' "${username}" | wc -c) || return 1
      password_bytes=$(printf '%s' "${password}" | wc -c) || return 1
      [[ "${username_bytes}" =~ ^[0-9]+$ && "${password_bytes}" =~ ^[0-9]+$ &&
        "${username_bytes}" -le 4096 && "${password_bytes}" -le 4096 ]]
      ;;
    n) return 0 ;;
    *) return 1 ;;
  esac
}

# Shared typed transport contract for the VMess/Trojan/plain-VLESS adapters.
# This does not register a deployable protocol. Native TCP is represented in
# managed data by {type:"none"}; it must be omitted from sing-box configuration.
# No state, certificate, account, credential or public-network access occurs here.
validate_v2ray_transport_state_json() {
  local transport_json=${1:-} LC_ALL=C
  [[ $# -eq 1 && -n "${transport_json}" && ${#transport_json} -le 65536 ]] || return 1
  jq -es '
    def bounded($n): type == "string" and utf8bytelength <= $n and
      (test("[\u0000-\u001f\u007f]") | not);
    def token: bounded(256) and length > 0 and
      test("^[!#$%&\u0027*+.^_`|~0-9A-Za-z-]+$");
    def allowed($keys): (keys_unsorted - $keys | length) == 0;
    def optional($key; filter): if has($key) then .[$key] | filter else true end;
    # A shared server/client path is decoded text, not a URI. Query, fragment
    # and percent-encoded paths have different server/client interpretations.
    def path: bounded(4096) and (length == 0 or startswith("/")) and
      (test("[%?#]") | not);
    def host: bounded(1024) and length > 0 and (test("[ /@?#%\\\\]") | not);
    def host_list: if type == "string" then host
      elif type == "array" then length <= 32 and all(.[]; host)
      else false end;
    # Managed timeouts use bounded, non-negative ASCII Go duration units.
    # Reject overflow before a core check; do not silently clamp or normalize.
    def duration:
      bounded(64) and
      (if . == "0" then true
       elif test("^([0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h))+$") then
         ([scan("([0-9]+(?:\\.[0-9]+)?)(ns|us|ms|s|m|h)") |
           (.[0] | tonumber) *
           ({ns:0.000000001,us:0.000001,ms:0.001,s:1,m:60,h:3600}[.[1]])] |
          add <= 86400)
       else false end);
    def header_values:
      if type == "string" then bounded(4096)
      elif type == "array" then length > 0 and length <= 32 and all(.[]; bounded(4096))
      else false end;
    def headers($ws):
      type == "object" and length <= 64 and
      ([keys_unsorted[] | ascii_downcase] | unique | length) == length and
      all(to_entries[];
        (.key | token) and (.value | header_values) and
        (.key | ascii_downcase) as $key |
        (["connection","proxy-connection","upgrade","content-length","content-encoding","expect","transfer-encoding","keep-alive",
          "te","trailer","sec-websocket-key","sec-websocket-accept",
          "sec-websocket-version","sec-websocket-extensions"] |
          index($key) | not) and
        (if $key == "host" then $ws and
           (.value | if type == "array" then length == 1 and (.[0] | host) else host end)
         elif $key == "sec-websocket-protocol" then $ws and
           (.value | if type == "array" then length == 1 and (.[0] | token) else token end)
         else true end));
    def record:
      type == "object" and (.type | type == "string") and
      (if .type == "none" or .type == "quic" then allowed(["type"])
       elif .type == "http" then
         allowed(["type","host","path","method","headers","idle_timeout","ping_timeout"]) and
         optional("host"; host_list) and optional("path"; path) and
         optional("method"; (. == "" or token) and . != "HEAD" and . != "CONNECT") and
         optional("headers"; headers(false)) and
         optional("idle_timeout"; duration) and optional("ping_timeout"; duration)
       elif .type == "ws" then
         allowed(["type","path","headers","max_early_data","early_data_header_name"]) and
         optional("path"; path) and optional("headers"; headers(true)) and
         # The core compares RequestURI against the unescaped base path when
         # early data uses the path, even with max_early_data=0. Only header-
         # based early data can safely use characters that Go URL-escapes.
         (if (.early_data_header_name // "") == "" then
            optional("path"; test("^[A-Za-z0-9/._~$&+,;=:@-]*$"))
          else true end) and
         optional("max_early_data"; type == "number" and floor == . and . >= 0 and . <= 65536) and
         optional("early_data_header_name"; . == "" or token) and
         (if (.early_data_header_name // "") != "" then
           (.max_early_data // 0) > 0 and
           (.early_data_header_name | ascii_downcase) as $key |
           (["host","connection","proxy-connection","upgrade","content-length","content-encoding","expect","transfer-encoding","keep-alive",
             "te","trailer","sec-websocket-key","sec-websocket-accept",
             "sec-websocket-version","sec-websocket-extensions"] | index($key) | not) and
           ([((.headers // {}) | keys_unsorted[]) | ascii_downcase] | index($key) | not)
          else true end)
       elif .type == "grpc" then
         allowed(["type","service_name","idle_timeout","ping_timeout","permit_without_stream"]) and
         optional("service_name"; bounded(256) and test("^[A-Za-z0-9_.-]*$")) and
         optional("idle_timeout"; duration) and optional("ping_timeout"; duration) and
         # The default lite gRPC build does not implement this standard-gRPC option.
         optional("permit_without_stream"; . == false)
       elif .type == "httpupgrade" then
         allowed(["type","host","path","headers"]) and
         optional("host"; . == "" or host) and optional("path"; path) and
         optional("headers"; headers(false))
       else false end);
    length == 1 and (.[0] | record)
  ' <<< "${transport_json}" >/dev/null 2>&1
}

inspect_v2ray_transport_profile_json() {
  local family=${1:-} transport_json=${2:-} tls_mode=${3:-} flow=${4-} core_version=${5:-}
  local transport_type listen_network=tcp alpn='[]' required_build_tags='[]'
  [[ $# -eq 5 ]] || {
    printf '[ERROR] v2ray_transport: invalid arguments\n' >&2
    return 1
  }
  # Explicit family, not normalize_protocol_id: the historical vless alias
  # remains vless-reality, while this API describes the upstream family.
  case "${family}" in vmess|trojan|vless) ;; *)
    printf '[ERROR] v2ray_transport: unsupported family\n' >&2; return 1 ;;
  esac
  case "${tls_mode}" in disabled|tls|reality) ;; *)
    printf '[ERROR] v2ray_transport: invalid security mode\n' >&2; return 1 ;;
  esac
  core_version=${core_version#v}
  if [[ ! "${core_version}" =~ ^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$ ]] ||
      ! singbox_version_at_least "${core_version}" 1.13.0 ||
      ! singbox_version_at_least "${SB_SUPPORT_MAX_VERSION}" "${core_version}"; then
    printf '[ERROR] v2ray_transport: unsupported core version\n' >&2
    return 1
  fi
  if ! validate_v2ray_transport_state_json "${transport_json}"; then
    printf '[ERROR] v2ray_transport: invalid typed transport\n' >&2
    return 1
  fi
  transport_type=$(jq -er '.type' <<< "${transport_json}") || return 1
  # Managed REALITY remains the native VLESS preset, not a generic switch
  # offered for arbitrary protocols/transports accepted by a loose TLS schema.
  if [[ "${tls_mode}" == reality && ( "${family}" != vless || "${transport_type}" != none ) ]] ||
      [[ -n "${flow}" && ( "${flow}" != xtls-rprx-vision || "${family}" != vless ||
        "${transport_type}" != none || "${tls_mode}" == disabled ) ]] ||
      [[ "${transport_type}" == quic && "${tls_mode}" != tls ]]; then
    printf '[ERROR] v2ray_transport: incompatible security or flow\n' >&2
    return 1
  fi
  if [[ "${transport_type}" == quic ]]; then
    listen_network=udp
    required_build_tags='["with_quic"]'
  fi
  if [[ "${tls_mode}" == tls ]]; then
    case "${transport_type}" in
      http|grpc) alpn='["h2"]' ;;
      ws|httpupgrade) alpn='["http/1.1"]' ;;
      quic) alpn='["h3"]' ;;
    esac
  fi
  jq -cn --argjson transport "${transport_json}" --arg network "${listen_network}" \
    --argjson alpn "${alpn}" --argjson required_build_tags "${required_build_tags}" '
    {transport:(if $transport.type == "none" then null else $transport end),
     listen_networks:[$network],tls_alpn:$alpn,required_build_tags:$required_build_tags,
     runtime_guard:(if $transport.type == "httpupgrade" then
       {status:"blocked",code:"httpupgrade_runtime_unreliable"}
       elif $transport.type == "ws" and ($transport.max_early_data // 0) > 0 then
       {status:"blocked",code:"ws_early_data_runtime_unreliable"}
       else {status:"requires_validation",code:null} end)}'
}

build_v2ray_transport_profile_json() {
  local profile guard_code
  profile=$(inspect_v2ray_transport_profile_json "$@") || return 1
  # Fixed 1.13.18/1.14.0 HTTPUpgrade client/server pairs intermittently lose
  # their protocol handshake despite passing check (both TLS and plaintext).
  # Keep inspection/reproduction available, but never publish this known
  # unreliable transport through the normal adapter contract. A newer core
  # must be independently revalidated before this guard is removed. WebSocket
  # early data also exposed response corruption; block it for all families and
  # security modes because the client upgrade buffering path is shared.
  if ! jq -e '.runtime_guard.status == "requires_validation"' <<< "${profile}" >/dev/null; then
    guard_code=$(jq -er '.runtime_guard.code' <<< "${profile}") || return 1
    printf '[ERROR] v2ray_transport: %s; use diagnostic inspection, not deployment\n' "${guard_code}" >&2
    return 1
  fi
  printf '%s\n' "${profile}"
}

validate_http_tls_state_json() {
  local tls_json=${1:-}
  [[ -n "${tls_json}" ]] || return 1
  jq -e 'type == "object" and (.enabled | type == "boolean") and
    (if .enabled then
       (keys_unsorted | sort) == ["certificate_path", "enabled", "key_path", "server_name"] and
       (.server_name | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]") | not)) and
       (.certificate_path | type == "string" and startswith("/") and (test("[\u0000-\u001F\u007F]") | not)) and
       (.key_path | type == "string" and startswith("/") and (test("[\u0000-\u001F\u007F]") | not))
     else
       (keys_unsorted | sort) == ["enabled"]
     end)' <<< "${tls_json}" >/dev/null
}

read_public_certificate_pem() {
  local certificate_path=${1:-} staged certificate_size certificate_pem
  [[ -n "${certificate_path}" && -f "${certificate_path}" && -r "${certificate_path}" ]] || return 1
  staged=$(mktemp) || return 1
  if ! head -c 1048577 -- "${certificate_path}" > "${staged}"; then
    rm -f -- "${staged}"
    return 1
  fi
  certificate_size=$(wc -c < "${staged}") || {
    rm -f -- "${staged}"
    return 1
  }
  if [[ ! "${certificate_size}" =~ ^[0-9]+$ || "${certificate_size}" -gt 1048576 ]]; then
    rm -f -- "${staged}"
    return 1
  fi
  certificate_pem=$(<"${staged}") || {
    rm -f -- "${staged}"
    return 1
  }
  rm -f -- "${staged}" || return 1
  LC_ALL=C awk '
    BEGIN { state = 0; certificates = 0; invalid = 0; payload = 0 }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*$/) next
      if (state == 0) {
        if (line == "-----BEGIN CERTIFICATE-----") { state = 1; payload = 0 }
        else { invalid = 1; next }
      } else if (line == "-----END CERTIFICATE-----") {
        if (payload == 0) invalid = 1
        else { state = 0; certificates++ }
      } else if (line !~ /^[A-Za-z0-9+\/=]+$/) {
        invalid = 1
      } else payload = 1
    }
    END { exit !(invalid == 0 && state == 0 && certificates > 0) }
  ' <<< "${certificate_pem}" >/dev/null || return 1
  printf '%s' "${certificate_pem}"
}

build_plain_proxy_link() {
  local scheme=${1:-} public_ip=${2:-} share_host username password
  [[ "${scheme}" == http || "${scheme}" == socks5 ]] || return 1
  [[ -n "${public_ip}" && "${public_ip}" != *[[:space:]@/?#%]* ]] || return 1
  if [[ "${scheme}" == http ]]; then
    validate_http_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
      "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}" || return 1
  else
    validate_mixed_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
      "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}" || return 1
  fi
  if [[ "${scheme}" == http ]] && ! plain_proxy_http_auth_representable; then
    printf '[WARN] mixed_http_auth_unrepresentable: HTTP Basic 无法表达当前认证；请使用 SOCKS5 或客户端 JSON，原凭据未修改。\n' >&2
    return 1
  fi
  share_host=$(format_share_host "${public_ip}") || return 1
  if [[ "${SB_MIXED_AUTH_ENABLED}" == y ]]; then
    username=$(encode_uri_userinfo_component "${SB_MIXED_USERNAME}") || return 1
    password=$(encode_uri_userinfo_component "${SB_MIXED_PASSWORD}") || return 1
    printf '%s://%s:%s@%s:%s' "${scheme}" "${username}" "${password}" "${share_host}" "${SB_PORT}"
  else
    printf '%s://%s:%s' "${scheme}" "${share_host}" "${SB_PORT}"
  fi
}

build_mixed_http_link() { build_plain_proxy_link http "$@"; }
build_mixed_socks5_link() { build_plain_proxy_link socks5 "$@"; }

build_plain_proxy_links_json() {
  local protocol=${1:-} address=${2:-} socks_link="" http_link="" tls_json
  case "${protocol}" in
    mixed)
      socks_link=$(build_mixed_socks5_link "${address}") || return 1
      if plain_proxy_http_auth_representable; then
        http_link=$(build_mixed_http_link "${address}") || return 1
      fi
      jq -cn --arg socks5 "${socks_link}" --arg http "${http_link}" \
        '{socks5:$socks5} + (if $http == "" then {} else {http:$http} end)'
      ;;
    socks)
      socks_link=$(build_mixed_socks5_link "${address}") || return 1
      jq -cn --arg socks5 "${socks_link}" '{socks5:$socks5}'
      ;;
    http)
      tls_json=${SB_HTTP_TLS_JSON:-}
      validate_http_tls_state_json "${tls_json}" || return 1
      validate_http_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
        "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}" || return 1
      plain_proxy_http_auth_representable || return 1
      [[ -n "${address}" && "${address}" != *[[:space:]@/?#%]* ]] || return 1
      if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null 2>&1; then
        jq -cn '{}'
      else
        http_link=$(build_mixed_http_link "${address}") || return 1
        jq -cn --arg http "${http_link}" '{http:$http}'
      fi
      ;;
    *) return 1 ;;
  esac
}

plain_proxy_share_warnings_json() {
  local protocol=${1:-} unavailable=false tls_uri_unavailable=false tls_json
  case "${protocol}" in
    mixed|socks) ;;
    http)
      tls_json=${SB_HTTP_TLS_JSON:-}
      validate_http_tls_state_json "${tls_json}" || return 1
      validate_http_client_connection "${SB_PORT:-}" "${SB_MIXED_AUTH_ENABLED:-}" \
        "${SB_MIXED_USERNAME:-}" "${SB_MIXED_PASSWORD:-}" || return 1
      plain_proxy_http_auth_representable || return 1
      if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null 2>&1; then
        tls_uri_unavailable=true
      fi
      ;;
    *) return 1 ;;
  esac
  if [[ "${protocol}" == mixed ]] && ! plain_proxy_http_auth_representable; then unavailable=true; fi
  jq -cn --argjson unavailable "${unavailable}" --argjson tls_uri_unavailable "${tls_uri_unavailable}" \
    --arg protocol "${protocol}" '
    (if $protocol == "http" then [] else [{code:"socks5_uri_transport_options_omitted",message:"SOCKS5 URI 只携带代理地址和认证，不携带 UoT v2 等客户端选项；完整连接配置请使用 export-client JSON。"}] end)
    + (if $protocol == "http" and ($tls_uri_unavailable | not) then [{code:"http_plaintext_transport",message:"HTTP 代理入口未启用 TLS，认证信息与非加密业务可能被读取；访问 HTTPS 目标不等于代理入口已加密。仅用于可信网络或受保护隧道。"}] else [] end)
    + (if $protocol == "http" then [] else (if $unavailable then [{code:"mixed_http_auth_unrepresentable",message:"当前认证不符合 HTTP Basic 字段约束，未提供 HTTP 链接；SOCKS5 和客户端 JSON 仍可使用，原凭据未修改。"}] else [] end) end)
    + (if $tls_uri_unavailable then [{code:"http_tls_uri_unrepresentable",message:"HTTP TLS 客户端配置包含证书信任或 SNI，分享 URI 无法安全表达；未提供 HTTP 链接，请使用客户端 JSON 导出。"}] else [] end)'
}

hy2_manual_certificate_algorithm() {
  local algorithm

  [[ "${SB_HY2_TLS_MODE:-}" == "manual" ]] || return 1
  [[ -n "${SB_HY2_CERT_PATH:-}" && -r "${SB_HY2_CERT_PATH}" ]] || return 1
  command -v openssl >/dev/null 2>&1 || return 1

  algorithm=$(LC_ALL=C openssl x509 -in "${SB_HY2_CERT_PATH}" -noout -text 2>/dev/null \
    | awk -F': ' '/Public Key Algorithm:/ {print $2; exit}' || true)
  algorithm=$(trim_whitespace "${algorithm}")
  [[ -n "${algorithm}" ]] || return 1

  printf '%s' "${algorithm}"
}

hy2_manual_certificate_uses_ed25519() {
  local algorithm

  algorithm=$(hy2_manual_certificate_algorithm) || return 1
  [[ "${algorithm^^}" == "ED25519" ]]
}

hy2_certificate_path_uses_ed25519() {
  local certificate_path=${1:-} algorithm

  [[ -n "${certificate_path}" && -r "${certificate_path}" ]] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  algorithm=$(LC_ALL=C openssl x509 -in "${certificate_path}" -noout -text 2>/dev/null \
    | awk -F': ' '/Public Key Algorithm:/ {print $2; exit}' || true)
  algorithm=$(trim_whitespace "${algorithm}")
  [[ "${algorithm^^}" == "ED25519" ]]
}

hy2_ed25519_share_warning_json() {
  local certificate_path=${1:-}

  if ! hy2_certificate_path_uses_ed25519 "${certificate_path}"; then
    printf '[]'
    return 0
  fi
  jq -cn '[{
    code:"hy2_ed25519_share_link_requires_client_override",
    message:"检测到 Hysteria2 手动 Ed25519 证书；分享链接无法携带 disable_chrome_parrot，1.14+ 客户端必须手动启用该选项。"
  }]'
}

hy2_client_needs_chrome_parrot_disabled() {
  singbox_config_supports_1_14 && hy2_manual_certificate_uses_ed25519
}

build_hy2_compatibility_warnings_json() {
  local context=${1:-share}
  local algorithm code message

  if [[ "${SB_HY2_TLS_MODE:-}" != "manual" ]]; then
    printf '[]'
    return 0
  fi

  if ! algorithm=$(hy2_manual_certificate_algorithm); then
    jq -n '[{
      code: "hy2_certificate_algorithm_unknown",
      message: "无法识别 Hysteria2 手动证书的公钥算法；请确认 1.14+ 客户端与证书算法兼容。"
    }]'
    return 0
  fi

  if [[ "${algorithm^^}" != "ED25519" ]]; then
    printf '[]'
    return 0
  fi

  if [[ "${context}" == "export" ]]; then
    if ! singbox_config_supports_1_14; then
      printf '[]'
      return 0
    fi
    code="hy2_ed25519_chrome_parrot_disabled"
    message="检测到 Hysteria2 手动 Ed25519 证书；导出的 1.14+ 客户端配置已设置 disable_chrome_parrot=true。"
  else
    code="hy2_ed25519_share_link_requires_client_override"
    message="检测到 Hysteria2 手动 Ed25519 证书；分享链接无法携带 disable_chrome_parrot，1.14+ 客户端必须手动启用该选项。"
  fi

  jq -n \
    --arg code "${code}" \
    --arg message "${message}" \
    '[{code: $code, message: $message}]'
}

collect_hy2_compatibility_warnings_json() (
  local context=${1:-share}

  if ! protocol_state_exists "hy2" || ! load_protocol_state "hy2" "read-only"; then
    printf '[]'
    return 0
  fi

  build_hy2_compatibility_warnings_json "${context}"
)

print_hy2_compatibility_warnings() {
  local context=${1:-share}
  local warnings_json warning_message

  warnings_json=$(collect_hy2_compatibility_warnings_json "${context}")
  while IFS= read -r warning_message; do
    [[ -n "${warning_message}" ]] && log_warn "${warning_message}"
  done < <(jq -r '.[]?.message' <<< "${warnings_json}")
}

client_export_mixed_tags_json() (
  local schema store_file instance_id

  if ! protocol_state_exists "mixed"; then
    printf '[]'
    return 0
  fi
  schema=$(protocol_instance_state_schema "mixed" 2>/dev/null || true)
  case "${schema}" in
    2)
      store_file=$(mixed_structured_store_file 2>/dev/null || true)
      if [[ -f "${store_file}" && ! -L "${store_file}" ]]; then
        jq -c '[.instances[]?.id | "mixed-" + .]' "${store_file}" 2>/dev/null || printf '[]'
      else
        printf '[]'
      fi
      ;;
    1)
      instance_id=$(protocol_default_instance_id "mixed" 2>/dev/null || true)
      if [[ -n "${instance_id}" ]] && load_protocol_instance_state mixed "${instance_id}" >/dev/null 2>&1; then
        jq -cn --arg tag "$(client_outbound_tag_for_protocol mixed)" '[ $tag ]'
      else
        printf '[]'
      fi
      ;;
    *)
      printf '[]'
      ;;
  esac
)

collect_client_export_warnings_json() {
  local config_json=$1 hy2_warnings mixed_tags_json
  hy2_warnings=$(collect_hy2_compatibility_warnings_json "export") || return 1
  if ! mixed_tags_json=$(client_export_mixed_tags_json); then
    mixed_tags_json='[]'
  fi
  jq --argjson warnings "${hy2_warnings}" --argjson mixed_tags "${mixed_tags_json}" '
    def mixed_origin:
      (.tag // "") as $tag |
      (any($mixed_tags[]; . == $tag) or
       (($tag | type) == "string" and ($tag | startswith("mixed-"))));
    $warnings
    + (if any(.outbounds[]?;
        .type == "socks" and mixed_origin) then [{
      code: "mixed_plaintext_transport",
      message: "Mixed 导出使用明文 SOCKS5，代理链路未启用 TLS，认证信息与非加密业务可能被读取；仅用于可信网络或受保护隧道。UDP 经 UoT v2 承载，UoT 不提供加密。"
    }] else [] end)
    + (if any(.outbounds[]?;
        .type == "socks" and (mixed_origin | not)) then [{
      code: "socks_plaintext_transport",
      message: "SOCKS5 导出使用明文代理链路，认证信息与非加密业务可能被读取；仅用于可信网络或受保护隧道。UoT 即使启用也不提供加密。"
    }] else [] end)
    + (if any(.outbounds[]?; .type == "http" and .tls.enabled != true) then [{
      code: "http_plaintext_transport",
      message: "HTTP 代理入口未启用 TLS，认证信息与非加密业务可能被读取；访问 HTTPS 目标不等于代理入口已加密。仅用于可信网络或受保护隧道。"
    }] else [] end)
    + (if any(.outbounds[]?; .type == "http" and .tls.enabled == true) then [{
      code: "http_tls_certificate_embedded",
      message: "HTTP TLS 导出仅嵌入公开证书信任与 server_name；服务端私钥未读取或写入客户端配置。"
    }] else [] end)
    + (if any(.outbounds[]?; .type == "shadowsocks" and .method == "none") then [{
      code: "shadowsocks_plaintext_transport",
      message: "Shadowsocks none 不提供加密或认证，只能用于可信网络或受保护隧道。"
    }] else [] end)
  ' <<< "${config_json}"
}

build_hy2_link() {
  local public_ip=$1
  local address_label=${2:-}
  local server_host query node_name
  server_host=${3:-${SB_HY2_DOMAIN:-${public_ip}}}
  node_name=$(display_node_name_for_protocol "hy2" "${SB_NODE_NAME}" "${address_label}") || return 1
  query="sni=${SB_HY2_DOMAIN:-${server_host}}"

  if [[ "${SB_HY2_OBFS_ENABLED}" == "y" ]]; then
    query="${query}&obfs=${SB_HY2_OBFS_TYPE:-salamander}&obfs-password=${SB_HY2_OBFS_PASSWORD}"
  fi

  printf 'hy2://%s@%s:%s?%s#%s' \
    "${SB_HY2_PASSWORD}" \
    "$(format_share_host "${server_host}")" \
    "${SB_PORT}" \
    "${query}" \
    "${node_name}"
}
