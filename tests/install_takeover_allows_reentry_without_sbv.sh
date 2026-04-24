#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

get_os_info() {
  OS_NAME="debian"
  OS_VERSION="12"
}

get_arch() {
  ARCH="amd64"
}

install_dependencies() {
  :
}

install_binary() {
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"
  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.5\n'
  exit 0
fi

if [[ "${1:-}" == "check" ]]; then
  exit 0
fi

exit 0
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}

ensure_sbv_command_installed() {
  log_warn "模拟 sbv 安装失败。"
}

write_legacy_config() {
  mkdir -p "${SB_PROJECT_DIR}"
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

write_runtime_artifacts_without_sbv() {
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"

  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version 1.13.5\n'
  exit 0
fi

if [[ "${1:-}" == "check" ]]; then
  exit 0
fi

exit 0
EOF
  chmod +x "${SINGBOX_BIN_PATH}"

  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF
}

run_takeover() {
  if ! TAKEOVER_OUTPUT=$(printf '1\n' | install_or_update_singbox 2>&1); then
    printf 'expected takeover flow to succeed, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  TAKEOVER_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")
  if [[ "${TAKEOVER_OUTPUT}" != *"检测到残缺的现有实例"* ]]; then
    printf 'expected incomplete-instance menu before takeover, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi
}

run_reentry_check() {
  if ! REENTRY_OUTPUT=$(printf '0\n' | install_or_update_singbox 2>&1); then
    printf 'expected reentry flow to succeed, got:\n%s\n' "${REENTRY_OUTPUT}" >&2
    exit 1
  fi

  REENTRY_OUTPUT=$(strip_ansi "${REENTRY_OUTPUT}")

  if [[ "${REENTRY_OUTPUT}" == *"检测到残缺的现有实例"* ]]; then
    printf 'expected post-takeover reentry without sbv to avoid incomplete-instance menu, got:\n%s\n' "${REENTRY_OUTPUT}" >&2
    exit 1
  fi

  if [[ "${REENTRY_OUTPUT}" != *"更新 sing-box 二进制并保留当前配置"* ]]; then
    printf 'expected post-takeover reentry without sbv to land on healthy-instance menu, got:\n%s\n' "${REENTRY_OUTPUT}" >&2
    exit 1
  fi
}

write_legacy_config
write_runtime_artifacts_without_sbv

run_takeover
run_reentry_check
