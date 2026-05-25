#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

if [[ "$(prompt_instance_outbound_policy "策略" "warp" </dev/null)" != "warp" ]]; then
  printf 'expected non-interactive prompt to keep current warp policy\n' >&2
  exit 1
fi

if [[ "$(prompt_instance_outbound_policy "策略" "invalid" </dev/null)" != "default" ]]; then
  printf 'expected non-interactive prompt to normalize invalid policy to default\n' >&2
  exit 1
fi
