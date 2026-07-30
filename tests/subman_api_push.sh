#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

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
payload_json='{"name":"edge-1","type":"vless","raw":"vless://example","enabled":true,"tags":["sing-box-vps"],"source":"single"}'
success_body='{"data":{"id":"node-1","name":"edge-1","type":"vless","raw":"vless://example","enabled":true,"tags":[{"id":"external-key","label":"external:sing-box-vps:edge-1:vless-reality"}],"updatedAt":"2026-07-30T00:00:00.000Z","source":"single"},"workspace":{"gistId":"gist-1","file":"subman.json","revision":13}}'
success_headers='HTTP/2 200\r\nETag: "subman-revision-13"\r\nX-SubMan-Revision: 13\r\nCache-Control: no-store\r\n\r\n'
set_mock_response "PUT" "" "200" "${success_body}" "${success_headers}"

success_output_file="${TMP_DIR}/success-output.txt"
push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" > "${success_output_file}" 2>&1
success_output=$(cat "${success_output_file}")
if [[ "${success_output}" != *"HTTP 200, Workspace revision 13"* ]]; then
  printf 'expected committed revision success output, got:\n%s\n' "${success_output}" >&2
  exit 1
fi
if [[ "${SUBMAN_LAST_NODE_ID}" != "node-1" || "${SUBMAN_LAST_REVISION}" != "13" ]]; then
  printf 'expected committed node and revision metadata, got node=%s revision=%s\n' "${SUBMAN_LAST_NODE_ID}" "${SUBMAN_LAST_REVISION}" >&2
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
if [[ $((after_transport_calls - before_transport_calls)) -ne 1 ]]; then
  printf 'expected transport failure not to blind-replay PUT\n' >&2
  exit 1
fi

before_invalid_calls=$(wc -l < "${CURL_CALLS_FILE}")
set +e
push_subman_node "$(printf 'x%.0s' {1..257})" "${payload_json}" > "${TMP_DIR}/invalid-output.txt" 2>&1
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
