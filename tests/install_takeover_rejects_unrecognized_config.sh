#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

write_validating_binary() {
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"

  cat > "${SINGBOX_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash

case "${1:-}" in
  version)
    printf 'sing-box version 1.13.5\n'
    exit 0
    ;;
  check)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}

write_service_file() {
  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF
}

write_unknown_protocol_config() {
  mkdir -p "${SB_PROJECT_DIR}"

  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen_port": 8388,
      "method": "2022-blake3-aes-128-gcm",
      "password": "secret"
    }
  ],
  "route": {
    "rules": []
  }
}
EOF
}

write_validating_binary
write_service_file
write_unknown_protocol_config

set +e
TAKEOVER_OUTPUT=$(printf '1\n' | install_or_update_singbox 2>&1)
TAKEOVER_STATUS=$?
set -e

if [[ "${TAKEOVER_STATUS}" == "0" ]]; then
  printf 'expected takeover to reject unrecognized config, but it succeeded:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
  exit 1
fi

TAKEOVER_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")

if [[ "${TAKEOVER_OUTPUT}" != *"检测到残缺的现有实例"* ]]; then
  printf 'expected incomplete-instance menu before unrecognized-config rejection, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
  exit 1
fi

if [[ "${TAKEOVER_OUTPUT}" != *"当前配置未识别到可接管的受支持协议"* ]]; then
  printf 'expected clear rejection for unrecognized config takeover, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
  exit 1
fi

if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
  printf 'expected rejected takeover to avoid rebuilding protocol index, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
  exit 1
fi
