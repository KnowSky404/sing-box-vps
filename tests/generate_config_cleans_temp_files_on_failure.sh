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

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project" "${TMP_DIR}/mktemp"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"
export TMPDIR="${TMP_DIR}/mktemp"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

list_vless_reality_instance_ids() {
  printf '%s\n' main missing second
}
build_vless_inbound_json_for_instance() {
  case "${1:-}" in
    missing)
      return 1
      ;;
    *)
      printf '{"type":"vless","tag":"%s"}\n' "$1"
      ;;
  esac
}

if build_vless_inbound_json >/dev/null; then
  printf 'expected VLESS Reality inbound builder to fail when any listed instance fails\n' >&2
  exit 1
fi

unset -f list_vless_reality_instance_ids
unset -f build_vless_inbound_json_for_instance

ensure_warp_routing_assets() { :; }
load_warp_route_settings() { :; }
refresh_warp_route_assets() { :; }
ensure_stack_mode_state_loaded() { :; }
list_effective_protocols() { printf 'vless-reality\n'; }
load_protocol_state() { :; }
build_inbound_for_protocol() {
  printf '{"type":"vless"}\n'
  return 1
}

if generate_config >/dev/null 2>&1; then
  printf 'expected generate_config to fail when inbound builder fails\n' >&2
  exit 1
fi

if find "${TMP_DIR}/mktemp" -type f | grep -q .; then
  printf 'expected generate_config to remove mktemp files after failure, found:\n' >&2
  find "${TMP_DIR}/mktemp" -type f >&2
  exit 1
fi

rm -rf "${TMP_DIR}/mktemp" "${TMP_DIR}/project"
mkdir -p "${TMP_DIR}/mktemp" "${TMP_DIR}/project/protocols/vless-reality.d"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=2
DEFAULT_INSTANCE_ID=main
INSTANCE_IDS=main,missing,second
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=public-key
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env" <<'EOF'
INSTANCE_ID=main
ENABLED=1
NODE_NAME=main
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/vless-reality.d/second.env" <<'EOF'
INSTANCE_ID=second
ENABLED=1
NODE_NAME=second
PORT=8443
UUID=22222222-2222-2222-2222-222222222222
SNI=www.cloudflare.com
SHORT_ID_1=cccccccccccccccc
SHORT_ID_2=dddddddddddddddd
RATE_LIMIT_UP_MBPS=
RATE_LIMIT_DOWN_MBPS=
EOF

unset -f build_inbound_for_protocol
unset -f list_effective_protocols
list_effective_protocols() { printf 'vless-reality\n'; }

if generate_config >/dev/null 2>&1; then
  printf 'expected generate_config to fail when a listed VLESS Reality instance state file is missing\n' >&2
  exit 1
fi

if [[ -f "${SINGBOX_CONFIG_FILE}" ]]; then
  printf 'expected no config file to be written after missing VLESS Reality instance failure\n' >&2
  exit 1
fi

if find "${TMP_DIR}/mktemp" -type f | grep -q .; then
  printf 'expected generate_config to remove mktemp files after nested builder failure, found:\n' >&2
  find "${TMP_DIR}/mktemp" -type f >&2
  exit 1
fi
