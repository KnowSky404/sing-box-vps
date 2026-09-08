#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

runtime_pid=''
stop_runtime() {
  local status
  [[ -n "${runtime_pid}" ]] || return 0
  if kill -0 "${runtime_pid}" 2>/dev/null; then
    kill -TERM "${runtime_pid}" || return 1
  fi
  if wait "${runtime_pid}"; then :; else
    status=$?
    runtime_pid=''
    [[ "${status}" == 143 || "${status}" == 130 ]] || {
      printf 'owned listener core exited unexpectedly: %s\n' "${status}" >&2
      return 1
    }
  fi
  runtime_pid=''
}
cleanup_network_test() {
  local status=$?
  stop_runtime || status=1
  if [[ "${status}" == 0 ]]; then
    rm -rf -- "${TMP_DIR}"
  else
    printf 'listener test failure artifacts retained: %s\n' "${TMP_DIR}" >&2
  fi
  exit "${status}"
}
trap cleanup_network_test EXIT

base_registry=$(protocol_registry_json)
config="${TMP_DIR}/network.json"
rejected=0
expect_rejected() {
  if managed_listener_plan "${config}" >"${TMP_DIR}/rejected.out" 2>"${TMP_DIR}/rejected.err"; then
    printf 'unexpectedly accepted network fixture\n' >&2
    return 1
  fi
  [[ ! -s "${TMP_DIR}/rejected.out" && -s "${TMP_DIR}/rejected.err" ]]
  ! grep -Fq 'secret-marker' "${TMP_DIR}/rejected.err"
  rejected=$((rejected+1))
}

# No Shadowsocks project adapter is advertised by this foundational test.
# The test-only metadata below exercises an upcoming dual-listener adapter.
jq -n '{inbounds:[{type:"shadowsocks",tag:"secret-marker",listen_port:23801}]}' >"${config}"
expect_rejected
fixture_registry=$(jq '. + [{state_id:"shadowsocks",type:"shadowsocks",
  listen_networks:["tcp","udp"],traffic_networks:["tcp","udp"],
  features:{listen_network_selection:true}}]' <<<"${base_registry}")
protocol_registry_json() { printf '%s\n' "${fixture_registry}"; }

for selection in 'null' '[]' '"tcp"' '"udp"' '["tcp","udp"]' '["udp","tcp"]'; do
  jq -n --argjson selection "${selection}" '{inbounds:[{
    type:"shadowsocks",tag:"secret-marker",listen:"127.0.0.1",listen_port:23801,network:$selection
  }]}' >"${config}"
  plan=$(managed_listener_plan "${config}")
  expected=$(jq -cn --argjson selection "${selection}" '
    if $selection == null or $selection == [] then ["tcp","udp"]
    elif ($selection|type)=="string" then [$selection] else ($selection|sort) end')
  jq -e --argjson expected "${expected}" 'map(.transport) == $expected' <<<"${plan}" >/dev/null
done
jq 'del(.inbounds[0].network)' "${config}" >"${config}.next"
mv "${config}.next" "${config}"
managed_listener_plan "${config}" | jq -e 'map(.transport)==["tcp","udp"]' >/dev/null

for selection in '""' '"icmp"' 'true' '7' '{}' '["tcp","tcp"]' '["tcp",null]' '["tcp","secret-marker"]'; do
  jq --argjson selection "${selection}" '.inbounds[0].network=$selection' "${config}" >"${config}.next"
  mv "${config}.next" "${config}"
  expect_rejected
done

# Unmodelled network fields cannot redefine current fixed-listener presets.
for protocol in mixed socks http hysteria2 anytls vless; do
  jq -n --arg protocol "${protocol}" '{inbounds:[{type:$protocol,tag:"secret-marker",listen_port:23801,network:"udp"}]}' >"${config}"
  expect_rejected
done

# Malformed capability metadata must not yield a successful empty plan.
for networks in '[]' '["tcp","tcp"]' '["icmp"]' 'null' '"tcp"'; do
  fixture_registry=$(jq --argjson networks "${networks}" '. + [{state_id:"shadowsocks",type:"shadowsocks",listen_networks:$networks,features:{listen_network_selection:true}}]' <<<"${base_registry}")
  jq -n '{inbounds:[{type:"shadowsocks",tag:"secret-marker",listen_port:23801}]}' >"${config}"
  expect_rejected
done
fixture_registry=$(jq '. + [{state_id:"shadowsocks",type:"shadowsocks",listen_networks:["tcp","udp"],features:{listen_network_selection:true}}]' <<<"${base_registry}")

# A selector may narrow capabilities, never expand or coerce them.
fixture_registry=$(jq '. + [{state_id:"shadowsocks",type:"shadowsocks",listen_networks:["tcp"],features:{listen_network_selection:true}}]' <<<"${base_registry}")
jq -n '{inbounds:[{type:"shadowsocks",tag:"secret-marker",listen_port:23801,network:"udp"}]}' >"${config}"
expect_rejected
fixture_registry=$(jq '. + [{state_id:"shadowsocks",type:"shadowsocks",listen_networks:["tcp","udp"],features:{listen_network_selection:"true"}}]' <<<"${base_registry}")
expect_rejected
fixture_registry=$(jq '. + [{state_id:"shadowsocks",type:"shadowsocks",listen_networks:["tcp","udp"],features:{listen_network_selection:true}}]' <<<"${base_registry}")

# Same address/port with distinct fixed transports is not a collision.
jq -n '{inbounds:[
  {type:"shadowsocks",tag:"tcp-owner",listen:"127.0.0.1",listen_port:23801,network:"tcp"},
  {type:"shadowsocks",tag:"udp-owner",listen:"127.0.0.1",listen_port:23801,network:"udp"}
]}' >"${config}"
validate_managed_listener_resources "${config}"
jq '.inbounds[1].network="tcp"' "${config}" >"${config}.next"
if validate_managed_listener_resources "${config}.next" >"${TMP_DIR}/conflict.out" 2>"${TMP_DIR}/conflict.err"; then
  printf 'same-transport collision was missed\n' >&2; exit 1
fi
[[ ! -s "${TMP_DIR}/conflict.out" ]]

# These real-core checks prove listener projection, not SS lifecycle or
# traffic delivery. SS is deliberately still absent from the real registry.
# Read socket ownership without binding probes that could race core startup.
checks=0
starts=0
for core in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  [[ -n "${core}" ]] || continue
  [[ -x "${core}" ]] || { printf 'configured core unavailable\n' >&2; exit 1; }
  for selection in 'null' '[]' '"tcp"' '"udp"' '["tcp","udp"]' '["udp","tcp"]'; do
    port=$(python3 -c 'import socket; t=socket.socket(); t.bind(("127.0.0.1",0)); p=t.getsockname()[1]; u=socket.socket(type=socket.SOCK_DGRAM); u.bind(("127.0.0.1",p)); print(p); u.close(); t.close()')
    jq -n --argjson port "${port}" --argjson selection "${selection}" '{
      log:{level:"info"},inbounds:[{type:"shadowsocks",tag:"ss-probe",listen:"127.0.0.1",listen_port:$port,
        network:$selection,method:"aes-128-gcm",password:"listener-fixture-only"}],
      outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}
    }' >"${config}"
    "${core}" check -c "${config}" >"${TMP_DIR}/check.log" 2>&1
    checks=$((checks+1))
    expected=$(managed_listener_plan "${config}" | jq -r 'map(.transport)|join(",")')
    # Clear in the parent before the asynchronous redirection can run; a
    # previous process's completed-start marker must never satisfy this run.
    : >"${TMP_DIR}/core.log"
    "${core}" run -c "${config}" >>"${TMP_DIR}/core.log" 2>&1 &
    runtime_pid=$!
    # Listener sockets can exist before Box.Start finishes. Wait for the
    # core's completed-start marker before observations and normal shutdown;
    # stopping in that window can correctly exit 1 with context canceled.
    ready=n
    for attempt in {1..100}; do
      kill -0 "${runtime_pid}" 2>/dev/null || break
      if grep -Fq 'sing-box started' "${TMP_DIR}/core.log"; then
        ready=y
        break
      fi
      sleep 0.02
    done
    [[ "${ready}" == y ]] || { printf 'listener core did not complete startup\n' >&2; exit 1; }
    python3 - "${port}" "${expected}" "${runtime_pid}" <<'PY'
import os
import sys
import time

port = int(sys.argv[1])
expected = set(sys.argv[2].split(','))
pid = int(sys.argv[3])
for _ in range(100):
    os.kill(pid, 0)
    owned_inodes = set()
    for descriptor in os.listdir(f'/proc/{pid}/fd'):
        try:
            target = os.readlink(f'/proc/{pid}/fd/{descriptor}')
        except FileNotFoundError:
            continue
        if target.startswith('socket:[') and target.endswith(']'):
            owned_inodes.add(target[8:-1])
    occupied = set()
    for network in ['tcp', 'udp']:
        with open(f'/proc/{pid}/net/{network}', encoding='ascii') as table:
            for row in table.readlines()[1:]:
                columns = row.split()
                address, local_port = columns[1].split(':')
                if (address == '0100007F' and int(local_port, 16) == port
                        and columns[9] in owned_inodes
                        and (network == 'udp' or columns[3] == '0A')):
                    occupied.add(network)
    if occupied == expected:
        break
    time.sleep(0.02)
else:
    raise SystemExit('actual listener transports do not match resource plan')
PY
    starts=$((starts+1))
    stop_runtime
  done
done
if [[ "${checks}" == 0 ]]; then
  printf 'SKIP real core listener checks: set SINGBOX_BINARY_113/SINGBOX_BINARY_114\n'
fi
printf 'listener network selection passed: rejected=%s real-checks=%s real-starts=%s (resource evidence only)\n' "${rejected}" "${checks}" "${starts}"
