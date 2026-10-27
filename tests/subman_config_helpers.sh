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
SUBMAN_EXPECTED_GIST_ID="  gist-1  "
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
SUBMAN_EXPECTED_GIST_ID=""
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

if [[ "${SUBMAN_EXPECTED_GIST_ID}" != "gist-1" ]]; then
  printf 'expected trimmed configured Gist ID, got %s\n' "${SUBMAN_EXPECTED_GIST_ID}" >&2
  exit 1
fi

cp "${expected_path}" "${TMP_DIR}/original-subman.env"
SUBMAN_EXPECTED_GIST_ID="   "
if write_subman_config; then
  printf 'expected missing Gist ID to reject config changes\n' >&2
  exit 1
fi
cmp "${expected_path}" "${TMP_DIR}/original-subman.env"

cat > "${expected_path}" <<'EOF'
SUBMAN_API_URL=https://subman.example.com
SUBMAN_API_TOKEN=legacy-token
SUBMAN_NODE_PREFIX=legacy-edge
EOF
SUBMAN_EXPECTED_GIST_ID="previous-gist"
load_subman_config
[[ -z "${SUBMAN_EXPECTED_GIST_ID}" ]]
agent_push_nodes_to_subman_json() {
  printf 'legacy config must stop before any sync request\n' >&2
  return 97
}
if legacy_agent_result=$(agent_subman_sync_json); then
  printf 'expected legacy Agent config to require an explicit expected Gist ID\n' >&2
  exit 1
fi
jq -e '.ok == false and .error == "subman_config_missing"' <<< "${legacy_agent_result}" >/dev/null
prompt_subman_config_if_needed <<'EOF'

   intended-gist
EOF
[[ "${SUBMAN_EXPECTED_GIST_ID}" == "intended-gist" ]]
[[ "${SUBMAN_API_TOKEN}" == "legacy-token" && "${SUBMAN_NODE_PREFIX}" == "legacy-edge" ]]
[[ "$(stat -c '%a' "${expected_path}")" == "600" ]]
[[ "$(stat -c '%a' "${expected_path}.bak")" == "600" ]]
if ! grep -Fxq 'SUBMAN_API_TOKEN=legacy-token' "${expected_path}.bak"; then
  printf 'expected legacy config backup before adding the expected Gist ID\n' >&2
  exit 1
fi

rm -f "${expected_path}"
prompt_subman_config_if_needed <<'EOF'
https://subman.example.com/
prompt-token

  prompt-gist
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

[[ "${SUBMAN_EXPECTED_GIST_ID}" == "prompt-gist" ]]
