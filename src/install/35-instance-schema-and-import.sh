
# --- Structured instance store (typed plain-proxy foundation) ---
#
# This store is deliberately separate from the legacy .env state.  It is a
# read/write file primitive for the next lifecycle layer; no caller here
# migrates legacy state or passes arbitrary JSON through to sing-box.
structured_instance_store_error() {
  local operation=${1:-operation} code=${2:-invalid}
  printf '[ERROR] structured instance store %s failed (%s).\n' "${operation}" "${code}" >&2
}

structured_instance_store_protocol() {
  local protocol
  protocol=$(normalize_protocol_id "${1:-}") || return 1
  [[ "${protocol}" == "mixed" || "${protocol}" == "vless-plain" || "${protocol}" == "socks" || "${protocol}" == "http" || "${protocol}" == "shadowsocks" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "anytls" || "${protocol}" == "hy2" || "${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls" ]] || return 1
  printf '%s' "${protocol}"
}

structured_instance_store_validate_id() {
  [[ "${1:-}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]]
}

structured_instance_store_validate_address() {
  local address=${1:-} part octet count left right ipv4_tail ipv4_prefix converted
  local parts=() octets=()
  [[ -n "${address}" && "${address}" != *%* ]] || return 1
  # Validate an IPv4 tail embedded in any IPv6 spelling by converting the
  # final dotted quad to its two hexadecimal groups before applying the normal
  # IPv6 grammar. This covers compressed and full IPv4-mapped forms alike;
  # the stored listen value itself remains unchanged.
  if [[ "${address}" == *.* && "${address}" == *:* ]]; then
    ipv4_tail=${address##*:}
    ipv4_prefix=${address%:*}
    IFS=. read -r -a octets <<< "${ipv4_tail}"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
      [[ "${octet}" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
      (( octet <= 255 )) || return 1
    done
    converted=$(printf '%x:%x' \
      "$((10#${octets[0]} * 256 + 10#${octets[1]}))" \
      "$((10#${octets[2]} * 256 + 10#${octets[3]}))") || return 1
    address="${ipv4_prefix}:${converted}"
  fi

  if [[ "${address}" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    IFS=. read -r -a octets <<< "${address}"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
      [[ "${octet}" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
      (( octet <= 255 )) || return 1
    done
    return 0
  fi

  [[ "${address}" == *:* && "${address}" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "${address}" != *:::* ]] || return 1
  [[ "${address}" != :* || "${address}" == ::* ]] || return 1
  [[ "${address}" != *: || "${address}" == *:: ]] || return 1
  count=0
  if [[ "${address}" == *::* ]]; then
    left=${address%%::*}
    right=${address#*::}
    [[ "${right}" != *::* ]] || return 1
    if [[ -n "${left}" ]]; then
      IFS=: read -r -a parts <<< "${left}"
      for part in "${parts[@]}"; do
        [[ "${part}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
        count=$((count + 1))
      done
    fi
    if [[ -n "${right}" ]]; then
      IFS=: read -r -a parts <<< "${right}"
      for part in "${parts[@]}"; do
        [[ "${part}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
        count=$((count + 1))
      done
    fi
    (( count < 8 )) || return 1
    return 0
  fi

  IFS=: read -r -a parts <<< "${address}"
  [[ ${#parts[@]} -eq 8 ]] || return 1
  for part in "${parts[@]}"; do
    [[ "${part}" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
  done
}

hy2_acme_record_jq_filter() {
  cat <<'JQ'
    def hy2_safe_string:
      type == "string" and utf8bytelength <= 8192 and (test("[\u0000-\u001F\u007F]") | not);
    def hy2_acme_options:
      type == "object" and
      ((keys - ["domain","data_directory","default_server_name","email","provider","account_key",
        "disable_http_challenge","disable_tls_alpn_challenge","alternative_http_port","alternative_tls_port",
        "external_account","dns01_challenge","key_type","profile","http_client"]) | length == 0) and
      (.domain | type == "array" and length > 0 and length <= 128 and
        all(.[]; hy2_safe_string and length > 0 and length <= 253 and (test("\\s") | not))) and
      (to_entries | all(.[] | select(.key | IN("data_directory","default_server_name","email","provider","account_key","key_type","profile")); .value | hy2_safe_string)) and
      (to_entries | all(.[] | select(.key | IN("disable_http_challenge","disable_tls_alpn_challenge")); .value | type == "boolean")) and
      (to_entries | all(.[] | select(.key | IN("alternative_http_port","alternative_tls_port")); .value | type == "number" and floor == . and . >= 0 and . <= 65535)) and
      ((has("external_account") | not) or
        (.external_account | type == "object" and (keys|sort)==["key_id","mac_key"] and all(.[]; hy2_safe_string and length > 0))) and
      ((has("dns01_challenge") | not) or
        (.dns01_challenge | type == "object" and
          ((keys - ["provider","api_token","zone_token"]) | length == 0) and
          .provider == "cloudflare" and (.api_token | hy2_safe_string and length > 0 and (test("\\s") | not)) and
          ((has("zone_token") | not) or (.zone_token | hy2_safe_string and length > 0)))) and
      ((has("http_client") | not) or (.http_client | (hy2_safe_string and length > 0) or type == "object"));
    def valid_hy2_tls($trust):
      type == "object" and .enabled == true and
      (.server_name | hy2_safe_string and length > 0) and
      (if has("acme") then
        (keys|sort)==["acme","enabled","server_name"] and $trust == "system" and (.acme | hy2_acme_options)
       else
        (keys|sort)==["certificate_path","enabled","key_path","server_name"] and
        (.certificate_path | hy2_safe_string and startswith("/")) and
        (.key_path | hy2_safe_string and startswith("/"))
       end);
JQ
}

structured_instance_record_jq_filter() {
  hy2_acme_record_jq_filter
  cat <<'JQ'
    def ss_key($method):
      type == "string" and utf8bytelength <= 4096 and
      test("^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/][AQgw]==|[A-Za-z0-9+/]{2}[AEIMQUYcgkosw048]=)?$") and
      # The pinned core derives longer PSKs, for both server and user keys.
      # Count decoded bytes without jq @base64d corrupting arbitrary binary.
      (((length / 4 * 3) - (if endswith("==") then 2 elif endswith("=") then 1 else 0 end)) >=
       (if $method == "2022-blake3-aes-128-gcm" then 16 else 32 end));
    def ss_auth:
      type == "object" and (keys | sort) == ["method","password","users"] and
      (.method | IN("none","aes-128-gcm","aes-192-gcm","aes-256-gcm",
        "chacha20-ietf-poly1305","xchacha20-ietf-poly1305",
        "2022-blake3-aes-128-gcm","2022-blake3-aes-256-gcm","2022-blake3-chacha20-poly1305")) and
      (.method as $method |
        (.password | type == "string" and index("\u0000") == null and utf8bytelength <= 4096) and
        (.users | type == "array" and length <= 128 and
          all(.[]; type == "object" and (keys | sort) == ["name","password"] and
            (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
              (test("[\u0000-\u001F\u007F]") | not)) and
            (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null) and
            (if $method | startswith("2022-") then (.password | ss_key($method)) else true end)) and
          ((map(.name)|unique|length) == length) and ((map(.password)|unique|length) == length)) and
        (if $method == "none" then .password == "" and .users == []
         elif $method | startswith("2022-") then
           (.password | ss_key($method)) and
           (if $method == "2022-blake3-chacha20-poly1305" then .users == [] else true end)
         elif (.users|length) > 0 then .password == ""
         else (.password|length) > 0 end));
    def valid_snell_obfs_host:
      if . == "" then true
      else type == "string" and length > 0 and utf8bytelength <= 255 and
        (test("[\u0000-\u001F\u007F]") | not)
      end;
    def valid_plain_instance($protocol):
      type == "object" and
      ((keys | sort) == ((["authentication","dependencies","id","listen","name","outbound_policy","tag"] +
        (if $protocol == "snell" then ["mode","obfs_host","obfs_mode","version"] else [] end) +
        (if $protocol == "http" or $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then ["tls"] else [] end) +
        (if $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then ["client_trust","transport"]
         elif $protocol == "anytls" then ["client_trust"]
         elif $protocol == "hy2" then ["bandwidth","client_trust","masquerade","obfs"]
         elif $protocol == "tuic" then ["client_trust","tuic"]
         elif $protocol == "hysteria" then ["bandwidth","client_trust","hysteria","obfs"]
         elif $protocol == "naive" then ["client_trust","naive"]
         else [] end)) | sort)) and
      (.id | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")) and
      (.name | type == "string" and length > 0 and index("\u0000") == null) and
      (.tag | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]")|not)) and
      (.listen | type == "object" and
        ((keys|sort) == (if $protocol == "shadowsocks" or $protocol == "naive" then ["address","network","port"] else ["address","port"] end)) and
        (.address | type == "string" and length > 0 and (test("[\u0000-\u0020\u007F]")|not)) and
        (.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
        (if $protocol == "shadowsocks" or $protocol == "naive" then
          (.network | type == "array" and length > 0 and length <= 2 and
            all(.[]; . == "tcp" or . == "udp") and . == (sort|unique))
         else true end)) and
      (if $protocol == "shadowsocks" then (.authentication | ss_auth)
      elif $protocol == "anytls" or $protocol == "hy2" then
         (.authentication | type == "object" and (keys|sort) == ["users"] and
           (.users | type == "array" and length >= 1 and length <= 128 and
             all(.[]; type == "object" and (keys|sort) == ["name","password"] and
               (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
                 (test("[\u0000-\u001F\u007F]") | not)) and
               (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null)) and
             (map(.name)|unique|length) == length and
             (map(.password)|unique|length) == length))
      elif $protocol == "hysteria" then
         (.authentication | type == "object" and (keys|sort) == ["users"] and
           (.users | type == "array" and length >= 1 and length <= 128 and
             all(.[]; type == "object" and (keys|sort) == ["auth_str","name"] and
               (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
               (.auth_str | type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]") | not))) and
             (map(.name)|unique|length) == length and (map(.auth_str)|unique|length) == length))
       elif $protocol == "naive" then
         (.authentication | type == "object" and (keys|sort) == ["users"] and
           (.users | type == "array" and length >= 1 and length <= 128 and
             all(.[]; type == "object" and (keys|sort) == ["name","password","username"] and
               (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
               (.username | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null and (test("[\u0000-\u001F\u007F]") | not) and (contains(":") | not)) and
               (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null and (test("[\u0000-\u001F\u007F]") | not))) and
             (map(.name)|unique|length) == length and (map(.username)|unique|length) == length))
       elif $protocol == "tuic" then
         (.authentication | type == "object" and (keys|sort) == ["users"] and
           (.users | type == "array" and length >= 1 and length <= 128 and
             all(.[]; type == "object" and (keys|sort) == ["name","password","uuid"] and
               (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
                 (test("[\u0000-\u001F\u007F]") | not)) and
               (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null) and
               (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"))) and
             (map(.name)|unique|length) == length and
             (map(.uuid)|unique|length) == length and
             (map(.password)|unique|length) == length))
       elif $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then
         (.authentication | type == "object" and (keys|sort) == ["users"] and
           (.users | type == "array" and length >= 1 and length <= 128 and
             all(.[]; type == "object" and (keys|sort) == (if $protocol == "trojan" then ["name","password"] elif $protocol == "vmess" then ["alter_id","name","security","uuid"] else ["flow","name","uuid"] end) and
               (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
                 (test("[\u0000-\u001F\u007F]") | not)) and
               (if $protocol == "trojan" then
                 (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null)
                elif $protocol == "vmess" then
                 (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")) and
                 (.alter_id | type == "number" and floor == . and . >= 0 and . <= 65535) and
                 (.security | type == "string" and IN("auto","none","zero","aes-128-cfb","aes-128-gcm","chacha20-poly1305"))
                else
                  (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")) and
                  (.flow | type == "string" and IN("","xtls-rprx-vision"))
                end)) and
             (map(.name)|unique|length) == length and
             (if $protocol == "trojan" then (map(.password)|unique|length) == length else (map(.uuid)|unique|length) == length end)))
       elif $protocol == "snell" then
         (.authentication | type == "object" and (keys|sort) == ["psk","users"] and
           (.psk | type == "string" and length > 0 and utf8bytelength <= 255 and index("\u0000") == null and
             (test("[\u0000-\u001F\u007F]") | not)) and
           (.users | type == "array" and length <= 128 and
             all(.[]; type == "object" and (keys|sort) == ["name","userkey"] and
               (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
                 (test("[\u0000-\u001F\u007F]") | not)) and
               (.userkey | type == "string" and length > 0 and utf8bytelength <= 255 and
                 index("\u0000") == null and (test("[\u0000-\u001F\u007F]") | not))) and
             (map(.name)|unique|length) == length and
             (map(.userkey)|unique|length) == length))
       else (.authentication | type == "object" and (keys|sort) == ["enabled","password","username"] and
         (.enabled|type == "boolean") and
         (.username|type == "string" and index("\u0000") == null) and
         (.password|type == "string" and index("\u0000") == null) and
         (if $protocol == "http" then
            (.username|utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not) and (contains(":")|not)) and
            (.password|utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not))
          else (.username|utf8bytelength <= 255) and (.password|utf8bytelength <= 255) end) and
         (if .enabled then (.username|length)>0 and (.password|length)>0 else .username=="" and .password=="" end))
       end) and
      (if $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then
         (.client_trust | type == "string" and IN("certificate","system")) and
         (if .tls.enabled == false then .client_trust == "system" else true end)
       else true end) and
      (if $protocol == "snell" then
         (.version | type == "number" and floor == . and IN(5,6)) and
         (.obfs_mode | type == "string") and (.obfs_host | type == "string") and
         (.mode | type == "string") and
         (if .version == 5 then
            (.mode == "" and (.obfs_mode | IN("none","http")) and
             (if .obfs_mode == "none" then .obfs_host == "" else
                (.obfs_host | length > 0 and utf8bytelength <= 255 and
                  (test("[\u0000-\u001F\u007F]") | not))
              end))
          else
            (.obfs_mode == "" and .obfs_host == "" and
             (.mode | IN("","default","unshaped","unsafe-raw")) and
             (.authentication.psk | utf8bytelength >= 12))
          end)
       else true end) and
      (.outbound_policy|IN("default","direct","warp")) and
      (.dependencies|type == "array" and length == 0) and
      (if $protocol == "hy2" then (.client_trust as $trust | .tls | valid_hy2_tls($trust))
       elif $protocol == "http" or $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then (.tls|type == "object" and
         (if .enabled == false then ($protocol != "anytls" and $protocol != "hy2" and $protocol != "tuic" and $protocol != "hysteria" and $protocol != "naive" and (keys|sort)==["enabled"])
          elif .enabled == true then
            (keys|sort)==["certificate_path","enabled","key_path","server_name"] and
            (.server_name|type=="string" and length>0 and (test("[\u0000-\u001F\u007F]")|not)) and
            (.certificate_path|type=="string" and startswith("/") and (test("[\u0000-\u001F\u007F]")|not)) and
            (.key_path|type=="string" and startswith("/") and (test("[\u0000-\u001F\u007F]")|not))
          else false end))
       else true end) and
      (if $protocol == "hysteria" then
         (.bandwidth | type == "object" and (keys|sort) == ["down_mbps","up_mbps"] and
           (.up_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000) and
           (.down_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000)) and
         (.obfs | type == "object" and (keys|sort) == ["enabled","password"] and
           (.enabled | type == "boolean") and
           (.password | type == "string" and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]") | not)) and
           (if .enabled then (.password|length)>0 else .password == "" end)) and
         (.hysteria | type == "object" and (keys|sort) == ["connection_receive_window","disable_path_mtu_discovery","initial_packet_size","max_concurrent_streams","stream_receive_window"] and
           (.initial_packet_size | type == "number" and floor == . and . >= 0 and . <= 65535) and
           (.max_concurrent_streams | type == "number" and floor == . and . >= 0 and . <= 65535) and
           (.disable_path_mtu_discovery | type == "boolean") and
           (.stream_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")) and
           (.connection_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")))
       elif $protocol == "hy2" then
         (.bandwidth | type == "object" and (keys|sort) == ["down_mbps","up_mbps"] and
           all(.[]; . == null or (type == "number" and floor == . and . >= 1 and . <= 1000000))) and
         (.obfs | type == "object" and (keys|sort) == ["enabled","password","type"] and
           (.enabled | type == "boolean") and
           (.type | type == "string" and (test("^[A-Za-z0-9_-]{0,32}$"))) and
           (.password | type == "string" and utf8bytelength <= 4096 and index("\u0000") == null and (test("[\u0000-\u001F\u007F]") | not)) and
           (if .enabled then .type == "salamander" and (.password|length)>0 else .type == "" and .password == "" end)) and
         (.masquerade | type == "string" and utf8bytelength <= 4096 and index("\u0000") == null and (test("[\u0000-\u001F\u007F]") | not))
       elif $protocol == "tuic" then
         (.tuic | type == "object" and (keys|sort) == ["auth_timeout_seconds","congestion_control","heartbeat_seconds","udp_over_stream","udp_relay_mode","zero_rtt_handshake"] and
           (.auth_timeout_seconds | type == "number" and floor == . and . >= 0 and . <= 86400) and
           (.heartbeat_seconds | type == "number" and floor == . and . >= 0 and . <= 86400) and
           (.congestion_control | type == "string" and IN("cubic","new_reno","bbr")) and
           (.udp_over_stream | type == "boolean") and
           (.zero_rtt_handshake | type == "boolean") and
           (.udp_relay_mode | type == "string" and IN("","native","quic")) and
           (if .udp_over_stream then .udp_relay_mode == "" else .udp_relay_mode != "" end))
       elif $protocol == "naive" then
         (.naive | type == "object" and (keys|sort) == ["extra_headers","insecure_concurrency","quic","quic_congestion_control","quic_session_receive_window","stream_receive_window"] and
           (.extra_headers | type == "object" and length <= 64 and all(to_entries[];
             (.key | type == "string" and length > 0 and length <= 128 and
               (test("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$") )) and
             (.value | type == "string" and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]") | not)))) and
           (.insecure_concurrency | type == "number" and floor == . and . >= 0 and . <= 1024) and
           (.quic | type == "boolean") and
           (.quic_congestion_control | type == "string" and IN("bbr","cubic","reno")) and
           (.quic_session_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")) and
           (.stream_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")))
       else true end);
    def valid_shadowtls_instance:
      . as $instance |
      type == "object" and
      (keys|sort) == ["authentication","client_tls","client_trust","dependencies","detour","handshake","handshake_for_server_name","id","listen","name","outbound_policy","strict_mode","tag","version","wildcard_sni"] and
      (.id | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")) and
      (.name | type == "string" and length > 0 and index("\u0000") == null) and
      (.tag | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]")|not)) and
      (.listen | type == "object" and (keys|sort) == ["address","port"] and
        (.address | type == "string" and length > 0 and (test("[\u0000-\u0020\u007F]")|not)) and
        (.port | type == "number" and floor == . and . >= 1 and . <= 65535)) and
      (.version | type == "number" and floor == . and IN(1,2,3)) and
      (.authentication | type == "object" and (keys|sort) == ["password","users"] and
        (.password | type == "string" and length <= 4096 and index("\u0000") == null and (test("[\u0000-\u001F\u007F]")|not)) and
        (.users | type == "array" and length <= 128 and
          all(.[]; type == "object" and (keys|sort) == ["name","password"] and
            (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]")|not)) and
            (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null and (test("[\u0000-\u001F\u007F]")|not))) and
          (map(.name)|unique|length) == length and (map(.password)|unique|length) == length) and
        (if $instance.version == 1 then .password == "" and .users == []
         elif $instance.version == 2 then (.password|length) > 0 and .users == []
         else .password == "" and (.users|length) >= 1 end)) and
      (.handshake | type == "object" and (keys|sort) == ["server","server_port"] and
        (.server | type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not)) and
        (.server_port | type == "number" and floor == . and . >= 1 and . <= 65535)) and
      (.handshake_for_server_name | type == "object" and
        all(to_entries[]; .key | type == "string" and length > 0 and utf8bytelength <= 255 and (test("[\u0000-\u001F\u007F]")|not)) and
        all(to_entries[]; .value | type == "object" and (keys|sort) == ["server","server_port"] and
          (.server | type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not)) and
          (.server_port | type == "number" and floor == . and . >= 1 and . <= 65535)) and
        (if $instance.version == 1 then length == 0 else true end)) and
      (.strict_mode | type == "boolean") and
      (.wildcard_sni | type == "string" and IN("off","authed","all")) and
      (if .version == 1 then (.strict_mode == false and .wildcard_sni == "off")
       elif .version == 2 then (.strict_mode == false and .wildcard_sni == "off")
       else true end) and
      (.detour | type == "object" and (keys|sort) == ["listen","tag"] and
        (.tag | type == "string" and . == ("shadowtls-inner-" + $instance.id)) and
        (.listen | type == "object" and (keys|sort) == ["address","port"] and
          .address == "127.0.0.1" and (.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          .port != $instance.listen.port)) and
      (.dependencies | type == "array") and (.dependencies == [$instance.detour.tag]) and
      (.client_trust | type == "string" and IN("system","certificate")) and
      (.client_tls | type == "object" and (keys|sort) == ["certificate_path","server_name"] and
        (.server_name | type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]")|not)) and
        (.certificate_path | type == "string" and (test("[\u0000-\u001F\u007F]")|not)) and
        (if $instance.client_trust == "system" then .certificate_path == "" else (.certificate_path | startswith("/")) end)) and
      (.outbound_policy | IN("default","direct","warp"));
    def valid_instance($protocol):
      if $protocol == "shadowtls" then valid_shadowtls_instance else valid_plain_instance($protocol) end;
JQ
}

structured_instance_store_validate_common_json() {
  local protocol=${1:-mixed} file=${2:-} file_size filter transport_json tls_mode transport_list transport_record flow flow_list
  if [[ $# -eq 1 ]]; then file=${1:-}; protocol=mixed; fi
  [[ -n "${file}" && -f "${file}" && ! -L "${file}" ]] || return 1
  file_size=$(wc -c < "${file}") || return 1
  [[ "${file_size}" =~ ^[0-9]+$ && ${file_size} -le 1048576 ]] || return 1
  filter=$(structured_instance_record_jq_filter) || return 1
  jq -es "${filter}"'
    length == 1 and (.[0] |
      type == "object" and
      (keys|sort) == ["default_instance_id","instances","protocol","revision","schema_version"] and
      .schema_version == 1 and .protocol == $protocol and
      (.revision|type=="number" and floor==. and .>=0 and .<=9007199254740991) and
      (.default_instance_id|type=="string" and (test("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$") or .=="")) and
      (. as $root | if (.instances|length)==0 then .default_instance_id==""
        else .default_instance_id!="" and any(.instances[]; .id==$root.default_instance_id) end) and
      (.instances|type=="array" and length<=128 and all(.[]; valid_instance($protocol)) and
        (map(.id)|unique|length)==length and (map(.tag)|unique|length)==length and
        (map([.listen.address,.listen.port,
          (if $protocol == "shadowtls" then ["tcp"]
           elif $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" then ["udp"]
           elif $protocol == "trojan" or $protocol == "vmess" then
             (if .transport.type == "quic" then ["udp"] else ["tcp"] end)
           else (.listen.network // ["tcp"]) end)]|@json)|unique|length)==length))
  ' --arg protocol "${protocol}" "${file}" >/dev/null 2>&1 || return 1
  if [[ "${protocol}" == hy2 ]]; then
    local acme_records acme_record
    acme_records=$(jq -c '.instances[] | .tls.acme // empty' "${file}") || return 1
    while IFS= read -r acme_record; do
      [[ -n "${acme_record}" ]] || continue
      normalize_acme_extra_json "${acme_record}" >/dev/null || return 1
    done <<< "${acme_records}"
  fi
  if [[ "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "vless-plain" ]]; then
    transport_list=$(jq -c '.instances[] | [.transport, .tls.enabled, (.authentication.users | map(.flow // ""))]' "${file}") || return 1
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
}

validate_structured_instance_store() {
  local protocol file addresses address listener_input listener_plan
  protocol=$(structured_instance_store_protocol "${1:-}") || {
    structured_instance_store_error validate unsupported_protocol
    return 1
  }
  file=${2:-}
  structured_instance_store_validate_common_json "${protocol}" "${file}" || {
    structured_instance_store_error validate invalid_store
    return 1
  }
  addresses=$(jq -r '.instances[].listen.address' "${file}" 2>/dev/null) || {
    structured_instance_store_error validate invalid_address
    return 1
  }
  while IFS= read -r address; do
    [[ -n "${address}" ]] || continue
    structured_instance_store_validate_address "${address}" || {
      structured_instance_store_error validate invalid_address
      return 1
    }
  done <<< "${addresses}"
  if [[ "${protocol}" == "shadowtls" ]]; then
    jq -e '(.instances | all(.[]; .detour.listen.address == "127.0.0.1" and .detour.listen.port != .listen.port)) and
      (([.instances[].listen.port] + [.instances[].detour.listen.port]) as $ports | ($ports|unique|length) == ($ports|length))' "${file}" >/dev/null 2>&1 || {
      structured_instance_store_error validate invalid_shadowtls_detour
      return 1
    }
    while IFS= read -r address; do
      [[ -n "${address}" ]] || continue
      structured_instance_store_validate_address "${address}" || {
        structured_instance_store_error validate invalid_detour_address
        return 1
      }
    done < <(jq -r '.instances[].detour.listen.address' "${file}")
  fi
  listener_input=$(jq -c --arg protocol "${protocol}" '{inbounds:[.instances[] | {type:(if $protocol == "vless-plain" then "vless" elif $protocol == "hy2" then "hysteria2" else $protocol end),tag:.tag,listen:.listen.address,listen_port:.listen.port} + (if $protocol == "shadowsocks" or $protocol == "naive" then {network:.listen.network} elif $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then {transport:.transport} else {} end)]}' "${file}") || return 1
  if [[ "${protocol}" == "shadowtls" ]]; then
    listener_input=$(jq -c '{inbounds:(.instances | map([
      ({type:"shadowtls",tag:.tag,listen:.listen.address,listen_port:.listen.port,detour:.detour.tag,version:.version,handshake:.handshake} +
       (if .version == 2 then {password:.authentication.password} elif .version == 3 then {users:.authentication.users} else {} end)),
      {type:"mixed",tag:.detour.tag,listen:.detour.listen.address,listen_port:.detour.listen.port}
    ]) | add // [])}' "${file}") || return 1
  fi
  listener_plan=$(managed_listener_plan_json <<< "${listener_input}") || return 1
  validate_listener_plan_json <<< "${listener_plan}" || return 1
  : "${protocol}"
}

hy2_normalize_config_acme() {
  # State stores ACME options in one version-independent shape. Resolve a
  # provider only when its mapping is unique; retain every option for validation.
  jq '
    . as $root | .inbounds |= map(
      if .type == "hysteria2" and (.tls | has("certificate_provider")) then
        if (.tls | has("acme")) then error("ambiguous Hysteria2 TLS") else . end |
        .tls.certificate_provider as $reference |
        (if ($reference | type) == "object" then $reference
         elif ($reference | type) == "string" then
           [$root.certificate_providers[]? | select(.tag == $reference)] |
           if length == 1 then .[0] else error("ambiguous ACME provider") end
         else error("invalid ACME provider") end) as $provider |
        if $provider.type != "acme" then error("unsupported certificate provider") else . end |
        .tls.acme = ($provider | del(.type,.tag)) | del(.tls.certificate_provider)
      else . end)
  ' "$1"
}

# Build a complete typed plain-proxy inventory from the live configuration. This
# read-only collector never writes state; the transaction owns publication.
plain_proxy_config_store_candidate() (
  umask 077
  local protocol config_file existing_file protocol_label
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  case "${protocol}" in
    mixed) protocol_label="Mixed" ;;
    socks) protocol_label="SOCKS" ;;
    http) protocol_label="HTTP" ;;
    shadowsocks) protocol_label="Shadowsocks" ;;
    trojan) protocol_label="Trojan" ;;
    vmess) protocol_label="VMess" ;;
    vless-plain) protocol_label="VLESS" ;;
    anytls) protocol_label="AnyTLS" ;;
    hy2) protocol_label="Hysteria2" ;;
    snell) protocol_label="Snell" ;;
    tuic) protocol_label="TUIC" ;;
    hysteria) protocol_label="Hysteria" ;;
    naive) protocol_label="NaiveProxy" ;;
    shadowtls) protocol_label="ShadowTLS" ;;
    *) return 1 ;;
  esac
  shift
  if [[ "${protocol}" == shadowtls ]]; then
    shadowtls_config_store_candidate "$@"
    return $?
  fi
  config_file=${1:-${SINGBOX_CONFIG_FILE:-}}
  existing_file=${2:-}
  local state_file state_schema legacy_name active_state store_file
  local temp_dir inbound_json inbound_count inbound_index tag address port
  local username password auth_enabled policy id name base digest suffix tls_json
  local ss_method ss_password ss_users_json network_json trojan_users_json='[]' trojan_transport_json='{"type":"none"}' trojan_client_trust=certificate trojan_profile
  local vmess_users_json='[]' vmess_transport_json='{"type":"none"}' vmess_client_trust=system vmess_profile
  local vless_users_json='[]' vless_transport_json='{"type":"none"}' vless_client_trust=system vless_profile vless_flow_list vless_flow
  local anytls_users_json='[]' anytls_tls_json='{"enabled":false}' anytls_client_trust=system
  local hy2_users_json='[]' hy2_tls_json='{"enabled":false}' hy2_client_trust=system
  local hy2_bandwidth_json='{"down_mbps":null,"up_mbps":null}' hy2_obfs_json='{"enabled":false,"password":"","type":""}' hy2_masquerade=""
  local snell_version=6 snell_psk="" snell_users_json='[]' snell_obfs_mode="" snell_obfs_host="" snell_mode=""
  local tuic_users_json='[]' tuic_tls_json='{"enabled":false}' tuic_client_trust=system tuic_congestion_control=bbr tuic_auth_timeout_seconds=3 tuic_heartbeat_seconds=10 tuic_zero_rtt_handshake=false tuic_udp_relay_mode=native tuic_udp_over_stream=false
  local hysteria_users_json='[]' hysteria_tls_json='{"enabled":false}' hysteria_client_trust=system hysteria_bandwidth_json='{"down_mbps":100,"up_mbps":100}' hysteria_obfs_json='{"enabled":false,"password":""}' hysteria_quic_json='{"connection_receive_window":"","disable_path_mtu_discovery":false,"initial_packet_size":0,"max_concurrent_streams":0,"stream_receive_window":""}'
  local naive_users_json='[]' naive_tls_json='{"enabled":false}' naive_client_trust=system naive_network_json='["tcp","udp"]' naive_quic_congestion_control=bbr naive_quic=false naive_insecure_concurrency=0 naive_stream_receive_window="" naive_quic_session_receive_window="" naive_extra_headers_json='{}'
  local existing_instance existing_store_json existing_match existing_snell_obfs_host default_id old_revision old_semantics new_semantics
  local candidate_revision status
  local marker_schema2=n store_instances=0

  [[ -n "${config_file}" && -f "${config_file}" && ! -L "${config_file}" ]] || {
    printf '[ERROR] %s_store_candidate: live configuration is unavailable.\n' "${protocol}" >&2
    return 1
  }

  temp_dir=$(mktemp -d) || return $?
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'return 130' INT
  trap 'return 143' TERM
  trap 'return 129' HUP

  # Canonicalize one complete snapshot before any inventory or route reads.
  # This keeps a concurrently rewritten config from producing a mixed record
  # assembled from different generations, without truncating arbitrary JSON.
  if ! jq -cS . "${config_file}" > "${temp_dir}/live.json"; then
    printf '[ERROR] %s_store_candidate: live configuration is invalid.\n' "${protocol}" >&2
    return 1
  fi
  config_file="${temp_dir}/live.json"
  if ! validate_live_inbound_inventory "${config_file}"; then
    printf '[ERROR] %s_store_candidate: live inbound inventory is not trusted.\n' "${protocol}" >&2
    return 1
  fi
  if [[ "${protocol}" == hy2 ]]; then
    # Exclude only proven-unmanaged HY2 listeners before their private typed
    # projection is normalized or validated. Their legal core-only fields
    # remain in the live config and must not block a managed mutation.
    local hy2_filter
    hy2_filter=$(config_protocol_jq_filter hy2 "${config_file}") || return 1
    if ! jq ".inbounds |= map(select(.type != \"hysteria2\" or (${hy2_filter})))" \
      "${config_file}" > "${temp_dir}/hy2-managed.json"; then
      return 1
    fi
    config_file="${temp_dir}/hy2-managed.json"
    if ! hy2_normalize_config_acme "${config_file}" > "${temp_dir}/hy2-normalized.json" 2>"${temp_dir}/normalize.stderr"; then
      printf '[ERROR] hy2_store_candidate: 无法无损读取 ACME/provider 配置；已保留原配置。\n' >&2
      return 1
    fi
    config_file="${temp_dir}/hy2-normalized.json"
  fi

  # Reject fields that this typed schema cannot reproduce.  In particular,
  # TLS, multiple users, and listen options must never disappear during a
  # takeover.  Missing users means unauthenticated Mixed; set_system_proxy is
  # accepted only in its generated/default false form.
  if [[ "$(config_protocol_inbound_count "${protocol}" "${config_file}" 2>/dev/null || printf 0)" -le 0 ]]; then
    printf '[ERROR] %s_store_candidate: no plain-proxy inbound found.\n' "${protocol}" >&2
    return 1
  fi
  if ! jq -e "$(hy2_acme_record_jq_filter)"'
    def target:
      if $protocol == "vless-plain" then (.type == "vless" and (.tls.reality? == null))
      elif $protocol == "hy2" then .type == "hysteria2"
      else .type == $protocol end;
    def valid_snell_obfs_host:
      if . == "" then true
      else type == "string" and length > 0 and utf8bytelength <= 255 and
        (test("[\u0000-\u001F\u007F]") | not)
      end;
    (.inbounds // []) | all(.[];
      if (target | not) then true
      else
        ((keys_unsorted - (["type", "tag", "listen", "listen_port", "users", "set_system_proxy"] +
          (if $protocol == "http" then ["tls"]
           elif $protocol == "shadowsocks" then ["network", "method", "password"]
           elif $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" then ["tls", "transport"]
           elif $protocol == "anytls" then ["tls"]
           elif $protocol == "hy2" then ["tls", "up_mbps", "down_mbps", "obfs", "masquerade"]
           elif $protocol == "snell" then ["version", "psk", "users", "obfs_mode", "obfs_host", "mode"]
           elif $protocol == "tuic" then ["tls", "users", "congestion_control", "auth_timeout", "zero_rtt_handshake", "heartbeat"]
           elif $protocol == "hysteria" then ["tls", "users", "up_mbps", "down_mbps", "obfs", "initial_packet_size", "disable_path_mtu_discovery", "stream_receive_window", "connection_receive_window", "max_concurrent_streams"]
           elif $protocol == "naive" then ["tls", "users", "network", "quic_congestion_control"]
           else [] end)) | length == 0))
        and (if has("tag") then (.tag | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]") | not)) else true end)
        and (if has("listen") then (.listen | type == "string" and length > 0) else true end)
        and (if has("listen_port") then (.listen_port | type == "number" and floor == . and . >= 1 and . <= 65535) else true end)
        and (if $protocol == "shadowsocks" then
              (has("method") and (.method | type == "string" and
                IN("none", "aes-128-gcm", "aes-192-gcm", "aes-256-gcm",
                   "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
                   "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm",
                   "2022-blake3-chacha20-poly1305"))) and
              (has("password") and (.password | type == "string" and index("\u0000") == null)) and
              (if has("users") then
                (.users | type == "array" and length <= 128 and all(.[];
                  type == "object" and ((keys_unsorted | sort) == ["name", "password"]) and
                  (.name | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.password | type == "string" and length > 0 and index("\u0000") == null)))
               else true end)
             elif $protocol == "anytls" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and ((keys_unsorted | sort) == ["name", "password"]) and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null)) and
                (map(.name) | unique | length) == length and (map(.password) | unique | length) == length)
             elif $protocol == "hy2" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and ((keys_unsorted | sort) == ["name", "password"]) and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null)) and
                (map(.name) | unique | length) == length and (map(.password) | unique | length) == length)
             elif $protocol == "snell" then
              (.version | type == "number" and floor == . and IN(5,6)) and
              (.psk | type == "string" and length > 0 and utf8bytelength <= 255 and index("\u0000") == null and
                (test("[\u0000-\u001F\u007F]") | not)) and
              (.users // [] | type == "array" and length <= 128 and
                all(.[]; type == "object" and (keys_unsorted | sort) == ["name", "userkey"] and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and
                    (test("[\u0000-\u001F\u007F]") | not)) and
                  (.userkey | type == "string" and length > 0 and utf8bytelength <= 255 and
                    index("\u0000") == null and (test("[\u0000-\u001F\u007F]") | not))) and
                (map(.name) | unique | length) == length and (map(.userkey) | unique | length) == length) and
              (if .version == 5 then
                 (.mode // "") == "" and ((.obfs_mode // "none") | IN("none", "http")) and
                 # Snell v5 inbound config does not require the outbound
                 # obfs_host hint. Preserve it from typed metadata when
                 # available; a missing value is rejected later by the
                 # typed-record validator if no metadata can supply it.
                 (
                   ((.obfs_mode // "none") == "none" and (.obfs_host // "") == "") or
                   ((.obfs_mode // "none") == "http" and ((.obfs_host // "") | valid_snell_obfs_host))
                 )
               else
                 (.obfs_mode // "") == "" and (.obfs_host // "") == "" and
                 ((.mode // "") | IN("","default","unshaped","unsafe-raw")) and
                 (.psk | utf8bytelength >= 12)
               end)
             elif $protocol == "hysteria" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and (keys_unsorted | sort) == ["auth_str","name"] and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.auth_str | type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]") | not))) and
                (map(.name) | unique | length) == length and (map(.auth_str) | unique | length) == length) and
              (.up_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000) and
              (.down_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000) and
              (if has("obfs") then (.obfs | type == "string" and length <= 4096 and (test("[\u0000-\u001F\u007F]") | not)) else true end) and
              (if has("initial_packet_size") then (.initial_packet_size | type == "number" and floor == . and . >= 0 and . <= 65535) else true end) and
              (if has("max_concurrent_streams") then (.max_concurrent_streams | type == "number" and floor == . and . >= 0 and . <= 65535) else true end) and
              (if has("disable_path_mtu_discovery") then (.disable_path_mtu_discovery | type == "boolean") else true end) and
              (if has("stream_receive_window") then (.stream_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")) else true end) and
              (if has("connection_receive_window") then (.connection_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")) else true end)
             elif $protocol == "naive" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and (keys_unsorted | sort) == ["password","username"] and
                  (.username | type == "string" and length > 0 and utf8bytelength <= 4096 and index(":") == null and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and (test("[\u0000-\u001F\u007F]") | not))) and
                (map(.username) | unique | length) == length)
             elif $protocol == "tuic" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and (keys_unsorted | sort) == ["name","password","uuid"] and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null) and
                  (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"))) and
                (map(.name) | unique | length) == length and (map(.uuid) | unique | length) == length and (map(.password) | unique | length) == length) and
              (if has("congestion_control") then (.congestion_control | type == "string" and IN("cubic","new_reno","bbr")) else true end) and
              (if has("auth_timeout") then (.auth_timeout | type == "string" and test("^[0-9]+s$") and (sub("s$";"")|tonumber) <= 86400) else true end) and
              (if has("heartbeat") then (.heartbeat | type == "string" and test("^[0-9]+s$") and (sub("s$";"")|tonumber) <= 86400) else true end) and
              (if has("zero_rtt_handshake") then (.zero_rtt_handshake | type == "boolean") else true end)
             elif $protocol == "trojan" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and ((keys_unsorted | sort) == ["name", "password"]) and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.password | type == "string" and length > 0 and utf8bytelength <= 4096 and index("\u0000") == null)) and
                (map(.name) | unique | length) == length and (map(.password) | unique | length) == length)
             elif $protocol == "vmess" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and ((keys_unsorted | sort) == ["alterId", "name", "uuid"]) and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")) and
                  (.alterId | type == "number" and floor == . and . >= 0 and . <= 65535)) and
                (map(.name) | unique | length) == length and (map(.uuid) | unique | length) == length)
             elif $protocol == "vless-plain" then
              (.users | type == "array" and length >= 1 and length <= 128 and
                all(.[]; type == "object" and
                  ((keys_unsorted | sort) == ["name", "uuid"] or
                   (keys_unsorted | sort) == ["flow", "name", "uuid"]) and
                  (.name | type == "string" and length > 0 and utf8bytelength <= 256 and (test("[\u0000-\u001F\u007F]") | not)) and
                  (.uuid | type == "string" and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$")) and
                  ((.flow // "") | type == "string" and IN("", "xtls-rprx-vision"))) and
                (map(.name) | unique | length) == length and (map(.uuid) | unique | length) == length)
             elif has("users") then
              (.users | type == "array" and length <= 1 and
                all(.[ ]; type == "object" and
                  ((keys_unsorted | sort) == ["password", "username"]) and
                  (.username | type == "string" and length > 0 and index("\u0000") == null) and
                  (.password | type == "string" and length > 0 and index("\u0000") == null)) )
             else true end)
        and (if $protocol == "shadowsocks" or $protocol == "naive" then
              (if has("network") then
                (.network | if type == "string" then [.]
                  elif type == "array" then (if length == 0 then ["tcp", "udp"] else . end)
                  elif . == null then ["tcp", "udp"]
                  else error("invalid network") end) |
                (length > 0 and length <= 2 and all(.[]; . == "tcp" or . == "udp") and
                 (sort | unique) == .)
               else true end)
             else true end)
        and (if $protocol == "mixed" then
             (if has("set_system_proxy") then .set_system_proxy == false else true end)
             elif $protocol == "http" or $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "anytls" or $protocol == "hy2" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then
              ((if has("set_system_proxy") then $protocol == "http" and .set_system_proxy == false else true end)
              and (if has("tls") then
                (.tls | type == "object") and
                  (if .tls.enabled == false then
                    ($protocol != "anytls" and $protocol != "hy2" and $protocol != "tuic" and $protocol != "hysteria" and $protocol != "naive" and (.tls | keys_unsorted | sort) == ["enabled"])
                  elif .tls.enabled == true then
                    (if $protocol == "hy2" then
                      (.tls | (del(.alpn) | valid_hy2_tls("system")) and ((.alpn // ["h3"]) == ["h3"]))
                     else
                    ((.tls | (if $protocol == "trojan" or $protocol == "vmess" or $protocol == "vless-plain" or $protocol == "tuic" or $protocol == "hysteria" or $protocol == "naive" then del(.alpn) else . end) | keys_unsorted | sort) == ["certificate_path", "enabled", "key_path", "server_name"]) and
                    (.tls.server_name | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]") | not)) and
                    (.tls.certificate_path | type == "string" and startswith("/") and (test("[\u0000-\u001F\u007F]") | not)) and
                    (.tls.key_path | type == "string" and startswith("/") and (test("[\u0000-\u001F\u007F]") | not))
                     end)
                  else false end)
                else $protocol != "anytls" end))
             else
              (has("set_system_proxy") | not)
             end)
      end)
    ' --arg protocol "${protocol}" "${config_file}" >/dev/null 2>&1; then
    printf '[ERROR] %s_store_candidate: plain-proxy inbound contains unsupported or lossy fields.\n' "${protocol}" >&2
    return 1
  fi

  # Existing structured metadata is authoritative only when the root marker
  # says that schema 2 is active.  A valid but orphaned JSON file must not
  # silently rename legacy nodes.  The helper is supplied by the structured
  # state layer; the raw schema check keeps this function usable during the
  # pre-publication phase of takeover.
  state_file=$(protocol_state_file "${protocol}") || return 1
  if [[ -f "${state_file}" ]] &&
     grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=" "${state_file}"; then
    if [[ "${protocol}" == "mixed" ]] || { [[ "${protocol}" == hy2 ]] &&
       ! grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=(2|\"2\"|'2')[[:space:]]*$" "${state_file}"; }; then
      validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
    else
      plain_proxy_structured_marker_is_valid "${state_file}" || return 1
    fi
  fi
  active_state=n
  if plain_proxy_structured_state_active "${protocol}" >/dev/null 2>&1; then
    active_state=y
  fi
  state_schema="1"
  if [[ -f "${state_file}" ]]; then
    state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" | head -n1) || return 1
    state_schema=${state_schema//\"/}
    state_schema=${state_schema//\'/}
  fi
  if [[ -z "${existing_file}" ]]; then
    if existing_file=$(plain_proxy_structured_store_file "${protocol}" 2>/dev/null); then :; else existing_file="${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"; fi
  fi
  store_file="${existing_file}"
  if [[ "${state_schema}" == "2" ]]; then
    marker_schema2=y
  fi
  if [[ "${protocol}" != "mixed" && "${protocol}" != "anytls" && "${protocol}" != "hy2" && "${protocol}" != "tuic" && "${protocol}" != "hysteria" && "${protocol}" != "naive" && -f "${state_file}" && "${state_schema}" != "2" ]]; then
    printf '[ERROR] %s_store_candidate: legacy state migration is unsupported.\n' "${protocol}" >&2
    return 1
  fi
  if [[ "${marker_schema2}" == "y" || "${active_state}" == "y" ]]; then
    [[ -f "${store_file}" && ! -L "${store_file}" ]] || {
      printf '[ERROR] %s_store_candidate: active %s store is missing.\n' "${protocol}" "${protocol_label}" >&2
      return 1
    }
    validate_structured_instance_store "${protocol}" "${store_file}" || return 1
    store_instances=$(jq -r '.instances | length' "${store_file}") || return 1
    [[ "${store_instances}" =~ ^[0-9]+$ && "${store_instances}" -gt 0 ]] || {
      printf '[ERROR] %s_store_candidate: empty or orphaned %s store cannot be reused.\n' "${protocol}" "${protocol_label}" >&2
      return 1
    }
    active_state=y
  elif [[ -e "${store_file}" || -L "${store_file}" ]]; then
    # A tombstone belongs to the delete transaction and is not legacy
    # metadata.  Refuse both empty and non-empty orphan stores so a fresh
    # takeover cannot accidentally reuse stale identities.
    printf '[ERROR] %s_store_candidate: orphaned %s store requires explicit recovery.\n' "${protocol}" "${protocol_label}" >&2
    return 1
  else
    store_file=""
  fi

  legacy_name=""
  if [[ -f "${state_file}" && "${state_schema}" == "1" ]]; then
    legacy_name=$(
      unset NODE_NAME
      # shellcheck disable=SC1090
      source "${state_file}"
      # Keep the sentinel outside command substitution's newline-stripping
      # boundary so a legacy name ending in one or more newlines is exact.
      printf '%s\1' "${NODE_NAME:-}"
    ) || return 1
    legacy_name=${legacy_name%$'\1'}
  fi

  if [[ -n "${store_file}" ]]; then
    existing_store_json=$(jq -cS . "${store_file}") || return 1
    old_revision=$(jq -r '.revision' <<< "${existing_store_json}") || return 1
  else
    existing_store_json=$(structured_instance_store_empty_json "${protocol}") || return 1
    old_revision=0
  fi

  inbound_count=$(config_protocol_inbound_count "${protocol}" "${config_file}") || return 1
  [[ "${inbound_count}" =~ ^[0-9]+$ && "${inbound_count}" -gt 0 ]] || return 1
  : > "${temp_dir}/instances.jsonl" || return 1

  # Config order is not identity.  Stable tags select the prior record; a
  # previously unseen tag gets a deterministic, collision-free ID and keeps
  # the live tag verbatim.
  for ((inbound_index = 0; inbound_index < inbound_count; inbound_index++)); do
    inbound_json=$(config_protocol_inbounds_jsonl "${protocol}" "${config_file}" | sed -n "$((inbound_index + 1))p") || return 1
    tag=$(jq -r '.tag // empty' <<< "${inbound_json}") || return 1
    if [[ -z "${tag}" ]]; then
      if [[ "${inbound_count}" == "1" && "${active_state}" != "y" ]]; then
        tag="${protocol}-in"
      else
        printf '[ERROR] %s_store_candidate: %s inbound tag is required for stable identity.\n' "${protocol}" "${protocol_label}" >&2
        return 1
      fi
    fi
    # sing-box's plain-proxy listener defaults to loopback, while an omitted port
    # means an ephemeral listener.  The former is safe to materialize; the
    # latter cannot be represented in typed state and must fail closed for
    # every migration path.
    jq -e 'has("listen_port")' <<< "${inbound_json}" >/dev/null 2>&1 || {
      printf '[ERROR] %s_store_candidate: %s listen_port must be explicit; ephemeral ports are not recoverable.\n' "${protocol}" "${protocol_label}" >&2
      return 1
    }
    address=$(jq -r '.listen // empty' <<< "${inbound_json}") || return 1
    if [[ -z "${address}" ]]; then
      address='127.0.0.1'
    fi
    port=$(jq -r '.listen_port' <<< "${inbound_json}") || return 1
    structured_instance_store_validate_address "${address}" || {
      printf '[ERROR] %s_store_candidate: %s listen address is unsupported.\n' "${protocol}" "${protocol_label}" >&2
      return 1
    }

    network_json='["tcp","udp"]'
    ss_method=""
    ss_password=""
    ss_users_json='[]'
    if [[ "${protocol}" == "shadowsocks" ]]; then
      ss_method=$(jq -r '.method' <<< "${inbound_json}") || return 1
      ss_password=$(jq -j '.password, "\u0001"' <<< "${inbound_json}") || return 1
      ss_password=${ss_password%$'\1'}
      ss_users_json=$(jq -c '.users // []' <<< "${inbound_json}") || return 1
      network_json=$(jq -c '
        if (.network == null or .network == []) then ["tcp", "udp"]
        elif (.network | type) == "string" then [.network]
        else .network
        end | sort | unique
      ' <<< "${inbound_json}") || return 1
    fi

    tls_json='null'
    if [[ "${protocol}" == "http" || "${protocol}" == "trojan" || "${protocol}" == "vmess" || "${protocol}" == "vless-plain" || "${protocol}" == "anytls" || "${protocol}" == "hy2" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" ]]; then
      tls_json=$(jq -c '.tls // {enabled:false}' <<< "${inbound_json}") || return 1
    fi

    username=""
    password=""
    auth_enabled=false
    if [[ "${protocol}" == "trojan" ]]; then
      trojan_users_json=$(jq -c '.users' <<< "${inbound_json}") || return 1
      trojan_transport_json=$(jq -c '.transport // {type:"none"}' <<< "${inbound_json}") || return 1
      trojan_client_trust=certificate
      if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null 2>&1; then
        :
      else
        trojan_client_trust=system
      fi
      trojan_profile=$(build_v2ray_transport_profile_json trojan "${trojan_transport_json}" \
        "$(jq -r 'if .enabled == true then "tls" else "disabled" end' <<< "${tls_json}")" "" \
        "$(resolve_config_target_singbox_version)") || {
        printf '[ERROR] %s_store_candidate: unsupported Trojan transport profile.\n' "${protocol}" >&2
        return 1
      }
      # Accept only the ALPN implied by the managed transport. Arbitrary live
      # ALPN cannot be discarded during takeover. The typed TLS record stores
      # user-owned trust paths; its renderer derives this ALPN again.
      if ! jq -e --argjson profile "${trojan_profile}" \
          'if has("alpn") then .alpn == $profile.tls_alpn else true end' <<< "${tls_json}" >/dev/null; then
        printf '[ERROR] trojan_store_candidate: unsupported TLS ALPN; 已保留原配置。\n' >&2
        return 1
      fi
      tls_json=$(jq -c 'del(.alpn)' <<< "${tls_json}") || return 1
    elif [[ "${protocol}" == "vmess" ]]; then
      vmess_users_json=$(jq -c '.users' <<< "${inbound_json}") || return 1
      vmess_users_json=$(jq -c 'map({name,uuid,alter_id:(.alterId // 0),security:"auto"})' <<< "${vmess_users_json}") || return 1
      vmess_transport_json=$(jq -c '.transport // {type:"none"}' <<< "${inbound_json}") || return 1
      vmess_client_trust=system
      if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null 2>&1; then :; else vmess_client_trust=system; fi
      vmess_profile=$(build_v2ray_transport_profile_json vmess "${vmess_transport_json}" "$(jq -r 'if .enabled == true then "tls" else "disabled" end' <<< "${tls_json}")" "" "$(resolve_config_target_singbox_version)") || {
        printf '[ERROR] %s_store_candidate: unsupported VMess transport profile.\n' "${protocol}" >&2
        return 1
      }
      if ! jq -e --argjson profile "${vmess_profile}" 'if has("alpn") then .alpn == $profile.tls_alpn else true end' <<< "${tls_json}" >/dev/null; then
        printf '[ERROR] vmess_store_candidate: unsupported TLS ALPN; 已保留原配置。\n' >&2
        return 1
      fi
      tls_json=$(jq -c 'del(.alpn)' <<< "${tls_json}") || return 1
    elif [[ "${protocol}" == "vless-plain" ]]; then
      vless_users_json=$(jq -c '.users | map({name,uuid,flow:(.flow // "")})' <<< "${inbound_json}") || return 1
      vless_transport_json=$(jq -c '.transport // {type:"none"}' <<< "${inbound_json}") || return 1
      vless_client_trust=system
      if jq -e '.enabled == true' <<< "${tls_json}" >/dev/null 2>&1; then
        vless_client_trust=certificate
      fi
      vless_flow_list=$(jq -r '.[] | .flow // ""' <<< "${vless_users_json}") || return 1
      while IFS= read -r vless_flow; do
        vless_profile=$(build_v2ray_transport_profile_json vless "${vless_transport_json}" \
          "$(jq -r 'if .enabled == true then "tls" else "disabled" end' <<< "${tls_json}")" \
          "${vless_flow}" "$(resolve_config_target_singbox_version)") || {
          printf '[ERROR] %s_store_candidate: unsupported VLESS transport profile.\n' "${protocol}" >&2
          return 1
        }
      done <<< "${vless_flow_list}"
      if ! jq -e --argjson profile "${vless_profile}" 'if has("alpn") then .alpn == $profile.tls_alpn else true end' <<< "${tls_json}" >/dev/null; then
        printf '[ERROR] vless_store_candidate: unsupported TLS ALPN; 已保留原配置。\n' >&2
        return 1
      fi
      tls_json=$(jq -c 'del(.alpn)' <<< "${tls_json}") || return 1
    elif [[ "${protocol}" == "anytls" ]]; then
      anytls_users_json=$(jq -c '.users' <<< "${inbound_json}") || return 1
      anytls_tls_json=$(jq -c '.tls' <<< "${inbound_json}") || return 1
      jq -e '.enabled == true and (keys_unsorted | sort) == ["certificate_path","enabled","key_path","server_name"]' <<< "${anytls_tls_json}" >/dev/null 2>&1 || {
        printf '[ERROR] %s_store_candidate: AnyTLS requires a manual TLS certificate that the typed state can preserve.\n' "${protocol}" >&2
        return 1
      }
      anytls_client_trust=system
    elif [[ "${protocol}" == "hy2" ]]; then
      hy2_users_json=$(jq -c '.users' <<< "${inbound_json}") || return 1
      hy2_tls_json=$(jq -c '.tls' <<< "${inbound_json}") || return 1
      hy2_tls_json=$(jq -c 'del(.alpn)' <<< "${hy2_tls_json}") || return 1
      hy2_bandwidth_json=$(jq -c '{up_mbps:(.up_mbps // null),down_mbps:(.down_mbps // null)}' <<< "${inbound_json}") || return 1
      hy2_obfs_json=$(jq -c 'if .obfs == null then {enabled:false,type:"",password:""} else {enabled:true,type:(.obfs.type // ""),password:(.obfs.password // "")} end' <<< "${inbound_json}") || return 1
      hy2_masquerade=$(jq -j '.masquerade // "", "\u0001"' <<< "${inbound_json}") || return 1
      hy2_masquerade=${hy2_masquerade%$'\1'}
      hy2_client_trust=system
    elif [[ "${protocol}" == "snell" ]]; then
      snell_version=$(jq -r '.version // 6' <<< "${inbound_json}") || return 1
      snell_psk=$(jq -j '.psk // "", "\u0001"' <<< "${inbound_json}") || return 1
      snell_psk=${snell_psk%$'\1'}
      snell_users_json=$(jq -c '.users // []' <<< "${inbound_json}") || return 1
      snell_obfs_mode=$(jq -j '.obfs_mode // "", "\u0001"' <<< "${inbound_json}") || return 1
      snell_obfs_mode=${snell_obfs_mode%$'\1'}
      snell_obfs_host=$(jq -j '.obfs_host // "", "\u0001"' <<< "${inbound_json}") || return 1
      snell_obfs_host=${snell_obfs_host%$'\1'}
      snell_mode=$(jq -j '.mode // "", "\u0001"' <<< "${inbound_json}") || return 1
      snell_mode=${snell_mode%$'\1'}
      [[ "${snell_version}" =~ ^(5|6)$ && -n "${snell_psk}" ]] || {
        printf '[ERROR] %s_store_candidate: Snell version or PSK is invalid.\n' "${protocol}" >&2
        return 1
      }
      if [[ "${snell_version}" == "5" ]]; then
        [[ -n "${snell_obfs_mode}" ]] || snell_obfs_mode=none
        [[ "${snell_obfs_mode}" == "none" || "${snell_obfs_mode}" == "http" ]] || return 1
        snell_mode=""
      else
        snell_obfs_mode=""
        snell_mode=${snell_mode:-default}
        [[ "${snell_mode}" == "default" || "${snell_mode}" == "unshaped" || "${snell_mode}" == "unsafe-raw" ]] || return 1
      fi
    elif [[ "${protocol}" == "tuic" ]]; then
      tuic_users_json=$(jq -c '.users' <<< "${inbound_json}") || return 1
      tuic_tls_json=$(jq -c '.tls' <<< "${inbound_json}") || return 1
      jq -e '(.enabled == true) and ((del(.alpn) | keys_unsorted | sort) == ["certificate_path","enabled","key_path","server_name"]) and ((.alpn // ["h3"]) == ["h3"])' <<< "${tuic_tls_json}" >/dev/null 2>&1 || {
        printf '[ERROR] %s_store_candidate: TUIC requires manual TLS certificate material and h3 ALPN.\n' "${protocol}" >&2
        return 1
      }
      tuic_tls_json=$(jq -c 'del(.alpn)' <<< "${tuic_tls_json}") || return 1
      tuic_congestion_control=$(jq -r '.congestion_control // "bbr"' <<< "${inbound_json}") || return 1
      tuic_auth_timeout_seconds=$(jq -r '(.auth_timeout // "3s") | sub("s$";"") | tonumber' <<< "${inbound_json}") || return 1
      tuic_heartbeat_seconds=$(jq -r '(.heartbeat // "10s") | sub("s$";"") | tonumber' <<< "${inbound_json}") || return 1
      tuic_zero_rtt_handshake=$(jq -r 'if .zero_rtt_handshake == true then true else false end' <<< "${inbound_json}") || return 1
      tuic_udp_relay_mode=$(jq -r '.udp_relay_mode // "native"' <<< "${inbound_json}") || return 1
      tuic_udp_over_stream=$(jq -r 'if .udp_over_stream == true then true else false end' <<< "${inbound_json}") || return 1
      [[ "${tuic_congestion_control}" == cubic || "${tuic_congestion_control}" == new_reno || "${tuic_congestion_control}" == bbr ]] || return 1
      [[ "${tuic_auth_timeout_seconds}" =~ ^[0-9]+$ && "${tuic_auth_timeout_seconds}" -le 86400 ]] || return 1
      [[ "${tuic_heartbeat_seconds}" =~ ^[0-9]+$ && "${tuic_heartbeat_seconds}" -le 86400 ]] || return 1
      if [[ "${tuic_udp_over_stream}" == true ]]; then
        [[ "${tuic_udp_relay_mode}" == native ]] && tuic_udp_relay_mode=""
        [[ -z "${tuic_udp_relay_mode}" ]] || return 1
      else
        [[ "${tuic_udp_relay_mode}" == native || "${tuic_udp_relay_mode}" == quic ]] || return 1
      fi
    elif [[ "${protocol}" == "hysteria" ]]; then
      hysteria_users_json=$(jq -c '.users' <<< "${inbound_json}") || return 1
      hysteria_tls_json=$(jq -c '.tls' <<< "${inbound_json}") || return 1
      jq -e '(.enabled == true) and ((del(.alpn) | keys_unsorted | sort) == ["certificate_path","enabled","key_path","server_name"]) and ((.alpn // ["h3"]) == ["h3"])' <<< "${hysteria_tls_json}" >/dev/null 2>&1 || {
        printf '[ERROR] %s_store_candidate: Hysteria requires manual TLS certificate material and h3 ALPN.\n' "${protocol}" >&2
        return 1
      }
      hysteria_tls_json=$(jq -c 'del(.alpn)' <<< "${hysteria_tls_json}") || return 1
      hysteria_bandwidth_json=$(jq -c '{up_mbps:.up_mbps,down_mbps:.down_mbps}' <<< "${inbound_json}") || return 1
      jq -e '.up_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000' <<< "${hysteria_bandwidth_json}" >/dev/null 2>&1 || return 1
      jq -e '.down_mbps | type == "number" and floor == . and . >= 1 and . <= 1000000' <<< "${hysteria_bandwidth_json}" >/dev/null 2>&1 || return 1
      hysteria_obfs_json=$(jq -c 'if has("obfs") then {enabled:true,password:.obfs} else {enabled:false,password:""} end' <<< "${inbound_json}") || return 1
      hysteria_quic_json=$(jq -c '{connection_receive_window:(.connection_receive_window // ""),disable_path_mtu_discovery:(.disable_path_mtu_discovery // false),initial_packet_size:(.initial_packet_size // 0),max_concurrent_streams:(.max_concurrent_streams // 0),stream_receive_window:(.stream_receive_window // "")}' <<< "${inbound_json}") || return 1
      jq -e '(.initial_packet_size | type == "number" and floor == . and . >= 0 and . <= 65535) and (.max_concurrent_streams | type == "number" and floor == . and . >= 0 and . <= 65535) and (.disable_path_mtu_discovery | type == "boolean") and (.stream_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$")) and (.connection_receive_window | type == "string" and length <= 64 and test("^$|^[0-9]+( ?(B|KB|MB|GB))$"))' <<< "${hysteria_quic_json}" >/dev/null 2>&1 || return 1
      hysteria_client_trust=system
    elif [[ "${protocol}" == "naive" ]]; then
      naive_users_json=$(jq -c '.users | map({name:(.username),username,password})' <<< "${inbound_json}") || return 1
      naive_tls_json=$(jq -c '.tls' <<< "${inbound_json}") || return 1
      jq -e '(.enabled == true) and ((del(.alpn) | keys_unsorted | sort) == ["certificate_path","enabled","key_path","server_name"]) and
        (.server_name | type == "string" and length > 0 and (test("[\u0000-\u001F\u007F]") | not)) and
        (.certificate_path | type == "string" and startswith("/")) and (.key_path | type == "string" and startswith("/"))' <<< "${naive_tls_json}" >/dev/null 2>&1 || {
        printf '[ERROR] %s_store_candidate: NaiveProxy requires manual TLS certificate material.\n' "${protocol}" >&2
        return 1
      }
      naive_tls_json=$(jq -c 'del(.alpn)' <<< "${naive_tls_json}") || return 1
      naive_network_json=$(jq -c 'if .network == null then ["tcp","udp"] elif (.network | type) == "string" then [.network] else .network end | sort | unique' <<< "${inbound_json}") || return 1
      naive_quic_congestion_control=$(jq -r '.quic_congestion_control // "bbr"' <<< "${inbound_json}") || return 1
      [[ "${naive_quic_congestion_control}" == bbr || "${naive_quic_congestion_control}" == cubic || "${naive_quic_congestion_control}" == reno ]] || return 1
      # The live inbound has no client-only Naive options. Keep their typed
      # defaults, or preserve them when a tag already exists below.
      naive_client_trust=system
    elif jq -e '.users | length > 0' <<< "${inbound_json}" >/dev/null 2>&1; then
      auth_enabled=true
      username=$(jq -j '.users[0].username, "\u0001"' <<< "${inbound_json}") || return 1
      username=${username%$'\1'}
      password=$(jq -j '.users[0].password, "\u0001"' <<< "${inbound_json}") || return 1
      password=${password%$'\1'}
    fi
    # This extractor deliberately rejects more than one matching route.  A
    # route target unknown to the managed model is equally unsafe to flatten.
    if ! policy=$(vless_reality_outbound_policy_from_config "${tag}" "${config_file}"); then
      printf '[ERROR] %s_store_candidate: %s outbound policy is ambiguous or unsupported.\n' "${protocol}" "${protocol_label}" >&2
      return 1
    fi

    id=""
    name=""
    if [[ -n "${store_file}" ]]; then
      existing_match=$(jq -c --arg tag "${tag}" '[.instances[] | select(.tag == $tag)]' "${store_file}") || return 1
      if [[ "$(jq 'length' <<< "${existing_match}")" == "1" ]]; then
        id=$(jq -r '.[0].id' <<< "${existing_match}")
        name=$(jq -j '.[0].name, "\u0001"' <<< "${existing_match}") || return 1
        name=${name%$'\1'}
        if [[ "${protocol}" == "trojan" ]]; then
          trojan_client_trust=$(jq -r '.[0].client_trust // "certificate"' <<< "${existing_match}") || return 1
        elif [[ "${protocol}" == "vmess" ]]; then
          vmess_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
          vmess_users_json=$(jq -c --argjson live "${vmess_users_json}" '.[0].authentication.users as $old | $live | map(. as $u | (($old[]? | select(.name == $u.name and .uuid == $u.uuid) | .security) // "auto") as $security | .security=$security)' <<< "${existing_match}") || return 1
        elif [[ "${protocol}" == "vless-plain" ]]; then
          vless_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
        elif [[ "${protocol}" == "anytls" ]]; then
          anytls_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
        elif [[ "${protocol}" == "hy2" ]]; then
          hy2_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
        elif [[ "${protocol}" == "snell" ]]; then
          existing_snell_obfs_host=$(jq -r '.[0].obfs_host // ""' <<< "${existing_match}") || return 1
          [[ -z "${existing_snell_obfs_host}" ]] || snell_obfs_host=${existing_snell_obfs_host}
        elif [[ "${protocol}" == "tuic" ]]; then
          tuic_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
          if ! jq -e 'has("congestion_control")' <<< "${inbound_json}" >/dev/null 2>&1; then tuic_congestion_control=$(jq -r '.[0].tuic.congestion_control // "bbr"' <<< "${existing_match}") || return 1; fi
          if ! jq -e 'has("auth_timeout")' <<< "${inbound_json}" >/dev/null 2>&1; then tuic_auth_timeout_seconds=$(jq -r '.[0].tuic.auth_timeout_seconds // 3' <<< "${existing_match}") || return 1; fi
          if ! jq -e 'has("heartbeat")' <<< "${inbound_json}" >/dev/null 2>&1; then tuic_heartbeat_seconds=$(jq -r '.[0].tuic.heartbeat_seconds // 10' <<< "${existing_match}") || return 1; fi
          if ! jq -e 'has("zero_rtt_handshake")' <<< "${inbound_json}" >/dev/null 2>&1; then tuic_zero_rtt_handshake=$(jq -r '.[0].tuic.zero_rtt_handshake // false' <<< "${existing_match}") || return 1; fi
          if ! jq -e 'has("udp_relay_mode") or has("udp_over_stream")' <<< "${inbound_json}" >/dev/null 2>&1; then
            tuic_udp_relay_mode=$(jq -r '.[0].tuic.udp_relay_mode // "native"' <<< "${existing_match}") || return 1
            tuic_udp_over_stream=$(jq -r '.[0].tuic.udp_over_stream // false' <<< "${existing_match}") || return 1
          elif ! jq -e 'has("udp_relay_mode")' <<< "${inbound_json}" >/dev/null 2>&1; then
            tuic_udp_relay_mode=""
          elif ! jq -e 'has("udp_over_stream")' <<< "${inbound_json}" >/dev/null 2>&1; then
            tuic_udp_over_stream=false
          fi
        elif [[ "${protocol}" == "hysteria" ]]; then
          hysteria_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
          if ! jq -e 'has("up_mbps")' <<< "${inbound_json}" >/dev/null 2>&1; then hysteria_bandwidth_json=$(jq -c '.[0].bandwidth' <<< "${existing_match}") || return 1; fi
          if ! jq -e 'has("obfs")' <<< "${inbound_json}" >/dev/null 2>&1; then hysteria_obfs_json=$(jq -c '.[0].obfs' <<< "${existing_match}") || return 1; fi
          if ! jq -e 'has("initial_packet_size") or has("disable_path_mtu_discovery") or has("stream_receive_window") or has("connection_receive_window") or has("max_concurrent_streams")' <<< "${inbound_json}" >/dev/null 2>&1; then hysteria_quic_json=$(jq -c '.[0].hysteria' <<< "${existing_match}") || return 1; fi
        elif [[ "${protocol}" == "naive" ]]; then
          naive_client_trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
          if ! jq -e 'has("quic_congestion_control")' <<< "${inbound_json}" >/dev/null 2>&1; then naive_quic_congestion_control=$(jq -r '.[0].naive.quic_congestion_control // "bbr"' <<< "${existing_match}") || return 1; fi
          naive_quic=$(jq -r 'if .[0].naive.quic then true else false end' <<< "${existing_match}") || return 1
          naive_insecure_concurrency=$(jq -r '.[0].naive.insecure_concurrency // 0' <<< "${existing_match}") || return 1
          naive_stream_receive_window=$(jq -r '.[0].naive.stream_receive_window // ""' <<< "${existing_match}") || return 1
          naive_quic_session_receive_window=$(jq -r '.[0].naive.quic_session_receive_window // ""' <<< "${existing_match}") || return 1
          naive_extra_headers_json=$(jq -c '.[0].naive.extra_headers // {}' <<< "${existing_match}") || return 1
        fi
      elif [[ "$(jq 'length' <<< "${existing_match}")" -gt 1 ]]; then
        printf '[ERROR] %s_store_candidate: duplicate stored %s identity.\n' "${protocol}" "${protocol_label}" >&2
        return 1
      fi
    elif [[ "${inbound_count}" == "1" && "${state_schema}" == "1" ]]; then
      id="main"
      name="${legacy_name}"
    fi

    if [[ -z "${id}" ]]; then
      if structured_instance_store_validate_id "${tag}"; then
        base="${tag}"
      else
        digest=$(printf '%s' "${tag}" | sha256sum) || return 1
        base="${protocol}-${digest%% *}"
        base=${base:0:48}
      fi
      id="${base}"
      suffix=2
      while {
        jq -e -s --arg id "${id}" '[.[] | select(.id == $id)] | length > 0' "${temp_dir}/instances.jsonl" >/dev/null 2>&1 ||
          { [[ -n "${store_file}" ]] && jq -e --arg id "${id}" 'any(.instances[]; .id == $id)' "${store_file}" >/dev/null 2>&1; };
      }; do
        id="${base}-${suffix}"
        suffix=$((suffix + 1))
      done
      name="${tag}"
    fi
    [[ -n "${name}" ]] || name="${tag}"
    if [[ "${protocol}" == "http" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" \
      --argjson auth_enabled "${auth_enabled}" --arg username "${username}" --arg password "${password}" \
      --arg policy "${policy}" --argjson tls "${tls_json}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{enabled:$auth_enabled,username:$username,password:$password},outbound_policy:$policy,tls:$tls,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "trojan" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${trojan_users_json}" \
      --arg policy "${policy}" --argjson tls "${tls_json}" --argjson transport "${trojan_transport_json}" \
      --arg client_trust "${trojan_client_trust}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,transport:$transport,client_trust:$client_trust,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "vmess" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${vmess_users_json}" \
      --arg policy "${policy}" --argjson tls "${tls_json}" --argjson transport "${vmess_transport_json}" \
      --arg client_trust "${vmess_client_trust}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,transport:$transport,client_trust:$client_trust,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "vless-plain" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${vless_users_json}" \
      --arg policy "${policy}" --argjson tls "${tls_json}" --argjson transport "${vless_transport_json}" \
      --arg client_trust "${vless_client_trust}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,transport:$transport,client_trust:$client_trust,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "anytls" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${anytls_users_json}" \
      --argjson tls "${anytls_tls_json}" --arg client_trust "${anytls_client_trust}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$client_trust,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "hy2" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${hy2_users_json}" \
      --argjson tls "${hy2_tls_json}" --arg client_trust "${hy2_client_trust}" \
      --argjson bandwidth "${hy2_bandwidth_json}" --argjson obfs "${hy2_obfs_json}" \
      --arg masquerade "${hy2_masquerade}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$client_trust,bandwidth:$bandwidth,obfs:$obfs,masquerade:$masquerade,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "snell" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson version "${snell_version}" \
      --arg psk "${snell_psk}" --argjson users "${snell_users_json}" \
      --arg obfs_mode "${snell_obfs_mode}" --arg obfs_host "${snell_obfs_host}" --arg mode "${snell_mode}" \
      --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{psk:$psk,users:$users},version:$version,obfs_mode:$obfs_mode,obfs_host:$obfs_host,mode:$mode,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "tuic" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${tuic_users_json}" \
      --argjson tls "${tuic_tls_json}" --arg trust "${tuic_client_trust}" \
      --arg congestion_control "${tuic_congestion_control}" --argjson auth_timeout_seconds "${tuic_auth_timeout_seconds}" \
      --argjson heartbeat_seconds "${tuic_heartbeat_seconds}" --argjson zero_rtt_handshake "${tuic_zero_rtt_handshake}" \
      --arg udp_relay_mode "${tuic_udp_relay_mode}" --argjson udp_over_stream "${tuic_udp_over_stream}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$trust,tuic:{auth_timeout_seconds:$auth_timeout_seconds,congestion_control:$congestion_control,heartbeat_seconds:$heartbeat_seconds,udp_over_stream:$udp_over_stream,udp_relay_mode:$udp_relay_mode,zero_rtt_handshake:$zero_rtt_handshake},outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "hysteria" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${hysteria_users_json}" \
      --argjson tls "${hysteria_tls_json}" --arg trust "${hysteria_client_trust}" \
      --argjson bandwidth "${hysteria_bandwidth_json}" --argjson obfs "${hysteria_obfs_json}" --argjson hysteria "${hysteria_quic_json}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{users:$users},tls:$tls,client_trust:$trust,bandwidth:$bandwidth,obfs:$obfs,hysteria:$hysteria,outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "naive" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson users "${naive_users_json}" \
      --argjson tls "${naive_tls_json}" --arg trust "${naive_client_trust}" --argjson network "${naive_network_json}" \
      --arg cc "${naive_quic_congestion_control}" --argjson quic "${naive_quic}" --argjson insecure_concurrency "${naive_insecure_concurrency}" \
      --arg stream_receive_window "${naive_stream_receive_window}" --arg quic_session_receive_window "${naive_quic_session_receive_window}" \
      --argjson extra_headers "${naive_extra_headers_json}" --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port,network:$network},authentication:{users:$users},tls:$tls,client_trust:$trust,naive:{extra_headers:$extra_headers,insecure_concurrency:$insecure_concurrency,quic:$quic,quic_congestion_control:$cc,quic_session_receive_window:$quic_session_receive_window,stream_receive_window:$stream_receive_window},outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    elif [[ "${protocol}" == "shadowsocks" ]]; then
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" --argjson network "${network_json}" \
      --arg method "${ss_method}" --arg password "${ss_password}" --argjson users "${ss_users_json}" \
      --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port,network:$network},authentication:{method:$method,password:$password,users:$users},outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    else
      jq -n -cS \
      --arg id "${id}" --arg name "${name}" --arg tag "${tag}" \
      --arg address "${address}" --argjson port "${port}" \
      --argjson auth_enabled "${auth_enabled}" --arg username "${username}" --arg password "${password}" \
      --arg policy "${policy}" \
      '{id:$id,name:$name,tag:$tag,listen:{address:$address,port:$port},authentication:{enabled:$auth_enabled,username:$username,password:$password},outbound_policy:$policy,dependencies:[]}' \
      >> "${temp_dir}/instances.jsonl" || return 1
    fi
  done

  default_id=""
  if [[ -n "${store_file}" ]]; then
    default_id=$(jq -r '.default_instance_id' "${store_file}") || return 1
  fi
  if [[ -z "${default_id}" || ! $(jq -s --arg id "${default_id}" 'any(.[]; .id == $id)' "${temp_dir}/instances.jsonl") == true ]]; then
    default_id=$(jq -r -s 'sort_by(.tag) | .[0].id' "${temp_dir}/instances.jsonl") || return 1
  fi
  new_semantics=$(jq -s --arg default_id "${default_id}" '{default_instance_id:$default_id,instances:(sort_by(.tag))}' "${temp_dir}/instances.jsonl") || return 1
  old_semantics=$(jq -cS '{default_instance_id,instances:(.instances | sort_by(.tag))}' <<< "${existing_store_json}") || return 1
  new_semantics=$(jq -cS . <<< "${new_semantics}") || return 1
  candidate_revision="${old_revision}"
  if [[ "${old_semantics}" != "${new_semantics}" ]]; then
    [[ "${old_revision}" -lt 9007199254740991 ]] || {
      printf '[ERROR] %s_store_candidate: revision exhausted.\n' "${protocol}" >&2
      return 1
    }
    candidate_revision=$((old_revision + 1))
  fi
  candidate_json=$(jq -n -cS --arg protocol "${protocol}" --argjson revision "${candidate_revision}" --argjson semantics "${new_semantics}" '{schema_version:1,protocol:$protocol,revision:$revision,default_instance_id:$semantics.default_instance_id,instances:$semantics.instances}') || return 1
  printf '%s\n' "${candidate_json}" > "${temp_dir}/candidate.json" || return 1
  validate_structured_instance_store "${protocol}" "${temp_dir}/candidate.json" || return 1
  rm -rf -- "${temp_dir}" || { status=$?; trap - EXIT INT TERM HUP; return "${status}"; }
  trap - EXIT INT TERM HUP
  printf '%s\n' "${candidate_json}"
)

mixed_config_store_candidate() {
  plain_proxy_config_store_candidate mixed "$@"
}

shadowsocks_config_store_candidate() {
  plain_proxy_config_store_candidate shadowsocks "$@"
}

vmess_config_store_candidate() {
  plain_proxy_config_store_candidate vmess "$@"
}

anytls_config_store_candidate() {
  plain_proxy_config_store_candidate anytls "$@"
}

hy2_config_store_candidate() {
  plain_proxy_config_store_candidate hy2 "$@"
}

tuic_config_store_candidate() {
  plain_proxy_config_store_candidate tuic "$@"
}

hysteria_config_store_candidate() {
  plain_proxy_config_store_candidate hysteria "$@"
}

naive_config_store_candidate() {
  plain_proxy_config_store_candidate naive "$@"
}

shadowtls_config_store_candidate() (
  umask 077
  local config_file=${1:-${SINGBOX_CONFIG_FILE:-}} existing_file=${2:-} temp_dir inbound_json tag detour detour_id detour_port id name policy trust cert_path client_server_name
  local default_id="" old_revision=0 candidate_revision=0 existing_match base digest suffix existing_semantics new_semantics candidate_json
  [[ -n "${config_file}" && -f "${config_file}" && ! -L "${config_file}" ]] || return 1
  temp_dir=$(mktemp -d) || return $?
  trap 'rm -rf -- "${temp_dir}"' EXIT
  trap 'return 130' INT
  trap 'return 143' TERM
  trap 'return 129' HUP
  jq -cS . "${config_file}" > "${temp_dir}/live.json" || return 1
  config_file="${temp_dir}/live.json"
  validate_live_inbound_inventory "${config_file}" || return 1
  [[ "$(config_protocol_inbound_count shadowtls "${config_file}")" -gt 0 ]] || return 1
  if ! jq -e '
    (.inbounds // []) | all(.[]?;
      if .type != "shadowtls" then true else
        ((keys_unsorted - ["type","tag","listen","listen_port","detour","version","password","users","handshake","handshake_for_server_name","strict_mode","wildcard_sni"]) | length == 0) and
        (.tag | type == "string" and length > 0) and (.listen | type == "string" and length > 0) and
        (.listen_port | type == "number" and floor == . and . >= 1 and . <= 65535) and
        (.version | type == "number" and floor == . and IN(1,2,3)) and
        (.detour | type == "string" and startswith("shadowtls-inner-")) and
        (.handshake | (type == "object" and
          (.server | type == "string" and length > 0) and
          (.server_port | type == "number" and floor == . and . >= 1 and . <= 65535))) and
        (if has("handshake_for_server_name") then .handshake_for_server_name | type == "object" else true end) and
        (if .version == 1 then (.password? == null and (.users? == null or .users == []) and (.strict_mode? == null or .strict_mode == false) and (.wildcard_sni? == null or .wildcard_sni == "off"))
         elif .version == 2 then (.password | type == "string" and length > 0) and (.users? == null or .users == []) and (.strict_mode? == null or .strict_mode == false) and (.wildcard_sni? == null or .wildcard_sni == "off")
         else (.password? == null or .password == "") and (.users | type == "array" and length >= 1 and all(.[]; type == "object" and (keys_unsorted|sort) == ["name","password"])) and ((.wildcard_sni? == null) or (.wildcard_sni | IN("off","authed","all"))) end)
      end)' "${config_file}" >/dev/null 2>&1; then
    printf '[ERROR] ShadowTLS live inbound contains unsupported or lossy fields.\n' >&2
    return 1
  fi
  if [[ -z "${existing_file}" ]]; then
    existing_file=$(plain_proxy_structured_store_file shadowtls 2>/dev/null || true)
  fi
  if [[ -n "${existing_file}" && -f "${existing_file}" ]]; then
    validate_structured_instance_store shadowtls "${existing_file}" || return 1
    old_revision=$(structured_instance_store_revision "${existing_file}") || return 1
    default_id=$(jq -r '.default_instance_id' "${existing_file}") || return 1
    existing_semantics=$(jq -cS '{default_instance_id,instances:(.instances|sort_by(.tag))}' "${existing_file}") || return 1
  else
    existing_file=""
    existing_semantics='{"default_instance_id":"","instances":[]}'
  fi
  : > "${temp_dir}/instances.jsonl"
  while IFS= read -r inbound_json; do
    [[ -n "${inbound_json}" ]] || continue
    tag=$(jq -r '.tag' <<< "${inbound_json}") || return 1
    detour=$(jq -r '.detour' <<< "${inbound_json}") || return 1
    detour_port=$(jq -r --arg tag "${detour}" '.inbounds[] | select(.type == "mixed" and .tag == $tag) | .listen_port' "${config_file}") || return 1
    [[ "${detour_port}" =~ ^[0-9]+$ ]] || return 1
    policy=$(vless_reality_outbound_policy_from_config "${detour}" "${config_file}") || return 1
    id=""; name=""; existing_match='[]'
    if [[ -n "${existing_file}" ]]; then
      existing_match=$(jq -c --arg tag "${tag}" '[.instances[] | select(.tag == $tag)]' "${existing_file}") || return 1
      if [[ "$(jq 'length' <<< "${existing_match}")" == 1 ]]; then
        id=$(jq -r '.[0].id' <<< "${existing_match}") || return 1
        name=$(jq -r '.[0].name' <<< "${existing_match}") || return 1
      elif [[ "$(jq 'length' <<< "${existing_match}")" -gt 1 ]]; then
        return 1
      fi
    fi
    if [[ -z "${id}" ]]; then
      detour_id=${detour#shadowtls-inner-}
      structured_instance_store_validate_id "${detour_id}" || {
        printf '[ERROR] ShadowTLS live detour tag cannot be mapped to a safe instance id.\n' >&2
        return 1
      }
      base="${detour_id}"
      id="${base}"; suffix=2
      while jq -e -s --arg id "${id}" 'any(.[]; .id == $id)' "${temp_dir}/instances.jsonl" >/dev/null 2>&1; do id="${base}-${suffix}"; suffix=$((suffix + 1)); done
      name="${tag}"
    fi
    [[ -n "${name}" ]] || name="${tag}"
    trust=$(jq -r '.[0].client_trust // "system"' <<< "${existing_match}") || return 1
    cert_path=$(jq -r '.[0].client_tls.certificate_path // ""' <<< "${existing_match}") || return 1
    client_server_name=$(jq -r '.[0].client_tls.server_name // empty' <<< "${existing_match}") || return 1
    [[ -n "${client_server_name}" ]] || client_server_name=$(jq -r '.handshake.server' <<< "${inbound_json}") || return 1
    if ! jq -n -cS --arg id "${id}" --arg name "${name}" --arg tag "${tag}" --argjson inbound "${inbound_json}" --argjson detour_port "${detour_port}" --arg policy "${policy}" --arg trust "${trust}" --arg server_name "${client_server_name}" --arg cert_path "${cert_path}" '
      {id:$id,name:$name,tag:$tag,listen:{address:$inbound.listen,port:$inbound.listen_port},version:$inbound.version,authentication:{password:($inbound.password // ""),users:($inbound.users // [])},handshake:$inbound.handshake,handshake_for_server_name:($inbound.handshake_for_server_name // {}),strict_mode:($inbound.strict_mode // false),wildcard_sni:($inbound.wildcard_sni // "off"),detour:{tag:$inbound.detour,listen:{address:"127.0.0.1",port:$detour_port}},dependencies:[$inbound.detour],client_trust:$trust,client_tls:{server_name:$server_name,certificate_path:$cert_path},outbound_policy:$policy}' >> "${temp_dir}/instances.jsonl"; then
      return 1
    fi
  done < <(config_protocol_inbounds_jsonl shadowtls "${config_file}")
  jq -s '{default_instance_id:"",instances:.}' "${temp_dir}/instances.jsonl" > "${temp_dir}/candidate-semantics.json" || return 1
  new_semantics=$(jq -cS . "${temp_dir}/candidate-semantics.json") || return 1
  default_id=$(jq -r --arg id "${default_id}" 'if $id != "" and any(.instances[]; .id == $id) then $id else (.instances[0].id // "") end' <<< "${new_semantics}") || return 1
  new_semantics=$(jq -cS --arg id "${default_id}" '.default_instance_id=$id' <<< "${new_semantics}") || return 1
  if [[ "${existing_semantics}" == "$(jq -cS . <<< "${new_semantics}")" ]]; then
    candidate_revision=${old_revision}
  else
    [[ "${old_revision}" -lt 9007199254740991 ]] || {
      printf '[ERROR] shadowtls_store_candidate: revision exhausted.\n' >&2
      return 1
    }
    candidate_revision=$((old_revision + 1))
  fi
  candidate_json=$(jq -n -cS --argjson revision "${candidate_revision}" --argjson semantics "${new_semantics}" '{schema_version:1,protocol:"shadowtls",revision:$revision,default_instance_id:$semantics.default_instance_id,instances:($semantics.instances|sort_by(.tag))}') || return 1
  printf '%s\n' "${candidate_json}" > "${temp_dir}/candidate.json"
  validate_structured_instance_store shadowtls "${temp_dir}/candidate.json" || return 1
  rm -rf -- "${temp_dir}" || return 1
  trap - EXIT INT TERM HUP
  printf '%s\n' "${candidate_json}"
)

plain_proxy_structured_state_matches_config() (
  local protocol config_file store_file current expected temp_dir
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  config_file=${2:-${SINGBOX_CONFIG_FILE:-}}
  [[ -n "${config_file}" ]] || return 1
  plain_proxy_structured_state_active "${protocol}" >/dev/null 2>&1 || return 1
  store_file=$(plain_proxy_structured_store_file "${protocol}" 2>/dev/null) || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store "${protocol}" "${store_file}" || return 1
  temp_dir=$(mktemp -d) || return $?
  trap 'rm -rf -- "${temp_dir}"' EXIT
  current=$(jq -cS '{default_instance_id,instances:(.instances | sort_by(.tag))}' "${store_file}") || return 1
  expected=$(plain_proxy_config_store_candidate "${protocol}" "${config_file}" "${store_file}") || return 1
  expected=$(jq -cS '{default_instance_id,instances:(.instances | sort_by(.tag))}' <<< "${expected}") || return 1
  [[ "${current}" == "${expected}" ]]
)

mixed_structured_state_matches_config() {
  plain_proxy_structured_state_matches_config mixed "$@"
}

plain_proxy_validate_state_inventory() (
  local protocol store_file config_count store_count config_tags store_tags state_file state_schema
  protocol=$(structured_instance_store_protocol "${1:-}") || return 1
  state_file=$(protocol_state_file "${protocol}" 2>/dev/null || true)
  state_schema=$(sed -n 's/^[[:space:]]*CONFIG_SCHEMA_VERSION=//p' "${state_file}" 2>/dev/null | head -n1 || true)
  state_schema=${state_schema//\"/}
  state_schema=${state_schema//\'/}
  if [[ ("${protocol}" == "anytls" || "${protocol}" == "hy2") && -n "${state_schema}" && "${state_schema}" != "2" ]]; then
    validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
    return 0
  fi
  if [[ ("${protocol}" == "snell" || "${protocol}" == "tuic" || "${protocol}" == "hysteria" || "${protocol}" == "naive" || "${protocol}" == "shadowtls") && "${state_schema}" != "2" ]]; then
    return 1
  fi
  if [[ -f "${state_file}" ]] &&
     grep -Eq "^[[:space:]]*CONFIG_SCHEMA_VERSION=" "${state_file}"; then
    if [[ "${protocol}" == "mixed" ]]; then
      validate_protocol_state_schema "${protocol}" "${state_file}" || return 1
    else
      plain_proxy_structured_marker_is_valid "${state_file}" || return 1
    fi
  fi
  if [[ "${state_schema}" != "2" ]]; then
    return 0
  fi
  plain_proxy_structured_state_active "${protocol}" >/dev/null 2>&1 || return 1
  store_file=$(plain_proxy_structured_store_file "${protocol}" 2>/dev/null) || return 1
  [[ -f "${store_file}" && ! -L "${store_file}" ]] || return 1
  validate_structured_instance_store "${protocol}" "${store_file}" || return 1
  plain_proxy_structured_state_matches_config "${protocol}" || return 1
  config_count=$(config_protocol_inbound_count "${protocol}" "${SINGBOX_CONFIG_FILE}") || return 1
  store_count=$(jq -r '.instances | length' "${store_file}") || return 1
  [[ "${config_count}" =~ ^[0-9]+$ && "${config_count}" == "${store_count}" ]] || return 1
  config_tags=$(config_protocol_inbounds_jsonl "${protocol}" "${SINGBOX_CONFIG_FILE}" | jq -sc 'map(.tag) | sort') || return 1
  store_tags=$(jq -c '[.instances[].tag] | sort' "${store_file}") || return 1
  [[ "${config_tags}" == "${store_tags}" ]]
)

mixed_validate_state_inventory() {
  plain_proxy_validate_state_inventory mixed "$@"
}
