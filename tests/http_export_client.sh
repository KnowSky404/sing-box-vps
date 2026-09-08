#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope: Bash 4.2 preserves the installer's readonly arrays.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == check ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"
get_public_ip() { printf '127.0.0.1'; }

cert_path="${TMP_DIR}/public.crt"
key_path="${TMP_DIR}/server.key"
printf '%s\n' '-----BEGIN CERTIFICATE-----' 'QUJD' '-----END CERTIFICATE-----' > "${cert_path}"
printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'c2VjcmV0' '-----END PRIVATE KEY-----' > "${key_path}"

printf 'INSTALLED_PROTOCOLS=http\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
jq -n \
  '{
    schema_version:1, protocol:"http", revision:4, default_instance_id:"main",
    instances:[{
      id:"main", name:"HTTP export", tag:"http-export",
      listen:{address:"127.0.0.1",port:38111},
      authentication:{enabled:true,username:"http-user",password:"http-pass"},
      outbound_policy:"default", dependencies:[], tls:{enabled:false}
    }]
  }' > "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
jq -n '{log:{level:"warn"},inbounds:[{
  type:"http",tag:"http-export",listen:"127.0.0.1",listen_port:38111,
  users:[{username:"http-user",password:"http-pass"}],tls:{enabled:false}
}],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' > "${SINGBOX_CONFIG_FILE}"
save_plain_proxy_structured_marker http

load_plain_proxy_structured_instance http main
plain_outbound=$(build_client_outbound_json_for_protocol http 203.0.113.10)
jq -e '
  .type == "http" and .tag == "http-main" and .server == "127.0.0.1" and
  .server_port == 38111 and .username == "http-user" and .password == "http-pass" and
  (has("version") | not) and (has("udp_over_tcp") | not) and (has("tls") | not)
' <<< "${plain_outbound}" >/dev/null

full_config=$(build_singbox_client_config)
printf '%s\n' "${full_config}" > "${TMP_DIR}/http-export-full.json"
jq -e '[.outbounds[] | select(.type == "http")] | length == 1' \
  "${TMP_DIR}/http-export-full.json" >/dev/null
jq -e 'all(.outbounds[]?; .type != "socks" or (has("udp_over_tcp") and .udp_over_tcp.version == 2))' \
  "${TMP_DIR}/http-export-full.json" >/dev/null

plain_links=$(build_plain_proxy_links_json http 203.0.113.10)
jq -e '.http == "http://http-user:http-pass@203.0.113.10:38111" and (keys | length) == 1' \
  <<< "${plain_links}" >/dev/null
jq -e 'any(.[]; .code == "http_plaintext_transport")' <<< "$(plain_proxy_share_warnings_json http)" >/dev/null
plain_export_config=$(jq -n --argjson outbound "${plain_outbound}" '{outbounds:[$outbound]}')
jq -e 'any(.[]; .code == "http_plaintext_transport")' \
  <<< "$(collect_client_export_warnings_json "${plain_export_config}")" >/dev/null

# Mixed export owns only SOCKS/HTTP plaintext. A stale HTTP typed TLS value
# must not suppress its plaintext HTTP share or leak an HTTP-TLS warning.
SB_HTTP_TLS_JSON='{"enabled":true,"server_name":"stale","certificate_path":"/no/cert","key_path":"/no/key"}'
mixed_stale_links=$(build_plain_proxy_links_json mixed 203.0.113.10)
jq -e 'has("http") and has("socks5")' <<< "${mixed_stale_links}" >/dev/null
if jq -e 'any(.[]; .code == "http_tls_uri_unrepresentable")' \
  <<< "$(plain_proxy_share_warnings_json mixed)" >/dev/null; then
  printf 'Mixed share warnings consulted stale HTTP TLS state\n' >&2
  exit 1
fi
SB_HTTP_TLS_JSON='{"enabled":false}'

# HTTP credentials use the 4096-byte Basic cap, independently of SOCKS's
# 255-byte protocol cap. URI representation still rejects colon usernames.
SB_MIXED_USERNAME=$(printf '%0256s' '')
SB_MIXED_USERNAME=${SB_MIXED_USERNAME// /u}
SB_MIXED_PASSWORD=valid-password
[[ "$(build_plain_proxy_link http 203.0.113.10)" == http://* ]]
SB_MIXED_USERNAME=$(printf '%04100s' '')
SB_MIXED_USERNAME=${SB_MIXED_USERNAME// /u}
if build_plain_proxy_link http 203.0.113.10 >/dev/null 2>"${TMP_DIR}/oversize.stderr"; then
  printf 'HTTP URI accepted a credential larger than 4096 bytes\n' >&2
  exit 1
fi
SB_MIXED_USERNAME='bad:user'
if build_plain_proxy_link http 203.0.113.10 >"${TMP_DIR}/colon.out" 2>"${TMP_DIR}/colon.stderr"; then
  printf 'HTTP URI accepted a colon username\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/colon.out" ]]
grep -Fq 'mixed_http_auth_unrepresentable' "${TMP_DIR}/colon.stderr"
if build_client_plain_proxy_outbound http 127.0.0.1 http-bad >"${TMP_DIR}/colon-outbound.json" 2>"${TMP_DIR}/colon-outbound.stderr"; then
  printf 'HTTP outbound accepted a colon username\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/colon-outbound.json" ]]

# TLS outbound embeds only public certificate trust and SNI, never key paths
# or private-key bytes.
jq --arg cert "${cert_path}" --arg key "${key_path}" \
  '.instances[0].tls={enabled:true,server_name:"http-export.example",certificate_path:$cert,key_path:$key}' \
  "${SB_PROTOCOL_STATE_DIR}/instances/http.json" > "${TMP_DIR}/tls-store.json"
mv "${TMP_DIR}/tls-store.json" "${SB_PROTOCOL_STATE_DIR}/instances/http.json"
jq --arg cert "${cert_path}" --arg key "${key_path}" \
  '.inbounds[0].tls={enabled:true,server_name:"http-export.example",certificate_path:$cert,key_path:$key}' \
  "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/tls-config.json"
mv "${TMP_DIR}/tls-config.json" "${SINGBOX_CONFIG_FILE}"
load_plain_proxy_structured_instance http main
tls_outbound=$(build_client_outbound_json_for_protocol http 127.0.0.1)
jq -e '
  .type == "http" and .tls.enabled == true and .tls.server_name == "http-export.example" and
  (.tls.certificate | contains("BEGIN CERTIFICATE")) and
  (has("certificate_path") | not) and (has("key_path") | not) and
  (.tls | tostring | contains("PRIVATE KEY") | not)
' <<< "${tls_outbound}" >/dev/null
jq -e 'length == 0' <<< "$(build_plain_proxy_links_json http 127.0.0.1)" >/dev/null
jq -e 'any(.[]; .code == "http_tls_uri_unrepresentable")' \
  <<< "$(plain_proxy_share_warnings_json http)" >/dev/null
tls_export_config=$(jq -n --argjson outbound "${tls_outbound}" '{outbounds:[$outbound]}')
jq -e 'any(.[]; .code == "http_tls_certificate_embedded")' \
  <<< "$(collect_client_export_warnings_json "${tls_export_config}")" >/dev/null

bad_cert="${TMP_DIR}/bad.crt"
printf '%s\n' '-----BEGIN CERTIFICATE-----' 'QUJD' '-----END CERTIFICATE-----' 'secret-suffix' > "${bad_cert}"
if read_public_certificate_pem "${bad_cert}" >/dev/null; then
  printf 'certificate reader accepted non-PEM suffix\n' >&2
  exit 1
fi
printf '%s\r\n' '-----BEGIN CERTIFICATE-----' 'QUJD' '-----END CERTIFICATE-----' > "${bad_cert}"
[[ "$(read_public_certificate_pem "${bad_cert}")" == *'BEGIN CERTIFICATE'* ]]
printf '%s\n' '-----BEGIN CERTIFICATE-----' 'QUJD' '-----END CERTIFICATE-----' '-----BEGIN PRIVATE KEY-----' 'secret' '-----END PRIVATE KEY-----' > "${bad_cert}"
if read_public_certificate_pem "${bad_cert}" >/dev/null; then
  printf 'certificate reader accepted private-key material\n' >&2
  exit 1
fi
printf 'not a certificate\n' > "${bad_cert}"
if read_public_certificate_pem "${bad_cert}" >/dev/null; then
  printf 'certificate reader accepted missing PEM certificate\n' >&2
  exit 1
fi
head -c 1048577 /dev/zero > "${bad_cert}"
if read_public_certificate_pem "${bad_cert}" >/dev/null; then
  printf 'certificate reader accepted oversized material\n' >&2
  exit 1
fi

printf 'HTTP export client checks passed: full-export-check=1, plain-outbound=1, tls-outbound=1, uri=3, certificate-rejections=4\n'
