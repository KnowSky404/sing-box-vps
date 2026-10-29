#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
systemctl() { printf '%s\n' "$*" >> "${TMP_DIR}/service.calls"; }
check_port_conflict() { :; }
load_current_config_state() {
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="all"
}
select_reality_sni_candidate() {
  printf 'speed.example.com'
}
probe_reality_sni_tls() { return 0; }

write_base_state() {
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443,
      "tls": {"enabled": true, "reality": {"enabled": true}}
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

  cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
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
}

assert_state_sni() {
  local expected=$1
  local instance_state="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
  if ! grep -Fqx "SNI=${expected}" "${instance_state}"; then
    printf 'expected SNI=%s, got:\n%s\n' "${expected}" "$(cat "${instance_state}")" >&2
    exit 1
  fi
}

write_base_state
update_config_only <<'EOF'
1
1







EOF
assert_state_sni "apple.com"

write_base_state
update_config_only <<'EOF'
1
1



2
speed.example.com



EOF
assert_state_sni "speed.example.com"

write_base_state
update_config_only <<'EOF'
1
1



3
custom.example.com
1



EOF
assert_state_sni "custom.example.com"

# Interruption after a selected SNI must leave all saved instance fields intact,
# including fields already changed in memory before a later prompt hits EOF.
for interrupted_stage in rates advanced; do
  write_base_state
  migrate_vless_reality_state_to_instances_if_needed
  instance_state="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
  sed -i \
    -e 's/^RATE_LIMIT_UP_MBPS=.*/RATE_LIMIT_UP_MBPS=100/' \
    -e 's/^RATE_LIMIT_DOWN_MBPS=.*/RATE_LIMIT_DOWN_MBPS=50/' \
    -e 's/^TCP_FAST_OPEN=.*/TCP_FAST_OPEN=y/' \
    "${instance_state}"
  grep -Fqx 'RATE_LIMIT_UP_MBPS=100' "${instance_state}"
  grep -Fqx 'RATE_LIMIT_DOWN_MBPS=50' "${instance_state}"
  grep -Fqx 'TCP_FAST_OPEN=y' "${instance_state}"
  cp -- "${instance_state}" "${TMP_DIR}/instance-before"
  cp -- "${SINGBOX_CONFIG_FILE}" "${TMP_DIR}/config-before"
  : > "${TMP_DIR}/service.calls"

  printf '%s\n' 1 1 renamed-node '' '' 2 candidate.example.com > "${TMP_DIR}/truncated-input"
  case "${interrupted_stage}" in
    rates) printf '%s\n' 2 5 >> "${TMP_DIR}/truncated-input" ;;
    advanced) printf '%s\n' 3 2 >> "${TMP_DIR}/truncated-input" ;;
  esac
  status=0
  # The production abort boundary exits; isolate it so the regression can inspect
  # the restored files and service calls after that nonzero exit.
  (update_config_only < "${TMP_DIR}/truncated-input") > "${TMP_DIR}/truncated-output" 2>&1 || status=$?
  if [[ "${status}" -eq 0 ]]; then
    printf 'expected interrupted %s prompts to reject the REALITY update\n' "${interrupted_stage}" >&2
    exit 1
  fi
  grep -Fq '已选择 Reality SNI: speed.example.com' "${TMP_DIR}/truncated-output" || {
    printf 'interruption fixture did not reach SNI selection\n' >&2
    exit 1
  }
  cmp "${TMP_DIR}/instance-before" "${instance_state}" || {
    printf 'interrupted %s prompts changed saved SNI/rates/TFO or other instance fields\n' "${interrupted_stage}" >&2
    exit 1
  }
  cmp "${TMP_DIR}/config-before" "${SINGBOX_CONFIG_FILE}" || exit 1
  if grep -Eq '(^|[[:space:]])restart([[:space:]]|$)' "${TMP_DIR}/service.calls"; then
    printf 'interrupted %s prompts restarted the service\n' "${interrupted_stage}" >&2
    exit 1
  fi
done
printf 'REALITY SNI updates and interrupted-input rollback tests passed.\n'
