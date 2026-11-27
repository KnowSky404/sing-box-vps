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
grep -Fq 'ref: ${{ inputs.head_sha }}' "${workflow}"
grep -Fq 'ref: ${{ github.sha }}' "${workflow}"
grep -Fq 'bash "$GITHUB_WORKSPACE/trusted/dev/verification/ci.sh" "$VERIFY_BASE_REF" "$PWD"' "${workflow}"
grep -Fq 'EXPECTED_HEAD: ${{ inputs.head_sha }}' "${workflow}"
# Cancel obsolete work only after the authorization job has passed.
awk '
  /^concurrency:/ { exit 1 }
  /^  command-contract:$/ { host_job=1; next }
  /^  [^[:space:]#]/ { host_job=0 }
  host_job && /^    needs: authorize-head$/ { authorized=1 }
  host_job && /^    concurrency:$/ { gated=1 }
  END { if (!authorized || !gated) exit 1 }
' "${workflow}"
grep -Fq 'group: command-contract-${{ inputs.head_sha }}-${{ inputs.base_ref }}-${{ inputs.legacy_core }}' "${workflow}"
grep -Fq 'prepare_core 1.13.18 SINGBOX_BINARY_113' "${workflow}"
grep -Fq 'git merge-base --is-ancestor "$EXPECTED_BASE" "$TRUSTED_MAIN_SHA"' "${workflow}"
grep -Fq 'ACTUAL_BASE=$(git merge-base "$EXPECTED_BASE" "$EXPECTED_HEAD")' "${workflow}"
grep -Fq 'persist-credentials: false' "${workflow}"
grep -Fq 'contents: read' "${workflow}"
grep -Fq 'retention-days: 14' "${workflow}"
grep -Fq 'sudo -n env TMPDIR=/tmp' "${workflow}"
grep -Fq "grep -Fxq 'host_gate=passed'" "${workflow}"
if grep -E 'uses:[[:space:]]+actions/[^@[:space:]]+@' "${workflow}" | grep -Ev '@[0-9a-f]{40}([[:space:]]|$)'; then exit 1; fi
grep -Fq 'VERIFY_BASE_REF: ${{ inputs.base_ref }}' "${workflow}"
fixture=$(mktemp -d)
trap 'rm -rf -- "${fixture}"' EXIT
awk '
  /^      - name: Validate inputs in the protected main workflow$/ { step=1 }
  step && /^        run: \|$/ { body=1; next }
  body && /^[^ ]|^  [^ ]/ { exit }
  body && /^          / { print substr($0,11) }
' "${workflow}" > "${fixture}/authorize.sh"
revision=0123456789abcdef0123456789abcdef01234567
GITHUB_REF=refs/heads/main EXPECTED_HEAD="${revision}" EXPECTED_BASE="${revision}" bash "${fixture}/authorize.sh"
if GITHUB_REF=refs/heads/main EXPECTED_HEAD="${revision}" EXPECTED_BASE=origin/main bash "${fixture}/authorize.sh" 2>/dev/null; then exit 1; fi
if GITHUB_REF=refs/heads/topic EXPECTED_HEAD="${revision}" EXPECTED_BASE="${revision}" bash "${fixture}/authorize.sh" 2>/dev/null; then exit 1; fi
grep -Fq 'not_run_not_authorized'  "${REPO_ROOT}/AGENTS.md"
printf 'All %s workflows require manual dispatch; automatic events rejected; no Actions run started\n' "${count}"
