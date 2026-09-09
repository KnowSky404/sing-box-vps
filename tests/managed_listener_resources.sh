#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at top level so Bash 4.2 keeps the readonly registry array global.
source "${TESTABLE_INSTALL}"

trap 'printf "managed listener resource test failed at line %s\n" "${LINENO}" >&2' ERR

runtime_core_pid=''
runtime_marker_pid=''
cleanup_runtime() {
  local pid
  for pid in "${runtime_core_pid}" "${runtime_marker_pid}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" 2>/dev/null; then
      if ! kill -TERM "${pid}" 2>/dev/null; then
        printf 'cleanup warning: could not stop owned test process %s\n' "${pid}" >&2
      fi
    fi
    if wait "${pid}" 2>/dev/null; then :; else :; fi
  done
  rm -rf -- "${TMP_DIR}"
}
trap cleanup_runtime EXIT

for api in managed_listener_plan validate_managed_listener_resources; do
  declare -F "${api}" >/dev/null || {
    printf 'missing managed listener API: %s\n' "${api}" >&2
    exit 1
  }
done

structured_instance_store_validate_address '0:0:0:0:0:ffff:192.0.2.7'

SECRET='listener-test-password-must-not-leak'
TAG_MARKERS='mixed-default|vless-ipv6|anytls-ipv6|hy2-udp|sensitive-tag|duplicate-tag|first-listener|second-listener|structured-first|structured-second'

assert_private_failure() {
  local stdout_file=$1
  local stderr_file=$2
  [[ ! -s "${stdout_file}" ]] || {
    printf 'failed listener operation emitted partial stdout\n' >&2
    return 1
  }
  if grep -E -q "${SECRET}|${TAG_MARKERS}" "${stderr_file}"; then
    printf 'failed listener operation leaked sensitive value\n' >&2
    return 1
  fi
}

expect_reject() {
  local label=$1
  local config=$2
  local status=0

  managed_listener_plan "${config}" >"${TMP_DIR}/${label}.plan.out" \
    2>"${TMP_DIR}/${label}.plan.err" || status=$?
  [[ "${status}" != 0 ]] || {
    printf 'listener plan accepted invalid fixture: %s\n' "${label}" >&2
    return 1
  }
  assert_private_failure "${TMP_DIR}/${label}.plan.out" "${TMP_DIR}/${label}.plan.err"

  status=0
  validate_managed_listener_resources "${config}" >"${TMP_DIR}/${label}.validate.out" \
    2>"${TMP_DIR}/${label}.validate.err" || status=$?
  [[ "${status}" != 0 ]] || {
    printf 'listener validator accepted invalid fixture: %s\n' "${label}" >&2
    return 1
  }
  [[ -s "${TMP_DIR}/${label}.validate.err" ]] || {
    printf 'listener validator has no fixed failure diagnostic: %s\n' "${label}" >&2
    return 1
  }
  assert_private_failure "${TMP_DIR}/${label}.validate.out" "${TMP_DIR}/${label}.validate.err"
}

expect_accept() {
  local label=$1
  local config=$2
  managed_listener_plan "${config}" >"${TMP_DIR}/${label}.plan.json"
  validate_managed_listener_resources "${config}" >"${TMP_DIR}/${label}.validate.out" \
    2>"${TMP_DIR}/${label}.validate.err"
  [[ ! -s "${TMP_DIR}/${label}.validate.out" && ! -s "${TMP_DIR}/${label}.validate.err" ]] || {
    printf 'listener validator produced output for valid fixture: %s\n' "${label}" >&2
    return 1
  }
}

expect_conflict_reject() {
  local label=$1
  local config=$2
  local status=0

  managed_listener_plan "${config}" >"${TMP_DIR}/${label}.plan.json"
  jq -e 'type == "array" and length == 2' "${TMP_DIR}/${label}.plan.json" >/dev/null
  validate_managed_listener_resources "${config}" >"${TMP_DIR}/${label}.validate.out" \
    2>"${TMP_DIR}/${label}.validate.err" || status=$?
  [[ "${status}" != 0 ]] || {
    printf 'listener validator accepted overlapping fixture: %s\n' "${label}" >&2
    return 1
  }
  [[ -s "${TMP_DIR}/${label}.validate.err" ]] || {
    printf 'listener validator has no fixed conflict diagnostic: %s\n' "${label}" >&2
    return 1
  }
  assert_private_failure "${TMP_DIR}/${label}.validate.out" "${TMP_DIR}/${label}.validate.err"
}

base_config="${TMP_DIR}/base.json"
jq -n --arg secret "${SECRET}" '
  {inbounds:[
    {type:"mixed",tag:"mixed-default",listen_port:21001},
    {type:"vless",tag:"vless-ipv6",listen:"::1",listen_port:21002,
      users:[{uuid:"11111111-1111-4111-8111-111111111111",password:$secret}],
      tls:{reality:{}}},
    {type:"anytls",tag:"anytls-ipv6",listen:"2001:0DB8:0:0:0:0:0:AB",listen_port:21003},
    {type:"hysteria2",tag:"hy2-udp",listen:"0.0.0.0",listen_port:21004,
      users:[{name:"test-user",password:$secret}],tls:{enabled:true}}
  ]}' >"${base_config}"
expect_accept base "${base_config}"
jq -e '
  length == 4 and
  .[0] == {owner:"mixed-default",protocol:"mixed",address:"127.0.0.1",family:"ipv4",transport:"tcp",port:21001,dual_stack:false} and
  .[1] == {owner:"vless-ipv6",protocol:"vless-reality",address:"0000:0000:0000:0000:0000:0000:0000:0001",family:"ipv6",transport:"tcp",port:21002,dual_stack:false} and
  .[2] == {owner:"anytls-ipv6",protocol:"anytls",address:"2001:0db8:0000:0000:0000:0000:0000:00ab",family:"ipv6",transport:"tcp",port:21003,dual_stack:false} and
  .[3] == {owner:"hy2-udp",protocol:"hy2",address:"0.0.0.0",family:"ipv4",transport:"udp",port:21004,dual_stack:false}
' "${TMP_DIR}/base.plan.json" >/dev/null

jq '.inbounds=[{type:"mixed",tag:"mapped-ipv6",listen:"::ffff:192.0.2.7",listen_port:21005}]' \
  "${base_config}" >"${TMP_DIR}/mapped.json"
expect_accept mapped "${TMP_DIR}/mapped.json"
jq -e '.[0] == {owner:"mapped-ipv6",protocol:"mixed",address:"192.0.2.7",family:"ipv4",transport:"tcp",port:21005,dual_stack:false}' \
  "${TMP_DIR}/mapped.plan.json" >/dev/null
jq '.inbounds=[{type:"mixed",tag:"mapped-ipv6-full",listen:"0:0:0:0:0:ffff:192.0.2.7",listen_port:21006}]' \
  "${base_config}" >"${TMP_DIR}/mapped-full.json"
expect_accept mapped-full "${TMP_DIR}/mapped-full.json"
jq -e '.[0] == {owner:"mapped-ipv6-full",protocol:"mixed",address:"192.0.2.7",family:"ipv4",transport:"tcp",port:21006,dual_stack:false}' \
  "${TMP_DIR}/mapped-full.plan.json" >/dev/null

invalid_index=0
for mutation in \
  '.inbounds[0].type="unknown"' \
  '.inbounds[0].listen="not-a-host"' \
  '.inbounds[0].listen="1::2::3"' \
  '.inbounds[0].listen="999.1.2.3"' \
  '.inbounds[0].listen="127.0.0.1/24"' \
  '.inbounds[0].listen=[]' \
  '.inbounds[0].listen=""' \
  '.inbounds[0].listen_port=0' \
  '.inbounds[0].listen_port=65536' \
  '.inbounds[0].listen_port=1.5' \
  '.inbounds[0].listen_port="21001"' \
  '.inbounds[0].listen_port=true' \
  '.inbounds[0].tag=null' \
  '.inbounds[0].tag=""' \
  '.inbounds[0].type=""' \
  '.inbounds[0].tag="sensitive-tag\nforged"' \
  '.inbounds[0].netns="private-netns"' \
  '.inbounds[0].bind_interface="eth0"' \
  '.inbounds[0].reuse_addr=true' \
  '.endpoints={}' \
  '.endpoints=[{type:"unknown-endpoint",listen_port:21111}]' \
  '.inbounds="not-an-array"' \
  '.inbounds[0]="not-an-object"' \
  '.inbounds[0].listen_port=null'; do
  invalid_index=$((invalid_index + 1))
  jq "${mutation}" "${base_config}" >"${TMP_DIR}/invalid-${invalid_index}.json"
  expect_reject "invalid-${invalid_index}" "${TMP_DIR}/invalid-${invalid_index}.json"
done

jq '.inbounds[0].tag="duplicate-tag" | .inbounds[1].tag="duplicate-tag"' \
  "${base_config}" >"${TMP_DIR}/duplicate-tag.json"
expect_reject duplicate-tag "${TMP_DIR}/duplicate-tag.json"

make_two_listener_config() {
  local first_type=$1
  local first_address=$2
  local second_type=$3
  local second_address=$4
  local port=$5
  local destination=$6
  jq -n --arg first_type "${first_type}" --arg first_address "${first_address}" \
    --arg second_type "${second_type}" --arg second_address "${second_address}" \
    --argjson port "${port}" \
    '{inbounds:[
      {type:$first_type,tag:"first-listener",listen:$first_address,listen_port:$port},
      {type:$second_type,tag:"second-listener",listen:$second_address,listen_port:$port}
    ]}' >"${destination}"
}

conflict_index=0
for conflict in \
  'mixed|127.0.0.1|anytls|127.0.0.1' \
  'mixed|0.0.0.0|anytls|192.0.2.8' \
  'mixed|::|anytls|192.0.2.9' \
  'mixed|::1|anytls|0:0:0:0:0:0:0:1' \
  'mixed|::ffff:192.0.2.7|anytls|192.0.2.7' \
  'mixed|0:0:0:0:0:ffff:192.0.2.7|anytls|192.0.2.7'; do
  conflict_index=$((conflict_index + 1))
  IFS='|' read -r first_type first_address second_type second_address <<<"${conflict}"
  make_two_listener_config "${first_type}" "${first_address}" "${second_type}" "${second_address}" \
    21010 "${TMP_DIR}/conflict-${conflict_index}.json"
  expect_conflict_reject "conflict-${conflict_index}" "${TMP_DIR}/conflict-${conflict_index}.json"
done

make_two_listener_config mixed 127.0.0.1 anytls 127.0.0.2 21020 "${TMP_DIR}/different-ipv4.json"
expect_accept different-ipv4 "${TMP_DIR}/different-ipv4.json"
make_two_listener_config mixed ::1 anytls 127.0.0.1 21021 "${TMP_DIR}/separate-loopback-families.json"
expect_accept separate-loopback-families "${TMP_DIR}/separate-loopback-families.json"
make_two_listener_config mixed 127.0.0.1 hysteria2 127.0.0.1 21022 "${TMP_DIR}/tcp-udp-share.json"
expect_accept tcp-udp-share "${TMP_DIR}/tcp-udp-share.json"

structured_base="${TMP_DIR}/structured-base.json"
jq -n --arg secret "${SECRET}" '
  {schema_version:1,protocol:"mixed",revision:1,default_instance_id:"first",instances:[
    {id:"first",name:"first node",tag:"structured-first",listen:{address:"192.0.2.10",port:21100},
      authentication:{enabled:true,username:"structured-user",password:$secret},outbound_policy:"default",dependencies:[]},
    {id:"second",name:"second node",tag:"structured-second",listen:{address:"192.0.2.11",port:21101},
      authentication:{enabled:true,username:"structured-user-2",password:$secret},outbound_policy:"default",dependencies:[]}
  ]}' >"${structured_base}"
validate_structured_instance_store mixed "${structured_base}" >"${TMP_DIR}/structured-valid.out" \
  2>"${TMP_DIR}/structured-valid.err"
[[ ! -s "${TMP_DIR}/structured-valid.out" && ! -s "${TMP_DIR}/structured-valid.err" ]]

for structured_case in wildcard equivalent-ipv6; do
  case "${structured_case}" in
    wildcard)
      jq '.instances[0].listen={address:"0.0.0.0",port:21100} | .instances[1].listen={address:"192.0.2.11",port:21100}' \
        "${structured_base}" >"${TMP_DIR}/structured-${structured_case}.json" ;;
    equivalent-ipv6)
      jq '.instances[0].listen={address:"::1",port:21100} | .instances[1].listen={address:"0:0:0:0:0:0:0:1",port:21100}' \
        "${structured_base}" >"${TMP_DIR}/structured-${structured_case}.json" ;;
  esac
  status=0
  validate_structured_instance_store mixed "${TMP_DIR}/structured-${structured_case}.json" \
    >"${TMP_DIR}/structured-${structured_case}.out" \
    2>"${TMP_DIR}/structured-${structured_case}.err" || status=$?
  [[ "${status}" != 0 ]] || {
    printf 'structured listener overlap accepted: %s\n' "${structured_case}" >&2
    exit 1
  }
  [[ -s "${TMP_DIR}/structured-${structured_case}.err" ]]
  assert_private_failure "${TMP_DIR}/structured-${structured_case}.out" \
    "${TMP_DIR}/structured-${structured_case}.err"
done

ipv6_runtime='unavailable'
if python3 - <<'PY' >/dev/null 2>&1
import socket

sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
sock.bind(("::1", 0))
sock.close()
PY
then
  ipv6_runtime='available'
else
  printf 'SKIP IPv6 runtime socket checks: ::1 is unavailable\n'
fi

allocate_port() {
  python3 - <<'PY'
import socket

tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
tcp.bind(("127.0.0.1", 0))
port = tcp.getsockname()[1]
udp.bind(("127.0.0.1", port))
tcp.close()
udp.close()
print(port)
PY
}

real_core_checks=0
real_core_starts=0
real_business_probes=0
real_startup_contrasts=0
real_wildcard_contrasts=0

if [[ -n "${SINGBOX_BINARY_113:-}${SINGBOX_BINARY_114:-}" ]]; then
  if ! command -v openssl >/dev/null 2>&1; then
    printf 'SKIP real core checks: openssl unavailable for isolated Hysteria2 TLS\n'
  else
    cert_file="${TMP_DIR}/localhost.crt"
    key_file="${TMP_DIR}/localhost.key"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
      -keyout "${key_file}" -out "${cert_file}" \
      >"${TMP_DIR}/openssl.out" 2>"${TMP_DIR}/openssl.err"
    chmod 600 "${key_file}"

    marker_info="${TMP_DIR}/marker-info.json"
    python3 -u - "${marker_info}" <<'PY' &
import http.server
import json
import sys

output = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"managed-listener-loopback-marker\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(output, "w", encoding="ascii") as handle:
    json.dump({"port": server.server_port}, handle)
    handle.write("\n")
    handle.flush()
server.serve_forever()
PY
    runtime_marker_pid=$!
    for attempt in {1..100}; do
      [[ -s "${marker_info}" ]] && break
      kill -0 "${runtime_marker_pid}" 2>/dev/null || break
      sleep 0.05
    done
    [[ -s "${marker_info}" ]] || {
      printf 'isolated marker service did not start\n' >&2
      exit 1
    }
    marker_port=$(jq -r '.port' "${marker_info}")

    for binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
      [[ -n "${binary}" ]] || continue
      [[ -x "${binary}" ]] || {
        printf 'configured real core is not executable: %s\n' "${binary}" >&2
        exit 1
      }
      shared_port=$(allocate_port)
      same_port_config="${TMP_DIR}/same-port-$(basename "${binary}").json"
      jq -n --arg cert "${cert_file}" --arg key "${key_file}" --argjson port "${shared_port}" '
        {inbounds:[
          {type:"mixed",tag:"tcp-one",listen:"127.0.0.1",listen_port:$port},
          {type:"mixed",tag:"tcp-two",listen:"127.0.0.2",listen_port:$port},
          {type:"hysteria2",tag:"udp-one",listen:"127.0.0.1",listen_port:$port,
            users:[{name:"core-test",password:"core-test-password"}],
            tls:{enabled:true,certificate_path:$cert,key_path:$key}}
        ],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
        >"${same_port_config}"
      managed_listener_plan "${same_port_config}" >"${TMP_DIR}/same-port.plan.json"
      validate_managed_listener_resources "${same_port_config}" >"${TMP_DIR}/same-port.validate.out" \
        2>"${TMP_DIR}/same-port.validate.err"
      [[ ! -s "${TMP_DIR}/same-port.validate.out" && ! -s "${TMP_DIR}/same-port.validate.err" ]]
      "${binary}" check -c "${same_port_config}" \
        >"${TMP_DIR}/same-port.check.out" 2>"${TMP_DIR}/same-port.check.err"
      real_core_checks=$((real_core_checks + 1))

      "${binary}" run -c "${same_port_config}" \
        >"${TMP_DIR}/same-port.run.out" 2>"${TMP_DIR}/same-port.run.err" &
      runtime_core_pid=$!
      started='n'
      for attempt in {1..120}; do
        if ! kill -0 "${runtime_core_pid}" 2>/dev/null; then break; fi
        if ss -H -lnt 2>/dev/null | grep -E -q ":${shared_port}([[:space:]]|$)" \
          && ss -H -lnu 2>/dev/null | grep -E -q ":${shared_port}([[:space:]]|$)"; then
          started='y'
          break
        fi
        sleep 0.05
      done
      [[ "${started}" == y ]] || {
        printf 'real core did not start TCP+UDP same-port fixture: %s\n' "${binary}" >&2
        exit 1
      }
      real_core_starts=$((real_core_starts + 1))
      for proxy_address in 127.0.0.1 127.0.0.2; do
        curl --silent --show-error --fail --max-time 3 --noproxy '' \
          --proxy "http://${proxy_address}:${shared_port}" \
          "http://127.0.0.1:${marker_port}/marker" >"${TMP_DIR}/marker.body" \
          2>"${TMP_DIR}/marker.curl.err"
        grep -Fqx 'managed-listener-loopback-marker' "${TMP_DIR}/marker.body"
        real_business_probes=$((real_business_probes + 1))
      done
      if ! kill -TERM "${runtime_core_pid}" 2>/dev/null; then
        printf 'could not stop owned real core process: %s\n' "${binary}" >&2
        exit 1
      fi
      if wait "${runtime_core_pid}"; then :; else :; fi
      runtime_core_pid=''

      if [[ "${ipv6_runtime}" == available ]]; then
        equivalent_port=$(allocate_port)
        equivalent_config="${TMP_DIR}/equivalent-ipv6-$(basename "${binary}").json"
        make_two_listener_config mixed ::1 mixed 0:0:0:0:0:0:0:1 "${equivalent_port}" "${equivalent_config}"
        expect_conflict_reject "equivalent-ipv6-$(basename "${binary}")" "${equivalent_config}"
        "${binary}" check -c "${equivalent_config}" >"${TMP_DIR}/equivalent.check.out" \
          2>"${TMP_DIR}/equivalent.check.err"
        real_core_checks=$((real_core_checks + 1))
        "${binary}" run -c "${equivalent_config}" >"${TMP_DIR}/equivalent.run.out" \
          2>"${TMP_DIR}/equivalent.run.err" &
        runtime_core_pid=$!
        equivalent_exited='n'
        for attempt in {1..120}; do
          if ! kill -0 "${runtime_core_pid}" 2>/dev/null; then
            equivalent_exited='y'
            break
          fi
          sleep 0.05
        done
        [[ "${equivalent_exited}" == y ]] || {
          if ! kill -TERM "${runtime_core_pid}" 2>/dev/null; then
            printf 'could not stop owned equivalent-IPv6 core process: %s\n' "${binary}" >&2
          fi
          forced_wait_status=0
          wait "${runtime_core_pid}" 2>/dev/null || forced_wait_status=$?
          runtime_core_pid=''
          printf 'equivalent IPv6 conflict unexpectedly stayed running: %s\n' "${binary}" >&2
          exit 1
        }
        equivalent_status=0
        wait "${runtime_core_pid}" || equivalent_status=$?
        runtime_core_pid=''
        [[ "${equivalent_status}" != 0 ]] || {
          printf 'equivalent IPv6 conflict exited successfully: %s\n' "${binary}" >&2
          exit 1
        }
        grep -Eiq 'address already in use' "${TMP_DIR}/equivalent.run.err" || {
          printf 'equivalent IPv6 startup did not report address conflict: %s\n' "${binary}" >&2
          exit 1
        }
        real_startup_contrasts=$((real_startup_contrasts + 1))
      fi

      # This opt-in case is reserved for the verification harness's isolated
      # Docker/network namespace. It is deliberately never exercised on the
      # host because an unspecified IPv6 bind can expose a service globally.
      if [[ "${SBV_TEST_ISOLATED_LISTENER_WILDCARD:-0}" == 1 ]]; then
        [[ "${ipv6_runtime}" == available ]] || {
          printf 'isolated wildcard test requested but IPv6 is unavailable\n' >&2
          exit 1
        }
        wildcard_port=$(allocate_port)
        wildcard_config="${TMP_DIR}/wildcard-$(basename "${binary}").json"
        make_two_listener_config mixed :: mixed 127.0.0.1 "${wildcard_port}" "${wildcard_config}"
        expect_conflict_reject "wildcard-$(basename "${binary}")" "${wildcard_config}"
        "${binary}" check -c "${wildcard_config}" >"${TMP_DIR}/wildcard.check.out" \
          2>"${TMP_DIR}/wildcard.check.err"
        real_core_checks=$((real_core_checks + 1))
        "${binary}" run -c "${wildcard_config}" >"${TMP_DIR}/wildcard.run.out" \
          2>"${TMP_DIR}/wildcard.run.err" &
        runtime_core_pid=$!
        wildcard_exited='n'
        for attempt in {1..120}; do
          if ! kill -0 "${runtime_core_pid}" 2>/dev/null; then
            wildcard_exited='y'
            break
          fi
          sleep 0.05
        done
        [[ "${wildcard_exited}" == y ]] || {
          if ! kill -TERM "${runtime_core_pid}" 2>/dev/null; then
            printf 'could not stop owned isolated wildcard core process: %s\n' "${binary}" >&2
          fi
          forced_wait_status=0
          wait "${runtime_core_pid}" 2>/dev/null || forced_wait_status=$?
          runtime_core_pid=''
          printf 'isolated wildcard conflict unexpectedly stayed running: %s\n' "${binary}" >&2
          exit 1
        }
        wildcard_status=0
        wait "${runtime_core_pid}" || wildcard_status=$?
        runtime_core_pid=''
        [[ "${wildcard_status}" != 0 ]] || {
          printf 'isolated wildcard conflict exited successfully: %s\n' "${binary}" >&2
          exit 1
        }
        grep -Eiq 'address already in use' "${TMP_DIR}/wildcard.run.err" || {
          printf 'isolated wildcard startup did not report address conflict: %s\n' "${binary}" >&2
          exit 1
        }
        real_wildcard_contrasts=$((real_wildcard_contrasts + 1))
      fi
    done
    if ! kill -TERM "${runtime_marker_pid}" 2>/dev/null; then
      printf 'could not stop owned marker service\n' >&2
      exit 1
    fi
    if wait "${runtime_marker_pid}" 2>/dev/null; then :; else :; fi
    runtime_marker_pid=''
  fi
else
  printf 'SKIP real core check/start/business tests: SINGBOX_BINARY_113/114 not configured\n'
fi

if [[ "${ipv6_runtime}" == unavailable ]]; then
  printf 'IPv6 normalization/rejection tested; IPv6 kernel startup evidence was SKIP\n'
fi
printf 'managed listener resource checks passed; real core check=%s start=%s business=%s startup-contrasts=%s\n' \
  "${real_core_checks}" "${real_core_starts}" "${real_business_probes}" "${real_startup_contrasts}"
if [[ "${SBV_TEST_ISOLATED_LISTENER_WILDCARD:-0}" != 1 ]]; then
  printf 'SKIP isolated IPv6 wildcard startup contrast: set SBV_TEST_ISOLATED_LISTENER_WILDCARD=1 in verification Docker only\n'
else
  printf 'isolated IPv6 wildcard startup contrasts=%s\n' "${real_wildcard_contrasts}"
fi
