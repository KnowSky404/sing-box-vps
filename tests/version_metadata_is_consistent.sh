#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_FILE="${REPO_ROOT}/install.sh"
README_FILE="${REPO_ROOT}/README.md"

install_comment_version=$(sed -n 's/^# Version: \(.\+\)$/\1/p' "${INSTALL_FILE}")
install_constant_version=$(sed -n 's/^readonly SCRIPT_VERSION=\"\([0-9]\+\)\"$/\1/p' "${INSTALL_FILE}")
readme_script_version=$(sed -n 's/^- 脚本版本：`\([0-9]\+\)`$/\1/p' "${README_FILE}" | head -n 1)

if [[ -z "${install_comment_version}" ]]; then
  printf 'missing install.sh version comment\n' >&2
  exit 1
fi

if [[ -z "${install_constant_version}" ]]; then
  printf 'missing install.sh SCRIPT_VERSION constant\n' >&2
  exit 1
fi

if [[ -z "${readme_script_version}" ]]; then
  printf 'missing README.md script version metadata\n' >&2
  exit 1
fi

if [[ ! "${install_comment_version}" =~ ^[0-9]{10}$ ]]; then
  printf 'install.sh version comment must use YYYYMMDDXX format: %s\n' "${install_comment_version}" >&2
  exit 1
fi

if [[ "${install_comment_version}" != "${install_constant_version}" ]]; then
  printf 'install.sh version comment and constant differ: %s vs %s\n' \
    "${install_comment_version}" \
    "${install_constant_version}" >&2
  exit 1
fi

if [[ "${readme_script_version}" != "${install_constant_version}" ]]; then
  printf 'README.md and install.sh SCRIPT_VERSION differ: %s vs %s\n' \
    "${readme_script_version}" \
    "${install_constant_version}" >&2
  exit 1
fi
