#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

assert_mode() {
  local expected=$1
  shift
  local plan
  plan=$(bash "${REPO_ROOT}/dev/verification/run.sh" --plan "$@")
  if ! grep -Fqx "mode=${expected}" <<<"${plan}"; then
    printf 'expected mode=%s for %s, got:\n%s\n' "${expected}" "$*" "${plan}" >&2
    exit 1
  fi
}

assert_mode local --changed-file README.md
assert_mode local --changed-file SECURITY.md
assert_mode local --changed-file AGENTS.md
assert_mode local --changed-file tests/install_hy2_protocol_creates_state.sh
assert_mode local --changed-file tests/mixed_active_state.sh
assert_mode local --changed-file tests/mixed_instance_lifecycle.sh
assert_mode local --changed-file tests/instance_firewall_ledger.sh
assert_mode local --changed-file tests/plain_proxy_structured_store.sh
assert_mode local --changed-file tests/socks_instance_lifecycle.sh
assert_mode local --changed-file tests/http_instance_lifecycle.sh
assert_mode remote --scenario fresh_install_http
assert_mode remote --scenario reconfigure_existing_install

printf 'Verification mode selection passed\n'
