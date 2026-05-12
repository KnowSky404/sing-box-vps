#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

expected_path="${TMP_DIR}/project/subman.env"
actual_path=$(subman_config_file_path)
if [[ "${actual_path}" != "${expected_path}" ]]; then
  printf 'expected subman config path %s, got %s\n' "${expected_path}" "${actual_path}" >&2
  exit 1
fi

normalized=$(normalize_subman_api_url "  https://subman.example.com///  ")
if [[ "${normalized}" != "https://subman.example.com" ]]; then
  printf 'expected normalized URL without trailing slash, got %s\n' "${normalized}" >&2
  exit 1
fi

SUBMAN_API_URL="https://subman.example.com"
SUBMAN_API_TOKEN="secret-token"
SUBMAN_NODE_PREFIX="edge-1"
write_subman_config

if [[ ! -f "${expected_path}" ]]; then
  printf 'expected subman config file to be written\n' >&2
  exit 1
fi

mode=$(stat -c '%a' "${expected_path}")
if [[ "${mode}" != "600" ]]; then
  printf 'expected subman config mode 600, got %s\n' "${mode}" >&2
  exit 1
fi

SUBMAN_API_URL=""
SUBMAN_API_TOKEN=""
SUBMAN_NODE_PREFIX=""
load_subman_config

if [[ "${SUBMAN_API_URL}" != "https://subman.example.com" ]]; then
  printf 'expected loaded API URL, got %s\n' "${SUBMAN_API_URL}" >&2
  exit 1
fi

if [[ "${SUBMAN_API_TOKEN}" != "secret-token" ]]; then
  printf 'expected loaded API token\n' >&2
  exit 1
fi

if [[ "${SUBMAN_NODE_PREFIX}" != "edge-1" ]]; then
  printf 'expected loaded node prefix, got %s\n' "${SUBMAN_NODE_PREFIX}" >&2
  exit 1
fi

rm -f "${expected_path}"
prompt_subman_config_if_needed <<'EOF'
https://subman.example.com/
prompt-token

EOF

if [[ "${SUBMAN_API_URL}" != "https://subman.example.com" ]]; then
  printf 'expected prompted URL to be normalized, got %s\n' "${SUBMAN_API_URL}" >&2
  exit 1
fi

if [[ "${SUBMAN_API_TOKEN}" != "prompt-token" ]]; then
  printf 'expected prompted token\n' >&2
  exit 1
fi

if [[ "${SUBMAN_NODE_PREFIX}" != "test-host" ]]; then
  printf 'expected empty prompted prefix to default to hostname, got %s\n' "${SUBMAN_NODE_PREFIX}" >&2
  exit 1
fi
