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
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash

printf 'upstream temporarily unavailable\n'
EOF
chmod +x "${TMP_DIR}/bin/curl"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sysctl" <<'EOF'
#!/usr/bin/env bash

printf 'net.ipv4.tcp_congestion_control = cubic\n'
EOF
chmod +x "${TMP_DIR}/bin/sysctl"

export PATH="${TMP_DIR}/bin:${PATH}"

set +e
output=$(printf '0\n' | bash "${TESTABLE_INSTALL}" 2>&1)
status=$?
set -e

if (( status != 0 )); then
  printf 'expected script to keep running when update check returns unexpected content, got exit code %s and output:\n%s\n' "${status}" "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"1. 安装协议 / 更新 sing-box"* ]]; then
  printf 'expected main menu to render when update check returns unexpected content, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"8. 查看状态"* ]]; then
  printf 'expected status menu entry to render, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"9. 查看节点信息"* ]]; then
  printf 'expected node info menu entry to render, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"14. 流媒体验证检测"* ]]; then
  printf 'expected media check menu entry to shift to 14, got:\n%s\n' "${output}" >&2
  exit 1
fi
