#!/usr/bin/env bash

# Assemble the standalone runtime without executing any source module.
set -euo pipefail

build_error() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

main() (
  local check_only=n repo_root source_dir manifest output entry module existing
  local staging=''
  local modules=() source_files=()

  case "${1:-}" in
    --check) check_only=y; shift ;;
    --help|-h)
      printf '%s\n' \
        'Usage: bash scripts/build-install.sh [--check]' \
        'Build install.sh from src/install/manifest.txt without executing modules.' \
        '--check validates the sources and reports a stale artifact without changing it.'
      return 0
      ;;
  esac
  if [[ "$#" -ne 0 ]]; then
    build_error 'expected no arguments or --check'
    return 2
  fi

  repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P) || return 1
  source_dir="${repo_root}/src/install"
  manifest="${source_dir}/manifest.txt"
  output="${repo_root}/install.sh"
  if [[ -L "${repo_root}/src" || -L "${source_dir}" || ! -d "${source_dir}" ||
        -L "${manifest}" || ! -f "${manifest}" ]]; then
    build_error 'src/install and its manifest must be local regular paths'
    return 1
  fi
  if [[ -L "${output}" || ( -e "${output}" && ! -f "${output}" ) ]]; then
    build_error 'install.sh must be a regular file, not a symlink or directory'
    return 1
  fi

  while IFS= read -r entry || [[ -n "${entry}" ]]; do
    case "${entry}" in ''|\#*) continue ;; esac
    if [[ ! "${entry}" =~ ^[0-9]{2}-[a-z][a-z0-9-]*\.sh$ ]]; then
      build_error "invalid module name in manifest: ${entry}"
      return 1
    fi
    for existing in "${modules[@]}"; do
      if [[ "${existing}" == "${entry}" ]]; then
        build_error "duplicate module in manifest: ${entry}"
        return 1
      fi
    done
    module="${source_dir}/${entry}"
    if [[ -L "${module}" || ! -f "${module}" ]]; then
      build_error "missing or non-regular module: ${entry}"
      return 1
    fi
    bash -n -- "${module}" || return 1
    modules+=("${entry}")
    source_files+=("${module}")
  done < "${manifest}"
  if [[ "${#modules[@]}" -eq 0 ]]; then
    build_error 'manifest has no modules'
    return 1
  fi

  # Refuse forgotten modules instead of silently publishing an incomplete build.
  shopt -s nullglob dotglob
  for module in "${source_dir}"/*.sh; do
    entry=${module##*/}
    existing=''
    for existing in "${modules[@]}"; do
      [[ "${entry}" != "${existing}" ]] || break
    done
    if [[ "${entry}" != "${existing}" ]]; then
      build_error "module is not listed in manifest: ${entry}"
      return 1
    fi
  done

  cleanup_build() {
    if [[ -n "${staging}" && -e "${staging}" ]] && ! rm -f -- "${staging}"; then
      printf 'WARN: could not remove build staging file: %s\n' "${staging}" >&2
    fi
  }
  trap cleanup_build EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "${check_only}" == y ]]; then
    staging=$(mktemp "${TMPDIR:-/tmp}/sing-box-vps-build.XXXXXXXX") || return 1
  else
    staging=$(mktemp "${repo_root}/.install.sh.build.XXXXXXXX") || return 1
  fi
  cat -- "${source_files[@]}" > "${staging}" || return 1
  bash -n -- "${staging}" || return 1

  if [[ -f "${output}" ]] && cmp -s -- "${staging}" "${output}"; then
    printf 'install.sh matches %s source modules.\n' "${#modules[@]}"
    return 0
  fi
  if [[ "${check_only}" == y ]]; then
    build_error 'install.sh is missing or stale; run bash scripts/build-install.sh'
    return 1
  fi

  if [[ -f "${output}" ]]; then
    chmod --reference="${output}" -- "${staging}" || return 1
  else
    chmod 755 -- "${staging}" || return 1
  fi
  mv -f -- "${staging}" "${output}" || return 1
  staging=''
  printf 'Built install.sh from %s source modules.\n' "${#modules[@]}"
)

main "$@"
