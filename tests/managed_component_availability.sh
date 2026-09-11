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
  length == 30 and
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
  length == 30 and
  all(.[]; .implemented == true and .available == null and
    .validated.status == "not_assessed" and (.environment.status | type) == "string")
' <<< "${registry}" >/dev/null

printf '%s\n' 'managed component availability checks passed'
