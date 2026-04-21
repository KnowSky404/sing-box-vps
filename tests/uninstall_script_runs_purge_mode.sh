#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TMP_REPO="${TMP_DIR}/repo"
mkdir -p "${TMP_REPO}"
cp "${REPO_ROOT}/uninstall.sh" "${TMP_REPO}/uninstall.sh"

cat > "${TMP_REPO}/install.sh" <<EOF
#!/usr/bin/env bash

printf '%s\n' "\$*" > "${TMP_DIR}/install-args.log"
EOF
chmod +x "${TMP_REPO}/install.sh" "${TMP_REPO}/uninstall.sh"

printf '\ny\n' | bash "${TMP_REPO}/uninstall.sh" >/dev/null 2>&1

if [[ ! -f "${TMP_DIR}/install-args.log" ]]; then
  printf 'expected uninstall.sh to invoke sibling install.sh\n' >&2
  exit 1
fi

if [[ "$(cat "${TMP_DIR}/install-args.log")" != "--internal-uninstall-purge --yes" ]]; then
  printf 'unexpected install.sh arguments: %s\n' "$(cat "${TMP_DIR}/install-args.log")" >&2
  exit 1
fi
