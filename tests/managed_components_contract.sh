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
