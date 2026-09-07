#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'state-marker\n' > "${SB_PROTOCOL_STATE_DIR}/mixed.env"
state_hash_before=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')

SB_PROTOCOL=mixed
SB_NODE_NAME=share-links
SB_MIXED_INSTANCE_ID=main
SB_MIXED_INBOUND_TAG=mixed-in
SB_MIXED_LISTEN_ADDRESS=127.0.0.1
SB_MIXED_STORE_REVISION=4
SB_PORT=2080
SB_MIXED_AUTH_ENABLED=y
RAW_USER=$'u@:/?#% \né'
RAW_PASSWORD=$'p@:/?#% \t😀'
SB_MIXED_USERNAME="${RAW_USER}"
SB_MIXED_PASSWORD="${RAW_PASSWORD}"

encoded_uri=$(build_plain_proxy_link socks5 2001:db8::10)
[[ "${encoded_uri}" == socks5://* ]]
userinfo=${encoded_uri#socks5://}
userinfo=${userinfo%@*}
encoded_user=${userinfo%%:*}
encoded_password=${userinfo#*:}
RAW_USER="${RAW_USER}" RAW_PASSWORD="${RAW_PASSWORD}" \
  ENCODED_USER="${encoded_user}" ENCODED_PASSWORD="${encoded_password}" \
  python3 - <<'PY'
import os
from urllib.parse import unquote_to_bytes

assert unquote_to_bytes(os.environ["ENCODED_USER"]) == os.environ["RAW_USER"].encode()
assert unquote_to_bytes(os.environ["ENCODED_PASSWORD"]) == os.environ["RAW_PASSWORD"].encode()
PY

[[ "${encoded_uri}" == *'%40%3A%2F%3F%23%25%20%0A%C3%A9'* ]]
[[ "${encoded_uri}" == *'%40%3A%2F%3F%23%25%20%09%F0%9F%98%80'* ]]
[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')" == "${state_hash_before}" ]]

SB_MIXED_AUTH_ENABLED=n
SB_MIXED_USERNAME=stale-user
SB_MIXED_PASSWORD=stale-password
[[ "$(build_plain_proxy_link socks5 203.0.113.10)" == 'socks5://203.0.113.10:2080' ]]
[[ "$(build_plain_proxy_link http 203.0.113.10)" == 'http://203.0.113.10:2080' ]]
[[ "$(build_plain_proxy_link socks5 2001:db8::10)" == 'socks5://[2001:db8::10]:2080' ]]

SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME='colon:user'
SB_MIXED_PASSWORD='safe-password'
http_stderr="${TMP_DIR}/http-colon.stderr"
if http_output=$(build_plain_proxy_link http 203.0.113.10 2>"${http_stderr}"); then
  printf 'HTTP link unexpectedly represented a colon username: %s\n' "${http_output}" >&2
  exit 1
fi
[[ -z "${http_output}" ]]
grep -Fq 'mixed_http_auth_unrepresentable' "${http_stderr}"
if [[ "$(<"${http_stderr}")" == *safe-password* ]]; then
  printf 'HTTP warning leaked credentials\n' >&2
  exit 1
fi

SB_MIXED_USERNAME='valid-user'
SB_MIXED_PASSWORD=$'safe-password\n'
if build_plain_proxy_link http 203.0.113.10 >"${TMP_DIR}/http-control.out" 2>"${TMP_DIR}/http-control.stderr"; then
  printf 'HTTP link unexpectedly represented a control-character password\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/http-control.out" ]]
if grep -Fq 'safe-password' "${TMP_DIR}/http-control.stderr"; then
  printf 'HTTP warning leaked a control-character password\n' >&2
  exit 1
fi

SB_MIXED_USERNAME='colon:user'
mixed_links=$(build_plain_proxy_links_json mixed 203.0.113.10)
jq -e '
  (has("http") | not) and
  (.socks5 | startswith("socks5://colon%3Auser:safe-password%0A@203.0.113.10:2080"))
' <<< "${mixed_links}" >/dev/null

SB_PROTOCOL=mixed
SB_MIXED_USERNAME='colon:user'
SB_MIXED_PASSWORD=$'safe-password\n'
mixed_agent_links=$(agent_link_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "mixed" and
  (.links | has("http") | not) and
  (.links.socks5 | contains("colon%3Auser")) and
  any(.warnings[]?; .code == "mixed_http_auth_unrepresentable") and
  any(.warnings[]?; .code == "socks5_uri_transport_options_omitted")
' <<< "${mixed_agent_links}" >/dev/null

SB_PROTOCOL=socks
SB_MIXED_LISTEN_ADDRESS=0.0.0.0
SB_MIXED_USERNAME="${RAW_USER}"
SB_MIXED_PASSWORD="${RAW_PASSWORD}"
socks_agent_links=$(agent_link_json_for_current_protocol 2001:db8::10)
jq -e '
  .protocol == "socks" and
  (.links | keys) == ["socks5"] and
  (.links.socks5 | startswith("socks5://u%40%3A%2F%3F%23%25%20%0A%C3%A9:")) and
  (.links.socks5 | contains("@[2001:db8::10]:2080")) and
  (has("http") | not) and
  any(.warnings[]?; .code == "socks5_uri_transport_options_omitted")
' <<< "${socks_agent_links}" >/dev/null

SB_PROTOCOL=mixed
display=$(show_link_info 203.0.113.10 2>"${TMP_DIR}/display.stderr")
grep -Fq 'Mixed SOCKS5 代理链接' <<< "${display}" || {
  printf 'Mixed display omitted SOCKS5 link\n' >&2
  exit 1
}
grep -Fq 'u%40%3A%2F%3F%23%25' <<< "${display}" || {
  printf 'Mixed display did not preserve encoded SOCKS credentials\n' >&2
  exit 1
}

SB_PROTOCOL=socks
if [[ "$(build_plain_proxy_links_json socks 203.0.113.10)" == *'"http"'* ]]; then
  printf 'SOCKS links unexpectedly exposed HTTP\n' >&2
  exit 1
fi

SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME='valid-user'
SB_MIXED_PASSWORD='valid-password'
original_encoder=$(declare -f encode_uri_userinfo_component)
encode_uri_userinfo_component() {
  return 73
}
encoder_output=''
if encoder_output=$(agent_link_json_for_current_protocol 203.0.113.10); then
  printf 'Agent links unexpectedly succeeded after encoder failure: %s\n' "${encoder_output}" >&2
  exit 1
fi
[[ -z "${encoder_output}" ]]
eval "${original_encoder}"

SB_MIXED_AUTH_ENABLED=''
if build_plain_proxy_link socks5 203.0.113.10 >"${TMP_DIR}/missing.out" 2>"${TMP_DIR}/missing.stderr"; then
  printf 'missing authentication flag was accepted\n' >&2
  exit 1
fi
[[ ! -s "${TMP_DIR}/missing.out" ]]

SB_MIXED_AUTH_ENABLED=n
if build_plain_proxy_link invalid 203.0.113.10 >/dev/null 2>"${TMP_DIR}/invalid.stderr"; then
  printf 'invalid proxy link scheme was accepted\n' >&2
  exit 1
fi
if build_plain_proxy_link socks5 'bad host' >/dev/null 2>"${TMP_DIR}/bad-host.stderr"; then
  printf 'invalid proxy link host was accepted\n' >&2
  exit 1
fi

[[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/mixed.env" | awk '{print $1}')" == "${state_hash_before}" ]]
printf 'plain proxy share-link checks passed\n'
