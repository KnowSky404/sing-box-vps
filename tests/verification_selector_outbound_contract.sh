#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# A selector proof must resolve a real member, route a marker and delete the
# group through CAS; parsing a group record alone is not runtime evidence.
grep -Fq 'selector-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'outbounds:["direct"]' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=selector_direct_loopback' "${SCENARIO_FILE}"
grep -Fq 'selector-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 13 --file "${selector_record}"' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 14 --id selector-outbound-verification' "${SCENARIO_FILE}"

if grep -Fq 'POLICY_OWNERSHIP=managed' "${SCENARIO_FILE}"; then
  printf 'selector verification must not claim managed host policy ownership\n' >&2
  exit 1
fi

printf 'verification selector outbound contract checks passed\n'
