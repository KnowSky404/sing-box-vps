#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

assert_manual_trigger() {
  awk '
    /^on:[[:space:]]*$/ { in_on=1; headers++; next }
    in_on && /^[^[:space:]#]/ { in_on=0 }
    in_on && /^  [^[:space:]#]/ {
      events++
      if ($0 !~ /^  workflow_dispatch:[[:space:]]*$/) invalid=1
    }
    END { exit (headers != 1 || events != 1 || invalid) }
  ' "$@"
}

count=0
for workflow in "${REPO_ROOT}"/.github/workflows/*.yml "${REPO_ROOT}"/.github/workflows/*.yaml; do
  [[ -f "${workflow}" ]] || continue
  assert_manual_trigger "${workflow}" || { printf 'automatic/unknown workflow trigger: %s\n' "${workflow}" >&2; exit 1; }
  count=$((count + 1))
done
[[ ${count} -gt 0 ]]
# Reject implicit events and compact event syntax rather than guessing YAML.
for trigger in push pull_request pull_request_target release schedule workflow_run workflow_call repository_dispatch; do
  if printf 'on:\n  workflow_dispatch:\n  %s:\n' "${trigger}" | assert_manual_trigger; then exit 1; fi
done
if printf 'on: [push, workflow_dispatch]\n' | assert_manual_trigger; then exit 1; fi
workflow="${REPO_ROOT}/.github/workflows/command-contract.yml"
grep -Fq 'ref: ${{ github.sha }}' "${workflow}"
grep -Fq 'VERIFY_BASE_REF: ${{ inputs.base_ref }}' "${workflow}"
grep -Fq 'not_run_not_authorized' "${REPO_ROOT}/AGENTS.md"
printf 'All %s workflows require manual dispatch; automatic events rejected; no Actions run started\n' "${count}"
