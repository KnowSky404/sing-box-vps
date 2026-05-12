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

set_protocol_defaults "hy2"
SB_HY2_DOMAIN="hy2.example.com"
SB_HY2_PASSWORD="hy2-password"
SB_HY2_USER_NAME="hy2-user"
SB_HY2_TLS_MODE="acme"
SB_HY2_ACME_MODE="http"
SB_HY2_ACME_DOMAIN="hy2.example.com"
SB_HY2_ACME_EMAIL=""

build_hy2_inbound_json > "${TMP_DIR}/hy2.json"

if ! jq -e --arg dir "${TMP_DIR}/project/acme" '.tls.acme.domain == ["hy2.example.com"] and .tls.acme.data_directory == $dir' "${TMP_DIR}/hy2.json" >/dev/null; then
  printf 'expected hy2 inbound to embed acme settings compatible with sing-box 1.13.x, got:\n%s\n' "$(cat "${TMP_DIR}/hy2.json")" >&2
  exit 1
fi

if jq -e '.tls.certificate_provider? != null' "${TMP_DIR}/hy2.json" >/dev/null; then
  printf 'expected hy2 inbound to avoid certificate_provider rejected by sing-box 1.13.x, got:\n%s\n' "$(cat "${TMP_DIR}/hy2.json")" >&2
  exit 1
fi

build_hy2_certificate_provider_json > "${TMP_DIR}/hy2-provider.json"

if [[ -s "${TMP_DIR}/hy2-provider.json" ]]; then
  printf 'expected hy2 acme provider builder to emit no root certificate provider, got:\n%s\n' "$(cat "${TMP_DIR}/hy2-provider.json")" >&2
  exit 1
fi
