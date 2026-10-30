#!/usr/bin/env bash
set -euo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install
curl() {
  local output=''
  while [[ $# -gt 0 ]]; do case $1 in -o) output=$2; shift 2 ;; *) shift ;; esac; done
  [[ ${QUERY_TRANSPORT:-0} == 0 ]] || return "${QUERY_TRANSPORT}"
  printf '%s' "${QUERY_BODY}" > "${output}"
  printf '%s' "${QUERY_HTTP:-200}"
}
for QUERY_TRANSPORT in 6 7 18 28 23; do
  SB_VERSION=latest
  QUERY_BODY='{"tag_name":"v1.14.2"}'
  if get_latest_version > "${TMP_DIR}/query.log"; then :; else exit 1; fi
  [[ ${SB_VERSION} == "${SB_SUPPORT_MAX_VERSION}" && ${SB_LATEST_VERSION_LOOKUP_STATUS} == unavailable ]]
  grep -Fq unavailable "${TMP_DIR}/query.log"
done
QUERY_TRANSPORT=0
for QUERY_BODY in '{}' '{' '{"tag_name":null}' '{"tag_name":"v1.14.2; touch /tmp/no"}' '{"tag_name":"v1.14.2-beta.1"}' '{"tag_name":"v1.14.2"}{"tag_name":"v1.14.3"}'; do
  SB_VERSION=latest
  get_latest_version > "${TMP_DIR}/query.log"
  [[ ${SB_LATEST_VERSION_LOOKUP_CODE} == invalid_release_response && ${SB_VERSION} == "${SB_SUPPORT_MAX_VERSION}" ]]
done
for QUERY_TRANSPORT in 129 130 143; do
  SB_VERSION=latest
  lookup_status=0
  get_latest_version > "${TMP_DIR}/signal.log" 2>&1 || lookup_status=$?
  [[ ${lookup_status} == "${QUERY_TRANSPORT}" && ${SB_VERSION} == latest && ${SB_LATEST_VERSION_LOOKUP_CODE} == signal_interrupted ]]
done
QUERY_TRANSPORT=0
QUERY_BODY='{"tag_name":"v1.14.2"}'
QUERY_HTTP=503
SB_VERSION=latest
get_latest_version > "${TMP_DIR}/query.log"
[[ ${SB_LATEST_VERSION_LOOKUP_CODE} == http_503 ]]
QUERY_HTTP=200
for version in 1.13.18 1.14.2 1.14.3; do
  QUERY_BODY="{\"tag_name\":\"v${version}\"}"
  SB_VERSION=latest
  get_latest_version > "${TMP_DIR}/query.log"
  [[ ${SB_VERSION} == "${version}" && ${SB_LATEST_VERSION_LOOKUP_STATUS} == available ]]
  if [[ ${version} == 1.14.3 ]]; then grep -Fq 高于适配版本 "${TMP_DIR}/query.log"; else ! grep -Fq 高于适配版本 "${TMP_DIR}/query.log"; fi
done
printf 'Latest-version HTTP/JSON/transport classification and bounded fallback passed\n'
