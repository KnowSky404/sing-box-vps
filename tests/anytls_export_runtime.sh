#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TESTS_DIR=${REPO_ROOT}/tests

if [[ ${1:-} != --run ]]; then
  if [[ $# -ne 0 ]]; then
    printf 'usage: %s [--run CORE_BINARY CORE_LABEL]\n' "${BASH_SOURCE[0]}" >&2
    exit 2
  fi
  if [[ -z "${SINGBOX_BINARY_113:-}" && -z "${SINGBOX_BINARY_114:-}" ]]; then
    printf 'AnyTLS export runtime skipped: no configured real cores\n'
    exit 0
  fi
  dispatch_status=0
  if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then
    [[ -x "${SINGBOX_BINARY_113}" ]] || { printf 'configured 1.13.18 core unavailable\n' >&2; exit 1; }
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_113}" 1.13.18 || dispatch_status=$?
  fi
  if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
    [[ -x "${SINGBOX_BINARY_114}" ]] || { printf 'configured 1.14.0 core unavailable\n' >&2; exit 1; }
    bash "${BASH_SOURCE[0]}" --run "${SINGBOX_BINARY_114}" 1.14.0 || dispatch_status=$?
  fi
  exit "${dispatch_status}"
fi

[[ $# -eq 3 && -x ${2:-} ]] || {
  printf 'usage: %s --run CORE_BINARY CORE_LABEL\n' "$0" >&2
  exit 2
}
core_binary=$2
core_label=$3
actual_core_version=$(${core_binary} version | awk 'NR == 1 {print $3}')
[[ "${actual_core_version}" == "${core_label#v}" ]] || {
  printf 'AnyTLS export runtime core version does not match its label\n' >&2
  exit 1
}
printf 'AnyTLS export runtime shell: Bash %s; core=%s\n' "${BASH_VERSION}" "${actual_core_version}"

source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 130
cp -p "${core_binary}" "${TMP_DIR}/bin/sing-box"
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=anytls.runtime.invalid' -addext 'subjectAltName=DNS:anytls.runtime.invalid' \
  -keyout "${TMP_DIR}/anytls.key" -out "${TMP_DIR}/anytls.crt" >/dev/null 2>"${TMP_DIR}/openssl.stderr"
chmod 600 "${TMP_DIR}/anytls.key" "${TMP_DIR}/anytls.crt"
printf 'INSTALLED_PROTOCOLS=anytls\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/anytls.env"

jq -n --arg cert "${TMP_DIR}/anytls.crt" --arg key "${TMP_DIR}/anytls.key" '
  {schema_version:1,protocol:"anytls",revision:1,default_instance_id:"main",instances:[
    {id:"main",name:"AnyTLS runtime",tag:"anytls-in",listen:{address:"0.0.0.0",port:18077},
     authentication:{users:[{name:"alice",password:"alice-password"},{name:"bob",password:"bob-password"}]},
     tls:{enabled:true,server_name:"anytls.runtime.invalid",certificate_path:$cert,key_path:$key},
     client_trust:"certificate",outbound_policy:"default",dependencies:[]}
  ]}
' > "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"
validate_structured_instance_store anytls "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json"
inbounds=$(render_structured_instance_inbounds anytls "${SB_PROTOCOL_STATE_DIR}/instances/anytls.json" | jq -s .)
outbounds=$(build_client_anytls_outbounds 203.0.113.9 | jq -s .)
jq -n --argjson inbounds "${inbounds}" \
  '{log:{disabled:true},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
  > "${TMP_DIR}/server.json"
jq -n --argjson outbounds "${outbounds}" --arg final "anytls-main-user-YWxpY2U=" \
  '{log:{disabled:true},inbounds:[{type:"socks",tag:"local",listen:"127.0.0.1",listen_port:19078}],outbounds:$outbounds,route:{final:$final}}' \
  > "${TMP_DIR}/client.json"
"${core_binary}" check -c "${TMP_DIR}/server.json" >/dev/null
"${core_binary}" check -c "${TMP_DIR}/client.json" >/dev/null
jq -e '
  length == 2 and all(.[]; .type=="anytls" and .server=="203.0.113.9" and
    .server_port==18077 and .client_metadata=="" and
    (.password|type)=="string" and .tls.enabled==true and
    .tls.server_name=="anytls.runtime.invalid" and
    (.tls.certificate | contains("BEGIN CERTIFICATE")))
' <<< "${outbounds}" >/dev/null

printf 'AnyTLS export runtime checks passed for %s\n' "${core_label}"
