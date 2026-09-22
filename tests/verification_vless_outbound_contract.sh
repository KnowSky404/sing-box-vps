#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"

test -r "${SCENARIO_FILE}"
bash -n "${SCENARIO_FILE}"

# VLESS must exercise a real local VLESS upstream, preserve the typed TCP
# network, and remove the component-owned route through the revision CAS.
grep -Fq 'vless-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'vless-outbound-upstream' "${SCENARIO_FILE}"
grep -Fq 'DATA_PLANE=vless_tcp_loopback' "${SCENARIO_FILE}"
grep -Fq 'UPSTREAM=vless_loopback_server' "${SCENARIO_FILE}"
grep -Fq 'vless-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 23 --file "${vless_outbound_record}"' \
  "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 24 --id vless-outbound-verification' \
  "${SCENARIO_FILE}"
grep -Fq 'config:{server:"127.0.0.1",server_port:$server_port,uuid:$uuid,' \
  "${SCENARIO_FILE}"
grep -Fq 'network == ["tcp"]' "${SCENARIO_FILE}"
grep -Fq 'grep -Fqx "${direct_marker}"' "${SCENARIO_FILE}"

if grep -Fq 'PUBLIC_DATA_PLANE=vless' "${SCENARIO_FILE}"; then
  printf 'VLESS outbound verification must not claim public data-plane ownership\n' >&2
  exit 1
fi

printf 'verification VLESS outbound contract checks passed\n'
