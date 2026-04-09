#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

if ! grep -Fq 'ACME 邮箱 (可留空，用于证书通知): ' "${REPO_ROOT}/install.sh"; then
  printf 'expected hy2 install prompt to clarify ACME email is optional\n' >&2
  exit 1
fi

if ! grep -Fq 'ACME 邮箱 (当前: ${SB_HY2_ACME_EMAIL}, 留空保持，用于证书通知): ' "${REPO_ROOT}/install.sh"; then
  printf 'expected hy2 update prompt to clarify ACME email is optional\n' >&2
  exit 1
fi

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

SB_HY2_TLS_MODE="acme"
SB_HY2_ACME_MODE="http"
SB_HY2_ACME_DOMAIN="hy2.example.com"
SB_HY2_ACME_EMAIL=""
SB_HY2_DNS_PROVIDER="cloudflare"
SB_HY2_CF_API_TOKEN=""

build_hy2_certificate_provider_json > "${TMP_DIR}/provider.json"

if jq -e '.email? != null' "${TMP_DIR}/provider.json" >/dev/null; then
  printf 'expected hy2 acme certificate provider to omit empty email, got:\n%s\n' "$(cat "${TMP_DIR}/provider.json")" >&2
  exit 1
fi
