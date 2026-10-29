#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
SUBMAN_API_URL=https://old.example.com
SUBMAN_API_TOKEN=original-secret
SUBMAN_NODE_PREFIX=edge
SUBMAN_EXPECTED_GIST_ID=original-gist
write_subman_config
config_file=$(subman_config_file_path)
cp "${config_file}" "${TMP_DIR}/original"
preflight_subman_workspace() {
  [[ "${SUBMAN_API_URL}" == https://new.example.com && "${SUBMAN_API_TOKEN}" == replacement-secret &&
     "${SUBMAN_EXPECTED_GIST_ID}" == replacement-gist ]] || return 1
  printf 'GET-only\n' >> "${TMP_DIR}/preflight"
}
configure_subman_interactive >"${TMP_DIR}/settings.out" 2>"${TMP_DIR}/settings.err" <<'INPUT'
https://new.example.com/api/nodes/
replacement-secret

replacement-gist
INPUT
load_subman_config
[[ "${SUBMAN_API_URL}" == https://new.example.com && "${SUBMAN_API_TOKEN}" == replacement-secret ]]
[[ "${SUBMAN_EXPECTED_GIST_ID}" == replacement-gist && "${SUBMAN_NODE_PREFIX}" == edge ]]
cmp "${TMP_DIR}/original" "${config_file}.bak"
[[ "$(stat -c %a "${config_file}")" == 600 && "$(stat -c %a "${config_file}.bak")" == 600 ]]
cp "${config_file}" "${TMP_DIR}/saved"
preflight_subman_workspace() { subman_set_client_error unauthorized auth-required; return 1; }
if configure_subman_interactive >"${TMP_DIR}/invalid.out" 2>&1 <<'INPUT'
https://unreachable.example.com
bad-secret

new-gist
INPUT
then exit 1; fi
cmp "${TMP_DIR}/saved" "${config_file}"
# Switching deployments must not reuse the previous Gist on blank input.
preflight_subman_workspace() { printf unexpected > "${TMP_DIR}/unexpected"; return 0; }
if configure_subman_interactive >"${TMP_DIR}/missing-gist.out" 2>&1 <<'INPUT'
https://different.example.com
replacement-secret


INPUT
then exit 1; fi
[[ ! -e "${TMP_DIR}/unexpected" ]]
cmp "${TMP_DIR}/saved" "${config_file}"
# Supplying the new Gist still cannot send a saved token to another deployment.
if configure_subman_interactive >"${TMP_DIR}/missing-token.out" 2>&1 <<'INPUT'
https://different.example.com


new-gist
INPUT
then exit 1; fi
[[ ! -e "${TMP_DIR}/unexpected" ]]
cmp "${TMP_DIR}/saved" "${config_file}"
# The same deployment can retain its credential and identity on blank input.
preflight_subman_workspace() {
  [[ "${SUBMAN_API_URL}" == https://new.example.com &&
     "${SUBMAN_API_TOKEN}" == replacement-secret &&
     "${SUBMAN_EXPECTED_GIST_ID}" == replacement-gist ]]
}
configure_subman_interactive >"${TMP_DIR}/retain.out" 2>&1 <<'INPUT'




INPUT
cmp "${TMP_DIR}/saved" "${config_file}"
# EOF before completion is cancellation, never a partial save.
if configure_subman_interactive </dev/null >"${TMP_DIR}/eof.out" 2>&1; then exit 1; fi
cmp "${TMP_DIR}/saved" "${config_file}"
[[ "$(normalize_subman_api_url ' https://subman.example.com/api/ ')" == https://subman.example.com ]]
SUBMAN_API_URL='https://user:password@example.com'
! validate_subman_connection_settings 2>/dev/null
SUBMAN_API_URL=https://subman.example.com
SUBMAN_API_TOKEN=$'token\nheader = "injected"'
! validate_subman_connection_settings 2>/dev/null
if grep -Eq 'original-secret|replacement-secret|bad-secret' \
  "${TMP_DIR}"/{settings.out,settings.err,invalid.out,missing-gist.out,missing-token.out,retain.out,eof.out}; then
  printf 'SubMan settings leaked a test credential\n' >&2
  exit 1
else
  [[ "$?" == 1 ]]
fi
printf 'SubMan reconfigure: replacement, private backup, preflight, target identity, cancellation and redaction passed\n'
