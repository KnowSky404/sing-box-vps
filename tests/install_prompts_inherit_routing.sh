#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

fail() {
  printf 'install routing defaults failed: %s\n' "$*" >&2
  exit 1
}

prompt_instance_outbound_policy() {
  printf 'called\n' >> "${TMP_DIR}/outbound-prompt-calls"
  return 98
}

# A bare VPS loads neutral defaults without displaying routing or requiring jq.
# Values left in memory from another operation must not replace fresh defaults.
(
  jq() { printf 'called\n' >> "${TMP_DIR}/default-jq-calls"; return 127; }
  read() { fail 'global defaults attempted to read input'; }
  prompt_yes_no() { fail 'global defaults asked a yes/no question'; }
  prompt_choice() { fail 'global defaults asked a routing choice'; }
  SB_ENABLE_WARP=y
  SB_ADVANCED_ROUTE=n
  routing_policy_prepare_install_defaults </dev/null > "${TMP_DIR}/default-summary"
  [[ "${SB_ENABLE_WARP}" == n && "${SB_ADVANCED_ROUTE}" == n ]]
  [[ ! -s "${TMP_DIR}/default-summary" && ! -e "${SB_ROUTING_POLICY_FILE}" &&
     ! -e "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]
  [[ ! -e "${TMP_DIR}/default-jq-calls" ]]
)

# Retained defaults are loaded without asking, displaying or changing settings.
(
  printf '%s\n' '{"inbounds":[],"endpoints":[{"tag":"warp-ep"}],"route":{"final":"warp-ep"}}' > "${SINGBOX_CONFIG_FILE}"
  read() { fail 'retained policy attempted to read input'; }
  routing_policy_prepare_install_defaults </dev/null > "${TMP_DIR}/retained-summary"
  [[ "${SB_ENABLE_WARP}" == y && "${SB_WARP_ROUTE_MODE}" == all && "${SB_ADVANCED_ROUTE}" == n ]]
  [[ ! -s "${TMP_DIR}/retained-summary" && ! -e "${SB_ROUTING_POLICY_FILE}" &&
     ! -e "${SB_WARP_ROUTE_SETTINGS_FILE}" ]]
)

# Exercise real typed creation and replacement. Only unrelated credential and
# input collection is stubbed; record dispatch and validation remain real.
printf '%s\n' '{"inbounds":[]}' > "${SINGBOX_CONFIG_FILE}"
read() {
  if [[ "${1:-}" != -rp && "${1:-}" != -rsp ]]; then builtin read "$@"; return $?; fi
  local target=${@: -1} value=''
  [[ "$*" != *监听地址* ]] || value=127.0.0.1
  printf -v "${target}" '%s' "${value}"
}
prompt_port() { printf '%s' "${2:-445}"; }
prompt_yes_no() { printf '%s' "${2:-n}"; }
ensure_mixed_auth_credentials() { SB_MIXED_USERNAME=fixture-user; SB_MIXED_PASSWORD=fixture-password; }
snapshot="${TMP_DIR}/snapshot.json"
record="${TMP_DIR}/record.json"
for protocol in mixed socks http; do
  structured_instance_store_empty_json "${protocol}" > "${snapshot}"
  SB_OUTBOUND_POLICY=warp
  plain_proxy_management_build_record "${protocol}" "${snapshot}" create '' "${record}" \
    > "${TMP_DIR}/typed.stdout" 2> "${TMP_DIR}/typed.stderr"
  jq -e '.outbound_policy=="default"' "${record}" >/dev/null
  id=$(jq -r '.id' "${record}")
  for existing_policy in direct warp; do
    jq -n --arg protocol "${protocol}" --arg policy "${existing_policy}" --slurpfile record "${record}" \
      '{schema_version:1,protocol:$protocol,revision:7,default_instance_id:$record[0].id,
        instances:[$record[0] | .outbound_policy=$policy]}' > "${snapshot}"
    plain_proxy_management_build_record "${protocol}" "${snapshot}" replace "${id}" "${record}" \
      > "${TMP_DIR}/typed.stdout" 2> "${TMP_DIR}/typed.stderr"
    jq -e --arg policy "${existing_policy}" '.outbound_policy==$policy and .authentication.password=="fixture-password"' \
      "${record}" >/dev/null
    jq -e --arg policy "${existing_policy}" '.revision==7 and .instances[0].outbound_policy==$policy' \
      "${snapshot}" >/dev/null
  done
done

# REALITY needs an explicit reset after it reads the default instance's SNI,
# because loading that instance also loads its independent outbound override.
pick_random_high_port() { printf 443; }
check_port_conflict() { :; }
port_in_configured_protocol_state() { return 1; }
prompt_reality_sni_install() { SB_SNI=fixture.example.com; }
prompt_reality_sni_update() { :; }
prompt_reality_sni_for_new_instance() { SB_SNI=$1; }
prompt_vless_reality_rate_limit_fields() { :; }
prompt_vless_reality_rate_limit_update_fields() { :; }
prompt_vless_reality_advanced_update_fields() { :; }
validate_current_reality_sni_alpn_or_warn() { return 7; }
SB_OUTBOUND_POLICY=warp
if ! prompt_vless_reality_install > "${TMP_DIR}/reality-install.stdout"; then
  fail 'REALITY installation still depended on an outbound-policy question'
fi
[[ "${SB_OUTBOUND_POLICY}" == default ]]
SB_OUTBOUND_POLICY=direct
if ! prompt_vless_reality_update > "${TMP_DIR}/reality-update.stdout"; then
  fail 'REALITY replacement did not preserve its routing policy'
fi
[[ "${SB_OUTBOUND_POLICY}" == direct ]]

migrate_vless_reality_state_to_instances_if_needed() { :; }
load_vless_reality_protocol_state() { :; }
list_vless_reality_instance_ids() { :; }
vless_reality_instance_id_exists() { return 1; }
load_vless_reality_instance_state() { SB_SNI=retained.example.com; SB_OUTBOUND_POLICY=warp; }
vless_reality_bandwidth_profile_exists() { return 1; }
ensure_vless_reality_materials() { :; }
append_vless_reality_instance_id() { :; }
save_vless_reality_protocol_state() { :; }
save_vless_reality_instance_state() { printf '%s' "${SB_OUTBOUND_POLICY}" > "${TMP_DIR}/saved-reality-policy"; }
if ! prompt_vless_reality_instance_create > "${TMP_DIR}/reality-create.stdout"; then
  fail 'REALITY creation still depended on an outbound-policy question'
fi
[[ "$(cat "${TMP_DIR}/saved-reality-policy")" == default ]]
[[ ! -e "${TMP_DIR}/outbound-prompt-calls" ]]

printf 'Install routing defaults passed: no routing prompts, inherited creates and preserved replacements\n'
