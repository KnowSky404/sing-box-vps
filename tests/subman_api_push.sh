#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

REAL_CURL_BIN=$(command -v curl)
setup_menu_test_env 120
source_testable_install

cleanup_subman_api_test() {
  if [[ -n "${SUBMAN_MOCK_PID:-}" ]] && kill -0 "${SUBMAN_MOCK_PID}" 2>/dev/null; then
    kill "${SUBMAN_MOCK_PID}"
    wait "${SUBMAN_MOCK_PID}" || [[ "$?" -eq 143 ]]
  fi
  rm -rf "${TMP_DIR}"
}
trap cleanup_subman_api_test EXIT

CURL_CALLS_FILE="${TMP_DIR}/curl-calls.txt"
CURL_CONFIG_FILE="${TMP_DIR}/curl-config.txt"
CURL_CONFIG_MODE_FILE="${TMP_DIR}/curl-config-mode.txt"
CURL_PAYLOAD_FILE="${TMP_DIR}/curl-payload.json"
CURL_PAYLOAD_MODE_FILE="${TMP_DIR}/curl-payload-mode.txt"
CURL_TEMP_PATHS_FILE="${TMP_DIR}/curl-temp-paths.txt"
CURL_RESPONSE_DIR="${TMP_DIR}/curl-responses"
CURL_METHOD_COUNT_DIR="${TMP_DIR}/curl-counts"
mkdir -p "${CURL_RESPONSE_DIR}" "${CURL_METHOD_COUNT_DIR}"
: > "${CURL_CALLS_FILE}"
: > "${CURL_TEMP_PATHS_FILE}"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash

method="GET"
url=""
config_file=""
data_file=""
headers_file=""
body_file=""

while (($# > 0)); do
  case "$1" in
    -X)
      shift
      method=${1:-}
      ;;
    --config)
      shift
      config_file=${1:-}
      ;;
    --data-binary)
      shift
      data_file=${1#@}
      ;;
    -D)
      shift
      headers_file=${1:-}
      ;;
    -o)
      shift
      body_file=${1:-}
      ;;
    http://*|https://*)
      url=$1
      ;;
  esac
  shift || true
done

if [[ -z "${config_file}" || ! -f "${config_file}" ]]; then
  printf 'expected curl --config file\n' >&2
  exit 91
fi
if [[ -z "${headers_file}" || -z "${body_file}" ]]; then
  printf 'expected separate response header and body files\n' >&2
  exit 92
fi
if ! grep -Fxq 'header = "Authorization: Bearer secret-token"' "${config_file}"; then
  printf 'expected Authorization header in curl config\n' >&2
  exit 93
fi

printf '%s\t%s\n' "${method}" "${url}" >> "${CURL_CALLS_FILE}"
printf '%s\n' "${config_file}" >> "${CURL_TEMP_PATHS_FILE}"
cp "${config_file}" "${CURL_CONFIG_FILE}"
stat -c '%a' "${config_file}" > "${CURL_CONFIG_MODE_FILE}"
if [[ -n "${data_file}" ]]; then
  if ! grep -Fxq 'header = "Content-Type: application/json"' "${config_file}"; then
    printf 'expected Content-Type header for JSON request\n' >&2
    exit 94
  fi
  cp "${data_file}" "${CURL_PAYLOAD_FILE}"
  printf '%s\n' "${data_file}" >> "${CURL_TEMP_PATHS_FILE}"
  stat -c '%a' "${data_file}" > "${CURL_PAYLOAD_MODE_FILE}"
fi

count_file="${CURL_METHOD_COUNT_DIR}/${method}"
count=0
[[ -f "${count_file}" ]] && count=$(cat "${count_file}")
count=$((count + 1))
printf '%s' "${count}" > "${count_file}"

response_prefix="${CURL_RESPONSE_DIR}/${method}.${count}"
if [[ ! -f "${response_prefix}.status" ]]; then
  response_prefix="${CURL_RESPONSE_DIR}/${method}"
fi

cp "${response_prefix}.headers" "${headers_file}"
cp "${response_prefix}.body" "${body_file}"
if [[ -s "${response_prefix}.stderr" ]]; then
  cat "${response_prefix}.stderr" >&2
fi
printf '%s' "$(cat "${response_prefix}.status")"
exit "$(cat "${response_prefix}.exit")"
EOF
chmod +x "${TMP_DIR}/bin/curl"
export CURL_CALLS_FILE CURL_CONFIG_FILE CURL_CONFIG_MODE_FILE CURL_PAYLOAD_FILE CURL_PAYLOAD_MODE_FILE CURL_TEMP_PATHS_FILE
export CURL_RESPONSE_DIR CURL_METHOD_COUNT_DIR

set_mock_response() {
  local method=$1
  local sequence=$2
  local status=$3
  local body=$4
  local headers=${5:-}
  local exit_status=${6:-0}
  local prefix="${CURL_RESPONSE_DIR}/${method}"

  [[ -n "${sequence}" ]] && prefix="${prefix}.${sequence}"
  printf '%s\n' "${status}" > "${prefix}.status"
  printf '%s\n' "${body}" > "${prefix}.body"
  printf '%b' "${headers}" > "${prefix}.headers"
  : > "${prefix}.stderr"
  printf '%s\n' "${exit_status}" > "${prefix}.exit"
}

reset_method_counts() {
  rm -f "${CURL_METHOD_COUNT_DIR}"/*
}

SUBMAN_API_URL=" https://subman.example.com/// "
SUBMAN_API_TOKEN="secret-token"
SUBMAN_EXPECTED_GIST_ID="gist-1"
payload_json='{"name":"edge-1","type":"vless","raw":"vless://example","enabled":true,"tags":["sing-box-vps"],"source":"single"}'
success_body='{"data":{"id":"node-1","name":"edge-1","type":"vless","raw":"vless://example","enabled":true,"tags":[{"id":"external-key","label":"external:sing-box-vps:edge-1:vless-reality"}],"updatedAt":"2026-07-30T00:00:00.000Z","source":"single"},"workspace":{"gistId":"gist-1","file":"subman.json","revision":13}}'
success_headers='HTTP/2 200\r\nETag: "subman-revision-13"\r\nX-SubMan-Revision: 13\r\nCache-Control: no-store\r\n\r\n'
preflight_body='{"data":[],"workspace":{"gistId":"gist-1","file":"subman.json","revision":12}}'
preflight_headers='HTTP/2 200\r\nETag: "subman-revision-12"\r\nX-SubMan-Revision: 12\r\nCache-Control: no-store\r\n\r\n'
set_mock_response "GET" "" "200" "${preflight_body}" "${preflight_headers}"
set_mock_response "PUT" "" "200" "${success_body}" "${success_headers}"

success_output_file="${TMP_DIR}/success-output.txt"
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${success_output_file}" 2>&1
success_output=$(cat "${success_output_file}")
if [[ "${success_output}" != *"HTTP 200, Workspace revision 13"* ]]; then
  printf 'expected committed revision success output, got:\n%s\n' "${success_output}" >&2
  exit 1
fi
if [[ "${SUBMAN_LAST_NODE_ID}" != "node-1" || "${SUBMAN_LAST_REVISION}" != "13" || "${SUBMAN_LAST_GIST_ID}" != "gist-1" || "${SUBMAN_LAST_OUTCOME}" != "committed" ]]; then
  printf 'expected committed node and revision metadata, got node=%s revision=%s\n' "${SUBMAN_LAST_NODE_ID}" "${SUBMAN_LAST_REVISION}" >&2
  exit 1
fi
if [[ "$(head -n 1 "${CURL_CALLS_FILE}")" != $'GET\thttps://subman.example.com/api/nodes' ]] || \
  ! grep -Fxq 'header = "If-Match: \"subman-revision-12\""' "${CURL_CONFIG_FILE}"; then
  printf 'expected expected-Gist preflight followed by conditional PUT\n' >&2
  exit 1
fi
if ! grep -Fxq $'PUT\thttps://subman.example.com/api/nodes/by-key/sing-box-vps%3Aedge-1%3Avless-reality' "${CURL_CALLS_FILE}"; then
  printf 'expected URL-encoded by-key PUT, got:\n%s\n' "$(cat "${CURL_CALLS_FILE}")" >&2
  exit 1
fi
if [[ "$(cat "${CURL_CONFIG_MODE_FILE}")" != "600" || "$(cat "${CURL_PAYLOAD_MODE_FILE}")" != "600" ]]; then
  printf 'expected curl config and payload modes to be 600\n' >&2
  exit 1
fi
if [[ "$(cat "${CURL_PAYLOAD_FILE}")" != "${payload_json}" ]]; then
  printf 'expected exact JSON payload to be read from the protected file\n' >&2
  exit 1
fi
if [[ "$(cat "${CURL_CALLS_FILE}")" == *"secret-token"* ]]; then
  printf 'expected curl argv record not to leak token\n' >&2
  exit 1
fi
while IFS= read -r temporary_path; do
  if [[ -e "${temporary_path}" ]]; then
    printf 'expected protected SubMan request file to be removed: %s\n' "${temporary_path}" >&2
    exit 1
  fi
done < "${CURL_TEMP_PATHS_FILE}"

encoded_success_body=${success_body/external:sing-box-vps:edge-1:vless-reality/external:sing-box-vps:edge 1\/hy2}
set_mock_response "PUT" "" "200" "${encoded_success_body}" "${success_headers}"
push_subman_node "sing-box-vps:edge 1/hy2" "${payload_json}" > "${TMP_DIR}/encoded-output.txt" 2>&1
if ! grep -Fxq $'PUT\thttps://subman.example.com/api/nodes/by-key/sing-box-vps%3Aedge%201%2Fhy2' "${CURL_CALLS_FILE}"; then
  printf 'expected spaces and slashes in external keys to be URL encoded\n' >&2
  exit 1
fi

set_mock_response "PUT" "" "200" "${success_body}" $'HTTP/2 200\r\n\r\n'
set +e
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/contract-output.txt" 2>&1
contract_status=$?
set -e
if [[ "${contract_status}" -eq 0 || "${SUBMAN_LAST_ERROR_CODE}" != "revision_contract_mismatch" ]]; then
  printf 'expected missing revision headers to fail the latest contract, got status=%s code=%s\n' "${contract_status}" "${SUBMAN_LAST_ERROR_CODE}" >&2
  exit 1
fi

error_body='{"error":{"code":"gist_write_failed","message":"rate limited","disposition":"retryable-upstream"},"workspace":{"revision":14}}'
error_headers='HTTP/2 429\r\nRetry-After: 60\r\nCache-Control: no-store\r\n\r\n'
set_mock_response "PUT" "" "429" "${error_body}" "${error_headers}"
set +e
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/error-output.txt" 2>&1
error_status=$?
set -e
if [[ "${error_status}" -eq 0 ]]; then
  printf 'expected structured API error to fail\n' >&2
  exit 1
fi
if [[ "${SUBMAN_LAST_ERROR_CODE}" != "gist_write_failed" || "${SUBMAN_LAST_ERROR_DISPOSITION}" != "retryable-upstream" || "${SUBMAN_LAST_RETRY_AFTER}" != "60" ]]; then
  printf 'expected stable error contract, got code=%s disposition=%s retry=%s\n' \
    "${SUBMAN_LAST_ERROR_CODE}" "${SUBMAN_LAST_ERROR_DISPOSITION}" "${SUBMAN_LAST_RETRY_AFTER}" >&2
  exit 1
fi
if [[ "$(cat "${TMP_DIR}/error-output.txt")" == *"secret-token"* ]]; then
  printf 'expected API error output not to leak token\n' >&2
  exit 1
fi

set_mock_response "PUT" "" "000" "" "" "6"
before_transport_calls=$(wc -l < "${CURL_CALLS_FILE}")
set +e
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/transport-output.txt" 2>&1
transport_status=$?
set -e
after_transport_calls=$(wc -l < "${CURL_CALLS_FILE}")
if [[ "${transport_status}" -eq 0 || "${SUBMAN_LAST_ERROR_DISPOSITION}" != "unknown-outcome" ]]; then
  printf 'expected transport failure to report an unknown outcome\n' >&2
  exit 1
fi
if [[ $((after_transport_calls - before_transport_calls)) -ne 3 ]]; then
  printf 'expected GET/PUT/GET for an uncertain write without a blind replay\n' >&2
  exit 1
fi

before_invalid_calls=$(wc -l < "${CURL_CALLS_FILE}")
set +e
push_subman_node "$(printf 'x%.0s' {1..120})" "${payload_json}" > "${TMP_DIR}/invalid-output.txt" 2>&1
invalid_status=$?
set -e
if [[ "${invalid_status}" -eq 0 || "${SUBMAN_LAST_ERROR_CODE}" != "invalid_external_key" ]]; then
  printf 'expected oversized external key to fail before request\n' >&2
  exit 1
fi
if [[ "$(wc -l < "${CURL_CALLS_FILE}")" -ne "${before_invalid_calls}" ]]; then
  printf 'expected invalid request not to invoke curl\n' >&2
  exit 1
fi

reserved_tag_payload='{"name":"edge-1","type":"vless","raw":"vless://example","tags":["external:caller-owned"]}'
set +e
push_subman_node "valid-key" "${reserved_tag_payload}" > "${TMP_DIR}/reserved-tag-output.txt" 2>&1
reserved_tag_status=$?
set -e
if [[ "${reserved_tag_status}" -eq 0 || "${SUBMAN_LAST_ERROR_CODE}" != "invalid_node_payload" ]]; then
  printf 'expected reserved external tag namespace to fail before request\n' >&2
  exit 1
fi

reset_method_counts
list_body='{"data":[{"id":"legacy-node","name":"legacy","type":"vless","raw":"vless://legacy","tags":[{"id":"external-old","label":"external:sing-box-vps:edge-1:vless-reality"}],"enabled":true,"updatedAt":"2026-07-30T00:00:00.000Z","source":"single"}],"workspace":{"gistId":"gist-1","file":"subman.json","revision":20}}'
list_headers='HTTP/2 200\r\nETag: "subman-revision-20"\r\nX-SubMan-Revision: 20\r\nCache-Control: no-store\r\n\r\n'
delete_body='{"data":{"deleted":true},"workspace":{"gistId":"gist-1","file":"subman.json","revision":21}}'
delete_headers='HTTP/2 200\r\nETag: "subman-revision-21"\r\nX-SubMan-Revision: 21\r\nCache-Control: no-store\r\n\r\n'
set_mock_response "GET" "" "200" "${list_body}" "${list_headers}"
set_mock_response "DELETE" "" "200" "${delete_body}" "${delete_headers}"

delete_subman_node_by_external_key "sing-box-vps:edge-1:vless-reality" > "${TMP_DIR}/delete-output.txt" 2>&1
if ! grep -Fxq $'DELETE\thttps://subman.example.com/api/nodes/legacy-node' "${CURL_CALLS_FILE}"; then
  printf 'expected legacy node cleanup through public DELETE endpoint\n' >&2
  exit 1
fi
if ! grep -Fxq 'header = "If-Match: \"subman-revision-20\""' "${CURL_CONFIG_FILE}"; then
  printf 'expected legacy delete to use the list response ETag, got:\n%s\n' "$(cat "${CURL_CONFIG_FILE}")" >&2
  exit 1
fi

reset_method_counts
conflict_body='{"error":{"code":"precondition_failed","message":"stale","disposition":"state-conflict"},"workspace":{"revision":21}}'
conflict_headers='HTTP/2 412\r\nCache-Control: no-store\r\n\r\n'
list_retry_body=${list_body/\"revision\":20/\"revision\":21}
list_retry_headers=${list_headers//20/21}
delete_retry_body=${delete_body/\"revision\":21/\"revision\":22}
delete_retry_headers=${delete_headers//21/22}
set_mock_response "GET" "1" "200" "${list_body}" "${list_headers}"
set_mock_response "DELETE" "1" "412" "${conflict_body}" "${conflict_headers}"
set_mock_response "GET" "2" "200" "${list_retry_body}" "${list_retry_headers}"
set_mock_response "DELETE" "2" "200" "${delete_retry_body}" "${delete_retry_headers}"

before_retry_calls=$(wc -l < "${CURL_CALLS_FILE}")
delete_subman_node_by_external_key "sing-box-vps:edge-1:vless-reality" "y"
after_retry_calls=$(wc -l < "${CURL_CALLS_FILE}")
if [[ $((after_retry_calls - before_retry_calls)) -ne 4 ]]; then
  printf 'expected one GET/DELETE retry after state conflict\n' >&2
  exit 1
fi
if ! grep -Fxq 'header = "If-Match: \"subman-revision-21\""' "${CURL_CONFIG_FILE}"; then
  printf 'expected retried delete to use the refreshed ETag\n' >&2
  exit 1
fi

# Exercise boundaries on the full, unencoded key, including multibyte text.
boundary_key=$(printf '节%.0s' {1..39})xx
[[ "$(printf '%s' "${boundary_key}" | wc -c)" -eq 119 ]]
validate_subman_node_request "${boundary_key}" "${payload_json}"
before_invalid_calls=$(wc -l < "${CURL_CALLS_FILE}")
if push_subman_node "${boundary_key}x" "${payload_json}" > "${TMP_DIR}/utf8-rejection.txt" 2>&1; then
  printf 'expected a 120-byte multibyte key to be rejected\n' >&2
  exit 1
fi
[[ "${SUBMAN_LAST_ERROR_CODE}" == "invalid_external_key" ]]
[[ "$(wc -l < "${CURL_CALLS_FILE}")" -eq "${before_invalid_calls}" ]]

tags_63_payload=$(jq -c '.tags = [range(0; 63) | "tag-\(.)"]' <<< "${payload_json}")
validate_subman_node_request valid-key "${tags_63_payload}"
repeated_tags_payload=$(jq -c '.tags += [" tag-0 ", {label: "tag-0"}]' <<< "${tags_63_payload}")
validate_subman_node_request valid-key "${repeated_tags_payload}"
tags_64_payload=$(jq -c '.tags += ["one-more"]' <<< "${tags_63_payload}")
if push_subman_node valid-key "${tags_64_payload}" > "${TMP_DIR}/tag-limit-rejection.txt" 2>&1; then
  printf 'expected 64 distinct caller labels to be rejected before PUT\n' >&2
  exit 1
fi
[[ "${SUBMAN_LAST_ERROR_CODE}" == "invalid_node_payload" ]]
[[ "$(wc -l < "${CURL_CALLS_FILE}")" -eq "${before_invalid_calls}" ]]
reserved_tag_payload=$(jq -c '.tags = [{label: " ExTeRnAl:caller-owned "}]' <<< "${payload_json}")
if validate_subman_node_request valid-key "${reserved_tag_payload}"; then
  printf 'expected trimmed reserved labels to be rejected\n' >&2
  exit 1
fi
reserved_tag_payload=$(jq -c '.tags = [{id: " ExTeRnAl:caller-owned ", label: "ordinary"}]' <<< "${payload_json}")
if validate_subman_node_request valid-key "${reserved_tag_payload}"; then
  printf 'expected reserved tag object IDs to be rejected\n' >&2
  exit 1
fi

rm -f "${CURL_RESPONSE_DIR}"/GET.[0-9]* "${CURL_RESPONSE_DIR}"/DELETE.[0-9]*
reset_method_counts
set_mock_response GET "" 200 "${preflight_body}" "${preflight_headers}"
set_mock_response PUT "" 200 "${success_body}" "${success_headers}"
before_guard_calls=$(wc -l < "${CURL_CALLS_FILE}")
SUBMAN_EXPECTED_GIST_ID=""
if push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/missing-gist.txt" 2>&1; then
  printf 'expected missing expected-Gist configuration to block all requests\n' >&2
  exit 1
fi
[[ "${SUBMAN_LAST_ERROR_CODE}" == "workspace_gist_required" ]]
[[ "$(wc -l < "${CURL_CALLS_FILE}")" -eq "${before_guard_calls}" ]]
SUBMAN_EXPECTED_GIST_ID="gist-1"
wrong_gist_body=${preflight_body/gist-1/gist-other}
set_mock_response GET "" 200 "${wrong_gist_body}" "${preflight_headers}"
if push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/wrong-gist.txt" 2>&1; then
  printf 'expected a wrong Gist to fail before writing\n' >&2
  exit 1
fi
[[ "${SUBMAN_LAST_ERROR_CODE}" == "workspace_gist_mismatch" && "${SUBMAN_LAST_OUTCOME}" == failed ]]
[[ "$(wc -l < "${CURL_CALLS_FILE}")" -eq $((before_guard_calls + 1)) ]]
if delete_subman_node_by_external_key legacy-key y; then
  printf 'expected a wrong Gist to block deletion\n' >&2
  exit 1
fi
[[ "$(wc -l < "${CURL_CALLS_FILE}")" -eq $((before_guard_calls + 2)) ]]

# Force mawk when available to reproduce the old IGNORECASE portability bug.
if command -v mawk >/dev/null 2>&1; then
  ln -s "$(command -v mawk)" "${TMP_DIR}/bin/awk"
fi
mixed_headers='HTTP/2 200\r\neTaG: "subman-revision-13"\r\nx-subman-revision: 13\r\ncache-CONTROL: private\r\nCACHE-control: NO-STORE\r\n\r\n'
set_mock_response GET "" 200 "${preflight_body}" "${preflight_headers}"
set_mock_response PUT "" 200 "${success_body}" "${mixed_headers}"
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/mixed-headers.txt" 2>&1
[[ "${SUBMAN_LAST_OUTCOME}" == committed && "${SUBMAN_LAST_REVISION}" == 13 ]]
set_mock_response PUT "" 429 "${error_body}" 'HTTP/2 429\r\nretry-after: 17\r\ncache-control: no-store\r\n\r\n'
if push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/lowercase-retry.txt" 2>&1; then
  printf 'expected rate limiting to remain a failed write\n' >&2
  exit 1
fi
[[ "${SUBMAN_LAST_RETRY_AFTER}" == 17 && "${SUBMAN_LAST_ERROR_CODE}" == gist_write_failed ]]

for contract_case in wrong-gist missing-cache wrong-revision wrong-marker; do
  response_body=${success_body}
  response_headers=${success_headers}
  expected_code=""
  case "${contract_case}" in
    wrong-gist)
      response_body=${success_body/gist-1/gist-other}
      expected_code=workspace_gist_mismatch
      ;;
    missing-cache)
      response_headers='HTTP/2 200\r\nETag: "subman-revision-13"\r\nX-SubMan-Revision: 13\r\nCache-Control: private\r\n\r\n'
      expected_code=cache_contract_mismatch
      ;;
    wrong-revision)
      response_headers=${success_headers/X-SubMan-Revision: 13/X-SubMan-Revision: 99}
      expected_code=revision_contract_mismatch
      ;;
    wrong-marker)
      response_body=${success_body/external:sing-box-vps:edge-1:vless-reality/external:other-key}
      expected_code=external_key_contract_mismatch
      ;;
  esac
  set_mock_response PUT "" 200 "${response_body}" "${response_headers}"
  if push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/${contract_case}.txt" 2>&1; then
    printf 'expected invalid write receipt to fail: %s\n' "${contract_case}" >&2
    exit 1
  fi
  [[ "${SUBMAN_LAST_ERROR_CODE}" == "${expected_code}" && "${SUBMAN_LAST_OUTCOME}" == unknown-outcome ]]
done

# A lost PUT receipt is reconciled from a fresh, guarded inventory read. Compare
# all writable fields and the exact marker; never issue a second PUT.
reconciled_list_body=$(jq -c '.data.tags += [{id: "ordinary-tag", label: "sing-box-vps"}] | .data = [.data]' <<< "${success_body}")
reset_method_counts
set_mock_response GET 1 200 "${preflight_body}" "${preflight_headers}"
set_mock_response GET 2 200 "${reconciled_list_body}" "${success_headers}"
set_mock_response PUT "" 000 "" "" 28
before_reconcile_calls=$(wc -l < "${CURL_CALLS_FILE}")
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/reconciled.txt" 2>&1
[[ "${SUBMAN_LAST_OUTCOME}" == reconciled && "${SUBMAN_LAST_NODE_ID}" == node-1 && "${SUBMAN_LAST_REVISION}" == 13 ]]
[[ "${SUBMAN_LAST_ERROR_CODE}" == "" && "${SUBMAN_LAST_GIST_ID}" == gist-1 ]]
[[ "$(wc -l < "${CURL_CALLS_FILE}")" -eq $((before_reconcile_calls + 3)) ]]
[[ "$(cat "${CURL_METHOD_COUNT_DIR}/PUT")" -eq 1 ]]

for changed_field in raw name enabled source tags marker; do
  reset_method_counts
  case "${changed_field}" in
    raw) different_body=$(jq -c '.data[0].raw = "vless://another"' <<< "${reconciled_list_body}") ;;
    name) different_body=$(jq -c '.data[0].name = "different"' <<< "${reconciled_list_body}") ;;
    enabled) different_body=$(jq -c '.data[0].enabled = false' <<< "${reconciled_list_body}") ;;
    source) different_body=$(jq -c '.data[0].source = "subscription"' <<< "${reconciled_list_body}") ;;
    tags) different_body=$(jq -c '.data[0].tags += [{label: "unexpected"}]' <<< "${reconciled_list_body}") ;;
    marker) different_body=${reconciled_list_body/external:sing-box-vps:edge-1:vless-reality/external:other-key} ;;
  esac
  set_mock_response GET 2 200 "${different_body}" "${success_headers}"
  if push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/unreconciled-${changed_field}.txt" 2>&1; then
    printf 'expected a differing %s to leave the write outcome uncertain\n' "${changed_field}" >&2
    exit 1
  fi
  [[ "${SUBMAN_LAST_OUTCOME}" == unknown-outcome && "${SUBMAN_LAST_ERROR_CODE}" == transport_error ]]
  [[ "${SUBMAN_LAST_ERROR_DISPOSITION}" == unknown-outcome && "${SUBMAN_LAST_HTTP_STATUS}" == 000 ]]
  [[ "${SUBMAN_LAST_NODE_ID}" == "" && "${SUBMAN_LAST_REVISION}" == "" ]]
  [[ "$(cat "${CURL_METHOD_COUNT_DIR}/PUT")" -eq 1 ]]
done

reset_method_counts
set_mock_response GET 2 200 "${reconciled_list_body}" "${success_headers}"
set_mock_response PUT "" 503 "${error_body}" 'HTTP/2 503\r\nRetry-After: 19\r\n\r\n'
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/upstream-reconciled.txt" 2>&1
[[ "${SUBMAN_LAST_OUTCOME}" == reconciled ]]
reset_method_counts
set_mock_response GET 2 200 "${preflight_body}" "${preflight_headers}"
if push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/upstream-unknown.txt" 2>&1; then
  printf 'expected an unconfirmed upstream failure to remain uncertain\n' >&2
  exit 1
fi
[[ "${SUBMAN_LAST_OUTCOME}" == unknown-outcome && "${SUBMAN_LAST_ERROR_CODE}" == gist_write_failed ]]
[[ "${SUBMAN_LAST_ERROR_DISPOSITION}" == retryable-upstream && "${SUBMAN_LAST_RETRY_AFTER}" == 19 && "${SUBMAN_LAST_HTTP_STATUS}" == 503 ]]

# A local failure after receiving a PUT does not prove the mutation failed.
# Keep the cleanup error visible instead of hiding it behind a successful read.
reset_method_counts
set_mock_response PUT "" 200 "${success_body}" "${success_headers}"
cleanup_attempts=0
failed_cleanup_dir=""
rm() {
  if [[ "${1:-}" == -rf && "${2:-}" == -- && "${3:-}" == */subman-api.* ]]; then
    cleanup_attempts=$((cleanup_attempts + 1))
    if [[ "${cleanup_attempts}" -eq 2 ]]; then
      failed_cleanup_dir=$3
      return 1
    fi
  fi
  command rm "$@"
}
cleanup_failure_status=0
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${TMP_DIR}/post-write-cleanup.txt" 2>&1 || cleanup_failure_status=$?
unset -f rm
[[ -z "${failed_cleanup_dir}" ]] || command rm -rf -- "${failed_cleanup_dir}"
[[ "${cleanup_failure_status}" -ne 0 && "${SUBMAN_LAST_ERROR_CODE}" == temporary_cleanup_failed && "${SUBMAN_LAST_OUTCOME}" == unknown-outcome ]]
[[ "$(cat "${CURL_METHOD_COUNT_DIR}/GET")" -eq 1 && "$(cat "${CURL_METHOD_COUNT_DIR}/PUT")" -eq 1 ]]

# Use a disposable local HTTP server and the real curl executable as a separate
# wire-level check of lowercase headers, conditional writes, and lost receipts.
cat > "${TMP_DIR}/subman-http-mock.py" <<'PY'
import http.server
import json
import pathlib
import socket
import sys
import urllib.parse

root = pathlib.Path(sys.argv[1])
nodes = {}
revision = 12


class Handler(http.server.BaseHTTPRequestHandler):
  def log_message(self, *_args):
    pass

  def record(self):
    with (root / "http-requests.txt").open("a") as requests:
      requests.write(self.command + " " + self.path + "\n")

  def respond(self, data, status=200):
    body = json.dumps({"data": data, "workspace": {
      "gistId": "gist-live-fixture", "file": "subman.json", "revision": revision
    }}).encode()
    self.send_response(status)
    self.send_header("content-type", "application/json")
    self.send_header("etag", f'"subman-revision-{revision}"')
    self.send_header("x-subman-revision", str(revision))
    self.send_header("cache-control", "no-store")
    self.send_header("content-length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)

  def do_GET(self):
    self.record()
    if self.path != "/api/nodes":
      self.send_error(404)
      return
    self.respond(list(nodes.values()))

  def do_PUT(self):
    global revision
    self.record()
    if self.headers.get("Authorization") != "Bearer secret-token":
      self.send_error(401)
      return
    if self.headers.get("If-Match") != f'"subman-revision-{revision}"':
      self.send_error(412)
      return
    key = urllib.parse.unquote(self.path[len("/api/nodes/by-key/"):])
    payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
    payload["id"] = "http-fixture-" + key
    payload["tags"] = [{"label": tag} for tag in payload["tags"]] + [{"label": "external:" + key}]
    nodes[key] = payload
    revision += 1
    if key == "live-lost-response":
      self.close_connection = True
      self.connection.shutdown(socket.SHUT_RDWR)
      self.connection.close()
      return
    self.respond(payload)


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
(root / "http-port.txt").write_text(str(server.server_port))
server.serve_forever()
PY
python3 "${TMP_DIR}/subman-http-mock.py" "${TMP_DIR}" > "${TMP_DIR}/http-server.log" 2>&1 &
SUBMAN_MOCK_PID=$!
for attempt in {1..100}; do
  [[ ! -s "${TMP_DIR}/http-port.txt" ]] || break
  sleep 0.05
done
[[ -s "${TMP_DIR}/http-port.txt" ]]
SUBMAN_API_URL="http://127.0.0.1:$(cat "${TMP_DIR}/http-port.txt")"
SUBMAN_EXPECTED_GIST_ID="gist-live-fixture"
curl() { "${REAL_CURL_BIN}" --noproxy '*' "$@"; }
push_subman_node live-success "${payload_json}" > "${TMP_DIR}/http-success.txt" 2>&1
[[ "${SUBMAN_LAST_OUTCOME}" == committed && "${SUBMAN_LAST_REVISION}" == 13 ]]
push_subman_node live-lost-response "${payload_json}" > "${TMP_DIR}/http-reconciled.txt" 2>&1
[[ "${SUBMAN_LAST_OUTCOME}" == reconciled && "${SUBMAN_LAST_NODE_ID}" == http-fixture-live-lost-response && "${SUBMAN_LAST_REVISION}" == 14 ]]
[[ "$(wc -l < "${TMP_DIR}/http-requests.txt")" -eq 5 ]]
[[ "$(grep -c '^PUT ' "${TMP_DIR}/http-requests.txt")" -eq 2 ]]
