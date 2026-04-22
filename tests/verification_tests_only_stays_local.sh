#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

output=$(
  VERIFY_SKIP_LOCAL_TESTS=1 VERIFY_SKIP_REMOTE=1 \
    bash "${REPO_ROOT}/dev/verification/run.sh" \
    --changed-file tests/install_hy2_protocol_creates_state.sh
)

grep -Fq 'mode=local' <<<"${output}"
