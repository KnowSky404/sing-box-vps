#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

INSTALL_BINARY_CALLS=0
INSTALL_DEPENDENCIES_CALLS=0
SETUP_SERVICE_CALLS=0
ENSURE_SBV_CALLS=0
RESTART_SERVICE_CALLS=0
TAKEOVER_OUTPUT=""

get_os_info() {
  OS_NAME="debian"
  OS_VERSION="12"
}

get_arch() {
  ARCH="amd64"
}

install_dependencies() {
  INSTALL_DEPENDENCIES_CALLS=$((INSTALL_DEPENDENCIES_CALLS + 1))
  printf '%s\n' "${INSTALL_DEPENDENCIES_CALLS}" > "${TMP_DIR}/install-dependencies-calls"
  printf 'install_dependencies\n' >> "${TMP_DIR}/repair-call-order"
}

install_binary() {
  INSTALL_BINARY_CALLS=$((INSTALL_BINARY_CALLS + 1))
  printf '%s\n' "${INSTALL_BINARY_CALLS}" > "${TMP_DIR}/install-binary-calls"
  printf '%s\n' "${SB_VERSION}" > "${TMP_DIR}/last-install-binary-version"
  printf 'install_binary\n' >> "${TMP_DIR}/repair-call-order"
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"
  cat > "${SINGBOX_BIN_PATH}" <<EOF
#!/usr/bin/env bash

if [[ "${1:-}" == "version" ]]; then
  printf 'sing-box version %s\n' '${SB_VERSION}'
  exit 0
fi

exit 0
EOF
  chmod +x "${SINGBOX_BIN_PATH}"
}

ensure_sbv_command_installed() {
  ENSURE_SBV_CALLS=$((ENSURE_SBV_CALLS + 1))
  printf '%s\n' "${ENSURE_SBV_CALLS}" > "${TMP_DIR}/ensure-sbv-calls"
  mkdir -p "$(dirname "${SBV_BIN_PATH}")"
  cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SBV_BIN_PATH}"
}

setup_service() {
  SETUP_SERVICE_CALLS=$((SETUP_SERVICE_CALLS + 1))
  printf '%s\n' "${SETUP_SERVICE_CALLS}" > "${TMP_DIR}/setup-service-calls"
  cat > "${SINGBOX_SERVICE_FILE}" <<EOF
[Unit]
Description=sing-box service
[Service]
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
EOF
}

restart_service_after_takeover() {
  RESTART_SERVICE_CALLS=$((RESTART_SERVICE_CALLS + 1))
  printf '%s\n' "${RESTART_SERVICE_CALLS}" > "${TMP_DIR}/restart-service-calls"
}

write_singbox_binary() {
  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"
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

write_service_file() {
  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box service
EOF
}

write_sbv_binary() {
  mkdir -p "$(dirname "${SBV_BIN_PATH}")"
  cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SBV_BIN_PATH}"
}

write_config() {
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

write_protocol_state() {
  local recorded_version=${1:-}
  mkdir -p "${SB_PROTOCOL_STATE_DIR}"
  cat > "${SB_PROTOCOL_INDEX_FILE}" <<EOF
INSTALLED_PROTOCOLS=vless-reality
PROTOCOL_STATE_VERSION=1
EOF

  if [[ -n "${recorded_version}" ]]; then
    printf 'INSTALLED_SINGBOX_VERSION=%s\n' "${recorded_version}" >> "${SB_PROTOCOL_INDEX_FILE}"
  fi

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
  rm -f "${SINGBOX_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" "${SBV_BIN_PATH}" "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}"
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
}

reset_runtime_stub_counters() {
  INSTALL_BINARY_CALLS=0
  INSTALL_DEPENDENCIES_CALLS=0
  SETUP_SERVICE_CALLS=0
  ENSURE_SBV_CALLS=0
  TAKEOVER_OUTPUT=""
  rm -f \
    "${TMP_DIR}/last-install-binary-version" \
    "${TMP_DIR}/install-binary-calls" \
    "${TMP_DIR}/install-dependencies-calls" \
    "${TMP_DIR}/ensure-sbv-calls" \
    "${TMP_DIR}/repair-call-order" \
    "${TMP_DIR}/restart-service-calls" \
    "${TMP_DIR}/setup-service-calls"
  RESTART_SERVICE_CALLS=0
}

run_takeover_from_incomplete_menu() {
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

assert_runtime_artifacts_restored() {
  local scenario=$1

  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    printf 'expected takeover to restore sing-box binary for scenario %s\n' "${scenario}" >&2
    exit 1
  fi

  if [[ ! -f "${SINGBOX_SERVICE_FILE}" ]]; then
    printf 'expected takeover to restore service file for scenario %s\n' "${scenario}" >&2
    exit 1
  fi

  if [[ ! -x "${SBV_BIN_PATH}" ]]; then
    printf 'expected takeover to restore sbv command for scenario %s\n' "${scenario}" >&2
    exit 1
  fi
}

assert_runtime_artifacts_not_restored() {
  local scenario=$1

  if [[ -e "${SINGBOX_BIN_PATH}" ]]; then
    printf 'expected takeover to leave sing-box binary absent for scenario %s\n' "${scenario}" >&2
    exit 1
  fi

  if [[ -e "${SINGBOX_SERVICE_FILE}" ]]; then
    printf 'expected takeover to leave service file absent for scenario %s\n' "${scenario}" >&2
    exit 1
  fi

  if [[ -e "${SBV_BIN_PATH}" ]]; then
    printf 'expected takeover to leave sbv command absent for scenario %s\n' "${scenario}" >&2
    exit 1
  fi
}

assert_binary_restored_with_version() {
  local expected_version=$1
  local scenario=$2
  local actual_version=""

  if [[ -f "${TMP_DIR}/last-install-binary-version" ]]; then
    actual_version=$(cat "${TMP_DIR}/last-install-binary-version")
  fi

  if [[ "${actual_version}" != "${expected_version}" ]]; then
    printf 'expected takeover to restore sing-box %s for scenario %s, got %s\n' \
      "${expected_version}" \
      "${scenario}" \
      "${actual_version}" >&2
    exit 1
  fi
}

assert_output_contains() {
  local expected_text=$1
  local scenario=$2

  if [[ "${TAKEOVER_OUTPUT}" != *"${expected_text}"* ]]; then
    printf 'expected takeover output to contain %s for scenario %s, got:\n%s\n' \
      "${expected_text}" \
      "${scenario}" \
      "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi
}

assert_counter_equals() {
  local counter_file=$1
  local expected_value=$2
  local scenario=$3
  local actual_value=""

  if [[ -f "${counter_file}" ]]; then
    actual_value=$(cat "${counter_file}")
  fi

  if [[ "${actual_value}" != "${expected_value}" ]]; then
    printf 'expected %s=%s for scenario %s, got %s\n' \
      "${counter_file}" \
      "${expected_value}" \
      "${scenario}" \
      "${actual_value}" >&2
    exit 1
  fi
}

assert_repair_call_order() {
  local expected_order=$1
  local scenario=$2
  local actual_order=""

  if [[ -f "${TMP_DIR}/repair-call-order" ]]; then
    actual_order=$(cat "${TMP_DIR}/repair-call-order")
  fi

  if [[ "${actual_order}" != "${expected_order}" ]]; then
    printf 'expected repair call order for scenario %s to be:\n%s\ngot:\n%s\n' \
      "${scenario}" \
      "${expected_order}" \
      "${actual_order}" >&2
    exit 1
  fi
}

scenario_missing_binary_uses_recorded_version() {
  reset_instance_artifacts
  reset_runtime_stub_counters
  write_config
  write_service_file
  write_sbv_binary
  write_protocol_state "1.13.5"

  run_takeover_from_incomplete_menu
  assert_runtime_artifacts_restored "missing-binary-recorded-version"
  assert_binary_restored_with_version "1.13.5" "missing-binary-recorded-version"
  assert_counter_equals "${TMP_DIR}/install-dependencies-calls" "1" "missing-binary-recorded-version"
  assert_counter_equals "${TMP_DIR}/restart-service-calls" "1" "missing-binary-recorded-version"
  assert_repair_call_order $'install_dependencies\ninstall_binary' "missing-binary-recorded-version"
}

scenario_missing_binary_without_recorded_version_warns() {
  reset_instance_artifacts
  reset_runtime_stub_counters
  write_config
  write_service_file
  write_sbv_binary
  write_protocol_state

  run_takeover_from_incomplete_menu
  assert_runtime_artifacts_restored "missing-binary-without-record"
  assert_binary_restored_with_version "${SB_SUPPORT_MAX_VERSION}" "missing-binary-without-record"
  assert_output_contains "未找到本地记录的 sing-box 版本" "missing-binary-without-record"
  assert_counter_equals "${TMP_DIR}/install-dependencies-calls" "1" "missing-binary-without-record"
  assert_counter_equals "${TMP_DIR}/restart-service-calls" "1" "missing-binary-without-record"
  assert_repair_call_order $'install_dependencies\ninstall_binary' "missing-binary-without-record"
}

scenario_missing_service_and_sbv_restores_sbv_explicitly() {
  reset_instance_artifacts
  reset_runtime_stub_counters
  write_config
  write_singbox_binary
  write_protocol_state "1.13.5"

  run_takeover_from_incomplete_menu
  assert_runtime_artifacts_restored "missing-service-and-sbv"
  assert_counter_equals "${TMP_DIR}/setup-service-calls" "1" "missing-service-and-sbv"
  assert_counter_equals "${TMP_DIR}/ensure-sbv-calls" "1" "missing-service-and-sbv"
  assert_counter_equals "${TMP_DIR}/restart-service-calls" "1" "missing-service-and-sbv"
}

scenario_invalid_existing_service_is_repaired() {
  reset_instance_artifacts
  reset_runtime_stub_counters
  write_config
  write_singbox_binary
  write_service_file
  write_sbv_binary

  run_takeover_from_incomplete_menu
  assert_runtime_artifacts_restored "invalid-existing-service"
  assert_counter_equals "${TMP_DIR}/setup-service-calls" "1" "invalid-existing-service"
  assert_counter_equals "${TMP_DIR}/restart-service-calls" "1" "invalid-existing-service"

  if ! grep -Fqx "ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}" "${SINGBOX_SERVICE_FILE}"; then
    printf 'expected takeover to rewrite invalid service file, got:\n%s\n' "$(cat "${SINGBOX_SERVICE_FILE}")" >&2
    exit 1
  fi
}

scenario_missing_only_sbv_stays_on_healthy_menu() {
  reset_instance_artifacts
  reset_runtime_stub_counters
  write_config
  write_singbox_binary
  write_service_file
  write_protocol_state "1.13.5"

  if ! TAKEOVER_OUTPUT=$(printf '0\n' | install_or_update_singbox 2>&1); then
    printf 'expected healthy-instance flow without sbv to succeed, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  TAKEOVER_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")

  if [[ "${TAKEOVER_OUTPUT}" == *"检测到残缺的现有实例"* ]]; then
    printf 'expected installed instance missing only sbv to avoid incomplete-instance menu, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  if [[ "${TAKEOVER_OUTPUT}" != *"更新 sing-box 二进制并保留当前配置"* ]]; then
    printf 'expected installed instance missing only sbv to land on healthy-instance menu, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  assert_counter_equals "${TMP_DIR}/install-binary-calls" "" "missing-only-sbv"
  assert_counter_equals "${TMP_DIR}/setup-service-calls" "" "missing-only-sbv"
  assert_counter_equals "${TMP_DIR}/ensure-sbv-calls" "" "missing-only-sbv"
}

scenario_missing_config_stops_before_runtime_repair() {
  reset_instance_artifacts
  reset_runtime_stub_counters
  write_protocol_state "1.13.5"

  if TAKEOVER_OUTPUT=$(printf '1\n' | install_or_update_singbox 2>&1); then
    printf 'expected takeover flow without config.json to fail clearly, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  TAKEOVER_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")

  if [[ "${TAKEOVER_OUTPUT}" != *"检测到残缺的现有实例"* ]]; then
    printf 'expected incomplete-instance menu before config-less takeover failure, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  if [[ "${TAKEOVER_OUTPUT}" != *"未找到配置文件，无法接管现有实例"* ]]; then
    printf 'expected clear config-less takeover failure message, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  assert_runtime_artifacts_not_restored "missing-config"
  assert_counter_equals "${TMP_DIR}/install-dependencies-calls" "" "missing-config"
  assert_counter_equals "${TMP_DIR}/install-binary-calls" "" "missing-config"
  assert_counter_equals "${TMP_DIR}/setup-service-calls" "" "missing-config"
  assert_counter_equals "${TMP_DIR}/ensure-sbv-calls" "" "missing-config"
  assert_repair_call_order "" "missing-config"
}

scenario_missing_binary_uses_recorded_version
scenario_missing_binary_without_recorded_version_warns
scenario_missing_service_and_sbv_restores_sbv_explicitly
scenario_invalid_existing_service_is_repaired
scenario_missing_only_sbv_stays_on_healthy_menu
scenario_missing_config_stops_before_runtime_repair
