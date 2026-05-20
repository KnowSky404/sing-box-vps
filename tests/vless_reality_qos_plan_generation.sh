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
INSTANCE_IDS=main,down-only,up-only,both
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

write_instance main 443 "" ""
write_instance down-only 8443 "" 20
write_instance up-only 9443 5 ""
write_instance both 10443 5 20

SB_PORT="5555"
SB_NODE_NAME="caller-node"
SB_UUID="99999999-9999-9999-9999-999999999999"
SB_SNI="caller.example.com"
SB_SHORT_ID_1="caller-short-1"
SB_SHORT_ID_2="caller-short-2"
SB_VLESS_RATE_LIMIT_UP_MBPS="99"
SB_VLESS_RATE_LIMIT_DOWN_MBPS="199"

build_vless_reality_qos_plan > "${TMP_DIR}/qos.plan"
plan=$(cat "${TMP_DIR}/qos.plan")

grep -Fq '8443|down||20' <<< "${plan}"
grep -Fq '9443|up|5|' <<< "${plan}"
grep -Fq '10443|both|5|20' <<< "${plan}"

if grep -Eq '^443\|' <<< "${plan}"; then
  printf 'expected unlimited main instance to be excluded from QoS plan, got:\n%s\n' "${plan}" >&2
  exit 1
fi

if [[ "${SB_PORT}" != "5555" || "${SB_NODE_NAME}" != "caller-node" ]]; then
  printf 'expected QoS planning to preserve caller state, got SB_PORT=%s SB_NODE_NAME=%s\n' \
    "${SB_PORT}" "${SB_NODE_NAME}" >&2
  exit 1
fi

if [[ "${SB_UUID}" != "99999999-9999-9999-9999-999999999999" ||
      "${SB_SNI}" != "caller.example.com" ||
      "${SB_SHORT_ID_1}" != "caller-short-1" ||
      "${SB_SHORT_ID_2}" != "caller-short-2" ||
      "${SB_VLESS_RATE_LIMIT_UP_MBPS}" != "99" ||
      "${SB_VLESS_RATE_LIMIT_DOWN_MBPS}" != "199" ]]; then
  printf 'expected QoS planning to preserve caller REALITY globals\n' >&2
  exit 1
fi

PATH="${TMP_DIR}/bin:/usr/local/bin:/usr/bin:/bin"
refresh_output=$(refresh_vless_reality_qos_rules 2>&1)
if [[ "${refresh_output}" != *"未检测到 tc，REALITY 限速规则未应用。"* ]]; then
  printf 'expected refresh to warn and return 0 when tc is unavailable, got:\n%s\n' "${refresh_output}" >&2
  exit 1
fi

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

refresh_output=$(refresh_vless_reality_qos_rules 2>&1)
if [[ "${refresh_output}" != *"REALITY 未配置限速，跳过 QoS 规则。"* ]]; then
  printf 'expected refresh to skip empty QoS plans, got:\n%s\n' "${refresh_output}" >&2
  exit 1
fi
