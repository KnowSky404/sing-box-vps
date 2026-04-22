#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

list_changed_files() {
  local seen_list=''
  local file
  local files=()

  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    if [[ ",${seen_list}," != *",${file},"* ]]; then
      files+=("${file}")
      seen_list="${seen_list},${file}"
    fi
  done < <(
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  )

  if [[ "${#files[@]}" -gt 0 ]]; then
    printf '%s\n' "${files[@]}"
  fi
}

run_local_tests() {
  local test_file

  if [[ "${VERIFY_SKIP_LOCAL_TESTS:-0}" == "1" ]]; then
    return 0
  fi

  for test_file in tests/verification_*.sh; do
    [[ "${test_file}" == "tests/verification_tests_only_stays_local.sh" ]] && continue
    env -u VERIFY_SKIP_REMOTE VERIFY_SKIP_LOCAL_TESTS=1 bash "${test_file}"
  done
}

resolve_changed_files() {
  if [[ "${1:-}" == "--changed-file" ]]; then
    shift
    if [[ "$#" -gt 0 ]]; then
      printf '%s\n' "$@"
    fi
    return 0
  fi

  list_changed_files
}

emit_remote_payload() {
  local scenario_file

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
  local mode
  local run_dir
  local changed_files=()
  local scenarios=()
  local status=0

  mapfile -t changed_files < <(resolve_changed_files "$@")
  mode=$(determine_verification_mode "${changed_files[@]}")
  run_dir=$(create_run_dir)
  if [[ "${#changed_files[@]}" -gt 0 ]]; then
    printf '%s\n' "${changed_files[@]}" > "${run_dir}/changed-files.txt"
  else
    : > "${run_dir}/changed-files.txt"
  fi
  printf 'mode=%s\n' "${mode}" > "${run_dir}/summary.log"

  printf 'mode=%s\nrun_dir=%s\n' "${mode}" "${run_dir}"
  run_local_tests

  if [[ "${VERIFY_SKIP_REMOTE:-0}" == "1" ]]; then
    printf 'remote execution skipped by VERIFY_SKIP_REMOTE\n' >> "${run_dir}/summary.log"
    exit 0
  fi

  if [[ "${mode}" == "remote" ]]; then
    require_remote_env
    resolve_remote_scenarios "${changed_files[@]}" > "${run_dir}/scenarios.txt"
    mapfile -t scenarios < "${run_dir}/scenarios.txt"
    if emit_remote_payload | ssh "${VERIFY_REMOTE_USER}@${VERIFY_REMOTE_HOST}" 'bash -s -- '"${scenarios[*]}" \
      > "${run_dir}/remote.stdout.log" \
      2> "${run_dir}/remote.stderr.log"; then
      printf 'remote_status=success\n' >> "${run_dir}/summary.log"
      return 0
    else
      status=$?
    fi

    printf 'remote_status=failure\n' >> "${run_dir}/summary.log"
    cat "${run_dir}/remote.stderr.log" >&2
    return "${status}"
  fi

  printf 'remote_status=not_required\n' >> "${run_dir}/summary.log"
}

main "$@"
