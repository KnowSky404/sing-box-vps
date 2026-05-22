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
  -e 's|main "\$@"|:|' \
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

check_port_conflict() { :; }
validate_tls_domain_points_to_server() { return 0; }
ensure_hy2_materials() { :; }
ensure_anytls_materials() { :; }

assert_eq() {
  local name=$1 expected=$2 actual=$3

  if [[ "${actual}" != "${expected}" ]]; then
    printf '[%s] expected %q, got %q\n' "${name}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_helper_output() {
  local name=$1 expected=$2 command=$3 input=$4 actual

  actual=$(eval "${command}" <<< "${input}" | tail -n 1)
  assert_eq "${name}" "${expected}" "${actual}"
}

assert_helper_output "choice rejects non-number and out-of-range" "2" \
  'prompt_choice "请选择 [1-2]: " 1 2 ""' \
  $'abc\n3\n2\n'

assert_helper_output "choice default accepts blank" "1" \
  'prompt_choice "请选择 [1-2] (默认 1): " 1 2 "1"' \
  $'\n'

assert_helper_output "yes-no rejects typo and normalizes uppercase" "y" \
  'prompt_yes_no "是否继续 [y/n]: " ""' \
  $'yes\ny\n'

assert_helper_output "optional positive integer rejects unit suffix" "50" \
  'prompt_optional_positive_integer "上行带宽 Mbps: " "" "上行带宽"' \
  $'50M\n0\n50\n'

assert_helper_output "port rejects non-numeric and out-of-range" "443" \
  'prompt_port "端口: " ""' \
  $'443M\n70000\n443\n'

assert_helper_output "optional email rejects malformed address" "admin@example.com" \
  'prompt_optional_email "ACME 邮箱: " ""' \
  $'admin\nadmin@example.com\n'

prompt_hy2_install <<< $'hy2.example.com\n443\n\n\n50M\n50\n100G\n100\ny\n\n1\n1\nadmin\nadmin@example.com\n\n\n'
assert_eq "hy2 install up bandwidth" "50" "${SB_HY2_UP_MBPS}"
assert_eq "hy2 install down bandwidth" "100" "${SB_HY2_DOWN_MBPS}"
assert_eq "hy2 install obfs yes" "y" "${SB_HY2_OBFS_ENABLED}"
assert_eq "hy2 install acme email" "admin@example.com" "${SB_HY2_ACME_EMAIL}"

SB_PORT="443"
SB_HY2_DOMAIN="old.example.com"
SB_HY2_PASSWORD="old-password"
SB_HY2_USER_NAME="old-user"
SB_HY2_UP_MBPS="10"
SB_HY2_DOWN_MBPS="20"
SB_HY2_OBFS_ENABLED="n"
SB_HY2_OBFS_PASSWORD=""
SB_HY2_TLS_MODE="acme"
SB_HY2_ACME_MODE="http"
SB_HY2_ACME_EMAIL="old@example.com"
SB_HY2_ACME_DOMAIN="old.example.com"
SB_HY2_DNS_PROVIDER="cloudflare"
SB_HY2_CF_API_TOKEN=""
SB_HY2_CERT_PATH=""
SB_HY2_KEY_PATH=""
SB_HY2_MASQUERADE=""

prompt_hy2_update <<< $'\n\n\n\nbad\n30\n40M\n40\nmaybe\ny\n\n3\n1\n3\n1\nbad-email\nnew@example.com\nnew.example.com\n'
assert_eq "hy2 update up bandwidth" "30" "${SB_HY2_UP_MBPS}"
assert_eq "hy2 update down bandwidth" "40" "${SB_HY2_DOWN_MBPS}"
assert_eq "hy2 update obfs yes" "y" "${SB_HY2_OBFS_ENABLED}"
assert_eq "hy2 update tls mode remains acme" "acme" "${SB_HY2_TLS_MODE}"
assert_eq "hy2 update acme mode http" "http" "${SB_HY2_ACME_MODE}"
assert_eq "hy2 update acme email" "new@example.com" "${SB_HY2_ACME_EMAIL}"

SB_PORT="443"
SB_HY2_DOMAIN="manual.example.com"
SB_HY2_PASSWORD="manual-password"
SB_HY2_USER_NAME="manual-user"
SB_HY2_UP_MBPS="10"
SB_HY2_DOWN_MBPS="20"
SB_HY2_OBFS_ENABLED="n"
SB_HY2_OBFS_PASSWORD=""
SB_HY2_TLS_MODE="manual"
SB_HY2_ACME_MODE="legacy-dns"
SB_HY2_ACME_EMAIL="legacy@example.com"
SB_HY2_ACME_DOMAIN="legacy.example.com"
SB_HY2_DNS_PROVIDER="cloudflare"
SB_HY2_CF_API_TOKEN="legacy-token"
SB_HY2_CERT_PATH="/etc/ssl/certs/manual.pem"
SB_HY2_KEY_PATH="/etc/ssl/private/manual.key"
SB_HY2_MASQUERADE="https://example.com"

prompt_hy2_update <<< $'\n\n\n\n\n\n\n\n\n\n'
assert_eq "hy2 update blank up clears bandwidth" "" "${SB_HY2_UP_MBPS}"
assert_eq "hy2 update blank down clears bandwidth" "" "${SB_HY2_DOWN_MBPS}"
assert_eq "hy2 update blank tls keeps manual mode" "manual" "${SB_HY2_TLS_MODE}"
assert_eq "hy2 update blank keeps legacy acme mode" "legacy-dns" "${SB_HY2_ACME_MODE}"
assert_eq "hy2 update blank keeps cert path" "/etc/ssl/certs/manual.pem" "${SB_HY2_CERT_PATH}"
assert_eq "hy2 update blank keeps key path" "/etc/ssl/private/manual.key" "${SB_HY2_KEY_PATH}"

SB_PORT="443"
SB_ANYTLS_DOMAIN="manual-any.example.com"
SB_ANYTLS_PASSWORD="manual-password"
SB_ANYTLS_USER_NAME="manual-user"
SB_ANYTLS_TLS_MODE="manual"
SB_ANYTLS_ACME_MODE="legacy-dns"
SB_ANYTLS_ACME_EMAIL="legacy@example.com"
SB_ANYTLS_ACME_DOMAIN="legacy.example.com"
SB_ANYTLS_DNS_PROVIDER="cloudflare"
SB_ANYTLS_CF_API_TOKEN="legacy-token"
SB_ANYTLS_CERT_PATH="/etc/ssl/certs/anytls.pem"
SB_ANYTLS_KEY_PATH="/etc/ssl/private/anytls.key"

prompt_anytls_update <<< $'\n\n\n\n\n'
assert_eq "anytls update blank tls keeps manual mode" "manual" "${SB_ANYTLS_TLS_MODE}"
assert_eq "anytls update blank keeps legacy acme mode" "legacy-dns" "${SB_ANYTLS_ACME_MODE}"
assert_eq "anytls update blank keeps cert path" "/etc/ssl/certs/anytls.pem" "${SB_ANYTLS_CERT_PATH}"
assert_eq "anytls update blank keeps key path" "/etc/ssl/private/anytls.key" "${SB_ANYTLS_KEY_PATH}"
