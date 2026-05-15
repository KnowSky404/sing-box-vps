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

check_port_conflict() { :; }
ensure_mixed_auth_credentials() { :; }
ensure_hy2_materials() { :; }
validate_tls_domain_points_to_server() { return 0; }
select_reality_sni_candidate() {
  printf 'www.example.com'
}

vless_output=$(prompt_vless_reality_install 2>&1 <<'EOF'


EOF
)

mixed_output=$(prompt_mixed_install 2>&1 <<'EOF'

n
EOF
)

hy2_output=$(prompt_hy2_install 2>&1 <<'EOF'
hy2.example.com




n
1



EOF
)

if [[ "${vless_output}" != *"[VLESS + REALITY] 端口"* ]]; then
  printf 'expected VLESS install prompt to include protocol name, got:\n%s\n' "${vless_output}" >&2
  exit 1
fi

if [[ "${mixed_output}" != *"[Mixed] 端口"* ]]; then
  printf 'expected Mixed install prompt to include protocol name, got:\n%s\n' "${mixed_output}" >&2
  exit 1
fi

if [[ "${hy2_output}" != *"[Hysteria2] 端口"* ]]; then
  printf 'expected Hysteria2 install prompt to include protocol name, got:\n%s\n' "${hy2_output}" >&2
  exit 1
fi

if ! grep -Fq '[Hysteria2] 是否启用 obfs / Salamander 混淆' "${REPO_ROOT}/install.sh"; then
  printf 'expected Hysteria2 install prompt to mention obfs / Salamander\n' >&2
  exit 1
fi

if ! grep -Fq 'obfs / Salamander 混淆密码' "${REPO_ROOT}/install.sh"; then
  printf 'expected Hysteria2 obfs password prompt to mention obfs / Salamander\n' >&2
  exit 1
fi
