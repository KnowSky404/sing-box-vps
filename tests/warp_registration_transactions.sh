#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
mkdir -p "${SB_PROJECT_DIR}"
PENDING="${SB_PROJECT_DIR}.warp-registration.pending.json"
RESPONSE='{"id":"test-id","token":"test-token","config":{"client_id":"hCaJ","interface":{"addresses":{"v4":"172.16.0.2","v6":"2606:4700:110:8cde::1"}}}}'
run_singbox_generate_command() {
  printf '%s\n' 'PrivateKey: 8DcUSmPINFuK1xkA1TncAJh46Ra8Mq8o42XL3b+rT2s=' 'PublicKey: j/gT24P0qv0p5RFqYVehc7Y88S5fDhcJ8E3HGqpCPVg='
}
curl() {
  local output=''
  printf 'POST\n' >> "${TMP_DIR}/requests"
  while [[ $# -gt 0 ]]; do
    [[ $1 != --retry && $1 != --retry-all-errors ]]
    case $1 in -o) output=$2; shift 2 ;; *) shift ;; esac
  done
  [[ ${TRANSPORT:-0} == 0 ]] || return "${TRANSPORT}"
  printf '%s' "${RESPONSE}" > "${output}"
  printf '%s' "${HTTP_STATUS:-200}"
}
reset_case() { rm -f "${SB_WARP_KEY_FILE}" "${PENDING}" "${TMP_DIR}/requests"; TRANSPORT=0; HTTP_STATUS=200; }
reset_case
TRANSPORT=28
if register_warp > "${TMP_DIR}/timeout.log" 2>&1; then exit 1; fi
[[ -f ${PENDING} && ! -f ${SB_WARP_KEY_FILE} ]]
if register_warp > "${TMP_DIR}/pending.log" 2>&1; then exit 1; fi
[[ $(wc -l < "${TMP_DIR}/requests") == 1 ]]
grep -Fq remote_outcome_unknown "${TMP_DIR}/pending.log"
for transport_failure in 6 7; do
  reset_case
  TRANSPORT=${transport_failure}
  if register_warp > "${TMP_DIR}/connection.log" 2>&1; then exit 1; fi
  [[ ! -f ${PENDING} && ! -f ${SB_WARP_KEY_FILE} ]]
done
reset_case
HTTP_STATUS=400
if register_warp > "${TMP_DIR}/http.log" 2>&1; then exit 1; fi
[[ ! -f ${PENDING} && ! -f ${SB_WARP_KEY_FILE} ]]
valid_response=${RESPONSE}
for RESPONSE in '{}' '{' '{"id":"id-only"}' "$(jq '.config.client_id="invalid"' <<< "${valid_response}")" "$(jq '.config.interface.addresses.v4="::1"' <<< "${valid_response}")"; do
  reset_case
  if register_warp > "${TMP_DIR}/invalid.log" 2>&1; then exit 1; fi
  [[ -f ${PENDING} && ! -f ${SB_WARP_KEY_FILE} ]]
  grep -Fq invalid_response "${TMP_DIR}/invalid.log"
done
RESPONSE=${valid_response}
reset_case
writer=$(declare -f write_warp_credentials_atomic)
write_warp_credentials_atomic() { return 19; }
save_status=0
register_warp > "${TMP_DIR}/save-failed.log" 2>&1 || save_status=$?
[[ ${save_status} == 19 ]]
jq -e '.phase=="received"' "${PENDING}" >/dev/null
[[ ! -f ${SB_WARP_KEY_FILE} ]]
eval "${writer}"
register_warp > "${TMP_DIR}/recovered.log" 2>&1
[[ $(wc -l < "${TMP_DIR}/requests") == 1 && ! -e ${PENDING} ]]
[[ $(stat -c %a "${SB_WARP_KEY_FILE}") == 600 ]]
# Remote strings remain inert data when the private shell state is loaded.
reset_case
inert_token='$(touch '"${TMP_DIR}"'/injected)'
RESPONSE=$(jq --arg token "${inert_token}" '.token=$token' <<< "${valid_response}")
register_warp > "${TMP_DIR}/inert.log" 2>&1
source "${SB_WARP_KEY_FILE}"
[[ ${WARP_TOKEN} == "${inert_token}" && ! -e ${TMP_DIR}/injected ]]
! grep -Fq "${inert_token}" "${SBV_LOG_FILE}"
# Postcommit corruption must restore the previous credential bytes.
printf 'old-key\n' > "${SB_WARP_KEY_FILE}"
old_hash=$(sha256sum "${SB_WARP_KEY_FILE}")
if (
  mv() {
    command mv "$@" || return $?
    if [[ ${*: -1} == "${SB_WARP_KEY_FILE}" && $* == *'.warp.key.'* ]]; then
      printf 'corrupted\n' > "${SB_WARP_KEY_FILE}"
    fi
  }
  write_warp_credentials_atomic id token private public 172.16.0.2 ::1 hCaJ
) > "${TMP_DIR}/rollback.log" 2>&1; then exit 1; fi
[[ $(sha256sum "${SB_WARP_KEY_FILE}") == "${old_hash}" ]]
grep -Fq rolled_back=true "${TMP_DIR}/rollback.log"
if (
  mv() {
    command mv "$@" || return $?
    if [[ ${*: -1} == "${SB_WARP_KEY_FILE}" && $* == *'.warp.key.'* ]]; then
      kill -TERM "${BASHPID}"
    fi
  }
  write_warp_credentials_atomic id token private public 172.16.0.2 ::1 hCaJ
) > "${TMP_DIR}/signal-rollback.log" 2>&1; then exit 1; fi
[[ $(sha256sum "${SB_WARP_KEY_FILE}") == "${old_hash}" ]]
grep -Fq rolled_back=true "${TMP_DIR}/signal-rollback.log"
printf 'WARP registration unknown-outcome, recovery, validation, quoting and rollback passed\n'
