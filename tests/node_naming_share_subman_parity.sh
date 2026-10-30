#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

trap 'printf "Node naming share/SubMan parity failed at line %s\n" "${LINENO}" >&2' ERR
mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=naming.example \
  -keyout "${TMP_DIR}/naming.key" -out "${TMP_DIR}/naming.crt" >/dev/null 2>"${TMP_DIR}/openssl.err"
SUBMAN_NODE_PREFIX=identity-host
curl() { printf 'unexpected network request in naming parity test\n' >&2; return 99; }
systemctl() { printf 'unexpected service operation in naming parity test\n' >&2; return 99; }
MOCK_KEYS=()
MOCK_PAYLOADS=()
push_subman_node() {
  MOCK_KEYS+=("${1}")
  MOCK_PAYLOADS+=("${2}")
  return 0
}

uri_display_name() {
  python3 -c '
import base64, json, sys
from urllib.parse import unquote, urlsplit
uri = sys.stdin.read()
if uri.startswith("vmess://"):
    payload = uri[len("vmess://"):]
    decoded = base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
    print(json.loads(decoded)["ps"], end="")
else:
    print(unquote(urlsplit(uri).fragment), end="")
'
}

local_links_for_instance() {
  local protocol=$1 server=$2 instance_id=$3 result
  case "${protocol}" in
    shadowsocks) build_shadowsocks_links_json "${server}" "${instance_id}" ;;
    trojan)
      result=$(build_trojan_subman_links_and_warnings_json "${server}" "${instance_id}") || return 1
      jq -c '.links' <<< "${result}"
      ;;
    vmess) build_vmess_links_json "${server}" "${instance_id}" ;;
    vless-plain) build_vless_plain_links_json "${server}" "${instance_id}" ;;
    hy2)
      result=$(build_hy2_subman_links_and_warnings_json "${server}" "${instance_id}") || return 1
      jq -c '.links' <<< "${result}"
      ;;
    *) return 1 ;;
  esac
}

assert_share_push_parity() {
  local protocol=$1 instance_id=$2 server=$3 address_label=$4 expected_count=$5
  local local_links payload uri name key expected_suffix selected_user technical_key
  local_links=$(local_links_for_instance "${protocol}" "${server}" "${instance_id}") || return 1
  [[ "$(jq 'length' <<< "${local_links}")" == "${expected_count}" ]] || return 1
  MOCK_KEYS=(); MOCK_PAYLOADS=()
  case "${protocol}" in
    shadowsocks) push_subman_shadowsocks_instance "${instance_id}" "${server}" y "${address_label}" ;;
    trojan) push_subman_trojan_instance "${instance_id}" "${server}" y "${address_label}" ;;
    vmess) push_subman_vmess_instance "${instance_id}" "${server}" y "${address_label}" ;;
    vless-plain) push_subman_vless_plain_instance "${instance_id}" "${server}" y "${address_label}" ;;
    hy2) push_subman_hy2_instance "${instance_id}" "${server}" y "${address_label}" ;;
    *) return 1 ;;
  esac
  [[ ${#MOCK_PAYLOADS[@]} == "${expected_count}" ]] || return 1
  for payload in "${MOCK_PAYLOADS[@]}"; do
    uri=$(jq -er '.raw' <<< "${payload}") || return 1
    name=$(jq -er '.name' <<< "${payload}") || return 1
    [[ "$(printf '%s' "${uri}" | uri_display_name)" == "${name}" ]] || return 1
    # Compare complete real URIs, so protocol fields and the displayed name must
    # refer to the same captured user, instance, address and credentials.
    jq -e --arg uri "${uri}" 'any(.[]; . == $uri)' <<< "${local_links}" >/dev/null || return 1
    [[ "${name}" != *identity-host* && "${name}" != *user-YWxpY2U* ]] || return 1
    case "${address_label}" in
      IPv4) [[ "${name}" == *-v4 ]] || return 1 ;;
      IPv6) [[ "${name}" == *-v6 ]] || return 1 ;;
      *) [[ "${name}" != *-v4 && "${name}" != *-v6 ]] || return 1 ;;
    esac
  done
  # Link-map keys stay technical IDs even though all URI remarks change.
  if [[ "${protocol}" == shadowsocks && "${instance_id}" == single ]]; then
    jq -e 'keys == ["shadowsocks-single-single"]' <<< "${local_links}" >/dev/null || return 1
  else
    while IFS= read -r selected_user; do
      technical_key="${protocol}-${instance_id}-user-$(printf '%s' "${selected_user}" | base64 -w0)"
      jq -e --arg key "${technical_key}" 'has($key)' <<< "${local_links}" >/dev/null || return 1
    done < <(jq -r --arg id "${instance_id}" '.instances[]|select(.id==$id)|.authentication.users[].name' "${store_file}")
  fi
}

for protocol in shadowsocks trojan vmess vless-plain hy2; do
  store_file="${SB_PROTOCOL_STATE_DIR}/instances/${protocol}.json"
  state_file="${SB_PROTOCOL_STATE_DIR}/${protocol}.env"
  printf '%s\n' INSTALLED=1 CONFIG_SCHEMA_VERSION=2 > "${state_file}"
  jq -n --arg protocol "${protocol}" --arg certificate "${TMP_DIR}/naming.crt" --arg key "${TMP_DIR}/naming.key" '
    def user($name; $index):
      if $protocol == "vmess" then
        {name:$name,uuid:(if $index==1 then "11111111-1111-4111-8111-111111111111" else "22222222-2222-4222-8222-222222222222" end),alter_id:0,security:"auto"}
      elif $protocol == "vless-plain" then
        {name:$name,uuid:(if $index==1 then "11111111-1111-4111-8111-111111111111" else "22222222-2222-4222-8222-222222222222" end),flow:""}
      else {name:$name,password:($name + "-synthetic-password")} end;
    {schema_version:1,protocol:$protocol,revision:7,default_instance_id:"multi",instances:
      [{id:"single",name:"德国单用户",port:443,users:[user("alice";1)]},
       {id:"multi",name:"德国多用户",port:8443,users:[user("alice";1),user("bob";2)]}]
      | map(. as $entry |
        {id:$entry.id,name:$entry.name,tag:($protocol + "-" + $entry.id),listen:{address:"::",port:$entry.port},
         authentication:{users:$entry.users},outbound_policy:"default",dependencies:[]}
        | if $protocol == "shadowsocks" then
            .listen.network=["tcp","udp"] |
            .authentication={method:"aes-128-gcm",password:(if .id=="single" then "single-synthetic-password" else "" end),users:(if .id=="single" then [] else $entry.users end)}
          else
            .tls={enabled:true,server_name:"naming.example",certificate_path:$certificate,key_path:$key} |
            .client_trust="system" |
            if $protocol == "hy2" then
              .bandwidth={up_mbps:20,down_mbps:80} | .obfs={enabled:false,type:"",password:""} | .masquerade=""
            else .transport={type:"none"} end
          end)
    }' > "${store_file}"
  chmod 600 "${state_file}" "${store_file}"
  validate_structured_instance_store "${protocol}" "${store_file}"
  save_plain_proxy_structured_marker "${protocol}"
  assert_share_push_parity "${protocol}" multi 203.0.113.20 IPv4 2
  first_keys=$(printf '%s\n' "${MOCK_KEYS[@]}" | sort)
  before_link_keys=$(local_links_for_instance "${protocol}" 203.0.113.20 multi | jq -c 'keys')
  assert_share_push_parity "${protocol}" multi 2001:db8::20 IPv6 2
  assert_share_push_parity "${protocol}" single 203.0.113.20 IPv4 1
  for payload in "${MOCK_PAYLOADS[@]}"; do
    name=$(jq -r '.name' <<< "${payload}")
    [[ "${name}" != *-u-* && "${name}" != *single-e3b0* ]]
  done

  # Editing display names or user ordering preserves external identities and
  # technical keys, while duplicate human names receive instance distinction.
  jq '.instances |= map(.name="同名备用" | .authentication.users |= reverse)' \
    "${store_file}" > "${TMP_DIR}/renamed.json"
  mv "${TMP_DIR}/renamed.json" "${store_file}"
  assert_share_push_parity "${protocol}" multi 203.0.113.20 IPv4 2
  [[ "$(printf '%s\n' "${MOCK_KEYS[@]}" | sort)" == "${first_keys}" ]]
  [[ "$(local_links_for_instance "${protocol}" 203.0.113.20 multi | jq -c 'keys')" == "${before_link_keys}" ]]
  for payload in "${MOCK_PAYLOADS[@]}"; do
    [[ "$(jq -r '.name' <<< "${payload}")" == 同名备用-i-*-u-* ]]
  done
  jq '.instances |= map(.listen.address="127.0.0.1")' "${store_file}" > "${TMP_DIR}/concrete.json"
  mv "${TMP_DIR}/concrete.json" "${store_file}"
  assert_share_push_parity "${protocol}" multi 127.0.0.1 '监听地址' 2
  printf 'share/SubMan parity: protocol=%s single=1 multi=2 IPv4=ok IPv6=ok concrete=ok rename=stable\n' "${protocol}"
done

# A store changed during an outbound producer must fail closed instead of
# combining the initial human name with a later snapshot of credentials.
store_file="${SB_PROTOCOL_STATE_DIR}/instances/vmess.json"
declare -f build_client_vmess_outbounds | sed '1s/build_client_vmess_outbounds/original_build_client_vmess_outbounds/' \
  > "${TMP_DIR}/real-vmess-outbounds.sh"
# shellcheck disable=SC1090
source "${TMP_DIR}/real-vmess-outbounds.sh"
build_client_vmess_outbounds() {
  local captured
  captured=$(original_build_client_vmess_outbounds "$@") || return 1
  jq '.revision += 1 | .instances[0].name="raced display name"' "${store_file}" > "${TMP_DIR}/raced.json" || return 1
  mv "${TMP_DIR}/raced.json" "${store_file}" || return 1
  printf '%s\n' "${captured}"
}
if build_vmess_links_json 127.0.0.1 multi >"${TMP_DIR}/race.out" 2>"${TMP_DIR}/race.err"; then
  printf 'raced naming/credential snapshot unexpectedly accepted\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/race.out" ]]
printf 'Node naming share/SubMan parity passed for five structured protocols; concurrent snapshot change rejected\n'
