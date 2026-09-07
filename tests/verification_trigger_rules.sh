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
assert_decision remote uninstall.sh
assert_decision remote utils/common.sh
assert_decision remote configs/example.json
assert_decision local tests/install_hy2_protocol_creates_state.sh
assert_decision local tests/mixed_active_state.sh
assert_decision local tests/mixed_instance_lifecycle.sh
assert_decision local tests/mixed_instance_lifecycle_runtime.sh
assert_decision local tests/mixed_structured_takeover.sh
assert_decision local tests/instance_firewall_ledger.sh
assert_decision local tests/mixed_instance_menu.sh
assert_decision local tests/plain_proxy_structured_store.sh
assert_decision local tests/socks_instance_lifecycle.sh
assert_decision local tests/socks_instance_lifecycle_runtime.sh
assert_decision local tests/socks_instance_menu.sh
assert_decision local tests/socks_structured_takeover.sh
assert_decision local tests/socks_export_client.sh
assert_decision local tests/plain_proxy_share_links.sh
assert_decision local tests/plain_proxy_share_runtime.sh
assert_decision local docs/superpowers/specs/2026-04-22-remote-validation-workflow-design.md
