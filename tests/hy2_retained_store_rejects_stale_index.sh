#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store="${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
jq -n '{schema_version:1,protocol:"hy2",revision:2,default_instance_id:"",instances:[]}' > "${store}"
printf '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}]}\n' > "${SINGBOX_CONFIG_FILE}"
printf 'INSTALLED_PROTOCOLS=\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cp "${store}" "${TMP_DIR}/store.before"
[[ -z "$(list_installed_protocols)" ]]
cmp "${store}" "${TMP_DIR}/store.before"

# No valid indexed entries does not mean the persisted index was empty.
# A retained HY2 store must not cause a missing REALITY state to be reported
# as installed or turn failed reconciliation into a successful enumeration.
printf 'INSTALLED_PROTOCOLS=vless-reality\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/index.before"
if list_installed_protocols > "${TMP_DIR}/stale.stdout" 2> "${TMP_DIR}/stale.stderr"; then
  printf 'retained HY2 store incorrectly accepted a stale nonempty index\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/stale.stdout" ]]
cmp "${SB_PROTOCOL_INDEX_FILE}" "${TMP_DIR}/index.before"
cmp "${store}" "${TMP_DIR}/store.before"
printf 'HY2 retained store accepts only a truly empty managed index\n'
