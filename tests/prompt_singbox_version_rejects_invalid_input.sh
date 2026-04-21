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

output=$(prompt_singbox_version <<'EOF' 2>&1
1
v1.13.9
EOF
)

if [[ "${SB_VERSION}" != "1.13.9" ]]; then
  printf 'expected SB_VERSION to normalize to 1.13.9, got: %s\n' "${SB_VERSION}" >&2
  exit 1
fi

if [[ "${output}" != *"无效版本号: 1"* ]]; then
  printf 'expected invalid version warning in output, got:\n%s\n' "${output}" >&2
  exit 1
fi
