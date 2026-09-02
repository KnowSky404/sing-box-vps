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

PORT_PROMPTS_FILE="${TMP_DIR}/port-prompts.log"
: > "${PORT_PROMPTS_FILE}"

prompt_port() {
  printf '%s\n' "$1" >> "${PORT_PROMPTS_FILE}"
  printf '%s' "${2:-443}"
}
check_port_conflict() { :; }
ensure_mixed_auth_credentials() { :; }
ensure_hy2_materials() { :; }
validate_tls_domain_points_to_server() { return 0; }
prompt_reality_sni_install() { SB_SNI="www.example.com"; }
prompt_vless_reality_rate_limit_fields() {
  SB_VLESS_RATE_LIMIT_UP_MBPS=""
  SB_VLESS_RATE_LIMIT_DOWN_MBPS=""
}
prompt_vless_reality_advanced_update_fields() {
  SB_VLESS_ALPN_MODE="off"
  SB_VLESS_TCP_FAST_OPEN="n"
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

if ! grep -Fq '[VLESS + REALITY] 端口' "${PORT_PROMPTS_FILE}"; then
  printf 'expected VLESS install prompt to include protocol name, got:\n%s\n' "${vless_output}" >&2
  exit 1
fi

if ! grep -Fq '[Mixed] 端口' "${PORT_PROMPTS_FILE}"; then
  printf 'expected Mixed install prompt to include protocol name, got:\n%s\n' "${mixed_output}" >&2
  exit 1
fi

if ! grep -Fq '[Hysteria2] 端口' "${PORT_PROMPTS_FILE}"; then
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
