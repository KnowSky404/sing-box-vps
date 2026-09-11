#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

awk '
  /^if ! mkdir "\$\{LOCK_DIR\}" 2>\/dev\/null; then$/ { exit }
  { print }
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh" > "${TMP_DIR}/entrypoint.sh"

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/artifacts"
cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  check)
    printf 'client-check-ok\n'
    ;;
  run)
    exec python3 - <<'PY'
import socket
import socketserver
import struct

def recv_exact(conn, size):
    data = bytearray()
    while len(data) < size:
        chunk = conn.recv(size - len(data))
        if not chunk:
            raise RuntimeError("control connection closed")
        data.extend(chunk)
    return bytes(data)

def read_address_from_packet(packet, atyp):
    if atyp == 1:
        return socket.inet_ntoa(packet[4:8]), 4
    if atyp == 3:
        length = packet[4]
        return packet[5:5 + length].decode("ascii"), 1 + length
    if atyp == 4:
        return socket.inet_ntop(socket.AF_INET6, packet[4:20]), 16
    raise RuntimeError("unsupported address type")

class SocksUDPHandler(socketserver.BaseRequestHandler):
    def handle(self):
        conn = self.request
        conn.settimeout(10)
        if recv_exact(conn, 3) != b"\x05\x01\x00":
            return
        conn.sendall(b"\x05\x00")
        request = recv_exact(conn, 10)
        if request[:4] != b"\x05\x03\x00\x01":
            return
        relay = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        relay.settimeout(10)
        relay.bind(("127.0.0.1", 0))
        relay_port = relay.getsockname()[1]
        conn.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01" + struct.pack("!H", relay_port))
        try:
            packet, client = relay.recvfrom(65535)
            if len(packet) < 10 or packet[:3] != b"\x00\x00\x00":
                return
            target_address, consumed = read_address_from_packet(packet, packet[3])
            target_port = struct.unpack("!H", packet[4 + consumed:6 + consumed])[0]
            payload = packet[6 + consumed:]
            relay.sendto(payload, (target_address, target_port))
            response, _ = relay.recvfrom(65535)
            header = b"\x00\x00\x00\x01" + socket.inet_aton(target_address) + struct.pack("!H", target_port)
            relay.sendto(header + response, client)
        finally:
            relay.close()

class ThreadingSocks(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

with ThreadingSocks(("127.0.0.1", 19080), SocksUDPHandler) as server:
    server.serve_forever()
PY
    ;;
  *)
    printf 'unexpected fake sing-box call: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

PATH="${TMP_DIR}/bin:${PATH}" bash -s -- "${TMP_DIR}/entrypoint.sh" "${TMP_DIR}/artifacts" <<'EOF_RUN'
set -euo pipefail
source "$1"
VERIFY_ARTIFACT_DIR=$2
VERIFY_CURRENT_SCENARIO_DIR=scenarios/udp-fixture

verification_artifact_path() {
  local relative_path=$1
  local target_path="${VERIFY_ARTIFACT_DIR}/${relative_path}"
  mkdir -p "$(dirname "${target_path}")"
  printf '%s\n' "${target_path}"
}

verification_write_artifact() {
  local relative_path=$1
  shift
  printf '%s\n' "$@" > "$(verification_artifact_path "${relative_path}")"
}

verification_generate_protocol_probe_client_config() {
  local protocol=$1 config_file=$2
  local output_path
  output_path=$(verification_artifact_path "${VERIFY_CURRENT_SCENARIO_DIR}/protocol-probes/${protocol}/client.json")
  printf '{"protocol":"%s","source":"%s"}\n' "${protocol}" "${config_file}" > "${output_path}"
  printf '%s\n' "${output_path}"
}

verification_execute_protocol_udp_probe fixture /tmp/server-config.json
EOF_RUN

PROBE_DIR="${TMP_DIR}/artifacts/scenarios/udp-fixture/protocol-probes/fixture"
grep -Fqx 'client-check-ok' "${PROBE_DIR}/udp-client.check.txt"
grep -Fqx 'RESULT=success' "${PROBE_DIR}/udp.result.env"
grep -Fq 'sing-box-vps-udp-loopback-ok-fixture-' "${PROBE_DIR}/udp-response.txt"
cmp "${PROBE_DIR}/udp-response.txt" "${PROBE_DIR}/udp-probe.stdout.txt"
if compgen -G '/tmp/sing-box-vps-udp-probe.*' > /dev/null; then
  printf 'UDP probe temporary directory was not cleaned up\n' >&2
  exit 1
fi

printf 'UDP protocol probe SOCKS ASSOCIATE and marker round-trip passed\n'
