#!/usr/bin/env bash

set -euo pipefail

CI_VERIFICATION_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
unset CI_CANDIDATE_ROOT
if [[ $# -ge 2 ]]; then
  [[ -n "$2" ]] || exit 2
  CI_CANDIDATE_ROOT=$(cd -- "$2" && pwd -P) || exit 2
fi
source "${CI_VERIFICATION_ROOT}/run.sh"

ci_worktree_snapshot() {
  local file
  # Hash the bytes read by tests, independent of Git's content normalization.
  {
    git ls-files --stage -z || return 1
    git ls-files --cached --others --exclude-standard -z | sort -zu |
      while IFS= read -r -d '' file; do
        if [[ -L "${file}" ]]; then
          verification_plan_error "CI cannot bind symlinked worktree input: $(printf '%q' "${file}")"
          return 1
        elif [[ -f "${file}" ]]; then
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
  local actual test_file log digest index=0 results="$1/local-tests/results.tsv"
  local -n log_digests="$2"
  [[ -f "${results}" && ! -L "${results}" ]] || return 1
  actual=$(awk -F '\t' '
    NR == 1 { if ($0 != "test\tstatus\telapsed_seconds") exit 1; next }
    NF != 3 || $2 != "passed" || $3 !~ /^[0-9]+$/ { exit 1 }
    { print $1 }
  ' "${results}") || return 1
  [[ "${actual}" == "$(printf '%s\n' "${VERIFY_PLAN_TESTS[@]}")" ]] || return 1
  [[ ${#log_digests[@]} == ${#VERIFY_PLAN_TESTS[@]} ]] || return 1
  for test_file in "${VERIFY_PLAN_TESTS[@]}"; do
    log="$1/local-tests/${test_file#tests/}.log"
    [[ -f "${log}" && ! -L "${log}" && -r "${log}" ]] || return 1
    digest=$(sha256sum < "${log}") || return 1
    [[ "${digest}" == "${log_digests[index]}" ]] || return 1
    index=$((index + 1))
  done
}

ci_core_digest() {
  if [[ -n "$1" ]]; then
    sha256sum < "$1" | cut -d ' ' -f 1
  else
    printf 'not_supplied\n'
  fi
}

ci_core_version() {
  local binary=$1 family=$2 version
  if [[ -z "${binary}" ]]; then
    printf 'not_supplied\n'
    return 0
  fi
  if [[ ! -f "${binary}" || ! -x "${binary}" ]] ||
    ! version=$("${binary}" version | sed -n '1p') ||
    [[ "${version}" != "sing-box version ${family}."* ]]; then
    verification_plan_error "Configured sing-box ${family} validation core is unusable"
    return 2
  fi
  printf '%s\n' "${version}"
}

ci_check_core_scope() {
  local test_file
  for test_file in "${VERIFY_PLAN_TESTS[@]}"; do
    # Paired compatibility checks also need legacy input on older candidates.
    case "${test_file}" in
      tests/routing_policy_config.sh|tests/routing_policy_instance_baseline.sh)
        if [[ -z "${SINGBOX_BINARY_114:-}" ]]; then
          verification_plan_error "Selected routing check requires SINGBOX_BINARY_114: ${test_file}"
          return 2
        fi
        ;;
      tests/managed_openvpn_endpoint_runtime.sh)
        if [[ -c /dev/net/tun ]] && ! grep -Fq '${SBV_CI_HOST_ONLY:-0}' "${test_file}"; then
          verification_plan_error 'Selected OpenVPN fixture lacks host-only TUN isolation'
          return 2
        fi
        ;;
      tests/singbox_1_14_compatibility.sh|tests/shadowsocks_export_client.sh)
        if [[ -z "${SINGBOX_BINARY_113:-}" || -z "${SINGBOX_BINARY_114:-}" ]]; then
          verification_plan_error "Selected check requires SINGBOX_BINARY_113 and SINGBOX_BINARY_114: ${test_file}"
          return 2
        fi
        ;;
    esac
    # The existing fixtures read the core directly or through a named loop.
    if [[ -z "${SINGBOX_BINARY_114:-}" ]] &&
      grep -Eq '\$\{?SINGBOX_BINARY_114\b|^[[:space:]]*for [[:alnum:]_]+ in SINGBOX_BINARY_113 SINGBOX_BINARY_114\b' "${test_file}"; then
      verification_plan_error "Selected check requires SINGBOX_BINARY_114: ${test_file}"
      return 2
    fi
  done
}

main() {
  local base=${1:?base revision required} scope_file=.github/verification-scope.txt
  local scope_changed=n file scope_base='' option value extra line run_dir summary provenance local_status
  local core_113_version core_114_version core_113_digest core_114_digest
  local head head_tree expected_base start_snapshot worktree_status worktree_state=clean status=0
  local -a selectors=() selected_tests tested_log_digests=() contracts=(
    tests/command_catalog_contract.sh tests/storage_selinux.sh
    tests/agent_service_operations.sh tests/agent_routing_operations.sh
    tests/agent_cli_ops_commands.sh tests/agent_docs_cover_capabilities.sh
    tests/wiki_documentation.sh tests/version_metadata_is_consistent.sh
    tests/reality_region_candidates.sh tests/reality_region_candidate_evidence.sh
    tests/reality_region_candidate_evidence_contract.sh
  )
  [[ $# -le 3 ]] || return 2
  cd "${REPO_ROOT}"
  if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
    if [[ -n "${SINGBOX_BINARY_114:-}" && ! "${ROUTING_POLICY_TEST_REAL_CORE}" -ef "${SINGBOX_BINARY_114}" ]]; then
      verification_plan_error 'Routing probe core conflicts with SINGBOX_BINARY_114'
      return 2
    fi
    SINGBOX_BINARY_114="${ROUTING_POLICY_TEST_REAL_CORE}"
  fi
  if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then
    SINGBOX_BINARY_113=$(realpath -e -- "${SINGBOX_BINARY_113}") || return 2
    export SINGBOX_BINARY_113
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
    SINGBOX_BINARY_114=$(realpath -e -- "${SINGBOX_BINARY_114}") || return 2
    export SINGBOX_BINARY_114
  fi
  if [[ -n "${ROUTING_POLICY_TEST_REAL_CORE:-}" ]]; then
    export ROUTING_POLICY_TEST_REAL_CORE="${SINGBOX_BINARY_114}"
  fi
  if [[ -n "${CI_CANDIDATE_ROOT:-}" ]]; then
    for file in planner.sh selection.sh; do
      if ! cmp -s "${CI_VERIFICATION_ROOT}/${file}" "dev/verification/${file}"; then
        verification_plan_error 'Candidate planning rules differ from the trusted driver; use scoped isolated validation'
        return 2
      fi
    done
  fi
  head=$(git rev-parse --verify HEAD)
  head_tree=$(git rev-parse "${head}^{tree}")
  if [[ -n "${3:-}" ]]; then
    if [[ ! "$3" =~ ^[0-9a-f]{40}$ ||
      "$(git -C "${CI_VERIFICATION_ROOT}" rev-parse --verify HEAD)" != "$3" ]] ||
      ! git -C "${CI_VERIFICATION_ROOT}" diff --no-ext-diff --quiet "$3" -- ci.sh common.sh run.sh planner.sh selection.sh ||
      ! git merge-base --is-ancestor "$3" refs/remotes/origin/main; then
      verification_plan_error 'Protected main revision does not match the verifier checkout'
      return 2
    fi
  fi
  worktree_status=$(git status --porcelain --untracked-files=all)
  start_snapshot=$(ci_worktree_snapshot)
  core_113_digest=$(ci_core_digest "${SINGBOX_BINARY_113:-}")
  core_114_digest=$(ci_core_digest "${SINGBOX_BINARY_114:-}")
  core_113_version=$(ci_core_version "${SINGBOX_BINARY_113:-}" 1.13)
  core_114_version=$(ci_core_version "${SINGBOX_BINARY_114:-}" 1.14)
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
  summary="${run_dir}/summary.log"
  verification_print_plan > "${run_dir}/plan.txt"
  printf 'run_dir=%s\nCI proof boundary: host tests only; Docker and dedicated container fixtures are not executed.\n' "${run_dir}"
  provenance=$(
    printf 'mode=host_ci\nhead=%s\nhead_tree=%s\nbase_ref_sha=%s\nbase=%s\nscope_base=%s\nworktree=%s\nworktree_sha256=%s\n' \
      "${head}" "${head_tree}" "${base}" "${expected_base}" "${scope_base:-not_used}" "${worktree_state}" "${start_snapshot%% *}"
    printf 'trusted_driver_sha=%s\n' "${3:-not_supplied}"
    printf 'environment=%s\nbash=%s\njq=%s\nvalidation_core=%s\nvalidation_core_113=%s\nvalidation_core_113_sha256=%s\nvalidation_core_114_sha256=%s\n' \
      "$(uname -sm)" "${BASH_VERSION}" "$(jq --version)" "${core_114_version}" "${core_113_version}" "${core_113_digest}" "${core_114_digest}"
    if [[ "${VERIFY_PLAN_RUNTIME_REQUIRED}" == 1 || ${#VERIFY_PLAN_SCENARIOS[@]} -gt 0 ||
      " ${VERIFY_PLAN_TESTS[*]} " == *' tests/managed_listener_resources.sh '* ||
      " ${VERIFY_PLAN_TESTS[*]} " == *' tests/managed_openvpn_endpoint_runtime.sh '* ]]; then
      printf 'remote_status=required_not_run\n'
    else
      printf 'remote_status=not_required\n'
    fi
  )
  printf '%s\n' "${provenance}" > "${summary}"
  if ! ci_check_core_scope; then
    printf 'local_status=required_not_run\nhost_gate=failed\n' >> "${summary}"
    return 2
  fi
  if [[ " ${VERIFY_PLAN_TESTS[*]} " == *' tests/routing_policy_config.sh '* ||
    " ${VERIFY_PLAN_TESTS[*]} " == *' tests/routing_policy_instance_baseline.sh '* ]]; then
    export ROUTING_POLICY_TEST_REAL_CORE="${SINGBOX_BINARY_114}"
  fi
  VERIFY_SKIP_LOCAL_TESTS=0 SBV_CI_HOST_ONLY=1 SBV_TEST_ISOLATED_LISTENER_WILDCARD=0 \
    run_local_tests "${run_dir}" tested_log_digests || status=$?
  if [[ -L "${summary}" || ( -e "${summary}" && ! -f "${summary}" ) ]]; then
    verification_plan_error 'CI summary is missing or invalid'
    return 2
  fi
  if ! ci_inputs_match "${head}" "${start_snapshot}" ||
    [[ "$(ci_core_digest "${SINGBOX_BINARY_113:-}")" != "${core_113_digest}" ||
       "$(ci_core_digest "${SINGBOX_BINARY_114:-}")" != "${core_114_digest}" ]]; then
    printf '%s\nevidence=inputs_changed\nhost_gate=failed\n' "${provenance}" > "${summary}"
    verification_plan_error 'CI inputs changed during host verification'
    return 2
  fi
  if [[ "${status}" != 0 ]]; then
    local_status=failed
    if [[ -f "${summary}" && "$(tail -n 1 "${summary}")" == "local_status=required_not_run" ]]; then
      local_status=required_not_run
    fi
    printf '%s\nlocal_status=%s\nhost_gate=failed\n' "${provenance}" "${local_status}" > "${summary}"
    return "${status}"
  fi
  if ! ci_results_match "${run_dir}" tested_log_digests ||
    [[ ! -f "${summary}" || ! -f "${run_dir}/plan.txt" || -L "${run_dir}/plan.txt" ||
      "$(< "${run_dir}/plan.txt")" != "$(verification_print_plan)" ||
      "$(< "${summary}")" != "${provenance}"$'\nlocal_status=passed' ]]; then
    printf '%s\nevidence=results_incomplete\nhost_gate=failed\n' "${provenance}" > "${summary}"
    verification_plan_error 'CI evidence does not match the planned host tests and inputs'
    return 2
  fi
  printf 'host_gate=passed\n' >> "${summary}"
}

main "$@"
