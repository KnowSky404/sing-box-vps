#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# Keep the remote proof fail-closed and explicit: it must create a typed SOCKS
# outbound, authenticate to the disposable upstream, reach only the marker,
# and delete the component through the following CAS revision.
grep -Fq 'socks-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'socks-upstream-user' "${SCENARIO_FILE}"
grep -Fq 'socks-upstream-pass' "${SCENARIO_FILE}"
grep -Fq 'AUTHENTICATED' "${SCENARIO_FILE}"
grep -Fq 'DESTINATION=${socks_outbound_target_domain}:${socks_outbound_marker_port}' "${SCENARIO_FILE}"
grep -Fq 'socks5_connect_loopback' "${SCENARIO_FILE}"
grep -Fq 'socks-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 9 --file "${socks_outbound_record}"' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 10 --id socks-outbound-verification' "${SCENARIO_FILE}"

# The same typed outbound must also prove native UDP through a real
# authenticated SOCKS5 UDP ASSOCIATE and remove its route/component by CAS.
grep -Fq 'socks-outbound-udp-verification' "${SCENARIO_FILE}"
grep -Fq 'socks-udp-upstream-user' "${SCENARIO_FILE}"
grep -Fq 'socks-udp-upstream-pass' "${SCENARIO_FILE}"
grep -Fq 'socks5_native_udp_loopback' "${SCENARIO_FILE}"
grep -Fq 'socks-outbound-udp.result.env' "${SCENARIO_FILE}"
grep -Fq 'socks-outbound-udp-upstream.request.txt' "${SCENARIO_FILE}"
grep -Fq 'UDP_ASSOCIATE' "${SCENARIO_FILE}"
grep -Fq 'network:["udp"]' "${SCENARIO_FILE}"
grep -Fq 'network == ["udp"]' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 31 --file "${socks_outbound_udp_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 32 --id socks-outbound-udp-verification' \
  "${SCENARIO_FILE}"
grep -Fq 'inbound:["socks-in"],network:["udp"],port:$marker_port' \
  "${SCENARIO_FILE}"

# The marker and upstream proxy are disposable loopback fixtures; no host
# firewall ownership or public/production reachability may be claimed.
if grep -Fq 'POLICY_OWNERSHIP=managed' "${SCENARIO_FILE}"; then
  printf 'SOCKS verification must not claim managed host policy ownership\n' >&2
  exit 1
fi

printf 'verification SOCKS outbound contract checks passed\n'
