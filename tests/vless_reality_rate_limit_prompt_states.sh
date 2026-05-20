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

cat > "${TMP_DIR}/bin/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "generate" && "${2:-}" == "reality-keypair" ]]; then
  printf 'PrivateKey: private-key\n'
  printf 'PublicKey: public-key\n'
  exit 0
fi

exit 0
EOF
chmod +x "${TMP_DIR}/bin/sing-box"

export PATH="${TMP_DIR}/bin:${PATH}"

# shellcheck disable=SC1090
source "${TESTABLE_INSTALL}"

check_port_conflict() { :; }
prompt_reality_sni_install() { SB_SNI="apple.com"; }
prompt_reality_sni_update() { SB_SNI="${SB_SNI:-apple.com}"; }

run_case() {
  local case_name=$1 input=$2 expected_up=$3 expected_down=$4
  local state_file
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"

  prompt_vless_reality_install <<< "${input}"
  save_protocol_state "vless-reality"

  state_file="${SB_PROTOCOL_STATE_DIR}/vless-reality.d/main.env"
  if [[ ! -f "${state_file}" ]]; then
    printf '[%s] expected %s to exist\n' "${case_name}" "${state_file}" >&2
    exit 1
  fi

  if ! grep -Eq "^RATE_LIMIT_UP_MBPS=${expected_up}$" "${state_file}"; then
    printf '[%s] expected up=%s, got:\n%s\n' "${case_name}" "${expected_up}" "$(cat "${state_file}")" >&2
    exit 1
  fi

  if ! grep -Eq "^RATE_LIMIT_DOWN_MBPS=${expected_down}$" "${state_file}"; then
    printf '[%s] expected down=%s, got:\n%s\n' "${case_name}" "${expected_down}" "$(cat "${state_file}")" >&2
    exit 1
  fi
}

run_case "unlimited" $'443\nn\n' "" ""
run_case "down-only" $'443\ny\n\n20\n' "" "20"
run_case "up-only" $'443\ny\n5\n\n' "5" ""
run_case "both" $'443\ny\n5\n20\n' "5" "20"
