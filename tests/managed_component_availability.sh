#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

# A missing core is an environment result, not a reason to hide the static
# registry. Every component reports the same bounded, credential-free cause.
without_core=$(component_registry_environment_json)
jq -e '
  length == 38 and
  all(.[]; .status == "unavailable" and .core.status == "unavailable" and
    .core.version == null and .dependencies[0].name == "sing_box_binary")
' <<< "${without_core}" >/dev/null

# The probe uses the installed core version only for the minimum-version gate;
# it does not claim that a passing version check proves external auth or a data
# plane. A fake version command keeps this test local and deterministic.
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "${1:-}" == version ]] && printf "%s\\n" "sing-box version 1.14.0" "Tags: with_cloudflared,with_openconnect,with_openvpn,with_quic,with_tailscale,with_wireguard"' \
  > "${TMP_DIR}/bin/sing-box"
chmod 0755 "${TMP_DIR}/bin/sing-box"
with_core=$(component_registry_environment_json)
jq -e 'any(.[]; .state_id == "route-rule-set-remote" and
  .status == "available" and .core.version == "1.14.0")' <<< "${with_core}" >/dev/null
jq -e '
  any(.[]; .state_id == "direct-inbound" and .status == "available" and
    .core.status == "available" and .core.version == "1.14.0") and
  any(.[]; .state_id == "direct-inbound" and
    .core.build_tags.status == "available" and
    (.core.build_tags.values | index("with_quic")) != null) and
  any(.[]; .state_id == "hysteria-outbound" and .status == "available" and
    any(.dependencies[]; .name == "build_tag_with_quic" and .status == "available")) and
  any(.[]; .state_id == "cloudflared-inbound" and
    .status == "unavailable" and .reason == "cloudflared_missing") and
  any(.[]; .state_id == "openconnect-endpoint" and
    .status == "not_assessed" and .reason == "external_auth_required") and
  all(.[]; .static_availability != null)
' <<< "${with_core}" >/dev/null

# Registry availability is refined per persisted component configuration. A
# system WireGuard endpoint needs privilege but no TUN device, while an
# internal endpoint needs the gVisor build tag. Bridge uses host privileges
# without claiming that it creates /dev/net/tun.
wireguard_base=$(jq -ce 'first(.[] | select(.state_id == "wireguard-endpoint").environment)' \
  <<< "$(component_registry_json)")
wireguard_system_record='{"id":"wg-system","role":"endpoint","type":"wireguard","tag":"wg-system","enabled":true,"route_rules":[],"config":{"system":true}}'
wireguard_internal_record='{"id":"wg-internal","role":"endpoint","type":"wireguard","tag":"wg-internal","enabled":true,"route_rules":[],"config":{"system":false}}'
wireguard_system_environment=$(managed_component_instance_environment_json \
  "${wireguard_system_record}" "${wireguard_base}")
wireguard_internal_environment=$(managed_component_instance_environment_json \
  "${wireguard_internal_record}" "${wireguard_base}")
jq -e '
  .status == "available" and .requirements.system_mode == "system" and
  .requirements.requires_root == true and .requirements.requires_tun_device == false and
  any(.dependencies[]; .name == "root" and .status == "available")
' <<< "${wireguard_system_environment}" >/dev/null
jq -e '
  .status == "unavailable" and .reason == "build_tag_missing_with_gvisor" and
  .requirements.system_mode == "internal" and .requirements.requires_gvisor == true and
  any(.dependencies[]; .name == "build_tag_with_gvisor" and .status == "unavailable")
' <<< "${wireguard_internal_environment}" >/dev/null

bridge_base=$(jq -ce 'first(.[] | select(.state_id == "bridge-outbound").environment)' \
  <<< "$(component_registry_json)")
bridge_record='{"id":"bridge-local","role":"outbound","type":"bridge","tag":"bridge-local","enabled":true,"route_rules":[],"config":{}}'
bridge_environment=$(managed_component_instance_environment_json "${bridge_record}" "${bridge_base}")
jq -e '
  .status == "available" and .requirements.requires_root == true and
  .requirements.requires_tun_device == false and .requirements.requires_gvisor == false and
  any(.dependencies[]; .name == "root" and .status == "available")
' <<< "${bridge_environment}" >/dev/null

tun_base=$(jq -ce 'first(.[] | select(.state_id == "tun-inbound").environment)' \
  <<< "$(component_registry_json)")
tun_record='{"id":"tun-local","role":"inbound","type":"tun","tag":"tun-local","enabled":true,"route_rules":[],"config":{}}'
tun_environment=$(managed_component_instance_environment_json "${tun_record}" "${tun_base}")
if [[ -c /dev/net/tun ]]; then
  jq -e '.status == "available" and .requirements.requires_tun_device == true' \
    <<< "${tun_environment}" >/dev/null
else
  jq -e '.status == "unavailable" and .reason == "tun_device_missing" and
    .requirements.requires_tun_device == true' <<< "${tun_environment}" >/dev/null
fi

# The component-list contract carries both the type-level environment and a
# config-derived instance_environment projection for each persisted record.
instance_state='{"schema":"1","revision":1,"components":[
  {"id":"wg-system","role":"endpoint","type":"wireguard","tag":"wg-system","enabled":true,"route_rules":[],"config":{"system":true}},
  {"id":"wg-internal","role":"endpoint","type":"wireguard","tag":"wg-internal","enabled":true,"route_rules":[],"config":{"system":false}},
  {"id":"bridge-local","role":"outbound","type":"bridge","tag":"bridge-local","enabled":true,"route_rules":[],"config":{}}
]}'
original_component_state_json=$(declare -f managed_component_state_json)
managed_component_state_json() {
  printf '%s\n' "${instance_state}"
}
instance_inventory=$(managed_component_inventory_json)
eval "${original_component_state_json}"
jq -e '
  (.components | length) == 3 and
  (.components[] | select(.id == "wg-system") |
    .environment.status == "available" and
    .instance_environment.requirements.system_mode == "system" and
    .instance_environment.requirements.requires_tun_device == false) and
  (.components[] | select(.id == "wg-internal") |
    .instance_environment.status == "unavailable" and
    .instance_environment.reason == "build_tag_missing_with_gvisor") and
  (.components[] | select(.id == "bridge-local") |
    .instance_environment.requirements.requires_root == true and
    .instance_environment.requirements.requires_tun_device == false)
' <<< "${instance_inventory}" >/dev/null

# A reported tag set is authoritative for the build gate.  A QUIC component
# must not be presented as available when the binary is otherwise new enough
# but was built without with_quic.
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "${1:-}" == version ]] && printf "%s\\n" "sing-box version 1.14.0" "Tags: with_openconnect"' \
  > "${TMP_DIR}/bin/sing-box"
chmod 0755 "${TMP_DIR}/bin/sing-box"
missing_tag=$(component_registry_environment_json)
jq -e '
  any(.[]; .state_id == "hysteria-outbound" and
    .status == "unavailable" and .reason == "build_tag_missing_with_quic" and
    any(.dependencies[]; .name == "build_tag_with_quic" and .status == "unavailable"))
' <<< "${missing_tag}" >/dev/null
single_missing_tag=$(component_registry_environment_probe hysteria-outbound outbound hysteria 1.13.0 with_quic)
jq -e '
  .status == "unavailable" and .reason == "build_tag_missing_with_quic" and
  any(.dependencies[]; .name == "build_tag_with_quic" and .status == "unavailable")
' <<< "${single_missing_tag}" >/dev/null

# Wrapper binaries that omit Tags are not treated as proof of a conditional
# build.  The result remains not_assessed and explains the missing observation.
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "${1:-}" == version ]] && printf "sing-box version 1.14.0\\n"' \
  > "${TMP_DIR}/bin/sing-box"
chmod 0755 "${TMP_DIR}/bin/sing-box"
unreported_tags=$(component_registry_environment_json)
jq -e '
  any(.[]; .state_id == "wireguard-endpoint" and
    .status == "not_assessed" and .reason == "build_tags_not_reported" and
    .core.build_tags.status == "not_assessed")
' <<< "${unreported_tags}" >/dev/null

# An invalid version observation cannot be used to assess build tags. Keep the
# two observations separate and do not report the tag probe as binary missing.
printf '%s\n' '#!/usr/bin/env bash' \
  '[[ "${1:-}" == version ]] && printf "sing-box version development\\n"' \
  > "${TMP_DIR}/bin/sing-box"
chmod 0755 "${TMP_DIR}/bin/sing-box"
invalid_version=$(component_registry_environment_json)
jq -e '
  any(.[]; .state_id == "wireguard-endpoint" and
    .status == "unavailable" and .reason == "sing_box_version_unavailable" and
    .core.build_tags.status == "not_assessed" and
    .core.build_tags.reason == "sing_box_version_unavailable")
' <<< "${invalid_version}" >/dev/null

# A component's minimum core is enforced independently from its static build
# availability. This must not silently downgrade to a syntactically valid
# configuration on an older target.
printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == version ]] && printf "sing-box version 1.13.0\\n"' \
  > "${TMP_DIR}/bin/sing-box"
chmod 0755 "${TMP_DIR}/bin/sing-box"
old_core=$(component_registry_environment_json)
jq -e '
  any(.[]; .state_id == "cloudflared-inbound" and
    .status == "unavailable" and .reason == "sing_box_version_too_old" and
    .core.version == "1.13.0")
' <<< "${old_core}" >/dev/null

# The public registry keeps the three dimensions separate: static build
# condition, runtime environment observation, and target-core validation.
registry=$(component_registry_json)
jq -e '
  length == 38 and
  all(.[]; .implemented == true and .available == null and
    .validated.status == "not_assessed" and (.environment.status | type) == "string")
' <<< "${registry}" >/dev/null

resolved_environment=$(jq -ce 'first(.[] | select(.state_id == "resolved-service").environment)' \
  <<< "${registry}")
if [[ "$(uname -s)" != Linux ]]; then
  jq -e '.status == "unavailable" and
    any(.dependencies[]; .name == "platform" and .reason == "resolved_linux_only")' \
    <<< "${resolved_environment}" >/dev/null
elif [[ -S /run/dbus/system_bus_socket || -S /var/run/dbus/system_bus_socket ]]; then
  jq -e '.status == "available" and
    any(.dependencies[]; .name == "dbus_system_bus" and .status == "available")' \
    <<< "${resolved_environment}" >/dev/null
else
  jq -e '.status == "unavailable" and
    any(.dependencies[]; .name == "dbus_system_bus" and .status == "unavailable" and
      .reason == "dbus_system_bus_missing")' <<< "${resolved_environment}" >/dev/null
fi

printf '%s\n' 'managed component availability checks passed'
