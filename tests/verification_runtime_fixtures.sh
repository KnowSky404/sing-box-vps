#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
export FIXTURE_TEST_ROOT="${TMP_DIR}"
export FIXTURE_SOURCE="${REPO_ROOT}/dev/verification/remote/scenarios/runtime_fixtures.sh"
cat > "${TMP_DIR}/exercise.sh" <<'SH'
set -euo pipefail
source "${FIXTURE_SOURCE}"
VERIFY_CURRENT_SCENARIO_DIR=fixture
verification_prepare_remote_local_tree() { VERIFY_REMOTE_LOCAL_TREE_DIR="${FIXTURE_TEST_ROOT}/tree"; mkdir -p "${VERIFY_REMOTE_LOCAL_TREE_DIR}"; }
verification_cleanup_remote_local_tree() { rm -rf -- "${VERIFY_REMOTE_LOCAL_TREE_DIR}"; }
verification_artifact_path() { mkdir -p "${FIXTURE_TEST_ROOT}/artifacts/$(dirname "$1")"; printf '%s/%s\n' "${FIXTURE_TEST_ROOT}/artifacts" "$1"; }
verification_write_artifact() { local path=$1; shift; printf '%s\n' "$@" > "$(verification_artifact_path "${path}")"; }
verification_case_context_start none
verification_fixture_tcp_marker
verification_fixture_udp_echo
printf '%s\n' "${direct_marker_pid}" "${direct_udp_marker_pid}" > "${FIXTURE_TEST_ROOT}/pids"
curl -fsS --noproxy '*' "http://127.0.0.1:${direct_marker_port}/" > "${FIXTURE_TEST_ROOT}/response"
printf '%s\n' "${direct_marker}" | cmp -s - "${FIXTURE_TEST_ROOT}/response"
python3 - "${direct_udp_marker_port}" <<'PY'
import socket,sys
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
 s.settimeout(3)
 s.sendto(b'exact-marker',('127.0.0.1',int(sys.argv[1])))
 assert s.recvfrom(65535)[0] == b'exact-marker'
PY
if verification_case_stop_pid arbitrary_pid; then exit 98; fi
exit "${FIXTURE_EXPECTED_STATUS:-0}"
SH
bash "${TMP_DIR}/exercise.sh"
while read -r pid; do if kill -0 "${pid}" 2>/dev/null; then printf 'fixture process leaked\n' >&2; exit 1; fi; done < "${TMP_DIR}/pids"
grep -Fqx 'PROCESS_CLEANUP=success' "${TMP_DIR}/artifacts/fixture/cleanup.env"
status=0
FIXTURE_EXPECTED_STATUS=17 bash "${TMP_DIR}/exercise.sh" || status=$?
[[ ${status} == 17 ]]
while read -r pid; do if kill -0 "${pid}" 2>/dev/null; then exit 1; fi; done < "${TMP_DIR}/pids"
[[ ! -e "${TMP_DIR}/tree" ]]
printf 'Shared TCP/UDP markers, PID isolation and failure cleanup passed\n'

# Extract definitions without executing the privileged entrypoint. Only the
# fixed component-store path is redirected into this test's private directory.
python3 - "${REPO_ROOT}" "${TMP_DIR}" <<'PY'
import pathlib, sys
root, target = map(pathlib.Path, sys.argv[1:])
entry = (root / 'dev/verification/remote/entrypoint.sh').read_text()
redirect = entry[entry.index('verification_prepare_redirect_policy_fixture() {'):entry.index('# Exercise a Redirect inbound')]
tproxy = entry[entry.index('verification_execute_tproxy_probe() ('):entry.index('verification_cleanup_tproxy_probe_fixture() {')]
fixtures = (root / 'dev/verification/remote/scenarios/runtime_fixtures.sh').read_text()
cleanup = fixtures[fixtures.index('verification_case_cleanup_tproxy_component() {'):]
(target / 'policy-definitions.sh').write_text((redirect + tproxy + cleanup).replace(
    '/root/.sing-box-vps/runtime/components.json', '${FIXTURE_CASE_ROOT}/components.json'))
PY
export FIXTURE_POLICY_DEFINITIONS="${TMP_DIR}/policy-definitions.sh"
cat > "${TMP_DIR}/policy-exercise.sh" <<'SH_POLICY'
set -euo pipefail
source "${FIXTURE_SOURCE}"
source "${FIXTURE_POLICY_DEFINITIONS}"
mkdir -p "${FIXTURE_CASE_ROOT}"
cd "${FIXTURE_CASE_ROOT}"
VERIFY_CURRENT_SCENARIO_DIR=fixture
verification_prepare_remote_local_tree() { VERIFY_REMOTE_LOCAL_TREE_DIR="${FIXTURE_CASE_ROOT}/tree"; mkdir -p "${VERIFY_REMOTE_LOCAL_TREE_DIR}"; }
verification_cleanup_remote_local_tree() { rm -rf -- "${VERIFY_REMOTE_LOCAL_TREE_DIR}"; }
verification_artifact_path() { mkdir -p "${FIXTURE_CASE_ROOT}/artifacts/$(dirname "$1")"; printf '%s/%s\n' "${FIXTURE_CASE_ROOT}/artifacts" "$1"; }
verification_write_artifact() { local path=$1; shift; printf '%s\n' "$@" > "$(verification_artifact_path "${path}")"; }
verification_capture_command() { local path=$1; shift; "$@" > "$(verification_artifact_path "${path}")" 2>&1; }
verification_capture_best_effort_command() { verification_capture_command "$@" || return 0; }
verification_assert_redirect_policy_removed() { printf 'assert-owned-policy\n' >> "${FIXTURE_CASE_ROOT}/network.log"; }
iptables() { return 0; }
iptables-save() { printf 'mock iptables\n'; }
sing-box() { return 0; }
ip() {
  printf '%s\n' "$*" >> "${FIXTURE_CASE_ROOT}/network.log"
  case "$*" in
    'netns list')
      if [[ -f "${FIXTURE_CASE_ROOT}/netns" ]]; then cat "${FIXTURE_CASE_ROOT}/netns"; fi ;;
    'link show dev '*) [[ -f "${FIXTURE_CASE_ROOT}/veth" ]] ;;
    'netns add '*)
      [[ "${FIXTURE_CASE_MODE}" != fail_netns ]] || return 38
      printf '%s\n' "$3" > "${FIXTURE_CASE_ROOT}/netns" ;;
    'link add '*)
      case "${FIXTURE_CASE_MODE}" in fail_veth|tproxy_fail_veth) return 37 ;; esac
      printf '%s\n' "$3" > "${FIXTURE_CASE_ROOT}/veth" ;;
    'netns del '*) rm -- "${FIXTURE_CASE_ROOT}/netns" ;;
    'link del '*) rm -- "${FIXTURE_CASE_ROOT}/veth" ;;
    'addr add '*) [[ "${FIXTURE_CASE_MODE}" != fail_address ]] || return 39 ;;
    'link set '*|'netns exec '*|'rule show') return 0 ;;
    *) printf 'unexpected mock ip invocation\n' >&2; return 97 ;;
  esac
}
python3() {
  printf '%s\n' "$4" > "${FIXTURE_CASE_ROOT}/expected-marker"
  exec sleep 60
}
curl() {
  local output=''
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then output=$2; shift; fi
    shift
  done
  [[ -s "${FIXTURE_CASE_ROOT}/expected-marker" ]] || return 1
  cp "${FIXTURE_CASE_ROOT}/expected-marker" "${output}"
}
verification_case_context_start none
printf '%s\n' '{"revision":0,"components":[]}' > "${FIXTURE_CASE_ROOT}/components.json"
case "${FIXTURE_CASE_MODE}" in
  collision_veth) printf 'existing-veth\n' > "${FIXTURE_CASE_ROOT}/veth" ;;
  collision_netns) printf 'sbv-rpc\n' > "${FIXTURE_CASE_ROOT}/netns" ;;
esac
if [[ "${FIXTURE_CASE_MODE}" == tproxy_fail_veth ]]; then
  verification_execute_tproxy_probe /unused-test-config 1095 managed 1
else
  verification_prepare_redirect_policy_fixture VERIFY_REDIRECT_MARKER_PID
  printf '%s\n' "${VERIFY_REDIRECT_MARKER_PID}" > "${FIXTURE_CASE_ROOT}/marker.pid"
fi
SH_POLICY

for mode in fail_netns fail_veth fail_address collision_veth collision_netns success tproxy_fail_veth; do
  case_root="${TMP_DIR}/policy-${mode}"
  status=0
  FIXTURE_CASE_ROOT="${case_root}" FIXTURE_CASE_MODE="${mode}" \
    bash "${TMP_DIR}/policy-exercise.sh" > "${TMP_DIR}/${mode}.stdout" 2> "${TMP_DIR}/${mode}.stderr" || status=$?
  case "${mode}" in
    fail_netns) [[ ${status} == 38 ]] ;;
    fail_veth|tproxy_fail_veth) [[ ${status} == 37 ]] ;;
    fail_address) [[ ${status} == 39 ]] ;;
    collision_*) [[ ${status} == 1 ]] ;;
    success) [[ ${status} == 0 ]] ;;
  esac
  if [[ "${mode}" == collision_veth ]]; then
    grep -Fqx existing-veth "${case_root}/veth"
  elif [[ "${mode}" == collision_netns ]]; then
    grep -Fqx sbv-rpc "${case_root}/netns"
  else
    [[ ! -e "${case_root}/netns" && ! -e "${case_root}/veth" ]]
  fi
  if [[ "${mode}" == collision_* || "${mode}" == fail_netns ]]; then
    if grep -Eq '^(netns del|link del|assert-owned-policy)' "${case_root}/network.log"; then
      printf 'cleanup touched a resource it did not create\n' >&2
      exit 1
    fi
  fi
  if [[ "${mode}" == fail_veth ]]; then grep -Fqx 'netns del sbv-rpc' "${case_root}/network.log"; fi
  if [[ "${mode}" == tproxy_fail_veth ]]; then
    grep -Eq '^netns del sbvtns-[0-9]+$' "${case_root}/network.log"
    grep -Fqx RESULT=failure "${case_root}/artifacts/fixture/transparent/tproxy/result.env"
  fi
  if [[ "${mode}" == success ]]; then
    grep -Fqx 'link del sbv-rph0' "${case_root}/network.log"
    grep -Fqx 'netns del sbv-rpc' "${case_root}/network.log"
    if kill -0 "$(cat "${case_root}/marker.pid")" 2>/dev/null; then exit 1; fi
  fi
  grep -Fqx PROCESS_CLEANUP=success "${case_root}/artifacts/fixture/cleanup.env"
done

cat > "${TMP_DIR}/registry-exercise.sh" <<'SH_REGISTRY'
set -euo pipefail
source "${FIXTURE_SOURCE}"
source "${FIXTURE_POLICY_DEFINITIONS}"
mkdir -p "${FIXTURE_CASE_ROOT}"
VERIFY_CURRENT_SCENARIO_DIR=registry
verification_artifact_path() { mkdir -p "${FIXTURE_CASE_ROOT}/artifacts/$(dirname "$1")"; printf '%s/%s\n' "${FIXTURE_CASE_ROOT}/artifacts" "$1"; }
verification_write_artifact() { local path=$1; shift; printf '%s\n' "$@" > "$(verification_artifact_path "${path}")"; }
verification_cleanup_remote_local_tree() { return 0; }
verification_cleanup_tproxy_probe_fixture() { return 0; }
VERIFY_REMOTE_INSTALL_SCRIPT="${FIXTURE_CASE_ROOT}/delete.sh"
cat > "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'SH_DELETE'
printf '%s\n' "$*" > "${FIXTURE_CASE_ROOT}/delete.called"
printf '%s\n' '{"ok":true}'
SH_DELETE
case "${FIXTURE_CASE_MODE}" in
  empty) printf '%s\n' '{"revision":7,"components":[]}' > "${FIXTURE_CASE_ROOT}/components.json" ;;
  target) printf '%s\n' '{"revision":7,"components":[{"id":"tproxy-inbound-verification","role":"inbound","type":"tproxy"}]}' > "${FIXTURE_CASE_ROOT}/components.json" ;;
  malformed|preserve_failure) printf '{broken-json' > "${FIXTURE_CASE_ROOT}/components.json" ;;
  wrong_shape) printf '%s\n' '{"revision":7,"components":{}}' > "${FIXTURE_CASE_ROOT}/components.json" ;;
  wrong_revision) printf '%s\n' '{"revision":"7","components":[]}' > "${FIXTURE_CASE_ROOT}/components.json" ;;
esac
if [[ "${FIXTURE_CASE_MODE}" == preserve_failure ]]; then
  printf '{}\n' > "$(verification_artifact_path registry/transparent/tproxy/fixture.json)"
  verification_case_context_cleanup 17
fi
verification_case_cleanup_tproxy_component
SH_REGISTRY
for mode in empty target malformed wrong_shape wrong_revision preserve_failure; do
  case_root="${TMP_DIR}/registry-${mode}"
  status=0
  FIXTURE_CASE_ROOT="${case_root}" FIXTURE_CASE_MODE="${mode}" \
    bash "${TMP_DIR}/registry-exercise.sh" > "${TMP_DIR}/registry-${mode}.stdout" 2> "${TMP_DIR}/registry-${mode}.stderr" || status=$?
  case "${mode}" in
    empty|target) [[ ${status} == 0 ]] ;;
    malformed|wrong_shape|wrong_revision) [[ ${status} == 1 ]] ;;
    preserve_failure) [[ ${status} == 17 ]] ;;
  esac
  if [[ "${mode}" == target ]]; then
    grep -Fqx 'agent component delete --json --yes --expected-revision 7 --id tproxy-inbound-verification' "${case_root}/delete.called"
  else
    [[ ! -e "${case_root}/delete.called" ]]
  fi
done
printf 'Redirect ownership/partial failure and TProxy failure/registry cleanup passed\n'
