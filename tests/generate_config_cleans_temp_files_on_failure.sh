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
