#!/usr/bin/env bash

set -euo pipefail

setup_protocol_probe_command_stubs() {
  local stub_dir="${TMP_DIR}/probe-bin"

  PROBE_CALL_LOG="${TMP_DIR}/probe-calls.log"
  PROBE_CLIENT_PID_FILE="${TMP_DIR}/probe-client.pid"
  PROBE_HTTP_PID_FILE="${TMP_DIR}/probe-http.pid"
  : > "${PROBE_CALL_LOG}"
  export PROBE_CALL_LOG PROBE_CLIENT_PID_FILE PROBE_HTTP_PID_FILE

  mkdir -p "${stub_dir}"
  cat > "${stub_dir}/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
set -euo pipefail

printf 'sing-box %s\n' "$*" >> "${PROBE_CALL_LOG:?}"
case "${1:-}" in
  check)
    if [[ "${PROBE_FAIL_CHECK:-0}" == "1" ]]; then
      printf 'client-check-failed\n' >&2
      exit 23
    fi
    printf 'client-check-ok\n'
    ;;
  run)
    if [[ "${PROBE_FAIL_RUN:-0}" == "1" ]]; then
      printf 'client-run-failed\n' >&2
      exit 24
    fi
    printf '%s\n' "$$" > "${PROBE_CLIENT_PID_FILE:?}"
    exec tail -f /dev/null
    ;;
  *)
    printf 'unexpected sing-box call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF_SINGBOX

  cat > "${stub_dir}/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail

printf 'curl %s\n' "$*" >> "${PROBE_CALL_LOG:?}"
printf '%s\n' "${PROBE_CURL_RESPONSE:-${VERIFY_PROTOCOL_PROBE_EXPECTED_MARKER:?}}"
EOF_CURL

  cat > "${stub_dir}/ss" <<'EOF_SS'
#!/usr/bin/env bash
set -euo pipefail

if [[ -s "${PROBE_CLIENT_PID_FILE:?}" ]] && kill -0 "$(cat "${PROBE_CLIENT_PID_FILE}")" 2>/dev/null; then
  printf 'LISTEN 0 0 127.0.0.1:19080 0.0.0.0:*\n'
fi
EOF_SS

  cat > "${stub_dir}/python3" <<'EOF_PYTHON3'
#!/usr/bin/env bash
set -euo pipefail

printf 'python3 %s\n' "$*" >> "${PROBE_CALL_LOG:?}"
printf '%s\n' "$$" > "${PROBE_HTTP_PID_FILE:?}"
exec /usr/bin/python3 "$@"
EOF_PYTHON3

  chmod +x "${stub_dir}/sing-box" "${stub_dir}/curl" "${stub_dir}/ss" "${stub_dir}/python3"
  export PATH="${stub_dir}:${PATH}"
}

assert_protocol_probe_processes_cleaned() {
  local pid_file=$1
  local pid

  [[ -s "${pid_file}" ]] || {
    printf 'expected probe process pid file: %s\n' "${pid_file}" >&2
    return 1
  }
  pid=$(cat "${pid_file}")
  if kill -0 "${pid}" 2>/dev/null; then
    printf 'probe process still running: %s\n' "${pid}" >&2
    return 1
  fi
}
