#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SBV_TEST_MODE=1
source "${REPO_ROOT}/install.sh"

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

hostname() {
  printf 'test-host'
}

migrate_vless_reality_state_to_instances_if_needed() {
  return 0
}

load_vless_reality_protocol_state() {
  return 0
}

validate_vless_reality_instance_id() {
  return 0
}

vless_reality_instance_id_exists() {
  return 1
}

validate_port_number() {
  return 0
}

port_in_configured_protocol_state() {
  return 1
}

check_port_conflict() {
  return 0
}

load_vless_reality_instance_state() {
  SB_SNI="www.cloudflare.com"
  return 0
}

prompt_reality_sni_for_new_instance() {
  SB_SNI="${1}"
}

prompt_vless_reality_rate_limit_fields() {
  SB_VLESS_RATE_LIMIT_UP_MBPS="40"
  SB_VLESS_RATE_LIMIT_DOWN_MBPS="100"
}

duplicate_check_seen="n"

vless_reality_bandwidth_profile_exists() {
  if [[ "${SB_NODE_NAME}" != "test-host-vless" ]]; then
    printf 'FAIL: expected default node name test-host-vless, got %s\n' "${SB_NODE_NAME}" >&2
    exit 1
  fi
  if [[ "$1" != "40" || "$2" != "100" || "$3" != "${SB_VLESS_INSTANCE_ID}" ]]; then
    printf 'FAIL: unexpected duplicate check args: up=%s down=%s exclude=%s\n' "$1" "$2" "$3" >&2
    exit 1
  fi
  duplicate_check_seen="y"
  return 0
}

ensure_vless_reality_materials() {
  printf 'FAIL: duplicate bandwidth profile should cancel before material generation\n' >&2
  exit 1
}

prompt_vless_reality_instance_create <<'EOF'


445
EOF

if [[ "${duplicate_check_seen}" != "y" ]]; then
  printf 'FAIL: duplicate bandwidth check was not reached\n' >&2
  exit 1
fi
