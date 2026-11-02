#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
fail() { printf 'routing diagnostic draft: %s\n' "$*" >&2; exit 1; }
# No backend/provider/network/system service is invoked. Only the diagnostic's
# exact persistent backend cache is written by this private fixture.
printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[],"final":"direct"}}' > "${SINGBOX_CONFIG_FILE}"
media_check_menu() {
  mkdir -p -- "${SB_MEDIA_CHECK_DIR}"
  printf '#!/usr/bin/env bash\nprintf fixture\n' > "${SB_MEDIA_CHECK_SCRIPT}"
  printf '# previous fixture backend\n' > "${SB_MEDIA_CHECK_SCRIPT}.bak"
}
routing_policy_apply() {
  local expected
  expected=$(jq -r '.fingerprint' "$1")
  [[ "${expected}" == "$(routing_state_fingerprint)" ]] || return 91
  cp -- "$1" "${TMP_DIR}/applied-draft.json"
}
routing_management_menu > "${TMP_DIR}/menu.log" 2>&1 <<'EOF'
1
2
2
0
4
5
1
y
0
y
EOF
[[ -f "${TMP_DIR}/applied-draft.json" ]] || fail 'first diagnostic cache invalidated the unsaved draft'
jq -e '.policy.server.block_cn and .warp.enabled and .warp.mode=="selective"' "${TMP_DIR}/applied-draft.json" >/dev/null
[[ "$(jq -r '.fingerprint' "${TMP_DIR}/applied-draft.json")" == "$(routing_state_fingerprint)" ]]
# The full and external transaction fingerprints still include cache bytes.
all_before=$(routing_state_fingerprint)
external_before=$(routing_state_fingerprint external)
printf '# backend updated\n' >> "${SB_MEDIA_CHECK_SCRIPT}"
[[ "$(routing_state_fingerprint)" != "${all_before}" &&
   "$(routing_state_fingerprint external)" != "${external_before}" ]]

# Reconciliation updates both private originals, retaining every pending edit.
draft="${TMP_DIR}/draft.json"
original="${TMP_DIR}/original.json"
for mutation in cache-only policy unknown-child cache-link already-stale; do
  rm -rf -- "${SB_MEDIA_CHECK_DIR}"
  routing_draft_create "${draft}"
  cp -- "${draft}" "${original}"
  routing_draft_edit "${draft}" '.policy.server.block_cn=true | .warp.enabled=true'
  previous=$(jq -r '.fingerprint' "${draft}")
  original_policy=$(jq -cS 'del(.fingerprint)' "${original}")
  if [[ "${mutation}" == already-stale ]]; then
    printf 'external mutation before diagnostic\n' > "${SB_PROJECT_DIR}/external-state"
  fi
  media_check_menu() {
    mkdir -p -- "${SB_MEDIA_CHECK_DIR}"
    printf '# backend fixture\n' > "${SB_MEDIA_CHECK_SCRIPT}"
    printf '# previous backend fixture\n' > "${SB_MEDIA_CHECK_SCRIPT}.bak"
    case "${mutation}" in
      policy) printf '%s\n' '{"external":true}' > "${SB_ROUTING_POLICY_FILE}" ;;
      unknown-child) printf 'operator-owned\n' > "${SB_MEDIA_CHECK_DIR}/operator-owned" ;;
      cache-link)
        rm -- "${SB_MEDIA_CHECK_SCRIPT}"
        ln -s "${SINGBOX_CONFIG_FILE}" "${SB_MEDIA_CHECK_SCRIPT}" ;;
    esac
  }
  routing_media_check_with_draft "${draft}" "${original}" > "${TMP_DIR}/${mutation}.log" 2>&1
  jq -e '.policy.server.block_cn and .warp.enabled' "${draft}" >/dev/null
  [[ "$(jq -cS 'del(.fingerprint)' "${original}")" == "${original_policy}" ]]
  if [[ "${mutation}" == cache-only ]]; then
    current=$(routing_state_fingerprint)
    [[ "$(jq -r '.fingerprint' "${draft}")" == "${current}" &&
       "$(jq -r '.fingerprint' "${original}")" == "${current}" ]]
    [[ "${current}" != "${previous}" ]]
  else
    [[ "$(jq -r '.fingerprint' "${draft}")" == "${previous}" &&
       "$(jq -r '.fingerprint' "${original}")" == "${previous}" ]]
    if routing_policy_apply "${draft}"; then fail "concurrent ${mutation} change was accepted"; fi
  fi
  rm -f -- "${SB_ROUTING_POLICY_FILE}" "${SB_PROJECT_DIR}/external-state"
done
# Mutate control state immediately after a control digest has been read. The
# surrounding full hashes must catch races on either side of the diagnostic.
declare -f routing_state_fingerprint > "${TMP_DIR}/fingerprint-function.sh"
sed '1s/routing_state_fingerprint/routing_fixture_real_fingerprint/' \
  "${TMP_DIR}/fingerprint-function.sh" > "${TMP_DIR}/real-fingerprint.sh"
source "${TMP_DIR}/real-fingerprint.sh"
routing_state_fingerprint() {
  local result
  result=$(routing_fixture_real_fingerprint "${1:-all}") || return 1
  if [[ "${1:-all}" == without_media_cache && ! -e "${TMP_DIR}/raced-once" &&
        ( "${race}" == before || -e "${TMP_DIR}/media-done" ) ]]; then
    printf 'concurrent state\n' > "${SB_PROJECT_DIR}/raced-state"
    touch "${TMP_DIR}/raced-once"
  fi
  printf '%s\n' "${result}"
}
for race in before after; do
  rm -rf -- "${SB_MEDIA_CHECK_DIR}"
  rm -f -- "${TMP_DIR}/raced-once" "${TMP_DIR}/media-done" "${SB_PROJECT_DIR}/raced-state"
  routing_draft_create "${draft}"
  cp -- "${draft}" "${original}"
  routing_draft_edit "${draft}" '.policy.server.block_cn=true'
  previous=$(jq -r '.fingerprint' "${draft}")
  media_check_menu() {
    mkdir -p -- "${SB_MEDIA_CHECK_DIR}"
    printf '# diagnostic cache\n' > "${SB_MEDIA_CHECK_SCRIPT}"
    touch "${TMP_DIR}/media-done"
  }
  routing_media_check_with_draft "${draft}" "${original}" > "${TMP_DIR}/race-${race}.log" 2>&1
  [[ -e "${TMP_DIR}/raced-once" ]]
  [[ "$(jq -r '.fingerprint' "${draft}")" == "${previous}" &&
     "$(jq -r '.fingerprint' "${original}")" == "${previous}" ]]
  if routing_policy_apply "${draft}"; then fail "${race} control-digest race was accepted"; fi
done
printf 'Diagnostic cache preserves pending drafts while external CAS remains strict\n'
