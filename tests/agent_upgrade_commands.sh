#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120

perl -0pi -e 's|/root/sing-box-vps-backups|'"${TMP_DIR}"'/sing-box-vps-backups|g' "${TESTABLE_INSTALL}"
source_testable_install

CURRENT_CHECK_FAIL_FILE="${TMP_DIR}/current-check-fails"
TARGET_CHECK_FAIL_FILE="${TMP_DIR}/target-check-fails"
SERVICE_RESTART_FAIL_FILE="${TMP_DIR}/service-restart-fails"
SYSTEMCTL_CALLS_FILE="${TMP_DIR}/systemctl.calls"
: > "${SYSTEMCTL_CALLS_FILE}"
export CURRENT_CHECK_FAIL_FILE SYSTEMCTL_CALLS_FILE

write_singbox_stub() {
  local version=$1
  local target_check_fails=${2:-n}

  cat > "${SINGBOX_BIN_PATH}" <<EOF_SINGBOX
#!/usr/bin/env bash
case "\${1:-}" in
  version)
    printf 'sing-box version ${version}\\n'
    ;;
  check)
    if [[ -f "${CURRENT_CHECK_FAIL_FILE}" ]]; then
      printf 'invalid current config\\n' >&2
      exit 23
    fi
    if [[ "${target_check_fails}" == "y" ]]; then
      printf 'target rejected config\\n' >&2
      exit 24
    fi
    printf 'config ok\\n'
    ;;
  *)
    exit 0
    ;;
esac
EOF_SINGBOX
  chmod +x "${SINGBOX_BIN_PATH}"
}

cat > "${TMP_DIR}/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SYSTEMCTL_CALLS_FILE}"
case "${1:-} ${2:-}" in
  "is-active sing-box") printf 'active\n' ;;
  "is-enabled sing-box") printf 'enabled\n' ;;
  "restart sing-box") printf 'restarted\n' ;;
  *) exit 0 ;;
esac
EOF_SYSTEMCTL
chmod +x "${TMP_DIR}/bin/systemctl"

mkdir -p "${SB_PROTOCOL_STATE_DIR}"
printf 'INSTALLED_PROTOCOLS=hy2\nPROTOCOL_STATE_VERSION=1\n' > "${SB_PROTOCOL_INDEX_FILE}"
cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF_STATE'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2_test-host
PORT=443
DOMAIN=hy2.example.com
PASSWORD=hy2-password
USER_NAME=hy2-user
UP_MBPS=
DOWN_MBPS=
TLS_MODE=acme
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=hy2.example.com
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=
KEY_PATH=
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
MASQUERADE=
EOF_STATE
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF_CONFIG'
{
  "inbounds": [
    {
      "type": "hysteria2",
      "listen_port": 443,
      "users": [{"name": "hy2-user", "password": "hy2-password"}],
      "tls": {
        "server_name": "hy2.example.com",
        "acme": {"domain": ["hy2.example.com"]}
      }
    }
  ],
  "route": {
    "rule_set": [{"type": "remote", "download_detour": "direct"}]
  }
}
EOF_CONFIG
cat > "${SINGBOX_SERVICE_FILE}" <<EOF_SERVICE
[Service]
ExecStart=${SINGBOX_BIN_PATH} run -c ${SINGBOX_CONFIG_FILE}
EOF_SERVICE
write_singbox_stub "1.13.18"

protocol_state_tree_hash() {
  find "${SB_PROTOCOL_STATE_DIR}" -type f -exec sha256sum {} \; | sort | sha256sum | awk '{print $1}'
}

capabilities_json=$(agent_cli capabilities --json)
jq -e '
  .ok == true
  and .schema
  and (.commands | type == "object")
  and (.interactive_features | type == "object")
  and (.protocols | keys | sort == ["anytls", "hysteria2", "mixed", "vless-reality"])
  and .multi_protocol_coexistence == true
  and .protocols["vless-reality"].multi_instance == true
  and .features.network_stack.inbound == ["ipv4_only", "ipv6_only", "dual_stack"]
  and .features.subman.supported_protocols == ["vless-reality", "hysteria2"]
  and (.commands["upgrade-check"].mutation == false)
  and (.commands.upgrade.mutation == true)
  and (.commands.links.sensitive == true)
  and (.commands.nodes.sensitive == false)
  and (.commands["export-client"].mutation == true)
  and (.commands["subman-sync"].sensitive == true)
  and .upgrade.manifest_scope == "all_regular_runtime_files_and_control_files"
  and .upgrade.restores_previous_service_activity == true
' <<< "${capabilities_json}" >/dev/null

state_hash_before=$(protocol_state_tree_hash)
state_files_before=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -printf '%P\n' | sort)
check_json=$(agent_cli upgrade-check --json 1.14.0)
state_hash_after=$(protocol_state_tree_hash)
state_files_after=$(find "${SB_PROTOCOL_STATE_DIR}" -type f -printf '%P\n' | sort)
[[ "${state_hash_after}" == "${state_hash_before}" ]]
[[ "${state_files_after}" == "${state_files_before}" ]]
jq -e '
  .schema == "1"
  and .schema_version == "1.0"
  and .command == "upgrade-check"
  and .ok == true
  and (.data | type == "object")
  and .ready == true
  and .blockers == []
  and .current == "1.13.18"
  and .target == "1.14.0"
  and .service.active_state == "active"
  and .managed_instance_state == "healthy"
  and .current_check.ok == true
  and (.config.sha256 | length == 64)
  and .config.schema.classification == "legacy_1_13"
  and .legacy.tls_acme_count == 1
  and .legacy.download_detour_count == 1
  and any(.warnings[]; .code == "inline_acme_deprecated")
  and any(.warnings[]; .code == "download_detour_deprecated")
  and .target_binary_validation.performed == false
  and .apply == false
' <<< "${check_json}" >/dev/null

if upgrade_json=$(agent_cli upgrade --json 1.14.0 2>/dev/null); then
  printf 'upgrade without --yes should fail\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "confirmation_required"' <<< "${upgrade_json}" >/dev/null

if upgrade_json=$(agent_cli upgrade --json 9.9.9 --yes 2>/dev/null); then
  printf 'unsupported upgrade target should fail\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "unsupported_version"' <<< "${upgrade_json}" >/dev/null

update_singbox_binary_preserving_config() {
  if [[ -f "${TARGET_CHECK_FAIL_FILE}" ]]; then
    write_singbox_stub "${SB_VERSION}" "y"
    printf '现有配置未通过 sing-box %s 校验。\n' "${SB_VERSION}"
    return 1
  fi

  if [[ -f "${SERVICE_RESTART_FAIL_FILE}" ]]; then
    write_singbox_stub "1.13.18"
    printf 'sing-box 服务重启失败或未保持 active。\n'
    printf '已恢复更新前的 sing-box 二进制及服务状态。\n'
    return 1
  fi

  write_singbox_stub "${SB_VERSION}"
  systemctl restart sing-box >/dev/null
}

original_transaction_result_function=$(declare -f write_agent_upgrade_transaction_result)
write_agent_upgrade_transaction_result() {
  return 1
}
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'backup-ready transaction record failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "transaction_record_failed"
  and (.backup | length > 0)
  and (.transaction.id | length > 0)
  and .transaction.status == "backup_ready"
  and .transaction.result_persisted == false
  and .transaction.rollback.attempted == false
' <<< "${upgrade_json}" >/dev/null
eval "${original_transaction_result_function}"

original_upgrade_check_function=$(declare -f agent_upgrade_check_json)
agent_upgrade_check_json() {
  printf '%s\n' "${check_json}"
}
mktemp() {
  if [[ $# -eq 0 ]]; then
    return 73
  fi
  command mktemp "$@"
}
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'operation-log allocation failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "temporary_log_failed"
  and .failure_reason == "temporary_log_failed"
  and .transaction.status == "failed"
  and .transaction.result_persisted == true
' <<< "${upgrade_json}" >/dev/null
operation_log_result_file=$(jq -r '.transaction.result_path' <<< "${upgrade_json}")
jq -e '
  .status == "failed"
  and .failure_reason == "temporary_log_failed"
  and .operation_exit_code == null
  and ([.status_history[].status] | . == ["backup_ready", "failed"])
' "${operation_log_result_file}" >/dev/null
unset -f mktemp

eval "$(printf '%s\n' "${original_transaction_result_function}" | sed '1s/^write_agent_upgrade_transaction_result /write_agent_upgrade_transaction_result_real /')"
write_agent_upgrade_transaction_result() {
  if [[ "${2:-}" == "failed" ]]; then
    return 75
  fi
  write_agent_upgrade_transaction_result_real "$@"
}
mktemp() {
  if [[ $# -eq 0 ]]; then
    return 73
  fi
  command mktemp "$@"
}
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'operation-log and terminal record failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "transaction_record_failed"
  and .failure_reason == "temporary_log_failed"
  and .transaction.status == "failed"
  and .transaction.result_persisted == false
' <<< "${upgrade_json}" >/dev/null
unset -f mktemp write_agent_upgrade_transaction_result_real
eval "${original_transaction_result_function}"
eval "${original_upgrade_check_function}"

original_hash=$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")
touch "${TARGET_CHECK_FAIL_FILE}"
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'target config-check failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "config_check_failed"
  and .rolled_back == true
  and .rollback_ok == true
  and .installed == "1.13.18"
  and .config_preserved == true
  and (.backup | length > 0)
' <<< "${upgrade_json}" >/dev/null
[[ "$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")" == "${original_hash}" ]]
rollback_backup_dir=$(jq -r '.backup' <<< "${upgrade_json}")
rollback_result_file=$(jq -r '.transaction.result_path' <<< "${upgrade_json}")
jq -e '
  .transaction.id
  and .transaction.status == "rolled_back"
  and .transaction.rollback.attempted == true
  and .transaction.rollback.result == "success"
' <<< "${upgrade_json}" >/dev/null
[[ -f "${rollback_result_file}" ]]
jq -e '
  .schema_version == "1.0"
  and (.transaction_id | length > 0)
  and .old_version == "1.13.18"
  and .new_version == "1.14.0"
  and .status == "rolled_back"
  and .rollback.attempted == true
  and .rollback.result == "success"
  and .failure_reason == "config_check_failed"
  and .operation_exit_code == 1
  and ([.status_history[].status] | . == ["backup_ready", "rolled_back"])
  and (.manifest.path | endswith("/SHA256SUMS"))
  and (.manifest.sha256 | length == 64)
' "${rollback_result_file}" >/dev/null
[[ "$(stat -c '%a' "${rollback_result_file}")" == "600" ]]
(cd "${rollback_backup_dir}" && sha256sum -c SHA256SUMS >/dev/null)
rm -f "${TARGET_CHECK_FAIL_FILE}"

touch "${SERVICE_RESTART_FAIL_FILE}"
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'service restart failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "service_not_active"
  and .failure_reason == "service_not_active"
  and .rolled_back == true
  and .rollback_ok == true
  and .installed == "1.13.18"
  and .service.after == "active"
  and .operation_exit_code == 1
  and (.operation_log | contains("服务重启失败或未保持 active"))
' <<< "${upgrade_json}" >/dev/null
rollback_result_file=$(jq -r '.transaction.result_path' <<< "${upgrade_json}")
jq -e '
  .status == "rolled_back"
  and .rollback.result == "success"
  and .failure_reason == "service_not_active"
  and .operation_exit_code == 1
' "${rollback_result_file}" >/dev/null
rm -f "${SERVICE_RESTART_FAIL_FILE}"

original_restore_function=$(declare -f restore_agent_upgrade_backup)
restore_agent_upgrade_backup() {
  return 1
}
touch "${TARGET_CHECK_FAIL_FILE}"
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'rollback failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "rollback_failed"
  and .reason == "rollback_failed"
  and .failure_reason == "config_check_failed"
  and .changed == true
  and .rollback_attempted == true
  and .rolled_back == false
  and .rollback_ok == false
  and .manual_intervention_required == true
  and .installed == "1.14.0"
' <<< "${upgrade_json}" >/dev/null
rollback_result_file=$(jq -r '.transaction.result_path' <<< "${upgrade_json}")
jq -e '
  .transaction.status == "rollback_failed"
  and .transaction.rollback.attempted == true
  and .transaction.rollback.result == "failed"
' <<< "${upgrade_json}" >/dev/null
jq -e '.status == "rollback_failed" and .rollback.result == "failed"' "${rollback_result_file}" >/dev/null
[[ "$(jq -r '[.status_history[].status] | join(",")' "${rollback_result_file}")" == "backup_ready,rollback_failed" ]]
[[ "$(stat -c '%a' "${rollback_result_file}")" == "600" ]]
eval "${original_restore_function}"
rm -f "${TARGET_CHECK_FAIL_FILE}"
write_singbox_stub "1.13.18"

eval "$(printf '%s\n' "${original_transaction_result_function}" | sed '1s/^write_agent_upgrade_transaction_result /write_agent_upgrade_transaction_result_real /')"
write_agent_upgrade_transaction_result() {
  if [[ "${2:-}" == "success" ]]; then
    return 75
  fi
  write_agent_upgrade_transaction_result_real "$@"
}
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'terminal transaction record failure should return non-zero\n' >&2
  exit 1
fi
jq -e '
  .ok == false
  and .error == "transaction_record_failed"
  and (.backup | length > 0)
  and .transaction.status == "success"
  and .transaction.result_persisted == false
  and .installed == "1.14.0"
  and .config_preserved == true
' <<< "${upgrade_json}" >/dev/null
failed_terminal_result_file=$(jq -r '.transaction.result_path' <<< "${upgrade_json}")
jq -e '.status == "backup_ready" and ([.status_history[].status] | . == ["backup_ready"])' "${failed_terminal_result_file}" >/dev/null
unset -f write_agent_upgrade_transaction_result_real
eval "${original_transaction_result_function}"
write_singbox_stub "1.13.18"

upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes)
jq -e '
  .schema == "1"
  and .schema_version == "1.0"
  and .command == "upgrade"
  and .ok == true
  and (.data | type == "object")
  and .changed == true
  and .restarted == true
  and .rolled_back == false
  and .installed == "1.14.0"
  and .config_preserved == true
  and (.backup | length > 0)
  and (.transaction.id | length > 0)
  and (.transaction.result_path | endswith("/transaction-result.json"))
  and .transaction.status == "success"
  and .transaction.rollback.attempted == false
  and .transaction.rollback.result == "not_attempted"
  and .check.ok == true
' <<< "${upgrade_json}" >/dev/null
[[ "$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")" == "${original_hash}" ]]
backup_dir=$(jq -r '.backup' <<< "${upgrade_json}")
[[ -f "${backup_dir}/runtime/config.json" ]]
[[ -f "${backup_dir}/sing-box" ]]
[[ -f "${backup_dir}/sing-box.service" ]]
[[ -f "${backup_dir}/SHA256SUMS" ]]
[[ -f "${backup_dir}/metadata.json" ]]
[[ -f "${backup_dir}/transaction-result.json" ]]
jq -e '
  (.transaction_id | length > 0)
  and .old_version == "1.13.18"
  and .new_version == "1.14.0"
  and (.manifest_path | endswith("/SHA256SUMS"))
' "${backup_dir}/metadata.json" >/dev/null
jq -e '
  .schema_version == "1.0"
  and .status == "success"
  and .rollback.attempted == false
  and .rollback.result == "not_attempted"
  and ([.status_history[].status] | . == ["backup_ready", "success"])
  and (.manifest_path | endswith("/SHA256SUMS"))
  and (.manifest_sha256 | length == 64)
  and (.completed_at | type == "string")
  and (.manifest.sha256 | length == 64)
  and .failure_reason == null
  and .operation_exit_code == 0
' "${backup_dir}/transaction-result.json" >/dev/null
grep -Fq '  runtime/protocols/hy2.env' "${backup_dir}/SHA256SUMS"
grep -Fq '  runtime/protocols/index.env' "${backup_dir}/SHA256SUMS"
grep -Fq '  metadata.json' "${backup_dir}/SHA256SUMS"
[[ "$(stat -c '%a' "${backup_dir}")" == "700" ]]
[[ "$(stat -c '%a' "${backup_dir}/metadata.json")" == "600" ]]
[[ "$(stat -c '%a' "${backup_dir}/transaction-result.json")" == "600" ]]
(cd "${backup_dir}" && sha256sum -c SHA256SUMS >/dev/null)

backup_count_before=$(find "${SB_UPGRADE_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | wc -l)
noop_json=$(agent_cli upgrade --json 1.14.0 --yes)
backup_count_after=$(find "${SB_UPGRADE_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | wc -l)
jq -e '
  .schema == "1"
  and .schema_version == "1.0"
  and .command == "upgrade"
  and .ok == true
  and .changed == false
  and .backup == null
  and .transaction.status == "not_attempted"
  and .transaction.result_persisted == false
  and .transaction.reason == "already_installed"
  and .transaction.rollback.attempted == false
' <<< "${noop_json}" >/dev/null
[[ "${backup_count_after}" == "${backup_count_before}" ]]

mv() {
  if [[ "${3:-}" == "${backup_dir}/transaction-result.json" ]]; then
    return 75
  fi
  command mv "$@"
}
if write_agent_upgrade_transaction_result \
  "${backup_dir}" \
  "success" \
  false \
  "not_attempted" \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; then
  printf 'expected transaction result atomic rename failure\n' >&2
  exit 1
fi
unset -f mv

touch "${CURRENT_CHECK_FAIL_FILE}"
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'current config-check failure should return non-zero\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "config_check_failed" and .preflight.current_check.exit_code == 23' <<< "${upgrade_json}" >/dev/null

rm -f "${CURRENT_CHECK_FAIL_FILE}"
: > "${SYSTEMCTL_CALLS_FILE}"
DIRECT_BINARY_COPY_FILE="${TMP_DIR}/direct-binary-copy"
cp() {
  local destination=${!#}

  if [[ "${destination}" == "${SINGBOX_BIN_PATH}" ]]; then
    : > "${DIRECT_BINARY_COPY_FILE}"
    return 26
  fi
  command cp "$@"
}
restore_agent_upgrade_backup "${backup_dir}" "n" "n"
unset -f cp
[[ ! -e "${DIRECT_BINARY_COPY_FILE}" ]]
grep -Fqx 'stop sing-box' "${SYSTEMCTL_CALLS_FILE}"

original_replace_function=$(declare -f replace_singbox_binary_atomically)
replace_singbox_binary_atomically() {
  return 1
}
: > "${SYSTEMCTL_CALLS_FILE}"
if restore_agent_upgrade_backup "${backup_dir}" "n" "y"; then
  printf 'expected binary restore failure to return non-zero\n' >&2
  exit 1
fi
eval "${original_replace_function}"
if grep -Fqx 'restart sing-box' "${SYSTEMCTL_CALLS_FILE}"; then
  printf 'binary restore failure must not restart sing-box\n' >&2
  exit 1
fi
grep -Fqx 'stop sing-box' "${SYSTEMCTL_CALLS_FILE}"

cp() {
  if [[ "${1:-}" == "-p" && "${2:-}" == "${backup_dir}/sing-box.service" ]]; then
    return 27
  fi
  command cp "$@"
}
: > "${SYSTEMCTL_CALLS_FILE}"
if restore_agent_upgrade_backup "${backup_dir}" "n" "y"; then
  printf 'expected service artifact restore failure to return non-zero\n' >&2
  exit 1
fi
unset -f cp
if grep -Fqx 'restart sing-box' "${SYSTEMCTL_CALLS_FILE}"; then
  printf 'partial artifact restore must not restart sing-box\n' >&2
  exit 1
fi
grep -Fqx 'stop sing-box' "${SYSTEMCTL_CALLS_FILE}"

printf 'tampered\n' >> "${backup_dir}/runtime/protocols/hy2.env"
if restore_agent_upgrade_backup "${backup_dir}" "n" "n"; then
  printf 'expected recursive backup manifest to reject a modified runtime state file\n' >&2
  exit 1
fi

backup_count_before=$(find "${SB_UPGRADE_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | wc -l)
sha256sum() {
  if [[ "${1:-}" == "runtime/protocols/hy2.env" ]]; then
    return 74
  fi
  command sha256sum "$@"
}
if create_agent_upgrade_backup "1.13.18" "1.14.0" >/dev/null; then
  printf 'expected a runtime file hash failure to cancel backup creation\n' >&2
  exit 1
fi
backup_count_after=$(find "${SB_UPGRADE_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | wc -l)
[[ "${backup_count_after}" == "${backup_count_before}" ]]

printf '%s\n' 'agent upgrade command checks passed'
