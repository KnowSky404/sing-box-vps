#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

assert_name() {
  local actual=$1 expected=$2 message=$3
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "${message}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

short_digest() {
  local digest
  digest=$(printf '%s' "$1" | sha256sum)
  printf '%s' "${digest:0:12}"
}

# The formatter is shared by human-facing links and SubMan payloads. Technical
# IDs and export tags never become part of the base name through this boundary.
assert_name "$(format_node_display_name '德国备用' '' '' '' '')" '德国备用' 'custom name is the base'
assert_name "$(format_node_display_name ' Custom ' '' '' '' IPv4)" Custom-v4 'display base matches SubMan whitespace trimming'
assert_name "$(format_node_display_name $'\tCustom\t' '' '' '' IPv4)" Custom-v4 'edge tabs are render-only whitespace'
assert_name "$(format_node_display_name $'\ufeff\tCustom\u00a0' '' '' '' IPv4)" Custom-v4 'ECMAScript Unicode whitespace is trimmed'
assert_name "$(format_node_display_name $'\u0085Custom\u0085' '' '' '' '')" $'\u0085Custom\u0085' 'NEL is not ECMAScript whitespace'
assert_name "$(format_node_display_name '德国备用' '' '' '' IPv4)" '德国备用-v4' 'IPv4 suffix'
assert_name "$(format_node_display_name '德国备用' '' '' '' IPv6)" '德国备用-v6' 'IPv6 suffix'
assert_name "$(format_node_display_name '德国备用' '' '' '' '监听地址')" '德国备用' 'concrete address label stays unsuffixed'
assert_name "$(format_node_display_name 'edge' 'u-2bd806c97f0e' 20 80 IPv6)" \
  'edge-u-2bd806c97f0e-U20M-D80M-v6' 'user, bandwidth and family ordering'
assert_name "$(format_node_display_name 'edge' '' 20 '' IPv4)" 'edge-U20M-v4' 'upload only'
assert_name "$(format_node_display_name 'edge' '' '' 80 IPv4)" 'edge-D80M-v4' 'download only'

assert_name "$(node_display_address_label '0:0:0:0:0:0:0:0' '2001:db8::20')" IPv6 'expanded IPv6 wildcard uses candidate family'
assert_name "$(node_display_address_label 127.0.0.1 203.0.113.20)" '监听地址' 'concrete listener is not a public-family candidate'
for invalid_name in '' $' \u00a0\ufeff ' $'bad\nname' $'bad\tname'; do
  if format_node_display_name "${invalid_name}" '' '' '' IPv4 > "${TMP_DIR}/invalid-name.out"; then
    printf 'empty or control-character display name unexpectedly accepted\n' >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/invalid-name.out" ]]
done

# UTF-8 limits apply to the complete candidate, including generated suffixes.
# Cropping preserves the suffix and a digest of the original full candidate.
base_253=$(printf '%253s' '' | tr ' ' a)
assert_name "$(format_node_display_name "${base_253}" '' '' '' IPv4)" "${base_253}-v4" 'exact 256-byte name remains intact'
base_254="${base_253}a"
name=$(format_node_display_name "${base_254}" '' '' '' IPv4)
[[ "$(printf '%s' "${name}" | wc -c)" -le 256 ]]
[[ "${name}" == *"-n-$(short_digest "${base_254}-v4")-v4" ]]
long_base=$(jq -nr '"德" * 85')
name=$(format_node_display_name "${long_base}" 'u-2bd806c97f0e' 20 80 IPv6)
[[ "$(printf '%s' "${name}" | wc -c)" -le 256 ]]
[[ "${name}" == *"-n-$(short_digest "${long_base}-u-2bd806c97f0e-U20M-D80M-v6")-u-2bd806c97f0e-U20M-D80M-v6" ]]
printf '%s' "${name}" | python3 -c 'import sys; sys.stdin.buffer.read().decode("utf-8", errors="strict")'
other_name=$(format_node_display_name "${long_base}乙" 'u-2bd806c97f0e' 20 80 IPv6)
[[ "${name}" != "${other_name}" ]]

# Default names use the canonical protocol ID. Existing persisted names and
# legacy fallback names remain independent of this new creation-only helper.
assert_name "$(node_name_host_label)" test-host 'unset display label uses hostname'
for protocol in vless-reality vless-plain hy2 trojan vmess shadowsocks mixed socks http anytls tuic hysteria naive snell shadowtls; do
  assert_name "$(default_instance_node_name "${protocol}")" "test-host-${protocol}-01" "default name for ${protocol}"
done
assert_name "$(default_instance_node_name vless+reality)" test-host-vless-reality-01 'runtime alias uses canonical protocol name'
assert_name "$(default_instance_node_name vless-plain)" test-host-vless-plain-01 'plain VLESS stays distinct from REALITY'
name_snapshot='{"instances":[{"id":"different-id","name":"test-host-hy2-01"},{"id":"custom-id","name":"test-host-hy2-03"},{"id":"hy2-02","name":"A custom name"}]}'
assert_name "$(default_instance_node_name hy2 "${name_snapshot}")" test-host-hy2-02 'next ordinal depends on saved names, not IDs'
assert_name "$(default_node_name_for_protocol hy2)" test-host-hy2 'legacy fallback is preserved'
assert_name "$(default_node_name_for_protocol vless+reality)" test-host-vless 'legacy REALITY fallback is preserved'

alice_suffix="u-$(short_digest alice)"
for protocol in shadowsocks trojan vmess vless-plain hy2; do
  snapshot=$(jq -cn --arg protocol "${protocol}" '{protocol:$protocol,instances:[{id:"main",name:"德国备用",tag:"fixed-inbound-tag",authentication:{users:[{name:"alice"}]},bandwidth:{up_mbps:null,down_mbps:null}}]}')
  assert_name "$(structured_node_display_name "${protocol}" "${snapshot}" main alice IPv4)" \
    '德国备用-v4' "${protocol} single user omits digest"
  snapshot=$(jq -c '.instances[0].authentication.users += [{name:"bob"}]' <<< "${snapshot}")
  assert_name "$(structured_node_display_name "${protocol}" "${snapshot}" main alice IPv6)" \
    "德国备用-${alice_suffix}-v6" "${protocol} multiple users get stable digest"
  reordered=$(jq -c '.instances[0].authentication.users |= reverse' <<< "${snapshot}")
  assert_name "$(structured_node_display_name "${protocol}" "${reordered}" main alice IPv6)" \
    "德国备用-${alice_suffix}-v6" "${protocol} user order is irrelevant"
done

snapshot='{"instances":[{"id":"main","name":"HY2 backup","authentication":{"users":[{"name":"alice"}]},"bandwidth":{"up_mbps":20,"down_mbps":80}}]}'
# Deliberately stale process globals must never override this instance snapshot.
SB_HY2_UP_MBPS=999
SB_HY2_DOWN_MBPS=888
assert_name "$(structured_node_display_name hy2 "${snapshot}" main alice IPv4)" \
  'HY2 backup-U20M-D80M-v4' 'HY2 bandwidth belongs to the captured instance'
assert_name "$(structured_node_display_name trojan "${snapshot}" main alice IPv4)" \
  'HY2 backup-v4' 'unrelated protocols do not inherit HY2 bandwidth'
snapshot=$(jq -c '.instances += [.instances[0] | .id="second"]' <<< "${snapshot}")
assert_name "$(structured_node_display_name hy2 "${snapshot}" main alice IPv4)" \
  "HY2 backup-i-$(short_digest hy2:main)-U20M-D80M-v4" 'duplicate names have stable instance distinction'
[[ "$(structured_node_display_name hy2 "${snapshot}" main alice IPv4)" != "$(structured_node_display_name hy2 "${snapshot}" second alice IPv4)" ]]
snapshot='{"instances":[{"id":"main","name":" Custom ","authentication":{"users":[{"name":"alice"}]}},{"id":"second","name":"Custom","authentication":{"users":[{"name":"alice"}]}}]}'
assert_name "$(structured_node_display_name trojan "${snapshot}" main alice IPv4)" \
  "Custom-i-$(short_digest trojan:main)-v4" 'duplicate names are compared after shared whitespace trimming'
snapshot=$(jq -cn --arg name $'\tCustom\t' '{instances:[{id:"main",name:$name,authentication:{users:[{name:"alice"}]}}]}')
assert_name "$(structured_node_display_name trojan "${snapshot}" main alice IPv4)" \
  Custom-v4 'structured entrypoint trims edge tabs before rejecting interior controls'
for invalid_json_name in '"bad\u0000name"' '"bad\tname"' '"bad\nname"'; do
  invalid_snapshot=$(jq -cn --argjson name "${invalid_json_name}" '{instances:[{id:"main",name:$name,authentication:{users:[{name:"alice"}]}}]}')
  if structured_node_display_name trojan "${invalid_snapshot}" main alice IPv4 >"${TMP_DIR}/invalid-structured-name.out" 2>"${TMP_DIR}/invalid-structured-name.err"; then
    printf 'structured name containing NUL or interior controls unexpectedly accepted\n' >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/invalid-structured-name.out" ]]
done
snapshot='{"instances":[{"id":"main","name":"SS single","authentication":{"users":[]}}]}'
assert_name "$(structured_node_display_name shadowsocks "${snapshot}" main '' IPv4)" \
  'SS single-v4' 'single-credential Shadowsocks omits empty-user digest'

# A rare short-hash collision expands only the user discriminator; changing
# user order must not pick a different winner or rename either identity.
sha256sum() {
  local value
  value=$(cat)
  case "${value}" in
    alice) printf '%s  -\n' aaaaaaaaaaaa1111000000000000000000000000000000000000000000000000 ;;
    bob) printf '%s  -\n' aaaaaaaaaaaa2222000000000000000000000000000000000000000000000000 ;;
    *) printf '%s' "${value}" | command sha256sum ;;
  esac
}
snapshot='{"instances":[{"id":"main","name":"Collision","authentication":{"users":[{"name":"alice"},{"name":"bob"}]}}]}'
assert_name "$(structured_node_display_name trojan "${snapshot}" main alice IPv4)" \
  Collision-u-aaaaaaaaaaaa1111-v4 'colliding user digest expands deterministically'
assert_name "$(structured_node_display_name trojan "${snapshot}" main bob IPv4)" \
  Collision-u-aaaaaaaaaaaa2222-v4 'both collision candidates remain distinct'
reordered=$(jq -c '.instances[0].authentication.users |= reverse' <<< "${snapshot}")
assert_name "$(structured_node_display_name trojan "${reordered}" main alice IPv4)" \
  Collision-u-aaaaaaaaaaaa1111-v4 'digest collision handling ignores order'
unset -f sha256sum

# Preparing a large instance hashes each identity once. Rendering all users
# from that prepared map must not hash the complete sibling set for each user.
# Count subprocess inputs rather than elapsed time or machine performance.
snapshot=$(jq -cn '{instances:[{id:"main",name:"Large",authentication:{users:[range(0;128) | {name:("user-" + ("00" + tostring)[-3:])}]}}]}')
hash_calls="${TMP_DIR}/prepared-user-hashes"
: > "${hash_calls}"
sha256sum() {
  local value
  value=$(cat) || return 1
  case "${value}" in
    user-[0-9][0-9][0-9]) printf '%s\n' "${value}" >> "${hash_calls}" ;;
  esac
  printf '%s' "${value}" | command sha256sum "$@"
}
digest_map=$(structured_node_user_digests "${snapshot}" main)
jq -e 'length == 128 and all(.[]; test("^[0-9a-f]{64}$"))' <<< "${digest_map}" >/dev/null
[[ "$(wc -l < "${hash_calls}")" -eq 128 ]]
[[ "$(sort -u "${hash_calls}" | wc -l)" -eq 128 ]]
: > "${hash_calls}"
: > "${TMP_DIR}/prepared-user-names"
while IFS= read -r prepared_user; do
  prepared_name=$(structured_node_display_name trojan "${snapshot}" main "${prepared_user}" IPv4 "${digest_map}")
  [[ "${prepared_name}" == Large-u-*-v4 ]]
  printf '%s\n' "${prepared_name}" >> "${TMP_DIR}/prepared-user-names"
done < <(jq -r '.instances[0].authentication.users[].name' <<< "${snapshot}")
[[ ! -s "${hash_calls}" ]]
[[ "$(wc -l < "${TMP_DIR}/prepared-user-names")" -eq 128 ]]
[[ "$(sort -u "${TMP_DIR}/prepared-user-names" | wc -l)" -eq 128 ]]
reordered=$(jq -c '.instances[0].authentication.users |= reverse' <<< "${snapshot}")
assert_name "$(structured_node_display_name trojan "${reordered}" main user-000 IPv4 "${digest_map}")" \
  "$(head -n 1 "${TMP_DIR}/prepared-user-names")" 'prepared digests are stable across user order'
for invalid_map in "$(jq -c 'del(.["user-127"])' <<< "${digest_map}")" "$(jq -c '.["user-127"]="malformed-digest"' <<< "${digest_map}")"; do
  if structured_node_display_name trojan "${snapshot}" main user-000 IPv4 "${invalid_map}" >"${TMP_DIR}/invalid-map.out" 2>"${TMP_DIR}/invalid-map.err"; then
    printf 'prepared map with missing or malformed sibling digest unexpectedly accepted\n' >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/invalid-map.out" ]]
done
unset -f sha256sum

# Renaming a display label, changing bandwidth, or shortening the displayed
# user hash must not change the complete legacy external-key resource identity.
SUBMAN_NODE_PREFIX=identity-host
for builder in subman_external_key_for_shadowsocks_user subman_external_key_for_trojan_user subman_external_key_for_vmess_user subman_external_key_for_vless_plain_user subman_external_key_for_hy2_user; do
  before=$("${builder}" main alice IPv4)
  SB_NODE_NAME='A new display name'
  SB_HY2_UP_MBPS=1
  SB_HY2_DOWN_MBPS=2
  after=$("${builder}" main alice IPv4)
  assert_name "${after}" "${before}" "${builder} ignores display-only settings"
  [[ "${after}" == *"user-$(printf alice | sha256sum | cut -d ' ' -f 1):v4" ]]
done

# Legacy client tags may exceed the user-facing 256-byte name budget. Keep
# those exact identifiers so existing selector/route references remain valid.
SB_NODE_NAME=$(jq -nr '"德" * 85')
SB_HY2_UP_MBPS=20
SB_HY2_DOWN_MBPS=80
assert_name "$(client_outbound_tag_for_protocol hy2)" "${SB_NODE_NAME}-U20M-D80M" 'long legacy HY2 technical tag is unchanged'
SB_VLESS_RATE_LIMIT_UP_MBPS=20
SB_VLESS_RATE_LIMIT_DOWN_MBPS=80
assert_name "$(client_outbound_tag_for_protocol vless-reality)" "${SB_NODE_NAME}-U20M-D80M" 'long legacy REALITY technical tag is unchanged'
shortened_display=$(display_node_name_for_protocol hy2 "${SB_NODE_NAME}" IPv4)
[[ "$(printf '%s' "${shortened_display}" | wc -c)" -le 256 ]]
[[ "${shortened_display}" == *-n-*-U20M-D80M-v4 ]]

printf 'Node naming contract passed: canonical defaults, custom names, UTF-8 budget, user/instance distinction and stable identities\n'
