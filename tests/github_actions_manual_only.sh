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

assert_pr_trigger() {
  local events
  events=$(awk '
    /^on:[[:space:]]*$/ { in_on=1; headers++; next }
    in_on && /^[^[:space:]#]/ { in_on=0 }
    in_on && /^[[:space:]]+[^[:space:]#]/ { print }
    END { if (headers != 1) exit 1 }
  ' "$@") || return 1
  [[ "${events}" == $'  pull_request:\n    branches: [main]\n    types: [opened, synchronize, reopened]' ]]
}

workflow_step_script() {
  local step_name=$1 workflow_file=$2
  awk -v step_name="${step_name}" '
    $0 == "      - name: " step_name { step=1; next }
    step && /^      - / { exit }
    step && /^        run: \|[-+]?[[:space:]]*$/ { body=1; next }
    body && NF && $0 !~ /^          / { exit }
    body && /^          / { print substr($0,11); lines++ }
    END { if (!lines) exit 1 }
  ' "${workflow_file}"
}

assert_pr_runner_scope() {
  local shape expected
  # The secrets context can be used with dot or bracket access or as a value.
  if grep -iwq 'secrets' "$@"; then return 1; fi
  # Check the complete permission and concurrency mappings, including folded values.
  shape=$(awk '
    /^[^[:space:]#]/ { section=$0; print; next }
    (section=="permissions:" || section=="concurrency:") && /^[[:space:]]*[^[:space:]#]/ { print; next }
    section=="jobs:" && /^(  |    |      |        )[^[:space:]#]/ {
      inputs=($0=="        with:" || $0=="        env:")
      if (/^      - uses: actions\/checkout@/) { print "      - uses: actions/checkout"; next }
      print
      next
    }
    section=="jobs:" && inputs && /^          [^[:space:]#]/ { print }
  ' "$@") || return 1
  expected=$(cat <<'SHAPE'
name: PR contract
on:
permissions:
  contents: read
concurrency:
  group: pr-contract-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  pr-contract:
    name: PR contract
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout
        with:
          ref: ${{ github.sha }}
          fetch-depth: 2
          persist-credentials: false
      - name: Verify the PR integration revision
        env:
          PR_HEAD: ${{ github.event.pull_request.head.sha }}
        run: |
      - name: Run lightweight repository checks
        run: |
SHAPE
) || return 1
  [[ "${shape}" == "${expected}" ]]
}

pr_workflow="${REPO_ROOT}/.github/workflows/pr-contract.yml"
assert_pr_trigger "${pr_workflow}"
assert_pr_runner_scope "${pr_workflow}"
count=0
for workflow in "${REPO_ROOT}"/.github/workflows/*.yml "${REPO_ROOT}"/.github/workflows/*.yaml; do
  [[ -f "${workflow}" && "${workflow}" != "${pr_workflow}" ]] || continue
  assert_manual_trigger "${workflow}" || { printf 'automatic/unknown workflow trigger: %s\n' "${workflow}" >&2; exit 1; }
  count=$((count + 1))
done
[[ ${count} -gt 0 ]]
# Reject implicit events and compact event syntax rather than guessing YAML.
for trigger in push pull_request pull_request_target release schedule workflow_run workflow_call repository_dispatch; do
  if printf 'on:\n  workflow_dispatch:\n  %s:\n' "${trigger}" | assert_manual_trigger; then exit 1; fi
done
if printf 'on: [push, workflow_dispatch]\n' | assert_manual_trigger; then exit 1; fi
for extra in '    paths: [install.sh]' '    branches-ignore: [legacy]' '  push:' '  pull_request_target:' '  workflow_dispatch:'; do
  if printf 'on:\n  pull_request:\n    branches: [main]\n    types: [opened, synchronize, reopened]\n%s\n' "${extra}" | assert_pr_trigger; then exit 1; fi
done
if printf 'on:\n  pull_request:\n    branches: [other]\n    types: [opened, synchronize, reopened]\n' | assert_pr_trigger; then exit 1; fi
if grep -Eq 'self-hosted|:[[:space:]]*write|(^|[[:space:]])sudo([[:space:]]|$)|^[[:space:]]*(environment|continue-on-error|if):' "${pr_workflow}"; then exit 1; fi
[[ "$(sed -n 's/^[[:space:]]*- uses: //p' "${pr_workflow}")" =~ ^actions/checkout@[0-9a-f]{40}[[:space:]] ]]
workflow="${REPO_ROOT}/.github/workflows/command-contract.yml"
grep -Fq 'ref: ${{ inputs.head_sha }}' "${workflow}"
grep -Fq 'ref: ${{ github.sha }}' "${workflow}"
grep -Fq 'bash "$GITHUB_WORKSPACE/trusted/dev/verification/ci.sh" "$VERIFY_BASE_REF" "$PWD" "$TRUSTED_MAIN_SHA"' "${workflow}"
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
grep -Fq 'group: command-contract-${{ github.sha }}-${{ inputs.head_sha }}-${{ inputs.base_ref }}-${{ inputs.legacy_core }}' "${workflow}"
grep -Fq 'prepare_core 1.13.18 SINGBOX_BINARY_113' "${workflow}"
grep -Fq 'git merge-base --is-ancestor "$EXPECTED_BASE" "$TRUSTED_MAIN_SHA"' "${workflow}"
grep -Fq 'ACTUAL_BASE=$(git merge-base "$TRUSTED_MAIN_SHA" "$EXPECTED_HEAD")' "${workflow}"
grep -Fq 'persist-credentials: false' "${workflow}"
grep -Fq 'contents: read' "${workflow}"
grep -Fq 'retention-days: 14' "${workflow}"
grep -Fq 'sudo -n env TMPDIR=/tmp' "${workflow}"
grep -Fq "grep -Fxq 'host_gate=passed'" "${workflow}"
if grep -E 'uses:[[:space:]]+actions/[^@[:space:]]+@' "${workflow}" | grep -Ev '@[0-9a-f]{40}([[:space:]]|$)'; then exit 1; fi
grep -Fq 'VERIFY_BASE_REF: ${{ inputs.base_ref }}' "${workflow}"
fixture=$(mktemp -d)
trap 'rm -rf -- "${fixture}"' EXIT
awk '/^    steps:$/ { print "    \"permissions\":"; print "      contents: \"write\"" } { print }' "${pr_workflow}" >"${fixture}/pr-override.yml"
if assert_pr_runner_scope "${fixture}/pr-override.yml"; then exit 1; fi
awk '$0=="      - name: Run lightweight repository checks" {
  print; print "        \"continue-on-error\": true"; next
} { print }' "${pr_workflow}" >"${fixture}/pr-soft-fail.yml"
if assert_pr_runner_scope "${fixture}/pr-soft-fail.yml"; then exit 1; fi
awk '/^  group:/ { print; print "    revision-specific-suffix"; next } { print }' "${pr_workflow}" >"${fixture}/pr-concurrency.yml"
if assert_pr_runner_scope "${fixture}/pr-concurrency.yml"; then exit 1; fi
for expression in 'secrets.FIXTURE_ONLY' "SeCrEtS ['FIXTURE_ONLY']" 'toJSON(secrets)'; do
  cat "${pr_workflow}" >"${fixture}/pr-secrets.yml"
  printf '          : "${{ %s }}"\n' "${expression}" >>"${fixture}/pr-secrets.yml"
  if assert_pr_runner_scope "${fixture}/pr-secrets.yml"; then exit 1; fi
done
sed '/^        run: |$/s/run: |/run: |-/g' "${pr_workflow}" >"${fixture}/pr-strip.yml"
workflow_step_script "Verify the PR integration revision" "${fixture}/pr-strip.yml" >"${fixture}/strip.sh"
grep -Fq 'diff --check' "${fixture}/strip.sh"
awk '/^        run: \|$/ && !changed { print "        run: exit 1"; changed=1; next } { print }' "${pr_workflow}" >"${fixture}/pr-inline.yml"
if workflow_step_script "Verify the PR integration revision" "${fixture}/pr-inline.yml" >"${fixture}/inline.sh"; then exit 1; fi
test ! -s "${fixture}/inline.sh"
workflow_step_script "Validate inputs in the protected main workflow" "${workflow}" > "${fixture}/authorize.sh"
revision=0123456789abcdef0123456789abcdef01234567
GITHUB_REF=refs/heads/main EXPECTED_HEAD="${revision}" EXPECTED_BASE="${revision}" bash "${fixture}/authorize.sh"
if GITHUB_REF=refs/heads/main EXPECTED_HEAD="${revision}" EXPECTED_BASE=origin/main bash "${fixture}/authorize.sh" 2>/dev/null; then exit 1; fi
if GITHUB_REF=refs/heads/topic EXPECTED_HEAD="${revision}" EXPECTED_BASE="${revision}" bash "${fixture}/authorize.sh" 2>/dev/null; then exit 1; fi
workflow_step_script "Verify the PR integration revision" "${pr_workflow}" > "${fixture}/pr-revision.sh"
test -s "${fixture}/pr-revision.sh"
(
  # A caller may run this test from a Git hook with an inherited index or worktree.
  git_local_env=$(git rev-parse --local-env-vars)
  while IFS= read -r variable; do
    unset "${variable}"
  done <<<"${git_local_env}"
  export LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  repo="${fixture}/pr-repo"
  mkdir "${fixture}/no-hooks"
  git init -q --template= "${repo}"
  cd "${repo}"
  git symbolic-ref HEAD refs/heads/main
  git config user.name 'Workflow fixture'
  git config user.email 'workflow@example.invalid'
  git config commit.gpgsign false
  git config core.hooksPath "${fixture}/no-hooks"
  printf 'base\n' >example.txt
  git add example.txt
  git commit -qm base
  base_sha=$(git rev-parse HEAD)
  git checkout -qb change
  printf 'candidate\n' >example.txt
  git commit -qam candidate
  head_sha=$(git rev-parse HEAD)
  git checkout -q main
  # A PR event can still report the base from before this main commit.
  printf 'upstream change\n' >upstream.txt
  git add upstream.txt
  git commit -qm 'advance main'
  tested_base=$(git rev-parse HEAD)
  git merge -q --no-ff --no-edit --no-verify-signatures change
  merge_sha=$(git rev-parse HEAD)
  export GITHUB_STEP_SUMMARY="${fixture}/summary"
  GITHUB_SHA="${merge_sha}" PR_BASE="${base_sha}" PR_HEAD="${head_sha}" bash "${fixture}/pr-revision.sh" >/dev/null
  grep -Fxq "pr_head=${head_sha}" "${GITHUB_STEP_SUMMARY}"
  grep -Fxq "pr_base=${tested_base}" "${GITHUB_STEP_SUMMARY}"
  grep -Fxq "merge_tree=$(git rev-parse HEAD^{tree})" "${GITHUB_STEP_SUMMARY}"
  for field in GITHUB_SHA PR_HEAD; do
    if env GITHUB_SHA="${merge_sha}" PR_HEAD="${head_sha}" \
      "${field}=${revision}" bash "${fixture}/pr-revision.sh" 2>"${fixture}/reject"; then exit 1; fi
    grep -Fq 'does not match the PR event' "${fixture}/reject"
  done
  git checkout -qb bad "${base_sha}"
  printf 'trailing space \n' >example.txt
  git commit -qam 'whitespace fixture'
  bad_sha=$(git rev-parse HEAD)
  bad_merge=$(git commit-tree HEAD^{tree} -p "${base_sha}" -p "${bad_sha}" -m 'merge fixture')
  git checkout -q --detach "${bad_merge}"
  if GITHUB_SHA="${bad_merge}" PR_HEAD="${bad_sha}" \
    bash "${fixture}/pr-revision.sh" >"${fixture}/whitespace" 2>&1; then exit 1; fi
  grep -Fq 'trailing whitespace' "${fixture}/whitespace"
)
grep -Fq 'not_run_not_authorized' "${REPO_ROOT}/AGENTS.md"
grep -Fq 'not_run_not_authorized' "${REPO_ROOT}/docs/wiki/Development.md"
printf 'One bounded PR workflow; %s manual workflows; trigger and revision fixtures passed\n' "${count}"
