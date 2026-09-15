#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# Tor must launch the image-provided external executable, prove the Tor page
# through the managed SOCKS route, and delete the component through CAS.
grep -Fq 'tor-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'executable_path:"/usr/bin/tor"' "${SCENARIO_FILE}"
grep -Fq 'check.torproject.org' "${SCENARIO_FILE}"
grep -Fq 'This browser is configured to use Tor' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=tor_external_tcp' "${SCENARIO_FILE}"
grep -Fq 'TARGET=check.torproject.org' "${SCENARIO_FILE}"
grep -Fq 'tor-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 23 --file "${tor_outbound_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 24 --id tor-outbound-verification' \
  "${SCENARIO_FILE}"
grep -Fq '.torrc.ClientOnly == "1"' "${SCENARIO_FILE}"

if grep -Fq 'PUBLIC_DATA_PLANE=tor' "${SCENARIO_FILE}"; then
  printf 'Tor outbound verification must not claim managed public data-plane ownership\n' >&2
  exit 1
fi

printf 'verification Tor outbound contract checks passed\n'
