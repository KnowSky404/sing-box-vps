
# Validate a CIDR prefix used by the WireGuard endpoint.  The endpoint schema
# uses netip.Prefix rather than a listener address, so the existing address
# validator is paired with an explicit prefix-length bound for both families.
managed_component_wireguard_prefix_validate() {
  local prefix=${1:-} address prefix_length
  [[ -n "${prefix}" && "${prefix}" != *$'\n'* && "${prefix}" != *$'\r'* ]] || return 1
  [[ "${prefix}" == */* ]] || return 1
  address=${prefix%/*}
  prefix_length=${prefix##*/}
  [[ -n "${address}" && "${prefix_length}" =~ ^[0-9]+$ ]] || return 1
  structured_instance_store_validate_address "${address}" || return 1
  if [[ "${address}" == *:* ]]; then
    (( 10#${prefix_length} <= 128 )) || return 1
  else
    (( 10#${prefix_length} <= 32 )) || return 1
  fi
}

# Validate the WireGuard endpoint contract against sing-box 1.14.0.  This is
# the modern endpoint surface; the removed wireguard outbound remains a
# separate fail-closed registry stub.  Keys are deliberately checked as the
# exact 32-byte standard base64 form consumed by wireguard-go, while all peer,
# NAT and Dial Field options are bounded before state/CAS or takeover publish.
managed_component_wireguard_config_validate_json() {
  local config=${1:-} prefix peer_prefix
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_bool($name):
      (has($name) | not) or (.[$name] | type == "boolean");
    def optional_uint($name; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max);
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
    def optional_udp_nat($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","endpoint_independent","address_dependent","address_and_port_dependent"));
    def listable_strings($name):
      has($name) and
      (.[$name] |
        ((type == "string" and safe_string) or
         (type == "array" and length > 0 and all(.[]; safe_string))));
    def optional_listable_prefix_shape($name):
      (has($name) | not) or listable_strings($name);
    def wireguard_key:
      type == "string" and test("^[A-Za-z0-9+/]{43}=$");
    def peer_shape:
      type == "object" and
      ((keys - ["address","port","public_key","pre_shared_key","allowed_ips",
        "persistent_keepalive_interval","reserved"]) | length == 0) and
      optional_safe_string("address") and
      optional_uint("port"; 65535) and
      (.public_key | wireguard_key) and
      ((has("pre_shared_key") | not) or
        (.pre_shared_key | type == "string" and (length == 0 or wireguard_key))) and
      (has("allowed_ips") and listable_strings("allowed_ips")) and
      optional_uint("persistent_keepalive_interval"; 65535) and
      ((has("reserved") | not) or
        (.reserved | type == "array" and length == 3 and
          all(.[]; type == "number" and . == floor and . >= 0 and . <= 255)));
    type == "object" and
    ((keys - ["system","name","mtu","address","private_key","listen_port","peers",
      "udp_timeout","udp_mapping","udp_filtering","udp_nat_max","workers",
      "detour","bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
      "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"])
      | length == 0) and
    optional_bool("system") and optional_safe_string("name") and
    optional_uint("mtu"; 4294967295) and
    (has("address") and listable_strings("address")) and
    (.private_key | wireguard_key) and
    optional_uint("listen_port"; 65535) and
    ((has("peers") | not) or
      (.peers | type == "array" and all(.[]; peer_shape))) and
    optional_duration("udp_timeout") and optional_udp_nat("udp_mapping") and
    optional_udp_nat("udp_filtering") and optional_uint("udp_nat_max"; 4294967295) and
    optional_uint("workers"; 2147483647) and
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
    ((.address | if type == "array" then length > 0 else true end))
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    managed_component_wireguard_prefix_validate "${prefix}" || return 1
  done < <(jq -r '.address | if type == "array" then .[] else . end' <<< "${config}")

  while IFS= read -r peer_prefix; do
    [[ -n "${peer_prefix}" ]] || continue
    managed_component_wireguard_prefix_validate "${peer_prefix}" || return 1
  done < <(jq -r '.peers[]?.allowed_ips | if type == "array" then .[] else . end' <<< "${config}")
}

# Shared endpoint address helpers.  Endpoint options use netip.Prefix and
# netip.AddrPort rather than listener addresses; keep their validation in the
# state layer so OpenVPN/Tailscale cannot silently retain malformed route or
# relay values.  The core remains responsible for parsing external hostnames,
# certificates and protocol material.
managed_component_endpoint_prefix_validate() {
  local prefix=${1:-} address prefix_length
  [[ -n "${prefix}" && "${prefix}" != *$'\n'* && "${prefix}" != *$'\r'* ]] || return 1
  [[ "${prefix}" == */* ]] || return 1
  address=${prefix%/*}
  prefix_length=${prefix##*/}
  [[ -n "${address}" && "${prefix_length}" =~ ^[0-9]+$ ]] || return 1
  structured_instance_store_validate_address "${address}" || return 1
  if [[ "${address}" == *:* ]]; then
    (( 10#${prefix_length} <= 128 )) || return 1
  else
    (( 10#${prefix_length} <= 32 )) || return 1
  fi
}

managed_component_endpoint_addrport_validate() {
  local value=${1:-} host port
  [[ -n "${value}" && "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || return 1
  if [[ "${value}" == \[*\]:* ]]; then
    host=${value#\[}
    host=${host%%\]:*}
    port=${value##*\]:}
  elif [[ "${value}" != *:*:* && "${value}" == *:* ]]; then
    host=${value%:*}
    port=${value##*:}
  else
    return 1
  fi
  [[ -n "${host}" && "${port}" =~ ^[0-9]+$ && ${#port} -le 5 ]] || return 1
  (( 10#${port} <= 65535 )) || return 1
  structured_instance_store_validate_address "${host}"
}

# Validate the Tailscale endpoint contract against sing-box 1.14.0.  Auth and
# control-plane values remain sensitive/external, but every persisted option,
# route prefix, relay address and SSH sub-object is shape-checked before CAS or
# takeover publication.
managed_component_tailscale_config_validate_json() {
  local config=${1:-} prefix relay_endpoint
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
    def optional_uint($name; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max);
    def optional_uint_or_null($name; $max):
      (has($name) | not) or (.[$name] == null or
        (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max));
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_udp_timeout:
      (has("udp_timeout") | not) or
      (.udp_timeout |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and safe_string)));
    def optional_udp_nat($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","endpoint_independent","address_dependent","address_and_port_dependent"));
    def optional_listable_strings($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and safe_string) or
         (type == "array" and all(.[]; safe_string))));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^(0x[0-9a-fA-F]+|[0-9]+)$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def optional_ssh_server:
      (has("ssh_server") | not) or
      (.ssh_server |
        (type == "boolean" or
         (type == "object" and
          ((keys - ["enabled","disable_pty","disable_sftp","disable_forwarding"]) | length == 0) and
          optional_bool("enabled") and optional_bool("disable_pty") and
          optional_bool("disable_sftp") and optional_bool("disable_forwarding"))));
    type == "object" and
    ((keys - [
      "state_directory","auth_key","control_url","ephemeral","hostname",
      "accept_routes","exit_node","exit_node_allow_lan_access","advertise_routes",
      "advertise_exit_node","advertise_tags","listen_port","relay_server_port",
      "relay_server_static_endpoints","system_interface","system_interface_name",
      "system_interface_mtu","udp_timeout","ssh_server","taildrop_directory",
      "detour","bind_interface","inet4_bind_address",
      "inet6_bind_address","bind_address_no_port","protect_path","routing_mark",
      "reuse_addr","netns","connect_timeout","tcp_fast_open","tcp_multi_path",
      "disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "udp_fragment","domain_resolver","network_strategy","network_type",
      "fallback_network_type","fallback_delay"
    ]) | length == 0) and
    optional_safe_string("state_directory") and optional_safe_string("auth_key") and
    optional_safe_string("control_url") and optional_bool("ephemeral") and
    optional_safe_string("hostname") and optional_bool("accept_routes") and
    optional_safe_string("exit_node") and optional_bool("exit_node_allow_lan_access") and
    ((has("advertise_routes") | not) or
      (.advertise_routes | type == "array" and all(.[]; type == "string" and length > 0))) and
    optional_bool("advertise_exit_node") and optional_listable_strings("advertise_tags") and
    optional_uint("listen_port"; 65535) and optional_uint_or_null("relay_server_port"; 65535) and
    ((has("relay_server_static_endpoints") | not) or
      (.relay_server_static_endpoints | type == "array" and all(.[]; type == "string" and length > 0))) and
    optional_bool("system_interface") and optional_safe_string("system_interface_name") and
    optional_uint("system_interface_mtu"; 4294967295) and optional_udp_timeout and
    optional_ssh_server and optional_safe_string("taildrop_directory") and
    optional_safe_string("detour") and
    optional_safe_string("bind_interface") and optional_safe_string("inet4_bind_address") and
    optional_safe_string("inet6_bind_address") and optional_bool("bind_address_no_port") and
    optional_safe_string("protect_path") and optional_routing_mark and optional_bool("reuse_addr") and
    optional_safe_string("netns") and optional_duration("connect_timeout") and
    optional_bool("tcp_fast_open") and optional_bool("tcp_multi_path") and
    optional_bool("disable_tcp_keep_alive") and optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and
    optional_network_strategy and optional_network_types("network_type") and
    optional_network_types("fallback_network_type") and optional_duration("fallback_delay") and
    (((.advertise_exit_node // false) != true) or ((.exit_node // "") == ""))
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    [[ "${prefix}" != "0.0.0.0/0" && "${prefix}" != "::/0" ]] || return 1
    managed_component_endpoint_prefix_validate "${prefix}" || return 1
  done < <(jq -r '.advertise_routes[]?' <<< "${config}")

  while IFS= read -r relay_endpoint; do
    [[ -n "${relay_endpoint}" ]] || continue
    managed_component_endpoint_addrport_validate "${relay_endpoint}" || return 1
  done < <(jq -r '.relay_server_static_endpoints[]?' <<< "${config}")
}

# Validate the OpenConnect client endpoint contract against sing-box 1.14.0.
# Authentication may be interactive or supplied by a cookie/token, so this
# validator checks material shape and protocol enums without pretending that a
# remote VPN control-plane login happened locally.
managed_component_openconnect_config_validate_json() {
  local config=${1:-} server
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
    def optional_uint($name; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max);
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_udp_timeout:
      (has("udp_timeout") | not) or
      (.udp_timeout | type == "string" and safe_string);
    def optional_udp_nat($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","endpoint_independent","address_dependent","address_and_port_dependent"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_routing_mark:
      (has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^(0x[0-9a-fA-F]+|[0-9]+)$")))));
    def optional_network_strategy:
      (has("network_strategy") | not) or
      (.network_strategy | type == "string" and IN("","default","hybrid","fallback"));
    def listable_safe_string:
      ((type == "string" and safe_string) or
       (type == "array" and all(.[]; safe_string)));
    def material_safe_string:
      type == "string" and
      (any(explode[]; ((. < 32 and . != 9 and . != 10 and . != 13) or . == 127)) | not);
    def material_listable_string:
      ((type == "string" and material_safe_string) or
       (type == "array" and all(.[]; material_safe_string)));
    def optional_listable_safe_string($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def optional_material_list($name):
      (has($name) | not) or (.[$name] | material_listable_string);
    def material_set($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then any(.[]; type == "string" and length > 0)
        else false end));
    def material_present($inline; $path):
      (material_set($inline) or
       (has($path) and (.[$path] | type == "string" and length > 0)));
    def optional_material_pair($inline; $path):
      ((material_set($inline) and material_set($path)) | not);
    def optional_token:
      (has("token") | not) or
      (.token |
        type == "object" and
        ((keys - ["mode","secret","secret_path","pin","password","device_id","counter"]) | length == 0) and
        (.mode | type == "string" and IN("totp","hotp","stoken","oidc")) and
        optional_safe_string("secret") and optional_safe_string("secret_path") and
        optional_safe_string("pin") and optional_safe_string("password") and
        optional_safe_string("device_id") and optional_uint("counter"; 9007199254740991) and
        (((.secret // "") | length > 0) != ((.secret_path // "") | length > 0)));
    def optional_mobile:
      (has("mobile") | not) or
      (.mobile | type == "object" and
        ((keys - ["platform_version","device_type","device_unique_id"]) | length == 0) and
        (has("platform_version") and (.platform_version | nonempty_safe_string)) and
        (has("device_type") and (.device_type | nonempty_safe_string)) and
        (has("device_unique_id") and (.device_unique_id | nonempty_safe_string)));
    def optional_wrapper($name):
      (has($name) | not) or
      (.[$name] | type == "object" and
        ((keys - ["wrapper_path"]) | length == 0) and optional_safe_string("wrapper_path"));
    def optional_tncc:
      (has("tncc") | not) or
      (.tncc | type == "object" and
        ((keys - ["wrapper_path","device_id","user_agent","machine_identification_enabled","certificates"]) | length == 0) and
        optional_safe_string("wrapper_path") and optional_safe_string("device_id") and
        optional_safe_string("user_agent") and optional_bool("machine_identification_enabled") and
        ((has("certificates") | not) or
          (.certificates | type == "array" and all(.[];
            type == "object" and
            ((keys - ["certificate","certificate_path"]) | length == 0) and
            optional_material_list("certificate") and optional_safe_string("certificate_path") and
            optional_material_pair("certificate"; "certificate_path")))) and
        (((.wrapper_path // "") == "") or
          (((.device_id // "") == "") and ((.user_agent // "") == "") and
           ((.machine_identification_enabled // false) == false) and
           ((.certificates // []) | length == 0))) and
        (((.certificates // []) | length == 0) or
          ((.machine_identification_enabled // false) == true)));
    def optional_fortinet_host_check:
      (has("fortinet_host_check") | not) or
      (.fortinet_host_check | type == "object" and
        ((keys - ["hostcheck","check_virtual_desktop"]) | length == 0) and
        optional_safe_string("hostcheck") and optional_safe_string("check_virtual_desktop"));
    def optional_tls:
      (has("tls") | not) or
      (.tls | type == "object" and
        ((keys - ["insecure","server_name","peer_fingerprint","system_trust_disabled",
          "certificate_authority","certificate_authority_path","client_certificate",
          "client_certificate_path","client_key","client_key_path","client_key_password",
          "mca_certificate","mca_certificate_path","mca_key","mca_key_path","mca_key_password"]) | length == 0) and
        optional_bool("insecure") and optional_safe_string("server_name") and
        optional_listable_safe_string("peer_fingerprint") and optional_bool("system_trust_disabled") and
        optional_material_list("certificate_authority") and optional_safe_string("certificate_authority_path") and
        optional_material_list("client_certificate") and optional_safe_string("client_certificate_path") and
        optional_material_list("client_key") and optional_safe_string("client_key_path") and
        optional_safe_string("client_key_password") and optional_material_list("mca_certificate") and
        optional_safe_string("mca_certificate_path") and optional_material_list("mca_key") and
        optional_safe_string("mca_key_path") and optional_safe_string("mca_key_password") and
        optional_material_pair("certificate_authority"; "certificate_authority_path") and
        optional_material_pair("client_certificate"; "client_certificate_path") and
        optional_material_pair("client_key"; "client_key_path") and
        optional_material_pair("mca_certificate"; "mca_certificate_path") and
        optional_material_pair("mca_key"; "mca_key_path") and
        (material_present("client_certificate"; "client_certificate_path") ==
          material_present("client_key"; "client_key_path")) and
        (material_present("mca_certificate"; "mca_certificate_path") ==
          material_present("mca_key"; "mca_key_path")));
    def optional_form_entries:
      (has("form_entries") | not) or
      (.form_entries | type == "array" and all(.[];
        type == "object" and
        ((keys - ["form_id","submission_key","name","value","promote"]) | length == 0) and
        optional_safe_string("form_id") and optional_safe_string("submission_key") and
        optional_safe_string("name") and optional_safe_string("value") and optional_bool("promote") and
        (((.submission_key // "") | length > 0) or
          (((.form_id // "") | length > 0) and ((.name // "") | length > 0))) and
        (((.value // "") | length == 0) or ((.promote // false) != true))));
    type == "object" and
    ((keys - [
      "system","name","udp_timeout","udp_mapping","udp_filtering","udp_nat_max",
      "server","flavor","username","password","auth_group","cookie","token",
      "reported_os","user_agent","version","local_hostname","mobile","csd","hip",
      "tncc","fortinet_host_check","no_udp","dtls_local_port","compression_disabled",
      "compression_mode","ipv6_disabled","http_keepalive_disabled","xml_post_disabled",
      "external_auth_disabled","password_authentication_disabled","tcp_keep_alive_enabled",
      "pfs","mtu","base_mtu","dpd_interval","reconnect_timeout","trojan_interval",
      "queue_length","allow_insecure_crypto","tls","form_entries",
      "detour","bind_interface","inet4_bind_address","inet6_bind_address",
      "bind_address_no_port","protect_path","routing_mark","reuse_addr","netns",
      "connect_timeout","tcp_fast_open","tcp_multi_path","disable_tcp_keep_alive",
      "tcp_keep_alive","tcp_keep_alive_interval","udp_fragment","domain_resolver",
      "network_strategy","network_type","fallback_network_type","fallback_delay"
    ]) | length == 0) and
    (.server | nonempty_safe_string) and
    ((has("flavor") | not) or (.flavor | type == "string" and
      IN("","anyconnect","gp","fortinet","f5","pulse","nc"))) and
    optional_bool("system") and optional_safe_string("name") and
    optional_udp_timeout and optional_udp_nat("udp_mapping") and optional_udp_nat("udp_filtering") and
    optional_uint("udp_nat_max"; 4294967295) and optional_safe_string("username") and
    optional_safe_string("password") and optional_safe_string("auth_group") and
    optional_safe_string("cookie") and optional_token and optional_safe_string("reported_os") and
    optional_safe_string("user_agent") and optional_safe_string("version") and
    optional_safe_string("local_hostname") and optional_mobile and optional_wrapper("csd") and
    optional_wrapper("hip") and optional_tncc and optional_fortinet_host_check and
    optional_bool("no_udp") and optional_uint("dtls_local_port"; 65535) and
    optional_bool("compression_disabled") and ((has("compression_mode") | not) or
      (.compression_mode | type == "string" and IN("","stateless","all"))) and
    optional_bool("ipv6_disabled") and optional_bool("http_keepalive_disabled") and
    optional_bool("xml_post_disabled") and optional_bool("external_auth_disabled") and
    optional_bool("password_authentication_disabled") and optional_bool("tcp_keep_alive_enabled") and
    optional_bool("pfs") and optional_uint("mtu"; 65535) and
    optional_uint("base_mtu"; 65535) and optional_duration("dpd_interval") and
    optional_duration("reconnect_timeout") and optional_duration("trojan_interval") and
    optional_uint("queue_length"; 4294967295) and optional_bool("allow_insecure_crypto") and
    optional_tls and optional_form_entries and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    optional_routing_mark and optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_duration("connect_timeout") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("disable_tcp_keep_alive") and
    optional_duration("tcp_keep_alive") and optional_duration("tcp_keep_alive_interval") and
    optional_bool("udp_fragment") and ((has("domain_resolver") | not) or
      (.domain_resolver | type == "string" or type == "object")) and optional_network_strategy and
    optional_network_types("network_type") and optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay") and
    (((.compression_mode // "") != "all") or ((.compression_disabled // false) != true)) and
    (((.tcp_keep_alive_enabled // false) != true) or ((.disable_tcp_keep_alive // false) != true))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
  server=$(jq -r '.server' <<< "${config}") || return 1
  [[ "${server}" != *'?'* && "${server}" != *'#'* && "${server}" != *'@'* ]] || return 1
  if [[ "${server}" == *"://"* && "${server}" != https://* ]]; then
    return 1
  fi
}

# OpenVPN TLS material is a discriminated nested object in the 1.14 option
# schema.  Keep client and server variants separate: the server owns `key` and
# certificate policy, while the client owns `client_key` and remote policy.
managed_component_openvpn_tls_outbound_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def listable_safe_string:
      ((type == "string" and safe_string) or
       (type == "array" and all(.[]; safe_string)));
    def optional_listable($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def material_safe_string:
      type == "string" and
      (any(explode[]; ((. < 32 and . != 9 and . != 10 and . != 13) or . == 127)) | not);
    def material_listable_string:
      ((type == "string" and material_safe_string) or
       (type == "array" and all(.[]; material_safe_string)));
    def optional_material_list($name):
      (has($name) | not) or (.[$name] | material_listable_string);
    def material_set($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then any(.[]; type == "string" and length > 0)
        else false end));
    def nonempty_listable($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then length > 0
        else false end));
    def optional_fingerprint($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and test("^[0-9a-f]{64}$")) or
         (type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9a-f]{64}$")))));
    def material_present($inline; $path):
      (material_set($inline) or
       (has($path) and (.[$path] | type == "string" and length > 0)));
    def version_index($value):
      (["1.0","1.1","1.2","1.3"] | index($value));
    def effective_version($value; $default):
      if (($value // "") == "") then $default else $value end;
    def optional_material_pair($inline; $path):
      ((material_set($inline) and material_set($path)) | not);
    def optional_control_wrap:
      (has("control_wrap") | not) or
      (.control_wrap | type == "object" and
        ((keys - ["type","key","key_path","direction"]) | length == 0) and
        ((has("type") | not) or (.type | type == "string" and IN("","tls_auth","tls_crypt","tls_crypt_v2"))) and
        optional_material_list("key") and optional_safe_string("key_path") and
        ((has("direction") | not) or (.direction | type == "string" and IN("","server","client"))) and
        optional_material_pair("key"; "key_path") and
        (((.type // "") == "" and
          ((material_set("key") | not) and ((.key_path // "") == "") and ((.direction // "") == ""))) or
         ((.type // "") | IN("tls_auth","tls_crypt","tls_crypt_v2")) and
          ((material_set("key") != (((.key_path // "") | length) > 0))) and
          (((.type // "") == "tls_auth") or ((.direction // "") == ""))));
    type == "object" and
    ((keys - [
      "server_name","server_name_type","certificate","certificate_path",
      "client_certificate","client_certificate_path","client_key","client_key_path",
      "peer_fingerprint","crl_path","remote_certificate_ku","remote_certificate_eku",
      "remote_certificate_tls","certificate_profile","ns_certificate_type","version_min",
      "version_max","cipher","groups","control_wrap"
    ]) | length == 0) and
    optional_safe_string("server_name") and
    ((has("server_name_type") | not) or
      (.server_name_type | type == "string" and IN("","subject","name","name-prefix"))) and
    optional_material_list("certificate") and optional_safe_string("certificate_path") and
    optional_material_pair("certificate"; "certificate_path") and
    optional_material_list("client_certificate") and optional_safe_string("client_certificate_path") and
    optional_material_pair("client_certificate"; "client_certificate_path") and
    optional_material_list("client_key") and optional_safe_string("client_key_path") and
    optional_material_pair("client_key"; "client_key_path") and
    optional_fingerprint("peer_fingerprint") and optional_safe_string("crl_path") and
    optional_listable("remote_certificate_ku") and optional_safe_string("remote_certificate_eku") and
    ((has("remote_certificate_tls") | not) or
      (.remote_certificate_tls | type == "string" and IN("","server","client","none"))) and
    ((has("certificate_profile") | not) or
      (.certificate_profile | type == "string" and IN("","legacy","preferred","insecure","suiteb"))) and
    ((has("ns_certificate_type") | not) or
      (.ns_certificate_type | type == "string" and IN("","server","client"))) and
    ((has("version_min") | not) or
      (.version_min | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
    ((has("version_max") | not) or
      (.version_max | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
    optional_safe_string("cipher") and optional_safe_string("groups") and optional_control_wrap and
    (((.remote_certificate_eku // "") == "") or ((.remote_certificate_tls // "") == "")) and
    (material_present("certificate"; "certificate_path") or nonempty_listable("peer_fingerprint")) and
    (material_present("client_certificate"; "client_certificate_path") ==
      material_present("client_key"; "client_key_path")) and
    (version_index(effective_version(.version_min; "1.2")) <=
      version_index(effective_version(.version_max; "1.3")))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

managed_component_openvpn_tls_inbound_validate_json() {
  local config=${1:-}
  [[ -n "${config}" ]] || return 1
  jq -e '
    def safe_string:
      type == "string" and (any(explode[]; . < 32 or . == 127) | not);
    def optional_safe_string($name):
      (has($name) | not) or (.[$name] | safe_string);
    def listable_safe_string:
      ((type == "string" and safe_string) or
       (type == "array" and all(.[]; safe_string)));
    def optional_listable($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def material_safe_string:
      type == "string" and
      (any(explode[]; ((. < 32 and . != 9 and . != 10 and . != 13) or . == 127)) | not);
    def material_listable_string:
      ((type == "string" and material_safe_string) or
       (type == "array" and all(.[]; material_safe_string)));
    def optional_material_list($name):
      (has($name) | not) or (.[$name] | material_listable_string);
    def material_set($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then any(.[]; type == "string" and length > 0)
        else false end));
    def nonempty_listable($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then length > 0
        else false end));
    def optional_fingerprint($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and test("^[0-9a-f]{64}$")) or
         (type == "array" and length > 0 and all(.[]; type == "string" and test("^[0-9a-f]{64}$")))));
    def material_present($inline; $path):
      (material_set($inline) or
       (has($path) and (.[$path] | type == "string" and length > 0)));
    def version_index($value):
      (["1.0","1.1","1.2","1.3"] | index($value));
    def effective_version($value; $default):
      if (($value // "") == "") then $default else $value end;
    def optional_material_pair($inline; $path):
      ((material_set($inline) and material_set($path)) | not);
    def optional_control_wrap:
      (has("control_wrap") | not) or
      (.control_wrap | type == "object" and
        ((keys - ["type","key","key_path","direction","force_cookie"]) | length == 0) and
        ((has("type") | not) or (.type | type == "string" and IN("","tls_auth","tls_crypt","tls_crypt_v2"))) and
        optional_material_list("key") and optional_safe_string("key_path") and
        ((has("direction") | not) or (.direction | type == "string" and IN("","server","client"))) and
        ((has("force_cookie") | not) or (.force_cookie | type == "boolean")) and
        optional_material_pair("key"; "key_path") and
        (((.type // "") == "" and
          ((material_set("key") | not) and ((.key_path // "") == "") and
           ((.direction // "") == "") and ((.force_cookie // false) == false))) or
         ((.type // "") | IN("tls_auth","tls_crypt","tls_crypt_v2")) and
          ((material_set("key") != (((.key_path // "") | length) > 0))) and
          (((.type // "") == "tls_auth") or ((.direction // "") == "")) and
          (((.type // "") == "tls_crypt_v2") or ((.force_cookie // false) == false))));
    type == "object" and
    ((keys - [
      "certificate","certificate_path","key","key_path","client_certificate",
      "client_certificate_path","verify_client_certificate","client_name",
      "client_name_type","peer_fingerprint","crl_path","remote_certificate_ku",
      "remote_certificate_eku","remote_certificate_tls","certificate_profile",
      "ns_certificate_type","version_min","version_max","cipher","groups",
      "control_wrap"
    ]) | length == 0) and
    optional_material_list("certificate") and optional_safe_string("certificate_path") and
    optional_material_pair("certificate"; "certificate_path") and
    optional_material_list("key") and optional_safe_string("key_path") and
    optional_material_pair("key"; "key_path") and
    material_present("certificate"; "certificate_path") and
    material_present("key"; "key_path") and
    optional_material_list("client_certificate") and optional_safe_string("client_certificate_path") and
    optional_material_pair("client_certificate"; "client_certificate_path") and
    ((has("verify_client_certificate") | not) or
      (.verify_client_certificate | type == "string" and IN("","require","optional","none"))) and
    optional_safe_string("client_name") and
    ((has("client_name_type") | not) or
      (.client_name_type | type == "string" and IN("","subject","name","name-prefix"))) and
    optional_fingerprint("peer_fingerprint") and optional_safe_string("crl_path") and
    optional_listable("remote_certificate_ku") and optional_safe_string("remote_certificate_eku") and
    ((has("remote_certificate_tls") | not) or
      (.remote_certificate_tls | type == "string" and IN("","server","client","none"))) and
    ((has("certificate_profile") | not) or
      (.certificate_profile | type == "string" and IN("","legacy","preferred","insecure","suiteb"))) and
    ((has("ns_certificate_type") | not) or
      (.ns_certificate_type | type == "string" and IN("","server","client"))) and
    ((has("version_min") | not) or
      (.version_min | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
    ((has("version_max") | not) or
      (.version_max | type == "string" and IN("","1.0","1.1","1.2","1.3"))) and
    optional_safe_string("cipher") and optional_safe_string("groups") and optional_control_wrap and
    (((.remote_certificate_eku // "") == "") or ((.remote_certificate_tls // "") == "")) and
    (((.verify_client_certificate // "require") == "none") or
      material_present("client_certificate"; "client_certificate_path") or
      nonempty_listable("peer_fingerprint")) and
    (version_index(effective_version(.version_min; "1.2")) <=
      version_index(effective_version(.version_max; "1.3")))
  ' <<< "${config}" >/dev/null 2>&1 || return 1
}

# Validate the OpenVPN client endpoint contract.  TLS and deprecated
# static-key mode are intentionally modeled as a discriminated union so a
# state record cannot contain mutually exclusive authentication, pull or
# renegotiation options that only fail after a service restart.
managed_component_openvpn_client_config_validate_json() {
  local config=${1:-} field value prefix
  local has_ipv4=false has_ipv6=false peer_address peer_address_ipv6
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
    def optional_uint($name; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max);
    def optional_int($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= -2147483648 and . <= 2147483647);
    def optional_uint64($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 9007199254740991);
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_udp_timeout:
      (has("udp_timeout") | not) or
      (.udp_timeout |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and safe_string)));
    def optional_udp_nat($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","endpoint_independent","address_dependent","address_and_port_dependent"));
    def listable_safe_string:
      ((type == "string" and safe_string) or
       (type == "array" and all(.[]; safe_string)));
    def listable_nonempty_safe_string:
      ((type == "string" and nonempty_safe_string) or
       (type == "array" and length > 0 and all(.[]; nonempty_safe_string)));
    def optional_listable($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def optional_prefix_list($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and safe_string and length > 0) or
         (type == "array" and all(.[]; type == "string" and safe_string and length > 0))));
    def optional_network($name):
      (has($name) | not) or
      (.[$name] | type == "string" and IN("","udp","udp4","udp6","tcp","tcp4","tcp6"));
    def optional_network_types($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and (length == 0 or IN("wifi","cellular","ethernet","other"))) or
         (type == "array" and all(.[]; type == "string" and
           IN("wifi","cellular","ethernet","other")))));
    def optional_addr($name):
      (has($name) | not) or (.[$name] | safe_string);
    def material_safe_string:
      type == "string" and
      (any(explode[]; ((. < 32 and . != 9 and . != 10 and . != 13) or . == 127)) | not);
    def material_listable_string:
      ((type == "string" and material_safe_string) or
       (type == "array" and all(.[]; material_safe_string)));
    def optional_material($name):
      (has($name) | not) or (.[$name] | material_listable_string);
    def inline_material_set($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then any(.[]; type == "string" and length > 0)
        else false end));
    def path_material_set($name):
      (has($name) and (.[$name] | type == "string" and length > 0));
    def material_set($inline; $path):
      (inline_material_set($inline) or path_material_set($path));
    def optional_pull_filters:
      (has("pull_filters") | not) or
      (.pull_filters | type == "array" and all(.[];
        type == "object" and ((keys - ["action","text"]) | length == 0) and
        (.action | type == "string" and IN("accept","ignore","reject")) and
        (.text | safe_string)));
    def optional_servers:
      (has("servers") | not) or
      (.servers | type == "array" and all(.[];
        type == "object" and ((keys - ["server","server_port","network"]) | length == 0) and
        (.server | nonempty_safe_string) and
        (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
        ((has("network") | not) or (.network | type == "string" and
          IN("","udp","udp4","udp6","tcp","tcp4","tcp6")))));
    (type == "object" and
    ((keys - [
      "mode","server","server_port","servers","remote_random","network","address",
      "peer_address","peer_address_ipv6","topology","username","password","auth_retry",
      "static_challenge","static_challenge_echo","static_key","static_key_path",
      "key_direction","tls","cipher","data_ciphers","data_ciphers_fallback","auth",
      "mss_fix","mss_fix_disabled","mss_fix_mode","fragment","replay_window",
      "replay_window_time","compression","compression_lzo","allow_compression",
      "route_no_pull","pull_filters","routes","route_gateway","route_metric",
      "redirect_gateway","redirect_gateway_flags","redirect_private","block_ipv6",
      "ping_interval","ping_restart","ping_restart_disabled","renegotiate_interval",
      "renegotiate_disabled","renegotiate_bytes","renegotiate_packets","tls_timeout",
      "handshake_window","explicit_exit_notify","system","name","mtu","udp_mapping",
      "udp_filtering","udp_nat_max","udp_timeout","detour","bind_interface",
      "inet4_bind_address","inet6_bind_address","bind_address_no_port","protect_path",
      "routing_mark","reuse_addr","netns","connect_timeout","tcp_fast_open",
      "tcp_multi_path","disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval",
      "udp_fragment","domain_resolver","network_strategy","network_type",
      "fallback_network_type","fallback_delay"
    ]) | length == 0) and
    ((has("mode") | not) or (.mode | type == "string" and IN("","tls","static_key"))) and
    optional_safe_string("server") and
    ((has("server_port") | not) or
      (.server_port | type == "number" and . == floor and . >= 1 and . <= 65535)) and
    optional_servers and optional_bool("remote_random") and optional_network("network") and
    optional_prefix_list("address") and optional_addr("peer_address") and
    optional_addr("peer_address_ipv6") and
    ((has("topology") | not) or (.topology | type == "string" and IN("","net30","p2p","subnet"))) and
    optional_safe_string("username") and optional_safe_string("password") and
    ((has("auth_retry") | not) or (.auth_retry | type == "string" and IN("","none","nointeract","interact"))) and
    optional_safe_string("static_challenge") and optional_bool("static_challenge_echo") and
    optional_material("static_key") and optional_safe_string("static_key_path") and
    ((has("key_direction") | not) or (.key_direction | type == "string" and IN("","server","client"))) and
    ((has("tls") | not) or (.tls | type == "object")) and
    optional_safe_string("cipher") and optional_listable("data_ciphers") and
    optional_safe_string("data_ciphers_fallback") and optional_safe_string("auth") and
    optional_uint("mss_fix"; 4294967295) and optional_bool("mss_fix_disabled") and
    ((has("mss_fix_mode") | not) or (.mss_fix_mode | type == "string" and IN("","mtu","fixed"))) and
    optional_uint("fragment"; 4294967295) and optional_uint("replay_window"; 65536) and
    optional_duration("replay_window_time") and
    ((has("compression") | not) or (.compression | type == "string" and
      IN("","none","no","lz4","lz4-v2","stub","stub-v2","disabled","off"))) and
    ((has("compression_lzo") | not) or (.compression_lzo | type == "string" and
      IN("","none","no","yes","adaptive","asym","disabled","off"))) and
    ((has("allow_compression") | not) or (.allow_compression | type == "string" and IN("","no","asym","yes"))) and
    optional_bool("route_no_pull") and optional_pull_filters and optional_prefix_list("routes") and
    optional_addr("route_gateway") and optional_int("route_metric") and
    optional_bool("redirect_gateway") and optional_listable("redirect_gateway_flags") and
    optional_bool("redirect_private") and optional_bool("block_ipv6") and
    optional_duration("ping_interval") and optional_duration("ping_restart") and
    optional_bool("ping_restart_disabled") and optional_duration("renegotiate_interval") and
    optional_bool("renegotiate_disabled") and optional_uint64("renegotiate_bytes") and
    optional_uint64("renegotiate_packets") and optional_duration("tls_timeout") and
    optional_duration("handshake_window") and optional_uint("explicit_exit_notify"; 4294967295) and
    optional_bool("system") and optional_safe_string("name") and optional_uint("mtu"; 4294967295) and
    optional_udp_nat("udp_mapping") and optional_udp_nat("udp_filtering") and
    optional_uint("udp_nat_max"; 4294967295) and optional_udp_timeout and
    optional_safe_string("detour") and optional_safe_string("bind_interface") and
    optional_safe_string("inet4_bind_address") and optional_safe_string("inet6_bind_address") and
    optional_bool("bind_address_no_port") and optional_safe_string("protect_path") and
    ((has("routing_mark") | not) or
      (.routing_mark | ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
        (type == "string" and (length == 0 or test("^(0x[0-9a-fA-F]+|[0-9]+)$")))))) and
    optional_bool("reuse_addr") and optional_safe_string("netns") and optional_duration("connect_timeout") and
    optional_bool("tcp_fast_open") and optional_bool("tcp_multi_path") and
    optional_bool("disable_tcp_keep_alive") and optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and optional_bool("udp_fragment") and
    ((has("domain_resolver") | not) or (.domain_resolver | type == "string" or type == "object")) and
    ((has("network_strategy") | not) or (.network_strategy | type == "string" and IN("","default","hybrid","fallback"))) and
    optional_network_types("network_type") and optional_network_types("fallback_network_type") and
    optional_duration("fallback_delay") and
    (((.mss_fix_disabled // false) != true) or
      (((.mss_fix // 0) == 0) and ((.mss_fix_mode // "") == ""))) and
    (((.mss_fix_mode // "") == "") or ((.mss_fix // 0) > 0)) and
    (((.fragment // 0) == 0) or ((.fragment // 0) >= 68)) and
    (((.ping_restart_disabled // false) != true) or ((.ping_restart // "") == "")) and
    (((.renegotiate_disabled // false) != true) or ((.renegotiate_interval // "") == "")) and
    (((.allow_compression // "") != "no") or
      (((.compression // "") | IN("","none","no","stub","stub-v2","disabled","off")) and
       ((.compression_lzo // "") | IN("","none","no","disabled","off"))))) as $shape |
    (.mode // "tls") as $mode |
    (.network // "udp") as $network |
    ($shape and (((.server // "") | length > 0) as $has_server |
      ((.servers // []) | length > 0) as $has_servers |
      ($has_server != $has_servers))) and
    ((($network | IN("tcp","tcp4","tcp6")) | not) or ((.fragment // 0) == 0)) and
    (((.server // "") | length == 0) or ((.server_port // 0) | type == "number" and . >= 1)) and
    ($mode != "tls" or (has("tls") and .tls != null)) and
    ($mode != "static_key" or
      (material_set("static_key"; "static_key_path") and
       ((inline_material_set("static_key") and path_material_set("static_key_path")) | not) and
       ((.tls? // null) == null) and ((.username // "") == "") and ((.password // "") == "") and
       ((.auth_retry // "none") == "none") and ((.static_challenge // "") == "") and
       ((.static_challenge_echo // false) == false) and ((.route_no_pull // false) == false) and
       ((.pull_filters // []) | length == 0) and ((.data_ciphers // []) | length == 0) and
       ((.data_ciphers_fallback // "") == "") and ((.renegotiate_interval // "") == "") and
       ((.renegotiate_disabled // false) == false) and ((.renegotiate_bytes // 0) == 0) and
       ((.renegotiate_packets // 0) == 0) and ((.tls_timeout // "") == "") and
       ((.handshake_window // "") == ""))) and
    ($mode != "tls" or
      ((material_set("static_key"; "static_key_path") | not) and
       ((.key_direction // "") == "") and ((.cipher // "") == ""))) and
    ($mode != "static_key" or
      ((.address // []) |
        if type == "array" then length > 0 else length > 0 end))
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  if jq -e 'has("tls") and .tls != null' <<< "${config}" >/dev/null 2>&1; then
    local tls
    tls=$(jq -c '.tls' <<< "${config}") || return 1
    managed_component_openvpn_tls_outbound_validate_json "${tls}" || return 1
  fi

  for field in address routes; do
    while IFS= read -r prefix; do
      [[ -n "${prefix}" ]] || continue
      managed_component_endpoint_prefix_validate "${prefix}" || return 1
      if [[ "${field}" == address ]]; then
        if [[ "${prefix%/*}" == *:* ]]; then
          has_ipv6=true
        else
          has_ipv4=true
        fi
      fi
    done < <(jq -r --arg field "${field}" '.[$field]? // empty | if type == "array" then .[] else . end' <<< "${config}")
  done
  for field in peer_address peer_address_ipv6 route_gateway; do
    value=$(jq -r --arg field "${field}" '.[$field]? // empty' <<< "${config}") || return 1
    if [[ -n "${value}" ]]; then
      structured_instance_store_validate_address "${value}" || return 1
    fi
  done
  if [[ "$(jq -r '.mode // "tls"' <<< "${config}")" == static_key ]]; then
    if [[ "${has_ipv4}" == true ]]; then
      peer_address=$(jq -r '.peer_address // empty' <<< "${config}") || return 1
      [[ -n "${peer_address}" && "${peer_address}" != *:* ]] || return 1
    fi
    if [[ "${has_ipv6}" == true ]]; then
      peer_address_ipv6=$(jq -r '.peer_address_ipv6 // empty' <<< "${config}") || return 1
      [[ -n "${peer_address_ipv6}" && "${peer_address_ipv6}" == *:* ]] || return 1
    fi
    if [[ "${has_ipv4}" != true ]]; then
      [[ -z "$(jq -r '.peer_address // empty' <<< "${config}")" ]] || return 1
    fi
    if [[ "${has_ipv6}" != true ]]; then
      [[ -z "$(jq -r '.peer_address_ipv6 // empty' <<< "${config}")" ]] || return 1
    fi
  fi
}

# Validate the OpenVPN server endpoint contract.  The server combines
# Listen Fields with a TLS/static-key union and an optional pushed DNS/route
# policy; keep those nested records strict before state publication so a
# restart cannot discover an invalid pool, peer address or authentication
# mode after the CAS has already committed.
managed_component_openvpn_server_config_validate_json() {
  local config=${1:-} field prefix value address family_count_v4=0 family_count_v6=0
  local has_ipv4=false has_ipv6=false peer_address peer_address_ipv6
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
    def optional_uint($name; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= $max);
    def optional_int($name; $min; $max):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= $min and . <= $max);
    def optional_uint64($name):
      (has($name) | not) or
      (.[$name] | type == "number" and . == floor and . >= 0 and . <= 9007199254740991);
    def optional_duration($name):
      (has($name) | not) or (.[$name] | safe_string);
    def optional_udp_timeout:
      (has("udp_timeout") | not) or
      (.udp_timeout |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and safe_string)));
    def optional_udp_nat($name):
      (has($name) | not) or
      (.[$name] | type == "string" and
        IN("","endpoint_independent","address_dependent","address_and_port_dependent"));
    def listable_safe_string:
      ((type == "string" and safe_string) or
       (type == "array" and all(.[]; safe_string)));
    def listable_nonempty_safe_string:
      ((type == "string" and nonempty_safe_string) or
       (type == "array" and length > 0 and all(.[]; nonempty_safe_string)));
    def optional_listable($name):
      (has($name) | not) or (.[$name] | listable_safe_string);
    def required_listable_nonempty($name):
      has($name) and (.[$name] | listable_nonempty_safe_string);
    def optional_nonempty_listable($name):
      (has($name) | not) or (.[$name] | listable_nonempty_safe_string);
    def optional_prefix_list($name):
      (has($name) | not) or
      (.[$name] |
        ((type == "string" and nonempty_safe_string) or
         (type == "array" and all(.[]; nonempty_safe_string))));
    def material_safe_string:
      type == "string" and
      (any(explode[]; ((. < 32 and . != 9 and . != 10 and . != 13) or . == 127)) | not);
    def material_listable_string:
      ((type == "string" and material_safe_string) or
       (type == "array" and all(.[]; material_safe_string)));
    def optional_material($name):
      (has($name) | not) or (.[$name] | material_listable_string);
    def inline_material_set($name):
      (has($name) and (.[$name] |
        if type == "string" then length > 0
        elif type == "array" then any(.[]; type == "string" and length > 0)
        else false end));
    def path_material_set($name):
      (has($name) and (.[$name] | type == "string" and length > 0));
    def material_set($inline; $path):
      (inline_material_set($inline) or path_material_set($path));
    def optional_users:
      (has("users") | not) or
      (.users | type == "array" and all(.[];
        type == "object" and ((keys - ["username","password"]) | length == 0) and
        (.username | nonempty_safe_string) and (.password | safe_string)));
    def optional_dns_servers:
      (has("dns_servers") | not) or
      (.dns_servers | type == "array" and all(.[];
        type == "object" and
        ((keys - ["priority","addresses","resolve_domains","dnssec","transport","sni"]) | length == 0) and
        (.priority | type == "number" and . == floor and . >= -2147483648 and . <= 2147483647) and
        (has("addresses") and (.addresses | listable_nonempty_safe_string)) and
        optional_listable("resolve_domains") and
        ((has("dnssec") | not) or (.dnssec | type == "string" and IN("","yes","optional","no"))) and
        ((has("transport") | not) or (.transport | type == "string" and IN("","plain","dot","doh"))) and
        optional_safe_string("sni")));
    def optional_push:
      (has("push") | not) or
      (.push | type == "object" and
        ((keys - ["routes","dns","dns_servers","search_domains","dhcp_options",
          "redirect_gateway","redirect_gateway_flags","block_outside_dns",
          "ping_interval","ping_restart"]) | length == 0) and
        optional_prefix_list("routes") and optional_nonempty_listable("dns") and optional_dns_servers and
        optional_listable("search_domains") and optional_listable("dhcp_options") and
        optional_bool("redirect_gateway") and optional_listable("redirect_gateway_flags") and
        optional_bool("block_outside_dns") and optional_duration("ping_interval") and
        optional_duration("ping_restart") and
        (((.redirect_gateway // false) == true) or
          ((.redirect_gateway_flags // []) | if type == "array" then length == 0 else length == 0 end)));
    (type == "object" and
    ((keys - [
      "listen","listen_port","bind_interface","routing_mark","reuse_addr","netns",
      "disable_tcp_keep_alive","tcp_keep_alive","tcp_keep_alive_interval","tcp_fast_open",
      "tcp_multi_path","udp_fragment","udp_timeout","detour","system","name","mtu",
      "udp_mapping","udp_filtering","udp_nat_max","mode","network","remote","remote_port",
      "max_clients","address","peer_address","peer_address_ipv6","topology","duplicate_cn",
      "users","static_key","static_key_path","key_direction","tls","cipher","data_ciphers",
      "data_ciphers_fallback","auth","mss_fix","mss_fix_disabled","mss_fix_mode",
      "replay_window","replay_window_time","push","ping_interval","ping_restart",
      "renegotiate_interval","renegotiate_disabled","renegotiate_bytes","renegotiate_packets",
      "handshake_window"
    ]) | length == 0) and
    optional_safe_string("listen") and
    (.listen_port | type == "number" and . == floor and . >= 1 and . <= 65535) and
    optional_safe_string("bind_interface") and
    ((has("routing_mark") | not) or
      (.routing_mark |
        ((type == "number" and . == floor and . >= 0 and . <= 4294967295) or
         (type == "string" and (length == 0 or test("^(0x[0-9a-fA-F]+|[0-9]+)$")))))) and
    optional_bool("reuse_addr") and optional_safe_string("netns") and
    optional_bool("disable_tcp_keep_alive") and optional_duration("tcp_keep_alive") and
    optional_duration("tcp_keep_alive_interval") and optional_bool("tcp_fast_open") and
    optional_bool("tcp_multi_path") and optional_bool("udp_fragment") and optional_udp_timeout and
    optional_safe_string("detour") and optional_bool("system") and optional_safe_string("name") and
    optional_uint("mtu"; 4294967295) and optional_udp_nat("udp_mapping") and
    optional_udp_nat("udp_filtering") and optional_uint("udp_nat_max"; 4294967295) and
    ((has("mode") | not) or (.mode | type == "string" and IN("","tls","static_key"))) and
    ((has("network") | not) or (.network | type == "string" and IN("","tcp","udp"))) and
    optional_safe_string("remote") and optional_uint("remote_port"; 65535) and
    optional_int("max_clients"; 0; 16777215) and required_listable_nonempty("address") and
    optional_safe_string("peer_address") and optional_safe_string("peer_address_ipv6") and
    ((has("topology") | not) or (.topology | type == "string" and IN("","net30","p2p","subnet"))) and
    optional_bool("duplicate_cn") and optional_users and optional_material("static_key") and
    optional_safe_string("static_key_path") and
    ((has("key_direction") | not) or (.key_direction | type == "string" and IN("","server","client"))) and
    ((has("tls") | not) or (.tls | type == "object")) and optional_safe_string("cipher") and
    optional_listable("data_ciphers") and optional_safe_string("data_ciphers_fallback") and
    optional_safe_string("auth") and optional_uint("mss_fix"; 4294967295) and
    optional_bool("mss_fix_disabled") and
    ((has("mss_fix_mode") | not) or (.mss_fix_mode | type == "string" and IN("","mtu","fixed"))) and
    optional_uint("replay_window"; 65536) and optional_duration("replay_window_time") and
    optional_push and optional_duration("ping_interval") and optional_duration("ping_restart") and
    optional_duration("renegotiate_interval") and optional_bool("renegotiate_disabled") and
    optional_uint64("renegotiate_bytes") and optional_uint64("renegotiate_packets") and
    optional_duration("handshake_window") and
    (((.mss_fix_mode // "") == "") or ((.mss_fix // 0) > 0)) and
    (((.mss_fix_disabled // false) != true) or
      (((.mss_fix // 0) == 0) and ((.mss_fix_mode // "") == "")))) as $shape |
    (.mode // "tls") as $mode |
    (.network // "udp") as $network |
    ($shape and ($mode == "tls" and has("tls") and .tls != null or $mode == "static_key")) and
    ($mode == "tls" or
      (material_set("static_key"; "static_key_path") and
       ((inline_material_set("static_key") and path_material_set("static_key_path")) | not) and
       ((.tls? // null) == null) and ((.users // []) | length == 0) and
       ((.duplicate_cn // false) == false) and ((.push? // null) == null) and
       ((.renegotiate_interval // "") == "") and ((.renegotiate_disabled // false) == false) and
       ((.renegotiate_bytes // 0) == 0) and ((.renegotiate_packets // 0) == 0) and
       ((.handshake_window // "") == "") and ((.data_ciphers // []) | length == 0) and
       ((.data_ciphers_fallback // "") == "") and
       ((.max_clients // 0) <= 1))) and
    ($mode == "tls" or
      (((.remote // "") != "") == ($network == "udp")) and
       (($network == "udp" and ((.remote_port // 0) >= 1)) or
        ($network == "tcp" and ((.remote_port // 0) == 0))) and
       ((.peer_address // "") == "" or (.peer_address | type == "string")) and
       ((.peer_address_ipv6 // "") == "" or (.peer_address_ipv6 | type == "string"))) and
    ($mode == "static_key" or
      (((.static_key? // null) == null or (.static_key? | if type == "string" then length == 0 else length == 0 end)) and
       ((.static_key_path // "") == "") and ((.key_direction // "") == "") and
       ((.cipher // "") == "") and ((.remote // "") == "") and
       ((.remote_port // 0) == 0) and ((.peer_address // "") == "") and
       ((.peer_address_ipv6 // "") == "") and ((.max_clients // 0) >= 0)))
  ' <<< "${config}" >/dev/null 2>&1 || return 1

  if jq -e 'has("tls") and .tls != null' <<< "${config}" >/dev/null 2>&1; then
    local tls
    tls=$(jq -c '.tls' <<< "${config}") || return 1
    managed_component_openvpn_tls_inbound_validate_json "${tls}" || return 1
  fi

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    managed_component_endpoint_prefix_validate "${prefix}" || return 1
    address=${prefix%/*}
    if [[ "${address}" == *:* ]]; then
      family_count_v6=$((family_count_v6 + 1))
      has_ipv6=true
    else
      family_count_v4=$((family_count_v4 + 1))
      has_ipv4=true
    fi
  done < <(jq -r '.address | if type == "array" then .[] else . end' <<< "${config}")
  (( family_count_v4 <= 1 && family_count_v6 <= 1 )) || return 1

  while IFS= read -r prefix; do
    [[ -n "${prefix}" ]] || continue
    managed_component_endpoint_prefix_validate "${prefix}" || return 1
  done < <(jq -r '.push.routes? // empty | if type == "array" then .[] else . end' <<< "${config}")

  for field in peer_address peer_address_ipv6; do
    value=$(jq -r --arg field "${field}" '.[$field]? // empty' <<< "${config}") || return 1
    if [[ -n "${value}" ]]; then
      structured_instance_store_validate_address "${value}" || return 1
      if [[ "${field}" == peer_address && "${value}" == *:* ]]; then
        return 1
      elif [[ "${field}" == peer_address_ipv6 && "${value}" != *:* ]]; then
        return 1
      fi
    fi
  done

  if [[ "$(jq -r '.mode // "tls"' <<< "${config}")" == static_key ]]; then
    if [[ "${has_ipv4}" == true ]]; then
      peer_address=$(jq -r '.peer_address // empty' <<< "${config}") || return 1
      [[ -n "${peer_address}" && "${peer_address}" != *:* ]] || return 1
    fi
    if [[ "${has_ipv6}" == true ]]; then
      peer_address_ipv6=$(jq -r '.peer_address_ipv6 // empty' <<< "${config}") || return 1
      [[ -n "${peer_address_ipv6}" && "${peer_address_ipv6}" == *:* ]] || return 1
    fi
    if [[ "${has_ipv4}" != true ]]; then
      [[ -z "$(jq -r '.peer_address // empty' <<< "${config}")" ]] || return 1
    fi
    if [[ "${has_ipv6}" != true ]]; then
      [[ -z "$(jq -r '.peer_address_ipv6 // empty' <<< "${config}")" ]] || return 1
    fi
  fi

  while IFS= read -r value; do
    [[ -n "${value}" ]] || continue
    if structured_instance_store_validate_address "${value}"; then
      continue
    fi
    managed_component_endpoint_addrport_validate "${value}" || return 1
    if [[ "${value}" == \[*\]:* ]]; then
      value=${value##*\]:}
    else
      value=${value##*:}
    fi
    (( 10#${value} >= 1 )) || return 1
  done < <(jq -r '.push.dns_servers[]?.addresses? // empty | if type == "array" then .[] else . end' <<< "${config}")

  while IFS= read -r value; do
    [[ -n "${value}" ]] || continue
    structured_instance_store_validate_address "${value}" || return 1
  done < <(jq -r '.push.dns? // empty | if type == "array" then .[] else . end' <<< "${config}")
}
