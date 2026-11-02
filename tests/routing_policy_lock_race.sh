#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"

lock_test_fd_count() {
  local entry target count=0
  for entry in "/proc/${BASHPID:-$$}/fd/"*; do
    target=$(command readlink "${entry}") || continue
    [[ "${target}" != "${SB_PROJECT_DIR}.management.flock" ]] || count=$((count+1))
  done
  printf '%s\n' "${count}"
}

lock_test_pause() {
  local message
  printf 'checked\n' >&"${LOCK_TEST_REQUEST_FD}"
  IFS= read -r -t 10 message <&"${LOCK_TEST_GO_FD}"
  [[ "${message}" == published ]]
}

lock_test_worker() {
  local requested=$1 exception=$2 pause_point=$3 ownership=$4 expected_mode=$5 outcome=$6
  local status=0 original_fd=${SB_MANAGEMENT_LOCK_FD:-} count probe
  if [[ "${ownership}" == new ]]; then
    unset SB_MANAGEMENT_LOCK_FD
    SB_MANAGEMENT_LOCK_MODE=preserved-marker
  fi
  # Synchronize a real kernel call instead of substituting a successful lock.
  flock() {
    [[ "${pause_point}" != before-flock ]] || lock_test_pause || return 1
    command flock "$@" || return $?
    [[ "${pause_point}" != after-flock ]] || lock_test_pause || return 1
  }
  readlink() {
    if [[ "${pause_point}" == readlink && "$1" == /proc/*/fd/"${SB_MANAGEMENT_LOCK_FD:-invalid}" ]]; then
      lock_test_pause || return 1
    fi
    command readlink "$@"
  }
  if acquire_managed_write_lock "${requested}" "${exception}"; then
    printf 'mutation\n' > "${LOCK_TEST_CASE_DIR}/mutation"
  else
    status=$?
  fi
  if [[ "${outcome}" == deny ]]; then
    [[ "${status}" != 0 && ! -e "${LOCK_TEST_CASE_DIR}/mutation" ]]
  else
    [[ "${status}" == 0 && -f "${LOCK_TEST_CASE_DIR}/mutation" ]]
  fi
  count=$(lock_test_fd_count)
  if [[ "${ownership}:${outcome}" == new:deny ]]; then
    [[ "${count}" == 0 && -z "${SB_MANAGEMENT_LOCK_FD+x}" &&
       "${SB_MANAGEMENT_LOCK_MODE}" == preserved-marker ]]
    return 0
  fi
  [[ "${count}" == 1 && "${SB_MANAGEMENT_LOCK_MODE}" == "${expected_mode}" ]]
  if [[ "${ownership}" == inherited ]]; then
    [[ "${SB_MANAGEMENT_LOCK_FD}" == "${original_fd}" && -e "/proc/${BASHPID}/fd/${original_fd}" ]]
  fi
  # The recorded mode must describe the actual retained open-file lock.
  exec {probe}>"${SB_PROJECT_DIR}.management.flock"
  if [[ "${expected_mode}" == exclusive ]]; then
    if command flock -n -s "${probe}"; then printf 'exclusive lock was lost\n' >&2; return 1; fi
  else
    command flock -n -s "${probe}"
    command flock -u "${probe}"
    if command flock -n -x "${probe}"; then printf 'shared lock was lost\n' >&2; return 1; fi
  fi
  exec {probe}>&-
  if [[ "${ownership}" == new ]]; then exec {SB_MANAGEMENT_LOCK_FD}>&-; fi
}

lock_test_channels() {
  LOCK_TEST_CASE_DIR="${TMP_DIR}/$1"
  mkdir -m 700 "${LOCK_TEST_CASE_DIR}"
  mkfifo "${LOCK_TEST_CASE_DIR}/held" "${LOCK_TEST_CASE_DIR}/request" "${LOCK_TEST_CASE_DIR}/go"
  exec {LOCK_TEST_HELD_FD}<>"${LOCK_TEST_CASE_DIR}/held"
  exec {LOCK_TEST_REQUEST_FD}<>"${LOCK_TEST_CASE_DIR}/request"
  exec {LOCK_TEST_GO_FD}<>"${LOCK_TEST_CASE_DIR}/go"
  export LOCK_TEST_CASE_DIR LOCK_TEST_REQUEST_FD LOCK_TEST_GO_FD
}

lock_test_child() {
  LOCK_TEST_TESTABLE="${TESTABLE_INSTALL}" LOCK_TEST_SOURCE="${REPO_ROOT}/src/install/32-instance-transactions.sh" \
    LOCK_TEST_LIBRARY="${TMP_DIR}/worker-functions.sh" \
    bash -s -- "$@" <<'WORKER'
set -euo pipefail
source "${LOCK_TEST_TESTABLE}"
source "${LOCK_TEST_SOURCE}"
source "${LOCK_TEST_LIBRARY}"
lock_test_worker "$@"
WORKER
}

lock_test_new_race() (
  trap - EXIT ERR
  local requested=$1 exception=${2:-} outcome=${3:-deny} actor message status=0
  unset SB_MANAGEMENT_LOCK_FD SB_MANAGEMENT_LOCK_MODE
  rm -rf -- "${SB_ROUTING_TRANSACTION_DIR}"
  lock_test_channels "new-${requested}-${outcome}"
  (
    trap - EXIT ERR
    exec {actor}>"${SB_PROJECT_DIR}.management.flock"
    command flock -x "${actor}"
    printf 'held\n' >&"${LOCK_TEST_HELD_FD}"
    IFS= read -r -t 10 message <&"${LOCK_TEST_REQUEST_FD}"
    [[ "${message}" == checked ]]
    mkdir -m 700 "${SB_ROUTING_TRANSACTION_DIR}"
    exec {actor}>&-
    printf 'published\n' >&"${LOCK_TEST_GO_FD}"
  ) &
  actor=$!
  IFS= read -r -t 10 message <&"${LOCK_TEST_HELD_FD}"
  [[ "${message}" == held ]]
  lock_test_child "${requested}" "${exception}" before-flock new "${requested}" "${outcome}" \
    > "${LOCK_TEST_CASE_DIR}/worker.log" 2>&1 || status=$?
  wait "${actor}"
  [[ "${status}" == 0 ]] || { cat "${LOCK_TEST_CASE_DIR}/worker.log" >&2; return 1; }
  [[ "${outcome}" != deny ]] || grep -Fq '存在未完成的规则事务' "${LOCK_TEST_CASE_DIR}/worker.log"
)

lock_test_inherited_race() (
  trap - EXIT ERR
  local initial=$1 requested=$2 pause=$3 exception=${4:-} outcome=${5:-deny} actor message status=0 expected
  unset SB_MANAGEMENT_LOCK_FD SB_MANAGEMENT_LOCK_MODE
  rm -rf -- "${SB_ROUTING_TRANSACTION_DIR}"
  acquire_managed_write_lock "${initial}"
  export SB_MANAGEMENT_LOCK_FD SB_MANAGEMENT_LOCK_MODE
  lock_test_channels "inherited-${initial}-${requested}-${outcome}"
  (
    trap - EXIT ERR
    IFS= read -r -t 10 message <&"${LOCK_TEST_REQUEST_FD}"
    [[ "${message}" == checked ]]
    mkdir -m 700 "${SB_ROUTING_TRANSACTION_DIR}"
    printf 'published\n' >&"${LOCK_TEST_GO_FD}"
  ) &
  actor=$!
  expected=${requested}
  [[ "${initial}:${requested}" != exclusive:shared ]] || expected=exclusive
  lock_test_child "${requested}" "${exception}" "${pause}" inherited "${expected}" "${outcome}" \
    > "${LOCK_TEST_CASE_DIR}/worker.log" 2>&1 || status=$?
  wait "${actor}"
  [[ "${status}" == 0 ]] || { cat "${LOCK_TEST_CASE_DIR}/worker.log" >&2; return 1; }
  [[ -e "/proc/${BASHPID}/fd/${SB_MANAGEMENT_LOCK_FD}" ]]
  exec {SB_MANAGEMENT_LOCK_FD}>&-
)

lock_test_contention_cleanup() (
  trap - EXIT ERR
  local actor message status=0 requested
  unset SB_MANAGEMENT_LOCK_FD SB_MANAGEMENT_LOCK_MODE
  rm -rf -- "${SB_ROUTING_TRANSACTION_DIR}"
  lock_test_channels contention
  (
    trap - EXIT ERR
    exec {actor}>"${SB_PROJECT_DIR}.management.flock"
    command flock -x "${actor}"
    printf 'held\n' >&"${LOCK_TEST_HELD_FD}"
    IFS= read -r -t 10 message <&"${LOCK_TEST_REQUEST_FD}"
    [[ "${message}" == release ]]
  ) &
  actor=$!
  IFS= read -r -t 10 message <&"${LOCK_TEST_HELD_FD}"
  [[ "${message}" == held ]]
  for requested in shared exclusive; do
    lock_test_child "${requested}" '' none new "${requested}" deny \
      > "${LOCK_TEST_CASE_DIR}/${requested}.log" 2>&1 || status=$?
  done
  printf 'release\n' >&"${LOCK_TEST_REQUEST_FD}"
  wait "${actor}"
  [[ "${status}" == 0 ]] || { cat "${LOCK_TEST_CASE_DIR}/"*.log >&2; return 1; }
)

setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
source "${REPO_ROOT}/src/install/32-instance-transactions.sh"
trap 'printf "routing lock race test failed at line %s\n" "${LINENO}" >&2' ERR
umask 077
declare -f lock_test_fd_count lock_test_pause lock_test_worker > "${TMP_DIR}/worker-functions.sh"

lock_test_new_race shared
lock_test_new_race exclusive
lock_test_new_race shared allow-rules-recovery allow
lock_test_new_race exclusive allow-rules-recovery allow
lock_test_inherited_race exclusive shared readlink
lock_test_inherited_race exclusive exclusive after-flock
lock_test_inherited_race shared shared after-flock
lock_test_inherited_race shared exclusive after-flock
lock_test_inherited_race exclusive shared readlink allow-rules-recovery allow
lock_test_inherited_race shared exclusive after-flock allow-rules-recovery allow
lock_test_contention_cleanup

# The fast precheck still rejects a dangling recovery journal without opening a
# descriptor. Only the exact internal recovery exception permits entry.
rm -rf -- "${SB_ROUTING_TRANSACTION_DIR}"
ln -s "${TMP_DIR}/absent-journal" "${SB_ROUTING_TRANSACTION_DIR}"
if acquire_managed_write_lock; then printf 'dangling recovery journal was ignored\n' >&2; exit 1; fi
[[ "$(lock_test_fd_count)" == 0 && -z "${SB_MANAGEMENT_LOCK_FD+x}" ]]
acquire_managed_write_lock exclusive allow-rules-recovery
[[ "${SB_MANAGEMENT_LOCK_MODE}" == exclusive ]]
exec {SB_MANAGEMENT_LOCK_FD}>&-
printf 'Real flock post-acquire barrier, inherited modes, recovery exception and descriptor cleanup passed\n'
