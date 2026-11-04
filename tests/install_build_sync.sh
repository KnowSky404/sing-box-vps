#!/usr/bin/env bash

# Routine source/version edits need generated-byte and syntax consistency only.
# Build-tool/manifest changes also require tests/install_build.sh fault injection.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bash "${REPO_ROOT}/scripts/build-install.sh" --check
