#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
umask 077

mkdir -p "${TMP_DIR}/project/protocols/instances"
printf 'INSTALLED=1\nCONFIG_SCHEMA_VERSION=2\n' > "${TMP_DIR}/project/protocols/shadowtls.env"
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -subj '/CN=shadowtls.example.com' \
  -keyout "${TMP_DIR}/shadowtls.key" \
  -out "${TMP_DIR}/shadowtls.crt" >/dev/null 2>&1
jq -n --arg cert "${TMP_DIR}/shadowtls.crt" '
  {schema_version:1,protocol:"shadowtls",revision:1,default_instance_id:"main",
   instances:[{id:"main",name:"ShadowTLS composite export",tag:"shadowtls-in",
     listen:{address:"0.0.0.0",port:18444},version:3,
     authentication:{password:"",users:[{name:"shadow-user",password:"shadow-password"}]},
     handshake:{server:"cover.example.com",server_port:443},handshake_for_server_name:{},
     strict_mode:false,wildcard_sni:"off",
     detour:{tag:"shadowtls-inner-main",listen:{address:"127.0.0.1",port:18445}},
     dependencies:["shadowtls-inner-main"],client_trust:"certificate",
     client_tls:{server_name:"shadowtls.example.com",certificate_path:$cert},
     outbound_policy:"default"}]}
' > "${TMP_DIR}/project/protocols/instances/shadowtls.json"

source_testable_install
bundle_json=$(build_client_shadowtls_bundle_json 198.51.100.20)
jq -e '
  . as $bundle |
  ($bundle.outbounds | length == 2) and
  (($bundle.outbounds | [.[] | select(.type == "shadowtls")] | length) == 1) and
  (($bundle.outbounds | [.[] | select(.type == "http")] | length) == 1) and
  (($bundle.outbounds | [.[] | select(.type == "shadowtls")][0]) as $transport |
  ($bundle.outbounds | [.[] | select(.type == "http")][0]) as $proxy |
  ($transport.tag | endswith("-transport")) and
  $transport.server == "198.51.100.20" and $transport.server_port == 18444 and
  $transport.password == "shadow-password" and
  $transport.tls.enabled == true and
  ($transport.tls.certificate | contains("BEGIN CERTIFICATE")) and
  ($transport.tls | has("key") | not) and
  $proxy.tag == .primary_tags[0] and
  $proxy.server == "127.0.0.1" and $proxy.server_port == 18445 and
  $proxy.detour == $transport.tag)
' <<< "${bundle_json}" >/dev/null
[[ "$(jq -r '.primary_tags | length' <<< "${bundle_json}")" == 1 ]]

export_json=$(build_client_shadowtls_outbounds 198.51.100.20 | jq -s .)
jq -e --argjson bundle "${bundle_json}" '$bundle.outbounds == . and ($bundle.primary_tags | length) == 1' \
  <<< "${export_json}" >/dev/null
! grep -Fq 'PRIVATE KEY' <<< "${bundle_json}"

SB_PROTOCOL=shadowtls
load_plain_proxy_structured_instance shadowtls main
agent_json=$(agent_shadowtls_link_json 198.51.100.20)
jq -e '
  .links == {} and
  (.outbounds | length == 2) and
  (.primary_outbound_tags == [.outbounds[] | select(.type == "http") | .tag]) and
  ([.outbounds[] | select(.type == "http" and .detour != null)] | length == 1)
' <<< "${agent_json}" >/dev/null
printf 'ShadowTLS composite export emits a usable HTTP proxy and transport dependency\n'
