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

if [[ "${SB_HY2_MASQUERADE}" != "https://www.cloudflare.com" ]]; then
  printf 'expected hy2 default masquerade to be https://www.cloudflare.com, got %s\n' "${SB_HY2_MASQUERADE}" >&2
  exit 1
fi
