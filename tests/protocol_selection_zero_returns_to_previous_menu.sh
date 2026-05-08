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

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

OUTPUT_FILE="${TMP_DIR}/selection.output"
if prompt_protocol_install_selection "additional" >"${OUTPUT_FILE}" 2>&1 <<'EOF'
0
EOF
then
  printf 'expected selecting 0 to return non-zero from prompt_protocol_install_selection\n' >&2
  exit 1
fi

if [[ -n "${SELECTED_PROTOCOLS_CSV:-}" ]]; then
  printf 'expected selecting 0 to leave SELECTED_PROTOCOLS_CSV empty, got %s\n' "${SELECTED_PROTOCOLS_CSV}" >&2
  exit 1
fi

output=$(cat "${OUTPUT_FILE}")

if [[ "${output}" != *"0. 返回上一级"* ]]; then
  printf 'expected prompt to show return option, got:\n%s\n' "${output}" >&2
  exit 1
fi
