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
export CURRENT_CHECK_FAIL_FILE

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
' <<< "${capabilities_json}" >/dev/null

check_json=$(agent_cli upgrade-check --json 1.14.0)
jq -e '
  .ready == true
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

  write_singbox_stub "${SB_VERSION}"
  systemctl restart sing-box >/dev/null
}

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
rm -f "${TARGET_CHECK_FAIL_FILE}"

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
eval "${original_restore_function}"
rm -f "${TARGET_CHECK_FAIL_FILE}"
write_singbox_stub "1.13.18"

upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes)
jq -e '
  .ok == true
  and .changed == true
  and .restarted == true
  and .rolled_back == false
  and .installed == "1.14.0"
  and .config_preserved == true
  and (.backup | length > 0)
  and .check.ok == true
' <<< "${upgrade_json}" >/dev/null
[[ "$(agent_file_sha256 "${SINGBOX_CONFIG_FILE}")" == "${original_hash}" ]]
backup_dir=$(jq -r '.backup' <<< "${upgrade_json}")
[[ -f "${backup_dir}/runtime/config.json" ]]
[[ -f "${backup_dir}/sing-box" ]]
[[ -f "${backup_dir}/sing-box.service" ]]
[[ -f "${backup_dir}/SHA256SUMS" ]]
[[ -f "${backup_dir}/metadata.json" ]]
[[ "$(stat -c '%a' "${backup_dir}")" == "700" ]]
[[ "$(stat -c '%a' "${backup_dir}/metadata.json")" == "600" ]]
(cd "${backup_dir}" && sha256sum -c SHA256SUMS >/dev/null)

touch "${CURRENT_CHECK_FAIL_FILE}"
if upgrade_json=$(agent_cli upgrade --json 1.14.0 --yes 2>/dev/null); then
  printf 'current config-check failure should return non-zero\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "config_check_failed" and .preflight.current_check.exit_code == 23' <<< "${upgrade_json}" >/dev/null

printf '%s\n' 'agent upgrade command checks passed'
