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

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

RESOLVE_LOG="${TMP_DIR}/resolve.log"

get_os_info() { :; }
get_arch() { ARCH="amd64"; }
install_dependencies() { :; }
get_latest_version() { :; }
install_binary() { :; }
generate_config() { :; }
check_config_valid() { :; }
setup_service() { :; }
open_firewall_port() { :; }
display_status_summary() { :; }
show_post_config_connection_info() { :; }
systemctl() { :; }
check_port_conflict() { :; }
save_warp_route_settings() { :; }

get_public_ip_candidates() {
  printf '203.0.113.10\n'
}

resolve_domain_ip_candidates() {
  printf '%s\n' "${1}" >> "${RESOLVE_LOG}"
  case "${1}" in
    match.example.com|shared.example.com|anytls-match.example.com)
      printf '203.0.113.10\n'
      ;;
    mismatch.example.com|wrong.example.com|anytls-wrong.example.com)
      printf '198.51.100.20\n'
      ;;
    *)
      return 1
      ;;
  esac
}

install_hy2_with_input() {
  install_protocols_interactive "fresh"
}

reset_state() {
  rm -rf "${SB_PROJECT_DIR}"
  mkdir -p "${SB_PROJECT_DIR}"
  SB_SHARED_TLS_DOMAIN=""
  SB_HY2_DOMAIN=""
  SB_ANYTLS_DOMAIN=""
  SB_HY2_PASSWORD=""
  SB_ANYTLS_PASSWORD=""
}

reset_state
>"${RESOLVE_LOG}"
install_hy2_with_input <<'EOF'

3
match.example.com
8443
hy2-pass
hy2-user


n
2
/etc/ssl/certs/hy2.pem
/etc/ssl/private/hy2.key

n
n
EOF

if ! grep -Fq 'DOMAIN=match.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected matching hy2 domain to be accepted, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

reset_state
>"${RESOLVE_LOG}"
install_hy2_with_input <<'EOF'

3
wrong.example.com

match.example.com
8443
hy2-pass
hy2-user


n
2
/etc/ssl/certs/hy2.pem
/etc/ssl/private/hy2.key

n
n
EOF

if grep -Fq 'DOMAIN=wrong.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected mismatched hy2 domain to be rejected by default, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Fq 'DOMAIN=match.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected second matching hy2 domain to be accepted, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

reset_state
>"${RESOLVE_LOG}"
install_protocols_interactive "fresh" <<'EOF'

4
anytls-wrong.example.com
y
9443
anytls-user
anytls-pass
2
/etc/ssl/certs/anytls.pem
/etc/ssl/private/anytls.key
n
n
EOF

if ! grep -Fq 'DOMAIN=anytls-wrong.example.com' "${SB_PROTOCOL_STATE_DIR}/anytls.env"; then
  printf 'expected mismatched anytls domain to continue after explicit confirmation, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/anytls.env")" >&2
  exit 1
fi

reset_state
>"${RESOLVE_LOG}"
install_protocols_interactive "fresh" <<'EOF'

3,4
shared.example.com
8443
hy2-pass
hy2-user


n
2
/etc/ssl/certs/shared.pem
/etc/ssl/private/shared.key


9443
anytls-user
anytls-pass
2
/etc/ssl/certs/shared.pem
/etc/ssl/private/shared.key
n
n
EOF

if ! grep -Fq 'DOMAIN=shared.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 state to persist shared domain, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Fq 'DOMAIN=shared.example.com' "${SB_PROTOCOL_STATE_DIR}/anytls.env"; then
  printf 'expected anytls state to reuse validated shared domain, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/anytls.env")" >&2
  exit 1
fi

if [[ "$(grep -Fx 'shared.example.com' "${RESOLVE_LOG}" | wc -l | tr -d ' ')" != "2" ]]; then
  printf 'expected shared domain to be validated for both hy2 and anytls, got log:\n%s\n' "$(cat "${RESOLVE_LOG}")" >&2
  exit 1
fi

SB_PORT="8443"
SB_HY2_DOMAIN="match.example.com"
SB_HY2_PASSWORD="old-pass"
SB_HY2_USER_NAME="hy2-user"
SB_HY2_UP_MBPS=""
SB_HY2_DOWN_MBPS=""
SB_HY2_OBFS_ENABLED="n"
SB_HY2_OBFS_TYPE=""
SB_HY2_OBFS_PASSWORD=""
SB_HY2_TLS_MODE="manual"
SB_HY2_CERT_PATH="/etc/ssl/certs/hy2.pem"
SB_HY2_KEY_PATH="/etc/ssl/private/hy2.key"
SB_HY2_MASQUERADE=""

prompt_hy2_update <<'EOF'

wrong.example.com










EOF

if [[ "${SB_HY2_DOMAIN}" != "match.example.com" ]]; then
  printf 'expected rejected hy2 update domain to preserve old value, got %s\n' "${SB_HY2_DOMAIN}" >&2
  exit 1
fi

SB_PORT="9443"
SB_ANYTLS_DOMAIN="anytls-match.example.com"
SB_ANYTLS_PASSWORD="old-pass"
SB_ANYTLS_USER_NAME="anytls-user"
SB_ANYTLS_TLS_MODE="manual"
SB_ANYTLS_CERT_PATH="/etc/ssl/certs/anytls.pem"
SB_ANYTLS_KEY_PATH="/etc/ssl/private/anytls.key"

prompt_anytls_update <<'EOF'

anytls-wrong.example.com







EOF

if [[ "${SB_ANYTLS_DOMAIN}" != "anytls-match.example.com" ]]; then
  printf 'expected rejected anytls update domain to preserve old value, got %s\n' "${SB_ANYTLS_DOMAIN}" >&2
  exit 1
fi
