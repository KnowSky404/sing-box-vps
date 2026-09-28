#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

extract_bootstrap_block() {
  local block_number=$1
  local block_file=$2

  awk -v requested="${block_number}" '
    /^```bash$/ {
      block_count++
      if (block_count == requested) {
        inside = 1
        next
      }
    }
    inside && /^```$/ { exit }
    inside { print }
  ' "${REPO_ROOT}/README.md" > "${block_file}"
  [[ -s "${block_file}" ]] || exit 1
  bash -n "${block_file}"
}

cat > "${TMP_DIR}/curl" <<'EOF'
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
      url=$1
      shift
      ;;
  esac
done

[[ "${connect_timeout}" == '10' && "${max_time}" == '60' && \
  "${retry_count}" == '2' && "${retry_delay}" == '1' ]] || {
  printf 'bootstrap curl received unexpected arguments\n' >&2
  exit 97
}
if [[ "${url}" == 'https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/bootstrap.sh' ]]; then
  printf '%s\n' "${output_file}" > "${BOOTSTRAP_FIRST_PATH_FILE:?}"
  cp "${BOOTSTRAP_ENTRY_SOURCE:?}" "${output_file}"
  exit 0
fi
[[ "${url}" == "${BOOTSTRAP_EXPECTED_URL:?}" ]] || exit 97
[[ "${output_file}" == "${TMPDIR:?}"/sing-box-vps-bootstrap.* ]] || {
  printf 'bootstrap curl did not receive a TMPDIR candidate path\n' >&2
  exit 98
}

printf '%s\n' "${output_file}" > "${BOOTSTRAP_OUTPUT_PATH_FILE:?}"
printf '%s\n' "$(stat -c '%a' "${output_file}")" > "${BOOTSTRAP_OUTPUT_MODE_FILE:?}"
case "${BOOTSTRAP_CURL_MODE:-valid}" in
  fail)
    printf '#!/usr/bin/env bash\npartial transfer\n' > "${output_file}"
    printf 'curl: (28) simulated timeout\n' >&2
    exit 28
    ;;
  signal)
    printf '#!/usr/bin/env bash\npartial transfer\n' > "${output_file}"
    kill -TERM "${PPID}"
    exit 143
    ;;
  syntax)
    cp "${BOOTSTRAP_SYNTAX_SOURCE:?}" "${output_file}"
    exit 0
    ;;
  identity)
    cp "${BOOTSTRAP_IDENTITY_SOURCE:?}" "${output_file}"
    exit 0
    ;;
  identity-url)
    cp "${BOOTSTRAP_IDENTITY_URL_SOURCE:?}" "${output_file}"
    exit 0
    ;;
  valid)
    cp "${BOOTSTRAP_SOURCE:?}" "${output_file}"
    exit 0
    ;;
esac
EOF
chmod +x "${TMP_DIR}/curl"

cat > "${TMP_DIR}/bootstrap-source.sh" <<'EOF'
#!/usr/bin/env bash
readonly PROJECT_AUTHOR="KnowSky404"
readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"
printf 'bootstrap script executed\n' > "${BOOTSTRAP_MARKER:?}"
exit "${BOOTSTRAP_SCRIPT_EXIT:-0}"
EOF
chmod +x "${TMP_DIR}/bootstrap-source.sh"

{
  cat "${TMP_DIR}/bootstrap-source.sh"
  printf '\nif (\n'
} > "${TMP_DIR}/bootstrap-syntax.sh"
sed 's/readonly PROJECT_AUTHOR="KnowSky404"/readonly PROJECT_AUTHOR="wrong"/' \
  "${TMP_DIR}/bootstrap-source.sh" > "${TMP_DIR}/bootstrap-identity.sh"
sed 's|readonly PROJECT_URL="https://github.com/KnowSky404/sing-box-vps"|readonly PROJECT_URL="https://example.invalid/wrong-project"|' \
  "${TMP_DIR}/bootstrap-source.sh" > "${TMP_DIR}/bootstrap-identity-url.sh"

cat > "${TMP_DIR}/mktemp" <<'EOF'
#!/usr/bin/env bash
umask > "${BOOTSTRAP_UMASK_FILE:?}"
exec /usr/bin/mktemp "$@"
EOF
chmod +x "${TMP_DIR}/mktemp"

export PATH="${TMP_DIR}:${PATH}"
export TMPDIR="${TMP_DIR}"
export BOOTSTRAP_SOURCE="${TMP_DIR}/bootstrap-source.sh"
export BOOTSTRAP_SYNTAX_SOURCE="${TMP_DIR}/bootstrap-syntax.sh"
export BOOTSTRAP_IDENTITY_SOURCE="${TMP_DIR}/bootstrap-identity.sh"
export BOOTSTRAP_IDENTITY_URL_SOURCE="${TMP_DIR}/bootstrap-identity-url.sh"
export BOOTSTRAP_OUTPUT_PATH_FILE="${TMP_DIR}/output-path"
export BOOTSTRAP_OUTPUT_MODE_FILE="${TMP_DIR}/output-mode"
export BOOTSTRAP_UMASK_FILE="${TMP_DIR}/umask"
export BOOTSTRAP_MARKER="${TMP_DIR}/executed"
export BOOTSTRAP_ENTRY_SOURCE="${REPO_ROOT}/bootstrap.sh"
export BOOTSTRAP_FIRST_PATH_FILE="${TMP_DIR}/first-path"

run_block() {
  local block=$1
  local mode=$2
  local expected_status=$3
  local output status output_path
  local expected_url operation=$4

  rm -f "${BOOTSTRAP_MARKER}" "${BOOTSTRAP_OUTPUT_PATH_FILE}" "${BOOTSTRAP_OUTPUT_MODE_FILE}"
  case "${operation}" in
    install) expected_url='https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh' ;;
    uninstall) expected_url='https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/uninstall.sh' ;;
    *) exit 1 ;;
  esac
  set +e
  output=$(BOOTSTRAP_CURL_MODE="${mode}" BOOTSTRAP_SCRIPT_EXIT="${5:-0}" \
    BOOTSTRAP_EXPECTED_URL="${expected_url}" \
    bash "${block}" "${operation}" 2>&1)
  status=$?
  set -e
  [[ "${status}" -eq "${expected_status}" ]] || {
    printf 'bootstrap mode %s returned %s, expected %s; output:\n%s\n' \
      "${mode}" "${status}" "${expected_status}" "${output}" >&2
    exit 1
  }
  output_path=$(<"${BOOTSTRAP_OUTPUT_PATH_FILE}")
  [[ -n "${output_path}" && ! -e "${output_path}" && ! -L "${output_path}" ]] || {
    printf 'bootstrap temporary file was not cleaned: %s\n' "${output_path}" >&2
    exit 1
  }
  [[ "$(<"${BOOTSTRAP_OUTPUT_MODE_FILE}")" == '600' ]] || {
    printf 'bootstrap temporary file was not created with mode 600\n' >&2
    exit 1
  }
  [[ "$(<"${BOOTSTRAP_UMASK_FILE}")" =~ ^0*77$ ]] || {
    printf 'bootstrap did not set umask 077\n' >&2
    exit 1
  }
  printf '%s\n' "${output}"
}

extract_bootstrap_block 1 "${TMP_DIR}/readme-install.sh"
[[ "$(wc -l < "${TMP_DIR}/readme-install.sh")" -eq 1 ]]

for operation in install uninstall; do
  failure_output=$(run_block "${REPO_ROOT}/bootstrap.sh" fail 28 "${operation}")
  [[ ! -e "${BOOTSTRAP_MARKER}" ]] || exit 1
  [[ "${failure_output}" == *'curl 退出码: 28'* ]] || exit 1
  [[ "${failure_output}" == *'脚本尚未执行，系统未发生变更'* ]] || exit 1

  signal_output=$(run_block "${REPO_ROOT}/bootstrap.sh" signal 143 "${operation}")
  [[ ! -e "${BOOTSTRAP_MARKER}" ]] || exit 1
  [[ "${signal_output}" == *'安装器尚未启动，系统未发生变更'* ]] || exit 1

  syntax_output=$(run_block "${REPO_ROOT}/bootstrap.sh" syntax 2 "${operation}")
  [[ ! -e "${BOOTSTRAP_MARKER}" ]] || exit 1
  [[ "${syntax_output}" == *'Bash 语法无效'* ]] || exit 1

  identity_output=$(run_block "${REPO_ROOT}/bootstrap.sh" identity 2 "${operation}")
  [[ ! -e "${BOOTSTRAP_MARKER}" ]] || exit 1
  [[ "${identity_output}" == *'项目身份不匹配'* ]] || exit 1

  identity_url_output=$(run_block "${REPO_ROOT}/bootstrap.sh" identity-url 2 "${operation}")
  [[ ! -e "${BOOTSTRAP_MARKER}" ]] || exit 1
  [[ "${identity_url_output}" == *'项目身份不匹配'* ]] || exit 1

  success_output=$(run_block "${REPO_ROOT}/bootstrap.sh" valid 37 "${operation}" 37)
  [[ -e "${BOOTSTRAP_MARKER}" ]] || exit 1
done

rm -f "${BOOTSTRAP_MARKER}" "${BOOTSTRAP_FIRST_PATH_FILE}"
set +e
BOOTSTRAP_EXPECTED_URL='https://raw.githubusercontent.com/KnowSky404/sing-box-vps/main/install.sh' \
  BOOTSTRAP_SCRIPT_EXIT=37 bash "${TMP_DIR}/readme-install.sh" > "${TMP_DIR}/readme-output" 2>&1
readme_status=$?
set -e
[[ "${readme_status}" -eq 37 && -e "${BOOTSTRAP_MARKER}" ]]
[[ ! -e "$(<"${BOOTSTRAP_FIRST_PATH_FILE}")" ]]
[[ ! -e "$(<"${BOOTSTRAP_OUTPUT_PATH_FILE}")" ]]

if grep -Fq 'bash <(curl' "${REPO_ROOT}/README.md"; then
  exit 1
fi
printf 'bootstrap download regression tests passed\n'
