#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

fixture_root="sing-box-1.14.0-linux-amd64"
mkdir -p "${TMP_DIR}/archive/${fixture_root}"
cat > "${TMP_DIR}/archive/${fixture_root}/sing-box" <<'EOF_BINARY'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  marker) printf 'atomically-installed\n' ;;
esac
EOF_BINARY
printf 'libcronet-test\n' > "${TMP_DIR}/archive/${fixture_root}/libcronet.so"
tar -czf "${TMP_DIR}/release.tar.gz" -C "${TMP_DIR}/archive" "${fixture_root}"

curl() {
  local destination=''
  while (($#)); do
    if [[ "$1" == -o ]]; then destination=$2; shift 2; else shift; fi
  done
  [[ -n "${destination}" ]] || return 1
  cp "${TMP_DIR}/release.tar.gz" "${destination}"
}
ldconfig() { printf 'refresh\n' >> "${TMP_DIR}/ldconfig.calls"; }
mv() {
  local args=("$@") source_arg destination_arg
  source_arg=${args[${#args[@]}-2]}
  destination_arg=${args[${#args[@]}-1]}
  if [[ "${destination_arg}" == "${SINGBOX_BIN_PATH}" ]]; then
    printf '%s\n' "${source_arg}" > "${TMP_DIR}/rename.source"
    stat -c '%a' "${source_arg}" > "${TMP_DIR}/rename.mode"
  fi
  command mv "$@"
}

SB_VERSION="1.14.0"
ARCH="amd64"
install_binary >/dev/null
[[ "$(cat "${TMP_DIR}/rename.source")" == "${TMP_DIR}/bin/.sing-box.restore."* ]]
[[ "$(cat "${TMP_DIR}/rename.mode")" == 755 ]]
[[ "$("${SINGBOX_BIN_PATH}" marker)" == atomically-installed ]]
[[ "$(cat "$(singbox_library_path)")" == libcronet-test ]]
[[ "$(cat "${SB_NAIVE_LIBRARY_MARKER}")" == "$(sha256sum "$(singbox_library_path)" | awk '{print $1}')" ]]
[[ "$(wc -l < "${TMP_DIR}/ldconfig.calls")" == 1 ]]

printf 'unowned-libcronet\n' > "$(singbox_library_path)"
rm -f "${SB_NAIVE_LIBRARY_MARKER}" "${TMP_DIR}/ldconfig.calls"
install_binary >/dev/null
[[ "$(cat "$(singbox_library_path)")" == unowned-libcronet ]]
[[ ! -e "${TMP_DIR}/ldconfig.calls" ]]
unset -f curl mv ldconfig

write_singbox_binary() {
  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.5\n'
  exit 0
fi

exit 0
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}

write_config() {
  mkdir -p "${TMP_DIR}/project"
  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
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
}

write_vless_reality_protocol_state() {
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"

  cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

  cat > "$(protocol_state_file vless-reality)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF
}

write_service_file() {
  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF
}

write_singbox_binary
write_config
write_vless_reality_protocol_state
write_service_file

unset OS_NAME || true
unset OS_VERSION || true

GET_OS_INFO_CALLS=0
INSTALL_DEPENDENCIES_SAW_OS_NAME=""

load_current_config_state() {
  SB_PROTOCOL="vless+reality"
  SB_PORT="443"
}
prompt_singbox_version() { SB_VERSION="1.13.9"; }
get_latest_version() { :; }
install_binary() {
  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.9\n'
fi
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}
validate_config_file() { return 0; }
setup_service() { :; }
display_status_summary() { :; }
systemctl() {
  if [[ "${1:-}" == "is-active" ]]; then
    printf 'active\n'
  fi
}
get_os_info() {
  GET_OS_INFO_CALLS=$((GET_OS_INFO_CALLS + 1))
  OS_NAME="debian"
  OS_VERSION="12"
}
install_dependencies() {
  INSTALL_DEPENDENCIES_SAW_OS_NAME="${OS_NAME}"
}

SB_VERSION="1.13.9"
if ! update_singbox_binary_preserving_config >/dev/null 2>&1; then
  printf 'expected update binary flow to complete without crashing\n' >&2
  exit 1
fi

if (( GET_OS_INFO_CALLS == 0 )); then
  printf 'expected update binary flow to initialize OS information before installing dependencies\n' >&2
  exit 1
fi

if [[ "${INSTALL_DEPENDENCIES_SAW_OS_NAME}" != "debian" ]]; then
  printf 'expected install_dependencies to observe initialized OS_NAME, got %s\n' "${INSTALL_DEPENDENCIES_SAW_OS_NAME:-<unset>}" >&2
  exit 1
fi
