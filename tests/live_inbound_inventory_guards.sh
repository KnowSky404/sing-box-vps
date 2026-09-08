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
  {"type":"vless","tag":"vless-in","tls":{"enabled":true,"reality":{"enabled":true}}},
  {"type":"vless","tag":"vless-reality-two","tls":{"enabled":true,"reality":{"enabled":true}}},
  {"type":"mixed","tag":"mixed-in"},
  {"type":"hysteria2","tag":"hy2-in"},
  {"type":"anytls","tag":"anytls-in"},
  {"type":"http","tag":"http-in","tls":{"enabled":false}},
  {"type":"shadowsocks","tag":"ss-in","listen":"127.0.0.1","listen_port":1084,
   "network":["tcp","udp"],"method":"aes-256-gcm","password":"SS-PASSWORD-DO-NOT-LOG"}
]}
EOF
      ;;
    unknown)
      cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{"inbounds":[
  {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":1080},
  {"type":"trojan","tag":"unknown-in","listen":"127.0.0.1","listen_port":8388}
]}
EOF
      ;;
    plain-vless)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"plain-vless","tls":{"enabled":true}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    implicit-reality)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"implicit-reality","tls":{"reality":{}}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    disabled-reality)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"disabled-reality","tls":{"enabled":true,"reality":{"enabled":false}}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    disabled-tls)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"disabled-tls","tls":{"enabled":false,"reality":{"enabled":true}}}]}' > "${SINGBOX_CONFIG_FILE}"
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
      printf '%s\n' '{"inbounds":[{"type":"mixed","tag":"same"},{"type":"vless","tag":"same","tls":{"enabled":true,"reality":{"enabled":true}}}]}' > "${SINGBOX_CONFIG_FILE}"
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
    managed-mixed-hy2)
      printf '%s\n' '{"inbounds":[{"type":"mixed","tag":"mixed-in"},{"type":"hysteria2","tag":"hy2-in"}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    managed-vless)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"vless-in","tls":{"enabled":true,"reality":{"enabled":true}}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    managed-vless-pair)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"vless-in","tls":{"enabled":true,"reality":{"enabled":true}}},{"type":"vless","tag":"vless-reality-edge","tls":{"enabled":true,"reality":{"enabled":true}}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    mismatched-vless-tags)
      printf '%s\n' '{"inbounds":[{"type":"vless","tag":"vless-in","tls":{"enabled":true,"reality":{"enabled":true}}},{"type":"vless","tag":"vless-other","tls":{"enabled":true,"reality":{"enabled":true}}}]}' > "${SINGBOX_CONFIG_FILE}"
      ;;
    managed-hy2)
      printf '%s\n' '{"inbounds":[{"type":"hysteria2","tag":"hy2-in"}]}' > "${SINGBOX_CONFIG_FILE}"
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
[[ "$(list_config_protocols)" == $'vless-reality\nmixed\nhy2\nanytls\nhttp\nshadowsocks' ]]
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
get_public_ip() { mark_side_effect; }

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

for agent_command in status nodes links; do
  agent_status=0
  agent_cli "${agent_command}" --json > "${TMP_DIR}/agent-${agent_command}.json" 2> "${TMP_DIR}/agent-${agent_command}.stderr" || agent_status=$?
  [[ "${agent_status}" -ne 0 ]]
  jq -e '
    .schema == "1" and .schema_version == "1.0" and .ok == false and
    .error == "live_inbound_inventory_untrusted" and
    .data.error == "live_inbound_inventory_untrusted" and
    (.protocols? == null) and (.nodes? == null)
  ' "${TMP_DIR}/agent-${agent_command}.json" >/dev/null
  if grep -Fq 'MDEyMzQ1Njc4OWFiY2RlZg==' "${TMP_DIR}/agent-${agent_command}.json" "${TMP_DIR}/agent-${agent_command}.stderr"; then
    printf 'agent %s leaked live inbound credentials\n' "${agent_command}" >&2
    exit 1
  fi
  [[ ! -e "${TMP_DIR}/side-effect" ]]
done

assert_agent_inventory_error() {
  local expected_error=$1 label=$2 agent_command agent_status secret
  shift 2

  for agent_command in "$@"; do
    rm -f "${TMP_DIR}/side-effect"
    agent_status=0
    agent_cli "${agent_command}" --json > "${TMP_DIR}/agent-${label}-${agent_command}.json" 2> "${TMP_DIR}/agent-${label}-${agent_command}.stderr" || agent_status=$?
    [[ "${agent_status}" -ne 0 ]]
    jq -e --arg expected "${expected_error}" '
      .schema == "1" and .schema_version == "1.0" and .ok == false and
      .error == $expected and .data.error == $expected and
      (.protocols? == null) and (.nodes? == null)
    ' "${TMP_DIR}/agent-${label}-${agent_command}.json" >/dev/null
    for secret in \
      MDEyMzQ1Njc4OWFiY2RlZg== \
      CONFIG-PASSWORD-DO-NOT-LOG \
      STATE-PASSWORD-DO-NOT-LOG \
      HY2-PASSWORD-DO-NOT-LOG \
      11111111-1111-4111-8111-111111111111 \
      22222222-2222-4222-8222-222222222222 \
      private-key \
      public-key; do
      if grep -Fq "${secret}" "${TMP_DIR}/agent-${label}-${agent_command}.json" "${TMP_DIR}/agent-${label}-${agent_command}.stderr"; then
        printf 'agent %s leaked credentials for %s\n' "${agent_command}" "${label}" >&2
        exit 1
      fi
    done
    [[ ! -e "${TMP_DIR}/side-effect" ]]
  done
}

write_fixture diagnostic
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed,future-protocol
PROTOCOL_STATE_VERSION=1
EOF
assert_agent_inventory_error protocol_index_untrusted unknown-index status nodes links

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=99
EOF
assert_agent_inventory_error protocol_index_untrusted future-index-schema status nodes links

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed,mixed
PROTOCOL_STATE_VERSION=1
EOF
assert_agent_inventory_error protocol_index_untrusted duplicate-index status nodes links

write_fixture managed-mixed-hy2
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF
assert_agent_inventory_error protocol_index_untrusted missing-live-index-entry status nodes links

write_fixture diagnostic
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed,hy2
PROTOCOL_STATE_VERSION=1
EOF
assert_agent_inventory_error protocol_index_untrusted extra-index-entry status nodes links

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=
PROTOCOL_STATE_VERSION=1
EOF
assert_agent_inventory_error protocol_index_untrusted empty-index status nodes links

rm -f "${SB_PROTOCOL_INDEX_FILE}"
assert_agent_inventory_error protocol_index_untrusted missing-index status nodes links

write_fixture managed-mixed-hy2
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=hy2,mixed
PROTOCOL_STATE_VERSION=1
EOF
cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2-inventory-test
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=HY2-PASSWORD-DO-NOT-LOG
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=n
TLS_MODE=manual
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=https://example.com/
EOF
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=99
EOF
get_public_ip() { printf '192.0.2.1'; }
assert_agent_inventory_error protocol_state_untrusted partial-state status nodes links

write_fixture diagnostic
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
cat > "${SB_PROTOCOL_STATE_DIR}/future.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
EOF
assert_agent_inventory_error protocol_state_untrusted orphan-state status nodes links
rm -f "${SB_PROTOCOL_STATE_DIR}/future.env"

write_fixture managed-vless
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF
rm -f "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${SB_PROTOCOL_STATE_DIR}/hy2.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
get_public_ip() { mark_side_effect; }
assert_agent_inventory_error protocol_state_untrusted missing-vless-state status nodes links

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
EOF
assert_agent_inventory_error protocol_state_untrusted incomplete-legacy-vless status nodes links

mkdir -p "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=vless-inventory-test
PORT=443
UUID=11111111-1111-4111-8111-111111111111
SNI=www.cloudflare.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
OUTBOUND_POLICY=default
EOF
(
  list_vless_reality_instance_ids() { return 42; }
  assert_agent_inventory_error protocol_state_untrusted vless-instance-enumeration status nodes links
)

sed -i 's/^REALITY_PUBLIC_KEY=.*/REALITY_PUBLIC_KEY=/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
assert_agent_inventory_error protocol_state_untrusted incomplete-vless-root status nodes links
sed -i 's/^REALITY_PUBLIC_KEY=.*/REALITY_PUBLIC_KEY=public-key/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

sed -i 's/^DEFAULT_INSTANCE_ID=.*/DEFAULT_INSTANCE_ID=ghost/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
assert_agent_inventory_error protocol_state_untrusted missing-vless-default-instance status nodes links
sed -i 's/^DEFAULT_INSTANCE_ID=.*/DEFAULT_INSTANCE_ID=main/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

sed -i 's/^SHORT_ID_1=.*/SHORT_ID_1=/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
assert_agent_inventory_error protocol_state_untrusted incomplete-vless-instance status nodes links
sed -i 's/^SHORT_ID_1=.*/SHORT_ID_1=aaaaaaaaaaaaaaaa/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"

rm -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
assert_agent_inventory_error protocol_state_untrusted missing-vless-instance status nodes links

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=vless-inventory-test
PORT=443
UUID=11111111-1111-4111-8111-111111111111
SNI=www.cloudflare.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
OUTBOUND_POLICY=default
EOF
sed -i 's/^INSTANCE_IDS=.*/INSTANCE_IDS=main,main/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
assert_agent_inventory_error protocol_state_untrusted duplicate-vless-instance status nodes links

sed -i 's/^INSTANCE_IDS=.*/INSTANCE_IDS=main/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
sed -i 's/^INSTANCE_ID=.*/INSTANCE_ID=edge/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
assert_agent_inventory_error protocol_state_untrusted mismatched-vless-instance-id status nodes links
sed -i 's/^INSTANCE_ID=.*/INSTANCE_ID=main/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/edge.env" <<'EOF'
INSTANCE_ID=edge
ENABLED=1
NODE_NAME=vless-edge-inventory-test
PORT=8443
UUID=22222222-2222-4222-8222-222222222222
SNI=www.apple.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
OUTBOUND_POLICY=default
EOF
assert_agent_inventory_error protocol_state_untrusted orphan-vless-instance status nodes links

sed -i 's/^INSTANCE_IDS=.*/INSTANCE_IDS=main,edge/' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
write_fixture mismatched-vless-tags
assert_agent_inventory_error protocol_state_untrusted mismatched-vless-live-tags status nodes links

write_fixture managed-vless-pair
get_public_ip() { printf '192.0.2.1'; }
for agent_command in status nodes links; do
  agent_cli "${agent_command}" --json > "${TMP_DIR}/agent-complete-vless-${agent_command}.json"
  jq -e '.ok == true' "${TMP_DIR}/agent-complete-vless-${agent_command}.json" >/dev/null
done

write_fixture managed-hy2
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=hy2
PROTOCOL_STATE_VERSION=1
EOF
rm -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2-restore-test
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=HY2-PASSWORD-DO-NOT-LOG
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=n
TLS_MODE=manual
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=https://example.com/
EOF
(
  SB_PROTOCOL=hy2
  load_protocol_state() {
    load_state_calls=$(( ${load_state_calls:-0} + 1 ))
    if (( load_state_calls > 1 )); then
      return 42
    fi
    SB_PROTOCOL=hy2
    SB_NODE_NAME=hy2-restore-test
    SB_PORT=8443
    SB_HY2_DOMAIN=hy2.example.com
    SB_HY2_PASSWORD=HY2-PASSWORD-DO-NOT-LOG
    SB_HY2_USER_NAME=hy2-user
    SB_HY2_UP_MBPS=100
    SB_HY2_DOWN_MBPS=50
    SB_HY2_OBFS_ENABLED=n
    SB_HY2_OBFS_TYPE=""
    SB_HY2_OBFS_PASSWORD=""
    SB_HY2_TLS_MODE=manual
    SB_HY2_MASQUERADE=https://example.com/
  }
  get_public_ip() { printf '192.0.2.1'; }
  assert_agent_inventory_error protocol_state_untrusted restore-failure nodes links
)

write_fixture diagnostic
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

write_fixture duplicate-mixed
validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}"

for fixture in plain-vless implicit-reality disabled-reality disabled-tls duplicate-hy2 duplicate-anytls duplicate-tag bad-structure invalid-json; do
  write_fixture "${fixture}"
  : > "${TMP_DIR}/stdout"
  if validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/stderr"; then
    printf '%s passed the live inbound inventory guard\n' "${fixture}" >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/stdout" ]]
  case "${fixture}" in
    plain-vless|implicit-reality|disabled-reality|disabled-tls) grep -Fq 'unsupported_inbound_preset' "${TMP_DIR}/stderr" ;;
    duplicate-hy2|duplicate-anytls) grep -Fq 'unsupported_inbound_multiplicity' "${TMP_DIR}/stderr" ;;
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
