#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCENARIO_FILE="${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"
DOCKERFILE="${REPO_ROOT}/dev/verification/docker/Dockerfile"

test -r "${SCENARIO_FILE}"
test -r "${DOCKERFILE}"
bash -n "${SCENARIO_FILE}"
grep -Eq '(^|[[:space:]])openssh-server([[:space:]]|\\|$)' "${DOCKERFILE}"

# Keep the remote proof fail-closed and explicit: it must create a typed SSH
# outbound, pin the generated host key, exercise the SOCKS route, and delete
# the component through the following CAS revision.
grep -Fq 'ssh-outbound-verification' "${SCENARIO_FILE}"
grep -Fq 'host_key:[$host_key]' "${SCENARIO_FILE}"
grep -Fq 'Accepted password for ${ssh_server_user}' "${SCENARIO_FILE}"
grep -Fq 'socks5h://socks-user:socks-pass@127.0.0.1:1081' "${SCENARIO_FILE}"
grep -Fq 'ssh-outbound.result.env' "${SCENARIO_FILE}"
grep -Fq "'DATA_PLANE=ssh_direct_tcpip_loopback'" "${SCENARIO_FILE}"
grep -Fq "'HOST_KEY_VERIFICATION=pinned'" "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 7 --file "${ssh_record}"' "${SCENARIO_FILE}"
grep -Fq -- '--expected-revision 8 --id ssh-outbound-verification' "${SCENARIO_FILE}"

# The marker is intentionally loopback-only and the scenario does not mutate
# the installer firewall ledger or claim public/production reachability.
grep -Fq 'DATA_PLANE=ssh_direct_tcpip_loopback' "${SCENARIO_FILE}"
if grep -Fq 'POLICY_OWNERSHIP=managed' "${SCENARIO_FILE}"; then
  printf 'SSH verification must not claim managed host policy ownership\n' >&2
  exit 1
fi

printf 'verification SSH outbound contract checks passed\n'
