#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "Shadowsocks structured takeover failed at line %s\n" "${LINENO}" >&2' ERR

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=shadowsocks\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
ss128_key='AAAAAAAAAAAAAAAAAAAAAA=='
ss256_key='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
ss256_user_key='BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
jq -n --arg ss128 "${ss128_key}" --arg ss256 "${ss256_key}" --arg ss256_user "${ss256_user_key}" '
  {log:{level:"warn"},inbounds:[
    {type:"shadowsocks",tag:"ss-none",listen:"::ffff:127.0.0.1",listen_port:33401,method:"none",password:""},
    {type:"shadowsocks",tag:"ss-a128",listen:"0.0.0.0",listen_port:33402,method:"aes-128-gcm",password:"classic-a128",network:"tcp"},
    {type:"shadowsocks",tag:"ss-a256-multi",listen_port:33403,method:"aes-256-gcm",password:"",users:[{name:"alpha",password:"alpha-password"},{name:"beta",password:"beta-password"}]},
    {type:"shadowsocks",tag:"ss-chacha",listen_port:33404,method:"chacha20-ietf-poly1305",password:"classic-chacha",network:["udp"]},
    {type:"shadowsocks",tag:"ss-xchacha",listen_port:33405,method:"xchacha20-ietf-poly1305",password:"classic-xchacha"},
    {type:"shadowsocks",tag:"ss-2022-a128",listen_port:33406,method:"2022-blake3-aes-128-gcm",password:$ss128},
    {type:"shadowsocks",tag:"ss-2022-a256",listen_port:33407,method:"2022-blake3-aes-256-gcm",password:$ss256},
    {type:"shadowsocks",tag:"ss-2022-a256-multi",listen_port:33408,method:"2022-blake3-aes-256-gcm",password:$ss256,users:[{name:"u1",password:$ss256},{name:"u2",password:$ss256_user}]},
    {type:"shadowsocks",tag:"ss-2022-chacha",listen_port:33409,method:"2022-blake3-chacha20-poly1305",password:$ss256}
  ],outbounds:[{type:"direct",tag:"direct"}],route:{rules:[],final:"direct"}}
' > "${SINGBOX_CONFIG_FILE}"

candidate=$(shadowsocks_config_store_candidate)
jq -e --arg k128 "${ss128_key}" --arg k256 "${ss256_key}" '
  .protocol == "shadowsocks" and .revision == 1 and .default_instance_id == "ss-2022-a128" and
  (.instances|length) == 9 and
  (any(.instances[];.tag == "ss-none" and .listen.address == "::ffff:127.0.0.1")) and
  (any(.instances[];.tag == "ss-none" and .listen.network == ["tcp","udp"])) and
  (any(.instances[];.tag == "ss-a128" and .listen.network == ["tcp"])) and
  (any(.instances[];.tag == "ss-chacha" and .listen.network == ["udp"])) and
  (any(.instances[];.tag == "ss-none" and .authentication == {method:"none",password:"",users:[]})) and
  (any(.instances[];.tag == "ss-a256-multi" and .authentication.password == "" and ([.authentication.users[].name]|sort)==["alpha","beta"])) and
  (any(.instances[];.tag == "ss-2022-a128" and .authentication.password == $k128 and (.authentication.users|length)==0)) and
  (any(.instances[];.tag == "ss-2022-a256-multi" and .authentication.password == $k256 and (.authentication.users|length)==2 and .authentication.users[0].password == $k256 and .authentication.users[1].password != $k256))
' <<< "${candidate}" >/dev/null

# A full IPv4-mapped IPv6 spelling must survive takeover extraction.  The
# listener resource projection canonicalizes it for collision checks, while
# the typed store intentionally preserves the user's original address.
full_mapped_config="${TMP_DIR}/full-mapped.json"
jq '(.inbounds[] | select(.tag == "ss-none")).listen = "0:0:0:0:0:ffff:127.0.0.1"' \
  "${SINGBOX_CONFIG_FILE}" >"${full_mapped_config}"
full_mapped_store_file=$(plain_proxy_structured_store_file shadowsocks)
full_mapped_candidate=$(plain_proxy_config_store_candidate ss "${full_mapped_config}" "${full_mapped_store_file}")
jq -e 'any(.instances[]; .tag == "ss-none" and .listen.address == "0:0:0:0:0:ffff:127.0.0.1")' \
  <<< "${full_mapped_candidate}" >/dev/null

jq '.inbounds[1].network=[]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/empty-network.json"
mv "${TMP_DIR}/empty-network.json" "${SINGBOX_CONFIG_FILE}"
candidate=$(shadowsocks_config_store_candidate)
jq -e '.revision == 1 and any(.instances[];.tag == "ss-a128" and .listen.network == ["tcp","udp"])' <<< "${candidate}" >/dev/null

rebuild_protocol_state_from_config
store_file=$(plain_proxy_structured_store_file shadowsocks)
jq -e 'any(.instances[];.tag == "ss-none" and .listen.address == "::ffff:127.0.0.1")' "${store_file}" >/dev/null
plain_proxy_structured_state_active shadowsocks
plain_proxy_validate_state_inventory shadowsocks
plain_proxy_structured_state_matches_config shadowsocks
protocol_state_matches_config shadowsocks
agent_validate_indexed_protocol_states shadowsocks
grep -Fqx 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/shadowsocks.env"

jq '(.instances[]|select(.tag=="ss-a256-multi")|.name)="Multi display name"' "${store_file}" > "${TMP_DIR}/named-store.json"
mv "${TMP_DIR}/named-store.json" "${store_file}"
jq '.inbounds |= reverse' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/reordered.json"
mv "${TMP_DIR}/reordered.json" "${SINGBOX_CONFIG_FILE}"
candidate=$(shadowsocks_config_store_candidate)
jq -e '.revision==1 and .default_instance_id=="ss-2022-a128" and (.instances|length)==9 and any(.instances[];.tag=="ss-a256-multi" and .id=="ss-a256-multi" and .name=="Multi display name" and .authentication.users[1].password=="beta-password")' <<< "${candidate}" >/dev/null
rebuild_protocol_state_from_config
protocol_state_matches_config shadowsocks

jq '(.inbounds |= map(if .tag == "ss-a128" then .listen="127.0.0.1" | .listen_port=33401 else . end))' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/mapped-collision.json"
mv "${TMP_DIR}/mapped-collision.json" "${SINGBOX_CONFIG_FILE}"
if shadowsocks_config_store_candidate >/dev/null 2>"${TMP_DIR}/mapped-collision.stderr"; then
  printf 'expected mapped IPv4 and IPv4 listener collision to be rejected\n' >&2; exit 1
fi
jq '(.inbounds |= map(if .tag == "ss-a128" then .listen="0.0.0.0" | .listen_port=33402 else . end))' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/mapped-restored.json"
mv "${TMP_DIR}/mapped-restored.json" "${SINGBOX_CONFIG_FILE}"

before_tree=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum)
jq '.inbounds[0].multiplex={enabled:true}' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-mux.json"
mv "${TMP_DIR}/bad-mux.json" "${SINGBOX_CONFIG_FILE}"
if shadowsocks_config_store_candidate >/dev/null 2>"${TMP_DIR}/bad-mux.stderr"; then
  printf 'expected Shadowsocks multiplex field to be rejected\n' >&2; exit 1
fi
grep -Fq '[ERROR] shadowsocks_store_candidate:' "${TMP_DIR}/bad-mux.stderr"
if grep -Eq 'alpha-password|beta-password' "${TMP_DIR}/bad-mux.stderr"; then
  printf 'Shadowsocks diagnostics leaked a credential\n' >&2; exit 1
fi
if rebuild_protocol_state_from_config >"${TMP_DIR}/bad-mux.stdout" 2>"${TMP_DIR}/bad-mux-rebuild.stderr"; then
  printf 'expected Shadowsocks lossy rebuild to fail\n' >&2; exit 1
fi
after_tree=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum)
[[ "${before_tree}" == "${after_tree}" ]]

jq 'del(.inbounds[0].multiplex)|.inbounds[1].network=["tcp","tcp"]' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-network.json"
mv "${TMP_DIR}/bad-network.json" "${SINGBOX_CONFIG_FILE}"
if shadowsocks_config_store_candidate >/dev/null 2>"${TMP_DIR}/bad-network.stderr"; then
  printf 'expected duplicate Shadowsocks network to be rejected\n' >&2; exit 1
fi
jq '.inbounds[1].network=["tcp"]|.inbounds[2].password="unsafe-top-level-password"' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/bad-multi.json"
mv "${TMP_DIR}/bad-multi.json" "${SINGBOX_CONFIG_FILE}"
if shadowsocks_config_store_candidate >/dev/null 2>"${TMP_DIR}/bad-multi.stderr"; then
  printf 'expected classic multi Shadowsocks password to be rejected\n' >&2; exit 1
fi

rendered_inbounds=$(render_structured_instance_inbounds shadowsocks "${store_file}" | jq -s .)
jq --argjson inbounds "${rendered_inbounds}" '.inbounds=$inbounds' "${SINGBOX_CONFIG_FILE}" > "${TMP_DIR}/rendered.json"
core_checks=0
for core_binary in "${SINGBOX_BINARY_113:-}" "${SINGBOX_BINARY_114:-}"; do
  if [[ -n "${core_binary}" && -x "${core_binary}" ]]; then
    "${core_binary}" check -c "${TMP_DIR}/rendered.json"
    core_checks=$((core_checks + 1))
  else
    printf 'SKIP Shadowsocks real-core check: binary unavailable\n'
  fi
done

printf 'Shadowsocks structured takeover checks passed; real core checks=%s\n' "${core_checks}"
