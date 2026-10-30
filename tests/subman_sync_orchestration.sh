#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
# Source at file scope: Bash 4.2 keeps the installer's readonly registry
# global; sourcing through the helper function makes it function-local.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

ensure_protocol_state_dir
write_protocol_index "vless-reality,mixed,hy2,anytls"

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-vless'
PORT=443
UUID='11111111-1111-1111-1111-111111111111'
SNI='www.cloudflare.com'
REALITY_PRIVATE_KEY='private-key'
REALITY_PUBLIC_KEY='public-key'
SHORT_ID_1='abcd1234'
SHORT_ID_2='dcba4321'
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-mixed'
PORT=2080
AUTH_ENABLED='y'
USERNAME='mixed-user'
PASSWORD='mixed-pass'
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-hy2'
PORT=8443
DOMAIN='hy2.example.com'
PASSWORD='hy2-password'
USER_NAME='hy2-user'
UP_MBPS=''
DOWN_MBPS=''
OBFS_ENABLED='y'
OBFS_TYPE='salamander'
OBFS_PASSWORD='obfs-password'
TLS_MODE='self-signed'
ACME_MODE=''
ACME_EMAIL=''
ACME_DOMAIN=''
DNS_PROVIDER=''
CF_API_TOKEN=''
CERT_PATH=''
KEY_PATH=''
MASQUERADE='https://bing.com'
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME='edge-anytls'
PORT=9443
DOMAIN='anytls.example.com'
PASSWORD='anytls-password'
USER_NAME='anytls-user'
TLS_MODE='self-signed'
ACME_MODE=''
ACME_EMAIL=''
ACME_DOMAIN=''
DNS_PROVIDER=''
CF_API_TOKEN=''
CERT_PATH=''
KEY_PATH=''
EOF

load_protocol_state "mixed"

prompt_subman_config_if_needed() {
  SUBMAN_API_URL="https://subman.example.com"
  SUBMAN_API_TOKEN="secret-token"
  SUBMAN_NODE_PREFIX="edge-1"
}

get_public_ip() {
  printf '203.0.113.10\n'
}

get_public_ipv4() {
  printf '203.0.113.10\n'
}

get_public_ipv6() {
  printf '2001:db8::10\n'
}

detect_host_ip_stack() {
  printf 'dual\n'
}

PUSH_KEYS_FILE="${TMP_DIR}/subman-push-keys.txt"
PUSH_PAYLOADS_FILE="${TMP_DIR}/subman-push-payloads.jsonl"
CLEANUP_KEYS_FILE="${TMP_DIR}/subman-cleanup-keys.txt"
push_subman_node() {
  local external_key=$1
  local payload_json=$2

  printf '%s\n' "${external_key}" >> "${PUSH_KEYS_FILE}"
  printf '%s\n' "${payload_json}" >> "${PUSH_PAYLOADS_FILE}"
}

delete_subman_node_by_external_key() {
  printf '%s\n' "$1" >> "${CLEANUP_KEYS_FILE}"
}

SB_INBOUND_STACK_MODE="dual_stack"
output=$(push_nodes_to_subman 2>&1)

if [[ "${output}" != *"SubMan 推送完成：已同步: 4，已跳过: 2，失败: 0"* ]]; then
  printf 'expected push summary for 4 synced, 2 skipped, 0 failed, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "$(wc -l < "${PUSH_KEYS_FILE}")" -ne 4 ]]; then
  printf 'expected exactly 4 node upserts, got keys:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if ! grep -Fxq "sing-box-vps:edge-1:vless-reality:v4" "${PUSH_KEYS_FILE}"; then
  printf 'expected vless-reality IPv4 external key, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if ! grep -Fxq "sing-box-vps:edge-1:vless-reality:v6" "${PUSH_KEYS_FILE}"; then
  printf 'expected vless-reality IPv6 external key, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if ! grep -Fxq "sing-box-vps:edge-1:vless-reality" "${CLEANUP_KEYS_FILE}"; then
  printf 'expected legacy vless-reality external key deletion, got:\n%s\n' "$(cat "${CLEANUP_KEYS_FILE}")" >&2
  exit 1
fi

if ! grep -Fxq "sing-box-vps:edge-1:hy2:v4" "${PUSH_KEYS_FILE}" ||
   ! grep -Fxq "sing-box-vps:edge-1:hy2:v6" "${PUSH_KEYS_FILE}"; then
  printf 'expected family-specific hy2 external keys, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if grep -Eq "mixed|anytls" "${PUSH_KEYS_FILE}"; then
  printf 'expected mixed and anytls not to be pushed, got:\n%s\n' "$(cat "${PUSH_KEYS_FILE}")" >&2
  exit 1
fi

if [[ "$(jq -r 'select(.type == "vless" and .name == "edge-vless-v4") | .raw' "${PUSH_PAYLOADS_FILE}")" != vless://*203.0.113.10*"#edge-vless-v4" ]]; then
  printf 'expected vless payload raw link, got:\n%s\n' "$(cat "${PUSH_PAYLOADS_FILE}")" >&2
  exit 1
fi

if [[ "$(jq -r 'select(.type == "vless" and .name == "edge-vless-v6") | .raw' "${PUSH_PAYLOADS_FILE}")" != vless://*"2001:db8::10"*"#edge-vless-v6" ]]; then
  printf 'expected vless IPv6 payload raw link, got:\n%s\n' "$(cat "${PUSH_PAYLOADS_FILE}")" >&2
  exit 1
fi

if jq -e 'select(.raw == "")' "${PUSH_PAYLOADS_FILE}" >/dev/null; then
  printf 'expected every SubMan upsert payload to keep a non-empty raw value, got:\n%s\n' "$(cat "${PUSH_PAYLOADS_FILE}")" >&2
  exit 1
fi

if ! jq -se '
  [.[] | select(.type == "hysteria2")] as $hy2 |
  ($hy2 | length == 2)
  and any($hy2[]; .name == "edge-hy2-v4"
    and (.raw | startswith("hy2://hy2-password@203.0.113.10:8443?"))
    and (.raw | contains("sni=hy2.example.com"))
    and (.raw | endswith("#edge-hy2-v4")))
  and any($hy2[]; .name == "edge-hy2-v6"
    and (.raw | startswith("hy2://hy2-password@[2001:db8::10]:8443?"))
    and (.raw | contains("sni=hy2.example.com"))
    and (.raw | endswith("#edge-hy2-v6")))
' "${PUSH_PAYLOADS_FILE}" >/dev/null; then
  printf 'expected HY2 connection IPs to follow each family while preserving domain SNI, got:\n%s\n' "$(cat "${PUSH_PAYLOADS_FILE}")" >&2
  exit 1
fi

if [[ "${SB_PROTOCOL}" != "mixed" || "${SB_NODE_NAME}" != "edge-mixed" ]]; then
  printf 'expected original protocol state to be restored, got protocol=%s node=%s\n' "${SB_PROTOCOL}" "${SB_NODE_NAME}" >&2
  exit 1
fi

printf '' > "${PUSH_KEYS_FILE}"
printf '' > "${PUSH_PAYLOADS_FILE}"
printf '' > "${CLEANUP_KEYS_FILE}"

push_subman_node() {
  local external_key=$1
  local payload_json=$2

  if [[ "${external_key}" == *":v6" ]]; then
    SUBMAN_LAST_OUTCOME="unknown-outcome"
    SUBMAN_LAST_ERROR_CODE="gist_write_failed"
    SUBMAN_LAST_ERROR_DISPOSITION="retryable-upstream"
    SUBMAN_LAST_HTTP_STATUS="502"
    return 1
  fi
  SUBMAN_LAST_NODE_ID="node-${external_key##*:}"
  SUBMAN_LAST_GIST_ID="gist-1"
  SUBMAN_LAST_REVISION="23"
  SUBMAN_LAST_OUTCOME="committed"
  printf '%s\n' "${external_key}" >> "${PUSH_KEYS_FILE}"
  printf '%s\n' "${payload_json}" >> "${PUSH_PAYLOADS_FILE}"
}

set +e
partial_output=$(push_nodes_to_subman 2>&1)
partial_status=$?
set -e
if [[ "${partial_status}" -eq 0 || "${partial_output}" != *"已同步: 2，已跳过: 2，失败: 2"* ]]; then
  printf 'expected partial dual-stack failure to be reported, got status=%s output:\n%s\n' "${partial_status}" "${partial_output}" >&2
  exit 1
fi
if [[ -s "${CLEANUP_KEYS_FILE}" ]]; then
  printf 'expected partial dual-stack sync to preserve the legacy fallback key, got:\n%s\n' "$(cat "${CLEANUP_KEYS_FILE}")" >&2
  exit 1
fi

SUBMAN_NODE_PREFIX="edge-1"
set +e
partial_agent_json=$(agent_push_nodes_to_subman_json)
partial_agent_status=$?
set -e
if [[ "${partial_agent_status}" -eq 0 ]]; then
  printf 'expected agent SubMan sync to fail for the partial dual-stack write\n' >&2
  exit 1
fi
if ! jq -e '
  .ok == false
  and .failed == 2
  and (.results | length == 4)
  and ([.results[] | select(.outcome == "committed")] | length == 2)
  and any(.results[]; .external_key == "sing-box-vps:edge-1:vless-reality:v4"
    and .node_id == "node-v4" and .gist_id == "gist-1" and .revision == 23)
  and any(.results[]; .external_key == "sing-box-vps:edge-1:vless-reality:v6"
    and .outcome == "unknown-outcome" and .node_id == null
    and .error.code == "gist_write_failed")
  and any(.results[]; .external_key == "sing-box-vps:edge-1:hy2:v6"
    and .outcome == "unknown-outcome" and .node_id == null
    and .error.code == "gist_write_failed")
  and all(.results[]; has("raw") | not)
  and .last_error.code == "gist_write_failed"
  and .last_error.disposition == "retryable-upstream"
  and .last_error.http_status == "502"
' >/dev/null <<< "${partial_agent_json}"; then
  printf 'expected agent JSON to retain the stable SubMan failure, got:\n%s\n' "${partial_agent_json}" >&2
  exit 1
fi

push_subman_node() {
  local external_key=$1
  local payload_json=$2

  printf '%s\n' "${external_key}" >> "${PUSH_KEYS_FILE}"
  printf '%s\n' "${payload_json}" >> "${PUSH_PAYLOADS_FILE}"
}

printf '' > "${PUSH_KEYS_FILE}"
printf '' > "${PUSH_PAYLOADS_FILE}"
printf '' > "${CLEANUP_KEYS_FILE}"

get_public_ip() {
  printf 'unexpected generic IP fallback\n' >> "${TMP_DIR}/generic-ip-calls"
  printf '198.51.100.20\n'
}

get_public_ipv4() {
  printf ''
}

get_public_ipv6() {
  printf ''
}

load_protocol_state "mixed"
set +e
fallback_output=$(push_nodes_to_subman 2>&1)
fallback_status=$?
set -e

if [[ "${fallback_status}" -eq 0 || "${fallback_output}" != *"SubMan 推送完成：已同步: 0，已跳过: 2，失败: 2"* ]]; then
  printf 'expected missing family candidates to fail both supported protocols, got status=%s output:\n%s\n' \
    "${fallback_status}" "${fallback_output}" >&2
  exit 1
fi

if [[ -s "${PUSH_KEYS_FILE}" || -s "${PUSH_PAYLOADS_FILE}" || -s "${TMP_DIR}/generic-ip-calls" ]]; then
  printf 'expected missing family candidates to prevent writes and generic fallback\n' >&2
  exit 1
fi

if [[ -s "${CLEANUP_KEYS_FILE}" ]]; then
  printf 'expected failed address discovery to preserve all legacy keys, got:\n%s\n' "$(cat "${CLEANUP_KEYS_FILE}")" >&2
  exit 1
fi

if missing_addresses_json=$(agent_push_nodes_to_subman_json); then
  printf 'expected Agent sync without family candidates to fail\n' >&2
  exit 1
fi
jq -e '.ok == false and .synced == 0 and .skipped == 2 and .failed == 2
  and (.results | length == 2)
  and ([.results[].protocol] | sort) == ["hy2", "vless-reality"]
  and all(.results[]; .outcome == "failed" and .external_key == null
    and .error.code == "public_ip_unavailable")
  and .last_error.code == "public_ip_unavailable"' <<< "${missing_addresses_json}" >/dev/null

# A failed selector for one protocol must remain a failure when another
# protocol synchronizes successfully. Process-substitution loops used to lose
# this status and could report the partial batch as successful.
(
  list_subman_addresses_for_current_protocol() {
    case "${SB_PROTOCOL}" in
      vless+reality|vless-reality) return 1 ;;
      *) printf 'IPv4|198.51.100.20\n' ;;
    esac
  }
  : > "${CLEANUP_KEYS_FILE}"
  if selection_partial_output=$(push_nodes_to_subman 2>&1); then
    printf 'expected one missing protocol address to fail a partially synchronized batch\n' >&2
    exit 1
  fi
  [[ "${selection_partial_output}" == *'已同步: 1，已跳过: 2，失败: 1'* ]] || {
    printf 'expected successful HY2 and failed REALITY discovery counts, got:\n%s\n' \
      "${selection_partial_output}" >&2
    exit 1
  }
  [[ ! -s "${CLEANUP_KEYS_FILE}" ]]
  if selection_partial_json=$(agent_push_nodes_to_subman_json); then
    printf 'expected Agent partial address-selection failure to remain unsuccessful\n' >&2
    exit 1
  fi
  jq -e '.ok == false and .synced == 1 and .skipped == 2 and .failed == 1
    and (.results | length == 2)
    and any(.results[]; .protocol == "vless-reality" and .outcome == "failed"
      and .error.code == "public_ip_unavailable")
    and any(.results[]; .external_key == "sing-box-vps:edge-1:hy2:v4"
      and .outcome == "committed")
    and .last_error.code == "public_ip_unavailable"' <<< "${selection_partial_json}" >/dev/null
)

get_public_ip() {
  printf ''
}

get_public_ipv4() {
  printf ''
}

get_public_ipv6() {
  printf ''
}

push_subman_node() {
  printf 'push_subman_node should not be called when public IP is empty\n' >&2
  return 99
}

set +e
empty_ip_output=$(push_nodes_to_subman 2>&1)
empty_ip_status=$?
set -e

if [[ "${empty_ip_status}" -eq 0 ]]; then
  printf 'expected SubMan sync without public IP to fail\n' >&2
  exit 1
fi

if [[ "${empty_ip_output}" != *"未获取到公网 IP"* && "${empty_ip_output}" != *"无法生成 SubMan 节点链接"* ]]; then
  printf 'expected empty public IP output to explain links cannot be generated, got:\n%s\n' "${empty_ip_output}" >&2
  exit 1
fi

if [[ "${empty_ip_output}" == *"push_subman_node should not be called"* ]]; then
  printf 'expected no SubMan push call when public IP is empty, got:\n%s\n' "${empty_ip_output}" >&2
  exit 1
fi

# Shadowsocks skips are a real result, not an empty public-IP discovery.  Keep
# both interactive and Agent orchestration diagnostics/counts explicit.
write_protocol_index "shadowsocks"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/shadowsocks.env"
jq -n '{schema_version:1,protocol:"shadowsocks",revision:1,default_instance_id:"ss-none",
  instances:[{id:"ss-none",name:"SS none",tag:"ss-none",listen:{address:"127.0.0.1",port:18081,network:["tcp","udp"]},
    authentication:{method:"none",password:"",users:[]},outbound_policy:"default",dependencies:[]}]}' \
  > "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
chmod 600 "${SB_PROTOCOL_STATE_DIR}/shadowsocks.env" "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
load_protocol_state "shadowsocks"

set +e
ss_empty_ip_output=$(push_nodes_to_subman 2>&1)
ss_empty_ip_status=$?
set -e
if [[ "${ss_empty_ip_status}" -eq 0 || "${ss_empty_ip_output}" != *"已同步: 0，已跳过: 1，失败: 0"* ]]; then
  printf 'expected Shadowsocks skip summary without public-IP diagnostic, got status=%s output:\n%s\n' \
    "${ss_empty_ip_status}" "${ss_empty_ip_output}" >&2
  exit 1
fi
if [[ "${ss_empty_ip_output}" == *"未获取到公网 IP"* ]]; then
  printf 'expected Shadowsocks skip not to be reported as public-IP discovery failure, got:\n%s\n' \
    "${ss_empty_ip_output}" >&2
  exit 1
fi

set +e
ss_agent_empty_ip_output=$(agent_push_nodes_to_subman_json)
ss_agent_empty_ip_status=$?
set -e
if [[ "${ss_agent_empty_ip_status}" -eq 0 ]]; then
  printf 'expected Agent Shadowsocks-only skip result to remain unsuccessful\n' >&2
  exit 1
fi
if ! jq -e '
  .ok == false and .synced == 0 and .skipped == 1 and .failed == 0
  and any(.warnings[]?; .code == "shadowsocks_subman_none_unsupported")
' >/dev/null <<< "${ss_agent_empty_ip_output}"; then
  printf 'expected Agent Shadowsocks skip warning/count, got:\n%s\n' "${ss_agent_empty_ip_output}" >&2
  exit 1
fi
if [[ "${ss_agent_empty_ip_output}" == *"public_ip_unavailable"* ]]; then
  printf 'expected Agent Shadowsocks skip not to use public_ip_unavailable, got:\n%s\n' \
    "${ss_agent_empty_ip_output}" >&2
  exit 1
fi

# An unsupported HTTP instance must be reported without fabricating an API
# type or preventing the existing VLESS/Hysteria2 nodes from synchronizing.
write_protocol_index "vless-reality,mixed,hy2,anytls,http"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${SB_PROTOCOL_STATE_DIR}/http.env"
jq -n '{schema_version:1,protocol:"http",revision:1,default_instance_id:"main",
  instances:[{id:"main",name:"HTTP",tag:"http-in",listen:{address:"127.0.0.1",port:18080},
    authentication:{enabled:true,username:"http-user",password:"http-secret"},
    tls:{enabled:false},outbound_policy:"default",dependencies:[]}]}' \
  > "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
http_state_hash=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/http.json")
get_public_ip() { printf '198.51.100.20\n'; }
get_public_ipv4() { printf '198.51.100.20\n'; }
get_public_ipv6() { printf ''; }
push_subman_node() {
  printf '%s\n' "$1" >> "${PUSH_KEYS_FILE}"
  printf '%s\n' "$2" >> "${PUSH_PAYLOADS_FILE}"
}
: > "${PUSH_KEYS_FILE}"
: > "${PUSH_PAYLOADS_FILE}"
http_output=$(push_nodes_to_subman 2>&1)
[[ "${http_output}" == *'已同步: 2，已跳过: 3，失败: 0'* ]]
[[ "${http_output}" == *'SubMan 暂不支持协议，已跳过: http'* ]]
[[ "${http_output}" != *http-secret* ]]
[[ "$(wc -l < "${PUSH_KEYS_FILE}")" == 2 ]]
jq -es 'length == 2 and all(.[]; .type == "vless" or .type == "hysteria2")' \
  "${PUSH_PAYLOADS_FILE}" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/http.json")" == "${http_state_hash}" ]]

# Unsupported-only Agent sync must preserve the per-protocol skip reason.  It
# must not misclassify a truthful zero-sync result as public-IP discovery
# failure, because no URI construction was attempted for either protocol.
write_protocol_index "http,anytls"
get_public_ip() { printf ''; }
set +e
unsupported_only_agent=$(agent_push_nodes_to_subman_json)
unsupported_only_status=$?
set -e
if [[ "${unsupported_only_status}" -eq 0 ]]; then
  printf 'expected unsupported-only Agent sync to remain unsuccessful\n' >&2
  exit 1
fi
jq -e '
  .ok == false and .synced == 0 and .skipped == 2 and .failed == 0
  and (.error // "") != "public_ip_unavailable"
  and ([.warnings[]? | select(.code == "subman_protocol_unsupported") | .protocol] | sort)
      == ["anytls", "http"]
' <<< "${unsupported_only_agent}" >/dev/null || {
  printf 'expected per-protocol unsupported warnings, got:\n%s\n' "${unsupported_only_agent}" >&2
  exit 1
}

# A generated key that cannot fit the server marker budget is a local failure,
# with enough metadata to identify the node and no attempted write.
(
  SUBMAN_NODE_PREFIX=$(printf 'x%.0s' {1..120})
  SUBMAN_NODE_RESULTS_JSON='[]'
  : > "${PUSH_KEYS_FILE}"
  if push_subman_protocol_instance vless-reality 198.51.100.20 main y IPv4; then
    printf 'expected oversized generated key to fail before a write\n' >&2
    exit 1
  fi
  [[ ! -s "${PUSH_KEYS_FILE}" ]]
  [[ "${SUBMAN_LAST_ERROR_CODE}" == invalid_external_key ]]
  jq -e 'length == 1 and .[0].external_key == null and .[0].outcome == "failed"
    and .[0].protocol == "vless-reality" and .[0].instance_id == "main"
    and .[0].address_label == "IPv4" and .[0].error.code == "invalid_external_key"' \
    <<< "${SUBMAN_NODE_RESULTS_JSON}" >/dev/null
)

# A lost or invalid cleanup receipt must retain the legacy key/ID and mutation
# outcome alongside the preceding successful dual-stack upserts.
(
  write_protocol_index vless-reality
  SUBMAN_NODE_PREFIX=edge-1
  SB_INBOUND_STACK_MODE=dual_stack
  get_public_ip() { printf '198.51.100.20\n'; }
  get_public_ipv4() { printf '198.51.100.20\n'; }
  get_public_ipv6() { printf '2001:db8::20\n'; }
  push_subman_node() {
    SUBMAN_LAST_NODE_ID="node-${1##*:}"
    SUBMAN_LAST_GIST_ID=gist-1
    SUBMAN_LAST_REVISION=24
    SUBMAN_LAST_OUTCOME=committed
  }
  delete_subman_node_by_external_key() {
    SUBMAN_LAST_NODE_ID=legacy-node
    SUBMAN_LAST_HTTP_STATUS=200
    SUBMAN_LAST_ERROR_CODE=revision_contract_mismatch
    SUBMAN_LAST_ERROR_DISPOSITION=operator-repair
    SUBMAN_LAST_OUTCOME=unknown-outcome
    return 1
  }
  if cleanup_json=$(agent_push_nodes_to_subman_json); then
    printf 'expected uncertain legacy deletion to fail the batch\n' >&2
    exit 1
  fi
  jq -e '.ok == false and .synced == 2 and .failed == 1
    and (.results | length == 3)
    and ([.results[] | select(.operation == "upsert" and .outcome == "committed")] | length == 2)
    and any(.results[]; .operation == "delete" and .external_key == "sing-box-vps:edge-1:vless-reality"
      and .node_id == "legacy-node" and .outcome == "unknown-outcome"
      and .error.code == "revision_contract_mismatch")' <<< "${cleanup_json}" >/dev/null
)

# Batch results can exceed Linux's per-argument limit. Preserve all earlier
# successes when appending metadata and rendering the final Agent response.
(
  bulk_results=$(jq -cn '[range(0;2000) | {operation:"upsert",external_key:("bulk-"+tostring),node_id:("node-"+tostring),outcome:"committed",gist_id:"gist-1",revision:1}]')
  [[ "$(printf '%s' "${bulk_results}" | wc -c)" -gt 131072 ]]
  list_installed_protocols() { printf 'vless-plain\n'; }
  protocol_state_exists() { return 0; }
  load_protocol_state() { return 0; }
  push_subman_vless_plain_protocol() {
    SUBMAN_NODE_RESULTS_JSON=${bulk_results}
    SUBMAN_LAST_OUTCOME=committed
    SUBMAN_LAST_NODE_ID=final-node
    SUBMAN_LAST_GIST_ID=gist-1
    SUBMAN_LAST_REVISION=2
    SUBMAN_LAST_ERROR_CODE=''
    record_subman_node_result final-key || return 1
    SUBMAN_VLESS_PLAIN_SYNCED=2001
    SUBMAN_VLESS_PLAIN_SKIPPED=0
    SUBMAN_VLESS_PLAIN_FAILED=0
    SUBMAN_VLESS_PLAIN_WARNINGS_JSON='[]'
  }
  bulk_response=$(agent_push_nodes_to_subman_json)
  jq -e '.ok == true and .synced == 2001 and .failed == 0
    and (.results | length == 2001)
    and .results[0].external_key == "bulk-0"
    and .results[-1].external_key == "final-key"
    and .results[-1].node_id == "final-node"' <<< "${bulk_response}" >/dev/null
)
