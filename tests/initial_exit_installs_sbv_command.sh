#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
SBV_BIN_PATH="${TMP_DIR}/usr-local-bin-sbv"

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${TMP_DIR}/project\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TMP_DIR}/bin/sing-box\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e "s|/usr/local/bin/sbv|${SBV_BIN_PATH}|g" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"

mkdir -p "${TMP_DIR}/project" "${TMP_DIR}/bin"

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
  printf '#!/usr/bin/env bash\nprintf "sbv stub\\n"\n' > "${output_file}"
else
  printf 'readonly SCRIPT_VERSION="2026041302"\n'
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

if [[ ! -x "${SBV_BIN_PATH}" ]]; then
  printf 'expected direct exit from bootstrap run to install sbv command at %s\n' "${SBV_BIN_PATH}" >&2
  exit 1
fi
