#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

perl -0pe '
  s/^\s*main "\$@"\s*$//m;
  s|readonly SB_PROJECT_DIR="/root/sing-box-vps"|readonly SB_PROJECT_DIR="'"${TMP_DIR}"'/project"|;
  s|readonly SINGBOX_BIN_PATH="/usr/local/bin/sing-box"|readonly SINGBOX_BIN_PATH="'"${TMP_DIR}"'/bin/sing-box"|;
  s|readonly SBV_BIN_PATH="/usr/local/bin/sbv"|readonly SBV_BIN_PATH="'"${TMP_DIR}"'/bin/sbv"|;
  s|readonly SINGBOX_SERVICE_FILE="/etc/systemd/system/sing-box.service"|readonly SINGBOX_SERVICE_FILE="'"${TMP_DIR}"'/sing-box.service"|;
' "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'legacy-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "check" && "${2:-}" == "-c" ]]; then
  config_path=${3:?}
  if ! jq -e '.outbounds[] | select(.type == "vless") | .tls.utls.enabled == true and .tls.utls.fingerprint == "chrome"' "${config_path}" >/dev/null; then
    printf 'FATAL[0000] initialize outbound[2]: uTLS is required by reality client\n' >&2
    exit 1
  fi
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

get_public_ip() {
  printf '203.0.113.20\n'
}

cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "legacy-vless-in",
      "listen_port": 443,
      "users": [
        {
          "uuid": "11111111-1111-1111-1111-111111111111"
        }
      ],
      "tls": {
        "server_name": "www.cloudflare.com",
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

if [[ ! -f "${SB_PROTOCOL_STATE_DIR}/vless-reality.env" ]]; then
  printf 'expected legacy migration to create vless-reality state file\n' >&2
  exit 1
fi

if ! export_singbox_client_config > "${TMP_DIR}/stdout.txt" 2> "${TMP_DIR}/stderr.txt"; then
  printf 'expected legacy vless export to pass after migration, stderr was:\n%s\n' "$(cat "${TMP_DIR}/stderr.txt")" >&2
  exit 1
fi

EXPORT_PATH="${SB_PROJECT_DIR}/client/sing-box-client.json"

if [[ ! -f "${EXPORT_PATH}" ]]; then
  printf 'expected exported config at %s\n' "${EXPORT_PATH}" >&2
  exit 1
fi

if ! jq -e '.outbounds[] | select(.type == "vless" and .tag == "vless-reality-443") | .tls.utls.enabled == true and .tls.utls.fingerprint == "chrome"' "${EXPORT_PATH}" >/dev/null; then
  printf 'expected migrated legacy export to include tls.utls chrome fingerprint, got:\n%s\n' "$(cat "${EXPORT_PATH}")" >&2
  exit 1
fi
