#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT

fail() {
  printf 'install build test failed: %s\n' "$*" >&2
  [[ ! -f "${TMP_DIR}/build.log" ]] || cat "${TMP_DIR}/build.log" >&2
  exit 1
}

bash "${REPO_ROOT}/scripts/build-install.sh" --check > "${TMP_DIR}/build.log" 2>&1 || fail 'committed installer is stale'

TEMPLATE="${TMP_DIR}/template"
mkdir -p "${TEMPLATE}/scripts" "${TEMPLATE}/src/install" "${TMP_DIR}/other cwd"
cp "${REPO_ROOT}/scripts/build-install.sh" "${TEMPLATE}/scripts/build-install.sh"
cat > "${TEMPLATE}/src/install/00-preamble.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

printf 'source was executed\n' > "${BUILD_EXECUTION_MARKER:?}"
EOF
cat > "${TEMPLATE}/src/install/10-functions.sh" <<'EOF'

demo() {
  printf '%s\n' 'first version'
}
EOF
cat > "${TEMPLATE}/src/install/20-entrypoint.sh" <<'EOF'

[[ "${BASH_SOURCE[0]}" != "$0" ]] || demo
EOF
cat > "${TEMPLATE}/src/install/manifest.txt" <<'EOF'
# Explicit order, with comments and blank lines permitted.
00-preamble.sh

10-functions.sh
20-entrypoint.sh
EOF
cat > "${TMP_DIR}/expected.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

printf 'source was executed\n' > "${BUILD_EXECUTION_MARKER:?}"

demo() {
  printf '%s\n' 'first version'
}

[[ "${BASH_SOURCE[0]}" != "$0" ]] || demo
EOF

export BUILD_EXECUTION_MARKER="${TMP_DIR}/source-executed"
FIXTURE=''
new_fixture() {
  FIXTURE="${TMP_DIR}/$1"
  cp -R "${TEMPLATE}" "${FIXTURE}"
}

run_build() (
  cd "${TMP_DIR}/other cwd"
  bash "${FIXTURE}/scripts/build-install.sh" "$@" > "${TMP_DIR}/build.log" 2>&1
)

root_entries() {
  find "${FIXTURE}" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort
}

assert_rejected() {
  local label=$1 before_metadata before_entries
  cp "${FIXTURE}/install.sh" "${TMP_DIR}/before.sh"
  before_metadata=$(stat -c '%i:%a:%s:%Y' "${FIXTURE}/install.sh")
  before_entries=$(root_entries)
  if run_build; then
    fail "${label} was accepted"
  fi
  cmp -s "${TMP_DIR}/before.sh" "${FIXTURE}/install.sh" || fail "${label} changed the installer"
  [[ "$(stat -c '%i:%a:%s:%Y' "${FIXTURE}/install.sh")" == "${before_metadata}" ]] || fail "${label} replaced or changed installer metadata"
  [[ "$(root_entries)" == "${before_entries}" ]] || fail "${label} left staging files"
  [[ ! -e "${BUILD_EXECUTION_MARKER}" ]] || fail "${label} executed source or manifest content"
}

new_fixture 'repository with spaces'
run_build || fail 'initial generation from a different cwd'
cmp -s "${TMP_DIR}/expected.sh" "${FIXTURE}/install.sh" || fail 'module contents or order changed'
[[ "$(stat -c '%a' "${FIXTURE}/install.sh")" == 755 ]] || fail 'new installer is not executable'
[[ ! -e "${BUILD_EXECUTION_MARKER}" ]] || fail 'generation executed source'
chmod 750 "${FIXTURE}/install.sh"
unchanged_metadata=$(stat -c '%i:%a:%s:%Y' "${FIXTURE}/install.sh")
run_build || fail 'repeat generation'
run_build --check || fail 'fresh installer check'
[[ "$(stat -c '%i:%a:%s:%Y' "${FIXTURE}/install.sh")" == "${unchanged_metadata}" ]] || fail 'unchanged build or check rewrote the installer'

sed -i "s/first version/second version/" "${FIXTURE}/src/install/10-functions.sh"
before_tree=$(find "${FIXTURE}" -printf '%P %y %s %T@\n' | LC_ALL=C sort)
if run_build --check; then
  fail 'stale installer passed --check'
fi
[[ "$(find "${FIXTURE}" -printf '%P %y %s %T@\n' | LC_ALL=C sort)" == "${before_tree}" ]] || fail '--check wrote into the repository'
cmp -s "${TMP_DIR}/expected.sh" "${FIXTURE}/install.sh" || fail '--check changed stale installer'
run_build || fail 'regeneration after source edit'
run_build --check || fail 'regenerated installer check'
[[ "$(stat -c '%a' "${FIXTURE}/install.sh")" == 750 ]] || fail 'regeneration lost existing permissions'
[[ ! -e "${BUILD_EXECUTION_MARKER}" ]] || fail 'checking or regenerating executed source'

# Invalid source trees must never publish a partial installer or retain staging.
cp "${TMP_DIR}/expected.sh" "${TEMPLATE}/install.sh"
chmod 751 "${TEMPLATE}/install.sh"

new_fixture missing-module
rm "${FIXTURE}/src/install/10-functions.sh"
assert_rejected 'missing module'

new_fixture duplicate-module
printf '%s\n' '10-functions.sh' >> "${FIXTURE}/src/install/manifest.txt"
assert_rejected 'duplicate module'

new_fixture empty-manifest
: > "${FIXTURE}/src/install/manifest.txt"
assert_rejected 'empty manifest'

new_fixture traversal
printf '%s\n' '../outside.sh' >> "${FIXTURE}/src/install/manifest.txt"
assert_rejected 'path traversal in manifest'

new_fixture manifest-execution
printf '%s\n' '$(printf executed > "${BUILD_EXECUTION_MARKER}")' >> "${FIXTURE}/src/install/manifest.txt"
assert_rejected 'shell expression in manifest'

new_fixture unlisted-module
printf '# Unlisted source must not silently disappear.\n' > "${FIXTURE}/src/install/30-forgotten.sh"
assert_rejected 'unlisted source module'

new_fixture invalid-syntax
printf '\nif then\n' >> "${FIXTURE}/src/install/10-functions.sh"
assert_rejected 'invalid Bash syntax'

new_fixture linked-module
mv "${FIXTURE}/src/install/10-functions.sh" "${TMP_DIR}/outside-module.sh"
ln -s "${TMP_DIR}/outside-module.sh" "${FIXTURE}/src/install/10-functions.sh"
assert_rejected 'source module symlink'

new_fixture linked-manifest
mv "${FIXTURE}/src/install/manifest.txt" "${TMP_DIR}/outside-manifest.txt"
ln -s "${TMP_DIR}/outside-manifest.txt" "${FIXTURE}/src/install/manifest.txt"
assert_rejected 'manifest symlink'

new_fixture linked-install-directory
mv "${FIXTURE}/src/install" "${TMP_DIR}/outside-install"
ln -s "${TMP_DIR}/outside-install" "${FIXTURE}/src/install"
assert_rejected 'module directory symlink'

new_fixture linked-src-directory
mv "${FIXTURE}/src" "${TMP_DIR}/outside-src"
ln -s "${TMP_DIR}/outside-src" "${FIXTURE}/src"
assert_rejected 'source parent symlink'

new_fixture linked-output
mv "${FIXTURE}/install.sh" "${TMP_DIR}/outside-output.sh"
ln -s "${TMP_DIR}/outside-output.sh" "${FIXTURE}/install.sh"
assert_rejected 'output symlink'
cmp -s "${TMP_DIR}/expected.sh" "${TMP_DIR}/outside-output.sh" || fail 'output symlink target was changed'

printf 'Install build isolation and publication checks passed\n'
