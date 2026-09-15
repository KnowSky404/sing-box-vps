#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# URLTest must retain its health URL and real member route, wait for a marker,
# and delete through CAS; a successful core check alone is insufficient.
grep -Fq 'urltest-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'urltest_probe_url' "${SCENARIO_FILE}"
grep -Fq 'interval:"1s"' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=urltest_direct_loopback' "${SCENARIO_FILE}"
grep -Fq 'HEALTHCHECK=loopback_http' "${SCENARIO_FILE}"
grep -Fq 'urltest-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 13 --file "${urltest_record}"' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 14 --id urltest-outbound-verification' "${SCENARIO_FILE}"

if grep -Fq 'POLICY_OWNERSHIP=managed' "${SCENARIO_FILE}"; then
  printf 'URLTest verification must not claim managed host policy ownership\n' >&2
  exit 1
fi

printf 'verification URLTest outbound contract checks passed\n'
