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

rm -f "${SB_WARP_ROUTE_SETTINGS_FILE}" "${SINGBOX_CONFIG_FILE}"

load_warp_route_settings

if [[ "${SB_WARP_ROUTE_MODE}" != "selective" ]]; then
  printf 'expected default warp route mode selective, got %s\n' "${SB_WARP_ROUTE_MODE}" >&2
  exit 1
fi
