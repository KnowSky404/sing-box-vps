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
  -e 's|main "\$@\"|:|' \
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

set_protocol_defaults "anytls"
SB_ANYTLS_DOMAIN="anytls.example.com"
SB_ANYTLS_PASSWORD="anytls-password"
SB_ANYTLS_USER_NAME="anytls-user"
SB_ANYTLS_TLS_MODE="acme"
SB_ANYTLS_ACME_MODE="dns"
SB_ANYTLS_ACME_DOMAIN="anytls.example.com"
SB_ANYTLS_ACME_EMAIL=""
SB_ANYTLS_DNS_PROVIDER="cloudflare"
SB_ANYTLS_CF_API_TOKEN="cf-token"

build_anytls_inbound_json > "${TMP_DIR}/anytls.json"

if ! jq -e --arg dir "${TMP_DIR}/project/acme" '.tls.acme.domain == ["anytls.example.com"] and .tls.acme.data_directory == $dir' "${TMP_DIR}/anytls.json" >/dev/null; then
  printf 'expected anytls inbound to embed acme settings compatible with sing-box 1.13.x, got:\n%s\n' "$(cat "${TMP_DIR}/anytls.json")" >&2
  exit 1
fi

if jq -e '.tls.certificate_provider? != null' "${TMP_DIR}/anytls.json" >/dev/null; then
  printf 'expected anytls inbound to avoid certificate_provider rejected by sing-box 1.13.x, got:\n%s\n' "$(cat "${TMP_DIR}/anytls.json")" >&2
  exit 1
fi

build_anytls_certificate_provider_json > "${TMP_DIR}/anytls-provider.json"

if [[ -s "${TMP_DIR}/anytls-provider.json" ]]; then
  printf 'expected anytls acme provider builder to emit no root certificate provider, got:\n%s\n' "$(cat "${TMP_DIR}/anytls-provider.json")" >&2
  exit 1
fi

if ! jq -e '.tls.acme.dns01_challenge.provider == "cloudflare" and .tls.acme.dns01_challenge.api_token == "cf-token"' "${TMP_DIR}/anytls.json" >/dev/null; then
  printf 'expected anytls inline dns acme credentials, got:\n%s\n' "$(cat "${TMP_DIR}/anytls.json")" >&2
  exit 1
fi

if jq -e '.tls.acme.email? != null' "${TMP_DIR}/anytls.json" >/dev/null; then
  printf 'expected anytls inline acme settings to omit empty email, got:\n%s\n' "$(cat "${TMP_DIR}/anytls.json")" >&2
  exit 1
fi
