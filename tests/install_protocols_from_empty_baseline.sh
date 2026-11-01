#!/usr/bin/env bash

set -euo pipefail
umask 077

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"

calls="${TMP_DIR}/calls"

reset_instance_fixture() {
  rm -rf -- "${SB_PROJECT_DIR}"
  mkdir -p "${SB_PROJECT_DIR}"
  rm -f -- "${SINGBOX_BIN_PATH}" "${SBV_BIN_PATH}" "${SINGBOX_SERVICE_FILE}"
  : > "${calls}"
}

write_empty_instance_fixture() {
  local index_mode=$1
  reset_instance_fixture
  mkdir -p "${SB_PROTOCOL_STATE_DIR}/instances"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SINGBOX_BIN_PATH}"
  chmod +x "${SINGBOX_BIN_PATH}"
  touch "${SINGBOX_SERVICE_FILE}"
  printf '%s\n' '{"inbounds":[],"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct"}}' \
    > "${SINGBOX_CONFIG_FILE}"
  if [[ "${index_mode}" == empty ]]; then
    printf '%s\n' 'PROTOCOL_STATE_VERSION=1' 'INSTALLED_PROTOCOLS=' > "${SB_PROTOCOL_INDEX_FILE}"
  fi
  structured_instance_store_empty_json hy2 | jq '.revision=5' \
    > "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
}

# An actual fresh installation, including a host retaining only sbv, must not
# assert that an existing instance was found before detection returns fresh.
for fresh_mode in fresh sbv-only; do
  reset_instance_fixture
  if [[ "${fresh_mode}" == sbv-only ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "${SBV_BIN_PATH}"
    chmod +x "${SBV_BIN_PATH}"
  fi
  (
    install_or_reconfigure_singbox() { printf 'fresh\n' >> "${calls}"; }
    install_protocols_interactive() { printf 'unexpected additional\n' >> "${calls}"; return 91; }
    prompt_incomplete_instance_action() { printf 'unexpected incomplete\n' >> "${calls}"; return 91; }
    install_new_protocols_menu > "${TMP_DIR}/fresh.output" 2> "${TMP_DIR}/fresh.stderr" </dev/null
    [[ "$(cat "${calls}")" == fresh ]]
    ! grep -Fq '现有实例' "${TMP_DIR}/fresh.output" "${TMP_DIR}/fresh.stderr"
  )
done

# Removing the final instance leaves its CAS revision. Both historical index
# shapes must allow cancellation before validation, detection or mutation.
for index_mode in missing empty; do
  write_empty_instance_fixture "${index_mode}"
  cp -a -- "${SB_PROJECT_DIR}" "${TMP_DIR}/before-${index_mode}"
  (
    detect_existing_instance_state() { printf 'unexpected detection\n' >> "${calls}"; return 91; }
    validate_config_file() { printf 'validate\n' >> "${calls}"; return "${validation_status:-0}"; }
    install_protocols_interactive() { printf 'install %s %s\n' "$1" "${2:-}" >> "${calls}"; }
    prompt_incomplete_instance_action() { printf 'unexpected incomplete\n' >> "${calls}"; return 91; }
    install_or_reconfigure_singbox() { printf 'unexpected fresh\n' >> "${calls}"; return 91; }

    install_new_protocols_menu > "${TMP_DIR}/cancel.output" 2> "${TMP_DIR}/cancel.stderr" <<<'0'
    [[ ! -s "${calls}" ]]
    grep -Fxq '当前已安装协议: 无' "${TMP_DIR}/cancel.output"
    grep -Fxq '3. Hysteria2' "${TMP_DIR}/cancel.output"
    ! grep -Fq '新增 Hysteria2 实例' "${TMP_DIR}/cancel.output"
    diff -ru -- "${TMP_DIR}/before-${index_mode}" "${SB_PROJECT_DIR}"

    install_new_protocols_menu > "${TMP_DIR}/selected.output" 2> "${TMP_DIR}/selected.stderr" <<<'3'
    [[ "$(cat "${calls}")" == $'validate\ninstall additional hy2' ]]
    diff -ru -- "${TMP_DIR}/before-${index_mode}" "${SB_PROJECT_DIR}"

    : > "${calls}"
    validation_status=7
    if install_new_protocols_menu > "${TMP_DIR}/invalid.output" 2> "${TMP_DIR}/invalid.stderr" <<<'3'; then
      printf 'expected invalid empty configuration to block installation\n' >&2
      exit 1
    else
      [[ $? == 7 ]]
    fi
    [[ "$(cat "${calls}")" == validate ]]
    diff -ru -- "${TMP_DIR}/before-${index_mode}" "${SB_PROJECT_DIR}"
  )
done

# Exercise the real loader and additional installer with empty inventory.
# Neither may reconstruct legacy state or read a nonexistent first inbound.
for index_mode in missing empty; do
  write_empty_instance_fixture "${index_mode}"
  (
    migrate_legacy_single_protocol_state_if_needed() { printf 'unexpected migration\n' >> "${calls}"; return 91; }
    list_installed_protocols() { printf 'unexpected reconciliation\n' >> "${calls}"; return 91; }
    rebuild_protocol_state_from_config() { printf 'unexpected rebuild\n' >> "${calls}"; return 91; }
    load_warp_route_settings() { warp_loaded=y; }
    load_stack_mode_state() { stack_loaded=y; }
    SB_PROTOCOL=hy2
    SB_PORT=443
    SB_ENABLE_WARP=y
    SB_ADVANCED_ROUTE=y
    warp_loaded=n
    stack_loaded=n
    load_current_config_state ''
    [[ -z "${SB_PROTOCOL}" && -z "${SB_PORT}" ]]
    [[ "${SB_ENABLE_WARP}" == n && "${SB_ADVANCED_ROUTE}" == n ]]
    [[ "${warp_loaded}" == y && "${stack_loaded}" == y ]]
    [[ ! -s "${calls}" ]]

    hy2_instance_management_menu() { printf 'hy2 %s\n' "$1" >> "${calls}"; }
    install_protocols_interactive additional hy2 </dev/null
    [[ "$(cat "${calls}")" == 'hy2 create' ]]
    jq -e '.revision==5 and .instances==[]' "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" >/dev/null
    [[ ! -e "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]
  )
done

# A malformed retained store must reach the existing fail-closed capture,
# never silently create a fresh revision-zero inventory in its place.
write_empty_instance_fixture empty
printf '%s\n' '{"malformed":true}' > "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json"
before_corrupt=$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}")
(
  migrate_legacy_single_protocol_state_if_needed() { printf 'unexpected migration\n' >> "${calls}"; return 91; }
  list_installed_protocols() { printf 'unexpected reconciliation\n' >> "${calls}"; return 91; }
  rebuild_protocol_state_from_config() { printf 'unexpected rebuild\n' >> "${calls}"; return 91; }
  load_warp_route_settings() { :; }
  load_stack_mode_state() { :; }
  apply_plain_proxy_instance_change() { printf 'unexpected mutation\n' >> "${calls}"; return 91; }
  if install_protocols_interactive additional hy2 > "${TMP_DIR}/corrupt.output" 2> "${TMP_DIR}/corrupt.stderr" </dev/null; then
    printf 'expected malformed retained store to block instance creation\n' >&2
    exit 1
  fi
  [[ ! -s "${calls}" ]]
  [[ "$(sha256sum "${SB_PROTOCOL_STATE_DIR}/instances/hy2.json" "${SINGBOX_CONFIG_FILE}" "${SB_PROTOCOL_INDEX_FILE}")" == "${before_corrupt}" ]]
  [[ ! -e "${SB_PROTOCOL_STATE_DIR}/hy2.env" ]]
)

printf 'empty installation menu checks passed: fresh/sbv-only missing/empty-index cancel validation loader retained-revision corrupt-store\n'
