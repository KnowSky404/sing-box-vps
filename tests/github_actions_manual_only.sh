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
# Actions checks out a SHA: only remote-tracking main is guaranteed to exist.
fixture=$(mktemp -d)
trap 'rm -rf -- "${fixture}"' EXIT
git -C "${fixture}" init -q
git -C "${fixture}" symbolic-ref HEAD refs/heads/fixture
printf 'fixture\n' > "${fixture}/README.md"
git -C "${fixture}" add README.md
git -C "${fixture}" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
git -C "${fixture}" update-ref refs/remotes/origin/main HEAD
git -C "${fixture}" checkout -q --detach HEAD
if git -C "${fixture}" show-ref --verify --quiet refs/heads/main; then exit 1; fi
default_base=$(sed -n 's/^        default: //p' "${workflow}")
[[ "$(git -C "${fixture}" rev-parse --verify "${default_base}^{commit}")" == "$(git -C "${fixture}" rev-parse HEAD)" ]]
grep -Fq 'not_run_not_authorized'  "${REPO_ROOT}/AGENTS.md"
printf 'All %s workflows require manual dispatch; automatic events rejected; no Actions run started\n' "${count}"
