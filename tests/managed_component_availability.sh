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
printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == version ]] && printf "sing-box version 1.14.0\\n"' \
  > "${TMP_DIR}/bin/sing-box"
chmod 0755 "${TMP_DIR}/bin/sing-box"
with_core=$(component_registry_environment_json)
jq -e '
  any(.[]; .state_id == "direct-inbound" and .status == "available" and
    .core.status == "available" and .core.version == "1.14.0") and
  any(.[]; .state_id == "cloudflared-inbound" and
    .status == "unavailable" and .reason == "cloudflared_missing") and
  any(.[]; .state_id == "openconnect-endpoint" and
    .status == "not_assessed" and .reason == "external_auth_required") and
  all(.[]; .static_availability != null)
' <<< "${with_core}" >/dev/null

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
