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
  printf 'install_binary\n' >> "${TMP_DIR}/repair-call-order"
  write_invalid_check_binary "${SB_VERSION:-1.13.5}"
}

setup_service() {
  SETUP_SERVICE_CALLS=$((SETUP_SERVICE_CALLS + 1))
  printf '%s\n' "${SETUP_SERVICE_CALLS}" > "${TMP_DIR}/setup-service-calls"
  cat > "${SINGBOX_SERVICE_FILE}" <<'EOF'
[Unit]
Description=sing-box
EOF
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

write_invalid_check_binary() {
  local version=${1:-1.13.5}

  mkdir -p "$(dirname "${SINGBOX_BIN_PATH}")"

  cat > "${SINGBOX_BIN_PATH}" <<EOF
#!/usr/bin/env bash

case "\${1:-}" in
  version)
    printf 'sing-box version %s\n' '${version}'
    exit 0
    ;;
  check)
    exit 1
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

write_sbv_binary() {
  mkdir -p "$(dirname "${SBV_BIN_PATH}")"

  cat > "${SBV_BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${SBV_BIN_PATH}"
}

write_invalid_config() {
  mkdir -p "${SB_PROJECT_DIR}"

  cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "vless",
      "listen_port": 443,
      "users": []
    }
  ],
  "route": {
    "rules": []
  }
}
EOF
}

run_takeover_expecting_invalid_config_failure() {
  set +e
  TAKEOVER_OUTPUT=$(printf '1\n' | install_or_update_singbox 2>&1)
  local status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    printf 'expected takeover to reject invalid config, but it succeeded:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  TAKEOVER_OUTPUT=$(strip_ansi "${TAKEOVER_OUTPUT}")

  if [[ "${TAKEOVER_OUTPUT}" != *"检测到残缺的现有实例"* ]]; then
    printf 'expected incomplete-instance menu before invalid-config rejection, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi

  if [[ "${TAKEOVER_OUTPUT}" != *"配置文件校验失败，请检查配置细节。"* ]]; then
    printf 'expected invalid-config rejection message during takeover, got:\n%s\n' "${TAKEOVER_OUTPUT}" >&2
    exit 1
  fi
}

assert_takeover_stops_before_rebuild() {
  if [[ -f "${SB_PROTOCOL_INDEX_FILE}" ]]; then
    printf 'expected invalid takeover to stop before rebuilding protocol index, got:\n%s\n' "$(cat "${SB_PROTOCOL_INDEX_FILE}")" >&2
    exit 1
  fi

  if [[ -d "${SB_PROTOCOL_STATE_DIR}" ]]; then
    printf 'expected invalid takeover to stop before creating protocol state directory\n' >&2
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

reset_takeover_artifacts() {
  rm -f \
    "${SINGBOX_BIN_PATH}" \
    "${SINGBOX_SERVICE_FILE}" \
    "${SBV_BIN_PATH}" \
    "${SINGBOX_CONFIG_FILE}" \
    "${SB_PROTOCOL_INDEX_FILE}" \
    "${TMP_DIR}/install-binary-calls" \
    "${TMP_DIR}/install-dependencies-calls" \
    "${TMP_DIR}/setup-service-calls" \
    "${TMP_DIR}/ensure-sbv-calls" \
    "${TMP_DIR}/repair-call-order"
  rm -rf "${SB_PROTOCOL_STATE_DIR}"
  TAKEOVER_OUTPUT=""
}

assert_sbv_not_repaired() {
  if [[ -x "${SBV_BIN_PATH}" ]]; then
    printf 'expected invalid takeover to stop before restoring sbv command\n' >&2
    exit 1
  fi
}

scenario_invalid_config_missing_binary_aborts_before_rebuild_and_runtime_repair() {
  reset_takeover_artifacts
  write_service_file
  write_sbv_binary
  write_invalid_config

  run_takeover_expecting_invalid_config_failure
  assert_takeover_stops_before_rebuild

  if [[ ! -x "${SINGBOX_BIN_PATH}" ]]; then
    printf 'expected missing-binary invalid-config scenario to exercise validation binary repair path\n' >&2
    exit 1
  fi

  if [[ ! -f "${SINGBOX_SERVICE_FILE}" ]]; then
    printf 'expected missing-binary invalid-config scenario to leave existing service file untouched\n' >&2
    exit 1
  fi

  if [[ ! -x "${SBV_BIN_PATH}" ]]; then
    printf 'expected missing-binary invalid-config scenario to leave existing sbv command untouched\n' >&2
    exit 1
  fi

  assert_counter_equals "${TMP_DIR}/install-dependencies-calls" "1" "missing-binary-invalid-config"
  assert_counter_equals "${TMP_DIR}/install-binary-calls" "1" "missing-binary-invalid-config"
  assert_counter_equals "${TMP_DIR}/setup-service-calls" "" "missing-binary-invalid-config"
  assert_counter_equals "${TMP_DIR}/ensure-sbv-calls" "" "missing-binary-invalid-config"
  assert_repair_call_order $'install_dependencies\ninstall_binary' "missing-binary-invalid-config"
}

scenario_invalid_config_missing_service_remains_unrepaired() {
  reset_takeover_artifacts
  write_invalid_check_binary
  write_sbv_binary
  write_invalid_config

  run_takeover_expecting_invalid_config_failure
  assert_takeover_stops_before_rebuild

  if [[ -f "${SINGBOX_SERVICE_FILE}" ]]; then
    printf 'expected missing-service invalid-config scenario to leave service absent when validation fails\n' >&2
    exit 1
  fi

  assert_counter_equals "${TMP_DIR}/install-dependencies-calls" "" "missing-service-invalid-config"
  assert_counter_equals "${TMP_DIR}/install-binary-calls" "" "missing-service-invalid-config"
  assert_counter_equals "${TMP_DIR}/setup-service-calls" "" "missing-service-invalid-config"
  assert_counter_equals "${TMP_DIR}/ensure-sbv-calls" "" "missing-service-invalid-config"
  assert_repair_call_order "" "missing-service-invalid-config"
}

scenario_invalid_config_missing_binary_aborts_before_rebuild_and_runtime_repair
scenario_invalid_config_missing_service_remains_unrepaired
