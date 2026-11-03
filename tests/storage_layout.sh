#!/usr/bin/env bash

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf -- "${TMP_DIR}"' EXIT
mkdir -m 700 "${TMP_DIR}/home" "${TMP_DIR}/system"

# Exercise the actual layout. Only the root account home and mandatory system
# integration destinations move into the isolated fixture.
sed \
  -e "s|^SB_ROOT_HOME=.*|SB_ROOT_HOME=\"${TMP_DIR}/home\"|" \
  -e "s|^readonly SB_LEGACY_PROJECT_DIR=.*|readonly SB_LEGACY_PROJECT_DIR=\"${TMP_DIR}/legacy\"|" \
  -e "s|^readonly SBV_LINK_PATH=.*|readonly SBV_LINK_PATH=\"${TMP_DIR}/system/sbv\"|" \
  -e "s|^readonly SINGBOX_LINK_PATH=.*|readonly SINGBOX_LINK_PATH=\"${TMP_DIR}/system/sing-box\"|" \
  -e "s|^readonly SINGBOX_SERVICE_LINK_PATH=.*|readonly SINGBOX_SERVICE_LINK_PATH=\"${TMP_DIR}/system/sing-box.service\"|" \
  "${REPO_ROOT}/install.sh" > "${TMP_DIR}/layout.sh"
source "${TMP_DIR}/layout.sh"

[[ "${SB_DATA_ROOT}" == "${TMP_DIR}/home/.sing-box-vps" ]]
[[ "${SB_PROJECT_DIR}" == "${SB_DATA_ROOT}/runtime" ]]
for path in "${SINGBOX_BIN_PATH}" "${SBV_BIN_PATH}" "${SINGBOX_SERVICE_FILE}" \
  "${SB_UPGRADE_BACKUP_ROOT}" "${SB_MEDIA_CHECK_DIR}" "${SBV_LOG_FILE}" \
  "${SB_ROUTING_TRANSACTION_DIR}" "${SB_COMPONENT_TRANSACTION_DIR}" \
  "${SB_WARP_REGISTRATION_PENDING_FILE}"; do
  [[ "${path}" == "${SB_DATA_ROOT}/"* ]]
done
[[ ! -e "${SB_DATA_ROOT}" ]]
storage_initialize
[[ "${TMPDIR}" == "${SB_DATA_ROOT}/tmp" ]]
for directory in '' /bin /lib /runtime /modules /logs /backups /tmp /migrations; do
  [[ "$(stat -c '%a' "${SB_DATA_ROOT}${directory}")" == 700 ]]
done
anonymous=$(storage_mktemp)
legacy_template=$(storage_mktemp -d /tmp/sbv-layout.XXXXXXXX)
for path in "${anonymous}" "${legacy_template}"; do
  [[ "${path}" == "${SB_DATA_ROOT}/tmp/"* ]]
done
explicit=$(storage_mktemp "${SB_DATA_ROOT}/bin/.candidate.XXXXXXXX")
[[ "${explicit}" == "${SB_DATA_ROOT}/bin/.candidate."* ]]

# Never follow an attacker-controlled directory or rewrite an unrelated system
# entry. A correct system link is idempotent and never copies the payload.
mkdir -m 700 "${TMP_DIR}/outside"
ln -s "${TMP_DIR}/outside" "${SB_DATA_ROOT}/unsafe"
if storage_private_directory "${SB_DATA_ROOT}/unsafe"; then exit 1; fi
mkdir -m 777 "${SB_DATA_ROOT}/writable"
if storage_private_directory "${SB_DATA_ROOT}/writable/child"; then exit 1; fi
[[ ! -e "${SB_DATA_ROOT}/writable/child" ]]
printf '#!/usr/bin/env bash\n: fixture\n' > "${SBV_BIN_PATH}"
chmod 700 "${SBV_BIN_PATH}"
printf 'external\n' > "${SBV_LINK_PATH}"
if storage_publish_system_links sbv; then exit 1; fi
[[ "$(<"${SBV_LINK_PATH}")" == external ]]
rm "${SBV_LINK_PATH}"
storage_publish_system_links sbv
storage_publish_system_links sbv
[[ -L "${SBV_LINK_PATH}" && "$(readlink "${SBV_LINK_PATH}")" == "${SBV_BIN_PATH}" ]]
storage_remove_system_link "${SBV_LINK_PATH}" "${SBV_BIN_PATH}"
[[ -f "${SBV_BIN_PATH}" && ! -e "${SBV_LINK_PATH}" ]]

# Optional Naive runtime libraries use a protected internal compatibility link.
printf 'library fixture\n' > "${SB_DATA_ROOT}/lib/libcronet.so"
storage_publish_library_link
storage_publish_library_link
[[ -L "${SB_DATA_ROOT}/bin/libcronet.so" && "$(readlink "${SB_DATA_ROOT}/bin/libcronet.so")" == "${SB_DATA_ROOT}/lib/libcronet.so" ]]
rm -- "${SB_DATA_ROOT}/lib/libcronet.so"
storage_publish_library_link
[[ ! -e "${SB_DATA_ROOT}/bin/libcronet.so" && ! -L "${SB_DATA_ROOT}/bin/libcronet.so" ]]
ln -s "${TMP_DIR}/outside/foreign.so" "${SB_DATA_ROOT}/bin/libcronet.so"
if storage_publish_library_link; then exit 1; fi
[[ "$(readlink "${SB_DATA_ROOT}/bin/libcronet.so")" == "${TMP_DIR}/outside/foreign.so" ]]
rm -- "${SB_DATA_ROOT}/bin/libcronet.so"

# Snapshot only runtime. Its siblings (backups, executables and locks) must not
# enter the snapshot or be replaced by restoring configuration.
printf 'original\n' > "${SB_PROJECT_DIR}/config.json"
printf 'outside snapshot\n' > "${SB_UPGRADE_BACKUP_ROOT}/kept"
snapshot=$(create_managed_state_snapshot)
[[ "${snapshot}" == "${SB_DATA_ROOT}/tmp/"* ]]
[[ -f "${snapshot}/project/config.json" && ! -e "${snapshot}/project/bin" && ! -e "${snapshot}/project/backups" ]]
printf 'changed\n' > "${SB_PROJECT_DIR}/config.json"
restore_managed_state_snapshot "${snapshot}"
[[ "$(<"${SB_PROJECT_DIR}/config.json")" == original ]]
[[ -f "${SBV_BIN_PATH}" && -f "${SB_UPGRADE_BACKUP_ROOT}/kept" ]]
discard_managed_state_snapshot "${snapshot}"
printf 'storage layout checks passed\n'
