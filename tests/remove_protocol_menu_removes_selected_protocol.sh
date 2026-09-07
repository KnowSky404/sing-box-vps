#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

GENERATE_CONFIG_COUNT_FILE="${TMP_DIR}/generate_config.count"
printf '0\n' > "${GENERATE_CONFIG_COUNT_FILE}"

generate_config() {
  local current_count
  current_count=$(cat "${GENERATE_CONFIG_COUNT_FILE}")
  printf '%s\n' "$((current_count + 1))" > "${GENERATE_CONFIG_COUNT_FILE}"
}

check_config_valid() { :; }
validate_config_file() { :; }
setup_service() { :; }
open_all_protocol_ports() { :; }
display_status_summary() {
  printf 'unexpected status summary after protocol removal\n'
}
SYSTEMCTL_MODE='inactive'
SYSTEMCTL_LOG="${TMP_DIR}/systemctl.log"
CLOSE_FIREWALL_LOG="${TMP_DIR}/close-firewall.log"
close_firewall_port() {
  printf '%s\n' "$*" >> "${CLOSE_FIREWALL_LOG}"
}
systemctl() {
  local action=${1:-}
  printf '%s\n' "$*" >> "${SYSTEMCTL_LOG}"
  case "${action}" in
    stop)
      if [[ "${SYSTEMCTL_MODE}" == stop-fail ]]; then return 47; fi
      ;;
    show)
      if [[ "${SYSTEMCTL_MODE}" == active ]]; then
        printf 'active\n'
      else
        printf 'inactive\n'
      fi
      ;;
    *)
      return 0
      ;;
  esac
}
load_current_config_state() {
  SB_PROTOCOL="vless+reality"
  SB_PORT="443"
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="selective"
}

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    { "type": "vless", "tag": "vless-in", "listen_port": 443, "tls": {"enabled": true, "reality": {"enabled": true}} },
    { "type": "hysteria2", "tag": "hy2-in", "listen_port": 8443 }
  ],
  "route": { "rules": [] }
}
EOF

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality,hy2
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=old-pass
USER_NAME=hy2-user
UP_MBPS=100
DOWN_MBPS=50
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=
EOF

if ! REMOVE_OUTPUT=$(printf '2\ny\n' | remove_protocol_menu 2>&1); then
  printf 'expected remove_protocol_menu to succeed, got:\n%s\n' "${REMOVE_OUTPUT}" >&2
  exit 1
fi

if [[ -f "$(protocol_state_file hy2)" ]]; then
  printf 'expected selected hy2 state file to be removed, got:\n%s\n' "$(cat "$(protocol_state_file hy2)")" >&2
  exit 1
fi

if [[ ! -f "$(protocol_state_file vless-reality)" ]]; then
  printf 'expected unselected vless state file to remain\n' >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=vless-reality' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to keep only vless-reality, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi

if ! compgen -G "$(protocol_state_file hy2).bak.*" >/dev/null; then
  printf 'expected removed protocol state backup next to original state file\n' >&2
  exit 1
fi

if [[ "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" != "1" ]]; then
  printf 'expected remove flow to regenerate config exactly once, got %s\n' "$(cat "${GENERATE_CONFIG_COUNT_FILE}")" >&2
  exit 1
fi

REMOVE_PLAIN_OUTPUT=$(strip_ansi "${REMOVE_OUTPUT}")
if [[ "${REMOVE_PLAIN_OUTPUT}" == *"unexpected status summary after protocol removal"* ]]; then
  printf 'expected remove flow not to display service summary, got:\n%s\n' "${REMOVE_OUTPUT}" >&2
  exit 1
fi

if [[ "${REMOVE_PLAIN_OUTPUT}" == *"连接信息未自动展示"* ]]; then
  printf 'expected remove flow not to display connection info hint, got:\n%s\n' "${REMOVE_OUTPUT}" >&2
  exit 1
fi

LAST_CONFIG_BEFORE=$(mktemp)
LAST_INDEX_BEFORE=$(mktemp)
cp "${SINGBOX_CONFIG_FILE}" "${LAST_CONFIG_BEFORE}"
cp "${SB_PROTOCOL_INDEX_FILE}" "${LAST_INDEX_BEFORE}"

if ! REMOVE_LAST_OUTPUT=$(printf '1\ny\n' | remove_protocol_menu 2>&1); then
  printf 'expected last-protocol remove attempt to return without shell failure, got:\n%s\n' "${REMOVE_LAST_OUTPUT}" >&2
  exit 1
fi

REMOVE_LAST_PLAIN_OUTPUT=$(strip_ansi "${REMOVE_LAST_OUTPUT}")
if [[ "${REMOVE_LAST_PLAIN_OUTPUT}" != *"所有协议已移除"* ]]; then
  printf 'expected last-protocol removal to stop the service and clear the install, got:\n%s\n' "${REMOVE_LAST_OUTPUT}" >&2
  exit 1
fi

if [[ -f "${SB_PROTOCOL_INDEX_FILE}" || -f "${SINGBOX_CONFIG_FILE}" ]]; then
  printf 'expected last-protocol removal to clear the protocol index and runtime config\n' >&2
  exit 1
fi

if ! cmp -s "${LAST_CONFIG_BEFORE}" "${SINGBOX_CONFIG_FILE}.bak"; then
  printf 'expected last-protocol removal to preserve the live config in config.json.bak\n' >&2
  exit 1
fi

if ! cmp -s "${LAST_INDEX_BEFORE}" "${SB_PROTOCOL_INDEX_FILE}.bak"; then
  printf 'expected last-protocol removal to preserve the protocol index in index.env.bak\n' >&2
  exit 1
fi

if [[ "$(stat -c '%a' "${SINGBOX_CONFIG_FILE}.bak")" != "600" || "$(stat -c '%a' "${SB_PROTOCOL_INDEX_FILE}.bak")" != "600" ]]; then
  printf 'expected persistent removal backups to use mode 600\n' >&2
  exit 1
fi

if [[ -f "$(protocol_state_file vless-reality)" ]]; then
  printf 'expected last-protocol removal to clear the active VLESS protocol state\n' >&2
  exit 1
fi

restore_single_protocol_fixture() {
  rm -rf -- "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/vless-reality.d"
  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    { "type": "vless", "tag": "vless-in", "listen": "127.0.0.1", "listen_port": 443,
      "tls": { "enabled": true, "reality": { "enabled": true } } }
  ],
  "route": { "rules": [] }
}
EOF
  cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
INBOUND_TAG=vless-in
ENABLED=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
ALPN_MODE=off
TCP_FAST_OPEN=n
OUTBOUND_POLICY=default
EOF
  printf 'previous config backup\n' > "${SINGBOX_CONFIG_FILE}.bak"
  printf 'previous index backup\n' > "${SB_PROTOCOL_INDEX_FILE}.bak"
  chmod 600 "${SINGBOX_CONFIG_FILE}.bak" "${SB_PROTOCOL_INDEX_FILE}.bak"
}

capture_fixture_hashes() {
  local destination=$1
  sha256sum \
    "${SINGBOX_CONFIG_FILE}" \
    "${SB_PROTOCOL_INDEX_FILE}" \
    "${SINGBOX_CONFIG_FILE}.bak" \
    "${SB_PROTOCOL_INDEX_FILE}.bak" \
    "$(protocol_state_file vless-reality)" \
    "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" > "${destination}"
}

assert_fixture_hashes_unchanged() {
  local expected=$1
  local actual="${TMP_DIR}/fixture-after.sha256"
  capture_fixture_hashes "${actual}"
  cmp -s "${expected}" "${actual}" || {
    printf 'stop safety rollback changed managed state/config/index or persistent .bak\n' >&2
    return 1
  }
}

# A failed stop must restore every managed file and must not attempt firewall
# cleanup while the service may still own its listeners.
restore_single_protocol_fixture
STOP_FAILURE_BEFORE="${TMP_DIR}/stop-failure-before.sha256"
capture_fixture_hashes "${STOP_FAILURE_BEFORE}"
: > "${CLOSE_FIREWALL_LOG}"
SYSTEMCTL_MODE=stop-fail
stop_failure_status=0
STOP_FAILURE_OUTPUT=$(printf '\ny\n' | remove_protocol_menu 2>&1) || stop_failure_status=$?
[[ "${stop_failure_status}" == 47 ]] || {
  printf 'expected all-protocol removal to fail when systemctl stop fails\n' >&2
  exit 1
}
grep -Fq 'stop_failed' <<< "${STOP_FAILURE_OUTPUT}"
[[ ! -s "${CLOSE_FIREWALL_LOG}" ]] || {
  printf 'expected stop failure not to invoke firewall cleanup\n' >&2
  exit 1
}
assert_fixture_hashes_unchanged "${STOP_FAILURE_BEFORE}"

# A successful stop call is still insufficient if systemd reports the unit as
# active. The same rollback and firewall invariant must hold.
restore_single_protocol_fixture
ACTIVE_FAILURE_BEFORE="${TMP_DIR}/active-failure-before.sha256"
capture_fixture_hashes "${ACTIVE_FAILURE_BEFORE}"
: > "${CLOSE_FIREWALL_LOG}"
SYSTEMCTL_MODE=active
active_failure_status=0
ACTIVE_FAILURE_OUTPUT=$(printf '\ny\n' | remove_protocol_menu 2>&1) || active_failure_status=$?
[[ "${active_failure_status}" != 0 ]] || {
  printf 'expected all-protocol removal to fail while systemctl reports active\n' >&2
  exit 1
}
grep -Fq 'service_state_unconfirmed' <<< "${ACTIVE_FAILURE_OUTPUT}"
[[ ! -s "${CLOSE_FIREWALL_LOG}" ]] || {
  printf 'expected active-service protection not to invoke firewall cleanup\n' >&2
  exit 1
}
assert_fixture_hashes_unchanged "${ACTIVE_FAILURE_BEFORE}"

printf '%s\n' 'protocol removal safety checks passed'
