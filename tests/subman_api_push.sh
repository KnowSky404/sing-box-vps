#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

CURL_ARGS_FILE="${TMP_DIR}/curl-args.txt"
CURL_RESPONSE_BODY="${TMP_DIR}/curl-response-body.txt"
CURL_RESPONSE_STATUS="${TMP_DIR}/curl-response-status.txt"
CURL_RESPONSE_STDERR="${TMP_DIR}/curl-response-stderr.txt"
CURL_EXIT_STATUS="${TMP_DIR}/curl-exit-status.txt"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash

printf '%s\n' "$*" > "${CURL_ARGS_FILE}"
if [[ -s "${CURL_RESPONSE_STDERR}" ]]; then
  cat "${CURL_RESPONSE_STDERR}" >&2
fi
cat "${CURL_RESPONSE_BODY}"
printf 'HTTP_STATUS:%s' "$(cat "${CURL_RESPONSE_STATUS}")"
exit "$(cat "${CURL_EXIT_STATUS}")"
EOF
chmod +x "${TMP_DIR}/bin/curl"
export CURL_ARGS_FILE CURL_RESPONSE_BODY CURL_RESPONSE_STATUS CURL_RESPONSE_STDERR CURL_EXIT_STATUS

SUBMAN_API_URL=" https://subman.example.com/// "
SUBMAN_API_TOKEN="secret-token"
payload_json='{"name":"edge-1","type":"vless","raw":"vless://example"}'

printf '' > "${CURL_RESPONSE_STDERR}"
printf '0' > "${CURL_EXIT_STATUS}"
printf '{"ok":true}\n' > "${CURL_RESPONSE_BODY}"
printf '200' > "${CURL_RESPONSE_STATUS}"

success_output=$(push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" 2>&1)
if [[ "${success_output}" != *"HTTP 200"* ]]; then
  printf 'expected success output to include HTTP 200, got:\n%s\n' "${success_output}" >&2
  exit 1
fi

curl_args=$(cat "${CURL_ARGS_FILE}")
if [[ "${curl_args}" != *"https://subman.example.com/api/nodes/by-key/sing-box-vps%3Aedge-1%3Avless-reality"* ]]; then
  printf 'expected curl to call node by-key endpoint, got:\n%s\n' "${curl_args}" >&2
  exit 1
fi
if [[ "${curl_args}" != *"-X PUT"* ]]; then
  printf 'expected curl to use PUT, got:\n%s\n' "${curl_args}" >&2
  exit 1
fi
if [[ "${curl_args}" != *"Authorization: Bearer secret-token"* ]]; then
  printf 'expected curl to pass bearer token header, got:\n%s\n' "${curl_args}" >&2
  exit 1
fi
if [[ "${curl_args}" != *"${payload_json}"* ]]; then
  printf 'expected curl to pass JSON payload, got:\n%s\n' "${curl_args}" >&2
  exit 1
fi

printf 'curl warning before body\n' > "${CURL_RESPONSE_STDERR}"
success_output=$(push_subman_node "sing-box-vps:edge 1/hy2" "${payload_json}" 2>&1)
if [[ "${success_output}" != *"HTTP 200"* ]]; then
  printf 'expected success output with curl stderr to include HTTP 200, got:\n%s\n' "${success_output}" >&2
  exit 1
fi

curl_args=$(cat "${CURL_ARGS_FILE}")
if [[ "${curl_args}" != *"https://subman.example.com/api/nodes/by-key/sing-box-vps%3Aedge%201%2Fhy2"* ]]; then
  printf 'expected external key to be URL-encoded in endpoint, got:\n%s\n' "${curl_args}" >&2
  exit 1
fi

printf '' > "${CURL_RESPONSE_STDERR}"
printf '{"error":"internal"}\n' > "${CURL_RESPONSE_BODY}"
printf '500' > "${CURL_RESPONSE_STATUS}"

set +e
failure_output=$(push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" 2>&1)
failure_status=$?
set -e

if [[ "${failure_status}" -eq 0 ]]; then
  printf 'expected HTTP 500 push to fail\n' >&2
  exit 1
fi
if [[ "${failure_output}" != *"HTTP 500"* ]]; then
  printf 'expected failure output to mention HTTP 500, got:\n%s\n' "${failure_output}" >&2
  exit 1
fi
if [[ "${failure_output}" == *"secret-token"* ]]; then
  printf 'expected failure output not to leak token, got:\n%s\n' "${failure_output}" >&2
  exit 1
fi

printf 'curl: (6) Could not resolve host: subman.example.com\n' > "${CURL_RESPONSE_STDERR}"
printf '' > "${CURL_RESPONSE_BODY}"
printf '000' > "${CURL_RESPONSE_STATUS}"
printf '6' > "${CURL_EXIT_STATUS}"

set +e
curl_failure_output=$(push_subman_node "sing-box-vps:edge-1:vless-reality" "${payload_json}" 2>&1)
curl_failure_status=$?
set -e

if [[ "${curl_failure_status}" -eq 0 ]]; then
  printf 'expected curl transport failure to fail\n' >&2
  exit 1
fi
if [[ "${curl_failure_output}" != *"SubMan"* ]]; then
  printf 'expected curl transport failure to log a SubMan warning, got:\n%s\n' "${curl_failure_output}" >&2
  exit 1
fi
if [[ "${curl_failure_output}" == *"secret-token"* ]]; then
  printf 'expected curl transport failure output not to leak token, got:\n%s\n' "${curl_failure_output}" >&2
  exit 1
fi
