#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# ShadowTLS is a transport: require a real v3 server, an HTTP detour carrying
# the application stream, the loopback marker, and ordered CAS cleanup.
grep -Fq 'shadowtls-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'shadowtls-outbound-server' "${SCENARIO_FILE}"
grep -Fq 'shadowtls-outbound-inner' "${SCENARIO_FILE}"
grep -Fq 'shadowtls-outbound-http' "${SCENARIO_FILE}"
grep -Fq 'shadowtls_tcp_composite' "${SCENARIO_FILE}"
grep -Fq 'shadowtls_v3_loopback' "${SCENARIO_FILE}"
grep -Fq 'shadowtls-outbound-response.txt' "${SCENARIO_FILE}"
grep -Fq 'shadowtls_outbound_server_stderr' "${SCENARIO_FILE}"
grep -Fq 'outbound/http[shadowtls-outbound-http]' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 25 --file "${shadowtls_outbound_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 26 --file "${shadowtls_outbound_http_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 27 --id shadowtls-outbound-http' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 28 --id shadowtls-outbound-verification' \
  "${SCENARIO_FILE}"
grep -Fq '.server_port == 1095 and .version == 3' "${SCENARIO_FILE}"
grep -Fq '.detour == "shadowtls-outbound-verification"' "${SCENARIO_FILE}"

if grep -Fq 'PUBLIC_DATA_PLANE=shadowtls' "${SCENARIO_FILE}"; then
  printf 'ShadowTLS outbound verification must not claim public data-plane ownership\n' >&2
  exit 1
fi

printf 'verification ShadowTLS outbound contract checks passed\n'
