#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${TESTS_DIR}/menu_test_helper.sh"

setup_menu_test_env 120
source_testable_install

assert_snapshot_api() {
  local function_name

  for function_name in \
    create_managed_state_snapshot \
    restore_managed_state_snapshot \
    discard_managed_state_snapshot; do
    if ! declare -F "${function_name}" >/dev/null 2>&1; then
      printf 'missing managed state snapshot API: %s\n' "${function_name}" >&2
      exit 1
    fi
  done
}

tree_fingerprint() {
  local root=$1

  if [[ ! -d "${root}" ]]; then
    printf '<absent>\n'
    return 0
  fi

  (
    cd "${root}"
    find . -mindepth 1 -printf '%y %m %p\n' | sort
    while IFS= read -r -d '' file; do
      sha256sum "${file}"
    done < <(find . -type f -print0 | sort -z)
  )
}

write_managed_project_fixture() {
  mkdir -p "${SB_PROJECT_DIR}/nested/inner"
  printf 'original config\n' > "${SB_PROJECT_DIR}/config.json"
  printf 'state root\n' > "${SB_PROJECT_DIR}/state.env"
  printf 'nested state\n' > "${SB_PROJECT_DIR}/nested/inner/state.env"
  printf 'hidden state\n' > "${SB_PROJECT_DIR}/.hidden-state"
  chmod 751 "${SB_PROJECT_DIR}"
  chmod 750 "${SB_PROJECT_DIR}/nested"
  chmod 711 "${SB_PROJECT_DIR}/nested/inner"
  chmod 640 "${SB_PROJECT_DIR}/config.json"
  chmod 600 "${SB_PROJECT_DIR}/state.env"
  chmod 640 "${SB_PROJECT_DIR}/nested/inner/state.env"
  chmod 600 "${SB_PROJECT_DIR}/.hidden-state"
}

assert_snapshot_api

# Existing projects must restore every nested file and its mode, including
# hidden files and the project directory mode itself.
command rm -rf "${SB_PROJECT_DIR}"
write_managed_project_fixture
BEFORE_FINGERPRINT=$(tree_fingerprint "${SB_PROJECT_DIR}")
EXISTING_SNAPSHOT=$(create_managed_state_snapshot)
if [[ ! -d "${EXISTING_SNAPSHOT}" ]]; then
  printf 'create_managed_state_snapshot did not return a snapshot directory: %s\n' "${EXISTING_SNAPSHOT}" >&2
  exit 1
fi

printf 'mutated config\n' > "${SB_PROJECT_DIR}/config.json"
rm -f "${SB_PROJECT_DIR}/.hidden-state"
mkdir -p "${SB_PROJECT_DIR}/new/deeper"
printf 'unexpected file\n' > "${SB_PROJECT_DIR}/new/deeper/file"
chmod 777 "${SB_PROJECT_DIR}"
chmod 755 "${SB_PROJECT_DIR}/nested"

restore_managed_state_snapshot "${EXISTING_SNAPSHOT}"
AFTER_FINGERPRINT=$(tree_fingerprint "${SB_PROJECT_DIR}")
if [[ "${AFTER_FINGERPRINT}" != "${BEFORE_FINGERPRINT}" ]]; then
  printf 'restored project tree differs from the original snapshot\noriginal:\n%s\nrestored:\n%s\n' \
    "${BEFORE_FINGERPRINT}" "${AFTER_FINGERPRINT}" >&2
  exit 1
fi
discard_managed_state_snapshot "${EXISTING_SNAPSHOT}"
if [[ -e "${EXISTING_SNAPSHOT}" ]]; then
  printf 'discard_managed_state_snapshot left the snapshot behind: %s\n' "${EXISTING_SNAPSHOT}" >&2
  exit 1
fi

# A project that did not exist before the transaction must not be recreated by
# rollback. Keep this separate from the existing-project case because the
# absence marker is part of the snapshot contract.
command rm -rf "${SB_PROJECT_DIR}"
ABSENT_SNAPSHOT=$(create_managed_state_snapshot)
mkdir -p "${SB_PROJECT_DIR}/created-after-snapshot"
printf 'must disappear\n' > "${SB_PROJECT_DIR}/created-after-snapshot/file"
restore_managed_state_snapshot "${ABSENT_SNAPSHOT}"
if [[ -e "${SB_PROJECT_DIR}" ]]; then
  printf 'rollback recreated a project directory that was originally absent\n' >&2
  exit 1
fi
if [[ -e "${ABSENT_SNAPSHOT}" ]]; then
  discard_managed_state_snapshot "${ABSENT_SNAPSHOT}"
fi

# Inject failure into both copy/move primitives without changing the command
# lookup used by the rest of the test. A failed restore must leave its
# snapshot available for a later retry.
write_managed_project_fixture
FAILURE_SNAPSHOT=$(create_managed_state_snapshot)
printf 'mutated before failed restore\n' > "${SB_PROJECT_DIR}/config.json"
SNAPSHOT_OPERATION_FAIL="y"
mv() {
  if [[ "${SNAPSHOT_OPERATION_FAIL}" == "y" ]]; then
    return 97
  fi
  command mv "$@"
}
cp() {
  if [[ "${SNAPSHOT_OPERATION_FAIL}" == "y" ]]; then
    return 98
  fi
  command cp "$@"
}
set +e
restore_managed_state_snapshot "${FAILURE_SNAPSHOT}"
RESTORE_FAILURE_STATUS=$?
set -e
unset -f mv cp
SNAPSHOT_OPERATION_FAIL="n"

if (( RESTORE_FAILURE_STATUS == 0 )); then
  printf 'restore_managed_state_snapshot unexpectedly succeeded under copy/move failure injection\n' >&2
  exit 1
fi
if [[ ! -d "${FAILURE_SNAPSHOT}" ]]; then
  printf 'failed restore discarded its snapshot: %s\n' "${FAILURE_SNAPSHOT}" >&2
  exit 1
fi
restore_managed_state_snapshot "${FAILURE_SNAPSHOT}"
discard_managed_state_snapshot "${FAILURE_SNAPSHOT}"

# update_config_only must restore both the live config and the selected
# protocol state when generation fails after state has been edited.
command rm -rf "${SB_PROJECT_DIR}"
mkdir -p "${SB_PROTOCOL_STATE_DIR}"
cat > "${SINGBOX_CONFIG_FILE}" <<'EOF'
{
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        { "name": "hy2-user", "password": "old-pass" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "hy2.example.com",
        "certificate_path": "/etc/ssl/certs/hy2.pem",
        "key_path": "/etc/ssl/private/hy2.key"
      }
    }
  ],
  "route": { "rules": [], "final": "direct" }
}
EOF
cat > "${SB_PROTOCOL_INDEX_FILE}" <<'EOF'
INSTALLED_PROTOCOLS=hy2
PROTOCOL_STATE_VERSION=1
EOF
cat > "${SB_PROTOCOL_STATE_DIR}/hy2.env" <<'EOF'
INSTALLED=1
CONFIG_SCHEMA_VERSION=1
NODE_NAME=hy2-test
PORT=8443
DOMAIN=hy2.example.com
PASSWORD=old-pass
USER_NAME=hy2-user
UP_MBPS=
DOWN_MBPS=
OBFS_ENABLED=n
OBFS_TYPE=
OBFS_PASSWORD=
TLS_MODE=manual
ACME_MODE=http
ACME_EMAIL=
ACME_DOMAIN=hy2.example.com
DNS_PROVIDER=cloudflare
CF_API_TOKEN=
CERT_PATH=/etc/ssl/certs/hy2.pem
KEY_PATH=/etc/ssl/private/hy2.key
MASQUERADE=
EOF

UPDATE_CONFIG_BEFORE=$(mktemp)
UPDATE_STATE_BEFORE=$(mktemp)
cp "${SINGBOX_CONFIG_FILE}" "${UPDATE_CONFIG_BEFORE}"
cp "${SB_PROTOCOL_STATE_DIR}/hy2.env" "${UPDATE_STATE_BEFORE}"

load_current_config_state() {
  SB_PROTOCOL="hy2"
  SB_PORT="8443"
  SB_ADVANCED_ROUTE="n"
  SB_ENABLE_WARP="n"
  SB_WARP_ROUTE_MODE="selective"
}
prompt_installed_protocol_selection() {
  SELECTED_PROTOCOL="hy2"
  return 0
}
prompt_protocol_update_fields() {
  SB_PORT="9443"
  SB_HY2_PASSWORD="new-pass"
}
generate_config() {
  return 42
}
check_config_valid() {
  printf 'check_config_valid must not run after failed generation\n' >&2
  return 1
}
setup_service() { :; }
open_all_protocol_ports() { :; }
systemctl() { :; }

set +e
(
  update_config_only
)
UPDATE_STATUS=$?
set -e

if (( UPDATE_STATUS == 0 )); then
  printf 'update_config_only unexpectedly succeeded when generate_config failed\n' >&2
  exit 1
fi
if ! cmp -s "${UPDATE_CONFIG_BEFORE}" "${SINGBOX_CONFIG_FILE}"; then
  printf 'update_config_only did not restore the live config after generation failure\n' >&2
  exit 1
fi
if ! cmp -s "${UPDATE_STATE_BEFORE}" "${SB_PROTOCOL_STATE_DIR}/hy2.env"; then
  printf 'update_config_only did not restore protocol state after generation failure\n' >&2
  exit 1
fi

rm -f "${UPDATE_CONFIG_BEFORE}" "${UPDATE_STATE_BEFORE}"
printf 'managed config transaction tests passed\n'
