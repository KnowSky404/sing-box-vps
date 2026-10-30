#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

ATTEMPTS_FILE="${TMP_DIR}/public-ip-attempts"
CHECK_COUNT=0
FAILURE_COUNT=0

# Each endpoint has independent transport, HTTP and body fixtures. Never contact
# public IP providers, even when a regression changes curl's option ordering.
curl() {
  local family="" endpoint="" argument fail_http=n status http_status
  for argument in "$@"; do
    case "${argument}" in
      -4) family=4 ;;
      -6) family=6 ;;
      --fail|--fail-with-body) fail_http=y ;;
      https://api.ip.sb/ip) endpoint=first ;;
      https://ifconfig.me|https://ifconfig.me/ip) endpoint=second ;;
      -*)
        if [[ "${argument}" != --* && "${argument}" == *f* ]]; then
          fail_http=y
        fi
        ;;
    esac
  done
  [[ -n "${family}" && -n "${endpoint}" ]] || return 98
  printf '%s:%s\n' "${family}" "${endpoint}" >> "${ATTEMPTS_FILE}"
  status=$(cat "${TMP_DIR}/${family}-${endpoint}.status")
  http_status=$(cat "${TMP_DIR}/${family}-${endpoint}.http")
  if [[ "${fail_http}" == y && "${http_status}" -ge 400 ]]; then
    return 22
  fi
  cat "${TMP_DIR}/${family}-${endpoint}.body"
  return "${status}"
}

set_response() {
  local family=$1 endpoint=$2 body=$3 status=${4:-0} http_status=${5:-200}
  printf '%s' "${body}" > "${TMP_DIR}/${family}-${endpoint}.body"
  printf '%s' "${status}" > "${TMP_DIR}/${family}-${endpoint}.status"
  printf '%s' "${http_status}" > "${TMP_DIR}/${family}-${endpoint}.http"
}

reset_case() {
  local family endpoint
  : > "${ATTEMPTS_FILE}"
  for family in 4 6; do
    for endpoint in first second; do
      set_response "${family}" "${endpoint}" '' 7
    done
  done
}

assert_detection() {
  local label=$1 detector=$2 expected_address=$3 expected_calls=$4 expected_status=${5:-success}
  local address status=0 calls
  address=$("${detector}") || status=$?
  calls=$(paste -sd ',' "${ATTEMPTS_FILE}")
  CHECK_COUNT=$((CHECK_COUNT + 1))
  if [[ "${address}" != "${expected_address}" || "${calls}" != "${expected_calls}" ]] ||
    [[ "${expected_status}" == success && "${status}" -ne 0 ]] ||
    [[ "${expected_status}" == failure && "${status}" -eq 0 ]]; then
    printf 'FAIL %s: address=%q status=%s calls=%s\n' \
      "${label}" "${address}" "${status}" "${calls}" >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
  fi
}

reset_case
set_response 4 first '203.0.113.10'
set_response 6 first '2001:db8::10'
assert_detection 'IPv4 preferred when both families work' get_public_ip '203.0.113.10' '4:first'

reset_case
set_response 4 first 'incomplete-response' 7
set_response 4 second '203.0.113.11'
assert_detection 'discard failed transport body before second endpoint' get_public_ipv4 '203.0.113.11' '4:first,4:second'

reset_case
set_response 6 first '2001:db8::10'
assert_detection 'IPv4 failure falls back to IPv6' get_public_ip '2001:db8::10' '4:first,4:second,6:first'

reset_case
set_response 4 first '<html>service unavailable</html>'
set_response 4 second '203.0.113.12'
assert_detection 'HTML response falls back to second endpoint' get_public_ipv4 '203.0.113.12' '4:first,4:second'

reset_case
set_response 4 first '203.0.113.99' 0 503
set_response 4 second '203.0.113.13'
assert_detection 'HTTP errors do not supply addresses' get_public_ipv4 '203.0.113.13' '4:first,4:second'

reset_case
set_response 4 first $' \t203.0.113.14\r\n'
assert_detection 'trim IPv4 response whitespace' get_public_ipv4 '203.0.113.14' '4:first'

reset_case
set_response 6 first $'\n 2001:db8::14 \r\n'
assert_detection 'trim IPv6 response whitespace' get_public_ipv6 '2001:db8::14' '6:first'

reset_case
assert_detection 'both families unavailable fail with no address' get_public_ip '' '4:first,4:second,6:first,6:second' failure

for invalid_address in 'example.com' '2001:db8::15' '999.1.1.1' '203.0.113' '203.0.113.1:443' \
  $'203.0.113.1\n203.0.113.2' '0.0.0.0'; do
  reset_case
  set_response 4 first "${invalid_address}"
  set_response 4 second '203.0.113.15'
  assert_detection "invalid IPv4 response ${invalid_address}" get_public_ipv4 '203.0.113.15' '4:first,4:second'
done

for invalid_address in 'example.com' '203.0.113.16' '2001:db8:::16' '2001:db8::gg' '[2001:db8::16]' \
  '2001:db8::16%eth0' $'2001:db8::16\n2001:db8::17' '::' '0:0:0:0:0:0:0:0' \
  '0000:0000:0000:0000:0000:0000:0000:0000' '0::0' '::0' '0:0:0:0:0:0:0::' \
  '::ffff:0.0.0.0' '0:0:0:0:0:ffff:0:0'; do
  reset_case
  set_response 6 first "${invalid_address}"
  set_response 6 second '2001:db8::16'
  assert_detection "invalid IPv6 response ${invalid_address}" get_public_ipv6 '2001:db8::16' '6:first,6:second'
done

reset_case
set_response 4 first 'not-an-ip'
set_response 4 second 'still-not-an-ip'
assert_detection 'invalid IPv4 providers fail without output' get_public_ipv4 '' '4:first,4:second' failure

reset_case
set_response 6 first 'not-an-ip'
set_response 6 second 'still-not-an-ip'
assert_detection 'invalid IPv6 providers fail without output' get_public_ipv6 '' '6:first,6:second' failure

reset_case
set_response 4 first '0.0.0.0'
set_response 4 second '0.0.0.0'
assert_detection 'IPv4 wildcard providers fail without output' get_public_ipv4 '' '4:first,4:second' failure

reset_case
set_response 6 first '::'
set_response 6 second '::ffff:0.0.0.0'
assert_detection 'IPv6 wildcard providers fail without output' get_public_ipv6 '' '6:first,6:second' failure

reset_case
set_response 4 first '0.0.0.0'
set_response 4 second '0.0.0.0'
set_response 6 first '0::0'
set_response 6 second '0:0:0:0:0:ffff:0:0'
assert_detection 'all wildcard providers fail without selecting any family' get_public_ip '' '4:first,4:second,6:first,6:second' failure

if [[ "${FAILURE_COUNT}" -gt 0 ]]; then
  printf 'Public IP detection checks: %s/%s failed\n' "${FAILURE_COUNT}" "${CHECK_COUNT}" >&2
  exit 1
fi
printf 'Public IP detection checks passed (%s cases)\n' "${CHECK_COUNT}"
