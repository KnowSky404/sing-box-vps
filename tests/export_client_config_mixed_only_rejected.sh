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
  s|readonly SBV_BIN_PATH="/usr/local/bin/sbv"|readonly SBV_BIN_PATH="'"${TMP_DIR}"'/bin/sbv"|;
  s|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|readonly SINGBOX_SERVICE_FILE="'"${TMP_DIR}"'/sing-box.service"|;
' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

mkdir -p "${SB_PROTOCOL_STATE_DIR}"

cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=mixed
PROTOCOL_STATE_VERSION=1
EOF

cat > "${SB_PROTOCOL_STATE_DIR}/mixed.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=mixed_test-host
PORT=2080
MIXED_AUTH_ENABLED=n
MIXED_USERNAME=
MIXED_PASSWORD=
EOF

load_protocol_state "mixed"

EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"
STDOUT_FILE="${TMP_DIR}/stdout.txt"
STDERR_FILE="${TMP_DIR}/stderr.txt"

if export_singbox_client_config >"${STDOUT_FILE}" 2>"${STDERR_FILE}"; then
  printf 'expected export_singbox_client_config to fail when only mixed is installed\n' >&2
  exit 1
fi

if [[ -f "${EXPORT_PATH}" ]]; then
  printf 'did not expect exported config at %s\n' "${EXPORT_PATH}" >&2
  exit 1
fi

if ! grep -Eq '当前无可导出的 sing-box 裸核客户端节点|未检测到可导出的远程协议' "${STDERR_FILE}"; then
  printf 'expected clear rejection message, stderr was:\n%s\n' "$(cat "${STDERR_FILE}")" >&2
  exit 1
fi
