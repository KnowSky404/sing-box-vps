#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${TESTS_DIR}/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
CASE_NUMBER=0
grep -Fqx 'readonly SB_LEGACY_PROJECT_DIR="/root/sing-box-vps"' "${REPO_ROOT}/src/install/47-storage-migration.sh"

fixture() {
  STORAGE_CASE_DIR="${TEST_ROOT}/${CASE_NUMBER}"
  export STORAGE_CASE_DIR
  mkdir -p -m 700 "${STORAGE_CASE_DIR}/home" "${STORAGE_CASE_DIR}/system/bin" "${STORAGE_CASE_DIR}/system/lib" "${STORAGE_CASE_DIR}/system/systemd" "${STORAGE_CASE_DIR}/external"
  SB_ROOT_HOME="${STORAGE_CASE_DIR}/home"
  SB_DATA_ROOT="${SB_ROOT_HOME}/.sing-box-vps"
  SB_PROJECT_DIR="${SB_DATA_ROOT}/runtime"
  SBV_BIN_PATH="${SB_DATA_ROOT}/bin/sbv"
  SINGBOX_BIN_PATH="${SB_DATA_ROOT}/bin/sing-box"
  SINGBOX_CONFIG_FILE="${SB_PROJECT_DIR}/config.json"
  SINGBOX_SERVICE_FILE="${SB_DATA_ROOT}/systemd/sing-box.service"
  SBV_LINK_PATH="${STORAGE_CASE_DIR}/system/bin/sbv"
  SINGBOX_LINK_PATH="${STORAGE_CASE_DIR}/system/bin/sing-box"
  SINGBOX_SERVICE_LINK_PATH="${STORAGE_CASE_DIR}/system/systemd/sing-box.service"
  SBV_LOG_FILE="${SB_DATA_ROOT}/logs/sbv.log"
  SB_MEDIA_CHECK_DIR="${SB_DATA_ROOT}/modules/media-check"
  PROJECT_AUTHOR=KnowSky404
  PROJECT_URL=https://github.com/KnowSky404/sing-box-vps
  AGENT_OUTPUT_SCHEMA_VERSION=1
  # Definitions only: these modules have no launcher or production operations.
  source "${REPO_ROOT}/src/install/29-agent-upgrade.sh"
  source "${REPO_ROOT}/src/install/46-storage-layout.sh"
  source <(sed -e "s|^readonly SB_LEGACY_PROJECT_DIR=.*|readonly SB_LEGACY_PROJECT_DIR=\"${SB_ROOT_HOME}/sing-box-vps\"|" "${REPO_ROOT}/src/install/47-storage-migration.sh")
  agent_current_user_is_root() { [[ "${EUID}" == 0 ]]; }
  # Policy commands are tested by the storage layout fixture. Never mutate the
  # host policy from migration fixtures, including on an enforcing test host.
  storage_selinux_prepare() {
    if [[ -f "${STORAGE_CASE_DIR}/active" ]]; then printf 'prepare active\n'; else printf 'prepare stopped\n'; fi >> "${STORAGE_CASE_DIR}/selinux.log"
    [[ ! -f "${STORAGE_CASE_DIR}/fail-selinux-prepare" ]]
  }
  storage_selinux_label() {
    [[ -e "$1" && ! -L "$1" ]] || return 1
    printf 'label %s -> %s\n' "$1" "${2:-$1}" >> "${STORAGE_CASE_DIR}/selinux.log"
  }
  storage_selinux_restore_system_path() {
    [[ -f "$1" && ! -L "$1" ]] || return 1
    printf 'restore %s\n' "$1" >> "${STORAGE_CASE_DIR}/selinux.log"
    [[ ! -f "${STORAGE_CASE_DIR}/fail-selinux-restore" ]]
  }
  # State validators are integration dependencies. Their detailed protocol
  # semantics are covered by the existing real validators and Docker fixture.
  validate_structured_instance_store() { jq -e '.revision>=0 and (.instances|type)=="array" and all(.instances[];(.id|type)=="string")' "$2" >/dev/null; }
  managed_component_state_validate_json() { jq -e '(.components|type)=="array"' <<< "$1" >/dev/null; }
  routing_policy_validate_json() { jq -e '.schema_version==1 or .schema_version==2' <<< "$1" >/dev/null; }
  systemctl() {
    printf '%s\n' "$*" >> "${STORAGE_CASE_DIR}/systemctl.log"
    case "$1" in
      show)
        [[ ! -f "${STORAGE_CASE_DIR}/dropins-unavailable" ]] || return 1
        if [[ -f "${STORAGE_CASE_DIR}/custom-dropin" ]]; then printf '%s\n' "${STORAGE_CASE_DIR}/custom-dropin"; fi
        return 0 ;;
      is-active) [[ -f "${STORAGE_CASE_DIR}/active" ]] && return 0; return 3 ;;
      stop) [[ ! -f "${STORAGE_CASE_DIR}/fail-stop" ]] || return 1; rm -f "${STORAGE_CASE_DIR}/active" ;;
      start)
        if [[ -L "${SINGBOX_SERVICE_LINK_PATH}" && -f "${STORAGE_CASE_DIR}/fail-new-start" ]]; then return 1; fi
        touch "${STORAGE_CASE_DIR}/active" ;;
      daemon-reload) return 0 ;;
      *) return 1 ;;
    esac
  }
  SB_STORAGE_SCRIPT_SOURCE="${STORAGE_CASE_DIR}/new-install.sh"
  cat > "${SB_STORAGE_SCRIPT_SOURCE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
# current management runtime fixture
EOF
  chmod 700 "${SB_STORAGE_SCRIPT_SOURCE}"
}

legacy_fixture() {
  mkdir -p -m 700 "${SB_LEGACY_PROJECT_DIR}/protocols/instances" "${SB_LEGACY_PROJECT_DIR}/media-check" "${SB_LEGACY_PROJECT_DIR}/rule-set/warp" "${SB_LEGACY_BACKUP_DIR}/upgrade-old"
  printf 'certificate\n' > "${SB_LEGACY_PROJECT_DIR}/cert.pem"
  printf 'external key\n' > "${STORAGE_CASE_DIR}/external/key.pem"
  jq -n --arg old "${SB_LEGACY_PROJECT_DIR}" --arg external "${STORAGE_CASE_DIR}/external/key.pem" \
    '{log:{level:"info"},inbounds:[],outbounds:[],tls:{certificate_path:($old+"/cert.pem"),key_path:$external},route:{rule_set:[{type:"local",path:($old+"/rule-set/warp/domains.srs")}]},password:($old+"/a-secret"),name:($old+"/a-name")}' > "${SB_LEGACY_PROJECT_DIR}/config.json"
  cp "${SB_LEGACY_PROJECT_DIR}/config.json" "${SB_LEGACY_PROJECT_DIR}/managed-config.generated.json"
  jq -n --arg old "${SB_LEGACY_PROJECT_DIR}" '{revision:9,instances:[{id:"retained-id",tls:{certificate_path:($old+"/cert.pem")},password:($old+"/not-a-path")} ]}' > "${SB_LEGACY_PROJECT_DIR}/protocols/instances/anytls.json"
  printf 'CERT_PATH=%q\nKEY_PATH=%q\nACME_EXTRA_JSON=%q\n' \
    "${SB_LEGACY_PROJECT_DIR}/cert.pem" "${STORAGE_CASE_DIR}/external/key.pem" \
    "{\"data_directory\":\"${SB_LEGACY_PROJECT_DIR}/acme\",\"token\":\"${SB_LEGACY_PROJECT_DIR}/secret\"}" > "${SB_LEGACY_PROJECT_DIR}/protocols/anytls.env"
  printf 'opaque\000unknown\n' > "${SB_LEGACY_PROJECT_DIR}/unknown-file"
  printf 'preserve unknown candidate-like filename\n' > "${SB_LEGACY_PROJECT_DIR}/config.json.storage-next"
  mkdir -m 700 "${SB_LEGACY_PROJECT_DIR}/protocols/archive"
  printf 'CERT_PATH=$(unrecognized historical literal)\n' > "${SB_LEGACY_PROJECT_DIR}/protocols/archive/unknown.env"
  printf 'legacy log\n' > "${SB_LEGACY_PROJECT_DIR}/sbv.log"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${SB_LEGACY_PROJECT_DIR}/media-check/check.sh"
  printf 'historical bytes\n' > "${SB_LEGACY_BACKUP_DIR}/upgrade-old/metadata.json"
  (cd "${SB_LEGACY_BACKUP_DIR}/upgrade-old" && sha256sum metadata.json > SHA256SUMS)
  cp "${SB_STORAGE_SCRIPT_SOURCE}" "${SBV_LINK_PATH}"
  cat > "${SINGBOX_LINK_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf 'sing-box version 1.14.2\n' ;;
  check)
    [[ ! -f "${STORAGE_CASE_DIR}/fail-check" ]] || exit 1
    [[ "${2:-}" == -c && -f "${3:-}" ]] || exit 1
    jq -e 'type=="object"' "$3" >/dev/null
    printf '%s\n' "$3" >> "${STORAGE_CASE_DIR}/checks.log"
    ;;
  *) exit 1 ;;
esac
EOF
  chmod 700 "${SBV_LINK_PATH}" "${SINGBOX_LINK_PATH}"
  cat > "${SINGBOX_SERVICE_LINK_PATH}" <<EOF
[Unit]
Description=sing-box service
[Service]
ExecStart=${SINGBOX_LINK_PATH} run -c ${SB_LEGACY_PROJECT_DIR}/config.json
[Install]
WantedBy=multi-user.target
EOF
  chmod 600 "${SINGBOX_SERVICE_LINK_PATH}"
}

expect_failure() {
  if "$@" > "${STORAGE_CASE_DIR}/unexpected-stdout" 2> "${STORAGE_CASE_DIR}/failure.log"; then
    printf 'expected command to fail: %s\n' "$1" >&2
    return 1
  fi
}

completed_backup() { jq -r .backup "${SB_DATA_ROOT}/migrations/completed.json"; }

case_status_read_only() {
  storage_status_json | jq -e '.migration_required==false and .recovery_required==false' >/dev/null
  [[ ! -e "${SB_DATA_ROOT}" ]]
  legacy_fixture
  storage_status_json | jq -e '.migration_required==true and .phase=="none"' >/dev/null
  [[ ! -e "${SB_DATA_ROOT}" ]]
}

case_migrate_active() {
  local backup value source_hash
  legacy_fixture
  chmod 755 "${SB_LEGACY_PROJECT_DIR}"
  touch "${STORAGE_CASE_DIR}/active"
  source_hash=$(sha256sum "${SB_LEGACY_PROJECT_DIR}/unknown-file" | cut -d' ' -f1)
  storage_cli migrate --json --yes > "${STORAGE_CASE_DIR}/result.json"
  jq -s -e 'length==1 and .[0].ok==true and .[0].data.migration_required==false' "${STORAGE_CASE_DIR}/result.json" >/dev/null
  backup=$(completed_backup)
  [[ -f "${STORAGE_CASE_DIR}/active" && ! -e "${SB_LEGACY_PROJECT_DIR}" && ! -e "${SB_LEGACY_BACKUP_DIR}" && ! -e "${SB_STORAGE_MIGRATION_DIR}" ]]
  [[ -L "${SBV_LINK_PATH}" && -L "${SINGBOX_LINK_PATH}" && -L "${SINGBOX_SERVICE_LINK_PATH}" ]]
  [[ -f "${backup}/legacy-runtime/config.json" && -f "${backup}/legacy-siblings/management.flock" ]]
  grep -Fqx 'prepare active' "${STORAGE_CASE_DIR}/selinux.log"
  grep -Fq " -> ${SINGBOX_BIN_PATH}" "${STORAGE_CASE_DIR}/selinux.log"
  grep -Fq " -> ${SINGBOX_SERVICE_FILE}" "${STORAGE_CASE_DIR}/selinux.log"
  grep -Fqx "label ${SB_PROJECT_DIR} -> ${SB_PROJECT_DIR}" "${STORAGE_CASE_DIR}/selinux.log"
  [[ "$(stat -c %a "${SB_PROJECT_DIR}")" == 700 && "$(stat -c %a "${backup}/legacy-runtime")" == 755 ]]
  [[ "$(sha256sum "${SB_PROJECT_DIR}/unknown-file" | cut -d' ' -f1)" == "${source_hash}" ]]
  cmp -s "${backup}/legacy-runtime/config.json.storage-next" "${SB_PROJECT_DIR}/config.json.storage-next"
  cmp -s "${backup}/legacy-runtime/protocols/archive/unknown.env" "${SB_PROJECT_DIR}/protocols/archive/unknown.env"
  jq -e --arg new "${SB_PROJECT_DIR}" --arg old "${SB_LEGACY_PROJECT_DIR}" --arg ext "${STORAGE_CASE_DIR}/external/key.pem" \
    '.tls.certificate_path==($new+"/cert.pem") and .tls.key_path==$ext and .password==($old+"/a-secret") and .name==($old+"/a-name") and .route.rule_set[0].path==($new+"/rule-set/warp/domains.srs")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  jq -e --arg new "${SB_PROJECT_DIR}" --arg old "${SB_LEGACY_PROJECT_DIR}" '.revision==9 and .instances[0].id=="retained-id" and .instances[0].password==($old+"/not-a-path") and .instances[0].tls.certificate_path==($new+"/cert.pem")' "${SB_PROJECT_DIR}/protocols/instances/anytls.json" >/dev/null
  value=$(storage_decode_env_literal "$(sed -n 's/^CERT_PATH=//p' "${SB_PROJECT_DIR}/protocols/anytls.env")")
  [[ "${value}" == "${SB_PROJECT_DIR}/cert.pem" ]]
  value=$(storage_decode_env_literal "$(sed -n 's/^ACME_EXTRA_JSON=//p' "${SB_PROJECT_DIR}/protocols/anytls.env")")
  jq -e --arg old "${SB_LEGACY_PROJECT_DIR}" --arg new "${SB_PROJECT_DIR}" '.data_directory==($new+"/acme") and .token==($old+"/secret")' <<< "${value}" >/dev/null
  [[ -f "${SBV_LOG_FILE}" && ! -e "${SB_PROJECT_DIR}/sbv.log" && -f "${SB_MEDIA_CHECK_DIR}/check.sh" ]]
  (cd "${backup}/legacy-backups/upgrade-old" && sha256sum -c SHA256SUMS >/dev/null)
  [[ "$(wc -l < "${STORAGE_CASE_DIR}/checks.log")" == 2 ]]
  storage_cli migrate --json --yes | jq -e '.ok==true' >/dev/null
}

case_migrate_stopped_and_history() {
  local backup
  legacy_fixture
  mkdir -m 700 "${SB_LEGACY_PROJECT_DIR}.rules-previous" "${SB_LEGACY_PROJECT_DIR}.instance-transactions"
  printf '{"phase":"committed"}\n' > "${SB_LEGACY_PROJECT_DIR}.rules-previous/transaction.json"
  printf 'historical result\n' > "${SB_LEGACY_PROJECT_DIR}.instance-transactions/result.json"
  storage_migrate
  backup=$(completed_backup)
  [[ ! -f "${STORAGE_CASE_DIR}/active" && -f "${backup}/legacy-rules-previous/transaction.json" && -f "${backup}/legacy-instance-transactions/result.json" ]]
}

case_conflict() {
  legacy_fixture
  mkdir -p "${SB_PROJECT_DIR}"
  printf 'keep\n' > "${SB_PROJECT_DIR}/keep"
  expect_failure storage_migrate
  [[ -f "${SB_PROJECT_DIR}/keep" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" && ! -e "${SB_STORAGE_MIGRATION_DIR}" ]]
}

case_pending() {
  local suffix
  legacy_fixture
  for suffix in instance-write.lock component-write.lock rules-write.lock warp-registration.pending.json; do
    touch "${SB_LEGACY_PROJECT_DIR}.${suffix}"
    expect_failure storage_migrate
    [[ ! -e "${SB_DATA_ROOT}" ]]
    rm "${SB_LEGACY_PROJECT_DIR}.${suffix}"
  done
}

case_untrusted() {
  legacy_fixture
  ln -s "${STORAGE_CASE_DIR}/external/key.pem" "${SB_LEGACY_PROJECT_DIR}/unsafe-link"
  expect_failure storage_migrate
  rm "${SB_LEGACY_PROJECT_DIR}/unsafe-link"
  chmod 666 "${SB_LEGACY_PROJECT_DIR}/config.json"
  expect_failure storage_migrate
  chmod 600 "${SB_LEGACY_PROJECT_DIR}/config.json"
  chmod 777 "${SB_LEGACY_PROJECT_DIR}"
  expect_failure storage_migrate
}

case_env_no_execution() {
  legacy_fixture
  printf 'CERT_PATH=$(touch %s)\n' "${STORAGE_CASE_DIR}/executed" > "${SB_LEGACY_PROJECT_DIR}/protocols/anytls.env"
  expect_failure storage_migrate
  [[ ! -e "${STORAGE_CASE_DIR}/executed" && ! -e "${SB_STORAGE_MIGRATION_DIR}" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" ]]
}

case_env_literal_roundtrip() {
  local value raw decoded
  for value in 'plain/path' '/a space/quote\value' '/a/$literal/$(never)' '/a/"double"/single\quote' $'{\n  "key":"value",\n  "token":"$never"\n}' $'unicode/\303\251'; do
    printf -v raw '%q' "${value}"
    decoded=$(storage_decode_env_literal "${raw}")
    [[ "${decoded}" == "${value}" ]]
  done
  [[ "$(storage_decode_env_literal '"/a/\z"')" == '/a/\z' ]]
  expect_failure storage_decode_env_literal "\$'\\000'"
}

case_implicit_module_state() {
  legacy_fixture
  jq '.outbounds=[{type:"tor",tag:"legacy-tor"}]' "${SB_LEGACY_PROJECT_DIR}/config.json" > "${STORAGE_CASE_DIR}/implicit.json"
  cp "${STORAGE_CASE_DIR}/implicit.json" "${SB_LEGACY_PROJECT_DIR}/config.json"
  expect_failure storage_migrate
  jq '.outbounds=[]|.endpoints=[{type:"tailscale",tag:"legacy-tail",state_directory:"/external/explicit",taildrop_directory:"/external/taildrop"}]' "${SB_LEGACY_PROJECT_DIR}/config.json" > "${STORAGE_CASE_DIR}/explicit.json"
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/explicit.json"
  jq -n '{components:[{type:"tailscale",config:{state_directory:"/external/explicit",taildrop_directory:"/external/taildrop"}},{type:"tor",config:{data_directory:"/external/explicit"}}]}' > "${STORAGE_CASE_DIR}/components-explicit.json"
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/components-explicit.json"
  [[ -f "${SB_LEGACY_PROJECT_DIR}/config.json" && ! -e "${SB_STORAGE_MIGRATION_DIR}" ]]
  jq '.outbounds=[]|.endpoints=[{type:"tailscale",tag:"legacy-tail",state_directory:"relative-state"}]' "${SB_LEGACY_PROJECT_DIR}/config.json" > "${STORAGE_CASE_DIR}/implicit.json"
  cp "${STORAGE_CASE_DIR}/implicit.json" "${SB_LEGACY_PROJECT_DIR}/config.json"
  expect_failure storage_migrate
}

case_check_failure_rollback() {
  local original
  legacy_fixture
  touch "${STORAGE_CASE_DIR}/active" "${STORAGE_CASE_DIR}/fail-selinux-prepare"
  expect_failure storage_migrate
  [[ -f "${STORAGE_CASE_DIR}/active" && ! -e "${SB_STORAGE_MIGRATION_DIR}" && ! -L "${SINGBOX_LINK_PATH}" ]]
  if grep -Fxq stop "${STORAGE_CASE_DIR}/systemctl.log"; then return 1; fi
  rm "${STORAGE_CASE_DIR}/fail-selinux-prepare"
  touch "${STORAGE_CASE_DIR}/fail-check"
  original=$(sha256sum "${SB_LEGACY_PROJECT_DIR}/config.json" | cut -d' ' -f1)
  expect_failure storage_migrate
  [[ ! -e "${SB_STORAGE_MIGRATION_DIR}" && ! -e "${SINGBOX_CONFIG_FILE}" && -f "${STORAGE_CASE_DIR}/active" && ! -L "${SBV_LINK_PATH}" ]]
  [[ "$(sha256sum "${SB_LEGACY_PROJECT_DIR}/config.json" | cut -d' ' -f1)" == "${original}" ]]
  rm "${STORAGE_CASE_DIR}/fail-check"
  storage_migrate
}

case_service_failure_rollback() {
  legacy_fixture
  touch "${STORAGE_CASE_DIR}/active" "${STORAGE_CASE_DIR}/fail-new-start"
  expect_failure storage_migrate
  [[ -f "${STORAGE_CASE_DIR}/active" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" && ! -L "${SINGBOX_LINK_PATH}" && ! -e "${SB_STORAGE_MIGRATION_DIR}" ]]
  grep -Fqx "restore ${SBV_LINK_PATH}" "${STORAGE_CASE_DIR}/selinux.log"
  grep -Fqx "restore ${SINGBOX_LINK_PATH}" "${STORAGE_CASE_DIR}/selinux.log"
  grep -Fqx "restore ${SINGBOX_SERVICE_LINK_PATH}" "${STORAGE_CASE_DIR}/selinux.log"
}

case_lock_and_handoff() {
  local inherited
  legacy_fixture
  exec {inherited}>"${SB_LEGACY_PROJECT_DIR}.management.flock"
  flock -x "${inherited}"
  expect_failure storage_migrate
  SB_MANAGEMENT_LOCK_FD=${inherited}
  SB_MANAGEMENT_LOCK_MODE=exclusive
  storage_cli migrate --json --yes > "${STORAGE_CASE_DIR}/handoff.json"
  [[ -z "${SB_MANAGEMENT_LOCK_FD:-}" && -z "${SB_MANAGEMENT_LOCK_MODE:-}" ]]
  jq -e '.ok==true' "${STORAGE_CASE_DIR}/handoff.json" >/dev/null
}

case_library() {
  local legacy_library backup
  legacy_fixture
  legacy_library="${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  printf 'managed library\n' > "${legacy_library}"
  sha256sum "${legacy_library}" | cut -d' ' -f1 > "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256"
  storage_migrate
  backup=$(completed_backup)
  [[ ! -e "${legacy_library}" && -f "${backup}/original-library" && -L "${SB_DATA_ROOT}/bin/libcronet.so" ]]
  cmp -s "${backup}/original-library" "${SB_DATA_ROOT}/lib/libcronet.so"
}

case_cli_confirmation() {
  legacy_fixture
  expect_failure storage_cli migrate --json
  jq -s -e 'length==1 and .[0].ok==false and .[0].error=="confirmation_required"' "${STORAGE_CASE_DIR}/unexpected-stdout" >/dev/null
  [[ ! -e "${SB_DATA_ROOT}" ]]
  expect_failure storage_cli status --json --json
  jq -e '.error=="invalid_arguments"' "${STORAGE_CASE_DIR}/unexpected-stdout" >/dev/null
  expect_failure storage_cli migrate --json --yes --yes
  jq -e '.error=="invalid_arguments"' "${STORAGE_CASE_DIR}/unexpected-stdout" >/dev/null
  expect_failure storage_cli status --json --unknown
  expect_failure storage_cli status --json --yes
  agent_current_user_is_root() { return 1; }
  storage_status_json() { printf 'unexpected storage state read\n' >&2; return 87; }
  expect_failure storage_cli status --json
  jq -e '.error=="root_required"' "${STORAGE_CASE_DIR}/unexpected-stdout" >/dev/null
  [[ ! -s "${STORAGE_CASE_DIR}/failure.log" && ! -e "${SB_DATA_ROOT}" ]]
}

case_recover_interrupted() {
  local backup
  legacy_fixture
  touch "${STORAGE_CASE_DIR}/active"
  # Inject an uncatchable stop immediately after durable links publication.
  storage_publish_system_links() {
    case "$1" in
      sbv) storage_publish_system_link "${SBV_LINK_PATH}" "${SBV_BIN_PATH}" ;;
      sing-box) storage_publish_system_link "${SINGBOX_LINK_PATH}" "${SINGBOX_BIN_PATH}" ;;
      service)
        storage_publish_system_link "${SINGBOX_SERVICE_LINK_PATH}" "${SINGBOX_SERVICE_FILE}"
        kill -KILL "${BASHPID}"
        ;;
    esac
  }
  expect_failure storage_migrate
  storage_needs_recovery
  backup=$(jq -r .backup "${SB_STORAGE_MIGRATION_DIR}/journal.json")
  touch "${STORAGE_CASE_DIR}/fail-stop"
  expect_failure storage_recover
  jq -e '.phase=="rollback_failed"' "${SB_STORAGE_MIGRATION_DIR}/journal.json" >/dev/null
  rm "${STORAGE_CASE_DIR}/fail-stop"
  touch "${STORAGE_CASE_DIR}/fail-selinux-restore"
  expect_failure storage_recover
  jq -e '.phase=="rollback_failed"' "${SB_STORAGE_MIGRATION_DIR}/journal.json" >/dev/null
  rm "${STORAGE_CASE_DIR}/fail-selinux-restore"
  storage_recover
  [[ ! -e "${SB_STORAGE_MIGRATION_DIR}" && -f "${STORAGE_CASE_DIR}/active" && ! -L "${SBV_LINK_PATH}" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" && -f "${backup}/journal/journal.json" ]]
}

case_recover_after_archive() {
  local backup
  legacy_fixture
  printf 'managed library\n' > "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  sha256sum "${STORAGE_CASE_DIR}/system/lib/libcronet.so" | cut -d' ' -f1 > "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256"
  touch "${STORAGE_CASE_DIR}/active"
  storage_migration_phase() {
    jq --arg phase "$1" '.phase=$phase' "${SB_STORAGE_MIGRATION_DIR}/journal.json" > "${SB_STORAGE_MIGRATION_DIR}/journal.next"
    mv -f "${SB_STORAGE_MIGRATION_DIR}/journal.next" "${SB_STORAGE_MIGRATION_DIR}/journal.json"
    if [[ "$1" == completed ]]; then kill -KILL "${BASHPID}"; fi
  }
  expect_failure storage_migrate
  storage_needs_recovery
  [[ ! -e "${SB_LEGACY_PROJECT_DIR}" && ! -e "${SB_LEGACY_PROJECT_DIR}.management.flock" ]]
  backup=$(jq -r .backup "${SB_STORAGE_MIGRATION_DIR}/journal.json")
  [[ -f "${backup}/legacy-siblings/management.flock" ]]
  storage_recover
  [[ ! -e "${SB_STORAGE_MIGRATION_DIR}" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" && -f "${STORAGE_CASE_DIR}/active" ]]
  [[ -f "${STORAGE_CASE_DIR}/system/lib/libcronet.so" && ! -e "${SB_DATA_ROOT}/lib/libcronet.so" && ! -L "${SB_DATA_ROOT}/bin/libcronet.so" ]]
}

case_recovery_ownership_conflict() {
  local backup replacement_hash
  legacy_fixture
  touch "${STORAGE_CASE_DIR}/active"
  printf 'managed library\n' > "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  sha256sum "${STORAGE_CASE_DIR}/system/lib/libcronet.so" | cut -d' ' -f1 > "${SB_LEGACY_PROJECT_DIR}/libcronet.sha256"
  storage_migration_phase() {
    jq --arg phase "$1" '.phase=$phase | if $phase=="rollback" then del(.last_error) else . end' "${SB_STORAGE_MIGRATION_DIR}/journal.json" > "${SB_STORAGE_MIGRATION_DIR}/journal.next"
    mv -f "${SB_STORAGE_MIGRATION_DIR}/journal.next" "${SB_STORAGE_MIGRATION_DIR}/journal.json"
    if [[ "$1" == completed ]]; then kill -KILL "${BASHPID}"; fi
  }
  expect_failure storage_migrate
  backup=$(jq -r .backup "${SB_STORAGE_MIGRATION_DIR}/journal.json")
  rm "${SBV_LINK_PATH}"
  printf 'unrelated administrator replacement\n' > "${SBV_LINK_PATH}"
  replacement_hash=$(sha256sum "${SBV_LINK_PATH}" | cut -d' ' -f1)
  expect_failure storage_cli recover --json --yes
  jq -e '.error=="ownership_conflict" and .data.recovery_required' "${STORAGE_CASE_DIR}/unexpected-stdout" >/dev/null
  [[ "$(sha256sum "${SBV_LINK_PATH}" | cut -d' ' -f1)" == "${replacement_hash}" && -e "${SB_STORAGE_MIGRATION_DIR}" ]]
  rm "${SBV_LINK_PATH}"
  ln -s "${STORAGE_CASE_DIR}/external/key.pem" "${SBV_LINK_PATH}"
  expect_failure storage_cli recover --json --yes
  [[ "$(readlink "${SBV_LINK_PATH}")" == "${STORAGE_CASE_DIR}/external/key.pem" ]]
  rm "${SBV_LINK_PATH}"
  ln -s "${SBV_BIN_PATH}" "${SBV_LINK_PATH}"
  printf 'unrelated library replacement\n' > "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  replacement_hash=$(sha256sum "${STORAGE_CASE_DIR}/system/lib/libcronet.so" | cut -d' ' -f1)
  expect_failure storage_cli recover --json --yes
  jq -e '.error=="ownership_conflict"' "${STORAGE_CASE_DIR}/unexpected-stdout" >/dev/null
  [[ "$(sha256sum "${STORAGE_CASE_DIR}/system/lib/libcronet.so" | cut -d' ' -f1)" == "${replacement_hash}" ]]
  rm "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  ln -s "${STORAGE_CASE_DIR}/external/key.pem" "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  expect_failure storage_cli recover --json --yes
  [[ "$(readlink "${STORAGE_CASE_DIR}/system/lib/libcronet.so")" == "${STORAGE_CASE_DIR}/external/key.pem" ]]
  rm "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  ln -s "${SB_DATA_ROOT}/lib/libcronet.so" "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  storage_cli recover --json --yes > "${STORAGE_CASE_DIR}/recovered.json"
  jq -e '.ok and (.data.recovery_required|not)' "${STORAGE_CASE_DIR}/recovered.json" >/dev/null
  [[ -f "${SB_LEGACY_PROJECT_DIR}/config.json" && -f "${STORAGE_CASE_DIR}/active" ]]
  cmp -s "${backup}/original-library" "${STORAGE_CASE_DIR}/system/lib/libcronet.so"
  storage_migration_recovery_target_owned "${backup}/original-sbv" "${SBV_LINK_PATH}" "${SBV_BIN_PATH}"
}

case_precise_path_contexts() {
  local fields field prefix uri expected value encoded_path query
  fields='["certificate_authority_path","crl_path","secret_path","taildrop_directory","executable_path","wrapper_path","initial_path","protect_path"]'
  jq -n --arg old "${SB_LEGACY_PROJECT_DIR}" --argjson fields "${fields}" '
    {paths:($fields|map({key:.,value:($old+"/"+.)})|from_entries),
     password:($old+"/password"),process_path:($old+"/process"),process_path_regex:($old+"/matcher.*"),
     transports:[{type:"ws",path:($old+"/ws")},{type:"http",path:($old+"/http")}],
     components:[{role:"rule_set",type:"local",config:{path:($old+"/rules.json")}},{role:"network_namespace",type:"default",config:{path:($old+"/ns")}}],
     network_namespaces:[{type:"default",path:($old+"/ns")}],log:{output:($old+"/core.log")},
     experimental:{clash_api:{external_ui:($old+"/ui")},cache_file:{enabled:true,path:($old+"/cache.db")}}}' > "${STORAGE_CASE_DIR}/path-contexts.json"
  storage_rewrite_path_json < "${STORAGE_CASE_DIR}/path-contexts.json" > "${STORAGE_CASE_DIR}/relocated-paths.json"
  jq -e --arg old "${SB_LEGACY_PROJECT_DIR}" --arg new "${SB_PROJECT_DIR}" --argjson fields "${fields}" '
    . as $result | all($fields[]; $result.paths[.]==($new+"/"+.)) and
    .components[0].config.path==($new+"/rules.json") and .components[1].config.path==($new+"/ns") and
    .network_namespaces[0].path==($new+"/ns") and .log.output==($new+"/core.log") and
    .experimental.clash_api.external_ui==($new+"/ui") and .experimental.cache_file.path==($new+"/cache.db") and
    .password==($old+"/password") and .process_path==($old+"/process") and .process_path_regex==($old+"/matcher.*") and
    .transports[0].path==($old+"/ws") and .transports[1].path==($old+"/http")
  ' "${STORAGE_CASE_DIR}/relocated-paths.json" >/dev/null
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relocated-paths.json"
  for field in $(jq -r '.[]' <<< "${fields}"); do
    jq --arg field "${field}" '.paths[$field]="relative"' "${STORAGE_CASE_DIR}/path-contexts.json" > "${STORAGE_CASE_DIR}/relative-paths.json"
    expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-paths.json"
  done
  jq '.components[0].config.path="relative"' "${STORAGE_CASE_DIR}/path-contexts.json" > "${STORAGE_CASE_DIR}/relative-paths.json"
  expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-paths.json"
  jq '.log.output="relative.log"' "${STORAGE_CASE_DIR}/path-contexts.json" > "${STORAGE_CASE_DIR}/relative-paths.json"
  expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-paths.json"
  jq '.experimental.clash_api.external_ui="relative-ui"' "${STORAGE_CASE_DIR}/path-contexts.json" > "${STORAGE_CASE_DIR}/relative-paths.json"
  expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-paths.json"
  printf '{"log":{"output":"stdout"}}\n' > "${STORAGE_CASE_DIR}/standard-output.json"
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/standard-output.json"
  jq -n --arg old "${SB_LEGACY_PROJECT_DIR}" '{log:{output:($old+"/sbv.log")},runtime:{executable_path:($old+"/media-check/check.sh")}}' |
    storage_rewrite_path_json | jq -e --arg log "${SBV_LOG_FILE}" --arg module "${SB_MEDIA_CHECK_DIR}" '.log.output==$log and .runtime.executable_path==($module+"/check.sh")' >/dev/null
  printf '{"log":{"output":"stderr"}}\n' > "${STORAGE_CASE_DIR}/standard-output.json"
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/standard-output.json"
  query='?token=$literal&source=%2Flegacy#fragment'
  for prefix in file: file:// file://localhost; do
    uri="${prefix}${SB_LEGACY_PROJECT_DIR}/site${query}"
    expected="${prefix}${SB_PROJECT_DIR}/site${query}"
    value=$(printf '%s' "${uri}" | jq -Rs '{masquerade:.,password:.}' | storage_rewrite_path_json)
    jq -e --arg expected "${expected}" --arg original "${uri}" '.masquerade==$expected and .password==$original' <<< "${value}" >/dev/null
  done
  uri="https://example.invalid/${SB_LEGACY_PROJECT_DIR}/site${query}"
  value=$(printf '%s' "${uri}" | jq -Rs '{masquerade:.}' | storage_rewrite_path_json | jq -r .masquerade)
  [[ "${value}" == "${uri}" ]]
  encoded_path=${SB_LEGACY_PROJECT_DIR//\//%2F}
  for uri in "file:${encoded_path}/site" "file://${SB_LEGACY_PROJECT_DIR}/si%74e" \
    "file://foreign${SB_LEGACY_PROJECT_DIR}/site" "file:${SB_LEGACY_PROJECT_DIR}/../outside" \
    "file:///${SB_LEGACY_PROJECT_DIR}/site"; do
    printf '%s' "${uri}" | jq -Rs '{masquerade:.}' > "${STORAGE_CASE_DIR}/ambiguous-uri.json"
    expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/ambiguous-uri.json"
  done
  mkdir -p -m 700 "${STORAGE_CASE_DIR}/env-tree/protocols"
  printf 'MASQUERADE=%q\n' "file://localhost${SB_LEGACY_PROJECT_DIR}/site${query}" > "${STORAGE_CASE_DIR}/env-tree/protocols/hy2.env"
  storage_migration_rewrite "${STORAGE_CASE_DIR}/env-tree"
  value=$(storage_decode_env_literal "$(sed -n 's/^MASQUERADE=//p' "${STORAGE_CASE_DIR}/env-tree/protocols/hy2.env")")
  [[ "${value}" == "file://localhost${SB_PROJECT_DIR}/site${query}" ]]
}

case_custom_service_directory() {
  local directive
  legacy_fixture
  for directive in WorkingDirectory RootDirectory RootImage Environment EnvironmentFile PassEnvironment UnsetEnvironment; do
    cp "${SINGBOX_SERVICE_LINK_PATH}" "${STORAGE_CASE_DIR}/canonical.service"
    printf '%s=%s\n' "${directive}" "${SB_LEGACY_PROJECT_DIR}" >> "${SINGBOX_SERVICE_LINK_PATH}"
    expect_failure storage_migrate
    grep -q unsupported_custom_service_directory "${STORAGE_CASE_DIR}/failure.log"
    [[ ! -e "${SB_DATA_ROOT}" ]]
    cp "${STORAGE_CASE_DIR}/canonical.service" "${SINGBOX_SERVICE_LINK_PATH}"
  done
  touch "${STORAGE_CASE_DIR}/custom-dropin"
  expect_failure storage_migrate
  grep -q unsupported_custom_service_directory "${STORAGE_CASE_DIR}/failure.log"
  rm "${STORAGE_CASE_DIR}/custom-dropin"
  touch "${STORAGE_CASE_DIR}/dropins-unavailable"
  expect_failure storage_migrate
  grep -q service_dropins_unavailable "${STORAGE_CASE_DIR}/failure.log"
  [[ ! -e "${SB_DATA_ROOT}" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" ]]
}

case_manager_only_migration() {
  local backup
  printf 'foreign command\n' > "${SBV_LINK_PATH}"
  if storage_needs_migration; then return 1; fi
  storage_migrate
  [[ "$(<"${SBV_LINK_PATH}")" == 'foreign command' && ! -e "${SB_DATA_ROOT}" ]]
  # A known sidecar must block accidental fresh-install treatment, while an
  # unrelated global command remains outside migration ownership.
  touch "${SB_LEGACY_PROJECT_DIR}.management.flock"
  storage_needs_migration
  expect_failure storage_migrate
  grep -q unmanaged_sbv_entry "${STORAGE_CASE_DIR}/failure.log"
  [[ "$(<"${SBV_LINK_PATH}")" == 'foreign command' && ! -e "${SB_DATA_ROOT}" ]]
  cp "${SB_STORAGE_SCRIPT_SOURCE}" "${SBV_LINK_PATH}"
  chmod 700 "${SBV_LINK_PATH}"
  storage_status_json | jq -e '.migration_required and (.legacy_pending|not)' >/dev/null
  storage_cli migrate --json --yes > "${STORAGE_CASE_DIR}/manager-only.json"
  jq -e '.ok and (.data.migration_required|not)' "${STORAGE_CASE_DIR}/manager-only.json" >/dev/null
  backup=$(completed_backup)
  [[ -L "${SBV_LINK_PATH}" && -f "${SBV_BIN_PATH}" && -f "${backup}/legacy-siblings/management.flock" ]]
  [[ ! -e "${SB_LEGACY_PROJECT_DIR}" && ! -e "${SB_LEGACY_BACKUP_DIR}" && ! -e "${SB_LEGACY_PROJECT_DIR}.management.flock" ]]
  [[ ! -e "${SINGBOX_LINK_PATH}" && ! -e "${SINGBOX_SERVICE_LINK_PATH}" && ! -f "${STORAGE_CASE_DIR}/active" ]]
}

case_sidecar_ownership() {
  local backup
  printf 'outside migration ownership\n' > "${SB_LEGACY_PROJECT_DIR}.user.customer"
  chmod 666 "${SB_LEGACY_PROJECT_DIR}.user.customer"
  ln -s "${STORAGE_CASE_DIR}/external/key.pem" "${SB_LEGACY_PROJECT_DIR}.user.link"
  printf 'wrong nonce length\n' > "${SB_LEGACY_PROJECT_DIR}.firewall-reconcile.aB12345"
  mkdir -m 700 "${SB_LEGACY_PROJECT_DIR}.warp-register.aB12345"
  if storage_needs_migration; then return 1; fi
  printf 'historical firewall journal\n' > "${SB_LEGACY_PROJECT_DIR}.firewall-reconcile.aB1234"
  mkdir -m 700 "${SB_LEGACY_PROJECT_DIR}.warp-register.aB123456"
  printf 'historical registration response\n' > "${SB_LEGACY_PROJECT_DIR}.warp-register.aB123456/response.json"
  storage_needs_migration 2> "${STORAGE_CASE_DIR}/sidecar-detection.stderr"
  [[ ! -s "${STORAGE_CASE_DIR}/sidecar-detection.stderr" ]]
  legacy_fixture
  storage_migrate
  backup=$(completed_backup)
  [[ "$(<"${SB_LEGACY_PROJECT_DIR}.user.customer")" == 'outside migration ownership' ]]
  [[ "$(stat -c %a "${SB_LEGACY_PROJECT_DIR}.user.customer")" == 666 && -L "${SB_LEGACY_PROJECT_DIR}.user.link" ]]
  [[ -f "${SB_LEGACY_PROJECT_DIR}.firewall-reconcile.aB12345" && -d "${SB_LEGACY_PROJECT_DIR}.warp-register.aB12345" ]]
  [[ -f "${backup}/legacy-siblings/firewall-reconcile.aB1234" && -f "${backup}/legacy-siblings/warp-register.aB123456/response.json" ]]
  [[ ! -e "${SB_LEGACY_PROJECT_DIR}.firewall-reconcile.aB1234" && ! -e "${SB_LEGACY_PROJECT_DIR}.warp-register.aB123456" ]]
  if storage_needs_migration; then return 1; fi
}

case_stale_unit_references() {
  local reference
  legacy_fixture
  cp "${SINGBOX_SERVICE_LINK_PATH}" "${STORAGE_CASE_DIR}/canonical.service"
  for reference in "ExecStartPre=/usr/bin/test -f ${SB_LEGACY_PROJECT_DIR}/config.json" \
    "ExecStopPost=/usr/bin/test -d ${SB_LEGACY_BACKUP_DIR}"; do
    printf '%s\n' "${reference}" >> "${SINGBOX_SERVICE_LINK_PATH}"
    expect_failure storage_migrate
    grep -q unsupported_legacy_service_reference "${STORAGE_CASE_DIR}/failure.log"
    [[ ! -e "${SB_DATA_ROOT}" && -f "${SB_LEGACY_PROJECT_DIR}/config.json" ]]
    cp "${STORAGE_CASE_DIR}/canonical.service" "${SINGBOX_SERVICE_LINK_PATH}"
  done
  printf '# prior directory: %s\n; prior backup: %s\n' "${SB_LEGACY_PROJECT_DIR}" "${SB_LEGACY_BACKUP_DIR}" >> "${SINGBOX_SERVICE_LINK_PATH}"
  storage_migration_legacy_service_is_supported
}

case_relative_runtime_source() {
  legacy_fixture
  ln -s new-install.sh "${STORAGE_CASE_DIR}/linked-install.sh"
  (
    cd "${STORAGE_CASE_DIR}"
    SB_STORAGE_SCRIPT_SOURCE=./linked-install.sh
    expect_failure storage_migrate
    grep -q invalid_current_runtime "${STORAGE_CASE_DIR}/failure.log"
  )
  [[ ! -e "${SB_DATA_ROOT}" ]]
  (
    cd "${STORAGE_CASE_DIR}"
    SB_STORAGE_SCRIPT_SOURCE=./new-install.sh
    storage_migrate
  )
  [[ -L "${SBV_LINK_PATH}" && ! -e "${SB_LEGACY_PROJECT_DIR}" ]]
  cmp -s "${STORAGE_CASE_DIR}/new-install.sh" "${SBV_BIN_PATH}"
}

case_dns_hosts_paths() {
  local external_hash
  legacy_fixture
  printf '192.0.2.10 managed.fixture.invalid\n' > "${SB_LEGACY_PROJECT_DIR}/dns-hosts"
  printf '198.51.100.8 external.fixture.invalid\n' > "${STORAGE_CASE_DIR}/external/dns-hosts"
  external_hash=$(sha256sum "${STORAGE_CASE_DIR}/external/dns-hosts" | cut -d' ' -f1)
  jq --arg owned "${SB_LEGACY_PROJECT_DIR}/dns-hosts" --arg external "${STORAGE_CASE_DIR}/external/dns-hosts" \
    '.dns={servers:[{type:"hosts",tag:"array-hosts",path:[$owned,$external]},{type:"hosts",tag:"scalar-hosts",path:$owned}],final:"array-hosts"}' \
    "${SB_LEGACY_PROJECT_DIR}/config.json" > "${STORAGE_CASE_DIR}/dns-config.json"
  cp "${STORAGE_CASE_DIR}/dns-config.json" "${SB_LEGACY_PROJECT_DIR}/config.json"
  cp "${STORAGE_CASE_DIR}/dns-config.json" "${SB_LEGACY_PROJECT_DIR}/managed-config.generated.json"
  storage_migrate
  jq -e --arg owned "${SB_PROJECT_DIR}/dns-hosts" --arg external "${STORAGE_CASE_DIR}/external/dns-hosts" \
    '.dns.servers[0].path==[$owned,$external] and .dns.servers[1].path==$owned' "${SINGBOX_CONFIG_FILE}" >/dev/null
  [[ ! -e "${SB_LEGACY_PROJECT_DIR}" && -f "${SB_PROJECT_DIR}/dns-hosts" ]]
  [[ "$(sha256sum "${STORAGE_CASE_DIR}/external/dns-hosts" | cut -d' ' -f1)" == "${external_hash}" ]]
  printf '{"dns":{"servers":[{"type":"hosts","path":"relative-hosts"}]}}\n' > "${STORAGE_CASE_DIR}/relative-hosts.json"
  expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-hosts.json"
  printf '{"dns":{"servers":[{"type":"hosts","path":["/etc/hosts","relative-hosts"]}]}}\n' > "${STORAGE_CASE_DIR}/relative-hosts.json"
  expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-hosts.json"
  printf '{"dns":{"servers":[{"type":"hosts","tag":"default-hosts"}]}}\n' > "${STORAGE_CASE_DIR}/default-hosts.json"
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/default-hosts.json"
}

case_object_masquerade_and_option_paths() {
  local document selector
  legacy_fixture
  mkdir -m 700 "${SB_LEGACY_PROJECT_DIR}/site" "${STORAGE_CASE_DIR}/external/site"
  printf 'owned file masquerade\n' > "${SB_LEGACY_PROJECT_DIR}/site/index.html"
  jq --arg old "${SB_LEGACY_PROJECT_DIR}" --arg external "${STORAGE_CASE_DIR}/external/site" \
    '.inbounds=[{type:"hysteria2",masquerade:{type:"file",directory:($old+"/site")}},
      {type:"hysteria2",masquerade:{type:"file",directory:$external}}] |
      .unrelated={type:"file",directory:($old+"/unchanged")}' \
    "${SB_LEGACY_PROJECT_DIR}/config.json" > "${STORAGE_CASE_DIR}/object-config.json"
  cp "${STORAGE_CASE_DIR}/object-config.json" "${SB_LEGACY_PROJECT_DIR}/config.json"
  cp "${STORAGE_CASE_DIR}/object-config.json" "${SB_LEGACY_PROJECT_DIR}/managed-config.generated.json"
  storage_migrate
  jq -e --arg old "${SB_LEGACY_PROJECT_DIR}" --arg new "${SB_PROJECT_DIR}" --arg external "${STORAGE_CASE_DIR}/external/site" \
    '.inbounds[0].masquerade.directory==($new+"/site") and .inbounds[1].masquerade.directory==$external and
     .unrelated.directory==($old+"/unchanged")' "${SINGBOX_CONFIG_FILE}" >/dev/null
  [[ -f "${SB_PROJECT_DIR}/site/index.html" && ! -e "${SB_LEGACY_PROJECT_DIR}" ]]
  grep -Fqx "Environment=\"XDG_CACHE_HOME=${SB_PROJECT_DIR}/.cache\" \"XDG_CONFIG_HOME=${SB_PROJECT_DIR}/.config\" \"XDG_STATE_HOME=${SB_PROJECT_DIR}/.local/state\" \"XDG_DATA_HOME=${SB_PROJECT_DIR}/.local/share\"" "${SINGBOX_SERVICE_FILE}"
  for document in \
    '{"inbounds":[{"masquerade":{"type":"file","directory":"relative"}}]}' \
    '{"inbounds":[{"masquerade":{"type":"file","directory":""}}]}' \
    '{"inbounds":[{"masquerade":{"type":"file"}}]}' \
    '{"inbounds":[{"masquerade":"file:relative-site"}]}' \
    '{"inbounds":[{"masquerade":"file://"}]}' \
    '{"inbounds":[{"masquerade":"file:"}]}'; do
    printf '%s\n' "${document}" > "${STORAGE_CASE_DIR}/ambiguous-file.json"
    expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/ambiguous-file.json"
  done
  jq -n --arg old "${SB_LEGACY_PROJECT_DIR}" --arg external "${STORAGE_CASE_DIR}/external/site" '
    {certificate:{certificate_directory_path:[$old+"/certificates",$external],store:"system"},
     route:{dhcp_lease_files:[$old+"/leases",$external]},
     services:[{type:"derp",mesh_psk_file:($old+"/mesh.key")},
       {type:"ssm-api",cache_path:($old+"/cache")},
       {type:"ocm",credential_path:($old+"/credentials"),usages_path:($old+"/usages")},
       {type:"ccm",credential_path:$external,usages_path:$external},
       {type:"api",dashboard:($old+"/dashboard")},
       {type:"api",dashboard:{enabled:true,path:($old+"/dashboard")}},
       {type:"api",dashboard:false},{type:"api",dashboard:{enabled:false}}],
     network_namespaces:[{tag:"omitted",path:($old+"/ns")},{tag:"empty",type:"",path:($old+"/ns")},
       {tag:"holder",type:"unshare",pid_file:($old+"/pid")},{tag:($old+"/logical-tag"),path:"stable-name"}],
     inbounds:[{netns:($old+"/namespace-file")},{netns:($old+"/logical-tag")},{netns:"stable-name"}],
     experimental:{cache_file:{enabled:false}}}' > "${STORAGE_CASE_DIR}/option-paths.json"
  storage_rewrite_path_json < "${STORAGE_CASE_DIR}/option-paths.json" > "${STORAGE_CASE_DIR}/option-paths-relocated.json"
  jq -e --arg old "${SB_LEGACY_PROJECT_DIR}" --arg new "${SB_PROJECT_DIR}" --arg external "${STORAGE_CASE_DIR}/external/site" '
    .certificate.certificate_directory_path==[$new+"/certificates",$external] and .certificate.store=="system" and
    .route.dhcp_lease_files==[$new+"/leases",$external] and .services[0].mesh_psk_file==($new+"/mesh.key") and
    .services[1].cache_path==($new+"/cache") and .services[2].credential_path==($new+"/credentials") and
    .services[2].usages_path==($new+"/usages") and .services[3].credential_path==$external and
    .services[3].usages_path==$external and .services[4].dashboard==($new+"/dashboard") and
    .services[5].dashboard.path==($new+"/dashboard") and .services[6].dashboard==false and
    .services[7].dashboard=={enabled:false} and .network_namespaces[0].path==($new+"/ns") and
    .network_namespaces[1].path==($new+"/ns") and .network_namespaces[2].pid_file==($new+"/pid") and
    .network_namespaces[3].path=="stable-name" and .network_namespaces[3].tag==($old+"/logical-tag") and
    .inbounds[0].netns==($new+"/namespace-file") and .inbounds[1].netns==($old+"/logical-tag") and
    .inbounds[2].netns=="stable-name"' "${STORAGE_CASE_DIR}/option-paths-relocated.json" >/dev/null
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/option-paths-relocated.json"
  for selector in '.certificate.certificate_directory_path=["relative"]' '.route.dhcp_lease_files=["relative"]' \
    '.services[0].mesh_psk_file="relative"' '.services[1].cache_path="relative"' \
    '.services[2].credential_path="relative"' '.services[2].usages_path="relative"' \
    '.services[4].dashboard="relative"' '.services[5].dashboard.path="relative"' \
    '.network_namespaces[2].pid_file="relative"'; do
    jq "${selector}" "${STORAGE_CASE_DIR}/option-paths.json" > "${STORAGE_CASE_DIR}/relative-option.json"
    expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/relative-option.json"
  done
  for document in \
    '{"services":[{"type":"api","dashboard":true}]}' \
    '{"services":[{"type":"api","dashboard":""}]}' \
    '{"services":[{"type":"api","dashboard":{"enabled":true}}]}' \
    '{"endpoints":[{"type":"tailscale","state_directory":"/explicit"}]}' \
    '{"certificate_providers":[{"type":"acme"}]}' \
    '{"certificate_providers":[{"type":"cloudflare-origin-ca"}]}' \
    '{"inbounds":[{"tls":{"enabled":true,"acme":{"domain":["fixture.invalid"]}}}]}'; do
    printf '%s\n' "${document}" > "${STORAGE_CASE_DIR}/implicit-option.json"
    expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/implicit-option.json"
  done
  printf '{"services":[{"type":"api","dashboard":false},{"type":"api","dashboard":{"enabled":false}}],"inbounds":[{"tls":{"enabled":false,"acme":{"domain":["fixture.invalid"]},"certificate_provider":{"type":"acme","domain":["fixture.invalid"]}}},{"tls":{"enabled":true,"acme":{"domain":[]}}}],"components":[{"role":"certificate_provider","type":"acme","enabled":false,"config":{"domain":["fixture.invalid"]}},{"role":"service","type":"api","enabled":false,"config":{"dashboard":true}}]}\n' > "${STORAGE_CASE_DIR}/disabled-options.json"
  storage_migration_explicit_paths "${STORAGE_CASE_DIR}/disabled-options.json"
  for selector in '.data_directory=($old+"/../certmagic")' '.data_directory=($old+"/./acme")' \
    '.data_directory=($old|sub("/sing-box-vps$";"/./sing-box-vps/acme"))' \
    '.certificate.certificate_directory_path=[$old+"/../certificates"]' \
    '.dns.servers=[{type:"hosts",path:[$old+"/../hosts"]}]' \
    '.route.rule_set=[{type:"local",path:($old+"/../rules")}]' \
    '.inbounds=[{masquerade:{type:"file",directory:($old+"/../site")}}]' \
    '.services=[{type:"api",dashboard:($old+"/../dashboard")}]' \
    '.log.output=($old+"/../log")' '.experimental.cache_file.path=($old+"/../cache")'; do
    jq -n --arg old "${SB_LEGACY_PROJECT_DIR}" "${selector}" > "${STORAGE_CASE_DIR}/ambiguous-material.json"
    expect_failure storage_migration_explicit_paths "${STORAGE_CASE_DIR}/ambiguous-material.json"
  done
}

case_instance_archive_bytes() {
  local backup known_hash malformed_hash
  legacy_fixture
  mkdir -m 700 "${SB_LEGACY_PROJECT_DIR}/protocols/instances/archive"
  cp "${SB_LEGACY_PROJECT_DIR}/protocols/instances/anytls.json" "${SB_LEGACY_PROJECT_DIR}/protocols/instances/archive/anytls.json"
  printf 'historical non-JSON bytes\000do not parse\n' > "${SB_LEGACY_PROJECT_DIR}/protocols/instances/archive/hy2.json"
  known_hash=$(sha256sum "${SB_LEGACY_PROJECT_DIR}/protocols/instances/archive/anytls.json" | cut -d' ' -f1)
  malformed_hash=$(sha256sum "${SB_LEGACY_PROJECT_DIR}/protocols/instances/archive/hy2.json" | cut -d' ' -f1)
  storage_migrate
  backup=$(completed_backup)
  [[ ! -e "${SB_LEGACY_PROJECT_DIR}" ]]
  [[ "$(sha256sum "${SB_PROJECT_DIR}/protocols/instances/archive/anytls.json" | cut -d' ' -f1)" == "${known_hash}" ]]
  [[ "$(sha256sum "${SB_PROJECT_DIR}/protocols/instances/archive/hy2.json" | cut -d' ' -f1)" == "${malformed_hash}" ]]
  cmp -s "${backup}/legacy-runtime/protocols/instances/archive/anytls.json" "${SB_PROJECT_DIR}/protocols/instances/archive/anytls.json"
  cmp -s "${backup}/legacy-runtime/protocols/instances/archive/hy2.json" "${SB_PROJECT_DIR}/protocols/instances/archive/hy2.json"
  jq -e --arg new "${SB_PROJECT_DIR}" --arg old "${SB_LEGACY_PROJECT_DIR}" \
    '.instances[0].tls.certificate_path==($new+"/cert.pem") and .instances[0].password==($old+"/not-a-path")' \
    "${SB_PROJECT_DIR}/protocols/instances/anytls.json" >/dev/null
}

for case_name in status_read_only migrate_active migrate_stopped_and_history conflict pending untrusted env_no_execution env_literal_roundtrip implicit_module_state check_failure_rollback service_failure_rollback lock_and_handoff library cli_confirmation recover_interrupted recover_after_archive recovery_ownership_conflict precise_path_contexts custom_service_directory manager_only_migration sidecar_ownership stale_unit_references relative_runtime_source dns_hosts_paths object_masquerade_and_option_paths instance_archive_bytes; do
  CASE_NUMBER=$((CASE_NUMBER+1))
  printf 'storage_migration_case=%s\n' "${case_name}"
  (fixture; "case_${case_name}")
done
printf 'storage_migration: passed (%s cases)\n' "${CASE_NUMBER}"
