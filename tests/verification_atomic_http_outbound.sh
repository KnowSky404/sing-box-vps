#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/component_http_outbound.sh"
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
source "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

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

# Keep the actual managed lifecycle and evidence boundary in the runtime case.
grep -Fq -- '--expected-revision 0 --file "${record}"' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 1 --id "${component_id}"' "${SCENARIO_FILE}"
grep -Fq '.revision==2 and (.components|length)==0' "${SCENARIO_FILE}"
grep -Fq 'all(.route.rules[]?; .outbound!=$id)' "${SCENARIO_FILE}"
grep -Fq 'socks5h://socks-user:socks-pass@127.0.0.1:1081' "${SCENARIO_FILE}"
grep -Fq 'sing-box check -c "${config_file}"' "${SCENARIO_FILE}"
grep -Fq 'trap verification_cleanup_atomic_http EXIT' "${SCENARIO_FILE}"
printf 'Atomic HTTP upstream authentication, marker and lifecycle contracts passed\n'
