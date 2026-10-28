#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_FILE="${REPO_ROOT}/install.sh"
README_FILE="${REPO_ROOT}/README.md"
EXPECTED_VERSION="1.14.2"

install_support_version=$(sed -n 's/^readonly SB_SUPPORT_MAX_VERSION="\([^\"]*\)"$/\1/p' "${INSTALL_FILE}")
[[ "${install_support_version}" == "${EXPECTED_VERSION}" ]] || {
  printf 'install.sh SB_SUPPORT_MAX_VERSION expected %s, got %s\n' "${EXPECTED_VERSION}" "${install_support_version}" >&2
  exit 1
}

grep -Fq "sing-box 适配版本：\`${EXPECTED_VERSION}\`" "${README_FILE}" || {
  printf 'README.md should mention current supported version %s\n' "${EXPECTED_VERSION}" >&2
  exit 1
}
