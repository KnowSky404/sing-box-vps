#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUBMAN_SOURCE_DIR=${SUBMAN_SOURCE_DIR:-/root/Clouds/SubMan}
SUBMAN_APP_ARTIFACT_DIR=${SUBMAN_APP_ARTIFACT_DIR:-$(mktemp -d /tmp/sbv-subman-app.XXXXXXXX)}
for dependency in git tar bun node jq openssl curl; do
  command -v "${dependency}" >/dev/null || { printf 'missing integration dependency: %s\n' "${dependency}" >&2; exit 1; }
done
[[ -f "${SUBMAN_SOURCE_DIR}/package.json" && -d "${SUBMAN_SOURCE_DIR}/node_modules/miniflare" ]] || {
  printf 'set SUBMAN_SOURCE_DIR to a SubMan checkout with its locked dependencies installed\n' >&2
  exit 1
}
mkdir -p "${SUBMAN_APP_ARTIFACT_DIR}/app"
SUBMAN_SOURCE_SHA=$(git -C "${SUBMAN_SOURCE_DIR}" rev-parse HEAD)
# Build committed application sources in isolation; keep the source checkout and
# all real credentials untouched. No dependency installation or deployment occurs.
git -C "${SUBMAN_SOURCE_DIR}" archive HEAD | tar -xf - -C "${SUBMAN_APP_ARTIFACT_DIR}/app"
mkdir -p "${SUBMAN_APP_ARTIFACT_DIR}/app/node_modules"
for dependency_path in "${SUBMAN_SOURCE_DIR}"/node_modules/* "${SUBMAN_SOURCE_DIR}"/node_modules/.[!.]*; do
  [[ -e "${dependency_path}" ]] || continue
  case "${dependency_path##*/}" in .vite*) continue ;; esac
  ln -s "${dependency_path}" "${SUBMAN_APP_ARTIFACT_DIR}/app/node_modules/${dependency_path##*/}"
done
(
  cd "${SUBMAN_APP_ARTIFACT_DIR}/app"
  env -u GITHUB_TOKEN -u SUBMAN_API_TOKEN bun run prepare
  env -u GITHUB_TOKEN -u SUBMAN_API_TOKEN bun run build
) > "${SUBMAN_APP_ARTIFACT_DIR}/build.log" 2>&1 || {
  tail -n 40 "${SUBMAN_APP_ARTIFACT_DIR}/build.log" >&2
  exit 1
}
export SUBMAN_SOURCE_SHA SUBMAN_APP_ARTIFACT_DIR
node "${TESTS_DIR}/subman_app_test_helper.mjs"
