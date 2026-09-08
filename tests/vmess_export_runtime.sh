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
    printf 'VMess export runtime skipped: no configured real cores\n'
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
  printf 'VMess export runtime core version does not match its label\n' >&2
  exit 1
}
printf 'VMess export runtime shell: Bash %s; core=%s\n' "${BASH_VERSION}" "${actual_core_version}"

source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
cp -p "${core_binary}" "${TMP_DIR}/bin/sing-box"
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=vmess.runtime.invalid' -addext 'subjectAltName=DNS:vmess.runtime.invalid' \
  -keyout "${TMP_DIR}/vmess.key" -out "${TMP_DIR}/vmess.crt" >/dev/null 2>"${TMP_DIR}/openssl.stderr"
chmod 600 "${TMP_DIR}/vmess.key" "${TMP_DIR}/vmess.crt"
printf '%s\n' 'INSTALLED_PROTOCOLS=vmess' 'PROTOCOL_STATE_VERSION=1' > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/vmess.env"

for transport in \
  '{"type":"none"}' \
  '{"type":"http","host":["vmess.runtime.invalid"],"path":"/vmess"}' \
  '{"type":"ws","path":"/vmess","headers":{"Host":"vmess.runtime.invalid"}}' \
  '{"type":"grpc","service_name":"vmess-runtime"}' \
  '{"type":"quic"}'; do
  tls='{"enabled":false}'
  trust=system
  if [[ "$(jq -r '.type' <<< "${transport}")" != none ]]; then
    tls=$(jq -cn --arg cert "${TMP_DIR}/vmess.crt" --arg key "${TMP_DIR}/vmess.key" \
      '{enabled:true,server_name:"vmess.runtime.invalid",certificate_path:$cert,key_path:$key}')
    trust=certificate
  fi
  jq -n --argjson transport "${transport}" --argjson tls "${tls}" --arg trust "${trust}" \
    '{schema_version:1,protocol:"vmess",revision:1,default_instance_id:"main",instances:[
      {id:"main",name:"VMess runtime",tag:"vmess-in",listen:{address:"127.0.0.1",port:18086},
       authentication:{users:[
         {name:"alice",uuid:"11111111-1111-4111-8111-111111111111",alter_id:0,security:"auto"},
         {name:"bob",uuid:"22222222-2222-4222-8222-222222222222",alter_id:7,security:"aes-128-gcm"}]},
       tls:$tls,client_trust:$trust,transport:$transport,outbound_policy:"default",dependencies:[]}]}' \
    > "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
  validate_structured_instance_store vmess "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
  inbounds=$(render_structured_instance_inbounds vmess "${SB_PROTOCOL_STATE_DIR}/instances/vmess.json" | jq -s .)
  outbounds=$(build_client_vmess_outbounds 203.0.113.9 | jq -s .)
  jq -n --argjson inbounds "${inbounds}" \
    '{log:{disabled:true},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
    > "${TMP_DIR}/server.json"
  jq -n --argjson outbounds "${outbounds}" \
    '{log:{disabled:true},inbounds:[{type:"socks",tag:"local",listen:"127.0.0.1",listen_port:19087}],outbounds:$outbounds,route:{final:"vmess-main-user-YWxpY2U="}}' \
    > "${TMP_DIR}/client.json"
  "${core_binary}" check -c "${TMP_DIR}/server.json" >/dev/null
  "${core_binary}" check -c "${TMP_DIR}/client.json" >/dev/null
  printf 'transport=%s users=2 export=ok\n' "$(jq -r '.type' <<< "${transport}")"
done

# URI export remains lossless for the managed Host-only WebSocket profile.
exported=$(build_client_vmess_outbounds 203.0.113.9 | head -n 1)
uri=$(build_vmess_uri_from_outbound "${exported}" 'VMess runtime')
[[ "${uri}" == vmess://* && "${uri}" != *PRIVATE* ]]
printf 'VMess export runtime checks passed for %s\n' "${core_label}"
