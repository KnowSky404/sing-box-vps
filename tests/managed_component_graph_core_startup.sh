#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d /tmp/sing-box-vps-graph-startup.XXXXXX)
trap 'rm -rf -- "${TEST_DIR}"' EXIT
source "${REPO_ROOT}/install.sh"

# No listeners, remote rule sets, certificates or credentials. These fixtures
# demonstrate errors that check accepts but the core startup phase rejects.
jq -n '{outbounds:[{type:"direct",tag:"direct"}],route:{final:"missing"}}' \
  > "${TEST_DIR}/route-final.json"
jq -n '{outbounds:[{type:"direct",tag:"direct"}],
  dns:{servers:[{type:"local",tag:"local"}],final:"missing"}}' \
  > "${TEST_DIR}/dns-final.json"
jq -n '{outbounds:[{type:"direct",tag:"direct"}],
  dns:{servers:[{type:"udp",tag:"a",server:"127.0.0.1",domain_resolver:"missing"}]}}' \
  > "${TEST_DIR}/dns-dependency.json"
jq -n '{outbounds:[{type:"direct",tag:"direct"}],route:{default_domain_resolver:"a"},dns:{servers:[
  {type:"udp",tag:"a",server:"127.0.0.1",domain_resolver:"b"},
  {type:"udp",tag:"b",server:"127.0.0.1",domain_resolver:"a"}]}}' \
  > "${TEST_DIR}/dns-cycle.json"

for case_name in route-final dns-final dns-dependency dns-cycle; do
  if validate_managed_component_graph "${TEST_DIR}/${case_name}.json" \
    >"${TEST_DIR}/graph.stdout" 2>"${TEST_DIR}/graph.stderr"; then
    printf 'graph accepted startup-invalid fixture: %s\n' "${case_name}" >&2
    exit 1
  fi
  [[ ! -s "${TEST_DIR}/graph.stdout" ]]
  if [[ "${case_name}" == dns-cycle ]]; then
    grep -Fq 'component_graph: dependency cycle;' "${TEST_DIR}/graph.stderr"
  else
    grep -Fq 'component_graph: unknown reference;' "${TEST_DIR}/graph.stderr"
  fi
done

comparison_count=0
for binary_var in SINGBOX_BINARY_113 SINGBOX_BINARY_114; do
  binary=${!binary_var:-}
  [[ -n "${binary}" ]] || continue
  [[ -x "${binary}" ]]
  expected_version=$("${binary}" version | sed -n 's/^sing-box version //p' | head -n 1)
  [[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'configured %s core reported an invalid version\n' "${binary_var}" >&2
    exit 1
  }
  [[ "$("${binary}" version | sed -n 's/^sing-box version //p')" == "${expected_version}" ]]
  for case_name in route-final dns-final dns-dependency dns-cycle; do
    "${binary}" check -c "${TEST_DIR}/${case_name}.json" \
      >"${TEST_DIR}/core-check.stdout" 2>"${TEST_DIR}/core-check.stderr"
    run_status=0
    timeout --signal=TERM --kill-after=2 5 "${binary}" run -c "${TEST_DIR}/${case_name}.json" \
      >"${TEST_DIR}/core-run.stdout" 2>"${TEST_DIR}/core-run.stderr" || run_status=$?
    [[ "${run_status}" == 1 ]] || {
      printf 'unexpected core startup status: %s %s status=%s\n' \
        "${expected_version}" "${case_name}" "${run_status}" >&2
      exit 1
    }
    case "${case_name}" in
      route-final) expected_error='default outbound not found' ;;
      dns-final) expected_error='default DNS server not found' ;;
      dns-dependency) expected_error='dependency[missing] not found' ;;
      dns-cycle) expected_error='circular server dependency' ;;
    esac
    grep -Fq "${expected_error}" "${TEST_DIR}/core-run.stderr"
    comparison_count=$((comparison_count + 1))
  done
done

printf 'graph startup fixtures: 4 rejected; real core comparisons: %s\n' "${comparison_count}"
if [[ "${comparison_count}" == 0 ]]; then
  printf 'real startup comparisons not run: set SINGBOX_BINARY_113 and SINGBOX_BINARY_114\n'
fi
