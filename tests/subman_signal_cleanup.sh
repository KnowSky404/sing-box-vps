#!/usr/bin/env bash

set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

cat <<'WORKER' > "${TMP_DIR}/worker.sh"
#!/usr/bin/env bash
set -euo pipefail
source "$1"
signal=$2
mode=$3
SUBMAN_API_URL=https://dummy.invalid
SUBMAN_API_TOKEN=dummy-signal-token
normalize_subman_api_url() { printf 'https://dummy.invalid'; }
validate_subman_connection_settings() { return 0; }
signal_target=${BASHPID}
subman_curl_with_progress() { kill -s "${signal}" "${signal_target}"; printf 200; }
if [[ "${mode}" == custom || "${mode}" == early || "${mode}" == allocation ]]; then
  caller_signal_seen=n
  trap 'caller_signal_seen=y' TERM
  trap_before=$(trap -p TERM)
  if [[ "${mode}" == early || "${mode}" == allocation ]]; then
    subman_curl_with_progress() { printf 'unexpected transport\n' >> "${SB_DATA_ROOT}/transport.calls"; return 99; }
    if [[ "${mode}" == early ]]; then
      chmod() {
        command chmod "$@" || return $?
        if [[ "$1" == 700 && "$2" == "${SB_DATA_ROOT}/tmp/subman-api."* ]]; then
          kill -TERM "${signal_target}"
          # Fail before any body redirection if cleanup loses the private path.
          [[ "${request_dir}" == "${SB_DATA_ROOT}/tmp/subman-api."* ]] || exit 97
        fi
      }
    else
      storage_mktemp() {
        local allocated
        allocated=$(command mktemp "$@") || return $?
        kill -TERM "${signal_target}"
        printf '%s\n' "${allocated}"
      }
    fi
  fi
  request_exit=0
  subman_api_request POST /api/nodes '{"name":"dummy"}' || request_exit=$?
  [[ "${request_exit}" == 143 && "${caller_signal_seen}" == y ]]
  [[ "${SUBMAN_LAST_OUTCOME}" == unknown-outcome && "${SUBMAN_LAST_ERROR_CODE}" == signal_interrupted ]]
  [[ "$(trap -p TERM)" == "${trap_before}" ]]
  [[ ! -e "${SB_DATA_ROOT}/transport.calls" ]]
else
  subman_api_request POST /api/nodes '{"name":"dummy"}'
  exit 99
fi
WORKER

for signal in TERM HUP INT; do
  request_exit=0
  bash "${TMP_DIR}/worker.sh" "${TESTABLE_INSTALL}" "${signal}" default > "${TMP_DIR}/worker.out" 2> "${TMP_DIR}/worker.err" || request_exit=$?
  case "${signal}" in TERM) expected_exit=143 ;; HUP) expected_exit=129 ;; INT) expected_exit=130 ;; esac
  [[ "${request_exit}" == "${expected_exit}" ]]
  [[ -z "$(find "${SB_DATA_ROOT}/tmp" -name 'subman-api.*' -print -quit)" ]]
  ! grep -q dummy-signal-token "${TMP_DIR}/worker.out" "${TMP_DIR}/worker.err"
done
bash "${TMP_DIR}/worker.sh" "${TESTABLE_INSTALL}" TERM custom > "${TMP_DIR}/worker.out" 2> "${TMP_DIR}/worker.err"
for mode in early allocation; do
  bash "${TMP_DIR}/worker.sh" "${TESTABLE_INSTALL}" TERM "${mode}" > "${TMP_DIR}/worker.out" 2> "${TMP_DIR}/worker.err" || {
    cat "${TMP_DIR}/worker.err" >&2
    exit 1
  }
done
[[ -z "$(find "${SB_DATA_ROOT}/tmp" -name 'subman-api.*' -print -quit)" ]]

# Normal calls retain response globals and the caller's signal/EXIT handlers.
SUBMAN_API_URL=https://dummy.invalid
SUBMAN_API_TOKEN=dummy-signal-token
normalize_subman_api_url() { printf 'https://dummy.invalid'; }
validate_subman_connection_settings() { return 0; }
subman_curl_with_progress() {
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -D) printf 'HTTP/1.1 200 OK\r\nETag: "dummy"\r\n' > "$2"; shift 2 ;;
      -o) printf '{"dummy":true}' > "$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf 200
}
trap 'CALLER_SIGNAL_SEEN=y' TERM
traps_before=$(trap -p INT TERM HUP EXIT)
subman_api_request GET /api/nodes
[[ "$(trap -p INT TERM HUP EXIT)" == "${traps_before}" ]]
[[ "${SUBMAN_LAST_HTTP_STATUS}" == 200 && "${SUBMAN_LAST_RESPONSE_ETAG}" == '"dummy"' ]]
[[ "${SUBMAN_LAST_RESPONSE_BODY}" == '{"dummy":true}' ]]
[[ -z "$(find "${SB_DATA_ROOT}/tmp" -name 'subman-api.*' -print -quit)" ]]
printf 'SubMan signal cleanup and caller traps passed\n'
