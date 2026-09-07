#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope so Bash 4.2 retains the real registry arrays.
source "${TESTABLE_INSTALL}"
trap 'printf "socks structured takeover failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED_PROTOCOLS=socks\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
jq -n '
  {log:{level:"warn"},
   inbounds:[
     {type:"socks",tag:"edge.tag",listen:"0.0.0.0",listen_port:33101,
      users:[{username:"edge-user\n",password:"edge-pass\n"}]},
     {type:"socks",tag:"local",listen_port:33102}
   ],
   outbounds:[{type:"direct",tag:"direct"}],
   route:{rules:[
     {inbound:"edge.tag",action:"route",outbound:"direct"}
   ],final:"direct"}}
' > "${SINGBOX_CONFIG_FILE}"

candidate=$(plain_proxy_config_store_candidate socks)
edge_id=$(jq -r '.instances[] | select(.tag == "edge.tag") | .id' <<< "${candidate}")
jq -e --arg edge_id "${edge_id}" '
  .protocol == "socks" and .revision == 1 and .default_instance_id == $edge_id and
  ([.instances[].tag] | sort) == ["edge.tag", "local"] and
  ([.instances[] | select(.tag == "edge.tag")][0] |
    .id == $edge_id and .name == "edge.tag" and .listen.address == "0.0.0.0" and
  .listen.port == 33101 and .authentication.enabled and
  .authentication.username == "edge-user\n" and .authentication.password == "edge-pass\n" and
  .outbound_policy == "direct") and
  ([.instances[] | select(.tag == "local")][0] |
    .listen.address == "127.0.0.1" and .listen.port == 33102 and
    .authentication.enabled == false and .outbound_policy == "default")
' <<< "${candidate}" >/dev/null

rebuild_protocol_state_from_config
store_file=$(plain_proxy_structured_store_file socks)
plain_proxy_structured_state_active socks
plain_proxy_validate_state_inventory socks
plain_proxy_structured_state_matches_config socks
protocol_state_matches_config socks
agent_validate_indexed_protocol_states socks
[[ "$(list_protocol_instance_ids socks | tr '\n' ',')" == "${edge_id},local," ]]
[[ "$(protocol_default_instance_id socks)" == "${edge_id}" ]]
load_protocol_instance_state socks "${edge_id}"
[[ "${SB_PROTOCOL}" == socks && "${SB_INSTANCE_ID}" == "${edge_id}" ]]
[[ "${SB_MIXED_USERNAME}" == $'edge-user\n' && "${SB_MIXED_PASSWORD}" == $'edge-pass\n' ]]
[[ "${SB_OUTBOUND_POLICY}" == direct ]]

inbounds=$(build_inbound_for_protocol socks | jq -s .)
jq -e '
  length == 2 and all(.[];.type == "socks") and
  any(.[];.tag == "edge.tag" and .listen == "0.0.0.0" and
      .users[0].username == "edge-user\n") and
  any(.[];.tag == "local" and .listen == "127.0.0.1" and (.users|length) == 0)
' <<< "${inbounds}" >/dev/null
routes=$(build_protocol_route_rules socks)
jq -e 'length == 3 and any(.[];.inbound == "edge.tag" and .outbound == "direct") and all(.[]; (.inbound != "local" or (.outbound // "") != "warp-ep"))' <<< "${routes}" >/dev/null

# Keep the route-policy extractor covered for Warp without making the
# positive full-core fixture depend on a machine-specific WireGuard endpoint.
jq '.route.rules += [{inbound:"local",action:"route",outbound:"warp-ep"}]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/warp-policy.json"
warp_candidate=$(plain_proxy_config_store_candidate socks "${TMP_DIR}/warp-policy.json" "${store_file}")
jq -e 'any(.instances[]; .tag == "local" and .outbound_policy == "warp")' <<< "${warp_candidate}" >/dev/null

# The generated configuration must request the Warp outbound whenever any
# SOCKS instance selects that policy, just as the Mixed path does.
cp -p "${store_file}" "${TMP_DIR}/store-before-warp.json"
jq '(.instances[] | select(.tag == "local") | .outbound_policy) = "warp"' \
  "${store_file}" > "${TMP_DIR}/store-warp.json"
mv "${TMP_DIR}/store-warp.json" "${store_file}"
instance_outbound_requires_warp
mv "${TMP_DIR}/store-before-warp.json" "${store_file}"

# Validate both the captured live config and the rendered typed inbounds with
# each real core supplied by the verification environment.  This is skipped
# explicitly when a binary is unavailable.
rendered_config="${TMP_DIR}/rendered.json"
jq --argjson inbounds "${inbounds}" '.inbounds = $inbounds' "${SINGBOX_CONFIG_FILE}" > "${rendered_config}"
core_checks=0
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${core_binary}" && -x "${core_binary}" ]]; then
    "${core_binary}" check -c "${SINGBOX_CONFIG_FILE}"
    "${core_binary}" check -c "${rendered_config}"
    core_checks=$((core_checks + 1))
  else
    printf 'SKIP SOCKS real-core check: binary unavailable\n'
  fi
done

# Every owned listener participates in health matching; drift in the second
# record must fail rather than silently checking only the default instance.
jq '.inbounds[1].listen_port = 33103' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/drift.json"
mv "${TMP_DIR}/drift.json" "${SINGBOX_CONFIG_FILE}"
if protocol_state_matches_config socks; then
  printf 'expected SOCKS health mismatch for second listener\n' >&2
  exit 1
fi
jq '.inbounds[1].listen_port = 33102' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/restored.json"
mv "${TMP_DIR}/restored.json" "${SINGBOX_CONFIG_FILE}"

# TLS, extra listen options, and multiple users are not representable in the
# typed SOCKS schema. SOCKS also cannot carry Mixed-only set_system_proxy.
jq '.inbounds[0].set_system_proxy = false' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/unknown.json"
mv "${TMP_DIR}/unknown.json" "${SINGBOX_CONFIG_FILE}"
if plain_proxy_config_store_candidate socks > /dev/null 2>"${TMP_DIR}/unknown.stderr"; then
  printf 'expected SOCKS set_system_proxy field to be rejected\n' >&2
  exit 1
fi
grep -Fq '[ERROR] socks_store_candidate:' "${TMP_DIR}/unknown.stderr"
if grep -Fq 'Mixed' "${TMP_DIR}/unknown.stderr"; then
  printf 'SOCKS collector diagnostic incorrectly used Mixed label\n' >&2
  exit 1
fi
jq 'del(.inbounds[0].set_system_proxy)' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/unknown-restored.json"
mv "${TMP_DIR}/unknown-restored.json" "${SINGBOX_CONFIG_FILE}"

# Rebuild must leave the entire prior state tree intact on a lossy failure.
before_tree=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum)
jq '.inbounds[0].tls = {enabled:true}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/lossy.json"
mv "${TMP_DIR}/lossy.json" "${SINGBOX_CONFIG_FILE}"
if rebuild_protocol_state_from_config > "${TMP_DIR}/lossy.stdout" 2> "${TMP_DIR}/lossy.stderr"; then
  printf 'expected lossy SOCKS takeover to fail\n' >&2
  exit 1
fi
after_tree=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum)
[[ "${before_tree}" == "${after_tree}" ]]
if grep -Eq 'edge-pass|edge-user' "${TMP_DIR}/lossy.stderr"; then
  printf 'SOCKS takeover diagnostic leaked a credential\n' >&2
  exit 1
fi

# save_socks_state must fail closed on missing credentials and preserve both
# the typed store and marker bytes.
store_hash=$(sha256sum "${store_file}")
state_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")
SB_INSTANCE_ID="${edge_id}"
SB_PORT=33101
SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=""
SB_MIXED_PASSWORD=""
if save_socks_state >/dev/null 2>&1; then
  printf 'expected missing SOCKS credentials to be rejected\n' >&2
  exit 1
fi
[[ "$(sha256sum "${store_file}")" == "${store_hash}" ]]
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")" == "${state_hash}" ]]

# An unindexed SOCKS store is accepted only as a validated, revisioned empty
# tombstone; malformed and non-empty orphan stores fail closed.
cp -p "${store_file}" "${TMP_DIR}/store-before-orphan.json"
cp -p "${SB_PROTOCOL_STATE_DIR}/socks.env" "${TMP_DIR}/state-before-orphan.env"
rm -f -- "${store_file}" "${SB_PROTOCOL_STATE_DIR}/socks.env"
printf 'INSTALLED_PROTOCOLS=\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cp -p "${TMP_DIR}/store-before-orphan.json" "${store_file}"
if agent_validate_indexed_protocol_states ""; then
  printf 'expected non-empty orphan SOCKS store to be rejected\n' >&2
  exit 1
fi
set_protocol_defaults socks
SB_INSTANCE_ID=main
SB_PORT=33104
SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=fresh-user
SB_MIXED_PASSWORD=fresh-password
orphan_hash=$(sha256sum "${store_file}" "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}")
if save_socks_state >/dev/null 2>&1; then
  printf 'SOCKS save unexpectedly reactivated orphan listeners\n' >&2
  exit 1
fi
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/socks.env" ]]
[[ "$(sha256sum "${store_file}" "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}")" == "${orphan_hash}" ]]
structured_instance_store_empty_json socks > "${store_file}"
zero_revision_hash=$(sha256sum "${store_file}")
if save_socks_state >/dev/null 2>&1; then
  printf 'SOCKS save unexpectedly accepted a revision-zero tombstone\n' >&2
  exit 1
fi
[[ ! -e "${SB_PROTOCOL_STATE_DIR}/socks.env" ]]
[[ "$(sha256sum "${store_file}")" == "${zero_revision_hash}" ]]
structured_instance_store_empty_json socks | jq '.revision = 1' > "${store_file}"
agent_validate_indexed_protocol_states ""
save_socks_state >/dev/null
jq -e '.revision == 2 and (.instances | length) == 1 and .instances[0].id == "main"' "${store_file}" >/dev/null
plain_proxy_structured_state_active socks
rm -f -- "${store_file}" "${SB_PROTOCOL_STATE_DIR}/socks.env"
mv "${TMP_DIR}/store-before-orphan.json" "${store_file}"
mv "${TMP_DIR}/state-before-orphan.env" "${SB_PROTOCOL_STATE_DIR}/socks.env"
printf 'INSTALLED_PROTOCOLS=socks\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"

# A schema-1 SOCKS marker is never sourced or migrated, and the untrusted
# marker cannot cause a store overwrite.
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=1\nPORT=33101\n' > "${SB_PROTOCOL_STATE_DIR}/socks.env"
bad_state_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")
bad_store_hash=$(sha256sum "${store_file}")
if load_protocol_state socks read-only; then
  printf 'expected legacy SOCKS state to be rejected\n' >&2
  exit 1
fi
if save_socks_state >/dev/null 2>&1; then
  printf 'expected save against legacy SOCKS state to be rejected\n' >&2
  exit 1
fi
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/socks.env")" == "${bad_state_hash}" ]]
[[ "$(sha256sum "${store_file}")" == "${bad_store_hash}" ]]

# A fresh SOCKS save with no explicit address uses the verified sing-box
# loopback default and never widens to the public stack bind.
cp -p "${store_file}" "${TMP_DIR}/store.saved"
rm -f -- "${store_file}" "${SB_PROTOCOL_STATE_DIR}/socks.env"
set_protocol_defaults socks
unset SB_MIXED_LISTEN_ADDRESS
SB_PORT=33104
SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=fresh-user
SB_MIXED_PASSWORD=fresh-password
save_socks_state >/dev/null
jq -e 'any(.instances[]; .tag == "socks-in" and .listen.address == "127.0.0.1" and .listen.port == 33104)' "${store_file}" >/dev/null
rm -f -- "${store_file}" "${SB_PROTOCOL_STATE_DIR}/socks.env"
mv "${TMP_DIR}/store.saved" "${store_file}"

printf 'socks structured takeover checks passed; real core checks=%s\n' "${core_checks}"
