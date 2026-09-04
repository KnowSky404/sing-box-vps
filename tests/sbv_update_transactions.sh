#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

TESTABLE_INSTALL="${TMP_DIR}/install-testable.sh"
TARGET_DIR="${TMP_DIR}/bin"
TARGET_PATH="${TARGET_DIR}/sbv"
PROJECT_DIR="${TMP_DIR}/project"
VALID_CANDIDATE="${TMP_DIR}/candidate-valid.sh"
OLD_SCRIPT="${TMP_DIR}/candidate-old.sh"
LOW_SCRIPT="${TMP_DIR}/candidate-low.sh"
INVALID_VERSION_SCRIPT="${TMP_DIR}/candidate-invalid-version.sh"
IDENTITY_SCRIPT="${TMP_DIR}/candidate-identity.sh"
IDENTITY_URL_SCRIPT="${TMP_DIR}/candidate-identity-url.sh"
DUPLICATE_VERSION_SCRIPT="${TMP_DIR}/candidate-duplicate-version.sh"
SYNTAX_SCRIPT="${TMP_DIR}/candidate-syntax.sh"
MEDIA_TARGET="${TMP_DIR}/media-check/region_restriction_check.sh"
TEST_TARGET_UID=$(id -u)
TEST_TARGET_GID=$(id -g)
nobody_uid=''
nobody_gid=''
if (( EUID == 0 )) && nobody_uid=$(id -u nobody 2>/dev/null) && \
  nobody_gid=$(id -g nobody 2>/dev/null); then
  owner_probe="${TMP_DIR}/owner-probe"
  : > "${owner_probe}"
  if chown "${nobody_uid}:${nobody_gid}" "${owner_probe}" 2>/dev/null; then
    TEST_TARGET_UID=${nobody_uid}
    TEST_TARGET_GID=${nobody_gid}
  fi
  rm -f "${owner_probe}"
fi

sed \
  -e "s|readonly SB_PROJECT_DIR=\"/root/sing-box-vps\"|readonly SB_PROJECT_DIR=\"${PROJECT_DIR}\"|" \
  -e "s|readonly SINGBOX_BIN_PATH=\"/usr/local/bin/sing-box\"|readonly SINGBOX_BIN_PATH=\"${TARGET_DIR}/sing-box\"|" \
  -e "s|readonly SBV_BIN_PATH=\"/usr/local/bin/sbv\"|readonly SBV_BIN_PATH=\"${TARGET_PATH}\"|" \
  -e "s|readonly SINGBOX_SERVICE_FILE=\"/etc/systemd/system/sing-box.service\"|readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"|" \
  -e "s|readonly SB_MEDIA_CHECK_DIR=\"\${SB_PROJECT_DIR}/media-check\"|readonly SB_MEDIA_CHECK_DIR=\"${TMP_DIR}/media-check\"|" \
  -e "s|readonly SB_MEDIA_CHECK_SCRIPT=\"\${SB_MEDIA_CHECK_DIR}/region_restriction_check.sh\"|readonly SB_MEDIA_CHECK_SCRIPT=\"${MEDIA_TARGET}\"|" \
  "${REPO_ROOT}/install.sh" > "${TESTABLE_INSTALL}"
main_guard='[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"'
grep -Fqx "${main_guard}" "${TESTABLE_INSTALL}" || {
  printf 'test fixture could not find the install.sh main guard\n' >&2
  exit 1
}
if ! sed -i '/BASH_SOURCE.*main/d' "${TESTABLE_INSTALL}"; then
  printf 'test fixture could not remove the install.sh main guard\n' >&2
  exit 1
fi
if grep -Fqx "${main_guard}" "${TESTABLE_INSTALL}"; then
  printf 'test fixture still executes install.sh main\n' >&2
  exit 1
fi

grep -Fqx "readonly SBV_BIN_PATH=\"${TARGET_PATH}\"" "${TESTABLE_INSTALL}" || {
  printf 'test fixture failed to isolate SBV_BIN_PATH\n' >&2
  exit 1
}
grep -Fqx "readonly SINGBOX_BIN_PATH=\"${TARGET_DIR}/sing-box\"" "${TESTABLE_INSTALL}" || {
  printf 'test fixture failed to isolate SINGBOX_BIN_PATH\n' >&2
  exit 1
}
grep -Fqx "readonly SINGBOX_SERVICE_FILE=\"${TMP_DIR}/sing-box.service\"" "${TESTABLE_INSTALL}" || {
  printf 'test fixture failed to isolate SINGBOX_SERVICE_FILE\n' >&2
  exit 1
}
grep -Fqx "readonly SB_PROJECT_DIR=\"${PROJECT_DIR}\"" "${TESTABLE_INSTALL}" || {
  printf 'test fixture failed to isolate SB_PROJECT_DIR\n' >&2
  exit 1
}
grep -Fqx "readonly SB_MEDIA_CHECK_DIR=\"${TMP_DIR}/media-check\"" "${TESTABLE_INSTALL}" || {
  printf 'test fixture failed to isolate SB_MEDIA_CHECK_DIR\n' >&2
  exit 1
}
grep -Fqx "readonly SB_MEDIA_CHECK_SCRIPT=\"${MEDIA_TARGET}\"" "${TESTABLE_INSTALL}" || {
  printf 'test fixture failed to isolate media script path\n' >&2
  exit 1
}

mkdir -p "${TARGET_DIR}" "${PROJECT_DIR}"
sed 's/readonly SCRIPT_VERSION="[0-9][0-9]*"/readonly SCRIPT_VERSION="2099010101"/' \
  "${REPO_ROOT}/install.sh" > "${VALID_CANDIDATE}"
sed 's/readonly SCRIPT_VERSION="[0-9][0-9]*"/readonly SCRIPT_VERSION="2026010101"/' \
  "${REPO_ROOT}/install.sh" > "${OLD_SCRIPT}"
sed 's/readonly SCRIPT_VERSION="[0-9][0-9]*"/readonly SCRIPT_VERSION="1999010101"/' \
  "${REPO_ROOT}/install.sh" > "${LOW_SCRIPT}"
sed 's/readonly SCRIPT_VERSION="[0-9][0-9]*"/readonly SCRIPT_VERSION="not-a-version"/' \
  "${REPO_ROOT}/install.sh" > "${INVALID_VERSION_SCRIPT}"
sed 's/readonly PROJECT_AUTHOR="KnowSky404"/readonly PROJECT_AUTHOR="unexpected-author"/' \
  "${VALID_CANDIDATE}" > "${IDENTITY_SCRIPT}"
sed 's|readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"|readonly PROJECT_URL="https://example.invalid/wrong-project"|' \
  "${VALID_CANDIDATE}" > "${IDENTITY_URL_SCRIPT}"
{
  cat "${VALID_CANDIDATE}"
  printf 'readonly SCRIPT_VERSION="2099010101"\n'
} > "${DUPLICATE_VERSION_SCRIPT}"
{
  cat "${VALID_CANDIDATE}"
  printf '\nif (\n'
} > "${SYNTAX_SCRIPT}"

grep -Fqx 'readonly SCRIPT_VERSION="2099010101"' "${VALID_CANDIDATE}" || {
  printf 'failed to create valid candidate version fixture\n' >&2
  exit 1
}
grep -Fqx 'readonly SCRIPT_VERSION="2026010101"' "${OLD_SCRIPT}" || {
  printf 'failed to create old target fixture\n' >&2
  exit 1
}
grep -Fqx 'readonly SCRIPT_VERSION="1999010101"' "${LOW_SCRIPT}" || {
  printf 'failed to create downgrade fixture\n' >&2
  exit 1
}
grep -Fqx 'readonly SCRIPT_VERSION="not-a-version"' "${INVALID_VERSION_SCRIPT}" || {
  printf 'failed to create invalid version fixture\n' >&2
  exit 1
}
grep -Fqx 'readonly PROJECT_AUTHOR="unexpected-author"' "${IDENTITY_SCRIPT}" || {
  printf 'failed to create identity fixture\n' >&2
  exit 1
}
grep -Fqx 'readonly PROJECT_URL="https://example.invalid/wrong-project"' "${IDENTITY_URL_SCRIPT}" || {
  printf 'failed to create URL identity fixture\n' >&2
  exit 1
}
[[ "$(grep -Ec '^[[:space:]]*readonly[[:space:]]+SCRIPT_VERSION="2099010101"[[:space:]]*$' "${DUPLICATE_VERSION_SCRIPT}")" == '2' ]] || {
  printf 'failed to create duplicate version fixture\n' >&2
  exit 1
}

export SYNTAX_SCRIPT IDENTITY_SCRIPT IDENTITY_URL_SCRIPT INVALID_VERSION_SCRIPT \
  DUPLICATE_VERSION_SCRIPT LOW_SCRIPT

cat > "${TARGET_DIR}/curl" <<'EOF'
#!/usr/bin/env bash

set -u

output_file=""
connect_timeout=""
max_time=""
retry_count=""
retry_delay=""
url=""
while (($# > 0)); do
  case "$1" in
    -o|--output)
      output_file=${2:-}
      shift 2
      ;;
    --connect-timeout)
      connect_timeout=${2:-}
      shift 2
      ;;
    --max-time)
      max_time=${2:-}
      shift 2
      ;;
    --retry)
      retry_count=${2:-}
      shift 2
      ;;
    --retry-delay)
      retry_delay=${2:-}
      shift 2
      ;;
    *)
      if [[ "$1" == http* ]]; then
        url=$1
      fi
      shift
      ;;
  esac
done

if [[ -n "${output_file}" ]] && {
  [[ "${connect_timeout}" == '10' ]] &&
  [[ "${max_time}" == '60' ]] &&
  [[ "${retry_count}" == '2' ]] &&
  [[ "${retry_delay}" == '1' ]] &&
  [[ "${url}" == *'/install.sh' || "${url}" == *'/check.sh' ]]
}; then
  :
elif [[ -n "${output_file}" ]]; then
  printf 'fake curl received unexpected transaction arguments\n' >&2
  exit 97
fi

output_dir=${output_file%/*}
output_name=${output_file##*/}
if [[ -n "${output_file}" ]]; then
  case "${url}" in
    */install.sh)
      [[ "${output_dir}" == "${TARGET_DIR}" && "${output_file}" != "${TARGET_PATH}" && \
        "${output_name}" == .sbv-candidate.* ]] || {
        printf 'sbv download did not use a same-directory candidate\n' >&2
        exit 98
      }
      ;;
    */check.sh)
      media_dir=${MEDIA_TARGET%/*}
      [[ "${output_dir}" == "${media_dir}" && "${output_file}" != "${MEDIA_TARGET}" && \
        "${output_name}" == .region_restriction_check.sh.candidate.* ]] || {
        printf 'media download did not use a same-directory candidate\n' >&2
        exit 98
      }
      ;;
  esac
fi

if [[ -z "${output_file}" ]]; then
  if [[ "${FAKE_CURL_MODE:-}" == "status-unavailable" ]]; then
    printf 'simulated status lookup failure\n' >&2
    exit 6
  fi
  printf 'readonly SCRIPT_VERSION="2099010101"\n'
  exit 0
fi

case "${FAKE_CURL_MODE:-valid}" in
  dns)
    printf 'curl: (6) Could not resolve host https://user:pass@example.invalid/?token=secret&key=secret-key Authorization: Bearer secret-token\n' >&2
    exit 6
    ;;
  connect)
    printf 'curl: (7) Failed to connect\n' >&2
    exit 7
    ;;
  timeout)
    printf 'curl: (28) Operation timed out\n' >&2
    exit 28
    ;;
  partial)
    printf '#!/usr/bin/env bash\npartial transfer\n' > "${output_file}"
    printf 'curl: (18) transfer closed with bytes remaining\n' >&2
    exit 18
    ;;
  empty)
    : > "${output_file}"
    exit 0
    ;;
  html)
    {
      printf '#!/usr/bin/env bash\n<html><body>gateway error</body></html>\n'
      printf '%*s\n' 1200 ''
    } > "${output_file}"
    exit 0
    ;;
  syntax)
    cp "${SYNTAX_SCRIPT}" "${output_file}"
    exit 0
    ;;
  identity)
    cp "${IDENTITY_SCRIPT}" "${output_file}"
    exit 0
    ;;
  identity-url)
    cp "${IDENTITY_URL_SCRIPT}" "${output_file}"
    exit 0
    ;;
  duplicate-version)
    cp "${DUPLICATE_VERSION_SCRIPT}" "${output_file}"
    exit 0
    ;;
  invalid-version)
    cp "${INVALID_VERSION_SCRIPT}" "${output_file}"
    exit 0
    ;;
  lower)
    cp "${LOW_SCRIPT}" "${output_file}"
    exit 0
    ;;
  signal-int|signal-term|signal-hup)
    case "${FAKE_CURL_MODE}" in
      signal-int) kill -INT "${PPID}"; exit 130 ;;
      signal-term) kill -TERM "${PPID}"; exit 143 ;;
      signal-hup) kill -HUP "${PPID}"; exit 129 ;;
    esac
    ;;
  valid|*)
    cp "${FAKE_CURL_SOURCE:?FAKE_CURL_SOURCE is required}" "${output_file}"
    exit 0
    ;;
esac
EOF
chmod +x "${TARGET_DIR}/curl"

cat > "${TARGET_DIR}/hostname" <<'EOF'
#!/usr/bin/env bash
printf 'test-host\n'
EOF
chmod +x "${TARGET_DIR}/hostname"

export PATH="${TARGET_DIR}:${PATH}"
export TARGET_DIR TARGET_PATH MEDIA_TARGET

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" == *"${needle}"* ]] || fail "expected output to contain ${needle}, got: ${haystack}"
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  [[ "${haystack}" != *"${needle}"* ]] || fail "did not expect output to contain ${needle}"
}

assert_status_nonzero() {
  local status=$1
  [[ "${status}" -ne 0 ]] || fail "expected non-zero status"
}

assert_target_matches() {
  local expected=$1
  [[ -f "${TARGET_PATH}" && ! -L "${TARGET_PATH}" ]] || fail 'target is not a regular non-symlink file'
  cmp -s "${expected}" "${TARGET_PATH}" || fail "target does not match ${expected}"
  [[ -x "${TARGET_PATH}" ]] || fail "target is not executable"
}

capture_file_attributes() {
  local file=$1

  printf '%s:%s:%s\n' \
    "$(stat -c '%a' "${file}")" \
    "$(stat -c '%u' "${file}")" \
    "$(stat -c '%g' "${file}")"
}

assert_file_attributes() {
  local file=$1
  local expected=$2
  local actual

  [[ -f "${file}" && ! -L "${file}" ]] || fail "${file} is not a regular non-symlink file"
  actual=$(capture_file_attributes "${file}")
  [[ "${expected}" == "${actual}" ]] || fail "${file} metadata changed: ${actual} != ${expected}"
}

assert_no_update_artifacts() {
  local artifacts
  artifacts=$(find "${TMP_DIR}" -mindepth 1 \( -name '.sbv-*' -o -name '.sbv.*' \) -print)
  [[ -z "${artifacts}" ]] || fail "unexpected update artifacts: ${artifacts}"
}

prepare_existing_target() {
  local source_file=$1

  cp "${source_file}" "${TARGET_PATH}"
  chmod 0711 "${TARGET_PATH}"
  chown "${TEST_TARGET_UID}:${TEST_TARGET_GID}" "${TARGET_PATH}" || \
    fail 'could not prepare the non-default target owner'
}

expected_error_code() {
  case "$1" in
    dns) printf 'download_dns_failure' ;;
    connect) printf 'download_connection_failed' ;;
    timeout) printf 'download_timeout' ;;
    partial) printf 'download_partial_transfer' ;;
    empty) printf 'candidate_too_small' ;;
    html) printf 'candidate_html' ;;
    syntax) printf 'candidate_syntax_invalid' ;;
    identity|identity-url) printf 'candidate_identity_mismatch' ;;
    invalid-version|duplicate-version) printf 'candidate_version_invalid' ;;
    lower) printf 'candidate_version_downgrade' ;;
    *) printf 'update_failed' ;;
  esac
}

expected_error_stage() {
  case "$1" in
    dns|connect|timeout|partial) printf 'download' ;;
    *) printf 'validate' ;;
  esac
}

expected_command_exit_code() {
  case "$1" in
    dns) printf '6' ;;
    connect) printf '7' ;;
    timeout) printf '28' ;;
    partial) printf '18' ;;
    *) printf '1' ;;
  esac
}

assert_error_context() {
  local output=$1
  local operation=$2
  local stage=$3
  local code=$4
  local command_exit_code=$5
  local target_path=$6

  assert_contains "${output}" "operation: ${operation}"
  assert_contains "${output}" "stage: ${stage}"
  assert_contains "${output}" "code: ${code}"
  assert_contains "${output}" "command_exit_code: ${command_exit_code}"
  assert_contains "${output}" 'hint:'
  assert_contains "${output}" 'changed:'
  assert_contains "${output}" 'rollback_attempted:'
  assert_contains "${output}" 'rolled_back:'
  assert_contains "${output}" 'rollback_ok:'
  assert_contains "${output}" 'manual_intervention_required:'
  assert_contains "${output}" "target_path: ${target_path}"
  assert_contains "${output}" 'log_file:'
}

run_update_case() {
  local mode=$1
  local target_source=$2
  local output status

  rm -f "${TARGET_PATH}"
  rm -rf "${TARGET_DIR}/.sbv-update.lock"
  if [[ "${target_source}" != "missing" ]]; then
    prepare_existing_target "${target_source}"
    printf '%s:%s:%s:%s\n' \
      "$(stat -c '%i' "${TARGET_PATH}")" \
      "$(stat -c '%a' "${TARGET_PATH}")" \
      "$(stat -c '%u' "${TARGET_PATH}")" \
      "$(stat -c '%g' "${TARGET_PATH}")" > "${TMP_DIR}/expected-target-meta"
    stat -c '%i' "${TARGET_PATH}" > "${TMP_DIR}/expected-target-inode"
  fi

  set +e
  output=$(FAKE_CURL_MODE="${mode}" FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
    bash -c "source '${TESTABLE_INSTALL}'; manual_update_script" 2>&1)
  status=$?
  set -e

  printf '%s\n' "${output}"
  printf '%s\n' "${status}" > "${TMP_DIR}/last-status"
}

for mode in dns connect timeout partial empty html syntax identity identity-url invalid-version duplicate-version lower; do
  run_update_case "${mode}" "${OLD_SCRIPT}" > "${TMP_DIR}/${mode}.output"
  status=$(<"${TMP_DIR}/last-status")
  assert_status_nonzero "${status}"
  [[ -f "${TARGET_PATH}" && ! -L "${TARGET_PATH}" ]] || fail "${mode} left a non-regular target"
  cmp -s "${OLD_SCRIPT}" "${TARGET_PATH}" || fail "${mode} changed the target"
  expected_meta=$(<"${TMP_DIR}/expected-target-meta")
  actual_meta=$(printf '%s:%s:%s:%s\n' \
    "$(stat -c '%i' "${TARGET_PATH}")" \
    "$(stat -c '%a' "${TARGET_PATH}")" \
    "$(stat -c '%u' "${TARGET_PATH}")" \
    "$(stat -c '%g' "${TARGET_PATH}")")
  [[ "${expected_meta}" == "${actual_meta}" ]] || fail "${mode} changed target metadata"
  mode_output=$(<"${TMP_DIR}/${mode}.output")
  assert_contains "${mode_output}" 'changed: false'
  assert_error_context "${mode_output}" 'sbv_update' \
    "$(expected_error_stage "${mode}")" \
    "$(expected_error_code "${mode}")" \
    "$(expected_command_exit_code "${mode}")" \
    "${TARGET_PATH}"
  if [[ "${mode}" == 'dns' ]]; then
    assert_contains "${mode_output}" '[REDACTED]'
    assert_not_contains "${mode_output}" 'secret-token'
    assert_not_contains "${mode_output}" 'secret-key'
    assert_not_contains "${mode_output}" 'https://user:pass@'
    [[ -f "${PROJECT_DIR}/sbv.log" ]] || fail 'self-update error was not logged'
    log_content=$(<"${PROJECT_DIR}/sbv.log")
    assert_not_contains "${log_content}" 'secret-token'
    assert_not_contains "${log_content}" 'secret-key'
  fi
  assert_no_update_artifacts
done

rm -f "${TARGET_PATH}"
ln -s "${OLD_SCRIPT}" "${TARGET_PATH}"
symlink_target_hash=$(sha256sum "${OLD_SCRIPT}" | awk '{print $1}')
symlink_target_inode=$(stat -c '%i' "${OLD_SCRIPT}")
set +e
symlink_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; manual_update_script" 2>&1)
symlink_status=$?
set -e
assert_status_nonzero "${symlink_status}"
[[ -L "${TARGET_PATH}" ]] || fail 'symlink target was not preserved after rejection'
[[ "$(readlink "${TARGET_PATH}")" == "${OLD_SCRIPT}" ]] || fail 'symlink target changed after rejection'
[[ "$(sha256sum "${OLD_SCRIPT}" | awk '{print $1}')" == "${symlink_target_hash}" ]] || \
  fail 'symlink referent content changed after rejection'
[[ "$(stat -c '%i' "${OLD_SCRIPT}")" == "${symlink_target_inode}" ]] || \
  fail 'symlink referent inode changed after rejection'
assert_contains "${symlink_output}" 'target_symlink_unsupported'
assert_error_context "${symlink_output}" 'sbv_update' 'precheck' \
  'target_symlink_unsupported' '1' "${TARGET_PATH}"
rm -f "${TARGET_PATH}"
assert_no_update_artifacts

prepare_existing_target "${VALID_CANDIDATE}"
no_op_attributes_before=$(capture_file_attributes "${TARGET_PATH}")
before_inode=$(stat -c '%i' "${TARGET_PATH}")
set +e
no_op_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; manual_update_script" 2>&1)
no_op_status=$?
set -e
printf '%s\n' "${no_op_output}" > "${TMP_DIR}/no-op.output"
[[ "${no_op_status}" -eq 0 ]] || fail "healthy same-version update was not a no-op"
after_inode=$(stat -c '%i' "${TARGET_PATH}")
[[ "${before_inode}" == "${after_inode}" ]] || fail "same-version update replaced a healthy target"
assert_contains "$(<"${TMP_DIR}/no-op.output")" 'no-op'
assert_target_matches "${VALID_CANDIDATE}"
assert_file_attributes "${TARGET_PATH}" "${no_op_attributes_before}"
assert_no_update_artifacts

run_update_case valid "${OLD_SCRIPT}" > "${TMP_DIR}/success.output"
status=$(<"${TMP_DIR}/last-status")
[[ "${status}" -eq 0 ]] || fail "valid update failed"
assert_target_matches "${VALID_CANDIDATE}"
success_old_inode=$(<"${TMP_DIR}/expected-target-inode")
success_new_inode=$(stat -c '%i' "${TARGET_PATH}")
[[ "${success_old_inode}" != "${success_new_inode}" ]] || fail 'successful update did not replace the target inode'
success_expected_meta=$(<"${TMP_DIR}/expected-target-meta")
success_expected_attributes=${success_expected_meta#*:}
assert_file_attributes "${TARGET_PATH}" "${success_expected_attributes}"
assert_contains "$(<"${TMP_DIR}/success.output")" 'changed: true'
assert_no_update_artifacts

prepare_existing_target "${OLD_SCRIPT}"
commit_old_hash=$(sha256sum "${TARGET_PATH}" | awk '{print $1}')
commit_old_attributes=$(capture_file_attributes "${TARGET_PATH}")
set +e
commit_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; commit_sbv_candidate() { SBV_UPDATE_STAGE=commit; return 73; }; manual_update_script" 2>&1)
commit_status=$?
set -e
assert_status_nonzero "${commit_status}"
[[ "$(sha256sum "${TARGET_PATH}" | awk '{print $1}')" == "${commit_old_hash}" ]] || fail 'commit failure changed the target'
assert_file_attributes "${TARGET_PATH}" "${commit_old_attributes}"
assert_contains "${commit_output}" 'changed: false'
assert_error_context "${commit_output}" 'sbv_update' 'commit' 'update_failed' '73' "${TARGET_PATH}"
assert_no_update_artifacts

prepare_existing_target "${OLD_SCRIPT}"
old_hash=$(sha256sum "${TARGET_PATH}" | awk '{print $1}')
old_attributes=$(capture_file_attributes "${TARGET_PATH}")
set +e
postcheck_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; postcheck_sbv_update() { return 74; }; manual_update_script" 2>&1)
postcheck_status=$?
set -e
assert_status_nonzero "${postcheck_status}"
new_hash=$(sha256sum "${TARGET_PATH}" | awk '{print $1}')
[[ "${old_hash}" == "${new_hash}" ]] || fail 'postcheck failure did not restore the old target'
assert_file_attributes "${TARGET_PATH}" "${old_attributes}"
assert_contains "${postcheck_output}" 'rolled_back: true'
assert_error_context "${postcheck_output}" 'sbv_update' 'postcheck' \
  'update_failed' '74' "${TARGET_PATH}"
assert_contains "${postcheck_output}" 'changed: true'
assert_contains "${postcheck_output}" 'rollback_attempted: true'
assert_contains "${postcheck_output}" 'rollback_ok: true'
assert_no_update_artifacts

rm -f "${TARGET_PATH}"
set +e
missing_postcheck_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; postcheck_sbv_update() { return 76; }; manual_update_script" 2>&1)
missing_postcheck_status=$?
set -e
assert_status_nonzero "${missing_postcheck_status}"
[[ ! -e "${TARGET_PATH}" && ! -L "${TARGET_PATH}" ]] || \
  fail 'rollback for a previously missing target did not remove the target'
assert_contains "${missing_postcheck_output}" 'rolled_back: true'
assert_contains "${missing_postcheck_output}" 'rollback_ok: true'
assert_error_context "${missing_postcheck_output}" 'sbv_update' 'postcheck' \
  'update_failed' '76' "${TARGET_PATH}"
assert_no_update_artifacts

prepare_existing_target "${OLD_SCRIPT}"
lock_old_attributes=$(capture_file_attributes "${TARGET_PATH}")
mkdir "${TARGET_DIR}/.sbv-update.lock"
set +e
lock_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; manual_update_script" 2>&1)
lock_status=$?
set -e
assert_status_nonzero "${lock_status}"
assert_file_attributes "${TARGET_PATH}" "${lock_old_attributes}"
[[ -d "${TARGET_DIR}/.sbv-update.lock" ]] || fail 'lock contention did not preserve the lock'
assert_error_context "${lock_output}" 'sbv_update' 'precheck' \
  'update_in_progress' '1' "${TARGET_PATH}"
rmdir "${TARGET_DIR}/.sbv-update.lock"
assert_no_update_artifacts

printf 'configuration\n' > "${PROJECT_DIR}/config.json"
service_state_before='active'
printf '%s\n' "${service_state_before}" > "${PROJECT_DIR}/service-state"
config_hash_before=$(sha256sum "${PROJECT_DIR}/config.json" | awk '{print $1}')
for signal_mode in signal-int signal-term signal-hup; do
  prepare_existing_target "${OLD_SCRIPT}"
  signal_old_attributes=$(capture_file_attributes "${TARGET_PATH}")
  case "${signal_mode}" in
    signal-int) expected_signal_status=130 ;;
    signal-term) expected_signal_status=143 ;;
    signal-hup) expected_signal_status=129 ;;
  esac
  set +e
  signal_output=$(FAKE_CURL_MODE="${signal_mode}" FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
    bash -c "source '${TESTABLE_INSTALL}'; manual_update_script" 2>&1)
  signal_status=$?
  set -e
  [[ "${signal_status}" -eq "${expected_signal_status}" ]] || \
    fail "${signal_mode} returned ${signal_status}, expected ${expected_signal_status}"
  cmp -s "${OLD_SCRIPT}" "${TARGET_PATH}" || fail "${signal_mode} changed the target"
  assert_file_attributes "${TARGET_PATH}" "${signal_old_attributes}"
  config_hash_after=$(sha256sum "${PROJECT_DIR}/config.json" | awk '{print $1}')
  [[ "${config_hash_before}" == "${config_hash_after}" ]] || fail "${signal_mode} changed configuration state"
  [[ "$(<"${PROJECT_DIR}/service-state")" == "${service_state_before}" ]] || fail "${signal_mode} changed service state"
  assert_contains "${signal_output}" '信号'
  assert_contains "${signal_output}" 'code: signal_interrupted'
  assert_contains "${signal_output}" "command_exit_code: ${expected_signal_status}"
  assert_error_context "${signal_output}" 'sbv_update' 'download' \
    'signal_interrupted' "${expected_signal_status}" "${TARGET_PATH}"
  assert_no_update_artifacts
done

rm -f "${TARGET_PATH}"
set +e
ensure_local_output=$(bash -c "source '${TESTABLE_INSTALL}'; ensure_sbv_command_installed" "${TESTABLE_INSTALL}" 2>&1)
ensure_local_status=$?
set -e
[[ "${ensure_local_status}" -eq 0 ]] || fail 'local ensure_sbv_command_installed failed'
assert_target_matches "${TESTABLE_INSTALL}"
assert_no_update_artifacts

rm -f "${TARGET_PATH}"
set +e
ensure_remote_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; ensure_sbv_command_installed" /nonexistent 2>&1)
ensure_remote_status=$?
set -e
[[ "${ensure_remote_status}" -eq 0 ]] || fail "remote ensure_sbv_command_installed failed: ${ensure_remote_output}"
assert_target_matches "${VALID_CANDIDATE}"
assert_no_update_artifacts

rm -f "${TARGET_PATH}"
set +e
ensure_remote_failure_output=$(FAKE_CURL_MODE=partial FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; ensure_sbv_command_installed" /nonexistent 2>&1)
ensure_remote_failure_status=$?
set -e
assert_status_nonzero "${ensure_remote_failure_status}"
[[ ! -e "${TARGET_PATH}" ]] || fail 'remote ensure failure created a target'
assert_no_update_artifacts

mkdir -p "${TMP_DIR}/media-check"
rm -f "${MEDIA_TARGET}"
set +e
media_missing_output=$(FAKE_CURL_MODE=empty FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; ensure_media_check_backend" 2>&1)
media_missing_status=$?
set -e
assert_status_nonzero "${media_missing_status}"
[[ ! -e "${MEDIA_TARGET}" && ! -L "${MEDIA_TARGET}" ]] || \
  fail 'media backend validation created a target from an empty download'
assert_error_context "${media_missing_output}" 'media_check_backend' 'validate' \
  'artifact_too_small' '1' "${MEDIA_TARGET}"
assert_no_update_artifacts

set +e
media_success_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; ensure_media_check_backend" 2>&1)
media_success_status=$?
set -e
[[ "${media_success_status}" -eq 0 ]] || fail "media backend success failed: ${media_success_output}"
[[ -f "${MEDIA_TARGET}" && ! -L "${MEDIA_TARGET}" && -x "${MEDIA_TARGET}" ]] || \
  fail 'media backend success did not create an executable regular file'
cmp -s "${VALID_CANDIDATE}" "${MEDIA_TARGET}" || fail 'media backend success has unexpected content'
assert_no_update_artifacts

rm -f "${MEDIA_TARGET}"
cp "${OLD_SCRIPT}" "${MEDIA_TARGET}"
chmod 0644 "${MEDIA_TARGET}"
chown "${TEST_TARGET_UID}:${TEST_TARGET_GID}" "${MEDIA_TARGET}" || \
  fail 'could not prepare the media target owner'
media_inode=$(stat -c '%i' "${MEDIA_TARGET}")
media_attributes=$(capture_file_attributes "${MEDIA_TARGET}")
set +e
media_output=$(FAKE_CURL_MODE=partial FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; ensure_media_check_backend" 2>&1)
media_status=$?
set -e
assert_status_nonzero "${media_status}"
cmp -s "${OLD_SCRIPT}" "${MEDIA_TARGET}" || fail 'media backend failure changed existing script'
assert_file_attributes "${MEDIA_TARGET}" "${media_attributes}"
[[ "$(stat -c '%i' "${MEDIA_TARGET}")" == "${media_inode}" ]] || fail 'media backend failure replaced existing script'
assert_error_context "${media_output}" 'media_check_backend' 'download' \
  'download_partial_transfer' '18' "${MEDIA_TARGET}"
assert_no_update_artifacts

for alias in 'update sbv' 'update-sbv'; do
  rm -f "${TARGET_PATH}"
  set +e
  cli_output=$(FAKE_CURL_MODE=dns FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
    bash -c "source '${TESTABLE_INSTALL}'; check_root() { :; }; main ${alias}" 2>&1)
  cli_status=$?
  set -e
  assert_status_nonzero "${cli_status}"
  assert_contains "${cli_output}" 'changed: false'
done

prepare_existing_target "${OLD_SCRIPT}"
set +e
menu_output=$(printf '15\n0\n' | FAKE_CURL_MODE=dns FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; show_banner() { :; }; check_root() { :; }; ensure_sbv_command_installed() { :; }; check_script_status() { SCRIPT_VER_STATUS='(无法检测更新)'; }; check_sb_version() { SB_VER_STATUS=''; }; check_bbr_status() { :; }; main_menu_service_status_summary() { printf 'mock'; }; main" 2>&1)
menu_status=$?
set -e
[[ "${menu_status}" -eq 0 ]] || fail "menu did not return after update failure: ${menu_output}"
assert_contains "${menu_output}" 'changed: false'
assert_contains "${menu_output}" '已返回管理菜单'
cmp -s "${OLD_SCRIPT}" "${TARGET_PATH}" || fail 'menu update failure changed the target'
assert_no_update_artifacts

rollback_marker="${TMP_DIR}/rollback-called"
rollback_old_attributes=$(capture_file_attributes "${TARGET_PATH}")
set +e
rollback_output=$(FAKE_CURL_MODE=valid FAKE_CURL_SOURCE="${VALID_CANDIDATE}" \
  bash -c "source '${TESTABLE_INSTALL}'; postcheck_sbv_update() { return 74; }; restore_sbv_backup() { printf 'called\\n' > '${rollback_marker}'; return 75; }; manual_update_script" 2>&1)
rollback_status=$?
set -e
assert_status_nonzero "${rollback_status}"
[[ -f "${rollback_marker}" ]] || fail 'rollback failure did not call restore_sbv_backup'
assert_contains "${rollback_output}" 'rollback_failed'
assert_contains "${rollback_output}" 'manual_intervention_required: true'
assert_error_context "${rollback_output}" 'sbv_update' 'postcheck' \
  'rollback_failed' '74' "${TARGET_PATH}"
assert_contains "${rollback_output}" 'changed: true'
assert_contains "${rollback_output}" 'rollback_attempted: true'
assert_contains "${rollback_output}" 'rolled_back: false'
assert_contains "${rollback_output}" 'rollback_ok: false'
assert_target_matches "${VALID_CANDIDATE}"
assert_file_attributes "${TARGET_PATH}" "${rollback_old_attributes}"
backup_artifact=$(find "${TARGET_DIR}" -maxdepth 1 -type f -name '.sbv-backup.*' -print -quit)
retained_candidate=$(find "${TARGET_DIR}" -maxdepth 1 -type f -name '.sbv-candidate-retained.*' -print -quit)
[[ -n "${backup_artifact}" && -f "${backup_artifact}" && ! -L "${backup_artifact}" ]] || \
  fail 'rollback failure did not preserve a regular backup'
[[ -n "${retained_candidate}" && -f "${retained_candidate}" && ! -L "${retained_candidate}" ]] || \
  fail 'rollback failure did not preserve a regular candidate'
[[ "$(stat -c '%a' "${backup_artifact}")" == '600' ]] || fail 'backup is not protected'
[[ "$(stat -c '%a' "${retained_candidate}")" == '600' ]] || fail 'retained candidate is not protected'
[[ "$(stat -c '%u:%g' "${backup_artifact}")" == "${TEST_TARGET_UID}:${TEST_TARGET_GID}" ]] || \
  fail 'preserved backup owner changed'
[[ "$(stat -c '%u:%g' "${retained_candidate}")" == "${TEST_TARGET_UID}:${TEST_TARGET_GID}" ]] || \
  fail 'retained candidate owner changed'
cmp -s "${OLD_SCRIPT}" "${backup_artifact}" || fail 'preserved backup does not contain the old script'
cmp -s "${VALID_CANDIDATE}" "${retained_candidate}" || fail 'retained candidate is not the submitted script'
[[ ! -d "${TARGET_DIR}/.sbv-update.lock" ]] || fail 'update lock survived rollback failure'

printf 'sbv update transaction regression tests passed\n'
