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
MARKER_PORT_PATH="${TEST_DIR}/marker.port"
MARKER_ACCESS_PATH="${TEST_DIR}/marker.access"
MARKER_STDOUT_PATH="${TEST_DIR}/marker.stdout"
MARKER_STDERR_PATH="${TEST_DIR}/marker.stderr"

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

run_openvpn_transport() {
  local network=$1
  local server_port=$2
  local proxy_port=$3
  local address_cidr=$4
  local server_tag="openvpn-runtime-${network}-server"
  local client_tag="openvpn-runtime-${network}-client"
  local inbound_tag="openvpn-runtime-${network}-in"
  local config_path="${TEST_DIR}/config-${network}.json"
  local marker_response_path="${TEST_DIR}/marker-${network}.response"
  local core_stdout_path="${TEST_DIR}/core-${network}.stdout"
  local core_stderr_path="${TEST_DIR}/core-${network}.stderr"
  local listener_ready=1

  : > "${MARKER_ACCESS_PATH}"
  jq -n \
    --arg cert "${CERT_PATH}" \
    --arg key "${KEY_PATH}" \
    --arg marker_address "${MARKER_ADDRESS}" \
    --arg network "${network}" \
    --arg server_tag "${server_tag}" \
    --arg client_tag "${client_tag}" \
    --arg inbound_tag "${inbound_tag}" \
    --argjson server_port "${server_port}" \
    --argjson proxy_port "${proxy_port}" \
    --argjson marker_port "${MARKER_PORT}" \
    --arg address_cidr "${address_cidr}" \
    '{
      log: { level: "info", timestamp: false },
      inbounds: [
        {
          type: "direct",
          tag: $inbound_tag,
          listen: "127.0.0.1",
          listen_port: $proxy_port,
          override_address: $marker_address,
          override_port: $marker_port
        }
      ],
      endpoints: [
        {
          type: "openvpn-server",
          tag: $server_tag,
          system: false,
          listen: "127.0.0.1",
          listen_port: $server_port,
          network: $network,
          address: [$address_cidr],
          users: [{username: "probe", password: "probe-pass"}],
          tls: {
            certificate_path: $cert,
            key_path: $key,
            verify_client_certificate: "none"
          }
        },
        {
          type: "openvpn-client",
          tag: $client_tag,
          system: false,
          server: "127.0.0.1",
          server_port: $server_port,
          network: $network,
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
            inbound: [$inbound_tag],
            action: "route",
            outbound: $client_tag
          }
        ],
        final: "direct"
      }
    }' > "${config_path}"

  "${CORE}" check -c "${config_path}"
  "${CORE}" run -c "${config_path}" >"${core_stdout_path}" 2>"${core_stderr_path}" &
  CORE_PID=$!

  for _ in {1..100}; do
    kill -0 "${CORE_PID}" 2>/dev/null || {
      printf 'OpenVPN %s endpoint core exited before startup\n' "${network}" >&2
      /usr/bin/sed -n '1,120p' "${core_stderr_path}" >&2
      return 1
    }
    if [[ "${network}" == "udp" ]]; then
      if ss -lun 2>/dev/null | awk -v port="${server_port}" \
        '$1 == "UNCONN" && $4 ~ (":" port "$") { found = 1 } END { exit(found ? 0 : 1) }' &&
        ss -lnt 2>/dev/null | awk -v port="${proxy_port}" \
        '$1 == "LISTEN" && $4 ~ (":" port "$") { found = 1 } END { exit(found ? 0 : 1) }'; then
        listener_ready=0
      fi
    elif ss -lnt 2>/dev/null | awk -v server_port="${server_port}" -v proxy_port="${proxy_port}" \
      '($1 == "LISTEN" && $4 ~ (":" server_port "$")) ||
       ($1 == "LISTEN" && $4 ~ (":" proxy_port "$")) { found++ }
       END { exit(found == 2 ? 0 : 1) }'; then
      listener_ready=0
    fi
    [[ "${listener_ready}" == 0 ]] && break
    sleep 0.1
  done
  [[ "${listener_ready}" == 0 ]]

  for _ in {1..100}; do
    grep -Fq 'tunnel established' "${core_stderr_path}" && break
    kill -0 "${CORE_PID}" 2>/dev/null || {
      printf 'OpenVPN %s endpoint core exited before tunnel establishment\n' "${network}" >&2
      /usr/bin/sed -n '1,160p' "${core_stderr_path}" >&2
      return 1
    }
    sleep 0.1
  done
  grep -Fq 'tunnel established' "${core_stderr_path}"

  curl --fail --silent --show-error --max-time 10 --noproxy '*' \
    "http://127.0.0.1:${proxy_port}/" >"${marker_response_path}"
  grep -Fqx "${MARKER}" "${marker_response_path}"
  grep -Fqx '/' "${MARKER_ACCESS_PATH}"
  grep -Fq 'peer connected' "${core_stderr_path}"
  grep -Fq "over ${network}" "${core_stderr_path}"

  jq -e --arg network "${network}" --arg server_tag "${server_tag}" \
    --arg client_tag "${client_tag}" --arg inbound_tag "${inbound_tag}" '
    ([.endpoints[] | select(.type == "openvpn-server" and .tag == $server_tag and
      .network == $network and .system == false)] | length == 1) and
    ([.endpoints[] | select(.type == "openvpn-client" and .tag == $client_tag and
      .network == $network and .system == false)] | length == 1) and
    (.route.rules[0].inbound == [$inbound_tag] and .route.rules[0].outbound == $client_tag)
  ' "${config_path}" >/dev/null

  kill "${CORE_PID}" 2>/dev/null || true
  wait "${CORE_PID}" 2>/dev/null || true
  CORE_PID=''
}

run_openvpn_transport tcp 11994 15091 10.77.0.1/24
run_openvpn_transport udp 11995 15092 10.78.0.1/24

printf 'OpenVPN endpoint TCP+UDP runtime closures passed: %s\n' "${MARKER}"
