#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

registry=$(component_registry_json)
jq -e '
  length == 30 and
  ([.[].state_id] | unique | length) == 30 and
  ([.[] | select(.role == "inbound") | .type] | sort) ==
    ["cloudflared","direct","redirect","tproxy","tun"] and
  ([.[] | select(.role == "endpoint") | .type] | sort) ==
    ["openconnect","openvpn-client","openvpn-server","tailscale","wireguard"] and
  any(.[]; .role == "outbound" and .type == "selector" and .features.group == true) and
  any(.[]; .role == "outbound" and .type == "urltest" and .features.group == true) and
  all(.[]; .lifecycle.takeover == true) and
  any(.[]; .role == "inbound" and .type == "cloudflared" and
    .features.account_mutation == false and .availability == "with_cloudflared")
' <<< "${registry}" >/dev/null

direct_record='{"id":"direct-local","role":"inbound","type":"direct","tag":"direct-local-in","enabled":true,"route_rules":[],"config":{"listen":"127.0.0.1","listen_port":15080}}'
tun_record='{"id":"tun-local","role":"inbound","type":"tun","tag":"tun-local-in","enabled":true,"route_rules":[],"config":{"interface_name":"tun-sbv","address":["172.19.0.1/30"],"auto_route":false,"strict_route":true}}'
redirect_record='{"id":"redirect-local","role":"inbound","type":"redirect","tag":"redirect-local-in","enabled":true,"route_rules":[],"config":{"listen":"127.0.0.1","listen_port":15081}}'
selector_record='{"id":"selector-local","role":"outbound","type":"selector","tag":"selector-local","enabled":true,"route_rules":[{"inbound":["direct-local-in"],"action":"route","outbound":"selector-local"}],"config":{"outbounds":["direct","block"],"default":"direct"}}'

state=$(managed_component_state_default_json)
state=$(managed_component_state_candidate "${state}" create "${direct_record}")
state=$(managed_component_state_candidate "${state}" create "${selector_record}")
invalid_state_file="${TMP_DIR}/invalid-components-state.json"
jq -e '.extra = true' <<< "${state}" >"${invalid_state_file}"
if managed_component_state_validate_json "$(< "${invalid_state_file}")"; then
  printf 'unexpected component state field was accepted\n' >&2
  exit 1
fi
rm -f "${invalid_state_file}"
jq -e '.revision == 2 and ([.components[].tag] | sort) == ["direct-local-in","selector-local"]' <<< "${state}" >/dev/null
rendered=$(managed_component_render_json "${state}")
jq -e '
  .inbounds[0].type == "direct" and .inbounds[0].tag == "direct-local-in" and
  .outbounds[0].type == "selector" and .outbounds[0].outbounds == ["direct","block"]
' <<< "${rendered}" >/dev/null

# SSH is a typed outbound contract: retain the upstream SSH fields and Dial
# Fields, require one usable authentication method, and reject accidental
# passthrough of unknown/deprecated keys.  Private keys may be PEM/multiline
# strings; list/diagnose must still expose metadata only.
ssh_record='{"id":"ssh-local","role":"outbound","type":"ssh","tag":"ssh-local","enabled":true,"route_rules":[],"config":{"server":"ssh.example","server_port":2222,"user":"deploy","password":"ssh-password","host_key":["ssh-ed25519 AAAAssh-host-key"],"client_version":"SSH-2.0-sing-box","connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/ssh-protect"}}'
managed_component_state_validate_record "${ssh_record}"
ssh_empty_path_record=$(jq -c '.config.private_key_path = ""' <<< "${ssh_record}")
managed_component_state_validate_record "${ssh_empty_path_record}"
ssh_rendered_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${ssh_record}")
ssh_rendered=$(managed_component_render_json "${ssh_rendered_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "ssh" and .outbounds[0].tag == "ssh-local" and
  .outbounds[0].server_port == 2222 and
  .outbounds[0].host_key == ["ssh-ed25519 AAAAssh-host-key"] and
  .outbounds[0].protect_path == "/usr/lib/sing-box/ssh-protect" and
  .outbounds[0].route_rules == null
' <<< "${ssh_rendered}" >/dev/null
ssh_path_record=$(jq -c '.config |= (del(.password) + {private_key_path:"/root/.ssh/id_ed25519",host_key:"ssh-ed25519 AAAAssh-host-key"})' <<< "${ssh_record}")
managed_component_state_validate_record "${ssh_path_record}"
ssh_key_record=$(jq -c '.config |= (del(.password) + {private_key:"-----BEGIN OPENSSH PRIVATE KEY-----\nfixture\n-----END OPENSSH PRIVATE KEY-----",private_key_passphrase:"passphrase"})' <<< "${ssh_record}")
managed_component_state_validate_record "${ssh_key_record}"
ssh_missing_auth=$(jq -c '.config |= del(.password,.private_key,.private_key_path)' <<< "${ssh_record}")
if managed_component_state_validate_record "${ssh_missing_auth}"; then
  printf 'SSH outbound without authentication unexpectedly accepted\n' >&2
  exit 1
fi
ssh_passphrase_without_key=$(jq -c '.config |= (del(.password) + {private_key_passphrase:"orphan-passphrase"})' <<< "${ssh_record}")
if managed_component_state_validate_record "${ssh_passphrase_without_key}"; then
  printf 'SSH private key passphrase without a key unexpectedly accepted\n' >&2
  exit 1
fi
ssh_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${ssh_record}")
if managed_component_state_validate_record "${ssh_unknown_field}"; then
  printf 'SSH deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
ssh_bad_port=$(jq -c '.config.server_port = 65536' <<< "${ssh_record}")
if managed_component_state_validate_record "${ssh_bad_port}"; then
  printf 'SSH out-of-range server port unexpectedly accepted\n' >&2
  exit 1
fi
ssh_unverified_record=$(jq -c '.config |= del(.host_key)' <<< "${ssh_record}")
managed_component_state_validate_record "${ssh_unverified_record}"
ssh_pinned_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${ssh_record}")
original_managed_component_state_json=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${ssh_pinned_state}"
}
ssh_pinned_inventory=$(managed_component_inventory_json)
eval "${original_managed_component_state_json}"
jq -e '.components[0].host_key_verification == "pinned"' <<< "${ssh_pinned_inventory}" >/dev/null
ssh_unverified_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${ssh_unverified_record}")
original_managed_component_state_json=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${ssh_unverified_state}"
}
ssh_unverified_inventory=$(managed_component_inventory_json)
eval "${original_managed_component_state_json}"
if grep -Fq 'ssh-password' <<< "${ssh_unverified_inventory}"; then
  printf 'SSH outbound password leaked from inventory\n' >&2
  exit 1
fi
jq -e '(.components | length == 1) and
  .components[0].type == "ssh" and
  .components[0].host_key_verification == "unverified" and
  (.components[0].config_keys | index("password")) != null' <<< "${ssh_unverified_inventory}" >/dev/null

# Tor is a runtime-backed outbound rather than a server node.  The typed
# contract preserves the upstream external/embedded forms, torrc string map,
# extra arguments and Dial Fields while rejecting deprecated/unsafe shapes.
tor_record='{"id":"tor-local","role":"outbound","type":"tor","tag":"tor-local","enabled":true,"route_rules":[],"config":{"executable_path":"/usr/bin/tor","extra_args":["--SocksPort","0"],"data_directory":"/var/lib/sing-box/tor","torrc":{"ClientOnly":"1","Log":"notice stdout"},"protect_path":"/usr/lib/sing-box/tor-protect","connect_timeout":"10s","network_strategy":"fallback","network_type":["ethernet"]}}'
managed_component_state_validate_record "${tor_record}"
tor_rendered_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${tor_record}")
tor_rendered=$(managed_component_render_json "${tor_rendered_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "tor" and .outbounds[0].tag == "tor-local" and
  .outbounds[0].executable_path == "/usr/bin/tor" and
  .outbounds[0].extra_args == ["--SocksPort","0"] and
  .outbounds[0].torrc.ClientOnly == "1" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/tor-protect"
' <<< "${tor_rendered}" >/dev/null
tor_embedded_record=$(jq -c '.config |= (del(.executable_path) + {torrc:{ClientOnly:"1"}})' <<< "${tor_record}")
managed_component_state_validate_record "${tor_embedded_record}"
tor_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${tor_record}")
if managed_component_state_validate_record "${tor_unknown_field}"; then
  printf 'Tor deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
tor_bad_args=$(jq -c '.config.extra_args = {value:"--SocksPort"}' <<< "${tor_record}")
if managed_component_state_validate_record "${tor_bad_args}"; then
  printf 'Tor non-array extra_args unexpectedly accepted\n' >&2
  exit 1
fi
tor_bad_torrc=$(jq -c '.config.torrc = {ClientOnly:1}' <<< "${tor_record}")
if managed_component_state_validate_record "${tor_bad_torrc}"; then
  printf 'Tor non-string torrc value unexpectedly accepted\n' >&2
  exit 1
fi
tor_bad_path=$(jq -c '.config.executable_path = "/usr/bin/tor\u0001"' <<< "${tor_record}")
if managed_component_state_validate_record "${tor_bad_path}"; then
  printf 'Tor control-character executable path unexpectedly accepted\n' >&2
  exit 1
fi
tor_external_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${tor_record}")
original_managed_component_state_json=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${tor_external_state}"
}
tor_external_inventory=$(managed_component_inventory_json)
eval "${original_managed_component_state_json}"
jq -e '.components[0].runtime_mode == "external"' <<< "${tor_external_inventory}" >/dev/null
tor_embedded_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${tor_embedded_record}")
original_managed_component_state_json=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${tor_embedded_state}"
}
tor_embedded_inventory=$(managed_component_inventory_json)
eval "${original_managed_component_state_json}"
jq -e '.components[0].runtime_mode == "embedded_unverified"' <<< "${tor_embedded_inventory}" >/dev/null

# SOCKS outbound is a typed client-side dialer.  Keep the server/auth,
# listable TCP/UDP network, optional UDP-over-TCP and shared Dial Fields, but
# reject deprecated/unknown fields and malformed scalar values before state
# publication.
socks_outbound_record='{"id":"socks-outbound-local","role":"outbound","type":"socks","tag":"socks-upstream","enabled":true,"route_rules":[],"config":{"server":"127.0.0.1","server_port":1080,"version":"5","username":"proxy-user","password":"proxy-password","network":["tcp","udp"],"udp_over_tcp":{"enabled":true,"version":2},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/socks-protect"}}'
managed_component_state_validate_record "${socks_outbound_record}"
socks_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${socks_outbound_record}")
socks_outbound_rendered=$(managed_component_render_json "${socks_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "socks" and
  .outbounds[0].tag == "socks-upstream" and
  .outbounds[0].server_port == 1080 and
  .outbounds[0].version == "5" and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].udp_over_tcp.enabled == true and
  .outbounds[0].udp_over_tcp.version == 2 and
  .outbounds[0].protect_path == "/usr/lib/sing-box/socks-protect" and
  .outbounds[0].route_rules == null
' <<< "${socks_outbound_rendered}" >/dev/null
socks_default_version=$(jq -c '.config |= del(.version)' <<< "${socks_outbound_record}")
managed_component_state_validate_record "${socks_default_version}"
socks_bad_version=$(jq -c '.config.version = "6"' <<< "${socks_outbound_record}")
if managed_component_state_validate_record "${socks_bad_version}"; then
  printf 'SOCKS unsupported version unexpectedly accepted\n' >&2
  exit 1
fi
socks_bad_network=$(jq -c '.config.network = ["icmp"]' <<< "${socks_outbound_record}")
if managed_component_state_validate_record "${socks_bad_network}"; then
  printf 'SOCKS unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
socks_bad_uot=$(jq -c '.config.udp_over_tcp = {enabled:true,version:3}' <<< "${socks_outbound_record}")
if managed_component_state_validate_record "${socks_bad_uot}"; then
  printf 'SOCKS unsupported UDP-over-TCP version unexpectedly accepted\n' >&2
  exit 1
fi
socks_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${socks_outbound_record}")
if managed_component_state_validate_record "${socks_unknown_field}"; then
  printf 'SOCKS deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
socks_bad_server=$(jq -c '.config.server = "proxy\u0001.example"' <<< "${socks_outbound_record}")
if managed_component_state_validate_record "${socks_bad_server}"; then
  printf 'SOCKS control-character server unexpectedly accepted\n' >&2
  exit 1
fi
socks_bad_port=$(jq -c '.config.server_port = 65536' <<< "${socks_outbound_record}")
if managed_component_state_validate_record "${socks_bad_port}"; then
  printf 'SOCKS out-of-range server port unexpectedly accepted\n' >&2
  exit 1
fi

# HTTP outbound is a TCP-only upstream proxy.  Its headers and outbound TLS
# object are typed recursively so an unknown nested option cannot bypass the
# component contract.
http_outbound_record='{"id":"http-outbound-local","role":"outbound","type":"http","tag":"http-upstream","enabled":true,"route_rules":[],"config":{"server":"127.0.0.1","server_port":3128,"username":"proxy-user","password":"proxy-password","path":"/proxy","headers":{"User-Agent":"sing-box-vps","X-Proxy":["one","two"]},"tls":{"enabled":true,"engine":"go","server_name":"proxy.example","insecure":false,"alpn":["h2","http/1.1"],"min_version":"1.2","max_version":"1.3","curve_preferences":["X25519","P256"],"utls":{"enabled":true,"fingerprint":"chrome"},"ech":{"enabled":false,"config_path":"/etc/sing-box/ech.bin"},"reality":{"enabled":false,"public_key":"","short_id":""}},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/http-protect"}}'
managed_component_state_validate_record "${http_outbound_record}"
http_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${http_outbound_record}")
http_outbound_rendered=$(managed_component_render_json "${http_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "http" and
  .outbounds[0].tag == "http-upstream" and
  .outbounds[0].server_port == 3128 and
  .outbounds[0].path == "/proxy" and
  .outbounds[0].headers["X-Proxy"] == ["one","two"] and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.utls.fingerprint == "chrome" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/http-protect" and
  .outbounds[0].route_rules == null
' <<< "${http_outbound_rendered}" >/dev/null
http_plain_record=$(jq -c '.config |= del(.tls,.path,.headers)' <<< "${http_outbound_record}")
managed_component_state_validate_record "${http_plain_record}"
http_bad_header_value=$(jq -c '.config.headers["X-Proxy"] = 42' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_bad_header_value}"; then
  printf 'HTTP non-string header value unexpectedly accepted\n' >&2
  exit 1
fi
http_bad_header_name=$(jq -c '.config.headers["Bad Header"] = "value"' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_bad_header_name}"; then
  printf 'HTTP invalid header name unexpectedly accepted\n' >&2
  exit 1
fi
http_bad_tls_field=$(jq -c '.config.tls |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_bad_tls_field}"; then
  printf 'HTTP unknown TLS field unexpectedly accepted\n' >&2
  exit 1
fi
http_bad_ech_field=$(jq -c '.config.tls.ech |= (. + {pq_signature_schemes_enabled:true})' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_bad_ech_field}"; then
  printf 'HTTP deprecated ECH field unexpectedly accepted\n' >&2
  exit 1
fi
http_bad_engine=$(jq -c '.config.tls.engine = "rustls"' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_bad_engine}"; then
  printf 'HTTP unsupported TLS engine unexpectedly accepted\n' >&2
  exit 1
fi
http_bad_path=$(jq -c '.config.path = "/proxy\u0001"' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_bad_path}"; then
  printf 'HTTP control-character path unexpectedly accepted\n' >&2
  exit 1
fi
http_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${http_outbound_record}")
if managed_component_state_validate_record "${http_unknown_field}"; then
  printf 'HTTP deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi

# Shadowsocks outbound keeps the target core's method/password contract,
# listable network, SIP003 plugin, UDP-over-TCP and multiplex options typed
# before state/CAS publication.  SS2022 passwords are validated by byte size.
shadowsocks_outbound_record='{"id":"shadowsocks-outbound-local","role":"outbound","type":"shadowsocks","tag":"ss-upstream","enabled":true,"route_rules":[],"config":{"server":"127.0.0.1","server_port":8388,"method":"2022-blake3-aes-128-gcm","password":"AAAAAAAAAAAAAAAAAAAAAA==","plugin":"obfs-local","plugin_opts":"obfs=http;obfs-host=proxy.example","network":["tcp","udp"],"udp_over_tcp":{"enabled":true,"version":2},"multiplex":{"enabled":true,"protocol":"h2mux","max_connections":2,"min_streams":1,"max_streams":4,"padding":true,"brutal":{"enabled":false}},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/shadowsocks-protect"}}'
managed_component_state_validate_record "${shadowsocks_outbound_record}"
shadowsocks_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${shadowsocks_outbound_record}")
shadowsocks_outbound_rendered=$(managed_component_render_json "${shadowsocks_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "shadowsocks" and
  .outbounds[0].tag == "ss-upstream" and
  .outbounds[0].server_port == 8388 and
  .outbounds[0].method == "2022-blake3-aes-128-gcm" and
  .outbounds[0].password == "AAAAAAAAAAAAAAAAAAAAAA==" and
  .outbounds[0].plugin == "obfs-local" and
  .outbounds[0].plugin_opts == "obfs=http;obfs-host=proxy.example" and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].udp_over_tcp.version == 2 and
  .outbounds[0].multiplex.protocol == "h2mux" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/shadowsocks-protect" and
  .outbounds[0].route_rules == null
' <<< "${shadowsocks_outbound_rendered}" >/dev/null
shadowsocks_legacy_record=$(jq -c '.config |= (. + {method:"aes-256-gcm",password:"legacy-password"})' <<< "${shadowsocks_outbound_record}")
managed_component_state_validate_record "${shadowsocks_legacy_record}"
shadowsocks_2022_256_record=$(jq -c '.config |= (. + {method:"2022-blake3-aes-256-gcm",password:"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="})' <<< "${shadowsocks_outbound_record}")
managed_component_state_validate_record "${shadowsocks_2022_256_record}"
shadowsocks_none_record=$(jq -c '.config |= (. + {method:"none",password:""})' <<< "${shadowsocks_outbound_record}")
managed_component_state_validate_record "${shadowsocks_none_record}"
shadowsocks_missing_method=$(jq -c '.config |= del(.method)' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_missing_method}"; then
  printf 'Shadowsocks missing method unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_method=$(jq -c '.config.method = "aes-192-foo"' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_method}"; then
  printf 'Shadowsocks unknown method unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_2022_short=$(jq -c '.config.password = "short"' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_2022_short}"; then
  printf 'Shadowsocks SS2022 short key unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_2022_256=$(jq -c '.config.method = "2022-blake3-aes-256-gcm"' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_2022_256}"; then
  printf 'Shadowsocks SS2022 256-bit short key unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_legacy_password=$(jq -c '.config |= (. + {method:"aes-128-gcm",password:""})' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_legacy_password}"; then
  printf 'Shadowsocks encrypted method without password unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_network=$(jq -c '.config.network = ["tcp","icmp"]' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_network}"; then
  printf 'Shadowsocks unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_plugin=$(jq -c '.config.plugin = "simple-obfs"' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_plugin}"; then
  printf 'Shadowsocks unsupported plugin unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_plugin_opts=$(jq -c '.config.plugin_opts = "obfs=http\u0001"' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_plugin_opts}"; then
  printf 'Shadowsocks control-character plugin options unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_multiplex=$(jq -c '.config.multiplex |= (. + {unknown:true})' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_multiplex}"; then
  printf 'Shadowsocks unknown multiplex field unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_uot=$(jq -c '.config.udp_over_tcp = {enabled:true,version:3}' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_uot}"; then
  printf 'Shadowsocks unsupported UDP-over-TCP version unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_unknown_field}"; then
  printf 'Shadowsocks deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
shadowsocks_bad_server=$(jq -c '.config.server = "proxy\u0001.example"' <<< "${shadowsocks_outbound_record}")
if managed_component_state_validate_record "${shadowsocks_bad_server}"; then
  printf 'Shadowsocks control-character server unexpectedly accepted\n' >&2
  exit 1
fi

# VMess and Trojan outbounds share the fixed 1.14 V2Ray transport, outbound
# TLS and multiplex contracts.  Keep credentials and packet/security options
# typed through the same component state/CAS path rather than accepting an
# arbitrary client profile blob.
vmess_outbound_record='{"id":"vmess-outbound-local","role":"outbound","type":"vmess","tag":"vmess-upstream","enabled":true,"route_rules":[],"config":{"server":"127.0.0.1","server_port":443,"uuid":"bf000d23-0752-40b4-affe-68f7707a9661","security":"auto","alter_id":0,"global_padding":true,"authenticated_length":true,"network":["tcp","udp"],"tls":{"enabled":true,"server_name":"vmess.example","insecure":true},"packet_encoding":"xudp","transport":{"type":"ws","path":"/vmess","headers":{"Host":"vmess.example"}},"multiplex":{"enabled":false,"protocol":"h2mux","max_connections":2,"min_streams":1,"max_streams":4,"padding":true,"brutal":{"enabled":false}},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/vmess-protect"}}'
managed_component_state_validate_record "${vmess_outbound_record}"
vmess_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${vmess_outbound_record}")
vmess_outbound_rendered=$(managed_component_render_json "${vmess_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "vmess" and
  .outbounds[0].tag == "vmess-upstream" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].uuid == "bf000d23-0752-40b4-affe-68f7707a9661" and
  .outbounds[0].security == "auto" and
  .outbounds[0].packet_encoding == "xudp" and
  .outbounds[0].transport.type == "ws" and
  .outbounds[0].transport.headers.Host == "vmess.example" and
  .outbounds[0].multiplex.protocol == "h2mux" and
  .outbounds[0].tls.server_name == "vmess.example" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/vmess-protect" and
  .outbounds[0].route_rules == null
' <<< "${vmess_outbound_rendered}" >/dev/null
vmess_plain_record=$(jq -c '.config |= del(.tls,.transport,.multiplex)' <<< "${vmess_outbound_record}")
managed_component_state_validate_record "${vmess_plain_record}"
vmess_http_transport=$(jq -c '.config.transport = {type:"http",host:["vmess.example"],path:"/vmess",method:"POST",headers:{"X-Proxy":"vmess"},idle_timeout:"30s",ping_timeout:"10s"}' <<< "${vmess_outbound_record}")
managed_component_state_validate_record "${vmess_http_transport}"
vmess_grpc_transport=$(jq -c '.config.transport = {type:"grpc",service_name:"vmess",idle_timeout:"30s",ping_timeout:"10s",permit_without_stream:false}' <<< "${vmess_outbound_record}")
managed_component_state_validate_record "${vmess_grpc_transport}"
vmess_quic_transport=$(jq -c '.config.transport = {type:"quic"} | .config.tls = {enabled:true,server_name:"vmess.example",insecure:true}' <<< "${vmess_outbound_record}")
managed_component_state_validate_record "${vmess_quic_transport}"
vmess_httpupgrade_transport=$(jq -c '.config.transport = {type:"httpupgrade",host:"vmess.example",path:"/vmess",headers:{Host:"vmess.example"}}' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_httpupgrade_transport}"; then
  printf 'VMess HTTPUpgrade transport unexpectedly accepted\n' >&2
  exit 1
fi
vmess_ws_early_data=$(jq -c '.config.transport = {type:"ws",path:"/vmess",max_early_data:1,early_data_header_name:"X-Early-Data"}' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_ws_early_data}"; then
  printf 'VMess WebSocket early data unexpectedly accepted\n' >&2
  exit 1
fi
vmess_quic_without_tls=$(jq -c '.config |= (del(.tls) | .transport = {type:"quic"})' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_quic_without_tls}"; then
  printf 'VMess plaintext QUIC unexpectedly accepted\n' >&2
  exit 1
fi
vmess_missing_uuid=$(jq -c '.config |= del(.uuid)' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_missing_uuid}"; then
  printf 'VMess outbound without UUID unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_security=$(jq -c '.config.security = "aes-256-gcm"' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_security}"; then
  printf 'VMess unsupported security unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_packet_encoding=$(jq -c '.config.packet_encoding = "quic"' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_packet_encoding}"; then
  printf 'VMess unsupported packet encoding unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_alter_id=$(jq -c '.config.alter_id = 65536' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_alter_id}"; then
  printf 'VMess out-of-range alter_id unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_transport_type=$(jq -c '.config.transport.type = "h2"' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_transport_type}"; then
  printf 'VMess unsupported transport unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_transport_field=$(jq -c '.config.transport |= (. + {unknown:true})' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_transport_field}"; then
  printf 'VMess unknown transport field unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_transport_header=$(jq -c '.config.transport.headers["Bad Header"] = "value"' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_transport_header}"; then
  printf 'VMess invalid transport header unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_multiplex=$(jq -c '.config.multiplex.protocol = "mux"' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_multiplex}"; then
  printf 'VMess unsupported multiplex protocol unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_tls=$(jq -c '.config.tls |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_tls}"; then
  printf 'VMess unknown TLS field unexpectedly accepted\n' >&2
  exit 1
fi
vmess_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_unknown_field}"; then
  printf 'VMess deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
vmess_bad_uuid=$(jq -c '.config.uuid = "vmess\u0001uuid"' <<< "${vmess_outbound_record}")
if managed_component_state_validate_record "${vmess_bad_uuid}"; then
  printf 'VMess control-character UUID unexpectedly accepted\n' >&2
  exit 1
fi

trojan_outbound_record='{"id":"trojan-outbound-local","role":"outbound","type":"trojan","tag":"trojan-upstream","enabled":true,"route_rules":[],"config":{"server":"127.0.0.1","server_port":443,"password":"trojan-password","network":["tcp","udp"],"tls":{"enabled":true,"server_name":"trojan.example","insecure":true},"transport":{"type":"grpc","service_name":"trojan","permit_without_stream":false},"multiplex":{"enabled":false,"protocol":"smux"},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/trojan-protect"}}'
managed_component_state_validate_record "${trojan_outbound_record}"
trojan_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${trojan_outbound_record}")
trojan_outbound_rendered=$(managed_component_render_json "${trojan_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "trojan" and
  .outbounds[0].tag == "trojan-upstream" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].password == "trojan-password" and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].transport.type == "grpc" and
  .outbounds[0].transport.service_name == "trojan" and
  .outbounds[0].multiplex.protocol == "smux" and
  .outbounds[0].tls.server_name == "trojan.example" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/trojan-protect" and
  .outbounds[0].route_rules == null
' <<< "${trojan_outbound_rendered}" >/dev/null
trojan_plain_record=$(jq -c '.config |= del(.tls,.transport,.multiplex)' <<< "${trojan_outbound_record}")
managed_component_state_validate_record "${trojan_plain_record}"
trojan_missing_password=$(jq -c '.config |= del(.password)' <<< "${trojan_outbound_record}")
if managed_component_state_validate_record "${trojan_missing_password}"; then
  printf 'Trojan outbound without password unexpectedly accepted\n' >&2
  exit 1
fi
trojan_bad_network=$(jq -c '.config.network = ["icmp"]' <<< "${trojan_outbound_record}")
if managed_component_state_validate_record "${trojan_bad_network}"; then
  printf 'Trojan unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
trojan_bad_transport=$(jq -c '.config.transport |= (. + {force_lite:true})' <<< "${trojan_outbound_record}")
if managed_component_state_validate_record "${trojan_bad_transport}"; then
  printf 'Trojan unsupported transport field unexpectedly accepted\n' >&2
  exit 1
fi
trojan_bad_tls=$(jq -c '.config.tls.server_name = "trojan\u0001.example"' <<< "${trojan_outbound_record}")
if managed_component_state_validate_record "${trojan_bad_tls}"; then
  printf 'Trojan control-character TLS name unexpectedly accepted\n' >&2
  exit 1
fi
trojan_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${trojan_outbound_record}")
if managed_component_state_validate_record "${trojan_unknown_field}"; then
  printf 'Trojan deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi

# VLESS outbound records use the same V2Ray transport/TLS/multiplex contract,
# with VLESS-specific flow and packet-encoding semantics.  Vision is only a
# direct TLS flow; native transports remain available for the empty flow.
vless_outbound_record='{"id":"vless-outbound-local","role":"outbound","type":"vless","tag":"vless-upstream","enabled":true,"route_rules":[],"config":{"server":"127.0.0.1","server_port":443,"uuid":"bf000d23-0752-40b4-affe-68f7707a9661","flow":"","network":["tcp","udp"],"tls":{"enabled":true,"server_name":"vless.example","insecure":true},"packet_encoding":"xudp","transport":{"type":"ws","path":"/vless","headers":{"Host":"vless.example"}},"multiplex":{"enabled":false,"protocol":"h2mux"},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/vless-protect"}}'
managed_component_state_validate_record "${vless_outbound_record}"
vless_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${vless_outbound_record}")
vless_outbound_rendered=$(managed_component_render_json "${vless_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "vless" and
  .outbounds[0].tag == "vless-upstream" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].uuid == "bf000d23-0752-40b4-affe-68f7707a9661" and
  .outbounds[0].packet_encoding == "xudp" and
  .outbounds[0].transport.type == "ws" and
  .outbounds[0].transport.headers.Host == "vless.example" and
  .outbounds[0].multiplex.protocol == "h2mux" and
  .outbounds[0].tls.server_name == "vless.example" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/vless-protect" and
  .outbounds[0].route_rules == null
' <<< "${vless_outbound_rendered}" >/dev/null
vless_plain_record=$(jq -c '.config |= del(.tls,.transport,.multiplex)' <<< "${vless_outbound_record}")
managed_component_state_validate_record "${vless_plain_record}"
vless_flow_record=$(jq -c '.config.flow = "xtls-rprx-vision" | .config |= (del(.transport) + {tls:{enabled:true,server_name:"vless.example",insecure:true}})' <<< "${vless_outbound_record}")
managed_component_state_validate_record "${vless_flow_record}"
vless_http_transport=$(jq -c '.config.transport = {type:"http",host:["vless.example"],path:"/vless",method:"POST",headers:{"X-Proxy":"vless"},idle_timeout:"30s",ping_timeout:"10s"}' <<< "${vless_outbound_record}")
managed_component_state_validate_record "${vless_http_transport}"
vless_grpc_transport=$(jq -c '.config.transport = {type:"grpc",service_name:"vless",idle_timeout:"30s",ping_timeout:"10s",permit_without_stream:false}' <<< "${vless_outbound_record}")
managed_component_state_validate_record "${vless_grpc_transport}"
vless_quic_transport=$(jq -c '.config.transport = {type:"quic"} | .config.tls = {enabled:true,server_name:"vless.example",insecure:true}' <<< "${vless_outbound_record}")
managed_component_state_validate_record "${vless_quic_transport}"
vless_packet_encoding_omitted=$(jq -c '.config |= del(.packet_encoding)' <<< "${vless_outbound_record}")
managed_component_state_validate_record "${vless_packet_encoding_omitted}"
vless_httpupgrade_transport=$(jq -c '.config.transport = {type:"httpupgrade",host:"vless.example",path:"/vless",headers:{Host:"vless.example"}}' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_httpupgrade_transport}"; then
  printf 'VLESS HTTPUpgrade transport unexpectedly accepted\n' >&2
  exit 1
fi
vless_ws_early_data=$(jq -c '.config.transport = {type:"ws",path:"/vless",max_early_data:1,early_data_header_name:"X-Early-Data"}' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_ws_early_data}"; then
  printf 'VLESS WebSocket early data unexpectedly accepted\n' >&2
  exit 1
fi
vless_grpc_permit=$(jq -c '.config.transport = {type:"grpc",service_name:"vless",permit_without_stream:true}' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_grpc_permit}"; then
  printf 'VLESS lite-gRPC permit_without_stream unexpectedly accepted\n' >&2
  exit 1
fi
vless_quic_without_tls=$(jq -c '.config |= (del(.tls) | .transport = {type:"quic"})' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_quic_without_tls}"; then
  printf 'VLESS plaintext QUIC unexpectedly accepted\n' >&2
  exit 1
fi
vless_flow_without_tls=$(jq -c '.config.flow = "xtls-rprx-vision" | .config |= del(.tls,.transport)' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_flow_without_tls}"; then
  printf 'VLESS Vision flow without TLS unexpectedly accepted\n' >&2
  exit 1
fi
vless_flow_with_transport=$(jq -c '.config.flow = "xtls-rprx-vision"' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_flow_with_transport}"; then
  printf 'VLESS Vision flow with transport unexpectedly accepted\n' >&2
  exit 1
fi
vless_missing_uuid=$(jq -c '.config |= del(.uuid)' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_missing_uuid}"; then
  printf 'VLESS outbound without UUID unexpectedly accepted\n' >&2
  exit 1
fi
vless_bad_flow=$(jq -c '.config.flow = "xtls-rprx-vision-plus"' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_bad_flow}"; then
  printf 'VLESS unsupported flow unexpectedly accepted\n' >&2
  exit 1
fi
vless_bad_packet_encoding=$(jq -c '.config.packet_encoding = "quic"' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_bad_packet_encoding}"; then
  printf 'VLESS unsupported packet encoding unexpectedly accepted\n' >&2
  exit 1
fi
vless_bad_transport=$(jq -c '.config.transport.type = "h2"' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_bad_transport}"; then
  printf 'VLESS unsupported transport unexpectedly accepted\n' >&2
  exit 1
fi
vless_none_transport=$(jq -c '.config.transport = {type:"none"}' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_none_transport}"; then
  printf 'VLESS none transport unexpectedly accepted\n' >&2
  exit 1
fi
vless_bad_multiplex=$(jq -c '.config.multiplex.protocol = "mux"' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_bad_multiplex}"; then
  printf 'VLESS unsupported multiplex protocol unexpectedly accepted\n' >&2
  exit 1
fi
vless_bad_tls=$(jq -c '.config.tls |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_bad_tls}"; then
  printf 'VLESS unknown TLS field unexpectedly accepted\n' >&2
  exit 1
fi
vless_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_unknown_field}"; then
  printf 'VLESS deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
vless_bad_uuid=$(jq -c '.config.uuid = "vless\u0001uuid"' <<< "${vless_outbound_record}")
if managed_component_state_validate_record "${vless_bad_uuid}"; then
  printf 'VLESS control-character UUID unexpectedly accepted\n' >&2
  exit 1
fi

# AnyTLS outbound records have a protocol-specific typed contract rather than
# generic JSON passthrough.  TLS is mandatory; session tuning and client
# metadata are optional; AnyTLS has no configurable network/transport/multiplex
# object; and the target adapter rejects TCP fast open when enabled.
anytls_outbound_record='{"id":"anytls-outbound-local","role":"outbound","type":"anytls","tag":"anytls-upstream","enabled":true,"route_rules":[],"config":{"server":"anytls.example","server_port":443,"password":"anytls-password","idle_session_check_interval":"30s","idle_session_timeout":"30s","min_idle_session":2,"client_metadata":"","tls":{"enabled":true,"server_name":"anytls.example","insecure":true},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/anytls-protect"}}'
managed_component_state_validate_record "${anytls_outbound_record}"
anytls_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${anytls_outbound_record}")
anytls_outbound_rendered=$(managed_component_render_json "${anytls_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "anytls" and
  .outbounds[0].tag == "anytls-upstream" and
  .outbounds[0].server == "anytls.example" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].password == "anytls-password" and
  .outbounds[0].idle_session_check_interval == "30s" and
  .outbounds[0].idle_session_timeout == "30s" and
  .outbounds[0].min_idle_session == 2 and
  .outbounds[0].client_metadata == "" and
  .outbounds[0].tls.server_name == "anytls.example" and
  .outbounds[0].protect_path == "/usr/lib/sing-box/anytls-protect" and
  .outbounds[0].route_rules == null
' <<< "${anytls_outbound_rendered}" >/dev/null
anytls_minimal_record=$(jq -c '.config |= (del(.idle_session_check_interval,.idle_session_timeout,.min_idle_session,.client_metadata,.connect_timeout,.network_strategy,.network_type,.domain_resolver,.protect_path) + {tcp_fast_open:false})' <<< "${anytls_outbound_record}")
managed_component_state_validate_record "${anytls_minimal_record}"
anytls_missing_password=$(jq -c '.config |= del(.password)' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_missing_password}"; then
  printf 'AnyTLS outbound without password unexpectedly accepted\n' >&2
  exit 1
fi
anytls_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_missing_tls}"; then
  printf 'AnyTLS outbound without TLS unexpectedly accepted\n' >&2
  exit 1
fi
anytls_disabled_tls=$(jq -c '.config.tls.enabled = false' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_disabled_tls}"; then
  printf 'AnyTLS outbound with disabled TLS unexpectedly accepted\n' >&2
  exit 1
fi
anytls_fast_open=$(jq -c '.config.tcp_fast_open = true' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_fast_open}"; then
  printf 'AnyTLS TCP fast open unexpectedly accepted\n' >&2
  exit 1
fi
anytls_network=$(jq -c '.config.network = "tcp"' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_network}"; then
  printf 'AnyTLS configurable network unexpectedly accepted\n' >&2
  exit 1
fi
anytls_transport=$(jq -c '.config.transport = {type:"ws",path:"/anytls"}' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_transport}"; then
  printf 'AnyTLS transport unexpectedly accepted\n' >&2
  exit 1
fi
anytls_multiplex=$(jq -c '.config.multiplex = {enabled:false}' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_multiplex}"; then
  printf 'AnyTLS multiplex unexpectedly accepted\n' >&2
  exit 1
fi
anytls_bad_metadata=$(jq -c '.config.client_metadata = {value:"metadata"}' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_bad_metadata}"; then
  printf 'AnyTLS non-string client metadata unexpectedly accepted\n' >&2
  exit 1
fi
anytls_bad_min_idle=$(jq -c '.config.min_idle_session = -1' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_bad_min_idle}"; then
  printf 'AnyTLS negative min_idle_session unexpectedly accepted\n' >&2
  exit 1
fi
anytls_bad_port=$(jq -c '.config.server_port = 65536' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_bad_port}"; then
  printf 'AnyTLS out-of-range server port unexpectedly accepted\n' >&2
  exit 1
fi
anytls_bad_tls=$(jq -c '.config.tls |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_bad_tls}"; then
  printf 'AnyTLS unknown TLS field unexpectedly accepted\n' >&2
  exit 1
fi
anytls_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_unknown_field}"; then
  printf 'AnyTLS deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
anytls_bad_password=$(jq -c '.config.password = "anytls\u0001password"' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_bad_password}"; then
  printf 'AnyTLS control-character password unexpectedly accepted\n' >&2
  exit 1
fi
anytls_bad_duration=$(jq -c '.config.idle_session_timeout = 30' <<< "${anytls_outbound_record}")
if managed_component_state_validate_record "${anytls_bad_duration}"; then
  printf 'AnyTLS non-string duration unexpectedly accepted\n' >&2
  exit 1
fi

# Snell outbound records are a versioned discriminated union.  sing-box 1.14
# exposes v4 (HTTP obfuscation) and v6 (traffic shaping); the v5 wire protocol
# is intentionally not a separate outbound version.  Shared Dial Fields and
# TCP/UDP network selection remain typed, and version-crossed fields fail
# closed instead of becoming arbitrary JSON.
snell4_outbound_record='{"id":"snell4-outbound-local","role":"outbound","type":"snell","tag":"snell4-upstream","enabled":true,"route_rules":[],"config":{"server":"snell.example","server_port":443,"version":4,"psk":"snell-password","userkey":"snell-user-key","reuse":true,"network":["tcp","udp"],"obfs_mode":"http","obfs_host":"snell.example","connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"protect_path":"/usr/lib/sing-box/snell-protect"}}'
managed_component_state_validate_record "${snell4_outbound_record}"
snell4_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${snell4_outbound_record}")
snell4_outbound_rendered=$(managed_component_render_json "${snell4_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "snell" and
  .outbounds[0].tag == "snell4-upstream" and
  .outbounds[0].server == "snell.example" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].version == 4 and
  .outbounds[0].psk == "snell-password" and
  .outbounds[0].userkey == "snell-user-key" and
  .outbounds[0].reuse == true and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].obfs_mode == "http" and
  .outbounds[0].obfs_host == "snell.example" and
  .outbounds[0].route_rules == null
' <<< "${snell4_outbound_rendered}" >/dev/null
snell6_outbound_record='{"id":"snell6-outbound-local","role":"outbound","type":"snell","tag":"snell6-upstream","enabled":true,"route_rules":[],"config":{"server":"snell.example","server_port":8443,"version":6,"psk":"snell-password-12","userkey":"","reuse":false,"network":"tcp","mode":"unshaped","connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"protect_path":"/usr/lib/sing-box/snell6-protect"}}'
managed_component_state_validate_record "${snell6_outbound_record}"
snell6_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${snell6_outbound_record}")
snell6_outbound_rendered=$(managed_component_render_json "${snell6_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "snell" and
  .outbounds[0].tag == "snell6-upstream" and
  .outbounds[0].version == 6 and
  .outbounds[0].psk == "snell-password-12" and
  .outbounds[0].network == "tcp" and
  .outbounds[0].mode == "unshaped" and
  (.outbounds[0] | has("obfs_mode") | not) and
  .outbounds[0].protect_path == "/usr/lib/sing-box/snell6-protect"
' <<< "${snell6_outbound_rendered}" >/dev/null
snell4_empty_obfs=$(jq -c '.config.obfs_mode = "" | .config.obfs_host = ""' <<< "${snell4_outbound_record}")
managed_component_state_validate_record "${snell4_empty_obfs}"
snell6_default_mode=$(jq -c '.config.mode = "default"' <<< "${snell6_outbound_record}")
managed_component_state_validate_record "${snell6_default_mode}"
snell_missing_version=$(jq -c '.config |= del(.version)' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_missing_version}"; then
  printf 'Snell outbound without version unexpectedly accepted\n' >&2
  exit 1
fi
snell_unsupported_version=$(jq -c '.config.version = 5' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_unsupported_version}"; then
  printf 'Snell outbound v5 unexpectedly accepted\n' >&2
  exit 1
fi
snell_missing_psk=$(jq -c '.config |= del(.psk)' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_missing_psk}"; then
  printf 'Snell outbound without PSK unexpectedly accepted\n' >&2
  exit 1
fi
snell_short_v6_psk=$(jq -c '.config.psk = "short"' <<< "${snell6_outbound_record}")
if managed_component_state_validate_record "${snell_short_v6_psk}"; then
  printf 'Snell v6 short PSK unexpectedly accepted\n' >&2
  exit 1
fi
snell_v6_obfs=$(jq -c '.config.obfs_mode = "none"' <<< "${snell6_outbound_record}")
if managed_component_state_validate_record "${snell_v6_obfs}"; then
  printf 'Snell v6 obfs field unexpectedly accepted\n' >&2
  exit 1
fi
snell_v6_obfs_host=$(jq -c '.config.obfs_host = "snell.example"' <<< "${snell6_outbound_record}")
if managed_component_state_validate_record "${snell_v6_obfs_host}"; then
  printf 'Snell v6 obfs host unexpectedly accepted\n' >&2
  exit 1
fi
snell_v4_mode=$(jq -c '.config.mode = "default"' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_v4_mode}"; then
  printf 'Snell v4 shaping field unexpectedly accepted\n' >&2
  exit 1
fi
snell_bad_obfs=$(jq -c '.config.obfs_mode = "tls"' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_bad_obfs}"; then
  printf 'Snell unsupported obfs mode unexpectedly accepted\n' >&2
  exit 1
fi
snell_bad_host=$(jq -c '.config.obfs_host = "snell\u0001.example"' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_bad_host}"; then
  printf 'Snell HTTP obfs control-character host unexpectedly accepted\n' >&2
  exit 1
fi
snell_bad_mode=$(jq -c '.config.mode = "shaped"' <<< "${snell6_outbound_record}")
if managed_component_state_validate_record "${snell_bad_mode}"; then
  printf 'Snell unsupported shaping mode unexpectedly accepted\n' >&2
  exit 1
fi
snell_bad_network=$(jq -c '.config.network = ["icmp"]' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_bad_network}"; then
  printf 'Snell unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
snell_duplicate_network=$(jq -c '.config.network = ["tcp","tcp"]' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_duplicate_network}"; then
  printf 'Snell duplicate network unexpectedly accepted\n' >&2
  exit 1
fi
snell_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_unknown_field}"; then
  printf 'Snell deprecated/unknown Dial Field unexpectedly accepted\n' >&2
  exit 1
fi
snell_bad_psk=$(jq -c '.config.psk = "snell\u0001password"' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_bad_psk}"; then
  printf 'Snell control-character PSK unexpectedly accepted\n' >&2
  exit 1
fi
snell_bad_port=$(jq -c '.config.server_port = 65536' <<< "${snell4_outbound_record}")
if managed_component_state_validate_record "${snell_bad_port}"; then
  printf 'Snell out-of-range server port unexpectedly accepted\n' >&2
  exit 1
fi

# Hysteria2 outbound records preserve the QUIC client contract instead of
# falling through to the generic protocol branch.  Port hopping, gecko obfs,
# QUIC fields, outbound TLS, optional Realm rendezvous and shared Dial Fields
# are all typed before state/CAS publication.
hysteria2_outbound_record='{"id":"hysteria2-outbound-local","role":"outbound","type":"hysteria2","tag":"hysteria2-upstream","enabled":true,"route_rules":[],"config":{"server":"hy2.example","server_port":443,"hop_interval":"30s","hop_interval_max":"60s","up_mbps":100,"down_mbps":200,"obfs":{"type":"gecko","password":"gecko-password","min_packet_size":512,"max_packet_size":1200},"password":"hy2-password","network":["tcp","udp"],"tls":{"enabled":true,"server_name":"hy2.example","insecure":true},"idle_timeout":"30s","keep_alive_period":"10s","stream_receive_window":"64 MB","connection_receive_window":"128 MB","max_concurrent_streams":100,"initial_packet_size":1200,"disable_path_mtu_discovery":false,"bbr_profile":"standard","brutal_debug":false,"disable_chrome_parrot":true,"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/hysteria2-protect"}}'
managed_component_state_validate_record "${hysteria2_outbound_record}"
hysteria2_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${hysteria2_outbound_record}")
hysteria2_outbound_rendered=$(managed_component_render_json "${hysteria2_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "hysteria2" and
  .outbounds[0].tag == "hysteria2-upstream" and
  .outbounds[0].server == "hy2.example" and
  .outbounds[0].server_port == 443 and
  (.outbounds[0] | has("server_ports") | not) and
  .outbounds[0].obfs.type == "gecko" and
  .outbounds[0].obfs.password == "gecko-password" and
  .outbounds[0].obfs.min_packet_size == 512 and
  .outbounds[0].obfs.max_packet_size == 1200 and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].bbr_profile == "standard" and
  .outbounds[0].disable_chrome_parrot == true and
  .outbounds[0].route_rules == null
' <<< "${hysteria2_outbound_rendered}" >/dev/null
hysteria2_realm_record=$(jq -c '
  .config |= (del(.server,.server_port,.server_ports,.obfs) + {
    realm:{server_url:"https://realm.example",token:"realm-token",realm_id:"slot-1",
      stun_servers:["stun.example.com","stun2.example.com"],ip_version:4,
      port_mapping:{enabled:true,timeout:"10s",lifetime:"10m"},
      http_client:{engine:"go",version:2,headers:{"User-Agent":"sbv"},
        tls:{enabled:true,server_name:"realm.example",insecure:true},connect_timeout:"5s"}}
  })
' <<< "${hysteria2_outbound_record}")
managed_component_state_validate_record "${hysteria2_realm_record}"
hysteria2_realm_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${hysteria2_realm_record}")
hysteria2_realm_rendered=$(managed_component_render_json "${hysteria2_realm_state}")
jq -e '
  .outbounds[0].type == "hysteria2" and
  (.outbounds[0] | has("server") | not) and
  .outbounds[0].realm.server_url == "https://realm.example" and
  .outbounds[0].realm.realm_id == "slot-1" and
  .outbounds[0].realm.stun_servers == ["stun.example.com","stun2.example.com"] and
  .outbounds[0].realm.port_mapping.enabled == true and
  .outbounds[0].realm.http_client.tls.server_name == "realm.example"
' <<< "${hysteria2_realm_rendered}" >/dev/null
hysteria2_salamander=$(jq -c '.config.obfs = {type:"salamander",password:"salamander-password"}' <<< "${hysteria2_outbound_record}")
managed_component_state_validate_record "${hysteria2_salamander}"
hysteria2_ports_only=$(jq -c '.config |= (del(.server_port) + {server_ports:["2080:3000"]})' <<< "${hysteria2_outbound_record}")
managed_component_state_validate_record "${hysteria2_ports_only}"
hysteria2_ports_only_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${hysteria2_ports_only}")
hysteria2_ports_only_rendered=$(managed_component_render_json "${hysteria2_ports_only_state}")
jq -e '
  .outbounds[0].server == "hy2.example" and
  (.outbounds[0] | has("server_port") | not) and
  .outbounds[0].server_ports == ["2080:3000"]
' <<< "${hysteria2_ports_only_rendered}" >/dev/null
hysteria2_port_conflict=$(jq -c '.config.server_ports = ["2080:3000"]' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_port_conflict}"; then
  printf 'Hysteria2 server_port/server_ports conflict unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_missing_tls}"; then
  printf 'Hysteria2 outbound without TLS unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_disabled_tls=$(jq -c '.config.tls.enabled = false' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_disabled_tls}"; then
  printf 'Hysteria2 outbound with disabled TLS unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_missing_server=$(jq -c '.config |= del(.server,.server_port,.server_ports)' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_missing_server}"; then
  printf 'Hysteria2 outbound without server unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_missing_port=$(jq -c '.config |= del(.server_port,.server_ports)' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_missing_port}"; then
  printf 'Hysteria2 outbound without server port unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_network=$(jq -c '.config.network = ["icmp"]' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_network}"; then
  printf 'Hysteria2 unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_duplicate_network=$(jq -c '.config.network = ["udp","udp"]' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_duplicate_network}"; then
  printf 'Hysteria2 duplicate network unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_obfs=$(jq -c '.config.obfs.type = "xor"' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_obfs}"; then
  printf 'Hysteria2 unsupported obfs type unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_missing_obfs_password=$(jq -c '.config.obfs |= del(.password)' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_missing_obfs_password}"; then
  printf 'Hysteria2 obfs without password unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_salamander_gecko_field=$(jq -c '.config.obfs = {type:"salamander",password:"salamander-password",min_packet_size:512}' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_salamander_gecko_field}"; then
  printf 'Hysteria2 salamander gecko field unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_reversed_gecko=$(jq -c '.config.obfs.min_packet_size = 1200 | .config.obfs.max_packet_size = 512' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_reversed_gecko}"; then
  printf 'Hysteria2 reversed gecko packet range unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_ports=$(jq -c '.config.server_ports = ["3000:2000"]' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_ports}"; then
  printf 'Hysteria2 reversed port range unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_bandwidth=$(jq -c '.config.up_mbps = -1' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_bandwidth}"; then
  printf 'Hysteria2 negative bandwidth unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_bbr=$(jq -c '.config.bbr_profile = "fast"' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_bbr}"; then
  printf 'Hysteria2 unsupported BBR profile unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_quic=$(jq -c '.config.initial_packet_size = "1200"' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_quic}"; then
  printf 'Hysteria2 invalid QUIC scalar unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_unknown_field=$(jq -c '.config |= (. + {recv_window:1})' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_unknown_field}"; then
  printf 'Hysteria2 deprecated field unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_bad_password=$(jq -c '.config.password = "hy2\u0001password"' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_bad_password}"; then
  printf 'Hysteria2 control-character password unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_realm_conflict=$(jq -c '.config.realm = {server_url:"https://realm.example",realm_id:"slot-1",stun_servers:["stun.example.com"]}' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_realm_conflict}"; then
  printf 'Hysteria2 realm/server conflict unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_realm_missing_stun=$(jq -c '.config |= (del(.server,.server_port,.server_ports) + {realm:{server_url:"https://realm.example",realm_id:"slot-1"}})' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_realm_missing_stun}"; then
  printf 'Hysteria2 realm without STUN servers unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_realm_ipv6_mapping=$(jq -c '.config |= (del(.server,.server_port,.server_ports) + {realm:{server_url:"https://realm.example",realm_id:"slot-1",stun_servers:["stun.example.com"],ip_version:6,port_mapping:{enabled:true}}})' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_realm_ipv6_mapping}"; then
  printf 'Hysteria2 IPv6 realm port mapping unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_realm_bad_http_client=$(jq -c '.config |= (del(.server,.server_port,.server_ports) + {realm:{server_url:"https://realm.example",realm_id:"slot-1",stun_servers:["stun.example.com"],http_client:{unknown:true}}})' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_realm_bad_http_client}"; then
  printf 'Hysteria2 realm unknown HTTP client field unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_realm_http1_variant=$(jq -c '.config |= (del(.server,.server_port,.server_ports) + {realm:{server_url:"https://realm.example",realm_id:"slot-1",stun_servers:["stun.example.com"],http_client:{version:1,idle_timeout:"5s"}}})' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_realm_http1_variant}"; then
  printf 'Hysteria2 realm HTTP/1 client with HTTP/2 field unexpectedly accepted\n' >&2
  exit 1
fi
hysteria2_realm_http2_quic_field=$(jq -c '.config |= (del(.server,.server_port,.server_ports) + {realm:{server_url:"https://realm.example",realm_id:"slot-1",stun_servers:["stun.example.com"],http_client:{version:2,initial_packet_size:1200}}})' <<< "${hysteria2_outbound_record}")
if managed_component_state_validate_record "${hysteria2_realm_http2_quic_field}"; then
  printf 'Hysteria2 realm HTTP/2 client with QUIC field unexpectedly accepted\n' >&2
  exit 1
fi

# Hysteria v1 outbound records keep the legacy auth/auth_str and bandwidth
# compatibility fields distinct from Hysteria2, while sharing typed TLS, QUIC,
# network and Dial Field handling.
hysteria_outbound_record='{"id":"hysteria-outbound-local","role":"outbound","type":"hysteria","tag":"hysteria-upstream","enabled":true,"route_rules":[],"config":{"server":"hy1.example","server_port":443,"hop_interval":"30s","up_mbps":100,"down_mbps":200,"obfs":"obfs-password","auth_str":"hy1-password","network":["tcp","udp"],"tls":{"enabled":true,"server_name":"hy1.example","insecure":true},"idle_timeout":"30s","keep_alive_period":"10s","stream_receive_window":"64 MB","connection_receive_window":"128 MB","max_concurrent_streams":100,"initial_packet_size":1200,"disable_path_mtu_discovery":false,"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/hysteria-protect"}}'
managed_component_state_validate_record "${hysteria_outbound_record}"
hysteria_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${hysteria_outbound_record}")
hysteria_outbound_rendered=$(managed_component_render_json "${hysteria_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "hysteria" and
  .outbounds[0].tag == "hysteria-upstream" and
  .outbounds[0].server == "hy1.example" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].up_mbps == 100 and
  .outbounds[0].down_mbps == 200 and
  .outbounds[0].obfs == "obfs-password" and
  .outbounds[0].auth_str == "hy1-password" and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].initial_packet_size == 1200 and
  .outbounds[0].route_rules == null
' <<< "${hysteria_outbound_rendered}" >/dev/null
hysteria_network_bytes=$(jq -c '.config |= (del(.up_mbps,.down_mbps) + {up:"100 Mbps",down:"200 Mbps"})' <<< "${hysteria_outbound_record}")
managed_component_state_validate_record "${hysteria_network_bytes}"
hysteria_auth_bytes=$(jq -c '.config |= (del(.auth_str) + {auth:"cHc="})' <<< "${hysteria_outbound_record}")
managed_component_state_validate_record "${hysteria_auth_bytes}"
hysteria_auth_array=$(jq -c '.config |= (del(.auth_str) + {auth:[112,119]})' <<< "${hysteria_outbound_record}")
managed_component_state_validate_record "${hysteria_auth_array}"
hysteria_ports_only=$(jq -c '.config |= (del(.server_port) + {server_ports:["2080:3000"]})' <<< "${hysteria_outbound_record}")
managed_component_state_validate_record "${hysteria_ports_only}"
hysteria_ports_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${hysteria_ports_only}")
hysteria_ports_rendered=$(managed_component_render_json "${hysteria_ports_state}")
jq -e '
  .outbounds[0].server == "hy1.example" and
  (.outbounds[0] | has("server_port") | not) and
  .outbounds[0].server_ports == ["2080:3000"]
' <<< "${hysteria_ports_rendered}" >/dev/null
hysteria_port_conflict=$(jq -c '.config.server_ports = ["2080:3000"]' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_port_conflict}"; then
  printf 'Hysteria server_port/server_ports conflict unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_missing_speed=$(jq -c '.config |= del(.up,.down,.up_mbps,.down_mbps)' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_missing_speed}"; then
  printf 'Hysteria outbound without bandwidth unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_negative_bandwidth=$(jq -c '.config.up_mbps = -1' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_negative_bandwidth}"; then
  printf 'Hysteria negative bandwidth unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_bad_network_bytes=$(jq -c '.config.up = 1.5' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_bad_network_bytes}"; then
  printf 'Hysteria fractional network bytes unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_bad_auth=$(jq -c '.config.auth = "not-base64"' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_bad_auth}"; then
  printf 'Hysteria invalid base64 auth unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_bad_auth_array=$(jq -c '.config.auth = [256]' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_bad_auth_array}"; then
  printf 'Hysteria out-of-range auth byte unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_missing_tls}"; then
  printf 'Hysteria outbound without TLS unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_disabled_tls=$(jq -c '.config.tls.enabled = false' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_disabled_tls}"; then
  printf 'Hysteria outbound with disabled TLS unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_missing_server=$(jq -c '.config |= del(.server)' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_missing_server}"; then
  printf 'Hysteria outbound without server unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_missing_port=$(jq -c '.config |= del(.server_port,.server_ports)' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_missing_port}"; then
  printf 'Hysteria outbound without server port unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_bad_network=$(jq -c '.config.network = ["icmp"]' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_bad_network}"; then
  printf 'Hysteria unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_duplicate_network=$(jq -c '.config.network = ["udp","udp"]' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_duplicate_network}"; then
  printf 'Hysteria duplicate network unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_bad_obfs=$(jq -c '.config.obfs = {password:"wrong-shape"}' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_bad_obfs}"; then
  printf 'Hysteria object obfs unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_bad_quic=$(jq -c '.config.initial_packet_size = "1200"' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_bad_quic}"; then
  printf 'Hysteria invalid QUIC scalar unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_deprecated_field=$(jq -c '.config |= (. + {recv_window:1})' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_deprecated_field}"; then
  printf 'Hysteria deprecated receive window unexpectedly accepted\n' >&2
  exit 1
fi
hysteria_hy2_field=$(jq -c '.config |= (. + {bbr_profile:"standard"})' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_hy2_field}"; then
  printf 'Hysteria2-only field unexpectedly accepted by Hysteria v1\n' >&2
  exit 1
fi
hysteria_control_password=$(jq -c '.config.auth_str = "hy1\u0001password"' <<< "${hysteria_outbound_record}")
if managed_component_state_validate_record "${hysteria_control_password}"; then
  printf 'Hysteria control-character auth unexpectedly accepted\n' >&2
  exit 1
fi

# Selector and URLTest groups own outbound member references.  Their upstream
# schemas are deliberately narrow: duplicate members, a selector default not
# present in the member list, and URLTest's selector-only fields must fail
# before graph/CAS publication.
selector_group_record=$(jq -c '.config.interrupt_exist_connections = true' <<< "${selector_record}")
managed_component_state_validate_record "${selector_group_record}"
selector_group_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${selector_group_record}")
selector_group_rendered=$(managed_component_render_json "${selector_group_state}")
jq -e '
  .outbounds[0].type == "selector" and
  .outbounds[0].outbounds == ["direct","block"] and
  .outbounds[0].default == "direct" and
  .outbounds[0].interrupt_exist_connections == true
' <<< "${selector_group_rendered}" >/dev/null
selector_duplicate_member=$(jq -c '.config.outbounds = ["direct","direct"]' <<< "${selector_group_record}")
if managed_component_state_validate_record "${selector_duplicate_member}"; then
  printf 'selector duplicate member unexpectedly accepted\n' >&2
  exit 1
fi
selector_unknown_member=$(jq -c '.config.default = "missing"' <<< "${selector_group_record}")
if managed_component_state_validate_record "${selector_unknown_member}"; then
  printf 'selector default outside member list unexpectedly accepted\n' >&2
  exit 1
fi
selector_unknown_field=$(jq -c '.config.url = "https://example.com"' <<< "${selector_group_record}")
if managed_component_state_validate_record "${selector_unknown_field}"; then
  printf 'selector unknown URLTest field unexpectedly accepted\n' >&2
  exit 1
fi
selector_bad_interrupt=$(jq -c '.config.interrupt_exist_connections = "true"' <<< "${selector_group_record}")
if managed_component_state_validate_record "${selector_bad_interrupt}"; then
  printf 'selector non-boolean interrupt flag unexpectedly accepted\n' >&2
  exit 1
fi
urltest_record='{"id":"urltest-local","role":"outbound","type":"urltest","tag":"urltest-local","enabled":true,"route_rules":[],"config":{"outbounds":["direct","block"],"url":"https://www.gstatic.com/generate_204","interval":"1m","tolerance":50,"idle_timeout":"30m","interrupt_exist_connections":true}}'
managed_component_state_validate_record "${urltest_record}"
urltest_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${urltest_record}")
urltest_rendered=$(managed_component_render_json "${urltest_state}")
jq -e '
  .outbounds[0].type == "urltest" and
  .outbounds[0].outbounds == ["direct","block"] and
  .outbounds[0].url == "https://www.gstatic.com/generate_204" and
  .outbounds[0].interval == "1m" and .outbounds[0].tolerance == 50 and
  .outbounds[0].idle_timeout == "30m" and
  .outbounds[0].interrupt_exist_connections == true
' <<< "${urltest_rendered}" >/dev/null
urltest_duplicate_member=$(jq -c '.config.outbounds = ["direct","block","block"]' <<< "${urltest_record}")
if managed_component_state_validate_record "${urltest_duplicate_member}"; then
  printf 'urltest duplicate member unexpectedly accepted\n' >&2
  exit 1
fi
urltest_bad_tolerance=$(jq -c '.config.tolerance = 65536' <<< "${urltest_record}")
if managed_component_state_validate_record "${urltest_bad_tolerance}"; then
  printf 'urltest out-of-range tolerance unexpectedly accepted\n' >&2
  exit 1
fi
urltest_selector_field=$(jq -c '.config.default = "direct"' <<< "${urltest_record}")
if managed_component_state_validate_record "${urltest_selector_field}"; then
  printf 'urltest selector-only default field unexpectedly accepted\n' >&2
  exit 1
fi
urltest_bad_url=$(jq -c '.config.url = 204' <<< "${urltest_record}")
if managed_component_state_validate_record "${urltest_bad_url}"; then
  printf 'urltest non-string URL unexpectedly accepted\n' >&2
  exit 1
fi
groups_inventory_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${selector_group_record}")
original_managed_component_state_json=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${groups_inventory_state}"
}
groups_inventory=$(managed_component_inventory_json)
eval "${original_managed_component_state_json}"
jq -e '.components[0].member_count == 2 and .components[0].config_keys == ["default","interrupt_exist_connections","outbounds"]' <<< "${groups_inventory}" >/dev/null

if managed_component_state_candidate "${state}" delete "" direct-local >/dev/null 2>&1; then
  printf 'expected deletion of referenced component to fail\n' >&2
  exit 1
fi

if managed_component_requires_public_confirmation "${direct_record}"; then
  printf 'loopback direct component unexpectedly required public confirmation\n' >&2
  exit 1
fi
public_direct=$(jq -c '.config.listen = "0.0.0.0"' <<< "${direct_record}")
managed_component_requires_public_confirmation "${public_direct}"
managed_component_requires_public_confirmation "${tun_record}"

unknown_record_field=$(jq -c '.config = {listen:"127.0.0.1",listen_port:15083} | .unexpected = true' <<< "${direct_record}")
if managed_component_state_validate_record "${unknown_record_field}"; then
  printf 'unexpected top-level component field was accepted\n' >&2
  exit 1
fi
if managed_component_state_validate_record "$(jq -c '.id = 1' <<< "${direct_record}")"; then
  printf 'numeric component id was unexpectedly accepted\n' >&2
  exit 1
fi
if managed_component_state_validate_record "$(jq -c '.tag = {value:"direct"}' <<< "${direct_record}")"; then
  printf 'non-string component tag was unexpectedly accepted\n' >&2
  exit 1
fi
unknown_config_field=$(jq -c '.config = (.config + {unexpected:true})' <<< "${direct_record}")
managed_component_state_validate_record "${unknown_config_field}"
unknown_wrapped_file=$(mktemp)
printf '%s\n' "${unknown_record_field}" > "${unknown_wrapped_file}"
if managed_component_normalize_input_file "${unknown_wrapped_file}" >/dev/null 2>&1; then
  printf 'unexpected wrapped component field was accepted\n' >&2
  exit 1
fi
rm -f "${unknown_wrapped_file}"

listener_state=$(managed_component_state_candidate "${state}" create "${tun_record}")
listener_config=$(jq -cn --argjson inbounds "$(managed_component_render_json "${listener_state}" | jq '.inbounds')" \
  '{inbounds:$inbounds,endpoints:[],outbounds:[{type:"direct",tag:"direct"},{type:"block",tag:"block"}],route:{final:"direct",rules:[]}}')
listener_config_file=$(mktemp)
printf '%s\n' "${listener_config}" > "${listener_config_file}"
validate_managed_component_graph "${listener_config_file}"
validate_managed_listener_resources "${listener_config_file}"
listener_plan=$(managed_listener_plan_json <<< "${listener_config}")
jq -e 'any(.[]; .owner == "direct-local-in" and .transport == "tcp" and .port == 15080) and length == 2' <<< "${listener_plan}" >/dev/null
rm -f "${listener_config_file}"

redirect_config=$(jq -cn --argjson inbounds "$(managed_component_render_json "$(managed_component_state_candidate "${state}" create "${redirect_record}")" | jq '.inbounds')" \
  '{inbounds:$inbounds,endpoints:[],outbounds:[{type:"direct",tag:"direct"},{type:"block",tag:"block"}],route:{final:"direct",rules:[]}}')
redirect_config_file=$(mktemp)
printf '%s\n' "${redirect_config}" > "${redirect_config_file}"
validate_managed_component_graph "${redirect_config_file}"
validate_managed_listener_resources "${redirect_config_file}"
redirect_plan=$(managed_listener_plan_json <<< "${redirect_config}")
jq -e 'any(.[]; .owner == "redirect-local-in" and .transport == "tcp") and
  all(.[]; .owner != "redirect-local-in" or .transport == "tcp")' <<< "${redirect_plan}" >/dev/null
rm -f "${redirect_config_file}"

secret_record=$(jq -c '.config.token = "secret-token-not-for-list"' <<< \
  '{"id":"cf1","role":"inbound","type":"cloudflared","tag":"cf-in","enabled":true,"route_rules":[],"config":{"token":"placeholder"}}')
managed_component_state_validate_record "${secret_record}"
managed_component_write_state "$(managed_component_state_candidate "${state}" create "${secret_record}")"
inventory=$(managed_component_inventory_json)
if grep -Fq 'secret-token-not-for-list' <<< "${inventory}"; then
  printf 'component list leaked a secret token\n' >&2
  exit 1
fi
jq -e '.revision == 3 and (.components | length == 3) and .components[0].config_keys' <<< "${inventory}" >/dev/null

ln -s "${TMP_DIR}/unexpected-components-backup" "${SB_COMPONENT_STATE_FILE}.bak"
if managed_component_write_state "${state}"; then
  printf 'symlink component backup was unexpectedly accepted\n' >&2
  exit 1
fi
rm -f "${SB_COMPONENT_STATE_FILE}.bak"

generate_config() {
  local rendered inbounds endpoints outbounds route_rules
  if [[ -e "${component_rebuild_failure:-}" ]]; then
    return 1
  fi
  rendered=$(managed_component_render_json) || return 1
  inbounds=$(jq -c '.inbounds' <<< "${rendered}") || return 1
  endpoints=$(jq -c '.endpoints' <<< "${rendered}") || return 1
  outbounds=$(jq -c '.outbounds' <<< "${rendered}") || return 1
  route_rules=$(jq -c '.route_rules' <<< "${rendered}") || return 1
  jq -n --argjson inbounds "${inbounds}" --argjson endpoints "${endpoints}" --argjson outbounds "${outbounds}" \
    --argjson route_rules "${route_rules}" \
    '{inbounds:$inbounds,endpoints:$endpoints,outbounds:([{type:"direct",tag:"direct"},{type:"block",tag:"block"}] + $outbounds),route:{final:"direct",rules:$route_rules}}' \
    > "${SINGBOX_CONFIG_FILE}"
}

generate_config

# An auto-routed TUN requires a host-route loop guard.  The generator adds the
# safe default when no route interface has been selected, preserves an explicit
# default interface, and rejects an explicitly disabled guard without one.
no_tun_route_options=$(managed_component_tun_route_options_json "${rendered}")
jq -e '. == {}' <<< "${no_tun_route_options}" >/dev/null
tun_auto_components=$(jq -cn '{inbounds:[{type:"tun",tag:"tun-auto",auto_route:true}],endpoints:[],outbounds:[],route_rules:[]}')
tun_route_options=$(managed_component_tun_route_options_json "${tun_auto_components}")
jq -e '.auto_detect_interface == true and (length == 1)' <<< "${tun_route_options}" >/dev/null
config_before_tun_route_guard=$(cat "${SINGBOX_CONFIG_FILE}")
jq '(.route |= (. + {auto_detect_interface:false} | del(.default_interface)))' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_tun_route_options_json "${tun_auto_components}" > /dev/null 2>"${TMP_DIR}/tun-route-error"; then
  printf 'explicitly disabled TUN loop guard unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'tun_auto_route_loop_guard_conflict' "${TMP_DIR}/tun-route-error"
jq '.route.auto_detect_interface = false | .route.default_interface = "eth0"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
tun_default_route_options=$(managed_component_tun_route_options_json "${tun_auto_components}")
jq -e '.auto_detect_interface == false and .default_interface == "eth0"' <<< "${tun_default_route_options}" >/dev/null
printf '%s\n' "${config_before_tun_route_guard}" > "${SINGBOX_CONFIG_FILE}"

diagnose_json=$(agent_cli component diagnose --json)
jq -e '.ok == true and .data.action == "component-diagnose" and
  .data.state.revision == 3 and .data.config.status == "present" and
  .data.config.graph == "passed" and .data.config.listener_resources == "passed" and
  .data.config.core_check == "unavailable" and (.data.components | length) == 3 and
  (.data.supported | length) == 30' <<< "${diagnose_json}" >/dev/null
if grep -Fq 'secret-token-not-for-list' <<< "${diagnose_json}"; then
  printf 'component diagnose leaked a secret token\n' >&2
  exit 1
fi

export_json=$(agent_dispatch component export --json --id cf1 --expected-revision 3)
jq -e '.ok == true and .data.action == "component-export" and
  .data.sensitive == true and .data.revision == 3 and
  .data.component.id == "cf1" and
  .data.component.config.token == "secret-token-not-for-list"' <<< "${export_json}" >/dev/null
if agent_dispatch component export --json --id cf1 --expected-revision 2 >/dev/null 2>&1; then
  printf 'stale component export unexpectedly succeeded\n' >&2
  exit 1
fi

state_before_rebuild=$(cat "${SB_COMPONENT_STATE_FILE}")
config_before_rebuild=$(cat "${SINGBOX_CONFIG_FILE}")
rebuild_json=$(agent_dispatch component rebuild --json --yes --expected-revision 3)
jq -e '.ok == true and .data.action == "component-apply" and
  .data.operation == "rebuild" and .data.revision == 3 and
  .data.id == null and .data.service_restarted == false and
  .data.firewall.status == "not_attempted"' <<< "${rebuild_json}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_rebuild}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${config_before_rebuild}" ]]

component_rebuild_failure="${TMP_DIR}/component-rebuild-failure"
touch "${component_rebuild_failure}"
if failed_rebuild_json=$(agent_dispatch component rebuild --json --yes --expected-revision 3); then
  printf 'component rebuild failure unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "config_check_failed"' <<< "${failed_rebuild_json}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_rebuild}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${config_before_rebuild}" ]]
rm -f "${component_rebuild_failure}"

component_firewall_log="${TMP_DIR}/component-firewall.log"
component_firewall_apply_failure="${TMP_DIR}/component-firewall-apply-failure"
: > "${component_firewall_log}"
instance_firewall_prepare() {
  printf 'prepare\n' >> "${component_firewall_log}"
  jq -n '{status:"prepared"}' > "${3}"
}
instance_firewall_apply() {
  printf 'apply\n' >> "${component_firewall_log}"
  if [[ -e "${component_firewall_apply_failure}" ]]; then
    return 1
  fi
  jq '.status="applied"' "${1}" > "${1}.next"
  mv -f "${1}.next" "${1}"
}
instance_firewall_rollback() {
  printf 'rollback\n' >> "${component_firewall_log}"
  return 0
}
instance_firewall_commit() {
  printf 'commit\n' >> "${component_firewall_log}"
  jq '.status="committed"' "${1}" > "${1}.next"
  mv -f "${1}.next" "${1}"
}
instance_transaction_firewall_summary() {
  local journal=${1:-} status="not_attempted"
  if [[ -f "${journal}" ]]; then
    status=$(jq -r '.status // "unavailable"' "${journal}")
  fi
  jq -cn --arg status "${status}" '{status:$status,backends:[],diagnostics:[]}'
}

created_record=$(mktemp)
printf '%s\n' "$(jq -c '.config.listen_port = 15084' <<< "${direct_record}")" > "${created_record}"
create_json=$(agent_cli component replace --json --yes --expected-revision 3 --file "${created_record}")
jq -e '.ok == true and .data.action == "component-apply" and .data.revision == 4 and
  .data.firewall.status == "committed"' <<< "${create_json}" >/dev/null
[[ "$(< "${component_firewall_log}")" == $'prepare\napply\ncommit' ]]
if agent_cli component replace --json --yes --expected-revision 3 --file "${created_record}" >/dev/null 2>&1; then
  printf 'stale component revision unexpectedly succeeded\n' >&2
  exit 1
fi

printf '%s\n' "$(jq -c '.config.listen_port = 15085' <<< "${direct_record}")" > "${created_record}"
touch "${component_firewall_apply_failure}"
if failed_json=$(agent_cli component replace --json --yes --expected-revision 4 --file "${created_record}"); then
  printf 'component firewall apply failure unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "firewall_apply_failed"' <<< "${failed_json}" >/dev/null
jq -e '.revision == 4 and any(.components[]; .id == "direct-local" and .config.listen_port == 15084)' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e '.inbounds[] | select(.tag == "direct-local-in") | .listen_port == 15084' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
[[ "$(< "${component_firewall_log}")" == $'prepare\napply\ncommit\nprepare\napply\nrollback' ]]
rm -f "${component_firewall_apply_failure}"
rm -f "${created_record}"

# Take over registered advanced objects from a live configuration without
# dropping object fields or route rules.  The operation is idempotent for
# already-owned objects and assigns a deterministic ID to a newly discovered
# endpoint.
live_without_selector_rules=$(jq -c '(.components[] | select(.id == "selector-local") | .route_rules) = []' \
  "${SB_COMPONENT_STATE_FILE}")
managed_component_write_state "${live_without_selector_rules}"
generate_config
wireguard_live=$(jq -cn '{type:"wireguard",tag:"wg-live",system:true,address:["10.0.0.2/32"],private_key:"private-key-preserved",peers:[{address:"198.51.100.1",port:51820,public_key:"peer-key",allowed_ips:["0.0.0.0/0"]}]}')
selector_live=$(jq -cn '{type:"selector",tag:"selector-live",outbounds:["direct","block"],default:"direct"}')
jq --argjson endpoint "${wireguard_live}" --argjson outbound "${selector_live}" \
  --argjson ssh_outbound "${ssh_record}" \
  --argjson tor_outbound "${tor_record}" \
  --argjson urltest_outbound "${urltest_record}" \
  '.endpoints += [$endpoint] | .outbounds += [$outbound] |
   .outbounds += [($ssh_outbound.config + {type:$ssh_outbound.type,tag:$ssh_outbound.tag})] |
   .outbounds += [($tor_outbound.config + {type:$tor_outbound.type,tag:$tor_outbound.tag})] |
   .outbounds += [($urltest_outbound.config + {type:$urltest_outbound.type,tag:$urltest_outbound.tag})] |
   .route.rules += [{domain:["selector.example"],action:"route",outbound:"selector-live"},
                    {domain:["ssh.example"],action:"route",outbound:"ssh-local"},
                    {domain:["tor.example"],action:"route",outbound:"tor-local"},
                    {domain:["urltest.example"],action:"route",outbound:"urltest-local"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if takeover_without_public=$(agent_dispatch component takeover --json --yes --expected-revision 4); then
  printf 'cloudflared takeover without public confirmation unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "confirmation_required"' <<< "${takeover_without_public}" >/dev/null
takeover_json=$(agent_dispatch component takeover --json --yes --expected-revision 4 --allow-public)
jq -e '.ok == true and .data.action == "component-apply" and
  .data.operation == "takeover" and .data.revision == 5 and
  .data.count == 8 and .data.firewall.status == "not_attempted"' <<< "${takeover_json}" >/dev/null
jq -e 'any(.components[]; .id == "endpoint-wireguard-wg-live" and
  .type == "wireguard" and .config.private_key == "private-key-preserved")' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.components[]; .id == "outbound-selector-selector-live" and
  .type == "selector" and .config.outbounds == ["direct","block"] and
  (.route_rules | any(.[]; .outbound == "selector-live")))' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.components[]; .type == "ssh" and .tag == "ssh-local" and
  .config.password == "ssh-password" and
  (.route_rules | any(.[]; .outbound == "ssh-local")))' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.components[]; .type == "tor" and .tag == "tor-local" and
  .config.executable_path == "/usr/bin/tor" and
  .config.torrc.ClientOnly == "1" and
  (.route_rules | any(.[]; .outbound == "tor-local")))' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.components[]; .type == "urltest" and .tag == "urltest-local" and
  .config.outbounds == ["direct","block"] and
  .config.interval == "1m" and
  (.route_rules | any(.[]; .outbound == "urltest-local")))' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null
jq -e 'any(.endpoints[]; .tag == "wg-live" and .private_key == "private-key-preserved")' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
jq -e 'any(.outbounds[]; .tag == "selector-live" and .outbounds == ["direct","block"]) and
  any(.outbounds[]; .tag == "ssh-local" and .server == "ssh.example" and .password == "ssh-password") and
  any(.outbounds[]; .tag == "tor-local" and .executable_path == "/usr/bin/tor" and
    .torrc.ClientOnly == "1") and
  any(.outbounds[]; .tag == "urltest-local" and .outbounds == ["direct","block"] and
    .interval == "1m") and
  any(.route.rules[]; .outbound == "selector-live" and (.domain | index("selector.example")) != null) and
  any(.route.rules[]; .outbound == "ssh-local" and (.domain | index("ssh.example")) != null) and
  any(.route.rules[]; .outbound == "tor-local" and (.domain | index("tor.example")) != null) and
  any(.route.rules[]; .outbound == "urltest-local" and (.domain | index("urltest.example")) != null)' \
  "${SINGBOX_CONFIG_FILE}" >/dev/null
export_takeover_json=$(agent_dispatch component export --json --id endpoint-wireguard-wg-live --expected-revision 5)
jq -e '.ok == true and .data.sensitive == true and
  .data.component.config.private_key == "private-key-preserved"' <<< "${export_takeover_json}" >/dev/null

# The generator-owned Warp endpoint is already emitted by the normal config
# builder and must not become a duplicate managed component during takeover.
config_before_warp_owner=$(cat "${SINGBOX_CONFIG_FILE}")
warp_owner_endpoint=$(jq -cn '{type:"wireguard",tag:"warp-ep",address:["172.16.0.2/32"],private_key:"warp-private-key",peers:[{address:"198.51.100.2",port:2408,public_key:"warp-peer-key",allowed_ips:["0.0.0.0/0"]}]}')
jq --argjson endpoint "${warp_owner_endpoint}" '.endpoints += [$endpoint]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
warp_owner_records=$(managed_component_live_takeover_records_json "$(managed_component_state_json)")
if jq -e 'any(.[]; .role == "endpoint" and .tag == "warp-ep")' <<< "${warp_owner_records}" >/dev/null; then
  printf 'generator-owned warp endpoint was unexpectedly imported\n' >&2
  exit 1
fi
printf '%s\n' "${config_before_warp_owner}" > "${SINGBOX_CONFIG_FILE}"

# Registered built-ins remain generator-owned, while unknown types and
# reserved tags are rejected before a takeover transaction can mutate state.
state_before_unknown_outbound=$(cat "${SB_COMPONENT_STATE_FILE}")
config_before_unknown_outbound=$(cat "${SINGBOX_CONFIG_FILE}")
jq '.outbounds += [{type:"future-outbound",tag:"future-live"}]' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if unknown_outbound_takeover=$(agent_dispatch component takeover --json --yes --expected-revision 5 --allow-public); then
  printf 'unknown outbound takeover unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "component_live_untrusted"' <<< "${unknown_outbound_takeover}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_unknown_outbound}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" != "${config_before_unknown_outbound}" ]]
printf '%s\n' "${config_before_unknown_outbound}" > "${SINGBOX_CONFIG_FILE}"

jq '.outbounds += [{type:"selector",tag:"direct",outbounds:["direct"]}]' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if reserved_outbound_takeover=$(agent_dispatch component takeover --json --yes --expected-revision 5 --allow-public); then
  printf 'reserved outbound tag takeover unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "component_live_untrusted"' <<< "${reserved_outbound_takeover}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_unknown_outbound}" ]]
printf '%s\n' "${config_before_unknown_outbound}" > "${SINGBOX_CONFIG_FILE}"

# Unknown top-level configuration is also outside the component model.  It
# must not be silently discarded by the normal generator during takeover.
state_before_unknown_root=$(cat "${SB_COMPONENT_STATE_FILE}")
jq '.experimental = {must_preserve:true}' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
config_with_unknown_root=$(cat "${SINGBOX_CONFIG_FILE}")
if unknown_root_takeover_json=$(agent_dispatch component takeover --json --yes --expected-revision 5 --allow-public); then
  printf 'unknown top-level component takeover unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "config_check_failed"' <<< "${unknown_root_takeover_json}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_unknown_root}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${config_with_unknown_root}" ]]
jq 'del(.experimental)' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"

# Global route rules are not implicitly assigned to a component.  A takeover
# must therefore reject the candidate rather than silently dropping one.
state_before_lossless_takeover=$(cat "${SB_COMPONENT_STATE_FILE}")
jq '.route.rules += [{domain:["must-preserve.example"],action:"route",outbound:"direct"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
config_with_unmanaged_rule=$(cat "${SINGBOX_CONFIG_FILE}")
if lossless_takeover_json=$(agent_dispatch component takeover --json --yes --expected-revision 5 --allow-public); then
  printf 'lossy component takeover unexpectedly succeeded\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "config_check_failed"' <<< "${lossless_takeover_json}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_lossless_takeover}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${config_with_unmanaged_rule}" ]]

# A process interruption after publish must leave a durable component journal
# that a later CAS-protected recover operation can safely roll back.
state_before_recovery=$(cat "${SB_COMPONENT_STATE_FILE}")
config_before_recovery=$(cat "${SINGBOX_CONFIG_FILE}")
mkdir -m 700 "${SB_COMPONENT_TRANSACTION_DIR}"
create_managed_state_snapshot "${SB_COMPONENT_TRANSACTION_DIR}/snapshot" >/dev/null
jq -n \
  --arg operation replace --arg expected 5 --arg start 0 --argjson pid 999999999 \
  '{schema_version:1,operation:$operation,expected_revision:$expected,owner_pid:$pid,
    owner_start:$start,before_active:false,phase:"publish",new_revision:6,firewall_expected:false}' \
  > "${SB_COMPONENT_TRANSACTION_DIR}/transaction.json"
chmod 600 "${SB_COMPONENT_TRANSACTION_DIR}/transaction.json"
jq '.revision = 6' "${SB_COMPONENT_STATE_FILE}" > "${SB_COMPONENT_STATE_FILE}.next"
mv -f "${SB_COMPONENT_STATE_FILE}.next" "${SB_COMPONENT_STATE_FILE}"
jq '.route.rules += [{domain:["crash-mutation.example"],action:"route",outbound:"direct"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if pending_component_write=$(agent_cli component rebuild --json --yes --expected-revision 6); then
  printf 'component write unexpectedly crossed a pending component journal\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "component_transaction_pending"' <<< "${pending_component_write}" >/dev/null
if pending_instance_recovery=$(agent_cli instance recover mixed --json --yes --expected-revision 0); then
  printf 'instance recovery unexpectedly crossed a pending component journal\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "component_transaction_pending"' <<< "${pending_instance_recovery}" >/dev/null
recovered_json=$(agent_dispatch component recover --json --yes --expected-revision 5)
jq -e '.ok == true and .data.action == "component-recover" and
  .data.operation == "replace" and .data.status == "rolled_back" and
  .data.transaction.phase == "publish" and
  .data.transaction.manual_intervention_required == false' <<< "${recovered_json}" >/dev/null
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_recovery}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" == "${config_before_recovery}" ]]
[[ ! -e "${SB_COMPONENT_TRANSACTION_DIR}" ]]

# A destructive component transition must compare the old live inventory with
# the transaction snapshot, not with the already-published candidate state.
# This exercises the delete path after a state record has been removed.
delete_state=$(jq -c '(.components[] | select(.id == "outbound-selector-selector-live") | .route_rules) = []' \
  "${SB_COMPONENT_STATE_FILE}")
managed_component_write_state "${delete_state}"
jq ' .route.rules |= map(select(.outbound != "selector-live"))' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
delete_json=$(agent_dispatch component delete --json --yes --expected-revision 5 \
  --id outbound-selector-selector-live)
jq -e '.ok == true and .data.operation == "delete" and .data.revision == 6 and
  .data.id == "outbound-selector-selector-live"' <<< "${delete_json}" >/dev/null
if jq -e 'any(.components[]; .id == "outbound-selector-selector-live")' \
  "${SB_COMPONENT_STATE_FILE}" >/dev/null; then
  printf 'deleted outbound component remained in state\n' >&2
  exit 1
fi
if jq -e 'any(.outbounds[]; .tag == "selector-live")' "${SINGBOX_CONFIG_FILE}" >/dev/null; then
  printf 'deleted outbound component remained in config\n' >&2
  exit 1
fi

printf '%s\n' 'managed component contracts passed'
