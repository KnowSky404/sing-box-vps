#!/usr/bin/env bash

set -euo pipefail
[[ "${SBV_COMPONENT_RUNTIME:-}" == 1 && -f /.dockerenv && -f /tmp/sbv-component-disposable ]] || {
  printf 'requires explicit disposable Docker fixture\n' >&2; exit 64;
}
CORE=${NAMESPACE_CORE_BINARY:?supply a target core}
ARTIFACT_DIR=${NAMESPACE_CORE_ARTIFACT_DIR:?supply a fresh artifact directory}
[[ ! -e "${ARTIFACT_DIR}" && -x "${CORE}" ]]
mkdir -p "${ARTIFACT_DIR}"
chmod 700 "${ARTIFACT_DIR}"
"${CORE}" version > "${ARTIFACT_DIR}/version.txt"
sha256sum "${CORE}" > "${ARTIFACT_DIR}/core.sha256"
grep -Fxq 'sing-box version 1.14.2' "${ARTIFACT_DIR}/version.txt"
CORE_PID='' MARKER_PID=''
cleanup() {
  local pid
  for pid in "${MARKER_PID}" "${CORE_PID}"; do
    [[ -n "${pid}" ]] || continue
    if kill -0 "${pid}" 2>/dev/null; then kill "${pid}"; fi
    if wait "${pid}"; then :; fi
  done
  if ip netns list | grep -Eq '^sbv-spec-minimal( |$)'; then ip netns delete sbv-spec-minimal; fi
}
trap cleanup EXIT
for mode in default unshare; do
  case_dir="${ARTIFACT_DIR}/${mode}"
  mkdir -p "${case_dir}/marker"
  printf 'namespace-%s-marker' "${mode}" > "${case_dir}/marker/index.html"
  if [[ "${mode}" == default ]]; then
    ip netns add sbv-spec-minimal
    ip netns exec sbv-spec-minimal ip link set lo up
    namespace_json='{"type":"default","tag":"ns","path":"/run/netns/sbv-spec-minimal"}'
    namespace_target=/run/netns/sbv-spec-minimal
  else
    namespace_json='{"type":"unshare","tag":"ns"}'
  fi
  jq -n --argjson namespace "${namespace_json}" '{log:{level:"debug"},network_namespaces:[$namespace],
    inbounds:[{type:"direct",tag:"positive",listen:"127.0.0.1",listen_port:21513,network:"tcp",override_address:"127.0.0.1",override_port:21512},
      {type:"direct",tag:"closed",listen:"127.0.0.1",listen_port:21515,network:"tcp",override_address:"127.0.0.1",override_port:21514}],
    outbounds:[{type:"direct",tag:"out",netns:"ns"}]}' > "${case_dir}/config.json"
  "${CORE}" check -c "${case_dir}/config.json" > "${case_dir}/check.log" 2>&1
  "${CORE}" run -c "${case_dir}/config.json" > "${case_dir}/core.log" 2>&1 &
  CORE_PID=$!
  if [[ "${mode}" == unshare ]]; then
    for attempt in {1..100}; do
      holder_pid=$(sed -n 's/.*holder pid: \([0-9]*\).*/\1/p' "${case_dir}/core.log" | head -n 1)
      [[ -n "${holder_pid}" ]] && break
      kill -0 "${CORE_PID}" || break
      sleep 0.1
    done
    [[ -n "${holder_pid}" ]]
    namespace_target="/proc/${holder_pid}/ns/net"
  fi
  nsenter --net="${namespace_target}" python3 -m http.server 21512 --bind 127.0.0.1 --directory "${case_dir}/marker" > "${case_dir}/marker.log" 2>&1 &
  MARKER_PID=$!
  ready=false
  for attempt in {1..50}; do
    if nsenter --net="${namespace_target}" curl -fsS --max-time 1 http://127.0.0.1:21512/ > "${case_dir}/control.txt" 2>"${case_dir}/control.err"; then ready=true; break; fi
    sleep 0.1
  done
  [[ "${ready}" == true ]]
  cmp "${case_dir}/marker/index.html" "${case_dir}/control.txt"
  for attempt in {1..50}; do
    if curl -fsS --max-time 1 http://127.0.0.1:21513/ > "${case_dir}/response.txt" 2>"${case_dir}/response.err"; then break; fi
    kill -0 "${CORE_PID}" || break
    sleep 0.1
  done
  sleep 0.3
  if ! kill -0 "${CORE_PID}" 2>/dev/null; then
    status=0; wait "${CORE_PID}" || status=$?
    printf 'CORE_EXIT=%s\nMODE=%s\n' "${status}" "${mode}" > "${case_dir}/failure.env"
    CORE_PID=''
    exit 1
  fi
  cmp "${case_dir}/marker/index.html" "${case_dir}/response.txt"
  if curl -fsS --max-time 2 http://127.0.0.1:21515/ > "${case_dir}/closed.txt" 2>"${case_dir}/closed.err"; then exit 1; fi
  sleep 0.3
  kill -0 "${CORE_PID}"
  printf 'RESULT=success\nTCP_MARKER=exact\nCLOSED_PORT=refused_without_core_exit\n' > "${case_dir}/result.env"
  kill "${MARKER_PID}" "${CORE_PID}"
  if wait "${MARKER_PID}"; then :; else [[ $? == 143 ]]; fi
  if wait "${CORE_PID}"; then :; else [[ $? == 143 ]]; fi
  MARKER_PID='' CORE_PID=''
  if [[ "${mode}" == default ]]; then
    test -e /run/netns/sbv-spec-minimal
    ip netns delete sbv-spec-minimal
  else
    [[ ! -e "/proc/${holder_pid}/ns/net" ]]
  fi
  printf '%s=passed\n' "${mode}" >> "${ARTIFACT_DIR}/results.env"
done
