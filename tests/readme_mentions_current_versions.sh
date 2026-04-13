#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_FILE="${REPO_ROOT}/install.sh"
README_FILE="${REPO_ROOT}/README.md"

script_version=$(sed -n 's/^readonly SCRIPT_VERSION="\([0-9]\+\)"$/\1/p' "${INSTALL_FILE}")
support_version=$(sed -n 's/^readonly SB_SUPPORT_MAX_VERSION="\([^"]\+\)"$/\1/p' "${INSTALL_FILE}")

if [[ -z "${script_version}" || -z "${support_version}" ]]; then
  printf 'failed to extract version metadata from install.sh\n' >&2
  exit 1
fi

if ! grep -q "脚本版本：\`${script_version}\`" "${README_FILE}"; then
  printf 'README.md should mention script version %s\n' "${script_version}" >&2
  exit 1
fi

if ! grep -q "sing-box 适配版本：\`${support_version}\`" "${README_FILE}"; then
  printf 'README.md should mention supported sing-box version %s\n' "${support_version}" >&2
  exit 1
fi
