#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
trap 'printf "binary install transaction failed at line %s\n" "${LINENO}" >&2; rm -rf -- "${TMP_DIR}"' ERR

SB_VERSION=1.14.0
ARCH=amd64
release_root=sing-box-1.14.0-linux-amd64
mkdir -p "${TMP_DIR}/archive/${release_root}" "$(dirname "$(singbox_library_path)")"
cat > "${TMP_DIR}/archive/${release_root}/sing-box" <<'EOF_BINARY'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.14.0\n' ;;
  marker) printf 'new\n' ;;
esac
EOF_BINARY
printf 'new-library\n' > "${TMP_DIR}/archive/${release_root}/libcronet.so"
tar -czf "${TMP_DIR}/valid.tar.gz" -C "${TMP_DIR}/archive" "${release_root}"

MOCK_CURL_STATUS=0
archive_file="${TMP_DIR}/valid.tar.gz"
fault=''
curl() {
  local destination=''
  printf '%s\n' "$@" > "${TMP_DIR}/curl.args"
  while (($#)); do
    if [[ "$1" == -o ]]; then destination=$2; shift 2; else shift; fi
  done
  if [[ "${MOCK_CURL_STATUS}" != 0 ]]; then
    printf 'Authorization: Bearer dummy-download-secret\n' >&2
    return "${MOCK_CURL_STATUS}"
  fi
  command cp -- "${archive_file}" "${destination}"
}
ldconfig() { :; }
cp() {
  local args=("$@") destination=${!#}
  if [[ "${fault}" == prepare_library && "${destination}" == *'/.libcronet.install.'* ]]; then return 17; fi
  if [[ "${fault}" == signal_prepare && "${destination}" == *'/.sing-box.restore.'* ]]; then kill -TERM "${BASHPID}"; fi
  command cp "$@"
}
mv() {
  local args=("$@") source_path destination
  source_path=${args[${#args[@]}-2]}
  destination=${args[${#args[@]}-1]}
  if [[ "${source_path}" == *'/.libcronet.install.'* && "${fault}" == publish_library ]]; then return 19; fi
  if [[ "${source_path}" == *'/.libcronet-marker.install.'* && "${fault}" == publish_marker ]]; then return 20; fi
  if [[ "${destination}" == "${SINGBOX_BIN_PATH}" && "${source_path}" == *'/.sing-box.restore.'* ]]; then
    if [[ "${fault}" == rollback_failure && -e "${TMP_DIR}/published" ]]; then return 21; fi
    command mv "$@" || return $?
    if [[ "${fault}" == postcheck || "${fault}" == rollback_failure ]]; then
      if [[ ! -e "${TMP_DIR}/published" ]]; then
        : > "${TMP_DIR}/published"
        printf 'broken-binary\n' > "${destination}"
      fi
    elif [[ "${fault}" == signal_after_commit && ! -e "${TMP_DIR}/signalled" ]]; then
      : > "${TMP_DIR}/signalled"
      kill -TERM "${BASHPID}"
    fi
    return 0
  fi
  command mv "$@"
}

reset_old_state() {
  MOCK_CURL_STATUS=0; fault=''; archive_file="${TMP_DIR}/valid.tar.gz"
  rm -f -- "${TMP_DIR}/published" "${TMP_DIR}/signalled"
  cat > "${SINGBOX_BIN_PATH}" <<'EOF_OLD'
#!/usr/bin/env bash
case "${1:-}" in
  version) printf 'sing-box version 1.13.18\n' ;;
  marker) printf 'old\n' ;;
esac
EOF_OLD
  chmod 0750 "${SINGBOX_BIN_PATH}"
  printf 'old-library\n' > "$(singbox_library_path)"
  chmod 0644 "$(singbox_library_path)"
  sha256sum "$(singbox_library_path)" | awk '{print $1}' > "${SB_NAIVE_LIBRARY_MARKER}"
  chmod 0600 "${SB_NAIVE_LIBRARY_MARKER}"
  command cp -p "${SINGBOX_BIN_PATH}" "${TMP_DIR}/binary.before"
  command cp -p "$(singbox_library_path)" "${TMP_DIR}/library.before"
  command cp -p "${SB_NAIVE_LIBRARY_MARKER}" "${TMP_DIR}/marker.before"
}
assert_old_state() {
  singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${TMP_DIR}/binary.before"
  singbox_file_matches_backup "$(singbox_library_path)" "${TMP_DIR}/library.before"
  singbox_file_matches_backup "${SB_NAIVE_LIBRARY_MARKER}" "${TMP_DIR}/marker.before"
  [[ -z "$(find "${TMP_DIR}/bin" -maxdepth 1 -name '.sing-box-*' -print -quit)" ]]
  [[ -z "$(find "${TMP_DIR}/lib" -maxdepth 1 -name '.libcronet.*' -print -quit)" ]]
}
expect_failure() {
  local name=$1 expected=${2:-1} actual
  if install_binary > "${TMP_DIR}/${name}.stdout" 2> "${TMP_DIR}/${name}.stderr"; then
    printf 'unexpected install success: %s\n' "${name}" >&2; exit 1
  else actual=$?; fi
  [[ "${actual}" == "${expected}" ]]
  ! grep -Fq 'dummy-download-secret' "${TMP_DIR}/${name}.stdout" "${TMP_DIR}/${name}.stderr" "${SBV_LOG_FILE}"
}

for code in 6 7 18 28; do
  reset_old_state; MOCK_CURL_STATUS=${code}
  expect_failure "transport-${code}" "${code}"
  assert_old_state
  grep -Fqx -- --connect-timeout "${TMP_DIR}/curl.args"
  grep -Fqx -- --max-time "${TMP_DIR}/curl.args"
  grep -Fqx -- --retry-max-time "${TMP_DIR}/curl.args"
done

reset_old_state
printf 'not a tarball\n' > "${TMP_DIR}/invalid.tar.gz"
archive_file="${TMP_DIR}/invalid.tar.gz"
expect_failure invalid_archive
assert_old_state

python3 - "${TMP_DIR}" "${release_root}" <<'PY'
import io, pathlib, sys, tarfile
base=pathlib.Path(sys.argv[1]); root=sys.argv[2]
for name, member, kind in [('traversal',root+'/../escape','file'),('symlink',root+'/sing-box','symlink'),('hardlink',root+'/sing-box','hardlink'),('duplicate',root+'/sing-box','duplicate')]:
    with tarfile.open(base/(name+'.tar.gz'),'w:gz') as archive:
        entry=tarfile.TarInfo(member)
        if kind=='symlink': entry.type=tarfile.SYMTYPE; entry.linkname='/etc/passwd'; archive.addfile(entry)
        elif kind=='hardlink': entry.type=tarfile.LNKTYPE; entry.linkname=root+'/other'; archive.addfile(entry)
        else:
            data=b'not executable'; entry.size=len(data); archive.addfile(entry,io.BytesIO(data))
            if kind=='duplicate': archive.addfile(entry,io.BytesIO(data))
with tarfile.open(base/'wrong-version.tar.gz','w:gz') as archive:
    data=b'#!/usr/bin/env bash\nprintf "sing-box version 1.13.18\\n"\n'
    entry=tarfile.TarInfo(root+'/sing-box'); entry.size=len(data); archive.addfile(entry,io.BytesIO(data))
PY
for kind in traversal symlink hardlink duplicate; do
  reset_old_state; archive_file="${TMP_DIR}/${kind}.tar.gz"
  expect_failure "archive-${kind}"
  assert_old_state
done

reset_old_state
archive_file="${TMP_DIR}/wrong-version.tar.gz"
expect_failure wrong_version
grep -Fq code=unexpected_binary_version "${TMP_DIR}/wrong_version.stderr"
assert_old_state
for kind in prepare_library publish_library publish_marker postcheck; do
  reset_old_state; fault=${kind}
  expect_failure "fault-${kind}"
  assert_old_state
done
reset_old_state; fault=signal_after_commit
expect_failure signal 143
assert_old_state
reset_old_state; fault=signal_prepare
expect_failure signal_prepare 143
assert_old_state
reset_old_state; fault=publish_marker
rm -f "$(singbox_library_path)" "${SB_NAIVE_LIBRARY_MARKER}"
expect_failure new_library_rollback
[[ ! -e "$(singbox_library_path)" && ! -e "${SB_NAIVE_LIBRARY_MARKER}" ]]
singbox_file_matches_backup "${SINGBOX_BIN_PATH}" "${TMP_DIR}/binary.before"

reset_old_state; fault=rollback_failure
expect_failure rollback_failure
[[ "$("${SINGBOX_BIN_PATH}" version 2>/dev/null || true)" != 'sing-box version 1.13.18' ]]
grep -Fq 'manual_intervention_required=true' "${TMP_DIR}/rollback_failure.stderr"
recovery_dir=$(find "${TMP_DIR}/bin" -maxdepth 1 -type d -name '.sing-box-install.*' -print -quit)
[[ -f "${recovery_dir}/binary.before" && -f "${recovery_dir}/library.before" ]]
rm -rf -- "${recovery_dir}"

reset_old_state
install_binary >/dev/null
[[ "$("${SINGBOX_BIN_PATH}" marker)" == new ]]
[[ "$(cat "$(singbox_library_path)")" == new-library ]]
[[ "$(cat "${SB_NAIVE_LIBRARY_MARKER}")" == "$(sha256sum "$(singbox_library_path)" | awk '{print $1}')" ]]
[[ -z "$(find "${TMP_DIR}/bin" -maxdepth 1 -name '.sing-box-*' -print -quit)" ]]
printf 'binary install: transport/archive validation, prepare/publish/postcheck failure, signal and verified rollback passed\n'
