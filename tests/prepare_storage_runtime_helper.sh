#!/usr/bin/env bash

set -euo pipefail

# Called only after the caller's explicit disposable-container guards. Move the
# pre-provisioned real core into the production layout before exercising it.
prepare_storage_runtime_core() {
  [[ "${EUID}" == 0 && -f /.dockerenv && "$(cat /proc/1/comm)" == systemd ]] || return 64
  storage_initialize || return 1
  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    [[ -x "${SINGBOX_LINK_PATH}" && -f "${SINGBOX_LINK_PATH}" && ! -L "${SINGBOX_LINK_PATH}" ]] || return 1
    cp -p -- "${SINGBOX_LINK_PATH}" "${SINGBOX_BIN_PATH}" || return 1
    # A bind-mounted global core must instead be prepared at SINGBOX_BIN_PATH
    # by the harness; never hide a failed unlink or override production guards.
    rm -- "${SINGBOX_LINK_PATH}" || return 1
  fi
  storage_publish_system_links sing-box || return 1
}
