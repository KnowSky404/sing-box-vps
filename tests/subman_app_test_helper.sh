#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
REPO_ROOT=${SUBMAN_APP_RUNTIME_SOURCE_DIR:-${REPO_ROOT}}
setup_menu_test_env 120
source_testable_install
stage=${1:?create or rename stage is required}
case "${stage}" in create) display_base='原名🌐' ;; rename) display_base='改名🚀' ;; *) exit 2 ;; esac
display_base+=${SUBMAN_APP_DISPLAY_SUFFIX:-}
SUBMAN_API_URL=${SUBMAN_APP_URL:?isolated application URL is required}
if [[ "${SUBMAN_APP_PRODUCTION_ACCEPT:-0}" == 1 ]]; then
  [[ "${SUBMAN_API_URL}" == https://* && -n "${SUBMAN_APP_KEY_PREFIX:-}" ]] || exit 1
  SUBMAN_API_TOKEN=$(python3 - "${SUBMAN_APP_HEADERS_FILE:?private authorization file is required}" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
if path.stat().st_mode & 0o077:
    raise SystemExit('authorization file must be private')
matches = re.findall(r'^Authorization: Bearer ([^\r\n]+)$', path.read_text(), re.M | re.I)
if len(matches) != 1:
    raise SystemExit('exactly one Bearer authorization header is required')
print(matches[0], end='')
PY
  )
else
  [[ "${SUBMAN_API_URL}" == http://127.0.0.1:* ]] || { printf 'integration target must be isolated loopback\n' >&2; exit 1; }
  SUBMAN_API_TOKEN=isolated-api-fixture
fi
SUBMAN_EXPECTED_GIST_ID=${SUBMAN_APP_GIST_ID:?isolated Gist ID is required}
SUBMAN_NODE_PREFIX=${SUBMAN_APP_KEY_PREFIX:-app-fixture}
SB_INBOUND_STACK_MODE=ipv6_only
SB_OUTBOUND_STACK_MODE=prefer_ipv4
# The test supplies documentation-range address probe results; it verifies
# selection and storage, not public reachability or provider network behavior.
get_public_ipv4() { printf '203.0.113.10\n'; }
get_public_ipv6() { printf '2001:db8::10\n'; }
systemctl() { printf 'unexpected service mutation in app naming test\n' >&2; return 99; }
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=app-naming.example \
  -keyout "${TMP_DIR}/naming.key" -out "${TMP_DIR}/naming.crt" >/dev/null 2>"${TMP_DIR}/openssl.err"
local_links_for_instance() {
  local protocol=$1 server=$2 result
  case "${protocol}" in
    shadowsocks) build_shadowsocks_links_json "${server}" main ;;
    trojan|hy2)
      result=$("build_${protocol}_subman_links_and_warnings_json" "${server}" main) || return 1
      jq -c '.links' <<< "${result}"
      ;;
    vmess) build_vmess_links_json "${server}" main ;;
    vless-plain) build_vless_plain_links_json "${server}" main ;;
  esac
}
for protocol in ${SUBMAN_APP_PROTOCOLS:-shadowsocks trojan vmess vless-plain hy2}; do
  case "${protocol}" in shadowsocks|trojan|vmess|vless-plain|hy2) ;; *) exit 2 ;; esac
  store_file="${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"
  state_file="${SB_PROTOCOL_STATE_DIR}/${protocol}.env"
  printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"
  jq -n --arg protocol "${protocol}" --arg name "${display_base}-${protocol}" \
    --arg certificate "${TMP_DIR}/naming.crt" --arg key "${TMP_DIR}/naming.key" '
    def user($name; $index):
      if $protocol == "vmess" then
        {name:$name,uuid:(if $index==1 then "11111111-1111-4111-8111-111111111111" else "22222222-2222-4222-8222-222222222222" end),alter_id:0,security:"auto"}
      elif $protocol == "vless-plain" then
        {name:$name,uuid:(if $index==1 then "11111111-1111-4111-8111-111111111111" else "22222222-2222-4222-8222-222222222222" end),flow:""}
      else {name:$name,password:($name+"-synthetic-password")} end;
    {schema_version:1,protocol:$protocol,revision:1,default_instance_id:"main",instances:[
      {id:"main",name:$name,tag:($protocol+"-main"),listen:{address:"::",port:8443},
       authentication:{users:[user("alice";1),user("bob";2)]},outbound_policy:"default",dependencies:[]}
      | if $protocol == "shadowsocks" then
          .listen.network=["tcp","udp"] | .authentication.method="aes-128-gcm" | .authentication.password=""
        else .tls={enabled:true,server_name:"app-naming.example",certificate_path:$certificate,key_path:$key} |
          .client_trust="system" |
          if $protocol == "hy2" then .bandwidth={up_mbps:20,down_mbps:80} | .obfs={enabled:false,type:"",password:""} | .masquerade=""
          else .transport={type:"none"} end
        end
    ]}' > "${store_file}"
  chmod 600 "${state_file}" "${store_file}"
  validate_structured_instance_store "${protocol}" "${store_file}"
  save_plain_proxy_structured_marker "${protocol}"
  SB_PROTOCOL=${protocol}
  CONFIG_SCHEMA_VERSION=2
  SB_MIXED_LISTEN_ADDRESS=0.0.0.0
  [[ "$(list_subman_addresses_for_current_protocol)" == 'IPv4|203.0.113.10' ]]
  SB_MIXED_LISTEN_ADDRESS=::
  [[ "$(list_subman_addresses_for_current_protocol)" == $'IPv4|203.0.113.10\nIPv6|2001:db8::10' ]]
  for address_case in dual concrete; do
    if [[ "${address_case}" == concrete ]]; then
      jq '.instances[0].listen.address="2001:db8::20"' "${store_file}" > "${TMP_DIR}/bound.json"
      mv "${TMP_DIR}/bound.json" "${store_file}"
      SB_MIXED_LISTEN_ADDRESS=2001:db8::20
      [[ "$(list_subman_addresses_for_current_protocol)" == '监听地址|2001:db8::20' ]]
    fi
    addresses=$(list_subman_addresses_for_current_protocol)
    while IFS='|' read -r label server; do
      push_subman_protocol_instance "${protocol}" "${server}" main y "${label}"
      links=$(local_links_for_instance "${protocol}" "${server}")
      [[ "$(jq length <<< "${links}")" -eq 2 ]]
      subman_api_request GET /api/nodes
      [[ "${SUBMAN_LAST_HTTP_STATUS}" == 200 ]]
      while IFS= read -r link; do
        jq -e --arg uri "${link}" 'any(.data[]; .raw==$uri)' <<< "${SUBMAN_LAST_RESPONSE_BODY}" >/dev/null
      done < <(jq -r '.[]' <<< "${links}")
    done <<< "${addresses}"
  done
  printf 'app-backed %s protocol=%s: dual-stack/concrete addresses and local URI parity passed\n' "${stage}" "${protocol}"
done
