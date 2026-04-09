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

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen_port": 8443,
      "users": [
        {
          "name": "hy2-user",
          "password": "hy2-pass"
        }
      ],
      "up_mbps": 100,
      "down_mbps": 50,
      "tls": {
        "enabled": true,
        "server_name": "hy2.example.com",
        "certificate_path": "/etc/ssl/certs/hy2.pem",
        "key_path": "/etc/ssl/private/hy2.key"
      }
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

migrate_legacy_single_protocol_state_if_needed

if [[ ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'expected protocol index file to be created: %s\n' "${SB_PROTOCOL_INDEX_FILE}" >&2
  exit 1
fi

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]; then
  printf 'expected hy2 protocol state file to be created\n' >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=hy2' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to include hy2, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi

if ! grep -Fq 'DOMAIN=hy2.example.com' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 protocol state to persist domain, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi

if ! grep -Fq 'TLS_MODE=manual' "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'expected hy2 protocol state to persist manual tls mode, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/hy2.env")" >&2
  exit 1
fi
