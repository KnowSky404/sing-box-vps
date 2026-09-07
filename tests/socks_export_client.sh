#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope so Bash 4.2 retains the top-level readonly registry.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
store_file="${SB_PROTOCOL_STATE_DIR}/instances/socks.json"
jq -n '
  {
    schema_version: 1,
    protocol: "socks",
    revision: 7,
    default_instance_id: "mixed",
    instances: [{
      id: "mixed",
      name: "SOCKS primary",
      tag: "socks-primary",
      listen: {address: "127.0.0.1", port: 33101},
      authentication: {enabled: true, username: "user\n", password: "pass\n"},
      outbound_policy: "default",
      dependencies: []
    }]
  }
' > "${store_file}"
chmod 600 "${store_file}"
save_plain_proxy_structured_marker socks
plain_proxy_structured_state_active socks

outbounds=$(build_client_outbound_json_for_protocol socks 203.0.113.10 | jq -s .)
jq -e '
  length == 1 and
  .[0].type == "socks" and .[0].tag == "socks-mixed" and
  .[0].server == "127.0.0.1" and .[0].server_port == 33101 and
  .[0].version == "5" and .[0].udp_over_tcp.enabled == true and
  .[0].udp_over_tcp.version == 2 and
  .[0].username == "user\n" and .[0].password == "pass\n"
' <<< "${outbounds}" >/dev/null

load_plain_proxy_structured_instance socks mixed
summary=$(agent_node_summary_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "socks" and .client_exportable == true and
  .auth_enabled == true and .instance_revision == 7 and
  .instance_id == "mixed" and .tag == "socks-primary" and
  .listen.address == "127.0.0.1" and .listen.port == 33101 and
  (has("username") | not) and (has("password") | not)
' <<< "${summary}" >/dev/null

links=$(agent_link_json_for_current_protocol 203.0.113.10)
jq -e '
  .protocol == "socks" and (.links | keys) == ["socks5"] and
  .links.socks5 == "socks5://user\n:pass\n@127.0.0.1:33101" and
  .instance_revision == 7 and (has("http") | not) and
  any(.warnings[]?; .code == "socks_plaintext_transport") and
  all(.warnings[]?; .code != "mixed_plaintext_transport") and
  all(.warnings[]?.message; contains("UoT v2") | not)
' <<< "${links}" >/dev/null

mixed_warning=$(collect_client_export_warnings_json \
  '{"outbounds":[{"type":"socks","tag":"mixed-out"}]}')
jq -e 'length == 1 and .[0].code == "mixed_plaintext_transport"' \
  <<< "${mixed_warning}" >/dev/null

socks_warning=$(collect_client_export_warnings_json \
  '{"outbounds":[{"type":"socks","tag":"socks-out"}]}')
jq -e 'length == 1 and .[0].code == "socks_plaintext_transport"' \
  <<< "${socks_warning}" >/dev/null

unmarked_warning=$(collect_client_export_warnings_json \
  '{"outbounds":[{"type":"socks"}]}')
jq -e 'length == 1 and .[0].code == "socks_plaintext_transport"' \
  <<< "${unmarked_warning}" >/dev/null
jq -e '.[0].message | contains("UoT v2") | not' \
  <<< "${unmarked_warning}" >/dev/null

both_warnings=$(collect_client_export_warnings_json \
  '{"outbounds":[{"type":"socks","tag":"mixed-main"},{"type":"socks","tag":"socks-main"},{"type":"socks","tag":"socks-extra"}]}')
jq -e '[.[].code] | sort == ["mixed_plaintext_transport", "socks_plaintext_transport"]' \
  <<< "${both_warnings}" >/dev/null

SB_MIXED_AUTH_ENABLED=y
SB_MIXED_USERNAME=''
SB_MIXED_PASSWORD=''
invalid_stderr="${TMP_DIR}/invalid-socks.stderr"
invalid_output=''
if invalid_output=$(build_client_plain_proxy_outbound socks 203.0.113.10 socks-out 2>"${invalid_stderr}"); then
  printf 'invalid SOCKS state unexpectedly exported: %s\n' "${invalid_output}" >&2
  exit 1
fi
[[ -z "${invalid_output}" ]]
grep -Fq 'socks_export_state_invalid' "${invalid_stderr}"
if grep -Fq 'mixed_export_state_invalid' "${invalid_stderr}"; then
  printf 'SOCKS diagnostic used the Mixed error code\n' >&2
  exit 1
fi

display=$(show_link_info 127.0.0.1 2>&1)
grep -Fq 'SOCKS5 代理链接' <<< "${display}"
if grep -Fq 'HTTP 代理链接' <<< "${display}"; then
  printf 'SOCKS presentation must not expose an HTTP link\n' >&2
  exit 1
fi

printf 'SOCKS client export and Agent presentation checks passed\n'
