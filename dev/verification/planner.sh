#!/usr/bin/env bash

# Host-side planning only: never source the runtime or execute selected tests here.
set -euo pipefail

# shellcheck disable=SC1091
source "${VERIFICATION_ROOT}/selection.sh"

verification_usage() {
  cat <<'EOF'
Usage: bash dev/verification/run.sh [options]
  --plan                 Print the plan without running tests or creating artifacts.
  --base REF             Include branch changes from merge-base(REF, HEAD), plus
                         staged/unstaged changes and untracked files.
  --changed-file PATH...  Explicit paths; repeatable, cannot combine with --base.
  --group NAME           Add a local regression group; repeatable.
  --scenario NAME        Add a Docker scenario and its prerequisites; repeatable.
  --full                 Explicitly select all registered host tests and scenarios.
  --help                 Show this help and supported groups/scenarios.

Without --base, inspect working-tree changes against HEAD. Unknown runtime impact
requires an explicit group/scenario or --full before execution. Groups select
local checks; choose scenarios separately when runtime verification is required.
VERIFY_SKIP_REMOTE=1 skips Docker only, not the selected local tests.
EOF
  printf '\nGroups:\n'
  verification_list_groups
  printf '\nScenarios:\n'
  verification_list_scenarios
}

verification_plan_error() {
  printf 'ERROR: %s\n' "$*" >&2
  return 2
}

verification_plan_append() {
  local -n target=$1
  local value=$2 existing
  for existing in "${target[@]}"; do
    [[ "${existing}" != "${value}" ]] || return 0
  done
  target+=("${value}")
}

verification_plan_reset() {
  VERIFY_PLAN_ONLY=0
  VERIFY_PLAN_HELP=0
  VERIFY_PLAN_FULL=0
  VERIFY_PLAN_EXPLICIT_FILES=0
  VERIFY_PLAN_EXPLICIT_SCOPE=0
  VERIFY_PLAN_RUNTIME_REQUIRED=0
  VERIFY_PLAN_BASE_REF=''
  VERIFY_PLAN_BASE=''
  VERIFY_PLAN_MODE=local
  VERIFY_PLAN_STATUS=ready
  VERIFY_CHANGED_FILES=()
  VERIFY_REQUESTED_GROUPS=()
  VERIFY_REQUESTED_SCENARIOS=()
  VERIFY_PLAN_GROUPS=()
  VERIFY_PLAN_TESTS=()
  VERIFY_PLAN_SYNTAX=()
  VERIFY_PLAN_SCENARIOS=()
  VERIFY_PLAN_REASONS=()
  VERIFY_PLAN_UNRESOLVED=()
}

verification_parse_options() {
  local option
  verification_plan_reset
  while [[ "$#" -gt 0 ]]; do
    option=$1
    shift
    case "${option}" in
      --plan) VERIFY_PLAN_ONLY=1 ;;
      --help|-h) VERIFY_PLAN_HELP=1 ;;
      --full)
        VERIFY_PLAN_FULL=1
        VERIFY_PLAN_EXPLICIT_SCOPE=1
        verification_plan_append VERIFY_REQUESTED_GROUPS full
        ;;
      --base|--group|--scenario)
        if [[ "$#" -eq 0 || -z "$1" || "$1" == --* ]]; then
          verification_plan_error "${option} requires a value"
          return 2
        fi
        case "${option}" in
          --base) VERIFY_PLAN_BASE_REF=$1 ;;
          --group)
            verification_plan_append VERIFY_REQUESTED_GROUPS "$1"
            VERIFY_PLAN_EXPLICIT_SCOPE=1
            ;;
          --scenario)
            verification_plan_append VERIFY_REQUESTED_SCENARIOS "$1"
            VERIFY_PLAN_EXPLICIT_SCOPE=1
            ;;
        esac
        shift
        ;;
      --changed-file)
        VERIFY_PLAN_EXPLICIT_FILES=1
        if [[ "$#" -eq 0 || "$1" == --* ]]; then
          verification_plan_error '--changed-file requires at least one path'
          return 2
        fi
        while [[ "$#" -gt 0 && "$1" != --* ]]; do
          verification_plan_append VERIFY_CHANGED_FILES "$1"
          shift
        done
        ;;
      *) verification_plan_error "unknown option: ${option}"; return 2 ;;
    esac
  done
  if [[ -n "${VERIFY_PLAN_BASE_REF}" && "${VERIFY_PLAN_EXPLICIT_FILES}" == 1 ]]; then
    verification_plan_error '--base and --changed-file are mutually exclusive'
    return 2
  fi
}

verification_validate_path() {
  local file=$1
  case "${file}" in
    ''|/*|-*|..|../*|*/../*|*/..|*$'\n'*|*$'\r'*|*$'\t'*)
      verification_plan_error "unsupported repository path: $(printf '%q' "${file}")"
      return 2
      ;;
  esac
}

verification_collect_changes() {
  local file reference encoded
  # Explicit file mode is useful for deterministic tools/tests; it never implies
  # branch coverage. The complete branch diff remains the review authority.
  if [[ -n "${VERIFY_PLAN_BASE_REF}" ]]; then
    if ! reference=$(git rev-parse --verify --end-of-options "${VERIFY_PLAN_BASE_REF}^{commit}" 2>/dev/null); then
      verification_plan_error "invalid base ref: ${VERIFY_PLAN_BASE_REF}"
      return 2
    fi
    if ! VERIFY_PLAN_BASE=$(git merge-base "${reference}" HEAD); then
      verification_plan_error 'base and HEAD have no merge base'
      return 2
    fi
  else
    if ! VERIFY_PLAN_BASE=$(git rev-parse --verify HEAD); then
      verification_plan_error 'cannot resolve repository HEAD'
      return 2
    fi
  fi
  if [[ "${VERIFY_PLAN_EXPLICIT_FILES}" == 0 ]]; then
    # Encode NUL-delimited output so command substitution preserves path bytes
    # and Git failure is checked before consuming any partial enumeration.
    if ! encoded=$(git diff --no-ext-diff --name-only --no-renames -z "${VERIFY_PLAN_BASE}" -- | base64); then
      verification_plan_error 'cannot inspect repository differences'
      return 2
    fi
    while IFS= read -r -d '' file; do
      verification_plan_append VERIFY_CHANGED_FILES "${file}"
    done < <(printf '%s' "${encoded}" | base64 -d)
    if ! encoded=$(git ls-files --others --exclude-standard -z | base64); then
      verification_plan_error 'cannot inspect untracked repository files'
      return 2
    fi
    while IFS= read -r -d '' file; do
      verification_plan_append VERIFY_CHANGED_FILES "${file}"
    done < <(printf '%s' "${encoded}" | base64 -d)
  fi
  for file in "${VERIFY_CHANGED_FILES[@]}"; do
    verification_validate_path "${file}" || return 2
  done
}

verification_add_group() {
  local group=$1 tests test
  if ! tests=$(verification_group_tests "${group}"); then
    verification_plan_error "unknown or unavailable group: ${group}"
    return 2
  fi
  verification_plan_append VERIFY_PLAN_GROUPS "${group}"
  while IFS= read -r test; do
    [[ -n "${test}" ]] || continue
    verification_plan_append VERIFY_PLAN_TESTS "${test}"
  done <<<"${tests}"
  case "${group}" in
    version) verification_plan_append VERIFY_PLAN_SYNTAX install.sh ;;
    bootstrap) verification_plan_append VERIFY_PLAN_SYNTAX bootstrap.sh ;;
    verification)
      for test in dev/verification/{run,common,planner,selection}.sh; do
        verification_plan_append VERIFY_PLAN_SYNTAX "${test}"
      done
      ;;
    full)
      for test in install.sh uninstall.sh bootstrap.sh dev/verification/{run,common,planner,selection}.sh; do
        verification_plan_append VERIFY_PLAN_SYNTAX "${test}"
      done
      ;;
  esac
}

verification_install_metadata_only() {
  [[ -f "${REPO_ROOT}/install.sh" ]] || return 1
  git cat-file -e "${VERIFY_PLAN_BASE}:install.sh" 2>/dev/null || return 1
  # Only the two fixed header locations are metadata. Similar lines inside a
  # function/heredoc, or moving the constant, must remain behavioral differences.
  diff -q \
    <(git show "${VERIFY_PLAN_BASE}:install.sh" | sed '4s/^# Version: [0-9]\{10\}$/# Version: __VERSION__/; 11s/^readonly SCRIPT_VERSION="[0-9]\{10\}"$/readonly SCRIPT_VERSION="__VERSION__"/') \
    <(sed '4s/^# Version: [0-9]\{10\}$/# Version: __VERSION__/; 11s/^readonly SCRIPT_VERSION="[0-9]\{10\}"$/readonly SCRIPT_VERSION="__VERSION__"/' "${REPO_ROOT}/install.sh") >/dev/null
}

verification_add_test_callers() {
  local helper=$1 candidate content found=0
  local pending=("${helper}") visited=() current item seen
  while [[ "${#pending[@]}" -gt 0 ]]; do
    current=${pending[0]}
    pending=("${pending[@]:1}")
    seen=0
    for item in "${visited[@]}"; do
      [[ "${item}" != "${current}" ]] || seen=1
    done
    [[ "${seen}" == 0 ]] || continue
    visited+=("${current}")
    for candidate in "${REPO_ROOT}"/tests/*.sh; do
      [[ -f "${candidate}" ]] || continue
      content=$(<"${candidate}")
      [[ "${content}" == *"${current##*/}"* ]] || continue
      candidate=${candidate#"${REPO_ROOT}/"}
      [[ "${candidate}" != "${current}" ]] || continue
      case "${candidate}" in
        *_helper.sh) pending+=("${candidate}") ;;
        tests/hy2_instance_acme_runtime.sh)
          verification_plan_append VERIFY_PLAN_REASONS 'container-only HY2 ACME fixture requires a separate Pebble/container run'
          VERIFY_PLAN_RUNTIME_REQUIRED=1
          ;;
        *) verification_plan_append VERIFY_PLAN_TESTS "${candidate}"; found=1 ;;
      esac
    done
  done
  [[ "${found}" == 1 ]] || verification_plan_append VERIFY_PLAN_UNRESOLVED "no host test caller found for ${helper}"
}

verification_classify_file() {
  local file=$1 scenario
  case "${file}" in
    install.sh)
      verification_plan_append VERIFY_PLAN_SYNTAX install.sh
      if verification_install_metadata_only; then
        verification_add_group version || return 2
        verification_plan_append VERIFY_PLAN_REASONS 'install.sh: only script-version metadata changed'
      else
        verification_plan_append VERIFY_PLAN_UNRESOLVED 'install.sh: choose --group and/or --scenario for the affected behavior, or --full'
      fi
      ;;
    bootstrap.sh) verification_add_group bootstrap || return 2 ;;
    tests/hy2_instance_acme_runtime.sh)
      VERIFY_PLAN_RUNTIME_REQUIRED=1
      verification_plan_append VERIFY_PLAN_UNRESOLVED 'HY2 ACME fixture requires a separate Pebble/container run; no registered scenario executes it'
      ;;
    tests/*_helper.sh) verification_add_test_callers "${file}" ;;
    tests/*.sh)
      if [[ -f "${REPO_ROOT}/${file}" ]]; then
        verification_plan_append VERIFY_PLAN_TESTS "${file}"
      else
        verification_plan_append VERIFY_PLAN_UNRESOLVED "removed test: ${file}; choose affected regression group"
      fi
      ;;
    dev/verification/run.sh|dev/verification/planner.sh|dev/verification/selection.sh)
      verification_add_group verification || return 2
      ;;
    dev/verification/remote/scenarios/*.sh)
      scenario=${file##*/}
      verification_plan_append VERIFY_REQUESTED_SCENARIOS "${scenario%.sh}"
      verification_add_group verification || return 2
      ;;
    dev/verification/common.sh|dev/verification/remote/*|dev/verification/docker/*)
      verification_add_group verification || return 2
      verification_plan_append VERIFY_PLAN_UNRESOLVED "${file}: classify host/transport impact with an explicit group/scenario"
      ;;
    README*.md|AGENTS.md|SECURITY.md|docs/*.md|docs/*.txt|skills/*.md|LICENSE|LICENSE.*)
      verification_add_group docs || return 2
      case "${file}" in
        README*.md) verification_add_group version || return 2 ;;
        docs/wiki/Agent-CLI.md|docs/wiki/Agent-Runbook.md)
          verification_plan_append VERIFY_PLAN_TESTS tests/agent_docs_cover_capabilities.sh
          ;;
        docs/wiki/Protocol-Coverage.md)
          verification_plan_append VERIFY_PLAN_TESTS tests/protocol_coverage_contract.sh
          ;;
        docs/wiki/Getting-Started.md) verification_add_group bootstrap || return 2 ;;
      esac
      ;;
    .gitignore|dev/.gitignore) verification_add_group verification || return 2 ;;
    *) verification_plan_append VERIFY_PLAN_UNRESOLVED "${file}: no automatic impact mapping; choose an explicit group/scenario" ;;
  esac
}

verification_build_plan() {
  local group file scenario scenarios
  verification_collect_changes || return 2
  for group in "${VERIFY_REQUESTED_GROUPS[@]}"; do
    verification_add_group "${group}" || return 2
  done
  for file in "${VERIFY_CHANGED_FILES[@]}"; do
    verification_classify_file "${file}" || return 2
  done
  if [[ "${VERIFY_PLAN_FULL}" == 1 ]]; then
    while IFS= read -r scenario; do
      verification_plan_append VERIFY_REQUESTED_SCENARIOS "${scenario}"
    done < <(verification_list_scenarios)
  fi
  if [[ "${#VERIFY_REQUESTED_SCENARIOS[@]}" -gt 0 ]]; then
    if ! scenarios=$(verification_expand_scenarios "${VERIFY_REQUESTED_SCENARIOS[@]}"); then
      verification_plan_error 'invalid Docker scenario selection'
      return 2
    fi
    while IFS= read -r scenario; do
      [[ -n "${scenario}" ]] && VERIFY_PLAN_SCENARIOS+=("${scenario}")
    done <<<"${scenarios}"
    VERIFY_PLAN_MODE=remote
  fi
  if [[ "${#VERIFY_PLAN_UNRESOLVED[@]}" -gt 0 ]]; then
    if [[ "${VERIFY_PLAN_EXPLICIT_SCOPE}" == 1 ]]; then
      verification_plan_append VERIFY_PLAN_REASONS 'unmapped impact assigned to the explicitly selected scope; verify this choice against AGENTS.md 4.2'
    else
      VERIFY_PLAN_STATUS=needs_scope
    fi
  fi
  if [[ "${VERIFY_PLAN_RUNTIME_REQUIRED}" == 1 ]]; then
    VERIFY_PLAN_STATUS=needs_scope
    verification_plan_append VERIFY_PLAN_UNRESOLVED 'automatic execution cannot cover the changed HY2 ACME fixture; run its isolated Pebble/container procedure separately'
  fi
}

verification_print_plan() {
  local item
  printf 'plan_status=%s\nmode=%s\nbase=%s\n' "${VERIFY_PLAN_STATUS}" "${VERIFY_PLAN_MODE}" "${VERIFY_PLAN_BASE}"
  printf 'changed_file_count=%s\nlocal_test_count=%s\nscenario_count=%s\n' \
    "${#VERIFY_CHANGED_FILES[@]}" "${#VERIFY_PLAN_TESTS[@]}" "${#VERIFY_PLAN_SCENARIOS[@]}"
  for item in "${VERIFY_CHANGED_FILES[@]}"; do printf 'file=%s\n' "${item}"; done
  for item in "${VERIFY_PLAN_GROUPS[@]}"; do printf 'group=%s\n' "${item}"; done
  for item in "${VERIFY_PLAN_SYNTAX[@]}"; do printf 'syntax=%s\n' "${item}"; done
  for item in "${VERIFY_PLAN_TESTS[@]}"; do printf 'test=%s\n' "${item}"; done
  for item in "${VERIFY_PLAN_SCENARIOS[@]}"; do printf 'scenario=%s\n' "${item}"; done
  for item in "${VERIFY_PLAN_REASONS[@]}"; do printf 'reason=%s\n' "${item}"; done
  for item in "${VERIFY_PLAN_UNRESOLVED[@]}"; do printf 'unmapped=%s\n' "${item}"; done
}
