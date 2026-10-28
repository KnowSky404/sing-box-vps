#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "HY2 ACME menu failed at line %s\n" "${LINENO}" >&2' ERR
snapshot="${TMP_DIR}/snapshot.json"
record="${TMP_DIR}/record.json"
structured_instance_store_empty_json hy2 > "${snapshot}"
validate_tls_domain_points_to_server() { printf '%s\n' "$2" >> "${TMP_DIR}/http-domain-checks"; }

# The default is HTTP-01; no certificate path is requested or pre-created.
printf '%s\n' '' '' '' '' 48443 '' '' '' '' hy2.example.com '' '' '' '' '' '' y > "${TMP_DIR}/http.input"
hy2_management_build_record "${snapshot}" create '' "${record}" < "${TMP_DIR}/http.input" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/guidance"
[[ ! -s "${TMP_DIR}/stdout" ]]
jq -e '.listen.address=="0.0.0.0" and .tls.acme.domain==["hy2.example.com"] and .client_trust=="system" and
  .tls.acme.disable_tls_alpn_challenge==true and (.tls|has("certificate_path")|not)' "${record}" >/dev/null
grep -Fxq hy2.example.com "${TMP_DIR}/http-domain-checks"

# DNS-01 accepts a domain without requiring its A/AAAA records to point here,
# rejects a missing token, and never writes the token to prompt output.
: > "${TMP_DIR}/http-domain-checks"
printf '%s\n' '' '' '' '' 48444 '' '' '' 1 dns.example.com 2 '' '' fixture-menu-token '' '' '' '' y > "${TMP_DIR}/dns.input"
hy2_management_build_record "${snapshot}" create '' "${record}" < "${TMP_DIR}/dns.input" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/guidance"
jq -e '.tls.acme.domain==["dns.example.com"] and .tls.acme.dns01_challenge=={provider:"cloudflare",api_token:"fixture-menu-token"} and
  .client_trust=="system" and (.tls|has("key_path")|not)' "${record}" >/dev/null
[[ ! -s "${TMP_DIR}/http-domain-checks" ]]
grep -Fq 'Token 不能为空' "${TMP_DIR}/guidance"
! grep -Fq fixture-menu-token "${TMP_DIR}/guidance"

# Leaving fields unchanged while replacing preserves DNS mode, existing
# credentials, alternate certificate domains, storage and zone-token settings.
jq '.tls.acme.domain += ["alternate.example.com"] | .tls.acme.dns01_challenge.zone_token="fixture-zone-token"' "${record}" > "${TMP_DIR}/original.json"
jq -n --slurpfile record "${TMP_DIR}/original.json" \
  '{schema_version:1,protocol:"hy2",revision:5,default_instance_id:$record[0].id,instances:$record}' > "${snapshot}"
id=$(jq -r '.id' "${record}")
printf '%s\n' '' '' '' '' '' '' '' '' '' '' '' '' y > "${TMP_DIR}/replace.input"
hy2_management_build_record "${snapshot}" replace "${id}" "${record}" < "${TMP_DIR}/replace.input" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/guidance"
[[ "$(jq -cS . "${record}")" == "$(jq -cS . "${TMP_DIR}/original.json")" ]]
! grep -Fq fixture-menu-token "${TMP_DIR}/guidance"

# An existing loopback address is explicit administrator state, and is kept
# when editing even though new server instances now default to all IPv4.
jq '.instances[0].listen.address="127.0.0.1"' "${snapshot}" > "${TMP_DIR}/loopback.json"
hy2_management_build_record "${TMP_DIR}/loopback.json" replace "${id}" "${record}" < "${TMP_DIR}/replace.input" > "${TMP_DIR}/stdout" 2> "${TMP_DIR}/guidance"
jq -e '.listen.address=="127.0.0.1"' "${record}" >/dev/null

# The additional-install dispatcher reaches this same ACME-capable record
# builder, rather than falling back to the fresh-install singleton path.
structured_instance_store_empty_json hy2 > "${snapshot}"
printf '{"inbounds":[]}\n' > "${SINGBOX_CONFIG_FILE}"
migrate_legacy_single_protocol_state_if_needed() { :; }
load_current_config_state() { :; }
load_warp_route_settings() { :; }
list_installed_protocols() { printf 'vless-reality\n'; }
prompt_protocol_install_selection() { [[ "$1" == additional ]]; SELECTED_PROTOCOLS_CSV=hy2; }
plain_proxy_management_capture_snapshot() { cp "${TMP_DIR}/snapshot.json" "$2"; }
apply_plain_proxy_instance_change() {
  [[ "$1" == hy2 && "$2" == create && "$3" == 0 ]]
  cp "$4" "${TMP_DIR}/additional-record.json"
  printf '{"ok":true,"revision":1}\n'
}
install_protocols_interactive additional < "${TMP_DIR}/http.input" > "${TMP_DIR}/additional.stdout" 2> "${TMP_DIR}/additional.stderr"
jq -e '.tls.acme.domain==["hy2.example.com"]' "${TMP_DIR}/additional-record.json" >/dev/null
printf 'HY2 ACME HTTP/DNS prompts, replacement defaults and additional-install entry passed\n'
