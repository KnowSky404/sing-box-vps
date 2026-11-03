#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

routing_nodes_json() { printf '[]\n'; }
register_warp() { printf 'read-only status registered Warp\n' >&2; return 98; }
systemctl() { printf 'read-only status controlled a service\n' >&2; return 98; }
ensure_warp_routing_assets() { printf 'read-only status created routing assets\n' >&2; return 98; }
routing_policy_apply() { printf 'read-only status applied settings\n' >&2; return 98; }

# The compatibility entry renders the unified overview from the live config,
# even when a stale shell variable says the opposite.
printf '%s\n' '{"inbounds":[],"endpoints":[{"type":"wireguard","tag":"warp-ep"}],"route":{"rules":[],"final":"warp-ep"}}' > "${SINGBOX_CONFIG_FILE}"
SB_ENABLE_WARP=n
output=$(warp_management <<'EOF'
0
EOF
)
plain_output=$(strip_ansi "${output}")
[[ "${plain_output}" == *'网络与分流'* ]]
[[ "${plain_output}" == *'WARP 开关与节点出口设置 开启（全量出口）'* ]]
[[ "${output}" == *$'\033[0;32m开启（全量出口）'* ]]
[[ "${output}" != *'\033[0;32m开启（全量出口）'* ]]

printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"rules":[],"final":"direct"}}' > "${SINGBOX_CONFIG_FILE}"
SB_ENABLE_WARP=y
output=$(warp_management <<'EOF'
0
EOF
)
plain_output=$(strip_ansi "${output}")
[[ "${plain_output}" == *'WARP 开关与节点出口设置 关闭（原生默认）'* ]]
[[ "${output}" == *$'\033[0;32m关闭（原生默认）'* ]]
[[ ! -e "${SB_ROUTING_POLICY_FILE}" && ! -e "${SB_WARP_KEY_FILE}" ]]
printf 'Unified WARP overview uses live state and rendered ANSI status colors\n'
