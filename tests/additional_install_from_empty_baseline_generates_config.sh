#!/usr/bin/env bash

set -euo pipefail
umask 077

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
[[ -x "${core}" ]] || { printf 'real sing-box 1.14 binary required: %s\n' "${core}" >&2; exit 1; }
export SBV_TEST_CORE
SBV_TEST_CORE=$(readlink -f -- "${core}")
cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "${SBV_TEST_CORE:?}" "$@"
EOF
chmod +x "${TMP_DIR}/bin/sing-box"
source_testable_install

# Keep configuration generation and core checks real. Only host mutations,
# external network assets and interactive protocol fields are replaced.
setup_service() { :; }
systemctl() { :; }
open_committed_protocol_ports() { :; }
refresh_vless_reality_qos_rules() { :; }
save_warp_route_settings() { :; }
load_warp_route_settings() { :; }
ensure_warp_routing_assets() { :; }
register_warp() { printf 'unexpected Warp registration\n' >&2; return 91; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'
  SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'
  SB_WARP_REMOTE_RULE_SETS_JSON='[]'
  SB_WARP_RULE_SET_TAGS_JSON='[]'
}
load_stack_mode_state() { SB_INBOUND_STACK_MODE=ipv4_only; SB_OUTBOUND_STACK_MODE=ipv4_only; }
ensure_stack_mode_state_loaded() { load_stack_mode_state; }

key_pair=$("${SINGBOX_BIN_PATH}" generate reality-keypair)
test_private_key=$(sed -n 's/^PrivateKey: //p' <<< "${key_pair}")
test_public_key=$(sed -n 's/^PublicKey: //p' <<< "${key_pair}")
[[ -n "${test_private_key}" && -n "${test_public_key}" ]]

prompt_protocol_install_fields() {
  local protocol=$1
  set_protocol_defaults "${protocol}"
  SB_NODE_NAME="empty-${protocol}"
  SB_PORT=36443
  if [[ "${protocol}" == vless-reality ]]; then
    SB_VLESS_INSTANCE_ID=main
    SB_VLESS_INBOUND_TAG=''
    SB_UUID=11111111-1111-4111-8111-111111111111
    SB_PRIVATE_KEY=${test_private_key}
    SB_PUBLIC_KEY=${test_public_key}
    SB_SNI=www.example.com
    SB_SHORT_ID_1=aaaaaaaaaaaaaaaa
    SB_SHORT_ID_2=bbbbbbbbbbbbbbbb
    SB_VLESS_RATE_LIMIT_UP_MBPS=''
    SB_VLESS_RATE_LIMIT_DOWN_MBPS=''
    SB_OUTBOUND_POLICY=default
  else
    SB_MIXED_AUTH_ENABLED=y
    SB_MIXED_USERNAME=fixture-user
    SB_MIXED_PASSWORD=fixture-password
    SB_MIXED_LISTEN_ADDRESS=127.0.0.1
    SB_OUTBOUND_POLICY=default
  fi
}

generation_state_digest() {
  sha256sum "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}" "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
  if [[ -e "${SB_PROJECT_DIR}/managed-config.generated.json" ]]; then
    sha256sum "${SB_PROJECT_DIR}/managed-config.generated.json"
  else
    printf 'generated baseline absent\n'
  fi
}

assert_generation_rejected_unchanged() {
  local label=$1 before
  shift
  before=$(generation_state_digest)
  if (generate_config "$@") > "${TMP_DIR}/${label}.output" 2> "${TMP_DIR}/${label}.stderr"; then
    printf 'expected generation to reject %s\n' "${label}" >&2
    return 1
  fi
  [[ "$(generation_state_digest)" == "${before}" ]]
}

# No previous generated baseline exists after this historical final deletion.
# The installer must first establish a validated baseline without managed
# protocols, then save the new protocol and generate through the normal path.
# Default generation must still reject an empty protocol inventory.
for protocol in vless-reality mixed socks; do
  (
    rm -rf -- "${SB_PROJECT_DIR}"
    mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
    touch "${SINGBOX_SERVICE_FILE}"
    printf '%s\n' 'PROTOCOL_STATE_VERSION=1' 'INSTALLED_PROTOCOLS=' > "${SB_PROTOCOL_INDEX_FILE}"
    structured_instance_store_empty_json hy2 | jq '.revision=5' \
      > "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
    retained_before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json")
    cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "log": {"level":"error"},
  "inbounds": [],
  "outbounds": [{"type":"direct","tag":"manual-direct","bind_interface":"lo"}],
  "route": {
    "rules": [{"domain":["example.net"],"action":"route","outbound":"manual-direct"}],
    "final":"manual-direct"
  }
}
EOF
    cp -- "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/empty-${protocol}.json"
    "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"
    [[ ! -e "${SB_PROJECT_DIR}/managed-config.generated.json" ]]
    instance_management_empty_config_baseline
    if [[ "${protocol}" == vless-reality ]]; then
      SB_PROTOCOL=''
      assert_generation_rejected_unchanged default-empty
    fi
    (install_protocols_interactive additional "${protocol}") </dev/null \
      > "${TMP_DIR}/${protocol}.output" 2> "${TMP_DIR}/${protocol}.stderr" || {
        cat "${TMP_DIR}/${protocol}.output" "${TMP_DIR}/${protocol}.stderr" >&2
        exit 1
      }
    "${SINGBOX_BIN_PATH}" check -c "${SINGBOX_CONFIG_FILE}"
    jq -e --arg type "$([[ "${protocol}" == vless-reality ]] && printf vless || printf '%s' "${protocol}")" '
      (.inbounds | length)==1 and .inbounds[0].type==$type and .inbounds[0].listen_port==36443 and
      any(.outbounds[]; .type=="direct" and .tag=="manual-direct" and .bind_interface=="lo") and
      .route.final=="manual-direct" and
      any(.route.rules[]; .domain==["example.net"] and .action=="route" and .outbound=="manual-direct")
    ' "${SINGBOX_CONFIG_FILE}" >/dev/null
    # Explicit log settings are preserved; generation may fill absent defaults
    # such as log.timestamp without changing the administrator's settings.
    jq -e --slurpfile before "${TMP_DIR}/empty-${protocol}.json" '
      (.log as $after_log | all($before[0].log | to_entries[]; $after_log[.key]==.value)) and
      [.outbounds[] | select(.tag=="manual-direct")]==$before[0].outbounds and
      [.route.rules[] | select(.outbound=="manual-direct")]==$before[0].route.rules and
      .route.final==$before[0].route.final
    ' "${SINGBOX_CONFIG_FILE}" >/dev/null
    grep -Fxq "INSTALLED_PROTOCOLS=${protocol}" "${SB_PROTOCOL_INDEX_FILE}"
    [[ -f "$(protocol_state_file "${protocol}")" ]]
    [[ -f "${SB_PROJECT_DIR}/managed-config.generated.json" ]]
    [[ "$(stat -c %a "${SB_PROJECT_DIR}/managed-config.generated.json")" == 600 ]]
    [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json")" == "${retained_before}" ]]
    [[ ! -e "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]
    if [[ "${protocol}" == vless-reality ]]; then
      assert_generation_rejected_unchanged active-with-empty-flag '' true
    fi
    printf 'first managed protocol from empty baseline passed: %s\n' "${protocol}"
  )
done
