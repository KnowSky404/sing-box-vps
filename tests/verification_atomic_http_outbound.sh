#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/component_http_outbound.sh"
CASE_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/outbound_cases.sh"
FIXTURE_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/runtime_fixtures.sh"
TMP_DIR=$(mktemp -d)
FIXTURE_PID=''
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "${FIXTURE_PID}" ]]; then
    if kill -0 "${FIXTURE_PID}" 2>/dev/null; then kill "${FIXTURE_PID}"; fi
    if wait "${FIXTURE_PID}"; then :; else
      case $? in 143) ;; *) status=1 ;; esac
    fi
  fi
  rm -rf "${TMP_DIR}"
  exit "${status}"
}
trap cleanup EXIT
source "${FIXTURE_FILE}"
source "${CASE_FILE}"
source "${SCENARIO_FILE}"
for file in "${FIXTURE_FILE}" "${CASE_FILE}" "${SCENARIO_FILE}"; do
  bash -n "${file}"
done

# The host regression runs only the upstream handshake, with negative auth,
# header and destination cases. It never sources an installer or starts Docker.
verification_atomic_http_fixture "${TMP_DIR}/ports.json" exact-loopback-marker \
  sbv-fixture.invalid "${TMP_DIR}/request.txt" >"${TMP_DIR}/stdout" 2>"${TMP_DIR}/stderr" &
FIXTURE_PID=$!
for _ in {1..50}; do
  [[ -s "${TMP_DIR}/ports.json" ]] && break
  kill -0 "${FIXTURE_PID}" 2>/dev/null
  sleep 0.1
done
python3 - "${TMP_DIR}/ports.json" "${TMP_DIR}/request.txt" <<'PY'
import json
import pathlib
import socket
import sys

port = json.loads(pathlib.Path(sys.argv[1]).read_text())["proxy"]
auth = "Proxy-Authorization: Basic cHJveHktdXNlcjpwcm94eS1wYXNz\r\n"
header = "X-SBV-Proxy: http-outbound\r\n"

def request(domain="sbv-fixture.invalid", authorization=auth, custom=header, success=False):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as conn:
        conn.settimeout(5)
        conn.sendall(("CONNECT " + domain + ":80 HTTP/1.1\r\n" + authorization + custom + "\r\n").encode())
        received = bytearray()
        while b"\r\n\r\n" not in received:
            chunk = conn.recv(1)
            if not chunk:
                raise AssertionError("proxy closed before sending headers")
            received.extend(chunk)
        if success:
            assert received.startswith(b"HTTP/1.1 200 "), received
            conn.sendall(b"GET / HTTP/1.1\r\nHost: sbv-fixture.invalid\r\nConnection: close\r\n\r\n")
            data = bytearray()
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data.extend(chunk)
            assert bytes(data).split(b"\r\n\r\n", 1)[1] == b"exact-loopback-marker\n", data
        return bytes(received)

assert request(authorization="").startswith(b"HTTP/1.1 407 ")
assert request(custom="").startswith(b"HTTP/1.1 403 ")
assert request(domain="forbidden.example").startswith(b"HTTP/1.1 403 ")
request(success=True)
assert b"CONNECT sbv-fixture.invalid:80 HTTP/1.1" in pathlib.Path(sys.argv[2]).read_bytes()
PY

# Keep the shared lifecycle and evidence boundary in the runtime case. The leaf
# deletes its component; aggregate retains that same authenticated component.
grep -Fq -- '--expected-revision "$((base_revision + 0))" --file "${record}"' "${CASE_FILE}"
grep -Fq -- '--expected-revision "$((base_revision + 1))" --id "${component_id}"' "${CASE_FILE}"
grep -Fq '.revision==($base_revision + 2) and all(.components[]; .id!=$id)' "${CASE_FILE}"
grep -Fq 'all(.route.rules[]?; .outbound!=$id)' "${CASE_FILE}"
grep -Fq 'socks5h://socks-user:socks-pass@127.0.0.1:1081' "${CASE_FILE}"
grep -Fq 'sing-box check -c "${config_file}"' "${CASE_FILE}"
grep -Fq 'http_outbound_proxy_pid=$!' "${CASE_FILE}"
grep -Fq 'verification_case_context_start' "${SCENARIO_FILE}"
grep -Fq 'verification_case_http_outbound 0 delete' "${SCENARIO_FILE}"
grep -Fq 'verification_case_assert_clean 2' "${SCENARIO_FILE}"
python3 - "${CASE_FILE}" "${FIXTURE_FILE}" "${SCENARIO_FILE}" <<'PY_SHARED_CONTRACT'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
helper = source.split('verification_case_http_outbound() {', 1)[1].split(
    '\nverification_', 1)[0]
fixtures = Path(sys.argv[2]).read_text()
entry = Path(sys.argv[3]).read_text()
assert 'verification_atomic_http_fixture() {' in fixtures
assert 'verification_atomic_http_fixture() {' not in source
assert 'verification_case_http_outbound() {' not in entry
assert 'verification_atomic_http_fixture() {' not in entry
assert 'verification_assert_atomic_socks_baseline' not in helper
assert 'trap ' not in helper
assert 'local http_outbound_proxy_pid' not in helper
assert helper.index('authenticated-http-marker-complete') < helper.index(
    'if [[ "${lifecycle}" == retain ]]') < helper.index('agent component delete')
assert 'LIFECYCLE=create_retain' in helper
assert 'LIFECYCLE=create_delete' in helper
assert '"REVISIONS=${base_revision},$((base_revision + 1))"' in helper
assert '"REVISIONS=${base_revision},$((base_revision + 1)),$((base_revision + 2))"' in helper
PY_SHARED_CONTRACT
# Invalid shared parameters must fail before starting a fixture or mutation.
http_outbound_proxy_pid=unchanged
for invalid in 'invalid delete' '0 invalid' '-1 retain' '01 delete'; do
  read -r base lifecycle <<<"${invalid}"
  if verification_case_http_outbound "${base}" "${lifecycle}"; then
    printf 'Invalid shared HTTP parameters were accepted: %s\n' "${invalid}" >&2
    exit 1
  else
    [[ $? == 2 ]]
  fi
  [[ "${http_outbound_proxy_pid}" == unchanged ]]
done
printf 'Atomic HTTP upstream authentication, marker and shared lifecycle contracts passed\n'
