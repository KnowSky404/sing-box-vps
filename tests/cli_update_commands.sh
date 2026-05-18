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

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.5\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

output=$(timeout 5 bash -c "
  source '${TESTABLE_INSTALL}'
  check_root() { :; }
  MANUAL_UPDATE_COUNT=0
  manual_update_script() {
    MANUAL_UPDATE_COUNT=\$((MANUAL_UPDATE_COUNT + 1))
    printf '%s\n' \"manual_update_count=\${MANUAL_UPDATE_COUNT}\"
  }
  main update sbv
" 2>&1)
if [[ "${output}" != *"manual_update_count=1"* ]]; then
  printf 'expected "update sbv" to call manual_update_script once, got output:\n%s\n' "${output}" >&2
  exit 1
fi

output=$(timeout 5 bash -c "
  source '${TESTABLE_INSTALL}'
  check_root() { :; }
  detect_existing_instance_state() { printf '%s\n' healthy; }
  update_singbox_binary_preserving_config() {
    printf '%s\n' \"update_singbox_version=\${SB_VERSION}\"
  }
  main update-sing-box 1.13.12
" 2>&1)
if [[ "${output}" != *"update_singbox_version=1.13.12"* ]]; then
  printf 'expected "update-sing-box" to pass SB_VERSION=1.13.12, got:\n%s\n' "${output}" >&2
  exit 1
fi

output=$(timeout 5 bash -c "
  source '${TESTABLE_INSTALL}'
  check_root() { :; }
  detect_existing_instance_state() { printf '%s\n' healthy; }
  update_singbox_binary_preserving_config() {
    printf '%s\n' \"update_singbox_version=\${SB_VERSION}\"
  }
  main update sing-box latest
" 2>&1)
if [[ "${output}" != *"update_singbox_version=latest"* ]]; then
  printf 'expected "update sing-box latest" to pass SB_VERSION=latest, got:\n%s\n' "${output}" >&2
  exit 1
fi

if timeout 5 bash -c "source '${TESTABLE_INSTALL}'; check_root() { :; }; detect_existing_instance_state() { printf '%s\n' healthy; }; main update sing-box 1" >/tmp/sbv-cli-update-invalid.out 2>&1; then
  printf 'expected invalid sing-box version argument to fail\n' >&2
  exit 1
fi

if ! grep -Fq '无效版本号' /tmp/sbv-cli-update-invalid.out; then
  printf 'expected invalid version output to mention 无效版本号, got:\n%s\n' "$(cat /tmp/sbv-cli-update-invalid.out)" >&2
  exit 1
fi

if timeout 5 bash -c "source '${TESTABLE_INSTALL}'; check_root() { :; }; detect_existing_instance_state() { printf '%s\n' incomplete; }; main update sing-box 1.13.12" >/tmp/sbv-cli-update-incomplete.out 2>&1; then
  printf 'expected incomplete sing-box instance update to fail\n' >&2
  exit 1
fi

if ! grep -Fq '残缺的 sing-box 实例' /tmp/sbv-cli-update-incomplete.out; then
  printf 'expected incomplete instance output to mention 残缺的 sing-box 实例, got:\n%s\n' "$(cat /tmp/sbv-cli-update-incomplete.out)" >&2
  exit 1
fi

help_output=$(timeout 5 bash -c "source '${TESTABLE_INSTALL}'; main --help" 2>&1)
for expected in \
  'sbv update sbv' \
  'sbv update sing-box [latest|x.y.z]' \
  'sbv update-sbv' \
  'sbv update-sing-box [latest|x.y.z]'; do
  if [[ "${help_output}" != *"${expected}"* ]]; then
    printf 'expected help output to contain %s, got:\n%s\n' "${expected}" "${help_output}" >&2
    exit 1
  fi
done
