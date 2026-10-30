#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT
mkdir -p "${TMP_DIR}/bin"
printf 'fixture\n' > "${TMP_DIR}/core"
printf 'fixture\n' > "${TMP_DIR}/headscale"
REAL_BASH=$(command -v bash)
cat > "${TMP_DIR}/bin/docker" <<DOCKER
#!${REAL_BASH}
printf '%s\n' "\$*" >> "${TMP_DIR}/calls"
case "\${1:-}" in
  create) printf 'owned-created-id\n' ;;
  start) exit 17 ;;
  rm) : ;;
  *) printf 'unexpected Docker operation\n' >&2; exit 99 ;;
esac
DOCKER
cat > "${TMP_DIR}/bin/sha256sum" <<SHA
#!${REAL_BASH}
cat >/dev/null
SHA
chmod +x "${TMP_DIR}/bin/docker" "${TMP_DIR}/bin/sha256sum"
status=0
PATH="${TMP_DIR}/bin:${PATH}" SINGBOX_TEST_BIN="${TMP_DIR}/core" \
  HEADSCALE_TEST_BIN="${TMP_DIR}/headscale" VPN_RUNTIME_ARTIFACT_DIR="${TMP_DIR}/artifacts" \
  bash "${REPO_ROOT}/tests/tailscale_openconnect_runtime.sh" \
  > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/stderr" || status=$?
[[ "${status}" -eq 17 ]]
grep -Fqx 'start owned-created-id' "${TMP_DIR}/calls"
grep -Fqx 'rm -f owned-created-id' "${TMP_DIR}/calls"
grep -Fqx 'owned_containers_removed=1' "${TMP_DIR}/artifacts/cleanup.env"
[[ $(wc -l < "${TMP_DIR}/calls") -eq 3 ]]

# Exercise the actual guest cleanup assertion without running the guest fixture
# or touching any host interface. A leaked interface must return failure even
# when the caller uses a conditional (which suppresses Bash errexit).
source <(awk '
  /^assert_interface_absent\(\)/ { printing=1 }
  printing { print }
  printing && /^}/ { exit }
' "${REPO_ROOT}/tests/tailscale_openconnect_test_helper.sh")
ip() { return "${MOCK_IP_STATUS}"; }
MOCK_IP_STATUS=0
if assert_interface_absent fixture-leaked > "${TMP_DIR}/leak.stdout" 2> "${TMP_DIR}/leak.stderr"; then
  printf 'leaked interface incorrectly accepted\n' >&2
  exit 1
fi
grep -Fq 'managed interface remains after deletion' "${TMP_DIR}/leak.stderr"
MOCK_IP_STATUS=1
assert_interface_absent fixture-removed
printf 'VPN orchestration startup-failure cleanup and interface guards passed\n'
