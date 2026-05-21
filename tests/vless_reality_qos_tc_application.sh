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
  -e 's|main "\$@"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project/protocols/vless-reality.d" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

TC_LOG="${TMP_DIR}/tc.log"
touch "${TC_LOG}"
cat > "${TMP_DIR}/bin/tc" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TC_LOG}"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/tc"

cat > "${TMP_DIR}/bin/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "route" && "${2:-}" == "show" && "${3:-}" == "default" ]]; then
  printf 'default via 192.0.2.1 dev eth0 proto static\n'
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/bin/ip"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=down-only,up-only,both
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

write_instance() {
  local id=$1 port=$2 up=$3 down=$4
  cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/${id}.env" <<EOF
INSTANCE_ID=${id}
ENABLED=1
NODE_NAME=${id}
PORT=${port}
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=${up}
RATE_LIMIT_DOWN_MBPS=${down}
EOF
}

write_instance down-only 8443 "" 20
write_instance up-only 9443 5 ""
write_instance both 10443 5 20

cat > "${TMP_DIR}/project/reality-qos.filters" <<'EOF'
eth0|down|ip|32001|8443|20
eth0|up|ipv6|32002|9443|5
EOF

refresh_output=$(refresh_vless_reality_qos_rules 2>&1)
tc_log=$(cat "${TC_LOG}")

if [[ "${refresh_output}" == *"仅完成规则规划"* ]]; then
  printf 'expected QoS refresh to apply tc rules instead of plan-only warning, got:\n%s\n' "${refresh_output}" >&2
  exit 1
fi

grep -Fqx 'filter del dev eth0 egress pref 32001 protocol ip' "${TC_LOG}"
grep -Fqx 'filter del dev eth0 ingress pref 32002 protocol ipv6' "${TC_LOG}"
grep -Fqx 'qdisc add dev eth0 clsact' "${TC_LOG}"
grep -Fqx 'filter add dev eth0 egress protocol ip pref 32001 flower ip_proto tcp src_port 8443 action police rate 20mbit burst 512k conform-exceed drop' "${TC_LOG}"
grep -Fqx 'filter add dev eth0 egress protocol ipv6 pref 32002 flower ip_proto tcp src_port 8443 action police rate 20mbit burst 512k conform-exceed drop' "${TC_LOG}"
grep -Fqx 'filter add dev eth0 ingress protocol ip pref 32003 flower ip_proto tcp dst_port 9443 action police rate 5mbit burst 512k conform-exceed drop' "${TC_LOG}"
grep -Fqx 'filter add dev eth0 ingress protocol ipv6 pref 32004 flower ip_proto tcp dst_port 9443 action police rate 5mbit burst 512k conform-exceed drop' "${TC_LOG}"
grep -Fqx 'filter add dev eth0 ingress protocol ip pref 32005 flower ip_proto tcp dst_port 10443 action police rate 5mbit burst 512k conform-exceed drop' "${TC_LOG}"
grep -Fqx 'filter add dev eth0 egress protocol ip pref 32007 flower ip_proto tcp src_port 10443 action police rate 20mbit burst 512k conform-exceed drop' "${TC_LOG}"

if [[ ! -f "${TMP_DIR}/project/reality-qos.filters" ]]; then
  printf 'expected QoS refresh to persist managed filter state\n' >&2
  exit 1
fi

if ! grep -Fqx 'eth0|down|ipv6|32008|10443|20' "${TMP_DIR}/project/reality-qos.filters"; then
  printf 'expected persisted QoS state to include generated filters, got tc log:\n%s\nstate:\n%s\n' \
    "${tc_log}" "$(cat "${TMP_DIR}/project/reality-qos.filters")" >&2
  exit 1
fi

: > "${TC_LOG}"
cat > "${TMP_DIR}/bin/tc" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TC_LOG}"
if [[ "\$*" == filter\ add*pref\ 32001* ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/tc"
rm -f "${TMP_DIR}/project/reality-qos.filters"

retry_output=$(refresh_vless_reality_qos_rules 2>&1)
if [[ "${retry_output}" == *"部分应用失败"* ]]; then
  printf 'expected QoS refresh to retry after a pref collision, got:\n%s\n' "${retry_output}" >&2
  exit 1
fi
if ! grep -Fqx 'eth0|down|ip|32002|8443|20' "${TMP_DIR}/project/reality-qos.filters"; then
  printf 'expected QoS state to skip collided pref 32001 and persist pref 32002, got:\n%s\n' \
    "$(cat "${TMP_DIR}/project/reality-qos.filters")" >&2
  exit 1
fi

cat > "${TMP_DIR}/bin/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "route" && "${2:-}" == "show" && "${3:-}" == "default" ]]; then
  exit 1
fi
if [[ "${1:-}" == "-6" && "${2:-}" == "route" && "${3:-}" == "show" && "${4:-}" == "default" ]]; then
  printf 'default via 2001:db8::1 dev eth1 proto static\n'
  exit 0
fi
exit 1
EOF
chmod +x "${TMP_DIR}/bin/ip"

if [[ "$(detect_default_network_interface)" != "eth1" ]]; then
  printf 'expected IPv6 default route fallback to detect eth1\n' >&2
  exit 1
fi

cat > "${TMP_DIR}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMP_DIR}/bin/systemctl"

cat > "${TMP_DIR}/bin/tc" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${TC_LOG}"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/tc"

cat > "${TMP_DIR}/project/reality-qos.filters" <<'EOF'
eth1|down|ip|32001|8443|20
EOF

perform_singbox_runtime_uninstall >/dev/null 2>&1 || true
if ! grep -Fqx 'filter del dev eth1 egress pref 32001 protocol ip' "${TC_LOG}"; then
  printf 'expected uninstall to clear managed QoS filters before deleting project dir, got:\n%s\n' "$(cat "${TC_LOG}")" >&2
  exit 1
fi
