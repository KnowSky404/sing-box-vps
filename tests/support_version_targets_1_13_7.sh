#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_FILE="${REPO_ROOT}/install.sh"
MAIN_FILE="${REPO_ROOT}/main.sh"
README_FILE="${REPO_ROOT}/README.md"
EXPECTED_VERSION="1.13.7"

install_support_version=$(sed -n 's/^readonly SB_SUPPORT_MAX_VERSION="\([^"]\+\)"$/\1/p' "${INSTALL_FILE}")
main_support_version=$(sed -n 's/^readonly SB_SUPPORT_MAX_VERSION="\([^"]\+\)"$/\1/p' "${MAIN_FILE}")

if [[ "${install_support_version}" != "${EXPECTED_VERSION}" ]]; then
  printf 'install.sh SB_SUPPORT_MAX_VERSION expected %s, got %s\n' "${EXPECTED_VERSION}" "${install_support_version}" >&2
  exit 1
fi

if [[ "${main_support_version}" != "${EXPECTED_VERSION}" ]]; then
  printf 'main.sh SB_SUPPORT_MAX_VERSION expected %s, got %s\n' "${EXPECTED_VERSION}" "${main_support_version}" >&2
  exit 1
fi

if ! grep -q "当前适配：${EXPECTED_VERSION}" "${README_FILE}"; then
  printf 'README.md should mention current supported version %s\n' "${EXPECTED_VERSION}" >&2
  exit 1
fi
