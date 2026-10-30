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

printf 'y\n' | bash "${TMP_REPO}/uninstall.sh" >/dev/null 2>&1

if [[ ! -f "${TMP_DIR}/install-args.log" ]]; then
  printf 'expected uninstall.sh to invoke sibling install.sh\n' >&2
  exit 1
fi
[[ "$(cat "${TMP_DIR}/install-args.log")" == '--internal-uninstall-purge --yes' ]]

# Unsupported preservation must never be overridden by a later purge flag or
# an interactive default; reject before delegating to the installed runtime.
rm "${TMP_DIR}/install-args.log"
for args in '--keep-config' '--keep-config --yes' '--keep-config --purge' '--purge --keep-config'; do
  read -r -a argv <<< "${args}"
  if bash "${TMP_REPO}/uninstall.sh" "${argv[@]}" < /dev/null > "${TMP_DIR}/unsupported.log" 2>&1; then
    printf 'unsupported preservation mode unexpectedly succeeded: %s\n' "${args}" >&2
    exit 1
  fi
  grep -Fq '未执行卸载' "${TMP_DIR}/unsupported.log"
  [[ ! -e "${TMP_DIR}/install-args.log" ]]
done

for answer in '' n; do
  printf '%s\n' "${answer}" | bash "${TMP_REPO}/uninstall.sh" > "${TMP_DIR}/cancelled.log" 2>&1
  grep -Fq '已取消卸载' "${TMP_DIR}/cancelled.log"
  [[ ! -e "${TMP_DIR}/install-args.log" ]]
done

bash "${TMP_REPO}/uninstall.sh" --purge --yes > /dev/null
[[ "$(cat "${TMP_DIR}/install-args.log")" == '--internal-uninstall-purge --yes' ]]
printf 'Uninstall confirmation, unsupported mode and purge delegation checks PASSED\n'
