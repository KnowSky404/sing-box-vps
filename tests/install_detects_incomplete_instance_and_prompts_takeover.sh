#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

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

reset_instance_artifacts() {
  rm -f "${SINGBOX_BIN_PATH}" "${SINGBOX_CONFIG_FILE}" "${SINGBOX_SERVICE_FILE}" "${SB_PROTOCOL_INDEX_FILE}" "${SBV_BIN_PATH}"
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
}

install_or_reconfigure_singbox() {
  printf 'INSTALL_OR_RECONFIGURE_CALLED\n'
}

run_install_flow() {
  local input=$1

  if ! printf '%s\n' "${input}" | install_or_update_singbox 2>&1; then
    printf 'install_or_update_singbox unexpectedly failed for input %s\n' "${input}" >&2
    return 1
  fi
}

reset_instance_artifacts

cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${SBV_BIN_PATH}"

fresh_output=$(run_install_flow '0')
fresh_plain_output=$(strip_ansi "${fresh_output}")

if [[ "${fresh_plain_output}" != *"INSTALL_OR_RECONFIGURE_CALLED"* ]]; then
  printf 'expected sbv-only host to stay on fresh install path, got:\n%s\n' "${fresh_output}" >&2
  exit 1
fi

if [[ "${fresh_plain_output}" == *"检测到残缺的现有实例"* ]]; then
  printf 'expected sbv-only host to avoid incomplete-instance menu, got:\n%s\n' "${fresh_output}" >&2
  exit 1
fi

if [[ "${fresh_plain_output}" == *"更新 sing-box 二进制并保留当前配置"* ]]; then
  printf 'expected sbv-only host to avoid healthy-instance update menu, got:\n%s\n' "${fresh_output}" >&2
  exit 1
fi

write_singbox_binary
write_config

incomplete_output=$(run_install_flow '0')
incomplete_plain_output=$(strip_ansi "${incomplete_output}")

if [[ "${incomplete_plain_output}" != *"检测到残缺的现有实例"* ]]; then
  printf 'expected incomplete-instance detection message, got:\n%s\n' "${incomplete_output}" >&2
  exit 1
fi

if [[ "${incomplete_plain_output}" != *"接管现有实例"* ]]; then
  printf 'expected takeover option in incomplete-instance menu, got:\n%s\n' "${incomplete_output}" >&2
  exit 1
fi

if [[ "${incomplete_plain_output}" != *"按全新安装处理"* ]]; then
  printf 'expected full-install option in incomplete-instance menu, got:\n%s\n' "${incomplete_output}" >&2
  exit 1
fi

if [[ "${incomplete_plain_output}" == *"更新 sing-box 二进制并保留当前配置"* ]]; then
  printf 'expected incomplete-instance flow to avoid legacy binary/config-only menu, got:\n%s\n' "${incomplete_output}" >&2
  exit 1
fi

reset_instance_artifacts
write_singbox_binary
write_config

incomplete_install_output=$(run_install_flow '2')
incomplete_install_plain_output=$(strip_ansi "${incomplete_install_output}")

if [[ "${incomplete_install_plain_output}" != *"检测到残缺的现有实例"* ]]; then
  printf 'expected option 2 flow to start from incomplete-instance menu, got:\n%s\n' "${incomplete_install_output}" >&2
  exit 1
fi

if [[ "${incomplete_install_plain_output}" != *"INSTALL_OR_RECONFIGURE_CALLED"* ]]; then
  printf 'expected option 2 from incomplete-instance menu to dispatch to install_or_reconfigure_singbox, got:\n%s\n' "${incomplete_install_output}" >&2
  exit 1
fi

reset_instance_artifacts
write_singbox_binary
write_config
write_vless_reality_protocol_state

cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF

missing_sbv_output=$(run_install_flow '0')
missing_sbv_plain_output=$(strip_ansi "${missing_sbv_output}")

if [[ "${missing_sbv_plain_output}" != *"检测到残缺的现有实例"* ]]; then
  printf 'expected installed instance missing only sbv to be treated as incomplete, got:\n%s\n' "${missing_sbv_output}" >&2
  exit 1
fi

if [[ "${missing_sbv_plain_output}" != *"接管现有实例"* ]]; then
  printf 'expected installed instance missing only sbv to offer takeover, got:\n%s\n' "${missing_sbv_output}" >&2
  exit 1
fi

if [[ "${missing_sbv_plain_output}" == *"更新 sing-box 二进制并保留当前配置"* ]]; then
  printf 'expected installed instance missing only sbv to avoid healthy-instance update menu, got:\n%s\n' "${missing_sbv_output}" >&2
  exit 1
fi

reset_instance_artifacts
write_singbox_binary
write_config

cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF

legacy_output=$(run_install_flow '0')
legacy_plain_output=$(strip_ansi "${legacy_output}")

if [[ "${legacy_plain_output}" != *"检测到残缺的现有实例"* ]]; then
  printf 'expected installed instance without protocol state layer to be treated as incomplete, got:\n%s\n' "${legacy_output}" >&2
  exit 1
fi

if [[ "${legacy_plain_output}" != *"接管现有实例"* ]]; then
  printf 'expected installed instance without protocol state layer to offer takeover, got:\n%s\n' "${legacy_output}" >&2
  exit 1
fi

reset_instance_artifacts
write_singbox_binary
write_config
write_vless_reality_protocol_state

cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF

cat > "$(protocol_state_file vless-reality)" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=vless_reality_test-host
PORT=8443
UUID=11111111-1111-1111-1111-111111111111
SNI=apple.com
REALITY_PRIVATE_KEY=private-key
REALITY_PUBLIC_KEY=
SHORT_ID_1=aaaaaaaaaaaaaaaa
SHORT_ID_2=bbbbbbbbbbbbbbbb
EOF

stale_state_output=$(run_install_flow '0')
stale_state_plain_output=$(strip_ansi "${stale_state_output}")

if [[ "${stale_state_plain_output}" != *"检测到残缺的现有实例"* ]]; then
  printf 'expected stale protocol state to be treated as incomplete, got:\n%s\n' "${stale_state_output}" >&2
  exit 1
fi

if [[ "${stale_state_plain_output}" != *"接管现有实例"* ]]; then
  printf 'expected stale protocol state to offer takeover, got:\n%s\n' "${stale_state_output}" >&2
  exit 1
fi
