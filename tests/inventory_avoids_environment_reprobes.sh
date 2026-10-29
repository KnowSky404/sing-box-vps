#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
# Listener and ownership projection need stable adapter metadata only. They
# must not repeatedly probe core/build tags and unrelated host dependencies.
protocol_registry_json() { printf 'unexpected environment reprobe\n' >&2; return 97; }
printf '%s\n' '{"inbounds":[{"type":"mixed","tag":"mixed-in","listen":"127.0.0.1","listen_port":18080}],"outbounds":[{"type":"direct","tag":"direct"}]}' > "${SINGBOX_CONFIG_FILE}"
validate_live_inbound_inventory "${SINGBOX_CONFIG_FILE}"
plan=$(managed_listener_plan_json < "${SINGBOX_CONFIG_FILE}")
jq -e 'length > 0 and any(.[]; .port==18080)' <<< "${plan}" >/dev/null
printf 'inventory and listener hot paths use static metadata without environment reprobes\n'
