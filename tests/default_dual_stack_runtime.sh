#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

docker_local() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS \
    -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
    docker --host=unix:///var/run/docker.sock "$@"
}

# All listeners, test credentials and processes live inside a disposable network
# namespace. No host ports, production services or public providers are used.
if [[ "${1:-}" != --container ]]; then
  [[ $# == 0 ]] || { printf 'usage: %s\n' "$0" >&2; exit 2; }
  core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
  image=${VERIFY_DOCKER_IMAGE:-sing-box-vps-verify:2026091501-ssh}
  [[ -x "${core}" ]] || { printf 'supported sing-box core unavailable: %s\n' "${core}" >&2; exit 1; }
  core_version=$("${core}" version)
  [[ "${core_version%%$'\n'*}" == 'sing-box version 1.14.2' ]] || {
    printf 'set SINGBOX_BINARY_114 to the supported sing-box 1.14.2 core\n' >&2; exit 1;
  }
  docker_local image inspect "${image}" >/dev/null
  artifact_dir=$(mktemp -d "${DUAL_STACK_ARTIFACT_ROOT:-/tmp}/sbv-default-dual-stack.XXXXXXXX")
  staging_dir=$(mktemp -d /tmp/sbv-default-dual-stack-input.XXXXXXXX)
  container_id=''
  cleanup_container() {
    local status=$?
    trap - EXIT
    if [[ -n "${container_id}" ]]; then
      if ! docker_local cp "${container_id}:/tmp/sbv-dual-stack-artifacts/." "${artifact_dir}/"; then
        printf 'could not extract dual-stack runtime evidence\n' >&2
        status=1
      fi
      if ! docker_local rm -f "${container_id}" >/dev/null; then
        printf 'could not remove the owned dual-stack test container\n' >&2
        status=1
      fi
    fi
    if ! rm -rf -- "${staging_dir}"; then status=1; fi
    printf 'Dual-stack runtime artifacts: %s\n' "${artifact_dir}"
    exit "${status}"
  }
  trap cleanup_container EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir -p "${staging_dir}/tests"
  cp -- "${REPO_ROOT}/install.sh" "${staging_dir}/install.sh"
  cp -- "${REPO_ROOT}/tests/menu_test_helper.sh" \
    "${REPO_ROOT}/tests/default_dual_stack_runtime.sh" "${staging_dir}/tests/"
  cp -- "${core}" "${staging_dir}/sing-box"
  container_id=$(docker_local create --network none \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 \
    --sysctl net.ipv6.conf.lo.disable_ipv6=0 \
    --entrypoint bash "${image}" \
    /tmp/sbv-default-dual-stack/tests/default_dual_stack_runtime.sh --container)
  docker_local cp "${staging_dir}" "${container_id}:/tmp/sbv-default-dual-stack"
  docker_local start -a "${container_id}"
  container_status=$(docker_local inspect --format '{{.State.ExitCode}}' "${container_id}")
  [[ "${container_status}" =~ ^[0-9]+$ && "${container_status}" -le 255 ]] || {
    printf 'invalid dual-stack fixture exit status\n' >&2; exit 1;
  }
  if [[ "${container_status}" != 0 ]]; then
    printf 'dual-stack fixture failed with status %s\n' "${container_status}" >&2
    exit "${container_status}"
  fi
  exit 0
fi

[[ $# == 1 && -f /.dockerenv ]] || {
  printf 'the runtime fixture requires its disposable Docker container\n' >&2; exit 64;
}
ARTIFACT_DIR=/tmp/sbv-dual-stack-artifacts
mkdir -m 700 "${ARTIFACT_DIR}"
source "${REPO_ROOT}/tests/menu_test_helper.sh"
setup_menu_test_env 120
cp -- "${REPO_ROOT}/sing-box" "${TMP_DIR}/bin/sing-box"
source "${TESTABLE_INSTALL}"
SB_VERSION=1.14.2
server_pid='' client_pid='' marker_pid=''

stop_owned_process() {
  local pid=${1:-} status
  [[ -n "${pid}" ]] || return 0
  if kill -0 "${pid}" 2>/dev/null; then kill -TERM "${pid}" || return 1; fi
  if wait "${pid}"; then return 0; else status=$?; fi
  [[ "${status}" == 130 || "${status}" == 143 ]]
}

cleanup_fixture() {
  local status=$? pid log
  trap - EXIT
  for pid in "${client_pid}" "${server_pid}" "${marker_pid}"; do
    stop_owned_process "${pid}" || status=1
  done
  if [[ "${status}" != 0 ]]; then
    for log in "${ARTIFACT_DIR}"/*.log; do
      [[ ! -f "${log}" ]] || tail -30 "${log}" >&2
    done
  fi
  printf 'status=%s\n' "${status}" > "${ARTIFACT_DIR}/result.env"
  rm -rf -- "${TMP_DIR}"
  exit "${status}"
}
trap cleanup_fixture EXIT
trap 'printf "default dual-stack runtime failed at line %s\n" "${LINENO}" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

"${SINGBOX_BIN_PATH}" version > "${ARTIFACT_DIR}/core-version.txt"
sha256sum "${REPO_ROOT}/install.sh" "${BASH_SOURCE[0]}" > "${ARTIFACT_DIR}/source.sha256"
python3 - <<'PY' > "${ARTIFACT_DIR}/ipv6-loopback.txt"
import socket
with socket.socket(socket.AF_INET6, socket.SOCK_STREAM) as listener:
    listener.bind(("::1", 0))
    print("IPv6 loopback available")
PY
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"

# HTTP uses its real new-install defaults and typed store renderer. Credentials
# are fixture-only; do not replace the listen address in the generated record.
set_protocol_defaults http
[[ "${SB_MIXED_LISTEN_ADDRESS}" == :: ]]
SB_NODE_NAME=dual-stack-http
SB_MIXED_USERNAME=fixture-user
SB_MIXED_PASSWORD=fixture-http-password
http_port=${SB_PORT}
save_http_state
render_structured_instance_inbounds http "${SB_PROTOCOL_STATE_DIR}/instances/http.json" \
  > "${ARTIFACT_DIR}/http-inbound.json"
jq -e '.type=="http" and .listen=="::"' "${ARTIFACT_DIR}/http-inbound.json" >/dev/null

# Generate a HY2 instance through the real create prompts, leaving the listener
# blank. A private self-signed certificate avoids ACME or other external calls.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=dual-stack.invalid \
  -addext subjectAltName=DNS:dual-stack.invalid -addext basicConstraints=critical,CA:TRUE \
  -keyout "${ARTIFACT_DIR}/server.key" -out "${ARTIFACT_DIR}/server.crt" \
  > "${ARTIFACT_DIR}/openssl.log" 2>&1
structured_instance_store_empty_json hy2 > "${TMP_DIR}/hy2-empty.json"
printf '%s\n' '' '' '' '' 48443 '' fixture-user fixture-hy2-password \
  2 dual-stack.invalid "${ARTIFACT_DIR}/server.crt" "${ARTIFACT_DIR}/server.key" \
  1 '' '' n '' y > "${TMP_DIR}/hy2-create.input"
hy2_management_build_record "${TMP_DIR}/hy2-empty.json" create '' \
  "${ARTIFACT_DIR}/hy2-record.json" < "${TMP_DIR}/hy2-create.input" \
  > "${ARTIFACT_DIR}/hy2-create.stdout.log" 2> "${ARTIFACT_DIR}/hy2-create.stderr.log"
jq -e '.listen.address=="::" and .listen.port==48443' "${ARTIFACT_DIR}/hy2-record.json" >/dev/null
store="${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
structured_instance_store_candidate hy2 '' create "${ARTIFACT_DIR}/hy2-record.json" 0 > "${store}"
render_structured_instance_inbounds hy2 "${store}" > "${ARTIFACT_DIR}/hy2-inbound.json"
jq -e '.type=="hysteria2" and .listen=="::"' "${ARTIFACT_DIR}/hy2-inbound.json" >/dev/null
jq -n --slurpfile http "${ARTIFACT_DIR}/http-inbound.json" \
  --slurpfile hy2 "${ARTIFACT_DIR}/hy2-inbound.json" \
  '{log:{level:"info"},inbounds:($http+$hy2),outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
  > "${ARTIFACT_DIR}/server.json"
"${SINGBOX_BIN_PATH}" check -c "${ARTIFACT_DIR}/server.json" > "${ARTIFACT_DIR}/server.check.log" 2>&1
managed_listener_plan "${ARTIFACT_DIR}/server.json" > "${ARTIFACT_DIR}/listener-plan.json"
jq -e 'length==2 and all(.[]; .dual_stack==true)' "${ARTIFACT_DIR}/listener-plan.json" >/dev/null
instance_firewall_targets_json "$(cat "${ARTIFACT_DIR}/listener-plan.json")" > "${ARTIFACT_DIR}/firewall-targets.json"
jq -e 'length==4 and
  ([.[]|select(.protocol=="http")]|map(.family)|sort)==["ipv4","ipv6"] and
  ([.[]|select(.protocol=="hy2")]|map(.family)|sort)==["ipv4","ipv6"] and
  all(.[]; if .family=="ipv4" then .address=="0.0.0.0" else .address=="::" end) and
  all(.[]; if .protocol=="http" then .transport=="tcp" else .transport=="udp" end)' \
  "${ARTIFACT_DIR}/firewall-targets.json" >/dev/null
printf 'PASS generated TCP/UDP listeners and both-family firewall targets\n'

python3 -u - "${ARTIFACT_DIR}/marker.port" <<'PY' > "${ARTIFACT_DIR}/marker.log" 2>&1 &
import http.server
import pathlib
import sys

class Marker(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        payload = b"default-dual-stack-runtime-ok\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

with http.server.HTTPServer(("127.0.0.1", 0), Marker) as server:
    pathlib.Path(sys.argv[1]).write_text(str(server.server_port), encoding="ascii")
    server.serve_forever()
PY
marker_pid=$!
for _ in {1..100}; do
  [[ -s "${ARTIFACT_DIR}/marker.port" ]] && break
  kill -0 "${marker_pid}"
  sleep 0.02
done
marker_port=$(cat "${ARTIFACT_DIR}/marker.port")
: > "${ARTIFACT_DIR}/server.log"
"${SINGBOX_BIN_PATH}" run -c "${ARTIFACT_DIR}/server.json" > "${ARTIFACT_DIR}/server.log" 2>&1 &
server_pid=$!
wait_for_core() {
  local pid=$1 log_file=$2 attempt
  for attempt in {1..100}; do
    kill -0 "${pid}" || return 1
    if grep -Fq 'sing-box started' "${log_file}"; then return 0; fi
    sleep 0.05
  done
  printf 'core startup timed out: %s\n' "${log_file}" >&2
  return 1
}
wait_for_core "${server_pid}" "${ARTIFACT_DIR}/server.log"
ss -lntup > "${ARTIFACT_DIR}/listeners.txt"

for family in v4 v6; do
  if [[ "${family}" == v4 ]]; then address=127.0.0.1; uri_host=127.0.0.1; else address=::1; uri_host='[::1]'; fi
  curl --fail --silent --show-error --max-time 8 --noproxy '' \
    --proxy "http://fixture-user:fixture-http-password@${uri_host}:${http_port}" \
    "http://127.0.0.1:${marker_port}/http-${family}" > "${ARTIFACT_DIR}/http-${family}.body"
  grep -Fxq default-dual-stack-runtime-ok "${ARTIFACT_DIR}/http-${family}.body"
  printf 'PASS HTTP TCP %s through the same default :: listener\n' "${family}"
  jq -n --arg server "${address}" --arg cert "${ARTIFACT_DIR}/server.crt" \
    '{log:{level:"info"},inbounds:[{type:"socks",tag:"local",listen:"127.0.0.1",listen_port:19080}],
      outbounds:[{type:"hysteria2",tag:"proxy",server:$server,server_port:48443,
        password:"fixture-hy2-password",tls:{enabled:true,server_name:"dual-stack.invalid",certificate_path:$cert}}],
      route:{final:"proxy"}}' > "${ARTIFACT_DIR}/hy2-client-${family}.json"
  "${SINGBOX_BIN_PATH}" check -c "${ARTIFACT_DIR}/hy2-client-${family}.json" \
    > "${ARTIFACT_DIR}/hy2-client-${family}.check.log" 2>&1
  : > "${ARTIFACT_DIR}/hy2-client-${family}.log"
  "${SINGBOX_BIN_PATH}" run -c "${ARTIFACT_DIR}/hy2-client-${family}.json" \
    > "${ARTIFACT_DIR}/hy2-client-${family}.log" 2>&1 &
  client_pid=$!
  wait_for_core "${client_pid}" "${ARTIFACT_DIR}/hy2-client-${family}.log"
  curl --fail --silent --show-error --max-time 8 --noproxy '' \
    --proxy socks5h://127.0.0.1:19080 \
    "http://127.0.0.1:${marker_port}/hy2-${family}" > "${ARTIFACT_DIR}/hy2-${family}.body"
  grep -Fxq default-dual-stack-runtime-ok "${ARTIFACT_DIR}/hy2-${family}.body"
  printf 'PASS HY2 UDP %s through the same default :: listener\n' "${family}"
  stop_owned_process "${client_pid}"
  client_pid=''
done
printf 'checks=4\nserver_config_checks=1\nclient_config_checks=2\nfirewall_target_families=2\n' \
  > "${ARTIFACT_DIR}/coverage.env"
printf 'Default dual-stack runtime checks passed (HTTP TCP and HY2 UDP, IPv4 and IPv6)\n'
