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
    printf 'VLESS plain export runtime skipped: no configured real cores\n'
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
  printf 'VLESS plain export runtime core version does not match its label\n' >&2
  exit 1
}
printf 'VLESS plain export runtime shell: Bash %s; core=%s\n' "${BASH_VERSION}" "${actual_core_version}"

source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
cp -p "${core_binary}" "${TMP_DIR}/bin/sing-box"
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances" "${SB_PROJECT_DIR}"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=vless.runtime.invalid' -addext 'subjectAltName=DNS:vless.runtime.invalid' \
  -keyout "${TMP_DIR}/vless.key" -out "${TMP_DIR}/vless.crt" >/dev/null 2>"${TMP_DIR}/openssl.stderr"
chmod 600 "${TMP_DIR}/vless.key" "${TMP_DIR}/vless.crt"
printf '%s\n' INSTALLED_PROTOCOLS=vless-plain PROTOCOL_STATE_VERSION=1 > "${SB_PROTOCOL_INDEX_FILE}"
printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${SB_PROTOCOL_STATE_DIR}/vless-plain.env"

case_count=0
none_variant=0
for transport in \
  '{"type":"none"}' \
  '{"type":"none"}' \
  '{"type":"http","host":["vless.runtime.invalid"],"path":"/vless"}' \
  '{"type":"ws","path":"/vless","headers":{"Host":"vless.runtime.invalid"}}' \
  '{"type":"grpc","service_name":"vless-runtime"}' \
  '{"type":"quic"}'; do
  transport_type=$(jq -r '.type' <<< "${transport}")
  tls='{"enabled":false}'
  trust=system
  users='[
    {"name":"alice","uuid":"11111111-1111-4111-8111-111111111111","flow":""},
    {"name":"bob","uuid":"22222222-2222-4222-8222-222222222222","flow":""}
  ]'
  if [[ "${transport_type}" == none && "${none_variant}" == 0 ]]; then
    none_variant=1
  elif [[ "${transport_type}" == none ]]; then
    # Exercise per-user XTLS flow on the only supported generic profile.
    users='[
      {"name":"alice","uuid":"11111111-1111-4111-8111-111111111111","flow":"xtls-rprx-vision"},
      {"name":"bob","uuid":"22222222-2222-4222-8222-222222222222","flow":""}
    ]'
    tls=$(jq -cn --arg cert "${TMP_DIR}/vless.crt" --arg key "${TMP_DIR}/vless.key" \
      '{enabled:true,server_name:"vless.runtime.invalid",certificate_path:$cert,key_path:$key}')
    trust=certificate
  else
    tls=$(jq -cn --arg cert "${TMP_DIR}/vless.crt" --arg key "${TMP_DIR}/vless.key" \
      '{enabled:true,server_name:"vless.runtime.invalid",certificate_path:$cert,key_path:$key}')
    trust=certificate
  fi
  if [[ "${transport_type}" == quic ]]; then
    tls=$(jq -cn --arg cert "${TMP_DIR}/vless.crt" --arg key "${TMP_DIR}/vless.key" \
      '{enabled:true,server_name:"vless.runtime.invalid",certificate_path:$cert,key_path:$key}')
    trust=certificate
  fi
  jq -n --argjson transport "${transport}" --argjson tls "${tls}" --argjson users "${users}" --arg trust "${trust}" \
    '{schema_version:1,protocol:"vless-plain",revision:1,default_instance_id:"main",instances:[
      {id:"main",name:"VLESS runtime",tag:"vless-in",listen:{address:"0.0.0.0",port:18096},
       authentication:{users:$users},tls:$tls,client_trust:$trust,transport:$transport,
       outbound_policy:"default",dependencies:[]}]}' \
    > "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"
  validate_structured_instance_store vless-plain "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json"
  inbounds=$(render_structured_instance_inbounds vless-plain "${SB_PROTOCOL_STATE_DIR}/instances/vless-plain.json" | jq -s .)
  outbounds=$(build_client_vless_plain_outbounds 203.0.113.9 | jq -s .)
  jq -n --argjson inbounds "${inbounds}" \
    '{log:{disabled:true},inbounds:$inbounds,outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
    > "${TMP_DIR}/server.json"
  default_tag=$(jq -r '.[0].tag' <<< "${outbounds}")
  jq -n --argjson outbounds "${outbounds}" --arg final "${default_tag}" \
    '{log:{disabled:true},inbounds:[{type:"socks",tag:"local",listen:"127.0.0.1",listen_port:19097}],outbounds:$outbounds,route:{final:$final}}' \
    > "${TMP_DIR}/client.json"
  "${core_binary}" check -c "${TMP_DIR}/server.json" >/dev/null
  "${core_binary}" check -c "${TMP_DIR}/client.json" >/dev/null
  jq -e --arg type "${transport_type}" --arg trust "${trust}" \
    'length==2 and all(.[]; .type=="vless" and .server=="203.0.113.9" and
      (.network|type)=="array" and ((.network|index("tcp")) != null or (.network|index("udp")) != null)) and
      all(.[]; .network==["tcp","udp"]) and
      (if $trust=="certificate" then all(.[]; ((.tls.certificate // "") | contains("BEGIN CERTIFICATE"))) else true end)' \
    <<< "${outbounds}" >/dev/null
  if [[ "${transport_type}" == ws ]]; then
    uri=$(build_vless_plain_uri_from_outbound "$(jq -c '.[0]' <<< "${outbounds}")" 'VLESS runtime')
    [[ "${uri}" == vless://*"type=ws"*"security=tls"*"host=vless.runtime.invalid"* ]]
  fi
  case_count=$((case_count + 1))
  printf 'transport=%s users=2 export=ok\n' "${transport_type}"
done

printf 'VLESS plain export runtime checks passed for %s (%s transports)\n' "${core_label}" "${case_count}"
