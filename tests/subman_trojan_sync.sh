#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "Trojan SubMan sync failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/trojan.json"
state_file="${SB_PROTOCOL_STATE_DIR}/trojan.env"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"

jq -n '
  {schema_version:1,protocol:"trojan",revision:21,default_instance_id:"system-none",instances:[
    {id:"system-none",name:"System none",tag:"trojan-none",listen:{address:"127.0.0.1",port:33501},authentication:{users:[{name:"alice",password:"alice-secret"}]},tls:{enabled:true,server_name:"none.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"system-ws",name:"System WS",tag:"trojan-ws",listen:{address:"0.0.0.0",port:33502},authentication:{users:[{name:"alice",password:"alice-secret"},{name:"bob",password:("é" * 2048)}]},tls:{enabled:true,server_name:"ws.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"system",transport:{type:"ws",path:("/" + ("a" * 4095)),headers:{Host:"ws.example"}},outbound_policy:"direct",dependencies:[]},
    {id:"system-grpc",name:"System gRPC",tag:"trojan-grpc",listen:{address:"127.0.0.1",port:33503},authentication:{users:[{name:"grpc",password:"grpc-secret"}]},tls:{enabled:true,server_name:"grpc.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"system",transport:{type:"grpc",service_name:"trojan-service"},outbound_policy:"warp",dependencies:[]},
    {id:"system-quic",name:"System QUIC",tag:"trojan-quic",listen:{address:"127.0.0.1",port:33504},authentication:{users:[{name:"quic",password:"quic-secret"}]},tls:{enabled:true,server_name:"quic.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"system",transport:{type:"quic"},outbound_policy:"default",dependencies:[]},
    {id:"plaintext",name:"Plaintext",tag:"trojan-plain",listen:{address:"127.0.0.1",port:33505},authentication:{users:[{name:"plain",password:"plain-secret"}]},tls:{enabled:false},client_trust:"system",transport:{type:"none"},outbound_policy:"default",dependencies:[]},
    {id:"pinned",name:"Pinned",tag:"trojan-pinned",listen:{address:"127.0.0.1",port:33506},authentication:{users:[{name:"pinned",password:"pinned-secret"}]},tls:{enabled:true,server_name:"pinned.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"certificate",transport:{type:"ws",path:"/pinned",headers:{Host:"pinned.example"}},outbound_policy:"default",dependencies:[]},
    {id:"custom-header",name:"Custom header",tag:"trojan-custom",listen:{address:"127.0.0.1",port:33507},authentication:{users:[{name:"custom",password:"custom-secret"}]},tls:{enabled:true,server_name:"custom.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"},client_trust:"system",transport:{type:"ws",path:"/custom",headers:{Host:"custom.example","X-Extra":"do-not-drop"}},outbound_policy:"default",dependencies:[]}
  ]}
' > "${store_file}"
chmod 600 "${store_file}" "${state_file}"
printf '%s\n' INSTALLED_PROTOCOLS=trojan PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
chmod 600 "${SB_PROTOCOL_INDEX_FILE}"

validate_structured_instance_store trojan "${store_file}"
save_plain_proxy_structured_marker trojan
SUBMAN_NODE_PREFIX='trojan-sync'
list_subman_addresses_for_current_protocol() { printf 'IPv4|198.51.100.21\n'; }
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_node() {
  MOCK_KEYS+=( "${1}" )
  MOCK_PAYLOADS+=( "${2}" )
  return 0
}

push_subman_trojan_protocol y
[[ "${SUBMAN_TROJAN_SYNCED}" == 4 ]]
[[ "${SUBMAN_TROJAN_SKIPPED}" == 4 ]]
[[ "${SUBMAN_TROJAN_FAILED}" == 0 ]]
[[ ${#MOCK_PAYLOADS[@]} -eq 4 ]]
jq -e 'length >= 3 and all(.[]; (.code|startswith("trojan_")))' <<< "${SUBMAN_TROJAN_WARNINGS_JSON}" >/dev/null
printf '%s\n' "${MOCK_PAYLOADS[@]}" | jq -s -e 'all(.[]; .type == "trojan" and .source == "single" and .enabled == true and (.raw|startswith("trojan://")))' >/dev/null
! printf '%s\n' "${MOCK_KEYS[@]}" | grep -Eq 'alice|bob|secret'
! printf '%s\n' "${MOCK_PAYLOADS[@]}" | grep -Eq 'private.key|X-Extra|pinned-secret|plain-secret'

ws_payload_count=0
for payload in "${MOCK_PAYLOADS[@]}"; do
  if [[ "$(jq -r '.raw' <<< "${payload}")" == *'@198.51.100.21:33502'* ]]; then
    ws_payload_count=$((ws_payload_count + 1))
  fi
done
[[ "${ws_payload_count}" == 1 ]]

# The interactive aggregate path must account for per-user skips as well.  An
# all-certificate store has no URI-shareable user, so it returns non-zero with
# a truthful zero-sync/skipped-only summary rather than claiming missing IP or
# silently succeeding.
store_before_certificate=$(<"${store_file}")
jq '.instances |= map(.client_trust = "certificate" | .tls = {enabled:true,server_name:"all-cert.example",certificate_path:"/etc/ssl/public.crt",key_path:"/etc/ssl/private.key"})' "${store_file}" > "${TMP_DIR}/certificate-store.json"
mv "${TMP_DIR}/certificate-store.json" "${store_file}"
prompt_subman_config_if_needed() { :; }
if all_certificate_output=$(push_nodes_to_subman 2>"${TMP_DIR}/all-certificate.stderr"); then
  printf 'All-skipped interactive sync falsely succeeded\n' >&2
  exit 1
fi
grep -Fq '已同步: 0' <<< "${all_certificate_output}"
if ! grep -Fq '已跳过: 8' <<< "${all_certificate_output}"; then
  printf 'Unexpected all-certificate summary: %s\n' "${all_certificate_output}" >&2
  cat "${TMP_DIR}/all-certificate.stderr" >&2
  exit 1
fi
grep -Fq '失败: 0' <<< "${all_certificate_output}"
! grep -Fq '公网 IP' <<< "${all_certificate_output}"
collect_hy2_compatibility_warnings_json() { printf '[]'; }
all_certificate_agent=$(agent_push_nodes_to_subman_json || true)
jq -e '.ok == false and .synced == 0 and .skipped == 8 and .failed == 0 and (.warnings|length)==8 and (.error // "") != "public_ip_unavailable"' \
  <<< "${all_certificate_agent}" >/dev/null
printf '%s' "${store_before_certificate}" > "${store_file}"
partial_interactive=$(push_nodes_to_subman)
grep -Fq '已同步: 4，已跳过: 4，失败: 0' <<< "${partial_interactive}"

# Oversized URI is a structured per-user skip (status 23), not a malformed
# typed record; the other valid user remains eligible for sync.
MOCK_KEYS=(); MOCK_PAYLOADS=()
push_subman_trojan_instance system-ws 198.51.100.21 y IPv4
[[ "${SUBMAN_TROJAN_SYNCED}" == 1 && "${SUBMAN_TROJAN_SKIPPED}" == 1 && "${SUBMAN_TROJAN_FAILED}" == 0 ]]
jq -e 'length == 1 and .[0].type == "trojan"' < <(printf '%s\n' "${MOCK_PAYLOADS[@]}" | jq -s .) >/dev/null
jq -e 'length == 1 and .[0].code == "trojan_uri_too_large" and .[0].instance_id == "system-ws" and any(.[]; .outbound_tag|startswith("trojan-system-ws-user-"))' <<< "${SUBMAN_TROJAN_WARNINGS_JSON}" >/dev/null

if build_trojan_subman_uri_from_store "${store_file}" 198.51.100.21 system-ws bob 'System WS'; then
  printf 'Oversized Trojan URI was accepted\n' >&2
  exit 1
else
  uri_status=$?
  [[ "${uri_status}" == 23 ]]
fi

# Capture the instance-specific keys independently of the aggregate sync; the
# key format is an implementation detail, but its bytes must be stable.
MOCK_KEYS=(); MOCK_PAYLOADS=()
push_subman_trojan_instance system-ws 203.0.113.77 y IPv4
before_keys=$(printf '%s\n' "${MOCK_KEYS[@]}" | sort)

jq '.instances |= map(if .id == "system-ws" then .authentication.users |= reverse else . end)'   "${store_file}" > "${TMP_DIR}/reordered.json"
mv "${TMP_DIR}/reordered.json" "${store_file}"
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_trojan_instance system-ws 203.0.113.77 y IPv4
after_keys=$(printf '%s\n' "${MOCK_KEYS[@]}" | sort)
[[ "${before_keys}" == "${after_keys}" ]]
for payload in "${MOCK_PAYLOADS[@]}"; do
  [[ "$(jq -r '.raw' <<< "${payload}")" == *'@203.0.113.77:33502'* ]]
done

original_builder=$(declare -f build_trojan_client_outbounds_from_store)
eval "${original_builder/build_trojan_client_outbounds_from_store/original_build_trojan_client_outbounds_from_store}"
build_trojan_client_outbounds_from_store() { return 73; }
MOCK_KEYS=()
MOCK_PAYLOADS=()
if push_subman_trojan_instance system-ws 198.51.100.21 y IPv4; then
  printf 'Trojan producer failure was reported as success\n' >&2
  exit 1
fi
[[ "${SUBMAN_TROJAN_SYNCED}" == 0 && "${SUBMAN_TROJAN_FAILED}" == 1 ]]
eval "$(declare -f original_build_trojan_client_outbounds_from_store | sed '1s/^original_build_trojan_client_outbounds_from_store /build_trojan_client_outbounds_from_store /')"

push_subman_node() {
  MOCK_KEYS+=( "${1}" )
  MOCK_PAYLOADS+=( "${2}" )
  if [[ "${1}" == *'user-'* ]]; then
    SUBMAN_LAST_ERROR_CODE=mock_failure
    SUBMAN_LAST_ERROR_DISPOSITION=retryable-upstream
    return 1
  fi
  return 0
}
MOCK_KEYS=()
MOCK_PAYLOADS=()
if push_subman_trojan_instance system-ws 198.51.100.21 y IPv4; then
  printf 'Trojan SubMan partial failure was reported as success\n' >&2
  exit 1
fi
[[ "${SUBMAN_TROJAN_SYNCED}" == 0 && "${SUBMAN_TROJAN_SKIPPED}" == 1 && "${SUBMAN_TROJAN_FAILED}" == 1 ]]

printf 'Trojan SubMan sync checks passed: synced=4 skipped=4 stable-user-keys=1\n'
