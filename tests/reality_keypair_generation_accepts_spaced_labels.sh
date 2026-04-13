#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e 's|main \"\$@\"|:|' \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/project"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "$1" == "generate" && "$2" == "reality-keypair" ]]; then
  printf 'Private key: private-key-value\n'
  printf 'Public key: public-key-value\n'
  exit 0
fi

exit 1
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

SB_PRIVATE_KEY=""
SB_PUBLIC_KEY=""
SB_SHORT_ID_1="aaaaaaaaaaaaaaaa"
SB_SHORT_ID_2="bbbbbbbbbbbbbbbb"

ensure_vless_reality_materials >/dev/null 2>&1

if [[ "${SB_PRIVATE_KEY}" != "private-key-value" ]]; then
  printf 'expected spaced private key label to be parsed, got %s\n' "${SB_PRIVATE_KEY}" >&2
  exit 1
fi

if [[ "${SB_PUBLIC_KEY}" != "public-key-value" ]]; then
  printf 'expected spaced public key label to be parsed, got %s\n' "${SB_PUBLIC_KEY}" >&2
  exit 1
fi
