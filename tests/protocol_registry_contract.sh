#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash "${REPO_ROOT}/tests/protocol_registry_legacy_bash.sh"
TEST_DIR=$(mktemp -d /tmp/sing-box-vps-registry-test.XXXXXX)
trap 'rm -rf "${TEST_DIR}"' EXIT

sed -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TEST_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TEST_DIR}/sing-box\"|" \
  "${REPO_ROOT}/install.sh" > "${TEST_DIR}/install.sh"
source "${TEST_DIR}/install.sh"

registry=$(protocol_registry_json)
jq -e '
  length == 6 and
  ([.[].state_id] | unique | length == 6) and
  ([.[].agent_id] | unique | length == 6) and
  ([.[].menu_order] | sort == [1,2,3,4,5,6]) and
  all(.[]; .implemented == true and .available == null and .validated.status == "not_assessed")
' >/dev/null <<< "${registry}"
capabilities=$(agent_capabilities_json)
jq -e '
  .features.plain_proxy_instances as $plain |
  ($plain.operations | index("migrate") == null) and
  ($plain.operations_by_protocol.mixed | index("migrate") != null) and
  ($plain.operations_by_protocol.socks == ["create", "replace", "delete", "default", "recover"]) and
  ($plain.protocols | index("http") != null) and
  ($plain.operations_by_protocol.http == ["create", "replace", "delete", "default", "recover"]) and
  .features.mixed_instances.operations == $plain.operations_by_protocol.mixed
' >/dev/null <<< "${capabilities}"
jq -e --argjson registry "${registry}" '
  .protocols == ($registry | map({key: .agent_id, value: .legacy_capabilities}) | from_entries) and
  ([.protocol_registry[].capabilities] == [$registry[].legacy_capabilities]) and
  .features.subman.supported_protocols == ($registry | map(select(.subman_type != "") | .agent_id))
' >/dev/null <<< "${capabilities}"

[[ "$(normalize_protocol_id vless)" == vless-reality ]]
[[ "$(normalize_protocol_id vless+reality)" == vless-reality ]]
[[ "$(normalize_protocol_id hysteria2)" == hy2 ]]
[[ "$(state_protocol_to_runtime vless-reality)" == vless+reality ]]
[[ "$(agent_protocol_id hy2)" == hysteria2 ]]
[[ "$(protocol_inbound_tag hysteria2)" == hy2-in ]]
for unknown in unknown '' '../mixed' 'mixed;touch /tmp/unsafe' '$(false)' 'vless-plain'; do
  for handler in normalize_protocol_id state_protocol_to_runtime protocol_inbound_tag protocol_state_file \
    build_inbound_for_protocol build_certificate_provider_for_protocol build_protocol_route_rules save_protocol_state; do
    if "${handler}" "${unknown}" > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr"; then
      printf 'unknown protocol accepted by %s\n' "${handler}" >&2
      exit 1
    fi
    [[ ! -s "${TEST_DIR}/unknown.stdout" ]]
  done
done

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
for protocol in $(list_registered_protocols); do
  protocol_registry_require_handlers "${protocol}"
  [[ "$(protocol_option_to_id "$(protocol_registry_field "${protocol}" menu_order)")" == "${protocol}" ]]
  if [[ "${protocol}" == "socks" || "${protocol}" == "http" ]]; then
    printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "$(protocol_state_file "${protocol}")"
    mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
    if [[ "${protocol}" == "socks" ]]; then
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/socks.json" <<'SOCKS_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "socks",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "SOCKS contract",
      "tag": "socks-in",
      "listen": {"address": "127.0.0.1", "port": 1081},
      "authentication": {"enabled": false, "username": "", "password": ""},
      "outbound_policy": "default",
      "dependencies": []
    }
  ]
}
SOCKS_STORE_EOF
    else
      cat > "${SB_PROTOCOL_STATE_DIR}/instances/http.json" <<'HTTP_STORE_EOF'
{
  "schema_version": 1,
  "protocol": "http",
  "revision": 1,
  "default_instance_id": "main",
  "instances": [
    {
      "id": "main",
      "name": "HTTP contract",
      "tag": "http-in",
      "listen": {"address": "127.0.0.1", "port": 1082},
      "authentication": {"enabled": true, "username": "http-user", "password": "HTTP-CONTRACT-PASSWORD"},
      "outbound_policy": "default",
      "dependencies": [],
      "tls": {"enabled": true, "server_name": "http.example.com", "certificate_path": "/tmp/http-contract.crt", "key_path": "/tmp/http-contract.key"}
    }
  ]
}
HTTP_STORE_EOF
    fi
  else
    printf 'CONFIG_SCHEMA_VERSION=1\n' > "$(protocol_state_file "${protocol}")"
  fi
done
printf 'INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls,socks,http\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
[[ "$(list_exportable_client_protocols)" == $'vless-reality\nmixed\nhy2\nanytls\nsocks\nhttp' ]]
[[ "$(protocol_registry_field mixed client_export)" == true ]]
[[ "$(protocol_registry_field mixed multi_instance)" == true ]]
[[ -z "$(protocol_registry_field mixed subman_type)" ]]
[[ "$(protocol_registry_field socks client_export)" == true ]]
[[ "$(protocol_registry_field socks multi_instance)" == true ]]
[[ "$(protocol_registry_field socks menu_order)" == 5 ]]
[[ "$(protocol_registry_field socks default_tag)" == socks-in ]]
[[ "$(protocol_registry_field socks handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field socks handlers)" == *apply_plain_proxy_instance_change* ]]
[[ "$(protocol_registry_field http menu_order)" == 6 ]]
[[ "$(protocol_registry_field http default_tag)" == http-in ]]
[[ "$(protocol_registry_field http state_id)" == http ]]
[[ "$(protocol_registry_field http listen_networks)" == tcp ]]
[[ "$(protocol_registry_field http handlers)" == *load_plain_proxy_structured_instance* ]]
[[ "$(protocol_registry_field http handlers)" == *apply_plain_proxy_instance_change* ]]

# Unknown protocol and future schema must not disappear during reconciliation.
for invalid in $'INSTALLED_PROTOCOLS=mixed,future-protocol\nPROTOCOL_STATE_VERSION=1' \
  $'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=9'; do
  printf '%s\n' "${invalid}" > "${SB_PROTOCOL_INDEX_FILE}"
  cp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
  for handler in reconcile_protocol_index_if_needed list_installed_protocols list_effective_protocols list_exportable_client_protocols rebuild_protocol_state_from_config; do
    if "${handler}" > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr"; then
      printf 'unknown state accepted by %s\n' "${handler}" >&2
      exit 1
    fi
    cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
    [[ ! -s "${TEST_DIR}/unknown.stdout" ]]
  done
done
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'CONFIG_SCHEMA_VERSION=1\n' > "${SB_PROTOCOL_STATE_DIR}/future.env"
cp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
if rebuild_protocol_state_from_config > /dev/null 2>&1; then
  printf 'unindexed unknown state was accepted for destructive rebuild\n' >&2
  exit 1
fi
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
[[ -f "${SB_PROTOCOL_STATE_DIR}/future.env" ]]
rm "${SB_PROTOCOL_STATE_DIR}/future.env"

printf '{"inbounds":[]}\n' > "${SINGBOX_CONFIG_FILE}"
mv "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${TEST_DIR}/mixed.saved"
for handler in reconcile_protocol_index_if_needed list_installed_protocols; do
  if "${handler}" > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr"; then
    printf 'failed stale-index recovery was reported as success\n' >&2
    exit 1
  fi
  cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
  [[ ! -s "${TEST_DIR}/unknown.stdout" ]]
done
for handler in reconcile_protocol_index_if_needed list_installed_protocols; do
  status=0
  (
    rebuild_protocol_state_from_config() { return 47; }
    "${handler}"
  ) > "${TEST_DIR}/unknown.stdout" 2> "${TEST_DIR}/unknown.stderr" || status=$?
  [[ "${status}" -eq 47 ]]
  cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
done
mv "${TEST_DIR}/mixed.saved" "${SB_PROTOCOL_STATE_DIR}/mixed.env"

printf '{"inbounds":[{"type":"mixed","tag":"keep-mixed"}]}\n' > "${SINGBOX_CONFIG_FILE}"
mv "${SB_PROTOCOL_STATE_DIR}/mixed.env" "${TEST_DIR}/mixed.saved"
if reconcile_protocol_index_if_needed > /dev/null 2>&1; then
  printf 'a live inbound without state was dropped from the index\n' >&2
  exit 1
fi
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TEST_DIR}/index.before"
mv "${TEST_DIR}/mixed.saved" "${SB_PROTOCOL_STATE_DIR}/mixed.env"
printf 'INSTALLED_PROTOCOLS=mixed\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf 'CONFIG_SCHEMA_VERSION=99\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
if load_protocol_state mixed read-only > /dev/null 2>&1 || reconcile_protocol_index_if_needed > /dev/null 2>&1; then
  printf 'future per-protocol schema was accepted\n' >&2
  exit 1
fi

# A present handler with empty/wrong output must fail as firmly as a missing one.
build_mixed_inbound_json() { :; }
if append_protocol_fragment mixed inbound "${TEST_DIR}/fragments" 2>/dev/null; then
  printf 'empty inbound was accepted\n' >&2
  exit 1
fi
build_mixed_inbound_json() { printf '{"type":"vless","tag":"mixed-in"}\n'; }
if append_protocol_fragment mixed inbound "${TEST_DIR}/fragments" 2>/dev/null; then
  printf 'wrong inbound type was accepted\n' >&2
  exit 1
fi
build_mixed_inbound_json() { printf '{"type":"mixed","tag":"mixed-in"}\n'; }
append_protocol_fragment mixed inbound "${TEST_DIR}/fragments"
append_protocol_fragment mixed certificate "${TEST_DIR}/certificates"
[[ ! -s "${TEST_DIR}/certificates" || -z "$(tr -d '[:space:]' < "${TEST_DIR}/certificates")" ]]
build_protocol_route_rules() { :; }
if append_protocol_fragment mixed route "${TEST_DIR}/routes" 2>/dev/null; then
  printf 'missing route array was accepted\n' >&2
  exit 1
fi
unset -f build_mixed_inbound_json
if append_protocol_fragment mixed inbound "${TEST_DIR}/fragments" 2>/dev/null; then
  printf 'missing handler was accepted\n' >&2
  exit 1
fi

# Partial discovery output followed by failure must never become a live config.
printf '#!/usr/bin/env bash\nexit 91\n' > "${SINGBOX_BIN_PATH}"
chmod 700 "${SINGBOX_BIN_PATH}"
printf '{"preserve":"unknown-state"}\n' > "${SINGBOX_CONFIG_FILE}"
cp "${SINGBOX_CONFIG_FILE}" "${TEST_DIR}/config.before"
list_effective_protocols() { printf 'mixed\n'; return 23; }
ensure_warp_routing_assets() { touch "${SB_PROJECT_DIR}/unexpected-prepare"; }
if generate_config > "${TEST_DIR}/generate.stdout" 2> "${TEST_DIR}/generate.stderr"; then
  printf 'discovery failure published a partial configuration\n' >&2
  exit 1
fi
cmp "${SINGBOX_CONFIG_FILE}" "${TEST_DIR}/config.before"
[[ ! -e "${SB_PROJECT_DIR}/unexpected-prepare" && ! -e "${SINGBOX_CONFIG_FILE}.bak" ]]

printf 'protocol registry and fail-closed contracts passed\n'
