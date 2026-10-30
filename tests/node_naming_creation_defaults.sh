#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"
setup_menu_test_env 120
source_testable_install

snapshot_file="${TMP_DIR}/snapshot.json"
printf '%s\n' '{"instances":[{"id":"first","name":"test-host-hy2-01","tag":"hy2-in"},{"id":"third","name":"test-host-hy2-03","tag":"hy2-in-3"}]}' > "${snapshot_file}"
[[ "$(default_instance_node_name_from_file hy2 "${snapshot_file}")" == test-host-hy2-02 ]]
ln -s "${snapshot_file}" "${TMP_DIR}/snapshot-link.json"
for invalid_file in "${TMP_DIR}/missing.json" "${TMP_DIR}/snapshot-link.json"; do
  if default_instance_node_name_from_file hy2 "${invalid_file}" >"${TMP_DIR}/invalid-file.out"; then
    printf 'missing or symlink snapshot unexpectedly accepted\n' >&2
    exit 1
  fi
  [[ ! -s "${TMP_DIR}/invalid-file.out" ]]
done

# The management entrypoints receive a snapshot FILE, not inline JSON. Capture
# their first default at the real name prompt, then cancel before credentials,
# listeners, TLS, services or a saved instance can be changed.
read() {
  if [[ "$*" == *实例名称* ]]; then
    printf '%s' "${name:-}" > "${TMP_DIR}/prompt-default"
    return 1
  fi
  builtin read "$@"
}
for protocol in hy2 mixed; do
  jq -n --arg name "test-host-${protocol}-01" \
    '{instances:[{id:"retained-id",name:$name,tag:"retained-inbound"}]}' > "${snapshot_file}"
  rm -f "${TMP_DIR}/prompt-default"
  if plain_proxy_management_build_record "${protocol}" "${snapshot_file}" create '' "${TMP_DIR}/record.json" \
      >"${TMP_DIR}/${protocol}-create.out" 2>"${TMP_DIR}/${protocol}-create.err"; then
    printf 'cancelled instance creation unexpectedly succeeded: %s\n' "${protocol}" >&2
    exit 1
  fi
  if [[ ! -f "${TMP_DIR}/prompt-default" ]]; then
    printf '%s creation failed before showing its default name from the snapshot file\n' "${protocol}" >&2
    cat "${TMP_DIR}/${protocol}-create.err" >&2
    exit 1
  fi
  [[ "$(cat "${TMP_DIR}/prompt-default")" == "test-host-${protocol}-02" ]]
  [[ ! -e "${TMP_DIR}/record.json" ]]
  jq -e --arg name "test-host-${protocol}-01" '.instances[0].id=="retained-id" and .instances[0].name==$name and .instances[0].tag=="retained-inbound"' "${snapshot_file}" >/dev/null
done
unset -f read
printf 'Node naming creation defaults passed: file adapter, retained names, free ordinal and HY2/Mixed creation prompts\n'
