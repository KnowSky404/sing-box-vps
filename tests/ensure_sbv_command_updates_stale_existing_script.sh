#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
SBV_BIN_PATH="${TMP_DIR}/usr-local-bin-sbv"
CURRENT_VERSION_LINE=$(sed -n 's/^readonly SCRIPT_VERSION=\"[^\"]*\"$/&/p' "${REPO_ROOT}/install.sh" | head -n 1)

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e "s|/usr/local/bin/sbv|${SBV_BIN_PATH}|g" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
readonly SCRIPT_VERSION="2026042202"
printf 'stale sbv\n'
EOF
chmod +x "${SBV_BIN_PATH}"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash

output_file=""
while (($#)); do
  case "$1" in
    -o)
      output_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${output_file}" ]]; then
  cat > "${output_file}" <<'SCRIPT'
#!/usr/bin/env bash
readonly SCRIPT_VERSION="1999010101"
printf 'remote sbv\n'
SCRIPT
else
  printf 'readonly SCRIPT_VERSION="1999010101"\n'
fi
EOF
chmod +x "${TMP_DIR}/bin/curl"

cat > "${TMP_DIR}/bin/hostname" <<'EOF'
#!/usr/bin/env bash

printf 'test-host\n'
EOF
chmod +x "${TMP_DIR}/bin/hostname"

cat > "${TMP_DIR}/bin/sysctl" <<'EOF'
#!/usr/bin/env bash

printf 'net.ipv4.tcp_congestion_control = cubic\n'
EOF
chmod +x "${TMP_DIR}/bin/sysctl"

export PATH="${TMP_DIR}/bin:${PATH}"

printf '0\n' | bash "${TESTABLE_INSTALL}" >/dev/null 2>&1

if ! grep -Fqx "${CURRENT_VERSION_LINE}" "${SBV_BIN_PATH}"; then
  printf 'expected existing sbv command to be refreshed to current script version, got:\n' >&2
  sed -n '1,5p' "${SBV_BIN_PATH}" >&2
  exit 1
fi
