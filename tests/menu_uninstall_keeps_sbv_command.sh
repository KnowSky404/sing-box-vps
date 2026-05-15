#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
PROJECT_DIR="${TMP_DIR}/project"
SINGBOX_BIN_PATH="${TMP_DIR}/bin/sing-box"
SBV_BIN_PATH="${TMP_DIR}/bin/sbv"
SINGBOX_SERVICE_FILE="${TMP_DIR}/systemd/sing-box.service"

sed \
  -e '/^main "\$@"$/d' \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${PROJECT_DIR}\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${SINGBOX_BIN_PATH}\"|" \
  -e "s|readonly SBV_BIN_PATH=\"/usr/local/bin/sbv\"|readonly SBV_BIN_PATH=\"${SBV_BIN_PATH}\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${SINGBOX_SERVICE_FILE}\"|" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${PROJECT_DIR}" "$(dirname "${SINGBOX_BIN_PATH}")" "$(dirname "${SINGBOX_SERVICE_FILE}")" "${TMP_DIR}/stub-bin"
touch "${PROJECT_DIR}/config.json" "${SINGBOX_BIN_PATH}" "${SBV_BIN_PATH}" "${SINGBOX_SERVICE_FILE}"

cat > "${TMP_DIR}/stub-bin/systemctl" <<EOF
#!/usr/bin/env bash

printf '%s\n' "\$*" >> "${TMP_DIR}/systemctl.log"
EOF
chmod +x "${TMP_DIR}/stub-bin/systemctl"

export PATH="${TMP_DIR}/stub-bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

perform_singbox_runtime_uninstall

if [[ -e "${PROJECT_DIR}" ]]; then
  printf 'expected project dir to be removed: %s\n' "${PROJECT_DIR}" >&2
  exit 1
fi

if [[ -e "${SINGBOX_BIN_PATH}" ]]; then
  printf 'expected sing-box binary to be removed: %s\n' "${SINGBOX_BIN_PATH}" >&2
  exit 1
fi

if [[ ! -e "${SBV_BIN_PATH}" ]]; then
  printf 'expected menu uninstall to keep sbv command: %s\n' "${SBV_BIN_PATH}" >&2
  exit 1
fi

if [[ -e "${SINGBOX_SERVICE_FILE}" ]]; then
  printf 'expected service file to be removed: %s\n' "${SINGBOX_SERVICE_FILE}" >&2
  exit 1
fi
