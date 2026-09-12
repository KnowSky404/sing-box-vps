#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
perl -0pi -e 's|local temp_dir="/tmp/sing-box-install"|local temp_dir="'"${TMP_DIR}"'/download"|' "${TESTABLE_INSTALL}"
source_testable_install

ATOMIC_RENAME_SOURCE=""
ATOMIC_RENAME_MODE=""

wget() {
  [[ "${1:-}" == "-O" && -n "${2:-}" ]]
  : > "${2}"
}

tar() {
  local extracted_dir="${TMP_DIR}/download/extracted"

  mkdir -p "${extracted_dir}"
  cat > "${extracted_dir}/sing-box" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "marker" ]]; then
  printf 'atomically-installed\n'
fi
EOF
  chmod 0644 "${extracted_dir}/sing-box"
  printf 'libcronet-test\n' > "${extracted_dir}/libcronet.so"
  chmod 0644 "${extracted_dir}/libcronet.so"
}

LD_CONFIG_CALLS=0
ldconfig() {
  LD_CONFIG_CALLS=$((LD_CONFIG_CALLS + 1))
}

mv() {
  local args=("$@")
  local source_arg=${args[${#args[@]}-2]}
  local destination_arg=${args[${#args[@]}-1]}

  if [[ "${destination_arg}" == "${SINGBOX_BIN_PATH}" ]]; then
    ATOMIC_RENAME_SOURCE=${source_arg}
    ATOMIC_RENAME_MODE=$(stat -c '%a' "${source_arg}")
  fi
  command mv "$@"
}

SB_VERSION="1.14.0"
ARCH="amd64"
install_binary >/dev/null

if [[ "${ATOMIC_RENAME_SOURCE}" != "${TMP_DIR}/bin/.sing-box.restore."* ]]; then
  printf 'expected install to stage the binary in its target directory, got %s\n' "${ATOMIC_RENAME_SOURCE:-<none>}" >&2
  exit 1
fi
if [[ "${ATOMIC_RENAME_MODE}" != "755" ]]; then
  printf 'expected staged install binary mode 755 before rename, got %s\n' "${ATOMIC_RENAME_MODE:-<none>}" >&2
  exit 1
fi
if [[ "$("${SINGBOX_BIN_PATH}" marker)" != "atomically-installed" ]]; then
  printf 'expected atomically installed binary at the final path\n' >&2
  exit 1
fi

if [[ "$(cat "$(singbox_library_path)")" != "libcronet-test" ]]; then
  printf 'expected libcronet.so to be installed beside the binary family\n' >&2
  exit 1
fi
if [[ "$(cat "${SB_NAIVE_LIBRARY_MARKER}")" != "$(sha256sum "$(singbox_library_path)" | awk '{print $1}')" ]]; then
  printf 'expected the managed libcronet.so marker to contain its committed hash\n' >&2
  exit 1
fi
if (( LD_CONFIG_CALLS != 1 )); then
  printf 'expected install to refresh the dynamic loader cache once, got %s\n' "${LD_CONFIG_CALLS}" >&2
  exit 1
fi

printf 'unowned-libcronet\n' > "$(singbox_library_path)"
rm -f "${SB_NAIVE_LIBRARY_MARKER}"
LD_CONFIG_CALLS=0
install_binary >/dev/null
if [[ "$(cat "$(singbox_library_path)")" != "unowned-libcronet" ]]; then
  printf 'expected an unowned libcronet.so to remain untouched during reinstall\n' >&2
  exit 1
fi
if (( LD_CONFIG_CALLS != 0 )); then
  printf 'expected reinstall to skip loader refresh for an unowned library, got %s\n' "${LD_CONFIG_CALLS}" >&2
  exit 1
fi

unset -f wget tar mv

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
