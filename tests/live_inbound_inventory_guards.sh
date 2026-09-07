#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 121
source_testable_install

write_fixture() {
  local fixture=$1
  case "${fixture}" in
    managed)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{"inbounds":[
  {"type":"vless","tag":"vless-in","tls":{"reality":{}}},
  {"type":"vless","tag":"vless-reality-two","tls":{"reality":{"enabled":true}}},
  {"type":"mixed","tag":"mixed-in"},
  {"type":"hysteria2","tag":"hy2-in"},
  {"type":"anytls","tag":"anytls-in"}
]}
EOF
      ;;
    unknown)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{"inbounds":[
  {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":1080},
  {"type":"shadowsocks","tag":"ss-in","listen":"127.0.0.1","listen_port":8388,
   "method":"2022-blake3-aes-128-gcm","password":"MDEyMzQ1Njc4OWFiY2RlZg=="}
]}
EOF
      ;;
    plain-vless)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"plain-vless","tls":{"enabled":true}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    duplicate-mixed)
      printf '%s\n' '{"inbounds":[{"type":"mixed","tag":"mixed-a"},{"type":"mixed","tag":"mixed-b"}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    duplicate-hy2)
      printf '%s\n' '{"inbounds":[{"type":"hysteria2","tag":"hy2-a"},{"type":"hysteria2","tag":"hy2-b"}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    duplicate-anytls)
      printf '%s\n' '{"inbounds":[{"type":"anytls","tag":"anytls-a"},{"type":"anytls","tag":"anytls-b"}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    duplicate-tag)
      printf '%s\n' '{"inbounds":[{"type":"mixed","tag":"same"},{"type":"vless","tag":"same","tls":{"reality":{}}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    bad-structure)
      printf '%s\n' '{"inbounds":{}}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    invalid-json)
      printf '%s\n' '{"inbounds":[' > "${SINGBOX_CONFIG_FILE}"
      ;;
    diagnostic)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{"inbounds":[{"type":"mixed","tag":"mixed-in","listen_port":1080,
"users":[{"username":"config-user","password":"CONFIG-PASSWORD-DO-NOT-LOG"}]}]}
EOF
      ;;
    *) return 1 ;;
  esac
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=inventory-test
PORT=1080
AUTH_ENABLED=y
USERNAME=state-user
PASSWORD=STATE-PASSWORD-DO-NOT-LOG
EOF
cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 755 "${SINGBOX_BIN_PATH}"
printf '%s\n' '[Service]' > "${SINGBOX_SERVICE_FILE}"

write_fixture managed
[[ "$(list_config_protocols)" == $'vless-reality\nmixed\nhy2\nanytls' ]]
validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}"
[[ "$(normalize_protocol_id vless)" == "vless-reality" ]]

rm -f "${SINGBOX_CONFIG_FILE}"
validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}"
write_fixture unknown

config_before=$(sha256sum "${SINGBOX_CONFIG_FILE}")
index_before=$(sha256sum "${SB_PROTOCOL_INDEX_FILE}")
state_before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
config_mode_before=$(stat -c '%a' "${SINGBOX_CONFIG_FILE}")
state_mode_before=$(stat -c '%a' "${SB_PROTOCOL_STATE_DIR}/mixed.env")

mark_side_effect() {
  : > "${TMP_DIR}/side-effect"
  return 97
}
create_managed_state_snapshot() { mark_side_effect; }
ensure_warp_routing_assets() { mark_side_effect; }
register_warp() { mark_side_effect; }
restart_service_after_takeover() { mark_side_effect; }

for handler in \
  validate_live_inbound_inventory \
  list_config_protocols \
  protocol_state_layer_matches_config \
  attempt_managed_instance_auto_heal \
  reconcile_protocol_index_if_needed \
  rebuild_protocol_state_from_config \
  generate_config_candidate \
  generate_config \
  take_over_existing_instance; do
  : > "${TMP_DIR}/stdout"
  : > "${TMP_DIR}/stderr"
  if [[ "${handler}" == "validate_live_inbound_inventory" ]]; then
    if "${handler}" "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/stderr"; then
      printf '%s accepted an unknown live inbound\n' "${handler}" >&2
      exit 1
    fi
  elif "${handler}" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/stderr"; then
    printf '%s accepted an unknown live inbound\n' "${handler}" >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/stdout" ]]
  grep -Fq 'live_inbound_inventory: unsupported_inbound_type' "${TMP_DIR}/stderr"
  [[ ! -e "${TMP_DIR}/side-effect" ]]
  [[ "$(sha256sum "${SINGBOX_CONFIG_FILE}")" == "${config_before}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_INDEX_FILE}")" == "${index_before}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${state_before}" ]]
  [[ "$(stat -c '%a' "${SINGBOX_CONFIG_FILE}")" == "${config_mode_before}" ]]
  [[ "$(stat -c '%a' "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${state_mode_before}" ]]
done

for fixture in plain-vless duplicate-mixed duplicate-hy2 duplicate-anytls duplicate-tag bad-structure invalid-json; do
  write_fixture "${fixture}"
  : > "${TMP_DIR}/stdout"
  if validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/stderr"; then
    printf '%s passed the live inbound inventory guard\n' "${fixture}" >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/stdout" ]]
  case "${fixture}" in
    plain-vless) grep -Fq 'unsupported_inbound_preset' "${TMP_DIR}/stderr" ;;
    duplicate-mixed|duplicate-hy2|duplicate-anytls) grep -Fq 'unsupported_inbound_multiplicity' "${TMP_DIR}/stderr" ;;
    duplicate-tag) grep -Fq 'duplicate_inbound_tag' "${TMP_DIR}/stderr" ;;
    bad-structure) grep -Fq 'invalid_inbounds' "${TMP_DIR}/stderr" ;;
    invalid-json) grep -Fq 'invalid_json_or_inventory' "${TMP_DIR}/stderr" ;;
  esac
done

write_fixture diagnostic
if log_takeover_state_diagnostics > "${TMP_DIR}/diagnostic.stdout" 2> "${TMP_DIR}/diagnostic.stderr"; then
  :
fi
cat "${TMP_DIR}/diagnostic.stdout" "${TMP_DIR}/diagnostic.stderr" "${SBV_LOG_FILE}" > "${TMP_DIR}/diagnostic.all"
for secret in CONFIG-PASSWORD-DO-NOT-LOG STATE-PASSWORD-DO-NOT-LOG config-user state-user; do
  if grep -Fq "${secret}" "${TMP_DIR}/diagnostic.all"; then
    printf 'takeover diagnostics leaked secret material\n' >&2
    exit 1
  fi
done
grep -Fq '已省略原始值' "${TMP_DIR}/diagnostic.all"

write_fixture unknown
real_core_checks=0
for core in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  [[ -n "${core}" ]] || continue
  [[ -x "${core}" ]] || {
    printf 'configured real core is not executable: %s\n' "${core}" >&2
    exit 1
  }
  "${core}" check -c "${SINGBOX_CONFIG_FILE}"
  real_core_checks=$((real_core_checks + 1))
done
if [[ "${real_core_checks}" -eq 0 ]]; then
  printf 'SKIP: real 1.13/1.14 core paths were not provided\n'
else
  printf 'real core inventory controls passed: %d\n' "${real_core_checks}"
fi

printf 'live inbound inventory guards passed\n'
