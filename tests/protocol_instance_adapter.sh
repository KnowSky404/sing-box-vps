#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at top level: Bash 4.2 scopes readonly array declarations to a calling
# function, unlike the runtime entrypoint and newer Bash versions.
source "${TESTABLE_INSTALL}"
trap 'printf "shared adapter test failed at line %s\n" "${LINENO}" >&2' ERR

for required_function in list_protocol_instance_ids protocol_default_instance_id load_protocol_instance_state; do
  declare -F "${required_function}" >/dev/null || {
    printf 'missing shared instance adapter: %s\n' "${required_function}" >&2
    exit 1
  }
done

tree_hash() {
  (
    cd "${SB_PROTOCOL_STATE_DIR}"
    find . -printf '%y %m %p\n' | sort
    find . -type f -print0 | sort -z | xargs -0 sha256sum
  ) | sha256sum
}

assert_rejected_without_output() {
  if "$@" > "${TMP_DIR}/rejected.stdout" 2> "${TMP_DIR}/rejected.stderr"; then
    printf 'expected adapter rejection\n' >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/rejected.stdout" ]]
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
for protocol in mixed hy2 anytls; do
  {
    printf '%s\n' 'INSTALLED=1' 'CONFIG_SCHEMA_VERSION=1' 'PORT=8443'
    write_env_assignment NODE_NAME "${protocol} name with spaces"
    write_env_assignment USERNAME 'user $() ; quote'
    write_env_assignment PASSWORD 'password $() ; quote'
    printf '%s\n' 'AUTH_ENABLED=y' 'DOMAIN=example.com' 'USER_NAME=proxy-user' 'TLS_MODE=manual'
  } > "${SB_PROTOCOL_STATE_DIR}/${protocol}.env"
done
printf '%s\n' 'INSTALLED=1' 'CONFIG_SCHEMA_VERSION=2' > "${SB_PROTOCOL_STATE_DIR}/http.env"
jq -n '
  {
    schema_version: 1,
    protocol: "http",
    revision: 0,
    default_instance_id: "main",
    instances: [{
      id: "main",
      name: "HTTP adapter",
      tag: "http-in",
      listen: {address: "127.0.0.1", port: 8444},
      authentication: {enabled: true, username: "http-user", password: "http-password"},
      outbound_policy: "default",
      dependencies: [],
      tls: {enabled: false}
    }]
  }
' > "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
[[ "$(list_protocol_instance_ids http)" == main ]]
[[ "$(protocol_default_instance_id http)" == main ]]
load_protocol_instance_state http main
[[ "${SB_PROTOCOL}" == http && "${SB_INSTANCE_ID}" == main ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 127.0.0.1 && "${SB_PORT}" == 8444 ]]
[[ "${SB_MIXED_AUTH_ENABLED}" == y && "${SB_MIXED_USERNAME}" == http-user ]]
jq -e '.enabled == false' <<< "${SB_HTTP_TLS_JSON}" >/dev/null
assert_rejected_without_output load_protocol_instance_state http other
printf '%s\n' 'INSTALLED=1' 'CONFIG_SCHEMA_VERSION=2' > "${SB_PROTOCOL_STATE_DIR}/shadowsocks.env"
jq -n '
  {
    schema_version: 1,
    protocol: "shadowsocks",
    revision: 0,
    default_instance_id: "main",
    instances: [{
      id: "main",
      name: "Shadowsocks adapter",
      tag: "ss-in",
      listen: {address: "127.0.0.1", port: 8445, network: ["tcp", "udp"]},
      authentication: {method: "aes-256-gcm", password: "ss-password", users: []},
      outbound_policy: "default",
      dependencies: []
    }]
  }
' > "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
[[ "$(list_protocol_instance_ids ss)" == main ]]
[[ "$(protocol_default_instance_id ss)" == main ]]
load_protocol_instance_state ss main
[[ "${SB_PROTOCOL}" == shadowsocks && "${SB_INSTANCE_ID}" == main ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 127.0.0.1 && "${SB_PORT}" == 8445 ]]
jq -e '.method == "aes-256-gcm" and .password == "ss-password" and (.users | length) == 0' \
  <<< "${SB_SHADOWSOCKS_AUTH_JSON}" >/dev/null
[[ "${SB_SHADOWSOCKS_NETWORK_JSON}" == '["tcp","udp"]' ]]
assert_rejected_without_output load_protocol_instance_state shadowsocks other
before_hash=$(tree_hash)
for protocol in mixed hy2 hysteria2 anytls; do
  [[ "$(list_protocol_instance_ids "${protocol}")" == main ]]
  [[ "$(protocol_default_instance_id "${protocol}")" == main ]]
  load_protocol_instance_state "${protocol}" main
  [[ "${SB_INSTANCE_ID}" == main && "${SB_PORT}" == 8443 ]]
  case "${protocol}" in
    mixed) [[ "${SB_MIXED_PASSWORD}" == 'password $() ; quote' ]] ;;
    hy2|hysteria2) [[ "${SB_HY2_PASSWORD}" == 'password $() ; quote' ]] ;;
    anytls) [[ "${SB_ANYTLS_PASSWORD}" == 'password $() ; quote' ]] ;;
  esac
  assert_rejected_without_output load_protocol_instance_state "${protocol}" other
done
[[ "$(tree_hash)" == "${before_hash}" ]]
assert_rejected_without_output list_protocol_instance_ids unknown
assert_rejected_without_output load_protocol_instance_state mixed '../../escape'
cp "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${TMP_DIR}/mixed.original.env"
sed '/^CONFIG_SCHEMA_VERSION=/d; /^PASSWORD=/d; /^USERNAME=/d' \
  "${TMP_DIR}/mixed.original.env" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
[[ "$(list_protocol_instance_ids mixed)" == main ]]
PASSWORD=stale-secret
USERNAME=stale-user
load_protocol_instance_state mixed main
[[ -z "${SB_MIXED_PASSWORD}" && -z "${SB_MIXED_USERNAME}" ]]
for bad_schema in 999 corrupt; do
  sed "s/CONFIG_SCHEMA_VERSION=1/CONFIG_SCHEMA_VERSION=${bad_schema}/" \
    "${TMP_DIR}/mixed.original.env" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
  assert_rejected_without_output list_protocol_instance_ids mixed
done
cp "${TMP_DIR}/mixed.original.env" "${SB_PROTOCOL_STATE_DIR}/mixed.env"

private_key=private-fixture
public_key=public-fixture
key_core=${SINGBOX_BINARY_114:-${SINGBOX_BINARY_113:-}}
if [[ -n "${key_core}" ]]; then
  key_pair=$("${key_core}" generate reality-keypair)
  private_key=$(sed -n 's/^PrivateKey: *//p' <<< "${key_pair}")
  public_key=$(sed -n 's/^PublicKey: *//p' <<< "${key_pair}")
  [[ -n "${private_key}" && -n "${public_key}" ]]
fi
{
  printf '%s\n' 'INSTALLED=1' 'CONFIG_SCHEMA_VERSION=1' 'NODE_NAME=legacy-reality' \
    'PORT=443' 'UUID=11111111-1111-4111-8111-111111111111' 'SNI=example.com' \
    'SHORT_ID_1=aaaaaaaaaaaaaaaa' 'SHORT_ID_2=bbbbbbbbbbbbbbbb'
  write_env_assignment REALITY_PRIVATE_KEY "${private_key}"
  write_env_assignment REALITY_PUBLIC_KEY "${public_key}"
} > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
printf '%s\n' 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls' 'PROTOCOL_STATE_VERSION=1' > "${SB_PROTOCOL_INDEX_FILE}"
cp "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" "${TMP_DIR}/legacy-original.env"
sed '/^SHORT_ID_2=/d' "${TMP_DIR}/legacy-original.env" > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
SB_SHORT_ID_2=stale-optional-short-id
load_protocol_instance_state vless main
[[ -z "${SB_SHORT_ID_2}" ]]
cp "${TMP_DIR}/legacy-original.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
for required_field in NODE_NAME PORT SNI; do
  sed "/^${required_field}=/d" "${TMP_DIR}/legacy-original.env" > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  assert_rejected_without_output load_protocol_instance_state vless main
  assert_rejected_without_output build_client_vless_reality_outbounds 127.0.0.1
done
cp "${TMP_DIR}/legacy-original.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

# Pure reads and client rendering must not migrate schema1 or prepare materials.
migrate_vless_reality_state_to_instances_if_needed() { printf 'migration called\n' >&2; return 49; }
ensure_vless_reality_materials() { printf 'material preparation called\n' >&2; return 49; }
before_hash=$(tree_hash)
for alias in vless vless+reality vless-reality; do
  [[ "$(list_protocol_instance_ids "${alias}")" == main ]]
  [[ "$(protocol_default_instance_id "${alias}")" == main ]]
  SB_VLESS_INSTANCE_ID=stale
  SB_VLESS_RATE_LIMIT_UP_MBPS=999
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=888
  load_protocol_instance_state "${alias}" main
  [[ "${SB_INSTANCE_ID}" == main && "${SB_VLESS_INSTANCE_ID}" == main ]]
  [[ -z "${SB_VLESS_RATE_LIMIT_UP_MBPS}" && -z "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" ]]
  [[ "${SB_UUID}" == 11111111-1111-4111-8111-111111111111 ]]
done
build_client_vless_reality_outbounds 127.0.0.1 > "${TMP_DIR}/legacy-outbounds.jsonl"
jq -s -e 'length == 1 and .[0].uuid == "11111111-1111-4111-8111-111111111111"' "${TMP_DIR}/legacy-outbounds.jsonl" >/dev/null
[[ "$(tree_hash)" == "${before_hash}" ]]
[[ ! -d "${SB_PROTOCOL_STATE_DIR}/vless-reality.d" ]]
get_public_ip() { printf '127.0.0.1'; }
reconcile_protocol_index_if_needed() { printf 'reconciliation called during render\n' >&2; return 49; }
build_singbox_client_config > "${TMP_DIR}/legacy-client.json"
jq -e '[.outbounds[] | select(.type == "vless")] | length == 1' "${TMP_DIR}/legacy-client.json" >/dev/null
[[ "$(tree_hash)" == "${before_hash}" ]]
[[ ! -d "${SB_PROTOCOL_STATE_DIR}/vless-reality.d" ]]
if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/legacy-client.json"
fi
cp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/canonical-index.env"
printf '%s\n' 'INSTALLED_PROTOCOLS=vless,mixed,hysteria2,anytls' 'PROTOCOL_STATE_VERSION=1' > "${SB_PROTOCOL_INDEX_FILE}"
[[ "$(list_installed_protocols_read_only)" == $'vless-reality\nmixed\nhy2\nanytls' ]]
index_hash=$(sha256sum "${SB_PROTOCOL_INDEX_FILE}")
build_singbox_client_config > "${TMP_DIR}/alias-client.json"
[[ "$(sha256sum "${SB_PROTOCOL_INDEX_FILE}")" == "${index_hash}" ]]
printf '%s\n' 'INSTALLED_PROTOCOLS=vless,vless-reality,mixed,hy2,anytls' 'PROTOCOL_STATE_VERSION=1' > "${SB_PROTOCOL_INDEX_FILE}"
assert_rejected_without_output list_installed_protocols_read_only
cp "${TMP_DIR}/canonical-index.env" "${SB_PROTOCOL_INDEX_FILE}"

VLESS_REALITY_DEFAULT_INSTANCE_ID=edge
VLESS_REALITY_INSTANCE_IDS=main,edge
SB_PRIVATE_KEY=${private_key}
SB_PUBLIC_KEY=${public_key}
save_vless_reality_protocol_state
for instance_id in main edge; do
  SB_VLESS_INSTANCE_ID=${instance_id}
  SB_NODE_NAME='same display name'
  SB_VLESS_INBOUND_TAG="fixed-${instance_id}"
  SB_PORT=443
  SB_UUID=11111111-1111-4111-8111-111111111111
  [[ "${instance_id}" == main ]] || { SB_PORT=8443; SB_UUID=22222222-2222-4222-8222-222222222222; }
  SB_SNI=example.com
  SB_SHORT_ID_1=aaaaaaaaaaaaaaaa
  SB_SHORT_ID_2=bbbbbbbbbbbbbbbb
  SB_VLESS_RATE_LIMIT_UP_MBPS=17
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=43
  SB_VLESS_ALPN_MODE=off
  SB_VLESS_TCP_FAST_OPEN=n
  SB_OUTBOUND_POLICY=direct
  save_vless_reality_instance_state
done
before_hash=$(tree_hash)
[[ "$(list_protocol_instance_ids vless)" == $'main\nedge' ]]
[[ "$(protocol_default_instance_id vless)" == edge ]]
load_protocol_instance_state vless main
[[ "${SB_INSTANCE_ID}" == main && "${SB_VLESS_INBOUND_TAG}" == fixed-main ]]
[[ "${SB_VLESS_RATE_LIMIT_UP_MBPS}" == 17 && "${SB_OUTBOUND_POLICY}" == direct ]]
build_client_vless_reality_outbounds 127.0.0.1 > "${TMP_DIR}/multi-outbounds.jsonl"
jq -s -e 'length == 2 and ([.[].tag] | unique | length) == 2' "${TMP_DIR}/multi-outbounds.jsonl" >/dev/null
[[ "$(tree_hash)" == "${before_hash}" ]]
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  [[ -n "${core_binary}" ]] || continue
  for fixture in legacy multi; do
    jq -s '{outbounds: .}' "${TMP_DIR}/${fixture}-outbounds.jsonl" > "${TMP_DIR}/client.json"
    "${core_binary}" check -c "${TMP_DIR}/client.json"
  done
done

# An invalid manifest must never expose a valid prefix as the complete list.
cp "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" "${TMP_DIR}/valid-root.env"
for bad_manifest in main,main main,missing; do
  sed "s/INSTANCE_IDS=main,edge/INSTANCE_IDS=${bad_manifest}/" "${TMP_DIR}/valid-root.env" > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
  assert_rejected_without_output list_protocol_instance_ids vless
done
cp "${TMP_DIR}/valid-root.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
cp "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/edge.env" "${TMP_DIR}/valid-edge.env"
for required_field in UUID SNI SHORT_ID_1 PORT; do
  sed "/^${required_field}=/d" "${TMP_DIR}/valid-edge.env" > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/edge.env"
  assert_rejected_without_output build_client_vless_reality_outbounds 127.0.0.1
  load_protocol_instance_state mixed main
  assert_rejected_without_output build_client_outbound_json_for_protocol vless-reality 127.0.0.1
  [[ "${SB_PROTOCOL}" == mixed && "${SB_INSTANCE_ID}" == main ]]
  [[ "${SB_NODE_NAME}" == 'mixed name with spaces' && "${SB_PORT}" == 8443 ]]
  [[ "${SB_MIXED_PASSWORD}" == 'password $() ; quote' && -z "${SB_UUID}" ]]
  build_client_outbound_json_for_protocol hy2 127.0.0.1 > "${TMP_DIR}/after-failed-reality.json"
  jq -e '.type == "hysteria2"' "${TMP_DIR}/after-failed-reality.json" >/dev/null
  [[ "${SB_PROTOCOL}" == mixed && "${SB_INSTANCE_ID}" == main ]]
done
cp "${TMP_DIR}/valid-edge.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/edge.env"
sed '/^REALITY_PUBLIC_KEY=/d' "${TMP_DIR}/valid-root.env" > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
assert_rejected_without_output build_client_vless_reality_outbounds 127.0.0.1
cp "${TMP_DIR}/valid-root.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
cp "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/edge.env" "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/orphan.env"
assert_rejected_without_output list_protocol_instance_ids vless
rm "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/orphan.env"
assert_rejected_without_output load_protocol_instance_state vless unlisted
(
  list_protocol_instance_ids() { printf 'main\n'; return 42; }
  failure_status=0
  build_client_vless_reality_outbounds 127.0.0.1 > "${TMP_DIR}/failure-output" || failure_status=$?
  [[ "${failure_status}" == 42 && ! -s "${TMP_DIR}/failure-output" ]]
)
(
  calls=0
  build_client_vless_reality_outbound() {
    [[ "${SB_VLESS_INSTANCE_ID}" == main ]] && { printf '{"type":"vless","tag":"first"}\n'; return 0; }
    return 45
  }
  failure_status=0
  build_client_vless_reality_outbounds 127.0.0.1 > "${TMP_DIR}/failure-output" || failure_status=$?
  [[ "${failure_status}" == 45 && ! -s "${TMP_DIR}/failure-output" ]]
)
(
  validate_live_inbound_inventory() { return 0; }
  agent_trusted_indexed_protocols_raw() { printf 'mixed\n'; }
  agent_validate_indexed_protocol_states() { return 0; }
  list_protocol_instance_ids() { printf 'main\n'; return 42; }
  get_public_ip() { touch "${TMP_DIR}/public-ip-called"; printf '192.0.2.1'; }
  if agent_collect_nodes_json summary > "${TMP_DIR}/agent-error.json"; then
    printf 'Agent ignored instance enumeration failure\n' >&2
    exit 1
  fi
  jq -e '.error == "protocol_state_untrusted" and (.nodes? == null)' "${TMP_DIR}/agent-error.json" >/dev/null
  [[ ! -e "${TMP_DIR}/public-ip-called" ]]
)
(
  validate_live_inbound_inventory() { return 0; }
  agent_trusted_indexed_protocols_raw() { printf 'mixed\n'; }
  agent_validate_indexed_protocol_states() { return 0; }
  agent_node_summary_json_for_current_protocol() { return 0; }
  if agent_collect_nodes_json summary > "${TMP_DIR}/agent-empty.json"; then
    printf 'Agent accepted an empty successful instance renderer\n' >&2
    exit 1
  fi
  jq -e '.error == "protocol_state_untrusted" and (.nodes? == null)' "${TMP_DIR}/agent-empty.json" >/dev/null
)

# A read-time disappearance returns to the caller instead of deep log_error/exit
# or treating cleared runtime fields as a valid already-selected protocol.
cp "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${TMP_DIR}/race-mixed.env"
(
  list_protocol_instance_ids() {
    rm "${SB_PROTOCOL_STATE_DIR}/mixed.env"
    printf 'main\n'
  }
  SB_PROTOCOL=hy2
  failure_status=0
  load_protocol_instance_state mixed main || failure_status=$?
  [[ "${failure_status}" != 0 ]]
  printf 'returned\n' > "${TMP_DIR}/read-race-returned"
)
[[ -s "${TMP_DIR}/read-race-returned" ]]
cp "${TMP_DIR}/race-mixed.env" "${SB_PROTOCOL_STATE_DIR}/mixed.env"
(
  validate_protocol_index_for_rebuild() { return 0; }
  list_indexed_protocols_raw() { return 0; }
  list_installed_protocols_read_only > "${TMP_DIR}/empty-index.stdout"
  [[ ! -s "${TMP_DIR}/empty-index.stdout" ]]
)

# Exercise the actual Agent inventory helpers under Bash 4.2 nounset, including
# the first array append and empty installation/error paths.
(
  list_indexed_protocols_raw() { printf 'mixed\n'; }
  list_config_protocols() { printf 'mixed\n'; }
  [[ "$(agent_trusted_indexed_protocols_raw)" == mixed ]]
  list_indexed_protocols_raw() { return 0; }
  list_config_protocols() { return 0; }
  agent_trusted_indexed_protocols_raw > "${TMP_DIR}/empty-agent-index"
  [[ ! -s "${TMP_DIR}/empty-agent-index" ]]
  assert_rejected_without_output agent_validate_indexed_protocol_states ''
)
(
  mv "${SB_PROTOCOL_STATE_DIR}" "${TMP_DIR}/saved-protocols"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  validate_live_inbound_inventory() { return 0; }
  list_config_protocols() { return 0; }
  SB_PROTOCOL=''
  agent_collect_nodes_json summary > "${TMP_DIR}/empty-agent-nodes.json"
  jq -e '.nodes == []' "${TMP_DIR}/empty-agent-nodes.json" >/dev/null
  rmdir "${SB_PROTOCOL_STATE_DIR}"
  mv "${TMP_DIR}/saved-protocols" "${SB_PROTOCOL_STATE_DIR}"
)

printf 'shared protocol instance adapter checks passed\n'
