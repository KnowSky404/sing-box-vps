#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
fail() { printf 'routing diagnostic independence: %s\n' "$*" >&2; exit 1; }
printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[],"final":"direct"}}' > "${SINGBOX_CONFIG_FILE}"
routing_policy_read_json > "${TMP_DIR}/initial-policy.json"
cp -- "${TMP_DIR}/initial-policy.json" "${SB_ROUTING_POLICY_FILE}"
printf 'WARP_ROUTE_MODE=selective\nWARP_ENABLED=n\n' > "${SB_WARP_ROUTE_SETTINGS_FILE}"
routing_nodes_json() { printf '[]\n'; }
# Persist only fixture settings. No provider, generator or service is invoked.
routing_policy_apply() {
  local expected
  expected=$(jq -r '.fingerprint' "$1")
  [[ "${expected}" == "$(routing_state_fingerprint)" ]] || {
    printf 'rejected\n' >> "${TMP_DIR}/cas-rejections"
    return 91
  }
  jq -c . "$1" >> "${TMP_DIR}/applied.jsonl"
  jq '.policy' "$1" > "${SB_ROUTING_POLICY_FILE}"
}
media_check_menu() {
  mkdir -p -- "${SB_MEDIA_CHECK_DIR}"
  printf '#!/usr/bin/env bash\nprintf fixture\n' > "${SB_MEDIA_CHECK_SCRIPT}"
  printf '# previous fixture backend\n' > "${SB_MEDIA_CHECK_SCRIPT}.bak"
}
# The first switch is already committed before diagnostics run. A subsequent
# switch receives a fresh snapshot including the diagnostic cache bytes.
routing_management_menu > "${TMP_DIR}/menu.log" 2>&1 <<'INPUT'
1
4
1
0
INPUT
[[ -f "${TMP_DIR}/applied.jsonl" ]] || fail 'switches were not applied'
jq -s -e 'length==2 and .[0].policy.server.block_cn and (.[1].policy.server.block_cn|not) and
  (.[0].warp.enabled|not) and (.[1].warp.enabled|not) and .[0].fingerprint!=.[1].fingerprint' \
  "${TMP_DIR}/applied.jsonl" >/dev/null
[[ ! -e "${TMP_DIR}/cas-rejections" ]]
jq -e '(.server.block_cn|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
! grep -Eq '草稿|待应用' "${TMP_DIR}/menu.log"

# Both transaction fingerprints still observe the backend cache. Immediate UI
# settings must not weaken the underlying external-state/concurrency boundary.
all_before=$(routing_state_fingerprint)
external_before=$(routing_state_fingerprint external)
printf '# backend updated\n' >> "${SB_MEDIA_CHECK_SCRIPT}"
[[ "$(routing_state_fingerprint)" != "${all_before}" &&
   "$(routing_state_fingerprint external)" != "${external_before}" ]]

# A concurrent write after a setting snapshot cannot be legitimized by merely
# refreshing its fingerprint. Rejection discards the failed requested edit.
current="${TMP_DIR}/current.json"
routing_draft_create "${current}"
printf 'operator-owned state\n' > "${SB_PROJECT_DIR}/operator-state"
if routing_setting_apply "${current}" '.policy.server.block_cn=true' > "${TMP_DIR}/stale.log" 2>&1; then
  fail 'concurrent state change bypassed CAS'
fi
[[ -s "${TMP_DIR}/cas-rejections" ]]
jq -e '(.server.block_cn|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
jq -e '(.policy.server.block_cn|not)' "${current}" >/dev/null
[[ "$(jq -r '.fingerprint' "${current}")" == "$(routing_state_fingerprint)" ]]
routing_setting_apply "${current}" '.policy.server.warp_ai=false' > "${TMP_DIR}/after-stale.log" 2>&1
jq -e '(.server.block_cn|not) and (.server.warp_ai|not)' "${SB_ROUTING_POLICY_FILE}" >/dev/null
[[ "$(cat "${SB_PROJECT_DIR}/operator-state")" == 'operator-owned state' ]]

# An unchanged selection must also detect an obsolete view instead of claiming
# it is already effective after another operator has changed the setting.
routing_draft_create "${current}"
jq '.server.warp_ai=true' "${SB_ROUTING_POLICY_FILE}" > "${TMP_DIR}/concurrent-policy.json"
cp -- "${TMP_DIR}/concurrent-policy.json" "${SB_ROUTING_POLICY_FILE}"
if routing_setting_apply "${current}" '.policy.server.warp_ai=false' > "${TMP_DIR}/stale-noop.log" 2>&1; then
  fail 'stale unchanged selection reported as currently effective'
fi
jq -e '.policy.server.warp_ai' "${current}" >/dev/null
routing_setting_apply "${current}" '.policy.server.warp_ai=false' > "${TMP_DIR}/retry-noop.log" 2>&1

# With no unsaved choices to preserve, a concurrent edit completed while the
# diagnostic runs is read normally; the next switch preserves that live edit.
media_check_menu() {
  printf '# refreshed backend\n' > "${SB_MEDIA_CHECK_SCRIPT}"
  jq '.server.warp_streaming=false' "${SB_ROUTING_POLICY_FILE}" > "${TMP_DIR}/concurrent-policy.json"
  cp -- "${TMP_DIR}/concurrent-policy.json" "${SB_ROUTING_POLICY_FILE}"
}
routing_management_menu > "${TMP_DIR}/diagnostic-concurrent.log" 2>&1 <<'INPUT'
4
1
0
INPUT
jq -e '.server.block_cn and (.server.warp_ai|not) and (.server.warp_streaming|not)' \
  "${SB_ROUTING_POLICY_FILE}" >/dev/null
[[ "$(wc -l < "${TMP_DIR}/cas-rejections")" == 1 ]]
[[ ! -e "${current}.apply" && ! -e "${current}.apply.next" ]]
printf 'Diagnostics refresh immediate settings while concurrent CAS remains strict\n'
