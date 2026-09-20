#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

registry=$(component_registry_json)
jq -e '
  length == 38 and
  ([.[].state_id] | unique | length) == 38 and
  ([.[] | select(.role == "inbound") | .type] | sort) ==
    ["cloudflared","direct","redirect","tproxy","tun"] and
  ([.[] | select(.role == "endpoint") | .type] | sort) ==
    ["openconnect","openvpn-client","openvpn-server","tailscale","wireguard"] and
  ([.[] | select(.role == "certificate_provider") | .type] | sort) == ["acme"] and
  ([.[] | select(.role == "network_namespace") | .type] | sort) == ["default","unshare"] and
  ([.[] | select(.role == "rule_set") | .type] | sort) == ["inline","local","remote"] and
  any(.[]; .role == "http_client" and .type == "shared" and
    .features.referenceable == true and .features.versions == [1,2,3]) and
  any(.[]; .role == "service" and .type == "resolved" and
    .features.linux == true and .features.dbus == true and
    .features.tcp == true and .features.udp == true) and
  any(.[]; .role == "outbound" and .type == "selector" and .features.group == true) and
  any(.[]; .role == "outbound" and .type == "urltest" and .features.group == true) and
  any(.[]; .role == "outbound" and .type == "naive" and
    .features.tls_required == true and .features.udp_over_tcp == true and
    .features.external_runtime == "libcronet") and
  any(.[]; .role == "outbound" and .type == "shadowtls" and
    .features.network == ["tcp"] and .features.tls_required == true and
    .features.versions == [1,2,3]) and
  any(.[]; .role == "endpoint" and .type == "wireguard" and
    .features.typed_config == true and .features.peers == true and
    .features.allowed_ips == true and .features.udp_nat == true) and
  any(.[]; .role == "endpoint" and .type == "tailscale" and
    .features.typed_config == true and .features.routes == true and
    .features.relay == true and .features.ssh_server == true) and
  any(.[]; .role == "endpoint" and .type == "openconnect" and
    .features.typed_config == true and .features.tls == true and
    .features.udp_nat == true) and
  any(.[]; .role == "endpoint" and .type == "openvpn-client" and
    .features.typed_config == true and .features.tls == true and
    .features.static_key == true and .features.routes == true) and
  any(.[]; .role == "endpoint" and .type == "openvpn-server" and
    .features.typed_config == true and .features.tls == true and
    .features.static_key == true and .features.users == true and
    .features.push == true) and
  any(.[]; .role == "rule_set" and .type == "inline" and
    .features.matcher_only == true and .features.max_tags_per_record == 1) and
  any(.[]; .role == "rule_set" and .type == "local" and
    .features.path_reference == true and .features.owns_file == false) and
  any(.[]; .role == "rule_set" and .type == "remote" and
    .features.download_detour == false and
    .features.http_client_reference_minimum_core == "1.14.0") and
  all(.[]; .lifecycle.takeover == true) and
  any(.[]; .role == "inbound" and .type == "cloudflared" and
    .features.account_mutation == false and .availability == "with_cloudflared")
' <<< "${registry}" >/dev/null

capabilities=$(agent_capabilities_json)
jq -e '
  (.features.components.diagnosis_fields | index("transparent_resources") != null) and
  (.commands.component.roles | sort) ==
    ["certificate_provider","endpoint","http_client","inbound","network_namespace","outbound","rule_set","service"]
' <<< "${capabilities}" >/dev/null

direct_record='{"id":"direct-local","role":"inbound","type":"direct","tag":"direct-local-in","enabled":true,"route_rules":[],"config":{"listen":"127.0.0.1","listen_port":15080}}'
tun_record='{"id":"tun-local","role":"inbound","type":"tun","tag":"tun-local-in","enabled":true,"route_rules":[],"config":{"interface_name":"tun-sbv","address":["172.19.0.1/30"],"auto_route":false,"strict_route":true}}'
redirect_record='{"id":"redirect-local","role":"inbound","type":"redirect","tag":"redirect-local-in","enabled":true,"route_rules":[],"config":{"listen":"127.0.0.1","listen_port":15081}}'
tproxy_record='{"id":"tproxy-local","role":"inbound","type":"tproxy","tag":"tproxy-local-in","enabled":true,"route_rules":[],"config":{"listen":"127.0.0.1","listen_port":15082}}'
selector_record='{"id":"selector-local","role":"outbound","type":"selector","tag":"selector-local","enabled":true,"route_rules":[{"inbound":["direct-local-in"],"action":"route","outbound":"selector-local"}],"config":{"outbounds":["direct","block"],"default":"direct"}}'

# Top-level certificate providers and network namespaces now use the same
# component CAS/render path.  The records are intentionally narrow: provider
# credentials are accepted only in sensitive state/export, while namespace
# paths must be absolute and unshare has no unmodeled options.
acme_provider_record='{"id":"acme-provider-local","role":"certificate_provider","type":"acme","tag":"acme-local","enabled":true,"route_rules":[],"config":{"domain":["managed.example"],"email":"ops@example.com","data_directory":"/var/lib/sing-box/acme","provider":"letsencrypt","http_client":"http-shared","dns01_challenge":{"provider":"cloudflare","api_token":"test-token"},"external_account":{"key_id":"kid","mac_key":"mkey"}}}'
managed_component_state_validate_record "${acme_provider_record}"
acme_provider_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${acme_provider_record}")
acme_provider_rendered=$(managed_component_render_json "${acme_provider_state}")
jq -e '
  (.certificate_providers | length == 1) and
  .certificate_providers[0].type == "acme" and
  .certificate_providers[0].tag == "acme-local" and
  .certificate_providers[0].domain == ["managed.example"] and
  .certificate_providers[0].dns01_challenge.provider == "cloudflare" and
  (.network_namespaces | length == 0)
' <<< "${acme_provider_rendered}" >/dev/null
acme_provider_unknown=$(jq -c '.config.unmodeled = true' <<< "${acme_provider_record}")
if managed_component_state_validate_record "${acme_provider_unknown}"; then
  printf 'ACME provider unknown field unexpectedly accepted\n' >&2
  exit 1
fi
acme_provider_bad_domain=$(jq -c '.config.domain = "managed.example"' <<< "${acme_provider_record}")
if managed_component_state_validate_record "${acme_provider_bad_domain}"; then
  printf 'ACME provider scalar domain unexpectedly accepted\n' >&2
  exit 1
fi
acme_provider_bad_port=$(jq -c '.config.alternative_http_port = 65536' <<< "${acme_provider_record}")
if managed_component_state_validate_record "${acme_provider_bad_port}"; then
  printf 'ACME provider out-of-range challenge port unexpectedly accepted\n' >&2
  exit 1
fi
acme_provider_reserved_tag=$(jq -c '.tag = "hy2-cert-provider"' <<< "${acme_provider_record}")
if managed_component_state_validate_record "${acme_provider_reserved_tag}"; then
  printf 'protocol-generated ACME provider tag unexpectedly accepted\n' >&2
  exit 1
fi

http_client_record='{"id":"http-client-local","role":"http_client","type":"shared","tag":"http-shared","enabled":true,"route_rules":[],"config":{"version":2,"headers":{"X-SBV":"managed","Accept":["application/json"]},"tls":{"enabled":true,"server_name":"managed.example","insecure":true},"detour":"direct"}}'
managed_component_state_validate_record "${http_client_record}"
http_client_state=$(managed_component_state_candidate "${acme_provider_state}" create "${http_client_record}")
http_client_rendered=$(managed_component_render_json "${http_client_state}")
jq -e '
  (.http_clients | length == 1) and
  .http_clients[0].tag == "http-shared" and
  .http_clients[0].version == 2 and
  .http_clients[0].headers["X-SBV"] == "managed" and
  .http_clients[0].tls.server_name == "managed.example" and
  (.certificate_providers[0].http_client == "http-shared")
' <<< "${http_client_rendered}" >/dev/null
http_client_unknown=$(jq -c '.config.unmodeled = true' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_unknown}"; then
  printf 'shared HTTP client unknown field unexpectedly accepted\n' >&2
  exit 1
fi
http_client_bad_variant=$(jq -c '.config.version = 1 | .config.max_concurrent_streams = 16' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_bad_variant}"; then
  printf 'HTTP/1 client HTTP/2 field unexpectedly accepted\n' >&2
  exit 1
fi
http_client_bad_keep_alive=$(jq -c '.config.version = 1 | .config.keep_alive_period = "5s"' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_bad_keep_alive}"; then
  printf 'HTTP/1 client keep-alive field unexpectedly accepted\n' >&2
  exit 1
fi
http_client_bad_engine=$(jq -c '.config.engine = "windows"' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_bad_engine}"; then
  printf 'shared HTTP client unsupported engine unexpectedly accepted\n' >&2
  exit 1
fi
http_client_bad_curve=$(jq -c '.config.tls.curve_preferences = ["not-a-curve"]' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_bad_curve}"; then
  printf 'shared HTTP client unsupported TLS curve unexpectedly accepted\n' >&2
  exit 1
fi
http_client_bad_fingerprint=$(jq -c '.config.tls.utls = {enabled:true,fingerprint:"not-a-fingerprint"}' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_bad_fingerprint}"; then
  printf 'shared HTTP client unsupported uTLS fingerprint unexpectedly accepted\n' >&2
  exit 1
fi
http_client_tls_bytes=$(jq -c '.config.tls = {enabled:true,certificate_public_key_sha256:[1,2,255]}' <<< "${http_client_record}")
managed_component_state_validate_record "${http_client_tls_bytes}"
http_client_bad_network_strategy=$(jq -c '.config.network_strategy = "as_is"' <<< "${http_client_record}")
if managed_component_state_validate_record "${http_client_bad_network_strategy}"; then
  printf 'shared HTTP client unsupported network strategy unexpectedly accepted\n' >&2
  exit 1
fi
if managed_component_state_candidate "${http_client_state}" delete "" "http-client-local"; then
  printf 'referenced shared HTTP client unexpectedly deleted\n' >&2
  exit 1
fi

# Inline, local and remote route.rule_set objects share the component CAS and
# renderer. Local paths are references only; remote URLs remain sensitive and
# use managed shared HTTP-client tags rather than deprecated download_detour.
inline_rule_set_record='{"id":"rule-set-inline","role":"rule_set","type":"inline","tag":"operator-inline-rules","enabled":true,"route_rules":[],"config":{"rules":[{"domain_suffix":["rules.example.test"]}]}}'
local_rule_set_record='{"id":"rule-set-local","role":"rule_set","type":"local","tag":"operator-local-rules","enabled":true,"route_rules":[],"config":{"format":"source","path":"/tmp/operator-rules.json"}}'
remote_rule_set_record='{"id":"rule-set-remote","role":"rule_set","type":"remote","tag":"operator-remote-rules","enabled":true,"route_rules":[],"config":{"format":"binary","url":"https://rules.invalid/rules.srs?token=fixture-secret-token","http_client":"http-shared","initial_path":"/tmp/operator-rules.srs","update_interval":"12h"}}'
managed_component_state_validate_record "${inline_rule_set_record}"
managed_component_state_validate_record "${local_rule_set_record}"
managed_component_state_validate_record "${remote_rule_set_record}"
rule_set_state=$(managed_component_state_candidate "${http_client_state}" create "${inline_rule_set_record}")
rule_set_state=$(managed_component_state_candidate "${rule_set_state}" create "${local_rule_set_record}")
rule_set_state=$(managed_component_state_candidate "${rule_set_state}" create "${remote_rule_set_record}")
original_detect_installed_singbox_version=$(declare -f detect_installed_singbox_version)
detect_installed_singbox_version() { printf '1.13.18'; }
if managed_component_state_core_features_supported "${rule_set_state}"; then
  printf '1.13 core unexpectedly accepted remote rule-set http_client\n' >&2
  exit 1
fi
remote_rule_set_without_http_client=$(jq -c 'del(.config.http_client)' <<< "${remote_rule_set_record}")
remote_rule_set_113_state=$(managed_component_state_candidate \
  "$(managed_component_state_default_json)" create "${remote_rule_set_without_http_client}")
managed_component_state_core_features_supported "${remote_rule_set_113_state}"
detect_installed_singbox_version() { printf '1.14.0'; }
managed_component_state_core_features_supported "${rule_set_state}"
detect_installed_singbox_version() { printf ''; }
if managed_component_state_core_features_supported "${rule_set_state}"; then
  printf 'unknown core version unexpectedly accepted remote rule-set http_client\n' >&2
  exit 1
fi
eval "${original_detect_installed_singbox_version}"
unset original_detect_installed_singbox_version
rule_sets_rendered=$(managed_component_render_json "${rule_set_state}")
jq -e '
  (.rule_sets | length == 3) and
  any(.rule_sets[]; .type == "inline" and .tag == "operator-inline-rules" and
    .rules == [{domain_suffix:["rules.example.test"]}]) and
  any(.rule_sets[]; .type == "local" and .format == "source" and
    .path == "/tmp/operator-rules.json") and
  any(.rule_sets[]; .type == "remote" and .format == "binary" and
    .http_client == "http-shared" and .update_interval == "12h")
' <<< "${rule_sets_rendered}" >/dev/null

inline_rule_set_bad_action=$(jq -c '.config.rules[0].action="reject"' <<< "${inline_rule_set_record}")
if managed_component_state_validate_record "${inline_rule_set_bad_action}"; then
  printf 'inline route rule-set action unexpectedly accepted\n' >&2
  exit 1
fi
inline_rule_set_bad_match=$(jq -c '.config.rules[0].unknown_match=true' <<< "${inline_rule_set_record}")
if managed_component_state_validate_record "${inline_rule_set_bad_match}"; then
  printf 'inline route rule-set unknown matcher unexpectedly accepted\n' >&2
  exit 1
fi
inline_rule_set_empty=$(jq -c '.config.rules=[]' <<< "${inline_rule_set_record}")
if managed_component_state_validate_record "${inline_rule_set_empty}"; then
  printf 'empty inline route rule-set unexpectedly accepted\n' >&2
  exit 1
fi
local_rule_set_bad_path=$(jq -c '.config.path="relative-rules.json"' <<< "${local_rule_set_record}")
if managed_component_state_validate_record "${local_rule_set_bad_path}"; then
  printf 'relative local route rule-set path unexpectedly accepted\n' >&2
  exit 1
fi
remote_rule_set_bad_url=$(jq -c '.config.url="ftp://rules.invalid/rules.srs"' <<< "${remote_rule_set_record}")
if managed_component_state_validate_record "${remote_rule_set_bad_url}"; then
  printf 'non-HTTP remote route rule-set URL unexpectedly accepted\n' >&2
  exit 1
fi
remote_rule_set_legacy_detour=$(jq -c '.config.download_detour="direct"' <<< "${remote_rule_set_record}")
if managed_component_state_validate_record "${remote_rule_set_legacy_detour}"; then
  printf 'deprecated remote route rule-set download_detour unexpectedly accepted\n' >&2
  exit 1
fi
remote_rule_set_inline_client=$(jq -c '.config.http_client={detour:"direct"}' <<< "${remote_rule_set_record}")
if managed_component_state_validate_record "${remote_rule_set_inline_client}"; then
  printf 'inline remote route rule-set HTTP client unexpectedly accepted\n' >&2
  exit 1
fi
remote_rule_set_reserved_tag=$(jq -c '.tag="warp-local-user-rules"' <<< "${inline_rule_set_record}")
if managed_component_state_validate_record "${remote_rule_set_reserved_tag}"; then
  printf 'Warp-owned route rule-set tag unexpectedly accepted\n' >&2
  exit 1
fi
remote_rule_set_multi_tag=$(jq -c '.tag=["one","two"]' <<< "${inline_rule_set_record}")
if managed_component_state_validate_record "${remote_rule_set_multi_tag}"; then
  printf 'unmodeled multi-tag route rule-set unexpectedly accepted\n' >&2
  exit 1
fi
if managed_component_state_candidate "${rule_set_state}" delete "" "http-client-local"; then
  printf 'shared HTTP client referenced by remote rule-set unexpectedly deleted\n' >&2
  exit 1
fi
rule_set_route_reference='{"id":"rule-set-route-reference","role":"outbound","type":"direct","tag":"route-reference-owner","enabled":true,"route_rules":[{"rule_set":"operator-inline-rules","action":"route","outbound":"direct"}],"config":{}}'
rule_set_reference_state=$(managed_component_state_candidate "${rule_set_state}" create "${rule_set_route_reference}")
if managed_component_state_candidate "${rule_set_reference_state}" delete "" "rule-set-inline"; then
  printf 'route rule-set referenced by a managed route rule unexpectedly deleted\n' >&2
  exit 1
fi
rule_set_remote_export=$(
  managed_component_state_json() { printf '%s\n' "${rule_set_state}"; }
  managed_component_export_json "rule-set-remote"
)
jq -e --arg secret "fixture-secret-token" '
  .sensitive == true and
  (.component.config.url | contains($secret))
' <<< "${rule_set_remote_export}" >/dev/null
rule_set_inventory=$(
  managed_component_state_json() { printf '%s\n' "${rule_set_state}"; }
  managed_component_inventory_json
)
jq -e '
  (.components | length == 5) and
  (any(.components[]; has("config") or has("url")) | not) and
  (tojson | contains("fixture-secret-token") | not)
' <<< "${rule_set_inventory}" >/dev/null

# Protocol state readers must preserve both supported shared ACME HTTP-client
# references and legacy inline HTTPClientOptions objects.  Invalid inline
# shapes still fail closed instead of becoming an untyped JSON escape hatch.
shared_acme_http_config_file=$(mktemp)
jq -n '{
  inbounds:[{type:"anytls",tls:{server_name:"shared-http.example",certificate_provider:"shared-provider"}}],
  certificate_providers:[{type:"acme",tag:"shared-provider",domain:["shared-http.example"],email:"ops@example.com",http_client:"shared-acme-http"}],
  http_clients:[{tag:"shared-acme-http",engine:"go",version:2}],
  route:{rules:[]}
}' > "${shared_acme_http_config_file}"
load_certificate_provider_from_config "${shared_acme_http_config_file}" 0
jq -e '.http_client == "shared-acme-http"' <<< "${CERT_PROVIDER_EXTRA_JSON}" >/dev/null
jq '.certificate_providers[0].http_client = {engine:"go"}' \
  "${shared_acme_http_config_file}" > "${shared_acme_http_config_file}.next"
mv -f "${shared_acme_http_config_file}.next" "${shared_acme_http_config_file}"
load_certificate_provider_from_config "${shared_acme_http_config_file}" 0
jq -e '.http_client.engine == "go"' <<< "${CERT_PROVIDER_EXTRA_JSON}" >/dev/null
jq '.certificate_providers[0].http_client = {unknown:true}' \
  "${shared_acme_http_config_file}" > "${shared_acme_http_config_file}.next"
mv -f "${shared_acme_http_config_file}.next" "${shared_acme_http_config_file}"
if load_certificate_provider_from_config "${shared_acme_http_config_file}" 0; then
  printf 'invalid inline ACME http_client unexpectedly passed protocol reader\n' >&2
  exit 1
fi
rm -f "${shared_acme_http_config_file}"

default_namespace_record='{"id":"default-namespace-local","role":"network_namespace","type":"default","tag":"netns-default","enabled":true,"route_rules":[],"config":{"path":"/proc/1/ns/net"}}'
unshare_namespace_record='{"id":"unshare-namespace-local","role":"network_namespace","type":"unshare","tag":"netns-unshare","enabled":true,"route_rules":[],"config":{}}'
resolved_service_record='{"id":"resolved-service-local","role":"service","type":"resolved","tag":"resolved-local","enabled":true,"route_rules":[],"config":{"listen":"127.0.0.53","listen_port":53}}'
managed_component_state_validate_record "${default_namespace_record}"
managed_component_state_validate_record "${unshare_namespace_record}"
managed_component_state_validate_record "${resolved_service_record}"
namespace_state=$(managed_component_state_candidate "${http_client_state}" create "${default_namespace_record}")
namespace_state=$(managed_component_state_candidate "${namespace_state}" create "${unshare_namespace_record}")
namespace_state=$(managed_component_state_candidate "${namespace_state}" create "${resolved_service_record}")
namespace_rendered=$(managed_component_render_json "${namespace_state}")
jq -e '
  (.network_namespaces | length == 2) and
  .network_namespaces[0].type == "default" and
  .network_namespaces[0].path == "/proc/1/ns/net" and
  .network_namespaces[1].type == "unshare" and
  (.network_namespaces[1] | keys) == ["tag","type"] and
  (.services | length == 1) and
  .services[0].type == "resolved" and
  .services[0].tag == "resolved-local" and
  .services[0].listen == "127.0.0.53" and
  .services[0].listen_port == 53
' <<< "${namespace_rendered}" >/dev/null
projection_config_file=$(mktemp)
jq -n --argjson providers "$(jq '.certificate_providers' <<< "${namespace_rendered}")" \
  --argjson clients "$(jq '.http_clients' <<< "${namespace_rendered}")" \
  --argjson namespaces "$(jq '.network_namespaces' <<< "${namespace_rendered}")" \
  --argjson services "$(jq '.services' <<< "${namespace_rendered}")" \
  '{certificate_providers:$providers,http_clients:$clients,services:$services,network_namespaces:$namespaces}' > "${projection_config_file}"
projection_state_json_definition=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${namespace_state}"
}
managed_component_live_config_projection_supported "${projection_config_file}"
jq '.services[0].listen_port = 54' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'managed resolved service drift unexpectedly passed projection guard\n' >&2
  exit 1
fi
jq '.services[0].listen_port = 53' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
managed_component_live_config_projection_supported "${projection_config_file}"
jq '.route={rule_set:[{type:"local",tag:"warp-local-owned",format:"source",path:"/var/lib/sing-box/warp.srs"}]}' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
managed_component_live_config_projection_supported "${projection_config_file}"
jq '.route.rule_set[0].tag="operator-rules"' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'unmanaged route rule-set unexpectedly passed projection guard\n' >&2
  exit 1
fi
jq '.route.rule_set="not-an-array"' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'malformed route rule-set container unexpectedly passed projection guard\n' >&2
  exit 1
fi
jq '.route.rule_set=null' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'null route rule-set container unexpectedly passed projection guard\n' >&2
  exit 1
fi
jq '.route={}' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
jq '.route.rule_set=[{type:"local",tag:"warp-local-owned",format:"source",path:"/var/lib/sing-box/warp.srs"}]' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
managed_component_live_config_projection_supported "${projection_config_file}"
projection_rule_set_record='{"id":"projection-rule-set","role":"rule_set","type":"inline","tag":"projection-rules","enabled":true,"route_rules":[],"config":{"rules":[{"domain_suffix":["projection.example.test"]}]}}'
projection_rule_set_state=$(managed_component_state_candidate "${namespace_state}" create "${projection_rule_set_record}")
projection_rule_set_rendered=$(managed_component_render_json "${projection_rule_set_state}")
jq --argjson rule_sets "$(jq -c '.rule_sets' <<< "${projection_rule_set_rendered}")" \
  '.route={rule_set:$rule_sets}' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
managed_component_state_json() {
  printf '%s\n' "${projection_rule_set_state}"
}
managed_component_live_route_rule_sets_match_state "${projection_config_file}" "${projection_rule_set_state}"
managed_component_live_config_projection_supported "${projection_config_file}"
jq '.route.rule_set[0].rules[0].domain_suffix=["drift.example.test"]' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'managed route rule-set field drift unexpectedly passed projection guard\n' >&2
  exit 1
fi
jq --argjson rule_sets "$(jq -c '.rule_sets' <<< "${projection_rule_set_rendered}")" \
  '.route={rule_set:$rule_sets}' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
jq '.route.rule_set=[]' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_route_rule_sets_match_state "${projection_config_file}" "${projection_rule_set_state}"; then
  printf 'missing managed route rule set unexpectedly matched state\n' >&2
  exit 1
fi
jq --argjson rule_sets "$(jq -c '.rule_sets' <<< "${projection_rule_set_rendered}")" \
  '.route={rule_set:$rule_sets}' "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
managed_component_write_state "${projection_rule_set_state}"
projection_rule_set_snapshot=$(create_managed_state_snapshot)
managed_component_live_route_rule_sets_supported \
  "${projection_config_file}" "${projection_rule_set_snapshot}/project/components.json"
discard_managed_state_snapshot "${projection_rule_set_snapshot}"
managed_component_state_json() {
  printf '%s\n' "${namespace_state}"
}
legacy_rule_set_config_file=$(mktemp)
jq -n '{route:{rule_set:[{type:"remote",download_detour:"direct"}]}}' > "${legacy_rule_set_config_file}"
legacy_rule_set_empty_state=$(managed_component_state_default_json)
if managed_component_live_route_rule_sets_match_state \
  "${legacy_rule_set_config_file}" "${legacy_rule_set_empty_state}"; then
  printf 'legacy untracked download_detour rule set unexpectedly passed strict state matching\n' >&2
  exit 1
fi
managed_component_live_route_rule_sets_match_state \
  "${legacy_rule_set_config_file}" "${legacy_rule_set_empty_state}" true
jq -n '{route:{rule_set:[{type:"remote",tag:"warp-local-invalid",download_detour:"direct"}]}}' \
  > "${legacy_rule_set_config_file}"
if managed_component_live_route_rule_sets_match_state \
  "${legacy_rule_set_config_file}" "${legacy_rule_set_empty_state}" true; then
  printf 'legacy download_detour exception accepted a remote Warp-local type mismatch\n' >&2
  exit 1
fi
jq -n '{route:{rule_set:[{type:"remote",tag:"warp-unknown-legacy",download_detour:"direct"}]}}' \
  > "${legacy_rule_set_config_file}"
if managed_component_live_route_rule_sets_match_state \
  "${legacy_rule_set_config_file}" "${legacy_rule_set_empty_state}" true; then
  printf 'legacy download_detour exception accepted an unknown reserved Warp tag\n' >&2
  exit 1
fi
jq -n '{route:{rule_set:[{type:"remote",tag:"warp-remote-legacy",download_detour:"direct"}]}}' \
  > "${legacy_rule_set_config_file}"
managed_component_live_route_rule_sets_match_state \
  "${legacy_rule_set_config_file}" "${legacy_rule_set_empty_state}" true
if managed_component_live_route_rule_sets_match_state \
  "${legacy_rule_set_config_file}" "${projection_rule_set_state}" true; then
  printf 'legacy rule-set health tolerance ignored enabled managed rule-set state\n' >&2
  exit 1
fi
rm -f "${legacy_rule_set_config_file}"
jq '.certificate_providers[0].domain = ["drift.example"]' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'managed certificate provider drift unexpectedly passed projection guard\n' >&2
  exit 1
fi
jq '.network_namespaces[0].path = "/proc/2/ns/net"' \
  "${projection_config_file}" > "${projection_config_file}.next"
mv -f "${projection_config_file}.next" "${projection_config_file}"
if managed_component_live_config_projection_supported "${projection_config_file}"; then
  printf 'managed network namespace drift unexpectedly passed projection guard\n' >&2
  exit 1
fi
eval "${projection_state_json_definition}"
unset projection_state_json_definition
rm -f "${projection_config_file}"

# Shared HTTP clients are first-class top-level components during takeover as
# well as render/projection.  The live path must reject malformed container
# shapes and duplicate tags, and state matching must notice field drift instead
# of treating a same-tag client as sufficient ownership proof.
http_client_takeover_config='{"http_clients":[{"tag":"http-takeover","version":2,"headers":{"Accept":"application/json"},"detour":"direct"}],"route":{"default_http_client":"http-takeover"}}'
printf '%s\n' "${http_client_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
http_client_takeover_base_state=$(managed_component_state_default_json)
http_client_takeover_records=$(managed_component_live_takeover_records_json "${http_client_takeover_base_state}")
jq -e '
  length == 1 and .[0].role == "http_client" and .[0].type == "shared" and
  .[0].tag == "http-takeover" and .[0].config.version == 2 and
  .[0].config.headers.Accept == "application/json" and .[0].route_rules == []
' <<< "${http_client_takeover_records}" >/dev/null
http_client_takeover_state=$(managed_component_state_takeover_candidate \
  "${http_client_takeover_base_state}" "${http_client_takeover_records}")
original_http_client_state_json_definition=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${http_client_takeover_state}"
}
managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"
jq '.http_clients[0].headers.Accept = "text/plain"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'shared HTTP client config drift unexpectedly matched managed state\n' >&2
  exit 1
fi
printf '%s\n' "${http_client_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
managed_component_live_config_projection_supported "${SINGBOX_CONFIG_FILE}"
jq '.route.default_http_client = "missing-http-takeover"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'unmapped shared HTTP client route default unexpectedly matched managed state\n' >&2
  exit 1
fi
printf '%s\n' "${http_client_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
jq '.http_clients += [{tag:"http-takeover",version:2}]' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'duplicate shared HTTP client tag unexpectedly matched managed state\n' >&2
  exit 1
fi
jq -n --argjson config "${http_client_takeover_config}" '$config' > "${SINGBOX_CONFIG_FILE}"
jq '.http_clients[0].type = "shared"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'typed shared HTTP client live object unexpectedly matched managed state\n' >&2
  exit 1
fi
jq -n --argjson config "${http_client_takeover_config}" '$config' > "${SINGBOX_CONFIG_FILE}"
jq '.http_clients = {tag:"http-takeover"}' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'scalar shared HTTP client container unexpectedly matched managed state\n' >&2
  exit 1
fi
jq -n --argjson config "${http_client_takeover_config}" '$config' > "${SINGBOX_CONFIG_FILE}"
jq 'del(.http_clients)' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'missing shared HTTP client inventory unexpectedly matched managed state\n' >&2
  exit 1
fi
if managed_component_live_config_projection_supported "${SINGBOX_CONFIG_FILE}"; then
  printf 'missing shared HTTP client projection unexpectedly passed\n' >&2
  exit 1
fi
jq -n --argjson config "${http_client_takeover_config}" '$config' > "${SINGBOX_CONFIG_FILE}"
jq '.http_clients += [{tag:"http-takeover",version:2}]' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${http_client_takeover_base_state}" >/dev/null 2>&1; then
  printf 'duplicate shared HTTP client tag unexpectedly passed takeover\n' >&2
  exit 1
fi
jq -n --argjson config "${http_client_takeover_config}" '$config' > "${SINGBOX_CONFIG_FILE}"
jq '.http_clients[0].type = "shared"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${http_client_takeover_base_state}" >/dev/null 2>&1; then
  printf 'typed shared HTTP client live object unexpectedly passed takeover\n' >&2
  exit 1
fi
jq -n --argjson config "${http_client_takeover_config}" '$config' > "${SINGBOX_CONFIG_FILE}"
jq '.http_clients = {tag:"http-takeover"}' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${http_client_takeover_base_state}" >/dev/null 2>&1; then
  printf 'scalar shared HTTP client container unexpectedly passed takeover\n' >&2
  exit 1
fi
eval "${original_http_client_state_json_definition}"
unset original_http_client_state_json_definition
rm -f "${SINGBOX_CONFIG_FILE}"

# Resolved services participate in live takeover and matching just like other
# typed top-level components. Their route ownership is intentionally empty;
# listener resources are projected as the core's TCP+UDP loopback pair.
resolved_takeover_config='{"inbounds":[],"services":[{"type":"resolved","tag":"resolved-takeover","listen":"127.0.0.53","listen_port":53}]}'
printf '%s\n' "${resolved_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
resolved_takeover_base_state=$(managed_component_state_default_json)
resolved_takeover_records=$(managed_component_live_takeover_records_json "${resolved_takeover_base_state}")
jq -e '
  length == 1 and .[0].role == "service" and .[0].type == "resolved" and
  .[0].tag == "resolved-takeover" and .[0].config.listen == "127.0.0.53" and
  .[0].config.listen_port == 53 and .[0].route_rules == []
' <<< "${resolved_takeover_records}" >/dev/null
resolved_takeover_state=$(managed_component_state_takeover_candidate \
  "${resolved_takeover_base_state}" "${resolved_takeover_records}")
original_resolved_state_json_definition=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${resolved_takeover_state}"
}
managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"
managed_component_live_config_projection_supported "${SINGBOX_CONFIG_FILE}"
jq '.services[0].listen_port = 54' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'resolved service config drift unexpectedly matched managed state\n' >&2
  exit 1
fi
printf '%s\n' "${resolved_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
jq '.services[0].type = "future-service"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${resolved_takeover_base_state}" >/dev/null 2>&1; then
  printf 'unknown resolved service type unexpectedly passed takeover\n' >&2
  exit 1
fi
eval "${original_resolved_state_json_definition}"
unset original_resolved_state_json_definition
rm -f "${SINGBOX_CONFIG_FILE}"

# Route rule sets are typed components too: takeover imports only registered
# non-Warp sets, while reserved Warp names must retain their expected type.
rule_set_takeover_config='{"route":{"rule_set":[{"type":"inline","tag":"inline-takeover","rules":[{"domain_suffix":["inline.example.test"]}]},{"type":"local","tag":"local-takeover","format":"source","path":"/tmp/local-rules.json"},{"type":"remote","tag":"remote-takeover","format":"source","url":"https://rules.example.test/remote.json"},{"type":"local","tag":"warp-local-owned","format":"source","path":"/tmp/warp-rules.json"}]}}'
printf '%s\n' "${rule_set_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
rule_set_takeover_base_state=$(managed_component_state_default_json)
rule_set_takeover_records=$(managed_component_live_takeover_records_json "${rule_set_takeover_base_state}")
jq -e '
  length == 3 and
  ([.[].role] | unique) == ["rule_set"] and
  ([.[].type] | sort) == ["inline","local","remote"] and
  (map(.tag) | sort) == ["inline-takeover","local-takeover","remote-takeover"] and
  all(.[]; .route_rules == [])
' <<< "${rule_set_takeover_records}" >/dev/null
rule_set_takeover_state=$(managed_component_state_takeover_candidate \
  "${rule_set_takeover_base_state}" "${rule_set_takeover_records}")
rule_set_takeover_rendered=$(managed_component_render_json "${rule_set_takeover_state}")
rule_set_takeover_before="${TMP_DIR}/rule-set-takeover-before.json"
rule_set_takeover_after="${TMP_DIR}/rule-set-takeover-after.json"
jq 'del(.route.rule_set[3])' <<< "${rule_set_takeover_config}" > "${rule_set_takeover_before}"
jq --argjson rule_sets "$(jq -c '.rule_sets' <<< "${rule_set_takeover_rendered}")" \
  '.route.rule_set=$rule_sets' "${rule_set_takeover_before}" > "${rule_set_takeover_after}"
managed_component_takeover_preserves_live_config \
  "${rule_set_takeover_before}" "${rule_set_takeover_after}"
original_rule_set_state_json_definition=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${rule_set_takeover_state}"
}
managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"
managed_component_live_config_projection_supported "${SINGBOX_CONFIG_FILE}"
jq '.route.rule_set[0].rules[0].domain_suffix=["drift.example.test"]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'route rule-set takeover drift unexpectedly matched state\n' >&2
  exit 1
fi
printf '%s\n' "${rule_set_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
jq '.route.rule_set[0].type="remote"' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${rule_set_takeover_base_state}" >/dev/null 2>&1; then
  printf 'reserved Warp rule-set type mismatch unexpectedly passed takeover\n' >&2
  exit 1
fi
printf '%s\n' "${rule_set_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
jq '.route.rule_set[0].tag=["multi","tag"]' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${rule_set_takeover_base_state}" >/dev/null 2>&1; then
  printf 'multi-tag live route rule-set unexpectedly passed takeover\n' >&2
  exit 1
fi
printf '%s\n' "${rule_set_takeover_config}" > "${SINGBOX_CONFIG_FILE}"
jq '.route.rule_set=null' "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "${rule_set_takeover_base_state}" >/dev/null 2>&1; then
  printf 'null live route rule-set unexpectedly passed takeover\n' >&2
  exit 1
fi
eval "${original_rule_set_state_json_definition}"
unset original_rule_set_state_json_definition
rm -f "${SINGBOX_CONFIG_FILE}"

namespace_bad_path=$(jq -c '.config.path = "relative/netns"' <<< "${default_namespace_record}")
if managed_component_state_validate_record "${namespace_bad_path}"; then
  printf 'network namespace relative path unexpectedly accepted\n' >&2
  exit 1
fi
namespace_unknown=$(jq -c '.config.mount = "/run"' <<< "${unshare_namespace_record}")
if managed_component_state_validate_record "${namespace_unknown}"; then
  printf 'unshare network namespace unknown field unexpectedly accepted\n' >&2
  exit 1
fi
namespace_route_rule=$(jq -c '.route_rules = [{"action":"route","outbound":"direct"}]' <<< "${unshare_namespace_record}")
if managed_component_state_validate_record "${namespace_route_rule}"; then
  printf 'network namespace route rules unexpectedly accepted\n' >&2
  exit 1
fi
resolved_service_unknown=$(jq -c '.config.unknown = true' <<< "${resolved_service_record}")
if managed_component_state_validate_record "${resolved_service_unknown}"; then
  printf 'resolved service unknown field unexpectedly accepted\n' >&2
  exit 1
fi
resolved_service_bad_port=$(jq -c '.config.listen_port = 65536' <<< "${resolved_service_record}")
if managed_component_state_validate_record "${resolved_service_bad_port}"; then
  printf 'resolved service out-of-range port unexpectedly accepted\n' >&2
  exit 1
fi
resolved_service_empty_listen=$(jq -c '.config.listen = ""' <<< "${resolved_service_record}")
if managed_component_state_validate_record "${resolved_service_empty_listen}"; then
  printf 'resolved service empty listen unexpectedly accepted\n' >&2
  exit 1
fi
resolved_service_hostname_listen=$(jq -c '.config.listen = "localhost.example"' <<< "${resolved_service_record}")
if managed_component_state_validate_record "${resolved_service_hostname_listen}"; then
  printf 'resolved service hostname listen unexpectedly accepted\n' >&2
  exit 1
fi
resolved_service_route_rule=$(jq -c '.route_rules = [{"action":"route","outbound":"direct"}]' <<< "${resolved_service_record}")
if managed_component_state_validate_record "${resolved_service_route_rule}"; then
  printf 'resolved service route rules unexpectedly accepted\n' >&2
  exit 1
fi
resolved_service_public=$(jq -c '.config.listen = "0.0.0.0"' <<< "${resolved_service_record}")
managed_component_requires_public_confirmation "${resolved_service_public}"

# Direct, block and bridge outbounds are registry-owned component records too.
# Their configs are flattened into the generated outbound objects, so each
# variant must have an explicit typed allowlist before it can enter the CAS
# state.  These fixtures exercise both renderability and the no-passthrough
# boundary for fields that sing-box does not expose on the corresponding
# option type.
direct_outbound_record='{"id":"direct-outbound-local","role":"outbound","type":"direct","tag":"direct-outbound-local","enabled":true,"route_rules":[],"config":{"bind_interface":"lo","routing_mark":"0x20","tcp_fast_open":true,"network_strategy":"default","network_type":["ethernet"]}}'
managed_component_state_validate_record "${direct_outbound_record}"
direct_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${direct_outbound_record}")
direct_outbound_rendered=$(managed_component_render_json "${direct_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "direct" and
  .outbounds[0].tag == "direct-outbound-local" and
  .outbounds[0].bind_interface == "lo" and
  .outbounds[0].routing_mark == "0x20" and
  .outbounds[0].tcp_fast_open == true and
  .outbounds[0].network_strategy == "default" and
  .outbounds[0].network_type == ["ethernet"]
' <<< "${direct_outbound_rendered}" >/dev/null
direct_outbound_unknown_field=$(jq -c '.config.unexpected = true' <<< "${direct_outbound_record}")
if managed_component_state_validate_record "${direct_outbound_unknown_field}"; then
  printf 'direct outbound unknown field unexpectedly accepted\n' >&2
  exit 1
fi
direct_outbound_override_field=$(jq -c '.config.override_address = "127.0.0.1"' <<< "${direct_outbound_record}")
if managed_component_state_validate_record "${direct_outbound_override_field}"; then
  printf 'direct outbound deprecated override field unexpectedly accepted\n' >&2
  exit 1
fi
direct_outbound_proxy_protocol_field=$(jq -c '.config.proxy_protocol = 1' <<< "${direct_outbound_record}")
if managed_component_state_validate_record "${direct_outbound_proxy_protocol_field}"; then
  printf 'direct outbound removed proxy protocol field unexpectedly accepted\n' >&2
  exit 1
fi
direct_outbound_detour_field=$(jq -c '.config.detour = "upstream"' <<< "${direct_outbound_record}")
if managed_component_state_validate_record "${direct_outbound_detour_field}"; then
  printf 'direct outbound non-empty detour unexpectedly accepted\n' >&2
  exit 1
fi

block_outbound_record='{"id":"block-outbound-local","role":"outbound","type":"block","tag":"block-outbound-local","enabled":true,"route_rules":[],"config":{}}'
managed_component_state_validate_record "${block_outbound_record}"
block_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${block_outbound_record}")
block_outbound_rendered=$(managed_component_render_json "${block_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "block" and
  .outbounds[0].tag == "block-outbound-local"
' <<< "${block_outbound_rendered}" >/dev/null
block_outbound_unknown_field=$(jq -c '.config.unexpected = true' <<< "${block_outbound_record}")
if managed_component_state_validate_record "${block_outbound_unknown_field}"; then
  printf 'block outbound unknown field unexpectedly accepted\n' >&2
  exit 1
fi

bridge_outbound_record='{"id":"bridge-outbound-local","role":"outbound","type":"bridge","tag":"bridge-outbound-local","enabled":true,"route_rules":[],"config":{"interface":"eth0","bridge_name":"sbv-bridge","iproute2_table_index":2200,"iproute2_rule_index":100}}'
managed_component_state_validate_record "${bridge_outbound_record}"
bridge_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${bridge_outbound_record}")
bridge_outbound_rendered=$(managed_component_render_json "${bridge_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "bridge" and
  .outbounds[0].tag == "bridge-outbound-local" and
  .outbounds[0].interface == "eth0" and
  .outbounds[0].bridge_name == "sbv-bridge" and
  .outbounds[0].iproute2_table_index == 2200 and
  .outbounds[0].iproute2_rule_index == 100
' <<< "${bridge_outbound_rendered}" >/dev/null
bridge_outbound_unknown_field=$(jq -c '.config.unexpected = true' <<< "${bridge_outbound_record}")
if managed_component_state_validate_record "${bridge_outbound_unknown_field}"; then
  printf 'bridge outbound unknown field unexpectedly accepted\n' >&2
  exit 1
fi
bridge_outbound_negative_index=$(jq -c '.config.iproute2_rule_index = -1' <<< "${bridge_outbound_record}")
if managed_component_state_validate_record "${bridge_outbound_negative_index}"; then
  printf 'bridge outbound negative rule index unexpectedly accepted\n' >&2
  exit 1
fi
bridge_outbound_fractional_index=$(jq -c '.config.iproute2_table_index = 2200.5' <<< "${bridge_outbound_record}")
if managed_component_state_validate_record "${bridge_outbound_fractional_index}"; then
  printf 'bridge outbound fractional table index unexpectedly accepted\n' >&2
  exit 1
fi
bridge_outbound_control_field=$(jq -c '.config.interface = "eth0\nforged"' <<< "${bridge_outbound_record}")
if managed_component_state_validate_record "${bridge_outbound_control_field}"; then
  printf 'bridge outbound control character unexpectedly accepted\n' >&2
  exit 1
fi

direct_override_record=$(jq -c '.config += {network:"tcp",override_address:"127.0.0.1",override_port:18082}' <<< "${direct_record}")
managed_component_state_validate_record "${direct_override_record}"
direct_override_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${direct_override_record}")
direct_override_rendered=$(managed_component_render_json "${direct_override_state}")
jq -e '
  .inbounds | length == 1 and
  .[0].type == "direct" and .[0].network == "tcp" and
  .[0].override_address == "127.0.0.1" and .[0].override_port == 18082
' <<< "${direct_override_rendered}" >/dev/null
direct_bad_network=$(jq -c '.config.network = "icmp"' <<< "${direct_override_record}")
if managed_component_state_validate_record "${direct_bad_network}"; then
  printf 'direct inbound invalid network was unexpectedly accepted\n' >&2
  exit 1
fi
direct_bad_override_address=$(jq -c '.config.override_address = "127.0.0.1\nforged"' <<< "${direct_override_record}")
if managed_component_state_validate_record "${direct_bad_override_address}"; then
  printf 'direct inbound override address control character was unexpectedly accepted\n' >&2
  exit 1
fi
direct_bad_override_port=$(jq -c '.config.override_port = 65536' <<< "${direct_override_record}")
if managed_component_state_validate_record "${direct_bad_override_port}"; then
  printf 'direct inbound override port overflow was unexpectedly accepted\n' >&2
  exit 1
fi

# Direct, redirect and TProxy inbounds share typed ListenOptions but keep their
# protocol-specific fields separate.  Arrays are accepted where sing-box's
# Listable type permits them; duplicate network members and unknown fields are
# rejected before state publication.
direct_listen_options=$(jq -c '.config += {network:["tcp","udp"],bind_interface:"lo",routing_mark:"0x20",reuse_addr:true,tcp_fast_open:true,udp_fragment:false,udp_timeout:"30s",detour:"direct-upstream"}' <<< "${direct_record}")
managed_component_state_validate_record "${direct_listen_options}"
direct_listen_rendered=$(managed_component_render_json "$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${direct_listen_options}")")
jq -e '.inbounds[0].network == ["tcp","udp"] and .inbounds[0].routing_mark == "0x20" and .inbounds[0].reuse_addr == true and .inbounds[0].udp_timeout == "30s"' <<< "${direct_listen_rendered}" >/dev/null
direct_duplicate_network=$(jq -c '.config.network = ["tcp","tcp"]' <<< "${direct_listen_options}")
if managed_component_state_validate_record "${direct_duplicate_network}"; then
  printf 'direct duplicate network member unexpectedly accepted\n' >&2
  exit 1
fi
direct_unknown_listen_field=$(jq -c '.config |= (. + {proxy_protocol:true})' <<< "${direct_record}")
if managed_component_state_validate_record "${direct_unknown_listen_field}"; then
  printf 'direct deprecated listen field unexpectedly accepted\n' >&2
  exit 1
fi

# Component-owned route rules use the target core's default/logical rule union
# and route actions, but are not an arbitrary JSON escape hatch.  Keep common
# match/action combinations renderable, reject unknown fields and preserve the
# nested-rule restriction that actions only belong to top-level rules.
route_rule_record=$(jq -c '.route_rules = [
  {domain:["managed.example"],network:["tcp","udp"],action:"route",outbound:"direct",
   override_address:"127.0.0.1",override_port:18082,udp_timeout:"5s"},
  {type:"logical",mode:"and",invert:false,rules:[
    {domain_suffix:["example"],ip_is_private:false},
    {protocol:"tls"}
  ],action:"route",outbound:"direct"}
]' <<< "${direct_record}")
managed_component_state_validate_record "${route_rule_record}"
route_rule_record=$(jq -c '.route_rules = [
  {domain:["managed.example"],network:["tcp","udp"],action:"route",outbound:"direct",
   override_address:"127.0.0.1",override_port:18082,udp_timeout:"5s"},
  {type:"logical",mode:"and",invert:false,rules:[
    {domain_suffix:["example"],ip_is_private:false},
    {protocol:"tls"}
  ]}
]' <<< "${direct_record}")
managed_component_state_validate_record "${route_rule_record}"
route_rule_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${route_rule_record}")
route_rule_rendered=$(managed_component_render_json "${route_rule_state}")
jq -e '
  .route_rules[0].action == "route" and
  .route_rules[0].outbound == "direct" and
  .route_rules[0].override_port == 18082 and
  .route_rules[1].type == "logical" and
  .route_rules[1].rules[0].domain_suffix == ["example"]
' <<< "${route_rule_rendered}" >/dev/null
route_rule_logical_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "$(jq -c '.route_rules = [
  {type:"logical",mode:"and",rules:[{domain:"example.com"}],action:"route",outbound:"direct"}
]' <<< "${direct_record}")")
route_rule_logical_rendered=$(managed_component_render_json "${route_rule_logical_state}")
jq -e '.route_rules[0].type == "logical" and .route_rules[0].action == "route" and .route_rules[0].outbound == "direct"' \
  <<< "${route_rule_logical_rendered}" >/dev/null
route_rule_unknown_field=$(jq -c '.route_rules[0].must_not_passthrough = true' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_unknown_field}"; then
  printf 'unknown component route field unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_bad_action=$(jq -c '.route_rules[0].action = "proxy"' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_bad_action}"; then
  printf 'unknown component route action unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_bad_match=$(jq -c '.route_rules[0].domain = {value:"managed.example"}' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_bad_match}"; then
  printf 'object component route matcher unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_duplicate_match=$(jq -c '.route_rules[0].network = ["tcp","tcp"]' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_duplicate_match}"; then
  printf 'duplicate component route matcher unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_oversized_match=$(jq -cn '
  [range(0; 65) | ("managed-" + tostring)] as $domains |
  {id:"route-oversized",role:"inbound",type:"direct",tag:"route-oversized",enabled:true,
   route_rules:[{domain:$domains}],config:{listen:"127.0.0.1",listen_port:18083}}
')
if managed_component_state_validate_record "${route_rule_oversized_match}"; then
  printf 'oversized component route matcher unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_nested_action=$(jq -c '.route_rules[1].rules[0].action = "route"' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_nested_action}"; then
  printf 'nested component route action unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_nested_logical_fields=$(jq -c '.route_rules[1].rules[0] += {mode:"and",rules:[]}' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_nested_logical_fields}"; then
  printf 'logical fields on a default nested route rule unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_default_logical_fields=$(jq -c '.route_rules[0] += {mode:"and",rules:[]}' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_default_logical_fields}"; then
  printf 'logical fields on a default route rule unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_deep_logical=$(jq -cn '
  reduce range(0; 10) as $depth
    ({domain:["deep.example"]}; {type:"logical",mode:"and",rules:[.]})
')
route_rule_deep_record=$(jq -c --argjson deep_rule "${route_rule_deep_logical}" '.route_rules = [$deep_rule]' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_deep_record}"; then
  printf 'unbounded nested logical route rule unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_empty_options=$(jq -c '.route_rules[0] = {domain:["managed.example"],action:"route-options"}' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_empty_options}"; then
  printf 'empty route-options action unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_fragment_conflict=$(jq -c '.route_rules[0] = {domain:["managed.example"],action:"route-options",tls_fragment:true,tls_record_fragment:true}' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_fragment_conflict}"; then
  printf 'conflicting route-options fragments unexpectedly accepted\n' >&2
  exit 1
fi
route_rule_resolve_remove=$(jq -c '.route_rules[0] = {domain:["managed.example"],action:"resolve",remove_client_subnet:true}' <<< "${route_rule_record}")
if managed_component_state_validate_record "${route_rule_resolve_remove}"; then
  printf 'unsupported resolve remove_client_subnet unexpectedly accepted\n' >&2
  exit 1
fi

redirect_listen_options=$(jq -c '.config += {bind_interface:"lo",disable_tcp_keep_alive:true,tcp_keep_alive:"5m",tcp_keep_alive_interval:"75s",tcp_multi_path:true}' <<< "${redirect_record}")
managed_component_state_validate_record "${redirect_listen_options}"
redirect_bad_port=$(jq -c '.config.listen_port = 0' <<< "${redirect_record}")
if managed_component_state_validate_record "${redirect_bad_port}"; then
  printf 'redirect zero listen port unexpectedly accepted\n' >&2
  exit 1
fi
redirect_unknown_field=$(jq -c '.config |= (. + {network:["tcp"]})' <<< "${redirect_record}")
if managed_component_state_validate_record "${redirect_unknown_field}"; then
  printf 'redirect protocol-only field unexpectedly accepted\n' >&2
  exit 1
fi

tproxy_options=$(jq -c '.config += {network:["tcp","udp"],udp_mapping:"address_dependent",udp_filtering:"address_and_port_dependent",udp_nat_max:4096,routing_mark:1234}' <<< "${tproxy_record}")
managed_component_state_validate_record "${tproxy_options}"
tproxy_empty_nat=$(jq -c '.config.udp_mapping = ""' <<< "${tproxy_options}")
managed_component_state_validate_record "${tproxy_empty_nat}"
tproxy_bad_nat=$(jq -c '.config.udp_filtering = "invalid"' <<< "${tproxy_options}")
if managed_component_state_validate_record "${tproxy_bad_nat}"; then
  printf 'TProxy invalid UDP NAT behavior unexpectedly accepted\n' >&2
  exit 1
fi
tproxy_duplicate_network=$(jq -c '.config.network = ["udp","udp"]' <<< "${tproxy_options}")
if managed_component_state_validate_record "${tproxy_duplicate_network}"; then
  printf 'TProxy duplicate network member unexpectedly accepted\n' >&2
  exit 1
fi
tproxy_unknown_field=$(jq -c '.config |= (. + {sniff:true})' <<< "${tproxy_record}")
if managed_component_state_validate_record "${tproxy_unknown_field}"; then
  printf 'TProxy legacy inbound field unexpectedly accepted\n' >&2
  exit 1
fi
tproxy_bad_timeout=$(jq -c '.config.udp_timeout = 4294967296' <<< "${tproxy_record}")
if managed_component_state_validate_record "${tproxy_bad_timeout}"; then
  printf 'TProxy UDP timeout overflow unexpectedly accepted\n' >&2
  exit 1
fi

# TUN exposes the v1.14 route, UID/package, UDP NAT and platform surfaces as a
# typed record.  The old inet4/inet6/GSO and legacy sniff fields are rejected;
# auto_redirect also requires auto_route so a record cannot claim a partial
# transparent-routing setup.
tun_advanced_record=$(jq -c '.config = {
  interface_name:"tun-sbv",netns:"sbv-net",mtu:1500,
  address:["172.19.0.1/30","fdfe:dcba:9876::1/126"],
  dns_mode:"hijack",dns_address:["172.19.0.2","fdfe:dcba:9876::2"],
  auto_route:true,iproute2_table_index:2022,iproute2_rule_index:9000,
  auto_redirect:true,auto_redirect_input_mark:"0x2023",auto_redirect_output_mark:"0x2024",
  auto_redirect_reset_mark:"0x2025",auto_redirect_nfqueue:100,
  auto_redirect_iproute2_fallback_rule_index:9001,exclude_mptcp:true,
  loopback_address:"127.0.0.1",strict_route:true,
  route_address:["0.0.0.0/0","::/0"],route_address_set:["set-main"],
  route_exclude_address:["192.168.0.0/16"],route_exclude_address_set:["set-private"],
  include_interface:["eth0"],exclude_interface:["docker0"],include_uid:[1000],
  include_uid_range:["1000:2000"],exclude_uid:[65534],exclude_uid_range:["65534:65534"],
  include_android_user:[0],include_package:["com.example.app"],exclude_package:["com.example.bad"],
  include_mac_address:["02:00:00:00:00:01"],exclude_mac_address:["02:00:00:00:00:02"],
  udp_timeout:"5m",udp_mapping:"endpoint_independent",udp_filtering:"address_dependent",udp_nat_max:8192,
  stack:"system",platform:{http_proxy:{enabled:true,server:"127.0.0.1",server_port:8080,bypass_domain:["localhost"],match_domain:["example.com"]}}
}' <<< "${tun_record}")
managed_component_state_validate_record "${tun_advanced_record}"
tun_bad_deprecated=$(jq -c '.config.gso = true' <<< "${tun_record}")
if managed_component_state_validate_record "${tun_bad_deprecated}"; then
  printf 'TUN deprecated GSO field unexpectedly accepted\n' >&2
  exit 1
fi
tun_bad_redirect=$(jq -c '.config.auto_redirect = true' <<< "${tun_record}")
if managed_component_state_validate_record "${tun_bad_redirect}"; then
  printf 'TUN auto_redirect without auto_route unexpectedly accepted\n' >&2
  exit 1
fi
tun_unknown_field=$(jq -c '.config |= (. + {unexpected:true})' <<< "${tun_record}")
if managed_component_state_validate_record "${tun_unknown_field}"; then
  printf 'TUN unknown field unexpectedly accepted\n' >&2
  exit 1
fi
tun_bad_uid_range=$(jq -c '.config.include_uid_range = ["1000-2000"]' <<< "${tun_advanced_record}")
if managed_component_state_validate_record "${tun_bad_uid_range}"; then
  printf 'TUN malformed UID range unexpectedly accepted\n' >&2
  exit 1
fi
tun_missing_http_proxy_server=$(jq -c '.config.platform.http_proxy |= del(.server,.server_port)' <<< "${tun_advanced_record}")
if managed_component_state_validate_record "${tun_missing_http_proxy_server}"; then
  printf 'TUN enabled HTTP proxy without server unexpectedly accepted\n' >&2
  exit 1
fi

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

# State and record arguments are JSON text boundaries, not jq streams.  A
# second valid document, or framing garbage around one document, must never
# reach the CAS candidate or the persisted-state reader.
duplicate_state_documents=$(printf '%s\n%s\n' "${state}" "${state}")
if managed_component_state_validate_json "${duplicate_state_documents}"; then
  printf 'multiple component state documents unexpectedly accepted\n' >&2
  exit 1
fi
if managed_component_state_candidate "${duplicate_state_documents}" create "${direct_record}" >/dev/null 2>&1; then
  printf 'multiple component state documents unexpectedly reached candidate\n' >&2
  exit 1
fi
prefix_state_document=$(printf 'prefix\n%s\n' "${state}")
if managed_component_state_validate_json "${prefix_state_document}"; then
  printf 'component state prefix garbage unexpectedly accepted\n' >&2
  exit 1
fi
suffix_state_document=$(printf '%s\nsuffix\n' "${state}")
if managed_component_state_validate_json "${suffix_state_document}"; then
  printf 'component state suffix garbage unexpectedly accepted\n' >&2
  exit 1
fi
printf '%s\n%s\n' "${state}" "${state}" > "${SB_COMPONENT_STATE_FILE}"
if managed_component_state_json >/dev/null 2>&1; then
  printf 'multiple persisted component state documents unexpectedly accepted\n' >&2
  exit 1
fi
rm -f "${SB_COMPONENT_STATE_FILE}"
duplicate_record_documents=$(printf '%s\n%s\n' "${direct_record}" "${direct_record}")
if managed_component_state_validate_record "${duplicate_record_documents}"; then
  printf 'multiple component record documents unexpectedly accepted\n' >&2
  exit 1
fi
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

# TUIC outbound records keep the client-only relay choices separate from the
# inbound schema, while sharing typed TLS, QUIC, network and Dial Field
# handling.
tuic_outbound_record='{"id":"tuic-outbound-local","role":"outbound","type":"tuic","tag":"tuic-upstream","enabled":true,"route_rules":[],"config":{"server":"tuic.example","server_port":443,"uuid":"2dd61d93-75d8-4da4-ac0e-6aece7eac365","password":"tuic-password","congestion_control":"bbr","udp_relay_mode":"native","udp_over_stream":false,"zero_rtt_handshake":true,"heartbeat":"10s","network":["tcp","udp"],"tls":{"enabled":true,"server_name":"tuic.example","insecure":true},"idle_timeout":"30s","keep_alive_period":"10s","stream_receive_window":"64 MB","connection_receive_window":"128 MB","max_concurrent_streams":100,"initial_packet_size":1200,"disable_path_mtu_discovery":false,"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"domain_resolver":"dns-local","protect_path":"/usr/lib/sing-box/tuic-protect"}}'
managed_component_state_validate_record "${tuic_outbound_record}"
tuic_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${tuic_outbound_record}")
tuic_outbound_rendered=$(managed_component_render_json "${tuic_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "tuic" and
  .outbounds[0].tag == "tuic-upstream" and
  .outbounds[0].server == "tuic.example" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].uuid == "2dd61d93-75d8-4da4-ac0e-6aece7eac365" and
  .outbounds[0].congestion_control == "bbr" and
  .outbounds[0].udp_relay_mode == "native" and
  .outbounds[0].udp_over_stream == false and
  .outbounds[0].network == ["tcp","udp"] and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].initial_packet_size == 1200 and
  .outbounds[0].route_rules == null
' <<< "${tuic_outbound_rendered}" >/dev/null
tuic_string_network=$(jq -c '.config.network = "tcp" | .config.udp_relay_mode = "quic"' <<< "${tuic_outbound_record}")
managed_component_state_validate_record "${tuic_string_network}"
tuic_udp_over_stream=$(jq -c '.config |= (del(.udp_relay_mode) + {udp_over_stream:true})' <<< "${tuic_outbound_record}")
managed_component_state_validate_record "${tuic_udp_over_stream}"
tuic_udp_over_stream_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${tuic_udp_over_stream}")
tuic_udp_over_stream_rendered=$(managed_component_render_json "${tuic_udp_over_stream_state}")
jq -e '
  .outbounds[0].type == "tuic" and
  (.outbounds[0] | has("udp_relay_mode") | not) and
  .outbounds[0].udp_over_stream == true
' <<< "${tuic_udp_over_stream_rendered}" >/dev/null
tuic_relay_conflict=$(jq -c '.config.udp_over_stream = true' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_relay_conflict}"; then
  printf 'TUIC udp relay/udp-over-stream conflict unexpectedly accepted\n' >&2
  exit 1
fi
tuic_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_missing_tls}"; then
  printf 'TUIC outbound without TLS unexpectedly accepted\n' >&2
  exit 1
fi
tuic_disabled_tls=$(jq -c '.config.tls.enabled = false' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_disabled_tls}"; then
  printf 'TUIC outbound with disabled TLS unexpectedly accepted\n' >&2
  exit 1
fi
tuic_missing_server=$(jq -c '.config |= del(.server)' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_missing_server}"; then
  printf 'TUIC outbound without server unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_port=$(jq -c '.config.server_port = 65536' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_port}"; then
  printf 'TUIC outbound invalid port unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_uuid=$(jq -c '.config.uuid = "not-a-uuid"' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_uuid}"; then
  printf 'TUIC outbound invalid UUID unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_password=$(jq -c '.config.password = "tuic\u0001password"' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_password}"; then
  printf 'TUIC outbound control-character password unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_congestion=$(jq -c '.config.congestion_control = "reno"' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_congestion}"; then
  printf 'TUIC unsupported congestion control unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_relay=$(jq -c '.config.udp_relay_mode = "native+quic"' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_relay}"; then
  printf 'TUIC unsupported relay mode unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_network=$(jq -c '.config.network = ["icmp"]' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_network}"; then
  printf 'TUIC unsupported network unexpectedly accepted\n' >&2
  exit 1
fi
tuic_duplicate_network=$(jq -c '.config.network = ["udp","udp"]' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_duplicate_network}"; then
  printf 'TUIC duplicate network unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_quic=$(jq -c '.config.initial_packet_size = "1200"' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_quic}"; then
  printf 'TUIC invalid QUIC scalar unexpectedly accepted\n' >&2
  exit 1
fi
tuic_bad_heartbeat=$(jq -c '.config.heartbeat = 10' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_bad_heartbeat}"; then
  printf 'TUIC invalid heartbeat scalar unexpectedly accepted\n' >&2
  exit 1
fi
tuic_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${tuic_outbound_record}")
if managed_component_state_validate_record "${tuic_unknown_field}"; then
  printf 'TUIC deprecated field unexpectedly accepted\n' >&2
  exit 1
fi

# NaiveProxy outbound records keep the official libcronet client surface
# typed: UDP is supplied by the optional UDP-over-TCP adapter, QUIC has its
# own congestion/window fields, and outbound TLS accepts only the four
# documented Naive fields.  A QUIC client cannot use insecure concurrency.
naive_outbound_record='{"id":"naive-outbound-local","role":"outbound","type":"naive","tag":"naive-upstream","enabled":true,"route_rules":[],"config":{"server":"naive.example","server_port":443,"username":"naive-user","password":"naive-password","insecure_concurrency":0,"extra_headers":{"User-Agent":["sing-box-vps"],"X-Naive":"value"},"stream_receive_window":"128 MB","udp_over_tcp":{"enabled":true,"version":2},"quic":true,"quic_congestion_control":"bbr2","quic_session_receive_window":"15 MB","tls":{"enabled":true,"server_name":"naive.example","ech":{"enabled":false,"config_path":"/etc/sing-box/ech.bin"}},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"protect_path":"/usr/lib/sing-box/naive-protect"}}'
managed_component_state_validate_record "${naive_outbound_record}"
naive_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${naive_outbound_record}")
naive_outbound_rendered=$(managed_component_render_json "${naive_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "naive" and
  .outbounds[0].tag == "naive-upstream" and
  .outbounds[0].server == "naive.example" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].udp_over_tcp.enabled == true and
  .outbounds[0].udp_over_tcp.version == 2 and
  .outbounds[0].quic == true and
  .outbounds[0].quic_congestion_control == "bbr2" and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].tls.ech.enabled == false and
  .outbounds[0].route_rules == null
' <<< "${naive_outbound_rendered}" >/dev/null
naive_h2_record=$(jq -c '.config.quic = false | .config.insecure_concurrency = 2' <<< "${naive_outbound_record}")
managed_component_state_validate_record "${naive_h2_record}"
naive_default_uot=$(jq -c '.config.udp_over_tcp = true' <<< "${naive_h2_record}")
managed_component_state_validate_record "${naive_default_uot}"
naive_bad_quic_concurrency=$(jq -c '.config.quic = true | .config.insecure_concurrency = 2' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_bad_quic_concurrency}"; then
  printf 'Naive QUIC insecure concurrency unexpectedly accepted\n' >&2
  exit 1
fi
naive_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_missing_tls}"; then
  printf 'Naive outbound without TLS unexpectedly accepted\n' >&2
  exit 1
fi
naive_disabled_tls=$(jq -c '.config.tls.enabled = false' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_disabled_tls}"; then
  printf 'Naive outbound with disabled TLS unexpectedly accepted\n' >&2
  exit 1
fi
naive_unsupported_tls=$(jq -c '.config.tls.insecure = true' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_unsupported_tls}"; then
  printf 'Naive unsupported TLS field unexpectedly accepted\n' >&2
  exit 1
fi
naive_bad_uot=$(jq -c '.config.udp_over_tcp = {enabled:true,version:3}' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_bad_uot}"; then
  printf 'Naive unsupported UDP-over-TCP version unexpectedly accepted\n' >&2
  exit 1
fi
naive_bad_congestion=$(jq -c '.config.quic_congestion_control = "reno2"' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_bad_congestion}"; then
  printf 'Naive unsupported congestion control unexpectedly accepted\n' >&2
  exit 1
fi
naive_bad_headers=$(jq -c '.config.extra_headers["Bad Header"] = "value"' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_bad_headers}"; then
  printf 'Naive invalid extra header name unexpectedly accepted\n' >&2
  exit 1
fi
naive_bad_memory=$(jq -c '.config.stream_receive_window = -1' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_bad_memory}"; then
  printf 'Naive negative receive window unexpectedly accepted\n' >&2
  exit 1
fi
naive_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${naive_outbound_record}")
if managed_component_state_validate_record "${naive_unknown_field}"; then
  printf 'Naive deprecated field unexpectedly accepted\n' >&2
  exit 1
fi

# ShadowTLS outbound is the TCP wrapper client, distinct from the project's
# local outer-inbound + loopback-Mixed composite.  Its typed record therefore
# has only server/version/password/TLS plus shared Dial Fields and never
# claims a standalone UDP or share-link surface.
shadowtls_outbound_record='{"id":"shadowtls-outbound-local","role":"outbound","type":"shadowtls","tag":"shadowtls-upstream","enabled":true,"route_rules":[],"config":{"server":"shadowtls.example","server_port":443,"version":3,"password":"shadow-password","tls":{"enabled":true,"server_name":"shadowtls.example","insecure":true},"connect_timeout":"5s","network_strategy":"default","network_type":["ethernet"],"protect_path":"/usr/lib/sing-box/shadowtls-protect"}}'
managed_component_state_validate_record "${shadowtls_outbound_record}"
shadowtls_outbound_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${shadowtls_outbound_record}")
shadowtls_outbound_rendered=$(managed_component_render_json "${shadowtls_outbound_state}")
jq -e '
  (.outbounds | length == 1) and
  .outbounds[0].type == "shadowtls" and
  .outbounds[0].tag == "shadowtls-upstream" and
  .outbounds[0].server == "shadowtls.example" and
  .outbounds[0].server_port == 443 and
  .outbounds[0].version == 3 and
  .outbounds[0].password == "shadow-password" and
  .outbounds[0].tls.enabled == true and
  .outbounds[0].route_rules == null
' <<< "${shadowtls_outbound_rendered}" >/dev/null
shadowtls_default_version=$(jq -c '.config |= del(.version,.password)' <<< "${shadowtls_outbound_record}")
managed_component_state_validate_record "${shadowtls_default_version}"
shadowtls_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${shadowtls_outbound_record}")
if managed_component_state_validate_record "${shadowtls_missing_tls}"; then
  printf 'ShadowTLS outbound without TLS unexpectedly accepted\n' >&2
  exit 1
fi
shadowtls_disabled_tls=$(jq -c '.config.tls.enabled = false' <<< "${shadowtls_outbound_record}")
if managed_component_state_validate_record "${shadowtls_disabled_tls}"; then
  printf 'ShadowTLS outbound with disabled TLS unexpectedly accepted\n' >&2
  exit 1
fi
shadowtls_bad_version=$(jq -c '.config.version = 4' <<< "${shadowtls_outbound_record}")
if managed_component_state_validate_record "${shadowtls_bad_version}"; then
  printf 'ShadowTLS unsupported version unexpectedly accepted\n' >&2
  exit 1
fi
shadowtls_bad_network=$(jq -c '.config.network = ["tcp"]' <<< "${shadowtls_outbound_record}")
if managed_component_state_validate_record "${shadowtls_bad_network}"; then
  printf 'ShadowTLS outbound network field unexpectedly accepted\n' >&2
  exit 1
fi
shadowtls_bad_password=$(jq -c '.config.password = "shadow\u0001password"' <<< "${shadowtls_outbound_record}")
if managed_component_state_validate_record "${shadowtls_bad_password}"; then
  printf 'ShadowTLS control-character password unexpectedly accepted\n' >&2
  exit 1
fi
shadowtls_unknown_field=$(jq -c '.config |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${shadowtls_outbound_record}")
if managed_component_state_validate_record "${shadowtls_unknown_field}"; then
  printf 'ShadowTLS deprecated field unexpectedly accepted\n' >&2
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
if managed_component_state_validate_record "${unknown_config_field}"; then
  printf 'unexpected direct config field was accepted\n' >&2
  exit 1
fi
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

resolved_listener_config=$(jq -cn --argjson services "$(jq '.services' <<< "${namespace_rendered}")" \
  '{inbounds:[],services:$services,outbounds:[{type:"direct",tag:"direct"},{type:"block",tag:"block"}],route:{final:"direct",rules:[]}}')
resolved_listener_plan=$(managed_listener_plan_json <<< "${resolved_listener_config}")
jq -e 'length == 2 and
  all(.[]; .owner == "resolved-local" and .protocol == "resolved-service" and
    .address == "127.0.0.53" and .port == 53) and
  ([.[].transport] | sort) == ["tcp","udp"]' <<< "${resolved_listener_plan}" >/dev/null
validate_listener_plan_json <<< "${resolved_listener_plan}"

# Cloudflared's token/control-plane settings and both nested DialerOptions are
# typed independently.  The token is accepted for state validation but is
# still redacted from inventory/diagnose output; nested arbitrary JSON is not.
cloudflared_advanced_record=$(jq -c '.config = {
  token:"eyJ-test-token",ha_connections:4,protocol:"quic",post_quantum:true,
  edge_ip_version:4,datagram_version:"v3",grace_period:"30s",region:"fra01",
  control_dialer:{detour:"direct",bind_interface:"eth0",inet4_bind_address:"192.0.2.10",
    bind_address_no_port:true,protect_path:"/usr/lib/sing-box/protect",
    routing_mark:"0x30",reuse_addr:true,netns:"sbv-net",connect_timeout:"5s",
    tcp_fast_open:true,tcp_multi_path:true,disable_tcp_keep_alive:false,
    tcp_keep_alive:"5m",tcp_keep_alive_interval:"75s",udp_fragment:false,
    domain_resolver:{server:"dns-local",timeout:"5s",strategy:"prefer_ipv4",disable_cache:true,rewrite_ttl:60,client_subnet:"192.0.2.0/24"},
    network_strategy:"hybrid",network_type:["ethernet"],fallback_network_type:["wifi"],fallback_delay:"1s"},
  tunnel_dialer:{detour:"direct",connect_timeout:"10s",network_strategy:"fallback",network_type:"ethernet",fallback_delay:"2s"}
}' <<< '{"id":"cloudflared-local","role":"inbound","type":"cloudflared","tag":"cloudflared-local-in","enabled":true,"route_rules":[],"config":{"token":"placeholder"}}')
managed_component_state_validate_record "${cloudflared_advanced_record}"
cloudflared_bad_datagram=$(jq -c '.config.datagram_version = "v4"' <<< "${cloudflared_advanced_record}")
if managed_component_state_validate_record "${cloudflared_bad_datagram}"; then
  printf 'Cloudflared unsupported datagram version unexpectedly accepted\n' >&2
  exit 1
fi
cloudflared_bad_dialer=$(jq -c '.config.control_dialer |= (. + {domain_strategy:"prefer_ipv4"})' <<< "${cloudflared_advanced_record}")
if managed_component_state_validate_record "${cloudflared_bad_dialer}"; then
  printf 'Cloudflared deprecated dialer field unexpectedly accepted\n' >&2
  exit 1
fi
cloudflared_bad_network_type=$(jq -c '.config.tunnel_dialer.network_type = "satellite"' <<< "${cloudflared_advanced_record}")
if managed_component_state_validate_record "${cloudflared_bad_network_type}"; then
  printf 'Cloudflared invalid dialer network type unexpectedly accepted\n' >&2
  exit 1
fi
cloudflared_bad_edge=$(jq -c '.config.edge_ip_version = 5' <<< "${cloudflared_advanced_record}")
if managed_component_state_validate_record "${cloudflared_bad_edge}"; then
  printf 'Cloudflared invalid edge IP version unexpectedly accepted\n' >&2
  exit 1
fi

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
  (.data.supported | length) == 38 and
  .data.transparent_resources.status == "not_assessed" and
  .data.transparent_resources.service_active == false' <<< "${diagnose_json}" >/dev/null
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

# WireGuard is managed as a typed modern endpoint rather than as the removed
# outbound.  Exercise listable prefixes, exact 32-byte keys, peer/NAT fields,
# Dial Fields, rendering, and fail-closed malformed combinations.
wireguard_fixture_private_key='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
wireguard_fixture_public_key='bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo='
wireguard_endpoint_record=$(jq -cn \
  --arg private_key "${wireguard_fixture_private_key}" \
  --arg public_key "${wireguard_fixture_public_key}" \
  '{id:"endpoint-wireguard-typed",role:"endpoint",type:"wireguard",tag:"wg-typed",enabled:true,route_rules:[],config:{
    system:false,name:"wg-typed",mtu:1408,address:["10.0.0.2/32","fd00::2/128"],
    private_key:$private_key,listen_port:51820,udp_timeout:"5m",
    udp_mapping:"endpoint_independent",udp_filtering:"address_dependent",udp_nat_max:1024,
    workers:2,peers:[{address:"198.51.100.1",port:51820,public_key:$public_key,
      pre_shared_key:$private_key,allowed_ips:["0.0.0.0/0","::/0"],
      persistent_keepalive_interval:25,reserved:[1,2,3]}],
    connect_timeout:"5s",network_type:["ethernet"]}}')
managed_component_state_validate_record "${wireguard_endpoint_record}"
wireguard_typed_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${wireguard_endpoint_record}")
wireguard_typed_rendered=$(managed_component_render_json "${wireguard_typed_state}")
jq -e --arg private_key "${wireguard_fixture_private_key}" --arg public_key "${wireguard_fixture_public_key}" '
  (.endpoints | length == 1) and
  .endpoints[0].type == "wireguard" and
  .endpoints[0].tag == "wg-typed" and
  .endpoints[0].private_key == $private_key and
  .endpoints[0].address == ["10.0.0.2/32","fd00::2/128"] and
  .endpoints[0].peers[0].public_key == $public_key and
  .endpoints[0].peers[0].allowed_ips == ["0.0.0.0/0","::/0"] and
  .endpoints[0].peers[0].reserved == [1,2,3] and
  .endpoints[0].udp_mapping == "endpoint_independent" and
  .endpoints[0].udp_filtering == "address_dependent"
' <<< "${wireguard_typed_rendered}" >/dev/null
wireguard_scalar_record=$(jq -c '.config.address = "10.0.0.2/32" | .config.peers[0].allowed_ips = "0.0.0.0/0"' <<< "${wireguard_endpoint_record}")
managed_component_state_validate_record "${wireguard_scalar_record}"
wireguard_bad_key=$(jq -c '.config.private_key = "not-a-wireguard-key"' <<< "${wireguard_endpoint_record}")
if managed_component_state_validate_record "${wireguard_bad_key}"; then
  printf 'WireGuard malformed private key unexpectedly accepted\n' >&2
  exit 1
fi
wireguard_bad_prefix=$(jq -c '.config.address[0] = "10.0.0.2/33"' <<< "${wireguard_endpoint_record}")
if managed_component_state_validate_record "${wireguard_bad_prefix}"; then
  printf 'WireGuard invalid address prefix unexpectedly accepted\n' >&2
  exit 1
fi
wireguard_missing_allowed_ips=$(jq -c '.config.peers[0] |= del(.allowed_ips)' <<< "${wireguard_endpoint_record}")
if managed_component_state_validate_record "${wireguard_missing_allowed_ips}"; then
  printf 'WireGuard peer without allowed IPs unexpectedly accepted\n' >&2
  exit 1
fi
wireguard_bad_reserved=$(jq -c '.config.peers[0].reserved = [1,2]' <<< "${wireguard_endpoint_record}")
if managed_component_state_validate_record "${wireguard_bad_reserved}"; then
  printf 'WireGuard invalid reserved tuple unexpectedly accepted\n' >&2
  exit 1
fi
wireguard_bad_nat=$(jq -c '.config.udp_mapping = "symmetric"' <<< "${wireguard_endpoint_record}")
if managed_component_state_validate_record "${wireguard_bad_nat}"; then
  printf 'WireGuard invalid UDP NAT behavior unexpectedly accepted\n' >&2
  exit 1
fi
wireguard_unknown_field=$(jq -c '.config.domain_strategy = "prefer_ipv4"' <<< "${wireguard_endpoint_record}")
if managed_component_state_validate_record "${wireguard_unknown_field}"; then
  printf 'WireGuard deprecated field unexpectedly accepted\n' >&2
  exit 1
fi

# Tailscale endpoint options combine a persistent control-plane state
# directory with route advertisement, relay pinning and optional SSH service.
# These are typed state/render checks only: no Tailscale login or peer data
# plane is attempted by this contract test.
tailscale_endpoint_record=$(jq -cn '{id:"endpoint-tailscale-typed",role:"endpoint",type:"tailscale",tag:"ts-typed",enabled:true,route_rules:[],config:{
  state_directory:"/var/lib/tailscale",auth_key:"tskey-auth-placeholder",control_url:"https://control.example",
  ephemeral:false,hostname:"sbv-node",accept_routes:true,advertise_routes:["10.20.0.0/24"],
  advertise_tags:["tag:prod"],listen_port:41641,relay_server_port:3478,
  relay_server_static_endpoints:["198.51.100.2:3478"],system_interface:false,
  system_interface_name:"tailscale0",system_interface_mtu:1280,udp_timeout:"5m",
  ssh_server:{enabled:true,disable_pty:false,disable_sftp:true,disable_forwarding:false},
  taildrop_directory:"/var/lib/tailscale/taildrop",connect_timeout:"5s",
  network_strategy:"default",network_type:["ethernet"]}}')
managed_component_state_validate_record "${tailscale_endpoint_record}"
tailscale_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${tailscale_endpoint_record}")
tailscale_rendered=$(managed_component_render_json "${tailscale_state}")
jq -e '
  (.endpoints | length == 1) and .endpoints[0].type == "tailscale" and
  .endpoints[0].tag == "ts-typed" and .endpoints[0].advertise_routes == ["10.20.0.0/24"] and
  .endpoints[0].relay_server_static_endpoints == ["198.51.100.2:3478"] and
  .endpoints[0].ssh_server.enabled == true and .endpoints[0].network_type == ["ethernet"]
' <<< "${tailscale_rendered}" >/dev/null
tailscale_default_route=$(jq -c '.config.advertise_routes=["0.0.0.0/0"]' <<< "${tailscale_endpoint_record}")
if managed_component_state_validate_record "${tailscale_default_route}"; then
  printf 'Tailscale default advertise route unexpectedly accepted\n' >&2
  exit 1
fi
tailscale_exit_route_conflict=$(jq -c '.config.exit_node="100.64.0.1" | .config.advertise_exit_node=true' <<< "${tailscale_endpoint_record}")
if managed_component_state_validate_record "${tailscale_exit_route_conflict}"; then
  printf 'Tailscale exit-node/advertise-exit conflict unexpectedly accepted\n' >&2
  exit 1
fi
tailscale_bad_ssh=$(jq -c '.config.ssh_server={enabled:true,unexpected:true}' <<< "${tailscale_endpoint_record}")
if managed_component_state_validate_record "${tailscale_bad_ssh}"; then
  printf 'Tailscale unknown SSH field unexpectedly accepted\n' >&2
  exit 1
fi

# OpenConnect is a client-only endpoint.  Keep the server/flavor/token/mobile
# and TLS material forms in the managed state while making authentication
# requirements and mutually-exclusive material sources explicit.
openconnect_endpoint_record=$(jq -cn '{id:"endpoint-openconnect-typed",role:"endpoint",type:"openconnect",tag:"oc-typed",enabled:true,route_rules:[],config:{
  server:"https://vpn.example.com",flavor:"anyconnect",username:"alice",password:"password",
  token:{mode:"totp",secret:"JBSWY3DPEHPK3PXP"},mobile:{platform_version:"17.0",device_type:"iphone",device_unique_id:"fixture-device"},
  tncc:{device_id:"tncc-device",machine_identification_enabled:true,certificates:[{certificate:"-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----"}]},
  tls:{server_name:"vpn.example.com",certificate_authority_path:"/etc/sbv/ca.pem",client_certificate_path:"/etc/sbv/client.pem",client_key_path:"/etc/sbv/client.key"},
  form_entries:[{form_id:"login",submission_key:"username",name:"user",value:"alice",promote:false}],
  no_udp:false,dtls_local_port:443,compression_mode:"stateless",mtu:1400,base_mtu:1500,udp_timeout:"5m",
  udp_mapping:"endpoint_independent",udp_filtering:"address_dependent",udp_nat_max:1024,connect_timeout:"5s",
  network_strategy:"default",network_type:["ethernet"]}}')
managed_component_state_validate_record "${openconnect_endpoint_record}"
openconnect_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${openconnect_endpoint_record}")
openconnect_rendered=$(managed_component_render_json "${openconnect_state}")
jq -e '
  (.endpoints | length == 1) and .endpoints[0].type == "openconnect" and
  .endpoints[0].server == "https://vpn.example.com" and
  .endpoints[0].token.mode == "totp" and
  .endpoints[0].mobile.device_unique_id == "fixture-device" and
  .endpoints[0].tls.certificate_authority_path == "/etc/sbv/ca.pem" and
  .endpoints[0].form_entries[0].promote == false
' <<< "${openconnect_rendered}" >/dev/null
openconnect_bad_flavor=$(jq -c '.config.flavor = "unsupported"' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_flavor}"; then
  printf 'OpenConnect unknown flavor unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_tls=$(jq -c '.config.tls = {certificate_authority:"inline",certificate_authority_path:"/tmp/ca.pem"}' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_tls}"; then
  printf 'OpenConnect conflicting TLS material unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_token=$(jq -c '.config.token = {mode:"hotp",secret:"inline",secret_path:"/tmp/token"}' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_token}"; then
  printf 'OpenConnect conflicting token material unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_mobile=$(jq -c '.config.mobile.device_unique_id = ""' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_mobile}"; then
  printf 'OpenConnect incomplete mobile identity unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_form=$(jq -c '.config.form_entries=[{name:"user",value:"alice"}]' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_form}"; then
  printf 'OpenConnect incomplete form entry unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_client_material=$(jq -c '.config.tls |= (del(.client_key_path) + {client_certificate_path:"/etc/sbv/client.pem"})' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_client_material}"; then
  printf 'OpenConnect client certificate without key unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_tncc=$(jq -c '.config.tncc.wrapper_path="/usr/libexec/tncc"' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_tncc}"; then
  printf 'OpenConnect TNCC wrapper/material conflict unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_form_promote=$(jq -c '.config.form_entries[0].promote=true' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_form_promote}"; then
  printf 'OpenConnect form value/promote conflict unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_bad_timeout=$(jq -c '.config.udp_timeout=5' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_bad_timeout}"; then
  printf 'OpenConnect numeric duration unexpectedly accepted\n' >&2
  exit 1
fi
openconnect_unknown_field=$(jq -c '.config.on_demand=true' <<< "${openconnect_endpoint_record}")
if managed_component_state_validate_record "${openconnect_unknown_field}"; then
  printf 'OpenConnect unknown field unexpectedly accepted\n' >&2
  exit 1
fi

# OpenVPN client and server records exercise both the TLS and deprecated
# static-key unions.  These checks stop at state/render boundaries; external
# certificate material and a peer control plane are intentionally not mocked.
openvpn_client_tls_record=$(jq -cn '{id:"endpoint-openvpn-client-tls",role:"endpoint",type:"openvpn-client",tag:"ovpn-client-tls",enabled:true,route_rules:[],config:{
  mode:"tls",server:"vpn.example.com",server_port:1194,network:"udp",address:["10.30.0.2/24","fd30::2/64"],
  username:"alice",password:"password",tls:{certificate_path:"/etc/sbv/ca.pem",server_name:"vpn.example.com",
    peer_fingerprint:["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],control_wrap:{type:"tls_auth",key_path:"/etc/sbv/ta.key",direction:"client"}},
  routes:["10.40.0.0/16"],redirect_gateway:false,udp_timeout:"5m",network_type:["ethernet"]}}')
managed_component_state_validate_record "${openvpn_client_tls_record}"
openvpn_client_tls_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${openvpn_client_tls_record}")
openvpn_client_tls_rendered=$(managed_component_render_json "${openvpn_client_tls_state}")
jq -e '
  (.endpoints | length == 1) and .endpoints[0].type == "openvpn-client" and
  .endpoints[0].tls.control_wrap.type == "tls_auth" and
  .endpoints[0].tls.peer_fingerprint[0] == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" and
  .endpoints[0].routes == ["10.40.0.0/16"]
' <<< "${openvpn_client_tls_rendered}" >/dev/null
openvpn_client_static_record=$(jq -c '.id="endpoint-openvpn-client-static" | .tag="ovpn-client-static" | .config |= (del(.tls,.username,.password,.routes) + {mode:"static_key",server:"198.51.100.5",server_port:1194,address:"10.31.0.2/30",peer_address:"10.31.0.1",static_key_path:"/etc/sbv/static.key",key_direction:"client",cipher:"AES-256-CBC"})' <<< "${openvpn_client_tls_record}")
managed_component_state_validate_record "${openvpn_client_static_record}"
openvpn_client_both_remotes=$(jq -c '.config.servers=[{server:"backup.example.com",server_port:1194}]' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_both_remotes}"; then
  printf 'OpenVPN client server/servers conflict unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_client_missing_tls=$(jq -c '.config |= del(.tls)' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_missing_tls}"; then
  printf 'OpenVPN TLS client without tls options unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_client_bad_fingerprint=$(jq -c '.config.tls.peer_fingerprint=["not-a-sha256-fingerprint"]' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_bad_fingerprint}"; then
  printf 'OpenVPN malformed peer fingerprint unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_client_bad_mss=$(jq -c '.config.mss_fix_mode="mtu"' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_bad_mss}"; then
  printf 'OpenVPN MSS mode without mss_fix unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_client_bad_fragment=$(jq -c '.config.network="tcp" | .config.fragment=1200' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_bad_fragment}"; then
  printf 'OpenVPN TCP fragment unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_client_bad_replay=$(jq -c '.config.replay_window=65537' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_bad_replay}"; then
  printf 'OpenVPN replay window overflow unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_client_bad_compression=$(jq -c '.config.allow_compression="no" | .config.compression="lz4"' <<< "${openvpn_client_tls_record}")
if managed_component_state_validate_record "${openvpn_client_bad_compression}"; then
  printf 'OpenVPN compression policy conflict unexpectedly accepted\n' >&2
  exit 1
fi

openvpn_server_tls_record=$(jq -cn '{id:"endpoint-openvpn-server-tls",role:"endpoint",type:"openvpn-server",tag:"ovpn-server-tls",enabled:true,route_rules:[],config:{
  mode:"tls",listen:"0.0.0.0",listen_port:1194,network:"udp",address:["10.50.0.1/24","fd50::1/64"],max_clients:128,
  users:[{username:"alice",password:"password"}],tls:{certificate_path:"/etc/sbv/server.pem",key_path:"/etc/sbv/server.key",
    verify_client_certificate:"optional",client_certificate_path:"/etc/sbv/ca.pem",control_wrap:{type:"tls_crypt_v2",key_path:"/etc/sbv/ta.key",force_cookie:true}},
  push:{routes:["10.60.0.0/16"],dns:["10.50.0.1"],dns_servers:[{priority:10,addresses:["1.1.1.1","[2001:4860:4860::8888]:853"],transport:"dot",sni:"cloudflare-dns.com"}]},
  udp_mapping:"endpoint_independent",udp_filtering:"address_dependent"}}')
managed_component_state_validate_record "${openvpn_server_tls_record}"
openvpn_server_tls_state=$(managed_component_state_candidate "$(managed_component_state_default_json)" create "${openvpn_server_tls_record}")
openvpn_server_tls_rendered=$(managed_component_render_json "${openvpn_server_tls_state}")
jq -e '
  (.endpoints | length == 1) and .endpoints[0].type == "openvpn-server" and
  .endpoints[0].tls.control_wrap.force_cookie == true and
  .endpoints[0].push.dns == ["10.50.0.1"] and
  .endpoints[0].push.dns_servers[0].addresses[1] == "[2001:4860:4860::8888]:853"
' <<< "${openvpn_server_tls_rendered}" >/dev/null
openvpn_server_static_record=$(jq -c '.id="endpoint-openvpn-server-static" | .tag="ovpn-server-static" | .config |= (del(.tls,.users,.push) + {mode:"static_key",network:"tcp",address:"10.51.0.1/30",peer_address:"10.51.0.2",max_clients:1,static_key_path:"/etc/sbv/static.key",key_direction:"server",cipher:"AES-256-CBC"})' <<< "${openvpn_server_tls_record}")
managed_component_state_validate_record "${openvpn_server_static_record}"
openvpn_server_missing_address=$(jq -c '.config.address=[]' <<< "${openvpn_server_tls_record}")
if managed_component_state_validate_record "${openvpn_server_missing_address}"; then
  printf 'OpenVPN server without address pool unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_server_bad_network=$(jq -c '.config.network="tcp4"' <<< "${openvpn_server_tls_record}")
if managed_component_state_validate_record "${openvpn_server_bad_network}"; then
  printf 'OpenVPN server invalid network unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_server_static_tls=$(jq -c '.config |= (. + {mode:"static_key",static_key_path:"/etc/sbv/static.key"})' <<< "${openvpn_server_tls_record}")
if managed_component_state_validate_record "${openvpn_server_static_tls}"; then
  printf 'OpenVPN server static/TLS conflict unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_server_bad_dns=$(jq -c '.config.push.dns=["not-an-ip"]' <<< "${openvpn_server_tls_record}")
if managed_component_state_validate_record "${openvpn_server_bad_dns}"; then
  printf 'OpenVPN server malformed pushed DNS unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_server_bad_mss=$(jq -c '.config.mss_fix_mode="fixed"' <<< "${openvpn_server_tls_record}")
if managed_component_state_validate_record "${openvpn_server_bad_mss}"; then
  printf 'OpenVPN server MSS mode without mss_fix unexpectedly accepted\n' >&2
  exit 1
fi
openvpn_server_bad_replay=$(jq -c '.config.replay_window=65537' <<< "${openvpn_server_tls_record}")
if managed_component_state_validate_record "${openvpn_server_bad_replay}"; then
  printf 'OpenVPN server replay window overflow unexpectedly accepted\n' >&2
  exit 1
fi

# Take over registered advanced objects from a live configuration without
# dropping object fields or route rules.  The operation is idempotent for
# already-owned objects and assigns a deterministic ID to a newly discovered
# endpoint.
live_without_selector_rules=$(jq -c '(.components[] | select(.id == "selector-local") | .route_rules) = []' \
  "${SB_COMPONENT_STATE_FILE}")
managed_component_write_state "${live_without_selector_rules}"
generate_config
wireguard_live=$(jq -cn \
  --arg private_key "${wireguard_fixture_private_key}" \
  --arg public_key "${wireguard_fixture_public_key}" \
  '{type:"wireguard",tag:"wg-live",system:true,address:["10.0.0.2/32"],private_key:$private_key,peers:[{address:"198.51.100.1",port:51820,public_key:$public_key,allowed_ips:["0.0.0.0/0"]}]}')
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
jq -e --arg private_key "${wireguard_fixture_private_key}" 'any(.components[]; .id == "endpoint-wireguard-wg-live" and
  .type == "wireguard" and .config.private_key == $private_key)' \
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
jq -e --arg private_key "${wireguard_fixture_private_key}" 'any(.endpoints[]; .tag == "wg-live" and .private_key == $private_key)' \
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
jq -e --arg private_key "${wireguard_fixture_private_key}" '.ok == true and .data.sensitive == true and
  .data.component.config.private_key == $private_key' <<< "${export_takeover_json}" >/dev/null

# Protocol regeneration must not silently discard an endpoint that is outside
# the managed registry. The live inventory gate runs before resource or
# config publication, so the state/config match check rejects the candidate
# before the generator can publish a partial projection.
state_before_unknown_endpoint=$(cat "${SB_COMPONENT_STATE_FILE}")
config_before_unknown_endpoint=$(cat "${SINGBOX_CONFIG_FILE}")
jq '.endpoints += [{type:"future-endpoint",tag:"future-endpoint"}]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_state_matches_live_config "${SINGBOX_CONFIG_FILE}"; then
  printf 'unknown endpoint inventory unexpectedly matched managed state\n' >&2
  exit 1
fi
[[ "$(cat "${SB_COMPONENT_STATE_FILE}")" == "${state_before_unknown_endpoint}" ]]
[[ "$(cat "${SINGBOX_CONFIG_FILE}")" != "${config_before_unknown_endpoint}" ]]
printf '%s\n' "${config_before_unknown_endpoint}" > "${SINGBOX_CONFIG_FILE}"

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

# Fixed ACME provider tags are generator-owned too.  A live object that keeps a
# fixed tag but changes its type must fail closed instead of being skipped from
# takeover and later replaced by a generated provider.
config_before_bad_fixed_provider=$(cat "${SINGBOX_CONFIG_FILE}")
jq '.certificate_providers += [{type:"future-provider",tag:"hy2-cert-provider",domain:["future.example"]}]' \
  "${SINGBOX_CONFIG_FILE}" > "${SINGBOX_CONFIG_FILE}.next"
mv -f "${SINGBOX_CONFIG_FILE}.next" "${SINGBOX_CONFIG_FILE}"
if managed_component_live_takeover_records_json "$(managed_component_state_json)" >/dev/null 2>&1; then
  printf 'fixed ACME provider tag with unknown type unexpectedly passed takeover\n' >&2
  exit 1
fi
printf '%s\n' "${config_before_bad_fixed_provider}" > "${SINGBOX_CONFIG_FILE}"

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
if managed_component_live_config_root_fields_supported "${SINGBOX_CONFIG_FILE}"; then
  printf 'unknown top-level component namespace unexpectedly matched managed state\n' >&2
  exit 1
fi
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
