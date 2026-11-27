#!/usr/bin/env bash

set -euo pipefail

CI_VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${CI_VERIFICATION_ROOT}/run.sh"

ci_worktree_snapshot() {
  local file
  # Hash the bytes read by tests, independent of Git's content normalization.
  {
    git ls-files --stage -z || return 1
    git ls-files --cached --others --exclude-standard -z | sort -zu |
      while IFS= read -r -d '' file; do
        if [[ -L "${file}" || -f "${file}" ]]; then
          printf '%s\0' "${file}"
        elif [[ -e "${file}" ]]; then
          return 1
        fi
      done | tar --null --no-recursion --format=gnu --mtime=@0 --owner=0 --group=0 -cf - -T - || return 1
  } | sha256sum
}

ci_inputs_match() {
  local current_head current_snapshot
  current_head=$(git rev-parse --verify HEAD) || return 1
  current_snapshot=$(ci_worktree_snapshot) || return 1
  [[ "${current_head}" == "$1" && "${current_snapshot}" == "$2" ]]
}

ci_results_match() {
  local actual results="$1/local-tests/results.tsv"
  [[ -f "${results}" && ! -L "${results}" ]] || return 1
  actual=$(awk -F '\t' '
    NR == 1 { if ($0 != "test\tstatus\telapsed_seconds") exit 1; next }
    NF != 3 || $2 != "passed" || $3 !~ /^[0-9]+$/ { exit 1 }
    { print $1 }
  ' "${results}") || return 1
  [[ "${actual}" == "$(printf '%s\n' "${VERIFY_PLAN_TESTS[@]}")" ]]
}

main() {
  local base=${1:?base revision required} scope_file=.github/verification-scope.txt
  local scope_changed=n file scope_base option value extra line run_dir core_version
  local head head_tree expected_base start_snapshot worktree_status worktree_state=clean status=0
  local -a selectors=() selected_tests contracts=(
    tests/command_catalog_contract.sh tests/storage_selinux.sh
    tests/agent_service_operations.sh tests/agent_routing_operations.sh
    tests/agent_cli_ops_commands.sh tests/agent_docs_cover_capabilities.sh
    tests/wiki_documentation.sh tests/version_metadata_is_consistent.sh
    tests/reality_region_candidates.sh tests/reality_region_candidate_evidence.sh
    tests/reality_region_candidate_evidence_contract.sh
  )
  [[ $# == 1 ]] || return 2
  cd "${REPO_ROOT}"
  head=$(git rev-parse --verify HEAD)
  head_tree=$(git rev-parse "${head}^{tree}")
  worktree_status=$(git status --porcelain --untracked-files=all)
  start_snapshot=$(ci_worktree_snapshot)
  [[ -z "${worktree_status}" ]] || worktree_state=dirty
  base=$(git rev-parse --verify --end-of-options "${base}^{commit}")
  expected_base=$(git merge-base "${base}" "${head}")
  verification_parse_options --base "${base}"
  verification_build_plan
  mkdir -p dev/verification-runs/ci
  verification_print_plan > dev/verification-runs/ci/unscoped-plan.txt
  for file in "${VERIFY_CHANGED_FILES[@]}"; do
    [[ "${file}" != "${scope_file}" ]] || scope_changed=y
  done
  if [[ "${VERIFY_PLAN_STATUS}" == needs_scope || "${scope_changed}" == y ]]; then
    if [[ "${scope_changed}" != y || ! -f "${scope_file}" || -L "${scope_file}" ]]; then
      verification_plan_error 'CI needs a changed .github/verification-scope.txt bound to this merge base'
      return 2
    fi
    {
      IFS=' ' read -r option scope_base extra
      if [[ "${option}" != base || ! "${scope_base}" =~ ^[0-9a-f]{40}$ || -n "${extra}" ]]; then
        verification_plan_error 'CI scope header must contain its full merge-base SHA'
        return 2
      fi
      if [[ "${scope_base}" != "${VERIFY_PLAN_BASE}" ]]; then
        verification_plan_error 'CI scope base is stale or invalid; use the actual merge-base revision'
        return 2
      fi
      while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        IFS=' ' read -r option value extra <<< "${line}"
        if [[ -z "${value}" || -n "${extra}" ]]; then
          verification_plan_error 'CI scope expects one selector and value per line'
          return 2
        fi
        case "${option}" in
          --test|--scenario) selectors+=("${option}" "${value}") ;;
          *) verification_plan_error 'CI scope accepts only --test and --scenario'; return 2 ;;
        esac
      done
    } < "${scope_file}"
    [[ ${#selectors[@]} -gt 0 ]] || { verification_plan_error 'CI scope is empty'; return 2; }
    verification_parse_options --base "${base}" "${selectors[@]}"
    verification_build_plan
  fi
  # Contract gates cannot resolve unmapped impact on behalf of an author.
  verification_print_plan > dev/verification-runs/ci/scoped-plan.txt
  if [[ "${VERIFY_PLAN_STATUS}" != ready && "${VERIFY_PLAN_RUNTIME_REQUIRED}" != 1 ]]; then
    verification_plan_error 'CI host impact still needs scope'
    return 2
  fi
  if [[ "${VERIFY_PLAN_BASE}" != "${expected_base}" ]] || ! ci_inputs_match "${head}" "${start_snapshot}"; then
    verification_plan_error 'CI inputs changed during planning'
    return 2
  fi
  # Check generated installer bytes before any selected test sources the installer.
  selected_tests=("${VERIFY_PLAN_TESTS[@]}")
  VERIFY_PLAN_TESTS=()
  verification_add_requested_test tests/install_build_sync.sh
  for file in "${selected_tests[@]}"; do verification_plan_append VERIFY_PLAN_TESTS "${file}"; done
  for file in "${contracts[@]}"; do verification_add_requested_test "${file}"; done
  run_dir=$(create_run_dir)
  verification_print_plan > "${run_dir}/plan.txt"
  printf 'run_dir=%s\nCI proof boundary: host tests only; Docker and dedicated container fixtures are not executed.\n' "${run_dir}"
  core_version=not_supplied
  if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
    core_version=$("${SINGBOX_BINARY_114}" version | sed -n '1p')
  fi
  {
    printf 'mode=host_ci\nhead=%s\nhead_tree=%s\nbase=%s\nworktree=%s\nworktree_sha256=%s\n' \
      "${head}" "${head_tree}" "${expected_base}" "${worktree_state}" "${start_snapshot%% *}"
    printf 'environment=%s\nbash=%s\njq=%s\nvalidation_core=%s\n' \
      "$(uname -sm)" "${BASH_VERSION}" "$(jq --version)" "${core_version}"
  } > "${run_dir}/summary.log"
  if [[ "${VERIFY_PLAN_RUNTIME_REQUIRED}" == 1 || ${#VERIFY_PLAN_SCENARIOS[@]} -gt 0 ]]; then
    printf 'remote_status=required_not_run\n' >> "${run_dir}/summary.log"
  else
    printf 'remote_status=not_required\n' >> "${run_dir}/summary.log"
  fi
  VERIFY_SKIP_LOCAL_TESTS=0 run_local_tests "${run_dir}" || status=$?
  if ! ci_inputs_match "${head}" "${start_snapshot}"; then
    printf 'evidence=inputs_changed\nhost_gate=failed\n' >> "${run_dir}/summary.log"
    verification_plan_error 'CI inputs changed during host verification'
    return 2
  fi
  if [[ "${status}" != 0 ]]; then
    printf 'host_gate=failed\n' >> "${run_dir}/summary.log"
    return "${status}"
  fi
  if ! ci_results_match "${run_dir}"; then
    printf 'evidence=results_incomplete\nhost_gate=failed\n' >> "${run_dir}/summary.log"
    verification_plan_error 'CI results do not match the planned host tests'
    return 2
  fi
  printf 'host_gate=passed\n' >> "${run_dir}/summary.log"
}

main "$@"
