#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

core113=${SINGBOX_BINARY_113:-/tmp/sbv-real-schema-final.6rMcum/sing-box-1.13.18-linux-arm64/sing-box}
core114=${SINGBOX_BINARY_114:-/tmp/sing-box-v1.14.0-cache/sing-box-1.14.0-linux-arm64/sing-box}
if [[ ! -x "${core113}" || ! -x "${core114}" ]]; then
  printf 'SKIP Shadowsocks export client checks: both real cores unavailable (set SINGBOX_BINARY_113/SINGBOX_BINARY_114)\n'
  exit 0
fi

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
printf 'INSTALLED_PROTOCOLS=shadowsocks\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"

server_key='MDEyMzQ1Njc4OWFiY2RlZg=='
server_key_256='MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY='
user_key='YWJjZGVmZ2hpamtsbW5vcA=='
user_key_256='YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXowMTIzNDU='
server_key_long='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
server_key_256_long='BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
user_key_long='CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
user_key_256_long='DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'
classic_single_password=$'classic-aes\n'
classic_multi_user_password=$'erin-secret\n'

jq -n \
  --arg k128 "${server_key}" --arg k256 "${server_key_256}" \
  --arg u128 "${user_key}" --arg u256 "${user_key_256}" \
  --arg server_key_long "${server_key_long}" --arg server_key_256_long "${server_key_256_long}" \
  --arg user_key_long "${user_key_long}" --arg user_key_256_long "${user_key_256_long}" \
  --arg classic_single_password "${classic_single_password}" \
  --arg classic_multi_user_password "${classic_multi_user_password}" \
  'def instance($id;$port;$network;$method;$password;$users):
    {id:$id,name:$id,tag:("ss-"+$id),listen:{address:"127.0.0.1",port:$port,network:$network},
     authentication:{method:$method,password:$password,users:$users},
     outbound_policy:"default",dependencies:[]};
   {schema_version:1,protocol:"shadowsocks",revision:7,default_instance_id:"none",
    instances:[
      instance("none";39001;["tcp","udp"];"none";"";[]),
      instance("aes128-single";39002;["tcp"];"aes-128-gcm";$classic_single_password;[]),
      instance("aes192-single";39003;["udp"];"aes-192-gcm";"classic-aes192";[]),
      instance("aes256-single";39004;["tcp","udp"];"aes-256-gcm";"classic-aes256";[]),
      instance("chacha-single";39005;["tcp"];"chacha20-ietf-poly1305";"classic-chacha";[]),
      instance("xchacha-single";39006;["udp"];"xchacha20-ietf-poly1305";"classic-xchacha";[]),
      instance("a128-2022-single";39007;["tcp","udp"];"2022-blake3-aes-128-gcm";$k128;[]),
      instance("a256-2022-single";39008;["tcp"];"2022-blake3-aes-256-gcm";$k256;[]),
      instance("a128-2022-multi";39009;["udp"];"2022-blake3-aes-128-gcm";$server_key_long;[
        {name:"alice",password:$user_key_long},{name:"bob",password:($user_key_long|sub("C";"E"))}
      ]),
      instance("a256-2022-multi";39010;["tcp","udp"];"2022-blake3-aes-256-gcm";$server_key_256_long;[
        {name:"carol",password:$user_key_256_long},{name:"dave",password:($user_key_256_long|sub("D";"F"))}
      ]),
      instance("classic-multi";39011;["tcp","udp"];"chacha20-ietf-poly1305";"";[
        {name:"erin",password:$classic_multi_user_password},{name:"frank",password:"frank-secret"}
      ]),
      instance("chacha-2022-single";39012;["tcp","udp"];"2022-blake3-chacha20-poly1305";$k256;[])
    ]}' > "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json"
jq '{log:{level:"warn"},inbounds:[.instances[] | {type:"shadowsocks",tag:.tag,listen:.listen.address,listen_port:.listen.port,network:.listen.network,method:.authentication.method,password:.authentication.password,users:.authentication.users}],outbounds:[{type:"direct",tag:"direct"}],route:{final:"direct"}}' \
  "${SB_PROTOCOL_STATE_DIR}/instances/shadowsocks.json" > "${SINGBOX_CONFIG_FILE}"
save_plain_proxy_structured_marker shadowsocks

store_file=$(plain_proxy_structured_store_file shadowsocks)
store_hash_before=$(sha256sum "${store_file}" | awk '{print $1}')
if build_shadowsocks_client_outbounds_from_store "${store_file}" 'bad host' >/dev/null; then
  printf 'Shadowsocks exporter accepted an unsafe server address\n' >&2
  exit 1
fi
[[ "$(sha256sum "${store_file}" | awk '{print $1}')" == "${store_hash_before}" ]]
outbound_lines=$(build_shadowsocks_client_outbounds_from_store "${store_file}" 198.51.100.20)
outbounds_json=$(jq -sc '.' <<< "${outbound_lines}")
jq -e '
  length == 15 and (map(.tag) | unique | length) == length and
  all(.[]; .type == "shadowsocks" and .server == "198.51.100.20" and
      ((has("plugin") or has("plugin_opts") or has("multiplex") or has("udp_over_tcp")) | not))
' <<< "${outbounds_json}" >/dev/null

# Single-user records retain the top-level password; classic multi-user records
# use each user password; SS2022 AES multi-user records combine server:user PSKs.
a128_server_psk=$(shadowsocks_client_psk 2022-blake3-aes-128-gcm "${server_key_long}")
a128_user_psk=$(shadowsocks_client_psk 2022-blake3-aes-128-gcm "${user_key_long}")
a128_user_psk_2=$(shadowsocks_client_psk 2022-blake3-aes-128-gcm "${user_key_long/C/E}")
a256_server_psk=$(shadowsocks_client_psk 2022-blake3-aes-256-gcm "${server_key_256_long}")
a256_user_psk=$(shadowsocks_client_psk 2022-blake3-aes-256-gcm "${user_key_256_long}")
a256_user_psk_2=$(shadowsocks_client_psk 2022-blake3-aes-256-gcm "${user_key_256_long/D/F}")
jq -e --arg k128 "${server_key}" --arg k256 "${server_key_256}" \
  --arg a128_server "${a128_server_psk}" --arg a128_user "${a128_user_psk}" \
  --arg a128_user_2 "${a128_user_psk_2}" --arg a256_server "${a256_server_psk}" \
  --arg a256_user "${a256_user_psk}" --arg a256_user_2 "${a256_user_psk_2}" \
  --arg classic_single_password "${classic_single_password}" \
  --arg classic_multi_user_password "${classic_multi_user_password}" '
  (map(select(.server_port == 39001)) | length) == 1 and
  (map(select(.server_port == 39002)) | .[0].password == $classic_single_password) and
  (map(select(.server_port == 39007)) | .[0].password == $k128) and
  (map(select(.server_port == 39008)) | .[0].password == $k256) and
  ([map(select(.server_port == 39009))[] | .password] | sort) ==
    ([$a128_server+":"+$a128_user, $a128_server+":"+$a128_user_2] | sort) and
  ([map(select(.server_port == 39010))[] | .password] | sort) ==
    ([$a256_server+":"+$a256_user, $a256_server+":"+$a256_user_2] | sort) and
  ([map(select(.server_port == 39011))[] | .password] | sort) == [$classic_multi_user_password,"frank-secret"]
' <<< "${outbounds_json}" >/dev/null

wrapper_lines=$(build_client_shadowsocks_outbounds 198.51.100.20)
wrapper_json=$(jq -sc '.' <<< "${wrapper_lines}")
jq -e 'length == 15 and all(.[]; .server == "127.0.0.1")' <<< "${wrapper_json}" >/dev/null

# The public export dispatcher captures the wrapper in one command substitution;
# keep this separate from jq so Bash 4.2 does not trigger its nested IFS bug.
dispatcher_lines=$(build_client_outbound_json_for_protocol shadowsocks 198.51.100.20)
dispatcher_json=$(jq -sc '.' <<< "${dispatcher_lines}")
jq -e 'length == 15 and all(.[]; .server == "127.0.0.1")' <<< "${dispatcher_json}" >/dev/null

for core in "${core113}" "${core114}"; do
  client_file="${TMP_DIR}/client-$(basename "${core}").json"
  jq -n --argjson remote "${outbounds_json}" \
    '{log:{level:"warn"},inbounds:[],outbounds:($remote+[{type:"direct",tag:"direct"}]),route:{final:"direct"}}' > "${client_file}"
  "${core}" check -c "${client_file}"
done

# User reordering must not change the identity-derived tags.
jq '.instances |= map(if .id == "a128-2022-multi" then .authentication.users |= reverse else . end)' \
  "${store_file}" > "${TMP_DIR}/reordered.json"
reordered_lines=$(build_shadowsocks_client_outbounds_from_store "${TMP_DIR}/reordered.json" 198.51.100.20)
reordered_json=$(jq -sc '.' <<< "${reordered_lines}")
jq -e --argjson before "${outbounds_json}" --argjson after "${reordered_json}" '
  ([$before[] | select(.server_port == 39009) | {password,tag}] | sort_by(.password)) ==
  ([$after[] | select(.server_port == 39009) | {password,tag}] | sort_by(.password))
' <<< '{}' >/dev/null

[[ "$(sha256sum "${store_file}" | awk '{print $1}')" == "${store_hash_before}" ]]
printf 'Shadowsocks export client checks passed: methods=9, outbounds=15, derived-psk=6, stable-user-tags=2, full-core-check=2\n'
