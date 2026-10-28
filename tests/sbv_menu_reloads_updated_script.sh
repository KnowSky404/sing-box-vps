#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
OLD_RUNTIME="${TMP_DIR}/old-runtime.sh"
NEW_RUNTIME="${TMP_DIR}/new-runtime.sh"
TARGET_PATH="${TMP_DIR}/bin/sbv"
export FAKE_CURL_SOURCE="${NEW_RUNTIME}"

fail() {
  printf '%s\n%s\n' "$1" "${output:-}" >&2
  exit 1
}

create_runtime() {
  local version=$1 destination=$2
  sed \
    -e '/BASH_SOURCE.*main/d' \
    -e "s/readonly SCRIPT_VERSION=\"[0-9]*\"/readonly SCRIPT_VERSION=\"${version}\"/" \
    "${TESTABLE_INSTALL}" > "${destination}"
  cat >> "${destination}" <<'EOF'

# Keep real menu dispatch, update transactions, and management locks. Isolate
# unrelated status probes so re-execution starts an observable, offline menu.
show_banner() {
  printf 'menu_version=%s pid=%s\n' "${SCRIPT_VERSION}" "$$"
  [[ ! -e "${SBV_BIN_PATH%/*}/.sbv-update.lock" ]] || exit 91
  if flock -n "${SB_PROJECT_DIR}.management.flock" true; then
    printf 'management lock was lost\n' >&2
    exit 92
  fi
}
check_root() { :; }
check_script_status() {
  SCRIPT_VER_STATUS=''
  printf 'runtime_version=%s\n' "${SCRIPT_VERSION}"
}
check_sb_version() { SB_VER_STATUS=''; }
check_bbr_status() { :; }
main_menu_service_status_summary() { printf 'offline'; }
render_section_title() { :; }
render_menu_item() { :; }
render_main_menu_footer() { :; }

[[ "${BASH_SOURCE[0]}" != "$0" ]] || main "$@"
EOF
  chmod +x "${destination}"
}

create_runtime 2026010101 "${OLD_RUNTIME}"
create_runtime 2099010101 "${NEW_RUNTIME}"

cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAKE_CURL_FAIL:-0}" != 1 ]] || exit 6
while (($#)); do
  case "$1" in
    -o) cp -- "${FAKE_CURL_SOURCE}" "$2"; exit 0 ;;
    *) shift ;;
  esac
done
exit 1
EOF
chmod +x "${TMP_DIR}/bin/curl"

assert_reloaded() {
  local old_pid new_pid
  [[ "${output}" == *'menu_version=2026010101 '* ]] || fail 'old menu did not start'
  [[ "${output}" == *'menu_version=2099010101 '* ]] || fail 'menu 15 did not enter the updated runtime'
  old_pid=$(sed -n 's/^menu_version=2026010101 pid=//p' <<< "${output}")
  new_pid=$(sed -n 's/^menu_version=2099010101 pid=//p' <<< "${output}")
  [[ "${old_pid}" == "${new_pid}" ]] || fail 'updated menu did not replace the old process'
  [[ $(grep -c '^runtime_version=2026010101$' <<< "${output}") == 1 ]] || fail 'old menu resumed after updating'
  [[ "${output}" != *'请重新运行 sbv'* ]] || fail 'successful menu handoff still requests a manual restart'
}

# Real atomic update, followed by a fresh runtime in the same process. The new
# runtime acquires the inherited management lock and consumes the pending exit.
cp -- "${OLD_RUNTIME}" "${TARGET_PATH}"
output=$(timeout 20 bash "${TARGET_PATH}" <<<'15
0' 2>&1) || fail 'interactive update failed'
assert_reloaded
cmp -s "${NEW_RUNTIME}" "${TARGET_PATH}" || fail 'new script was not installed'

# A healthy current runtime stays in its menu without re-executing on no-op.
before_inode=$(stat -c '%i' "${TARGET_PATH}")
output=$(timeout 20 bash "${TARGET_PATH}" <<<'15
0' 2>&1) || fail 'current-version menu update failed'
[[ $(grep -c '^menu_version=' <<< "${output}") == 1 ]] || fail 'current-version no-op restarted the menu'
[[ $(stat -c '%i' "${TARGET_PATH}") == "${before_inode}" ]] || fail 'no-op replaced the installed script'

# Another update can already have installed the latest target while this
# process still runs old definitions. A disk no-op must still refresh it.
output=$(timeout 20 bash -c '
  source "$1"
  ensure_sbv_command_installed() { :; }
  main
' _ "${OLD_RUNTIME}" <<<'15
0' 2>&1) || fail 'stale runtime no-op failed'
assert_reloaded
[[ $(stat -c '%i' "${TARGET_PATH}") == "${before_inode}" ]] || fail 'stale runtime no-op replaced the target'

# A failed update must keep the original runtime and file, and allow exit.
cp -- "${OLD_RUNTIME}" "${TARGET_PATH}"
output=$(FAKE_CURL_FAIL=1 timeout 20 bash "${TARGET_PATH}" <<<'15
0' 2>&1) || fail 'download failure prevented returning to the menu'
[[ "${output}" == *'已返回管理菜单'* ]] || fail 'download failure was not reported'
[[ "${output}" != *'menu_version=2099010101 '* ]] || fail 'failed update launched another runtime'
cmp -s "${OLD_RUNTIME}" "${TARGET_PATH}" || fail 'failed download changed the target'

# CLI updates complete without opening any interactive menu or re-executing.
for alias in 'update sbv' 'update-sbv' 'update script' 'update-script'; do
  cp -- "${OLD_RUNTIME}" "${TARGET_PATH}"
  read -r -a arguments <<< "${alias}"
  output=$(timeout 20 bash "${TARGET_PATH}" "${arguments[@]}" 2>&1) || fail "CLI ${alias} failed"
  [[ "${output}" != *'menu_version='* ]] || fail "CLI ${alias} opened the menu"
  cmp -s "${NEW_RUNTIME}" "${TARGET_PATH}" || fail "CLI ${alias} did not install the new script"
done

# Failed exec must report that the update committed and keep the menu usable.
cp -- "${OLD_RUNTIME}" "${TARGET_PATH}"
output=$(timeout 20 bash -c '
  source "$1"
  ensure_sbv_command_installed() { :; }
  BASH="$2"
  main
' _ "${OLD_RUNTIME}" "${TMP_DIR}/missing-bash" <<<'15
0' 2>&1) || fail 'failed handoff terminated the menu'
[[ "${output}" == *'自动切换失败'* ]] || fail 'failed handoff was not reported'
[[ "${output}" != *'sbv 自更新失败'* ]] || fail 'failed handoff was reported as a failed update'
cmp -s "${NEW_RUNTIME}" "${TARGET_PATH}" || fail 'failed handoff lost the installed update'

printf 'sbv menu update handoff: ok\n'
