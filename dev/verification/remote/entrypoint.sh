#!/usr/bin/env bash

set -euo pipefail

LOCK_DIR=/tmp/sing-box-vps-verification.lock
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  printf 'verification host is busy\n' >&2
  exit 32
fi

cleanup() {
  rmdir "${LOCK_DIR}"
}
trap cleanup EXIT

hostname
