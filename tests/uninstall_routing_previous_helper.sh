#!/usr/bin/env bash

set -euo pipefail

# Build actual private snapshot material in the fixed sibling location. The
# journal describes a completed transaction; no service or remote API is used.
create_uninstall_routing_previous_snapshot() {
  local fingerprint external_fingerprint
  [[ ! -e "${SB_ROUTING_TRANSACTION_DIR}" && ! -L "${SB_ROUTING_TRANSACTION_DIR}" &&
     ! -e "${SB_ROUTING_PREVIOUS_DIR}" && ! -L "${SB_ROUTING_PREVIOUS_DIR}" ]] || return 1
  fingerprint=$(routing_state_fingerprint) || return 1
  external_fingerprint=$(routing_state_fingerprint external) || return 1
  mkdir -m 700 -- "${SB_ROUTING_TRANSACTION_DIR}" || return 1
  create_managed_state_snapshot "${SB_ROUTING_TRANSACTION_DIR}/snapshot" >/dev/null || return 1
  jq -n --arg fingerprint "${fingerprint}" --arg external "${external_fingerprint}" \
    '{schema_version:1,phase:"committed",before_active:false,service_changed:true,
      before_fingerprint:$fingerprint,external_fingerprint:$external,after_fingerprint:$fingerprint}' \
    > "${SB_ROUTING_TRANSACTION_DIR}/transaction.json" || return 1
  chmod 600 "${SB_ROUTING_TRANSACTION_DIR}/transaction.json" || return 1
  routing_transaction_keep_previous || return 1
  routing_transaction_valid "${SB_ROUTING_PREVIOUS_DIR}"
}
