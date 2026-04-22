#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if VERIFY_SKIP_LOCAL_TESTS=1 bash "${REPO_ROOT}/dev/verification/run.sh" --changed-file install.sh > /tmp/verification.out 2>/tmp/verification.err; then
  printf 'expected remote verification to fail without host configuration\n' >&2
  exit 1
fi

grep -Fq 'VERIFY_REMOTE_HOST_ALIAS or VERIFY_REMOTE_HOST is required' /tmp/verification.err
