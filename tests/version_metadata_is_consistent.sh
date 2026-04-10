#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_FILE="${REPO_ROOT}/install.sh"
MAIN_FILE="${REPO_ROOT}/main.sh"

install_comment_version=$(sed -n 's/^# Version: \(.\+\)$/\1/p' "${INSTALL_FILE}")
install_constant_version=$(sed -n 's/^readonly SCRIPT_VERSION=\"\([0-9]\+\)\"$/\1/p' "${INSTALL_FILE}")
main_constant_version=$(sed -n 's/^readonly SCRIPT_VERSION=\"\([0-9]\+\)\"$/\1/p' "${MAIN_FILE}")

if [[ -z "${install_comment_version}" ]]; then
  printf 'missing install.sh version comment\n' >&2
  exit 1
fi

if [[ -z "${install_constant_version}" ]]; then
  printf 'missing install.sh SCRIPT_VERSION constant\n' >&2
  exit 1
fi

if [[ -z "${main_constant_version}" ]]; then
  printf 'missing main.sh SCRIPT_VERSION constant\n' >&2
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

if [[ "${main_constant_version}" != "${install_constant_version}" ]]; then
  printf 'main.sh and install.sh SCRIPT_VERSION differ: %s vs %s\n' \
    "${main_constant_version}" \
    "${install_constant_version}" >&2
  exit 1
fi
