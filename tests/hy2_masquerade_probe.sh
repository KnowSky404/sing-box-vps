#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "HY2 probe failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
# A REALITY instance configured earlier in the same install is also selectable.
set_protocol_defaults vless-reality
SB_SNI=www.example.com
save_vless_reality_state
jq -n '{inbounds:[{type:"vless",tls:{server_name:"www.example.com",reality:{enabled:true}}},
  {type:"vless",tls:{server_name:"second.example.com",reality:{enabled:true}}},
  {type:"vless",tls:{server_name:"ignored.example.com"}}]}' > "${SINGBOX_CONFIG_FILE}"
[[ "$(hy2_reality_masquerade_candidates)" == $'https://second.example.com\nhttps://www.example.com' ]]
curl() {
  printf '%s\n' "$@" >> "${TMP_DIR}/curl.args"
  cat > "${TMP_DIR}/curl.config"
  [[ "${CURL_EXIT:-0}" == 0 ]] || return "${CURL_EXIT}"
  printf '%s' "${HTTP_STATUS:-204}"
}
for HTTP_STATUS in 200 204 301 399; do probe_hy2_masquerade_url https://example.com; done
for HTTP_STATUS in 000 400 403 405 500; do
  if probe_hy2_masquerade_url https://example.com; then exit 1; fi
done
HTTP_STATUS=204
probe_hy2_masquerade_url 'https://user:private@example.com/path?token=private&quote="back\slash'
! grep -Fq 'private' "${TMP_DIR}/curl.args"
[[ "$(cat "${TMP_DIR}/curl.config")" == 'url = "https://user:private@example.com/path?token=private&quote=\"back\\slash"' ]]
if probe_hy2_masquerade_url $'https://example.com/\noutput = "/tmp/forbidden"'; then exit 1; fi
CURL_EXIT=60
if probe_hy2_masquerade_url https://example.com; then exit 1; fi
CURL_EXIT=0
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< r2)" == https://www.example.com ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< $'r3\nr1')" == https://second.example.com ]]
grep -Fxq -- --max-time "${TMP_DIR}/curl.args"
grep -Fxq -- --proto-redir "${TMP_DIR}/curl.args"
grep -Fxq -- --globoff "${TMP_DIR}/curl.args"
! grep -Fxq -- --insecure "${TMP_DIR}/curl.args"
# Blank replacement is offline, while a new installation checks its default.
rm -f "${TMP_DIR}/curl.args"
[[ "$(prompt_hy2_masquerade_url 'URL: ' https://existing.example.com <<< '')" == https://existing.example.com ]]
[[ ! -e "${TMP_DIR}/curl.args" ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' https://new.example.com create <<< '')" == https://new.example.com ]]
[[ -s "${TMP_DIR}/curl.args" ]]
rm -f "${TMP_DIR}/curl.args"
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< file:///srv/site)" == file:///srv/site ]]
[[ ! -e "${TMP_DIR}/curl.args" ]]
HTTP_STATUS=403
if prompt_hy2_masquerade_url 'URL: ' '' <<< https://secret.invalid/path?private=dummy > "${TMP_DIR}/out" 2> "${TMP_DIR}/error"; then exit 1; fi
[[ ! -s "${TMP_DIR}/out" ]]
! grep -Fq 'private=dummy' "${TMP_DIR}/error"
# The canonical and legacy structured entrypoints use the same bounded probe.
HTTP_STATUS=204
storage_require_current() { :; }
for mode in canonical agent; do
  if [[ "${mode}" == canonical ]]; then
    main hy2 masquerade-check --json --url https://example.com > "${TMP_DIR}/cli.json"
  else main agent hy2 masquerade-check --json --url https://example.com > "${TMP_DIR}/cli.json"; fi
  jq -e '.ok and .data.http_available and (.data.reality_candidates|length)==2 and
    .data.tls_server_name_reused==false' "${TMP_DIR}/cli.json" >/dev/null
done
HTTP_STATUS=500
if main hy2 masquerade-check --json --url https://example.com > "${TMP_DIR}/cli.json"; then exit 1; fi
jq -e '.ok==false and .data.http_available==false and .error=="masquerade_probe_failed"' "${TMP_DIR}/cli.json" >/dev/null
if main hy2 masquerade-check --json --extra > "${TMP_DIR}/cli.json"; then exit 1; fi
jq -e '.ok==false' "${TMP_DIR}/cli.json" >/dev/null
printf 'HY2 candidate selection, bounded DNS/TLS/HTTP probe, EOF, privacy and structured CLI passed\n'
