#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope: Bash 4.2 treats readonly arrays declared from inside
# the helper function as locals and drops the protocol registry on return.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
trap 'printf "mixed active state test failed at line %s\\n" "${LINENO}" >&2' ERR

store_file="${SB_PROTOCOL_STATE_DIR}/instances/mixed.json"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"

make_store() {
  jq -n '
    {
      schema_version: 1,
      protocol: "mixed",
      revision: 0,
      default_instance_id: "Edge_A",
      instances: [
        {
          id: "Edge_A",
          name: "duplicate name",
          tag: "mixed-edge-a",
          listen: {address: "0.0.0.0", port: 32101},
          authentication: {enabled: true, username: "user\n", password: "pass\n"},
          outbound_policy: "direct",
          dependencies: []
        },
        {
          id: "edge-B",
          name: "duplicate name",
          tag: "mixed-edge-b",
          listen: {address: "127.0.0.1", port: 32102},
          authentication: {enabled: false, username: "", password: ""},
          outbound_policy: "direct",
          dependencies: []
        }
      ]
    }
  ' > "${store_file}"
  chmod 600 "${store_file}"
}

# A valid orphaned store does not activate schema 2 and cannot alter legacy
# rendering. This is the no-implicit-migration boundary.
make_store
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nNODE_NAME=legacy\nPORT=32100\nAUTH_ENABLED=n\nUSERNAME=\nPASSWORD=\n' \
  > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
legacy_state_copy="${TMP_DIR}/mixed-legacy.env"
cp -p "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${legacy_state_copy}"
legacy_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")
! mixed_structured_state_active
load_protocol_instance_state mixed main
[[ "${SB_INSTANCE_ID}" == main && "${SB_PORT}" == 32100 ]]
legacy_inbound=$(build_mixed_inbound_json | jq -s .)
jq -e 'length == 1 and .[0].tag == "mixed-in" and .[0].listen_port == 32100' \
  <<< "${legacy_inbound}" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env")" == "${legacy_hash}" ]]

# A schema-2 marker with invalid activation metadata must fail closed instead
# of falling back to the legacy state reader or renderer.
printf 'INSTALLED=0\nCONFIG_SCHEMA_VERSION=2\nNODE_NAME=legacy\nPORT=32100\nAUTH_ENABLED=n\nUSERNAME=\nPASSWORD=\n' \
  > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
! mixed_structured_state_active
! build_mixed_inbound_json >/dev/null 2>&1
! load_protocol_instance_state mixed main >/dev/null 2>&1
cp -p "${legacy_state_copy}" "${SB_PROTOCOL_STATE_DIR}/mixed.env"

# Schema-2 marker parsing is data-only: an injected shell fragment is rejected
# before load_protocol_state can source it. Duplicate metadata assignments are
# rejected as well, while quoted metadata and comments remain supported.
marker_probe="${TMP_DIR}/mixed-marker-executed"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n%s\n' \
  "\$(touch \"${marker_probe}\")" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
! validate_protocol_state_schema mixed "${SB_PROTOCOL_STATE_DIR}/mixed.env" >/dev/null 2>&1
! load_protocol_state mixed >/dev/null 2>&1
[[ ! -e "${marker_probe}" ]]
printf 'INSTALLED=1\n CONFIG_SCHEMA_VERSION=2\n%s\n' \
  "\$(touch \"${marker_probe}\")" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
! validate_protocol_state_schema mixed "${SB_PROTOCOL_STATE_DIR}/mixed.env" >/dev/null 2>&1
! load_protocol_state mixed >/dev/null 2>&1
[[ ! -e "${marker_probe}" ]]
printf 'INSTALLED=1\n\tCONFIG_SCHEMA_VERSION=2\n%s\n' \
  "\$(touch \"${marker_probe}\")" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
! validate_protocol_state_schema mixed "${SB_PROTOCOL_STATE_DIR}/mixed.env" >/dev/null 2>&1
! load_protocol_state mixed >/dev/null 2>&1
[[ ! -e "${marker_probe}" ]]
printf 'INSTALLED=1\n CONFIG_SCHEMA_VERSION=2; %s\n' \
  "\$(touch \"${marker_probe}\")" > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
! validate_protocol_state_schema mixed "${SB_PROTOCOL_STATE_DIR}/mixed.env" >/dev/null 2>&1
! load_protocol_state mixed >/dev/null 2>&1
[[ ! -e "${marker_probe}" ]]
printf 'INSTALLED=1\nINSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' \
  > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
! mixed_structured_marker_is_valid "${SB_PROTOCOL_STATE_DIR}/mixed.env"
{
  printf '# inert comment\n'
  printf '%s\n' '  INSTALLED="1"'
  printf '\tCONFIG_SCHEMA_VERSION=%s\n' "'2'"
} > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
mixed_structured_marker_is_valid "${SB_PROTOCOL_STATE_DIR}/mixed.env"
load_protocol_state mixed read-only
[[ "${SB_MIXED_INSTANCE_ID}" == Edge_A ]]
indented_inbounds=$(build_mixed_inbound_json | jq -s .)
jq -e 'length == 2 and .[0].tag == "mixed-edge-a" and .[1].tag == "mixed-edge-b"' \
  <<< "${indented_inbounds}" >/dev/null
[[ "$(list_protocol_instance_ids mixed)" == $'Edge_A\nedge-B' ]]
[[ "$(protocol_default_instance_id mixed)" == Edge_A ]]
jq '{inbounds: [.instances[] | {type: "mixed", tag: .tag, listen: .listen.address,
  listen_port: .listen.port,
  users: (if .authentication.enabled then
    [{username: .authentication.username, password: .authentication.password}]
  else [] end)}],
  route: {rules: ([.instances[] | select(.outbound_policy != "default") |
    {inbound: .tag, action: "route", outbound: (if .outbound_policy == "warp" then "warp-ep" else .outbound_policy end)}])}}' \
  "${store_file}" > "${SINGBOX_CONFIG_FILE}"
mixed_validate_state_inventory
candidate_json=$(mixed_config_store_candidate)
jq -e '([.instances[]] | length) == 2 and .instances[0].tag == "mixed-edge-a"' \
  <<< "${candidate_json}" >/dev/null
mv "${store_file}" "${store_file}.missing"
! mixed_config_store_candidate >/dev/null 2>&1
mv "${store_file}.missing" "${store_file}"
cp -p "${legacy_state_copy}" "${SB_PROTOCOL_STATE_DIR}/mixed.env"

# Explicit marker activation switches all reads/renders to the typed store.
save_mixed_structured_marker
[[ -f "${SB_PROTOCOL_STATE_DIR}/mixed.env.bak" && ! -L "${SB_PROTOCOL_STATE_DIR}/mixed.env.bak" ]]
cmp -s "${legacy_state_copy}" "${SB_PROTOCOL_STATE_DIR}/mixed.env.bak"
mixed_structured_state_active
[[ "$(list_protocol_instance_ids mixed)" == $'Edge_A\nedge-B' ]]
[[ "$(protocol_default_instance_id mixed)" == Edge_A ]]

load_protocol_instance_state mixed edge-B
[[ "${SB_INSTANCE_ID}" == edge-B ]]
[[ "${SB_MIXED_INBOUND_TAG}" == mixed-edge-b ]]
[[ "${SB_MIXED_LISTEN_ADDRESS}" == 127.0.0.1 ]]
[[ "${SB_OUTBOUND_POLICY}" == direct ]]

load_protocol_instance_state mixed Edge_A
[[ "${SB_MIXED_USERNAME}" == $'user\n' ]]
[[ "${SB_MIXED_PASSWORD}" == $'pass\n' ]]
[[ "${SB_MIXED_INSTANCE_ID}" == Edge_A ]]

# Typed rendering must not prepare or mutate credentials, and must preserve
# every instance's tag/address/port/authentication independently.
ensure_mixed_auth_credentials() {
  printf 'structured rendering attempted credential generation\n' >&2
  return 49
}
inbounds_json=$(build_mixed_inbound_json | jq -s .)
jq -e '
  length == 2 and
  .[0].tag == "mixed-edge-a" and .[0].listen == "0.0.0.0" and
  .[0].users[0].username == "user\n" and
  .[1].tag == "mixed-edge-b" and .[1].listen == "127.0.0.1" and
  (.[1].users | length == 0)
' <<< "${inbounds_json}" >/dev/null
route_json=$(build_protocol_route_rules mixed)
jq -e 'length == 4 and all(.[]; .action == "sniff" or .action == "route")' <<< "${route_json}" >/dev/null

# Export tags are derived from stable IDs, not duplicate display names. A
# wildcard uses the detected public address; a loopback stays loopback and is
# explicitly warned as local-only.
export_json=$(build_client_outbound_json_for_protocol mixed 203.0.113.44 | jq -s .)
jq -e '
  length == 2 and
  .[0].tag == "mixed-Edge_A" and .[0].server == "203.0.113.44" and
  .[0].username == "user\n" and .[0].password == "pass\n" and
  .[1].tag == "mixed-edge-B" and .[1].server == "127.0.0.1" and
  .[0].udp_over_tcp.enabled == true and .[1].udp_over_tcp.enabled == true
' <<< "${export_json}" >/dev/null

summary_json=$(agent_node_summary_json_for_current_protocol 203.0.113.44)
jq -e '
  .instance_id == "Edge_A" and .tag == "mixed-edge-a" and
  .listen.address == "0.0.0.0" and .listen.port == 32101 and
  .instance_revision == 0
' <<< "${summary_json}" >/dev/null
links_json=$(agent_link_json_for_current_protocol 203.0.113.44)
jq -e '(.instance_id == "Edge_A" and .tag == "mixed-edge-a" and .instance_revision == 0 and
  .links.socks5 == "socks5://user%0A:pass%0A@203.0.113.44:32101" and
  (.links | has("http") | not) and any(.warnings[]; .code == "mixed_http_auth_unrepresentable"))' \
  <<< "${links_json}" >/dev/null

# Active saves are CAS replacements: credentials are taken from the selected
# runtime record, while identity, tag, listen address and dependencies remain
# store-owned. Empty credentials are rejected rather than generated.
SB_NODE_NAME='renamed node'
SB_PORT=32111
SB_MIXED_USERNAME='updated-user'
SB_MIXED_PASSWORD='updated-pass'
save_mixed_state
jq -e '
  .revision == 1 and .instances[0].id == "Edge_A" and
  .instances[0].tag == "mixed-edge-a" and
  .instances[0].listen.address == "0.0.0.0" and
  .instances[0].listen.port == 32111 and
  .instances[0].name == "renamed node" and
  .instances[0].authentication.username == "updated-user"
' "${store_file}" >/dev/null
summary_json=$(agent_node_summary_json_for_current_protocol 203.0.113.44)
jq -e '.instance_revision == 1' <<< "${summary_json}" >/dev/null
links_json=$(agent_link_json_for_current_protocol 203.0.113.44)
jq -e '.instance_revision == 1' <<< "${links_json}" >/dev/null

if [[ -n "${SINGBOX_BINARY_113:-}${SINGBOX_BINARY_114:-}" ]]; then
  inbounds_json=$(build_mixed_inbound_json | jq -s .)
  route_json=$(build_protocol_route_rules mixed)
  jq -n --argjson inbounds "${inbounds_json}" --argjson rules "${route_json}" \
    '{log:{level:"warn"},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{rules:$rules,final:"direct"}}' \
    > "${TMP_DIR}/mixed-active-core.json"
  for binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
    [[ -n "${binary}" ]] || continue
    "${binary}" check -c "${TMP_DIR}/mixed-active-core.json"
  done
fi

printf 'mixed active state checks passed\n'
