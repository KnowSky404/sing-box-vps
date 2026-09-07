#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120

cat > "${TMP_DIR}/bin/sing-box" <<'EOF_SINGBOX'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  check) exit 0 ;;
esac
EOF_SINGBOX
chmod +x "${TMP_DIR}/bin/sing-box"

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "is-active sing-box" ]]; then
  printf 'active\n'
fi
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

source_testable_install

get_public_ip() { printf '203.0.113.20\n'; }
get_public_ipv4() { printf '203.0.113.20\n'; }
get_public_ipv6() { printf '2001:db8::20\n'; }
detect_host_ip_stack() { printf 'dual\n'; }
sysctl() {
  if [[ "${1:-}" == "-n" && "${2:-}" == "net.ipv4.tcp_congestion_control" ]]; then
    printf 'bbr\n'
    return 0
  fi
  return 1
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}/vless-reality.d" "$(dirname "$(client_export_file_path)")"
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_INDEX'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF_INDEX
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF_PROTOCOL'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,edge
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF_PROTOCOL
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF_MAIN'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=vless-main
PORT=443
UUID=11111111-1111-4111-8111-111111111111
SNI=www.cloudflare.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=80
ALPN_MODE=off
TCP_FAST_OPEN=n
OUTBOUND_POLICY=default
EOF_MAIN
cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/edge.env" <<'EOF_EDGE'
INSTANCE_ID=edge
ENABLED=1
NODE_NAME=vless-edge
PORT=8443
UUID=22222222-2222-4222-8222-222222222222
SNI=www.apple.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=25
RATE_LIMIT_DOWN_MBPS=50
ALPN_MODE=h2
TCP_FAST_OPEN=y
OUTBOUND_POLICY=warp
EOF_EDGE
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF_CONFIG'
{
  "inbounds": [
    {"type": "vless", "listen_port": 443, "tls": {"enabled": true, "reality": {"enabled": true}}},
    {"type": "vless", "listen_port": 8443, "tls": {"enabled": true, "reality": {"enabled": true}}}
  ]
}
EOF_CONFIG
cat > "${SB_STACK_STATE_FILE}" <<'EOF_STACK'
STACK_STATE_VERSION=1
INBOUND_STACK_MODE=dual_stack
OUTBOUND_STACK_MODE=prefer_ipv6
EOF_STACK
printf 'eth0|up|ip|10001|443|25\neth0|down|ip|10002|8443|50\n' > "${SB_REALITY_QOS_FILTER_STATE_FILE}"
printf 'SUBMAN_API_URL=https://subman.example.test\n' > "$(subman_config_file_path)"
printf '{}\n' > "$(client_export_file_path)"

nodes_json=$(agent_cli nodes --json)
jq -e '
  .action == "nodes"
  and .sensitive == false
  and (.nodes | length) == 2
  and any(.nodes[];
    .instance_id == "main"
    and .port == 443
    and .rate_limit.up_mbps == null
    and .rate_limit.down_mbps == 80
    and .outbound_policy == "default")
  and any(.nodes[];
    .instance_id == "edge"
    and .port == 8443
    and .rate_limit.up_mbps == 25
    and .rate_limit.down_mbps == 50
    and .outbound_policy == "warp")
' <<< "${nodes_json}" >/dev/null
if grep -Fq '11111111-1111' <<< "${nodes_json}" || grep -Fq 'private-key' <<< "${nodes_json}"; then
  printf 'node summaries exposed REALITY credentials\n' >&2
  exit 1
fi

links_json=$(agent_cli links --json)
jq -e '
  .action == "links"
  and .sensitive == true
  and (.nodes | length) == 2
  and any(.nodes[]; .instance_id == "main" and (.links.vless | contains(":443?")))
  and any(.nodes[]; .instance_id == "edge" and (.links.vless | contains(":8443?")) and .outbound_policy == "warp")
' <<< "${links_json}" >/dev/null

status_json=$(agent_cli status --json)
jq -e '
  .network_stack.host == "dual"
  and .network_stack.inbound == "dual_stack"
  and .network_stack.outbound == "prefer_ipv6"
  and .system.tcp_congestion_control == "bbr"
  and .system.bbr_enabled == true
  and .reality.instances == 2
  and .reality.qos_filters == 2
  and .integrations.subman_configured == true
  and .integrations.client_export_exists == true
' <<< "${status_json}" >/dev/null

# Read-only Agent commands must report stale indexed state without reconciling
# or rewriting it. Doctor is responsible for flagging the inconsistency.
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF_STALE_INDEX'
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
EOF_STALE_INDEX
stale_index_hash=$(sha256sum "${SB_PROTOCOL_INDEX_FILE}" | awk '{print $1}')

status_json=$(agent_cli status --json)
jq -e '.protocols == ["vless-reality", "hysteria2"]' <<< "${status_json}" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_INDEX_FILE}" | awk '{print $1}')" == "${stale_index_hash}" ]]

doctor_json=$(agent_cli doctor --json)
jq -e '.diagnostics.managed_instance_state == "incomplete"' <<< "${doctor_json}" >/dev/null
[[ "$(sha256sum "${SB_PROTOCOL_INDEX_FILE}" | awk '{print $1}')" == "${stale_index_hash}" ]]

if (agent_cli nodes --json >/dev/null 2>&1); then
  printf 'expected nodes to reject an indexed protocol with missing state\n' >&2
  exit 1
fi
[[ "$(sha256sum "${SB_PROTOCOL_INDEX_FILE}" | awk '{print $1}')" == "${stale_index_hash}" ]]

printf '%s\n' 'agent multi-instance and status checks passed'
