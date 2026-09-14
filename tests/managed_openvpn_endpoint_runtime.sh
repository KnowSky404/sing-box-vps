#!/usr/bin/env bash

set -euo pipefail

CORE=${SINGBOX_BINARY_114:-}
if [[ -z "${CORE}" || ! -x "${CORE}" ]]; then
  printf 'SKIP OpenVPN endpoint runtime: SINGBOX_BINARY_114 unavailable\n'
  exit 0
fi

command -v ip >/dev/null 2>&1 || {
  printf 'SKIP OpenVPN endpoint runtime: ip unavailable\n'
  exit 0
}
command -v python3 >/dev/null 2>&1 || {
  printf 'SKIP OpenVPN endpoint runtime: python3 unavailable\n'
  exit 0
}
for REQUIRED_COMMAND in jq openssl ss curl grep; do
  if ! command -v "${REQUIRED_COMMAND}" >/dev/null 2>&1; then
    printf 'SKIP OpenVPN endpoint runtime: %s unavailable\n' "${REQUIRED_COMMAND}"
    exit 0
  fi
done

TEST_DIR=$(mktemp -d /tmp/sing-box-vps-openvpn-runtime.XXXXXX)
CORE_PID=''
MARKER_PID=''
cleanup() {
  set +e
  if [[ -n "${CORE_PID}" ]]; then
    kill "${CORE_PID}" 2>/dev/null || true
    wait "${CORE_PID}" 2>/dev/null || true
  fi
  if [[ -n "${MARKER_PID}" ]]; then
    kill "${MARKER_PID}" 2>/dev/null || true
    wait "${MARKER_PID}" 2>/dev/null || true
  fi
  rm -rf -- "${TEST_DIR}"
}
trap cleanup EXIT INT TERM

MARKER_IP_JSON=''
if ! MARKER_IP_JSON=$(ip -j -4 addr show scope global); then
  printf 'SKIP OpenVPN endpoint runtime: ip JSON output unavailable\n'
  exit 0
fi
MARKER_ADDRESS=$(jq -r '
  [.[] | .addr_info[]? | select(.family == "inet" and .scope == "global") | .local][0] // empty
' <<<"${MARKER_IP_JSON}")
if [[ -z "${MARKER_ADDRESS}" ]]; then
  printf 'SKIP OpenVPN endpoint runtime: no global IPv4 marker address\n'
  exit 0
fi

CERT_PATH="${TEST_DIR}/server.crt"
KEY_PATH="${TEST_DIR}/server.key"
CONFIG_PATH="${TEST_DIR}/config.json"
MARKER_PORT_PATH="${TEST_DIR}/marker.port"
MARKER_ACCESS_PATH="${TEST_DIR}/marker.access"
MARKER_RESPONSE_PATH="${TEST_DIR}/marker.response"
MARKER_STDOUT_PATH="${TEST_DIR}/marker.stdout"
MARKER_STDERR_PATH="${TEST_DIR}/marker.stderr"
CORE_STDOUT_PATH="${TEST_DIR}/core.stdout"
CORE_STDERR_PATH="${TEST_DIR}/core.stderr"

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "${KEY_PATH}" \
  -out "${CERT_PATH}" \
  -subj '/CN=sing-box-vps-openvpn-runtime.invalid' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,digitalSignature,keyEncipherment' \
  -addext 'extendedKeyUsage=serverAuth' \
  -addext 'subjectAltName=DNS:sing-box-vps-openvpn-runtime.invalid' \
  -days 1 >/dev/null 2>&1
chmod 600 "${CERT_PATH}" "${KEY_PATH}"

MARKER='sing-box-vps-openvpn-endpoint-runtime-ok'
python3 - "${MARKER_PORT_PATH}" "${MARKER_ADDRESS}" "${MARKER}" "${MARKER_ACCESS_PATH}" \
  >"${MARKER_STDOUT_PATH}" 2>"${MARKER_STDERR_PATH}" <<'PY' &
import http.server
import pathlib
import sys

port_path, bind_address, marker, access_path = sys.argv[1:]

class MarkerHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        pathlib.Path(access_path).write_text(self.path + "\n", encoding="ascii")
        body = (marker + "\n").encode("ascii")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

server = http.server.ThreadingHTTPServer((bind_address, 0), MarkerHandler)
pathlib.Path(port_path).write_text(str(server.server_address[1]), encoding="ascii")
server.serve_forever()
PY
MARKER_PID=$!
for _ in {1..100}; do
  [[ -s "${MARKER_PORT_PATH}" ]] && break
  kill -0 "${MARKER_PID}" 2>/dev/null || {
    printf 'OpenVPN endpoint marker exited before binding\n' >&2
    exit 1
  }
  sleep 0.1
done
[[ -s "${MARKER_PORT_PATH}" ]]
MARKER_PORT=$(<"${MARKER_PORT_PATH}")
[[ "${MARKER_PORT}" =~ ^[0-9]+$ ]]

jq -n \
  --arg cert "${CERT_PATH}" \
  --arg key "${KEY_PATH}" \
  --arg marker_address "${MARKER_ADDRESS}" \
  --argjson marker_port "${MARKER_PORT}" \
  '{
    log: { level: "info", timestamp: false },
    inbounds: [
      {
        type: "direct",
        tag: "openvpn-runtime-in",
        listen: "127.0.0.1",
        listen_port: 15091,
        override_address: $marker_address,
        override_port: $marker_port
      }
    ],
    endpoints: [
      {
        type: "openvpn-server",
        tag: "openvpn-runtime-server",
        system: false,
        listen: "127.0.0.1",
        listen_port: 11994,
        network: "tcp",
        address: ["10.77.0.1/24"],
        users: [{username: "probe", password: "probe-pass"}],
        tls: {
          certificate_path: $cert,
          key_path: $key,
          verify_client_certificate: "none"
        }
      },
      {
        type: "openvpn-client",
        tag: "openvpn-runtime-client",
        system: false,
        server: "127.0.0.1",
        server_port: 11994,
        network: "tcp",
        username: "probe",
        password: "probe-pass",
        tls: {
          certificate_path: $cert,
          server_name: "sing-box-vps-openvpn-runtime.invalid",
          remote_certificate_tls: "server"
        }
      }
    ],
    outbounds: [{type: "direct", tag: "direct"}],
    route: {
      rules: [
        {
          inbound: ["openvpn-runtime-in"],
          action: "route",
          outbound: "openvpn-runtime-client"
        }
      ],
      final: "direct"
    }
  }' > "${CONFIG_PATH}"

"${CORE}" check -c "${CONFIG_PATH}"
"${CORE}" run -c "${CONFIG_PATH}" >"${CORE_STDOUT_PATH}" 2>"${CORE_STDERR_PATH}" &
CORE_PID=$!

for _ in {1..100}; do
  kill -0 "${CORE_PID}" 2>/dev/null || {
    printf 'OpenVPN endpoint core exited before startup\n' >&2
    /usr/bin/sed -n '1,120p' "${CORE_STDERR_PATH}" >&2
    exit 1
  }
  if ss -lnt 2>/dev/null | awk '$1 == "LISTEN" && $4 ~ /:15091$/ { found = 1 } END { exit(found ? 0 : 1) }'; then
    break
  fi
  sleep 0.1
done
ss -lnt 2>/dev/null | awk '$1 == "LISTEN" && $4 ~ /:15091$/ { found = 1 } END { exit(found ? 0 : 1) }'

for _ in {1..100}; do
  grep -Fq 'tunnel established' "${CORE_STDERR_PATH}" && break
  kill -0 "${CORE_PID}" 2>/dev/null || {
    printf 'OpenVPN endpoint core exited before tunnel establishment\n' >&2
    /usr/bin/sed -n '1,160p' "${CORE_STDERR_PATH}" >&2
    exit 1
  }
  sleep 0.1
done
grep -Fq 'tunnel established' "${CORE_STDERR_PATH}"

curl --fail --silent --show-error --max-time 10 --noproxy '*' \
  "http://127.0.0.1:15091/" >"${MARKER_RESPONSE_PATH}"
grep -Fqx "${MARKER}" "${MARKER_RESPONSE_PATH}"
grep -Fqx '/' "${MARKER_ACCESS_PATH}"
grep -Fq 'peer connected' "${CORE_STDERR_PATH}"

jq -e '
  ([.endpoints[] | select(.type == "openvpn-server" and .tag == "openvpn-runtime-server")] | length == 1) and
  ([.endpoints[] | select(.type == "openvpn-client" and .tag == "openvpn-runtime-client")] | length == 1) and
  (.route.rules[0].outbound == "openvpn-runtime-client")
' "${CONFIG_PATH}" >/dev/null

printf 'OpenVPN endpoint TCP runtime closure passed: %s\n' "${MARKER}"
