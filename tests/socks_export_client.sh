#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# Source at file scope so Bash 4.2 retains the top-level readonly registry.
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
if [[ "${1:-}" == "check" ]]; then
  exit 0
fi
exit 0
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

get_public_ip() {
  printf '203.0.113.10\n'
}

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
  .links.socks5 == "socks5://user%0A:pass%0A@127.0.0.1:33101" and
  .instance_revision == 7 and (has("http") | not) and
  any(.warnings[]?; .code == "socks_plaintext_transport") and
  all(.warnings[]?; .code != "mixed_plaintext_transport") and
  all(.warnings[]? | select(.code == "socks_plaintext_transport") | .message; contains("UoT v2") | not) and
  any(.warnings[]?; .code == "socks5_uri_transport_options_omitted")
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

# Mixed and SOCKS are both exportable protocols, but an invalid SOCKS state
# must fail the aggregate export before it can replace an existing artifact.
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=mixed,socks
PROTOCOL_STATE_VERSION=1
EOF_INDEX
cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF_MIXED'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed-regression
PORT=2080
AUTH_ENABLED=n
USERNAME=
PASSWORD=
EOF_MIXED

leaked_secret='socks-secret-must-not-leak'
jq --arg secret "${leaked_secret}" \
  '.instances[0].authentication.username = "" | .instances[0].authentication.password = $secret' \
  "${store_file}" > "${store_file}.invalid"
mv "${store_file}.invalid" "${store_file}"
chmod 600 "${store_file}"

export_path="${SB_PROJECT_DIR}/client/sing-box-client.json"
mkdir -p "$(dirname "${export_path}")"
printf 'old-export\n' > "${export_path}"
printf 'old-backup\n' > "${export_path}.bak"
chmod 600 "${export_path}" "${export_path}.bak"
export_hash_before=$(sha256sum "${export_path}" | awk '{print $1}')
backup_hash_before=$(sha256sum "${export_path}.bak" | awk '{print $1}')

aggregate_stderr="${TMP_DIR}/aggregate-invalid.stderr"
aggregate_stdout=''
if aggregate_stdout=$(export_singbox_client_config 2>"${aggregate_stderr}"); then
  printf 'aggregate export unexpectedly succeeded with invalid SOCKS state\n' >&2
  exit 1
fi
[[ -z "${aggregate_stdout}" ]]
if ! grep -Eq 'SOCKS 客户端连接材料无效|structured instance store validate failed' "${aggregate_stderr}"; then
  exit 1
fi
if grep -Fq -- "${leaked_secret}" "${aggregate_stderr}"; then
  printf 'aggregate export leaked invalid SOCKS credentials\n' >&2
  exit 1
fi
[[ "$(sha256sum "${export_path}" | awk '{print $1}')" == "${export_hash_before}" ]]
[[ "$(sha256sum "${export_path}.bak" | awk '{print $1}')" == "${backup_hash_before}" ]]

agent_stderr="${TMP_DIR}/aggregate-agent-invalid.stderr"
agent_output=''
if agent_output=$(agent_cli export-client --json 2>"${agent_stderr}"); then
  printf 'agent aggregate export unexpectedly succeeded with invalid SOCKS state\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "client_config_generation_failed"' <<< "${agent_output}" >/dev/null
if grep -Fq -- "${leaked_secret}" "${agent_stderr}" ||
   grep -Fq -- "${leaked_secret}" <<< "${agent_output}"; then
  printf 'agent aggregate export leaked invalid SOCKS credentials\n' >&2
  exit 1
fi
[[ "$(sha256sum "${export_path}" | awk '{print $1}')" == "${export_hash_before}" ]]
[[ "$(sha256sum "${export_path}.bak" | awk '{print $1}')" == "${backup_hash_before}" ]]

mv "${SB_PROTOCOL_STATE_DIR}/socks.env" "${SB_PROTOCOL_STATE_DIR}/socks.env.missing"
missing_stderr="${TMP_DIR}/aggregate-missing.stderr"
missing_stdout=''
if missing_stdout=$(export_singbox_client_config 2>"${missing_stderr}"); then
  printf 'aggregate export unexpectedly succeeded with missing SOCKS state\n' >&2
  exit 1
fi
[[ -z "${missing_stdout}" ]]
grep -Fq 'SOCKS 状态缺失' "${missing_stderr}"
if grep -Fq -- "${leaked_secret}" "${missing_stderr}"; then
  printf 'missing SOCKS export leaked invalid credentials\n' >&2
  exit 1
fi
[[ "$(sha256sum "${export_path}" | awk '{print $1}')" == "${export_hash_before}" ]]
[[ "$(sha256sum "${export_path}.bak" | awk '{print $1}')" == "${backup_hash_before}" ]]

SB_PROTOCOL=socks
SB_PORT=33101
SB_MIXED_AUTH_ENABLED=n
SB_MIXED_USERNAME=""
SB_MIXED_PASSWORD=""
display=$(show_link_info 127.0.0.1 2>&1)
grep -Fq 'SOCKS5 代理链接' <<< "${display}"
if grep -Fq 'HTTP 代理链接' <<< "${display}"; then
  printf 'SOCKS presentation must not expose an HTTP link\n' >&2
  exit 1
fi

printf 'SOCKS client export and Agent presentation checks passed\n'
