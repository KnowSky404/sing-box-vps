#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"

assert_decision() {
  local expected=$1
  shift
  local actual
  actual=$(determine_verification_mode "$@")
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected %s, got %s for files: %s\n' "${expected}" "${actual}" "$*" >&2
    exit 1
  fi
}

assert_decision remote install.sh
assert_decision remote utils/common.sh
assert_decision local tests/install_hy2_protocol_creates_state.sh
assert_decision local README.md docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md
