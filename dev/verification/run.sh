#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/planner.sh"

run_local_tests() {
  local run_dir=$1 test_file syntax_file status started
  for syntax_file in "${VERIFY_PLAN_SYNTAX[@]}"; do
    bash -n "${REPO_ROOT}/${syntax_file}" || return $?
  done
  if [[ "${VERIFY_SKIP_LOCAL_TESTS:-0}" == 1 ]]; then
    printf 'local_status=skipped\n' >> "${run_dir}/summary.log"
    return 0
  fi
  mkdir -p "${run_dir}/local-tests" || return $?
  printf 'test\tstatus\telapsed_seconds\n' > "${run_dir}/local-tests/results.tsv" || return $?
  for test_file in "${VERIFY_PLAN_TESTS[@]}"; do
    started=${SECONDS}
    printf 'local_test=%s\n' "${test_file}"
    if env -u VERIFY_SKIP_REMOTE VERIFY_SKIP_LOCAL_TESTS=1 bash "${test_file}" \
      > "${run_dir}/local-tests/${test_file##*/}.log" 2>&1; then
      printf '%s\tpassed\t%s\n' "${test_file}" "$((SECONDS - started))" >> "${run_dir}/local-tests/results.tsv"
      printf 'local_test_passed=%s elapsed_seconds=%s\n' "${test_file}" "$((SECONDS - started))"
    else
      status=$?
      printf '%s\tfailed:%s\t%s\n' "${test_file}" "${status}" "$((SECONDS - started))" >> "${run_dir}/local-tests/results.tsv"
      printf 'local_test_failed=%s status=%s\n' "${test_file}" "${status}" >&2
      tail -n 40 "${run_dir}/local-tests/${test_file##*/}.log" >&2
      printf 'local_status=failed\n' >> "${run_dir}/summary.log"
      return "${status}"
    fi
  done
  printf 'local_status=passed\n' >> "${run_dir}/summary.log"
}

emit_remote_payload() {
  local scenario_file registry_json

  # Read metadata from the exact local runtime under test, before injecting it
  # into the container. Sourcing is confined to a subshell and does not run main.
  registry_json=$(source "${REPO_ROOT}/install.sh"; protocol_registry_json) || return 1
  printf 'VERIFY_PROTOCOL_REGISTRY_JSON=%q\n' "${registry_json}"

  cat <<'EOF'
verification_prepare_remote_local_tree() {
  if [[ -n "${VERIFY_REMOTE_INSTALL_SCRIPT:-}" && -f "${VERIFY_REMOTE_INSTALL_SCRIPT}" ]] && \
    [[ -n "${VERIFY_REMOTE_UNINSTALL_SCRIPT:-}" && -f "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" ]]; then
    return 0
  fi

  verification_cleanup_remote_local_tree

  VERIFY_REMOTE_LOCAL_TREE_DIR=$(mktemp -d /tmp/sing-box-vps-verification.XXXXXX)
  VERIFY_REMOTE_INSTALL_SCRIPT="${VERIFY_REMOTE_LOCAL_TREE_DIR}/install.sh"
  VERIFY_REMOTE_UNINSTALL_SCRIPT="${VERIFY_REMOTE_LOCAL_TREE_DIR}/uninstall.sh"

  cat > "${VERIFY_REMOTE_INSTALL_SCRIPT}" <<'VERIFY_REMOTE_INSTALL_SH'
EOF
  cat "${REPO_ROOT}/install.sh"
  cat <<'EOF'
VERIFY_REMOTE_INSTALL_SH

  cat > "${VERIFY_REMOTE_UNINSTALL_SCRIPT}" <<'VERIFY_REMOTE_UNINSTALL_SH'
EOF
  cat "${REPO_ROOT}/uninstall.sh"
  cat <<'EOF'
VERIFY_REMOTE_UNINSTALL_SH

  chmod +x "${VERIFY_REMOTE_INSTALL_SCRIPT}" "${VERIFY_REMOTE_UNINSTALL_SCRIPT}"
  export VERIFY_REMOTE_LOCAL_TREE_DIR VERIFY_REMOTE_INSTALL_SCRIPT VERIFY_REMOTE_UNINSTALL_SCRIPT
}

verification_cleanup_remote_local_tree() {
  if [[ -n "${VERIFY_REMOTE_LOCAL_TREE_DIR:-}" && -d "${VERIFY_REMOTE_LOCAL_TREE_DIR}" ]]; then
    rm -rf "${VERIFY_REMOTE_LOCAL_TREE_DIR}"
    unset VERIFY_REMOTE_LOCAL_TREE_DIR VERIFY_REMOTE_INSTALL_SCRIPT VERIFY_REMOTE_UNINSTALL_SCRIPT
  fi
}

EOF

  for scenario_file in "${REPO_ROOT}"/dev/verification/remote/scenarios/*.sh; do
    [[ -f "${scenario_file}" ]] || continue
    cat "${scenario_file}"
    printf '\n'
  done

  cat "${REPO_ROOT}/dev/verification/remote/entrypoint.sh"
}

main() {
  local run_dir status=0 artifact_status=1

  cd "${REPO_ROOT}"
  verification_parse_options "$@" || return 2
  if [[ "${VERIFY_PLAN_HELP}" == 1 ]]; then
    verification_usage
    return 0
  fi
  verification_build_plan || return 2
  verification_print_plan
  if [[ "${VERIFY_PLAN_ONLY}" == 1 ]]; then
    return 0
  fi
  if [[ "${VERIFY_PLAN_STATUS}" != ready ]]; then
    verification_plan_error 'impact needs an explicit --group and/or --scenario, or --full; inspect --plan first'
    return 2
  fi

  run_dir=$(create_run_dir)
  verification_print_plan > "${run_dir}/plan.txt"
  : > "${run_dir}/changed-files.txt"
  if [[ "${#VERIFY_CHANGED_FILES[@]}" -gt 0 ]]; then
    printf '%s\n' "${VERIFY_CHANGED_FILES[@]}" > "${run_dir}/changed-files.txt"
  fi
  : > "${run_dir}/scenarios.txt"
  if [[ "${#VERIFY_PLAN_SCENARIOS[@]}" -gt 0 ]]; then
    printf '%s\n' "${VERIFY_PLAN_SCENARIOS[@]}" > "${run_dir}/scenarios.txt"
  fi
  printf 'mode=%s\n' "${VERIFY_PLAN_MODE}" > "${run_dir}/summary.log"
  printf 'run_dir=%s\n' "${run_dir}"
  run_local_tests "${run_dir}" || return $?

  if [[ "${VERIFY_SKIP_REMOTE:-0}" == 1 ]]; then
    printf 'remote execution skipped by VERIFY_SKIP_REMOTE\nremote_status=skipped\n' >> "${run_dir}/summary.log"
    return 0
  fi
  if [[ "${VERIFY_PLAN_MODE}" == remote ]]; then
    require_docker_env || return $?
    printf 'remote_target=docker:%s\n' "${VERIFY_DOCKER_CONTAINER}"
    printf 'remote_target=docker:%s\n' "${VERIFY_DOCKER_CONTAINER}" >> "${run_dir}/summary.log"
    trap 'require_docker_cleanup' EXIT
    if { trap - EXIT; emit_remote_payload; } | docker exec -i "${VERIFY_DOCKER_CONTAINER}" bash -s -- "${VERIFY_PLAN_SCENARIOS[@]}" \
      > "${run_dir}/remote.stdout.log" \
      2> "${run_dir}/remote.stderr.log"; then
      status=0
    else
      status=$?
    fi
    if extract_remote_artifacts "${run_dir}/remote.stdout.log" "${run_dir}"; then
      artifact_status=0
      printf 'remote_artifacts=extracted\n' >> "${run_dir}/summary.log"
    else
      artifact_status=$?
      printf 'remote_artifacts=%s\n' "${artifact_status}" >> "${run_dir}/summary.log"
    fi
    if [[ "${status}" == 0 && "${artifact_status}" != 0 ]]; then
      printf 'remote_status=failure\n' >> "${run_dir}/summary.log"
      printf 'remote artifact bundle missing or invalid\n' >&2
      return 24
    fi
    if [[ "${status}" == 0 ]]; then
      printf 'remote_status=success\n' >> "${run_dir}/summary.log"
      return 0
    fi
    printf 'remote_status=failure\n' >> "${run_dir}/summary.log"
    cat "${run_dir}/remote.stderr.log" >&2
    return "${status}"
  fi
  printf 'remote_status=not_required\n' >> "${run_dir}/summary.log"
}

main "$@"
