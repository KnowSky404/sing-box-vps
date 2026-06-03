#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

perl -0pe '
  s/^\s*main "\$@"\s*$//m;
  s|readonly SB_PROJECT_DIR="/root/sing-box-vps"|readonly SB_PROJECT_DIR="'"${TMP_DIR}"'/project"|;
  s|readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"|readonly SINGBOX_BIN_PATH="'"${TMP_DIR}"'/bin/sing-box"|;
  s|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|readonly SINGBOX_SERVICE_FILE="'"${TMP_DIR}"'/sing-box.service"|;
' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

SB_VLESS_ALPN_MODE="h2_http1"
SB_VLESS_TCP_FAST_OPEN="y"

prompt_vless_reality_advanced_update_fields <<'EOF' >/dev/null
1
y
EOF

if [[ "${SB_VLESS_ALPN_MODE}" != "h2_http1" ]]; then
  printf 'expected default advanced prompt choice to preserve ALPN mode, got %s\n' "${SB_VLESS_ALPN_MODE}" >&2
  exit 1
fi

if [[ "${SB_VLESS_TCP_FAST_OPEN}" != "y" ]]; then
  printf 'expected TCP Fast Open to stay enabled, got %s\n' "${SB_VLESS_TCP_FAST_OPEN}" >&2
  exit 1
fi
