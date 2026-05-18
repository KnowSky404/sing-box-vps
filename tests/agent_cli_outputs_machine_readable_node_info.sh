#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.12\n'
    ;;
  check)
    exit 0
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "is-active" && "${2:-}" == "sing-box" ]]; then
  printf 'active\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/systemctl"

source_testable_install
export SINGBOX_CONFIG_FILE SB_PROJECT_DIR

get_public_ip() {
  printf '203.0.113.10\n'
}

get_public_ipv4() {
  printf '203.0.113.10\n'
}

get_public_ipv6() {
  return 1
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
touch "${SINGBOX_CONFIG_FILE}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,mixed,hy2,anytls
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=www.cloudflare.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_test-host
PORT=2080
AUTH_ENABLED=y
USERNAME=mixed-user
PASSWORD=mixed-pass
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=hy2-password
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=y
OBFS_TYPE=salamander
OBFS_PASSWORD=obfs-pass
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=https://example.com
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/anytls.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=anytls_test-host
PORT=9443
DOMAIN=anytls.example.com
PASSWORD=anytls-password
USER_NAME=anytls-user
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/anytls.pem
KEY_PATH=/etc/ssl/private/anytls.key
EOF

status_json=$(agent_cli status --json)
jq -e '
  .script_version == "2026051802"
  and .supported_sing_box_version == "1.13.12"
  and .service.active_state == "active"
  and .sing_box.version == "1.13.12"
  and .paths.config == env.SINGBOX_CONFIG_FILE
  and .protocols == ["vless-reality", "mixed", "hy2", "anytls"]
' <<< "${status_json}" >/dev/null

nodes_json=$(agent_cli nodes --json)
jq -e '
  .public_address == "203.0.113.10"
  and (.nodes | length) == 4
  and any(.nodes[]; .protocol == "vless-reality" and .shareable == true and .client_exportable == true and .port == 443)
  and any(.nodes[]; .protocol == "mixed" and .shareable == true and .client_exportable == false and .auth_enabled == true)
  and any(.nodes[]; .protocol == "anytls" and .shareable == true and .client_exportable == true and .server_name == "anytls.example.com")
' <<< "${nodes_json}" >/dev/null

if grep -Fq 'vless://' <<< "${nodes_json}" || grep -Fq 'hy2://' <<< "${nodes_json}" || grep -Fq 'mixed-pass' <<< "${nodes_json}"; then
  printf 'agent nodes should not include full share links or passwords:\n%s\n' "${nodes_json}" >&2
  exit 1
fi

links_json=$(agent_cli links --json)
jq -e '
  .public_address == "203.0.113.10"
  and any(.nodes[]; .protocol == "vless-reality" and .links.vless == "vless://11111111-1111-1111-1111-111111111111@203.0.113.10:443?security=reality&sni=www.cloudflare.com&fp=chrome&pbk=public-key&sid=aaaaaaaaaaaaaaaa&flow=xtls-rprx-vision#vless_test-host")
  and any(.nodes[]; .protocol == "mixed" and .links.http == "http://mixed-user:mixed-pass@203.0.113.10:2080" and .links.socks5 == "socks5://mixed-user:mixed-pass@203.0.113.10:2080")
  and any(.nodes[]; .protocol == "hy2" and (.links.hy2 | startswith("hy2://hy2-password@hy2.example.com:8443?")))
  and any(.nodes[]; .protocol == "anytls" and .outbound.type == "anytls" and .outbound.server == "anytls.example.com")
' <<< "${links_json}" >/dev/null

export_json=$(agent_cli export-client --json)
jq -e '
  .path == (env.SB_PROJECT_DIR + "/client/sing-box-client.json")
  and .config.inbounds[0].type == "mixed"
  and any(.config.outbounds[]; .type == "vless")
  and any(.config.outbounds[]; .type == "hysteria2")
  and any(.config.outbounds[]; .type == "anytls")
' <<< "${export_json}" >/dev/null

if [[ ! -f "${SB_PROJECT_DIR}/client/sing-box-client.json" ]]; then
  printf 'agent export-client should write client config file\n' >&2
  exit 1
fi
