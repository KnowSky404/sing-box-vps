#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=${SBV_SELINUX_TEST_ROOT:-$(mktemp -d)}
if [[ "${SBV_SELINUX_DEFINITIONS_ONLY:-}" != 1 ]]; then trap 'rm -rf -- "${TEST_ROOT}"' EXIT; fi

fixture() {
  local case_name=$1
  CASE_DIR="${TEST_ROOT}/${case_name}"
  mkdir -p -m 700 "${CASE_DIR}/root.[home]/.sing-box-vps" "${CASE_DIR}/system/bin" "${CASE_DIR}/system/lib" "${CASE_DIR}/system/systemd"
  SB_ROOT_HOME="${CASE_DIR}/root.[home]"
  SB_DATA_ROOT="${SB_ROOT_HOME}/.sing-box-vps"
  SB_PROJECT_DIR="${SB_DATA_ROOT}/runtime"
  SBV_BIN_PATH="${SB_DATA_ROOT}/bin/sbv"
  SINGBOX_BIN_PATH="${SB_DATA_ROOT}/bin/sing-box"
  SINGBOX_SERVICE_FILE="${SB_DATA_ROOT}/systemd/sing-box.service"
  SBV_LINK_PATH="${CASE_DIR}/system/bin/sbv"
  SINGBOX_LINK_PATH="${CASE_DIR}/system/bin/sing-box"
  SINGBOX_SERVICE_LINK_PATH="${CASE_DIR}/system/systemd/sing-box.service"
  SBV_LOG_FILE="${SB_DATA_ROOT}/logs/sbv.log"
  MOCK_MODE=Enforcing
  MOCK_FAIL_CHCON=''
  MOCK_FAIL_RESTORE=''
  MOCK_FAIL_ADD=''
  MOCK_EXTRA_TABLE=''
  printf '[]\n' > "${CASE_DIR}/rules.json"
  printf '{}\n' > "${CASE_DIR}/labels.json"
  : > "${CASE_DIR}/policy.log"
  source "${REPO_ROOT}/src/install/46-storage-layout.sh"
  source "${REPO_ROOT}/src/install/10-script-artifacts.sh"
  source "${REPO_ROOT}/src/install/12-core-install.sh"
  storage_initialize
}
getenforce() { printf '%s\n' "${MOCK_MODE}"; }
semanage() {
  [[ "$1" == fcontext ]] || return 89
  case "$2" in
    -l)
      printf 'SELinux fcontext                                   type               Context\n\n'
      jq -r '.[] | .spec+"   "+(.kind // "all files")+"   "+.context' "${CASE_DIR}/rules.json"
      [[ -z "${MOCK_EXTRA_TABLE}" ]] || printf '%s\n' "${MOCK_EXTRA_TABLE}"
      ;;
    -a)
      [[ "$3" == -t && "$#" == 5 ]] || return 89
      [[ "$5" != "${MOCK_FAIL_ADD}" ]] || return 86
      printf 'add %s %s\n' "$4" "$5" >> "${CASE_DIR}/policy.log"
      jq --arg spec "$5" --arg context "system_u:object_r:$4:s0" '.+[{spec:$spec,context:$context}]' "${CASE_DIR}/rules.json" > "${CASE_DIR}/rules.next"
      mv "${CASE_DIR}/rules.next" "${CASE_DIR}/rules.json"
      ;;
    *) return 89 ;;
  esac
}
mock_context() {
  local path=$1 context
  context=$(jq -r --arg path "${path}" '[.[] | . as $entry | select($path|test("^(?:"+$entry.spec+")$"))] | last | .context // empty' "${CASE_DIR}/rules.json")
  if [[ -n "${context}" ]]; then printf '%s\n' "${context}"
  else
    case "${path}" in
      "${CASE_DIR}/system/bin/"*) printf 'system_u:object_r:bin_t:s0\n' ;;
      "${CASE_DIR}/system/lib/"*) printf 'system_u:object_r:lib_t:s0\n' ;;
      "${CASE_DIR}/system/systemd/"*) printf 'system_u:object_r:systemd_unit_file_t:s0\n' ;;
      *) printf 'system_u:object_r:admin_home_t:s0\n' ;;
    esac
  fi
}
mock_set_label() {
  local path=$1 context=$2 inode
  inode=$(command stat -c '%d:%i' -- "${path}") || return 1
  jq --arg inode "${inode}" --arg context "${context}" '.[$inode]=$context' "${CASE_DIR}/labels.json" > "${CASE_DIR}/labels.next"
  mv "${CASE_DIR}/labels.next" "${CASE_DIR}/labels.json"
}
stat() {
  if [[ "$1" == -c && "$2" == %C ]]; then
    local inode
    inode=$(command stat -c '%d:%i' -- "${@: -1}") || return 1
    jq -r --arg inode "${inode}" '.[$inode] // "system_u:object_r:admin_home_t:s0"' "${CASE_DIR}/labels.json"
  else command stat "$@"
  fi
}
matchpathcon() {
  local expected actual path=${2:-}
  case "$1" in
    -n) mock_context "${path}" ;;
    -V)
      expected=$(mock_context "${path}")
      actual=$(stat -c %C -- "${path}")
      [[ "${actual}" == "${expected}" ]]
      ;;
    *) return 89 ;;
  esac
}
chcon() {
  local context=$1 path=${3:-}
  [[ "$2" == -- ]] || return 89
  [[ "${path}" != "${MOCK_FAIL_CHCON}" ]] || return 85
  printf 'chcon %s\n' "${path}" >> "${CASE_DIR}/policy.log"
  mock_set_label "${path}" "${context}"
}
restorecon() {
  local path=${3:-} item context
  [[ "$2" == -- ]] || return 89
  [[ "${path}" != "${MOCK_FAIL_RESTORE}" ]] || return 84
  printf 'restorecon %s\n' "${path}" >> "${CASE_DIR}/policy.log"
  if [[ "$1" == -RF ]]; then
    while IFS= read -r -d '' item; do
      context=$(mock_context "${item}") || return 1
      mock_set_label "${item}" "${context}" || return 1
    done < <(find "${path}" -print0)
  else
    context=$(mock_context "${path}") || return 1
    mock_set_label "${path}" "${context}"
  fi
}
expect_failure() { if "$@" > "${CASE_DIR}/failure.stdout" 2> "${CASE_DIR}/failure.stderr"; then printf 'expected failure: %s\n' "$1" >&2; return 1; fi; }

# A child shell uses the same fixtures with its real argv[0] set to SBV_BIN_PATH.
if [[ "${SBV_SELINUX_DEFINITIONS_ONLY:-}" == 1 ]]; then return 0; fi

(
  fixture disabled
  MOCK_MODE=Disabled
  semanage() { return 91; }
  storage_selinux_prepare
  storage_selinux_label /outside/unowned
  [[ ! -s "${CASE_DIR}/policy.log" ]]
)
(
  fixture missing_tools
  command() {
    if [[ "${1:-}" == -v && "${2:-}" == semanage ]]; then return 1; fi
    builtin command "$@"
  }
  expect_failure storage_selinux_prepare
  grep -Fq 'semanage' "${CASE_DIR}/failure.stderr"
  [[ ! -s "${CASE_DIR}/policy.log" ]]
)
(
  fixture detection_failure
  getenforce() { return 1; }
  expect_failure storage_selinux_prepare
  [[ ! -s "${CASE_DIR}/policy.log" ]]
)
(
  fixture idempotence
  storage_selinux_prepare
  [[ "$(jq length "${CASE_DIR}/rules.json")" == 4 ]]
  storage_selinux_prepare
  [[ "$(jq length "${CASE_DIR}/rules.json")" == 4 ]]
  [[ "$(grep -c '^add ' "${CASE_DIR}/policy.log")" == 4 ]]
  [[ "$(mock_context "${SB_DATA_ROOT}/bin/new")" == system_u:object_r:bin_t:s0 ]]
  [[ "$(mock_context "${CASE_DIR}/root.XhomeY/.sing-box-vps/bin/new")" == system_u:object_r:admin_home_t:s0 ]]
  MOCK_MODE=Permissive
  storage_selinux_prepare
)
(
  fixture conflicts
  expression="$(storage_selinux_root_regex)/bin(/.*)?"
  jq -cn --arg spec "${expression}" '[{spec:$spec,context:"system_u:object_r:admin_home_t:s0"}]' > "${CASE_DIR}/rules.json"
  expect_failure storage_selinux_prepare
  [[ "$(jq length "${CASE_DIR}/rules.json")" == 1 && ! -s "${CASE_DIR}/policy.log" ]]
  printf '[]\n' > "${CASE_DIR}/rules.json"
  MOCK_EXTRA_TABLE="SELinux Local fcontext Equivalence
${SB_DATA_ROOT} = /var/lib/foreign"
  expect_failure storage_selinux_prepare
  [[ ! -s "${CASE_DIR}/policy.log" ]]
  MOCK_EXTRA_TABLE='unexpected malformed policy listing'
  expect_failure storage_selinux_prepare
  [[ ! -s "${CASE_DIR}/policy.log" ]]
  MOCK_EXTRA_TABLE=''
  jq -cn --arg spec "${CASE_DIR}/.*" '[{spec:$spec,context:"system_u:object_r:admin_home_t:s0"}]' > "${CASE_DIR}/rules.json"
  expect_failure storage_selinux_prepare
  [[ ! -s "${CASE_DIR}/policy.log" ]]
)
(
  fixture existing_child_mapping
  expression="$(storage_selinux_root_regex)/bin(/.*)?"
  jq -cn --arg spec "${expression}" '[{spec:$spec,context:"system_u:object_r:bin_t:s0"}]' > "${CASE_DIR}/rules.json"
  before=$(sha256sum < "${CASE_DIR}/rules.json")
  [[ "$(mock_context "${SINGBOX_BIN_PATH}")" == system_u:object_r:bin_t:s0 ]]
  expect_failure storage_selinux_prepare
  [[ "$(sha256sum < "${CASE_DIR}/rules.json")" == "${before}" && ! -s "${CASE_DIR}/policy.log" ]]
  [[ "$(mock_context "${SINGBOX_BIN_PATH}")" == system_u:object_r:bin_t:s0 ]]
)
(
  fixture failed_prepare
  MOCK_FAIL_ADD="$(storage_selinux_root_regex)/lib(/.*)?"
  expect_failure storage_selinux_prepare
  [[ "$(jq length "${CASE_DIR}/rules.json")" == 2 ]]
  MOCK_FAIL_ADD=''
  storage_selinux_prepare
  [[ "$(jq length "${CASE_DIR}/rules.json")" == 4 ]]
  MOCK_FAIL_RESTORE="${SB_DATA_ROOT}/bin"
  expect_failure storage_selinux_prepare
  MOCK_FAIL_RESTORE=''
  storage_selinux_prepare
)
(
  fixture label_update_rollback
  storage_selinux_prepare
  printf 'original core\n' > "${SINGBOX_BIN_PATH}"
  printf 'updated core\n' > "${CASE_DIR}/new-core"
  cp "${SINGBOX_BIN_PATH}" "${CASE_DIR}/core.before"
  mock_set_label "${SINGBOX_BIN_PATH}" system_u:object_r:admin_home_t:s0
  replace_singbox_binary_atomically "${CASE_DIR}/new-core"
  [[ "$(cat "${SINGBOX_BIN_PATH}")" == 'updated core' ]]
  matchpathcon -V "${SINGBOX_BIN_PATH}"
  replace_singbox_binary_atomically "${CASE_DIR}/core.before"
  [[ "$(cat "${SINGBOX_BIN_PATH}")" == 'original core' ]]
  matchpathcon -V "${SINGBOX_BIN_PATH}"
  candidate=$(storage_mktemp "${SB_DATA_ROOT}/bin/.sbv-candidate.XXXXXXXX")
  printf 'candidate\n' > "${candidate}"
  reset_sbv_update_context
  SBV_UPDATE_CANDIDATE_PATH=${candidate}
  commit_sbv_candidate
  matchpathcon -V "${SBV_BIN_PATH}"
  mock_set_label "${SBV_BIN_PATH}" system_u:object_r:admin_home_t:s0
  storage_publish_system_links sbv
  matchpathcon -V "${SBV_BIN_PATH}"
  candidate=$(storage_mktemp "${SB_DATA_ROOT}/bin/.sbv-candidate.XXXXXXXX")
  printf 'failed candidate\n' > "${candidate}"
  reset_sbv_update_context
  SBV_UPDATE_CANDIDATE_PATH=${candidate}
  MOCK_FAIL_CHCON=${candidate}
  expect_failure commit_sbv_candidate
  [[ "$(cat "${SBV_BIN_PATH}")" == candidate ]]
  MOCK_FAIL_CHCON=''
  SBV_UPDATE_TARGET_EXISTS=true
  SBV_UPDATE_BACKUP_PATH="${CASE_DIR}/core.before"
  SBV_UPDATE_TARGET_MODE=755
  SBV_UPDATE_TARGET_UID=0
  SBV_UPDATE_TARGET_GID=0
  restore_sbv_backup
  [[ "$(cat "${SBV_BIN_PATH}")" == 'original core' ]]
  matchpathcon -V "${SBV_BIN_PATH}"
)
(
  fixture rpm_dependencies
  OS_NAME=centos
  log_info() { :; }
  log_success() { :; }
  run_with_progress() { shift; printf '%s\n' "$*" >> "${CASE_DIR}/packages.log"; }
  OS_VERSION=7.9
  install_dependencies
  grep -Fqx 'yum install -y policycoreutils policycoreutils-python' "${CASE_DIR}/packages.log"
  [[ "$(wc -l < "${CASE_DIR}/packages.log")" == 2 ]]
  : > "${CASE_DIR}/packages.log"
  OS_NAME=almalinux
  OS_VERSION=9.5
  install_dependencies
  grep -Fqx 'yum install -y policycoreutils policycoreutils-python-utils' "${CASE_DIR}/packages.log"
  [[ "$(wc -l < "${CASE_DIR}/packages.log")" == 2 ]]
  : > "${CASE_DIR}/packages.log"
  MOCK_MODE=Disabled
  install_dependencies
  [[ "$(wc -l < "${CASE_DIR}/packages.log")" == 1 ]]
  if grep -Fq policycoreutils "${CASE_DIR}/packages.log"; then exit 1; fi
  [[ ! -s "${CASE_DIR}/policy.log" ]]
)
(
  fixture migration_role_and_system_restore
  storage_selinux_prepare
  candidate=$(storage_mktemp)
  printf 'unit candidate\n' > "${candidate}"
  storage_selinux_label "${candidate}" "${SINGBOX_SERVICE_FILE}"
  [[ "$(stat -c %C "${candidate}")" == system_u:object_r:systemd_unit_file_t:s0 ]]
  storage_selinux_label "${candidate}" "${SINGBOX_LINK_PATH}"
  mv "${candidate}" "${SINGBOX_LINK_PATH}"
  storage_selinux_restore_system_path "${SINGBOX_LINK_PATH}"
  matchpathcon -V "${SINGBOX_LINK_PATH}"
  expect_failure storage_selinux_restore_system_path "${CASE_DIR}/foreign"
  candidate=$(storage_mktemp)
  ln -s "${CASE_DIR}/outside" "${SB_PROJECT_DIR}/external"
  expect_failure storage_selinux_label "${SB_PROJECT_DIR}"
  expect_failure storage_selinux_label "${candidate}" "${SB_DATA_ROOT}/../outside"
)
(
  fixture noop_transaction
  SCRIPT_VERSION=$(extract_sbv_script_version "${REPO_ROOT}/install.sh")
  PROJECT_AUTHOR=KnowSky404
  PROJECT_URL=https://github.com/KnowSky404/sing-box-vps
  SBV_SCRIPT_MIN_SIZE=1024
  SBV_CURL_STDERR_MAX_BYTES=4096
  storage_selinux_prepare
  cp "${REPO_ROOT}/install.sh" "${SBV_BIN_PATH}"
  chmod 755 "${SBV_BIN_PATH}"
  inode_before=$(stat -c %i "${SBV_BIN_PATH}")
  mock_set_label "${SBV_BIN_PATH}" system_u:object_r:admin_home_t:s0
  sbv_update_transaction sbv_update file "${REPO_ROOT}/install.sh"
  [[ "${SBV_UPDATE_NOOP}" == true && "$(stat -c %i "${SBV_BIN_PATH}")" == "${inode_before}" ]]
  matchpathcon -V "${SBV_BIN_PATH}"
)
SBV_SELINUX_TEST_ROOT=${TEST_ROOT} SBV_SELINUX_DEFINITIONS_ONLY=1 "${BASH}" -c '
  source "$1"
  fixture source_fastpath
  storage_selinux_prepare
  cp "${REPO_ROOT}/install.sh" "${SBV_BIN_PATH}"
  chmod 755 "${SBV_BIN_PATH}"
  [[ "$0" == "${SBV_BIN_PATH}" ]]
  mock_set_label "${SBV_BIN_PATH}" system_u:object_r:admin_home_t:s0
  ensure_sbv_command_installed
  matchpathcon -V "${SBV_BIN_PATH}"
' "${TEST_ROOT}/source_fastpath/root.[home]/.sing-box-vps/bin/sbv" "${REPO_ROOT}/tests/storage_selinux.sh"
printf 'SELinux storage rules, conflicts, candidate publication, drift and rollback checks passed\n'
