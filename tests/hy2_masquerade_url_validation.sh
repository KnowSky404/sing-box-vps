#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "HY2 masquerade regression failed at line %s\n" "${LINENO}" >&2' ERR
core=${SINGBOX_BINARY_114:-/usr/local/bin/sing-box}
mkdir -p "${SB_PROTOCOL_STATE_DIR}" "${TMP_DIR}/website with spaces"
ln -s "${core}" "${SINGBOX_BIN_PATH}"
openssl req -x509 -newkey ed25519 -nodes -days 1 -subj /CN=hy2.example.com \
  -keyout "${TMP_DIR}/hy2.key" -out "${TMP_DIR}/hy2.pem" > "${TMP_DIR}/openssl.log" 2>&1

# Reproduce the reported decoder error with the real core, without any network.
jq -n '{inbounds:[{type:"hysteria2",masquerade:"example.com"}]}' > "${TMP_DIR}/invalid.json"
if "${core}" check -c "${TMP_DIR}/invalid.json" > "${TMP_DIR}/invalid.log" 2>&1; then
  printf 'core unexpectedly accepted a schemeless masquerade\n' >&2; exit 1
fi
grep -Fq 'unknown masquerade URL scheme:' "${TMP_DIR}/invalid.log"

# Reject malformed website input without echoing it. Trim pasted whitespace,
# preserve valid URLs verbatim, and retain upstream file:// support.
result=$(prompt_hy2_masquerade_url 'URL: ' '' <<'INPUT' 2> "${TMP_DIR}/retry.log"
example.com
ftp://example.com
https://
https:///example.com
https://example.com/with space
  https://example.com/path?x=1&y=2  
INPUT
)
[[ "${result}" == 'https://example.com/path?x=1&y=2' ]]
[[ "$(grep -c '请重新输入' "${TMP_DIR}/retry.log")" == 5 ]]
! grep -Fq 'ftp://example.com' "${TMP_DIR}/retry.log"
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< '')" == '' ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' https://example.com <<< '')" == https://example.com ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< http://example.com)" == http://example.com ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< 'hTtPs://example.com/CaseSensitive')" == hTtPs://example.com/CaseSensitive ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' 'HTTPS://example.com/CaseSensitive' <<< '')" == HTTPS://example.com/CaseSensitive ]]
[[ "$(prompt_hy2_masquerade_url 'URL: ' '' <<< "FILE://${TMP_DIR}/website with spaces")" == "FILE://${TMP_DIR}/website with spaces" ]]
if prompt_hy2_masquerade_url 'URL: ' '' <<< example.com > "${TMP_DIR}/eof.out" 2> "${TMP_DIR}/eof.log"; then
  printf 'invalid input followed by EOF unexpectedly succeeded\n' >&2; exit 1
fi
[[ ! -s "${TMP_DIR}/eof.out" ]]

# The fresh-install legacy path must retry at the masquerade prompt, rather
# than consuming subsequent global options or publishing a broken state.
check_port_conflict() { :; }
validate_tls_domain_points_to_server() { :; }
printf '%s\n' hy2.example.com 48443 fixture-password fixture-user '' '' n 2 \
  "${TMP_DIR}/hy2.pem" "${TMP_DIR}/hy2.key" example.com https://example.com \
  > "${TMP_DIR}/install.input"
prompt_hy2_install < "${TMP_DIR}/install.input" > "${TMP_DIR}/install.out" 2> "${TMP_DIR}/install.log"
[[ "${SB_HY2_MASQUERADE}" == https://example.com ]]
grep -Fq '请重新输入' "${TMP_DIR}/install.log"
save_hy2_state

# Updating the singleton also retries; blank continues to preserve its value.
printf '%s\n' '' '' '' '' '' '' n '' example.com http://example.com \
  > "${TMP_DIR}/update.input"
prompt_hy2_update < "${TMP_DIR}/update.input" > "${TMP_DIR}/update.out" 2> "${TMP_DIR}/update.log"
[[ "${SB_HY2_MASQUERADE}" == http://example.com ]]
grep -Fq '请重新输入' "${TMP_DIR}/update.log"

# Additional-install / instance-create uses the typed record builder.
snapshot="${TMP_DIR}/snapshot.json"
record="${TMP_DIR}/record.json"
structured_instance_store_empty_json hy2 > "${snapshot}"
printf '%s\n' '' '' '' 127.0.0.1 48443 '' '' '' 2 hy2.example.com \
  "${TMP_DIR}/hy2.pem" "${TMP_DIR}/hy2.key" 1 '' '' n example.com https://example.com \
  > "${TMP_DIR}/create.input"
hy2_management_build_record "${snapshot}" create '' "${record}" \
  < "${TMP_DIR}/create.input" > "${TMP_DIR}/create.out" 2> "${TMP_DIR}/create.log"
[[ ! -s "${TMP_DIR}/create.out" ]]
jq -e '.masquerade=="https://example.com"' "${record}" >/dev/null
grep -Fq '请重新输入' "${TMP_DIR}/create.log"
jq -n --slurpfile record "${record}" \
  '{schema_version:1,protocol:"hy2",revision:1,default_instance_id:$record[0].id,instances:$record} |
   .instances[0].masquerade="HTTPS://example.com/CaseSensitive"' > "${snapshot}"
id=$(jq -r '.id' "${record}")
printf '%s\n' '' '' '' n '' '' '' '' 1 '' '' n '' > "${TMP_DIR}/replace.input"
hy2_management_build_record "${snapshot}" replace "${id}" "${record}" \
  < "${TMP_DIR}/replace.input" > "${TMP_DIR}/replace.out" 2> "${TMP_DIR}/replace.log"
jq -e '.masquerade=="HTTPS://example.com/CaseSensitive"' "${record}" >/dev/null

# Generate the actual VLESS + HY2 configuration, including valid REALITY
# keys, and check both renderers and the disabled/file variants with the core.
set_protocol_defaults vless-reality
SB_SNI=example.com
SB_PORT=48441
save_vless_reality_state
write_protocol_index vless-reality,hy2
SB_ADVANCED_ROUTE=n
SB_ENABLE_WARP=n
register_warp() { :; }
ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() {
  SB_WARP_CUSTOM_DOMAINS_JSON='[]'; SB_WARP_CUSTOM_DOMAIN_SUFFIXES_JSON='[]'
  SB_WARP_LOCAL_RULE_SETS_JSON='[]'; SB_WARP_REMOTE_RULE_SETS_JSON='[]'; SB_WARP_RULE_SET_TAGS_JSON='[]'
}
generate_config > "${TMP_DIR}/generate.log" 2>&1
jq -e '(.inbounds|length)==2 and any(.inbounds[]; .type=="vless") and
  any(.inbounds[]; .type=="hysteria2" and .masquerade=="https://example.com")' "${SINGBOX_CONFIG_FILE}" >/dev/null
"${core}" check -c "${SINGBOX_CONFIG_FILE}"
SB_VERSION=1.14.2
for url in '' https://example.com http://example.com HTTPS://example.com/CaseSensitive \
  hTtPs://example.com/CaseSensitive "FILE://${TMP_DIR}/website with spaces"; do
  jq --arg url "${url}" '.instances[0].masquerade=$url' "${snapshot}" > "${TMP_DIR}/variant.json"
  render_structured_instance_inbounds hy2 "${TMP_DIR}/variant.json" | jq -s \
    '{inbounds:.,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${TMP_DIR}/server.json"
  "${core}" check -c "${TMP_DIR}/server.json"
  if [[ -z "${url}" ]]; then jq -e 'all(.inbounds[]; has("masquerade")|not)' "${TMP_DIR}/server.json" >/dev/null; fi
done
printf 'HY2 masquerade retry, EOF, legacy/typed prompts and VLESS + HY2 real-core checks passed\n'
