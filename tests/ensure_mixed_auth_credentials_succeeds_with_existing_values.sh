#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

SB_MIXED_AUTH_ENABLED="y"
SB_MIXED_USERNAME="proxy_501265"
SB_MIXED_PASSWORD="e9dd334d6630fb62"

ensure_mixed_auth_credentials

if [[ "${SB_MIXED_USERNAME}" != "proxy_501265" ]]; then
  printf 'expected mixed username to remain unchanged, got %s\n' "${SB_MIXED_USERNAME}" >&2
  exit 1
fi

if [[ "${SB_MIXED_PASSWORD}" != "e9dd334d6630fb62" ]]; then
  printf 'expected mixed password to remain unchanged, got %s\n' "${SB_MIXED_PASSWORD}" >&2
  exit 1
fi
