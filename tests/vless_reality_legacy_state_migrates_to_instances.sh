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

mkdir -p "${TMP_DIR}/project/protocols" "${TMP_DIR}/bin"

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
INSTALLED_SINGBOX_VERSION=1.13.9
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=gl-gb-lon+vless
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

migrate_vless_reality_state_to_instances_if_needed

main_state="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"

if [[ ! -f "${main_state}" ]]; then
  printf 'expected migrated main instance state at %s\n' "${main_state}" >&2
  exit 1
fi

grep -Fq 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'DEFAULT_INSTANCE_ID=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PRIVATE_KEY=private-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PUBLIC_KEY=public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

grep -Fq 'INSTANCE_ID=main' "${main_state}"
grep -Fq 'NODE_NAME=gl-gb-lon-vless' "${main_state}"
grep -Fq 'PORT=443' "${main_state}"
grep -Fq 'UUID=11111111-1111-1111-1111-111111111111' "${main_state}"
grep -Fq 'SNI=apple.com' "${main_state}"
grep -Fq 'SHORT_ID_1=aaaaaaaaaaaaaaaa' "${main_state}"
grep -Fq 'SHORT_ID_2=bbbbbbbbbbbbbbbb' "${main_state}"
grep -Eq '^RATE_LIMIT_UP_MBPS=$' "${main_state}"
grep -Eq '^RATE_LIMIT_DOWN_MBPS=$' "${main_state}"

if ! compgen -G "${SB_PROTOCOL_STATE_DIR}/vless-reality.env.bak.*" >/dev/null; then
  printf 'expected legacy vless-reality.env backup to be created\n' >&2
  exit 1
fi

load_protocol_state "vless-reality"
save_protocol_state "vless-reality"

grep -Fq 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'DEFAULT_INSTANCE_ID=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PRIVATE_KEY=private-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PUBLIC_KEY=public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"

if grep -Fq 'CONFIG_SCHEMA_VERSION=1' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
  printf 'expected save_protocol_state to preserve vless-reality schema v2, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
  exit 1
fi

grep -Fq 'INSTANCE_ID=main' "${main_state}"
grep -Fq 'PORT=443' "${main_state}"
grep -Fq 'UUID=11111111-1111-1111-1111-111111111111' "${main_state}"
grep -Eq '^RATE_LIMIT_UP_MBPS=$' "${main_state}"
grep -Eq '^RATE_LIMIT_DOWN_MBPS=$' "${main_state}"

SB_PUBLIC_KEY=""
SB_PRIVATE_KEY=""

cat > "${SB_KEY_FILE}" <<'EOF'
PRIVATE_KEY=regenerated-private-key
PUBLIC_KEY=regenerated-public-key
EOF

ensure_vless_reality_materials

grep -Fq 'CONFIG_SCHEMA_VERSION=2' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'INSTANCE_IDS=main' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PRIVATE_KEY=regenerated-private-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'REALITY_PUBLIC_KEY=regenerated-public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"
grep -Fq 'PORT=443' "${main_state}"
grep -Fq 'UUID=11111111-1111-1111-1111-111111111111' "${main_state}"
grep -Eq '^RATE_LIMIT_UP_MBPS=$' "${main_state}"
grep -Eq '^RATE_LIMIT_DOWN_MBPS=$' "${main_state}"
