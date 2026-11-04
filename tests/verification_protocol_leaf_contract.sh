#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"
# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/remote/scenarios/protocol_cases.sh"

# Validate the shared Docker fixtures against the production store schema and
# renderer. This catches stale fixture fields without installing a core or
# starting any service on the host.
cert_path="${TMP_DIR}/protocol.crt"
key_path="${TMP_DIR}/protocol.key"
openssl req -x509 -newkey ed25519 -nodes -keyout "${key_path}" \
  -out "${cert_path}" -subj /CN=sing-box-vps-verification.invalid \
  -days 1 >/dev/null 2>&1
resolve_config_target_singbox_version() { printf '1.14.0\n'; }

for protocol in mixed socks http shadowsocks trojan vmess snell tuic shadowtls naive hy2 anytls; do
  verification_protocol_record "${protocol}" > "${TMP_DIR}/${protocol}-record.json"
  jq -n --arg protocol "${protocol}" --slurpfile records "${TMP_DIR}/${protocol}-record.json" \
    '{schema_version:1,protocol:$protocol,revision:0,default_instance_id:"main",instances:$records}' \
    > "${TMP_DIR}/${protocol}-store.json"
  chmod 600 "${TMP_DIR}/${protocol}-store.json"
  validate_structured_instance_store "${protocol}" "${TMP_DIR}/${protocol}-store.json"
  render_structured_instance_inbounds "${protocol}" "${TMP_DIR}/${protocol}-store.json" \
    | jq -s -e 'length>0 and all(.[]; .listen=="127.0.0.1" and (.listen_port|type)=="number")' >/dev/null
done
if verification_protocol_record vless-reality > "${TMP_DIR}/unsupported.json" 2>/dev/null; then
  printf 'REALITY must retain its explicit interactive fixture boundary\n' >&2
  exit 1
fi

# Each public leaf must select only its own protocol, even when all wrapper
# definitions are loaded together by the remote dispatcher.
verification_protocol_leaf() { printf '%s:%s\n' "$1" "${2:-none}"; }
for protocol in vless-reality mixed hy2 anytls socks http shadowsocks trojan tuic vmess snell shadowtls naive; do
  scenario="protocol_probe_${protocol//-/_}"
  # shellcheck disable=SC1090
  source "${REPO_ROOT}/dev/verification/remote/scenarios/${scenario}.sh"
  [[ "$("verification_scenario_${scenario}")" == "${protocol}:none" ]]
done
# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/remote/scenarios/protocol_naive_transition.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/remote/scenarios/protocol_snell_transition.sh"
[[ "$(verification_scenario_protocol_naive_transition)" == naive:naive ]]
[[ "$(verification_scenario_protocol_snell_transition)" == snell:snell ]]

printf 'Protocol leaf fixture schemas and independent selectors passed\n'
