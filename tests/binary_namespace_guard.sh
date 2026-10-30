#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source "${TESTABLE_INSTALL}"
SB_VERSION=1.14.2
ARCH=arm64
uname() { case "${1:-}" in -m) printf 'aarch64\n' ;; -s) printf 'Linux\n' ;; *) command uname "$@" ;; esac; }
ldconfig() { :; }
curl() {
  local destination=''
  while [[ $# -gt 0 ]]; do case $1 in -o) destination=$2; shift 2 ;; *) shift ;; esac; done
  command cp "${TMP_DIR}/candidate.tar.gz" "${destination}"
}
release_root=sing-box-1.14.2-linux-arm64
mkdir -p "${TMP_DIR}/release/${release_root}"
printf 'new-library\n' > "${TMP_DIR}/release/${release_root}/libcronet.so"
prepare_candidate() {
  local tag_line=$1
  printf '#!/usr/bin/env bash\nif [[ $1 == version ]]; then printf "sing-box version 1.14.2\\n%s\\n"; else printf "new\\n"; fi\n' "${tag_line}" > "${TMP_DIR}/release/${release_root}/sing-box"
  tar -czf "${TMP_DIR}/candidate.tar.gz" -C "${TMP_DIR}/release" "${release_root}"
}
restore_old() {
  printf '#!/usr/bin/env bash\nif [[ $1 == version ]]; then printf "sing-box version 1.14.0\\nTags: with_gvisor\\n"; else printf "old\\n"; fi\n' > "${SINGBOX_BIN_PATH}"
  chmod 0755 "${SINGBOX_BIN_PATH}"
  old_hash=$(sha256sum "${SINGBOX_BIN_PATH}")
  mkdir -p "$(dirname "$(singbox_library_path)")"
  printf 'old-library\n' > "$(singbox_library_path)"
  chmod 0644 "$(singbox_library_path)"
  printf 'old-marker\n' > "${SB_NAIVE_LIBRARY_MARKER}"
  chmod 0600 "${SB_NAIVE_LIBRARY_MARKER}"
  old_library_hash=$(sha256sum "$(singbox_library_path)")
  old_marker_hash=$(sha256sum "${SB_NAIVE_LIBRARY_MARKER}")
}
for config in \
  '{"network_namespaces":[{"type":"unshare","tag":"ns"}]}' \
  '{"outbounds":[{"type":"direct","tag":"out","netns":"/run/netns/test"}]}' \
  '{"inbounds":[{"type":"cloudflared","control_dialer":{"netns":"ns"}}]}' \
  '{"certificate_providers":[{"type":"acme","tag":"provider","domain":["namespace.example.invalid"],"http_client":{"engine":"go","netns":"/proc/self/ns/net"}}]}' \
  '{"outbounds":[{"type":"hysteria2","realm":{"http_client":{"netns":"/proc/self/ns/net"}}}]}'; do
  printf '%s\n' "${config}" > "${SINGBOX_CONFIG_FILE}"
  config_hash=$(sha256sum "${SINGBOX_CONFIG_FILE}")
  for tag_line in 'Tags: with_purego,with_gvisor' '' 'Tags: ,' 'Tags: with_gvisor,' 'Tags: with_gvisor,with_gvisor'; do
    restore_old
    prepare_candidate "${tag_line}"
    result=0
    install_binary > "${TMP_DIR}/out" 2> "${TMP_DIR}/err" || result=$?
    if [[ "${tag_line}" == 'Tags: with_purego,with_gvisor' ]]; then
      [[ ${result} == 1 ]]; grep -Fq code=namespace_runtime_unsafe_build "${TMP_DIR}/err"
    else
      [[ ${result} == 2 ]]; grep -Fq code=namespace_runtime_build_not_assessed "${TMP_DIR}/err"
    fi
    [[ $(sha256sum "${SINGBOX_BIN_PATH}") == "${old_hash}" ]]
    [[ $(sha256sum "${SINGBOX_CONFIG_FILE}") == "${config_hash}" ]]
    [[ $(sha256sum "$(singbox_library_path)") == "${old_library_hash}" ]]
    [[ $(sha256sum "${SB_NAIVE_LIBRARY_MARKER}") == "${old_marker_hash}" ]]
    [[ -z $(find "${TMP_DIR}/bin" -maxdepth 1 -name '.sing-box-*' -print -quit) ]]
  done
  restore_old
  prepare_candidate 'Tags: with_gvisor,with_quic'
  install_binary > "${TMP_DIR}/safe.out" 2> "${TMP_DIR}/safe.err"
  [[ $("${SINGBOX_BIN_PATH}" marker) == new ]]
done
# Multiple JSON documents cannot hide an active namespace behind a later object.
printf '{"network_namespaces":[{"type":"unshare","tag":"ns"}]}\n{}\n' > "${SINGBOX_CONFIG_FILE}"
restore_old
prepare_candidate 'Tags: with_purego,with_gvisor'
result=0
install_binary > "${TMP_DIR}/stream.out" 2> "${TMP_DIR}/stream.err" || result=$?
[[ ${result} == 3 ]]
grep -Fq code=namespace_configuration_unavailable "${TMP_DIR}/stream.err"
[[ $(sha256sum "${SINGBOX_BIN_PATH}") == "${old_hash}" ]]
# Normal configurations retain the original core selection, including purego.
printf '{"inbounds":[],"outbounds":[{"type":"http","headers":{"netns":"ordinary HTTP header"}}],"certificate_providers":[{"http_client":{"headers":{"netns":"ordinary HTTP header"}}}]}\n' > "${SINGBOX_CONFIG_FILE}"
restore_old
prepare_candidate 'Tags: with_purego,with_gvisor'
install_binary > "${TMP_DIR}/normal.out" 2> "${TMP_DIR}/normal.err"
[[ $("${SINGBOX_BIN_PATH}" marker) == new ]]
printf 'Candidate binary namespace build guard preserves old artifacts and normal installs\n'
