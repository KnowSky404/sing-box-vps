#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120

# Run outside a conditional so errexit remains active inside the real display
# functions. An outage must warn and return to the menu, never emit a bad URI.
for protocol in hy2 anytls vless+reality; do
  output=$(bash -s -- "${TESTABLE_INSTALL}" "${protocol}" <<'BASH'
set -euo pipefail
source "$1"
SB_PROTOCOL=$2
get_public_ipv4() { return 1; }
get_public_ipv6() { return 1; }
plain_proxy_structured_state_active() { return 1; }
list_public_addresses_for_current_stack() { return 1; }
show_link_info() { printf 'invalid link rendered\n'; return 99; }
show_connection_details_for_detected_addresses link
printf 'display returned\n'
BASH
  )
  [[ "${output}" == *'未获取到公网 IP'* && "${output}" == *'display returned'* ]]
  [[ "${output}" != *'invalid link rendered'* ]]
done
printf 'Public IP display outage checks passed (3 protocols, errexit active)\n'
