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
      "type": "vless",
      "tag": "vless-in",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111"
        }
      ],
      "tls": {
        "server_name": "apple.com",
        "reality": {
          "private_key": "private-key",
          "short_id": [
            "aaaaaaaaaaaaaaaa",
            "bbbbbbbbbbbbbbbb"
          ]
        }
      }
    }
  ],
  "route": {
    "rules": []
  }
}
EOF

cat > "${SB_KEY_FILE}" <<'EOF'
PRIVATE_KEY=private-key
PUBLIC_KEY=public-key
EOF

migrate_legacy_single_protocol_state_if_needed

if [[ ! -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'expected protocol index file to be created: %s\n' "${SB_PROTOCOL_INDEX_FILE}" >&2
  exit 1
fi

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" ]]; then
  printf 'expected vless protocol state file to be created\n' >&2
  exit 1
fi

if ! grep -Fq 'INSTALLED_PROTOCOLS=vless-reality' "${SB_PROTOCOL_INDEX_FILE}"; then
  printf 'expected protocol index to include vless-reality, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi

if ! grep -Fq 'UUID=11111111-1111-1111-1111-111111111111' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
  printf 'expected vless protocol state to persist UUID, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
  exit 1
fi

if ! grep -Fq 'REALITY_PUBLIC_KEY=public-key' "${SB_PROTOCOL_STATE_DIR}/vless-reality.env"; then
  printf 'expected vless protocol state to persist REALITY public key, got:\n%s\n' "$(cat "${SB_PROTOCOL_STATE_DIR}/vless-reality.env")" >&2
  exit 1
fi
