#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

CHECK_COUNT=0
FAILURE_COUNT=0
MOCK_IPV4_ADDRESS='2: eth0    inet 203.0.113.10/24 scope global eth0'
MOCK_IPV6_ADDRESS='2: eth0    inet6 2001:db8::10/64 scope global'
MOCK_IPV4_STATUS=0
MOCK_IPV6_STATUS=0
MOCK_IPV4_BURST=n
MOCK_IPV6_BURST=n
MOCK_BURST_CHUNK="${MOCK_IPV4_ADDRESS}"$'\n'
# Multiple writes larger than a pipe buffer force an early-exiting reader to
# interrupt the producer, without relying on scheduling, sleeps or a real host.
for ((CHUNK_INDEX=0; CHUNK_INDEX<10; CHUNK_INDEX++)); do
  MOCK_BURST_CHUNK+="${MOCK_BURST_CHUNK}"
done

ip() {
  local address status burst chunk
  case "$*" in
    '-o -4 addr show scope global')
      address=${MOCK_IPV4_ADDRESS}; status=${MOCK_IPV4_STATUS}; burst=${MOCK_IPV4_BURST}
      ;;
    '-o -6 addr show scope global')
      address=${MOCK_IPV6_ADDRESS}; status=${MOCK_IPV6_STATUS}; burst=${MOCK_IPV6_BURST}
      ;;
    *) printf 'unexpected ip invocation in host-stack test\n' >&2; return 98 ;;
  esac
  if [[ -n "${address}" ]]; then
    printf '%s\n' "${address}" || return $?
    if [[ "${burst}" == y ]]; then
      for ((chunk=0; chunk<16; chunk++)); do
        printf '%s' "${MOCK_BURST_CHUNK}" || return $?
      done
    fi
  fi
  return "${status}"
}

curl() { printf 'unexpected network request in host-stack test\n' >&2; return 99; }
get_public_ipv4() { printf '203.0.113.10'; }
get_public_ipv6() { printf '2001:db8::10'; }

assert_equal() {
  local label=$1 actual=$2 expected=$3
  CHECK_COUNT=$((CHECK_COUNT + 1))
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL %s: expected %q, got %q\n' "${label}" "${expected}" "${actual}" >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
  fi
}

MOCK_IPV4_LINE=${MOCK_IPV4_ADDRESS}
MOCK_IPV6_LINE=${MOCK_IPV6_ADDRESS}
MOCK_IPV4_ADDRESS=''
MOCK_IPV6_ADDRESS=''
assert_equal 'no global addresses retain IPv4 fallback' "$(detect_host_ip_stack)" ipv4
MOCK_IPV4_ADDRESS=${MOCK_IPV4_LINE}
assert_equal 'IPv4-only host' "$(detect_host_ip_stack)" ipv4
MOCK_IPV4_ADDRESS=''
MOCK_IPV6_ADDRESS=${MOCK_IPV6_LINE}
assert_equal 'IPv6-only host' "$(detect_host_ip_stack)" ipv6
MOCK_IPV4_ADDRESS=${MOCK_IPV4_LINE}
assert_equal 'dual-stack host' "$(detect_host_ip_stack)" dual

MOCK_IPV4_BURST=y
assert_equal 'IPv4 producer survives an early matching line' "$(detect_host_ip_stack)" dual
MOCK_IPV4_BURST=n
MOCK_IPV6_BURST=y
assert_equal 'IPv6 producer survives an early matching line' "$(detect_host_ip_stack)" dual
MOCK_IPV4_BURST=y
assert_equal 'both producers finish their complete output' "$(detect_host_ip_stack)" dual

# Nonempty partial output must not hide a failed ip command. A fix that ignores
# all producer statuses would falsely classify these cases as dual-stack.
MOCK_IPV4_BURST=n
MOCK_IPV6_BURST=n
MOCK_IPV4_STATUS=7
assert_equal 'failed IPv4 producer is not evidence of IPv4' "$(detect_host_ip_stack)" ipv6
MOCK_IPV4_STATUS=0
MOCK_IPV6_STATUS=7
assert_equal 'failed IPv6 producer is not evidence of IPv6' "$(detect_host_ip_stack)" ipv4
MOCK_IPV6_STATUS=0
MOCK_IPV4_BURST=y
MOCK_IPV6_BURST=n

# Exercise the real saved-state and candidate-selection callers. This is the
# production failure shape: a bursty IPv4 producer and a short IPv6 response.
SB_PROTOCOL=vless+reality
for MODE in ipv4_only dual_stack; do
  SB_INBOUND_STACK_MODE=${MODE}
  SB_OUTBOUND_STACK_MODE=prefer_ipv4
  save_stack_mode_state
  SB_INBOUND_STACK_MODE=''
  SB_OUTBOUND_STACK_MODE=''
  ensure_stack_mode_state_loaded
  assert_equal "saved ${MODE} survives stack initialization" "${SB_INBOUND_STACK_MODE}" "${MODE}"
  SB_INBOUND_STACK_MODE=${MODE}
  SB_OUTBOUND_STACK_MODE=prefer_ipv4
  ensure_stack_mode_state_loaded
  assert_equal "current ${MODE} survives stack validation" "${SB_INBOUND_STACK_MODE}" "${MODE}"
  if [[ "${MODE}" == dual_stack ]]; then
    EXPECTED=$'IPv4|203.0.113.10\nIPv6|2001:db8::10'
  else
    EXPECTED='IPv4|203.0.113.10'
  fi
  assert_equal "REALITY ${MODE} retains all allowed SubMan candidates" \
    "$(list_subman_addresses_for_current_protocol)" "${EXPECTED}"
done

if (( FAILURE_COUNT > 0 )); then
  printf 'host IP stack detection: %s/%s checks failed\n' "${FAILURE_COUNT}" "${CHECK_COUNT}" >&2
  exit 1
fi
printf 'host IP stack detection: %s checks passed\n' "${CHECK_COUNT}"
