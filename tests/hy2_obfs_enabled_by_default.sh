#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

set_protocol_defaults "hy2"
ensure_hy2_obfs_settings

if [[ "${SB_HY2_OBFS_ENABLED}" != "y" ]]; then
  printf 'expected hy2 obfs to be enabled by default, got %s\n' "${SB_HY2_OBFS_ENABLED}" >&2
  exit 1
fi

if [[ "${SB_HY2_OBFS_TYPE}" != "salamander" ]]; then
  printf 'expected default hy2 obfs type to be salamander, got %s\n' "${SB_HY2_OBFS_TYPE}" >&2
  exit 1
fi

if [[ -z "${SB_HY2_OBFS_PASSWORD}" ]]; then
  printf 'expected default hy2 obfs password to be generated\n' >&2
  exit 1
fi
