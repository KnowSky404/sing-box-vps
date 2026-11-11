#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
[[ -x "${core}" ]] || { printf 'real sing-box core required\n' >&2; exit 1; }
# Root-owned runtime fixtures need local ownership semantics; all are disposable
# inside this network-isolated container. Only stdout leaves the container.
docker run --rm --network none --cap-add NET_ADMIN \
  --mount "type=bind,src=${REPO_ROOT},dst=/repo,readonly" \
  --mount "type=bind,src=${core},dst=/core,readonly" \
  "${VERIFY_DOCKER_IMAGE:-sing-box-vps-verify:2026091501-ssh}" \
  python3 /repo/tests/media_warp_runtime.py
