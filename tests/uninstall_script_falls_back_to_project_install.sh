#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

REMOTE_DIR="${TMP_DIR}/remote"
PROJECT_DIR="${TMP_DIR}/project"

mkdir -p "${REMOTE_DIR}" "${PROJECT_DIR}"
cp "${REPO_ROOT}/uninstall.sh" "${REMOTE_DIR}/uninstall.sh"

cat > "${PROJECT_DIR}/install.sh" <<EOF
#!/usr/bin/env bash

printf '%s\n' "\$*" > "${TMP_DIR}/install-args.log"
EOF
chmod +x "${REMOTE_DIR}/uninstall.sh" "${PROJECT_DIR}/install.sh"

SB_PROJECT_DIR="${PROJECT_DIR}" bash "${REMOTE_DIR}/uninstall.sh" --yes >/dev/null 2>&1

if [[ ! -f "${TMP_DIR}/install-args.log" ]]; then
  printf 'expected standalone uninstall.sh to invoke project install.sh fallback\n' >&2
  exit 1
fi

if [[ "$(cat "${TMP_DIR}/install-args.log")" != "--internal-uninstall-purge --yes" ]]; then
  printf 'unexpected install.sh arguments: %s\n' "$(cat "${TMP_DIR}/install-args.log")" >&2
  exit 1
fi
