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

list_installed_protocols() { :; }

OUTPUT_FILE="${TMP_DIR}/selection.output"
prompt_protocol_install_selection "additional" >"${OUTPUT_FILE}" 2>&1 <<'EOF'

EOF

output=$(cat "${OUTPUT_FILE}")

if [[ "${SELECTED_PROTOCOLS_CSV}" != "vless-reality,vless-plain,mixed,hy2,anytls,socks,http,shadowsocks,trojan,vmess,snell,tuic,hysteria,naive,shadowtls" ]]; then
  printf 'expected blank selection to install all available protocols, got %s\n' "${SELECTED_PROTOCOLS_CSV}" >&2
  exit 1
fi

if [[ "${output}" != *"留空则安装全部可用协议"* ]]; then
  printf 'expected prompt to mention blank selection installs all, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"10. VLESS"* || "${output}" == *"10. VLESS + REALITY"* ]]; then
  printf 'expected menu item 10 to identify ordinary VLESS separately, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"13. Hysteria"* ]]; then
  printf 'expected menu item 13 to identify Hysteria, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"14. NaiveProxy"* ]]; then
  printf 'expected menu item 14 to identify NaiveProxy, got:\n%s\n' "${output}" >&2
  exit 1
fi

if [[ "${output}" != *"15. ShadowTLS"* ]]; then
  printf 'expected menu item 15 to identify ShadowTLS, got:\n%s\n' "${output}" >&2
  exit 1
fi
