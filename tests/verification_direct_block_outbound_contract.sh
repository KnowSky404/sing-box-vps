#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# Direct must use route destination overrides for TCP and UDP, while block
# must prove an expected rejected request and remove its component-owned route
# via CAS.
grep -Fq 'direct-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=direct_route_override_loopback' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=direct_udp_route_override_loopback' "${SCENARIO_FILE}"
grep -Fq 'block-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=block_reject_loopback' "${SCENARIO_FILE}"
grep -Fq 'block-outbound-curl-rejected' "${SCENARIO_FILE}"
grep -Fq 'direct-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq 'direct-outbound-udp.result.env' "${SCENARIO_FILE}"
grep -Fq 'block-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 19 --file "${direct_outbound_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 20 --id direct-outbound-verification' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 21 --file "${block_outbound_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 22 --id block-outbound-verification' \
  "${SCENARIO_FILE}"
grep -Fq 'override_address:"127.0.0.1"' "${SCENARIO_FILE}"
grep -Fq 'override_port:$marker_port' "${SCENARIO_FILE}"
grep -Fq 'network:["udp"],port:$target_port' "${SCENARIO_FILE}"
grep -Fq 'config:{}}' "${SCENARIO_FILE}"

if grep -Fq 'POLICY_OWNERSHIP=managed' "${SCENARIO_FILE}"; then
  printf 'direct/block outbound verification must not claim managed host policy ownership\n' >&2
  exit 1
fi

printf 'verification direct/block outbound contract checks passed\n'
