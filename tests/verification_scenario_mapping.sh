#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/dev/verification/remote/scenarios/multi_protocol_coexistence.sh"
VERIFY_PROTOCOL_REGISTRY_JSON=$(source "${REPO_ROOT}/install.sh"; protocol_registry_json)
# Load the real metadata lookup without starting the remote entrypoint.
source <(awk '
  /^verification_protocol_metadata\(\)/ {printing=1}
  printing {print}
  /^}/ && printing {exit}
' "${REPO_ROOT}/dev/verification/remote/entrypoint.sh")

[[ $(verification_config_inbound_type_for_protocol vless-reality) == "vless" ]]
[[ $(verification_config_inbound_type_for_protocol mixed) == "mixed" ]]
[[ $(verification_config_inbound_type_for_protocol hy2) == "hysteria2" ]]
[[ $(verification_config_inbound_type_for_protocol anytls) == "anytls" ]]
[[ $(verification_config_inbound_type_for_protocol socks) == "socks" ]]
[[ $(verification_config_inbound_type_for_protocol http) == "http" ]]
[[ $(verification_config_inbound_type_for_protocol shadowsocks) == "shadowsocks" ]]
[[ $(verification_config_inbound_type_for_protocol trojan) == "trojan" ]]
[[ $(verification_config_inbound_type_for_protocol vmess) == "vmess" ]]
[[ $(verification_config_inbound_type_for_protocol vless-plain) == "vless" ]]
if verification_config_inbound_type_for_protocol unsupported >/dev/null; then
  printf 'expected unsupported protocol config type lookup to fail\n' >&2
  exit 1
fi

assert_scenarios() {
  local expected=$1
  shift
  local actual
  actual=$(printf '%s\n' "$(resolve_remote_scenarios "$@")" | paste -sd, -)
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'expected scenarios %s, got %s\n' "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_scenarios "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke" install.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke" configs/example.json
assert_scenarios "runtime_smoke" utils/common.sh
assert_scenarios "runtime_smoke,uninstall_and_reinstall" uninstall.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke,uninstall_and_reinstall" install.sh tests/uninstall_purge_removes_runtime_artifacts.sh
assert_scenarios "multi_protocol_coexistence,runtime_smoke" dev/verification/remote/scenarios/multi_protocol_coexistence.sh
assert_scenarios "upgrade_rollback_1_13_to_1_14,runtime_smoke" dev/verification/remote/scenarios/upgrade_rollback_1_13_to_1_14.sh
assert_scenarios "legacy_takeover_export,runtime_smoke,uninstall_and_reinstall" dev/verification/remote/scenarios/legacy_takeover_export.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke,uninstall_and_reinstall" dev/verification/common.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke,uninstall_and_reinstall" dev/verification/remote/entrypoint.sh
assert_scenarios "fresh_install_vless,reconfigure_existing_install,legacy_takeover_export,fresh_install_anytls,fresh_install_socks,fresh_install_http,fresh_install_shadowsocks,fresh_install_trojan,fresh_install_vmess,fresh_install_vless_plain,multi_protocol_coexistence,upgrade_1_13_to_1_14,upgrade_rollback_1_13_to_1_14,runtime_smoke" install.sh dev/verification/remote/scenarios/multi_protocol_coexistence.sh
assert_scenarios "fresh_install_socks,runtime_smoke" dev/verification/remote/scenarios/fresh_install_socks.sh
assert_scenarios "fresh_install_http,runtime_smoke" dev/verification/remote/scenarios/fresh_install_http.sh
assert_scenarios "fresh_install_shadowsocks,runtime_smoke" dev/verification/remote/scenarios/fresh_install_shadowsocks.sh
assert_scenarios "fresh_install_trojan,runtime_smoke" dev/verification/remote/scenarios/fresh_install_trojan.sh
assert_scenarios "fresh_install_vmess,runtime_smoke" dev/verification/remote/scenarios/fresh_install_vmess.sh
assert_scenarios "fresh_install_vless_plain,runtime_smoke" dev/verification/remote/scenarios/fresh_install_vless_plain.sh

date() {
  if [[ "${1:-}" == "+%s" ]]; then
    printf '1710000000\n'
    return 0
  fi

  command date "$@"
}

RESULT_ROOT="${TMP_DIR}/verification-runs"
first_run_dir=$(create_run_dir "${RESULT_ROOT}")
second_run_dir=$(create_run_dir "${RESULT_ROOT}")

[[ "${first_run_dir}" != "${second_run_dir}" ]] || {
  printf 'expected unique run dirs, got %s twice\n' "${first_run_dir}" >&2
  exit 1
}

case "${first_run_dir}" in
  "${RESULT_ROOT}"/20????????????) ;;
  *)
    printf 'unexpected first run dir: %s\n' "${first_run_dir}" >&2
    exit 1
    ;;
esac

case "${second_run_dir}" in
  "${RESULT_ROOT}"/20????????????) ;;
  *)
    printf 'unexpected second run dir: %s\n' "${second_run_dir}" >&2
    exit 1
    ;;
esac

[[ -d "${first_run_dir}" ]] || {
  printf 'expected first run dir to exist: %s\n' "${first_run_dir}" >&2
  exit 1
}

[[ -d "${second_run_dir}" ]] || {
  printf 'expected second run dir to exist: %s\n' "${second_run_dir}" >&2
  exit 1
}
