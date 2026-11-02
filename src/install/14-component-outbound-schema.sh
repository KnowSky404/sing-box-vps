
# --- Managed advanced components -------------------------------------------------
# Advanced inbounds, endpoints, outbounds, certificate providers and network
# namespaces are stored as typed JSON records.
# They intentionally have their own CAS state file so that adding a TUN or an
# endpoint cannot silently change the share-link protocol index.  The config
# graph validator remains the final reference/dep-cycle gate; these helpers
# provide the state, identity, exposure and transaction guards before a
# candidate reaches that validator.
managed_component_state_default_json() {
  jq -cn --argjson schema "${SB_COMPONENT_STATE_SCHEMA_VERSION}" \
    '{schema_version:$schema,revision:0,components:[]}'
}

managed_component_state_id_valid() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]
}

managed_component_tag_valid() {
  local tag=${1:-}
  [[ -n "${tag}" && ${#tag} -le 128 && "${tag}" != *[[:space:]]* &&
    "${tag}" != *$'\n'* && "${tag}" != *$'\r'* ]]
}

# Certificate providers and network namespaces live in their own top-level
# arrays.  Keep the small subset managed by this script typed instead of
# treating either namespace as arbitrary core JSON.  ACME credentials are
# validated for shape only; they are returned only by the explicit sensitive
# component export path.
managed_component_certificate_provider_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonempty_safe_string($name):
      (has($name) | not) or (.[$name] | nonempty_safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_port($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 65535);
    def optional_dns01:
      (has("dns01_challenge") | not) or
      (.dns01_challenge | type == "object" and
        ((keys - ["provider","api_token"]) | length == 0) and
        (.provider | nonempty_safe_string) and
        ((has("api_token") | not) or (.api_token | safe_string)));
    def optional_external_account:
      (has("external_account") | not) or
      (.external_account | type == "object" and
        ((keys - ["key_id","mac_key"]) | length == 0) and
        (.key_id | nonempty_safe_string) and
        (.mac_key | nonempty_safe_string));
    type == "object" and
    ((keys - [
      "domain","data_directory","default_server_name","email","provider",
      "disable_http_challenge","disable_tls_alpn_challenge",
      "alternative_http_port","alternative_tls_port","external_account",
      "dns01_challenge","http_client"
    ]) | length == 0) and
    (.domain | type == "array" and length > 0 and length <= 128 and
      all(.[]; nonempty_safe_string and length <= 253)) and
    optional_nonempty_safe_string("data_directory") and
    optional_safe_string("default_server_name") and
    optional_safe_string("email") and
    optional_safe_string("provider") and
    optional_bool("disable_http_challenge") and
    optional_bool("disable_tls_alpn_challenge") and
    optional_port("alternative_http_port") and
    optional_port("alternative_tls_port") and
    optional_external_account and
    optional_dns01 and
    ((has("http_client") | not) or (.http_client | nonempty_safe_string))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate a shared top-level HTTP client against the sing-box 1.14 HTTPClient
# option.  Shared clients are referenced by tag from ACME, remote rule sets,
# service dashboards and route defaults; they are not HTTP proxy outbounds and
# therefore intentionally have their own bounded schema.  Keep the supported
# HTTP/TLS/Dial fields typed so a shared client cannot become an arbitrary JSON
# escape hatch during a component transaction.
managed_component_http_client_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and length <= 4096 and
      (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonempty_safe_string($name):
      (has($name) | not) or (.[$name] | nonempty_safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_memory($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 9007199254740991) or
         (type == "string" and length <= 64 and
          (any(explode[]; . < 32 or . == 127) | not))));
    def byte_array:
      type == "array" and length <= 1024 and
      all(.[]; type == "number" and . == floor and . >= 0 and . <= 255);
    def optional_listable_bytes($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and safe_string) or byte_array or
         (type == "array" and length <= 128 and
          all(.[]; (type == "string" and safe_string) or byte_array))));
    def optional_listable_safe_string($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and safe_string) or
         (type == "array" and length <= 128 and all(.[]; safe_string))));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or
          IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and length <= 4 and
          all(.[]; type == "string" and
            IN("wifi","cellular","ethernet","other")) and
          (length == (unique | length)))));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and length <= 32 and
          (length == 0 or test("^(0x[0-9a-fA-F]+|[0-9]+)$")))));
    def optional_header_map:
      (has("headers") | not) or
      (.headers | type == "object" and length <= 128 and
        all(to_entries[];
          (.key | type == "string" and length > 0 and length <= 256 and
            test("^[A-Za-z0-9!#$%&\u0027+.^_\u0060|~-]+$")) and
          (.value |
            ((type == "string" and safe_string) or
             (type == "array" and length <= 32 and
              all(.[]; safe_string))))));
    def optional_tls_listable_curve($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and IN("P256","P384","P521","X25519","X25519MLKEM768")) or
         (type == "array" and length <= 128 and
          all(.[]; type == "string" and IN("P256","P384","P521","X25519","X25519MLKEM768")))));
    def optional_domain_resolver:
      (has("domain_resolver") | not) or
      (.domain_resolver |
        if type == "string" then safe_string
        elif type == "object" then
          ((keys - ["server","timeout","strategy","disable_cache",
            "disable_optimistic_cache","rewrite_ttl","client_subnet"]) | length == 0) and
          (.server | nonempty_safe_string) and
          optional_duration("timeout") and
          ((has("strategy") | not) or
            (.strategy | type == "string" and
              IN("","as_is","prefer_ipv4","prefer_ipv6","ipv4_only","ipv6_only"))) and
          optional_bool("disable_cache") and
          optional_bool("disable_optimistic_cache") and
          ((has("rewrite_ttl") | not) or
            (.rewrite_ttl | type == "number" and . == floor and . >= 0 and
              . <= 4294967295)) and
          optional_safe_string("client_subnet")
        else false end);
    def optional_tls:
      (has("tls") | not) or
      (.tls | type == "object" and
        ((keys - [
          "enabled","engine","disable_sni","server_name","insecure","alpn",
          "min_version","max_version","cipher_suites","curve_preferences",
          "certificate","certificate_path","certificate_public_key_sha256",
          "client_certificate","client_certificate_path","client_key","client_key_path",
          "fragment","fragment_fallback_delay","record_fragment","spoof","spoof_method",
          "kernel_tx","kernel_rx","handshake_timeout","ech","utls","reality"
        ]) | length == 0) and
        optional_bool("enabled") and
        ((has("engine") | not) or
          (.engine | type == "string" and IN("","go","apple","windows"))) and
        optional_bool("disable_sni") and
        optional_safe_string("server_name") and
        optional_bool("insecure") and
        optional_listable_safe_string("alpn") and
        ((has("min_version") | not) or
          (.min_version | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
        ((has("max_version") | not) or
          (.max_version | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
        optional_listable_safe_string("cipher_suites") and
        optional_tls_listable_curve("curve_preferences") and
        optional_listable_safe_string("certificate") and
        optional_safe_string("certificate_path") and
        optional_listable_bytes("certificate_public_key_sha256") and
        optional_listable_safe_string("client_certificate") and
        optional_safe_string("client_certificate_path") and
        optional_listable_safe_string("client_key") and
        optional_safe_string("client_key_path") and
        optional_bool("fragment") and
        optional_duration("fragment_fallback_delay") and
        optional_bool("record_fragment") and
        optional_safe_string("spoof") and
        ((has("spoof_method") | not) or
          (.spoof_method | type == "string" and IN("","wrong-sequence",
            "wrong-checksum","wrong-ack","wrong-md5","wrong-timestamp"))) and
        optional_bool("kernel_tx") and
        optional_bool("kernel_rx") and
        optional_duration("handshake_timeout") and
        ((has("ech") | not) or
          (.ech | type == "object" and
            ((keys - ["enabled","config","config_path","query_server_name",
              "pq_signature_schemes_enabled","dynamic_record_sizing_disabled"]) | length == 0) and
            optional_bool("enabled") and optional_listable_safe_string("config") and
            optional_safe_string("config_path") and optional_safe_string("query_server_name") and
            optional_bool("pq_signature_schemes_enabled") and
            optional_bool("dynamic_record_sizing_disabled"))) and
        ((has("utls") | not) or
          (.utls | type == "object" and
            ((keys - ["enabled","fingerprint"]) | length == 0) and
            optional_bool("enabled") and
            ((has("fingerprint") | not) or
              (.fingerprint | type == "string" and IN("","chrome_psk","chrome_psk_shuffle",
                "chrome_padding_psk_shuffle","chrome_pq","chrome_pq_psk","chrome",
                "firefox","edge","safari","360","qq","ios","android","random","randomized"))))) and
        ((has("reality") | not) or
          (.reality | type == "object" and
            ((keys - ["enabled","public_key","short_id"]) | length == 0) and
            optional_bool("enabled") and optional_safe_string("public_key") and
            optional_safe_string("short_id"))));
    type == "object" and
    ((keys - [
      "engine","version","disable_version_fallback","headers",
      "idle_timeout","keep_alive_period","stream_receive_window",
      "connection_receive_window","max_concurrent_streams","initial_packet_size",
      "disable_path_mtu_discovery","tls","detour","bind_interface",
      "inet4_bind_address","inet6_bind_address","bind_address_no_port",
      "protect_path","routing_mark","reuse_addr","netns","connect_timeout",
      "tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","udp_fragment","domain_resolver","network_strategy",
      "network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    ((has("engine") | not) or (.engine | type == "string" and IN("","go","apple"))) and
    ((has("version") | not) or
      (.version | type == "number" and . == floor and IN(0,1,2,3))) and
    optional_bool("disable_version_fallback") and
    optional_header_map and
    optional_duration("idle_timeout") and
    optional_duration("keep_alive_period") and
    optional_memory("stream_receive_window") and
    optional_memory("connection_receive_window") and
    optional_nonnegative_int("max_concurrent_streams") and
    optional_nonnegative_int("initial_packet_size") and
    optional_bool("disable_path_mtu_discovery") and
    optional_tls and
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
    optional_bool("udp_fragment") and
    optional_domain_resolver and
    ((has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("default","hybrid","fallback"))) and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay") and
    # Version 1 is HTTP/1 only; version 2 is the default; version 3 uses the
    # QUIC fields.  Keep variant-only fields out of state before core check.
    ((((if (.version? == 0) then 2 else (.version // 2) end) == 1) and
       (has("idle_timeout") | not) and
       (has("keep_alive_period") | not) and
       (has("stream_receive_window") | not) and
       (has("connection_receive_window") | not) and
       (has("max_concurrent_streams") | not) and
       (has("initial_packet_size") | not) and
       (has("disable_path_mtu_discovery") | not)) or
      ((if (.version? == 0) then 2 else (.version // 2) end) != 1)) and
    (((if (.version? == 0) then 2 else (.version // 2) end) == 3) or
      ((has("initial_packet_size") | not) and
       (has("disable_path_mtu_discovery") | not)))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

managed_component_network_namespace_config_validate_json() {
  local type=${1:-} config=${2:-}
  [[ -n "${type}" && -n "${config}" ]] || return 1
  case "${type}" in
    default)
      jq -e '
        type == "object" and
        ((keys - ["path"]) | length == 0) and
        (.path | type == "string" and length > 0 and startswith("/") and
          (any(explode[]; . < 32 or . == 127) | not))
      ' <<< "${config}" >/dev/null 2>&1
      ;;
    unshare)
      jq -e 'type == "object" and length == 0' <<< "${config}" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

# Validate the SSH outbound contract instead of treating its config as an
# unbounded core-JSON passthrough.  The allowlist follows the sing-box 1.14
# SSHOutboundOptions plus its shared Dial Fields.  Secrets are only inspected
# for shape here; this function never prints the input or embeds it in an
# error.  An empty host_key remains an explicit upstream-compatible choice
# (sing-box accepts any host key), while inventory reports that weaker mode.
managed_component_ssh_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def listable_nonempty_string:
      (type == "string" and length > 0) or
      (type == "array" and length > 0 and
        all(.[]; type == "string" and length > 0));
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_string($name):
      (has($name) | not) or (.[$name] | type == "string");
    def optional_listable_safe_string($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and safe_string) or
         (type == "array" and all(.[]; nonempty_safe_string))));
    def optional_listable_private_key($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string") or
         (type == "array" and all(.[]; type == "string" and length > 0))));
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    type == "object" and
    ((keys - [
      "server","server_port","user","password","private_key",
      "private_key_path","private_key_passphrase","host_key",
      "host_key_algorithms","client_version","cipher","mac",
      "kex_algorithm","detour","bind_interface","inet4_bind_address",
      "inet6_bind_address","bind_address_no_port","protect_path","routing_mark",
      "reuse_addr","netns","connect_timeout","tcp_fast_open",
      "tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type",
      "fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    ((has("server_port") | not) or
      (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
    optional_safe_string("user") and
    optional_string("password") and
    optional_listable_private_key("private_key") and
    optional_safe_string("private_key_path") and
    optional_string("private_key_passphrase") and
    optional_listable_safe_string("host_key") and
    optional_listable_safe_string("host_key_algorithms") and
    optional_safe_string("client_version") and
    optional_listable_safe_string("cipher") and
    optional_listable_safe_string("mac") and
    optional_listable_safe_string("kex_algorithm") and
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
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay") and
    (
      ((.password? // "") | type == "string" and length > 0) or
      ((.private_key? // null) |
        if . == null then false else listable_nonempty_string end) or
      ((.private_key_path? // "") | nonempty_safe_string)
    ) and
    (
      ((.private_key_passphrase? // "") | type == "string" and length == 0) or
      ((.private_key? // null) |
        if . == null then false else listable_nonempty_string end) or
      ((.private_key_path? // "") | nonempty_safe_string)
    )
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the Tor outbound contract against sing-box 1.14.0.  Tor has no
# server/authentication fields: the managed record controls the Tor runtime
# (external executable or embedded build), its torrc map, extra arguments and
# shared Dial Fields.  The embedded form is accepted for upstream
# compatibility, but inventory marks it unverified because the default
# sing-box build does not include embedded Tor.
managed_component_tor_config_validate_json() {
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
      (has($name) | not) or (.[$name] | safe_string);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_extra_args:
      (has("extra_args") | not) or
      (.extra_args | type == "array" and all(.[]; safe_string));
    def optional_torrc:
      (has("torrc") | not) or
      (.torrc | type == "object" and
        all(to_entries[]; (.key | safe_string) and (.value | safe_string)));
    type == "object" and
    ((keys - [
      "executable_path","extra_args","data_directory","torrc",
      "detour","bind_interface","inet4_bind_address",
      "inet6_bind_address","bind_address_no_port","protect_path",
      "routing_mark","reuse_addr","netns","connect_timeout",
      "tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment",
      "domain_resolver","network_strategy","network_type",
      "fallback_network_type","fallback_delay"
    ]) | length == 0) and
    optional_safe_string("executable_path") and
    optional_extra_args and
    optional_safe_string("data_directory") and
    optional_torrc and
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
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the SOCKS outbound contract against sing-box 1.14.0.  This is a
# managed client-side dialer, not a share-link inbound: keep the upstream
# server/auth/network/UoT fields and the shared Dial Fields, while rejecting
# deprecated domain_strategy and arbitrary JSON passthrough before CAS or
# takeover publication.
managed_component_socks_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_network($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("tcp","udp"))) or
         (type == "array" and all(.[]; type == "string" and IN("tcp","udp")))));
    def optional_udp_over_tcp:
      (has("udp_over_tcp") | not) or
      (.udp_over_tcp |
        (type == "boolean" or
         (type == "object" and
          ((keys - ["enabled","version"]) | length == 0) and
          ((has("enabled") | not) or (.enabled | type == "boolean")) and
          ((has("version") | not) or
            (.version | type == "number" and . == floor and . >= 1 and . <= 2)))));
    type == "object" and
    ((keys - [
      "server","server_port","version","username","password","network",
      "udp_over_tcp","detour","bind_interface","inet4_bind_address",
      "inet6_bind_address","bind_address_no_port","protect_path",
      "routing_mark","reuse_addr","netns","connect_timeout","tcp_fast_open",
      "tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    ((has("version") | not) or (.version | type == "string" and IN("","4","4a","5"))) and
    optional_safe_string("username") and
    optional_safe_string("password") and
    optional_network("network") and
    optional_udp_over_tcp and
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
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the HTTP outbound contract against sing-box 1.14.0.  HTTP is a
# TCP-only upstream proxy; its optional TLS and header maps are still typed
# here so nested JSON cannot become an unbounded passthrough.  Deprecated
# Dial/TLS fields are rejected before state/CAS or live takeover publication.
managed_component_http_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def listable_safe_string:
      (safe_string or (type == "array" and all(.[]; safe_string)));
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_listable_safe_string($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_header_map:
      (has("headers") | not) or
      (.headers | type == "object" and
        all(to_entries[];
          (.key | type == "string" and length > 0 and
            (test("^[A-Za-z0-9!#$%&\u0027+.^_\u0060|~-]+$") )) and
          (.value | listable_safe_string)));
    def optional_domain_resolver:
      (has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object");
    def optional_tls_listable_curve($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and IN("P256","P384","P521","X25519","X25519MLKEM768")) or
         (type == "array" and all(.[]; type == "string" and
           IN("P256","P384","P521","X25519","X25519MLKEM768")))));
    def optional_ech:
      (has("ech") | not) or
      (.ech | type == "object" and
        ((keys - ["enabled","config","config_path","query_server_name"]) | length == 0) and
        optional_bool("enabled") and
        optional_listable_safe_string("config") and
        optional_safe_string("config_path") and
        optional_safe_string("query_server_name"));
    def optional_utls:
      (has("utls") | not) or
      (.utls | type == "object" and
        ((keys - ["enabled","fingerprint"]) | length == 0) and
        optional_bool("enabled") and
        ((has("fingerprint") | not) or
          (.fingerprint | type == "string" and IN("","chrome_psk","chrome_psk_shuffle",
            "chrome_padding_psk_shuffle","chrome_pq","chrome_pq_psk","chrome",
            "firefox","edge","safari","360","qq","ios","android","random","randomized"))));
    def optional_reality:
      (has("reality") | not) or
      (.reality | type == "object" and
        ((keys - ["enabled","public_key","short_id"]) | length == 0) and
        optional_bool("enabled") and
        optional_safe_string("public_key") and
        optional_safe_string("short_id"));
    def optional_tls:
      (has("tls") | not) or
      (.tls | type == "object" and
        ((keys - [
          "enabled","engine","disable_sni","server_name","insecure","alpn",
          "min_version","max_version","cipher_suites","curve_preferences",
          "certificate","certificate_path","certificate_public_key_sha256",
          "client_certificate","client_certificate_path","client_key","client_key_path",
          "fragment","fragment_fallback_delay","record_fragment","spoof","spoof_method",
          "kernel_tx","kernel_rx","handshake_timeout","ech","utls","reality"
        ]) | length == 0) and
        optional_bool("enabled") and
        ((has("engine") | not) or (.engine | type == "string" and IN("","go","apple","windows"))) and
        optional_bool("disable_sni") and
        optional_safe_string("server_name") and
        optional_bool("insecure") and
        optional_listable_safe_string("alpn") and
        ((has("min_version") | not) or (.min_version | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
        ((has("max_version") | not) or (.max_version | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
        optional_listable_safe_string("cipher_suites") and
        optional_tls_listable_curve("curve_preferences") and
        optional_listable_safe_string("certificate") and
        optional_safe_string("certificate_path") and
        optional_listable_safe_string("certificate_public_key_sha256") and
        optional_listable_safe_string("client_certificate") and
        optional_safe_string("client_certificate_path") and
        optional_listable_safe_string("client_key") and
        optional_safe_string("client_key_path") and
        optional_bool("fragment") and
        optional_duration("fragment_fallback_delay") and
        optional_bool("record_fragment") and
        optional_safe_string("spoof") and
        ((has("spoof_method") | not) or (.spoof_method | type == "string" and
          IN("","wrong-sequence","wrong-checksum","wrong-ack","wrong-md5","wrong-timestamp"))) and
        optional_bool("kernel_tx") and
        optional_bool("kernel_rx") and
        optional_duration("handshake_timeout") and
        optional_ech and optional_utls and optional_reality);
    type == "object" and
    ((keys - [
      "server","server_port","username","password","path","headers","tls",
      "detour","bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
      "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    optional_safe_string("username") and
    optional_safe_string("password") and
    optional_safe_string("path") and
    optional_header_map and optional_tls and
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
    optional_bool("udp_fragment") and
    optional_domain_resolver and
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the Shadowsocks outbound contract against sing-box 1.14.0.  Keep
# the upstream method/password, plugin, network, UDP-over-TCP and multiplex
# shapes typed while rejecting deprecated Dial Fields and arbitrary nested
# JSON before state/CAS or takeover publication.  SS2022 key sizes are
# checked below after strict base64 decoding because the core derives the key
# from the decoded password bytes.
managed_component_shadowsocks_config_validate_json() {
  local config=${1:-} method password password_bytes
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_network:
      (has("network") | not) or
      (.network |
        ((type == "string" and (length == 0 or IN("tcp","udp"))) or
         (type == "array" and all(.[]; type == "string" and IN("tcp","udp")))));
    def optional_udp_over_tcp:
      (has("udp_over_tcp") | not) or
      (.udp_over_tcp |
        (type == "boolean" or
         (type == "object" and
          ((keys - ["enabled","version"]) | length == 0) and
          ((has("enabled") | not) or (.enabled | type == "boolean")) and
          ((has("version") | not) or
            (.version | type == "number" and . == floor and . >= 1 and . <= 2)))));
    def optional_brutal:
      (has("brutal") | not) or
      (.brutal | type == "object" and
        ((keys - ["enabled","up_mbps","down_mbps"]) | length == 0) and
        optional_bool("enabled") and
        optional_nonnegative_int("up_mbps") and
        optional_nonnegative_int("down_mbps"));
    def optional_multiplex:
      (has("multiplex") | not) or
      (.multiplex | type == "object" and
        ((keys - ["enabled","protocol","max_connections","min_streams",
          "max_streams","padding","brutal"]) | length == 0) and
        optional_bool("enabled") and
        ((has("protocol") | not) or
          (.protocol | type == "string" and IN("","h2mux","smux","yamux"))) and
        optional_nonnegative_int("max_connections") and
        optional_nonnegative_int("min_streams") and
        optional_nonnegative_int("max_streams") and
        optional_bool("padding") and optional_brutal);
    type == "object" and
    ((keys - [
      "server","server_port","method","password","plugin","plugin_opts",
      "network","udp_over_tcp","multiplex","detour","bind_interface",
      "inet4_bind_address","inet6_bind_address","bind_address_no_port",
      "protect_path","routing_mark","reuse_addr","netns","connect_timeout",
      "tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","udp_fragment","domain_resolver","network_strategy",
      "network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    (.method | type == "string" and IN(
      "none","aes-128-gcm","aes-192-gcm","aes-256-gcm",
      "chacha20-ietf-poly1305","xchacha20-ietf-poly1305",
      "2022-blake3-aes-128-gcm","2022-blake3-aes-256-gcm",
      "2022-blake3-chacha20-poly1305","aes-128-ctr","aes-192-ctr",
      "aes-256-ctr","aes-128-cfb","aes-192-cfb","aes-256-cfb",
      "rc4-md5","chacha20-ietf","xchacha20")) and
    (.password | safe_string) and
    ((has("plugin") | not) or
      (.plugin | type == "string" and IN("","obfs-local","v2ray-plugin"))) and
    optional_safe_string("plugin_opts") and optional_network and
    optional_udp_over_tcp and optional_multiplex and
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
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  method=$(jq -er '.method' <<< "${config}") || return 1
  password=$(jq -er '.password' <<< "${config}") || return 1
  if [[ "${method}" == 2022-* ]]; then
    [[ "${password}" =~ ^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$ ]] || return 1
    password_bytes=$(LC_ALL=C printf '%s' "${password}" |
      LC_ALL=C base64 -d | LC_ALL=C wc -c) || return 1
    if [[ "${method}" == 2022-blake3-aes-128-gcm ]]; then
      ((password_bytes == 16)) || return 1
    else
      ((password_bytes == 32)) || return 1
    fi
  elif [[ "${method}" != "none" && -z "${password}" ]]; then
    return 1
  fi
}

# Validate the AnyTLS outbound contract against sing-box 1.14.0.  AnyTLS has
# a deliberately small protocol-specific surface: server/port/password,
# optional session tuning and client metadata, mandatory outbound TLS, and the
# shared Dial Fields.  It does not expose a configurable network, transport or
# multiplex object; unknown fields must therefore fail before state/CAS or
# takeover publication.  The target AnyTLS adapter also rejects TCP fast open
# when enabled because its lazy connection path cannot safely use it.
managed_component_anytls_config_validate_json() {
  local config=${1:-} tls tls_record
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    type == "object" and
    ((keys - [
      "server","server_port","password","idle_session_check_interval",
      "idle_session_timeout","min_idle_session","client_metadata","tls",
      "detour","bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr",
      "netns","connect_timeout","tcp_fast_open","tcp_multi_path",
      "disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "udp_fragment","domain_resolver","network_strategy","network_type",
      "fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    (.password | nonempty_safe_string) and
    optional_duration("idle_session_check_interval") and
    optional_duration("idle_session_timeout") and
    optional_nonnegative_int("min_idle_session") and
    optional_safe_string("client_metadata") and
    optional_bool("tcp_fast_open") and
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
    optional_bool("tcp_multi_path") and
    optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and
    ((has("udp_fragment") | not) or (.udp_fragment | type == "boolean")) and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay") and
    (.tls | (type == "object" and .enabled == true))
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  # Reuse the recursive outbound-TLS validator used by HTTP/V2Ray clients so
  # AnyTLS cannot carry an unbounded nested TLS object.
  tls=$(jq -c '.tls' <<< "${config}") || return 1
  tls_record=$(jq -cn --argjson tls "${tls}" \
    '{server:"anytls-tls",server_port:1,tls:$tls}') || return 1
  managed_component_http_config_validate_json "${tls_record}" || return 1

  # protocol/anytls/outbound.go rejects TCP fast open=true on the lazy
  # connection path; preserve that runtime safety boundary in state.
  jq -e '((.tcp_fast_open // false) != true)' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the Snell outbound contract against sing-box 1.14.0.  The outbound
# discriminator is version 4 or 6 (the inbound uses the corresponding wire
# versions 5 and 6): v4 exposes HTTP obfuscation, while v6 exposes traffic
# shaping.  Keep the PSK/userkey, network list and shared Dial Fields typed;
# version-crossed fields and deprecated Dial Fields must fail before state/CAS
# or takeover publication.
managed_component_snell_config_validate_json() {
  local config=${1:-} version
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_network:
      (has("network") | not) or
      (.network |
        ((type == "string" and (length == 0 or IN("tcp","udp"))) or
         (type == "array" and length <= 2 and
           all(.[]; type == "string" and IN("tcp","udp")) and
           (length == (unique | length)))));
    type == "object" and
    ((keys - [
      "server","server_port","version","psk","userkey","reuse","network",
      "obfs_mode","obfs_host","mode","detour","bind_interface",
      "inet4_bind_address","inet6_bind_address","bind_address_no_port",
      "protect_path","routing_mark","reuse_addr","netns","connect_timeout",
      "tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    (.version | type == "number" and . == floor and IN(4,6)) and
    (.psk | nonempty_safe_string and utf8bytelength <= 255) and
    ((has("userkey") | not) or
      (.userkey | safe_string and utf8bytelength <= 255)) and
    optional_bool("reuse") and
    optional_network and
    optional_safe_string("obfs_mode") and
    optional_safe_string("obfs_host") and
    optional_safe_string("mode") and
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
    optional_network_strategy and
    optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  version=$(jq -er '.version' <<< "${config}") || return 1
  if [[ "${version}" == 4 ]]; then
    jq -e '
      (has("mode") | not) and
      ((.obfs_mode // "") | IN("","none","http")) and
      ((.obfs_host // "") | type == "string" and utf8bytelength <= 255) and
      (((.obfs_mode // "") == "http") or ((.obfs_host // "") == ""))
    ' <<< "${config}" >/dev/null 2>&1 || return 1
  else
    jq -e '
      (has("obfs_mode") | not) and
      (has("obfs_host") | not) and
      ((.obfs_mode // "") == "") and
      ((.obfs_host // "") == "") and
      ((.mode // "") | IN("","default","unshaped","unsafe-raw")) and
      (.psk | utf8bytelength >= 12)
    ' <<< "${config}" >/dev/null 2>&1 || return 1
  fi
}

# Validate the Hysteria2 outbound contract against sing-box 1.14.0.  Hysteria2
# is a QUIC client with optional TCP/UDP projection, port hopping, typed obfs,
# and the 1.14 Hysteria Realm rendezvous path.  Keep those discriminated
# objects bounded instead of treating a registered outbound as arbitrary JSON;
# the target core remains responsible for duration and memory-size parsing.
managed_component_hysteria2_config_validate_json() {
  local config=${1:-} tls tls_record realm_http_tls realm_http_tls_record
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def nonempty_safe_string:
      safe_string and length > 0;
    def listable_safe_string:
      safe_string or (type == "array" and all(.[]; safe_string));
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_memory($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 9007199254740991) or
         (type == "string" and safe_string)));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_network:
      (has("network") | not) or
      (.network |
        ((type == "string" and (length == 0 or IN("tcp","udp"))) or
         (type == "array" and length <= 2 and
           all(.[]; type == "string" and IN("tcp","udp")) and
           (length == (unique | length)))));
    def valid_port_range:
      safe_string and
      (try (test("^[0-9]{1,5}(:[0-9]{1,5})?$") and
        (split(":") | map(tonumber)) as $ports |
          all($ports[]; . >= 1 and . <= 65535) and
          (($ports | length) == 1 or $ports[0] <= $ports[1])) catch false);
    def optional_server_ports:
      (has("server_ports") | not) or
      (.server_ports |
        (valid_port_range or
          (type == "array" and length > 0 and
           all(.[]; valid_port_range) and (length == (unique | length)))));
    def optional_header_map:
      (has("headers") | not) or
      (.headers | type == "object" and
        all(to_entries[];
          (.key | type == "string" and length > 0 and
            test("^[A-Za-z0-9!#$%&\u0027+.^_\u0060|~-]+$")) and
          (.value | listable_safe_string)));
    def optional_domain_resolver:
      (has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object");
    def optional_http_client:
      (has("http_client") | not) or
      (.http_client |
        ((type == "string" and nonempty_safe_string) or
         (type == "object" and
          ((keys - [
            "engine","version","disable_version_fallback","headers","idle_timeout",
            "keep_alive_period","stream_receive_window","connection_receive_window",
            "max_concurrent_streams","initial_packet_size","disable_path_mtu_discovery",
            "tls","detour","bind_interface","inet4_bind_address","inet6_bind_address",
            "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
            "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
            "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
            "network_strategy","network_type","fallback_network_type","fallback_delay"
          ]) | length == 0) and
          ((has("engine") | not) or (.engine | type == "string" and IN("","go","apple"))) and
          ((has("version") | not) or (.version | type == "number" and . == floor and . >= 0 and . <= 3)) and
          optional_bool("disable_version_fallback") and optional_header_map and
          optional_duration("idle_timeout") and optional_duration("keep_alive_period") and
          optional_memory("stream_receive_window") and optional_memory("connection_receive_window") and
          optional_nonnegative_int("max_concurrent_streams") and
          optional_nonnegative_int("initial_packet_size") and
          optional_bool("disable_path_mtu_discovery") and
          ((.version // 0) != 1 or
            ((has("idle_timeout") | not) and (has("keep_alive_period") | not) and
             (has("stream_receive_window") | not) and
             (has("connection_receive_window") | not) and
             (has("max_concurrent_streams") | not) and
             (has("initial_packet_size") | not) and
             (has("disable_path_mtu_discovery") | not))) and
          ((.version // 0) == 3 or
            ((has("initial_packet_size") | not) and
             (has("disable_path_mtu_discovery") | not))) and
          ((has("tls") | not) or (.tls | type == "object")) and
          optional_safe_string("detour") and optional_safe_string("bind_interface") and
          optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
          optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
          optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
          optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
          optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
          optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
          optional_bool("udp_fragment") and optional_domain_resolver and optional_network_strategy and
          optional_network_types("network_type") and optional_network_types("fallback_network_type") and
          optional_duration("fallback_delay"))));
    def optional_obfs:
      (has("obfs") | not) or
      (.obfs | type == "object" and
        ((keys - ["type","password","min_packet_size","max_packet_size"]) | length == 0) and
        (.type | type == "string" and IN("salamander","gecko")) and
        (.password | nonempty_safe_string) and
        (((.type == "salamander") and
          (has("min_packet_size") | not) and (has("max_packet_size") | not)) or
         ((.type == "gecko") and optional_nonnegative_int("min_packet_size") and
          optional_nonnegative_int("max_packet_size") and
          ((.min_packet_size // 512) as $min | (.max_packet_size // 1200) as $max |
            $min >= 1 and $max <= 65535 and $min <= $max))));
    def optional_port_mapping:
      (has("port_mapping") | not) or
      (.port_mapping | type == "object" and
        ((keys - ["enabled","timeout","lifetime"]) | length == 0) and
        optional_bool("enabled") and optional_duration("timeout") and optional_duration("lifetime"));
    def optional_realm:
      (has("realm") | not) or
      (.realm | type == "object" and
        ((keys - ["server_url","token","realm_id","stun_servers","ip_version",
          "port_mapping","http_client"]) | length == 0) and
        (.server_url | nonempty_safe_string and
          test("^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$")) and
        optional_safe_string("token") and (.realm_id | nonempty_safe_string) and
        (.stun_servers |
          ((type == "string" and nonempty_safe_string) or
           (type == "array" and length > 0 and all(.[]; nonempty_safe_string) and
            (length == (unique | length))))) and
        ((has("ip_version") | not) or
          (.ip_version | type == "number" and . == floor and IN(0,4,6))) and
        optional_port_mapping and
        (((.port_mapping.enabled // false) != true) or ((.ip_version // 0) != 6)) and
        optional_http_client);
    type == "object" and
    ((keys - [
      "server","server_port","server_ports","hop_interval","hop_interval_max",
      "up_mbps","down_mbps","obfs","password","network","tls",
      "idle_timeout","keep_alive_period","stream_receive_window",
      "connection_receive_window","max_concurrent_streams","initial_packet_size",
      "disable_path_mtu_discovery","bbr_profile","brutal_debug","disable_chrome_parrot",
      "realm","detour","bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
      "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    ((has("server") | not) or (.server | nonempty_safe_string)) and
    ((has("server_port") | not) or
      (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
    ((has("server_port") and has("server_ports")) | not) and
    optional_server_ports and optional_duration("hop_interval") and
    optional_duration("hop_interval_max") and optional_nonnegative_int("up_mbps") and
    optional_nonnegative_int("down_mbps") and optional_obfs and optional_safe_string("password") and
    optional_network and
    (has("tls") and (.tls | type == "object" and
      (.enabled | type == "boolean" and . == true))) and
    optional_duration("idle_timeout") and optional_duration("keep_alive_period") and
    optional_memory("stream_receive_window") and optional_memory("connection_receive_window") and
    optional_nonnegative_int("max_concurrent_streams") and optional_nonnegative_int("initial_packet_size") and
    optional_bool("disable_path_mtu_discovery") and
    ((has("bbr_profile") | not) or
      (.bbr_profile | type == "string" and IN("","conservative","standard","aggressive"))) and
    optional_bool("brutal_debug") and optional_bool("disable_chrome_parrot") and optional_realm and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
    optional_bool("udp_fragment") and optional_domain_resolver and optional_network_strategy and
    optional_network_types("network_type") and optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  if jq -e 'has("realm")' <<< "${config}" >/dev/null 2>&1; then
    jq -e '((has("server") | not) and (has("server_port") | not) and (has("server_ports") | not))' \
      <<< "${config}" >/dev/null 2>&1 || return 1
  else
    jq -e '(.server | type == "string" and length > 0 and
      (any(explode[]; . < 32 or . == 127) | not)) and
      ((has("server_port") and (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) or
       (has("server_ports")))' \
      <<< "${config}" >/dev/null 2>&1 || return 1
  fi

  tls=$(jq -c '.tls' <<< "${config}") || return 1
  tls_record=$(jq -cn --argjson tls "${tls}" \
    '{server:"hysteria2-tls",server_port:1,tls:$tls}') || return 1
  managed_component_http_config_validate_json "${tls_record}" || return 1

  if jq -e '(.realm.http_client? | type == "object" and has("tls"))' \
    <<< "${config}" >/dev/null 2>&1; then
    realm_http_tls=$(jq -c '.realm.http_client.tls' <<< "${config}") || return 1
    realm_http_tls_record=$(jq -cn --argjson tls "${realm_http_tls}" \
      '{server:"hysteria2-realm",server_port:1,tls:$tls}') || return 1
    managed_component_http_config_validate_json "${realm_http_tls_record}" || return 1
  fi
}

# Validate the Hysteria v1 outbound contract against sing-box 1.14.0.  Hysteria
# v1 has a different authentication/obfuscation model from Hysteria2: it keeps
# the legacy auth/auth_str and network-byte bandwidth forms, while sharing TLS,
# QUIC and Dial Fields.  Reject the deprecated receive-window aliases and keep
# the two protocol families from silently accepting each other's fields.
managed_component_hysteria_config_validate_json() {
  local config=${1:-} tls tls_record
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_memory($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 9007199254740991) or
         (type == "string" and safe_string)));
    def optional_network_bytes($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 9007199254740991) or
         (type == "string" and nonempty_safe_string)));
    def optional_auth:
      (has("auth") | not) or
      (.auth |
        ((type == "string" and safe_string and
          test("^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")) or
         (type == "array" and all(.[];
           type == "number" and . == floor and . >= 0 and . <= 255))));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_network:
      (has("network") | not) or
      (.network |
        ((type == "string" and (length == 0 or IN("tcp","udp"))) or
         (type == "array" and length <= 2 and
           all(.[]; type == "string" and IN("tcp","udp")) and
           (length == (unique | length)))));
    def valid_port_range:
      safe_string and
      (try (test("^[0-9]{1,5}(:[0-9]{1,5})?$") and
        (split(":") | map(tonumber)) as $ports |
          all($ports[]; . >= 1 and . <= 65535) and
          (($ports | length) == 1 or $ports[0] <= $ports[1])) catch false);
    def optional_server_ports:
      (has("server_ports") | not) or
      (.server_ports |
        (valid_port_range or
          (type == "array" and length > 0 and
           all(.[]; valid_port_range) and (length == (unique | length)))));
    type == "object" and
    ((keys - [
      "server","server_port","server_ports","hop_interval","up","up_mbps",
      "down","down_mbps","obfs","auth","auth_str","network","tls",
      "idle_timeout","keep_alive_period","stream_receive_window",
      "connection_receive_window","max_concurrent_streams","initial_packet_size",
      "disable_path_mtu_discovery","detour","bind_interface","inet4_bind_address",
      "inet6_bind_address","bind_address_no_port","protect_path","routing_mark",
      "reuse_addr","netns","connect_timeout","tcp_fast_open","tcp_multi_path",
      "disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "udp_fragment","domain_resolver","network_strategy","network_type",
      "fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    ((has("server_port") | not) or
      (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
    ((has("server_port") and has("server_ports")) | not) and
    optional_server_ports and optional_duration("hop_interval") and
    optional_network_bytes("up") and optional_nonnegative_int("up_mbps") and
    optional_network_bytes("down") and optional_nonnegative_int("down_mbps") and
    ((has("up") or has("up_mbps")) and (has("down") or has("down_mbps"))) and
    optional_safe_string("obfs") and optional_auth and optional_safe_string("auth_str") and
    optional_network and
    (has("tls") and (.tls | type == "object" and
      (.enabled | type == "boolean" and . == true))) and
    optional_duration("idle_timeout") and optional_duration("keep_alive_period") and
    optional_memory("stream_receive_window") and optional_memory("connection_receive_window") and
    optional_nonnegative_int("max_concurrent_streams") and optional_nonnegative_int("initial_packet_size") and
    optional_bool("disable_path_mtu_discovery") and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  if jq -e 'has("server_ports")' <<< "${config}" >/dev/null 2>&1; then
    jq -e '(.server_ports | type == "string" or type == "array")' \
      <<< "${config}" >/dev/null 2>&1 || return 1
  elif ! jq -e 'has("server_port")' <<< "${config}" >/dev/null 2>&1; then
    return 1
  fi

  tls=$(jq -c '.tls' <<< "${config}") || return 1
  tls_record=$(jq -cn --argjson tls "${tls}" \
    '{server:"hysteria-tls",server_port:1,tls:$tls}') || return 1
  managed_component_http_config_validate_json "${tls_record}" || return 1
}

# Validate the TUIC outbound contract against sing-box 1.14.0.  TUIC has
# mandatory outbound TLS and UUID authentication, plus outbound-only UDP relay
# choices that must not be confused with the TUIC inbound fields.  Keep QUIC
# and shared Dial Fields typed, and reject udp_over_stream/udp_relay_mode
# conflicts before state/CAS or takeover publication.
managed_component_tuic_config_validate_json() {
  local config=${1:-} tls tls_record
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_memory($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 9007199254740991) or
         (type == "string" and safe_string)));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_network:
      (has("network") | not) or
      (.network |
        ((type == "string" and (length == 0 or IN("tcp","udp"))) or
         (type == "array" and length <= 2 and
           all(.[]; type == "string" and IN("tcp","udp")) and
           (length == (unique | length)))));
    type == "object" and
    ((keys - [
      "server","server_port","uuid","password","congestion_control",
      "udp_relay_mode","udp_over_stream","zero_rtt_handshake","heartbeat",
      "network","tls","idle_timeout","keep_alive_period",
      "stream_receive_window","connection_receive_window","max_concurrent_streams",
      "initial_packet_size","disable_path_mtu_discovery","detour","bind_interface",
      "inet4_bind_address","inet6_bind_address","bind_address_no_port","protect_path",
      "routing_mark","reuse_addr","netns","connect_timeout","tcp_fast_open",
      "tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive",
      "tcp_keep_alive_interval","udp_fragment","domain_resolver","network_strategy",
      "network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    (.uuid | type == "string" and
      test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89abAB][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$")) and
    optional_safe_string("password") and
    ((has("congestion_control") | not) or
      (.congestion_control | type == "string" and IN("","cubic","new_reno","bbr"))) and
    ((has("udp_relay_mode") | not) or
      (.udp_relay_mode | type == "string" and IN("","native","quic"))) and
    optional_bool("udp_over_stream") and optional_bool("zero_rtt_handshake") and
    optional_duration("heartbeat") and optional_network and
    (has("tls") and (.tls | type == "object" and
      (.enabled | type == "boolean" and . == true))) and
    optional_duration("idle_timeout") and optional_duration("keep_alive_period") and
    optional_memory("stream_receive_window") and optional_memory("connection_receive_window") and
    optional_nonnegative_int("max_concurrent_streams") and
    optional_nonnegative_int("initial_packet_size") and
    optional_bool("disable_path_mtu_discovery") and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and optional_duration("fallback_delay") and
    ((.udp_over_stream // false) != true or (.udp_relay_mode // "") == "")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  tls=$(jq -c '.tls' <<< "${config}") || return 1
  tls_record=$(jq -cn --argjson tls "${tls}" \
    '{server:"tuic-tls",server_port:1,tls:$tls}') || return 1
  managed_component_http_config_validate_json "${tls_record}" || return 1
}

# Validate the NaiveProxy outbound contract against sing-box 1.14.0.  Naive
# uses the optional UDP-over-TCP adapter for UDP and has a deliberately narrow
# outbound TLS surface; accepting generic TLS fields here would make a record
# pass state/CAS only to fail when libcronet is initialized.  Keep the
# libcronet/build-tag requirement in registry availability metadata rather
# than pretending that a config check proves the runtime library is loaded.
managed_component_naive_config_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def listable_safe_string:
      safe_string or (type == "array" and all(.[]; safe_string));
    def nonempty_safe_string:
      safe_string and length > 0;
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_listable_safe_string($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_nonnegative_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 2147483647);
    def optional_memory($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "number" and . == floor and . >= 0 and . <= 9007199254740991) or
         (type == "string" and safe_string)));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_header_map:
      (has("extra_headers") | not) or
      (.extra_headers | type == "object" and
        all(to_entries[];
          (.key | type == "string" and length > 0 and
            test("^[A-Za-z0-9!#$%&\u0027+.^_\u0060|~-]+$")) and
          (.value | listable_safe_string)));
    def optional_udp_over_tcp:
      (has("udp_over_tcp") | not) or
      (.udp_over_tcp |
        (type == "boolean" or
         (type == "object" and
          ((keys - ["enabled","version"]) | length == 0) and
          ((has("enabled") | not) or (.enabled | type == "boolean")) and
          ((has("version") | not) or
            (.version | type == "number" and . == floor and . >= 1 and . <= 2)))));
    def optional_ech:
      (has("ech") | not) or
      (.ech | type == "object" and
        ((keys - ["enabled","config","config_path","query_server_name"]) | length == 0) and
        optional_bool("enabled") and
        optional_listable_safe_string("config") and
        optional_safe_string("config_path") and
        optional_safe_string("query_server_name"));
    def naive_tls:
      type == "object" and
      ((keys - ["enabled","server_name","certificate","certificate_path","ech"]) | length == 0) and
      (.enabled | type == "boolean" and . == true) and
      optional_safe_string("server_name") and
      optional_listable_safe_string("certificate") and
      optional_safe_string("certificate_path") and
      optional_ech;
    type == "object" and
    ((keys - [
      "server","server_port","username","password","insecure_concurrency",
      "extra_headers","stream_receive_window","udp_over_tcp","quic",
      "quic_congestion_control","quic_session_receive_window","tls",
      "detour","bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
      "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    optional_safe_string("username") and optional_safe_string("password") and
    optional_nonnegative_int("insecure_concurrency") and optional_header_map and
    optional_memory("stream_receive_window") and optional_udp_over_tcp and
    optional_bool("quic") and
    ((has("quic_congestion_control") | not) or
      (.quic_congestion_control | type == "string" and IN("","bbr","bbr2","cubic","reno"))) and
    optional_memory("quic_session_receive_window") and
    ((.quic // false) != true or (.insecure_concurrency // 0) == 0) and
    (has("tls") and (.tls | naive_tls)) and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the ShadowTLS outbound contract against sing-box 1.14.0.  This is
# a TCP-only wrapper around a remote ShadowTLS server, not the project's local
# ShadowTLS inbound composite; keep its version/password/TLS fields separate
# and reuse the strict outbound TLS and shared Dial Field validator.
managed_component_shadowtls_config_validate_json() {
  local config=${1:-} tls tls_record
  [[ -n "${config}" ]] || return 1
  jq -e '
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
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^0x[0-9a-fA-F]+$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    type == "object" and
    ((keys - [
      "server","server_port","version","password","tls","detour",
      "bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
      "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    ((has("version") | not) or
      (.version | type == "number" and . == floor and . >= 1 and . <= 3)) and
    optional_safe_string("password") and
    (has("tls") and (.tls | type == "object" and
      (.enabled | type == "boolean" and . == true))) and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
    optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and optional_duration("fallback_delay")
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  tls=$(jq -c '.tls' <<< "${config}") || return 1
  tls_record=$(jq -cn --argjson tls "${tls}" \
    '{server:"shadowtls-tls",server_port:1,tls:$tls}') || return 1
  managed_component_http_config_validate_json "${tls_record}" || return 1
}
