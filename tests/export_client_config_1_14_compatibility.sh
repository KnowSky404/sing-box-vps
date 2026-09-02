#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

SB_HY2_DOMAIN=hy2.example.com
SB_HY2_PASSWORD=hy2-password
SB_HY2_USER_NAME=hy2-user
SB_HY2_PORT=443
SB_HY2_TLS_MODE=manual
SB_HY2_CERT_PATH="${TMP_DIR}/ed25519.crt"
SB_HY2_KEY_PATH="${TMP_DIR}/ed25519.key"
openssl req -x509 -newkey ed25519 -nodes -keyout "${SB_HY2_KEY_PATH}" -out "${SB_HY2_CERT_PATH}" -subj /CN=hy2.example.com -days 1 >/dev/null 2>&1

SB_VERSION=1.14.0
[[ "$(hy2_manual_certificate_algorithm)" == ED25519 ]] || { printf 'expected Ed25519 certificate detection\n' >&2; exit 1; }
hy2_manual_certificate_uses_ed25519 || { printf 'expected Ed25519 capability detection\n' >&2; exit 1; }
outbound=$(build_client_hy2_outbound 203.0.113.10)
jq -e '.disable_chrome_parrot == true' <<< "${outbound}" >/dev/null || { printf '1.14 Ed25519 Hy2 export must disable chrome parrot\n' >&2; exit 1; }

SB_VERSION=1.13.18
outbound=$(build_client_hy2_outbound 203.0.113.10)
jq -e '(.disable_chrome_parrot? == null)' <<< "${outbound}" >/dev/null || { printf '1.13 Hy2 export must not contain chrome-parrot override\n' >&2; exit 1; }

# A non-Ed25519 certificate must never receive the 1.14 override.
openssl req -x509 -newkey rsa:2048 -nodes -keyout "${TMP_DIR}/rsa.key" -out "${TMP_DIR}/rsa.crt" -subj /CN=hy2.example.com -days 1 >/dev/null 2>&1
SB_HY2_CERT_PATH="${TMP_DIR}/rsa.crt" SB_HY2_KEY_PATH="${TMP_DIR}/rsa.key" SB_VERSION=1.14.0
outbound=$(build_client_hy2_outbound 203.0.113.10)
jq -e '(.disable_chrome_parrot? == null)' <<< "${outbound}" >/dev/null || { printf 'RSA Hy2 export must not disable chrome parrot\n' >&2; exit 1; }

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=hy2\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<EOF_STATE
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=443
DOMAIN=hy2.example.com
PASSWORD=hy2-password
USER_NAME=hy2-user
UP_MBPS=
DOWN_MBPS=
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=${TMP_DIR}/ed25519.crt
KEY_PATH=${TMP_DIR}/ed25519.key
MASQUERADE=
EOF_STATE
load_protocol_state hy2
SB_VERSION=1.14.0
links=$(agent_link_json_for_current_protocol 203.0.113.10)
jq -e '.warnings[] | select(.code == "hy2_ed25519_share_link_requires_client_override")' <<< "${links}" >/dev/null || { printf 'agent links must expose the stable Ed25519 warning code\n' >&2; exit 1; }

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
[[ "${1:-}" == check ]] && exit 0
exit 0
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"
export_config=$(build_singbox_client_config)
jq -e '.route.rule_set | all(.[]; .http_client.detour == "proxy" and (.download_detour? == null))' <<< "${export_config}" >/dev/null || { printf '1.14 client remote rule-sets must use http_client.detour=proxy\n' >&2; exit 1; }
if [[ -n "${SINGBOX_BINARY_114:-}" ]]; then
  printf '%s\n' "${export_config}" > "${TMP_DIR}/client-114.json"
  "${SINGBOX_BINARY_114}" check -c "${TMP_DIR}/client-114.json" || { printf 'real sing-box 1.14.0 rejected the generated client configuration\n' >&2; exit 1; }
fi
agent_export=$(agent_export_client_json)
jq -e '.warnings[] | select(.code == "hy2_ed25519_chrome_parrot_disabled")' <<< "${agent_export}" >/dev/null || { printf 'agent export must expose the stable Ed25519 warning code\n' >&2; exit 1; }

# SubMan sync is exercised with its network write stubbed; warning semantics remain observable.
list_subman_addresses_for_current_protocol() { printf 'IPv4|203.0.113.10\n'; }
push_subman_protocol_instance() { return 0; }
SB_VERSION=1.14.0
subman_json=$(agent_push_nodes_to_subman_json)
jq -e '.warnings[] | select(.code == "hy2_ed25519_share_link_requires_client_override")' <<< "${subman_json}" >/dev/null || { printf 'agent SubMan sync must expose the stable Ed25519 warning code\n' >&2; exit 1; }
SB_VERSION=1.13.18
export_config=$(build_singbox_client_config)
jq -e '.route.rule_set | all(.[]; (.http_client? == null) and (.download_detour? == null))' <<< "${export_config}" >/dev/null || { printf '1.13 client remote rule-sets must not contain 1.14 fields\n' >&2; exit 1; }
if [[ -n "${SINGBOX_BINARY_113:-}" ]]; then
  printf '%s\n' "${export_config}" > "${TMP_DIR}/client-113.json"
  "${SINGBOX_BINARY_113}" check -c "${TMP_DIR}/client-113.json" || { printf 'real sing-box 1.13.18 rejected the generated client configuration\n' >&2; exit 1; }
fi
warnings=$(build_hy2_compatibility_warnings_json export)
jq -e 'length == 0' <<< "${warnings}" >/dev/null || { printf '1.13 client export must not claim a 1.14-only override\n' >&2; exit 1; }

printf '%s\n' '1.14 client export checks passed'
