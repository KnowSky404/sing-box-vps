#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# The managed outbound must prove a real SS2022 path, constrain the route to
# the ingress that owns it, and remove both component-owned rules via CAS.
grep -Fq 'shadowsocks-outbound-verification' "${SCENARIO_FILE}"
grep -Fq '2022-blake3-aes-128-gcm' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=shadowsocks2022_connect_loopback' "${SCENARIO_FILE}"
grep -Fq 'AUTHENTICATION=ss2022_psk' "${SCENARIO_FILE}"
grep -Fq 'shadowsocks-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 15 --file "${shadowsocks_outbound_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 16 --id shadowsocks-outbound-verification' \
  "${SCENARIO_FILE}"
grep -Fq 'inbound:["socks-in"]' "${SCENARIO_FILE}"
grep -Fq 'inbound:["ss-in"]' "${SCENARIO_FILE}"

# The same managed family must also prove native UDP through an authenticated
# SOCKS5 UDP ASSOCIATE, with an independent component/revision sequence.
grep -Fq 'shadowsocks-outbound-udp-verification' "${SCENARIO_FILE}"
grep -Fq 'shadowsocks2022_udp_loopback' "${SCENARIO_FILE}"
grep -Fq 'shadowsocks-outbound-udp-response.txt' "${SCENARIO_FILE}"
grep -Fq 'shadowsocks-outbound-udp-journal.txt' "${SCENARIO_FILE}"
grep -Fq 'network:["udp"]' "${SCENARIO_FILE}"
grep -Fq 'network == ["udp"]' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 29 --file "${shadowsocks_outbound_udp_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 30 --id shadowsocks-outbound-udp-verification' \
  "${SCENARIO_FILE}"
grep -Fq 'network:["udp"],port:$marker_port' "${SCENARIO_FILE}"

if grep -Fq 'POLICY_OWNERSHIP=managed' "${SCENARIO_FILE}"; then
  printf 'Shadowsocks outbound verification must not claim managed host policy ownership\n' >&2
  exit 1
fi

printf 'verification Shadowsocks outbound contract checks passed\n'
