
# Validate the shared V2Ray transport object used by VMess/Trojan/VLESS
# outbounds.  The transport is a discriminated union in sing-box; keeping the
# variant-specific fields here prevents an HTTP/WS/gRPC option from silently
# crossing into another transport or from carrying arbitrary JSON.
managed_component_v2ray_transport_validate_json() {
  local transport=${1:-} transport_type
  [[ -n "${transport}" ]] || return 1
  jq -e 'type == "object" and
    (.type | type == "string" and IN("http","ws","quic","grpc","httpupgrade"))' \
    <<< "${transport}" >/dev/null 2>&1 || return 1
  transport_type=$(jq -er '.type' <<< "${transport}") || return 1
  # Reuse the transport contract already exercised by the protocol adapters:
  # bounded paths/hosts, header-injection protections, duration limits and
  # the default lite-gRPC restriction all stay identical across roles.
  validate_v2ray_transport_state_json "${transport}" || return 1
  case "${transport_type}" in
    httpupgrade)
      # Fixed 1.13.18/1.14.0 clients have a known handshake buffering defect;
      # keep the type available to diagnostic inspection, never deployment.
      return 1
      ;;
    ws)
      # WebSocket early data has the same reproduced response corruption. A
      # non-empty header name is also rejected when the size is zero so no
      # inert early-data hint is carried into generated state.
      jq -e '((.max_early_data // 0) == 0) and ((.early_data_header_name // "") == "")' \
        <<< "${transport}" >/dev/null 2>&1 || return 1
      ;;
  esac
}

# Validate the shared outbound multiplex object against sing-box 1.14.0.
# Brutal is only meaningful when enabled and then requires positive speeds;
# the target core still performs the final protocol/runtime checks.
managed_component_outbound_multiplex_validate_json() {
  local multiplex=${1:-}
  [[ -n "${multiplex}" ]] || return 1
  jq -e '
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_positive_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 1 and . <= 2147483647);
    def optional_brutal:
      (has("brutal") | not) or
      (.brutal | type == "object" and
        ((keys - ["enabled","up_mbps","down_mbps"]) | length == 0) and
        optional_bool("enabled") and
        optional_nonnegative_int("up_mbps") and
        optional_nonnegative_int("down_mbps") and
        ((.enabled? // false) != true or
          (optional_positive_int("up_mbps") and optional_positive_int("down_mbps"))));
    type == "object" and
    ((keys - ["enabled","protocol","max_connections","min_streams",
      "max_streams","padding","brutal"]) | length == 0) and
    optional_bool("enabled") and
    ((has("protocol") | not) or
      (.protocol | type == "string" and IN("h2mux","smux","yamux"))) and
    optional_nonnegative_int("max_connections") and
    optional_nonnegative_int("min_streams") and
    optional_nonnegative_int("max_streams") and
    optional_bool("padding") and optional_brutal
  ' <<< "${multiplex}" >/dev/null 2>&1 || return 1
}

# Validate VLESS, VMess and Trojan outbound records.  Their TLS object reuses
# the already fixed outbound-TLS validator from the HTTP contract; V2Ray
# transport and multiplex remain explicit shared validators so all V2Ray
# client families use the same guarded path.
managed_component_v2ray_outbound_config_validate_json() {
  local kind=${1:-} config=${2:-} transport multiplex tls tls_record transport_type flow
  [[ "${kind}" == vmess || "${kind}" == trojan || "${kind}" == vless ]] || return 1
  [[ -n "${config}" ]] || return 1
  jq -e --arg kind "${kind}" '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 65535);
    def optional_network:
      (has("network") | not) or
      (.network |
        ((type == "string" and IN("tcp","udp")) or
         (type == "array" and all(.[]; type == "string" and IN("tcp","udp")))));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and IN("wifi","cellular","ethernet","other")) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and test("^(0x[0-9a-fA-F]+|[0-9]+)$"))));
    def shared_fields:
      ["detour","bind_interface","inet4_bind_address","inet6_bind_address",
       "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
       "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
       "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
       "network_strategy","network_type","fallback_network_type","fallback_delay"];
    type == "object" and
    (if $kind == "vmess" then
       ((keys - (["server","server_port","uuid","security","alter_id",
          "global_padding","authenticated_length","network","tls","packet_encoding",
          "multiplex","transport"] + shared_fields)) | length == 0) and
       (.uuid | nonempty_safe_string) and
       (.security | type == "string" and
         IN("auto","none","zero","aes-128-cfb","aes-128-gcm","chacha20-poly1305")) and
       optional_int("alter_id") and
       optional_bool("global_padding") and
       optional_bool("authenticated_length") and
       ((has("packet_encoding") | not) or
         (.packet_encoding | type == "string" and IN("","packetaddr","xudp")))
     elif $kind == "trojan" then
       ((keys - (["server","server_port","password","network","tls",
          "multiplex","transport"] + shared_fields)) | length == 0) and
       (.password | nonempty_safe_string)
     elif $kind == "vless" then
       ((keys - (["server","server_port","uuid","flow","network","tls",
          "packet_encoding","multiplex","transport"] + shared_fields)) | length == 0) and
       (.uuid | nonempty_safe_string) and
       ((has("flow") | not) or
         (.flow | type == "string" and IN("","xtls-rprx-vision"))) and
       ((has("packet_encoding") | not) or
         (.packet_encoding | type == "string" and IN("","packetaddr","xudp")))
     else false end) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    optional_network and
    optional_safe_string("detour") and
    optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and
    optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and
    optional_safe_string("protect_path") and
    optional_routing_mark and
    optional_bool("reuse_addr") and
    optional_safe_string("netns") and
    optional_duration("connect_timeout") and
    optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and
    optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and
    ((has("udp_fragment") | not) or (.udp_fragment | type == "boolean")) and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    ((has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("default","hybrid","fallback"))) and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  if [[ "${kind}" == vless ]]; then
    flow=$(jq -r '.flow // empty' <<< "${config}") || return 1
    if [[ "${flow}" == xtls-rprx-vision ]]; then
      # Vision is a TCP/TLS sub-protocol.  The existing transport profile
      # contract requires TLS and no V2Ray transport for this flow; preserve
      # that boundary for generic VLESS outbounds as well.
      jq -e '(.tls.enabled == true) and (has("transport") | not)' \
        <<< "${config}" >/dev/null 2>&1 || return 1
    fi
  fi

  if jq -e 'has("transport")' <<< "${config}" >/dev/null 2>&1; then
    transport=$(jq -c '.transport' <<< "${config}") || return 1
    managed_component_v2ray_transport_validate_json "${transport}" || return 1
    transport_type=$(jq -er '.type' <<< "${transport}") || return 1
    if [[ "${transport_type}" == quic ]]; then
      # V2Ray QUIC constructs an HTTP/3 TLS dialer; a plaintext QUIC profile is
      # not a supported client combination even though its JSON may parse.
      jq -e '.tls.enabled == true' <<< "${config}" >/dev/null 2>&1 || return 1
    fi
  fi
  if jq -e 'has("multiplex")' <<< "${config}" >/dev/null 2>&1; then
    multiplex=$(jq -c '.multiplex' <<< "${config}") || return 1
    managed_component_outbound_multiplex_validate_json "${multiplex}" || return 1
  fi
  if jq -e 'has("tls")' <<< "${config}" >/dev/null 2>&1; then
    tls=$(jq -c '.tls' <<< "${config}") || return 1
    tls_record=$(jq -cn --argjson tls "${tls}" \
      '{server:"v2ray-tls",server_port:1,tls:$tls}') || return 1
    managed_component_http_config_validate_json "${tls_record}" || return 1
  fi
}

# Validate selector and URLTest groups against sing-box 1.14.0.  Group
# members are stable outbound references rather than arbitrary labels: require
# a non-empty unique list here, while the graph validator resolves each tag to
# a real outbound and detects dependency cycles.  URLTest retains upstream's
# empty-string defaults for URL and durations; the target core remains the
# authority for parsing duration syntax and probing reachability.
managed_component_group_config_validate_json() {
  local group_type=${1:-} config=${2:-}
  [[ "${group_type}" == selector || "${group_type}" == urltest ]] || return 1
  [[ -n "${config}" ]] || return 1
  jq -e --arg group_type "${group_type}" '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def members:
      (.outbounds | type == "array" and length > 0 and
        all(.[]; nonempty_safe_string) and
        (length == (unique | length)));
    type == "object" and
    members and
    (if $group_type == "selector" then
      ((keys - ["outbounds","default","interrupt_exist_connections"]) | length == 0) and
      optional_safe_string("default") and
      optional_bool("interrupt_exist_connections") and
      ((.default? // "") as $default |
        ($default == "" or (.outbounds | index($default)) != null))
    elif $group_type == "urltest" then
      ((keys - ["outbounds","url","interval","tolerance","idle_timeout",
        "interrupt_exist_connections"]) | length == 0) and
      optional_safe_string("url") and
      optional_duration("interval") and
      ((has("tolerance") | not) or
        (.tolerance | type == "number" and . == floor and . >= 0 and . <= 65535)) and
      optional_duration("idle_timeout") and
      optional_bool("interrupt_exist_connections")
    else false end)
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# ListenOptions is shared by the redirect, TProxy and direct inbounds.  Keep
# this allowlist separate from outbound Dial Fields: inbound listen options
# have a different contract and must not accidentally accept deprecated
# inbound fields or arbitrary JSON.
managed_component_listen_config_validate_json() {
  local config=${1:-} extra_keys=${2:-'[]'}
  [[ -n "${config}" ]] || return 1
  jq -e --argjson extra_keys "${extra_keys}" '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string and length > 0);
    def optional_udp_timeout:
      (has("udp_timeout") | not) or
      (.udp_timeout |
        ((type == "string" and safe_string and length > 0) or
         (type == "number" and . == floor and . >= 0 and . <= 4294967295)));
    def optional_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and
          ((test("^0x[0-9a-fA-F]{1,8}$")) or
           (test("^[0-9]{1,10}$") and (tonumber <= 4294967295))))));
    type == "object" and
    ((keys - ([
      "listen","listen_port","bind_interface","routing_mark","reuse_addr",
      "netns","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","tcp_fast_open","tcp_multi_path",
      "udp_fragment","udp_timeout","detour"
    ] + $extra_keys)) | length == 0) and
    optional_safe_string("listen") and
    ((has("listen_port") | not) or
      (.listen_port | type == "number" and . == floor and . >= 0 and . <= 65535)) and
    optional_safe_string("bind_interface") and
    optional_mark and
    optional_bool("reuse_addr") and
    optional_safe_string("netns") and
    optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and
    optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and
    ((has("udp_fragment") | not) or (.udp_fragment | type == "boolean")) and
    optional_udp_timeout and
    optional_safe_string("detour")
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# The resolved service is a narrow service surface backed by sing-box's
# shared ListenOptions.  Keep it separate from inbound listeners so a service
# record cannot accidentally inherit inbound-only fields or route ownership.
managed_component_resolved_service_config_validate_json() {
  local config=${1:-} listen
  [[ -n "${config}" ]] || return 1
  managed_component_listen_config_validate_json "${config}" || return 1
  jq -e '
    (has("listen") | not) or (.listen | length > 0)
  ' <<< "${config}" >/dev/null 2>&1 || return 1
  if jq -e 'has("listen")' <<< "${config}" >/dev/null 2>&1; then
    listen=$(jq -r '.listen' <<< "${config}") || return 1
    structured_instance_store_validate_address "${listen}" || return 1
  fi
}

managed_component_direct_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  managed_component_listen_config_validate_json "${config}" '["network","override_address","override_port"]' || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def network_list:
      ((type == "string" and IN("tcp","udp")) or
       (type == "array" and length > 0 and
        all(.[]; type == "string" and IN("tcp","udp")) and
        (length as $count | unique | length == $count)));
    type == "object" and
    ((keys - ["listen","listen_port","bind_interface","routing_mark","reuse_addr",
      "netns","disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "tcp_fast_open","tcp_multi_path","udp_fragment","udp_timeout","detour",
      "network","override_address","override_port"]) | length == 0) and
    (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    ((has("network") | not) or (.network | network_list)) and
    ((has("override_address") | not) or
      (.override_address | safe_string and length > 0)) and
    ((has("override_port") | not) or
      (.override_port | type == "number" and . == floor and . >= 1 and . <= 65535))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

managed_component_redirect_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  managed_component_listen_config_validate_json "${config}" || return 1
  jq -e '.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535' \
    <<< "${config}" >/dev/null 2>&1
}

managed_component_tproxy_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  managed_component_listen_config_validate_json "${config}" '["network","udp_mapping","udp_filtering","udp_nat_max"]' || return 1
  jq -e '
    def network_list:
      ((type == "string" and IN("tcp","udp")) or
       (type == "array" and length > 0 and
        all(.[]; type == "string" and IN("tcp","udp")) and
        (length as $count | unique | length == $count)));
    def nat_behavior:
      type == "string" and
      IN("","endpoint_independent","address_dependent","address_and_port_dependent");
    type == "object" and
    ((keys - ["listen","listen_port","bind_interface","routing_mark","reuse_addr",
      "netns","disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "tcp_fast_open","tcp_multi_path","udp_fragment","udp_timeout","detour",
      "network","udp_mapping","udp_filtering","udp_nat_max"]) | length == 0) and
    (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    ((has("network") | not) or (.network | network_list)) and
    ((has("udp_mapping") | not) or (.udp_mapping | nat_behavior)) and
    ((has("udp_filtering") | not) or (.udp_filtering | nat_behavior)) and
    ((has("udp_nat_max") | not) or
      (.udp_nat_max | type == "number" and . == floor and . >= 0 and . <= 4294967295))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

managed_component_tun_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def listable_safe_string:
      ((type == "string" and safe_string) or
       (type == "array" and all(.[]; safe_string)));
    def listable_nonempty_safe_string:
      ((type == "string" and safe_string and length > 0) or
       (type == "array" and length > 0 and all(.[]; safe_string and length > 0)));
    def listable_uint32:
      ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
       (type == "array" and all(.[]; type == "number" and . == floor and
         . >= 0 and . <= 4294967295)));
    def listable_nonnegative_int:
      ((type == "number" and . == floor and . >= 0 and . <= 2147483647) or
       (type == "array" and all(.[]; type == "number" and . == floor and
         . >= 0 and . <= 2147483647)));
    def uid_range:
      if type != "string" then false
      else (capture("^(?<start>[0-9]+):(?<end>[0-9]+)$") // false) as $range |
        if $range == false then false
        else ($range.start | tonumber) <= 4294967295 and
          ($range.end | tonumber) <= 4294967295 and
          ($range.start | tonumber) <= ($range.end | tonumber)
        end
      end;
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string and length > 0);
    def optional_listable_safe_string($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def interface_type:
      type == "string" and IN("wifi","cellular","ethernet","other");
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and interface_type) or
         (type == "array" and all(.[]; interface_type))));
    def optional_listable_uint32($name):
      (has($name) | not) or (.[$name] | listable_uint32);
    def optional_listable_nonnegative_int($name):
      (has($name) | not) or (.[$name] | listable_nonnegative_int);
    def optional_uid_range($name):
      (has($name) | not) or
      (.[$name] | (uid_range or (type == "array" and all(.[]; uid_range))));
    def optional_mark($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and
          ((test("^0x[0-9a-fA-F]{1,8}$")) or
           (test("^[0-9]{1,10}$") and (tonumber <= 4294967295))))));
    def optional_nat($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","endpoint_independent","address_dependent","address_and_port_dependent"));
    def optional_udp_timeout:
      (has("udp_timeout") | not) or
      (.udp_timeout |
        ((type == "string" and safe_string and length > 0) or
         (type == "number" and . == floor and . >= 0 and . <= 4294967295)));
    def optional_platform:
      (has("platform") | not) or
      (.platform | type == "object" and
        ((keys - ["http_proxy"]) | length == 0) and
        ((has("http_proxy") | not) or
          (.http_proxy | type == "object" and
            ((keys - ["enabled","server","server_port","bypass_domain","match_domain"]) | length == 0) and
            ((has("enabled") | not) or (.enabled | type == "boolean")) and
            ((has("server") | not) or (.server | safe_string)) and
            ((has("server_port") | not) or
              (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
            ((.enabled // false) != true or
              (.server | type == "string" and length > 0 and safe_string) and
              (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
            ((has("bypass_domain") | not) or (.bypass_domain | listable_safe_string)) and
            ((has("match_domain") | not) or (.match_domain | listable_safe_string)))));
    type == "object" and
    ((keys - [
      "interface_name","netns","mtu","address","dns_mode","dns_address",
      "auto_route","iproute2_table_index","iproute2_rule_index","auto_redirect",
      "auto_redirect_input_mark","auto_redirect_output_mark","auto_redirect_reset_mark",
      "auto_redirect_nfqueue","auto_redirect_iproute2_fallback_rule_index",
      "exclude_mptcp","loopback_address","strict_route","route_address",
      "route_address_set","route_exclude_address","route_exclude_address_set",
      "include_interface","exclude_interface","include_uid","include_uid_range",
      "exclude_uid","exclude_uid_range","include_android_user","include_package",
      "exclude_package","include_mac_address","exclude_mac_address","udp_timeout",
      "udp_mapping","udp_filtering","udp_nat_max","stack","platform",
      "inet4_address","inet6_address","inet4_route_address","inet6_route_address",
      "inet4_route_exclude_address","inet6_route_exclude_address","gso",
      "endpoint_independent_nat","sniff","sniff_override_destination","sniff_timeout",
      "domain_strategy","udp_disable_domain_unmapping"
    ]) | length == 0) and
    (has("inet4_address") | not) and
    (has("inet6_address") | not) and
    (has("inet4_route_address") | not) and
    (has("inet6_route_address") | not) and
    (has("inet4_route_exclude_address") | not) and
    (has("inet6_route_exclude_address") | not) and
    (has("gso") | not) and
    (has("endpoint_independent_nat") | not) and
    (has("sniff") | not) and
    (has("sniff_override_destination") | not) and
    (has("sniff_timeout") | not) and
    (has("domain_strategy") | not) and
    (has("udp_disable_domain_unmapping") | not) and
    (.address | listable_nonempty_safe_string) and
    (.auto_route | type == "boolean") and
    optional_safe_string("interface_name") and
    optional_safe_string("netns") and
    ((has("mtu") | not) or (.mtu | type == "number" and . == floor and . >= 0 and . <= 4294967295)) and
    ((has("dns_mode") | not) or (.dns_mode | type == "string" and IN("disabled","native","hijack"))) and
    optional_listable_safe_string("dns_address") and
    optional_listable_nonnegative_int("iproute2_table_index") and
    optional_listable_nonnegative_int("iproute2_rule_index") and
    optional_bool("auto_redirect") and
    ((.auto_redirect // false) != true or .auto_route == true) and
    optional_mark("auto_redirect_input_mark") and
    optional_mark("auto_redirect_output_mark") and
    optional_mark("auto_redirect_reset_mark") and
    ((has("auto_redirect_nfqueue") | not) or
      (.auto_redirect_nfqueue | type == "number" and . == floor and . >= 0 and . <= 65535)) and
    optional_listable_nonnegative_int("auto_redirect_iproute2_fallback_rule_index") and
    optional_bool("exclude_mptcp") and
    optional_listable_safe_string("loopback_address") and
    optional_bool("strict_route") and
    optional_listable_safe_string("route_address") and
    optional_listable_safe_string("route_address_set") and
    optional_listable_safe_string("route_exclude_address") and
    optional_listable_safe_string("route_exclude_address_set") and
    optional_listable_safe_string("include_interface") and
    optional_listable_safe_string("exclude_interface") and
    optional_listable_uint32("include_uid") and
    optional_uid_range("include_uid_range") and
    optional_listable_uint32("exclude_uid") and
    optional_uid_range("exclude_uid_range") and
    optional_listable_nonnegative_int("include_android_user") and
    optional_listable_safe_string("include_package") and
    optional_listable_safe_string("exclude_package") and
    optional_listable_safe_string("include_mac_address") and
    optional_listable_safe_string("exclude_mac_address") and
    optional_udp_timeout and
    optional_nat("udp_mapping") and
    optional_nat("udp_filtering") and
    ((has("udp_nat_max") | not) or
      (.udp_nat_max | type == "number" and . == floor and . >= 0 and . <= 4294967295)) and
    ((has("stack") | not) or (.stack | type == "string" and IN("","system","gvisor","mixed"))) and
    optional_platform
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

managed_component_cloudflared_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string and length > 0);
    def optional_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and
          ((test("^0x[0-9a-fA-F]{1,8}$")) or
           (test("^[0-9]{1,10}$") and (tonumber <= 4294967295))))));
    def interface_type:
      type == "string" and IN("wifi","cellular","ethernet","other");
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and interface_type) or
         (type == "array" and all(.[]; interface_type))));
    def optional_domain_resolver:
      (has("domain_resolver") | not) or
      (.domain_resolver |
        ((type == "string" and safe_string) or
         (type == "object" and
          ((keys - ["server","timeout","strategy","disable_cache",
            "disable_optimistic_cache","rewrite_ttl","client_subnet"]) | length == 0) and
          (.server | type == "string" and length > 0 and safe_string) and
          ((has("timeout") | not) or (.timeout | safe_string and length > 0)) and
          ((has("strategy") | not) or (.strategy | type == "string" and
            IN("","as_is","prefer_ipv4","prefer_ipv6","ipv4_only","ipv6_only"))) and
          ((has("disable_cache") | not) or (.disable_cache | type == "boolean")) and
          ((has("disable_optimistic_cache") | not) or
            (.disable_optimistic_cache | type == "boolean")) and
          ((has("rewrite_ttl") | not) or
            (.rewrite_ttl | type == "number" and . == floor and . >= 0 and . <= 4294967295)) and
          ((has("client_subnet") | not) or (.client_subnet | safe_string)))));
    def dialer($name):
      (has($name) | not) or
      (.[$name] | type == "object" and
        ((keys - ["detour","bind_interface","inet4_bind_address","inet6_bind_address",
          "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
          "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
          "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
          "network_strategy","network_type","fallback_network_type","fallback_delay"]) | length == 0) and
        optional_safe_string("detour") and optional_safe_string("bind_interface") and
        optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
        optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
        optional_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
        optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
        optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
        optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
        ((has("udp_fragment") | not) or (.udp_fragment | type == "boolean")) and
        optional_domain_resolver and
        ((has("network_strategy") | not) or (.network_strategy | type == "string" and
          IN("","default","hybrid","fallback"))) and
        optional_network_types("network_type") and optional_network_types("fallback_network_type") and
        optional_duration("fallback_delay"));
    type == "object" and
    ((keys - ["token","ha_connections","protocol","post_quantum","edge_ip_version",
      "datagram_version","grace_period","region","control_dialer","tunnel_dialer"]) | length == 0) and
    (.token | type == "string" and length > 0 and safe_string) and
    ((has("ha_connections") | not) or
      (.ha_connections | type == "number" and . == floor and . >= 0 and . <= 2147483647)) and
    ((has("protocol") | not) or (.protocol | type == "string" and IN("","auto","quic","http2","h2mux"))) and
    optional_bool("post_quantum") and
    ((has("edge_ip_version") | not) or (.edge_ip_version | type == "number" and . == floor and IN(0,4,6))) and
    ((has("datagram_version") | not) or (.datagram_version | type == "string" and IN("v2","v3"))) and
    optional_duration("grace_period") and
    optional_safe_string("region") and
    dialer("control_dialer") and dialer("tunnel_dialer")
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Direct, block and bridge outbounds are registered component types too.  Keep
# their small option surfaces typed instead of treating the empty dispatch
# branch below as permission to pass arbitrary JSON through to sing-box.  A
# direct outbound deliberately rejects non-empty detours and the deprecated
# destination/proxy-protocol fields because the 1.14 core rejects them in its
# constructor; route actions are the supported destination-override path.
managed_component_direct_outbound_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonempty_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string and length > 0);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and
          ((test("^0x[0-9a-fA-F]{1,8}$")) or
           (test("^[0-9]{1,10}$") and (tonumber <= 4294967295))))));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and IN("wifi","cellular","ethernet","other")) or
         (type == "array" and length <= 64 and
          all(.[]; type == "string" and IN("wifi","cellular","ethernet","other")) and
          (unique | length) == length)));
    def optional_domain_resolver:
      (has("domain_resolver") | not) or
      (.domain_resolver |
        if type == "string" then safe_string
        elif type == "object" then
          ((keys - ["server","timeout","strategy","disable_cache",
            "disable_optimistic_cache","rewrite_ttl","client_subnet"]) | length == 0) and
          (.server | type == "string" and length > 0 and safe_string) and
          ((has("timeout") | not) or (.timeout | safe_string)) and
          ((has("strategy") | not) or
            (.strategy | type == "string" and
              IN("","as_is","prefer_ipv4","prefer_ipv6","ipv4_only","ipv6_only"))) and
          ((has("disable_cache") | not) or (.disable_cache | type == "boolean")) and
          ((has("disable_optimistic_cache") | not) or
            (.disable_optimistic_cache | type == "boolean")) and
          ((has("rewrite_ttl") | not) or
            (.rewrite_ttl | type == "number" and . == floor and . >= 0 and . <= 4294967295)) and
          ((has("client_subnet") | not) or (.client_subnet | safe_string))
        else false
        end);
    type == "object" and
    ((keys - [
      "bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr",
      "netns","connect_timeout","tcp_fast_open","tcp_multi_path",
      "disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "udp_fragment","domain_resolver","network_strategy","network_type",
      "fallback_network_type","fallback_delay","detour"
    ]) | length == 0) and
    optional_safe_string("bind_interface") and
    optional_nonempty_safe_string("inet4_bind_address") and
    optional_nonempty_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and
    optional_safe_string("protect_path") and
    optional_routing_mark and
    optional_bool("reuse_addr") and
    optional_safe_string("netns") and
    optional_duration("connect_timeout") and
    optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and
    optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and
    ((has("udp_fragment") | not) or (.udp_fragment | type == "boolean")) and
    optional_domain_resolver and
    ((has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"))) and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay") and
    ((has("detour") | not) or (.detour | type == "string" and length == 0))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

managed_component_block_outbound_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e 'type == "object" and length == 0' <<< "${config}" >/dev/null 2>&1
}

managed_component_bridge_outbound_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_index($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    type == "object" and
    ((keys - ["interface","bridge_name","iproute2_table_index","iproute2_rule_index"])
      | length == 0) and
    optional_safe_string("interface") and
    optional_safe_string("bridge_name") and
    optional_index("iproute2_table_index") and
    optional_index("iproute2_rule_index")
  ' <<< "${config}" >/dev/null 2>&1
}

# Component route rules are data owned by the component state store.  Do not
# pass arbitrary objects through to the top-level sing-box route list: an
# unknown field could otherwise survive state/CAS and only fail (or change
# meaning) after publication.  This is the project-facing subset of the
# sing-box 1.14 default/logical rule union and route actions.  Values that are
# intentionally opaque to the project (CIDR/domain expressions and duration
# strings) are still constrained to safe scalar/listable forms.
managed_component_route_rules_validate_json() {
  local rules=${1:-}
  [[ -n "${rules}" ]] || return 1
  jq -e '
    def max_list_items: 64;
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def listable_string:
      ((type == "string" and safe_string) or
       (type == "array" and length > 0 and length <= max_list_items and all(.[]; safe_string) and
        (length == (unique | length))));
    def listable_nonempty_string:
      ((type == "string" and nonempty_safe_string) or
       (type == "array" and length > 0 and length <= max_list_items and all(.[]; nonempty_safe_string) and
        (length == (unique | length))));
    def listable_enum($values):
      ((type == "string" and IN($values[])) or
       (type == "array" and length > 0 and length <= max_list_items and all(.[]; type == "string" and IN($values[])) and
        (length == (unique | length))));
    def optional_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonempty_string($name):
      (has($name) | not) or (.[$name] | nonempty_safe_string);
    def optional_listable_string($name):
      (has($name) | not) or (.[$name] | listable_string);
    def optional_listable_nonempty_string($name):
      (has($name) | not) or (.[$name] | listable_nonempty_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_uint($name; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max);
    def optional_int32($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and
        . >= -2147483648 and . <= 2147483647);
    def optional_listable_int32($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= -2147483648 and . <= 2147483647) or
         (type == "array" and length > 0 and length <= max_list_items and all(.[]; type == "number" and . == floor and
           . >= -2147483648 and . <= 2147483647) and (length == (unique | length)))));
    def optional_listable_uint16($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 65535) or
         (type == "array" and length > 0 and length <= max_list_items and all(.[]; type == "number" and . == floor and
           . >= 0 and . <= 65535) and (length == (unique | length)))));
    def optional_uint32($name): optional_uint($name; 4294967295);
    def optional_duration($name):
      (has($name) | not) or (.[$name] | nonempty_safe_string);
    def optional_strategy($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","as_is","prefer_ipv4","prefer_ipv6","ipv4_only","ipv6_only"));
    def optional_route_network_strategy($name):
      (has($name) | not) or
      (.[$name] | type == "string" and IN("default","hybrid","fallback"));
    def optional_interface_address:
      (has("interface_address") | not) or
      (.interface_address | type == "object" and length <= max_list_items and
        all(to_entries[];
          (.key | nonempty_safe_string) and
          (.value | listable_nonempty_string)));
    def optional_network_interface_address:
      (has("network_interface_address") | not) or
      (.network_interface_address | type == "object" and length <= max_list_items and
        all(to_entries[];
          (.key | type == "string" and IN("wifi","cellular","ethernet","other")) and
          (.value | listable_nonempty_string)));
    def optional_default_interface_address:
      (has("default_interface_address") | not) or
      (.default_interface_address | listable_nonempty_string);
    def optional_match_fields:
      optional_listable_string("inbound") and
      optional_uint("ip_version"; 6) and
      ((has("ip_version") | not) or (.ip_version | IN(4,6))) and
      ((has("network") | not) or (.network | listable_enum(["tcp","udp","icmp"]))) and
      optional_listable_string("auth_user") and
      ((has("protocol") | not) or (.protocol | listable_enum(["tls","http","quic","dns","stun","bittorrent","dtls","ssh","rdp","ntp"]))) and
      optional_listable_string("client") and
      optional_listable_string("domain") and
      optional_listable_string("domain_suffix") and
      optional_listable_string("domain_keyword") and
      optional_listable_string("domain_regex") and
      optional_listable_string("geosite") and
      optional_listable_string("source_geoip") and
      optional_listable_string("geoip") and
      optional_listable_string("source_ip_cidr") and
      optional_bool("source_ip_is_private") and
      optional_listable_string("ip_cidr") and
      optional_bool("ip_is_private") and
      optional_listable_uint16("source_port") and
      optional_listable_string("source_port_range") and
      optional_listable_uint16("port") and
      optional_listable_string("port_range") and
      optional_listable_string("process_name") and
      optional_listable_string("process_path") and
      optional_listable_string("process_path_regex") and
      optional_listable_string("package_name") and
      optional_listable_string("package_name_regex") and
      optional_listable_string("user") and
      optional_listable_int32("user_id") and
      optional_string("clash_mode") and
      ((has("network_type") | not) or (.network_type | listable_enum(["wifi","cellular","ethernet","other"]))) and
      optional_bool("network_is_expensive") and
      optional_bool("network_is_constrained") and
      optional_listable_string("wifi_ssid") and
      optional_listable_string("wifi_bssid") and
      optional_interface_address and
      optional_network_interface_address and
      optional_default_interface_address and
      optional_listable_string("source_mac_address") and
      optional_listable_string("source_hostname") and
      optional_listable_string("preferred_by") and
      optional_listable_string("rule_set") and
      optional_bool("rule_set_ip_cidr_match_source") and
      optional_bool("invert");
    def optional_route_action_fields:
      optional_string("outbound") and
      optional_string("override_address") and
      optional_uint("override_port"; 65535) and
      optional_route_network_strategy("network_strategy") and
      optional_uint32("fallback_delay") and
      optional_bool("udp_disable_domain_unmapping") and
      optional_bool("udp_connect") and
      optional_duration("udp_timeout") and
      optional_bool("tls_fragment") and
      optional_duration("tls_fragment_fallback_delay") and
      optional_bool("tls_record_fragment") and
      optional_string("tls_spoof") and
      ((has("tls_spoof_method") | not) or (.tls_spoof_method | type == "string" and
        IN("wrong-sequence","wrong-checksum","wrong-ack","wrong-md5","wrong-timestamp")));
    def route_options_nonempty:
      ((.override_address // "") != "") or
      ((.override_port // 0) != 0) or
      ((.network_strategy // "") != "") or
      ((.fallback_delay // 0) != 0) or
      ((.udp_disable_domain_unmapping // false) == true) or
      ((.udp_connect // false) == true) or
      ((.udp_timeout // "") != "") or
      ((.tls_fragment // false) == true) or
      ((.tls_fragment_fallback_delay // "") != "") or
      ((.tls_record_fragment // false) == true) or
      ((.tls_spoof // "") != "") or
      ((.tls_spoof_method // "") != "");
    def route_rule($nested; $depth):
      if $depth > 8 then false
      elif type != "object" then false
      elif (($nested and ((keys - [
              "type","mode","rules","invert","inbound","ip_version","network","auth_user",
              "protocol","client","domain","domain_suffix","domain_keyword","domain_regex","geosite",
              "source_geoip","geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private",
              "source_port","source_port_range","port","port_range","process_name","process_path",
              "process_path_regex","package_name","package_name_regex","user","user_id","clash_mode",
              "network_type","network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid",
              "interface_address","network_interface_address","default_interface_address","source_mac_address",
              "source_hostname","preferred_by","rule_set","rule_set_ip_cidr_match_source","invert"
            ]) | length != 0)) or
            ($nested and (.type // "") != "logical" and (has("mode") or has("rules"))) or
            (keys | length > 128)) then false
      elif (($nested | not) and
            ((keys - [
              "type","mode","rules","inbound","ip_version","network","auth_user","protocol","client",
              "domain","domain_suffix","domain_keyword","domain_regex","geosite","source_geoip",
              "geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private",
              "source_port","source_port_range","port","port_range","process_name","process_path",
              "process_path_regex","package_name","package_name_regex","user","user_id","clash_mode",
              "network_type","network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid",
              "interface_address","network_interface_address","default_interface_address","source_mac_address",
              "source_hostname","preferred_by","rule_set","rule_set_ip_cidr_match_source","invert",
              "action","outbound","override_address","override_port","network_strategy","fallback_delay",
              "udp_disable_domain_unmapping","udp_connect","udp_timeout","tls_fragment",
              "tls_fragment_fallback_delay","tls_record_fragment","tls_spoof","tls_spoof_method",
              "method","no_drop","sniffer","timeout","server","strategy","disable_cache",
              "disable_optimistic_cache","rewrite_ttl","client_subnet","remove_client_subnet"
            ]) | length != 0)) then false
      elif (.type // "") == "logical" then
        ((keys - ["type","mode","rules","invert","action","outbound","override_address",
          "override_port","network_strategy","fallback_delay","udp_disable_domain_unmapping",
          "udp_connect","udp_timeout","tls_fragment","tls_fragment_fallback_delay",
          "tls_record_fragment","tls_spoof","tls_spoof_method","method","no_drop","sniffer",
          "timeout","server","strategy","disable_cache","disable_optimistic_cache","rewrite_ttl",
          "client_subnet","remove_client_subnet"]) | length == 0) and
        (.mode | type == "string" and IN("and","or")) and
        (.rules | type == "array" and length > 0 and length <= 64 and all(.[]; route_rule(true; ($depth + 1)))) and
        optional_bool("invert") and
        (if $nested then
           (has("action") | not)
         else
           (del(.type,.mode,.rules,.invert) | route_rule(false; $depth))
         end)
      elif ((.type // "") == "" or .type == "default") then
        (has("mode") | not) and (has("rules") | not) and
        optional_match_fields and
        ((has("action") | not) or (.action | type == "string" and
          IN("route","route-options","direct","bypass","reject","hijack-dns","sniff","resolve"))) and
        (if ((.action // "route") | IN("route","bypass")) then
           optional_route_action_fields and
           ((has("method") | not) and (has("no_drop") | not) and (has("sniffer") | not)) and
           ((has("timeout") | not) and (has("server") | not) and (has("strategy") | not) and
            (has("disable_cache") | not) and (has("disable_optimistic_cache") | not) and
            (has("rewrite_ttl") | not) and (has("client_subnet") | not) and (has("remove_client_subnet") | not))
         elif .action == "route-options" then
           (has("outbound") | not) and optional_route_action_fields and route_options_nonempty and
           ((.tls_fragment // false) != true or (.tls_record_fragment // false) != true) and
           ((has("method") | not) and (has("no_drop") | not) and (has("sniffer") | not)) and
           ((has("timeout") | not) and (has("server") | not) and (has("strategy") | not) and
            (has("disable_cache") | not) and (has("disable_optimistic_cache") | not) and
            (has("rewrite_ttl") | not) and (has("client_subnet") | not) and (has("remove_client_subnet") | not))
         elif .action == "reject" then
           ((has("method") | not) or (.method | type == "string" and IN("","default","drop","reply"))) and
           optional_bool("no_drop") and
           ((.method // "") != "drop" or (.no_drop // false) != true) and
           ((keys - ["type","inbound","ip_version","network","auth_user","protocol","client",
             "domain","domain_suffix","domain_keyword","domain_regex","geosite","source_geoip",
             "geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private","source_port",
             "source_port_range","port","port_range","process_name","process_path","process_path_regex",
             "package_name","package_name_regex","user","user_id","clash_mode","network_type",
             "network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid","interface_address",
             "network_interface_address","default_interface_address","source_mac_address","source_hostname",
             "preferred_by","rule_set","rule_set_ip_cidr_match_source","invert","action","method","no_drop"])
             | length == 0)
         elif .action == "hijack-dns" then
           ((keys - ["type","inbound","ip_version","network","auth_user","protocol","client",
             "domain","domain_suffix","domain_keyword","domain_regex","geosite","source_geoip",
             "geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private","source_port",
             "source_port_range","port","port_range","process_name","process_path","process_path_regex",
             "package_name","package_name_regex","user","user_id","clash_mode","network_type",
             "network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid","interface_address",
             "network_interface_address","default_interface_address","source_mac_address","source_hostname",
             "preferred_by","rule_set","rule_set_ip_cidr_match_source","invert","action"])
             | length == 0)
         elif .action == "sniff" then
           ((has("sniffer") | not) or (.sniffer | listable_enum(["tls","http","quic","dns","stun","bittorrent","dtls","ssh","rdp","ntp"]))) and
           optional_duration("timeout") and
           ((keys - ["type","inbound","ip_version","network","auth_user","protocol","client",
             "domain","domain_suffix","domain_keyword","domain_regex","geosite","source_geoip",
             "geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private","source_port",
             "source_port_range","port","port_range","process_name","process_path","process_path_regex",
             "package_name","package_name_regex","user","user_id","clash_mode","network_type",
             "network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid","interface_address",
             "network_interface_address","default_interface_address","source_mac_address","source_hostname",
             "preferred_by","rule_set","rule_set_ip_cidr_match_source","invert","action","sniffer","timeout"])
             | length == 0)
         elif .action == "resolve" then
           optional_string("server") and optional_duration("timeout") and optional_strategy("strategy") and
           optional_bool("disable_cache") and optional_bool("disable_optimistic_cache") and
           optional_uint32("rewrite_ttl") and optional_string("client_subnet") and
           ((keys - ["type","inbound","ip_version","network","auth_user","protocol","client",
             "domain","domain_suffix","domain_keyword","domain_regex","geosite","source_geoip",
             "geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private","source_port",
             "source_port_range","port","port_range","process_name","process_path","process_path_regex",
             "package_name","package_name_regex","user","user_id","clash_mode","network_type",
             "network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid","interface_address",
             "network_interface_address","default_interface_address","source_mac_address","source_hostname",
             "preferred_by","rule_set","rule_set_ip_cidr_match_source","invert","action","server","timeout",
             "strategy","disable_cache","disable_optimistic_cache","rewrite_ttl","client_subnet"])
             | length == 0)
         elif .action == "direct" then
           ((keys - ["type","inbound","ip_version","network","auth_user","protocol","client",
             "domain","domain_suffix","domain_keyword","domain_regex","geosite","source_geoip",
             "geoip","source_ip_cidr","source_ip_is_private","ip_cidr","ip_is_private","source_port",
             "source_port_range","port","port_range","process_name","process_path","process_path_regex",
             "package_name","package_name_regex","user","user_id","clash_mode","network_type",
             "network_is_expensive","network_is_constrained","wifi_ssid","wifi_bssid","interface_address",
             "network_interface_address","default_interface_address","source_mac_address","source_hostname",
             "preferred_by","rule_set","rule_set_ip_cidr_match_source","invert","action"])
             | length == 0)
         else false end)
      else false end;
    type == "array" and length <= 128 and all(.[]; route_rule(false; 0))
  ' <<< "${rules}" >/dev/null 2>&1 || return 1
}

managed_component_rule_set_inline_config_validate_json() {
  local config=${1:-} rules
  [[ -n "${config}" ]] || return 1
  jq -e '
    type == "object" and
    ((keys - ["rules"]) | length == 0) and
    (.rules | type == "array" and length > 0 and length <= 128) and
    (.rules as $rules |
      ([ $rules[] | .. | objects | keys[] ] |
        any(.[]; IN(
          "action","outbound","override_address","override_port","network_strategy",
          "fallback_delay","udp_disable_domain_unmapping","udp_connect","udp_timeout",
          "tls_fragment","tls_fragment_fallback_delay","tls_record_fragment","tls_spoof",
          "tls_spoof_method","method","no_drop","sniffer","timeout","server","strategy",
          "disable_cache","disable_optimistic_cache","rewrite_ttl","client_subnet",
          "remove_client_subnet"
        )) | not))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
  rules=$(jq -c '[.rules[] | . + {action:"route",outbound:"direct"}]' <<< "${config}") || return 1
  managed_component_route_rules_validate_json "${rules}"
}

managed_component_rule_set_local_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_path:
      type == "string" and length > 1 and length <= 4096 and startswith("/") and
      (any(explode[]; . < 32 or . == 127) | not);
    type == "object" and
    ((keys - ["format","path"]) | length == 0) and
    (.format | type == "string" and IN("source","binary")) and
    (.path | safe_path)
  ' <<< "${config}" >/dev/null 2>&1
}

managed_component_rule_set_remote_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and length > 0 and length <= 4096 and
      (any(explode[]; . < 32 or . == 127) | not);
    def safe_path:
      safe_string and startswith("/") and . != "/";
    type == "object" and
    ((keys - ["format","url","initial_path","http_client","update_interval"]) | length == 0) and
    (.format | type == "string" and IN("source","binary")) and
    (.url | safe_string and (startswith("http://") or startswith("https://")) and
      (contains("#") | not)) and
    ((has("initial_path") | not) or (.initial_path | safe_path)) and
    ((has("http_client") | not) or
      (.http_client | type == "string" and length > 0 and length <= 128 and
        (any(explode[]; . < 32 or . == 127) | not))) and
    ((has("update_interval") | not) or
      (.update_interval | type == "string" and length > 0 and length <= 64 and
        (any(explode[]; . < 32 or . == 127) | not)))
  ' <<< "${config}" >/dev/null 2>&1
}
