#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

REMOTE_DIR="${TMP_DIR}/remote"
PROJECT_DIR="${TMP_DIR}/project"
SBV_BIN_PATH="${TMP_DIR}/bin/sbv"

mkdir -p "${REMOTE_DIR}" "${PROJECT_DIR}" "$(dirname "${SBV_BIN_PATH}")"
cp "${REPO_ROOT}/uninstall.sh" "${REMOTE_DIR}/uninstall.sh"

cat > "${SBV_BIN_PATH}" <<EOF
#!/usr/bin/env bash

printf '%s\n' "\$*" > "${TMP_DIR}/install-args.log"
EOF
chmod +x "${REMOTE_DIR}/uninstall.sh" "${SBV_BIN_PATH}"

SB_PROJECT_DIR="${PROJECT_DIR}" SBV_BIN_PATH="${SBV_BIN_PATH}" bash "${REMOTE_DIR}/uninstall.sh" --yes >/dev/null 2>&1

if [[ ! -f "${TMP_DIR}/install-args.log" ]]; then
  printf 'expected standalone uninstall.sh to invoke installed sbv fallback\n' >&2
  exit 1
fi

if [[ "$(cat "${TMP_DIR}/install-args.log")" != "--internal-uninstall-purge --yes" ]]; then
  printf 'unexpected sbv arguments: %s\n' "$(cat "${TMP_DIR}/install-args.log")" >&2
  exit 1
fi
