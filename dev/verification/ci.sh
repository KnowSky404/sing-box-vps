#!/usr/bin/env bash

set -euo pipefail

CI_VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${CI_VERIFICATION_ROOT}/common.sh"
source "${CI_VERIFICATION_ROOT}/planner.sh"

main() {
  local base=${1:?base revision required} scope_file=.github/verification-scope.txt
  local scope_changed=n file scope_base option value extra line
  local -a selectors=() contracts=(
    tests/command_catalog_contract.sh tests/storage_selinux.sh
    tests/agent_service_operations.sh tests/agent_routing_operations.sh
    tests/agent_cli_ops_commands.sh tests/agent_docs_cover_capabilities.sh
    tests/wiki_documentation.sh tests/version_metadata_is_consistent.sh
    tests/reality_region_candidates.sh tests/reality_region_candidate_evidence.sh
    tests/reality_region_candidate_evidence_contract.sh
  )
  [[ $# == 1 ]] || return 2
  cd "${REPO_ROOT}"
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
      if [[ "${option}" != base || "${scope_base}" != "${VERIFY_PLAN_BASE}" || -n "${extra}" ]]; then
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
  fi
  # Contract gates cannot resolve unmapped impact on behalf of an author.
  verification_parse_options --base "${base}" "${selectors[@]}"
  verification_build_plan
  verification_print_plan > dev/verification-runs/ci/scoped-plan.txt
  [[ "${VERIFY_PLAN_STATUS}" == ready ]] || { verification_plan_error 'CI impact still needs scope'; return 2; }
  for file in "${contracts[@]}"; do selectors+=(--test "${file}"); done
  bash scripts/build-install.sh --check
  bash scripts/build-command-docs.sh --check
  printf 'CI proof boundary: host tests only; Docker scenarios are not executed.\n'
  VERIFY_SKIP_REMOTE=1 bash dev/verification/run.sh --base "${base}" "${selectors[@]}"
}

main "$@"
