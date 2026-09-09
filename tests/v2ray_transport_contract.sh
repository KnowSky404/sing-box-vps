#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
# Source at top level so readonly arrays stay global under Bash 4.2.  The
# helper's function wrapper makes those declarations function-scoped there.
source "${TESTABLE_INSTALL}"

fail() {
  printf 'v2ray transport contract: %s\n' "$1" >&2
  exit 1
}

assert_valid() {
  local label=$1
  local transport_json=$2
  local output status
  output=''
  status=0
  output=$(validate_v2ray_transport_state_json "${transport_json}" 2>"${TMP_DIR}/${label}.stderr") || status=$?
  (( status == 0 )) || fail "${label} should be valid (status ${status})"
  [[ -z "${output}" ]] || fail "${label} emitted validator diagnostics on stdout"
  [[ ! -s "${TMP_DIR}/${label}.stderr" ]] || fail "${label} emitted validator diagnostics on stderr"
}

assert_invalid() {
  local label=$1
  local transport_json=$2
  local output status
  output=''
  status=0
  output=$(validate_v2ray_transport_state_json "${transport_json}" 2>"${TMP_DIR}/${label}.stderr") || status=$?
  (( status != 0 )) || fail "${label} should be rejected"
  [[ -z "${output}" ]] || fail "${label} emitted validator diagnostics on stdout"
  [[ ! -s "${TMP_DIR}/${label}.stderr" ]] || fail "${label} emitted validator diagnostics on stderr"
}

assert_profile() {
  local label=$1
  local family=$2
  local transport_json=$3
  local tls_mode=$4
  local flow=$5
  local version=$6
  local expected=$7
  local output status
  output=''
  status=0
  output=$(build_v2ray_transport_profile_json "${family}" "${transport_json}" "${tls_mode}" "${flow}" "${version}" \
    2>"${TMP_DIR}/${label}.stderr") || status=$?
  (( status == 0 )) || fail "${label} should be a valid profile (status ${status})"
  [[ ! -s "${TMP_DIR}/${label}.stderr" ]] || fail "${label} emitted profile diagnostics on stderr"
  jq -e "${expected}" >/dev/null <<<"${output}" || fail "${label} had an unexpected profile"
}

assert_profile_invalid() {
  local label=$1
  local family=$2
  local transport_json=$3
  local tls_mode=$4
  local flow=$5
  local version=$6
  local secret=${7:-}
  local output status
  output=''
  status=0
  output=$(build_v2ray_transport_profile_json "${family}" "${transport_json}" "${tls_mode}" "${flow}" "${version}" \
    2>"${TMP_DIR}/${label}.stderr") || status=$?
  (( status != 0 )) || fail "${label} should be rejected"
  [[ -z "${output}" ]] || fail "${label} emitted rejected profile JSON on stdout"
  if [[ -n "${secret}" ]] && grep -Fq -- "${secret}" "${TMP_DIR}/${label}.stderr"; then
    fail "${label} echoed a secret in diagnostics"
  fi
}

assert_validator_arity_invalid() {
  local label=$1
  local output status
  output=''
  status=0
  if [[ "${label}" == no_args ]]; then
    output=$(validate_v2ray_transport_state_json >"${TMP_DIR}/${label}.stdout" 2>"${TMP_DIR}/${label}.stderr") || status=$?
  else
    output=$(validate_v2ray_transport_state_json '{}' extra >"${TMP_DIR}/${label}.stdout" 2>"${TMP_DIR}/${label}.stderr") || status=$?
  fi
  (( status != 0 )) || fail "validator ${label} should reject invalid arity"
  [[ ! -s "${TMP_DIR}/${label}.stdout" && ! -s "${TMP_DIR}/${label}.stderr" ]] || \
    fail "validator ${label} emitted diagnostics"
}

assert_builder_arity_invalid() {
  local label=$1
  local output status
  output=''
  status=0
  if [[ "${label}" == no_args ]]; then
    output=$(build_v2ray_transport_profile_json >"${TMP_DIR}/${label}.stdout" 2>"${TMP_DIR}/${label}.stderr") || status=$?
  else
    output=$(build_v2ray_transport_profile_json vmess '{"type":"none"}' disabled '' 1.14.0 extra \
      >"${TMP_DIR}/${label}.stdout" 2>"${TMP_DIR}/${label}.stderr") || status=$?
  fi
  (( status != 0 )) || fail "profile builder ${label} should reject invalid arity"
  [[ ! -s "${TMP_DIR}/${label}.stdout" ]] || fail "profile builder ${label} emitted rejected JSON"
}

# Seed a content sentinel as well as a path snapshot: pure validators and
# profile builders must neither create state nor rewrite existing state.
printf 'state-sentinel\n' > "${TMP_DIR}/project/sentinel"
STATE_BEFORE=$(find "${TMP_DIR}/project" -mindepth 0 -print | sort)
STATE_SENTINEL_BEFORE=$(sha256sum "${TMP_DIR}/project/sentinel")

# The contract is exactly one JSON object, with a bounded input string.  The
# validator itself is deliberately silent: callers decide how to diagnose a
# rejected typed record.
assert_valid none '{"type":"none"}'
assert_valid quic '{"type":"quic"}'
assert_invalid empty ''
assert_invalid empty_object '{}'
assert_invalid array_root '[]'
assert_invalid multiple_roots $'{"type":"none"}\n{"type":"none"}'
assert_invalid malformed '{"type":"none"'
assert_invalid type_number '{"type":7}'
assert_invalid unknown_type '{"type":"tcp"}'
assert_validator_arity_invalid no_args
assert_validator_arity_invalid extra_arg

printf -v oversized_value '%*s' 65537 ''
assert_invalid oversized "{\"type\":\"http\",\"path\":\"/${oversized_value}\"}"

# Valid transport records preserve meaningful text and supported fields.  The
# special characters below are header data, not shell syntax, and are checked
# semantically after the profile is built.
HTTP_JSON=$(jq -cn \
  --arg host '例え.example' \
  --arg header '值; comma, quote " dollar $ ampersand &' \
  '{type:"http",host:[$host,"fallback.example"],path:"/api/v1",method:"GET",headers:{"X-Display":$header,"X-List":["one","two"]},idle_timeout:"86400s",ping_timeout:"1m24s"}')
WS_JSON=$(jq -cn \
  --arg header '早期数据:你好; quote="; dollar=$' \
  '{type:"ws",path:"/socket",headers:{"Host":"例え.テスト","X-Display":$header},max_early_data:2048,early_data_header_name:"Sec-WebSocket-Protocol"}')
WS_UNICODE_EARLY_JSON=$(jq -cn \
  '{type:"ws",path:"/你好 space",max_early_data:2048,early_data_header_name:"X-Early-Data"}')
GRPC_JSON='{"type":"grpc","service_name":"svc.v1-test","idle_timeout":"0","ping_timeout":"1.000s","permit_without_stream":false}'
HTTPUPGRADE_JSON='{"type":"httpupgrade","host":"upgrade.example","path":"/upgrade","headers":{"X-Test":"ok"}}'

assert_valid http_valid "${HTTP_JSON}"
assert_valid ws_valid "${WS_JSON}"
assert_valid ws_unicode_with_header_early_data "${WS_UNICODE_EARLY_JSON}"
assert_valid grpc_valid "${GRPC_JSON}"
assert_valid httpupgrade_valid "${HTTPUPGRADE_JSON}"
assert_valid http_empty_optional '{"type":"http","host":[],"path":"","method":"","headers":{}}'
assert_valid ws_empty_optional '{"type":"ws","path":"","headers":{},"max_early_data":0,"early_data_header_name":""}'
assert_valid grpc_empty_optional '{"type":"grpc","service_name":""}'
assert_valid httpupgrade_empty_optional '{"type":"httpupgrade","host":"","path":"","headers":{}}'

# Unknown keys are rejected for every registered transport type, so an
# unrecognized core option cannot silently pass through the typed boundary.
for transport_type in none quic http ws grpc httpupgrade; do
  assert_invalid "unknown_${transport_type}" "{\"type\":\"${transport_type}\",\"x_unknown\":\"secret-value\"}"
done
SECRET='transport-secret-should-not-leak'
SECRET_JSON=$(jq -cn --arg secret "${SECRET}" '{type:"http",headers:{"X-Secret":$secret},unknown:$secret}')
assert_invalid unknown_secret "${SECRET_JSON}"

# All string and array fields have type, character, and size contracts.
assert_invalid http_host_number '{"type":"http","host":7}'
assert_invalid http_host_empty_string '{"type":"http","host":""}'
assert_invalid http_host_bad_chars '{"type":"http","host":"a/b"}'
assert_invalid http_host_array_bad_entry '{"type":"http","host":["good.example",""]}'
assert_invalid http_path_no_slash '{"type":"http","path":"api"}'
assert_invalid http_path_query '{"type":"http","path":"/api?x=1"}'
assert_invalid http_path_fragment '{"type":"http","path":"/api#fragment"}'
assert_invalid http_method_bad_chars '{"type":"http","method":"GET HTTP"}'
assert_invalid http_header_value_number '{"type":"http","headers":{"X-Test":7}}'
assert_invalid http_headers_number '{"type":"http","headers":7}'
assert_invalid http_path_number '{"type":"http","path":7}'
assert_invalid http_method_number '{"type":"http","method":7}'
assert_invalid http_header_array_empty '{"type":"http","headers":{"X-Test":[]}}'
assert_invalid http_header_array_bad_entry '{"type":"http","headers":{"X-Test":["ok",7]}}'
assert_invalid grpc_service_bad_chars '{"type":"grpc","service_name":"svc/name"}'
assert_invalid grpc_permit_true '{"type":"grpc","permit_without_stream":true}'
assert_invalid httpupgrade_host_bad_chars '{"type":"httpupgrade","host":"bad host"}'
assert_invalid ws_unicode_without_early_header '{"type":"ws","path":"/你好"}'
assert_invalid ws_space_without_early_header '{"type":"ws","path":"/space path"}'

# Header names are case-insensitive, and request-hop headers are never
# accepted. Host is special: it is allowed only by WebSocket transport.
assert_invalid headers_case_collision '{"type":"http","headers":{"X-Test":"one","x-test":"two"}}'
assert_invalid http_host_header '{"type":"http","headers":{"Host":"example.com"}}'
assert_valid ws_host_header '{"type":"ws","headers":{"Host":"例え.テスト"}}'
assert_invalid ws_bad_host_header '{"type":"ws","headers":{"Host":"bad host"}}'
for hop_header in connection upgrade content-length transfer-encoding keep-alive te trailer \
  sec-websocket-key sec-websocket-accept sec-websocket-version sec-websocket-extensions \
  proxy-connection content-encoding expect; do
  assert_invalid "http_hop_${hop_header//-/_}" "{\"type\":\"http\",\"headers\":{\"${hop_header}\":\"x\"}}"
  assert_invalid "ws_hop_${hop_header//-/_}" "{\"type\":\"ws\",\"headers\":{\"${hop_header}\":\"x\"}}"
done
assert_invalid http_hop_sec_websocket_protocol '{"type":"http","headers":{"Sec-WebSocket-Protocol":"x"}}'
assert_valid ws_subprotocol_string '{"type":"ws","headers":{"Sec-WebSocket-Protocol":"chat.v1"}}'
assert_valid ws_subprotocol_array '{"type":"ws","headers":{"Sec-WebSocket-Protocol":["chat.v1"]}}'
assert_invalid ws_subprotocol_empty '{"type":"ws","headers":{"Sec-WebSocket-Protocol":""}}'
assert_invalid ws_subprotocol_array_empty '{"type":"ws","headers":{"Sec-WebSocket-Protocol":[]}}'
assert_invalid ws_subprotocol_array_multiple '{"type":"ws","headers":{"Sec-WebSocket-Protocol":["one","two"]}}'
assert_invalid ws_subprotocol_bad_token '{"type":"ws","headers":{"Sec-WebSocket-Protocol":"chat protocol"}}'
assert_invalid ws_subprotocol_early_data_collision '{"type":"ws","max_early_data":1,"early_data_header_name":"Sec-WebSocket-Protocol","headers":{"Sec-WebSocket-Protocol":"chat.v1"}}'
INJECTED_HEADER=$(jq -cn --arg value $'ok\r\nInjected: yes' '{type:"http",headers:{"X-Test":$value}}')
assert_invalid header_injection "${INJECTED_HEADER}"
assert_invalid header_bad_name '{"type":"http","headers":{"Bad Name":"x"}}'
assert_invalid http_method_head '{"type":"http","method":"HEAD"}'
assert_invalid http_method_connect '{"type":"http","method":"CONNECT"}'

HEADERS_64=$(jq -cn 'reduce range(0;64) as $i ({}; .["X-Header-" + ($i|tostring)] = "x")')
HEADERS_65=$(jq -cn 'reduce range(0;65) as $i ({}; .["X-Header-" + ($i|tostring)] = "x")')
assert_valid headers_64 "{\"type\":\"http\",\"headers\":${HEADERS_64}}"
assert_invalid headers_65 "{\"type\":\"http\",\"headers\":${HEADERS_65}}"
HEADER_VALUES_32=$(jq -cn 'range(0;32) | "v"' | jq -sc '.')
HEADER_VALUES_33=$(jq -cn 'range(0;33) | "v"' | jq -sc '.')
assert_valid header_values_32 "{\"type\":\"http\",\"headers\":{\"X-Test\":${HEADER_VALUES_32}}}"
assert_invalid header_values_33 "{\"type\":\"http\",\"headers\":{\"X-Test\":${HEADER_VALUES_33}}}"

# Durations accept zero and exact 24-hour totals, but reject negative, unitless,
# malformed, or overflowing values rather than clamping them.
for duration in 0 86400s 86400000ms 1.000s 1m24s; do
  assert_valid "duration_valid_${duration//[^[:alnum:]]/_}" "{\"type\":\"http\",\"idle_timeout\":\"${duration}\"}"
done
for duration in 86401s 86400001ms -1s 1 0.5 1xs 999999999999999999999999999h; do
  assert_invalid "duration_invalid_${duration//[^[:alnum:]]/_}" "{\"type\":\"http\",\"idle_timeout\":\"${duration}\"}"
done
assert_invalid duration_number '{"type":"http","idle_timeout":1}'

# WebSocket early data is enabled only with a positive size and a non-reserved
# header name that does not collide with ordinary headers.
assert_valid ws_early_data_boundary '{"type":"ws","max_early_data":65536,"early_data_header_name":"X-Early-Data"}'
assert_valid ws_early_data_zero_no_header '{"type":"ws","max_early_data":0}'
assert_invalid ws_early_data_negative '{"type":"ws","max_early_data":-1}'
assert_invalid ws_early_data_fractional '{"type":"ws","max_early_data":1.5}'
assert_invalid ws_early_data_too_large '{"type":"ws","max_early_data":65537}'
assert_invalid ws_early_header_without_size '{"type":"ws","early_data_header_name":"X-Early-Data"}'
assert_invalid ws_early_header_zero_size '{"type":"ws","max_early_data":0,"early_data_header_name":"X-Early-Data"}'
assert_invalid ws_early_header_reserved '{"type":"ws","max_early_data":1,"early_data_header_name":"Host"}'
assert_invalid ws_early_header_hop '{"type":"ws","max_early_data":1,"early_data_header_name":"Connection"}'
for early_header in proxy-connection content-encoding expect; do
  assert_invalid "ws_early_header_${early_header//-/_}" \
    "{\"type\":\"ws\",\"max_early_data\":1,\"early_data_header_name\":\"${early_header}\"}"
done
assert_invalid ws_early_header_collision '{"type":"ws","max_early_data":1,"early_data_header_name":"x-early-data","headers":{"X-Early-Data":"already-present"}}'
assert_invalid ws_early_header_bad_name '{"type":"ws","max_early_data":1,"early_data_header_name":"Bad Name"}'
assert_invalid ws_early_header_bad_type '{"type":"ws","max_early_data":1,"early_data_header_name":7}'
assert_valid ws_early_data_exponent '{"type":"ws","max_early_data":1e3,"early_data_header_name":"X-Early-Data"}'
assert_valid ws_early_data_decimal_integral '{"type":"ws","max_early_data":1.0,"early_data_header_name":"X-Early-Data"}'

# The profile builder validates the same typed record and maps transports to
# the core-facing network, ALPN, and build-tag requirements.
assert_profile native_vless vless '{"type":"none"}' reality xtls-rprx-vision 1.14.0 \
  '.transport == null and .listen_networks == ["tcp"] and .tls_alpn == [] and .required_build_tags == []'
assert_profile native_vmess vmess '{"type":"none"}' disabled '' v1.13.0 \
  '.transport == null and .listen_networks == ["tcp"] and .tls_alpn == [] and .required_build_tags == []'
assert_profile native_trojan trojan '{"type":"none"}' tls '' 1.14.0 \
  '.transport == null and .listen_networks == ["tcp"] and .tls_alpn == [] and .required_build_tags == []'
assert_profile quic_tls vmess '{"type":"quic"}' tls '' 1.14.0 \
  '.transport.type == "quic" and .listen_networks == ["udp"] and .tls_alpn == ["h3"] and .required_build_tags == ["with_quic"]'
assert_profile http_tls vmess "${HTTP_JSON}" tls '' 1.14.0 \
  '.transport.type == "http" and .listen_networks == ["tcp"] and .tls_alpn == ["h2"] and .transport.headers["X-Display"] == "值; comma, quote \" dollar $ ampersand &"'
assert_profile ws_tls trojan '{"type":"ws","path":"/socket","headers":{"Host":"例え.テスト"}}' tls '' 1.14.0 \
  '.transport.type == "ws" and .listen_networks == ["tcp"] and .tls_alpn == ["http/1.1"] and .transport.headers.Host == "例え.テスト"'
assert_profile grpc_tls vless "${GRPC_JSON}" tls '' 1.14.0 \
  '.transport.type == "grpc" and .listen_networks == ["tcp"] and .tls_alpn == ["h2"]'
assert_profile_invalid httpupgrade_tls trojan "${HTTPUPGRADE_JSON}" tls '' 1.14.0
assert_profile_invalid httpupgrade_plain vmess "${HTTPUPGRADE_JSON}" disabled '' 1.13.18
for family in vmess trojan vless; do
  for security in tls disabled; do
    assert_profile_invalid "ws_early_${family}_${security}" "${family}" "${WS_JSON}" "${security}" '' 1.14.0
    assert_profile_invalid "ws_path_early_${family}_${security}" "${family}" \
      '{"type":"ws","path":"/socket","max_early_data":1}' "${security}" '' 1.13.18
  done
done
inspection=$(inspect_v2ray_transport_profile_json vmess "${WS_UNICODE_EARLY_JSON}" disabled '' 1.13.18)
jq -e --argjson original "${WS_UNICODE_EARLY_JSON}" '
  .transport == $original and .runtime_guard.status == "blocked" and
  .runtime_guard.code == "ws_early_data_runtime_unreliable"' <<< "${inspection}" >/dev/null
inspection=$(inspect_v2ray_transport_profile_json trojan "${HTTPUPGRADE_JSON}" tls '' 1.14.0)
jq -e '.transport.type == "httpupgrade" and .listen_networks == ["tcp"] and
  .tls_alpn == ["http/1.1"] and .runtime_guard.status == "blocked" and
  .runtime_guard.code == "httpupgrade_runtime_unreliable"' <<< "${inspection}" >/dev/null
assert_profile native_disabled_transport vmess '{"type":"none"}' disabled '' 1.14.0 \
  '.transport == null and .listen_networks == ["tcp"]'

# Security, flow, family, and supported-version compatibility are explicit;
# the old VLESS alias remains the REALITY preset and is not accepted as a
# generic family name.
[[ "$(normalize_protocol_id vless)" == "vless-reality" ]] || fail 'vless alias no longer normalizes to vless-reality'
[[ "$(normalize_protocol_id vless+reality)" == "vless-reality" ]] || fail 'vless+reality no longer normalizes to vless-reality'
assert_profile_invalid reality_on_vmess vmess '{"type":"none"}' reality '' 1.14.0
assert_profile_invalid reality_on_ws vless '{"type":"ws"}' reality '' 1.14.0
assert_profile_invalid flow_on_trojan trojan '{"type":"none"}' tls xtls-rprx-vision 1.14.0
assert_profile_invalid flow_on_ws vless '{"type":"ws"}' tls xtls-rprx-vision 1.14.0
assert_profile_invalid flow_disabled vless '{"type":"none"}' disabled xtls-rprx-vision 1.14.0
assert_profile_invalid invalid_flow vless '{"type":"none"}' tls bad-flow 1.14.0
assert_profile_invalid quic_disabled vmess '{"type":"quic"}' disabled '' 1.14.0
assert_profile_invalid quic_reality vmess '{"type":"quic"}' reality '' 1.14.0
assert_profile_invalid bad_family vless-reality '{"type":"none"}' disabled '' 1.14.0
assert_profile_invalid bad_family_empty '' '{"type":"none"}' disabled '' 1.14.0
assert_profile_invalid bad_security vmess '{"type":"none"}' self-signed '' 1.14.0
assert_profile_invalid old_core vmess '{"type":"none"}' disabled '' 1.12.99
assert_profile_invalid above_max_core vmess '{"type":"none"}' disabled '' 1.14.1
assert_profile_invalid malformed_core vmess '{"type":"none"}' disabled '' 1.14
assert_profile_invalid latest_core vmess '{"type":"none"}' disabled '' latest
assert_profile_invalid invalid_profile_secret vmess "${SECRET_JSON}" disabled '' 1.14.0 "${SECRET}"
assert_builder_arity_invalid no_args
assert_builder_arity_invalid extra_arg

MALICIOUS_VERSION='$(touch '"${TMP_DIR}"'/v2ray-version-command-executed)'
assert_profile_invalid malicious_version vmess '{"type":"none"}' disabled '' "${MALICIOUS_VERSION}"
[[ ! -e "${TMP_DIR}/v2ray-version-command-executed" ]] || fail 'malicious version input was executed'
if grep -Fq -- "${MALICIOUS_VERSION}" "${TMP_DIR}/malicious_version.stderr"; then
  fail 'malicious version input was echoed in diagnostics'
fi

STATE_AFTER=$(find "${TMP_DIR}/project" -mindepth 0 -print 2>/dev/null | sort)
[[ "${STATE_BEFORE}" == "${STATE_AFTER}" ]] || fail 'transport validation/profile calls mutated managed state'
STATE_SENTINEL_AFTER=$(sha256sum "${TMP_DIR}/project/sentinel")
[[ "${STATE_SENTINEL_BEFORE}" == "${STATE_SENTINEL_AFTER}" ]] || fail 'transport calls rewrote existing managed state'

# The deployable protocol registry includes the validated Trojan, Snell, TUIC,
# Hysteria v1 and NaiveProxy adapters; the transport helper must not add any
# other family as a side effect.
registered_protocols=''
registry_status=0
registered_protocols=$(list_registered_protocols) || registry_status=$?
(( registry_status == 0 )) || fail "protocol registry producer failed (status ${registry_status})"
expected_registered_protocols=$'vless-reality\nvless-plain\nmixed\nhy2\nanytls\nsocks\nhttp\nshadowsocks\ntrojan\nvmess\nsnell\ntuic\nhysteria\nnaive'
[[ "${registered_protocols}" == "${expected_registered_protocols}" ]] || \
  fail "unexpected protocol appeared in the deployable protocol registry: ${registered_protocols}"

printf 'v2ray transport contract: PASS\n'
